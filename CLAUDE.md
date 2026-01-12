# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

GitOps-driven Kubernetes cluster template on Talos Linux with Flux CD. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI (kube-proxy replacement, BGP optional), Gateway API + Envoy, SOPS/Age encryption, Cloudflare (DNS + Tunnel), UniFi DNS (optional), makejinja templating, OpenTofu v1.11+ (IaC)

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

**Deployment:** 7-stage workflow (Hardware → Machine Prep → Workstation → Cloudflare → Infrastructure → Cluster Config → Bootstrap)

**Control Plane:** Does NOT run workloads by default (`allowSchedulingOnControlPlanes: false`)

## Quick Context Loading

Run `/expert-mode` for efficient project context loading (94% token reduction).

Alternatively, read `PROJECT_INDEX.md` first - it provides complete project understanding in ~3K tokens.

## Common Commands (go-task)

This project uses **go-task** as the primary task runner. All commands via `task <name>`.

```bash
task --list              # List all available tasks
task init                # Initialize config files from samples
task configure -y        # Render templates, validate, encrypt secrets
task reconcile           # Force Flux to sync from Git

# Bootstrap
task bootstrap:talos     # Install Talos on nodes
task bootstrap:apps      # Deploy Cilium, CoreDNS, Spegel, Flux

# Talos
task talos:apply-node IP=<ip>     # Apply config to running node
task talos:upgrade-node IP=<ip>   # Upgrade Talos version
task talos:upgrade-k8s            # Upgrade Kubernetes version

# Infrastructure (OpenTofu)
task infra:plan          # Create execution plan
task infra:apply         # Apply saved plan
```

For complete CLI reference, see `docs/CLI_REFERENCE.md`.

## Architecture

### Directory Layout
- `templates/config/kubernetes/apps/<namespace>/<app>/` - Jinja2 templates for K8s manifests
- `templates/config/talos/` - Talos configuration templates
- `templates/config/bootstrap/` - Bootstrap resource templates
- `templates/config/infrastructure/` - OpenTofu/IaC templates
- `kubernetes/`, `talos/`, `infrastructure/` - GENERATED (after `task configure`)
- `docs/` - Comprehensive documentation

### Template Flow
```
cluster.yaml + nodes.yaml → makejinja → kubernetes/ + talos/ + bootstrap/ + infrastructure/
                                            ↓
                              task bootstrap:talos → Nodes ready
                                            ↓
                              task bootstrap:apps → Flux syncs Git
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
- Comment: `#| ... #|` - **SYMMETRICAL** - both ends use `#|`, NOT `|#`

> **CRITICAL**: Comments use the SAME delimiter on both ends (`#|`). The correct comment is `#| comment here #|`, **never** `#| comment here |#`.

**SOPS Encryption:** All `*.sops.yaml` files encrypted with Age.

### Networks (Configured via cluster.yaml)
- Node Network: `node_cidr` (e.g., 192.168.1.0/24)
- Pods: `cluster_pod_cidr` (default: 10.42.0.0/16)
- Services: `cluster_svc_cidr` (default: 10.43.0.0/16)
- LoadBalancers: `cluster_gateway_addr`, `cloudflare_gateway_addr`

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

### Configuration Variables

For complete configuration variable reference, see `docs/ai-context/configuration-variables.md`.

**Required variables:** `node_cidr`, `cluster_api_addr`, `cluster_gateway_addr`, `cloudflare_domain`, `cloudflare_token`, `cloudflare_gateway_addr`, `repository_name`

**Optional features:** UniFi DNS, Cilium BGP, Observability Stack, RustFS S3, Network Policies, Talos Backup, CloudNativePG, Keycloak OIDC, LiteLLM, Dragonfly, Langfuse, Obot, Proxmox Infrastructure

All derived variables are computed in `templates/scripts/plugin.py`. See `docs/CONFIGURATION.md` for complete schema reference.

## AI Assistants

### Slash Commands

| Command | Purpose |
| ------- | ------- |
| `/expert-mode` | Load project context efficiently |
| `/flux-status` | Check Flux GitOps health |
| `/talos-status` | Check Talos node health |
| `/infra-status` | Check OpenTofu state/resources |
| `/network-status` | Network diagnostics |

### Agents

| Agent | Use For |
| ----- | ------- |
| `talos-expert` | Talos node operations, upgrades, patches |
| `flux-expert` | Flux troubleshooting, reconciliation issues |
| `template-expert` | makejinja templates, Jinja2 patterns |
| `network-debugger` | Cilium/Gateway debugging, connectivity, OIDC |
| `infra-expert` | OpenTofu/Proxmox IaC operations |

### Domain Documentation

Deep context in `docs/ai-context/`:
- `flux-gitops.md` - Flux architecture & patterns
- `talos-operations.md` - Talos workflows
- `cilium-networking.md` - Cilium CNI patterns + OIDC integration
- `template-system.md` - makejinja templating
- `infrastructure-opentofu.md` - OpenTofu IaC & R2 backend
- `configuration-variables.md` - Complete cluster.yaml variable reference
- `litellm.md` - LiteLLM proxy configuration
- `langfuse.md` - Langfuse LLM observability
- `obot.md` - Obot MCP gateway + Keycloak SSO

## Troubleshooting Quick Reference

| Issue | Command |
| ----- | ------- |
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| CNI issues | `cilium status`, `cilium connectivity test` |
| Network policy blocking | `hubble observe --verdict DROPPED` |
| OIDC "OAuth flow failed" | Check envoy logs; verify SecurityPolicy has internal `tokenEndpoint` |
| OIDC API Server auth | Headlamp/kubectl OIDC: verify API Server has `--oidc-*` flags; check token aud claim matches |
| PostgreSQL issues | `kubectl cnpg status <cluster> -n <namespace>` |

For comprehensive troubleshooting with diagnostic flowcharts, see `docs/TROUBLESHOOTING.md`.

For complete CLI command reference, see `docs/CLI_REFERENCE.md`.

For network endpoints and policies inventory, see `docs/NETWORK-INVENTORY.md`.
