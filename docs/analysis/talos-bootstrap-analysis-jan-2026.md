# Talos Bootstrap Analysis - January 2026

## Executive Summary

Analysis of Talos cluster bootstrap issues with VMs in MAINTENANCE stage. Five new/modified Talos patch templates were reviewed and two critical issues were identified and **FIXED**.

## Template Changes Reviewed

### 1. `machine-dns.yaml.j2` (NEW)
**Purpose:** Enable host DNS caching and cluster member name resolution

**Configuration:**
```yaml
machine:
  features:
    hostDNS:
      enabled: true
      forwardKubeDNSToHost: true
      resolveMemberNames: true
```

**Assessment:** ✅ **VALID**
- Enables local DNS caching at 127.0.0.53
- Forwards CoreDNS queries through host DNS (default since Talos 1.8+)
- Enables hostname resolution for cluster members (e.g., `matherlynet-cp-1` → `192.168.22.101`)
- REF: https://docs.siderolabs.com/talos/v1.11/networking/host-dns

### 2. `machine-kubelet.yaml.j2` (MODIFIED)
**Change:** Added ImageVolume feature gate

**Configuration:**
```yaml
machine:
  kubelet:
    extraArgs:
      feature-gates: ImageVolume=true
    extraConfig:
      serializeImagePulls: false
    nodeIP:
      validSubnets:
        - #{ node_cidr }#
```

**Assessment:** ✅ **VALID**
- ImageVolume feature gate enables CNPG managed extensions
- Matches apiServer feature gate in `controller/cluster.yaml.j2`

### 3. `machine-logging.yaml.j2` (NEW)
**Purpose:** Forward Talos service logs to Vector via UDP

**Configuration:** (Conditional on `loki_enabled`)
```yaml
#% if loki_enabled | default(false) %#
machine:
  logging:
    destinations:
      - endpoint: "udp://127.0.0.1:6051"
        format: json_lines
#% endif %#
```

**Assessment:** ✅ **FIXED** (see Issues #1 and #2 below)

### 4. `machine-network.yaml.j2` (MODIFIED)
**Change:** Added loopback address for Cilium eBPF host routing workaround

**Configuration:**
```yaml
machine:
  network:
    disableSearchDomain: true
    nameservers:
      - 172.64.36.1
      - 172.64.36.2
      - 192.168.1.254
    interfaces:
      - interface: lo
        addresses:
          - 169.254.116.108/32
```

**Assessment:** ✅ **VALID**
- Workaround for Cilium eBPF host routing with Talos `forwardKubeDNSToHost`
- Adds Talos host DNS IP (169.254.116.108) to loopback interface
- REF: https://github.com/cilium/cilium/issues/36761#issuecomment-3493689525
- REF: https://github.com/siderolabs/talos/pull/9200#issuecomment-2805269653

### 5. `controller/cluster.yaml.j2` (MODIFIED)
**Change:** Added ImageVolume feature gate to apiServer

**Configuration:**
```yaml
cluster:
  apiServer:
    extraArgs:
      enable-aggregator-routing: true
      feature-gates: ImageVolume=true
```

**Assessment:** ✅ **VALID**
- Enables ImageVolume feature gate for CNPG managed extensions
- Must match kubelet feature gate (which it does)

---

## Critical Issues Identified and Fixed

### ISSUE #1: `machine-logging.yaml` File Not Generated ✅ FIXED

**Symptom:** When running `talhelper genconfig`, it would fail with "file not found" for `machine-logging.yaml`

**Root Cause:**
1. The template `machine-logging.yaml.j2` was wrapped in a conditional:
   ```jinja2
   #% if talos_system_logs_enabled %#
   ...content...
   #% endif %#
   ```
2. The variable `talos_system_logs_enabled` was **NOT DEFINED** anywhere
3. When undefined, the conditional evaluated to `false`, producing no output
4. However, `talos_patches('global')` still included it in the patch list

**Fix Applied:**
Changed the conditional from `talos_system_logs_enabled` to `loki_enabled`:
```jinja2
#% if loki_enabled | default(false) %#
```

**Rationale:**
- `loki_enabled: true` is already set in `cluster.yaml`
- Talos system logging feeds into Vector/Alloy → Loki pipeline
- When Loki is enabled, Talos logging should also be enabled
- This maintains consistency with the existing observability stack configuration

---

### ISSUE #2: SecureBoot/UKI Conflict with extraKernelArgs ✅ FIXED

**Symptom:** Bootstrap failed with error:
```
install.extraKernelArgs and install.grubUseUKICmdline can't be used together
```

**Root Cause:**
1. Talos v1.12.0 defaults to `grubUseUKICmdline: true` for SecureBoot images
2. With UKI (Unified Kernel Image) mode, kernel command line arguments are embedded at build time
3. Runtime `machine.install.extraKernelArgs` in config conflicts with this mode
4. The original template had:
   ```yaml
   machine:
     install:
       extraKernelArgs:
         - talos.logging.kernel=udp://127.0.0.1:6050
   ```

**Fix Applied:**
1. Created new Image Factory schematic with kernel logging embedded:
   ```yaml
   customization:
     extraKernelArgs:
       - talos.logging.kernel=udp://127.0.0.1:6050
     systemExtensions:
       officialExtensions:
         - siderolabs/qemu-guest-agent
   ```

2. New schematic ID: `a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca`
   - Previous: `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`

3. Updated `nodes.yaml` with new schematic ID for all 6 nodes

4. Removed `machine.install.extraKernelArgs` from template:
   ```yaml
   # Before (conflicting)
   machine:
     install:
       extraKernelArgs:
         - talos.logging.kernel=udp://127.0.0.1:6050
     logging:
       destinations:
         - endpoint: "udp://127.0.0.1:6051"
           format: json_lines

   # After (fixed)
   machine:
     logging:
       destinations:
         - endpoint: "udp://127.0.0.1:6051"
           format: json_lines
   ```

**Technical Details:**
- With SecureBoot/UKI mode, kernel args must be baked into the schematic via Image Factory
- The schematic is retrieved at boot time and contains the embedded kernel command line
- Runtime config can only modify `machine.logging` section, not `machine.install.extraKernelArgs`
- REF: https://docs.siderolabs.com/talos/v1.12/configure-your-talos-cluster/logging-and-telemetry/logging

---

## Network Configuration Validation

| Setting | Value | Status |
| --------- | ------- | -------- |
| `node_cidr` | `192.168.20.0/22` | ✅ Valid /22 subnet |
| `node_default_gateway` | `192.168.23.254` | ✅ In range |
| `cluster_api_addr` | `192.168.22.100` | ✅ VIP for control plane |
| `cluster_pod_cidr` | `10.42.0.0/16` | ✅ No overlap |
| `cluster_svc_cidr` | `10.43.0.0/16` | ✅ No overlap |
| `proxmox_vlan_mode` | `true` | ✅ Proxmox handles VLAN tagging |
| `node_vlan_tag` | `7` | ✅ VLAN 7 (Proxmox access port mode) |

**Node IP Addresses:**

| Node | IP | Subnet Match |
| ------ | ----- | ------------ |
| matherlynet-cp-1 | 192.168.22.101/22 | ✅ |
| matherlynet-cp-2 | 192.168.22.102/22 | ✅ |
| matherlynet-cp-3 | 192.168.22.103/22 | ✅ |
| matherlynet-wrkr-1 | 192.168.22.111/22 | ✅ |
| matherlynet-wrkr-2 | 192.168.22.112/22 | ✅ |
| matherlynet-wrkr-3 | 192.168.22.113/22 | ✅ |

---

## Proxmox Configuration Validation

Per Talos documentation for Proxmox integration:

| Requirement | Status |
| ----------- | ------ |
| QEMU Guest Agent extension | ✅ Included in schematic |
| VirtIO SCSI controller | ✅ Configured in OpenTofu |
| q35 machine type | ✅ Configured in OpenTofu |
| UEFI/OVMF BIOS | ✅ Required for SecureBoot |
| Memory ballooning disabled | ✅ Configured in OpenTofu |

---

## RPC Error Analysis

Based on research, common causes of RPC errors during Talos bootstrap:

### TLS Certificate Errors
- **Cause:** `talosconfig` regenerated with `--force`, overwriting cluster secrets
- **Fix:** Use the existing `talosconfig` or recover from cluster state

### Connection Refused
- **Cause:** Node not reachable on port 50000 (maintenance mode) or 50001 (configured mode)
- **Fix:** Verify network connectivity and firewall rules

### Disk Selector Errors
- **Cause:** `installDiskSelector` doesn't match any disk on the node
- **Fix:** Verify disk serial numbers with `talosctl get disks -n <ip> --insecure`

### Bootstrap Already in Progress
- **Cause:** Bootstrap command issued multiple times
- **Fix:** Wait for bootstrap to complete; only bootstrap ONE control plane node

---

## Recommended Actions

1. **Destroy and recreate VMs** to pick up the new schematic with embedded kernel args:
   ```bash
   task infra:destroy
   task infra:apply
   ```

2. **Verify node connectivity** before bootstrap:
   ```bash
   task infra:verify-nodes
   ```

3. **Bootstrap sequence:**
   ```bash
   # 1. Apply configuration to all nodes
   task talos:apply-node IP=192.168.22.101
   task talos:apply-node IP=192.168.22.102
   task talos:apply-node IP=192.168.22.103
   task talos:apply-node IP=192.168.22.111
   task talos:apply-node IP=192.168.22.112
   task talos:apply-node IP=192.168.22.113

   # 2. Bootstrap ONLY the first control plane node
   task bootstrap:talos

   # 3. Wait for etcd cluster formation (2-5 minutes)
   talosctl -n 192.168.22.101 health

   # 4. Deploy cluster apps
   task bootstrap:apps
   ```

4. **Monitor bootstrap progress:**
   ```bash
   talosctl -n 192.168.22.101 dmesg -f
   talosctl -n 192.168.22.101 service
   ```

---

## Template Documentation Updates

The Talos system logging is now automatically enabled when `loki_enabled: true` is set in `cluster.yaml`.

Key changes:
- Kernel logging (`talos.logging.kernel`) is embedded in the Image Factory schematic
- Service logging (`machine.logging`) is configured via the template when `loki_enabled: true`
- Both send to Vector DaemonSet on localhost (ports 6050 and 6051 respectively)

---

## References

- [Talos Host DNS Documentation](https://docs.siderolabs.com/talos/v1.11/networking/host-dns)
- [Cilium eBPF Host Routing Issue](https://github.com/cilium/cilium/issues/36761)
- [Talos forwardKubeDNSToHost PR](https://github.com/siderolabs/talos/pull/9200)
- [Talos Logging Documentation](https://docs.siderolabs.com/talos/v1.12/configure-your-talos-cluster/logging-and-telemetry/logging)
- [Talos Image Factory](https://factory.talos.dev/)
- [Talos Proxmox Installation Guide](https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/virtualized-platforms/proxmox)
- [Kubernetes ImageVolume Feature Gate](https://kubernetes.io/docs/concepts/storage/volumes/#image)
