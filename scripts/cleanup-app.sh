#!/usr/bin/env bash

# cleanup-app.sh - Kubernetes Application Cleanup Tool
#
# Purpose:
#   Time-saving tool for cleaning up failed deployments during development.
#   Discovers and removes all Kubernetes resources related to an application.
#
# Usage:
#   cleanup-app.sh [OPTIONS] [APP_NAME]
#
# Options:
#   -h, --help          Show this help message
#   -v, --version       Show version information
#   -d, --dry-run       Preview resources without deleting
#   -y, --yes           Skip confirmation prompts (automatic mode)
#   -n, --namespace NS  Limit search to specific namespace
#   -t, --timeout SEC   Timeout for kubectl commands (default: 30)
#   --trace             Enable debug tracing (set -x)
#
# Exit Codes:
#   0 - Success (all resources deleted)
#   1 - Partial failure (some resources failed to delete)
#   2 - Error (validation failed, missing dependencies, user abort)
#
# Author: Generated for matherlynet-talos-cluster
# Version: 1.0.0
# Last Modified: 2026-01-11

set -Eeuo pipefail

# Enable error tracing and inheritance in subshells
shopt -s inherit_errexit 2>/dev/null || true

# Script metadata
readonly SCRIPT_NAME="cleanup-app"
readonly SCRIPT_VERSION="1.2.0"

# Configuration defaults
readonly DEFAULT_TIMEOUT=30

#######################################
# GUARDRAILS: Protected namespaces and critical components
# These cannot be cleaned up to prevent catastrophic cluster failure
#######################################

# Protected namespaces - cleanup is completely blocked
readonly -a PROTECTED_NAMESPACES=(
  "kube-system"
  "kube-public"
  "kube-node-lease"
  "flux-system"
  "cert-manager"
  "cnpg-system"
  "envoy-gateway-system"
)

# Critical applications - cleanup is blocked regardless of namespace
# These are infrastructure components that would cause cluster failure or security issues
readonly -a CRITICAL_APPS=(
  # Flux GitOps - removing breaks all reconciliation
  "flux-operator"
  "flux-instance"
  "flux"

  # CNI - removing breaks all pod networking
  "cilium"
  "cilium-operator"
  "hubble"

  # DNS - removing breaks service discovery
  "coredns"
  "k8s-gateway"
  "external-dns"

  # Certificate management - removing breaks TLS/HTTPS
  "cert-manager"
  "cert-manager-webhook"
  "cert-manager-cainjector"

  # Ingress/Gateway - removing breaks external access
  "envoy-gateway"
  "envoy"
  "cloudflared"

  # Container image distribution
  "spegel"

  # Metrics and monitoring infrastructure
  "metrics-server"

  # Cloud controller managers
  "talos-cloud-controller-manager"
  "proxmox-cloud-controller-manager"

  # CSI drivers - removing breaks storage
  "proxmox-csi"
  "proxmox-csi-plugin"

  # Operators (not instances) - removing orphans managed resources
  "cnpg-controller-manager"
  "cloudnative-pg"
  "keycloak-operator"
  "dragonfly-operator"

  # Security - removing could expose cluster
  "external-secrets"
  "reloader"
)

# Warning-level apps - allow with explicit confirmation
# These are important but recoverable
readonly -a WARNING_APPS=(
  # Identity providers - removing breaks SSO
  "keycloak"

  # Databases - removing causes data loss
  "postgres"
  "postgresql"
  "cnpg"

  # Cache - removing may cause application issues
  "dragonfly"
  "redis"

  # Storage backends
  "rustfs"
  "minio"
)

# Track Flux Kustomization for reconcile option
FLUX_KS_NAME=""
FLUX_KS_NAMESPACE="flux-system"

TIMEOUT="${DEFAULT_TIMEOUT}"
DRY_RUN=false
AUTO_YES=false
TARGET_NAMESPACE=""
APP_NAME=""
TRACE_MODE=false

# Color codes for output (disable if not a terminal)
if [[ -t 1 ]]; then
  readonly COLOR_RESET='\033[0m'
  readonly COLOR_RED='\033[0;31m'
  readonly COLOR_GREEN='\033[0;32m'
  readonly COLOR_YELLOW='\033[0;33m'
  readonly COLOR_BLUE='\033[0;34m'
  readonly COLOR_CYAN='\033[0;36m'
  readonly COLOR_BOLD='\033[1m'
else
  readonly COLOR_RESET=''
  readonly COLOR_RED=''
  readonly COLOR_GREEN=''
  readonly COLOR_YELLOW=''
  readonly COLOR_BLUE=''
  readonly COLOR_CYAN=''
  readonly COLOR_BOLD=''
fi

# Temporary file for storing discovered resources
TEMP_RESOURCES=""

# Resource types to discover (grouped by category)
declare -A RESOURCE_TYPES=(
  ["Flux Resources"]="kustomizations.kustomize.toolkit.fluxcd.io helmreleases.helm.toolkit.fluxcd.io gitrepositories.source.toolkit.fluxcd.io ocirepositories.source.toolkit.fluxcd.io helmrepositories.source.toolkit.fluxcd.io"
  ["Workloads"]="deployments statefulsets daemonsets jobs cronjobs replicasets pods"
  ["Networking"]="services ingresses httproutes.gateway.networking.k8s.io grpcroutes.gateway.networking.k8s.io referencegrants.gateway.networking.k8s.io ciliumnetworkpolicies.cilium.io networkpolicies"
  ["Configuration"]="configmaps secrets"
  ["Storage"]="persistentvolumeclaims persistentvolumes"
  ["Database"]="clusters.postgresql.cnpg.io backups.postgresql.cnpg.io scheduledbackups.postgresql.cnpg.io poolers.postgresql.cnpg.io"
  ["RBAC & Quotas"]="serviceaccounts roles rolebindings resourcequotas limitranges"
  ["Custom Resources"]="externalsecrets.external-secrets.io servicemonitors.monitoring.coreos.com securitypolicies.gateway.envoyproxy.io"
)

# Track suspended Kustomizations for resume
declare -a SUSPENDED_KUSTOMIZATIONS=()

# Track secondary namespaces discovered
declare -a SECONDARY_NAMESPACES=()

#######################################
# Cleanup function for trap
# Globals:
#   TEMP_RESOURCES
# Arguments:
#   None
# Returns:
#   None
#######################################
cleanup() {
  local exit_code=$?
  if [[ -n "${TEMP_RESOURCES}" && -f "${TEMP_RESOURCES}" ]]; then
    rm -f -- "${TEMP_RESOURCES}"
  fi
  exit "${exit_code}"
}

trap cleanup EXIT SIGINT SIGTERM SIGHUP

#######################################
# Logging functions with timestamps and colors
# Globals:
#   COLOR_* variables
# Arguments:
#   $@ - Message to log
# Returns:
#   None
#######################################
log_info() {
  printf "[%s] ${COLOR_BLUE}INFO${COLOR_RESET}: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_success() {
  printf "[%s] ${COLOR_GREEN}SUCCESS${COLOR_RESET}: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_warn() {
  printf "[%s] ${COLOR_YELLOW}WARN${COLOR_RESET}: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_error() {
  printf "[%s] ${COLOR_RED}ERROR${COLOR_RESET}: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_debug() {
  if [[ "${TRACE_MODE}" == "true" ]]; then
    printf "[%s] ${COLOR_CYAN}DEBUG${COLOR_RESET}: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  fi
}

#######################################
# GUARDRAIL VALIDATION FUNCTIONS
#######################################

#######################################
# Check if namespace is protected
# Globals:
#   PROTECTED_NAMESPACES
# Arguments:
#   $1 - Namespace to check
# Returns:
#   0 if protected, 1 if not protected
#######################################
is_protected_namespace() {
  local namespace="$1"
  for protected in "${PROTECTED_NAMESPACES[@]}"; do
    if [[ "${namespace}" == "${protected}" ]]; then
      return 0
    fi
  done
  return 1
}

#######################################
# Check if application is critical infrastructure
# Globals:
#   CRITICAL_APPS
# Arguments:
#   $1 - Application name to check
# Returns:
#   0 if critical, 1 if not critical
#######################################
is_critical_app() {
  local app_name="$1"
  local app_lower
  app_lower=$(printf "%s" "${app_name}" | tr '[:upper:]' '[:lower:]')

  for critical in "${CRITICAL_APPS[@]}"; do
    # Check exact match or if app name contains critical name
    if [[ "${app_lower}" == "${critical}" ]] || [[ "${app_lower}" == *"${critical}"* ]]; then
      return 0
    fi
  done
  return 1
}

#######################################
# Check if application requires warning
# Globals:
#   WARNING_APPS
# Arguments:
#   $1 - Application name to check
# Returns:
#   0 if warning needed, 1 if no warning
#######################################
is_warning_app() {
  local app_name="$1"
  local app_lower
  app_lower=$(printf "%s" "${app_name}" | tr '[:upper:]' '[:lower:]')

  for warning in "${WARNING_APPS[@]}"; do
    if [[ "${app_lower}" == "${warning}" ]] || [[ "${app_lower}" == *"${warning}"* ]]; then
      return 0
    fi
  done
  return 1
}

#######################################
# Validate application against guardrails
# Globals:
#   APP_NAME, TARGET_NAMESPACE, AUTO_YES
# Arguments:
#   None
# Returns:
#   0 if safe to proceed, 2 if blocked
#######################################
validate_guardrails() {
  log_info "Validating against cluster guardrails..."

  # Check if target namespace is protected
  if [[ -n "${TARGET_NAMESPACE}" ]] && is_protected_namespace "${TARGET_NAMESPACE}"; then
    printf "\n"
    printf "%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n" "${COLOR_RED}" "${COLOR_RESET}"
    printf "%b║  🛑 BLOCKED: PROTECTED NAMESPACE                                              ║%b\n" "${COLOR_RED}" "${COLOR_RESET}"
    printf "%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n" "${COLOR_RED}" "${COLOR_RESET}"
    printf "\n"
    log_error "Namespace '${TARGET_NAMESPACE}' is protected and cannot be targeted for cleanup"
    log_error "Protected namespaces contain critical cluster infrastructure"
    printf "\n"
    printf "%bProtected namespaces:%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    for ns in "${PROTECTED_NAMESPACES[@]}"; do
      printf "  • %s\n" "${ns}"
    done
    printf "\n"
    log_error "If you need to modify resources in this namespace, use kubectl directly with extreme caution"
    return 2
  fi

  # Check if application is critical infrastructure
  if is_critical_app "${APP_NAME}"; then
    printf "\n"
    printf "%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n" "${COLOR_RED}" "${COLOR_RESET}"
    printf "%b║  🛑 BLOCKED: CRITICAL CLUSTER COMPONENT                                       ║%b\n" "${COLOR_RED}" "${COLOR_RESET}"
    printf "%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n" "${COLOR_RED}" "${COLOR_RESET}"
    printf "\n"
    log_error "Application '${APP_NAME}' is a critical cluster component"
    log_error "Removing this component could cause:"
    printf "\n"
    printf "  ${COLOR_RED}•${COLOR_RESET} Catastrophic cluster failure\n"
    printf "  ${COLOR_RED}•${COLOR_RESET} Complete loss of pod networking\n"
    printf "  ${COLOR_RED}•${COLOR_RESET} Loss of GitOps reconciliation\n"
    printf "  ${COLOR_RED}•${COLOR_RESET} Security vulnerabilities\n"
    printf "  ${COLOR_RED}•${COLOR_RESET} Data loss from orphaned resources\n"
    printf "\n"
    printf "%bCritical components include:%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf "  Flux, Cilium, CoreDNS, cert-manager, Envoy Gateway,\n"
    printf "  Spegel, Metrics Server, Cloud Controllers, CSI drivers,\n"
    printf "  and all infrastructure operators\n"
    printf "\n"
    log_error "This operation is blocked for safety. No override is available."
    return 2
  fi

  # Check if application requires warning
  if is_warning_app "${APP_NAME}"; then
    printf "\n"
    printf "%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf "%b║  ⚠️  WARNING: SENSITIVE APPLICATION                                           ║%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf "%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf "\n"
    log_warn "Application '${APP_NAME}' is a sensitive component"
    log_warn "Removing this application may cause:"
    printf "\n"
    printf "  ${COLOR_YELLOW}•${COLOR_RESET} Loss of authentication/SSO capabilities\n"
    printf "  ${COLOR_YELLOW}•${COLOR_RESET} Permanent data loss (databases)\n"
    printf "  ${COLOR_YELLOW}•${COLOR_RESET} Application failures (cache dependencies)\n"
    printf "  ${COLOR_YELLOW}•${COLOR_RESET} Storage unavailability\n"
    printf "\n"

    if [[ "${AUTO_YES}" == "true" ]]; then
      log_error "Cannot use --yes (automatic mode) with sensitive applications"
      log_error "Explicit confirmation is required for safety"
      return 2
    fi

    printf "%bType 'I UNDERSTAND THE RISKS' to proceed:%b " "${COLOR_BOLD}" "${COLOR_RESET}" >&2
    local response
    read -r response

    if [[ "${response}" != "I UNDERSTAND THE RISKS" ]]; then
      log_warn "Confirmation not provided, aborting cleanup"
      return 2
    fi

    log_info "Warning acknowledged, proceeding with cleanup"
  fi

  log_success "Guardrail validation passed"
  return 0
}

#######################################
# FLUX GITOPS HANDLING FUNCTIONS
#######################################

#######################################
# Discover all Flux Kustomizations related to the application
# Searches BOTH flux-system AND app-specific namespaces
# Globals:
#   APP_NAME, TIMEOUT, FLUX_KS_NAME, FLUX_KS_NAMESPACE, SUSPENDED_KUSTOMIZATIONS
# Arguments:
#   None
# Returns:
#   0 if found, 1 if not found
#######################################
discover_flux_kustomizations() {
  log_info "Discovering Flux Kustomizations for ${APP_NAME}..."

  SUSPENDED_KUSTOMIZATIONS=()
  local found_any=false

  # Get all namespaces that might contain Kustomizations
  local search_namespaces=("flux-system")

  # Also search in common app namespaces
  local app_namespaces
  app_namespaces=$(timeout "${TIMEOUT}" kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -E "(ai-system|ai-services|${APP_NAME})" || true)

  for ns in ${app_namespaces}; do
    if [[ ! " ${search_namespaces[*]} " =~ " ${ns} " ]]; then
      search_namespaces+=("${ns}")
    fi
  done

  log_debug "Searching namespaces for Kustomizations: ${search_namespaces[*]}"

  for ns in "${search_namespaces[@]}"; do
    # Find Kustomizations by name match
    local ks_list
    ks_list=$(timeout "${TIMEOUT}" kubectl get kustomization -n "${ns}" -o json 2>/dev/null | \
      jq -r --arg app "${APP_NAME}" '.items[] | select(.metadata.name | contains($app)) | .metadata.name' 2>/dev/null || true)

    if [[ -n "${ks_list}" ]]; then
      while IFS= read -r ks_name; do
        if [[ -n "${ks_name}" ]]; then
          SUSPENDED_KUSTOMIZATIONS+=("${ns}:${ks_name}")
          found_any=true
          log_debug "Found Kustomization: ${ks_name} in ${ns}"

          # Store first one for later reconcile
          if [[ -z "${FLUX_KS_NAME}" ]]; then
            FLUX_KS_NAME="${ks_name}"
            FLUX_KS_NAMESPACE="${ns}"
          fi
        fi
      done <<< "${ks_list}"
    fi

    # Also find by path containing app name
    local ks_by_path
    ks_by_path=$(timeout "${TIMEOUT}" kubectl get kustomization -n "${ns}" -o json 2>/dev/null | \
      jq -r --arg app "${APP_NAME}" '.items[] | select(.spec.path != null) | select(.spec.path | contains($app)) | .metadata.name' 2>/dev/null || true)

    if [[ -n "${ks_by_path}" ]]; then
      while IFS= read -r ks_name; do
        if [[ -n "${ks_name}" ]]; then
          local entry="${ns}:${ks_name}"
          # Avoid duplicates
          if [[ ! " ${SUSPENDED_KUSTOMIZATIONS[*]} " =~ " ${entry} " ]]; then
            SUSPENDED_KUSTOMIZATIONS+=("${entry}")
            found_any=true
            log_debug "Found Kustomization by path: ${ks_name} in ${ns}"
          fi
        fi
      done <<< "${ks_by_path}"
    fi
  done

  if [[ "${found_any}" == "true" ]]; then
    log_success "Found ${#SUSPENDED_KUSTOMIZATIONS[@]} related Kustomization(s)"
    return 0
  else
    log_warn "No Flux Kustomizations found for ${APP_NAME}"
    return 1
  fi
}

#######################################
# Suspend all discovered Flux Kustomizations
# CRITICAL: Must be done BEFORE deleting resources to prevent race condition
# Globals:
#   SUSPENDED_KUSTOMIZATIONS, TIMEOUT, DRY_RUN
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
suspend_flux_kustomizations() {
  if [[ ${#SUSPENDED_KUSTOMIZATIONS[@]} -eq 0 ]]; then
    log_debug "No Kustomizations to suspend"
    return 0
  fi

  printf "\n"
  printf "%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
  printf "%b║  FLUX SUSPENSION REQUIRED                                                     ║%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
  printf "%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
  printf "\n"

  log_info "Flux Kustomizations must be suspended to prevent recreation during cleanup"
  printf "\n"
  printf "%bKustomizations to suspend:%b\n" "${COLOR_BOLD}" "${COLOR_RESET}"
  for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
    local ns="${entry%%:*}"
    local name="${entry#*:}"
    printf "  • %s (namespace: %s)\n" "${name}" "${ns}"
  done
  printf "\n"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry-run mode: Would suspend ${#SUSPENDED_KUSTOMIZATIONS[@]} Kustomization(s)"
    return 0
  fi

  log_info "Suspending ${#SUSPENDED_KUSTOMIZATIONS[@]} Kustomization(s)..."

  for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
    local ns="${entry%%:*}"
    local name="${entry#*:}"

    if command -v flux &>/dev/null; then
      if flux suspend kustomization "${name}" -n "${ns}" 2>/dev/null; then
        printf "%b✓%b Suspended %s in %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${name}" "${ns}"
      else
        log_warn "Failed to suspend ${name} in ${ns} (may already be suspended)"
      fi
    else
      # Fallback to kubectl patch
      if kubectl patch kustomization "${name}" -n "${ns}" --type=merge -p '{"spec":{"suspend":true}}' 2>/dev/null; then
        printf "%b✓%b Suspended %s in %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${name}" "${ns}"
      else
        log_warn "Failed to suspend ${name} in ${ns}"
      fi
    fi
  done

  printf "\n"
  log_success "Flux reconciliation suspended - resources will not be recreated during cleanup"
  return 0
}

#######################################
# Resume all previously suspended Flux Kustomizations
# Globals:
#   SUSPENDED_KUSTOMIZATIONS, TIMEOUT
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
resume_flux_kustomizations() {
  if [[ ${#SUSPENDED_KUSTOMIZATIONS[@]} -eq 0 ]]; then
    return 0
  fi

  log_info "Resuming ${#SUSPENDED_KUSTOMIZATIONS[@]} Kustomization(s)..."

  for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
    local ns="${entry%%:*}"
    local name="${entry#*:}"

    if command -v flux &>/dev/null; then
      if flux resume kustomization "${name}" -n "${ns}" 2>/dev/null; then
        printf "%b✓%b Resumed %s in %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${name}" "${ns}"
      else
        log_warn "Failed to resume ${name} in ${ns}"
      fi
    else
      # Fallback to kubectl patch
      if kubectl patch kustomization "${name}" -n "${ns}" --type=merge -p '{"spec":{"suspend":false}}' 2>/dev/null; then
        printf "%b✓%b Resumed %s in %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${name}" "${ns}"
      else
        log_warn "Failed to resume ${name} in ${ns}"
      fi
    fi
  done

  return 0
}

#######################################
# Discover secondary namespaces created by the application
# Common patterns: <app>-mcp, <app>-workers, <app>-jobs, etc.
# Globals:
#   APP_NAME, TIMEOUT, SECONDARY_NAMESPACES
# Arguments:
#   None
# Returns:
#   0 if found, 1 if not found
#######################################
discover_secondary_namespaces() {
  log_debug "Searching for secondary namespaces related to ${APP_NAME}..."

  SECONDARY_NAMESPACES=()

  # Common secondary namespace patterns
  local patterns=(
    "${APP_NAME}-mcp"
    "${APP_NAME}-workers"
    "${APP_NAME}-jobs"
    "${APP_NAME}-system"
  )

  for pattern in "${patterns[@]}"; do
    if timeout "${TIMEOUT}" kubectl get namespace "${pattern}" &>/dev/null; then
      SECONDARY_NAMESPACES+=("${pattern}")
      log_debug "Found secondary namespace: ${pattern}"
    fi
  done

  # Also search for namespaces with app label
  local labeled_ns
  labeled_ns=$(timeout "${TIMEOUT}" kubectl get ns -l "app.kubernetes.io/name=${APP_NAME}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

  for ns in ${labeled_ns}; do
    if [[ -n "${ns}" ]] && [[ ! " ${SECONDARY_NAMESPACES[*]} " =~ " ${ns} " ]]; then
      SECONDARY_NAMESPACES+=("${ns}")
      log_debug "Found labeled namespace: ${ns}"
    fi
  done

  if [[ ${#SECONDARY_NAMESPACES[@]} -gt 0 ]]; then
    log_info "Found ${#SECONDARY_NAMESPACES[@]} secondary namespace(s): ${SECONDARY_NAMESPACES[*]}"
    return 0
  fi

  return 1
}

#######################################
# Clean up secondary namespaces
# Globals:
#   SECONDARY_NAMESPACES, DRY_RUN, AUTO_YES, TIMEOUT
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
cleanup_secondary_namespaces() {
  if [[ ${#SECONDARY_NAMESPACES[@]} -eq 0 ]]; then
    return 0
  fi

  printf "\n"
  printf "%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n" "${COLOR_CYAN}" "${COLOR_RESET}"
  printf "%b║  SECONDARY NAMESPACES DETECTED                                                ║%b\n" "${COLOR_CYAN}" "${COLOR_RESET}"
  printf "%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n" "${COLOR_CYAN}" "${COLOR_RESET}"
  printf "\n"

  log_info "The following secondary namespaces were created by ${APP_NAME}:"
  for ns in "${SECONDARY_NAMESPACES[@]}"; do
    printf "  • %s\n" "${ns}"
  done
  printf "\n"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry-run mode: Would delete ${#SECONDARY_NAMESPACES[@]} secondary namespace(s)"
    return 0
  fi

  if [[ "${AUTO_YES}" != "true" ]]; then
    printf "%bDelete these secondary namespaces? [y/N]:%b " "${COLOR_BOLD}" "${COLOR_RESET}" >&2
    local confirm
    read -r confirm

    if [[ ! "${confirm}" =~ ^[Yy] ]]; then
      log_info "Skipping secondary namespace cleanup"
      return 0
    fi
  fi

  log_info "Cleaning up secondary namespaces..."

  for ns in "${SECONDARY_NAMESPACES[@]}"; do
    # First delete all resources in the namespace
    log_debug "Cleaning resources in ${ns}..."
    timeout "${TIMEOUT}" kubectl delete all,configmap,secret,pvc,networkpolicy,ciliumnetworkpolicy,resourcequota --all -n "${ns}" --ignore-not-found=true 2>/dev/null || true

    # Then delete the namespace
    if timeout "${TIMEOUT}" kubectl delete namespace "${ns}" --ignore-not-found=true 2>/dev/null; then
      printf "%b✓%b Deleted namespace: %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${ns}"
    else
      log_warn "Failed to delete namespace ${ns} (may still be terminating)"
    fi
  done

  return 0
}

#######################################
# Display usage information
# Globals:
#   SCRIPT_NAME, DEFAULT_TIMEOUT
# Arguments:
#   None
# Returns:
#   None
#######################################
usage() {
  cat <<EOF
${COLOR_BOLD}${SCRIPT_NAME}${COLOR_RESET} - Kubernetes Application Cleanup Tool (v${SCRIPT_VERSION})

${COLOR_BOLD}USAGE:${COLOR_RESET}
  ${SCRIPT_NAME} [OPTIONS] [APP_NAME]

${COLOR_BOLD}DESCRIPTION:${COLOR_RESET}
  Discovers and removes all Kubernetes resources related to an application.
  Supports interactive and automatic cleanup modes with dry-run capability.
  Includes guardrails to prevent removal of critical cluster infrastructure.

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -h, --help          Show this help message and exit
  -v, --version       Show version information and exit
  -d, --dry-run       Preview resources without deleting (safe mode)
  -y, --yes           Skip confirmation prompts (automatic mode)
                      Note: Cannot be used with sensitive applications
  -n, --namespace NS  Limit search to specific namespace
  -t, --timeout SEC   Timeout for kubectl commands (default: ${DEFAULT_TIMEOUT}s)
  --trace             Enable debug tracing (set -x)

${COLOR_BOLD}ARGUMENTS:${COLOR_RESET}
  APP_NAME            Name of the application to clean up
                      If not provided, will prompt interactively

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  # Interactive mode with preview (recommended first step)
  ${SCRIPT_NAME} --dry-run obot

  # Automatic cleanup without confirmation
  ${SCRIPT_NAME} --yes obot

  # Cleanup in specific namespace only
  ${SCRIPT_NAME} --namespace ai-services obot

  # Interactive mode (prompt for app name)
  ${SCRIPT_NAME}

${COLOR_BOLD}GUARDRAILS (Safety Features):${COLOR_RESET}
  This script includes guardrails to prevent catastrophic cluster damage:

  ${COLOR_RED}BLOCKED (cannot be cleaned up):${COLOR_RESET}
    - Protected namespaces: kube-system, flux-system, cert-manager,
      cnpg-system, envoy-gateway-system, kube-public, kube-node-lease
    - Critical components: Flux, Cilium, CoreDNS, cert-manager, Envoy Gateway,
      Spegel, Metrics Server, Cloud Controllers, CSI drivers, Operators

  ${COLOR_YELLOW}WARNING (requires explicit confirmation):${COLOR_RESET}
    - Sensitive apps: Keycloak, PostgreSQL/CNPG databases, Dragonfly/Redis,
      RustFS/MinIO storage backends
    - --yes flag is disabled for these applications

${COLOR_BOLD}GITOPS WORKFLOW (v1.2.0):${COLOR_RESET}
  The script follows proper GitOps cleanup workflow:
    1) Discovers Flux Kustomizations (in flux-system AND app namespaces)
    2) Discovers secondary namespaces (e.g., obot-mcp for obot)
    3) SUSPENDS Flux reconciliation before deletion (prevents race condition)
    4) Deletes resources
    5) Cleans up secondary namespaces
    6) Offers post-cleanup options (resume/reconcile)

${COLOR_BOLD}POST-CLEANUP OPTIONS:${COLOR_RESET}
  After cleanup, Flux remains SUSPENDED. You choose:
    1) Resume + Reconcile - Redeploy if app still exists in Git
    2) Resume only - Re-enable Flux without forcing reconcile
    3) Verify cleanup - Check for lingering artifacts (Flux stays suspended)
    4) Exit - Manual resume required later

${COLOR_BOLD}EXIT CODES:${COLOR_RESET}
  0 - Success (all resources deleted)
  1 - Partial failure (some resources failed to delete)
  2 - Error (guardrail blocked, validation failed, user abort)

${COLOR_BOLD}RESOURCE TYPES DISCOVERED:${COLOR_RESET}
  - Flux: Kustomizations, HelmReleases, GitRepositories, OCIRepositories
  - Workloads: Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, Pods
  - Networking: Services, Ingresses, HTTPRoutes, GRPCRoutes, ReferenceGrants,
    NetworkPolicies, CiliumNetworkPolicies, SecurityPolicies
  - Configuration: ConfigMaps, Secrets
  - Storage: PersistentVolumeClaims, PersistentVolumes
  - RBAC & Quotas: ServiceAccounts, Roles, RoleBindings, ResourceQuotas
  - Database: CNPG Clusters, Backups, ScheduledBackups, Poolers
  - Custom: ExternalSecrets, ServiceMonitors

EOF
}

#######################################
# Display version information
# Globals:
#   SCRIPT_NAME, SCRIPT_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
version() {
  cat <<EOF
${SCRIPT_NAME} version ${SCRIPT_VERSION}
Copyright (c) 2026 matherlynet-talos-cluster
EOF
}

#######################################
# Validate required dependencies
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if all dependencies available, 2 otherwise
#######################################
validate_dependencies() {
  local missing_deps=()

  if ! command -v kubectl &>/dev/null; then
    missing_deps+=("kubectl")
  fi

  if ! command -v jq &>/dev/null; then
    missing_deps+=("jq")
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_error "Please install missing tools and try again"
    return 2
  fi

  # Verify kubectl can connect to cluster
  if ! timeout "${TIMEOUT}" kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    log_error "Please verify your kubeconfig and cluster connectivity"
    return 2
  fi

  log_debug "All dependencies validated successfully"
  return 0
}

#######################################
# Parse command line arguments
# Globals:
#   DRY_RUN, AUTO_YES, TARGET_NAMESPACE, TIMEOUT, APP_NAME, TRACE_MODE
# Arguments:
#   $@ - Command line arguments
# Returns:
#   0 on success, 2 on invalid arguments
#######################################
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -v|--version)
        version
        exit 0
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -y|--yes)
        AUTO_YES=true
        shift
        ;;
      -n|--namespace)
        if [[ -z "${2:-}" ]]; then
          log_error "Option --namespace requires an argument"
          return 2
        fi
        TARGET_NAMESPACE="$2"
        shift 2
        ;;
      -t|--timeout)
        if [[ -z "${2:-}" ]]; then
          log_error "Option --timeout requires an argument"
          return 2
        fi
        if ! [[ "$2" =~ ^[0-9]+$ ]]; then
          log_error "Timeout must be a positive integer"
          return 2
        fi
        TIMEOUT="$2"
        shift 2
        ;;
      --trace)
        TRACE_MODE=true
        set -x
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        return 2
        ;;
      *)
        if [[ -z "${APP_NAME}" ]]; then
          APP_NAME="$1"
        else
          log_error "Multiple app names provided: ${APP_NAME} and $1"
          return 2
        fi
        shift
        ;;
    esac
  done

  return 0
}

#######################################
# Prompt for application name interactively
# Globals:
#   APP_NAME
# Arguments:
#   None
# Returns:
#   0 on success, 2 if user cancels
#######################################
prompt_app_name() {
  if [[ -n "${APP_NAME}" ]]; then
    return 0
  fi

  printf "%bEnter application name to clean up:%b " "${COLOR_BOLD}" "${COLOR_RESET}" >&2
  read -r APP_NAME

  if [[ -z "${APP_NAME}" ]]; then
    log_error "Application name cannot be empty"
    return 2
  fi

  return 0
}

#######################################
# Discover resources related to application
# Globals:
#   APP_NAME, TARGET_NAMESPACE, TIMEOUT, TEMP_RESOURCES, RESOURCE_TYPES
# Arguments:
#   None
# Returns:
#   0 if resources found, 1 if no resources found
#######################################
discover_resources() {
  log_info "Discovering resources for application: ${COLOR_BOLD}${APP_NAME}${COLOR_RESET}"

  TEMP_RESOURCES="$(mktemp)"
  local total_found=0

  # Build namespace filter args as array
  local namespace_filter=()
  if [[ -n "${TARGET_NAMESPACE}" ]]; then
    namespace_filter=("--namespace=${TARGET_NAMESPACE}")
    log_info "Limiting search to namespace: ${COLOR_CYAN}${TARGET_NAMESPACE}${COLOR_RESET}"
  else
    namespace_filter=("--all-namespaces")
  fi

  # Iterate through resource type categories
  for category in "${!RESOURCE_TYPES[@]}"; do
    local types="${RESOURCE_TYPES[$category]}"
    local category_found=0

    for resource_type in ${types}; do
      log_debug "Searching for ${resource_type}"

      # Try to get resources, skip if type doesn't exist
      local resources
      if ! resources=$(timeout "${TIMEOUT}" kubectl get "${resource_type}" "${namespace_filter[@]}" \
        -o json 2>/dev/null | jq -r --arg app "${APP_NAME}" \
        '.items[] | select(.metadata.name | contains($app)) |
        "\(.kind)|\(.metadata.namespace // "cluster-scoped")|\(.metadata.name)"' 2>/dev/null); then
        continue
      fi

      if [[ -n "${resources}" ]]; then
        while IFS='|' read -r kind namespace name; do
          printf "%s\t%s\t%s\t%s\n" "${category}" "${kind}" "${namespace}" "${name}" >> "${TEMP_RESOURCES}"
          ((category_found++))
          ((total_found++))
        done <<< "${resources}"
      fi
    done

    if [[ ${category_found} -gt 0 ]]; then
      log_debug "Found ${category_found} resources in category: ${category}"
    fi
  done

  if [[ ${total_found} -eq 0 ]]; then
    log_warn "No resources found for application: ${APP_NAME}"
    return 1
  fi

  log_success "Discovered ${COLOR_BOLD}${total_found}${COLOR_RESET} resources"
  return 0
}

#######################################
# Display discovered resources in organized format
# Globals:
#   TEMP_RESOURCES, COLOR_*
# Arguments:
#   None
# Returns:
#   None
#######################################
display_resources() {
  if [[ ! -f "${TEMP_RESOURCES}" ]] || [[ ! -s "${TEMP_RESOURCES}" ]]; then
    return
  fi

  printf "\n%bDiscovered Resources:%b\n" "${COLOR_BOLD}" "${COLOR_RESET}"
  printf "%b%-25s %-30s %-30s %-40s%b\n" "${COLOR_BOLD}" "CATEGORY" "KIND" "NAMESPACE" "NAME" "${COLOR_RESET}"
  printf "%s\n" "$(printf '=%.0s' {1..130})"

  # Sort by category, then kind, then namespace, then name
  sort -t $'\t' -k1,1 -k2,2 -k3,3 -k4,4 "${TEMP_RESOURCES}" | \
  while IFS=$'\t' read -r category kind namespace name; do
    printf "${COLOR_CYAN}%-25s${COLOR_RESET} %-30s ${COLOR_YELLOW}%-30s${COLOR_RESET} %s\n" \
      "${category}" "${kind}" "${namespace}" "${name}"
  done

  printf "\n"
}

#######################################
# Generate kubectl delete commands
# Globals:
#   TEMP_RESOURCES
# Arguments:
#   None
# Returns:
#   None
#######################################
generate_delete_commands() {
  if [[ ! -f "${TEMP_RESOURCES}" ]] || [[ ! -s "${TEMP_RESOURCES}" ]]; then
    return
  fi

  printf "%bGenerated Delete Commands:%b\n\n" "${COLOR_BOLD}" "${COLOR_RESET}"

  # Group by kind and namespace for efficient deletion
  declare -A commands

  while IFS=$'\t' read -r category kind namespace name; do
    local resource_type
    # Convert kind to resource type (lowercase, handle special cases)
    resource_type=$(printf "%s" "${kind}" | tr '[:upper:]' '[:lower:]')

    # Handle special resource types with API groups
    case "${kind}" in
      Kustomization)
        resource_type="kustomizations.kustomize.toolkit.fluxcd.io"
        ;;
      HelmRelease)
        resource_type="helmreleases.helm.toolkit.fluxcd.io"
        ;;
      GitRepository)
        resource_type="gitrepositories.source.toolkit.fluxcd.io"
        ;;
      OCIRepository)
        resource_type="ocirepositories.source.toolkit.fluxcd.io"
        ;;
      HelmRepository)
        resource_type="helmrepositories.source.toolkit.fluxcd.io"
        ;;
      HTTPRoute)
        resource_type="httproutes.gateway.networking.k8s.io"
        ;;
      GRPCRoute)
        resource_type="grpcroutes.gateway.networking.k8s.io"
        ;;
      CiliumNetworkPolicy)
        resource_type="ciliumnetworkpolicies.cilium.io"
        ;;
      Cluster)
        resource_type="clusters.postgresql.cnpg.io"
        ;;
      Backup)
        resource_type="backups.postgresql.cnpg.io"
        ;;
      ScheduledBackup)
        resource_type="scheduledbackups.postgresql.cnpg.io"
        ;;
      Pooler)
        resource_type="poolers.postgresql.cnpg.io"
        ;;
      ExternalSecret)
        resource_type="externalsecrets.external-secrets.io"
        ;;
      ServiceMonitor)
        resource_type="servicemonitors.monitoring.coreos.com"
        ;;
    esac

    local ns_flag=""
    if [[ "${namespace}" != "cluster-scoped" ]]; then
      ns_flag="--namespace=${namespace}"
    fi

    local cmd_key="${resource_type}|${namespace}"
    if [[ -z "${commands[$cmd_key]:-}" ]]; then
      commands[$cmd_key]="${resource_type} ${ns_flag} ${name}"
    else
      commands[$cmd_key]="${commands[$cmd_key]} ${name}"
    fi
  done < "${TEMP_RESOURCES}"

  # Output commands
  for cmd_key in "${!commands[@]}"; do
    printf "${COLOR_GREEN}kubectl delete %s${COLOR_RESET}\n" "${commands[$cmd_key]}"
  done

  printf "\n"
}

#######################################
# Confirm deletion with user
# Globals:
#   AUTO_YES, DRY_RUN, APP_NAME
# Arguments:
#   None
# Returns:
#   0 if confirmed, 2 if cancelled
#######################################
confirm_deletion() {
  if [[ "${AUTO_YES}" == "true" ]]; then
    log_info "Auto-yes mode enabled, proceeding with deletion"
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry-run mode enabled, no resources will be deleted"
    return 0
  fi

  printf "%b%bWARNING:%b This will delete all resources shown above for application: %b%s%b\n" \
    "${COLOR_YELLOW}" "${COLOR_BOLD}" "${COLOR_RESET}" "${COLOR_BOLD}" "${APP_NAME}" "${COLOR_RESET}" >&2
  printf "%bThis action cannot be undone!%b\n\n" "${COLOR_YELLOW}" "${COLOR_RESET}" >&2
  printf "Type 'yes' to confirm deletion: " >&2

  local response
  read -r response

  if [[ "${response}" != "yes" ]]; then
    log_warn "Deletion cancelled by user"
    return 2
  fi

  return 0
}

#######################################
# Execute resource deletion
# Globals:
#   TEMP_RESOURCES, TIMEOUT, DRY_RUN
# Arguments:
#   None
# Returns:
#   0 if all deleted, 1 if partial failure
#######################################
delete_resources() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry-run mode: No resources were deleted"
    return 0
  fi

  log_info "Starting resource deletion..."

  local total_resources=0
  local deleted_count=0
  local failed_count=0
  local failed_resources=()

  total_resources=$(wc -l < "${TEMP_RESOURCES}" | tr -d ' ')

  while IFS=$'\t' read -r category kind namespace name; do
    local resource_type
    resource_type=$(printf "%s" "${kind}" | tr '[:upper:]' '[:lower:]')

    # Handle special resource types (same logic as generate_delete_commands)
    case "${kind}" in
      Kustomization) resource_type="kustomizations.kustomize.toolkit.fluxcd.io" ;;
      HelmRelease) resource_type="helmreleases.helm.toolkit.fluxcd.io" ;;
      GitRepository) resource_type="gitrepositories.source.toolkit.fluxcd.io" ;;
      OCIRepository) resource_type="ocirepositories.source.toolkit.fluxcd.io" ;;
      HelmRepository) resource_type="helmrepositories.source.toolkit.fluxcd.io" ;;
      HTTPRoute) resource_type="httproutes.gateway.networking.k8s.io" ;;
      GRPCRoute) resource_type="grpcroutes.gateway.networking.k8s.io" ;;
      CiliumNetworkPolicy) resource_type="ciliumnetworkpolicies.cilium.io" ;;
      Cluster) resource_type="clusters.postgresql.cnpg.io" ;;
      Backup) resource_type="backups.postgresql.cnpg.io" ;;
      ScheduledBackup) resource_type="scheduledbackups.postgresql.cnpg.io" ;;
      Pooler) resource_type="poolers.postgresql.cnpg.io" ;;
      ExternalSecret) resource_type="externalsecrets.external-secrets.io" ;;
      ServiceMonitor) resource_type="servicemonitors.monitoring.coreos.com" ;;
    esac

    local ns_flag=""
    if [[ "${namespace}" != "cluster-scoped" ]]; then
      ns_flag="--namespace=${namespace}"
    fi

    log_debug "Deleting ${kind}/${name} in ${namespace}"

    if timeout "${TIMEOUT}" kubectl delete "${resource_type}" "${name}" "${ns_flag}" --ignore-not-found=true &>/dev/null; then
      ((deleted_count++))
      printf "%b✓%b Deleted %s/%s in %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${kind}" "${name}" "${namespace}"
    else
      ((failed_count++))
      failed_resources+=("${kind}/${name} in ${namespace}")
      printf "%b✗%b Failed to delete %s/%s in %s\n" "${COLOR_RED}" "${COLOR_RESET}" "${kind}" "${name}" "${namespace}"
    fi
  done < "${TEMP_RESOURCES}"

  printf "\n"
  log_success "Deleted ${deleted_count}/${total_resources} resources"

  if [[ ${failed_count} -gt 0 ]]; then
    log_warn "Failed to delete ${failed_count} resources:"
    for resource in "${failed_resources[@]}"; do
      log_warn "  - ${resource}"
    done
    return 1
  fi

  return 0
}

#######################################
# Verify resources are deleted
# Globals:
#   TEMP_RESOURCES, TIMEOUT
# Arguments:
#   None
# Returns:
#   0 if all deleted, 1 if some remain
#######################################
verify_deletion() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  log_info "Verifying resource deletion..."

  local remaining_count=0
  local remaining_resources=()

  # Wait a moment for deletions to propagate
  sleep 2

  while IFS=$'\t' read -r category kind namespace name; do
    local resource_type
    resource_type=$(printf "%s" "${kind}" | tr '[:upper:]' '[:lower:]')

    # Handle special resource types (same logic as before)
    case "${kind}" in
      Kustomization) resource_type="kustomizations.kustomize.toolkit.fluxcd.io" ;;
      HelmRelease) resource_type="helmreleases.helm.toolkit.fluxcd.io" ;;
      GitRepository) resource_type="gitrepositories.source.toolkit.fluxcd.io" ;;
      OCIRepository) resource_type="ocirepositories.source.toolkit.fluxcd.io" ;;
      HelmRepository) resource_type="helmrepositories.source.toolkit.fluxcd.io" ;;
      HTTPRoute) resource_type="httproutes.gateway.networking.k8s.io" ;;
      GRPCRoute) resource_type="grpcroutes.gateway.networking.k8s.io" ;;
      CiliumNetworkPolicy) resource_type="ciliumnetworkpolicies.cilium.io" ;;
      Cluster) resource_type="clusters.postgresql.cnpg.io" ;;
      Backup) resource_type="backups.postgresql.cnpg.io" ;;
      ScheduledBackup) resource_type="scheduledbackups.postgresql.cnpg.io" ;;
      Pooler) resource_type="poolers.postgresql.cnpg.io" ;;
      ExternalSecret) resource_type="externalsecrets.external-secrets.io" ;;
      ServiceMonitor) resource_type="servicemonitors.monitoring.coreos.com" ;;
    esac

    local ns_flag=""
    if [[ "${namespace}" != "cluster-scoped" ]]; then
      ns_flag="--namespace=${namespace}"
    fi

    if timeout "${TIMEOUT}" kubectl get "${resource_type}" "${name}" "${ns_flag}" &>/dev/null; then
      ((remaining_count++))
      remaining_resources+=("${kind}/${name} in ${namespace}")
    fi
  done < "${TEMP_RESOURCES}"

  if [[ ${remaining_count} -eq 0 ]]; then
    log_success "All resources successfully deleted"
    return 0
  else
    log_warn "${remaining_count} resources still exist (may be in terminating state):"
    for resource in "${remaining_resources[@]}"; do
      log_warn "  - ${resource}"
    done
    return 1
  fi
}

#######################################
# Detect Flux Kustomization for the application
# Globals:
#   APP_NAME, FLUX_KS_NAME, FLUX_KS_NAMESPACE, TIMEOUT
# Arguments:
#   None
# Returns:
#   0 if found, 1 if not found
#######################################
detect_flux_kustomization() {
  log_debug "Searching for Flux Kustomization for ${APP_NAME}"

  # Try to find Kustomization by name match
  local ks_name
  ks_name=$(timeout "${TIMEOUT}" kubectl get kustomization -n "${FLUX_KS_NAMESPACE}" -o json 2>/dev/null | \
    jq -r --arg app "${APP_NAME}" '.items[] | select(.metadata.name | contains($app)) | .metadata.name' 2>/dev/null | head -1)

  if [[ -n "${ks_name}" ]]; then
    FLUX_KS_NAME="${ks_name}"
    log_debug "Found Kustomization: ${FLUX_KS_NAME}"
    return 0
  fi

  # Try to find by path in spec
  ks_name=$(timeout "${TIMEOUT}" kubectl get kustomization -n "${FLUX_KS_NAMESPACE}" -o json 2>/dev/null | \
    jq -r --arg app "${APP_NAME}" '.items[] | select(.spec.path | contains($app)) | .metadata.name' 2>/dev/null | head -1)

  if [[ -n "${ks_name}" ]]; then
    FLUX_KS_NAME="${ks_name}"
    log_debug "Found Kustomization by path: ${FLUX_KS_NAME}"
    return 0
  fi

  log_debug "No Flux Kustomization found for ${APP_NAME}"
  return 1
}

#######################################
# Offer post-cleanup reconcile option
# Globals:
#   APP_NAME, FLUX_KS_NAME, FLUX_KS_NAMESPACE, AUTO_YES, DRY_RUN, TIMEOUT, SUSPENDED_KUSTOMIZATIONS
# Arguments:
#   None
# Returns:
#   0 always (reconcile is optional)
#######################################
offer_reconcile() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  printf "\n"
  printf "%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n" "${COLOR_CYAN}" "${COLOR_RESET}"
  printf "%b║  POST-CLEANUP OPTIONS                                                         ║%b\n" "${COLOR_CYAN}" "${COLOR_RESET}"
  printf "%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n" "${COLOR_CYAN}" "${COLOR_RESET}"
  printf "\n"

  # Show suspended Kustomizations status
  if [[ ${#SUSPENDED_KUSTOMIZATIONS[@]} -gt 0 ]]; then
    printf "%b⚠ Flux Kustomizations are currently SUSPENDED:%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
      local ns="${entry%%:*}"
      local name="${entry#*:}"
      printf "  • %s (namespace: %s)\n" "${name}" "${ns}"
    done
    printf "\n"
  fi

  # Check if we have flux CLI available
  if ! command -v flux &>/dev/null; then
    log_warn "Flux CLI not available - manual commands shown below"
    printf "\n"
    printf "%bTo resume Flux (for apps removed from Git):%b\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
      local ns="${entry%%:*}"
      local name="${entry#*:}"
      printf "  kubectl patch kustomization %s -n %s --type=merge -p '{\"spec\":{\"suspend\":false}}'\n" "${name}" "${ns}"
    done
    printf "\n"
    printf "%bTo reconcile from source (redeploy):%b\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    if [[ -n "${FLUX_KS_NAME}" ]]; then
      printf "  # First resume, then trigger reconcile:\n"
      printf "  kubectl patch kustomization %s -n %s --type=merge -p '{\"spec\":{\"suspend\":false}}'\n" "${FLUX_KS_NAME}" "${FLUX_KS_NAMESPACE}"
      printf "  kubectl annotate kustomization %s -n %s \\\\\n" "${FLUX_KS_NAME}" "${FLUX_KS_NAMESPACE}"
      printf "    reconcile.fluxcd.io/requestedAt=\"\$(date +%%s)\" --overwrite\n"
    fi
    printf "\n"
    return 0
  fi

  printf "Cleanup is complete. What would you like to do next?\n\n"
  printf "  ${COLOR_GREEN}1)${COLOR_RESET} Resume Flux + Reconcile (redeploy application)\n"
  printf "     Use this to redeploy if the app still exists in Git\n\n"
  printf "  ${COLOR_YELLOW}2)${COLOR_RESET} Resume Flux only (no reconcile)\n"
  printf "     Use this if app was removed from Git - just re-enable Flux\n\n"
  printf "  ${COLOR_BLUE}3)${COLOR_RESET} Verify cleanup (keep Flux suspended)\n"
  printf "     Check for lingering resources without re-enabling Flux\n\n"
  printf "  ${COLOR_CYAN}4)${COLOR_RESET} Exit (keep Flux suspended)\n"
  printf "     Manual intervention required to resume Flux later\n\n"

  printf "%bSelect option [1-4]:%b " "${COLOR_BOLD}" "${COLOR_RESET}" >&2
  local choice
  read -r choice

  case "${choice}" in
    1)
      printf "\n"
      log_info "Resuming Flux and initiating reconcile..."

      # First resume all Kustomizations
      resume_flux_kustomizations

      # Then trigger reconciliation
      if [[ -n "${FLUX_KS_NAME}" ]]; then
        printf "\n"
        log_info "Reconciling Kustomization: ${FLUX_KS_NAME}"
        if flux reconcile kustomization "${FLUX_KS_NAME}" -n "${FLUX_KS_NAMESPACE}" --with-source --timeout="${TIMEOUT}s"; then
          log_success "Reconciliation triggered for ${FLUX_KS_NAME}"
          printf "\n"
          log_info "Checking reconciliation status..."
          sleep 3
          flux get kustomization "${FLUX_KS_NAME}" -n "${FLUX_KS_NAMESPACE}"
        else
          log_warn "Reconciliation may have failed - check Flux status"
          printf "\n"
          printf "%bManual check command:%b\n" "${COLOR_BOLD}" "${COLOR_RESET}"
          printf "  flux get kustomization %s -n %s\n" "${FLUX_KS_NAME}" "${FLUX_KS_NAMESPACE}"
        fi
      else
        log_warn "No specific Kustomization found for ${APP_NAME}"
        printf "\n"
        printf "%bWould you like to reconcile the root flux-system Kustomization? [y/N]:%b " \
          "${COLOR_BOLD}" "${COLOR_RESET}" >&2
        local confirm
        read -r confirm

        if [[ "${confirm}" =~ ^[Yy] ]]; then
          log_info "Reconciling flux-system..."
          if flux reconcile kustomization flux-system -n flux-system --with-source --timeout="${TIMEOUT}s"; then
            log_success "Root reconciliation triggered"
          else
            log_warn "Reconciliation may have failed"
          fi
        fi
      fi
      ;;

    2)
      printf "\n"
      log_info "Resuming Flux Kustomizations (no reconcile)..."
      resume_flux_kustomizations
      printf "\n"
      log_success "Flux will reconcile on its normal schedule"
      log_info "To force immediate reconcile later:"
      if [[ -n "${FLUX_KS_NAME}" ]]; then
        printf "  flux reconcile ks %s -n %s --with-source\n" "${FLUX_KS_NAME}" "${FLUX_KS_NAMESPACE}"
      else
        printf "  flux reconcile ks <ks-name> -n <namespace> --with-source\n"
      fi
      ;;

    3)
      printf "\n"
      log_info "Verifying cleanup - searching for any remaining resources..."
      log_warn "Note: Flux Kustomizations remain SUSPENDED"

      # Re-run discovery to check for any remaining resources
      local remaining
      remaining=$(timeout "${TIMEOUT}" kubectl get all,configmap,secret,pvc -A -o json 2>/dev/null | \
        jq -r --arg app "${APP_NAME}" \
        '.items[] | select(.metadata.name | contains($app)) | "\(.kind)/\(.metadata.name) in \(.metadata.namespace)"' 2>/dev/null)

      if [[ -z "${remaining}" ]]; then
        log_success "No remaining resources found for ${APP_NAME}"
        log_success "Cleanup verified complete"
        printf "\n"
        printf "%bRemember to resume Flux when ready:%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
          local ns="${entry%%:*}"
          local name="${entry#*:}"
          printf "  flux resume ks %s -n %s\n" "${name}" "${ns}"
        done
      else
        log_warn "Found remaining resources:"
        printf "%s\n" "${remaining}"
        printf "\n"
        log_warn "These may be in terminating state or managed by other Kustomizations"
      fi
      ;;

    4|"")
      log_info "Exiting without further action"
      if [[ ${#SUSPENDED_KUSTOMIZATIONS[@]} -gt 0 ]]; then
        printf "\n"
        printf "%b⚠ IMPORTANT: Flux Kustomizations remain SUSPENDED%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        printf "%bTo resume manually:%b\n" "${COLOR_BOLD}" "${COLOR_RESET}"
        for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
          local ns="${entry%%:*}"
          local name="${entry#*:}"
          printf "  flux resume ks %s -n %s\n" "${name}" "${ns}"
        done
      fi
      ;;

    *)
      log_warn "Invalid option, exiting without further action"
      if [[ ${#SUSPENDED_KUSTOMIZATIONS[@]} -gt 0 ]]; then
        printf "\n"
        printf "%b⚠ Flux Kustomizations remain SUSPENDED%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
      fi
      ;;
  esac

  return 0
}

#######################################
# Main function
# Globals:
#   All script globals
# Arguments:
#   $@ - Command line arguments
# Returns:
#   Exit code based on operation result
#######################################
main() {
  local exit_code=0

  # Parse command line arguments
  if ! parse_arguments "$@"; then
    return 2
  fi

  # Validate dependencies
  if ! validate_dependencies; then
    return 2
  fi

  # Get application name (interactive if not provided)
  if ! prompt_app_name; then
    return 2
  fi

  log_info "Starting cleanup for application: ${COLOR_BOLD}${APP_NAME}${COLOR_RESET}"

  # GUARDRAILS: Validate against protected namespaces and critical components
  if ! validate_guardrails; then
    return 2
  fi

  # Discover Flux Kustomizations (searches both flux-system AND app namespaces)
  discover_flux_kustomizations || true

  # Discover secondary namespaces (e.g., obot-mcp for obot)
  discover_secondary_namespaces || true

  # Discover resources
  if ! discover_resources; then
    log_info "No cleanup necessary"
    return 0
  fi

  # Display discovered resources
  display_resources

  # Generate delete commands
  generate_delete_commands

  # Confirm deletion
  if ! confirm_deletion; then
    return 2
  fi

  # CRITICAL: Suspend Flux BEFORE deletion to prevent race condition
  # Without this, Flux immediately recreates deleted resources
  suspend_flux_kustomizations

  # Execute deletion
  if ! delete_resources; then
    exit_code=1
  fi

  # Verify deletion
  if ! verify_deletion; then
    exit_code=1
  fi

  # Clean up secondary namespaces (e.g., obot-mcp)
  cleanup_secondary_namespaces

  if [[ ${exit_code} -eq 0 ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "Dry-run completed successfully"
    else
      log_success "Cleanup completed successfully for application: ${COLOR_BOLD}${APP_NAME}${COLOR_RESET}"

      # Offer post-cleanup options (reconcile, resume, or verify)
      # This is intentionally NOT automatic - user must choose
      if [[ "${AUTO_YES}" != "true" ]]; then
        offer_reconcile
      else
        printf "\n"
        log_info "Auto-yes mode: Flux Kustomizations remain SUSPENDED"
        log_info "To resume and reconcile manually:"
        for entry in "${SUSPENDED_KUSTOMIZATIONS[@]}"; do
          local ns="${entry%%:*}"
          local name="${entry#*:}"
          printf "  flux resume ks %s -n %s\n" "${name}" "${ns}"
        done
        log_info "Then reconcile: flux reconcile kustomization <ks-name> -n <namespace> --with-source"
      fi
    fi
  else
    log_warn "Cleanup completed with some failures"
    printf "\n"
    log_info "Flux Kustomizations remain SUSPENDED to prevent recreation"
    log_info "You may want to investigate remaining resources before resuming"
  fi

  return ${exit_code}
}

# Execute main function with all arguments
main "$@"
