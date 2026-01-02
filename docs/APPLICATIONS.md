# Application Reference

> Detailed documentation for all included applications

## Application Index

| Namespace | Application | Purpose | Dependencies |
| ----------- | ------------- | --------- | -------------- |
| `kube-system` | [Cilium](#cilium) | CNI + Load Balancer | None (bootstrapped) |
| `kube-system` | [CoreDNS](#coredns) | Cluster DNS | Cilium |
| `kube-system` | [Spegel](#spegel) | P2P Image Distribution | Cilium |
| `kube-system` | [Metrics Server](#metrics-server) | Resource Metrics | Cilium |
| `kube-system` | [Reloader](#reloader) | ConfigMap/Secret Reload | Cilium |
| `flux-system` | [Flux Operator](#flux-operator) | Flux Installation | Cilium, CoreDNS |
| `flux-system` | [Flux Instance](#flux-instance) | GitOps Configuration | Flux Operator |
| `cert-manager` | [cert-manager](#cert-manager) | TLS Certificates | Flux |
| `network` | [Envoy Gateway](#envoy-gateway) | Gateway API Ingress | cert-manager |
| `network` | [external-dns](#external-dns) | Public DNS Records | Flux |
| `network` | [k8s-gateway](#k8s-gateway) | Split DNS | Flux |
| `network` | [Cloudflare Tunnel](#cloudflare-tunnel) | External Access | Flux |
| `default` | [Echo](#echo) | Test Application | Envoy Gateway |

---

## kube-system Namespace

### Cilium

**Purpose:** Container Network Interface (CNI) and kube-proxy replacement with eBPF.

**Template:** `templates/config/kubernetes/apps/kube-system/cilium/`

**Key Features:**
- Native routing (no overlay)
- L2 load balancer announcements (MetalLB replacement)
- kube-proxy replacement
- Optional BGP peering

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cluster_pod_cidr` | ipv4NativeRoutingCIDR |
| `cilium_loadbalancer_mode` | DSR or SNAT mode |
| `cilium_bgp_enabled` | Enable BGP control plane |

**Helm Values Highlights:**
```yaml
kubeProxyReplacement: true
l2announcements:
  enabled: true
loadBalancer:
  algorithm: maglev
  mode: "dsr"  # or "snat"
routingMode: native
```

**Troubleshooting:**
```bash
cilium status
cilium connectivity test
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list
```

---

### CoreDNS

**Purpose:** Cluster DNS server for service discovery.

**Template:** `templates/config/kubernetes/apps/kube-system/coredns/`

**Notes:**
- Replaces Talos-bundled CoreDNS
- Managed by Flux for consistent configuration

**Troubleshooting:**
```bash
kubectl -n kube-system logs deploy/coredns
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes
```

---

### Spegel

**Purpose:** Peer-to-peer container image distribution.

**Template:** `templates/config/kubernetes/apps/kube-system/spegel/`

**Condition:** Only enabled when `nodes | length > 1`

**Benefits:**
- Reduces external registry bandwidth
- Faster image pulls from peer nodes
- Works with any OCI registry

---

### Metrics Server

**Purpose:** Provides resource metrics for `kubectl top` and HPA.

**Template:** `templates/config/kubernetes/apps/kube-system/metrics-server/`

**Usage:**
```bash
kubectl top nodes
kubectl top pods -A
```

---

### Reloader

**Purpose:** Automatically restarts pods when ConfigMaps or Secrets change.

**Template:** `templates/config/kubernetes/apps/kube-system/reloader/`

**Usage:** Add annotation to deployment:
```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

---

## flux-system Namespace

### Flux Operator

**Purpose:** Manages Flux installation and lifecycle.

**Template:** `templates/config/kubernetes/apps/flux-system/flux-operator/`

**What it does:**
- Installs Flux controllers
- Manages Flux CRDs
- Handles upgrades

---

### Flux Instance

**Purpose:** Configures Flux to sync from GitHub repository.

**Template:** `templates/config/kubernetes/apps/flux-system/flux-instance/`

**Components:**
- `GitRepository` - Points to your repo
- `Receiver` - Webhook for push events
- `HTTPRoute` - Exposes webhook externally

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `repository_name` | GitHub repo (owner/name) |
| `repository_branch` | Branch to track |
| `repository_visibility` | public/private |

**Secrets Required:**
- `github-deploy-key.sops.yaml` - SSH key for Git access
- `flux-instance` secret - Webhook token

---

## cert-manager Namespace

### cert-manager

**Purpose:** Automates TLS certificate management.

**Template:** `templates/config/kubernetes/apps/cert-manager/cert-manager/`

**Features:**
- Let's Encrypt ACME issuer
- Cloudflare DNS-01 challenge
- Wildcard certificate for domain

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cloudflare_domain` | Certificate domain |
| `cloudflare_token` | API token for DNS challenge |

**ClusterIssuer:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-token
              key: token
```

**Troubleshooting:**
```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl -n cert-manager logs deploy/cert-manager
```

---

## network Namespace

### Envoy Gateway

**Purpose:** Gateway API implementation for ingress traffic.

**Template:** `templates/config/kubernetes/apps/network/envoy-gateway/`

**Gateways Created:**

| Gateway | IP Variable | Purpose |
| --------- | ------------- | --------- |
| `envoy-internal` | `cluster_gateway_addr` | Private access |
| `envoy-external` | `cloudflare_gateway_addr` | Public access (via tunnel) |

**Usage - Creating HTTPRoute:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-namespace
spec:
  parentRefs:
    - name: envoy-internal  # or envoy-external
      namespace: network
  hostnames:
    - "myapp.example.com"
  rules:
    - backendRefs:
        - name: my-service
          port: 80
```

**TLS Certificate:**
- Wildcard certificate: `*.cloudflare_domain`
- Managed by cert-manager
- Shared across all routes

---

### external-dns

**Purpose:** Automatically manages public DNS records in Cloudflare.

**Template:** `templates/config/kubernetes/apps/network/cloudflare-dns/`

**How it works:**
1. Watches HTTPRoutes with `envoy-external` parent
2. Creates/updates Cloudflare DNS records
3. Points to `cloudflare_gateway_addr` (tunnel ingress)

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cloudflare_domain` | Zone to manage |
| `cloudflare_token` | API token |

---

### k8s-gateway

**Purpose:** Split-horizon DNS for internal service discovery.

**Template:** `templates/config/kubernetes/apps/network/k8s-gateway/`

**How it works:**
1. Runs as DNS server on `cluster_dns_gateway_addr`
2. Resolves `*.cloudflare_domain` to gateway IPs
3. Home DNS forwards domain queries here

**Configuration:**
```yaml
# In your home router/Pi-hole/AdGuard:
# Forward cloudflare_domain → cluster_dns_gateway_addr
```

---

### Cloudflare Tunnel

**Purpose:** Secure external access without exposing ports.

**Template:** `templates/config/kubernetes/apps/network/cloudflare-tunnel/`

**How it works:**
1. `cloudflared` connects outbound to Cloudflare
2. Traffic flows: Internet → Cloudflare → Tunnel → `envoy-external`
3. No inbound ports required

**Required Files:**
- `cloudflare-tunnel.json` - Tunnel credentials

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cloudflare_domain` | Tunnel hostname |
| `cloudflare_gateway_addr` | Ingress destination |

---

## default Namespace

### Echo

**Purpose:** Test application to verify ingress and DNS.

**Template:** `templates/config/kubernetes/apps/default/echo/`

**Endpoints:**
- Internal: `echo.cloudflare_domain` (via `envoy-internal`)
- External: `echo.cloudflare_domain` (via `envoy-external` + tunnel)

**Testing:**
```bash
# Internal (from network with split DNS)
curl https://echo.example.com

# External (from internet)
curl https://echo.example.com

# Both should return echo server response
```

---

## Adding Custom Applications

### Template Structure

```
templates/config/kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml.j2              # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2   # For Helm charts
    ├── ocirepository.yaml.j2 # OCI source
    └── secret.sops.yaml.j2   # Optional secrets
```

### Kustomization Template (ks.yaml.j2)

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  namespace: flux-system
spec:
  targetNamespace: my-namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/my-namespace/myapp/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: envoy-gateway  # If needs ingress
```

### HelmRelease Template

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: myapp
  values:
    # Your Helm values here
```

### OCI Repository Template

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: myapp
spec:
  interval: 12h
  url: oci://ghcr.io/myorg/charts/myapp
  ref:
    tag: 1.0.0
```

### Adding to Namespace Kustomization

```yaml
# templates/config/kubernetes/apps/<namespace>/kustomization.yaml.j2
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./existing-app/ks.yaml
  - ./myapp/ks.yaml  # Add your app
```
