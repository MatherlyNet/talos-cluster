#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="${LOG_LEVEL:-info}"
export ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel)}"

# Configuration
readonly NODE_REACHABILITY_RETRIES=3
readonly NODE_REACHABILITY_DELAY=2

function get_all_nodes() {
    # Parse talconfig.yaml and extract all node IPs
    local talconfig="$1"
    yq -r '.nodes[].ipAddress' "${talconfig}"
}

function check_node_reachable() {
    local node_ip="$1"
    local max_retries="${2:-${NODE_REACHABILITY_RETRIES}}"
    local delay="${3:-${NODE_REACHABILITY_DELAY}}"

    log debug "Starting reachability check" "ip=${node_ip}"

    for attempt in $(seq 1 "${max_retries}"); do
        if talosctl get links -n "${node_ip}" --insecure &>/dev/null; then
            log info "Node reachable" "ip=${node_ip}"
            return 0
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log debug "Node unreachable, retrying" \
                "ip=${node_ip}" "attempt=${attempt}/${max_retries}" "delay=${delay}s"
            sleep "${delay}"
        fi
    done

    log error "Node unreachable after ${max_retries} attempts" "ip=${node_ip}"
    return 1
}

function check_node_stage() {
    local node_ip="$1"
    local stage

    stage=$(talosctl get machineconfig -n "${node_ip}" --insecure -o json 2>/dev/null | \
        yq -r '.phase // "MAINTENANCE"' || echo "MAINTENANCE")

    if [[ "$stage" != "MAINTENANCE" ]]; then
        log warn "Node not in expected MAINTENANCE stage" "ip=${node_ip}" "stage=${stage}"
        return 1
    fi

    log debug "Node in MAINTENANCE stage" "ip=${node_ip}"
    return 0
}

function check_disk_available() {
    local node_ip="$1"
    local expected_disk="$2"

    # Skip if disk selector is empty or null
    if [[ -z "$expected_disk" ]] || [[ "$expected_disk" == "null" ]]; then
        log debug "Disk selector is flexible or empty, skipping disk check" "ip=${node_ip}"
        return 0
    fi

    log debug "Checking if disk is available" "ip=${node_ip}" "disk=${expected_disk}"

    # Query available disks on the node
    if talosctl get disks -n "${node_ip}" --insecure -o json 2>/dev/null | \
        yq -e ".[] | select(.devname == \"${expected_disk}\")" >/dev/null 2>&1; then
        log info "Expected disk available" "ip=${node_ip}" "disk=${expected_disk}"
        return 0
    fi

    log error "Expected disk NOT found on node" "ip=${node_ip}" "disk=${expected_disk}"
    return 1
}

function extract_disk_selector() {
    local talconfig="$1"
    local node_ip="$2"

    # Extract installDisk or installDiskSelector for this node
    # This is a simplified version - real implementation would parse YAML properly
    local install_disk
    install_disk=$(yq -r ".nodes[] | select(.ipAddress == \"${node_ip}\") | .installDisk // .installDiskSelector.serial // empty" "${talconfig}")

    echo "${install_disk}"
}

function main() {
    check_env TALOSCONFIG ROOT_DIR
    check_cli talosctl yq

    local talconfig="${ROOT_DIR}/talos/talconfig.yaml"

    if [[ ! -f "${talconfig}" ]]; then
        log error "talconfig.yaml not found" "path=${talconfig}"
    fi

    log info "Talos bootstrap pre-flight health check starting"
    log debug "Configuration file" "talconfig=${talconfig}"

    local nodes=()
    mapfile -t nodes < <(get_all_nodes "${talconfig}")

    if [[ ${#nodes[@]} -eq 0 ]]; then
        log error "No nodes found in talconfig.yaml"
    fi

    log info "Found nodes to check" "count=${#nodes[@]}" "nodes=${nodes[*]}"

    local failed_nodes=()
    local failed_reasons=()

    for node_ip in "${nodes[@]}"; do
        log info "Checking node" "ip=${node_ip}"

        # Check 1: Node is reachable
        if ! check_node_reachable "${node_ip}"; then
            failed_nodes+=("${node_ip}")
            failed_reasons+=("Node unreachable after ${NODE_REACHABILITY_RETRIES} attempts")
            continue
        fi

        # Check 2: Node is in MAINTENANCE stage
        if ! check_node_stage "${node_ip}"; then
            log warn "Node not in MAINTENANCE stage (may already be configured)" "ip=${node_ip}"
            # Don't fail on this - could be a retry after partial success
        fi

        # Check 3: Disk selector validation (optional)
        local install_disk
        install_disk=$(extract_disk_selector "${talconfig}" "${node_ip}")

        if [[ -n "${install_disk}" ]] && [[ "${install_disk}" != "null" ]]; then
            if ! check_disk_available "${node_ip}" "${install_disk}"; then
                failed_nodes+=("${node_ip}")
                failed_reasons+=("Disk not found: ${install_disk}")
                continue
            fi
        fi

        log info "Node pre-flight check passed" "ip=${node_ip}"
    done

    # Summary
    local summary_status="PASS"
    if [[ ${#failed_nodes[@]} -gt 0 ]]; then
        summary_status="FAIL"
        log error "Pre-flight check FAILED for nodes: ${failed_nodes[*]}"
        for i in "${!failed_nodes[@]}"; do
            log error "  - ${failed_nodes[$i]}: ${failed_reasons[$i]}"
        done
        return 1
    fi

    log info "Pre-flight check COMPLETE" \
        "status=${summary_status}" \
        "total_nodes=${#nodes[@]}" \
        "passed=${#nodes[@]}" \
        "failed=${#failed_nodes[@]}"
    return 0
}

main "$@"
