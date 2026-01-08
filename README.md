# MatherlyNet Kubernetes Cluster

A GitOps-driven Kubernetes cluster on Talos Linux, forked from [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template).

## Features

- **[Talos Linux](https://github.com/siderolabs/talos)** - Immutable, secure Kubernetes OS
- **[Flux CD](https://github.com/fluxcd/flux2)** - GitOps reconciliation with GitHub
- **[Cilium](https://github.com/cilium/cilium)** - CNI with kube-proxy replacement and BGP
- **[Gateway API](https://gateway-api.sigs.k8s.io/)** - Modern ingress with Envoy Gateway
- **[SOPS/Age](https://github.com/getsops/sops)** - Secret encryption at rest
- **[Cloudflare](https://www.cloudflare.com/)** - DNS, tunnels, and external access
- **[OpenTofu](https://opentofu.org/)** - Infrastructure as Code (optional)
- **[UniFi DNS](https://github.com/kashalls/external-dns-unifi-webhook)** - Native UniFi DNS integration (optional)

**Included components:** flux, cilium, cert-manager, spegel, reloader, envoy-gateway, external-dns, cloudflared, k8s-gateway (or unifi-dns), talos-ccm, tuppr, talos-backup (optional), cloudnative-pg (optional), keycloak (optional), rustfs (optional), dragonfly (optional), litellm (optional), langfuse (optional)

**Other features:**
- Dev environment managed with [mise](https://mise.jdx.dev/)
- Workflow automation with [GitHub Actions](https://github.com/features/actions)
- Dependency automation with [Renovate](https://www.mend.io/renovate)
- Flux diffs with [flux-local](https://github.com/allenporter/flux-local)

## Prerequisites

- **Required:** Knowledge of Containers, YAML, Git, and a **Cloudflare account** with a **domain**
- **Hardware:** See [Stage 1](#stage-1-hardware-configuration) for requirements
- **Optional:** Proxmox or other hypervisor for VM-based deployments

## Quick Start

There are **7 stages** for a complete deployment. Follow them in order.

| Stage | Description | Time |
| ------- | ------------- | ------ |
| [1. Hardware](#stage-1-hardware-configuration) | Plan hardware requirements | - |
| [2. Machine Prep](#stage-2-machine-preparation) | Boot nodes into Talos maintenance | ~30 min |
| [3. Workstation](#stage-3-local-workstation) | Clone repo, install tools | ~15 min |
| [4. Cloudflare](#stage-4-cloudflare-configuration) | API token, tunnel setup | ~10 min |
| [5. Infrastructure](#stage-5-infrastructure-optional) | OpenTofu for VM management | ~20 min |
| [6. Cluster Config](#stage-6-cluster-configuration) | Configure and template | ~15 min |
| [7. Bootstrap](#stage-7-bootstrap-talos-kubernetes-and-flux) | Deploy the cluster | ~15 min |

---

## Stage 1: Hardware Configuration

For a **stable** and **high-availability** production Kubernetes cluster, hardware selection is critical.

### Recommendations

| Aspect | Recommended | Acceptable | Avoid |
| -------- | ------------- | ------------ | ------- |
| **Storage** | Enterprise NVMe/SSD | Consumer SSD | HDD |
| **Platform** | Bare Metal | Proxmox (enterprise drives) | Nested virtualization |
| **Drives** | Dedicated per workload | Shared (careful tuning) | Consumer drives for etcd |

> **Note:** These guidelines provide a baseline. Always **test thoroughly and benchmark performance** under realistic workloads.

---

## Stage 2: Machine Preparation

> [!IMPORTANT]
> If you have **3 or more nodes**, make 3 of them controller nodes for high availability. By default, control plane nodes do **not** run workloads—dedicated worker nodes are recommended for production.
>
> **Minimum requirements per node:**
>
> | Role | Cores | Memory | System Disk |
> | ------ | ------- | -------- | ------------- |
> | Control Plane | 4 | 8GB | 128GB SSD/NVMe |
> | Worker | 4 | 16GB | 256GB SSD/NVMe |

### Option A: Bare Metal Deployment

1. **Create Talos Image**: Go to [Talos Linux Image Factory](https://factory.talos.dev) and create an image with your required system extensions. Note the **schematic ID**.

2. **Boot Nodes**: Flash the ISO/RAW image to USB and boot your nodes into maintenance mode.

3. **Verify Network Access**:
   ```sh
   nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'
   ```

### Option B: VM Deployment (Proxmox via OpenTofu)

If using OpenTofu for automated VM provisioning, configuration follows the same templating pattern as the rest of the project.

1. **Configure Infrastructure Settings** in `cluster.yaml`:
   ```yaml
   # -- Proxmox API endpoint
   #    (REQUIRED for VM deployment)
   proxmox_api_url: "https://pve.example.com:8006/api2/json"

   # -- Proxmox node name to create VMs on
   #    (REQUIRED for VM deployment)
   proxmox_node: "pve"

   # -- Default VM resources (can be overridden per-node)
   proxmox_vm_defaults:
     cores: 4
     memory: 8192      # MB
     disk_size: 128    # GB
   ```

2. **Configure Node VM Specs** in `nodes.yaml`:
   ```yaml
   nodes:
     - name: cp-1
       address: 192.168.1.10
       controller: true
       schematic_id: "your-schematic-id"
       mac_addr: "BC:24:11:xx:xx:xx"
       disk: /dev/sda
       # VM-specific overrides (optional)
       vm_cores: 4
       vm_memory: 8192
       vm_disk_size: 128
   ```

   > **Note:** The `schematic_id`, `address`, and `mac_addr` from `nodes.yaml` are used by both Talos configuration AND OpenTofu VM provisioning.

3. **Render Templates** (generates infrastructure alongside kubernetes/talos):
   ```sh
   task configure
   ```

4. **Provision Infrastructure**:
   ```sh
   task infra:plan    # Review what will be created
   task infra:apply   # Provision VMs
   ```

   This automatically:
   - Downloads Talos ISO from Image Factory using your schematic ID
   - Uploads ISO to Proxmox storage
   - Creates VMs with specified resources
   - Attaches ISO and configures boot order
   - Boots VMs into Talos maintenance mode

5. **Verify Network Access**:
   ```sh
   nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'
   ```

> **Note:** For OpenTofu VM provisioning, continue to [Stage 5](#stage-5-infrastructure-optional) for R2 backend setup, then [Stage 6](#stage-6-cluster-configuration). For manually provisioned VMs or bare metal, skip directly to [Stage 6](#stage-6-cluster-configuration).

---

## Stage 3: Local Workstation

### Steps

1. **Create Repository** from template:
   ```sh
   export REPONAME="home-ops"
   gh repo create $REPONAME --template onedr0p/cluster-template --disable-wiki --public --clone && cd $REPONAME
   ```

2. **Install Mise CLI**: Follow the [installation guide](https://mise.jdx.dev/getting-started.html#installing-mise-cli) and [activate it](https://mise.jdx.dev/getting-started.html#activate-mise).

3. **Install Tools**:
   ```sh
   mise trust
   pip install pipx
   mise install
   ```

4. **Logout of GHCR** (prevents auth issues):
   ```sh
   docker logout ghcr.io
   helm registry logout ghcr.io
   ```

---

## Stage 4: Cloudflare Configuration

### Steps

1. **Create API Token**:
   - Go to Cloudflare Dashboard > API Tokens
   - Use "Edit zone DNS" template
   - Name it `kubernetes`
   - Add permissions:
     - `Zone - DNS - Edit`
     - `Account - Cloudflare Tunnel - Read`
   - Save the token securely

2. **Create Cloudflare Tunnel**:
   ```sh
   cloudflared tunnel login
   cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
   ```

---

## Stage 5: Infrastructure (Optional)

> [!TIP]
> This stage is **optional**. Skip to [Stage 6](#stage-6-cluster-configuration) if you're deploying on existing VMs or bare metal without IaC management.

OpenTofu manages infrastructure (VMs, networks) with state stored in Cloudflare R2 via a custom HTTP backend.

### Architecture

```
Developer Workstation
         │
         │ task infra:*
         ▼
┌─────────────────────┐
│   tfstate-worker    │  ◄── Cloudflare Worker
│   (HTTP Backend)    │      - Basic Auth
│   - State locking   │      - Concurrent access
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Cloudflare R2     │  ◄── Free tier: 10GB
│   - State storage   │
└─────────────────────┘
```

### Prerequisites (One-Time)

Complete these in Cloudflare before proceeding:

1. **Create R2 Bucket**:
   ```sh
   npx wrangler login
   npx wrangler r2 bucket create matherlynet-tfstate
   ```

2. **Deploy tfstate-worker**:
   - Clone: https://github.com/MatherlyNet/matherlynet-tfstate
   - Configure `wrangler.toml` with your account ID
   - Set secrets:
     ```sh
     npx wrangler secret put TFSTATE_USERNAME
     npx wrangler secret put TFSTATE_PASSWORD
     ```
   - Deploy: `npx wrangler deploy`
   - (Optional) Configure custom domain

### Setup

1. **Initialize Config Files** (if not done already):
   ```sh
   task init
   ```

2. **Edit Configuration**:
   - `cluster.yaml` - Add `proxmox_api_url` and `proxmox_node` to enable infrastructure
   - `nodes.yaml` - Add VM specs per node (`vm_cores`, `vm_memory`, etc.)

3. **Add Credentials** to `cluster.yaml`:
   ```yaml
   # R2 state backend credentials (must match tfstate-worker secrets)
   tfstate_username: "terraform"
   tfstate_password: "your-strong-password"

   # Proxmox API token (for VM provisioning)
   proxmox_api_token_id: "root@pam!terraform"
   proxmox_api_token_secret: "your-api-token"
   ```

4. **Render Templates** (generates configs and auto-initializes backend):
   ```sh
   task configure
   ```

5. **Verify Connection** (use `-lock=false` for initial setup when no state exists):
   ```sh
   task infra:plan -- -lock=false
   ```
   > **Note:** The `-lock=false` flag is only needed for the first plan/apply when no state file exists yet. After the initial apply creates state, locking works normally.

### Backend Configuration

The HTTP backend is configured via template and generated to `infrastructure/tofu/backend.tf`:

```hcl
terraform {
  backend "http" {
    address        = "https://tfstate.matherly.net/tfstate/states/proxmox"
    lock_address   = "https://tfstate.matherly.net/tfstate/states/proxmox/lock"
    lock_method    = "LOCK"
    unlock_address = "https://tfstate.matherly.net/tfstate/states/proxmox/lock"
    unlock_method  = "UNLOCK"
    # Credentials via TF_HTTP_USERNAME / TF_HTTP_PASSWORD env vars
  }
}
```

> **Note:** Credentials are injected automatically by `task infra:*` commands from `infrastructure/secrets.sops.yaml`.

### Available Tasks

| Command | Description |
| --------- | ------------- |
| `task infra:init` | Initialize OpenTofu backend |
| `task infra:plan` | Create execution plan |
| `task infra:apply` | Apply saved plan |
| `task infra:apply-auto` | Apply with auto-approve |
| `task infra:destroy` | Destroy all resources |
| `task infra:state-list` | List managed resources |
| `task infra:secrets-edit` | Edit encrypted secrets (rotation) |

> **See also:** [templates/config/infrastructure/README.md](./templates/config/infrastructure/README.md) for detailed documentation.

---

## Stage 6: Cluster Configuration

### Steps

1. **Initialize Config Files** (skip if done in Stage 5):
   ```sh
   task init
   ```

2. **Edit Configuration**:
   - `cluster.yaml` - Network settings, Cloudflare config, repository info
   - `nodes.yaml` - Node names, IPs, disks, MAC addresses, schematic IDs

3. **Render Templates**:
   ```sh
   task configure
   ```
   This validates schemas, renders templates, and encrypts secrets.

4. **Verify Encryption**:
   ```sh
   # All *.sops.* files should be encrypted
   find kubernetes talos bootstrap infrastructure -name "*.sops.*" -exec sops filestatus {} \;
   ```

5. **Commit and Push**:
   ```sh
   git add -A
   git commit -m "chore: initial commit"
   git push
   ```

> [!TIP]
> **Private repository?** Add the public key from `github-deploy.key.pub` to your repository's deploy keys with read/write access.

---

## Stage 7: Bootstrap Talos, Kubernetes, and Flux

> [!WARNING]
> Cluster setup takes **10+ minutes**. You'll see errors like "couldn't get current server API group list" - this is normal until CNI is deployed. Don't interrupt with Ctrl+C.

### Steps

1. **Install Talos**:
   ```sh
   task bootstrap:talos
   ```

2. **Commit Talos Secrets**:
   ```sh
   git add -A
   git commit -m "chore: add talhelper encrypted secret"
   git push
   ```

3. **Install Cilium, CoreDNS, Spegel, and Flux**:
   ```sh
   task bootstrap:apps
   ```

4. **Watch Deployment**:
   ```sh
   kubectl get pods --all-namespaces --watch
   ```

---

## Post Installation

### Verification

1. **Cilium Status**:
   ```sh
   cilium status
   ```

2. **Flux Status**:
   ```sh
   flux check
   flux get sources git flux-system
   flux get ks -A
   flux get hr -A
   ```

3. **Gateway Connectivity**:
   ```sh
   nmap -Pn -n -p 443 ${cluster_gateway_addr} ${cloudflare_gateway_addr} -vv
   ```

4. **DNS Resolution**:
   ```sh
   dig @${cluster_dns_gateway_addr} echo.${cloudflare_domain}
   ```

5. **Certificate Status**:
   ```sh
   kubectl -n network describe certificates
   ```

### GitHub Webhook (Push-based Reconciliation)

1. Get webhook path:
   ```sh
   kubectl -n flux-system get receiver github-webhook --output=jsonpath='{.status.webhookPath}'
   ```

2. Create webhook at `https://flux-webhook.${cloudflare_domain}<webhook-path>` in your GitHub repository settings.

---

## Maintenance

### Talos Node Configuration

```sh
# Regenerate configs after editing talconfig.yaml
task talos:generate-config

# Apply to a node
task talos:apply-node IP=10.10.10.10 MODE=auto
```

### Version Upgrades

**Option A: Automated via tuppr (Recommended)**

Update version in `cluster.yaml` and let GitOps handle the upgrade:
```sh
# Edit cluster.yaml:
#   talos_version: "1.12.1"
#   kubernetes_version: "1.35.1"
task configure
git add -A && git commit -m "chore: upgrade versions" && git push
# tuppr performs rolling upgrade automatically
```

**Option B: Manual Upgrade**

```sh
# Upgrade Talos (update talenv.yaml first)
task talos:upgrade-node IP=10.10.10.10

# Upgrade Kubernetes
task talos:upgrade-k8s
```

### Adding Nodes

1. Boot new node into maintenance mode
2. Get disk and MAC info:
   ```sh
   talosctl get disks -n <ip> --insecure
   talosctl get links -n <ip> --insecure
   ```
3. Update `nodes.yaml` and run `task configure`
4. Apply config: `task talos:apply-node IP=<ip>`

### Infrastructure Changes

```sh
# Edit OpenTofu templates, then regenerate
vim templates/config/infrastructure/tofu/main.tf.j2
task configure

# Validate and plan
task infra:validate
task infra:plan

# Apply changes
task infra:apply
```

---

## Reset

> [!CAUTION]
> Resetting multiple times quickly can trigger **rate limiting** by DockerHub or Let's Encrypt.

```sh
task talos:reset
```

---

## Troubleshooting

| Issue | Command |
| --------- | --------- |
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| Bootstrap node stuck | `task bootstrap:preflight`, `task bootstrap:verify` |
| CNI issues | `cilium status`, `cilium connectivity test` |
| Certificate issues | `kubectl get certificates -A` |
| Infrastructure state lock | `task infra:force-unlock LOCK_ID=<id>` |
| Infrastructure 404 on lock | Use `-- -lock=false` for initial plan/apply (new state) |
| Infrastructure auth | Check credentials in `cluster.yaml`, re-run `task configure` |

See [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) for comprehensive diagnostic flowcharts.

---

## Documentation

| Document | Description |
| ---------- | ------------- |
| [ARCHITECTURE.md](./docs/ARCHITECTURE.md) | System design and diagrams |
| [CONFIGURATION.md](./docs/CONFIGURATION.md) | Configuration reference |
| [OPERATIONS.md](./docs/OPERATIONS.md) | Day-2 operations |
| [QUICKSTART.md](./docs/QUICKSTART.md) | Step-by-step setup guide |
| [CLI_REFERENCE.md](./docs/CLI_REFERENCE.md) | Complete command reference |
| [infrastructure/README.md](./templates/config/infrastructure/README.md) | OpenTofu setup details |

---

## Related Projects

- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) - Upstream template
- [ajaykumar4/cluster-template](https://github.com/ajaykumar4/cluster-template) - Argo CD variant
- [khuedoan/homelab](https://github.com/khuedoan/homelab) - Fully automated homelab

---

## Support

- [GitHub Discussions](https://github.com/onedr0p/cluster-template/discussions) (upstream)
- [Home Operations Discord](https://discord.gg/home-operations) - `#support` or `#cluster-template`
