# Project Index: matherlynet-talos-cluster

> Generated: 2026-01-02
> Token-efficient repository index for AI-assisted development
> **AI Assistant Files:** `AGENTS.md`, `CLAUDE.md`, `PROJECT_INDEX.md`, `PROJECT_INDEX.json`

## Project Overview

A **Talos Linux Kubernetes cluster** template using **Flux GitOps** for home/bare-metal deployments. Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template).

**Core Stack:**
- **OS:** Talos Linux (immutable Kubernetes-native OS)
- **GitOps:** Flux CD with SOPS encryption
- **CNI:** Cilium (kube-proxy replacement, BGP Control Plane v2 optional)
- **Ingress:** Envoy Gateway (Gateway API)
- **DNS:** external-dns (Cloudflare external, UniFi internal) + k8s_gateway fallback
- **Tunnel:** Cloudflare cloudflared
- **Templating:** makejinja (Jinja2 templates)
- **IaC:** OpenTofu v1.11+ with Cloudflare R2 state backend

**Optional Features (Jan 2026):**
- Cilium BGP Control Plane v2 for multi-VLAN routing
- UniFi DNS Integration via external-dns webhook

**Deployment:** 7-stage workflow (Hardware → Machine Prep → Workstation → Cloudflare → Infrastructure → Cluster Config → Bootstrap)

**Control Plane:** Does NOT run workloads by default; dedicated workers recommended

## Project Structure

```
matherlynet-talos-cluster/
├── .github/              # GitHub Actions workflows
│   ├── workflows/        # CI/CD (flux-local, labeler, release)
│   └── tests/            # Test fixtures
├── .taskfiles/           # Task automation (go-task)
│   ├── bootstrap/        # Cluster bootstrap tasks
│   ├── infrastructure/   # OpenTofu/IaC tasks
│   ├── talos/            # Talos node management
│   └── template/         # Template rendering/validation
├── scripts/              # Shell scripts
│   ├── bootstrap-apps.sh # Main bootstrap orchestrator
│   └── lib/common.sh     # Shared shell utilities
├── templates/            # Jinja2 templates (100 files)
│   ├── config/           # Main configuration templates
│   │   ├── kubernetes/   # K8s manifests (apps, flux, components)
│   │   ├── talos/        # Talos config (talconfig, patches)
│   │   ├── bootstrap/    # Bootstrap resources (helmfile, secrets)
│   │   └── infrastructure/  # OpenTofu vars (terraform.tfvars)
│   └── overrides/        # Template overrides
├── cluster.sample.yaml   # Cluster configuration template
├── nodes.sample.yaml     # Node definitions template
├── Taskfile.yaml         # Main task definitions
└── makejinja.toml        # Template engine config
```

## Entry Points

| Entry Point | Path | Description |
| ------------- | ------ | ------------- |
| Main Tasks | `Taskfile.yaml` | Primary task runner |
| Bootstrap Talos | `.taskfiles/bootstrap/Taskfile.yaml` | `task bootstrap:talos` |
| Bootstrap Apps | `.taskfiles/bootstrap/Taskfile.yaml` | `task bootstrap:apps` |
| Template Init | `.taskfiles/template/Taskfile.yaml` | `task init` / `task configure` |
| Talos Mgmt | `.taskfiles/talos/Taskfile.yaml` | Node upgrades, config apply |
| Infrastructure | `.taskfiles/infrastructure/Taskfile.yaml` | OpenTofu IaC operations |

## Key Tasks (go-task)

| Task | Description |
| ------ | ------------- |
| `task init` | Generate config files from samples |
| `task configure` | Render templates + validate + encrypt secrets |
| `task bootstrap:talos` | Install Talos on nodes |
| `task bootstrap:apps` | Deploy Cilium, CoreDNS, Spegel, Flux |
| `task talos:apply-node IP=x` | Apply config to specific node |
| `task talos:upgrade-node IP=x` | Upgrade Talos version on node |
| `task talos:upgrade-k8s` | Upgrade Kubernetes version |
| `task talos:reset` | Reset cluster to maintenance mode |
| `task reconcile` | Force Flux Git sync |
| `task template:debug` | Gather cluster resources |
| `task template:tidy` | Archive template files post-setup |
| `task infra:init` | Initialize OpenTofu with R2 backend |
| `task infra:plan` | Create OpenTofu execution plan |
| `task infra:apply` | Apply OpenTofu changes |
| `task infra:secrets-edit` | Edit infrastructure secrets |

## Configuration Files

| File | Purpose |
| ------ | --------- |
| `cluster.yaml` | Main cluster config (network, cloudflare, repo) |
| `nodes.yaml` | Node definitions (name, IP, disk, MAC, schematic) |
| `makejinja.toml` | Template engine settings |
| `.mise.toml` | Dev environment tools (kubectl, flux, talosctl, opentofu, etc.) |
| `.sops.yaml` | SOPS encryption rules (generated) |
| `age.key` | SOPS Age encryption key (generated) |
| `infrastructure/secrets.sops.yaml` | Infrastructure secrets (R2/Proxmox credentials) |

## Included Applications

| Namespace | App | Purpose |
| ----------- | ----- | --------- |
| `kube-system` | cilium | CNI + LoadBalancer |
| `kube-system` | coredns | Cluster DNS |
| `kube-system` | kubelet-csr-approver | CSR automation |
| `kube-system` | spegel | P2P image distribution |
| `flux-system` | flux-operator | Flux deployment |
| `flux-system` | flux-instance | Flux config |
| `cert-manager` | cert-manager | TLS certificates |
| `network` | envoy-gateway | Ingress/Gateway API |
| `network` | cloudflare-dns | External DNS (Cloudflare) |
| `network` | unifi-dns | Internal DNS (UniFi webhook) - optional |
| `network` | cloudflare-tunnel | External access |
| `network` | k8s-gateway | Split DNS fallback (if no UniFi) |
| `default` | echo | Test application |
| `kube-system` | reloader | Secret/ConfigMap reload |
| `kube-system` | talos-ccm | Node lifecycle management |
| `kube-system` | talos-backup | Automated etcd backups (optional) |
| `system-upgrade` | tuppr | Automated Talos/K8s upgrades |

## Tool Dependencies

Managed via `mise` (.mise.toml):

| Tool | Version | Purpose |
| ------ | --------- | --------- |
| talosctl | 1.12.0 | Talos node management |
| talhelper | 3.0.44 | Talos config generator |
| kubectl | 1.35.0 | Kubernetes CLI |
| flux | 2.7.5 | Flux CD CLI |
| helm | 3.19.4 | Helm charts |
| helmfile | 1.2.3 | Helm release management |
| sops | 3.11.0 | Secret encryption |
| age | 1.3.1 | Encryption backend |
| cilium | 0.18.9 | Cilium CLI |
| cloudflared | 2025.11.1 | Cloudflare tunnel |
| kustomize | 5.8.0 | Kustomize |
| kubeconform | 0.7.0 | Manifest validation |
| cue | 0.15.3 | Schema validation |
| yq/jq | latest | YAML/JSON processing |
| opentofu | 1.11.2 | Infrastructure as Code |

## GitHub Workflows

| Workflow | Trigger | Purpose |
| ---------- | --------- | --------- |
| `flux-local.yaml` | PR to main | Test/diff Flux resources |
| `labeler.yaml` | PR | Auto-label PRs |
| `label-sync.yaml` | Push | Sync GitHub labels |
| `release.yaml` | Push | Release automation |
| `e2e.yaml` | Manual | End-to-end testing |

## Quick Start

```bash
# 1. Install mise and activate
mise trust && mise install

# 2. Initialize configs
task init

# 3. Edit cluster.yaml and nodes.yaml

# 4. Create Cloudflare tunnel
cloudflared tunnel login
cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes

# 5. Render and validate templates
task configure

# 6. Commit and push
git add -A && git commit -m "Initial config" && git push

# 7. Bootstrap Talos
task bootstrap:talos

# 8. Bootstrap applications
task bootstrap:apps

# 9. Verify
kubectl get pods -A
flux get ks -A
```

## Template Structure

Templates use custom Jinja2 delimiters:
- Block: `#% ... %#`
- Variable: `#{ ... }#`
- Comment: `#| ... #|`

Key template paths:
- `templates/config/kubernetes/apps/` - Application manifests
- `templates/config/talos/` - Talos machine config
- `templates/config/bootstrap/` - Bootstrap resources
- `templates/config/infrastructure/` - OpenTofu configs and secrets

## Environment Variables

| Variable | Source | Purpose |
| ---------- | -------- | --------- |
| `KUBECONFIG` | `./kubeconfig` | Kubernetes access |
| `TALOSCONFIG` | `./talos/clusterconfig/talosconfig` | Talos access |
| `SOPS_AGE_KEY_FILE` | `./age.key` | SOPS decryption |

## Key Directories (Post-Configure)

Generated after `task configure`:
- `kubernetes/` - Rendered K8s manifests
- `talos/` - Rendered Talos configs
- `bootstrap/` - Rendered bootstrap resources
- `infrastructure/` - Rendered OpenTofu configs, secrets, and variables

## Infrastructure (OpenTofu)

The `infrastructure/` directory is **fully generated** by `task configure`:

```
infrastructure/                      # GENERATED directory
├── README.md                        # Documentation (copied)
├── secrets.sops.yaml                # Encrypted credentials
└── tofu/
    ├── backend.tf                   # HTTP backend (R2 + Worker)
    ├── versions.tf                  # OpenTofu/provider versions
    ├── providers.tf                 # Provider configs (conditional)
    ├── variables.tf                 # Input variables
    ├── main.tf                      # Resources (conditional)
    └── terraform.tfvars             # VM/node configuration

templates/config/infrastructure/     # Source templates
├── README.md                        # Copied as-is
├── secrets.sops.yaml.j2             # Secrets template
└── tofu/*.tf.j2                     # All .tf templates
```

**Features:**
- State stored in Cloudflare R2 via tfstate-worker HTTP backend with locking
- Automated Proxmox VM provisioning (ISO download, upload, VM creation)
- Talos Image Factory integration for schematic IDs
- Two deployment paths: Bare Metal (manual) or Proxmox VM (automated)
- All files auto-generated from templates via makejinja
- Conditional rendering based on `infrastructure_enabled`

See `docs/ai-context/infrastructure-opentofu.md` for deep-dive documentation.

## AI Context Documentation

The `docs/ai-context/` directory provides domain-specific deep-dive documentation for AI assistants:

| Document | Domain | Use When |
| -------- | ------ | -------- |
| `flux-gitops.md` | Flux CD | Adding apps, troubleshooting sync issues, understanding GitOps flow |
| `talos-operations.md` | Talos Linux | Node operations, upgrades, configuration changes |
| `cilium-networking.md` | Cilium CNI | Network debugging, LoadBalancer issues, BGP config |
| `template-system.md` | makejinja | Template syntax, adding variables, creating new templates |
| `infrastructure-opentofu.md` | OpenTofu | IaC operations, R2 backend, Proxmox automation |

**Token Efficiency:** Each document focuses on one domain (~8-12KB each), more efficient than loading full documentation (~64KB).
