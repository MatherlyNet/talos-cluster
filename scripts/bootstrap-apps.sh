#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

# Maximum parallel jobs for background operations
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-4}"

# Track background job PIDs for parallel execution
declare -a BACKGROUND_PIDS=()

# Run a command in background and track its PID
function run_parallel() {
    local name="$1"
    shift
    log debug "Starting parallel task" "task=${name}"
    "$@" &
    BACKGROUND_PIDS+=($!)
}

# Wait for all background jobs to complete
function wait_parallel() {
    local failed=0
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done
    BACKGROUND_PIDS=()
    return $failed
}

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    log debug "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        log info "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        log info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# Namespaces to be applied before the SOPS secrets are installed
function apply_namespaces() {
    log debug "Applying namespaces"

    local -r apps_dir="${ROOT_DIR}/kubernetes/apps"

    if [[ ! -d "${apps_dir}" ]]; then
        log error "Directory does not exist" "directory=${apps_dir}"
    fi

    for app in "${apps_dir}"/*/; do
        namespace=$(basename "${app}")

        # Check if the namespace resources are up-to-date
        if kubectl get namespace "${namespace}" &>/dev/null; then
            log info "Namespace resource is up-to-date" "resource=${namespace}"
            continue
        fi

        # Apply the namespace resources
        if kubectl create namespace "${namespace}" --dry-run=client --output=yaml \
            | kubectl apply --server-side --filename - &>/dev/null;
        then
            log info "Namespace resource applied" "resource=${namespace}"
        else
            log error "Failed to apply namespace resource" "resource=${namespace}"
        fi
    done
}

# SOPS secrets to be applied before the helmfile charts are installed
function apply_sops_secrets() {
    log debug "Applying secrets"

    local -r secrets=(
        "${ROOT_DIR}/bootstrap/github-deploy-key.sops.yaml"
        "${ROOT_DIR}/bootstrap/sops-age.sops.yaml"
        "${ROOT_DIR}/kubernetes/components/sops/cluster-secrets.sops.yaml"
    )

    for secret in "${secrets[@]}"; do
        if [ ! -f "${secret}" ]; then
            log warn "File does not exist" "file=${secret}"
            continue
        fi

        # Check if the secret resources are up-to-date
        if sops exec-file "${secret}" "kubectl --namespace flux-system diff --filename {}" &>/dev/null; then
            log info "Secret resource is up-to-date" "resource=$(basename "${secret}" ".sops.yaml")"
            continue
        fi

        # Apply secret resources
        if sops exec-file "${secret}" "kubectl --namespace flux-system apply --server-side --filename {}" &>/dev/null; then
            log info "Secret resource applied successfully" "resource=$(basename "${secret}" ".sops.yaml")"
        else
            log error "Failed to apply secret resource" "resource=$(basename "${secret}" ".sops.yaml")"
        fi
    done
}

# CRDs to be applied before the helmfile charts are installed
function apply_crds() {
    log debug "Applying CRDs"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/00-crds.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log fatal "File does not exist" "file" "${helmfile_file}"
    fi

    if ! crds=$(helmfile --file "${helmfile_file}" template --quiet) || [[ -z "${crds}" ]]; then
        log fatal "Failed to render CRDs from Helmfile" "file" "${helmfile_file}"
    fi

    if echo "${crds}" | kubectl diff --filename - &>/dev/null; then
        log info "CRDs are up-to-date"
        return
    fi

    if ! echo "${crds}" | kubectl apply --server-side --filename - &>/dev/null; then
        log fatal "Failed to apply crds from Helmfile" "file" "${helmfile_file}"
    fi

    log info "CRDs applied successfully"
}

# Sync Helm releases
function sync_helm_releases() {
    log debug "Syncing Helm releases"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/01-apps.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log error "File does not exist" "file=${helmfile_file}"
    fi

    if ! helmfile --file "${helmfile_file}" sync --hide-notes; then
        log error "Failed to sync Helm releases"
    fi

    log info "Helm releases synced successfully"
}

function main() {
    check_env KUBECONFIG TALOSCONFIG
    check_cli helmfile kubectl kustomize sops talhelper yq

    local start_time
    start_time=$(date +%s)

    # Phase 1: Wait for nodes (required before anything else)
    wait_for_nodes

    # Phase 2: Apply namespaces and secrets in parallel (independent operations)
    log info "Phase 2: Applying namespaces and secrets in parallel"
    run_parallel "namespaces" apply_namespaces
    run_parallel "secrets" apply_sops_secrets
    if ! wait_parallel; then
        log error "Phase 2 failed: namespaces or secrets application failed"
    fi
    log info "Phase 2 complete: namespaces and secrets applied"

    # Phase 3: Apply CRDs (depends on namespaces)
    log info "Phase 3: Applying CRDs"
    apply_crds

    # Phase 4: Sync Helm releases (depends on CRDs)
    log info "Phase 4: Syncing Helm releases"
    sync_helm_releases

    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    log info "Congrats! The cluster is bootstrapped and Flux is syncing the Git repository" "duration=${duration}s"
}

main "$@"
