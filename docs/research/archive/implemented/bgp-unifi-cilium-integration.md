# BGP Integration Research: UniFi Router + Cilium Kubernetes

> **Research Date:** January 2026
> **Status:** Complete - Validated
> **Sources:** waifulabs/infrastructure, Ubiquiti documentation, Cilium docs, stonegarden.dev blog, community implementations

## Executive Summary

This document analyzes BGP integration between UniFi routers/gateways and Kubernetes clusters using Cilium as the CNI. The research is based on the [waifulabs/infrastructure](https://github.com/waifulabs/infrastructure) reference implementation and official documentation.

**Key Finding:** Our project already has BGP support templated in `networks.yaml.j2`. Enabling BGP requires only configuration in `cluster.yaml` and deploying an FRR configuration to the UniFi gateway.

### Benefits of BGP vs L2 Announcements

| Aspect | L2 (ARP/NDP) | BGP |
| -------- | ------------ | ----- |
| **Scope** | Single broadcast domain | Multi-subnet, routable |
| **Failover** | Gratuitous ARP (seconds) | BFD-enabled (sub-second) |
| **Scalability** | Limited by broadcast domain | Scales with routing infrastructure |
| **Debugging** | ARP tables, tcpdump | BGP session state, route tables |
| **Complexity** | Low | Medium |

**Recommendation:** For home lab environments with a single subnet, L2 announcements are sufficient. BGP becomes valuable when:

- Services need to be reachable across VLANs without NAT
- Faster failover is required (with BFD)
- Integration with existing BGP infrastructure exists
- Multi-site or hybrid cloud routing is planned
- Source IP preservation is needed (`externalTrafficPolicy: Local`)

### Important Limitations

> **ICMP/Ping Warning:** BGP-advertised LoadBalancer IPs will NOT respond to ICMP ping requests. This is a known Cilium limitation ([GitHub issue #14118](https://github.com/cilium/cilium/issues/14118)). Use `curl` or actual service connections to test reachability instead of ping.

---

## Reference Implementation Analysis

### waifulabs/infrastructure Repository

**Repository Stats:** 192+ GitHub stars, 12,540+ commits
**Architecture:** Talos Linux + Flux CD + Cilium (similar to our project)

#### Network Design

The waifulabs cluster uses a dedicated VLAN for BGP peering:

| VLAN | Purpose | CIDR |
| ------ | --------- | ------ |
| 1 | Management | Servers + network devices |
| 2 | Devices | Wireless/workstations |
| 3 | IoT | Security isolation |
| **4** | **Services** | **BGP cluster traffic (no DHCP)** |
| 86 | Untrusted | Guest network |

#### UniFi BGP Configuration

From `unifi/bgp.conf`:

```
router bgp 64513
  bgp router-id 10.0.10.1
  no bgp ebgp-requires-policy
  no bgp default ipv4-unicast
  no bgp network import-check
  !
  neighbor k8s peer-group
  neighbor k8s remote-as 64514
  neighbor 10.0.10.10 peer-group k8s
  neighbor 10.0.10.11 peer-group k8s
  neighbor 10.0.10.12 peer-group k8s
  neighbor 10.0.10.13 peer-group k8s
  !
  address-family ipv4 unicast
    neighbor k8s next-hop-self
    neighbor k8s activate
  exit-address-family
```

**Key Configuration Points:**

- **ASN 64513** (router) peers with **ASN 64514** (K8s nodes)
- Uses private ASN range (64512-65534 for eBGP)
- `no bgp ebgp-requires-policy` - **Critical:** Allows route exchange without explicit policies
- `next-hop-self` - Router rewrites next-hop for proper routing
- Peer group simplifies multi-node configuration

---

## UniFi BGP Requirements & Configuration

### Supported Hardware

BGP is available on these UniFi devices:

| Device | Minimum UniFi OS Version |
| -------- | -------------------------- |
| UDM-Pro-Max | 4.1.13+ |
| UDM-SE | 4.1.13+ |
| UDM-Pro | 4.1.13+ |
| UDW | 4.1.13+ |
| UXG-Enterprise | 4.1.8+ |
| EFG | 4.1.13+ |

### FRR Configuration Format

UniFi uses [FRRouting (FRR)](https://frrouting.org/) for BGP. Configuration is uploaded as a text file via:

**Settings → Routing → BGP → Upload Configuration**

#### Basic Template for Kubernetes Peering

```
router bgp <ROUTER_ASN>
  bgp router-id <ROUTER_IP>
  no bgp ebgp-requires-policy
  no bgp default ipv4-unicast
  !
  neighbor K8S peer-group
  neighbor K8S remote-as <NODE_ASN>
  # Add each node as a neighbor
  neighbor <NODE1_IP> peer-group K8S
  neighbor <NODE2_IP> peer-group K8S
  neighbor <NODE3_IP> peer-group K8S
  !
  address-family ipv4 unicast
    neighbor K8S activate
    neighbor K8S next-hop-self
    neighbor K8S soft-reconfiguration inbound
  exit-address-family
!
exit
!
# Optional: Restrict accepted prefixes
ip prefix-list K8S-SERVICES seq 5 permit <SERVICE_CIDR> le 32
!
route-map ACCEPT-K8S permit 10
  match ip address prefix-list K8S-SERVICES
exit
```

### Configuration Notes

1. **Order Matters:** `router bgp` section must come before prefix-lists and route-maps
2. **Prefix Lists:** Place at the end of the file after `exit` from router bgp
3. **Firewall:** TCP port 179 must be allowed for BGP sessions
4. **Logging:** Check `/var/log/frr/bgpd.log` on UniFi device

### Verification Commands (SSH to UniFi)

```bash
# Check FRR service status
service frr status

# View running BGP config
vtysh -c "show running-config"

# Check BGP session status
vtysh -c "show ip bgp summary"

# View learned routes
vtysh -c "show ip bgp"
ip route show proto bgp

# Check specific neighbor
vtysh -c "show ip bgp neighbors <PEER_IP>"
```

---

## Cilium BGP Control Plane

Cilium v1.18+ uses the graduated **BGP Control Plane v2**, which provides improved configuration through dedicated CRDs. This is the recommended approach for new deployments.

### Enabling BGP

In `cluster.yaml`:

```yaml
cilium_bgp_router_addr: "192.168.1.1"  # UniFi gateway IP
cilium_bgp_router_asn: "64513"          # Gateway ASN
cilium_bgp_node_asn: "64514"            # K8s nodes ASN
```

These variables trigger conditional templating in `helmrelease.yaml.j2`:

```yaml
#% if cilium_bgp_enabled %#
bgpControlPlane:
  enabled: true
#% endif %#
```

### Generated Kubernetes Resources

When BGP is enabled, `networks.yaml.j2` generates:

#### CiliumLoadBalancerIPPool

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: pool
spec:
  allowFirstLastIPs: "No"
  blocks:
    - cidr: "#{ node_cidr }#"
```

#### CiliumBGPAdvertisement

> **Note:** The current template uses a `matchExpressions` workaround to match all services. A cleaner approach uses explicit labels on services.

**Current Template (matches all services):**

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisement-config
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - { key: somekey, operator: NotIn, values: ["never-used-value"] }
```

**Recommended Approach (explicit labels):**

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: loadbalancer-services
  labels:
    bgp.cilium.io/advertise: loadbalancer-services
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchLabels:
          bgp.cilium.io/advertise-service: default
```

With this approach, label your LoadBalancer services:

```yaml
metadata:
  labels:
    bgp.cilium.io/ip-pool: default           # For IP pool assignment
    bgp.cilium.io/advertise-service: default  # For BGP advertisement
```

#### CiliumBGPPeerConfig

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: bgp-peer-config-v4
spec:
  # Optional: Enable graceful restart for maintenance windows
  gracefulRestart:
    enabled: true
  # Optional: Reference auth secret for password authentication
  # authSecretRef: bgp-peer-password
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
```

#### CiliumBGPClusterConfig

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
    - name: instance-#{ cilium_bgp_node_asn }#
      localASN: #{ cilium_bgp_node_asn }#
      peers:
        - name: peer-#{ cilium_bgp_router_asn }#-v4
          peerASN: #{ cilium_bgp_router_asn }#
          peerAddress: #{ cilium_bgp_router_addr }#
          peerConfigRef:
            name: bgp-peer-config-v4
```

### Cilium BGP Verification

```bash
# Check BGP peer status
cilium bgp peers

# View advertised routes
cilium bgp routes advertised ipv4 unicast

# View available routes
cilium bgp routes available ipv4 unicast

# Check BGP node configuration
kubectl get ciliumbgpnodeconfig
kubectl get ciliumbgpclusterconfig
kubectl get ciliumbgpadvertisement
kubectl get ciliumbgppeerconfig
```

---

## Integration Recommendations

### Phase 1: Preparation (No Changes to Production)

1. **Verify UniFi Firmware**
   - Confirm gateway runs UniFi OS 4.1.13+ (or 4.1.8+ for UXG-Enterprise)
   - Enable SSH access for troubleshooting

2. **Plan ASN Allocation**
   - Recommended: Router ASN 64513, K8s nodes ASN 64514
   - Use private ASN range: 64512-65534

3. **Network Planning**
   - Decide: Same VLAN as nodes, or dedicated services VLAN?
   - For simplicity: Use node network (`node_cidr`) for BGP peering
   - For isolation: Create dedicated VLAN (like waifulabs VLAN 4)

4. **LoadBalancer IP Pool Planning** (Recommended)
   - Consider using a **dedicated CIDR** for LoadBalancer IPs separate from `node_cidr`
   - Example: Node network `192.168.1.0/24`, Services `172.20.10.0/24`
   - Benefits:
     - Avoids IP conflicts with node/device IPs
     - Clearer network segmentation
     - Easier firewall rules
   - To implement, add a new variable like `cilium_lb_pool_cidr` to `cluster.yaml`

### Phase 2: Configuration

1. **Update `cluster.yaml`**

```yaml
# BGP Configuration (required)
cilium_bgp_router_addr: "192.168.1.1"   # Your UniFi gateway IP
cilium_bgp_router_asn: "64513"
cilium_bgp_node_asn: "64514"

# Optional: Authentication
# cilium_bgp_password: "your-secure-password"

# Optional: Dedicated LoadBalancer IP pool
# cilium_lb_pool_cidr: "172.20.10.0/24"

# Optional: ECMP max paths (default: 3)
# cilium_bgp_ecmp_max_paths: 3
```

1. **Regenerate Templates**

```bash
task configure
```

This generates:

- `unifi/bgp.conf` - UniFi FRR configuration with ECMP, route-map filtering, and all node IPs
- `kubernetes/apps/kube-system/cilium/app/networks.yaml` - Cilium BGP CRDs
- Optional: BGP authentication Secret (when `cilium_bgp_password` is set)

1. **Upload UniFi Config**

Upload the generated `unifi/bgp.conf` to your UniFi gateway:

- Navigate to **Settings → Routing → BGP**
- Click **Add Configuration** and upload the file
- Give it a descriptive name (e.g., "kubernetes-bgp")

1. **Apply to Cluster**

```bash
git add -A && git commit -m "feat: enable BGP peering"
git push
task reconcile
```

### Phase 3: Verification

1. **Check Cilium BGP Status**

```bash
cilium bgp peers
# Expected: Established sessions with router
```

1. **Verify Route Advertisement**

```bash
cilium bgp routes advertised ipv4 unicast
# Should show LoadBalancer IPs
```

1. **Check UniFi Learned Routes**

```bash
ssh <unifi-gateway>
vtysh -c "show ip bgp"
# Should show routes from K8s cluster
```

1. **Test Service Accessibility**

```bash
# From a client on a different VLAN
curl http://<loadbalancer-ip>
```

---

## Troubleshooting Guide

### BGP Session Not Establishing

| Symptom | Cause | Solution |
| --------- | ------- | ---------- |
| Session stuck in `Active` | Firewall blocking port 179 | Add firewall rule for TCP 179 |
| Session stuck in `OpenSent` | ASN mismatch | Verify ASNs match on both sides |
| Session flapping | MTU issues | Check path MTU, reduce if needed |
| No routes exchanged | Missing `no bgp ebgp-requires-policy` | Add to router config |

### Cilium Not Advertising Routes

```bash
# Check if LoadBalancer IPs are assigned
kubectl get svc -A -o wide | grep LoadBalancer

# Verify IP pool has available addresses
kubectl get ciliumloadbalancerippool -o yaml

# Check advertisement config
kubectl get ciliumbgpadvertisement -o yaml

# Check Cilium agent logs
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp
```

### UniFi Not Learning Routes

```bash
# SSH to gateway
vtysh -c "show ip bgp summary"

# Check if neighbors are established
# Look for "Estab" state and number of prefixes received

# If prefixes = 0, check policies
vtysh -c "show running-config" | grep -A5 "route-map"
```

---

## Advanced Configuration Options

### BFD (Bidirectional Forwarding Detection)

> **Status (January 2026):** BFD is **NOT supported** in open-source Cilium BGP Control Plane. See [GitHub issue #22394](https://github.com/cilium/cilium/issues/22394) for tracking.

BFD enables sub-second failure detection (vs ~9s with tuned BGP timers). However:

- **Open-source Cilium:** Not supported. GoBGP (Cilium's BGP backend) lacks BFD support.
- **Cilium Enterprise:** BFD support added in v1.16 (November 2024).
- **No timeline:** No announced date for open-source availability.

**Current Workarounds:**

1. **Tune BGP timers** (minimum values):

   ```yaml
   cilium_bgp_hold_time: 3        # Minimum: 3 seconds
   cilium_bgp_keepalive_time: 1   # Minimum: 1 second
   ```

   This achieves ~9s failure detection vs default ~90s.

2. **Enable Graceful Restart** for smoother failovers:

   ```yaml
   cilium_bgp_graceful_restart: true
   ```

3. **BIRD (deprecated):** The legacy BIRD-based approach supports BFD but is deprecated in favor of native BGP Control Plane.

**UniFi Side (for future use):**

```
neighbor K8S bfd
```

**Bottom Line:** For most home lab use cases, tuned BGP timers with graceful restart provide adequate failover (~9s). BFD would reduce this to sub-second but isn't available in open-source Cilium.

### Password Authentication

**Cilium Side:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bgp-auth-secret
  namespace: kube-system
type: Opaque
data:
  password: <base64-encoded-password>
```

Update CiliumBGPPeerConfig:

```yaml
spec:
  authSecretRef: bgp-auth-secret
```

**UniFi Side:**

```
neighbor K8S password <your-password>
```

### Graceful Restart

**Cilium Side** (CiliumBGPPeerConfig):

```yaml
spec:
  gracefulRestart:
    enabled: true
```

**UniFi Side:**

```
neighbor K8S graceful-restart
neighbor K8S graceful-restart-helper
```

### Multipath Routing (ECMP Load Balancing)

For load balancing across multiple paths:

**UniFi Side:**

```
bgp bestpath as-path multipath-relax
maximum-paths 3
```

This allows the router to use multiple next-hops for the same prefix, distributing traffic across all advertising nodes.

### externalTrafficPolicy: Local

When using BGP, you can preserve the original client source IP by setting:

```yaml
spec:
  externalTrafficPolicy: Local
```

**Behavior:**

- Only nodes with matching pods advertise the service route
- Client source IP is preserved (visible in `RemoteAddr`)
- If the pod moves to a non-BGP node, the service becomes unreachable

**Without this setting** (default `Cluster`):

- All BGP nodes advertise the route
- Traffic is forwarded between nodes
- Original client IP is replaced with pod network IP

---

## Comparison: BGP vs L2 in This Project

### Current State (L2 Announcements)

The project currently uses Cilium L2 announcements:

```yaml
l2announcements:
  enabled: true
```

This works by:

1. Cilium responds to ARP requests for LoadBalancer IPs
2. Traffic is directed to the responding node
3. Works within a single broadcast domain

### With BGP

```yaml
bgpControlPlane:
  enabled: true
l2announcements:
  enabled: true  # Can coexist
```

This adds:

1. Routes advertised to upstream router via BGP
2. Router installs routes to its routing table
3. Traffic can cross VLAN boundaries via routing

### Recommendation for This Project

**For Single-VLAN Home Lab:** Keep L2 announcements, optionally add BGP for learning.

**For Multi-VLAN Setup:** Enable BGP for cross-VLAN service accessibility.

**For Production-Like Environment:** Use BGP with BFD for faster failover.

---

## Sources

### Primary References

- [waifulabs/infrastructure](https://github.com/waifulabs/infrastructure) - Reference implementation
- [UniFi BGP Documentation](https://help.ui.com/hc/en-us/articles/16271338193559-UniFi-Border-Gateway-Protocol-BGP) - Official Ubiquiti docs
- [Cilium BGP Control Plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane/) - Cilium documentation
- [BGP with Cilium and UniFi](https://blog.stonegarden.dev/articles/2025/11/bgp-cilium-unifi/) - Comprehensive community guide (stonegarden.dev)

### Additional Resources

- [UniFi UDM Pro BGP Configuration](https://gibsonvirt.com/2025/01/14/unifi-udm-pro-bgp-configuration/) - Configuration examples
- [BGP with MetalLB and Cloud Gateway Ultra](https://dglloyd.net/2025/07/04/bgp-with-metallb-and-a-cloud-gateway-ultra/) - Alternative approach
- [Isovalent BGP Labs](https://isovalent.com/labs/cilium-bgp/) - Hands-on Cilium BGP learning
- [Isovalent LB-IPAM and BGP Lab](https://isovalent.com/labs/cilium-lb-ipam-bgp/) - IP pool and advertisement lab
- [Packetswitch BGP Guide](https://www.packetswitch.co.uk/bgp/) - BGP fundamentals

### Community Implementations

- [Gerard Samuel](https://gerardsamuel.me/posts/homelab/howto-setup-kubernetes-cilium-bgp-with-unifi-v4.1-router/) - Cilium BGP with UniFi v4.1
- [Sander Sneekes](https://sneekes.app/posts/advanced-kubernetes-networking-bgp-with-cilium-and-udm-pro/) - Advanced K8s networking with BGP
- [Raj Singh](https://rajsingh.info/p/cilium-unifi/) - Cilium + UniFi integration
- [baremetalblog](https://baremetalblog.com/posts/tech/2024-03-12-cilium-bgp-and-you/) - Cilium BGP with OPNsense

---

## Appendix: Example Files

### A. Complete UniFi BGP Config for matherlynet

> **Note:** This configuration is now **auto-generated** by `task configure` from the template at `templates/config/unifi/bgp.conf.j2`. You don't need to manually create this file.

Example generated output (`unifi/bgp.conf`):

```frr
! BGP Configuration for matherlynet-talos-cluster
! Generated by: makejinja template
! Upload to UniFi: Settings → Routing → BGP
!
router bgp 64513
  bgp router-id <GATEWAY_IP>
  no bgp ebgp-requires-policy
  no bgp default ipv4-unicast
  no bgp network import-check
  !
  ! ECMP - Enable multi-path routing for load distribution
  bgp bestpath as-path multipath-relax
  maximum-paths 3
  !
  ! Peer group for Kubernetes nodes
  neighbor TALOS peer-group
  neighbor TALOS remote-as 64514
  neighbor TALOS timers 10 30
  !
  ! Node IPs (auto-generated from nodes.yaml)
  neighbor <NODE1_IP> peer-group TALOS
  neighbor <NODE2_IP> peer-group TALOS
  neighbor <NODE3_IP> peer-group TALOS
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
! Only accept LoadBalancer service IPs
ip prefix-list K8S-LOADBALANCER seq 5 permit <NODE_CIDR> ge 32
!
route-map ACCEPT-K8S permit 10
  match ip address prefix-list K8S-LOADBALANCER
exit
```

### B. cluster.yaml BGP Section

```yaml
# =============================================================================
# BGP Configuration (Optional)
# =============================================================================
# Enable BGP peering between Cilium and your router for dynamic routing.
# This allows LoadBalancer IPs to be advertised via BGP instead of L2/ARP.
#
# Requirements:
# - UniFi gateway with UniFi OS 4.1.13+ (or UXG-Enterprise 4.1.8+)
# - Run 'task configure' after setting these values
# - Upload generated 'unifi/bgp.conf' to gateway
#
# Reference: docs/guides/bgp-unifi-cilium-implementation.md

# Required for BGP:
cilium_bgp_router_addr: "192.168.1.1"   # Gateway IP on node VLAN
cilium_bgp_router_asn: "64513"          # Private ASN (64512-65534)
cilium_bgp_node_asn: "64514"            # Must differ from router ASN

# Optional: Dedicated LoadBalancer IP pool (separate from node_cidr)
# cilium_lb_pool_cidr: "172.20.10.0/24"

# Optional: BGP timers for failure detection (~9s with these settings)
# cilium_bgp_hold_time: 30
# cilium_bgp_keepalive_time: 10

# Optional: ECMP max paths for load balancing (default: 3)
# cilium_bgp_ecmp_max_paths: 3

# Optional: MD5 password for BGP session authentication (RFC 2385)
# cilium_bgp_password: "your-secure-password"

# Optional: Graceful restart for smoother Cilium restarts
# cilium_bgp_graceful_restart: true
# cilium_bgp_graceful_restart_time: 120
```
