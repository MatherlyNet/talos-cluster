# Cilium Network Policies Remediation Research

> **Status**: Ready for Implementation | **Date**: January 2026
> **Validated**: 2026-01-09 (comprehensive codebase audit performed)
> **Focus**: Remaining gaps requiring network policy implementation
> **Scope**: Hubble UI (kube-system), RustFS (storage)

## Executive Summary

This document provides research-backed recommendations for implementing CiliumNetworkPolicies for the two remaining components without network policy coverage. All recommendations follow:

- **NIST SP 800-207** Zero Trust Architecture principles
- **Cilium 2025-2026** best practices for L3-L7 policy enforcement
- **Kubernetes Gateway API** ingress patterns via Envoy Gateway
- **Existing codebase patterns** for consistency

### Validation Status

| Aspect | Status | Notes |
| -------- | -------- | ------- |
| Codebase pattern alignment | ✅ Validated | Follows `dragonfly/app/networkpolicy.yaml.j2` patterns |
| Gateway label verification | ✅ Corrected | Uses `gateway.networking.k8s.io/gateway-name` (not `gateway.envoyproxy.io`) |
| RustFS consumer audit | ✅ Complete | All S3 consumers identified and documented |
| Hubble port verification | ✅ Corrected | HTTPRoute targets port 80, UI listens on 8081 |
| `enableDefaultDeny` pattern | ✅ Added | Mode-based enforcement per codebase convention |

## Gap Analysis

| Component | Namespace | Current State | Risk Level |
| ----------- | ----------- | --------------- | ------------ |
| Hubble UI | kube-system | ❌ No policy | **HIGH** - Exposes network observability data |
| RustFS | storage | ❌ No policy | **HIGH** - S3 storage backend with credentials |

Both components are exposed via HTTPRoute through Envoy Gateway. Hubble UI supports optional OIDC authentication via SecurityPolicy; RustFS uses native authentication only.

---

## 1. Hubble UI Network Policy

### 1.1 Component Analysis

**Labels (from Cilium HelmRelease):**
```yaml
k8s-app: hubble-ui        # UI frontend
k8s-app: hubble-relay     # gRPC relay to Hubble agents
```

**Ports:**
- Hubble UI: TCP/80 (HTTP frontend)
- Hubble Relay: TCP/4245 (gRPC)

**Traffic Flows:**
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Envoy Gateway  │────▶│   Hubble UI     │────▶│  Hubble Relay   │
│ (network ns)    │:80  │ (kube-system)   │:4245│ (kube-system)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
                                               ┌─────────────────┐
                                               │  Cilium Agents  │
                                               │ (all nodes)     │
                                               └─────────────────┘
```

### 1.2 Security Requirements

Per NIST SP 800-207 Zero Trust principles:

1. **Least Privilege**: Only allow traffic from known sources
2. **Microsegmentation**: Separate UI from Relay policies where possible
3. **Explicit Allow**: Default deny with explicit ingress/egress rules
4. **Authentication Boundary**: OIDC enforced at Gateway level

### 1.3 Recommended Implementation

**File**: `templates/config/kubernetes/apps/kube-system/network-policies/app/hubble-ui.yaml.j2`

> **CRITICAL CORRECTIONS APPLIED:**
> 1. Gateway label corrected: `gateway.networking.k8s.io/gateway-name` (not `gateway.envoyproxy.io/owning-gateway-name`)
> 2. Added `enableDefaultDeny` with mode-based enforcement per codebase convention
> 3. Added namespace label for DNS egress (`io.kubernetes.pod.namespace: kube-system`)
> 4. Corrected Prometheus ingress pattern with combined label selector (not separate matchLabels and matchExpressions)

```yaml
#% if network_policies_enabled | default(false) and hubble_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy for Hubble UI                                             #|
#| Cilium network observability dashboard - serves web UI, queries Hubble Relay  #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  description: "Hubble UI: Serve web interface, query Hubble Relay for flow data"
  endpointSelector:
    matchLabels:
      k8s-app: hubble-ui
#% if enforce %#
  enableDefaultDeny:
    ingress: true
    egress: true
#% else %#
  #| Audit mode - observe traffic patterns via Hubble without blocking #|
  enableDefaultDeny:
    ingress: false
    egress: false
#% endif %#
  ingress:
    #| User access via Envoy Gateway (internal) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
            gateway.networking.k8s.io/gateway-name: internal
      toPorts:
        - ports:
            - port: "8081"
              protocol: TCP
  egress:
    #| DNS resolution #|
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
    #| Query Hubble Relay for flow data #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: hubble-relay
      toPorts:
        - ports:
            - port: "4245"
              protocol: TCP
---
#| ============================================================================= #|
#| CiliumNetworkPolicy for Hubble Relay                                          #|
#| gRPC relay service - aggregates flow data from Cilium agents on all nodes     #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: hubble-relay
  namespace: kube-system
spec:
  description: "Hubble Relay: Aggregate flow data from Cilium agents, serve to UI"
  endpointSelector:
    matchLabels:
      k8s-app: hubble-relay
#% if enforce %#
  enableDefaultDeny:
    ingress: true
    egress: true
#% else %#
  #| Audit mode - observe traffic patterns via Hubble without blocking #|
  enableDefaultDeny:
    ingress: false
    egress: false
#% endif %#
  ingress:
    #| Hubble UI queries flow data #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: hubble-ui
      toPorts:
        - ports:
            - port: "4245"
              protocol: TCP
#% if monitoring_enabled | default(false) %#
    #| Prometheus scraping #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "9966"
              protocol: TCP
#% endif %#
  egress:
    #| DNS resolution #|
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
    #| Hubble Relay communicates with Cilium agents via host networking #|
    - toEntities:
        - host
      toPorts:
        - ports:
            - port: "4244"
              protocol: TCP
#% endif %#
```

### 1.4 Kustomization Update

**File**: `templates/config/kubernetes/apps/kube-system/network-policies/app/kustomization.yaml.j2`

Add to resources list:
```yaml
#% if hubble_enabled | default(false) %#
  - ./hubble-ui.yaml
#% endif %#
```

### 1.5 Validation Criteria

| Test | Expected Result |
| ------ | ----------------- |
| Hubble UI accessible via HTTPRoute | ✅ Traffic flows through Envoy Gateway |
| Direct pod access blocked | ✅ Only Gateway can reach UI |
| Hubble Relay only from UI | ✅ No external access to Relay |
| DNS resolution works | ✅ Can resolve internal services |
| Prometheus scraping (if enabled) | ✅ Metrics collected |

---

## 2. RustFS Network Policy

### 2.1 Component Analysis

**Labels (from HelmRelease):**
```yaml
app.kubernetes.io/name: rustfs
app.kubernetes.io/instance: rustfs
```

**Ports:**
- S3 API: TCP/9000
- Console UI: TCP/9001

**Traffic Flows:**
```
┌─────────────────┐         ┌─────────────────┐
│  Envoy Gateway  │────────▶│     RustFS      │
│ (network ns)    │:9001    │   (storage ns)  │
└─────────────────┘         └─────────────────┘
                                    ▲
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────┴───────┐          ┌────────┴────────┐         ┌────────┴────────┐
│     Loki      │          │    Dragonfly    │         │    Langfuse     │
│ (monitoring)  │:9000     │    (cache)      │:9000    │  (ai-system)    │:9000
└───────────────┘          └─────────────────┘         └─────────────────┘
        │                           │                           │
┌───────┴───────┐          ┌────────┴────────┐         ┌────────┴────────┐
│   Keycloak    │          │    LiteLLM      │         │     CNPG        │
│  (identity)   │:9000     │  (ai-system)    │:9000    │  (various)      │:9000
└───────────────┘          └─────────────────┘         └─────────────────┘
```

### 2.2 Security Requirements

Per NIST SP 800-207 and MinIO/S3 security best practices:

1. **API Access Control**: Only authorized namespaces can access S3 API
2. **Console Isolation**: UI access only via authenticated Gateway
3. **Credential Protection**: Network-level enforcement prevents credential theft exploitation
4. **Audit Trail**: Hubble provides visibility into all S3 access patterns

### 2.3 Recommended Implementation

**File**: `templates/config/kubernetes/apps/storage/rustfs/app/networkpolicy.yaml.j2`

> **CRITICAL CORRECTIONS APPLIED:**
> 1. Gateway label corrected: `gateway.networking.k8s.io/gateway-name` (not `gateway.envoyproxy.io/owning-gateway-name`)
> 2. Added `enableDefaultDeny` with mode-based enforcement per codebase convention
> 3. Fixed label selector patterns (combined `io.kubernetes.pod.namespace` + app labels)
> 4. Added `storage` namespace for RustFS setup Job (bucket creation)
> 5. Corrected CNPG cluster labels: `keycloak-postgres`, `litellm-postgresql`, `langfuse-postgresql`

```yaml
#% if rustfs_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy for RustFS S3-compatible storage                          #|
#| Pattern: Infrastructure component with multi-namespace consumers              #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: rustfs
  namespace: storage
spec:
  description: "RustFS: S3-compatible object storage for Loki, CNPG backups, Langfuse"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: rustfs
#% if enforce %#
  enableDefaultDeny:
    ingress: true
    egress: true
#% else %#
  #| Audit mode - observe traffic patterns via Hubble without blocking #|
  enableDefaultDeny:
    ingress: false
    egress: false
#% endif %#
  ingress:
#% if loki_enabled | default(false) %#
    #| S3 API access from Loki (monitoring namespace) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: loki
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% if dragonfly_backup_enabled | default(false) %#
    #| S3 API access from Dragonfly backups (cache namespace) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: cache
            app: dragonfly
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% if keycloak_backup_enabled | default(false) %#
    #| S3 API access from Keycloak CNPG PostgreSQL backups #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: identity
            cnpg.io/cluster: keycloak-postgres
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% if litellm_backup_enabled | default(false) %#
    #| S3 API access from LiteLLM CNPG PostgreSQL backups #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: ai-system
            cnpg.io/cluster: litellm-postgresql
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% if langfuse_backup_enabled | default(false) %#
    #| S3 API access from Langfuse CNPG PostgreSQL backups #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: ai-system
            cnpg.io/cluster: langfuse-postgresql
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% if langfuse_enabled | default(false) %#
    #| S3 API access from Langfuse application (events, media, exports buckets) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: ai-system
            app.kubernetes.io/name: langfuse
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
    #| S3 API access from storage namespace (setup Job for bucket creation) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: storage
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
    #| Console UI access from Envoy Gateway (internal) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
            gateway.networking.k8s.io/gateway-name: internal
      toPorts:
        - ports:
            - port: "9001"
              protocol: TCP
#% if rustfs_monitoring_enabled | default(false) %#
    #| Prometheus metrics scraping #|
    #| NOTE: RustFS uses OTLP push, ServiceMonitor removed - this is for fallback #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
  egress:
    #| DNS resolution #|
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
---
#| ============================================================================= #|
#| NetworkPolicy for RustFS (Standard Kubernetes)                                #|
#| Provides baseline protection and portability if Cilium is unavailable         #|
#| ============================================================================= #|
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rustfs
  namespace: storage
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: rustfs
  policyTypes:
    - Ingress
    - Egress
  ingress:
    #| S3 API from authorized namespaces #|
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: cache
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: identity
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ai-system
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: network
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: storage
      ports:
        - port: 9000
          protocol: TCP
        - port: 9001
          protocol: TCP
  egress:
    #| DNS resolution #|
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
#% endif %#
```

### 2.4 Kustomization Update

**File**: `templates/config/kubernetes/apps/storage/rustfs/app/kustomization.yaml.j2`

Add to resources list:
```yaml
#% if network_policies_enabled | default(false) %#
  - ./networkpolicy.yaml
#% endif %#
```

### 2.5 Validation Criteria

| Test | Expected Result |
| ------ | ----------------- |
| Loki can write to S3 buckets | ✅ Ingestion works |
| CNPG backups succeed | ✅ WAL archiving to S3 |
| Dragonfly snapshots work | ✅ RDB files uploaded |
| Console UI via Gateway | ✅ OIDC-protected access |
| Unauthorized namespace blocked | ✅ Default namespace cannot access |
| Prometheus scraping works | ✅ Metrics collected |

---

## 3. Implementation Checklist

### Phase 1: Create Policy Files

- [ ] Create `templates/config/kubernetes/apps/kube-system/network-policies/app/hubble-ui.yaml.j2`
- [ ] Create `templates/config/kubernetes/apps/storage/rustfs/app/networkpolicy.yaml.j2`

### Phase 2: Update Kustomizations

- [ ] Update `templates/config/kubernetes/apps/kube-system/network-policies/app/kustomization.yaml.j2`
- [ ] Update `templates/config/kubernetes/apps/storage/rustfs/app/kustomization.yaml.j2`

### Phase 3: Validation

- [ ] Run `task configure` to regenerate manifests
- [ ] Verify YAML syntax with `kubeconform`
- [ ] Deploy with `network_policies_enabled: true` and `network_policies_mode: "audit"`
- [ ] Monitor with `hubble observe --verdict DROPPED`
- [ ] Test all traffic flows documented above
- [ ] Switch to `network_policies_mode: "enforce"` after validation

---

## 4. Best Practices Applied

### 4.1 NIST SP 800-207 Compliance

| Principle | Implementation |
| ----------- | -------------- |
| Never trust, always verify | Default deny with explicit allows |
| Least privilege access | Per-component, per-consumer rules |
| Assume breach | Microsegmentation limits blast radius |
| Verify explicitly | Label-based identity verification |

### 4.2 Cilium-Specific Patterns

| Pattern | Usage |
| --------- | ------- |
| `toEndpoints` with labels | Preferred over CIDR for pod-to-pod |
| `toEntities: host` | For host-network communication (Hubble Relay) |
| `io.kubernetes.pod.namespace` | Cross-namespace access control |
| Conditional blocks | Feature flags control policy scope |

### 4.3 Dual Policy Pattern

Both components use the dual policy pattern where applicable:

1. **CiliumNetworkPolicy**: L7-aware, FQDN support, full feature set
2. **Standard NetworkPolicy**: Portable fallback, defense in depth

---

## 5. References

- [Cilium Network Policy Documentation](https://docs.cilium.io/en/stable/security/policy/)
- [NIST SP 800-207 Zero Trust Architecture](https://csrc.nist.gov/publications/detail/sp/800-207/final)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [MinIO Security Best Practices](https://min.io/docs/minio/kubernetes/upstream/administration/identity-access-management.html)
- Existing codebase patterns: `dragonfly/app/networkpolicy.yaml.j2`, `litellm/app/networkpolicy.yaml.j2`

---

## 6. Review Notes and Corrections

### 6.1 Critical Issues Identified and Fixed

| Issue | Original | Corrected |
| ------- | ---------- | ----------- |
| Gateway label | `gateway.envoyproxy.io/owning-gateway-name` | `gateway.networking.k8s.io/gateway-name` |
| Missing `enableDefaultDeny` | Not present | Added with mode-based enforcement |
| Label selector pattern | Separate `matchLabels` + `matchExpressions` | Combined single `matchLabels` block |
| Missing namespace labels | Partial | All selectors now include `io.kubernetes.pod.namespace` |
| Missing storage namespace ingress | Not included | Added for RustFS setup Job |
| CNPG cluster label for LiteLLM | `litellm-postgres` | `litellm-postgresql` |

### 6.2 Patterns Validated Against Codebase

Reference files analyzed:
- `cache/dragonfly/app/networkpolicy.yaml.j2` - Audit/enforce mode pattern
- `ai-system/litellm/app/networkpolicy.yaml.j2` - Multi-policy pattern, CNPG labels
- `monitoring/network-policies/app/grafana.yaml.j2` - Gateway label verification
- `kube-system/network-policies/app/coredns.yaml.j2` - DNS egress pattern

### 6.3 RustFS Consumer Audit

Verified S3 consumers from codebase:

| Consumer | Namespace | Service Name | Verified |
| ---------- | ----------- | -------------- | ---------- |
| Loki | monitoring | `rustfs-svc.storage.svc:9000` | ✅ |
| Dragonfly backups | cache | `rustfs-svc.storage.svc.cluster.local:9000` | ✅ |
| Keycloak CNPG | identity | `rustfs.storage.svc.cluster.local:9000` | ✅ |
| Keycloak embedded backup | identity | `rustfs-svc.storage.svc:9000` | ✅ |
| LiteLLM CNPG | ai-system | `rustfs.storage.svc.cluster.local:9000` | ✅ |
| Langfuse CNPG | ai-system | `rustfs.storage.svc.cluster.local:9000` | ✅ |
| Langfuse S3 (events/media/exports) | ai-system | `rustfs-svc.storage.svc.cluster.local:9000` | ✅ |
| RustFS setup Job | storage | `rustfs-svc.storage.svc:9000` | ✅ |

---

## Document History

| Date | Change | Author |
| ------ | -------- | -------- |
| 2026-01-09 | Comprehensive validation and corrections - fixed gateway labels, added enableDefaultDeny, corrected label patterns, added storage namespace ingress | AI Assistant |
| 2026-01-09 | Initial research document | AI Assistant |
