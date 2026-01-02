# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

GitOps-driven Kubernetes cluster template on Talos Linux with Flux CD. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI (kube-proxy replacement), Gateway API + Envoy, SOPS/Age encryption, Cloudflare (DNS + Tunnel), makejinja templating

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

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
- `kubernetes/` - GENERATED K8s manifests (after `task configure`)
- `talos/` - GENERATED Talos configs (after `task configure`)
- `docs/` - Comprehensive documentation

### Template Flow
```
cluster.yaml + nodes.yaml → makejinja → kubernetes/ + talos/ + bootstrap/
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
- Comment: `#| ... #|`

**SOPS Encryption:** All `*.sops.yaml` files encrypted with Age.

### Networks (Configured via cluster.yaml)
- Node Network: `node_cidr` (e.g., 192.168.1.0/24)
- Pods: `cluster_pod_cidr` (default: 10.42.0.0/16)
- Services: `cluster_svc_cidr` (default: 10.43.0.0/16)
- LoadBalancers: `cluster_gateway_addr`, `cloudflare_gateway_addr`, `cluster_dns_gateway_addr`

## Key Files

| Purpose | Path |
| ------- | ---- |
| **Task runner** | `Taskfile.yaml`, `.taskfiles/` |
| **Dev tools** | `.mise.toml` (managed by mise) |
| **AI assistants** | `.claude/` (agents, commands), `docs/ai-context/` |
| **Cluster config** | `cluster.yaml` (network, cloudflare, repo) |
| **Node config** | `nodes.yaml` (name, IP, disk, MAC, schematic) |
| **Template engine** | `makejinja.toml` |
| **SOPS rules** | `.sops.yaml` (generated) |
| Age encryption key | `age.key` (gitignored, NEVER commit) |
| **Detailed docs** | `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`, `docs/OPERATIONS.md` |

## Conventions

### Configuration
- Edit `cluster.yaml` and `nodes.yaml` for cluster settings
- NEVER edit files in `kubernetes/`, `talos/`, or `bootstrap/` directly - they are generated
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

See `docs/CONFIGURATION.md` for complete schema reference.

## AI Assistants

### Slash Commands

| Command | Purpose |
| ------- | ------- |
| `/expert-mode` | Load project context efficiently |
| `/flux-status` | Check Flux GitOps health |
| `/flux-reconcile` | Force reconcile Flux resources |
| `/talos-status` | Check Talos node health |
| `/deploy-check` | Verify deployment status |
| `/debug-network` | Network diagnostics |

### Agents

| Agent | Use For |
| ----- | ------- |
| `talos-expert` | Talos node operations, upgrades, patches |
| `flux-expert` | Flux troubleshooting, reconciliation issues |
| `template-expert` | makejinja templates, Jinja2 patterns |
| `network-debugger` | Cilium/Gateway debugging, connectivity |

### Domain Documentation
Deep context in `docs/ai-context/`:
- `flux-gitops.md` - Flux architecture & patterns
- `talos-operations.md` - Talos workflows
- `cilium-networking.md` - Cilium CNI patterns
- `template-system.md` - makejinja templating

## Troubleshooting Quick Reference

| Issue | Command |
| ----- | ------- |
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| CNI issues | `cilium status`, `cilium connectivity test` |
| Certificate issues | `kubectl get certificates -A` |

For comprehensive troubleshooting with diagnostic flowcharts and decision trees, see `docs/TROUBLESHOOTING.md`.

For complete CLI command reference, see `docs/CLI_REFERENCE.md`.
