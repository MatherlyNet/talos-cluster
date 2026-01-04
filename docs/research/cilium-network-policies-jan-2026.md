# CiliumNetworkPolicy Implementation Research

**Date:** January 2026
**Status:** Research Complete
**Source:** Review Follow-Up Item #11 from `docs/REVIEW-FOLLOWUP-JAN-2026.md`

---

## Executive Summary

This document provides comprehensive research for implementing CiliumNetworkPolicies across the matherlynet-talos-cluster. The goal is to establish **zero-trust network segmentation** while maintaining operational functionality.

### Key Findings

1. **Zero-Trust Foundation Required**: Default-deny policies with explicit allowlists
2. **Bidirectional Control**: Both ingress AND egress rules needed for true zero-trust
3. **Phased Rollout Recommended**: Use `enableDefaultDeny: false` initially for audit mode
4. **Entity-Based Rules**: Leverage Cilium's `kube-apiserver`, `world`, `host`, `cluster` entities
5. **Layer 7 Policies**: Optional but available for HTTP/DNS filtering

---

## Cluster Namespace Inventory

### Priority 1: Core Infrastructure (Implement First)

| Namespace | Components | Network Requirements |
| ----------- | ----------- | --------------------- |
| `kube-system` | Cilium, CoreDNS, metrics-server, Reloader, Talos CCM, Spegel, Hubble | Complex inter-dependencies |
| `flux-system` | Flux Operator, Flux Instance (source-controller, kustomize-controller, helm-controller, notification-controller) | Git repos, OCI registries, kube-apiserver |

### Priority 2: Security-Sensitive Namespaces

| Namespace | Components | Network Requirements |
| ----------- | ----------- | --------------------- |
| `cert-manager` | cert-manager controller, webhook, cainjector | ACME (Let's Encrypt), DNS providers, kube-apiserver |
| `external-secrets` (optional) | External Secrets Operator | Vault/1Password/AWS SM endpoints, kube-apiserver |

### Priority 3: Observability Stack

| Namespace | Components | Network Requirements |
| ----------- | ----------- | --------------------- |
| `monitoring` | VictoriaMetrics (vmsingle, vmagent), Grafana, AlertManager, Loki, Tempo, Alloy, node-exporter, kube-state-metrics | Scrape all namespaces, receive logs/traces |

### Priority 4: Application Ingress

| Namespace | Components | Network Requirements |
| ----------- | ----------- | --------------------- |
| `network` | Envoy Gateway, Cloudflare Tunnel, external-dns (cloudflare-dns/unifi-dns), k8s-gateway | External traffic, Cloudflare API, DNS |

### Priority 5: Optional Namespaces

| Namespace | Components | Network Requirements |
| ----------- | ----------- | --------------------- |
| `csi-proxmox` (optional) | Proxmox CSI driver | Proxmox API |
| `system-upgrade` | tuppr (Talos upgrade controller) | Talos API, container registries |
| `default` | Echo test app | Gateway ingress only |

---

## Cilium Entity Reference

From [Cilium Policy Language Documentation](https://docs.cilium.io/en/stable/security/policy/language/):

| Entity | Description | Use Case |
| -------- | ----------- | ---------- |
| `host` | Local node including host-networked pods | Node metrics, kubelet |
| `remote-node` | Other nodes in the cluster | Inter-node communication |
| `kube-apiserver` | Kubernetes API server | All controllers need this |
| `cluster` | All endpoints inside the cluster | Intra-cluster traffic |
| `world` | All endpoints outside the cluster | External APIs, registries |
| `ingress` | Cilium Envoy L7 ingress | Gateway traffic |
| `all` | Everything (whitelists all) | Development/debugging only |

---

## Implementation Strategy

### Phase 1: Baseline Default-Deny with Audit Mode

Start with cluster-wide policies that don't enable default-deny, allowing traffic observation via Hubble.

```yaml
#| CiliumClusterwideNetworkPolicy for DNS without enabling default-deny #|
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-dns-cluster-wide
spec:
  description: "Allow DNS queries to CoreDNS - does not enable default-deny"
  endpointSelector:
    matchExpressions:
      - key: io.kubernetes.pod.namespace
        operator: NotIn
        values: ["kube-system"]
  enableDefaultDeny:
    egress: false
    ingress: false
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

### Phase 2: Namespace-Level Default-Deny

Apply namespace-scoped default-deny policies:

```yaml
#| Per-namespace default-deny template #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny
  namespace: monitoring
spec:
  description: "Default deny all traffic in monitoring namespace"
  endpointSelector: {}
  ingress:
    - {}
  egress:
    - {}
```

### Phase 3: Add Explicit Allow Rules

Layer on specific allow rules per component.

---

## Detailed Policy Specifications

### 1. Monitoring Namespace Policies

#### VictoriaMetrics vmsingle
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: vmsingle
  namespace: monitoring
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vmsingle
  ingress:
    # From vmagent (metrics push)
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "8429"
              protocol: TCP
    # From Grafana (queries)
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: grafana
      toPorts:
        - ports:
            - port: "8429"
              protocol: TCP
  egress:
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### VMAgent
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: vmagent
  namespace: monitoring
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vmagent
  ingress: []
  egress:
    # To vmsingle (push metrics)
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: vmsingle
      toPorts:
        - ports:
            - port: "8429"
              protocol: TCP
    # To kube-apiserver (service discovery)
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # To all pods for scraping (cluster-wide)
    - toEntities:
        - cluster
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
            - port: "9100"
              protocol: TCP
            - port: "9153"
              protocol: TCP
            - port: "8080"
              protocol: TCP
            - port: "8429"
              protocol: TCP
            - port: "10250"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### Grafana
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: grafana
  namespace: monitoring
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  ingress:
    # From envoy gateway (user access)
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
            gateway.networking.k8s.io/gateway-name: internal
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
  egress:
    # To vmsingle (queries)
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: vmsingle
      toPorts:
        - ports:
            - port: "8429"
              protocol: TCP
    # To Loki (log queries)
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: loki
      toPorts:
        - ports:
            - port: "3100"
              protocol: TCP
    # To Tempo (trace queries)
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: tempo
      toPorts:
        - ports:
            - port: "3200"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### Alloy (Log/Trace Collector)
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: alloy
  namespace: monitoring
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: alloy
  ingress:
    # OTLP traces from applications
    - fromEntities:
        - cluster
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
            - port: "4318"
              protocol: TCP
  egress:
    # To Loki (push logs)
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: loki
      toPorts:
        - ports:
            - port: "3100"
              protocol: TCP
    # To Tempo (push traces)
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: tempo
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
    # To kube-apiserver (pod discovery)
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

### 2. Flux-System Namespace Policies

#### Flux Controllers (source, kustomize, helm, notification)
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: flux-controllers
  namespace: flux-system
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/part-of: flux
  ingress:
    # Metrics scraping
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
  egress:
    # To kube-apiserver (manage resources)
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # To GitHub/GitLab (source repos) - FQDN or world
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "22"
              protocol: TCP
    # To OCI registries (Helm charts, images)
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

### 3. Cert-Manager Namespace Policies

Based on [cert-manager best practices](https://cert-manager.io/docs/installation/best-practice/):

#### cert-manager Controller
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cert-manager-controller
  namespace: cert-manager
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/instance: cert-manager
  ingress:
    # Metrics scraping
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "9402"
              protocol: TCP
  egress:
    # To kube-apiserver
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # To ACME providers (Let's Encrypt)
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    # DNS for DNS01 challenges
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    # Internal DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### cert-manager Webhook
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cert-manager-webhook
  namespace: cert-manager
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/component: webhook
      app.kubernetes.io/instance: cert-manager
  ingress:
    # From kube-apiserver (admission webhooks)
    - fromEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "10250"
              protocol: TCP
    # From host (health checks)
    - fromEntities:
        - host
      toPorts:
        - ports:
            - port: "6080"
              protocol: TCP
  egress:
    # To kube-apiserver
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

### 4. Network Namespace Policies

#### Cloudflare Tunnel (cloudflared)
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cloudflare-tunnel
  namespace: network
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: cloudflare-tunnel
  ingress:
    # Metrics scraping
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
  egress:
    # To Cloudflare (tunnel establishment)
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "7844"
              protocol: UDP
    # To envoy-external gateway (forward requests)
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
            gateway.networking.k8s.io/gateway-name: external
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### Envoy Gateway
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: envoy-gateway
  namespace: network
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: envoy-gateway
  ingress:
    # From cloudflare-tunnel
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: cloudflare-tunnel
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    # From external (LoadBalancer)
    - fromEntities:
        - world
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
    # Metrics
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "19001"
              protocol: TCP
  egress:
    # To backend services (all namespaces)
    - toEntities:
        - cluster
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
            - port: "8080"
              protocol: TCP
    # To kube-apiserver (gateway configuration)
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### external-dns (Cloudflare)
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cloudflare-dns
  namespace: network
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: external-dns
  ingress:
    # Metrics
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "7979"
              protocol: TCP
  egress:
    # To Cloudflare API
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    # To kube-apiserver
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

### 5. Kube-System Namespace Policies

**Note**: kube-system requires careful policy design as it hosts critical cluster components.

#### CoreDNS
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: coredns
  namespace: kube-system
spec:
  endpointSelector:
    matchLabels:
      k8s-app: kube-dns
  ingress:
    # From all pods (DNS queries)
    - fromEntities:
        - cluster
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    # Metrics
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "9153"
              protocol: TCP
  egress:
    # To upstream DNS (Cloudflare, etc.)
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
            - port: "443"
              protocol: TCP
    # To kube-apiserver
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
```

#### Metrics Server
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  endpointSelector:
    matchLabels:
      k8s-app: metrics-server
  ingress:
    # From kube-apiserver (aggregated API)
    - fromEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "10250"
              protocol: TCP
  egress:
    # To kubelets (scrape metrics)
    - toEntities:
        - host
        - remote-node
      toPorts:
        - ports:
            - port: "10250"
              protocol: TCP
    # To kube-apiserver
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # DNS
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

---

## Cluster-Wide Policies

### Global DNS Allow (Without Default-Deny)

Deploy first to ensure DNS works before enabling default-deny:

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-dns-all
spec:
  description: "Allow all pods to query CoreDNS"
  endpointSelector:
    matchExpressions:
      - key: io.kubernetes.pod.namespace
        operator: NotIn
        values: ["kube-system"]
  enableDefaultDeny:
    egress: false
    ingress: false
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

### Global Kube-APIServer Allow

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-kube-apiserver
spec:
  description: "Allow controllers to access kube-apiserver"
  endpointSelector:
    matchExpressions:
      - key: app.kubernetes.io/part-of
        operator: In
        values: ["flux", "cert-manager"]
  enableDefaultDeny:
    egress: false
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
```

---

## Implementation Roadmap

### Week 1: Preparation & Observation

1. **Enable Hubble** if not already enabled (`hubble_enabled: true`)
2. **Deploy observation policies** with `enableDefaultDeny: false`
3. **Observe traffic patterns** using `hubble observe`
4. **Document unexpected flows** that need allowlisting

### Week 2: Monitoring Namespace (Priority 1)

1. Deploy `monitoring/default-deny.yaml`
2. Deploy allow policies for each component
3. Verify Grafana, VictoriaMetrics, Alloy functionality
4. Validate metrics scraping still works

### Week 3: Flux-System Namespace (Priority 1)

1. Deploy `flux-system/default-deny.yaml`
2. Deploy allow policies for Flux controllers
3. Verify GitOps reconciliation works
4. Validate OCI repository pulls

### Week 4: Cert-Manager & Network (Priority 2)

1. Deploy cert-manager policies
2. Verify certificate issuance (Let's Encrypt)
3. Deploy network namespace policies
4. Verify Cloudflare Tunnel connectivity

### Week 5: Kube-System & Final Validation

1. Carefully deploy kube-system policies (highest risk)
2. Deploy cluster-wide policies
3. Full connectivity testing
4. Document final policy set

---

## Testing Strategy

Based on [CNCF Best Practices](https://www.cncf.io/blog/2025/11/06/safely-managing-cilium-network-policies-in-kubernetes-testing-and-simulation-techniques/):

### 1. Audit Mode First

Use `enableDefaultDeny: false` on initial policies to observe without blocking.

### 2. Hubble Observability

```bash
#| Monitor policy verdicts #|
hubble observe --verdict DROPPED
hubble observe --verdict AUDIT

#| Check specific namespace #|
hubble observe --namespace monitoring --verdict DROPPED
```

### 3. Gradual Enforcement

1. Deploy audit policies (enableDefaultDeny: false)
2. Monitor for 24-48 hours
3. Convert to enforcement (enableDefaultDeny: true)
4. Monitor for issues

### 4. Rollback Plan

Keep previous policy state in Git. If issues occur:
```bash
git revert HEAD
flux reconcile ks network-policies --with-source
```

---

## File Structure for Implementation

```
templates/config/kubernetes/apps/
├── kube-system/
│   └── network-policies/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── coredns.yaml.j2
│           ├── metrics-server.yaml.j2
│           └── default-deny.yaml.j2
├── monitoring/
│   └── network-policies/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── vmsingle.yaml.j2
│           ├── vmagent.yaml.j2
│           ├── grafana.yaml.j2
│           ├── alloy.yaml.j2
│           └── default-deny.yaml.j2
├── flux-system/
│   └── network-policies/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── flux-controllers.yaml.j2
│           └── default-deny.yaml.j2
├── cert-manager/
│   └── network-policies/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── controller.yaml.j2
│           ├── webhook.yaml.j2
│           └── default-deny.yaml.j2
├── network/
│   └── network-policies/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── cloudflare-tunnel.yaml.j2
│           ├── envoy-gateway.yaml.j2
│           ├── external-dns.yaml.j2
│           └── default-deny.yaml.j2
└── cluster-policies/
    └── network-policies/
        ├── ks.yaml.j2
        └── app/
            ├── kustomization.yaml.j2
            ├── allow-dns.yaml.j2
            └── allow-kube-apiserver.yaml.j2
```

---

## Configuration Variable

Add to `cluster.yaml`:

```yaml
#| Enable CiliumNetworkPolicies (default: false) #|
network_policies_enabled: false

#| Network policy enforcement mode: audit or enforce #|
network_policies_mode: "audit"  # or "enforce"
```

---

## Official Cilium Examples (from GitHub)

Reference: [cilium/cilium/examples/policies](https://github.com/cilium/cilium/tree/main/examples/policies)

### Egress Default-Deny Pattern

```yaml
#| From: examples/policies/l3/egress-default-deny/egress-default-deny.yaml #|
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "deny-all-egress"
spec:
  endpointSelector:
    matchLabels:
      role: restricted
  egress:
  - {}
```

**Key insight**: Empty egress rule `{}` denies all outbound traffic by default.

### CIDR-Based Policy with Exceptions

```yaml
#| From: examples/policies/l3/cidr/cidr.yaml #|
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "cidr-rule"
spec:
  endpointSelector:
    matchLabels:
      app: myService
  egress:
  - toCIDR:
    - 20.1.1.1/32
  - toCIDRSet:
    - cidr: 10.0.0.0/8
      except:
      - 10.96.0.0/12  # Exclude K8s service CIDR
```

**Key insight**: Use `except` to exclude sensitive IP ranges from broader CIDR allowlists.

### Service-Based Policy

```yaml
#| From: examples/policies/l3/service/service.yaml #|
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "service-rule"
spec:
  endpointSelector:
    matchLabels:
      id: app2
  egress:
  - toServices:
    - k8sService:
        serviceName: myservice
        namespace: default
    - k8sServiceSelector:
        selector:
          matchLabels:
            env: staging
        namespace: another-namespace
```

**Key insight**: Reference K8s services by name OR by label selector across namespaces.

### DNS Layer 7 Policy (FQDN Filtering)

```yaml
#| From: examples/policies/l7/dns/dns.yaml #|
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "dns-visibility"
spec:
  endpointSelector:
    matchLabels:
      org: alliance
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchName: "cilium.io"
        - matchPattern: "*.cilium.io"
        - matchPattern: "*.api.cilium.io"
  - toFQDNs:
    - matchName: "cilium.io"
    - matchName: "sub.cilium.io"
    - matchPattern: "special*service.api.cilium.io"
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

**Key insight**: Combine DNS rules (for visibility/filtering) with FQDN rules (for egress to specific domains).

### HTTP Layer 7 Policy (Method/Path/Header Filtering)

```yaml
#| From: examples/policies/l7/http/http.yaml #|
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "l7-rule"
spec:
  endpointSelector:
    matchLabels:
      app: myService
  ingress:
  - toPorts:
    - ports:
      - port: '80'
        protocol: TCP
      rules:
        http:
        - method: GET
          path: "/path1$"
        - method: PUT
          path: "/path2$"
          headers:
          - 'X-My-Header: true'
```

**Key insight**: Layer 7 policies can filter by HTTP method, path regex, and headers.

### FQDN-Based Egress Policy

```yaml
#| From: examples/policies/l3/fqdn/fqdn.yaml #|
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "fqdn-rule"
spec:
  endpointSelector:
    matchLabels:
      app: test-app
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
  - toFQDNs:
    - matchName: "my-remote-service.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
```

**Key insight**: FQDN policies require DNS egress to CoreDNS for domain resolution.

---

## Cilium Examples Directory Structure

From [github.com/cilium/cilium/examples](https://github.com/cilium/cilium/tree/main/examples):

| Directory | Purpose | Relevance |
| ----------- | ----------- | ----------- |
| `policies/l3` | IP/CIDR, entity, service policies | HIGH - Core L3/L4 rules |
| `policies/l7` | DNS, HTTP, Kafka policies | MEDIUM - Optional L7 filtering |
| `policies/kubernetes` | Namespace, ServiceAccount policies | HIGH - K8s-native patterns |
| `policies/host` | Host-level policies | LOW - Usually not needed |
| `kubernetes-dns` | DNS policy examples | HIGH - DNS visibility |
| `kubernetes-egress-gateway` | Egress gateway patterns | LOW - Advanced use case |
| `hubble` | Observability setup | HIGH - Traffic monitoring |

---

## Sources & References

- [Cilium Network Policy Documentation](https://docs.cilium.io/en/stable/network/kubernetes/policy/)
- [Cilium Policy Language (Entities, CIDR, Ports)](https://docs.cilium.io/en/stable/security/policy/language/)
- [Cilium GitHub Examples](https://github.com/cilium/cilium/tree/main/examples/policies)
- [Zero Trust K3s Network with Cilium (2025)](https://mmacleod.ca/2025/04/zero-trust-k3s-network-with-cilium/)
- [Mastering Cilium Network Policies: Zero-Trust Security](https://yogender027mae.medium.com/mastering-cilium-network-policies-zero-trust-security-for-kubernetes-58cc00518602)
- [CNCF: Safely Managing Cilium Network Policies (2025)](https://www.cncf.io/blog/2025/11/06/safely-managing-cilium-network-policies-in-kubernetes-testing-and-simulation-techniques/)
- [cert-manager Best Practices](https://cert-manager.io/docs/installation/best-practice/)
- [Azure AKS Network Policy Best Practices](https://learn.microsoft.com/en-us/azure/aks/network-policy-best-practices)
- [Flux Prometheus Monitoring](https://toolkit.fluxcd.io/guides/monitoring/)

---

## Next Steps

1. [ ] Review this document with project owner
2. [ ] Confirm Hubble is enabled for traffic observation
3. [ ] Create template files for network policies
4. [ ] Test in development environment first
5. [ ] Document any additional service dependencies discovered
6. [ ] Update `docs/REVIEW-FOLLOWUP-JAN-2026.md` with implementation status
