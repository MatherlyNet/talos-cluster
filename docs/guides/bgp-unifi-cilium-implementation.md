# BGP Implementation Guide: UniFi Router + Cilium Kubernetes

> **Guide Version:** 2.0.0
> **Last Updated:** January 2026
> **Status:** Implemented | Validated for Cilium 1.19.0-pre.3+ and UniFi OS 4.1.13+ (4.4.6 recommended)

---

## ⚠️ Cilium 1.19 Upgrade Requirements

> **BREAKING CHANGE:** Cilium 1.19 (final release expected February 2026) contains **critical breaking changes** that must be addressed before upgrading. This section documents all required changes for this project.

### Cilium 1.19 Release Status

| Version | Release Date | Status |
| ------- | ------------ | ------ |
| 1.18.5 | December 18, 2025 | **Current Stable** |
| 1.19.0-pre.3 | December 1, 2025 | **Latest Pre-release** |
| 1.19.0 | February 2026 | **Upcoming Final** |

### Breaking Changes Affecting This Project

#### 1. CiliumBGPPeeringPolicy Removed

**Impact:** None - project already uses `CiliumBGPClusterConfig` (BGP Control Plane v2)

The `CiliumBGPPeeringPolicy` CRD and the entire BGPv1 control plane have been **completely removed** in Cilium 1.19. This was deprecated in 1.17 and removed in 1.19.

```yaml
# ❌ REMOVED in 1.19 - Will cause API errors
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy

# ✅ Use instead (project already uses this)
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
```

#### 2. CiliumLoadBalancerIPPool API Version

**Impact:** None - project already uses `cilium.io/v2`

The `v2alpha1` API version for `CiliumLoadBalancerIPPool` has been removed. Only `cilium.io/v2` is supported.

```yaml
# ❌ REMOVED in 1.19
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool

# ✅ Project uses (no change needed)
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
```

#### 3. Removed Helm Flags

**Impact:** None - project doesn't use any of these flags

The following Helm values/CLI flags have been removed:

| Removed Flag | Replacement |
| ------------ | ----------- |
| `--enable-nodeport` | Now always enabled with kube-proxy replacement |
| `--enable-session-affinity` | Now always enabled |
| `--enable-host-port` | Now always enabled |
| `--enable-external-ips` | Now always enabled |
| `--enable-custom-calls` | Remove (deprecated eBPF feature) |
| `--enable-recorder` | Replaced with network observability |
| `--loadbalancer-enable-l4lb-health-check` | Removed |
| `--enable-l2-announcements` | Always enabled when L2 config present |

**Verification:** Confirm project templates don't use these:
```bash
grep -E "enable-nodeport|enable-session-affinity|enable-host-port" \
  templates/config/kubernetes/apps/kube-system/cilium/
# Should return no results ✅
```

#### 4. CiliumNetworkPolicy Changes

**Impact:** None - project doesn't use FromRequires/ToRequires

`FromRequires` and `ToRequires` have been removed from `CiliumNetworkPolicy`. Use `FromEntities` and `ToEntities` with the `all` entity and labels instead.

#### 5. ClusterMesh Default Change

**Impact:** Low - only affects multi-cluster deployments

`policy-default-local-cluster` is now enabled by default in ClusterMesh configurations. This affects cross-cluster network policy behavior.

### Project Template Compatibility Summary

| Template File | 1.19 Compatible | Notes |
| ------------- | --------------- | ----- |
| `cilium/app/networks.yaml.j2` | ✅ Yes | Uses `cilium.io/v2` for all CRDs |
| `cilium/app/helmrelease.yaml.j2` | ✅ Yes | No deprecated flags used |
| `cilium/app/ocirepository.yaml.j2` | ✅ Yes | Uses `oci://quay.io/cilium-charts-dev/cilium` |
| `bootstrap/helmfile.d/01-apps.yaml.j2` | ✅ Yes | Uses `oci://quay.io/cilium-charts-dev/cilium` |

### Current Version Configuration

The project uses Cilium 1.19.0-pre.3 from the official Cilium OCI dev charts repository:

**1. `templates/config/kubernetes/apps/kube-system/cilium/app/ocirepository.yaml.j2`:**
```yaml
spec:
  ref:
    tag: 1.19.0-pre.3-dev.1-7df990dc67
  url: oci://quay.io/cilium-charts-dev/cilium
```

**2. `templates/config/bootstrap/helmfile.d/01-apps.yaml.j2`:**
```yaml
releases:
  - name: cilium
    chart: oci://quay.io/cilium-charts-dev/cilium
    version: 1.19.0-pre.3-dev.1-7df990dc67
```

> **Note:** The Cilium dev charts repository (`quay.io/cilium-charts-dev`) provides OCI-based Helm charts for pre-release versions. When Cilium 1.19.0 stable is released, the chart will be available at `https://helm.cilium.io/` and may be mirrored to `ghcr.io/home-operations/charts-mirror`.

### New 1.19 Features Available

#### Auto-Discovery (DefaultGateway Mode)

Cilium 1.19 introduces automatic BGP peer discovery. Instead of manually specifying `peerAddress`, the cluster can discover the default gateway automatically:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-cluster-config
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
    - name: instance-64514
      localASN: 64514
      peers:
        - name: peer-64513-v4
          peerASN: 64513
          # NEW: Auto-discovery instead of peerAddress
          autoDiscovery:
            ipv4:
              defaultGateway: true
          peerConfigRef:
            name: bgp-peer-config-v4
```

**Limitations:**
- Multi-homing: Only one BGP session per address family when using auto-discovery
- Link-local addresses as default gateway are not supported
- Requires ToR switches configured with `bgp listen range`

#### Prefix Aggregation for Service VIPs

Instead of advertising individual `/32` routes, aggregate them into larger prefixes:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisement-aggregated
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
        # NEW: Aggregate to /24 instead of /32
        aggregationLengthIPv4: 24
      selector:
        matchExpressions:
          - { key: somekey, operator: NotIn, values: ["never-used-value"] }
```

**⚠️ Caveat:** Prefix aggregation can create routing black holes if traffic arrives for an IP not assigned to any service within the aggregated range.

#### Enhanced Transport Configuration

Custom BGP session transport settings:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: bgp-peer-config-custom
spec:
  transport:
    peerPort: 1179  # Non-standard BGP port
    sourceInterface: "eth0"  # Override source interface
  # ... other settings
```

#### BGP Origin Attribute Configuration

New in 1.19: Configure the BGP origin attribute for LoadBalancer IPs, enabling smoother migration from MetalLB:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisement-with-origin
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      attributes:
        origin: igp  # Options: igp, egp, incomplete
```

#### Interface Advertisement Type

New in 1.19: Advertise arbitrary IPs assigned to local interfaces (useful for VIPs on loopback):

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-interface-advertisement
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: Interface
      interface:
        name: "lo"  # Advertise IPs on loopback interface
```

---

## Overview

This guide provides step-by-step instructions for enabling BGP peering between your UniFi gateway and Kubernetes cluster using Cilium's BGP Control Plane v2. The implementation is natively integrated with the project's templating system.

### Environment Configuration

This guide is configured for the **matherlynet** cluster environment:

| Network | CIDR | Gateway | Purpose |
| ------- | ---- | ------- | ------- |
| **VLAN 7** (Kubernetes) | `192.168.20.0/22` | `192.168.23.254` | Node network, BGP peering |
| **VLAN 1** (Management) | `192.168.1.0/24` | `192.168.1.254` | UDM management (not used for BGP) |

> **Note:** BGP peering occurs over VLAN 7 using the gateway IP `192.168.23.254`, not the UDM's management IP on VLAN 1.

### What This Guide Covers

1. Prerequisites and validation
2. Cluster configuration (`cluster.yaml`)
3. UniFi FRR configuration
4. Template regeneration and deployment
5. Verification and troubleshooting

### When to Use BGP vs L2 Announcements

| Use Case | Recommendation |
| -------- | -------------- |
| Single VLAN home lab | L2 announcements (default) |
| Multi-VLAN environment | BGP required |
| Cross-subnet service access | BGP required |
| Faster failover needed (~9s) | BGP with tuned timers (BFD not yet supported) |
| Source IP preservation needed | BGP with `externalTrafficPolicy: Local` |

---

## Prerequisites

### Hardware Requirements

#### UniFi Gateway

BGP requires one of these devices with minimum firmware:

| Device | Minimum UniFi OS Version |
| ------ | ------------------------ |
| UDM-Pro-Max | 4.1.13+ |
| UDM-SE | 4.1.13+ |
| UDM-Pro | 4.1.13+ |
| UDW | 4.1.13+ |
| UXG-Enterprise | 4.1.8+ |
| EFG | 4.1.13+ |
| Cloud Gateway Max | 4.1.13+ |
| Cloud Gateway Ultra | 4.1.13+ |

**Verify your firmware:**
1. Log into UniFi Network UI
2. Navigate to **Settings > System > Updates**
3. Confirm UniFi OS version is 4.1.13 or newer

#### Cluster Requirements

- Cilium 1.18+ (project uses latest stable via OCI)
- Kubernetes 1.28+ (project uses v1.35.0)
- Working L2 announcements (validates Cilium LB-IPAM)

### Network Planning

Before proceeding, decide on your BGP architecture:

#### Option A: Simple Setup (Current Configuration)

Use the node network (`node_cidr`) for both BGP peering and LoadBalancer IPs. This is the **matherlynet** configuration.

```
Node Network:    192.168.20.0/22 (VLAN 7)
LoadBalancer IPs: 192.168.20.x-192.168.23.x (assigned from node_cidr)
BGP Peering:     Node IPs ↔ 192.168.23.254 (VLAN 7 Gateway)
```

**Pros:** Simple, no additional VLANs beyond existing VLAN 7
**Cons:** LB IPs share space with node/device IPs

#### Option B: Dedicated Services Network

Use a separate CIDR for LoadBalancer IPs.

```
Node Network:    192.168.20.0/22 (VLAN 7)
Services VLAN:   172.20.10.0/24 (no DHCP)
BGP Peering:     Node IPs ↔ 192.168.23.254
```

**Pros:** Clear segmentation, easier firewall rules
**Cons:** Requires additional VLAN and routing

This guide uses **Option A** which matches the current cluster configuration. Option B requires additional template modifications (documented in Advanced Configuration).

---

## Pre-Implementation Checklist

> **✅ Already Complete:** The project templates already use `cilium.io/v2` API version for all Cilium CRDs. No template modifications are required before enabling BGP.

Verify this by checking the template:
```bash
grep "apiVersion: cilium.io" templates/config/kubernetes/apps/kube-system/cilium/app/networks.yaml.j2
# Should show: apiVersion: cilium.io/v2
```

---

## Step 1: Configure cluster.yaml

Add the BGP configuration section to your `cluster.yaml`:

```yaml
# =============================================================================
# BGP Configuration
# =============================================================================
# Enable BGP peering between Cilium and your router for dynamic routing.
# This allows LoadBalancer IPs to be advertised via BGP instead of L2/ARP.
#
# Requirements:
# - UniFi gateway with UniFi OS 4.1.13+ (or UXG-Enterprise 4.1.8+)
# - FRR BGP config uploaded to gateway (see docs/guides/bgp-unifi-cilium-implementation.md)

# The IP address of the BGP router (VLAN 7 gateway, NOT UDM management IP)
cilium_bgp_router_addr: "192.168.23.254"

# The BGP ASN for the router (use private range 64512-65534)
cilium_bgp_router_asn: "64513"

# The BGP ASN for Kubernetes nodes (must differ from router ASN for eBGP)
cilium_bgp_node_asn: "64514"
```

> **Important:** Use the VLAN 7 gateway IP (`192.168.23.254`) for BGP peering, not the UDM's management IP on VLAN 1 (`192.168.1.254`).

### ASN Allocation

| Component | Recommended ASN | Notes |
| --------- | --------------- | ----- |
| UniFi Gateway | 64513 | Private ASN (RFC 1930) |
| Kubernetes Nodes | 64514 | Must differ from gateway ASN |

Private ASN ranges:
- **2-byte:** 64512-65534
- **4-byte:** 4200000000-4294967294

---

## Step 2: UniFi FRR Configuration

The UniFi FRR configuration is **automatically generated** from your `cluster.yaml` and `nodes.yaml` when you run `task configure`. The generated file is located at `unifi/bgp.conf`.

> **Note:** You don't need to manually create this file. The template at `templates/config/unifi/bgp.conf.j2` generates it with all your node IPs and configuration options.

### Generated Configuration Features

The template automatically includes:
- **ECMP** (Equal-Cost Multi-Path) for load balancing across advertising nodes
- **Route-map filtering** to only accept LoadBalancer IPs from the cluster
- **All node IPs** from your `nodes.yaml` as BGP neighbors
- **Timer configuration** from your `cluster.yaml` settings
- **Optional authentication** when `cilium_bgp_password` is set
- **Optional graceful restart** when `cilium_bgp_graceful_restart` is enabled

### Example Generated Configuration

After running `task configure`, `unifi/bgp.conf` will contain something like:

```frr
! =============================================================================
! BGP Configuration for matherlynet-talos-cluster
! Generated by: makejinja template
! Upload to UniFi: Settings → Routing → BGP → Add Configuration
! =============================================================================

router bgp 64513
  bgp router-id 192.168.23.254
  no bgp ebgp-requires-policy
  no bgp default ipv4-unicast
  no bgp network import-check
  !
  ! ECMP - Enable multi-path routing for load distribution across advertising nodes
  bgp bestpath as-path multipath-relax
  maximum-paths 3
  !
  ! Peer group for Kubernetes nodes
  neighbor TALOS peer-group
  neighbor TALOS remote-as 64514
  neighbor TALOS timers 10 30
  !
  ! Add each Kubernetes node as a neighbor (auto-generated from nodes.yaml)
  neighbor 192.168.20.10 peer-group TALOS
  neighbor 192.168.20.11 peer-group TALOS
  neighbor 192.168.20.12 peer-group TALOS
  !
  address-family ipv4 unicast
    neighbor TALOS activate
    neighbor TALOS next-hop-self
    neighbor TALOS soft-reconfiguration inbound
    neighbor TALOS route-map ACCEPT-K8S in
  exit-address-family
!
exit
!
! =============================================================================
! Prefix List - Only accept LoadBalancer IPs from the cluster
! =============================================================================
ip prefix-list K8S-LOADBALANCER seq 5 permit 192.168.20.0/22 ge 32
!
route-map ACCEPT-K8S permit 10
  match ip address prefix-list K8S-LOADBALANCER
exit
```

### Critical Configuration Notes

1. **`bgp router-id`** - Uses `cilium_bgp_router_addr` (gateway IP on node VLAN)
2. **`no bgp ebgp-requires-policy`** - **Required** for route exchange without explicit policies
3. **ECMP enabled** - `bgp bestpath as-path multipath-relax` + `maximum-paths` for load distribution
4. **Route-map applied** - `neighbor TALOS route-map ACCEPT-K8S in` filters incoming routes
5. **Prefix lists** - Must come AFTER the `exit` from `router bgp` section
6. **Node IPs auto-generated** - All nodes from `nodes.yaml` are included automatically

### Upload to UniFi

1. Navigate to **Settings → Routing → BGP**
2. Click **Add Configuration** or **Upload Configuration**
3. Upload the `unifi/bgp.conf` file
4. Give it a descriptive name (e.g., "kubernetes-bgp")
5. Save the configuration

---

## Step 3: Regenerate Templates and Deploy

```bash
# Regenerate all templates with BGP configuration
task configure

# Review the generated Cilium networks configuration
cat kubernetes/apps/kube-system/cilium/app/networks.yaml

# Verify BGP CRDs are present
grep -A 50 "CiliumBGPClusterConfig" kubernetes/apps/kube-system/cilium/app/networks.yaml
```

### What Gets Generated

When BGP is enabled, `networks.yaml.j2` generates these additional CRDs:

1. **CiliumBGPClusterConfig** - Defines BGP instances and peers
2. **CiliumBGPPeerConfig** - Peer connection settings (includes `authSecretRef` if password configured)
3. **CiliumBGPAdvertisement** - What routes to advertise
4. **Secret** (optional) - BGP authentication password when `cilium_bgp_password` is set

Additionally, `bgp.conf.j2` generates the UniFi FRR configuration at `unifi/bgp.conf`.

### Apply to Cluster

```bash
# Commit changes
git add -A
git commit -m "feat: enable BGP peering with UniFi gateway"
git push

# Force Flux to reconcile immediately
task reconcile

# Or wait for automatic reconciliation (default: 1 hour)
```

---

## Step 4: Verification

### Cilium BGP Status

```bash
# Check BGP peer status (should show "Established")
cilium bgp peers

# Example output for matherlynet cluster:
# Node                    Local AS   Peer AS    Peer Address      Session State   Uptime
# node-1                  64514      64513      192.168.23.254    established     1h30m
# node-2                  64514      64513      192.168.23.254    established     1h30m
# node-3                  64514      64513      192.168.23.254    established     1h30m

# View advertised routes
cilium bgp routes advertised ipv4 unicast

# Check BGP CRD status
kubectl get ciliumbgpclusterconfig
kubectl get ciliumbgppeerconfig
kubectl get ciliumbgpadvertisement
kubectl get ciliumbgpnodeconfig
```

### UniFi BGP Status (via SSH)

```bash
# SSH to your UniFi gateway (use management IP on VLAN 1)
ssh root@192.168.1.254

# Check FRR service status
service frr status

# View BGP summary
vtysh -c "show ip bgp summary"

# Example output for matherlynet cluster (VLAN 7 node IPs):
# Neighbor        V    AS   MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
# 192.168.20.10   4 64514       150     145        3    0    0 01:30:15        2
# 192.168.20.11   4 64514       150     145        3    0    0 01:30:12        2
# 192.168.20.12   4 64514       150     145        3    0    0 01:30:10        2

# View learned routes from cluster
vtysh -c "show ip bgp"

# Check kernel routing table for BGP routes
ip route show proto bgp
```

### Service Connectivity Test

```bash
# Create a test LoadBalancer service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Get the assigned LoadBalancer IP
kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test from a client on the network (NOT ping - use curl)
curl http://<loadbalancer-ip>

# IMPORTANT: ICMP ping will NOT work to BGP-advertised IPs
# This is a known Cilium limitation (GitHub issue #14118)
```

---

## Troubleshooting

### BGP Session Not Establishing

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| Session stuck in `Active` | Firewall blocking TCP 179 | Add firewall rule allowing TCP 179 from nodes to gateway |
| Session stuck in `OpenSent` | ASN mismatch | Verify ASNs match on both sides |
| Session flapping | MTU issues | Check path MTU, reduce if needed |
| No routes exchanged | Missing `no bgp ebgp-requires-policy` | Add to UniFi FRR config |

### Cilium Not Advertising Routes

```bash
# Check if LoadBalancer IPs are assigned
kubectl get svc -A -o wide | grep LoadBalancer

# Verify IP pool has available addresses
kubectl get ciliumloadbalancerippool -o yaml

# Check advertisement configuration
kubectl get ciliumbgpadvertisement -o yaml

# Check Cilium agent logs for BGP errors
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp
```

### UniFi Not Learning Routes

```bash
# SSH to gateway and check neighbor state
vtysh -c "show ip bgp summary"

# If "State/PfxRcd" shows 0, check route policies
vtysh -c "show running-config" | grep -A10 "route-map"

# Check if routes are being filtered (use actual node IP)
vtysh -c "show ip bgp neighbors 192.168.20.10 filtered-routes"
```

### Firewall Rules (if needed)

Add a firewall rule in UniFi Network:

1. Navigate to **Settings → Security → Firewall Rules**
2. Create a **LAN Local** rule:
   - Name: `Allow BGP from Kubernetes`
   - Action: `Accept`
   - Source: Your node network CIDR (`192.168.20.0/22` for VLAN 7)
   - Destination: `Gateway`
   - Port/Protocol: `TCP 179`

---

## Advanced Configuration

### Enable Graceful Restart

For smoother failover during Cilium restarts:

**Template Update** (`templates/config/kubernetes/apps/kube-system/cilium/app/networks.yaml.j2`):

```yaml
#% if cilium_bgp_enabled %#
---
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: bgp-peer-config-v4
spec:
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 120
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
#% endif %#
```

**UniFi FRR Update:**

```frr
neighbor TALOS graceful-restart
neighbor TALOS graceful-restart-helper
```

### Faster Failure Detection (Timer Tuning)

> **Note:** BFD (Bidirectional Forwarding Detection) is **not yet supported** in Cilium's BGP Control Plane. The GoBGP backend used by Cilium lacks native BFD support. See [GitHub issue #22394](https://github.com/cilium/cilium/issues/22394) for status. This remains unchanged in Cilium 1.19.

As a workaround, tune BGP timers for faster failure detection:

**Cilium CiliumBGPPeerConfig:**

```yaml
spec:
  # Minimum values: holdTimeSeconds=3, keepAliveTimeSeconds=1
  holdTimeSeconds: 9
  keepAliveTimeSeconds: 3
```

**UniFi FRR:**

```frr
neighbor TALOS timers 3 9
```

This reduces failure detection from ~90 seconds (default) to ~9 seconds.

### Enable BGP Authentication

For added security, enable TCP MD5 authentication (RFC 2385). This is now natively integrated into the template system.

**Add to `cluster.yaml`:**

```yaml
# MD5 password for BGP session authentication
cilium_bgp_password: "your-secure-password"
```

**Regenerate templates:**

```bash
task configure
```

This automatically:
1. Creates a SOPS-encrypted Kubernetes Secret (`bgp-peer-password`) in `kube-system` namespace
2. Configures `authSecretRef` in `CiliumBGPPeerConfig`
3. Adds the password to the UniFi FRR configuration template

> **Security Note:** The BGP password Secret is stored in `kubernetes/apps/kube-system/cilium/app/secret.sops.yaml` and encrypted with SOPS/Age, following the same pattern as other secrets in this project.
>
> **Note:** After regenerating, upload the new `unifi/bgp.conf` to your UniFi gateway.

### ECMP (Multi-Path Routing)

ECMP (Equal-Cost Multi-Path) is now **enabled by default** in the template. This allows load balancing across multiple nodes when they advertise the same LoadBalancer IP.

**Default configuration (in UniFi FRR template):**

```frr
bgp bestpath as-path multipath-relax
maximum-paths 3
```

**To customize the maximum paths, add to `cluster.yaml`:**

```yaml
# Maximum ECMP paths (default: 3)
cilium_bgp_ecmp_max_paths: 4
```

**How ECMP works:**
- When multiple nodes advertise the same LoadBalancer IP, the router can use multiple paths
- Traffic is distributed across up to `maximum-paths` nodes
- Requires `bgp bestpath as-path multipath-relax` to treat paths with different AS paths as equal

### Dedicated LoadBalancer IP Pool

To use a separate CIDR for LoadBalancer IPs:

**1. Add to `cluster.yaml`:**

```yaml
# Dedicated CIDR for LoadBalancer IPs (separate from node_cidr)
cilium_lb_pool_cidr: "172.20.10.0/24"
```

**2. Update `networks.yaml.j2`:**

```yaml
---
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: pool
spec:
  allowFirstLastIPs: "No"
  blocks:
    #% if cilium_lb_pool_cidr is defined %#
    - cidr: "#{ cilium_lb_pool_cidr }#"
    #% else %#
    - cidr: "#{ node_cidr }#"
    #% endif %#
```

**3. Update UniFi Prefix List:**

```frr
ip prefix-list K8S-LOADBALANCER seq 5 permit 172.20.10.0/24 ge 32
```

**4. Create Static Route (if different subnet):**

On UniFi, create a static route for the services network pointing to any cluster node, or let BGP handle it dynamically.

---

## API Version Migration Notice

### Cilium 1.18+ (Current)

The project uses `cilium.io/v2` for all BGP CRDs:

- `CiliumBGPClusterConfig`
- `CiliumBGPPeerConfig`
- `CiliumBGPAdvertisement`
- `CiliumBGPNodeConfigOverride`

### Cilium 1.19 (Upcoming - February 2026)

> **⚠️ Breaking Change:** `CiliumBGPPeeringPolicy` CRD and its control plane (BGPv1) will be **completely removed** in Cilium 1.19. Migration to `cilium.io/v2` CRDs is **required before upgrading**.

New features in 1.19:
- **Auto-Discovery**: `DefaultGateway` mode for automatic BGP peer discovery
- **Prefix Aggregation**: Service VIP aggregation with `aggregationLengthIPv4/IPv6`
- **Enhanced Transport**: Custom destination ports and source interface specification

### Deprecated (Cilium 1.16-1.17)

The `v2alpha1` API version is **deprecated** as of Cilium 1.18. If upgrading from older Cilium versions, change:

```yaml
# Old (deprecated)
apiVersion: cilium.io/v2alpha1

# New (current)
apiVersion: cilium.io/v2
```

The `CiliumBGPPeeringPolicy` CRD is **deprecated** in Cilium 1.18 and **removed** in 1.19+. Use `CiliumBGPClusterConfig` instead.

---

## Verification Checklist

Before considering the BGP setup complete:

- [ ] BGP configuration added to `cluster.yaml`
- [ ] UniFi FRR config created and uploaded
- [ ] Templates regenerated with `task configure`
- [ ] Changes committed and pushed to Git
- [ ] Flux reconciled with `task reconcile`
- [ ] `cilium bgp peers` shows "Established" for all nodes
- [ ] `vtysh -c "show ip bgp summary"` shows active sessions
- [ ] LoadBalancer service IPs appear in UniFi BGP routes
- [ ] Service accessible via `curl` from network client (not ping!)

---

## References

### Official Documentation

- [Cilium BGP Control Plane v2](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/) - Cilium v1.18+ CRD specifications
- [Cilium BGP Control Plane v2 (1.19-dev)](https://docs.cilium.io/en/latest/network/bgp-control-plane/bgp-control-plane-configuration/) - Cilium v1.19 configuration reference
- [Cilium 1.19 Upgrade Guide](https://docs.cilium.io/en/latest/operations/upgrade/) - Breaking changes and migration paths
- [Cilium BGP Control Plane Operation](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-operation/) - Operational guide and troubleshooting
- [Cilium LB-IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/) - LoadBalancer IP Address Management
- [UniFi BGP Documentation](https://help.ui.com/hc/en-us/articles/16271338193559-UniFi-Border-Gateway-Protocol-BGP) - Official Ubiquiti guide

### Community Resources

- [BGP with Cilium and UniFi (stonegarden.dev)](https://blog.stonegarden.dev/articles/2025/11/bgp-cilium-unifi/) - Comprehensive community guide
- [waifulabs/infrastructure](https://github.com/waifulabs/infrastructure) - Reference implementation
- [UniFi UDM Pro BGP Configuration](https://gibsonvirt.com/2025/01/14/unifi-udm-pro-bgp-configuration/) - Configuration examples
- [Cilium BGP Auto-Discovery Feature](https://medium.com/@simardeep.oberoi/simplifying-network-management-with-ciliums-bgp-auto-discovery-feature-2f340d2225f8) - Auto-discovery deep-dive

### Feature Requests & Known Issues

- [Cilium BFD Support (GitHub #22394)](https://github.com/cilium/cilium/issues/22394) - BFD feature request status
- [Cilium ICMP Limitation (GitHub #14118)](https://github.com/cilium/cilium/issues/14118) - ICMP ping limitation for BGP-advertised IPs
- [Cilium 1.19 Milestones (GitHub #41523)](https://github.com/cilium/cilium/discussions/41523) - 1.19 release milestones
- [Cilium Releases](https://github.com/cilium/cilium/releases) - All Cilium releases

### Project Documentation

- [Research: BGP UniFi Cilium Integration](../research/archive/implemented/bgp-unifi-cilium-integration.md) - Original research document (archived - implemented)
- [Cilium Networking Context](../ai-context/cilium-networking.md) - Cilium architecture patterns
