# CLI Reference

> Complete command reference for cluster management

## Task Commands

All tasks use [go-task](https://taskfile.dev/). Run `task --list` for all available commands.

### Core Tasks

| Command | Description | When to Use |
| ------- | ----------- | ----------- |
| `task init` | Initialize config files from samples | First-time setup |
| `task configure` | Render templates, validate, encrypt | After any config change |
| `task reconcile` | Force Flux to sync from Git | After manual changes |

**Usage Examples:**

```bash
# Initialize project (creates cluster.yaml, nodes.yaml, age.key)
task init

# Render all templates and validate
task configure

# Force immediate Git sync
task reconcile
```

### Bootstrap Tasks

| Command | Description | Prerequisites |
| ------- | ----------- | ------------- |
| `task bootstrap:talos` | Install Talos on all nodes | Nodes booted to Talos ISO |
| `task bootstrap:apps` | Deploy core applications | Talos bootstrap complete |

**Usage Examples:**

```bash
# Bootstrap Talos cluster (first time)
task bootstrap:talos

# Deploy Cilium, CoreDNS, Flux
task bootstrap:apps
```

### Talos Tasks

| Command | Description | Parameters |
| ------- | ----------- | ---------- |
| `task talos:generate-config` | Regenerate Talos configs | None |
| `task talos:apply-node` | Apply config to a node | `IP=<node-ip>` |
| `task talos:upgrade-node` | Upgrade Talos version | `IP=<node-ip>` |
| `task talos:upgrade-k8s` | Upgrade Kubernetes | None |
| `task talos:reset` | Reset cluster (destructive) | None |

**Usage Examples:**

```bash
# Regenerate configs after editing talconfig
task talos:generate-config

# Apply configuration to specific node
task talos:apply-node IP=192.168.1.10

# Upgrade Talos on node (after updating talenv.yaml)
task talos:upgrade-node IP=192.168.1.10

# Upgrade Kubernetes version
task talos:upgrade-k8s

# Reset entire cluster (WARNING: destructive)
task talos:reset
```

### Template Tasks

| Command | Description | When to Use |
| ------- | ----------- | ----------- |
| `task template:schema` | Generate JSON Schema from CUE | IDE validation updates |
| `task template:debug` | Dump cluster resource states | Debugging |
| `task template:tidy` | Archive template files | Post-setup cleanup |
| `task template:reset` | Remove all generated files | Start fresh |

### Infrastructure Tasks (OpenTofu)

| Command | Description | Parameters |
| ------- | ----------- | ---------- |
| `task infra:init` | Initialize OpenTofu with R2 backend | None |
| `task infra:plan` | Create execution plan (outputs tfplan) | None |
| `task infra:apply` | Apply saved plan (requires tfplan) | None |
| `task infra:apply-auto` | Apply with auto-approve (interactive) | None |
| `task infra:destroy` | Destroy managed resources (interactive) | None |
| `task infra:output` | Show OpenTofu outputs | None |
| `task infra:state-list` | List resources in state | None |
| `task infra:force-unlock` | Force unlock state lock | `LOCK_ID=<id>` |
| `task infra:validate` | Validate configuration | None |
| `task infra:fmt` | Format configuration files | None |
| `task infra:fmt-check` | Check formatting (CI) | None |
| `task infra:secrets-edit` | Edit encrypted secrets (for rotation) | None |
| `task infra:verify-nodes` | Verify nodes accessible in maintenance mode | None |

**Usage Examples:**

```bash
# Initialize OpenTofu (first time or after backend changes)
# NOTE: task configure auto-runs init when credentials are configured
task infra:init

# Plan and review changes
task infra:plan

# Apply the saved plan
task infra:apply

# Quick apply without plan file (prompts for confirmation)
task infra:apply-auto

# View current outputs
task infra:output

# List managed resources
task infra:state-list

# Force unlock a stuck state
task infra:force-unlock LOCK_ID=abc123

# Edit encrypted secrets (for credential rotation only)
# NOTE: Initial credentials come from cluster.yaml via task configure
task infra:secrets-edit

# Validate configuration syntax
task infra:validate

# Format configuration files
task infra:fmt

# Verify all nodes are accessible after VM provisioning
# Run before task bootstrap:talos
task infra:verify-nodes
```

**Prerequisites:**

- Configure credentials in `cluster.yaml`: `tfstate_username`, `tfstate_password`, `proxmox_api_token_id`, `proxmox_api_token_secret`
- Run `task configure` to generate and encrypt `infrastructure/secrets.sops.yaml`
- `age.key` must be present for SOPS encryption
- Required tools: `tofu`, `sops`, `yq`

---

## talosctl Reference

Talos node management CLI. Full docs: https://www.talos.dev/latest/reference/cli/

### Node Information

```bash
# Check node health
talosctl health -n <node-ip>

# List services
talosctl services -n <node-ip>

# View system logs
talosctl dmesg -n <node-ip>

# Get specific resource
talosctl get disks -n <node-ip>
talosctl get links -n <node-ip>
talosctl get virtualip -n <node-ip>
```

### Configuration

```bash
# Apply machine config
talosctl apply-config --nodes <ip> --file <config.yaml>

# Apply with mode (auto, no-reboot, reboot, staged)
talosctl apply-config --nodes <ip> --file <config.yaml> --mode=auto

# View current config
talosctl get machineconfig -n <node-ip> -o yaml
```

### Upgrades

```bash
# Upgrade Talos
talosctl upgrade --nodes <ip> --image ghcr.io/siderolabs/installer:v1.8.0

# Upgrade Kubernetes
talosctl upgrade-k8s --to 1.30.0
```

### etcd Operations

```bash
# Check etcd status
talosctl etcd status -n <control-plane-ip>

# List members
talosctl etcd members -n <control-plane-ip>

# Create snapshot
talosctl etcd snapshot db.snapshot -n <control-plane-ip>

# Remove failed member
talosctl etcd remove-member <member-id> -n <control-plane-ip>
```

### Troubleshooting

```bash
# View container logs
talosctl logs kubelet -n <node-ip>
talosctl logs containerd -n <node-ip>

# List containers
talosctl containers -n <node-ip>

# Execute command (limited)
talosctl read /etc/os-release -n <node-ip>

# Reset node (destructive)
talosctl reset --nodes <ip> --graceful=false
```

---

## kubectl Reference

Kubernetes CLI. Full docs: https://kubernetes.io/docs/reference/kubectl/

### Cluster Information

```bash
# Get nodes
kubectl get nodes -o wide

# Get all pods
kubectl get pods -A

# Get pods not running
kubectl get pods -A | grep -v Running

# Get events (sorted by time)
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

### Resource Operations

```bash
# Describe resource
kubectl describe pod <name> -n <namespace>
kubectl describe node <name>

# View logs
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
kubectl logs <pod> -n <namespace> -c <container>

# Execute in pod
kubectl exec -it <pod> -n <namespace> -- /bin/sh
```

### Service & Networking

```bash
# Get services
kubectl get svc -A

# Get endpoints
kubectl get endpoints -n <namespace> <service>

# Port forward
kubectl port-forward svc/<name> -n <namespace> <local>:<remote>

# Get ingress/httproutes
kubectl get httproute -A
kubectl get gateway -A
```

### Resource Management

```bash
# Get resource usage
kubectl top nodes
kubectl top pods -A

# Drain node for maintenance
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Cordon/uncordon
kubectl cordon <node>
kubectl uncordon <node>

# Rolling restart
kubectl rollout restart deployment/<name> -n <namespace>
kubectl rollout restart daemonset/<name> -n <namespace>
```

---

## flux Reference

Flux CD CLI. Full docs: https://fluxcd.io/flux/cmd/

### Status Commands

```bash
# Overall Flux status
flux check

# Get all Flux resources
flux get all -A

# Get sources
flux get sources git -A
flux get sources oci -A

# Get kustomizations
flux get ks -A

# Get helm releases
flux get hr -A

# Flux statistics
flux stats
```

### Reconciliation

```bash
# Reconcile source
flux reconcile source git flux-system

# Reconcile kustomization (with source)
flux reconcile ks <name> --with-source

# Reconcile helm release
flux reconcile hr -n <namespace> <name>
```

### Suspend/Resume

```bash
# Suspend resource
flux suspend ks <name>
flux suspend hr -n <namespace> <name>

# Resume resource
flux resume ks <name>
flux resume hr -n <namespace> <name>

# Suspend all kustomizations
flux suspend ks --all
```

### Debugging

```bash
# View logs
flux logs --level=error
flux logs --kind=Kustomization --name=<name>

# Trace resource
flux trace kustomization <name>
flux trace helmrelease <name> -n <namespace>
```

---

## cilium Reference

Cilium CLI. Full docs: https://docs.cilium.io/en/stable/cmdref/cilium-dbg/

### Status Commands

```bash
# Overall status
cilium status

# Connectivity test
cilium connectivity test

# BPF map info
cilium bpf lb list
cilium bpf endpoint list
```

### From Cilium Pod

```bash
# Access cilium agent
kubectl -n kube-system exec -it ds/cilium -- cilium status

# List services
kubectl -n kube-system exec -it ds/cilium -- cilium service list

# List endpoints
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list

# BPF load balancer entries
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list

# Monitor traffic
kubectl -n kube-system exec -it ds/cilium -- cilium monitor
```

### Hubble (if enabled)

```bash
# Observe traffic
hubble observe
hubble observe --pod <pod-name>
hubble observe --namespace <namespace>

# Status
hubble status
```

---

## sops Reference

Secret encryption CLI. Full docs: https://github.com/getsops/sops

### Encryption

```bash
# Encrypt file
sops -e secrets.yaml > secrets.sops.yaml

# Encrypt in place
sops -e -i secrets.sops.yaml
```

### Decryption

```bash
# Decrypt to stdout
sops -d secrets.sops.yaml

# Decrypt to file
sops -d secrets.sops.yaml > secrets.yaml
```

### Editing

```bash
# Edit encrypted file
sops secrets.sops.yaml

# Update keys (rotate)
sops updatekeys secrets.sops.yaml
```

---

## helm Reference

Helm CLI. Full docs: https://helm.sh/docs/helm/

### Chart Operations

```bash
# List releases
helm list -A

# Get release values
helm get values <release> -n <namespace>

# Get release manifest
helm get manifest <release> -n <namespace>

# Release history
helm history <release> -n <namespace>
```

### Debugging

```bash
# Template locally
helm template <release> <chart> -f values.yaml

# Dry run install
helm install --dry-run --debug <release> <chart>

# Diff (with helm-diff plugin)
helm diff upgrade <release> <chart> -n <namespace>
```

---

## cloudflared Reference

Cloudflare Tunnel CLI. Full docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

### Tunnel Management

```bash
# Login
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create <name>
cloudflared tunnel create --credentials-file <file> <name>

# List tunnels
cloudflared tunnel list

# Delete tunnel
cloudflared tunnel delete <name>
```

### Tunnel Operations

```bash
# Run tunnel
cloudflared tunnel run <name>

# Get tunnel info
cloudflared tunnel info <name>

# Route traffic
cloudflared tunnel route dns <tunnel> <hostname>
```

---

## Environment Variables

Required for CLI tools:

```bash
# Kubernetes access
export KUBECONFIG=./kubeconfig

# Talos access
export TALOSCONFIG=./talos/clusterconfig/talosconfig

# SOPS decryption
export SOPS_AGE_KEY_FILE=./age.key
```

These are automatically set by:

- `Taskfile.yaml` (`env:` block)
- `.mise.toml` (`[env]` section)

---

## Quick Reference Card

### Daily Operations

```bash
# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
flux get ks -A

# Force sync
task reconcile

# View logs
kubectl logs <pod> -n <namespace>
flux logs --level=error
```

### Maintenance

```bash
# Drain node
kubectl drain <node> --ignore-daemonsets

# Upgrade node
task talos:upgrade-node IP=<ip>

# Uncordon
kubectl uncordon <node>
```

### Troubleshooting

```bash
# Node health
talosctl health -n <ip>

# Network
cilium status

# GitOps
flux check
flux logs
```

---

**Last Updated:** January 13, 2026
**Tools Covered:** go-task, talosctl, kubectl, flux, cilium, sops, helm, cloudflared
**Task Runner:** go-task v3.x (run `task --list` for all commands)
**Related Docs:** OPERATIONS.md, TROUBLESHOOTING.md
