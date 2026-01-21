# Network Policies Implementation Guide

**Status:** Production Reference
**Last Updated:** 2026-01-09
**Last Validated:** 2026-01-09 (comprehensive codebase audit)
**Cluster Version:** Kubernetes v1.35.0, Cilium CNI

## Table of Contents

- [Overview](#overview)
- [Current State Analysis](#current-state-analysis)
- [Gap Analysis](#gap-analysis)
- [Best Practices and Industry Standards](#best-practices-and-industry-standards)
- [Pattern Standardization](#pattern-standardization)
- [Implementation Guidelines](#implementation-guidelines)
- [Priority Remediation Plan](#priority-remediation-plan)
- [Policy Requirements by Component Type](#policy-requirements-by-component-type)
- [Testing and Validation](#testing-and-validation)
- [Troubleshooting](#troubleshooting)

## Overview

This guide documents the network policy implementation approach for this Kubernetes cluster, which follows zero-trust networking principles using Cilium CNI and standard Kubernetes NetworkPolicies.

### Key Principles

1. **Zero-Trust Networking**: Default-deny all traffic, explicitly allow only what's needed
2. **Defense in Depth**: Multiple layers of network security (CiliumNetworkPolicy + NetworkPolicy)
3. **Least Privilege**: Minimal necessary access for each component
4. **Observable Security**: Audit mode for testing before enforcement
5. **GitOps Compliance**: All policies version-controlled and template-driven

### Configuration Variables

Network policies are controlled by two main variables in `cluster.yaml`:

```yaml
network_policies_enabled: true    # Enable/disable all network policies
network_policies_mode: "audit"    # "audit" or "enforce"
```

**Audit Mode** (`audit`):

- Policies are applied but NOT enforced
- Traffic is observed via Hubble without blocking
- Allows testing and validation before enforcement
- `enableDefaultDeny: false` in CiliumNetworkPolicy specs

**Enforce Mode** (`enforce`):

- Policies are actively enforced
- Unauthorized traffic is dropped
- Production security posture
- `enableDefaultDeny: true` in CiliumNetworkPolicy specs

## Current State Analysis

### Components WITH Network Policies

| Component | Namespace | CiliumNetworkPolicy | Standard NetworkPolicy | Database NetworkPolicy | Location |
| ----------- | ----------- | --------------------- | ------------------------ | ------------------------ | ---------- |
| **kube-system Infrastructure** | | | | | |
| CoreDNS | kube-system | ✅ | ❌ | N/A | `kube-system/network-policies/app/coredns.yaml.j2` |
| Spegel | kube-system | ✅ | ❌ | N/A | `kube-system/network-policies/app/spegel.yaml.j2` |
| Metrics Server | kube-system | ✅ | ❌ | N/A | `kube-system/network-policies/app/metrics-server.yaml.j2` |
| Reloader | kube-system | ✅ | ❌ | N/A | `kube-system/network-policies/app/reloader.yaml.j2` |
| **cert-manager** | | | | | |
| Controller | cert-manager | ✅ | ❌ | N/A | `cert-manager/network-policies/app/controller.yaml.j2` |
| Webhook | cert-manager | ✅ | ❌ | N/A | `cert-manager/network-policies/app/webhook.yaml.j2` |
| CA Injector | cert-manager | ✅ | ❌ | N/A | `cert-manager/network-policies/app/cainjector.yaml.j2` |
| **Network Components** | | | | | |
| Envoy Gateway | network | ✅ | ❌ | N/A | `network/network-policies/app/envoy-gateway.yaml.j2` |
| Cloudflare DNS (external-dns) | network | ✅ | ❌ | N/A | `network/network-policies/app/cloudflare-dns.yaml.j2` |
| UniFi DNS (external-dns) | network | ✅ | ❌ | N/A | `network/network-policies/app/unifi-dns.yaml.j2` |
| k8s-gateway | network | ✅ | ❌ | N/A | `network/network-policies/app/k8s-gateway.yaml.j2` |
| Cloudflare Tunnel | network | ✅ | ❌ | N/A | `network/network-policies/app/cloudflare-tunnel.yaml.j2` |
| **Monitoring Stack** | | | | | |
| Grafana | monitoring | ✅ | ❌ | N/A | `monitoring/network-policies/app/grafana.yaml.j2` |
| Prometheus | monitoring | ✅ | ❌ | N/A | `monitoring/network-policies/app/prometheus.yaml.j2` |
| Loki | monitoring | ✅ | ❌ | N/A | `monitoring/network-policies/app/loki.yaml.j2` |
| Alloy | monitoring | ✅ | ❌ | N/A | `monitoring/network-policies/app/alloy.yaml.j2` |
| Tempo | monitoring | ✅ | ❌ | N/A | `monitoring/network-policies/app/tempo.yaml.j2` |
| **Cache Services** | | | | | |
| Dragonfly | cache | ✅ | ❌ | N/A | `cache/dragonfly/app/networkpolicy.yaml.j2` |
| **Application Components (Triple Policy Pattern)** | | | | | |
| Keycloak | identity | ✅ | ✅ | ✅ (CNPG) | `identity/keycloak/*/networkpolicy*.yaml.j2` |
| Keycloak config-cli | identity | ✅ | ❌ | N/A | `identity/keycloak/config/networkpolicy.yaml.j2` |
| LiteLLM | ai-system | ✅ (2x) | ✅ | ✅ (CNPG) | `ai-system/litellm/app/networkpolicy.yaml.j2` |
| Langfuse | ai-system | ✅ (2x) | ✅ | ✅ (CNPG) | `ai-system/langfuse/app/networkpolicy.yaml.j2` |

**Total:** 22 components with network policies across 6 namespaces

### Components MISSING Network Policies (Gaps)

| Component | Namespace | Exposed Externally | HTTPRoute | Priority | Risk Level |
| ----------- | ----------- | ------------------- | ----------- | ---------- | ---------- |
| **Hubble UI** | kube-system | ✅ Yes | ✅ Yes | **HIGH** | **HIGH** |
| **RustFS** | storage | ✅ Yes | ✅ Yes | **HIGH** | **HIGH** |

> **Note:** All other infrastructure components now have network policies implemented. Only Hubble UI and RustFS remain as gaps requiring remediation.

### HTTPRoute Status

All externally exposed components have HTTPRoutes configured in `templates/config/kubernetes/apps/network/envoy-gateway/app/internal-httproutes.yaml.j2`:

| Component | HTTPRoute | OIDC Protection | Native Auth |
| ----------- | ----------- | ----------------- | ------------- |
| Hubble UI | ✅ (conditional on `hubble_enabled`) | Optional (if `oidc_sso_enabled`) | No |
| Grafana | ✅ (conditional on `monitoring_enabled`) | Optional (if `oidc_sso_enabled`) | Yes (optional) |
| RustFS Console | ✅ (conditional on `rustfs_enabled`) | ❌ No (not supported) | ✅ Yes (required) |
| LiteLLM | ✅ (conditional on `litellm_enabled`) | ❌ No (uses native SSO) | ✅ Yes |
| Langfuse | ✅ Separate file in ai-system | ❌ No (uses native SSO) | ✅ Yes |
| Keycloak | ✅ In identity namespace | ❌ No (is the IdP) | N/A |

**Important Notes:**

- Prometheus, Loki, Alloy, Tempo are NOT exposed externally (internal services only)
- Dragonfly is NOT exposed externally (internal cache service)
- OIDC protection is implemented via SecurityPolicy targeting HTTPRoutes with label `security: oidc-protected`

## Gap Analysis

### Critical Gaps (HIGH Priority)

#### 1. Hubble UI (kube-system namespace)

**Risk:** Network observability dashboard exposed without network policy

**Impact:**

- Externally accessible via HTTPRoute
- Can view ALL cluster network traffic flows
- No ingress restrictions beyond gateway
- No egress restrictions (can probe internal services)

**Required Policy:**

- Ingress: Allow only from Envoy Gateway (internal + external if exposed)
- Egress: DNS, kube-apiserver, Hubble Relay (port 4245)
- Optional: Prometheus metrics scraping

#### 2. RustFS Console (storage namespace)

**Risk:** S3-compatible storage management UI exposed without network policy

**Impact:**

- Externally accessible via HTTPRoute
- Access to all S3 buckets and credentials
- Can create/delete buckets and manage users
- No ingress restrictions beyond gateway
- No egress restrictions

**Required Policy:**

- Ingress: Allow only from Envoy Gateway (internal + external if exposed)
- Egress: DNS, RustFS backend service (port 9000)
- Optional: Prometheus metrics scraping

### ~~Medium Priority Gaps~~ (RESOLVED)

> **✅ IMPLEMENTED:** The following components now have network policies implemented. See "Components WITH Network Policies" table above for locations.

| Component | Status | Implementation |
| --------- | ------ | -------------- |
| Metrics Server | ✅ Implemented | `kube-system/network-policies/app/metrics-server.yaml.j2` |
| cert-manager | ✅ Implemented | `cert-manager/network-policies/app/` (controller, webhook, cainjector) |
| external-dns (Cloudflare) | ✅ Implemented | `network/network-policies/app/cloudflare-dns.yaml.j2` |
| external-dns (UniFi) | ✅ Implemented | `network/network-policies/app/unifi-dns.yaml.j2` |

### ~~Low Priority Gaps~~ (RESOLVED)

| Component | Status | Implementation |
| --------- | ------ | -------------- |
| Reloader | ✅ Implemented | `kube-system/network-policies/app/reloader.yaml.j2` |
| Cloudflare Tunnel | ✅ Implemented | `network/network-policies/app/cloudflare-tunnel.yaml.j2` |

## Best Practices and Industry Standards

### 1. Zero-Trust Networking (NIST SP 800-207)

**Principles:**

- Never trust, always verify
- Assume breach - minimize blast radius
- Least privilege access
- Micro-segmentation

**Implementation:**

- Default-deny all ingress and egress
- Explicitly allow only required traffic
- Use namespace isolation
- Implement service-to-service authentication (mTLS via Cilium)

### 2. Defense in Depth (CISA Security Guidance)

**Multiple Layers:**

1. CiliumNetworkPolicy (L3-L7, FQDN-based egress)
2. Standard NetworkPolicy (L3-L4, portable fallback)
3. Gateway SecurityPolicy (OIDC/JWT authentication)
4. Application-level authentication (native auth)

**Why Both CiliumNetworkPolicy AND NetworkPolicy?**

- **CiliumNetworkPolicy**: Advanced features (FQDN filtering, L7 rules, entities)
- **NetworkPolicy**: Portability, fallback for non-Cilium CNI
- Applications (LiteLLM, Langfuse, Keycloak) use both for maximum compatibility

### 3. Least Privilege Access

**Ingress Rules:**

- Specify exact source namespaces and labels
- Use `fromEndpoints` (Cilium) or `podSelector`/`namespaceSelector` (NetworkPolicy)
- Limit to specific ports and protocols

**Egress Rules:**

- DNS: Only to CoreDNS (`k8s-app: kube-dns`)
- APIs: Only to kube-apiserver using `toEntities: [kube-apiserver]`
- Databases: Only to specific cluster labels (`cnpg.io/cluster: <name>`)
- External: Use FQDN patterns (Cilium) or IP CIDR blocks (NetworkPolicy)

### 4. Observable Security (Cilium Hubble)

**Audit Mode Workflow:**

1. Deploy policies in audit mode (`network_policies_mode: audit`)
2. Monitor traffic via Hubble: `hubble observe --verdict DROPPED`
3. Identify legitimate traffic patterns
4. Adjust policies to allow legitimate traffic
5. Switch to enforce mode (`network_policies_mode: enforce`)
6. Monitor for unexpected drops

**Hubble Commands:**

```bash
# View all dropped traffic
hubble observe --verdict DROPPED

# View traffic for specific namespace
hubble observe --namespace ai-system

# View traffic for specific pod
hubble observe --pod langfuse-web-0

# View traffic between specific endpoints
hubble observe --from-namespace ai-system --to-namespace monitoring
```

### 5. GitOps Compliance

**Requirements:**

- All policies as Jinja2 templates
- Version-controlled in Git
- Automated deployment via Flux
- Conditional generation based on cluster configuration
- Consistent naming and labeling

## Pattern Standardization

### Pattern A: Infrastructure Components (Single CiliumNetworkPolicy)

**Use Cases:**

- System infrastructure (CoreDNS, Spegel)
- Monitoring stack (Prometheus, Grafana, Loki, Alloy, Tempo)
- Cache services (Dragonfly)

**Characteristics:**

- Single `CiliumNetworkPolicy` resource
- Centralized in `<namespace>/network-policies/app/` directory
- Uses `enableDefaultDeny` with mode-based enforcement
- Leverages Cilium-specific features (entities, FQDN)

**Directory Structure:**

```
templates/config/kubernetes/apps/<namespace>/
├── network-policies/
│   ├── ks.yaml.j2              # Flux Kustomization
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── <component1>.yaml.j2
│       └── <component2>.yaml.j2
```

**Template Example:**

```yaml
#% if network_policies_enabled | default(false) and <component>_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| Component network policy: Brief description #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: component-name
  namespace: target-namespace
spec:
  description: "Component: Purpose and function"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: component-name
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| User access via envoy gateway #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
            gateway.networking.k8s.io/gateway-name: internal
      toPorts:
        - ports:
            - port: "8080"
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
#% endif %#
```

### Pattern B: Application Components (Triple Policy: Cilium + Standard + Database)

**Use Cases:**

- Database-backed applications (LiteLLM, Langfuse, Keycloak)
- Applications requiring portability across CNIs
- Applications with complex external dependencies

**Characteristics:**

- Multiple policy resources in single file
- Located within app's directory (`<app>/app/networkpolicy.yaml.j2`)
- Includes separate database policies when using CNPG PostgreSQL
- Provides fallback for non-Cilium environments

**Directory Structure:**

```
templates/config/kubernetes/apps/<namespace>/<app>/
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2
    ├── networkpolicy.yaml.j2       # All policies in one file
    └── secret.sops.yaml.j2
```

**Template Structure (networkpolicy.yaml.j2):**

```yaml
#% if <app>_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - Application Component                                  #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: app-name
  namespace: app-namespace
spec:
  description: "App: Main application access controls"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: app-name
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    # ... ingress rules
  egress:
    # ... egress rules (can use FQDN for external APIs)
---
#| ============================================================================= #|
#| NetworkPolicy - Application Component (Standard K8s)                         #|
#| ============================================================================= #|
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-name
  namespace: app-namespace
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: app-name
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # ... standard ingress rules (namespace/pod selectors)
  egress:
    # ... standard egress rules (cannot use FQDN, use IP CIDR)
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - Database (CNPG PostgreSQL)                             #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: app-db-kube-api-egress
  namespace: app-namespace
spec:
  description: "App PostgreSQL: Kubernetes API and DNS access"
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: app-postgresql
  egress:
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
            io.kubernetes.pod.namespace: kube-system
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
#| ============================================================================= #|
#| NetworkPolicy - Database (Standard K8s)                                      #|
#| ============================================================================= #|
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-db
  namespace: app-namespace
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: app-postgresql
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # ... database ingress (app access, replication, operator, metrics)
  egress:
    # ... database egress (DNS, replication, backups)
#% endif %#
```

### When to Use Which Pattern

| Criteria | Pattern A (Single Cilium) | Pattern B (Triple Policy) |
| ---------- | -------------------------- | --------------------------- |
| **Component Type** | Infrastructure, monitoring | Applications |
| **Database** | No database | Uses CNPG PostgreSQL |
| **External APIs** | Few or no external calls | Multiple external APIs |
| **CNI Portability** | Cilium-only cluster | May migrate CNI |
| **Complexity** | Simple, well-defined traffic | Complex dependencies |
| **Examples** | CoreDNS, Prometheus, Grafana | LiteLLM, Langfuse, Keycloak |

## Implementation Guidelines

### 1. Naming Conventions

**CiliumNetworkPolicy:**

- Main app: `<component-name>` (e.g., `litellm`, `grafana`)
- Database: `<component-name>-db-kube-api-egress`
- FQDN egress: `<component-name>-<provider>-egress` (e.g., `litellm-azure-egress`)
- ICMP egress: `<component-name>-icmp-egress`

**NetworkPolicy:**

- Main app: `<component-name>` (e.g., `litellm`, `grafana`)
- Database: `<component-name>-db`

### 2. Required Sections

**Every Policy MUST Include:**

1. **Conditional Rendering:**

   ```yaml
   #% if <component>_enabled | default(false) and network_policies_enabled | default(false) %#
   #% set enforce = network_policies_mode | default('audit') == 'enforce' %#
   ```

2. **Descriptive Header Comments:**

   ```yaml
   #| ============================================================================= #|
   #| CiliumNetworkPolicy - Component Name                                         #|
   #| Brief description of purpose and function                                    #|
   #| REF: docs/path/to/implementation-guide.md (optional)                         #|
   #| ============================================================================= #|
   ```

3. **Metadata with Description:**

   ```yaml
   metadata:
     name: component-name
     namespace: target-namespace
     labels:
       app.kubernetes.io/name: component-name
       app.kubernetes.io/component: network-policy
   spec:
     description: "Component: Concise description of purpose"
   ```

4. **Mode-Based Enforcement:**

   ```yaml
   enableDefaultDeny:
     egress: #{ enforce | lower }#
     ingress: #{ enforce | lower }#
   ```

5. **Inline Rule Comments:**

   ```yaml
   ingress:
     #| User access via envoy gateway #|
     - fromEndpoints:
         - matchLabels:
             io.kubernetes.pod.namespace: network
   ```

6. **DNS Egress (Almost Universal):**

   ```yaml
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
   ```

### 3. Common Ingress Patterns

#### Gateway API (Envoy Gateway)

**CiliumNetworkPolicy:**

```yaml
ingress:
  #| User access via envoy gateway (internal) #|
  - fromEndpoints:
      - matchLabels:
          io.kubernetes.pod.namespace: network
          gateway.networking.k8s.io/gateway-name: internal
    toPorts:
      - ports:
          - port: "8080"
            protocol: TCP
```

**NetworkPolicy:**

```yaml
ingress:
  #| Allow from Envoy Gateway (external access) #|
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: network
    ports:
      - protocol: TCP
        port: 8080
```

#### Prometheus Metrics Scraping

**CiliumNetworkPolicy:**

```yaml
ingress:
  #| Prometheus scraping #|
  - fromEndpoints:
      - matchLabels:
          app.kubernetes.io/name: prometheus
          io.kubernetes.pod.namespace: monitoring
    toPorts:
      - ports:
          - port: "9090"
            protocol: TCP
```

**NetworkPolicy:**

```yaml
ingress:
  #| Allow Prometheus scraping #|
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
    ports:
      - protocol: TCP
        port: 9090
```

#### Inter-Component (Same Namespace)

**CiliumNetworkPolicy:**

```yaml
ingress:
  #| LiteLLM callbacks (trace ingestion) #|
  - fromEndpoints:
      - matchLabels:
          app.kubernetes.io/name: litellm
          io.kubernetes.pod.namespace: ai-system
    toPorts:
      - ports:
          - port: "3000"
            protocol: TCP
```

**NetworkPolicy:**

```yaml
ingress:
  #| Allow from LiteLLM (trace ingestion) #|
  - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: litellm
    ports:
      - protocol: TCP
        port: 3000
```

### 4. Common Egress Patterns

#### Kubernetes API Server

**CiliumNetworkPolicy (Preferred):**

```yaml
egress:
  #| Kubernetes API access #|
  - toEntities:
      - kube-apiserver
    toPorts:
      - ports:
          - port: "6443"
            protocol: TCP
```

**Note:** Standard NetworkPolicy cannot use `toEntities`, must allow broad cluster egress

#### Database (CNPG PostgreSQL)

**CiliumNetworkPolicy:**

```yaml
egress:
  #| PostgreSQL (CNPG) - Application database #|
  - toEndpoints:
      - matchLabels:
          cnpg.io/cluster: app-postgresql
          io.kubernetes.pod.namespace: app-namespace
    toPorts:
      - ports:
          - port: "5432"
            protocol: TCP
```

**NetworkPolicy:**

```yaml
egress:
  #| Allow PostgreSQL connection to CloudNativePG cluster #|
  - to:
      - podSelector:
          matchLabels:
            cnpg.io/cluster: app-postgresql
    ports:
      - protocol: TCP
        port: 5432
```

#### External HTTPS APIs (FQDN-Based)

**CiliumNetworkPolicy (FQDN Support):**

```yaml
egress:
  #| Azure OpenAI endpoints #|
  - toFQDNs:
      - matchPattern: "*.openai.azure.com"
      - matchPattern: "*.cognitiveservices.azure.com"
    toPorts:
      - ports:
          - port: "443"
            protocol: TCP
```

**NetworkPolicy (IP CIDR Fallback):**

```yaml
egress:
  #| External LLM providers (cannot use FQDN, allow public IPs) #|
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except:
            - 10.0.0.0/8
            - 172.16.0.0/12
            - 192.168.0.0/16
    ports:
      - protocol: TCP
        port: 443
```

#### Shared Cache (Dragonfly/Redis)

**CiliumNetworkPolicy:**

```yaml
egress:
  #| Redis (Dragonfly) - Queue and caching #|
  - toEndpoints:
      - matchLabels:
          app: dragonfly
          io.kubernetes.pod.namespace: cache
    toPorts:
      - ports:
          - port: "6379"
            protocol: TCP
```

**NetworkPolicy:**

```yaml
egress:
  #| Dragonfly (Redis-compatible cache) #|
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: cache
        podSelector:
          matchLabels:
            app: dragonfly
    ports:
      - protocol: TCP
        port: 6379
```

#### S3 Storage (RustFS)

**CiliumNetworkPolicy:**

```yaml
egress:
  #| S3 (RustFS) - Blob storage #|
  - toEndpoints:
      - matchLabels:
          app.kubernetes.io/name: rustfs
          io.kubernetes.pod.namespace: storage
    toPorts:
      - ports:
          - port: "9000"
            protocol: TCP
```

**NetworkPolicy:**

```yaml
egress:
  #| RustFS S3 storage #|
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: storage
        podSelector:
          matchLabels:
            app.kubernetes.io/name: rustfs
    ports:
      - protocol: TCP
        port: 9000
```

#### Keycloak (OIDC SSO)

**CiliumNetworkPolicy:**

```yaml
egress:
  #| Keycloak (OIDC SSO) #|
  - toEndpoints:
      - matchLabels:
          app.kubernetes.io/name: keycloak
          io.kubernetes.pod.namespace: identity
    toPorts:
      - ports:
          - port: "8080"
            protocol: TCP
```

**Note:** Keycloak uses `app.kubernetes.io/instance` label from operator, not `app.kubernetes.io/name`

#### OpenTelemetry (Tempo Tracing)

**CiliumNetworkPolicy:**

```yaml
egress:
  #| OpenTelemetry (Tempo) - Trace export #|
  - toEndpoints:
      - matchLabels:
          app.kubernetes.io/name: tempo
          io.kubernetes.pod.namespace: monitoring
    toPorts:
      - ports:
          - port: "4318"  # OTLP HTTP
            protocol: TCP
          - port: "4317"  # OTLP gRPC
            protocol: TCP
```

### 5. Database Policy Requirements (CNPG PostgreSQL)

When using CloudNativePG, ALWAYS include separate policies for database pods.

**Database Ingress Requirements:**

```yaml
ingress:
  #| CNPG operator health checks on port 8000 #|
  - fromEndpoints:
      - matchLabels:
          app.kubernetes.io/name: cloudnative-pg
          io.kubernetes.pod.namespace: cnpg-system
    toPorts:
      - ports:
          - port: "8000"
            protocol: TCP
  #| Application access on port 5432 #|
  - fromEndpoints:
      - matchLabels:
          app.kubernetes.io/name: app-name
    toPorts:
      - ports:
          - port: "5432"
            protocol: TCP
  #| Inter-pod replication between cluster instances #|
  - fromEndpoints:
      - matchLabels:
          cnpg.io/cluster: app-postgresql
    toPorts:
      - ports:
          - port: "5432"
            protocol: TCP
  #| Prometheus metrics scraping on port 9187 (optional) #|
  - fromEndpoints:
      - matchLabels:
          app.kubernetes.io/name: prometheus
          io.kubernetes.pod.namespace: monitoring
    toPorts:
      - ports:
          - port: "9187"
            protocol: TCP
```

**Database Egress Requirements:**

```yaml
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
  #| Inter-pod replication #|
  - toEndpoints:
      - matchLabels:
          cnpg.io/cluster: app-postgresql
    toPorts:
      - ports:
          - port: "5432"
            protocol: TCP
  #| Backup to RustFS S3 endpoint (optional) #|
  - toEndpoints:
      - matchLabels:
          app.kubernetes.io/name: rustfs
          io.kubernetes.pod.namespace: storage
    toPorts:
      - ports:
          - port: "9000"
            protocol: TCP
```

### 6. Conditional Features

**Use Jinja2 conditionals for optional features:**

```yaml
#% if monitoring_enabled | default(false) %#
  #| Prometheus metrics scraping #|
  - fromEndpoints:
      - matchLabels:
          app.kubernetes.io/name: prometheus
    toPorts:
      - ports:
          - port: "9090"
            protocol: TCP
#% endif %#
```

**Common Conditionals:**

- `monitoring_enabled` - Prometheus scraping
- `tracing_enabled` - Tempo OTLP export
- `rustfs_enabled` - S3 storage egress
- `dragonfly_enabled` - Redis cache egress
- `keycloak_enabled` or `<app>_sso_enabled` - OIDC SSO egress
- `<app>_backup_enabled` - S3 backup egress

## Priority Remediation Plan

### Phase 1: Critical Gaps (Week 1)

**Objective:** Protect externally exposed components

#### 1.1 Hubble UI Network Policy

**File:** `templates/config/kubernetes/apps/kube-system/network-policies/app/hubble-ui.yaml.j2`

**Priority:** CRITICAL - Externally exposed observability dashboard

**Implementation:**

```yaml
#% if hubble_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| Hubble UI network policy: Cilium network observability dashboard #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  description: "Hubble UI: Serve web interface, query Hubble Relay"
  endpointSelector:
    matchLabels:
      k8s-app: hubble-ui
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| User access via envoy gateway (internal) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
            gateway.networking.k8s.io/gateway-name: internal
      toPorts:
        - ports:
            - port: "8081"
              protocol: TCP
  egress:
    #| Query Hubble Relay for flow data #|
    - toEndpoints:
        - matchLabels:
            k8s-app: hubble-relay
            io.kubernetes.pod.namespace: kube-system
      toPorts:
        - ports:
            - port: "4245"
              protocol: TCP
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
#% endif %#
```

**Validation:**

```bash
# Apply in audit mode first
task configure

# Monitor traffic patterns
hubble observe --pod hubble-ui --namespace kube-system

# Check for dropped traffic after enforcement
hubble observe --pod hubble-ui --verdict DROPPED
```

#### 1.2 RustFS Network Policy

**File:** `templates/config/kubernetes/apps/storage/rustfs/app/networkpolicy.yaml.j2`

**Priority:** CRITICAL - Externally exposed S3 management console

**Implementation:**

```yaml
#% if rustfs_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - RustFS Console and API                                  #|
#| S3-compatible object storage management and data access                       #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: rustfs
  namespace: storage
  labels:
    app.kubernetes.io/name: rustfs
    app.kubernetes.io/component: network-policy
spec:
  description: "RustFS: S3 API and management console"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: rustfs
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| S3 API access (port 9000) from applications #|
    - fromEntities:
        - cluster
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
    #| Management console (port 9001) via envoy gateway #|
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
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
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
#% endif %#
```

**Validation:**

```bash
# Test S3 API access from applications
kubectl -n ai-system exec -it langfuse-web-0 -- curl -I http://rustfs-svc.storage.svc.cluster.local:9000

# Test console access via HTTPRoute
curl -I https://rustfs.${SECRET_DOMAIN}

# Monitor traffic
hubble observe --namespace storage
```

#### 1.3 Update Kustomizations

**File:** `templates/config/kubernetes/apps/kube-system/network-policies/app/kustomization.yaml.j2`

Add Hubble UI policy:

```yaml
resources:
  - ./coredns.yaml
  - ./spegel.yaml
  - ./metrics-server.yaml
  - ./reloader.yaml
  - ./hubble-ui.yaml  # ADD THIS LINE
```

**File:** Create `templates/config/kubernetes/apps/storage/rustfs/app/kustomization.yaml.j2` if not exists:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./networkpolicy.yaml  # ADD THIS LINE
```

### ~~Phase 2: Medium Priority~~ ✅ COMPLETED

> **All Phase 2 items have been implemented.** The following sections are preserved for reference as the canonical implementation patterns.

#### 2.1 Metrics Server Network Policy ✅

**File:** `templates/config/kubernetes/apps/kube-system/network-policies/app/metrics-server.yaml.j2`

**Implementation:**

```yaml
#% if network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| Metrics Server network policy: Cluster-wide resource metrics API #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  description: "Metrics Server: Collect kubelet metrics, serve aggregation API"
  endpointSelector:
    matchLabels:
      k8s-app: metrics-server
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| kube-apiserver aggregation layer #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "4443"
              protocol: TCP
#% if monitoring_enabled | default(false) %#
    #| Prometheus metrics scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "10250"
              protocol: TCP
#% endif %#
  egress:
    #| Kubernetes API access #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| Scrape kubelet metrics from all nodes #|
    - toEntities:
        - host
        - remote-node
      toPorts:
        - ports:
            - port: "10250"
              protocol: TCP
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
#% endif %#
```

#### 2.2 cert-manager Network Policy ✅

**Directory:** `templates/config/kubernetes/apps/cert-manager/network-policies/` (EXISTS)

**File:** `templates/config/kubernetes/apps/cert-manager/network-policies/ks.yaml.j2`

```yaml
#% if network_policies_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager-network-policies
  namespace: flux-system
spec:
  interval: 30m
  path: ./kubernetes/apps/cert-manager/network-policies/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: true
#% endif %#
```

**File:** `templates/config/kubernetes/apps/cert-manager/network-policies/app/cert-manager.yaml.j2`

```yaml
#% if network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| cert-manager controller network policy #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  description: "cert-manager: TLS certificate management and ACME challenges"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: cert-manager
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
#% if monitoring_enabled | default(false) %#
    #| Prometheus metrics scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9402"
              protocol: TCP
#% endif %#
  egress:
    #| Kubernetes API access #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    #| ACME challenges (Let's Encrypt) #|
    - toFQDNs:
        - matchPattern: "acme-v02.api.letsencrypt.org"
        - matchPattern: "acme-staging-v02.api.letsencrypt.org"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#
```

#### 2.3 external-dns Network Policy ✅

**File:** `templates/config/kubernetes/apps/network/network-policies/app/cloudflare-dns.yaml.j2` (EXISTS)

> **Note:** Implementation uses centralized network-policies directory pattern, not per-app directory.

**Implementation:**

```yaml
#% if network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| external-dns network policy: DNS record synchronization #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: external-dns
  namespace: network
spec:
  description: "external-dns: Sync Kubernetes services/ingresses to DNS providers"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: external-dns
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
#% if monitoring_enabled | default(false) %#
    #| Prometheus metrics scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "7979"
              protocol: TCP
#% endif %#
  egress:
    #| Kubernetes API access #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    #| Cloudflare API #|
    - toFQDNs:
        - matchPattern: "api.cloudflare.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% if unifi_dns_enabled | default(false) %#
    #| UniFi Controller API (if configured) #|
    - toFQDNs:
        - matchName: "#{ unifi_host }#"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#
#% endif %#
```

### ~~Phase 3: Low Priority~~ ✅ COMPLETED

> **All Phase 3 items have been implemented.** The following sections are preserved for reference.

#### 3.1 Reloader Network Policy ✅

**File:** `templates/config/kubernetes/apps/kube-system/network-policies/app/reloader.yaml.j2` (EXISTS)

Implementation follows Pattern A (single CiliumNetworkPolicy) with proper conditionals.

#### 3.2 Cloudflare Tunnel Network Policy ✅

**File:** `templates/config/kubernetes/apps/network/network-policies/app/cloudflare-tunnel.yaml.j2` (EXISTS)

> **Note:** Implementation uses centralized network-policies directory pattern.

**Implementation:**

```yaml
#% if network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| Cloudflare Tunnel network policy: Outbound tunnel to Cloudflare edge #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cloudflared
  namespace: network
spec:
  description: "Cloudflared: Outbound tunnel to Cloudflare for external ingress"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: cloudflared
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: false  # No ingress - outbound tunnel only
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
    #| Cloudflare tunnel endpoints #|
    - toFQDNs:
        - matchPattern: "*.argotunnel.com"
        - matchPattern: "*.cloudflare.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    #| Internal services (proxied via tunnel) #|
    - toEntities:
        - cluster
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
#% endif %#
```

## Policy Requirements by Component Type

### 1. Web UI Components (HTTPRoute Exposed)

**Examples:** Hubble UI, RustFS Console, Grafana

**Required Policies:**

- ✅ CiliumNetworkPolicy (Pattern A)
- ❌ Standard NetworkPolicy (infrastructure component)

**Ingress Requirements:**

- Envoy Gateway (internal and/or external)
- Optional: Prometheus metrics scraping

**Egress Requirements:**

- DNS (CoreDNS)
- Backend services (specific to component)
- Optional: kube-apiserver (if needed for data)

**Security Considerations:**

- OIDC protection via SecurityPolicy (if supported by application)
- Native authentication as fallback (RustFS)
- Rate limiting via gateway

### 2. Application Components (with Database)

**Examples:** LiteLLM, Langfuse, Keycloak

**Required Policies:**

- ✅ CiliumNetworkPolicy (main app + database)
- ✅ Standard NetworkPolicy (main app + database)

**Ingress Requirements:**

- Envoy Gateway (for web UI)
- Optional: Inter-component (e.g., LiteLLM → Langfuse)
- Optional: Prometheus metrics scraping

**Egress Requirements:**

- DNS (CoreDNS)
- PostgreSQL database (CNPG cluster)
- External APIs (FQDN-based in Cilium, IP CIDR in NetworkPolicy)
- Optional: Keycloak (OIDC SSO)
- Optional: Dragonfly (Redis cache)
- Optional: RustFS (S3 storage)
- Optional: Tempo (OpenTelemetry tracing)

**Database Policy Requirements:**

- Ingress: App access, CNPG operator, inter-replica, metrics
- Egress: DNS, inter-replica, S3 backups (optional)

**Security Considerations:**

- FQDN egress filtering (CiliumNetworkPolicy)
- IP CIDR fallback (NetworkPolicy)
- Database isolation (separate policies)
- Multi-tenant cache access (ACL in Dragonfly)

### 3. Monitoring Components

**Examples:** Prometheus, Grafana, Loki, Alloy, Tempo

**Required Policies:**

- ✅ CiliumNetworkPolicy (Pattern A)
- ❌ Standard NetworkPolicy (infrastructure component)

**Ingress Requirements:**

- Component-specific (e.g., Grafana from gateway)
- Inter-component (e.g., Grafana → Prometheus)
- Prometheus scraping (for self-monitoring)

**Egress Requirements:**

- DNS (CoreDNS)
- kube-apiserver (service discovery)
- Cluster-wide scraping (toEntities: cluster)
- Node metrics (toEntities: host, remote-node)
- Optional: External storage (S3 for Loki)

**Special Cases:**

- **Prometheus**: Broad cluster egress for metrics scraping
- **Loki**: External S3 egress when using SimpleScalable mode
- **Alloy**: Broad cluster ingress for log/metric collection

### 4. Infrastructure Components

**Examples:** CoreDNS, Spegel, cert-manager, external-dns

**Required Policies:**

- ✅ CiliumNetworkPolicy (Pattern A)
- ❌ Standard NetworkPolicy (infrastructure component)

**Ingress Requirements:**

- Component-specific (e.g., DNS queries for CoreDNS)
- Optional: Prometheus metrics scraping

**Egress Requirements:**

- DNS (CoreDNS)
- kube-apiserver (most infrastructure components)
- External services (component-specific)

**Special Cases:**

- **CoreDNS**: Broad cluster ingress (`fromEntities: cluster`)
- **cert-manager**: ACME challenge egress (Let's Encrypt)
- **external-dns**: DNS provider API egress (Cloudflare, UniFi)

### 5. Cache Services

**Examples:** Dragonfly

**Required Policies:**

- ✅ CiliumNetworkPolicy (Pattern A)
- ❌ Standard NetworkPolicy (infrastructure component)

**Ingress Requirements:**

- Authorized namespaces (identity, ai-system, default)
- Prometheus metrics scraping

**Egress Requirements:**

- DNS (CoreDNS)
- Optional: S3 backups (RustFS)

**Security Considerations:**

- Namespace isolation (only allow specific namespaces)
- ACL-based multi-tenancy (separate credentials per app)
- No external egress except backups

### 6. Database Services (CNPG PostgreSQL)

**Examples:** LiteLLM PostgreSQL, Langfuse PostgreSQL, Keycloak PostgreSQL

**Required Policies:**

- ✅ CiliumNetworkPolicy (kube-apiserver + DNS)
- ✅ Standard NetworkPolicy (full ingress/egress)

**Ingress Requirements:**

- Application access (port 5432)
- CNPG operator health checks (port 8000)
- Inter-replica replication (port 5432, 8000)
- Prometheus metrics (port 9187)

**Egress Requirements:**

- DNS (CoreDNS)
- Inter-replica replication (port 5432)
- Optional: S3 backups (RustFS port 9000)

**Security Considerations:**

- Separate network policy from application
- Use `cnpg.io/cluster` label for pod selection
- CNPG operator requires access on port 8000

## Testing and Validation

### Pre-Deployment Testing (Audit Mode)

**Step 1: Deploy in Audit Mode**

```yaml
# cluster.yaml
network_policies_enabled: true
network_policies_mode: "audit"  # Non-enforcing
```

```bash
task configure
flux reconcile ks cluster-apps --with-source
```

**Step 2: Monitor Traffic Patterns**

```bash
# Monitor all traffic for a specific namespace
hubble observe --namespace ai-system

# Monitor traffic for a specific pod
hubble observe --pod litellm-0 --namespace ai-system

# Monitor traffic between specific endpoints
hubble observe --from-namespace ai-system --to-namespace monitoring

# Monitor all dropped traffic (should be empty in audit mode)
hubble observe --verdict DROPPED
```

**Step 3: Analyze Traffic Flows**

```bash
# Export flow data for analysis
hubble observe --namespace ai-system --output json > flows.json

# Identify unique source/destination pairs
hubble observe --namespace ai-system | grep -E "from|to" | sort -u

# Check for unexpected external connections
hubble observe --namespace ai-system --to-fqdn
```

**Step 4: Adjust Policies**

Based on observed traffic, add missing rules:

```yaml
# Example: Found unexpected traffic to new service
egress:
  #| New service discovered during testing #|
  - toEndpoints:
      - matchLabels:
          app.kubernetes.io/name: new-service
    toPorts:
      - ports:
          - port: "8080"
            protocol: TCP
```

### Enforcement Testing

**Step 1: Switch to Enforce Mode**

```yaml
# cluster.yaml
network_policies_mode: "enforce"  # Enforcing
```

```bash
task configure
flux reconcile ks cluster-apps --with-source
```

**Step 2: Verify No Unexpected Drops**

```bash
# Monitor for dropped traffic
hubble observe --verdict DROPPED

# Monitor specific application for drops
hubble observe --pod litellm-0 --verdict DROPPED
```

**Step 3: Test Application Functionality**

```bash
# Test web UI access
curl -I https://litellm.${SECRET_DOMAIN}

# Test database connectivity
kubectl -n ai-system exec -it litellm-0 -- nc -zv litellm-postgresql.ai-system.svc.cluster.local 5432

# Test cache connectivity
kubectl -n ai-system exec -it litellm-0 -- nc -zv dragonfly.cache.svc.cluster.local 6379

# Test S3 connectivity
kubectl -n ai-system exec -it litellm-0 -- nc -zv rustfs-svc.storage.svc.cluster.local 9000
```

**Step 4: Test Negative Cases (Should Fail)**

```bash
# Attempt unauthorized database access from different namespace
kubectl -n default run test --image=postgres:18 --rm -it -- psql -h litellm-postgresql.ai-system.svc.cluster.local -U litellm

# Attempt unauthorized cache access
kubectl -n default run test --image=redis:alpine --rm -it -- redis-cli -h dragonfly.cache.svc.cluster.local ping

# Should see drops in Hubble
hubble observe --verdict DROPPED --namespace default
```

### Continuous Validation

**Automated Testing with Cilium Connectivity Test:**

```bash
# Run comprehensive connectivity tests
cilium connectivity test

# Test specific namespace
cilium connectivity test --namespace ai-system
```

**Regular Hubble Audits:**

```bash
# Weekly audit of dropped traffic
hubble observe --verdict DROPPED --since 7d > dropped-traffic-$(date +%Y%m%d).log

# Analyze for patterns
cat dropped-traffic-*.log | grep -E "DROPPED" | awk '{print $10,$12}' | sort | uniq -c | sort -rn
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Application Cannot Connect to Database

**Symptoms:**

```bash
kubectl -n ai-system logs litellm-0
# Error: could not connect to server: Connection refused
```

**Diagnosis:**

```bash
# Check if traffic is being dropped
hubble observe --pod litellm-0 --verdict DROPPED

# Expected output if policy issue:
# DROPPED (Policy denied) flow ai-system/litellm-0 -> ai-system/litellm-postgresql-1:5432
```

**Solution:**

Check NetworkPolicy allows database egress:

```yaml
egress:
  #| Allow PostgreSQL connection to CloudNativePG cluster #|
  - to:
      - podSelector:
          matchLabels:
            cnpg.io/cluster: litellm-postgresql  # Verify label matches
    ports:
      - protocol: TCP
        port: 5432
```

Verify database pod labels:

```bash
kubectl -n ai-system get pods -l cnpg.io/cluster=litellm-postgresql --show-labels
```

#### Issue 2: External API Calls Failing

**Symptoms:**

```bash
kubectl -n ai-system logs litellm-0
# Error: Failed to connect to api.openai.azure.com
```

**Diagnosis:**

```bash
# Check for DNS resolution drops
hubble observe --pod litellm-0 --protocol UDP --port 53

# Check for external egress drops
hubble observe --pod litellm-0 --verdict DROPPED --to-fqdn
```

**Solution:**

Ensure FQDN-based egress in CiliumNetworkPolicy:

```yaml
egress:
  #| Azure OpenAI endpoints #|
  - toFQDNs:
      - matchPattern: "*.openai.azure.com"
    toPorts:
      - ports:
          - port: "443"
            protocol: TCP
```

Ensure IP CIDR fallback in NetworkPolicy:

```yaml
egress:
  #| External LLM providers #|
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except:
            - 10.0.0.0/8
            - 172.16.0.0/12
            - 192.168.0.0/16
    ports:
      - protocol: TCP
        port: 443
```

#### Issue 3: Prometheus Cannot Scrape Metrics

**Symptoms:**

```bash
# Prometheus UI shows target down
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus
# Error: context deadline exceeded scraping target
```

**Diagnosis:**

```bash
# Check if Prometheus traffic is being dropped
hubble observe --from-namespace monitoring --to-namespace ai-system --verdict DROPPED
```

**Solution:**

Ensure application policy allows Prometheus ingress:

```yaml
#% if monitoring_enabled | default(false) %#
ingress:
  #| Allow Prometheus scraping #|
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
    ports:
      - protocol: TCP
        port: 4000  # Verify correct port
#% endif %#
```

Verify namespace label:

```bash
kubectl get namespace monitoring --show-labels
# Should include: kubernetes.io/metadata.name=monitoring
```

#### Issue 4: HTTP 503 from Gateway (Envoy)

**Symptoms:**

```bash
curl https://litellm.${SECRET_DOMAIN}
# 503 Service Unavailable
```

**Diagnosis:**

```bash
# Check if Envoy traffic is being dropped
hubble observe --from-namespace network --to-namespace ai-system --verdict DROPPED

# Check Envoy logs
kubectl -n network logs -l gateway.networking.k8s.io/gateway-name=internal
```

**Solution:**

Ensure application policy allows Envoy ingress:

```yaml
ingress:
  #| Allow from Envoy Gateway (external access) #|
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: network
    ports:
      - protocol: TCP
        port: 4000  # Verify matches service port
```

Verify HTTPRoute backend port matches service:

```bash
kubectl -n network get httproute litellm -o yaml | grep port
kubectl -n ai-system get svc litellm -o yaml | grep port
```

#### Issue 5: DNS Resolution Failing

**Symptoms:**

```bash
kubectl -n ai-system logs litellm-0
# Error: no such host
```

**Diagnosis:**

```bash
# Check DNS traffic
hubble observe --pod litellm-0 --protocol UDP --port 53

# Test DNS from pod
kubectl -n ai-system exec -it litellm-0 -- nslookup rustfs-svc.storage.svc.cluster.local
```

**Solution:**

Ensure DNS egress in EVERY policy:

```yaml
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
```

Verify CoreDNS pods are running:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

#### Issue 6: Database Replication Failing (CNPG)

**Symptoms:**

```bash
kubectl cnpg status litellm-postgresql -n ai-system
# Replica out of sync
```

**Diagnosis:**

```bash
# Check inter-replica traffic
hubble observe --namespace ai-system --label cnpg.io/cluster=litellm-postgresql
```

**Solution:**

Ensure database policy allows inter-replica communication:

```yaml
ingress:
  #| Allow from other database replicas (replication and health checks) #|
  - from:
      - podSelector:
          matchLabels:
            cnpg.io/cluster: litellm-postgresql
    ports:
      #| PostgreSQL replication #|
      - protocol: TCP
        port: 5432
      #| CNPG instance manager HTTP API #|
      - protocol: TCP
        port: 8000

egress:
  #| Replication and health checks between database pods #|
  - to:
      - podSelector:
          matchLabels:
            cnpg.io/cluster: litellm-postgresql
    ports:
      - protocol: TCP
        port: 5432
      - protocol: TCP
        port: 8000
```

### Debugging Commands Reference

**View CiliumNetworkPolicy:**

```bash
kubectl get ciliumnetworkpolicies -A
kubectl describe ciliumnetworkpolicy litellm -n ai-system
```

**View Standard NetworkPolicy:**

```bash
kubectl get networkpolicies -A
kubectl describe networkpolicy litellm -n ai-system
```

**View Applied Policies on Pod:**

```bash
kubectl -n ai-system exec -it litellm-0 -- env | grep POD
cilium endpoint list | grep litellm
cilium endpoint get <endpoint-id>
```

**Test Connectivity from Pod:**

```bash
# TCP connectivity test
kubectl -n ai-system exec -it litellm-0 -- nc -zv rustfs-svc.storage.svc.cluster.local 9000

# DNS resolution test
kubectl -n ai-system exec -it litellm-0 -- nslookup rustfs-svc.storage.svc.cluster.local

# HTTP test
kubectl -n ai-system exec -it litellm-0 -- curl -I http://rustfs-svc.storage.svc.cluster.local:9000
```

**Export Hubble Flows for Analysis:**

```bash
# All flows
hubble observe --output json > all-flows.json

# Dropped flows only
hubble observe --verdict DROPPED --output json > dropped-flows.json

# Namespace-specific flows
hubble observe --namespace ai-system --output json > ai-system-flows.json
```

## References

### Industry Standards

- [NIST SP 800-207 - Zero Trust Architecture](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-207.pdf)
- [CISA Zero Trust Maturity Model](https://www.cisa.gov/zero-trust-maturity-model)
- [Kubernetes Network Policies Best Practices](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Cilium Network Policy Guide](https://docs.cilium.io/en/stable/security/policy/)

### Project Documentation

- [Cilium Network Policies Research](../research/archive/cilium-network-policies-jan-2026.md)
- [Architecture Overview](../ARCHITECTURE.md)
- [Configuration Reference](../CONFIGURATION.md)
- [Troubleshooting Guide](../TROUBLESHOOTING.md)

### Related Guides

- [Observability Stack Implementation](./observability-stack-implementation-victoriametrics.md)
- [BGP UniFi Cilium Implementation](../bgp-unifi-cilium-implementation.md)
- [CNPG Implementation](../completed/cnpg-implementation.md)

---

**Document History:**

- 2026-01-09: Comprehensive audit and validation - Updated current state analysis to reflect 22 implemented policies; marked Phase 2 and Phase 3 as COMPLETED; corrected gap analysis to show only Hubble UI and RustFS as remaining gaps
- 2026-01-08: Initial version documenting current state and remediation plan
