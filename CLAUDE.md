# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

GitOps-driven Kubernetes cluster template on Talos Linux with Flux CD. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI (kube-proxy replacement, BGP Control Plane v2 optional), Gateway API + Envoy, SOPS/Age encryption, Cloudflare (DNS + Tunnel), UniFi DNS (optional internal), makejinja templating, OpenTofu v1.11+ (IaC)

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

**Deployment:** 7-stage workflow (Hardware → Machine Prep → Workstation → Cloudflare → Infrastructure → Cluster Config → Bootstrap)

**Control Plane:** Does NOT run workloads by default (`allowSchedulingOnControlPlanes: false`); dedicated workers recommended

## Quick Context Loading

Run `/expert-mode` for efficient project context loading (94% token reduction).

Alternatively, read `PROJECT_INDEX.md` first - it provides complete project understanding in ~3K tokens.

## Common Commands (go-task)

This project uses **go-task** as the primary task runner. All commands via `task <name>`.

### Quick Reference
```bash
task --list              # List all available tasks
task init                # Initialize config files from samples
task configure           # Render templates, validate, encrypt secrets
task reconcile           # Force Flux to sync from Git
```

### Bootstrap (New Cluster)
```bash
task bootstrap:talos     # Install Talos on nodes
task bootstrap:apps      # Deploy Cilium, CoreDNS, Spegel, Flux
```

### Talos Operations
```bash
task talos:generate-config        # Regenerate Talos configs
task talos:apply-node IP=<ip>     # Apply config to running node
task talos:upgrade-node IP=<ip>   # Upgrade Talos version
task talos:upgrade-k8s            # Upgrade Kubernetes version
task talos:reset                  # Reset cluster to maintenance
```

### Infrastructure (OpenTofu)
```bash
task infra:init              # Initialize OpenTofu with R2 backend
task infra:plan              # Create execution plan
task infra:apply             # Apply saved plan
task infra:apply-auto        # Apply with auto-approve
task infra:destroy           # Destroy managed resources
task infra:secrets-edit      # Edit secrets (rotation only)
task infra:validate          # Validate configuration
task infra:fmt               # Format configuration
```

### Template Management
```bash
task template:debug      # Gather cluster resource states
task template:tidy       # Archive template files post-setup
task template:reset      # Remove all generated files
```

### Verification
```bash
kubectl get nodes -o wide
kubectl get pods -A
flux check
flux get ks -A
flux get hr -A
cilium status
```

## Architecture

### Directory Layout
- `templates/config/kubernetes/apps/<namespace>/<app>/` - Jinja2 templates for K8s manifests
- `templates/config/talos/` - Talos configuration templates
- `templates/config/bootstrap/` - Bootstrap resource templates
- `templates/config/infrastructure/` - OpenTofu/IaC templates
- `kubernetes/` - GENERATED K8s manifests (after `task configure`)
- `talos/` - GENERATED Talos configs (after `task configure`)
- `infrastructure/` - GENERATED OpenTofu configs (after `task configure`)
- `docs/` - Comprehensive documentation

### Template Flow
```
cluster.yaml + nodes.yaml → makejinja → kubernetes/ + talos/ + bootstrap/ + infrastructure/
                                            ↓
                              task bootstrap:talos → Nodes ready
                                            ↓
                              task bootstrap:apps → Flux syncs Git
```

### GitOps Flow (After Bootstrap)
```
Git Repo → GitRepository → Kustomizations → HelmReleases
                              ↓
                    ExternalSecrets (future) → Native Secrets
```

### Key Patterns

**App Template Structure:**
```
templates/config/kubernetes/apps/<namespace>/<app>/
├── ks.yaml.j2              # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2
    ├── ocirepository.yaml.j2
    └── secret.sops.yaml.j2  # (if secrets needed)
```

**Template Delimiters (makejinja):**
- Block: `#% ... %#` (e.g., `#% if condition %#`)
- Variable: `#{ ... }#` (e.g., `#{ cluster_api_addr }#`)
- Comment: `#| ... #|` ⚠️ **SYMMETRICAL** - both ends use `#|`, NOT `|#`

> **CRITICAL**: Comments use the SAME delimiter on both ends (`#|`). Do NOT extrapolate from the block/variable mirror pattern. The correct comment is `#| comment here #|`, **never** `#| comment here |#`.

**SOPS Encryption:** All `*.sops.yaml` files encrypted with Age.

### Networks (Configured via cluster.yaml)
- Node Network: `node_cidr` (e.g., 192.168.1.0/24)
- Pods: `cluster_pod_cidr` (default: 10.42.0.0/16)
- Services: `cluster_svc_cidr` (default: 10.43.0.0/16)
- LoadBalancers: `cluster_gateway_addr`, `cloudflare_gateway_addr`
- Internal DNS: `cluster_dns_gateway_addr` (only when NOT using UniFi DNS)

## Key Files

| Purpose | Path |
| ------- | ---- |
| **Task runner** | `Taskfile.yaml`, `.taskfiles/` |
| **Dev tools** | `.mise.toml` (managed by mise) |
| **AI assistants** | `.claude/` (agents, commands), `docs/ai-context/` |
| **Cluster config** | `cluster.yaml` (network, cloudflare, repo) |
| **Node config** | `nodes.yaml` (name, IP, disk, MAC, schematic) |
| **Infrastructure** | `infrastructure/` (OpenTofu configs, R2 backend) |
| **Template engine** | `makejinja.toml` |
| **SOPS rules** | `.sops.yaml` (generated) |
| Age encryption key | `age.key` (gitignored, NEVER commit) |
| **Detailed docs** | `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`, `docs/OPERATIONS.md` |

## Conventions

### Configuration
- Edit `cluster.yaml` and `nodes.yaml` for cluster settings
- NEVER edit files in `kubernetes/`, `talos/`, `bootstrap/`, or `infrastructure/` directly - they are generated
- After changes: `task configure` to regenerate

### Kubernetes/GitOps
- HelmReleases use OCI repositories for charts
- Secrets via SOPS/Age encryption
- All apps follow the standard template structure

### Template Variables
Required variables in `cluster.yaml`:
- `node_cidr`, `cluster_api_addr`, `cluster_gateway_addr`
- `cloudflare_domain`, `cloudflare_token`, `cloudflare_gateway_addr`
- `repository_name`

Optional UniFi DNS (replaces k8s_gateway - makes `cluster_dns_gateway_addr` unnecessary):
- `unifi_host`, `unifi_api_key` (requires UniFi Network v9.0.0+)
- When configured, `k8s_gateway_enabled=false` and `unifi_dns_enabled=true` (derived in plugin.py)
- See `docs/research/archive/implemented/external-dns-unifi-integration.md` for setup guide

Optional Cilium BGP Control Plane v2 (for multi-VLAN routing):
- `cilium_bgp_router_addr`, `cilium_bgp_router_asn`, `cilium_bgp_node_asn` (all three required)
- Optional: `cilium_lb_pool_cidr`, `cilium_bgp_hold_time`, `cilium_bgp_keepalive_time`, `cilium_bgp_graceful_restart`
- See `docs/guides/bgp-unifi-cilium-implementation.md` for setup guide

Optional Observability Stack (metrics, logs, traces):
- `monitoring_enabled` - Enable VictoriaMetrics + Grafana + AlertManager
- `hubble_enabled` - Enable Cilium Hubble network observability
- `loki_enabled` - Enable log aggregation with Loki + Alloy
- `tracing_enabled` - Enable distributed tracing with Tempo
- See `docs/guides/observability-stack-implementation.md` for setup guide

Optional CiliumNetworkPolicies (zero-trust networking):
- `network_policies_enabled` - Enable namespace-scoped network policies
- `network_policies_mode` - "audit" (observe via Hubble) or "enforce" (active blocking)
- See `docs/research/cilium-network-policies-jan-2026.md` for policy designs

Optional Talos Backup (etcd snapshots to S3):
- `backup_s3_endpoint`, `backup_s3_bucket` (both required to enable)
- When configured, `talos_backup_enabled=true` (derived in plugin.py)
- See `docs/CONFIGURATION.md` for all backup settings

Optional OIDC/JWT Authentication (Envoy Gateway SecurityPolicy):
- `oidc_issuer_url`, `oidc_jwks_uri` (both required to enable)
- When configured, `oidc_enabled=true` (derived in plugin.py)
- Creates SecurityPolicy targeting HTTPRoutes with label `security: jwt-protected`

Optional Proxmox Infrastructure (VM provisioning via OpenTofu):
- `proxmox_api_url`, `proxmox_node` (both required to enable)
- When configured, `infrastructure_enabled=true` and OpenTofu configs are generated
- Role-based VM defaults with 3-tier fallback chain:
  - `proxmox_vm_controller_defaults` - Controller nodes (4 cores, 8GB, 64GB disk)
  - `proxmox_vm_worker_defaults` - Worker nodes (8 cores, 16GB, 256GB disk)
  - `proxmox_vm_defaults` - Global fallback
- Per-node overrides via `vm_cores`, `vm_memory`, `vm_disk_size` in nodes.yaml
- Fallback chain: per-node → role-defaults → global-defaults
- See `docs/CONFIGURATION.md` for complete Proxmox settings

Derived Variables (computed in `templates/scripts/plugin.py`):
- `cilium_bgp_enabled` - true when all 3 BGP keys set
- `unifi_dns_enabled` - true when unifi_host + unifi_api_key set
- `k8s_gateway_enabled` - true when unifi_dns_enabled is false (mutually exclusive)
- `talos_backup_enabled` - true when backup_s3_endpoint + backup_s3_bucket set
- `oidc_enabled` - true when oidc_issuer_url + oidc_jwks_uri set
- `spegel_enabled` - true when >1 node (can be overridden by user)
- `infrastructure_enabled` - true when proxmox_api_url + proxmox_node set
- `proxmox_vm_controller_defaults` - Merged controller VM settings
- `proxmox_vm_worker_defaults` - Merged worker VM settings

See `docs/CONFIGURATION.md` for complete schema reference.

## AI Assistants

### Slash Commands

| Command | Purpose |
| ------- | ------- |
| `/expert-mode` | Load project context efficiently |
| `/flux-status` | Check Flux GitOps health |
| `/flux-reconcile` | Force reconcile Flux resources |
| `/talos-status` | Check Talos node health |
| `/infra-status` | Check OpenTofu state/resources |
| `/deploy-check` | Verify deployment status |
| `/debug-network` | Network diagnostics |

### Agents

| Agent | Use For |
| ----- | ------- |
| `talos-expert` | Talos node operations, upgrades, patches |
| `flux-expert` | Flux troubleshooting, reconciliation issues |
| `template-expert` | makejinja templates, Jinja2 patterns |
| `network-debugger` | Cilium/Gateway debugging, connectivity |
| `infra-expert` | OpenTofu/Proxmox IaC operations |

### Domain Documentation
Deep context in `docs/ai-context/`:
- `flux-gitops.md` - Flux architecture & patterns
- `talos-operations.md` - Talos workflows
- `cilium-networking.md` - Cilium CNI patterns
- `template-system.md` - makejinja templating
- `infrastructure-opentofu.md` - OpenTofu IaC & R2 backend

## Troubleshooting Quick Reference

| Issue | Command |
| ----- | ------- |
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| CNI issues | `cilium status`, `cilium connectivity test` |
| BGP issues | `cilium bgp peers`, `kubectl get ciliumbgpclusterconfig -A` |
| Certificate issues | `kubectl get certificates -A` |
| OpenTofu state lock | `task infra:force-unlock LOCK_ID=xxx` |
| OpenTofu auth issues | Check credentials in `cluster.yaml`, run `task configure` |
| Monitoring not working | `flux get hr -n monitoring`, `kubectl -n monitoring get pods` |
| Hubble not visible | `hubble status`, `kubectl -n kube-system port-forward svc/hubble-relay 4245:80` |
| Network policy blocking | `hubble observe --verdict DROPPED`, `kubectl get cnp -A` |

For comprehensive troubleshooting with diagnostic flowcharts and decision trees, see `docs/TROUBLESHOOTING.md`.

For complete CLI command reference, see `docs/CLI_REFERENCE.md`.
