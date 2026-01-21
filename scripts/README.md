# Scripts Directory

This directory contains utility scripts for cluster operations and development workflows.

## Available Scripts

### cleanup-app.sh

Production-quality Bash script for cleaning up Kubernetes application resources during development.

**Purpose:**
Time-saving tool for removing all resources related to a failed or unwanted deployment. Automatically discovers and removes Flux resources, workloads, networking, storage, and custom resources.

**Key Features:**

- ✅ Defensive bash scripting with comprehensive error handling
- 🔍 Automatic resource discovery across all namespaces
- 🎨 Color-coded output for readability
- 🔒 Safe deletion with confirmation prompts
- 🚀 Dry-run mode for preview without changes
- ⚡ Automatic mode for CI/CD integration
- ⏱️ Configurable timeouts for kubectl operations
- 📊 Detailed verification and status reporting
- 🛡️ **Guardrails** - Blocks deletion of critical cluster infrastructure
- 🔄 **Post-cleanup options** - Reconcile from source or verify cleanup

**Quick Start:**

```bash
# Interactive mode with preview (safest)
./scripts/cleanup-app.sh --dry-run obot

# Interactive mode with confirmation
./scripts/cleanup-app.sh obot

# Automatic mode (no prompts)
./scripts/cleanup-app.sh --yes obot

# Limit to specific namespace
./scripts/cleanup-app.sh --namespace ai-services obot

# Show help
./scripts/cleanup-app.sh --help
```

**Resource Types Discovered:**

| Category | Resources |
| ---------- | ----------- |
| **Flux Resources** | Kustomizations, HelmReleases, GitRepositories, OCIRepositories, HelmRepositories |
| **Workloads** | Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, ReplicaSets |
| **Networking** | Services, Ingresses, HTTPRoutes, GRPCRoutes, CiliumNetworkPolicies, NetworkPolicies |
| **Configuration** | ConfigMaps, Secrets |
| **Storage** | PersistentVolumeClaims, PersistentVolumes |
| **Database** | CNPG Clusters, Backups, ScheduledBackups, Poolers |
| **Custom Resources** | ExternalSecrets, ServiceMonitors |

**Exit Codes:**

- `0` - Success (all resources deleted)
- `1` - Partial failure (some resources failed to delete)
- `2` - Error (validation failed, missing dependencies, or user cancelled)

**Requirements:**

- kubectl (with cluster connectivity)
- jq (for JSON processing)
- Bash 4.4+ (for modern error handling)

**Safety Features:**

- Proper quoting of all variables
- Timeout handling for all kubectl commands
- Temporary file cleanup with EXIT trap
- Input validation and sanitization
- Detailed logging with timestamps
- Verification step after deletion

**Guardrails (v1.1.0+):**

The script includes guardrails to prevent catastrophic cluster damage:

| Level | Components | Behavior |
| ----- | ---------- | -------- |
| 🛑 **BLOCKED** | Protected namespaces: `kube-system`, `flux-system`, `cert-manager`, `cnpg-system`, `envoy-gateway-system` | Cleanup completely blocked, no override |
| 🛑 **BLOCKED** | Critical apps: Flux, Cilium, CoreDNS, cert-manager, Envoy Gateway, Spegel, Metrics Server, Cloud Controllers, CSI drivers, all Operators | Cleanup completely blocked, no override |
| ⚠️ **WARNING** | Sensitive apps: Keycloak, PostgreSQL/CNPG, Dragonfly/Redis, RustFS/MinIO | Requires typing "I UNDERSTAND THE RISKS", `--yes` flag disabled |

**Post-Cleanup Options (v1.1.0+):**

After successful cleanup, the script offers three non-automatic options:

1. **Reconcile from source** - Triggers Flux reconciliation to redeploy if app still exists in Git
2. **Verify cleanup only** - Re-scans cluster to confirm no lingering artifacts
3. **Exit** - No further action

This is intentionally NOT automatic - useful for:

- Cleaning up apps removed from Git (verify no lingering artifacts)
- Fresh redeploy of failed deployments
- Controlled recovery after debugging

**Examples:**

```bash
# Example 1: Preview what would be deleted for 'obot' app
./scripts/cleanup-app.sh --dry-run obot

# Example 2: Clean up all 'litellm' resources with confirmation
./scripts/cleanup-app.sh litellm

# Example 3: Automatic cleanup in CI/CD pipeline
./scripts/cleanup-app.sh --yes --namespace ai-services langfuse

# Example 4: Debug mode with tracing
./scripts/cleanup-app.sh --trace --dry-run obot

# Example 5: Interactive mode (prompts for app name)
./scripts/cleanup-app.sh
```

**Output Example:**

```
[2026-01-11 10:30:15] INFO: Starting cleanup for application: obot
[2026-01-11 10:30:15] INFO: Discovering resources for application: obot
[2026-01-11 10:30:18] SUCCESS: Discovered 12 resources

Discovered Resources:
CATEGORY                  KIND                           NAMESPACE                      NAME
==================================================================================================================================
Custom Resources          ExternalSecret                 ai-services                    obot-keycloak-secret
Database                  Cluster                        ai-services                    obot-postgres
Flux Resources            HelmRelease                    ai-services                    obot
Flux Resources            OCIRepository                  ai-services                    obot
Networking                CiliumNetworkPolicy            ai-services                    obot-egress
Networking                HTTPRoute                      ai-services                    obot
Networking                Service                        ai-services                    obot
Workloads                 Deployment                     ai-services                    obot

Generated Delete Commands:

kubectl delete externalsecrets.external-secrets.io --namespace=ai-services obot-keycloak-secret
kubectl delete clusters.postgresql.cnpg.io --namespace=ai-services obot-postgres
kubectl delete helmreleases.helm.toolkit.fluxcd.io --namespace=ai-services obot
kubectl delete ocirepositories.source.toolkit.fluxcd.io --namespace=ai-services obot
kubectl delete ciliumnetworkpolicies.cilium.io --namespace=ai-services obot-egress
kubectl delete httproutes.gateway.networking.k8s.io --namespace=ai-services obot
kubectl delete services --namespace=ai-services obot
kubectl delete deployments --namespace=ai-services obot

WARNING: This will delete all resources shown above for application: obot
This action cannot be undone!

Type 'yes' to confirm deletion: yes
[2026-01-11 10:30:25] INFO: Auto-yes mode enabled, proceeding with deletion
[2026-01-11 10:30:25] INFO: Starting resource deletion...
✓ Deleted ExternalSecret/obot-keycloak-secret in ai-services
✓ Deleted Cluster/obot-postgres in ai-services
✓ Deleted HelmRelease/obot in ai-services
...
[2026-01-11 10:30:35] SUCCESS: Deleted 12/12 resources
[2026-01-11 10:30:37] SUCCESS: All resources successfully deleted
[2026-01-11 10:30:37] SUCCESS: Cleanup completed successfully for application: obot

╔══════════════════════════════════════════════════════════════════════════════╗
║  POST-CLEANUP OPTIONS                                                         ║
╚══════════════════════════════════════════════════════════════════════════════╝

Cleanup is complete. What would you like to do next?

  1) Reconcile from source (redeploy application)
     Use this to redeploy if the app still exists in Git

  2) Verify cleanup only (no reconcile)
     Use this if the app was removed from Git and you want to ensure cleanup

  3) Exit without further action

Select option [1-3]: 2

[2026-01-11 10:30:45] INFO: Verifying cleanup - searching for any remaining resources...
[2026-01-11 10:30:47] SUCCESS: No remaining resources found for obot
[2026-01-11 10:30:47] SUCCESS: Cleanup verified complete
```

**Integration with Task Runner:**

You can integrate this script into your Taskfile.yaml for convenience:

```yaml
tasks:
  cleanup:app:
    desc: Clean up Kubernetes application resources
    summary: |
      Discovers and removes all resources for a given application.
      Uses the cleanup-app.sh script with safety features.
    cmd: ./scripts/cleanup-app.sh {{.CLI_ARGS}}
    preconditions:
      - sh: test -f ./scripts/cleanup-app.sh
        msg: cleanup-app.sh script not found

  cleanup:app:dry-run:
    desc: Preview cleanup without deleting (dry-run mode)
    cmd: ./scripts/cleanup-app.sh --dry-run {{.CLI_ARGS}}
```

Then use with:

```bash
task cleanup:app -- obot
task cleanup:app:dry-run -- litellm
```

**Troubleshooting:**

| Issue | Solution |
| ------- | ---------- |
| "Cannot connect to Kubernetes cluster" | Verify kubeconfig: `kubectl cluster-info` |
| "Missing required dependencies: jq" | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| Resources remain after deletion | Some resources may have finalizers. Check with: `kubectl get <resource> -o yaml` and remove finalizers manually |
| Permission denied | Make script executable: `chmod +x scripts/cleanup-app.sh` |
| Timeout errors | Increase timeout: `--timeout 60` |

**Best Practices:**

1. **Always dry-run first**: Use `--dry-run` to preview changes before deletion
2. **Namespace scoping**: Use `--namespace` to limit scope when possible
3. **Verify connectivity**: Test `kubectl cluster-info` before running
4. **Check Flux state**: Run `flux get ks -A` to see if resources will be recreated
5. **Suspend Flux reconciliation**: If needed, suspend Kustomization first:

   ```bash
   flux suspend ks <app-name> -n flux-system
   ```

**Common Workflows:**

```bash
# Workflow 1: Clean up failed deployment
./scripts/cleanup-app.sh --dry-run myapp    # Preview
./scripts/cleanup-app.sh myapp              # Execute with confirmation

# Workflow 2: Remove app and prevent recreation
flux suspend ks myapp -n flux-system        # Suspend Flux reconciliation
./scripts/cleanup-app.sh --yes myapp        # Clean up resources
# Remove from Git repository
git rm templates/config/kubernetes/apps/*/myapp/ -r
task configure                              # Regenerate configs

# Workflow 3: CI/CD cleanup on branch deletion
./scripts/cleanup-app.sh --yes --namespace preview-${BRANCH_NAME} ${APP_NAME}
```

## Development Guidelines

When adding new scripts to this directory:

1. **Use defensive programming**: `set -Eeuo pipefail` at minimum
2. **Implement proper error handling**: trap cleanup functions
3. **Quote all variables**: prevent word splitting issues
4. **Provide help text**: implement `--help` flag
5. **Support dry-run mode**: allow preview without changes
6. **Add to this README**: document usage and examples
7. **Make executable**: `chmod +x script.sh`
8. **Use shellcheck**: validate with `shellcheck script.sh`
9. **Format with shfmt**: `shfmt -w -i 2 -ci script.sh`

## Testing Scripts

Before committing new scripts:

```bash
# Static analysis
shellcheck scripts/*.sh

# Format check
shfmt -d -i 2 -ci scripts/*.sh

# Manual testing
./scripts/cleanup-app.sh --dry-run test-app
```
