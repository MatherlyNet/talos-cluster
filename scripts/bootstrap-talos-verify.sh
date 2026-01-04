#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="${LOG_LEVEL:-info}"
export ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel)}"

# Verification configuration
readonly VERIFICATION_TIMEOUT=300  # 5 minutes
readonly CHECK_INTERVAL=5

declare -a VERIFIED_NODES=()
declare -a STUCK_NODES=()

function get_node_stage() {
    local node_ip="$1"

    # Query the machine config phase/stage
    talosctl get machineconfig -n "${node_ip}" --insecure -o json 2>/dev/null | \
        yq -r '.phase // "MAINTENANCE"' || echo "UNKNOWN"
}

function wait_for_node_transition() {
    local node_ip="$1"
    local initial_stage="$2"
    local timeout="${3:-${VERIFICATION_TIMEOUT}}"

    log info "Waiting for node to transition from ${initial_stage}" "ip=${node_ip}" "timeout=${timeout}s"

    local elapsed=0
    local checks=0

    while [[ $elapsed -lt $timeout ]]; do
        local current_stage
        current_stage=$(get_node_stage "${node_ip}")

        ((checks++))

        if [[ "$current_stage" != "$initial_stage" ]]; then
            log info "Node transitioned to new stage" \
                "ip=${node_ip}" "from=${initial_stage}" "to=${current_stage}" "elapsed=${elapsed}s" "checks=${checks}"
            VERIFIED_NODES+=("${node_ip}")
            return 0
        fi

        log debug "Node still in ${initial_stage} stage" \
            "ip=${node_ip}" "elapsed=${elapsed}s" "check=${checks}"

        elapsed=$((elapsed + CHECK_INTERVAL))
        sleep "${CHECK_INTERVAL}"
    done

    log error "Node did not transition within ${timeout}s" "ip=${node_ip}" "stuck_stage=${initial_stage}" "checks=${checks}"
    STUCK_NODES+=("${node_ip}")
    return 1
}

function verify_all_nodes() {
    local talconfig="$1"

    log info "Verifying config application on all nodes"

    # Extract all node IPs from talconfig
    local nodes=()
    mapfile -t nodes < <(yq -r '.nodes[].ipAddress' "${talconfig}")

    if [[ ${#nodes[@]} -eq 0 ]]; then
        log error "No nodes found in talconfig.yaml"
    fi

    log debug "Nodes to verify" "count=${#nodes[@]}" "nodes=${nodes[*]}"

    # Verify each node
    for node_ip in "${nodes[@]}"; do
        log info "Starting verification for node" "ip=${node_ip}"

        # All nodes should transition away from MAINTENANCE after config apply
        if ! wait_for_node_transition "${node_ip}" "MAINTENANCE"; then
            log error "Verification failed for node ${node_ip}"
            # Continue to next node instead of stopping
        fi
    done

    # Generate summary
    log info "Verification complete" \
        "verified=${#VERIFIED_NODES[@]}" \
        "stuck=${#STUCK_NODES[@]}" \
        "total=${#nodes[@]}"

    if [[ ${#STUCK_NODES[@]} -gt 0 ]]; then
        log error "Nodes stuck in MAINTENANCE stage: ${STUCK_NODES[*]}"
        log info "Recovery options:"
        log info "  1. Check node logs: talosctl dmesg -n <ip> --insecure"
        log info "  2. Reboot node: talosctl reboot -n <ip> --insecure"
        log info "  3. Reset and retry: talosctl reset -n <ip> --insecure --graceful=false"
        return 1
    fi

    log info "All nodes verified successfully"
    return 0
}

function check_node_services() {
    local node_ip="$1"

    log debug "Checking critical services on node" "ip=${node_ip}"

    # Check that talosctl can query services (indicates node is responsive)
    if ! talosctl services -n "${node_ip}" --insecure &>/dev/null; then
        log warn "Could not query services (node may still be booting)" "ip=${node_ip}"
        return 1
    fi

    log debug "Services query successful" "ip=${node_ip}"
    return 0
}

function generate_summary() {
    log info "========== Talos Node Verification Summary =========="
    log info "Verified Nodes:  ${#VERIFIED_NODES[@]}"
    if [[ ${#VERIFIED_NODES[@]} -gt 0 ]]; then
        for node in "${VERIFIED_NODES[@]}"; do
            log info "  ✓ ${node}"
        done
    fi

    if [[ ${#STUCK_NODES[@]} -gt 0 ]]; then
        log info "Stuck Nodes:     ${#STUCK_NODES[@]}"
        for node in "${STUCK_NODES[@]}"; do
            log info "  ✗ ${node}"
        done
    fi
    log info "====================================================="
}

function main() {
    check_env TALOSCONFIG ROOT_DIR
    check_cli talosctl yq

    local talconfig="${ROOT_DIR}/talos/talconfig.yaml"

    if [[ ! -f "${talconfig}" ]]; then
        log error "talconfig.yaml not found" "path=${talconfig}"
    fi

    log info "Talos bootstrap node verification starting"
    log debug "Configuration file" "talconfig=${talconfig}"

    if ! verify_all_nodes "${talconfig}"; then
        generate_summary
        log error "Bootstrap node verification FAILED"
        return 1
    fi

    generate_summary
    log info "Bootstrap node verification COMPLETE"
    return 0
}

main "$@"
