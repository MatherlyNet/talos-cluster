#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="${LOG_LEVEL:-info}"
export ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel)}"

# Exponential backoff retry configuration
readonly INITIAL_DELAY=3
readonly MAX_DELAY=60
readonly MAX_RETRIES=5
readonly BACKOFF_MULTIPLIER=2

declare -a FAILED_NODES=()
declare -a SUCCESSFUL_NODES=()

function exponential_backoff_retry() {
    local max_retries="$1"
    shift
    local cmd=("$@")

    local retry=0
    local delay="${INITIAL_DELAY}"

    while [[ $retry -lt $max_retries ]]; do
        if "${cmd[@]}"; then
            return 0
        fi

        ((retry++))

        if [[ $retry -lt $max_retries ]]; then
            log debug "Command failed, retrying" \
                "retry=${retry}/${max_retries}" "delay=${delay}s" "command=${cmd[0]}"
            sleep "${delay}"
            delay=$((delay * BACKOFF_MULTIPLIER))
            [[ $delay -gt $MAX_DELAY ]] && delay=$MAX_DELAY
        fi
    done

    log error "Command failed after ${max_retries} retries" "command=${cmd[0]}"
    return 1
}

function apply_node_config() {
    local node_ip="$1"
    local config_file="$2"
    local node_name="${config_file%.*}"
    node_name="${node_name##*/}"

    log info "Applying Talos config to node" "ip=${node_ip}" "node=${node_name}"

    # Pre-apply validation: verify config file exists
    if [[ ! -f "$config_file" ]]; then
        log error "Config file not found" "file=${config_file}" "ip=${node_ip}"
        FAILED_NODES+=("${node_ip}")
        return 1
    fi

    # Pre-apply validation: verify node is still reachable
    if ! talosctl get links -n "${node_ip}" --insecure &>/dev/null; then
        log error "Node unreachable before config apply" "ip=${node_ip}"
        FAILED_NODES+=("${node_ip}")
        return 1
    fi

    log debug "Pre-apply validation passed" "ip=${node_ip}"

    # Apply config with retry logic
    if exponential_backoff_retry "${MAX_RETRIES}" \
        talosctl apply-config \
            --talosconfig="${TALOSCONFIG}" \
            --nodes="${node_ip}" \
            --file="${config_file}" \
            --insecure; then

        log info "Config applied successfully" "ip=${node_ip}" "node=${node_name}"
        SUCCESSFUL_NODES+=("${node_ip}")

        # Post-apply verification: wait briefly for acknowledgment
        log debug "Verifying config acceptance" "ip=${node_ip}"
        if sleep 2 && talosctl get machineconfig -n "${node_ip}" --insecure &>/dev/null; then
            log info "Node acknowledged config" "ip=${node_ip}"
        else
            log warn "Could not immediately verify config (node may still be applying)" "ip=${node_ip}"
        fi

        return 0
    else
        log error "Failed to apply config to node after ${MAX_RETRIES} retries" "ip=${node_ip}"
        FAILED_NODES+=("${node_ip}")
        return 1
    fi
}

function apply_all_nodes_sequential() {
    local out_dir="${1:-.}"

    log info "Applying configs to all nodes sequentially"

    # Generate apply commands from talhelper
    local apply_cmds
    apply_cmds=$(talhelper gencommand apply --extra-flags="--insecure" --out-dir="${out_dir}")

    local total_cmds=0
    local processed_cmds=0

    # Count total commands
    total_cmds=$(echo "${apply_cmds}" | grep -c "talosctl apply-config" || echo 0)
    log debug "Total commands to execute" "count=${total_cmds}"

    # Parse and execute each apply command
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue
        [[ ! "$line" =~ talosctl\ apply-config ]] && continue

        local node_ip config_file

        # Extract IP from --nodes=IP
        if [[ $line =~ --nodes=([0-9.]+) ]]; then
            node_ip="${BASH_REMATCH[1]}"
        else
            log error "Could not extract node IP from command: $line"
            continue
        fi

        # Extract config file from --file=PATH
        if [[ $line =~ --file=([^ ]+) ]]; then
            config_file="${BASH_REMATCH[1]}"
        else
            log error "Could not extract config file from command: $line"
            continue
        fi

        ((processed_cmds++))

        # Apply config to this node
        if ! apply_node_config "${node_ip}" "${config_file}"; then
            log error "Failed to apply config to node ${node_ip} (continuing with next node)"
        fi

    done <<< "$apply_cmds"

    log debug "Completed command execution" "processed=${processed_cmds}/${total_cmds}"
}

function apply_all_nodes_parallel() {
    local out_dir="${1:-.}"
    local max_parallel="${2:-2}"

    log info "Applying configs to nodes in parallel" "max_concurrent=${max_parallel}"

    # Generate apply commands from talhelper
    local apply_cmds
    apply_cmds=$(talhelper gencommand apply --extra-flags="--insecure" --out-dir="${out_dir}")

    declare -a pids=()
    declare -a node_ips=()
    local active_jobs=0
    local total_jobs=0

    # Parse commands and start parallel jobs
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue
        [[ ! "$line" =~ talosctl\ apply-config ]] && continue

        local node_ip config_file

        if [[ $line =~ --nodes=([0-9.]+) ]]; then
            node_ip="${BASH_REMATCH[1]}"
        else
            continue
        fi

        if [[ $line =~ --file=([^ ]+) ]]; then
            config_file="${BASH_REMATCH[1]}"
        else
            continue
        fi

        ((total_jobs++))

        # Wait if we've reached max parallel jobs
        while [[ $active_jobs -ge $max_parallel ]]; do
            local i=0
            while [[ $i -lt ${#pids[@]} ]]; do
                local pid=${pids[$i]}
                if ! kill -0 "$pid" 2>/dev/null; then
                    # Job completed, check status
                    if wait "$pid" 2>/dev/null; then
                        log debug "Parallel job completed successfully" "pid=${pid}" "node=${node_ips[$i]}"
                    else
                        log error "Parallel job failed" "pid=${pid}" "node=${node_ips[$i]}"
                    fi
                    # Remove from arrays
                    unset 'pids[$i]'
                    unset 'node_ips[$i]'
                    ((active_jobs--))
                fi
                ((i++))
            done

            if [[ $active_jobs -ge $max_parallel ]]; then
                sleep 1
            fi
        done

        # Start parallel job
        log debug "Starting parallel job" "node=${node_ip}" "active=${active_jobs}/${max_parallel}"
        apply_node_config "${node_ip}" "${config_file}" &
        local job_pid=$!
        pids+=("$job_pid")
        node_ips+=("$node_ip")
        ((active_jobs++))

    done <<< "$apply_cmds"

    # Wait for all remaining jobs to complete
    log info "Waiting for remaining parallel jobs to complete" "active=${active_jobs}"
    local failed_parallel=0

    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local node_ip=${node_ips[$i]:-unknown}

        if [[ -n "$pid" ]]; then
            if wait "$pid" 2>/dev/null; then
                log debug "Parallel job completed" "pid=${pid}" "node=${node_ip}"
            else
                log error "Parallel job failed" "pid=${pid}" "node=${node_ip}"
                ((failed_parallel++))
            fi
        fi
    done

    log info "All parallel jobs completed" "total=${total_jobs}" "failed=${failed_parallel}"
    return $([[ $failed_parallel -eq 0 ]] && echo 0 || echo 1)
}

function generate_report() {
    log info "Talos Config Apply Report"

    local successful_count=${#SUCCESSFUL_NODES[@]}
    local failed_count=${#FAILED_NODES[@]}
    local total=$((successful_count + failed_count))

    log info "  Status: $([ $failed_count -eq 0 ] && echo PASS || echo FAIL)"
    log info "  Successful: ${successful_count}/${total} nodes"
    if [[ ${#SUCCESSFUL_NODES[@]} -gt 0 ]]; then
        log info "    - ${SUCCESSFUL_NODES[*]}"
    fi

    if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
        log info "  Failed: ${failed_count}/${total} nodes"
        log info "    - ${FAILED_NODES[*]}"
        return 1
    fi

    return 0
}

function main() {
    check_env TALOSCONFIG
    check_cli talhelper talosctl bash yq

    local out_dir="${1:-.}"
    local mode="${2:-sequential}"

    if [[ ! -d "$out_dir" ]]; then
        log error "Output directory not found" "dir=${out_dir}"
    fi

    log info "Talos config apply starting" "mode=${mode}" "out_dir=${out_dir}"

    local start_time
    start_time=$(date +%s)

    case "$mode" in
        sequential)
            apply_all_nodes_sequential "${out_dir}"
            ;;
        parallel)
            apply_all_nodes_parallel "${out_dir}" 2
            ;;
        *)
            log error "Invalid mode: ${mode}" "valid_modes=sequential|parallel"
            ;;
    esac

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log debug "Execution completed" "duration=${duration}s"
    generate_report
    log info "Config apply finished" "mode=${mode}" "duration=${duration}s"
}

main "$@"