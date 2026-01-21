# Envoy Gateway Examples Analysis & Adoption Recommendations

> **Research Date:** 2026-01-02
> **Last Validated:** 2026-01-03
> **Status:** Research Complete - Validated ✅
> **Source:** https://github.com/envoyproxy/gateway/tree/main/examples
> **Target Version:** v0.0.0-latest (K8s 1.35 compatible)

## Version Context

| Component | Version | Release Date | Notes |
| ----------- | --------- | -------------- | ------- |
| **Envoy Gateway (in use)** | v0.0.0-latest | Rolling | ✅ Active - K8s 1.35 support |
| **Envoy Gateway (stable)** | v1.6.1 | Dec 5, 2025 | K8s 1.30-1.33 only |
| **Gateway API CRDs** | v1.4.1 | Dec 4, 2024 | Experimental channel |
| **Kubernetes** | v1.35.0 | - | Project target |

**Why v0.0.0-latest?** This project uses `v0.0.0-latest` because no stable release supports K8s 1.35 yet. As of January 3, 2026, v1.7 has not been released. K8s 1.35 tests were added Dec 30, 2025 in preparation for future releases. When v1.7 releases with K8s 1.35 support, migration to stable is recommended. Monitor [Envoy Gateway Releases](https://github.com/envoyproxy/gateway/releases).

## Executive Summary

This document provides a comprehensive analysis of the official Envoy Gateway examples repository, evaluating each example's relevance and adoption potential for the matherlynet-talos-cluster. The analysis considers the existing cluster configuration, GitOps patterns, and operational requirements.

### Key Findings

| Priority | Category | Recommendation |
| ---------- | ---------- | ---------------- |
| **High** | Access Logging | Adopt JSON/OTel logging patterns (CEL filtering available in v1.6+) |
| **High** | JWT Authentication | Adopt for service-to-service auth (JWKS cacheDuration configurable) |
| **Medium** | Distributed Tracing | Adopt Zipkin/OTel patterns |
| **Medium** | Merged Gateways | Evaluate for gateway consolidation |
| **Low** | gRPC/TCP Routing | Adopt when needed (requires experimental channel) |
| **Low** | Extension Server | Reference for custom extensions |

---

## Table of Contents

1. [Current Project Configuration Analysis](#current-project-configuration-analysis)
2. [Examples Directory Structure](#examples-directory-structure)
3. [Kubernetes Examples Analysis](#kubernetes-examples-analysis)
4. [Observability Examples Analysis](#observability-examples-analysis)
5. [Extension Examples Analysis](#extension-examples-analysis)
6. [Adoption Recommendations](#adoption-recommendations)
7. [Implementation Templates](#implementation-templates)
8. [References](#references)

---

## Current Project Configuration Analysis

### Existing Envoy Gateway Setup

The cluster already has a mature configuration:

```
templates/config/kubernetes/apps/network/envoy-gateway/app/
├── certificate.yaml.j2      # Wildcard TLS certificate
├── envoy.yaml.j2           # EnvoyProxy, GatewayClass, Gateways, Policies
├── helmrelease.yaml.j2     # Flux HelmRelease
├── kustomization.yaml.j2   # Kustomize resources
├── ocirepository.yaml.j2   # OCI chart source
└── podmonitor.yaml.j2      # Prometheus PodMonitor
```

### Current Features Implemented

| Feature | Status | Configuration |
| --------- | -------- | --------------- |
| **EnvoyProxy** | ✅ Configured | 2 replicas, resource limits, drain timeout |
| **GatewayClass** | ✅ Configured | `envoy` class with custom EnvoyProxy |
| **External Gateway** | ✅ Configured | HTTPS with Cloudflare integration |
| **Internal Gateway** | ✅ Configured | HTTPS with Cilium LB IP |
| **ClientTrafficPolicy** | ✅ Configured | XFF, HTTP/2, HTTP/3, TLS 1.2+ |
| **BackendTrafficPolicy** | ✅ Configured | Brotli/Gzip compression, keepalive |
| **HTTPRoute (redirect)** | ✅ Configured | HTTP→HTTPS 301 redirect |
| **Prometheus Metrics** | ✅ Configured | PodMonitor with Gzip compression |
| **TLS Certificates** | ✅ Configured | Wildcard via cert-manager |

### Current Implementation Status (Updated January 2026)

| Feature | Status | Notes |
| ------- | ------ | ----- |
| JSON Access Logging | ✅ **DEPLOYED** | Official JSON format in `envoy.yaml.j2` lines 27-59 |
| Distributed Tracing | ✅ **DEPLOYED** | Zipkin/Tempo integration, `tracing_enabled: true` |
| JWT SecurityPolicy | ⏳ **TEMPLATES READY** | `securitypolicy-jwt.yaml.j2` exists, OIDC config needed |
| Prometheus Metrics | ✅ **DEPLOYED** | Gzip compression enabled |
| OTel Metrics Sink | ❌ Not implemented | Optional unified observability |
| gRPC Routing | ❌ Not implemented | Adopt when gRPC services deployed |
| TCP/TLS Passthrough | ❌ Not implemented | Adopt when needed |

### Remaining Gaps

| Gap | Impact | Priority |
| ----- | -------- | ---------- |
| JWT/OIDC Config | OIDC provider variables commented out | High (when OIDC available) |
| OTel Metrics Sink | Missing unified observability option | Low |
| gRPC Routing | Not configured (may be needed for services) | Low |
| TCP/TLS Passthrough | Not configured | Low |

---

## Examples Directory Structure

### Top-Level Organization

```
examples/
├── admin-console-config.yaml     # Development/production config patterns
├── envoy-ext-auth/               # External authentication service
├── extension-server/             # Full extension server implementation
├── grpc-ext-proc/               # gRPC external processing
├── kubernetes/                   # Main Kubernetes examples
│   ├── accesslog/               # Access logging patterns
│   ├── jwt/                     # JWT authentication
│   ├── metric/                  # Metrics configuration
│   └── tracing/                 # Distributed tracing
├── preserve-case-backend/        # Header case sensitivity
├── redis/                        # Redis integration
├── simple-extension-server/      # Simplified extension example
└── standalone/                   # Non-Kubernetes deployment
```

---

## Kubernetes Examples Analysis

### 1. Routing Examples

#### HTTP Routing (`http-routing.yaml`)

**What it demonstrates:**

- Basic HTTPRoute with host-based routing
- Path prefix matching (`/login`)
- Header-based routing (canary deployments)

**Current project comparison:**

- Project already has HTTPS redirect HTTPRoute
- Pattern useful for application routing templates

**Adoption recommendation:** ✅ **Reference for app routing patterns**

```yaml
# Example pattern for canary deployments
rules:
  - matches:
      - headers:
          - type: Exact
            name: env
            value: canary
    backendRefs:
      - name: app-canary
        port: 8080
  - backendRefs:
      - name: app-stable
        port: 8080
```

---

#### gRPC Routing (`grpc-routing.yaml`)

**What it demonstrates:**

- GRPCRoute resource (experimental channel)
- gRPC service backend configuration

**Current project status:** Not configured

**Adoption recommendation:** ✅ **Adopt when gRPC services deployed**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-service
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "grpc.${SECRET_DOMAIN}"
  rules:
    - backendRefs:
        - name: grpc-service
          port: 9000
```

---

#### TCP Routing (`tcp-routing.yaml`)

**What it demonstrates:**

- TCPRoute with multiple listeners on different ports
- Gateway listener configuration for TCP protocol

**Current project status:** Not configured

**Adoption recommendation:** ⏸️ **Defer until TCP services needed**

**Use cases:**

- Database connections (PostgreSQL, MySQL)
- Redis/memcached access
- Custom TCP protocols

---

#### TLS Passthrough (`tls-passthrough.yaml`)

**What it demonstrates:**

- TLSRoute for SNI-based routing without termination
- End-to-end encryption to backend

**Current project status:** Not configured (TLS termination at gateway)

**Adoption recommendation:** ⏸️ **Consider for mTLS requirements**

**Use cases:**

- Services requiring end-to-end mTLS
- Legacy applications with embedded certificates
- Compliance requirements for unbroken encryption

---

#### TLS Termination (`tls-termination.yaml`)

**What it demonstrates:**

- Gateway listener with TLS mode "Terminate"
- Certificate reference pattern

**Current project comparison:** ✅ Already implemented similarly

**Adoption recommendation:** ℹ️ **Reference only - already implemented**

---

### 2. Gateway Configuration Examples

#### Merged Gateways (`merged-gateways.yaml`)

**What it demonstrates:**

- Single Envoy proxy serving multiple Gateway resources
- `mergeGateways: true` in EnvoyProxy spec
- Reduced resource consumption

**Current project status:** Two separate gateways (external/internal)

**Adoption recommendation:** 🔍 **Evaluate for optimization**

**Potential benefits:**

- Reduced pod count
- Lower resource usage
- Simplified management

**Potential drawbacks:**

- Single point of failure
- Mixed security domains

```yaml
# Pattern for merged gateways
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: merged-config
spec:
  mergeGateways: true
  # ... other config
```

---

#### Gateway Namespace Mode (`gateway-namespace-mode.yaml`)

**What it demonstrates:**

- Deploy Envoy proxies in same namespace as Gateway

**Current project comparison:** ✅ Already using `GatewayNamespace` mode

```yaml
# Current configuration in helmrelease.yaml.j2
config:
  envoyGateway:
    provider:
      type: Kubernetes
      kubernetes:
        deploy:
          type: GatewayNamespace
```

**Adoption recommendation:** ℹ️ **Already implemented**

---

#### EnvoyProxy Config (`envoy-proxy-config.yaml`)

**What it demonstrates:**

- Custom image configuration
- Resource requests/limits
- Pod and service annotations

**Current project comparison:** ✅ Already implemented with similar patterns

**Notable differences:**

| Setting | Example | Current Project |
| --------- | --------- | ----------------- |
| Replicas | 2 | 2 ✅ |
| CPU Request | 150m | 100m |
| Memory Request | 640Mi | Not set |
| Memory Limit | 1Gi | 1Gi ✅ |
| CPU Limit | 500m | Not set |

**Adoption recommendation:** 🔧 **Consider adding CPU limits and memory requests**

---

#### Zone-Aware Routing (`zone-aware-routing.yaml`)

**What it demonstrates:**

- Pod affinity/anti-affinity for zone-aware traffic
- Scheduler-based locality routing

**Current project status:** Not configured

**Adoption recommendation:** ⏸️ **Defer - single zone deployment**

**When to adopt:**

- Multi-zone cluster deployment
- Cross-region traffic optimization
- Data locality requirements

---

#### Multicluster Service (`multicluster-service.yaml`)

**What it demonstrates:**

- ServiceImport from Submariner
- ReferenceGrant for cross-namespace access

**Current project status:** Single cluster

**Adoption recommendation:** ⏸️ **Defer - not multicluster**

---

### 3. Security Examples

> **Updated:** January 2026 - Validated against [OIDC Authentication docs](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)

#### JWT Authentication (`jwt/jwt.yaml`)

**What it demonstrates:**

- SecurityPolicy with JWT provider
- Remote JWKS validation
- Route-level targeting
- Claim-to-header injection

**Current project status:** Not configured (see OIDC research)

**Adoption recommendation:** ✅ **High priority for API protection**

**New in v1.6:**

- Configurable `cacheDuration` for remoteJWKS
- OIDC refresh token auto-enabled (set `refreshToken: false` to disable)
- `CSRFTokenTTL` configuration available

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-example
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: protected-api
  jwt:
    providers:
      - name: keycloak
        issuer: https://auth.${SECRET_DOMAIN}/realms/matherlynet
        remoteJWKS:
          uri: https://auth.${SECRET_DOMAIN}/realms/matherlynet/protocol/openid-connect/certs
          cacheDuration: 300s  # New in v1.6 - configurable cache
        claimToHeaders:
          - claim: sub
            header: X-User-ID
          - claim: email
            header: X-User-Email
          - claim: groups
            header: X-User-Groups
```

**Integration with existing OIDC research:**

- Complements `envoy-gateway-oidc-integration.md` findings
- JWT validation for API endpoints (service-to-service)
- OIDC for interactive user sessions (browser-based)
- Can combine JWT + OIDC on same HTTPRoute

---

#### External Auth gRPC (`ext-auth-grpc-service.yaml`)

**What it demonstrates:**

- Custom gRPC authorization service
- Bearer token validation
- TLS between gateway and auth service

**Current project status:** Not needed if using native OIDC

**Adoption recommendation:** ⏸️ **Reference only - prefer native OIDC**

---

#### External Auth HTTP (`ext-auth-http-service.yaml`)

**What it demonstrates:**

- HTTP-based external authorization
- Token to user mapping

**Current project status:** Consider with OAuth2-Proxy approach

**Adoption recommendation:** ⏸️ **Reference for Phase 2 OIDC implementation**

---

### 4. Advanced Features

#### External Processing (`ext-proc-grpc-service.yaml`)

**What it demonstrates:**

- gRPC external processor for request/response modification
- Header manipulation at proxy level

**Current project status:** Not needed

**Adoption recommendation:** ⏸️ **Reference for advanced use cases**

**Use cases:**

- Request transformation
- Response modification
- Custom logging/metrics injection

---

#### Merge Patch (`mergepatch.yaml`)

**What it demonstrates:**

- EnvoyPatchPolicy for low-level Envoy config

**Current project status:** Not using EnvoyPatchPolicy

**Adoption recommendation:** ⏸️ **Avoid unless necessary**

**Note:** EnvoyPatchPolicy is brittle across version upgrades

---

---

## Observability Examples Analysis

### 1. Access Logging (`accesslog/`)

> **Updated:** January 2026 - Validated against [official documentation](https://gateway.envoyproxy.io/docs/tasks/observability/proxy-accesslog/)

#### Available Patterns

| File | Description | Adoption Priority |
| ------ | ------------- | ------------------- |
| `json-accesslog.yaml` | Structured JSON logging | **High** |
| `otel-accesslog.yaml` | OpenTelemetry export | **High** |
| `text-accesslog.yaml` | Plain text logging | Low |
| `multi-sinks.yaml` | Multiple destinations | Medium |
| `als-accesslog.yaml` | Access Log Service (gRPC) | Low |
| `disable-accesslog.yaml` | Disable logging | Reference |

#### New in v1.6+: Advanced Logging Features

| Feature | Description | Use Case |
| --------- | ------------- | ---------- |
| **CEL Expression Filtering** | Filter logs using CEL | Conditional logging |
| **Route/Listener-Specific** | Different formats per type | Debug unmatched traffic |
| **ALS gRPC Backend** | Send logs to gRPC service | External log processing |

#### Recommended: JSON Access Logging (Official Default Format)

**Benefits:**

- Structured format for log aggregation
- Parseable by Loki, Elasticsearch, etc.
- Compatible with existing kube-prometheus-stack
- Includes response code details and failure reasons

```yaml
# Template: accesslog-config.yaml.j2
# Based on official Envoy Gateway default JSON format (January 2026)
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoy
  namespace: network
spec:
  # ... existing config ...
  telemetry:
    accessLog:
      settings:
        - format:
            type: JSON
            json:
              start_time: "%START_TIME%"
              method: "%REQ(:METHOD)%"
              x-envoy-origin-path: "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
              protocol: "%PROTOCOL%"
              response_code: "%RESPONSE_CODE%"
              response_flags: "%RESPONSE_FLAGS%"
              response_code_details: "%RESPONSE_CODE_DETAILS%"
              connection_termination_details: "%CONNECTION_TERMINATION_DETAILS%"
              upstream_transport_failure_reason: "%UPSTREAM_TRANSPORT_FAILURE_REASON%"
              bytes_received: "%BYTES_RECEIVED%"
              bytes_sent: "%BYTES_SENT%"
              duration: "%DURATION%"
              x-envoy-upstream-service-time: "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%"
              x-forwarded-for: "%REQ(X-FORWARDED-FOR)%"
              user-agent: "%REQ(USER-AGENT)%"
              x-request-id: "%REQ(X-REQUEST-ID)%"
              ":authority": "%REQ(:AUTHORITY)%"
              upstream_host: "%UPSTREAM_HOST%"
              upstream_cluster: "%UPSTREAM_CLUSTER%"
              upstream_local_address: "%UPSTREAM_LOCAL_ADDRESS%"
              downstream_local_address: "%DOWNSTREAM_LOCAL_ADDRESS%"
              downstream_remote_address: "%DOWNSTREAM_REMOTE_ADDRESS%"
              requested_server_name: "%REQUESTED_SERVER_NAME%"
              route_name: "%ROUTE_NAME%"
          sinks:
            - type: File
              file:
                path: /dev/stdout
```

#### New: CEL Expression Filtering (v1.6+)

Filter logs based on request characteristics:

```yaml
# Only log requests with specific header
settings:
  - format:
      type: JSON
      json:
        # ... format fields ...
    matches:
      - "'x-envoy-logged' in request.headers"
    sinks:
      - type: File
        file:
          path: /dev/stdout
```

#### New: Route vs Listener-Specific Logging (v1.6+)

Different logging for matched routes vs unmatched traffic:

```yaml
settings:
  - type: Route    # Logs for matched routes (default behavior)
  - type: Listener # Logs for unmatched traffic
    format:
      type: Text
      text: |
        [%START_TIME%] %DOWNSTREAM_REMOTE_ADDRESS% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DOWNSTREAM_TRANSPORT_FAILURE_REASON%
    sinks:
      - type: OpenTelemetry
        openTelemetry:
          host: otel-collector.monitoring.svc.cluster.local
          port: 4317
```

#### Recommended: OpenTelemetry Access Logging

**Benefits:**

- Native integration with OTel Collector
- Correlation with traces
- Centralized observability

```yaml
# For OTel integration (when collector deployed)
sinks:
  - type: OpenTelemetry
    openTelemetry:
      host: otel-collector.monitoring.svc.cluster.local
      port: 4317
      resources:
        k8s.cluster.name: matherlynet
```

---

### 2. Metrics (`metric/`)

#### Available Patterns

| File | Description | Current Status |
| ------ | ------------- | ---------------- |
| `pod-monitor.yaml` | Prometheus PodMonitor | ✅ Implemented |
| `otel-sink.yaml` | OTel metrics export | Not implemented |
| `stats-compression.yaml` | Gzip compression | ✅ Implemented |
| `disable-prometheus.yaml` | Disable metrics | Reference |

**Current project status:** ✅ Well configured

**Adoption recommendation:** 🔍 **Consider OTel sink for unified observability**

```yaml
# Add to EnvoyProxy spec for OTel metrics
telemetry:
  metrics:
    sinks:
      - type: OpenTelemetry
        openTelemetry:
          host: otel-collector.monitoring.svc.cluster.local
          port: 4317
    prometheus:
      compression:
        type: Gzip
```

---

### 3. Distributed Tracing (`tracing/`)

#### Available Patterns

| File | Description | Adoption Priority |
| ------ | ------------- | ------------------- |
| `zipkin.yaml` | Zipkin format to OTel | **Medium** |
| `default.yaml` | Default tracing | Reference |

#### Recommended: Zipkin Tracing with OTel Collector

**Benefits:**

- Request tracing across services
- Latency analysis
- Dependency mapping
- Custom tags for filtering

```yaml
# Template: tracing-config.yaml.j2
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoy
  namespace: network
spec:
  telemetry:
    tracing:
      samplingRate: 10  # 10% sampling for production
      provider:
        host: otel-collector.monitoring.svc.cluster.local
        port: 9411
        type: Zipkin
        zipkin:
          enable128BitTraceId: true
      customTags:
        cluster:
          type: Literal
          literal:
            value: "matherlynet"
        gateway:
          type: RequestHeader
          requestHeader:
            name: ":authority"
            defaultValue: "unknown"
```

**Integration considerations:**

- Requires OpenTelemetry Collector deployment
- Consider Tempo for trace storage (integrates with Grafana)
- Start with low sampling rate in production

---

## Extension Examples Analysis

### Extension Server (`extension-server/`)

**What it provides:**

- Full Go implementation of EG extension
- Helm chart for deployment
- API definitions and internal logic

**Current project status:** Not needed

**Adoption recommendation:** ⏸️ **Reference for custom extensions**

**When to consider:**

- Custom xDS modifications
- Policy injection requirements
- Integration with external systems

---

### Simple Extension Server (`simple-extension-server/`)

**What it provides:**

- Minimal extension implementation
- Learning resource

**Adoption recommendation:** ⏸️ **Reference only**

---

### Redis Integration (`redis/`)

**What it provides:**

- Rate limiting with Redis backend
- Session storage patterns

**Current project status:** Not needed

**Adoption recommendation:** ⏸️ **Adopt if rate limiting needed**

---

### Admin Console Config (`admin-console-config.yaml`)

**What it provides:**

- Development vs production configurations
- pprof and config dump settings
- Logging level configuration

**Current project comparison:**

- Current logging level: `info`
- No admin console exposure configured

**Adoption recommendation:** 🔍 **Reference for debugging scenarios**

```yaml
# Development configuration pattern
spec:
  logging:
    level:
      default: debug
  telemetry:
    metrics:
      prometheus: {}
```

---

## Adoption Recommendations

### Priority Matrix

| Priority | Feature | Effort | Impact | Timeline |
| ---------- | --------- | -------- | -------- | ---------- |
| **P0** | JSON Access Logging | Low | High | Immediate |
| **P0** | JWT SecurityPolicy | Medium | High | With OIDC |
| **P1** | Distributed Tracing | Medium | Medium | Next sprint |
| **P1** | OTel Metrics Sink | Low | Medium | With OTel |
| **P2** | Merged Gateways | Medium | Low | Evaluate |
| **P2** | gRPC Routing | Low | Low | When needed |
| **P3** | TCP Routing | Low | Low | When needed |
| **P3** | TLS Passthrough | Low | Low | When needed |

---

### Phase 1: Immediate Adoption (This Sprint)

#### 1. Add JSON Access Logging

**Files to modify:**

- `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2`

**Changes:**

```yaml
# Add to EnvoyProxy spec.telemetry
telemetry:
  accessLog:
    settings:
      - format:
          type: JSON
          json:
            # ... JSON format spec
        sinks:
          - type: File
            file:
              path: /dev/stdout
  metrics:
    prometheus:
      compression:
        type: Gzip
```

---

### Phase 2: OIDC Integration (With Auth Implementation)

#### 2. Add JWT SecurityPolicy

**Files to create:**

- `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-jwt.yaml.j2`

**Integration with existing OIDC research:**

- Use for API authentication
- Complement OIDC for user sessions
- Enable `claimToHeaders` for backend user info

---

### Phase 3: Observability Enhancement (With OTel Stack)

#### 3. Add Distributed Tracing

**Prerequisites:**

- OpenTelemetry Collector deployed
- Tempo or Jaeger for trace storage

**Files to modify:**

- `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2`

---

### Phase 4: Optimization (Future)

#### 4. Evaluate Merged Gateways

**Decision criteria:**

- Resource constraints
- Security domain requirements
- Operational complexity tolerance

---

## Implementation Templates

> **Updated:** January 2026 - Based on official Envoy Gateway documentation

### JSON Access Logging Template (Official Format)

```yaml
# Add to envoy.yaml.j2 EnvoyProxy spec
# Based on official default JSON format - January 2026
spec:
  telemetry:
    accessLog:
      settings:
        - format:
            type: JSON
            json:
              start_time: "%START_TIME%"
              method: "%REQ(:METHOD)%"
              x-envoy-origin-path: "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
              protocol: "%PROTOCOL%"
              response_code: "%RESPONSE_CODE%"
              response_flags: "%RESPONSE_FLAGS%"
              response_code_details: "%RESPONSE_CODE_DETAILS%"
              connection_termination_details: "%CONNECTION_TERMINATION_DETAILS%"
              upstream_transport_failure_reason: "%UPSTREAM_TRANSPORT_FAILURE_REASON%"
              bytes_received: "%BYTES_RECEIVED%"
              bytes_sent: "%BYTES_SENT%"
              duration: "%DURATION%"
              x-envoy-upstream-service-time: "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%"
              x-forwarded-for: "%REQ(X-FORWARDED-FOR)%"
              user-agent: "%REQ(USER-AGENT)%"
              x-request-id: "%REQ(X-REQUEST-ID)%"
              ":authority": "%REQ(:AUTHORITY)%"
              upstream_host: "%UPSTREAM_HOST%"
              upstream_cluster: "%UPSTREAM_CLUSTER%"
              upstream_local_address: "%UPSTREAM_LOCAL_ADDRESS%"
              downstream_local_address: "%DOWNSTREAM_LOCAL_ADDRESS%"
              downstream_remote_address: "%DOWNSTREAM_REMOTE_ADDRESS%"
              requested_server_name: "%REQUESTED_SERVER_NAME%"
              route_name: "%ROUTE_NAME%"
          sinks:
            - type: File
              file:
                path: /dev/stdout
    metrics:
      prometheus:
        compression:
          type: Gzip
```

### JWT SecurityPolicy Template

> **Updated:** 2026-01-03 - Added `targetSelectors` alternative and TCPRoute limitations

```yaml
# securitypolicy-jwt.yaml.j2
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-auth
  namespace: network
spec:
  # Option 1: Direct reference by name (original pattern)
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: api-routes
  # Option 2: Label-based selection (alternative - uncomment to use)
  # targetSelectors:
  #   - group: gateway.networking.k8s.io
  #     kind: HTTPRoute
  #     matchLabels:
  #       security: jwt-protected
  jwt:
    providers:
      - name: #{ oidc_provider_name | default('keycloak') }#
        issuer: "#{ oidc_issuer_url }#"
        remoteJWKS:
          uri: "#{ oidc_jwks_uri }#"
          cacheDuration: 300s
        claimToHeaders:
          - claim: sub
            header: X-User-ID
          - claim: email
            header: X-User-Email
          - claim: groups
            header: X-User-Groups
```

#### SecurityPolicy Targeting Options

| Method | Use Case | Syntax |
| -------- | ---------- | -------- |
| `targetRefs` | Explicit named resources | `name: my-route` |
| `targetSelectors` | Label-based matching | `matchLabels: {key: value}` |

**Important Limitations:**

- SecurityPolicy can only target resources **in the same namespace** as the policy
- `targetSelectors` cannot match resources across namespaces
- TCPRoute targets are limited to IP-based authorization only (see below)

#### TCPRoute Authentication Limitations

> **Critical:** Per [SecurityPolicy docs](https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/):
> "TCPRoute support is limited to authorization using client IP allow/deny lists. JWT, API Key, Basic Auth, or OIDC are **not applicable** to TCPRoute targets."

This affects Phase 2 gRPC routing if using TCP-level routing instead of GRPCRoute.

### Distributed Tracing Template

> **Updated:** 2026-01-03 - Uses `backendRefs` syntax (current API)

```yaml
# Add to EnvoyProxy spec.telemetry
telemetry:
  tracing:
    samplingRate: #{ tracing_sample_rate | default(10) }#
    provider:
      backendRefs:
        - name: otel-collector
          namespace: #{ observability_namespace | default('monitoring') }#
          port: 9411
      type: Zipkin
      zipkin:
        enable128BitTraceId: true
    customTags:
      cluster:
        type: Literal
        literal:
          value: "#{ cluster_name | default('matherlynet') }#"
      environment:
        type: Literal
        literal:
          value: "#{ environment | default('production') }#"
      "k8s.pod.name":
        type: Environment
        environment:
          name: ENVOY_POD_NAME
          defaultValue: "-"
```

---

## References

> **Validated:** January 2026

### Official Documentation

- [Envoy Gateway Examples](https://github.com/envoyproxy/gateway/tree/main/examples)
- [Envoy Gateway Docs](https://gateway.envoyproxy.io/)
- [Gateway API Specification](https://gateway-api.sigs.k8s.io/)
- [Envoy Gateway Releases](https://github.com/envoyproxy/gateway/releases) - v1.6.1 latest stable (Dec 5, 2025)
- [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/)
- [v1.6 Release Announcement](https://gateway.envoyproxy.io/news/releases/v1.6/)

### Gateway API Resources

- [Gateway API v1.4 Blog](https://kubernetes.io/blog/2025/11/06/gateway-api-v1-4/) - GEP-1494 experimental
- [GEP-1494: HTTP External Auth](https://gateway-api.sigs.k8s.io/geps/gep-1494/)
- [Experimental Channel Install](https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml)

### Feature-Specific Documentation

- [Proxy Access Logs](https://gateway.envoyproxy.io/docs/tasks/observability/proxy-accesslog/)
- [OIDC Authentication](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)
- [External Authorization](https://gateway.envoyproxy.io/docs/tasks/security/ext-auth/)
- [Install with Helm](https://gateway.envoyproxy.io/latest/install/install-helm/)

### Related Project Research

- [`docs/research/envoy-gateway-oidc-integration.md`](./envoy-gateway-oidc-integration.md) - OIDC/OAuth2 integration
- [`docs/ai-context/cilium-networking.md`](../ai-context/cilium-networking.md) - Cilium integration patterns

### Envoy Gateway Version Notes

- **Current Target:** v0.0.0-latest (K8s 1.35 compatible)
- **Latest Stable:** v1.6.1 (Dec 5, 2025) - K8s 1.30-1.33 only
- **Experimental Features Used:** GRPCRoute, TCPRoute, TLSRoute (Gateway API experimental channel)
- **Breaking Changes:** Review [v1.5→v1.6 migration](https://gateway.envoyproxy.io/news/releases/v1.6/) - OIDC refresh token, ALPN defaults, TLS SNI

---

## Appendix: Feature Compatibility Matrix

| Feature | v1.6 | v0.0.0-latest | Notes |
| --------- | ------ | --------------- | ------- |
| HTTP Routing | ✅ | ✅ | Stable |
| HTTPS/TLS | ✅ | ✅ | Stable |
| gRPC Routing | ✅ | ✅ | Experimental channel |
| TCP Routing | ✅ | ✅ | Experimental channel |
| TLS Passthrough | ✅ | ✅ | Experimental channel |
| JWT Auth | ✅ | ✅ | Stable |
| OIDC Auth | ✅ | ✅ | Stable |
| ext_authz | ✅ | ✅ | Stable |
| Access Logging | ✅ | ✅ | Stable |
| Tracing | ✅ | ✅ | Stable |
| Merged Gateways | ✅ | ✅ | Stable |
| EnvoyPatchPolicy | ⚠️ | ⚠️ | Migration required |

---

## Appendix B: January 2026 Reflection & Validation

> **Validated:** 2026-01-03 via `/sc:reflect` and `/sc:research`
> **Last Updated:** 2026-01-03
> **Sources:** [Envoy Gateway Releases](https://github.com/envoyproxy/gateway/releases), [Gateway API v1.4](https://kubernetes.io/blog/2025/11/06/gateway-api-v1-4/), [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/), [SecurityPolicy Docs](https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/)

### Version Status Verification

#### Envoy Gateway Release Timeline

| Version | Release Date | Support Ends | K8s Support |
| --------- | -------------- | -------------- | ------------- |
| **v1.6.1** | Dec 5, 2025 | ~Jun 2026 | 1.30-1.33 |
| v1.5.6 | Dec 5, 2025 | Feb 13, 2026 | 1.30-1.33 |
| v1.4.6 | Nov 27, 2025 | Nov 13, 2025 (EOL) | 1.30-1.33 |
| **v0.0.0-latest** | Rolling | Development | **1.32-1.35** |

**Key Finding:** No v1.7 release yet. K8s 1.35 tests were added Dec 30, 2025 ([ci: add tests for Kubernetes 1.35 #7788](https://github.com/envoyproxy/gateway/commit/)), preparing for future releases.

#### Gateway API Status

| Version | Release Date | Status |
| --------- | -------------- | -------- |
| **v1.4.1** | Dec 4, 2024 | Current Stable |
| v1.4.0 | Oct 6, 2024 | GEP-1494 Experimental |

**GEP-1494 (HTTP External Auth):** Now EXPERIMENTAL in v1.4. Uses Envoy's ext_authz protocol. Available as HTTPRoute filter for authentication/authorization.

### v1.6 Breaking Changes to Note

When upgrading from v1.5 to v1.6, be aware of these changes:

| Change | Impact | Action |
| -------- | -------- | -------- |
| **OIDC Refresh Token** | Auto-enabled when issued by provider | Set `refreshToken: false` to retain old behavior |
| **ALPN Protocols** | Default `[h2, http/1.1]` when not configured | Review TLS settings |
| **TLS SNI** | Auto-detected from HTTP Host header | May affect Backend routing |
| **Certificate Validation** | Requires DNS SAN matching SNI | Update certificates if needed |

### New Features in v1.6 (Adoption Candidates)

| Feature | Description | Priority |
| --------- | ------------- | ---------- |
| **CEL Access Log Filtering** | Filter logs using CEL expressions | Medium |
| **Route/Listener-Specific Logging** | Different log settings per type | Medium |
| **JWKS Cache Duration** | Configurable `cacheDuration` for remoteJWKS | High |
| **mTLS for Extensions** | Mutual TLS for ExtensionServer | Low |
| **CSRFTokenTTL** | CSRF protection in OIDC | Medium |
| **CRL Support** | Certificate Revocation Lists in ClientTrafficPolicy | Low |

### Updated Access Logging Patterns

The official documentation now shows an enhanced default JSON format:

```yaml
# Default JSON format (from official docs)
{
  "start_time": "%START_TIME%",
  "method": "%REQ(:METHOD)%",
  "x-envoy-origin-path": "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%",
  "protocol": "%PROTOCOL%",
  "response_code": "%RESPONSE_CODE%",
  "response_flags": "%RESPONSE_FLAGS%",
  "response_code_details": "%RESPONSE_CODE_DETAILS%",
  "connection_termination_details": "%CONNECTION_TERMINATION_DETAILS%",
  "upstream_transport_failure_reason": "%UPSTREAM_TRANSPORT_FAILURE_REASON%",
  "bytes_received": "%BYTES_RECEIVED%",
  "bytes_sent": "%BYTES_SENT%",
  "duration": "%DURATION%",
  "x-envoy-upstream-service-time": "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%",
  "x-forwarded-for": "%REQ(X-FORWARDED-FOR)%",
  "user-agent": "%REQ(USER-AGENT)%",
  "x-request-id": "%REQ(X-REQUEST-ID)%",
  ":authority": "%REQ(:AUTHORITY)%",
  "upstream_host": "%UPSTREAM_HOST%",
  "upstream_cluster": "%UPSTREAM_CLUSTER%",
  "upstream_local_address": "%UPSTREAM_LOCAL_ADDRESS%",
  "downstream_local_address": "%DOWNSTREAM_LOCAL_ADDRESS%",
  "downstream_remote_address": "%DOWNSTREAM_REMOTE_ADDRESS%",
  "requested_server_name": "%REQUESTED_SERVER_NAME%",
  "route_name": "%ROUTE_NAME%"
}
```

**New: CEL Expression Filtering**

```yaml
# Filter logs based on request headers
matches:
  - "'x-envoy-logged' in request.headers"
```

**New: Route vs Listener-Specific Logging**

```yaml
settings:
  - type: Route    # Logs for matched routes
  - type: Listener # Logs for unmatched traffic
    format:
      type: Text
      text: "[%START_TIME%] %DOWNSTREAM_REMOTE_ADDRESS% ..."
```

### CRDs Chart Configuration Validated

The `gateway-crds-helm` chart parameters are confirmed:

```yaml
# Validated configuration for experimental channel
values:
  - crds:
      gatewayAPI:
        enabled: true
        channel: experimental  # or "standard"
      envoyGateway:
        enabled: true
```

### Project Configuration Validation

Current template changes reviewed and validated:

| File | Change | Status |
| ------ | -------- | -------- |
| `ocirepository.yaml.j2` | `v1.6.1` → `v0.0.0-latest` | ✅ Correct |
| `ocirepository.yaml.j2` | `mirror.gcr.io` → `docker.io` | ✅ Correct |
| `00-crds.yaml.j2` | Using `gateway-crds-helm` | ✅ Correct |
| `00-crds.yaml.j2` | `channel: experimental` | ✅ Required for K8s 1.35 |
| `helmrelease.yaml.j2` | `install/upgrade.crds: Skip` | ✅ Best practice |

### Recommendations Update

Based on January 2026 validation (updated 2026-01-03):

1. **v0.0.0-latest is necessary** for K8s 1.35 until v1.7 releases
2. **v1.7 not yet released** - As of January 3, 2026, no v1.7 release exists
3. **Experimental channel required** for GRPCRoute, TCPRoute, TLSRoute
4. **Consider v1.6 stable features** when v1.7 adds K8s 1.35 support
5. **Access logging templates updated** with official default format (`:authority` key)
6. **OIDC refresh token behavior** changed - document if using OIDC
7. **Tracing uses `backendRefs`** - Not `host`/`port` syntax
8. **SecurityPolicy `targetSelectors`** now available as alternative to `targetRefs`
9. **TCPRoute auth limitations** - Only IP-based authorization supported

### Source References

- [Envoy Gateway v1.6 Announcement](https://gateway.envoyproxy.io/news/releases/v1.6/)
- [GitHub Releases](https://github.com/envoyproxy/gateway/releases)
- [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/)
- [Gateway API v1.4 Blog](https://kubernetes.io/blog/2025/11/06/gateway-api-v1-4/)
- [GEP-1494: HTTP Auth](https://gateway-api.sigs.k8s.io/geps/gep-1494/)
- [Proxy Access Logs](https://gateway.envoyproxy.io/docs/tasks/observability/proxy-accesslog/)
- [Install with Helm](https://gateway.envoyproxy.io/latest/install/install-helm/)

---

## Changelog

| Date | Change |
| ------ | -------- |
| 2026-01-02 | Initial research document created |
| 2026-01-02 | Validated for January 2026 with inline updates throughout document |
| 2026-01-02 | Updated: Version Context, Access Logging, JWT Auth, References, Implementation Templates |
| 2026-01-03 | Validated via `/sc:reflect` - Confirmed v1.7 not yet released |
| 2026-01-03 | Updated: Tracing template to use `backendRefs` syntax (current API) |
| 2026-01-03 | Updated: JSON access log field name from `authority` to `:authority` |
| 2026-01-03 | Added: SecurityPolicy `targetSelectors` alternative to `targetRefs` |
| 2026-01-03 | Added: TCPRoute authentication limitations documentation |
| 2026-01-03 | Added: SecurityPolicy namespace limitations note |
