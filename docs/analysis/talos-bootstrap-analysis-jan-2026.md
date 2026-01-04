# Talos Bootstrap Analysis - January 2026

## Executive Summary

Analysis of Talos cluster bootstrap issues with VMs in MAINTENANCE stage. Five new/modified Talos patch templates were reviewed and one critical issue was identified and **FIXED**.

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
**Purpose:** Forward Talos kernel/service logs to Vector via UDP

**Configuration:** (Conditional on `talos_system_logs_enabled`)
```yaml
#% if talos_system_logs_enabled %#
machine:
  install:
    extraKernelArgs:
      - talos.logging.kernel=udp://127.0.0.1:6050
  logging:
    destinations:
      - endpoint: "udp://127.0.0.1:6051"
        format: json_lines
#% endif %#
```

**Assessment:** ✅ **FIXED** - Changed conditional from `talos_system_logs_enabled` to `loki_enabled`

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

## Critical Issues Identified

### ISSUE #1: `machine-logging.yaml` File Not Generated (CRITICAL - Bootstrap Blocker)

**Symptom:** When running `talhelper genconfig`, it will fail with "file not found" for `machine-logging.yaml`

**Root Cause:**
1. The template `machine-logging.yaml.j2` is wrapped in a conditional:
   ```jinja2
   #% if talos_system_logs_enabled %#
   ...content...
   #% endif %#
   ```
2. The variable `talos_system_logs_enabled` is **NOT DEFINED** anywhere:
   - Not in `cluster.yaml`
   - Not in `plugin.py` defaults
3. When undefined, the conditional evaluates to `false` (due to `undefined = "chainable"` in makejinja.toml)
4. The template produces **no output**, so makejinja doesn't create the file
5. However, `talos_patches('global')` in `talconfig.yaml.j2` still includes it in the patch list

**Evidence:**
```bash
$ ls talos/patches/global/
machine-cloud-provider.yaml  machine-kubelet.yaml  machine-sysctls.yaml
machine-dns.yaml             machine-network.yaml  machine-time.yaml
machine-files.yaml
# machine-logging.yaml is MISSING
```

But `talconfig.yaml` references it:
```yaml
patches:
  - "@./patches/global/machine-cloud-provider.yaml"
  - "@./patches/global/machine-dns.yaml"
  - "@./patches/global/machine-files.yaml"
  - "@./patches/global/machine-kubelet.yaml"
  - "@./patches/global/machine-logging.yaml"  # ← FILE DOES NOT EXIST
  - "@./patches/global/machine-network.yaml"
  - "@./patches/global/machine-sysctls.yaml"
  - "@./patches/global/machine-time.yaml"
```

**Fix Options:**

**Option A (Recommended):** Modify `machine-logging.yaml.j2` to always generate valid output
```yaml
#| Talos Logging Configuration #|
#% if talos_system_logs_enabled | default(false) %#
machine:
  install:
    extraKernelArgs:
      - talos.logging.kernel=udp://127.0.0.1:6050
  logging:
    destinations:
      - endpoint: "udp://127.0.0.1:6051"
        format: json_lines
#% else %#
#| Logging disabled - placeholder for valid YAML #|
{}
#% endif %#
```

**Option B:** Add default to `plugin.py`:
```python
data.setdefault("talos_system_logs_enabled", False)
```
Then update template to output empty dict `{}` when disabled.

**Option C:** Add `talos_system_logs_enabled: true` to `cluster.yaml` if logging is desired

**Option D:** Create a smart `talos_patches()` function that only returns patches for files that exist after rendering

---

## Network Configuration Validation

| Setting | Value | Status |
|---------|-------|--------|
| `node_cidr` | `192.168.20.0/22` | ✅ Valid /22 subnet |
| `node_default_gateway` | `192.168.23.254` | ✅ In range |
| `cluster_api_addr` | `192.168.22.100` | ✅ VIP for control plane |
| `cluster_pod_cidr` | `10.42.0.0/16` | ✅ No overlap |
| `cluster_svc_cidr` | `10.43.0.0/16` | ✅ No overlap |
| `proxmox_vlan_mode` | `true` | ✅ Proxmox handles VLAN tagging |
| `node_vlan_tag` | `7` | ✅ VLAN 7 (Proxmox access port mode) |

**Node IP Addresses:**
| Node | IP | Subnet Match |
|------|-----|--------------|
| matherlynet-cp-1 | 192.168.22.101/22 | ✅ |
| matherlynet-cp-2 | 192.168.22.102/22 | ✅ |
| matherlynet-cp-3 | 192.168.22.103/22 | ✅ |
| matherlynet-wrkr-1 | 192.168.22.111/22 | ✅ |
| matherlynet-wrkr-2 | 192.168.22.112/22 | ✅ |
| matherlynet-wrkr-3 | 192.168.22.113/22 | ✅ |

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

1. **Fix the `machine-logging.yaml` issue** (Critical - blocks bootstrap)
   - Choose Option A, B, C, or D from the fix options above

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

## Template Documentation Updates Required

The following documentation should be updated to reflect the new templates:

1. **CLAUDE.md** - Add `talos_system_logs_enabled` to Optional Configuration section
2. **docs/CONFIGURATION.md** - Document the new Talos logging configuration
3. **docs/ai-context/talos-operations.md** - Add logging configuration patterns

---

## References

- [Talos Host DNS Documentation](https://docs.siderolabs.com/talos/v1.11/networking/host-dns)
- [Cilium eBPF Host Routing Issue](https://github.com/cilium/cilium/issues/36761)
- [Talos forwardKubeDNSToHost PR](https://github.com/siderolabs/talos/pull/9200)
- [Talos Logging Documentation](https://docs.siderolabs.com/talos/v1.11/configure-your-talos-cluster/logging-and-telemetry/logging)
- [Kubernetes ImageVolume Feature Gate](https://kubernetes.io/docs/concepts/storage/volumes/#image)
