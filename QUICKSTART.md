# Quickstart Guide

Step-by-step commands for deploying the cluster. See [README.md](./README.md) for detailed explanations.

## Prerequisites

- Cloudflare account with domain
- [mise](https://mise.jdx.dev/) installed
- **Option A (Manual):** Nodes booted into Talos maintenance mode (port 50000 accessible)
- **Option B (Automated):** Proxmox VE with API access for VM provisioning

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

# ⚠️ CRITICAL: Backup age.key immediately! This key encrypts ALL secrets.
# Store it securely (password manager, offline backup). If lost, encrypted
# secrets cannot be recovered and you'll need to regenerate everything.
cp age.key ~/secure-backup/  # Or your preferred backup location

# 4. Edit configuration files
# - cluster.yaml: network settings, cloudflare, credentials
#   For VM provisioning: proxmox_api_url, proxmox_node, proxmox_api_token_id, proxmox_api_token_secret
#   For state backend: tfstate_username, tfstate_password
#   For BGP (optional): cilium_bgp_router_addr, cilium_bgp_router_asn, cilium_bgp_node_asn
# - nodes.yaml: node names, IPs, disks, MACs, schematic IDs

# 5. Render templates, validate, and auto-init infrastructure
task configure
# Note: Automatically runs 'tofu init' if tfstate_password is configured
```

## Infrastructure (Proxmox VM Provisioning)

If you configured Proxmox credentials in cluster.yaml, `task configure` already initialized OpenTofu.

This automatically:
- Downloads Talos ISO from Image Factory using your schematic IDs
- Uploads ISO to Proxmox storage
- Creates VMs with configured resources (cores, memory, disk)
- Boots VMs into Talos maintenance mode

```bash
# Review execution plan (shows ISO downloads + VM creations)
task infra:plan

# Provision VMs (downloads ISO, creates VMs, boots them)
task infra:apply

# VMs are now in Talos maintenance mode (port 50000)
# Verify ALL nodes are accessible before proceeding to Bootstrap
task infra:verify-nodes
```

**First-time setup (new state backend):**
```bash
# Use -lock=false for initial plan/apply when no state exists
task infra:plan -- -lock=false
task infra:apply -- -lock=false
# Locking works normally after first apply
```

**Troubleshooting:**
```bash
# If backend URL changed after initial setup
task infra:init -- -reconfigure

# View provisioned resources
task infra:output
```

## Bootstrap

```bash
# 1. Install Talos on nodes (applies machine configs)
task bootstrap:talos

# 2. Commit generated secrets
git add -A && git commit -m "chore: add talhelper encrypted secret" && git push

# 3. Deploy Cilium, CoreDNS, Spegel, Flux
task bootstrap:apps

# 4. Watch deployment
kubectl get pods -A --watch
```

## BGP Configuration (Optional)

Enable BGP peering between Cilium and your UniFi gateway for multi-VLAN routing:

**1. Add to `cluster.yaml`:**
```yaml
cilium_bgp_router_addr: "192.168.23.254"  # Gateway IP (VLAN gateway, NOT UDM management IP)
cilium_bgp_router_asn: "64513"            # Gateway ASN (private: 64512-65534)
cilium_bgp_node_asn: "64514"              # Kubernetes ASN (must differ from gateway)
```

**2. Regenerate templates:**
```bash
task configure
```

**3. Upload UniFi BGP configuration:**
```bash
# Generated file: unifi/bgp.conf (gitignored - contains password)
# Sample structure: unifi/bgp.conf.sample
# Upload via: Settings → Routing → BGP → Add Configuration
```

**4. Deploy and verify:**
```bash
git add -A && git commit -m "feat: enable BGP peering" && git push
task reconcile
cilium bgp peers  # Should show "established" for all nodes
```

> **Full guide:** See [docs/guides/bgp-unifi-cilium-implementation.md](docs/guides/bgp-unifi-cilium-implementation.md) for advanced options (authentication, ECMP, graceful restart, timers).

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

# Check BGP (if enabled)
cilium bgp peers
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

# Modify infrastructure
task infra:plan
task infra:apply
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
| VM not booting | Check Proxmox console, verify schematic_id in nodes.yaml |
| Nodes not accessible | `task infra:verify-nodes`, check VM power state, network/firewall |
| BGP not established | Check `cilium bgp peers`, verify ASNs match, ensure UniFi config uploaded |

## Key Files

| File | Purpose |
| ------ | --------- |
| `cluster.yaml` | Cluster configuration (gitignored) |
| `nodes.yaml` | Node definitions (gitignored) |
| `age.key` | Encryption key (gitignored, never commit) |
| `cloudflare-tunnel.json` | Tunnel credentials (gitignored) |
| `infrastructure/tofu/` | Generated OpenTofu configs |
| `unifi/bgp.conf` | Generated UniFi BGP config (gitignored, upload to gateway) |
| `unifi/bgp.conf.sample` | Sample BGP config structure (committed) |

## Reset

```bash
# Reset Talos cluster (wipes nodes)
task talos:reset

# Destroy infrastructure (removes VMs)
task infra:destroy
```
