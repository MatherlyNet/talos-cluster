# Quick Start Guide

> Get your Talos Kubernetes cluster running in under 30 minutes

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] 1-3 physical or virtual machines with:
  - 2+ CPU cores
  - 4GB+ RAM
  - 20GB+ disk
  - Network connectivity
- [ ] A domain managed by Cloudflare
- [ ] A GitHub repository (public or private)
- [ ] Network access to configure static IPs

## Visual Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLUSTER SETUP WORKFLOW                            │
└─────────────────────────────────────────────────────────────────────────────┘

     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
     │  1. PREPARE  │────▶│  2. CONFIG   │────▶│ 3. BOOTSTRAP │
     │   HARDWARE   │     │    FILES     │     │    CLUSTER   │
     └──────────────┘     └──────────────┘     └──────────────┘
           │                    │                    │
           │                    │                    │
           ▼                    ▼                    ▼
    ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
    │ Boot nodes  │      │ task init   │      │ task        │
    │ with Talos  │      │ Edit YAML   │      │ bootstrap:  │
    │ ISO         │      │ task        │      │ talos       │
    │             │      │ configure   │      │             │
    └─────────────┘      └─────────────┘      └─────────────┘
                                                    │
                                                    ▼
                               ┌──────────────────────────────────┐
                               │        4. DEPLOY APPS            │
                               │    task bootstrap:apps           │
                               │                                  │
                               │  Cilium → CoreDNS → Flux → Apps  │
                               └──────────────────────────────────┘
                                                    │
                                                    ▼
                               ┌──────────────────────────────────┐
                               │        5. GITOPS TAKES OVER      │
                               │                                  │
                               │   Git Push → Flux → K8s Deploy   │
                               └──────────────────────────────────┘
```

---

## Step 1: Install Development Tools (2 min)

```bash
# Install mise (tool version manager)
curl https://mise.run | sh

# Clone and enter repository
git clone https://github.com/YOUR_USER/YOUR_REPO.git
cd YOUR_REPO

# Trust and install tools
mise trust
mise install
```

**Installed Tools:**
- `talosctl` - Talos node management
- `kubectl` - Kubernetes CLI
- `flux` - GitOps CLI
- `sops` - Secret encryption
- `helm` - Chart management

---

## Step 2: Initialize Configuration (5 min)

```bash
# Generate config files from samples
task init
```

This creates:
- `cluster.yaml` - Cluster-wide settings
- `nodes.yaml` - Node definitions
- `age.key` - Encryption key (keep safe!)
- `github-deploy.key` - Git access key

### Edit cluster.yaml

```yaml
# Network - adjust to your network
node_cidr: "192.168.1.0/24"
cluster_api_addr: "192.168.1.100"        # VIP for K8s API
cluster_gateway_addr: "192.168.1.101"    # Internal services
cluster_dns_gateway_addr: "192.168.1.102" # Split DNS
cloudflare_gateway_addr: "192.168.1.103" # External services

# GitHub
repository_name: "your-user/your-repo"

# Cloudflare
cloudflare_domain: "your-domain.com"
cloudflare_token: "your-api-token"
```

### Edit nodes.yaml

Get node info while booted to Talos ISO:
```bash
talosctl get disks -n <node-ip> --insecure
talosctl get links -n <node-ip> --insecure
```

```yaml
nodes:
  - name: "node-1"
    address: "192.168.1.10"
    controller: true
    disk: "/dev/nvme0n1"
    mac_addr: "aa:bb:cc:dd:ee:01"
    schematic_id: "..."  # From factory.talos.dev

  - name: "node-2"
    address: "192.168.1.11"
    controller: true
    disk: "/dev/sda"
    mac_addr: "aa:bb:cc:dd:ee:02"
    schematic_id: "..."

  - name: "node-3"
    address: "192.168.1.12"
    controller: true
    disk: "/dev/nvme0n1"
    mac_addr: "aa:bb:cc:dd:ee:03"
    schematic_id: "..."
```

---

## Step 3: Create Cloudflare Tunnel (5 min)

```bash
# Login to Cloudflare
cloudflared tunnel login

# Create tunnel (saves credentials to file)
cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
```

---

## Step 4: Render and Validate (2 min)

```bash
# Render templates, validate, encrypt secrets
task configure
```

**What happens:**
1. Jinja2 templates → Kubernetes YAML
2. CUE schema validation
3. SOPS encryption of secrets
4. Kubeconform manifest validation

---

## Step 5: Commit to Git (1 min)

```bash
git add -A
git commit -m "Initial cluster configuration"
git push origin main
```

---

## Step 6: Bootstrap Talos (10 min)

Ensure nodes are booted from Talos ISO, then:

```bash
task bootstrap:talos
```

**What happens:**
1. Generates Talos configs via talhelper
2. Applies machine config to each node
3. Bootstraps etcd on first control plane
4. Waits for all nodes to join cluster
5. Generates kubeconfig

**Verify:**
```bash
kubectl get nodes
# All nodes should be Ready
```

---

## Step 7: Deploy Applications (5 min)

```bash
task bootstrap:apps
```

**Deployment Order:**
```
1. CRDs (Gateway API, Prometheus, etc.)
   ↓
2. Cilium (CNI, LoadBalancer)
   ↓
3. CoreDNS (Cluster DNS)
   ↓
4. Spegel (P2P image distribution)
   ↓
5. Flux Operator + Instance (GitOps)
   ↓
6. Flux takes over → deploys remaining apps
```

**Verify:**
```bash
# All pods running
kubectl get pods -A

# Flux syncing
flux get ks -A
```

---

## Step 8: Configure Home DNS (Optional)

For internal access to services, configure your home router/DNS:

**Forward these domains to `cluster_dns_gateway_addr`:**
```
*.your-domain.com → 192.168.1.102
```

**Example (Pi-hole/AdGuard):**
```
# Custom DNS rules
your-domain.com 192.168.1.102
```

---

## Verification Checklist

```bash
# 1. Nodes healthy
kubectl get nodes -o wide
# Expected: All nodes Ready

# 2. System pods running
kubectl get pods -n kube-system
# Expected: cilium, coredns, spegel running

# 3. Flux syncing
flux get ks -A
# Expected: All kustomizations Ready

# 4. Load balancer IPs assigned
kubectl get svc -A | grep LoadBalancer
# Expected: envoy-internal, envoy-external, k8s-gateway with IPs

# 5. Certificates issued
kubectl get certificates -A
# Expected: wildcard certificate Ready

# 6. Test application
curl https://echo.your-domain.com
# Expected: Echo response (if internal DNS configured)
```

---

## Common Issues

### Nodes Not Joining

```bash
# Check Talos health
talosctl health -n <node-ip>

# Check etcd
talosctl etcd status -n <control-plane-ip>
```

### Flux Not Syncing

```bash
# Check source
flux get sources git -A

# Check logs
kubectl -n flux-system logs deploy/source-controller
```

### No LoadBalancer IPs

```bash
# Check Cilium
cilium status

# Check L2 announcements
kubectl get ciliuml2announcementpolicy
kubectl get ciliumloadbalancerippool
```

---

## Next Steps

1. **Add Applications**: See [OPERATIONS.md](./OPERATIONS.md#adding-a-new-application)
2. **Configure BGP**: See [research/bgp-unifi-cilium-integration.md](./research/bgp-unifi-cilium-integration.md)
3. **Understand Architecture**: See [ARCHITECTURE.md](./ARCHITECTURE.md)
4. **Day-2 Operations**: See [OPERATIONS.md](./OPERATIONS.md)

---

## Quick Reference Card

| Task | Command |
| ------ | --------- |
| Initialize | `task init` |
| Configure | `task configure` |
| Bootstrap Talos | `task bootstrap:talos` |
| Bootstrap Apps | `task bootstrap:apps` |
| Force Sync | `task reconcile` |
| Node Status | `kubectl get nodes -o wide` |
| Pod Status | `kubectl get pods -A` |
| Flux Status | `flux get ks -A` |
| Talos Health | `talosctl health -n <ip>` |
| Cilium Status | `cilium status` |
