# Envoy Gateway Observability & Security Implementation Guide

> **Created:** 2026-01-03
> **Based on:** [Envoy Gateway Examples Analysis](../research/archive/completed/envoy-gateway-examples-analysis.md)
> **Status:** Phases 1 & 3 DEPLOYED, Phase 2 templates complete (OIDC config pending)
> **Version:** Envoy Gateway v0.0.0-latest (K8s 1.35 compatible)

## Overview

This guide provides step-by-step implementation instructions for enhancing the Envoy Gateway deployment with observability and security features based on the research analysis of official Envoy Gateway examples.

### Implementation Status

| Phase | Feature | Status | Notes |
| ----- | ------- | ------ | ----- |
| **1** | JSON Access Logging | ✅ **DEPLOYED** | Always active in `envoy.yaml.j2` |
| **2** | JWT SecurityPolicy | ⏳ **TEMPLATES READY** | Needs OIDC config in `cluster.yaml` |
| **3** | Distributed Tracing | ✅ **DEPLOYED** | `tracing_enabled: true` configured |

### Prerequisites

- Envoy Gateway deployed with `v0.0.0-latest` (for K8s 1.35 support)
- Gateway API CRDs v1.4.1 (experimental channel)
- Existing `envoy-external` and `envoy-internal` gateways configured
- **Prometheus Operator CRDs installed** (via `00-crds.yaml.j2` line 33-36, kube-prometheus-stack v80.10.0)
- **Recommended:** Full observability stack deployed (kube-prometheus-stack + Loki + Grafana platform)

> **Note:** This project installs kube-prometheus-stack **CRDs only** during bootstrap (PodMonitor, ServiceMonitor, etc.). The full observability platform (kube-prometheus-stack, Grafana, Loki, Alloy) is enabled via `monitoring_enabled: true` in `cluster.yaml`. The existing Envoy `PodMonitor` works with any Prometheus-compatible scraper.

---

## Phase 1: JSON Access Logging

### Purpose

Enable structured JSON access logging for traffic analysis, debugging, and compliance. Logs are written to stdout and collected by the log aggregation system.

> **Integration:** When the [observability stack](./archived/observability-stack-implementation-victoriametrics.md) is deployed, Alloy collects these JSON logs from pod stdout and forwards them to Loki. Query logs in Grafana using LogQL: `{namespace="network", app="envoy"}`

### Current State

The existing `EnvoyProxy` configuration has Prometheus metrics enabled but no access logging configured.

### Implementation

#### Step 1: Update EnvoyProxy Configuration

Edit `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2`:

```yaml
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoy
spec:
  logging:
    level:
      default: info
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 2
        container:
          imageRepository: docker.io/envoyproxy/envoy
          resources:
            requests:
              cpu: 100m
            limits:
              memory: 1Gi
      envoyService:
        externalTrafficPolicy: Cluster
  shutdown:
    drainTimeout: 180s
  telemetry:
    # NEW: Access Logging Configuration
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

#### Step 2: Apply Changes

```bash
# Regenerate templates
task configure

# Reconcile Flux
task reconcile

# Verify the EnvoyProxy update
kubectl get envoyproxy envoy -n network -o yaml | grep -A 50 accessLog
```

#### Step 3: Verify Logging

```bash
# Check Envoy proxy pods for JSON logs
kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-internal -c envoy --tail=20

# Expected output (JSON formatted):
# {"start_time":"2026-01-03T10:15:30.123Z","method":"GET","response_code":"200",...}
```

### Optional: CEL Expression Filtering (v1.6+)

To filter logs based on specific criteria (e.g., only log requests with a debug header):

```yaml
accessLog:
  settings:
    - format:
        type: JSON
        json:
          # ... format fields ...
      matches:
        - "'x-debug-log' in request.headers"
      sinks:
        - type: File
          file:
            path: /dev/stdout
```

### Optional: Access Log Types (v1.6+)

Envoy Gateway v1.6+ introduces granular control over which traffic generates logs:

```yaml
accessLog:
  settings:
    - type: Route      # Only log routed requests (excludes health checks, etc.)
      format:
        type: JSON
        json:
          # ... format fields ...
      sinks:
        - type: File
          file:
            path: /dev/stdout
    - type: Listener   # Log all listener-level events (connection errors, etc.)
      format:
        type: JSON
        json:
          event: "%RESPONSE_FLAGS%"
          downstream_remote_address: "%DOWNSTREAM_REMOTE_ADDRESS%"
      sinks:
        - type: File
          file:
            path: /dev/stdout
```

| Type | Use Case |
| ---- | -------- |
| `Route` | Application traffic logging (most common) |
| `Listener` | Connection-level debugging, security auditing |
| (both) | Complete visibility (default if type omitted) |

### Verification Checklist

- [ ] EnvoyProxy shows `accessLog` configuration in spec
- [ ] Envoy pods emit JSON-formatted logs to stdout
- [ ] Logs contain expected fields (method, response_code, duration, etc.)
- [ ] Loki receives logs via Alloy (if observability stack deployed)
- [ ] Grafana LogQL query returns Envoy access logs

---

## Phase 2: JWT SecurityPolicy

### Purpose

Enable JWT-based authentication for API endpoints, validating tokens against a JWKS endpoint (e.g., Keycloak). This provides service-to-service authentication without requiring browser-based OIDC flows.

### Prerequisites

- OIDC provider deployed (e.g., Keycloak)
- JWKS endpoint accessible from the cluster
- HTTPRoutes configured for protected services

### Implementation

#### Step 1: Define Template Variables

Add to `cluster.yaml` (or create as optional variables):

```yaml
# =============================================================================
# OIDC/JWT CONFIGURATION - Optional for API authentication
# =============================================================================

# -- OIDC provider name (used in SecurityPolicy)
#    (OPTIONAL) / (DEFAULT: "keycloak")
# oidc_provider_name: "keycloak"

# -- OIDC issuer URL (JWT token issuer)
#    (OPTIONAL) / (e.g. "https://auth.example.com/realms/myrealm")
# oidc_issuer_url: ""

# -- OIDC JWKS URI for JWT validation
#    (OPTIONAL) / (e.g. "https://auth.example.com/realms/myrealm/protocol/openid-connect/certs")
# oidc_jwks_uri: ""
```

#### Step 2: Create SecurityPolicy Template

Create `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-jwt.yaml.j2`:

```yaml
#% if oidc_issuer_url is defined and oidc_jwks_uri is defined %#
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-auth
  namespace: network
spec:
  # Option 1: Target specific HTTPRoutes by name
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: api-protected
  # Option 2: Target by labels (uncomment to use instead)
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
#% endif %#
```

#### Step 3: Update Kustomization

Edit `templates/config/kubernetes/apps/network/envoy-gateway/app/kustomization.yaml.j2`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./envoy.yaml
  - ./certificate.yaml
  - ./podmonitor.yaml
#% if oidc_issuer_url is defined and oidc_jwks_uri is defined %#
  - ./securitypolicy-jwt.yaml
#% endif %#
```

#### Step 4: Label Protected HTTPRoutes

For any HTTPRoute that should require JWT authentication, add the label:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-api
  namespace: my-app
  labels:
    security: jwt-protected  # If using targetSelectors
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  # ... route rules ...
```

Or reference by name in the SecurityPolicy `targetRefs`.

#### Step 5: Apply and Verify

```bash
# Regenerate templates
task configure

# Reconcile
task reconcile

# Verify SecurityPolicy
kubectl get securitypolicy -n network
kubectl describe securitypolicy jwt-auth -n network

# Test without token (should fail with 401)
curl -v https://api.example.com/protected

# Test with valid token
curl -v -H "Authorization: Bearer <valid-jwt>" https://api.example.com/protected
```

### Important Limitations

| Limitation | Description |
| ---------- | ----------- |
| **Same namespace only** | SecurityPolicy can only target resources in the same namespace |
| **TCPRoute restriction** | JWT/OIDC not available for TCPRoute - use IP-based auth only |
| **JWKS caching** | Default 5 minutes; adjust `cacheDuration` for security/performance balance |

### Verification Checklist

- [ ] SecurityPolicy created in network namespace
- [ ] Requests without valid JWT receive 401 Unauthorized
- [ ] Requests with valid JWT pass through to backend
- [ ] X-User-* headers injected for backend services
- [ ] JWKS endpoint accessible from Envoy pods

---

## Phase 3: Distributed Tracing

### Purpose

Enable request tracing across services for latency analysis, dependency mapping, and debugging. Uses Zipkin format with OpenTelemetry Collector.

### Prerequisites

> **Note:** Distributed tracing is now fully documented in the [observability stack](./archived/observability-stack-implementation-victoriametrics.md#phase-5-tempo-for-distributed-tracing). Enable `tracing_enabled: true` in `cluster.yaml`.

- [Observability stack](./archived/observability-stack-implementation-victoriametrics.md) deployed with `tracing_enabled: true`
- Alloy deployed (receives OTLP traces, forwards to Tempo)
- Tempo deployed (stores traces, queries from Grafana)
- Grafana configured with Tempo datasource (automatic when stack deployed)

### Implementation

#### Step 1: Define Template Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# OBSERVABILITY CONFIGURATION - Optional for tracing
# =============================================================================

# -- Enable distributed tracing
#    (OPTIONAL) / (DEFAULT: false)
# tracing_enabled: false

# -- Tracing sample rate (percentage, 1-100)
#    (OPTIONAL) / (DEFAULT: 10)
# tracing_sample_rate: 10

# -- OpenTelemetry Collector namespace
#    (OPTIONAL) / (DEFAULT: "monitoring")
# observability_namespace: "monitoring"

# -- Cluster name for trace tags
#    (OPTIONAL) / (DEFAULT: "matherlynet")
# cluster_name: "matherlynet"
```

#### Step 2: Update EnvoyProxy Configuration

Add tracing configuration to the existing EnvoyProxy in `envoy.yaml.j2`.

> **Integration Note:** Envoy Gateway supports three tracing providers: **Zipkin**, **OpenTelemetry**, and **Datadog**. Choose based on your backend infrastructure.

### Tracing Provider Options

| Provider | Backend | Port | Use Case |
| -------- | ------- | ---- | -------- |
| **Zipkin** | Tempo (direct) | 9411 | Simplest setup, direct to Tempo |
| **OpenTelemetry** | Alloy → Tempo | 4317 | Additional processing, multi-destination |
| **Datadog** | Datadog Agent | 8126 | Datadog APM users (requires Datadog subscription) |

### Sampling Configuration

**Percentage-based (1-100%):**
```yaml
tracing:
  samplingRate: 10  # Sample 10% of requests
```

**Fractional sampling (for rates below 1%):**
```yaml
tracing:
  samplingFraction:
    numerator: 1
    denominator: 1000  # Sample 0.1% of requests
```

> **Tip:** Use `samplingRate: 100` during debugging, then reduce to 1-10% for production to balance visibility with storage costs.

**Option A: Direct to Tempo (Simpler)**

```yaml
spec:
  telemetry:
    #% if tracing_enabled is defined and tracing_enabled %#
    tracing:
      samplingRate: #{ tracing_sample_rate | default(10) }#
      provider:
        backendRefs:
          # Tempo exposes Zipkin receiver on port 9411
          - name: tempo
            namespace: monitoring
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
    #% endif %#
    accessLog:
      # ... existing access log config ...
    metrics:
      prometheus:
        compression:
          type: Gzip
```

**Option B: Via Alloy (For additional processing/routing)**

```yaml
spec:
  telemetry:
    #% if tracing_enabled is defined and tracing_enabled %#
    tracing:
      samplingRate: #{ tracing_sample_rate | default(10) }#
      provider:
        backendRefs:
          # Alloy receives OTLP and forwards to Tempo
          - name: alloy
            namespace: monitoring
            port: 4317
        type: OpenTelemetry
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
    #% endif %#
    accessLog:
      # ... existing access log config ...
    metrics:
      prometheus:
        compression:
          type: Gzip
```

#### Step 3: Verify Trace Flow

The trace flow depends on which option you chose:

```
Option A: Envoy → Tempo (port 9411/Zipkin) → Grafana
Option B: Envoy → Alloy (port 4317/OTLP) → Tempo → Grafana
```

Both options result in traces being queryable in Grafana via the Tempo datasource.

#### Step 4: Apply and Verify

```bash
# Regenerate templates
task configure

# Reconcile
task reconcile

# Verify tracing configuration
kubectl get envoyproxy envoy -n network -o yaml | grep -A 20 tracing

# Generate test traffic
curl https://internal.example.com/api/test

# Check OTel Collector logs for received traces
kubectl logs -n monitoring -l app=otel-collector --tail=50 | grep -i trace
```

### Trace Context Propagation

Ensure backend services propagate trace headers:

| Header | Purpose |
| ------ | ------- |
| `x-request-id` | Request correlation ID |
| `x-b3-traceid` | B3 trace ID (Zipkin format) |
| `x-b3-spanid` | B3 span ID |
| `x-b3-sampled` | Sampling decision |
| `traceparent` | W3C Trace Context (alternative) |

### Verification Checklist

- [ ] EnvoyProxy shows tracing configuration
- [ ] OTel Collector receives Zipkin spans
- [ ] Traces visible in Grafana/Tempo/Jaeger
- [ ] Custom tags (cluster, environment) appear in traces
- [ ] Sampling rate matches configuration

---

## Rollback Procedures

### Phase 1 Rollback (Access Logging)

Remove the `accessLog` section from EnvoyProxy spec:

```bash
# Edit template to remove accessLog section
# Then regenerate and reconcile
task configure && task reconcile
```

### Phase 2 Rollback (JWT SecurityPolicy)

```bash
# Remove or comment out oidc_* variables from cluster.yaml
# Regenerate templates (SecurityPolicy won't be created)
task configure && task reconcile

# Or delete directly
kubectl delete securitypolicy jwt-auth -n network
```

### Phase 3 Rollback (Tracing)

```bash
# Set tracing_enabled: false in cluster.yaml
# Or remove tracing_* variables
task configure && task reconcile
```

---

## Troubleshooting

### Access Logging Issues

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| No logs appearing | EnvoyProxy not updated | Check `kubectl get envoyproxy -o yaml` |
| Logs not JSON | Format type incorrect | Verify `type: JSON` in settings |
| Missing fields | Field name typo | Compare against official format |

### JWT Authentication Issues

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| 401 on all requests | JWKS unreachable | Check network policy, test curl from pod |
| 403 after valid token | Issuer mismatch | Verify `iss` claim matches `issuer` config |
| Claims not in headers | claimToHeaders config | Check claim names match token structure |
| Policy not applied | Wrong targetRef | Verify namespace and resource name |

### Tracing Issues

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| No spans in collector | Backend unreachable | Check service name/port |
| Low trace volume | Sampling rate | Increase `samplingRate` for testing |
| Missing custom tags | Environment variable | Verify pod has `ENVOY_POD_NAME` |

### Debug Commands

```bash
# Check EnvoyProxy configuration
kubectl get envoyproxy envoy -n network -o yaml

# Check SecurityPolicy status
kubectl describe securitypolicy -n network

# View Envoy proxy logs
kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-internal -c envoy --tail=100

# Test JWKS endpoint accessibility
kubectl run curl-test --rm -it --image=curlimages/curl -- \
  curl -v https://auth.example.com/realms/myrealm/protocol/openid-connect/certs

# Check Envoy admin interface (port-forward for debugging)
kubectl port-forward -n network svc/envoy-internal 19000:19000
# Then visit http://localhost:19000/config_dump
```

---

## References

### Project Documentation
- [Application Docs: kube-prometheus-stack](../APPLICATIONS.md#kube-prometheus-stack) - **Primary** - kube-prometheus-stack + Loki + Grafana platform
- [Envoy Gateway Examples Analysis](../research/archive/completed/envoy-gateway-examples-analysis.md) - Source research document
- [k8s-at-home Patterns Implementation](./archived/k8s-at-home-patterns-implementation.md) - General k8s-at-home patterns
- [Bootstrap CRDs](../../templates/config/bootstrap/helmfile.d/00-crds.yaml.j2) - kube-prometheus-stack CRD installation

### External Documentation
- [Proxy Access Logs](https://gateway.envoyproxy.io/docs/tasks/observability/proxy-accesslog/) - Official docs
- [SecurityPolicy Reference](https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/) - JWT/OIDC patterns
- [Observability Tracing](https://gateway.envoyproxy.io/docs/tasks/observability/proxy-trace/) - Tracing setup
- [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/) - Version compatibility

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-03 | **IMPLEMENTED**: Phase 1 JSON Access Logging in `envoy.yaml.j2` |
| 2026-01-03 | **IMPLEMENTED**: Phase 2 JWT SecurityPolicy template (`securitypolicy-jwt.yaml.j2`) |
| 2026-01-03 | **IMPLEMENTED**: Phase 3 Distributed Tracing (conditional on `tracing_enabled`) |
| 2026-01-03 | **IMPLEMENTED**: CUE schema validation for all new variables |
| 2026-01-03 | **IMPLEMENTED**: cluster.sample.yaml with OIDC/JWT configuration section |
| 2026-01-03 | Added v1.6 Access Log Types (Route/Listener) documentation to Phase 1 |
| 2026-01-03 | Added fractional sampling (`samplingFraction`) for sub-1% trace rates |
| 2026-01-03 | Added Datadog as optional third tracing provider (requires subscription) |
| 2026-01-03 | Added tracing provider comparison table (Zipkin/OpenTelemetry/Datadog) |
| 2026-01-03 | Updated Phase 3 tracing: Now uses Tempo directly or via Alloy (no longer "future enhancement") |
| 2026-01-03 | Updated cross-references to unified observability-stack-implementation.md |
| 2026-01-03 | Added Loki/Alloy integration notes for JSON access logging |
| 2026-01-03 | Clarified kube-prometheus-stack CRD-only installation and linked to monitoring stack options |
| 2026-01-03 | Initial implementation guide created from research findings |
