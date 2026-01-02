# Talos Operations Guide

> Deep-dive documentation for AI assistants working with Talos Linux in this project.

## Overview

Talos Linux v1.12.0 is an immutable, API-driven Kubernetes OS. There is no SSH, no shell, and no package manager. All configuration is done via the Talos API using `talosctl`.

## Architecture

### Talos Principles

1. **Immutable**: Read-only root filesystem
2. **API-Driven**: All config via gRPC API
3. **Secure**: No SSH, no shell, minimal attack surface
4. **Declarative**: Configuration as YAML

### Node Types

- **Controller**: Runs control plane (etcd, API server, scheduler, controller-manager)
- **Worker**: Runs workloads only (optional in this project)

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
talosVersion: v1.12.0
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

**Cluster Configuration** (global):
```yaml
cluster:
  network:
    cni:
      name: none  # Cilium provides CNI
    podSubnets:
      - 10.42.0.0/16
    serviceSubnets:
      - 10.43.0.0/16
  proxy:
    disabled: true  # Cilium replaces kube-proxy
```

**Machine Configuration** (global):
```yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: "true"
  network:
    nameservers:
      - 1.1.1.1
      - 1.0.0.1
  time:
    servers:
      - 162.159.200.1
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

# Snapshot (backup)
talosctl etcd snapshot db.snapshot -n <cp-ip>
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
