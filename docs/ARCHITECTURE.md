# Architecture Documentation

> Comprehensive architecture guide for matherlynet-talos-cluster

## System Overview

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                     INTERNET                                │
                                    └───────────────────────────┬─────────────────────────────────┘
                                                                │
                                                                ▼
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │               Cloudflare (DNS + Tunnel)                     │
                                    │    ┌─────────────────┐    ┌─────────────────────────────┐   │
                                    │    │  external-dns   │    │     cloudflared tunnel      │   │
                                    │    │  (DNS records)  │    │   (secure ingress proxy)    │   │
                                    │    └─────────────────┘    └─────────────────────────────┘   │
                                    └───────────────────────────┬─────────────────────────────────┘
                                                                │
        ┌───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────┐
        │                                          Kubernetes Cluster                                                   │
        │                                                       │                                                       │
        │  ┌────────────────────────────────────────────────────┼────────────────────────────────────────────────────┐  │
        │  │                                    Envoy Gateway (Gateway API)                                          │  │
        │  │              ┌────────────────────────┐            │           ┌────────────────────────┐               │  │
        │  │              │   envoy-external       │◄───────────┘           │    envoy-internal      │               │  │
        │  │              │  (public traffic)      │                        │   (private traffic)    │               │  │
        │  │              └────────────┬───────────┘                        └───────────┬────────────┘               │  │
        │  └───────────────────────────┼────────────────────────────────────────────────┼────────────────────────────┘  │
        │                              │                                                │                               │
        │  ┌───────────────────────────┼────────────────────────────────────────────────┼────────────────────────────┐  │
        │  │                           │              Application Namespaces            │                            │  │
        │  │              ┌────────────┴───────────┐                        ┌───────────┴────────────┐               │  │
        │  │              │       HTTPRoutes       │                        │      HTTPRoutes        │               │  │
        │  │              │   (public services)    │                        │  (internal services)   │               │  │
        │  │              └────────────────────────┘                        └────────────────────────┘               │  │
        │  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
        │                                                                                                               │
        │  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
        │  │                                          Infrastructure Layer                                           │  │
        │  │    ┌───────────┐  ┌───────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │  │
        │  │    │  Cilium   │  │  CoreDNS  │  │   Spegel   │  │  Reloader  │  │ split DNS  │  │   cert-manager     │  │  │
        │  │    │   (CNI)   │  │   (DNS)   │  │  (images)  │  │ (reload)   │  │(k8s-gw/unifi)│  │   (TLS certs)      │  │  │
        │  │    └───────────┘  └───────────┘  └────────────┘  └────────────┘  └────────────┘  └────────────────────┘  │  │
        │  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
        │                                                                                                               │
        │  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
        │  │                                            GitOps Layer                                                 │  │
        │  │    ┌─────────────────────────────────────────┐    ┌─────────────────────────────────────────────────┐   │  │
        │  │    │            Flux Operator                │    │              Flux Instance                      │   │  │
        │  │    │  (manages Flux installation)            │    │   (GitRepository → Kustomization → HelmRelease) │   │  │
        │  │    └─────────────────────────────────────────┘    └─────────────────────────────────────────────────┘   │  │
        │  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
        │                                                                                                               │
        └───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                                                │
        ┌───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────┐
        │                                           Talos Linux Nodes                                                   │
        │    ┌──────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐                          │
        │    │   Control Plane 1    │    │   Control Plane 2    │    │   Control Plane 3    │   (HA: 3+ controllers)   │
        │    │   ┌──────────────┐   │    │   ┌──────────────┐   │    │   ┌──────────────┐   │                          │
        │    │   │     etcd     │   │    │   │     etcd     │   │    │   │     etcd     │   │                          │
        │    │   └──────────────┘   │    │   └──────────────┘   │    │   └──────────────┘   │                          │
        │    │   VIP: cluster_api   │    │   VIP: cluster_api   │    │   VIP: cluster_api   │                          │
        │    └──────────────────────┘    └──────────────────────┘    └──────────────────────┘                          │
        └───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Component Layers

### Layer 1: Operating System (Talos Linux)

Talos Linux is an immutable, API-driven OS designed specifically for Kubernetes:

| Feature | Description |
| ---------------- | ------------- |
| **Immutable** | No SSH, no shell - managed entirely via API |
| **Secure Boot** | Optional TPM-based disk encryption |
| **Minimal** | ~50MB compressed, boots in seconds |
| **API-driven** | Configured via `talosctl` and YAML patches |

**Configuration Flow:**

```
talconfig.yaml → talhelper genconfig → clusterconfig/*.yaml → talosctl apply
```

### Layer 2: Networking (Cilium CNI)

Cilium provides advanced networking with eBPF:

| Feature | Configuration |
| ---------------- | -------------- |
| **Routing Mode** | Native (no overlay) |
| **kube-proxy** | Replaced (kubeProxyReplacement: true) |
| **Load Balancer** | L2 announcements (MetalLB replacement) |
| **LB Algorithm** | Maglev (DSR or SNAT mode) |
| **BGP** | Optional (cilium_bgp_enabled) |

**Key IPs:**

- `cluster_gateway_addr` → envoy-internal LB
- `cloudflare_gateway_addr` → envoy-external LB
- `cluster_dns_gateway_addr` → k8s-gateway or unifi-dns LB

### Layer 3: Ingress (Envoy Gateway)

Gateway API implementation with two entry points:

| Gateway | Purpose | Access |
| ---------------- | --------- | -------- |
| `envoy-internal` | Private services | Local network only |
| `envoy-external` | Public services | Via Cloudflare tunnel |

**TLS:** Wildcard certificate from Let's Encrypt via cert-manager.

### Layer 4: GitOps (Flux CD)

Declarative cluster management:

```
Git Repository
     │
     ▼
┌─────────────────┐
│  GitRepository  │  (source-controller)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Kustomization  │  (kustomize-controller)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  HelmRelease    │  (helm-controller)
└────────┬────────┘
         │
         ▼
    Kubernetes Resources
```

**Reconciliation:** Every 30m or on Git push (via webhook).

## Directory Structure (Post-Configure)

```
kubernetes/
├── apps/                          # Application definitions
│   ├── cert-manager/
│   │   ├── namespace.yaml
│   │   ├── kustomization.yaml
│   │   └── cert-manager/
│   │       ├── ks.yaml            # Flux Kustomization
│   │       └── app/
│   │           ├── helmrelease.yaml
│   │           ├── ocirepository.yaml
│   │           ├── kustomization.yaml
│   │           └── *.sops.yaml    # Encrypted secrets
│   ├── default/
│   ├── flux-system/
│   ├── kube-system/
│   └── network/
├── components/
│   └── sops/                      # Shared SOPS config
└── flux/
    └── cluster/
        └── ks.yaml                # Root Kustomization

talos/
├── talconfig.yaml                 # Node definitions
├── talenv.yaml                    # Version pins
├── talsecret.sops.yaml            # Encrypted secrets
├── clusterconfig/                 # Generated configs
│   ├── talosconfig
│   └── kubernetes-*.yaml          # Per-node configs
└── patches/
    ├── global/                    # All nodes
    ├── controller/                # Control plane only
    └── worker/                    # Worker nodes only

bootstrap/
├── helmfile.d/
│   ├── 00-crds.yaml               # CRD installation
│   └── 01-apps.yaml               # Bootstrap apps
├── github-deploy-key.sops.yaml    # Flux Git access
└── sops-age.sops.yaml             # SOPS decryption key
```

## Application Pattern

Every application follows this structure:

```yaml
# ks.yaml - Flux Kustomization
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  namespace: flux-system
spec:
  targetNamespace: myapp-namespace
  path: ./kubernetes/apps/namespace/myapp/app
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: another-app  # Optional dependency chain
```

```yaml
# app/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
spec:
  chartRef:
    kind: OCIRepository
    name: myapp
  values:
    # Application-specific values
```

## Secret Management

SOPS with Age encryption:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: .*\.sops\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxx  # Public key
```

**Encryption Flow:**

```
plaintext → sops encrypt → *.sops.yaml → git push → Flux → sops decrypt → Kubernetes Secret
```

## Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              node_cidr (e.g., 192.168.1.0/24)               │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │  Control Node 1 │  │  Control Node 2 │  │  Control Node 3 │              │
│  │  192.168.1.10   │  │  192.168.1.11   │  │  192.168.1.12   │              │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘              │
│           │                    │                    │                       │
│           └────────────────────┼────────────────────┘                       │
│                                │                                            │
│                    ┌───────────┴───────────┐                                │
│                    │  VIP: cluster_api_addr│  (floating, shared via Talos)  │
│                    │  e.g., 192.168.1.100  │                                │
│                    └───────────────────────┘                                │
│                                                                             │
│  Load Balancer IPs (Cilium L2):                                             │
│  ┌───────────────────────┐  ┌────────────────────────┐  ┌────────────────┐  │
│  │cluster_gateway_addr   │  │cloudflare_gateway_addr │  │cluster_dns_gw  │  │
│  │ 192.168.1.101         │  │ 192.168.1.102          │  │ 192.168.1.103  │  │
│  │ (envoy-internal)      │  │ (envoy-external)       │  │(k8s-gw/unifi)  │  │
│  └───────────────────────┘  └────────────────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘

Pod Network: cluster_pod_cidr (default: 10.42.0.0/16)
Service Network: cluster_svc_cidr (default: 10.43.0.0/16)
```

## DNS Resolution

### External DNS (Public)

```
User → Cloudflare DNS → cloudflared tunnel → envoy-external → Service
```

- Managed by `external-dns` + Cloudflare provider
- Only `envoy-external` gateway apps are public

### Split DNS (Internal)

```
# Using k8s-gateway (default):
Internal Device → Home DNS → k8s-gateway → Service (via envoy-internal)

# Using unifi-dns (when unifi_host + unifi_api_key configured):
Internal Device → UniFi Controller DNS → Service (via envoy-internal)
```

**Note:** When UniFi DNS is configured, k8s-gateway is disabled and DNS records are written directly to the UniFi controller.

**Home DNS Configuration:**
Forward `cloudflare_domain` queries to `cluster_dns_gateway_addr`.

## Security Model

| Layer | Mechanism |
| ---------------- | ----------- |
| **OS** | Immutable Talos, no SSH/shell |
| **Secrets** | SOPS + Age encryption at rest |
| **Network** | Cilium NetworkPolicies |
| **Ingress** | Cloudflare tunnel (no exposed ports) |
| **TLS** | cert-manager wildcard certificates |
| **GitOps** | Deploy key with limited permissions |

## Upgrade Paths

### Talos Version Upgrade

```bash
task talos:upgrade-node IP=192.168.1.10
```

### Kubernetes Version Upgrade

```bash
# Update talenv.yaml: kubernetesVersion
task talos:upgrade-k8s
```

### Application Upgrades

```yaml
# Managed by Renovate PRs
# Merge PR → Flux auto-reconciles
```

## Dependency Graph

```
                     ┌─────────────────────────────────────┐
                     │           Talos Bootstrap           │
                     │   (bootstrap:talos → nodes ready)   │
                     └─────────────────────┬───────────────┘
                                           │
                     ┌─────────────────────┴───────────────┐
                     │          bootstrap:apps             │
                     │     (helmfile → initial deploy)     │
                     └─────────────────────┬───────────────┘
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         │                                 │                                 │
         ▼                                 ▼                                 ▼
┌─────────────────┐              ┌─────────────────┐              ┌─────────────────┐
│     Cilium      │              │     CoreDNS     │              │     Spegel      │
│  (CNI + LB)     │              │  (cluster DNS)  │              │  (P2P images)   │
└────────┬────────┘              └────────┬────────┘              └─────────────────┘
         │                                │
         │                                │
         ▼                                ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              Flux Operator + Instance                               │
│                        (GitOps takes over from helmfile)                            │
└───────────────────────────────────────────┬─────────────────────────────────────────┘
                                            │
    ┌───────────────────┬───────────────────┼───────────────────┬─────────────────────┐
    │                   │                   │                   │                     │
    ▼                   ▼                   ▼                   ▼                     ▼
┌───────────┐  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐
│cert-manager│  │ envoy-gateway │  │cloudflare-dns  │  │   talos-ccm    │  │      tuppr       │
│(TLS certs) │  │  (ingress)    │  │ (external-dns) │  │(node lifecycle)│  │(auto upgrades)   │
└─────┬─────┘  └───────┬────────┘  └────────────────┘  └────────────────┘  └──────────────────┘
      │                │                                                          │
      │                │                              ┌───────────────────────────┘
      │                │                              │
      │                │                   ┌──────────┴──────────┐
      │                │                   │    talos-backup     │
      │                │                   │ (etcd snapshots)    │
      │                │                   │  [optional: S3]     │
      │                │                   └─────────────────────┘
      ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              Application Workloads                                  │
│                     (default/echo, custom apps, etc.)                               │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

**Last Updated:** January 13, 2026
**Talos Linux:** v1.12.1
**Kubernetes:** v1.35.0
**Flux CD:** v2.7.5 (via Flux Operator v0.38.1)
**Cilium CNI:** Native routing mode, kube-proxy replacement enabled
