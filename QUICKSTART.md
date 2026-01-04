# Quickstart Guide

Step-by-step commands for deploying the cluster. See [README.md](./README.md) for detailed explanations.

## Prerequisites

- Cloudflare account with domain
- Nodes booted into Talos maintenance mode (port 50000 accessible)
- [mise](https://mise.jdx.dev/) installed

## Setup

```bash
# 1. Clone and install tools
gh repo create home-ops --template onedr0p/cluster-template --public --clone && cd home-ops
mise trust && pip install pipx && mise install
docker logout ghcr.io && helm registry logout ghcr.io

# 2. Create Cloudflare tunnel
cloudflared tunnel login
cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes

# 3. Initialize configuration
task init

# 4. Edit configuration files
# - cluster.yaml: network settings, cloudflare, credentials (including tfstate_* for infra)
# - nodes.yaml: node names, IPs, disks, MACs, schematic IDs

# 5. Render templates, validate, and auto-init infrastructure
task configure
# Note: Automatically runs 'tofu init' if tfstate_password is configured
```

## Infrastructure (Optional - for OpenTofu/Proxmox)

If you configured infrastructure credentials in cluster.yaml, `task configure` already initialized OpenTofu. Continue with:

```bash
# First plan (use -lock=false for new state backend)
task infra:plan -- -lock=false

# Apply infrastructure (provision VMs)
task infra:apply -- -lock=false

# Subsequent operations (locking works after state exists)
task infra:plan
task infra:apply
```

**Troubleshooting:**
```bash
# If backend URL changed after initial setup
task infra:init -- -reconfigure
```

## Bootstrap

```bash
# 1. Install Talos on nodes
task bootstrap:talos

# 2. Commit generated secrets
git add -A && git commit -m "chore: add talhelper encrypted secret" && git push

# 3. Deploy Cilium, CoreDNS, Spegel, Flux
task bootstrap:apps

# 4. Watch deployment
kubectl get pods -A --watch
```

## Verification

```bash
# Check nodes
kubectl get nodes -o wide

# Check Cilium
cilium status

# Check Flux
flux check
flux get ks -A
flux get hr -A

# Check certificates
kubectl get certificates -A
```

## Day-2 Operations

```bash
# Force Flux sync
task reconcile

# Apply config to node
task talos:apply-node IP=<ip>

# Upgrade Talos
task talos:upgrade-node IP=<ip>

# Upgrade Kubernetes
task talos:upgrade-k8s

# Re-render after config changes
task configure
```

## Troubleshooting

| Issue | Fix |
| ------- | ----- |
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| CNI issues | `cilium status` |
| Infra 404 on lock | Use `-- -lock=false` (new state, see above) |
| Infra state lock stuck | `task infra:force-unlock LOCK_ID=<id>` |
| Infra auth (401) | Check credentials in `cluster.yaml`, re-run `task configure` |
| Backend URL changed | `task infra:init -- -reconfigure` |

## Key Files

| File | Purpose |
| ------ | --------- |
| `cluster.yaml` | Cluster configuration (gitignored) |
| `nodes.yaml` | Node definitions (gitignored) |
| `age.key` | Encryption key (gitignored, never commit) |
| `cloudflare-tunnel.json` | Tunnel credentials (gitignored) |

## Reset

```bash
task talos:reset
```
