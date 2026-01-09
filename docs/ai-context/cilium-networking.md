# Cilium Networking Guide

> Deep-dive documentation for AI assistants working with Cilium CNI in this project.

## Overview

Cilium is the Container Network Interface (CNI) for this cluster, providing:
- Pod networking with native routing
- kube-proxy replacement via eBPF
- L2 load balancer announcements (MetalLB alternative)
- Optional BGP peering

## Architecture

### eBPF-Based Networking

Cilium uses eBPF (extended Berkeley Packet Filter) for high-performance networking directly in the Linux kernel.

```
┌─────────────────────────────────────────────────┐
│                  Linux Kernel                    │
│  ┌────────────────────────────────────────────┐ │
│  │              eBPF Programs                  │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────┐ │ │
│  │  │ L3/L4   │  │ Service │  │ LoadBalancer│ │ │
│  │  │ Routing │  │  Proxy  │  │ (L2/BGP)    │ │ │
│  │  └─────────┘  └─────────┘  └─────────────┘ │ │
│  └────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### Key Features

| Feature | Configuration |
| --------- | --------------- |
| Native Routing | `routingMode: native` |
| kube-proxy Replacement | `kubeProxyReplacement: true` |
| L2 Announcements | `l2announcements.enabled: true` |
| DSR Mode | `loadBalancer.mode: dsr` |
| Maglev Hashing | `loadBalancer.algorithm: maglev` |

## Configuration

### HelmRelease Values

Located at `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`:

```yaml
values:
  # Replace kube-proxy
  kubeProxyReplacement: true
  kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256

  # Native routing (no overlay)
  routingMode: native
  ipv4NativeRoutingCIDR: "#{ cluster_pod_cidr }#"
  autoDirectNodeRoutes: true

  # L2 Load Balancer
  l2announcements:
    enabled: true
  externalIPs:
    enabled: true

  # LoadBalancer mode
  loadBalancer:
    algorithm: maglev
    mode: "#{ cilium_loadbalancer_mode }#"  # dsr or snat

  #% if cilium_bgp_enabled %#
  # BGP (optional)
  bgpControlPlane:
    enabled: true
  #% endif %#
```

### L2 Announcement Policy

Tells Cilium which IPs to announce via ARP:

```yaml
apiVersion: cilium.io/v2
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default-policy
spec:
  loadBalancerIPs: true
  interfaces:
    - eth0
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
```

### LoadBalancer IP Pool

Defines available IPs for LoadBalancer services:

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: main-pool
spec:
  blocks:
    - start: 192.168.1.100
      stop: 192.168.1.110
```

## Load Balancer Modes

### DSR (Direct Server Return)

Default mode. Response traffic bypasses the load balancer:

```
Client → Node (LB) → Pod → Client (direct)
```

Pros:
- Lower latency for responses
- Reduced load on LB node

Cons:
- Client IP visible to pods
- May require MTU adjustments

### SNAT (Source NAT)

All traffic flows through load balancer:

```
Client → Node (LB) → Pod → Node (LB) → Client
```

Pros:
- Simpler networking
- Works with any MTU

Cons:
- Higher latency
- Original client IP hidden (use X-Forwarded-For)

Configuration:
```yaml
# cluster.yaml
cilium_loadbalancer_mode: "snat"  # or "dsr"
```

## BGP Control Plane v2 (Optional)

For multi-VLAN environments requiring cross-subnet LoadBalancer access. When enabled, L2 announcements are disabled in favor of BGP route advertisements.

### When to Use BGP

- Multi-VLAN environment requiring cross-subnet service access
- Faster failover needed (~9s with tuned timers vs ARP cache timeout)
- Source IP preservation with `externalTrafficPolicy: Local`
- UniFi gateway with UniFi OS 4.1.13+ (or UXG-Enterprise 4.1.8+)

### Configuration

```yaml
# cluster.yaml - Required fields (all must be set)
cilium_bgp_router_addr: "192.168.1.1"    # Gateway IP on node VLAN
cilium_bgp_router_asn: "64513"           # Gateway ASN (private: 64512-65534)
cilium_bgp_node_asn: "64514"             # K8s node ASN (must differ for eBGP)

# cluster.yaml - Optional fields
cilium_lb_pool_cidr: "172.20.10.0/24"    # Dedicated LB pool (default: node_cidr)
cilium_bgp_hold_time: 30                 # Hold timer seconds (3-300)
cilium_bgp_keepalive_time: 10            # Keepalive interval seconds (1-100)
cilium_bgp_graceful_restart: false       # Enable graceful restart
cilium_bgp_graceful_restart_time: 120    # Graceful restart timeout (30-600)
cilium_bgp_ecmp_max_paths: 3             # ECMP paths for load balancing (1-16)
cilium_bgp_password: "secret"            # BGP MD5 authentication (RFC 2385, SOPS-encrypted)
```

### Generated CRDs

When BGP is enabled, these CRDs are generated in `networks.yaml.j2`:

```yaml
# CiliumBGPPeerConfig - Timer and session configuration
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: bgp-peer-config-v4
spec:
  authSecretRef: bgp-peer-password   # Only if password configured
  holdTimeSeconds: 30
  keepAliveTimeSeconds: 10
  gracefulRestart:           # Only if enabled
    enabled: true
    restartTimeSeconds: 120
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp

# CiliumBGPClusterConfig - Per-node BGP instances
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
          peerAddress: 192.168.1.1
          peerConfigRef:
            name: bgp-peer-config-v4

# CiliumBGPAdvertisement - What to advertise
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisement-config
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
```

### UniFi Gateway Configuration

When BGP is enabled, `templates/config/unifi/bgp.conf.j2` generates FRR configuration for UniFi gateways:

```bash
# Generated in unifi/bgp.conf after task configure
# Upload to UniFi: Settings → Routing → BGP → Add Configuration
router bgp 64513
  bgp router-id 192.168.1.1
  no bgp ebgp-requires-policy
  bgp bestpath as-path multipath-relax    # Enable ECMP
  maximum-paths 3                          # Up to 3 ECMP paths
  neighbor TALOS peer-group
  neighbor TALOS remote-as 64514
  neighbor TALOS timers 10 30
  neighbor TALOS password secret           # If password configured
  neighbor TALOS graceful-restart          # If enabled
  neighbor 192.168.1.10 peer-group TALOS   # Per-node
  neighbor 192.168.1.11 peer-group TALOS
  address-family ipv4 unicast
    neighbor TALOS activate
    neighbor TALOS next-hop-self
    neighbor TALOS soft-reconfiguration inbound
    neighbor TALOS route-map ACCEPT-K8S in
  exit-address-family
```

### BGP Debugging

```bash
# Check peering status
cilium bgp peers

# Verify routes advertised
cilium bgp routes advertised ipv4 unicast

# Check from Cilium agent
kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers

# Check BGP CRDs
kubectl get ciliumbgpclusterconfig -A
kubectl get ciliumbgppeerconfig -A
kubectl get ciliumbgpadvertisement -A

# Cilium agent logs
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp
```

### BGP vs L2 Comparison

| Feature | L2 (Default) | BGP |
| ------- | ------------ | --- |
| Network scope | Single VLAN | Multi-VLAN |
| Failover time | ~30s (ARP timeout) | ~9s (with tuned timers) |
| Router support | Any | BGP-capable (UniFi 4.1.13+) |
| Configuration | Simple | Requires FRR config |
| externalTrafficPolicy | Works | Works with Local |

### BFD Support Status

> **BFD is NOT supported** in open-source Cilium (as of January 2026).

BFD (Bidirectional Forwarding Detection) would enable sub-second failover, but:
- GoBGP (Cilium's BGP backend) lacks BFD support
- Cilium Enterprise added BFD in v1.16
- No timeline for open-source availability ([GitHub #22394](https://github.com/cilium/cilium/issues/22394))

**Workaround:** Tune BGP timers for ~9s failover:
```yaml
cilium_bgp_hold_time: 3        # Minimum
cilium_bgp_keepalive_time: 1   # Minimum
```

## Services in This Project

LoadBalancer IPs assigned:

| Service | IP Variable | Purpose |
| --------- | ------------- | --------- |
| envoy-internal | `cluster_gateway_addr` | Internal gateway |
| envoy-external | `cloudflare_gateway_addr` | External gateway |
| k8s-gateway | `cluster_dns_gateway_addr` | Split DNS |

## Troubleshooting

### Cilium Status

```bash
# Overall status
cilium status

# Connectivity test
cilium connectivity test
```

### BPF Maps

```bash
# List load balancer entries
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list

# List endpoints
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list
```

### L2 Announcements

```bash
# Check policy
kubectl get ciliuml2announcementpolicy

# Check IP pool
kubectl get ciliumloadbalancerippool

# Verify announcements
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list | grep <ip>
```

### Service Not Reachable

```bash
# 1. Check service has external IP
kubectl get svc -A | grep LoadBalancer

# 2. Check L2 announcement
kubectl get ciliuml2announcementpolicy
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list

# 3. Check endpoints
kubectl get endpoints -n <ns> <svc>

# 4. ARP check from external
arping -I <interface> <service-ip>
```

### Pod Networking Issues

```bash
# Check Cilium agent
kubectl -n kube-system get pods -l k8s-app=cilium

# Check agent logs
kubectl -n kube-system logs ds/cilium

# Check endpoint health
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint health
```

## Network Flow Diagram

```
External Traffic (Internet)
          │
          ▼
┌─────────────────────────┐
│    Cloudflare Tunnel    │  (outbound connection)
│    (cloudflared pod)    │
└─────────────────────────┘
          │
          ▼
┌─────────────────────────┐
│    envoy-external       │  LoadBalancer: cloudflare_gateway_addr
│    (Gateway)            │
└─────────────────────────┘
          │
          ▼
┌─────────────────────────┐
│    Application Pods     │
└─────────────────────────┘

Internal Traffic (LAN)
          │
          ▼
┌─────────────────────────┐
│    envoy-internal       │  LoadBalancer: cluster_gateway_addr
│    (Gateway)            │
└─────────────────────────┘
          │
          ▼
┌─────────────────────────┐
│    Application Pods     │
└─────────────────────────┘

DNS (Split Horizon)
          │
          ▼
┌─────────────────────────┐
│    k8s-gateway          │  LoadBalancer: cluster_dns_gateway_addr
│    (DNS Server)         │
└─────────────────────────┘
          │
          ▼
┌─────────────────────────┐
│    Resolves to internal │
│    gateway IPs          │
└─────────────────────────┘
```

## Hubble Network Observability (Optional)

Cilium's observability layer providing deep visibility into network flows.

### Configuration

Enable via `cluster.yaml`:
```yaml
hubble_enabled: true        # Enable Hubble relay and metrics
hubble_ui_enabled: true     # Enable Hubble UI (optional)
```

### Features When Enabled

- **Hubble Relay**: Aggregates flows from all nodes
- **Hubble UI**: Web interface for flow visualization
- **Metrics Export**: Prometheus integration via ServiceMonitor
- **Flow Types**: DNS, TCP, HTTP, ICMP, drop events

### Commands

```bash
# CLI status (requires port-forward or Hubble CLI installed)
hubble status
hubble observe

# Flow queries
hubble observe --namespace <ns>
hubble observe --pod <pod-name>
hubble observe --protocol tcp
hubble observe --verdict DROPPED

# Port-forward for Hubble CLI access
kubectl -n kube-system port-forward svc/hubble-relay 4245:80

# Hubble UI access (if enabled)
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
# Visit http://localhost:12000

# Check from Cilium agent
kubectl -n kube-system exec -it ds/cilium -- hubble observe
```

### Integration with Observability Stack

When `monitoring_enabled: true` and `hubble_enabled: true`:
- Hubble metrics are scraped by Prometheus
- Grafana dashboards are automatically provisioned
- Metrics include: dns queries, drops, tcp flows, http requests

## CiliumNetworkPolicies (Zero-Trust Networking)

Optional network segmentation layer providing L3-L7 policy enforcement. Policies define explicit ingress/egress rules per workload.

### Configuration

Enable via `cluster.yaml`:
```yaml
network_policies_enabled: true   # Enable network policies
network_policies_mode: "audit"   # "audit" (observe) or "enforce" (block)
```

### Modes

| Mode | `enableDefaultDeny` | Behavior |
| ---- | ------------------- | -------- |
| `audit` | `false` | Policies observe but don't block; use Hubble to monitor |
| `enforce` | `true` | Non-matching traffic actively blocked |

**Recommended workflow:** Start in `audit` mode → monitor with Hubble → switch to `enforce` after validation.

### Policy Types

| CRD | Scope | Use Case |
| --- | ----- | -------- |
| `CiliumNetworkPolicy` (CNP) | Namespace | App-specific rules |
| `CiliumClusterwideNetworkPolicy` (CCNP) | Cluster | Cross-namespace/global rules |

### Covered Namespaces

When `network_policies_enabled: true`:

- **cluster-policies**: Cluster-wide DNS and API server access
- **kube-system**: CoreDNS, metrics-server, Spegel, Reloader, Hubble UI/Relay (if hubble_enabled)
- **monitoring**: Prometheus, Grafana, AlertManager, Loki, Tempo, Alloy
- **flux-system**: Flux controllers
- **cert-manager**: Controller, webhook, cainjector
- **network**: Envoy Gateway, Cloudflare Tunnel, external-dns, k8s-gateway
- **storage**: RustFS S3-compatible storage (if rustfs_enabled)
- **cache**: Dragonfly Redis-compatible cache (if dragonfly_enabled)
- **identity**: Keycloak OIDC provider (if keycloak_enabled)
- **ai-system**: LiteLLM, Langfuse (if litellm_enabled or langfuse_enabled)

### Policy Structure

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: app-policy
  namespace: myapp
spec:
  description: "Policy description"
  endpointSelector:
    matchLabels:
      app: myapp
  enableDefaultDeny:
    egress: false  # audit mode
    ingress: false
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

### Cilium Entities

Special selectors for common destinations:

| Entity | Matches |
| ------ | ------- |
| `kube-apiserver` | Kubernetes API server |
| `host` | Node host networking |
| `world` | All external traffic (0.0.0.0/0) |
| `cluster` | All in-cluster endpoints |
| `remote-node` | Other Kubernetes nodes |

### Debugging

```bash
# Monitor policy verdicts via Hubble
hubble observe --verdict DROPPED
hubble observe --verdict AUDIT
hubble observe --namespace <ns> --verdict DROPPED

# List deployed policies
kubectl get cnp -A       # Namespace-scoped
kubectl get ccnp -A      # Cluster-wide

# Inspect policy details
kubectl describe cnp -n <ns> <name>
kubectl get cnp -n <ns> <name> -o yaml

# Debug pod connectivity
hubble observe --from-pod <ns>/<pod> --verdict DROPPED
hubble observe --to-pod <ns>/<pod> --verdict DROPPED

# Check Cilium endpoint policy status
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list
kubectl -n kube-system exec -it ds/cilium -- cilium policy get -n <ns>
```

### Transition: Audit → Enforce

1. Deploy with `network_policies_mode: "audit"`
2. Monitor for 24-48 hours via Hubble
3. Review `AUDIT` verdicts for legitimate traffic
4. Adjust policies as needed
5. Change to `network_policies_mode: "enforce"` in `cluster.yaml`
6. Run `task configure` and commit changes

## CLI Reference

| Command | Description |
| --------- | ------------- |
| `cilium status` | Overall Cilium health |
| `cilium connectivity test` | Full connectivity test |
| `cilium bpf lb list` | LoadBalancer BPF entries |
| `cilium endpoint list` | List all endpoints |
| `cilium service list` | List all services |
| `cilium monitor` | Real-time packet monitoring |
| `hubble observe --verdict DROPPED` | Policy-blocked traffic |
| `kubectl get cnp -A` | List CiliumNetworkPolicies |
| `kubectl get ccnp -A` | List CiliumClusterwideNetworkPolicies |
