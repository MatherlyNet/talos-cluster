# Talos Operations Guide

> Deep-dive documentation for AI assistants working with Talos Linux in this project.

## Overview

**Talos Linux v1.12.1** is an immutable, API-driven Kubernetes OS. There is no SSH, no shell, and no package manager. All configuration is done via the Talos API using `talosctl`.

**Key Facts:**

- **Talos Version**: v1.12.1 (talenv.yaml)
- **Kubernetes Version**: v1.35.0
- **Config Generator**: talhelper v3.1.0
- **Boot Method**: Talos Image Factory with schematic IDs
- **Control Plane Scheduling**: Disabled by default (`allowSchedulingOnControlPlanes: false`)

## Architecture

### Talos Principles

1. **Immutable**: Read-only root filesystem
2. **API-Driven**: All config via gRPC API
3. **Secure**: No SSH, no shell, minimal attack surface
4. **Declarative**: Configuration as YAML

### Node Types

- **Controller**: Runs control plane (etcd, API server, scheduler, controller-manager); does NOT run workloads by default
- **Worker**: Runs workloads only; recommended for production deployments

### Control Plane Scheduling

Control plane nodes are configured with `allowSchedulingOnControlPlanes: false` by default. This means:

- Workloads will NOT be scheduled on control plane nodes
- Dedicated worker nodes are required for running applications
- Configurable via `templates/config/talos/patches/controller/cluster.yaml.j2`

## Talos Platform Components

The cluster includes platform components for Talos lifecycle management:

| Component | Version | Purpose |
| --------- | ------- | ------- |
| **tuppr** | v0.0.51 | Talos Upgrade Controller - GitOps-driven OS and K8s upgrades |
| **talos-ccm** | v0.5.4 | Talos Cloud Controller Manager - Node lifecycle management |
| **talos-backup** | v0.1.2 | Automated etcd snapshots with S3 storage and Age encryption |

### tuppr (Talos Upgrade Controller)

Located in `kubernetes/apps/system-upgrade/tuppr/`:

- Manages Talos OS upgrades via `TalosUpgrade` CRs
- Manages Kubernetes upgrades via `KubernetesUpgrade` CRs
- Enables GitOps-driven upgrades without manual talosctl commands

### talos-ccm (Cloud Controller Manager)

Located in `kubernetes/apps/kube-system/talos-ccm/`:

- Manages node lifecycle (registration, status updates)
- Integrates Talos nodes with Kubernetes control plane
- Always deployed (no conditional flag)

### talos-backup

Located in `kubernetes/apps/kube-system/talos-backup/`:

- Automated etcd snapshots to S3-compatible storage
- Age encryption for backup data
- Conditional: Enabled when `backup_s3_endpoint` and `backup_s3_bucket` configured
- See "Automated Etcd Backup" section below for details

## Configuration Generation

### talhelper

This project uses [talhelper](https://github.com/budimanjojo/talhelper) to generate Talos configurations from a single source.

```
talos/
├── talconfig.yaml      # Main config (generated from template)
├── talenv.yaml         # Version pins
├── talsecret.sops.yaml # Encrypted secrets (after bootstrap)
└── clusterconfig/      # Per-node configs (generated)
```

### talconfig.yaml

Generated from `templates/config/talos/talconfig.yaml.j2`:

```yaml
clusterName: talos
endpoint: https://<cluster_api_addr>:6443

nodes:
  - hostname: k8s-node-1
    ipAddress: 192.168.1.10
    controlPlane: true
    installDisk: /dev/nvme0n1
    networkInterfaces:
      - interface: eth0
        addresses:
          - 192.168.1.10/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        mtu: 1500
    schematic:
      customization:
        systemExtensions:
          officialExtensions:
            - siderolabs/...
```

### talenv.yaml

Version pins:

```yaml
talosVersion: v1.12.1
kubernetesVersion: v1.35.0
```

## Patches

Talos patches customize node configuration. Organized by scope:

```
templates/config/talos/patches/
├── global/           # All nodes
│   ├── cluster.yaml.j2
│   ├── machine.yaml.j2
│   └── ...
├── controller/       # Control plane only
│   ├── admission.yaml.j2
│   └── ...
├── worker/          # Workers only
│   └── ...
└── <node-name>/     # Specific node
    └── custom.yaml.j2
```

### Common Patches

**Cluster Configuration** (controller):

```yaml
cluster:
  allowSchedulingOnControlPlanes: false
  proxy:
    disabled: true  # Cilium replaces kube-proxy
  coreDNS:
    disabled: true  # CoreDNS deployed via Flux
```

**CNI Configuration** (talconfig.yaml):

```yaml
# Disable built-in CNI to use Cilium
cniConfig:
  name: none

clusterPodNets: ["10.42.0.0/16"]
clusterSvcNets: ["10.43.0.0/16"]
```

**Machine Configuration** (global):

```yaml
machine:
  kubelet:
    extraArgs:
      feature-gates: ImageVolume=true  # CNPG managed extensions
    extraConfig:
      serializeImagePulls: false
    nodeIP:
      validSubnets:
        - <node_cidr>

  features:
    hostDNS:
      enabled: true                    # Local DNS caching at 127.0.0.53
      forwardKubeDNSToHost: true       # Forward CoreDNS queries
      resolveMemberNames: true         # Hostname resolution (e.g., talos-cp-001)

  network:
    disableSearchDomain: true
    nameservers:
      - <configured_dns_servers>       # From cluster.yaml
    interfaces:
      - interface: lo
        addresses:
          - 169.254.116.108/32         # Cilium eBPF workaround

  time:
    disabled: false
    servers:
      - <configured_ntp_servers>       # From cluster.yaml
```

## Node Lifecycle

### Initial Installation

```bash
# 1. Boot from Talos ISO (maintenance mode)
# 2. Get disk/NIC info
talosctl get disks -n <ip> --insecure
talosctl get links -n <ip> --insecure

# 3. Add to nodes.yaml
# 4. Generate and apply config
task configure
task talos:generate-config
task talos:apply-node IP=<ip>

# 5. Bootstrap first control plane (only once)
task bootstrap:talos
```

### Configuration Updates

```bash
# 1. Modify templates or nodes.yaml
# 2. Regenerate
task configure
task talos:generate-config

# 3. Apply (mode: auto, reboot, no-reboot, staged)
task talos:apply-node IP=<ip> MODE=auto
```

### Upgrades

**Talos Version:**

```bash
# 1. Update talenv.yaml
talosVersion: v1.x.y

# 2. Upgrade one node at a time
task talos:generate-config
task talos:upgrade-node IP=192.168.1.10
# Wait for ready
task talos:upgrade-node IP=192.168.1.11
# Repeat...
```

**Kubernetes Version:**

```bash
# 1. Update talenv.yaml
kubernetesVersion: v1.x.y

# 2. Single command upgrades all
task talos:upgrade-k8s
```

## Schematic System

Talos uses "schematics" to customize boot images with extensions.

### Obtaining Schematic ID

1. Go to [Talos Image Factory](https://factory.talos.dev/)
2. Select Talos version
3. Choose extensions (qemu-guest-agent, iscsi-tools, etc.)
4. Generate → Copy 64-character schematic ID

### nodes.yaml

```yaml
nodes:
  - name: k8s-node-1
    schematic_id: "a1b2c3d4..."  # 64-char hex
```

### Common Extensions

| Extension | Purpose |
| ----------- | --------- |
| qemu-guest-agent | VM integration |
| iscsi-tools | iSCSI storage |
| intel-ucode | Intel CPU microcode |
| amd-ucode | AMD CPU microcode |

## Security Features

### Secure Boot

```yaml
# nodes.yaml
- name: k8s-node-1
  secureboot: true
```

Requires:

- UEFI Secure Boot enabled
- Talos Secure Boot image

### Disk Encryption

```yaml
# nodes.yaml
- name: k8s-node-1
  encrypt_disk: true
```

Uses TPM 2.0 for key storage. Data encrypted at rest.

## Troubleshooting

### Health Check

```bash
talosctl health -n <ip>
```

Shows:

- etcd health
- API server health
- Controller manager health
- Scheduler health

### Services

```bash
talosctl services -n <ip>
```

Key services:

- `apid` - Talos API
- `etcd` - etcd (controllers only)
- `kubelet` - Kubernetes kubelet
- `containerd` - Container runtime

### Logs

```bash
# Kernel logs
talosctl dmesg -n <ip>

# Service logs
talosctl logs -n <ip> kubelet
talosctl logs -n <ip> etcd
```

### Etcd Operations

```bash
# Status
talosctl etcd status -n <cp-ip>

# Members
talosctl etcd members -n <cp-ip>

# Manual snapshot (one-time backup)
talosctl etcd snapshot db.snapshot -n <cp-ip>
```

## Automated Etcd Backup (Talos Backup)

Talos Backup provides automated, encrypted etcd snapshots to S3-compatible storage. This is the **recommended approach** for production disaster recovery.

### Configuration

Enabled automatically when both `backup_s3_endpoint` and `backup_s3_bucket` are set in `cluster.yaml`:

```yaml
# Option A: Internal RustFS (when rustfs_enabled: true)
backup_s3_endpoint: "http://rustfs-svc.storage.svc.cluster.local:9000"
backup_s3_bucket: "etcd-backups"

# Option B: External Cloudflare R2 (true disaster recovery)
backup_s3_endpoint: "https://<account-id>.r2.cloudflarestorage.com"
backup_s3_bucket: "cluster-backups"
```

### Derived Variables

- `talos_backup_enabled` - True when endpoint + bucket configured
- `backup_s3_internal` - True when endpoint contains `.svc.cluster.local`

Internal RustFS automatically sets `S3_FORCE_PATH_STYLE=true` and `S3_USE_SSL=false`.

### Components

| Component | Description |
| --------- | ----------- |
| `talos.dev/v1alpha1/ServiceAccount` | Grants `os:etcd:backup` role to backup pod |
| `HelmRelease` | Deploys talos-backup chart |
| `Secret` | Age public key + S3 credentials (SOPS encrypted) |

### IAM for RustFS

When using internal RustFS, create credentials via Console UI:

1. Create `backup-storage` policy (Identity → Policies)
2. Create `backups` group with policy attached
3. Create user in group, generate access key

See: `docs/guides/talos-backup-rustfs-implementation.md`

### Verification

```bash
# Check backup pod
kubectl -n kube-system get pods -l app.kubernetes.io/name=talos-backup

# Check backup logs
kubectl -n kube-system logs -l app.kubernetes.io/name=talos-backup

# List backups in RustFS
kubectl -n storage exec -it deploy/rustfs -- mc ls local/etcd-backups
```

### Reset Operations

```bash
# Graceful reset
talosctl reset --nodes <ip>

# Force reset (stuck node)
talosctl reset --nodes <ip> --graceful=false
```

## API Reference

Common `talosctl` commands:

| Command | Description |
| --------- | ------------- |
| `health` | Check node health |
| `services` | List services |
| `dmesg` | Kernel logs |
| `logs <svc>` | Service logs |
| `get disks` | List disks |
| `get links` | List NICs |
| `apply-config` | Apply configuration |
| `upgrade` | Upgrade Talos |
| `reset` | Reset to maintenance |
| `etcd status` | Etcd health |
| `etcd members` | Etcd membership |
| `etcd snapshot` | Backup etcd |

## Environment

Required environment variables:

```bash
TALOSCONFIG=./talos/clusterconfig/talosconfig
```

Set automatically by Taskfile and mise.

---

**Last Updated:** January 13, 2026
**Talos Version:** v1.12.1
**Kubernetes Version:** v1.35.0
**talhelper Version:** v3.1.0
