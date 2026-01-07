# RustFS OTLP Metrics Integration via Alloy

> **Research Date:** January 2026
> **Status:** IMPLEMENTED - PENDING VERIFICATION
> **Dependencies:** Alloy (deployed), kube-prometheus-stack (deployed), RustFS (deployed)
> **Effort:** Low complexity (extend existing Alloy configuration)

---

## Problem Statement

RustFS does **NOT** support Prometheus pull-based metrics like MinIO. It exclusively uses OpenTelemetry (OTLP) push mode for metrics export. The current RustFS dashboard shows no data because:

1. RustFS is not configured to send OTLP metrics
2. No OTLP receiver is exposed to accept RustFS metrics
3. No pipeline exists to convert OTLP metrics to Prometheus format

**References:**
- [GitHub Issue #1228](https://github.com/rustfs/rustfs/issues/1228) - Confirms OTLP-only metrics
- [GitHub Issue #796](https://github.com/rustfs/rustfs/issues/796) - Community request for Prometheus metrics
- [RustFS Observability Stack](https://github.com/rustfs/rustfs/tree/main/.docker/observability)

---

## Architecture Overview

### Current State (Not Working)

```
RustFS Pod → (no metrics export configured) → Dashboard shows no data
```

### Target State

```
RustFS Pod → OTLP HTTP (4318) → Alloy (otelcol.receiver.otlp)
                                    ↓
                              otelcol.processor.batch
                                    ↓
                              otelcol.exporter.prometheus (OTLP → Prometheus format)
                                    ↓
                              prometheus.remote_write → Prometheus → Dashboard
```

### Why Alloy (vs. Dedicated OTEL Collector)

| Option | Pros | Cons |
| ------ | ---- | ---- |
| **Extend Alloy** | Already deployed, unified telemetry, follows patterns | Minimal |
| **Dedicated OTEL Collector** | Isolated | Additional deployment, maintenance overhead |

**Recommendation:** Extend Alloy - it's Grafana's OpenTelemetry Collector distribution and already handles traces.

---

## Research Findings

### 1. RustFS Environment Variables

RustFS exports metrics via OpenTelemetry using these environment variables:

| Variable | Purpose | Example Value |
| -------- | ------- | ------------- |
| `RUSTFS_OBS_METRIC_ENDPOINT` | OTLP metrics endpoint (RustFS-specific) | `http://alloy.monitoring.svc:4318/v1/metrics` |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Standard OTEL SDK variable | Same as above |

**Source:** [GitHub Issue #1228](https://github.com/rustfs/rustfs/issues/1228)

### 2. Current Alloy Configuration

The existing Alloy HelmRelease (`templates/config/kubernetes/apps/monitoring/alloy/app/helmrelease.yaml.j2`) already has:

- **OTLP receivers** configured (ports 4317 gRPC, 4318 HTTP)
- **Traces pipeline** to Tempo
- **Logs pipeline** to Loki

However:
- **Service only exposes port 12345** (metrics endpoint), not OTLP ports
- **No metrics output** from OTLP receiver (only traces)

```alloy
// Current config - traces only
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces = [otelcol.processor.batch.default.input]  // No metrics!
  }
}
```

### 3. Prometheus Remote Write

The kube-prometheus-stack has `enableRemoteWriteReceiver: true`, meaning Prometheus accepts remote writes at:

```
http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/write
```

### 4. Alloy Service Port Configuration

The Alloy Helm chart supports `alloy.extraPorts` for exposing additional ports:

```yaml
alloy:
  extraPorts:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP
```

**Source:** [Grafana Alloy Helm Chart](https://github.com/grafana/alloy/blob/main/operations/helm/charts/alloy/values.yaml)

### 5. RustFS Metrics Available

Per [GitHub Discussion #601](https://github.com/orgs/rustfs/discussions/601), RustFS exports:

| Category | Metrics |
| -------- | ------- |
| **Process** | CPU usage, CPU util percent, memory usage, virtual memory |
| **I/O** | IO read, IO write, network I/O |
| **HTTP** | Request body length, request total, response times |
| **Status** | Process status |

**Note:** Storage capacity metrics (disk bytes total, bucket/object counts) are planned but not yet implemented.

---

## Implementation Plan

### Phase 1: Extend Alloy Configuration

**File:** `templates/config/kubernetes/apps/monitoring/alloy/app/helmrelease.yaml.j2`

#### 1.1 Add OTLP Port Exposure

Add `extraPorts` when tracing OR rustfs_monitoring is enabled:

```yaml
#% if tracing_enabled | default(false) or rustfs_monitoring_enabled | default(false) %#
    # Service for receiving OTLP telemetry
    service:
      enabled: true
    alloy:
      extraPorts:
        - name: otlp-grpc
          port: 4317
          targetPort: 4317
          protocol: TCP
        - name: otlp-http
          port: 4318
          targetPort: 4318
          protocol: TCP
#% endif %#
```

#### 1.2 Add Metrics Pipeline to Alloy Config

Extend the OTLP receiver output and add metrics processing:

```alloy
// Receive OTLP telemetry (traces + metrics)
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
#% if tracing_enabled | default(false) %#
    traces = [otelcol.processor.batch.traces.input]
#% endif %#
#% if rustfs_monitoring_enabled | default(false) %#
    metrics = [otelcol.processor.batch.metrics.input]
#% endif %#
  }
}

#% if tracing_enabled | default(false) %#
// Batch processor for traces
otelcol.processor.batch "traces" {
  output {
    traces = [otelcol.exporter.otlp.tempo.input]
  }
}

// Export traces to Tempo
otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "tempo:4317"
    tls { insecure = true }
  }
}
#% endif %#

#% if rustfs_monitoring_enabled | default(false) %#
// Batch processor for metrics
otelcol.processor.batch "metrics" {
  output {
    metrics = [otelcol.exporter.prometheus.default.input]
  }
}

// Convert OTLP metrics to Prometheus format
otelcol.exporter.prometheus "default" {
  forward_to = [prometheus.remote_write.default.receiver]
}

// Export metrics to Prometheus via remote write
prometheus.remote_write "default" {
  endpoint {
    url = "http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/write"
  }
}
#% endif %#
```

### Phase 2: Configure RustFS OTLP Export

**File:** `templates/config/kubernetes/apps/storage/rustfs/app/helmrelease.yaml.j2`

Add OTLP environment variable when monitoring is enabled:

```yaml
    #| Environment variables #|
    environment:
      RUSTFS_BUFFER_PROFILE: "#{ rustfs_buffer_profile | default('DataAnalytics') }#"
      RUSTFS_ENABLE_SCANNER: "true"
      RUSTFS_ENABLE_HEAL: "true"
      RUSTFS_CONSOLE_ENABLE: "true"
#% if rustfs_monitoring_enabled | default(false) %#
      #| OTLP metrics export to Alloy - RustFS uses push-mode OpenTelemetry #|
      #| REF: https://github.com/rustfs/rustfs/issues/1228 #|
      RUSTFS_OBS_METRIC_ENDPOINT: "http://alloy.monitoring.svc:4318/v1/metrics"
#% endif %#
```

### Phase 3: Update Documentation

Update `docs/guides/grafana-dashboards-implementation.md`:
- Mark RustFS metrics as "IMPLEMENTED"
- Document the Alloy-based OTLP pipeline
- Update troubleshooting section

---

## Verification Steps

After implementation:

### 1. Verify Alloy Service Ports

```bash
kubectl get svc -n monitoring alloy -o yaml | grep -A 20 "ports:"
# Should show ports 4317, 4318, and 12345
```

### 2. Verify RustFS Environment Variables

```bash
kubectl get pods -n storage -l app.kubernetes.io/name=rustfs -o jsonpath='{.items[0].spec.containers[0].env}' | jq .
# Should include RUSTFS_OBS_METRIC_ENDPOINT
```

### 3. Check Alloy Logs for Metrics Reception

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy -f | grep -i metrics
```

### 4. Query Prometheus for RustFS Metrics

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090
# Query: {job="rustfs"} or search for metrics starting with "rustfs_"
```

### 5. Verify Dashboard Data

Open Grafana → Storage folder → RustFS Storage dashboard
- Panels should now display metrics

---

## Fallback: Direct Prometheus OTLP Receiver

If the Alloy approach proves problematic, Prometheus 2.47+ supports native OTLP ingestion:

**Prometheus Configuration:**
```yaml
prometheus:
  prometheusSpec:
    # Enable OTLP receiver
    enableFeatures:
      - otlp-write-receiver
```

**RustFS Environment:**
```yaml
RUSTFS_OBS_METRIC_ENDPOINT: "http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/otlp/v1/metrics"
```

**Note:** This requires Prometheus to be restarted with `--web.enable-otlp-receiver` flag.

---

## Security Considerations

### Network Policy Impact

If `network_policies_enabled: true`, ensure:
- RustFS pods can reach Alloy service (storage → monitoring namespace)
- Alloy pods can reach Prometheus service (same namespace)

### Credential-Free Pipeline

The OTLP pipeline uses cluster-internal HTTP:
- No authentication required (internal cluster traffic)
- No TLS required (internal cluster traffic)
- Network policies provide access control

---

## Estimated Effort

| Task | Effort |
| ---- | ------ |
| Update Alloy HelmRelease template | 30 minutes |
| Update RustFS HelmRelease template | 10 minutes |
| Testing and verification | 20 minutes |
| Documentation updates | 15 minutes |
| **Total** | ~1.5 hours |

---

## Files to Modify

| File | Changes |
| ---- | ------- |
| `templates/config/kubernetes/apps/monitoring/alloy/app/helmrelease.yaml.j2` | Add extraPorts, metrics pipeline |
| `templates/config/kubernetes/apps/storage/rustfs/app/helmrelease.yaml.j2` | Add RUSTFS_OBS_METRIC_ENDPOINT |
| `docs/guides/grafana-dashboards-implementation.md` | Update status, document solution |

---

## References

### RustFS
- [RustFS Issue #1228](https://github.com/rustfs/rustfs/issues/1228) - OTLP metrics confirmation
- [RustFS Issue #796](https://github.com/rustfs/rustfs/issues/796) - Prometheus metrics request
- [RustFS Discussion #601](https://github.com/orgs/rustfs/discussions/601) - Available metrics
- [RustFS Observability Stack](https://github.com/rustfs/rustfs/tree/main/.docker/observability)

### Alloy
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [otelcol.receiver.otlp](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.receiver.otlp/)
- [prometheus.remote_write](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.remote_write/)
- [Alloy Helm Chart](https://github.com/grafana/alloy/blob/main/operations/helm/charts/alloy/values.yaml)

### Prometheus
- [Prometheus OTLP Guide](https://prometheus.io/docs/guides/opentelemetry/)
- [Remote Write Receiver](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write)

### OpenTelemetry
- [OTLP Exporter Configuration](https://opentelemetry.io/docs/languages/sdk-configuration/otlp-exporter/)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-07 | Initial research document created |
| 2026-01-07 | Confirmed Alloy-based approach as recommended solution |
| 2026-01-07 | Documented implementation plan with code examples |
| 2026-01-07 | **VALIDATED** - Fixed syntax error: added `otelcol.exporter.prometheus` between batch processor and remote_write |
| 2026-01-07 | **VALIDATED** - Confirmed Alloy 1.5.1 compatibility with all required components |
| 2026-01-07 | **VALIDATED** - Implementation plan follows project conventions (delimiters, patterns) |
| 2026-01-07 | **IMPLEMENTED** - Updated Alloy HelmRelease with OTLP receiver, metrics pipeline, extraPorts |
| 2026-01-07 | **IMPLEMENTED** - Updated RustFS HelmRelease with RUSTFS_OBS_METRIC_ENDPOINT env var |
| 2026-01-07 | **FIXED** - Corrected YAML structure (extraPorts inside alloy: block, not duplicate key) |
