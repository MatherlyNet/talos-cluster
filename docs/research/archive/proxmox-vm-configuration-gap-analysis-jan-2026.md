# Proxmox VM Configuration Gap Analysis

**Date**: January 2026
**Status**: ✅ Implementation Complete
**Priority**: High - Infrastructure Configuration

## Overview

This document analyzes the gap between a deployed Proxmox VM configuration and the implemented configuration options in the cluster template. The goal is to ensure complete coverage of all necessary VM settings for Talos Linux nodes.

## Reference: Deployed VM Configuration

Source: `local_docs/archive/proxmox_vm_config.md` (from `qm config 2001`)

```ini
agent: 1
balloon: 0
bios: ovmf
boot: order=scsi0;ide2;net0
cores: 4
cpu: host
efidisk0: local-zfs:vm-2001-disk-0,efitype=4m,size=1M
ide2: local:iso/talos-v1-12nocloud-amd64.iso,media=cdrom,size=308556K
machine: q35
memory: 8192
name: talos-cplane-001
net0: virtio=BC:24:11:62:36:54,bridge=vmbr0,queues=4,tag=7
numa: 1
ostype: l26
scsi0: local-zfs:vm-2001-disk-1,backup=0,discard=on,replicate=0,size=256G,ssd=1
scsihw: virtio-scsi-pci
sockets: 1
startup: order=4,up=15,down=60
tags: kubernetes;linux;talos;template
```

## Configuration Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CONFIGURATION FLOW                                   │
└─────────────────────────────────────────────────────────────────────────────┘

  cluster.yaml                    nodes.yaml
  ─────────────                   ──────────
  • proxmox_api_url               • name, address, mac_addr
  • proxmox_node                  • vm_cores, vm_sockets
  • proxmox_vm_defaults           • vm_memory, vm_disk_size
  • proxmox_vm_controller_defaults• vm_startup_order
  • proxmox_vm_worker_defaults    • vm_startup_delay
  • proxmox_vm_advanced           • mtu (optional)
  • node_vlan_tag
         │                               │
         └───────────┬───────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │     plugin.py         │
         │  ───────────────────  │
         │  PROXMOX_VM_DEFAULTS  │
         │  PROXMOX_VM_CONTROLLER│
         │  PROXMOX_VM_WORKER    │
         │  PROXMOX_VM_ADVANCED  │
         │                       │
         │  Merge Logic:         │
         │  global → role → user │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  cluster.schema.cue   │
         │  nodes.schema.cue     │
         │  ───────────────────  │
         │  Validation Rules     │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  terraform.tfvars.j2  │
         │  ───────────────────  │
         │  • vm_defaults        │
         │  • vm_controller_def  │
         │  • vm_worker_defaults │
         │  • vm_advanced        │
         │  • nodes[]            │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │     main.tf.j2        │
         │  ───────────────────  │
         │  (PLACEHOLDER ONLY)   │
         │  No VM module exists  │
         └───────────────────────┘
```

## Implementation Status

### Fully Implemented Options

| Deployed Setting | Implementation Location | Variable Name | Default Value |
| ----------------- | ------------------------ | --------------- | --------------- |
| `agent: 1` | `plugin.py` PROXMOX_VM_ADVANCED | `qemu_agent` | `True` |
| `balloon: 0` | `plugin.py` PROXMOX_VM_ADVANCED | `balloon` | `0` |
| `bios: ovmf` | `plugin.py` PROXMOX_VM_ADVANCED | `bios` | `"ovmf"` |
| `cores: 4` | `plugin.py` Role defaults | `cores` | 4 (ctrl) / 8 (worker) |
| `cpu: host` | `plugin.py` PROXMOX_VM_ADVANCED | `cpu_type` | `"host"` |
| `machine: q35` | `plugin.py` PROXMOX_VM_ADVANCED | `machine` | `"q35"` |
| `memory: 8192` | `plugin.py` Role defaults | `memory` | 8192 (ctrl) / 16384 (worker) |
| `numa: 1` | `plugin.py` PROXMOX_VM_ADVANCED | `numa` | `True` |
| `sockets: 1` | `plugin.py` Role defaults | `sockets` | `1` |
| `scsihw: virtio-scsi-pci` | `plugin.py` PROXMOX_VM_ADVANCED | `scsi_hw` | `"virtio-scsi-pci"` |
| `net0: queues=4` | `plugin.py` PROXMOX_VM_ADVANCED | `net_queues` | `4` |
| `scsi0: discard=on` | `plugin.py` PROXMOX_VM_ADVANCED | `disk_discard` | `True` |
| `scsi0: ssd=1` | `plugin.py` PROXMOX_VM_ADVANCED | `disk_ssd` | `True` |
| `tags: ...` | `plugin.py` PROXMOX_VM_ADVANCED | `tags` | `["kubernetes", "linux", "talos"]` |
| `net0: tag=7` | `cluster.yaml` | `node_vlan_tag` | (user-defined) |
| `startup: order=4` | `nodes.yaml` | `vm_startup_order` | `loop.index + 3` |
| `startup: up=15` | `nodes.yaml` | `vm_startup_delay` | `15` |

### Missing Options (Gaps)

| Deployed Setting | Priority | Reason | Recommended Default |
| ----------------- | ---------- | -------- | --------------------- |
| `net0: bridge=vmbr0` | **CRITICAL** | Required for network connectivity | `"vmbr0"` |
| `ostype: l26` | IMPORTANT | Linux kernel driver selection | `"l26"` |
| `startup: down=60` | IMPORTANT | Graceful shutdown timing | `60` |
| `scsi0: backup=0` | OPTIONAL | Proxmox backup exclusion | `False` |
| `scsi0: replicate=0` | OPTIONAL | Proxmox replication flag | `False` |

### Auto-Handled Options (No Configuration Needed)

| Deployed Setting | Reason |
| ----------------- | -------- |
| `boot: order=scsi0;ide2;net0` | Automatically set by Proxmox based on disk/ISO config |
| `efidisk0: ...` | Implied by `bios: ovmf` UEFI selection |
| `ide2: ...iso...` | ISO attachment handled during provisioning workflow |
| `smbios1: uuid=...` | Auto-generated by Proxmox |
| `vmgenid: ...` | Auto-generated by Proxmox |
| `meta: ...` | Proxmox metadata, auto-managed |

## Gap Details

### 1. Network Bridge (CRITICAL)

**Current State**: Not configurable
**Impact**: VMs cannot connect to network without bridge specification
**Deployed Value**: `bridge=vmbr0`

The network bridge is essential for VM network connectivity. Without it, Proxmox doesn't know which bridge interface to attach the VM's NIC to.

**Recommendation**: Add to `PROXMOX_VM_ADVANCED`
```python
"network_bridge": "vmbr0",
```

### 2. OS Type (IMPORTANT)

**Current State**: Not configurable
**Impact**: Affects kernel module and driver selection
**Deployed Value**: `l26` (Linux 2.6/3.x/4.x/5.x/6.x kernel)

Proxmox uses `ostype` to optimize QEMU settings for the guest OS. For Talos Linux, `l26` is correct.

**Recommendation**: Add to `PROXMOX_VM_ADVANCED`
```python
"ostype": "l26",
```

### 3. Shutdown Delay (IMPORTANT)

**Current State**: Only startup delay (`up`) is configurable
**Impact**: May cause ungraceful shutdowns during maintenance
**Deployed Value**: `down=60` (60 seconds)

The shutdown delay allows Talos to properly drain workloads and shut down gracefully.

**Recommendation**: Add to nodes.yaml schema alongside `vm_startup_delay`
```yaml
vm_shutdown_delay?: int & >=0 & <=300
```

### 4. Disk Backup Flag (OPTIONAL)

**Current State**: Not configurable
**Impact**: VMs included in Proxmox backup jobs by default
**Deployed Value**: `backup=0` (excluded)

For Talos nodes, disk backup is typically unnecessary since the OS is immutable and cluster state is in etcd.

**Recommendation**: Add to `PROXMOX_VM_ADVANCED`
```python
"disk_backup": False,
```

### 5. Disk Replicate Flag (OPTIONAL)

**Current State**: Not configurable
**Impact**: Disks may be included in Proxmox replication
**Deployed Value**: `replicate=0` (disabled)

Kubernetes handles HA at the application layer, so Proxmox replication is typically disabled.

**Recommendation**: Add to `PROXMOX_VM_ADVANCED`
```python
"disk_replicate": False,
```

## Recommended Changes

### 1. Update `templates/scripts/plugin.py`

```python
# Line 168-181: Update PROXMOX_VM_ADVANCED
PROXMOX_VM_ADVANCED = {
    "bios": "ovmf",
    "machine": "q35",
    "cpu_type": "host",
    "scsi_hw": "virtio-scsi-pci",
    "balloon": 0,
    "numa": True,
    "qemu_agent": True,
    "net_queues": 4,
    "disk_discard": True,
    "disk_ssd": True,
    "tags": ["kubernetes", "linux", "talos"],
    # NEW: Missing options
    "network_bridge": "vmbr0",      # CRITICAL: Network connectivity
    "ostype": "l26",                # IMPORTANT: Linux kernel type
    "disk_backup": False,           # OPTIONAL: Exclude from Proxmox backups
    "disk_replicate": False,        # OPTIONAL: Disable Proxmox replication
}
```

### 2. Update `.taskfiles/template/resources/cluster.schema.cue`

```cue
// Line 104-116: Add new fields to proxmox_vm_advanced
proxmox_vm_advanced?: {
    bios?:           *"ovmf" | "seabios"
    machine?:        *"q35" | "i440fx"
    cpu_type?:       *"host" | string & !=""
    scsi_hw?:        *"virtio-scsi-pci" | "virtio-scsi-single" | "lsi"
    balloon?:        *0 | int & >=0
    numa?:           *true | bool
    qemu_agent?:     *true | bool
    net_queues?:     *4 | int & >=1 & <=16
    disk_discard?:   *true | bool
    disk_ssd?:       *true | bool
    tags?: [...string]
    // NEW: Missing options
    network_bridge?: *"vmbr0" | string & !=""
    ostype?:         *"l26" | "l24" | "win10" | "win11" | string & !=""
    disk_backup?:    *false | bool
    disk_replicate?: *false | bool
}
```

### 3. Update `.taskfiles/template/resources/nodes.schema.cue`

```cue
// Line 35: Add shutdown delay
vm_startup_order?: int & >=1 & <=100
vm_startup_delay?: int & >=0 & <=300
vm_shutdown_delay?: *60 | int & >=0 & <=600  // NEW
```

### 4. Update `templates/config/infrastructure/tofu/terraform.tfvars.j2`

```hcl
// Line 50-62: Add new vm_advanced fields
vm_advanced = {
  bios           = "#{ proxmox_vm_advanced.bios }#"
  machine        = "#{ proxmox_vm_advanced.machine }#"
  cpu_type       = "#{ proxmox_vm_advanced.cpu_type }#"
  scsi_hw        = "#{ proxmox_vm_advanced.scsi_hw }#"
  balloon        = #{ proxmox_vm_advanced.balloon }#
  numa           = #{ proxmox_vm_advanced.numa | lower }#
  qemu_agent     = #{ proxmox_vm_advanced.qemu_agent | lower }#
  net_queues     = #{ proxmox_vm_advanced.net_queues }#
  disk_discard   = #{ proxmox_vm_advanced.disk_discard | lower }#
  disk_ssd       = #{ proxmox_vm_advanced.disk_ssd | lower }#
  tags           = [#% for tag in proxmox_vm_advanced.tags %#"#{ tag }#"#% if not loop.last %#, #% endif %##% endfor %#]
  # NEW: Missing options
  network_bridge = "#{ proxmox_vm_advanced.network_bridge }#"
  ostype         = "#{ proxmox_vm_advanced.ostype }#"
  disk_backup    = #{ proxmox_vm_advanced.disk_backup | lower }#
  disk_replicate = #{ proxmox_vm_advanced.disk_replicate | lower }#
}

// Per-node: Add shutdown delay
#% for node in nodes %#
  {
    ...
    vm_startup_delay  = #{ node.vm_startup_delay | default(15) }#
    vm_shutdown_delay = #{ node.vm_shutdown_delay | default(60) }#  # NEW
    ...
  },
#% endfor %#
```

## Architecture Note: VM Module Not Implemented

The current `main.tf.j2` is a **placeholder** containing only commented example code. No actual Proxmox VM resources are defined.

```hcl
# Current state (templates/config/infrastructure/tofu/main.tf.j2)
# module "talos_nodes" {
#   source = "./modules/talos-vm"
#   for_each = { for node in var.nodes : node.name => node }
#   ...
# }
```

**Status**: Configuration preparation is ~85% complete, but the actual VM provisioning module needs to be implemented.

**Next Steps**:
1. Implement the missing configuration options (this document)
2. Create the Proxmox VM module (`modules/talos-vm/`)
3. Wire up the module in `main.tf.j2`
4. Test with `task infra:plan`

## Implementation Priority

| Priority | Item | Effort | Impact |
| ---------- | ------ | -------- | -------- |
| P0 | Add `network_bridge` | 10 min | Critical for networking |
| P1 | Add `ostype` | 5 min | Proper driver selection |
| P1 | Add `vm_shutdown_delay` | 15 min | Graceful maintenance |
| P2 | Add `disk_backup` | 5 min | Backup control |
| P2 | Add `disk_replicate` | 5 min | Replication control |
| P3 | Create VM module | 2-4 hours | Enable provisioning |

## Validation Checklist

After implementing changes:

- [ ] Run `cue vet` on updated schema files
- [ ] Run `task configure` to regenerate templates # DO *NOT* run task configure yet
- [ ] Verify `infrastructure/tofu/terraform.tfvars` contains new fields
- [ ] Run `task infra:validate` to check OpenTofu syntax
- [ ] Update `docs/CONFIGURATION.md` with new options

## References

- [Proxmox QEMU/KVM VM Options](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines)
- [bpg/proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Talos on Proxmox Guide](https://www.talos.dev/latest/talos-guides/install/virtualized-platforms/proxmox/)
- Project docs: `docs/CONFIGURATION.md`, `docs/ai-context/infrastructure-opentofu.md`
