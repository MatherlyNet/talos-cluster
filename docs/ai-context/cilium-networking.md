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
apiVersion: cilium.io/v2alpha1
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
apiVersion: cilium.io/v2alpha1
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

## BGP Integration (Optional)

For advanced routing with upstream routers:

```yaml
# cluster.yaml
cilium_bgp_enabled: true  # Auto-detected from keys
cilium_bgp_router_addr: "192.168.1.1"
cilium_bgp_router_asn: "64512"
cilium_bgp_node_asn: "64513"
```

### BGP Peer Config

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  virtualRouters:
    - localASN: 64513
      neighbors:
        - peerAddress: 192.168.1.1/32
          peerASN: 64512
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

## Hubble (Optional)

Cilium's observability layer. Not enabled by default in this project.

To enable:
```yaml
# Add to Cilium HelmRelease values
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
```

Commands:
```bash
hubble observe
hubble observe --pod <pod-name>
hubble status
```

## CLI Reference

| Command | Description |
| --------- | ------------- |
| `cilium status` | Overall Cilium health |
| `cilium connectivity test` | Full connectivity test |
| `cilium bpf lb list` | LoadBalancer BPF entries |
| `cilium endpoint list` | List all endpoints |
| `cilium service list` | List all services |
| `cilium monitor` | Real-time packet monitoring |
