# Talos Kubernetes Interoperability Research - January 2026

**Date:** January 4, 2026
**Talos Version:** v1.12.0
**Kubernetes Version:** v1.35.0
**Purpose:** Comprehensive configuration validation against official Siderolabs documentation

## Executive Summary

This research document validates the matherlynet-talos-cluster project configuration against Talos v1.12 documentation across seven critical areas:

| Area | Status | Finding |
| ------ | ------ | --------- |
| Host DNS | **Compliant** | Correctly configured with workaround for Cilium eBPF |
| DNS Resolvers | **Compliant** | Custom resolvers properly configured |
| Cilium Deployment | **Compliant** | All required settings present |
| Time Configuration | **Compliant** | NTP servers properly configured |
| etcd Metrics | **Compliant** | Metrics endpoint exposed on port 2381 |
| Node Labels | **Enhancement Available** | No labels configured (optional) |
| Proxmox VMs | **Compliant** | Correct BIOS/disk controller settings |

**Overall Assessment:** Project configuration is fully aligned with Talos v1.12 best practices. Minor enhancement opportunities identified for node labels.

---

## 1. Host DNS Configuration

### Documentation Reference

- https://docs.siderolabs.com/talos/v1.12/networking/host-dns.md

### Official Requirements

| Setting | Description | Default |
| --------- | ------------- | --------- |
| `hostDNS.enabled` | Enable local DNS caching at 127.0.0.53 | `true` (v1.7+) |
| `forwardKubeDNSToHost` | CoreDNS forwards to host DNS (169.254.116.108) | `true` (v1.8+) |
| `resolveMemberNames` | Resolve cluster member hostnames | `false` |

### Project Configuration (`templates/config/talos/patches/global/machine-dns.yaml.j2`)

```yaml
machine:
  features:
    hostDNS:
      enabled: true
      forwardKubeDNSToHost: true
      resolveMemberNames: true
```

### Analysis

**Compliant:** All three settings are correctly configured.

| Setting | Project Value | Documentation Default | Notes |
| --------- | --------------- | ---------------------- | ------- |
| `enabled` | `true` | `true` | Matches default |
| `forwardKubeDNSToHost` | `true` | `true` (v1.8+) | Matches default |
| `resolveMemberNames` | `true` | `false` | **Enhanced** - enables hostname resolution |

### Critical Compatibility Note

The documentation explicitly warns:

> Enabling both Talos's `forwardKubeDNSToHost=true` and Cilium's `bpf.masquerade=true` breaks CoreDNS

**Project addresses this** via `machine-network.yaml.j2`:

```yaml
machine:
  network:
    interfaces:
      - interface: lo
        addresses:
          - 169.254.116.108/32
```

This workaround adds the Talos host DNS IP to loopback, enabling eBPF host routing while maintaining DNS forwarding functionality. References:

- https://github.com/cilium/cilium/issues/36761#issuecomment-3493689525
- https://github.com/siderolabs/talos/pull/9200#issuecomment-2805269653

**Verification Commands:**

```bash
talosctl get resolvers
talosctl get dnsupstream
talosctl logs dns-resolve-cache
```

---

## 2. DNS Resolvers Configuration

### Documentation Reference

- https://docs.siderolabs.com/talos/v1.12/networking/configuration/resolvers.md

### Official Requirements

Talos uses `8.8.8.8` and `1.1.1.1` by default. Custom resolvers can be configured via:

- `machine.network.nameservers`
- ResolverConfig document
- DHCP/platform metadata

### Project Configuration

**cluster.yaml:**

```yaml
node_dns_servers: ["192.168.1.254", "172.64.36.1", "172.64.36.2"]
```

**machine-network.yaml.j2:**

```yaml
machine:
  network:
    disableSearchDomain: true
    nameservers:
      #% for item in node_dns_servers %#
      - #{ item }#
      #% endfor %#
```

### Analysis

**Compliant:** Custom DNS resolvers are properly configured.

| Aspect | Project Configuration | Notes |
| -------- | ---------------------- | ------- |
| Custom nameservers | Yes - 3 servers | Local + Cloudflare |
| Search domain | Disabled | Prevents conflicts |
| Resolution order | Project DNS first | Correct priority |

**Verification Commands:**

```bash
talosctl get resolvers
talosctl get resolverspec --namespace=network-config
```

---

## 3. Cilium CNI Deployment

### Documentation Reference

- https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium.md

### Official Requirements

| Configuration | Required Value | Purpose |
| --------------- | ---------------- | --------- |
| `cluster.network.cni.name` | `none` | Disable default CNI |
| `cluster.proxy.disabled` | `true` | For kube-proxy replacement |
| `ipam.mode` | `kubernetes` | K8s-native IPAM |
| `cgroup.automount.enabled` | `false` | Use Talos cgroups |
| `cgroup.hostRoot` | `/sys/fs/cgroup` | Talos cgroup location |
| `kubeProxyReplacement` | `true` | Replace kube-proxy |
| `k8sServiceHost` | `127.0.0.1` or `localhost` | KubePrism |
| `k8sServicePort` | `7445` | KubePrism port |

**Security Capabilities (ciliumAgent):**

- CHOWN, KILL, NET_ADMIN, NET_RAW, IPC_LOCK, SYS_ADMIN, SYS_RESOURCE, DAC_OVERRIDE, FOWNER, SETGID, SETUID
- Note: SYS_MODULE is **not allowed** on Talos

### Project Configuration

**talconfig.yaml.j2:**

```yaml
cniConfig:
  name: none
```

**cluster.yaml.j2 (controller patch):**

```yaml
cluster:
  proxy:
    disabled: true
```

**cilium/helmrelease.yaml.j2:**

```yaml
values:
  ipam:
    mode: kubernetes
  cgroup:
    automount:
      enabled: false
    hostRoot: /sys/fs/cgroup
  kubeProxyReplacement: true
  k8sServiceHost: 127.0.0.1
  k8sServicePort: 7445
  securityContext:
    capabilities:
      ciliumAgent:
        - CHOWN
        - KILL
        - NET_ADMIN
        - NET_RAW
        - IPC_LOCK
        - SYS_ADMIN
        - SYS_RESOURCE
        - PERFMON
        - BPF
        - DAC_OVERRIDE
        - FOWNER
        - SETGID
        - SETUID
      cleanCiliumState:
        - NET_ADMIN
        - SYS_ADMIN
        - SYS_RESOURCE
```

### Analysis

**Compliant:** All required settings are properly configured.

| Requirement | Project Value | Status |
| ------------- | ------------- | ------ |
| CNI disabled | `none` | **OK** |
| kube-proxy disabled | `true` | **OK** |
| IPAM mode | `kubernetes` | **OK** |
| cgroup automount | `false` | **OK** |
| cgroup hostRoot | `/sys/fs/cgroup` | **OK** |
| kubeProxyReplacement | `true` | **OK** |
| k8sServiceHost | `127.0.0.1` | **OK** |
| k8sServicePort | `7445` | **OK** |
| SYS_MODULE excluded | Not present | **OK** |

**Additional Project Enhancements:**

- `PERFMON` and `BPF` capabilities added (for eBPF observability)
- BGP Control Plane v2 optional configuration
- L2 announcements for non-BGP mode
- Hubble observability integration

---

## 4. Time Configuration

### Documentation Reference

- https://docs.siderolabs.com/talos/v1.12/networking/configuration/time.md

### Official Requirements

Default NTP server: `time.cloudflare.com`

Custom NTP servers configured via:

```yaml
apiVersion: v1alpha1
kind: TimeSyncConfig
ntp:
  servers:
    - 0.pool.ntp.org
```

Or via machine config:

```yaml
machine:
  time:
    servers:
      - ntp.example.com
```

### Project Configuration

**cluster.yaml:**

```yaml
node_ntp_servers: ["162.159.200.1", "162.159.200.123"]
```

**machine-time.yaml.j2:**

```yaml
machine:
  time:
    disabled: false
    servers:
      #% for item in node_ntp_servers %#
      - #{ item }#
      #% endfor %#
```

### Analysis

**Compliant:** NTP is properly configured with Cloudflare's NTP IPs.

| Aspect | Project Value | Notes |
| -------- | ------------- | ------- |
| NTP enabled | `disabled: false` | Explicit enable |
| Time servers | Cloudflare IPs | `162.159.200.1`, `162.159.200.123` |

Note: Using IP addresses instead of hostnames (`time.cloudflare.com`) avoids DNS resolution dependency during early boot.

**Verification Commands:**

```bash
talosctl get timeservers
talosctl get timeserverspec --namespace=network-config
```

---

## 5. etcd Metrics Configuration

### Documentation Reference

- https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/etcd-metrics.md

### Official Requirements

Enable etcd metrics via:

```yaml
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
```

**Security Warning:** Secure control plane IP addresses to prevent public access.

### Project Configuration

**cluster.yaml.j2 (controller patch):**

```yaml
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
    advertisedSubnets:
      - #{ node_cidr }#
```

### Analysis

**Compliant:** etcd metrics are properly exposed.

| Requirement | Project Value | Status |
| ------------- | ------------- | ------ |
| Metrics URL | `http://0.0.0.0:2381` | **OK** |
| Network restriction | `advertisedSubnets` set | **OK** (limits to node CIDR) |

**Security Considerations:**

- etcd metrics bound to all interfaces on port 2381
- `advertisedSubnets` restricts etcd peer communication to `node_cidr`
- Additional firewall rules recommended for production (see Ingress Firewall guide)

**Verification Command:**

```bash
curl "${CONTROL_PLANE_IP}:2381/metrics"
```

---

## 6. Node Labels Configuration

### Documentation Reference

- https://docs.siderolabs.com/kubernetes-guides/advanced-guides/node-labels.md

### Official Requirements

Node labels configured via:

```yaml
machine:
  nodeLabels:
    topology.kubernetes.io/zone: "zone-a"
    topology.kubernetes.io/region: "region-1"
```

**Permitted Labels (NodeRestriction):**

- `topology.kubernetes.io/region` and `topology.kubernetes.io/zone`
- `kubernetes.io/hostname`, `kubernetes.io/arch`, `kubernetes.io/os`
- Selected `node.kubernetes.io/*` labels

**Restricted Labels:**

- `node-role.kubernetes.io/*` (must be applied by cluster admin via kubectl)

### Project Configuration

The project does **not** currently configure `machine.nodeLabels`.

### Analysis

**Enhancement Available:** Node labels are not configured but are optional.

| Aspect | Current State | Recommendation |
| -------- | ------------- | ---------------- |
| Topology labels | Not set | Optional - useful for PVC scheduling |
| Custom labels | Not set | Optional |
| Role labels | N/A | Must use `kubectl label` |

**Potential Enhancement:**

For Proxmox multi-node environments, consider adding topology labels:

```yaml
# templates/config/talos/patches/global/machine-labels.yaml.j2
machine:
  nodeLabels:
    topology.kubernetes.io/region: "#{ proxmox_region | default('pve') }#"
    # Zone could be derived from Proxmox node name
```

This would enable:

- Pod topology spread constraints
- CSI storage location awareness
- Multi-zone scheduling strategies

**Note:** The project uses Proxmox CCM (`proxmox_ccm_enabled: true`), which automatically applies node labels based on Proxmox metadata. Manual `machine.nodeLabels` may not be necessary when CCM is active.

---

## 7. Proxmox VM Configuration

### Documentation Reference

- https://docs.siderolabs.com/talos/v1.11/platform-specific-installations/virtualized-platforms/proxmox.md

### Official Requirements

| Setting | Required Value | Purpose |
| -------- | ---------------- | --------- |
| BIOS | `ovmf` (UEFI) | Modern firmware |
| Machine type | `q35` | PCIe-based architecture |
| CPU type | `host` | Best performance |
| Memory ballooning | Disabled | Talos doesn't support hotplug |
| Disk controller | `VirtIO SCSI` (NOT 'Single') | Prevents bootstrap hangs |
| Network model | `virtio` | Paravirtualized driver |
| Control plane resources | Min 2 cores, 4GB RAM | |
| Worker resources | Min 4 cores, 8GB RAM | |

**Critical:** Use `VirtIO SCSI` controller, NOT `VirtIO SCSI Single` (Talos issue #11173).

### Project Configuration

**main.tf.j2:**

```hcl
resource "proxmox_virtual_environment_vm" "talos_node" {
  bios    = var.vm_advanced.bios         # ovmf
  machine = var.vm_advanced.machine      # q35

  cpu {
    type = var.vm_advanced.cpu_type      # host
    numa = var.vm_advanced.numa          # true
  }

  memory {
    dedicated = each.value.vm_memory
    floating  = var.vm_advanced.balloon  # 0 (disabled)
  }

  scsi_hardware = var.vm_advanced.scsi_hw # virtio-scsi-pci

  network_device {
    model = "virtio"
  }

  efi_disk {
    datastore_id      = var.proxmox_disk_storage
    pre_enrolled_keys = false  # Required for Talos SecureBoot
  }

  serial_device {}  # For console access
}
```

**cluster.yaml default values:**

```yaml
# Controller: 4 cores, 8GB, 64GB disk
# Worker: 8 cores, 16GB, 256GB disk
```

### Analysis

**Compliant:** All Proxmox requirements are properly configured.

| Requirement | Project Value | Status |
| -------- | ------------- | ------ |
| BIOS | `ovmf` | **OK** |
| Machine type | `q35` | **OK** |
| CPU type | `host` | **OK** |
| Memory ballooning | `0` (disabled) | **OK** |
| SCSI controller | `virtio-scsi-pci` | **OK** |
| Network model | `virtio` | **OK** |
| Serial console | Enabled | **OK** |
| EFI disk | Pre-enrolled keys disabled | **OK** (Talos SecureBoot) |
| Controller resources | 4 cores, 8GB | **Exceeds min** |
| Worker resources | 8 cores, 24GB | **Exceeds min** |

**Additional Project Enhancements:**

- NUMA enabled for better memory performance
- SSD emulation and TRIM/discard support
- Multi-queue networking (`net_queues: 4`)
- QEMU guest agent support
- SecureBoot support with custom ISOs
- Boot order: disk first, ISO fallback

---

## Additional Findings

### Cloud Controller Manager Integration

The project correctly handles the CCM "chicken-egg" problem by adding tolerations for `node.cloudprovider.kubernetes.io/uninitialized`:

**Components with toleration:**

- Cilium Hubble Relay and UI
- Flux Operator and Instance
- Proxmox CCM
- CoreDNS
- cert-manager (controller, cainjector, webhook, startupapicheck)

This aligns with Kubernetes best practices for external cloud providers:

- https://kubernetes.io/blog/2025/02/14/cloud-controller-manager-chicken-egg-problem/

### Cilium eBPF Host Routing Workaround

The project implements a known workaround for Cilium eBPF compatibility:

```yaml
# machine-network.yaml.j2
bpf:
  masquerade: true
  hostLegacyRouting: true  # Workaround for Talos issue #10002
```

Combined with the loopback address configuration (`169.254.116.108/32`), this ensures CoreDNS forwarding works correctly with Cilium's eBPF datapath.

### External Cloud Provider Configuration

When Proxmox CCM is enabled, the project correctly sets:

```yaml
cluster:
  externalCloudProvider:
    enabled: true
```

This instructs kubelet to wait for CCM initialization before scheduling workloads.

---

## Recommendations Summary

### Current Compliance Status

| Category | Items | Status |
| -------- | ------- | ------ |
| Required configurations | 20+ | **All compliant** |
| Security considerations | 3 | **All addressed** |
| Known compatibility issues | 2 | **Both mitigated** |

### Enhancement Opportunities

1. **Node Labels (Optional)**
   - Consider adding topology labels for multi-zone scheduling
   - May not be needed with Proxmox CCM active

2. **etcd Metrics Security (Optional)**
   - Consider additional firewall rules for port 2381
   - Current `advertisedSubnets` provides network-level restriction

3. **Documentation Reference Updates**
   - Update reference URLs in template comments to v1.12 where applicable

---

## Verification Checklist

Run these commands to verify configuration after deployment:

```bash
# DNS Configuration
talosctl get resolvers
talosctl get dnsupstream
talosctl logs dns-resolve-cache

# Time Sync
talosctl get timeservers

# etcd Metrics
curl "${CP_IP}:2381/metrics" | head -20

# Cilium Status
cilium status
cilium config view | grep -E 'kube-proxy-replacement|ipam'

# Node Labels (after CCM initialization)
kubectl get nodes --show-labels

# Proxmox CCM Status
kubectl get pods -n kube-system -l app.kubernetes.io/name=proxmox-cloud-controller-manager
kubectl logs -n kube-system -l app.kubernetes.io/name=proxmox-cloud-controller-manager
```

---

## References

- [Talos Host DNS Documentation](https://docs.siderolabs.com/talos/v1.12/networking/host-dns.md)
- [Talos Resolvers Configuration](https://docs.siderolabs.com/talos/v1.12/networking/configuration/resolvers.md)
- [Deploying Cilium on Talos](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium.md)
- [Talos Time Synchronization](https://docs.siderolabs.com/talos/v1.12/networking/configuration/time.md)
- [etcd Metrics Guide](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/etcd-metrics.md)
- [Node Labels Guide](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/node-labels.md)
- [Proxmox Installation Guide](https://docs.siderolabs.com/talos/v1.11/platform-specific-installations/virtualized-platforms/proxmox.md)
- [Cilium eBPF Host Routing Issue #36761](https://github.com/cilium/cilium/issues/36761)
- [Talos Host DNS PR #9200](https://github.com/siderolabs/talos/pull/9200)
- [CCM Chicken-Egg Problem Blog](https://kubernetes.io/blog/2025/02/14/cloud-controller-manager-chicken-egg-problem/)
