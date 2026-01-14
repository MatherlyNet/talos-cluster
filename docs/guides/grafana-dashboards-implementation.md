# Grafana Dashboards Implementation Guide

> **Created:** January 2026
> **Status:** IMPLEMENTED
> **Dependencies:** kube-prometheus-stack, Keycloak (optional), RustFS (optional)
> **Effort:** Low-Medium complexity

---

## Overview

This guide implements **conditional Grafana dashboards** for Keycloak and RustFS, utilizing the Grafana sidecar auto-discovery pattern already established in the project (used by CNPG).

### Dashboard Sources

| Component | Dashboard Source | Grafana.net ID | Notes |
| --------- | ---------------- | -------------- | ----- |
| **Keycloak Troubleshooting** | [keycloak-grafana-dashboard](https://github.com/keycloak/keycloak-grafana-dashboard) | N/A (GitHub) | SLO metrics, JVM, HTTP, Cluster |
| **Keycloak Capacity Planning** | [keycloak-grafana-dashboard](https://github.com/keycloak/keycloak-grafana-dashboard) | N/A (GitHub) | Event metrics, password validations |
| **RustFS/MinIO** | [MinIO Dashboard v3](https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3) | N/A (GitHub) | Storage, S3 API, capacity metrics |
| **Loki Stack Monitoring** | [Grafana Labs](https://grafana.com/grafana/dashboards/14055-loki-stack-monitoring-promtail-loki/) | 14055 | Error metrics, resource usage vs limits |
| **CoreDNS** | kube-prometheus-stack built-in | N/A (built-in) | Keep existing - comprehensive coverage |

---

## Architecture Decision

### Dashboard Provisioning Options

| Option | Pros | Cons | Recommendation |
| ------ | ---- | ---- | -------------- |
| **ConfigMap Sidecar** | GitOps-managed, namespace-aware, folder organization | Large ConfigMaps for complex dashboards | **Production** |
| **Grafana `dashboards:` section** | Simple, built into HelmRelease | No conditional logic per dashboard | Custom dashboards only |
| **`gnetId` references** | Small config, auto-updated | Dashboards not in Grafana.net registry | Not available for Keycloak |

**Recommendation:** Use **ConfigMap-based provisioning** via the Grafana sidecar (matching the existing CNPG pattern) because:

1. **Conditional deployment** - Dashboard ConfigMaps can be conditionally generated via Jinja2
2. **Namespace isolation** - ConfigMaps deployed alongside their respective applications
3. **Folder organization** - `grafana_folder` annotation organizes dashboards logically
4. **Version control** - Dashboard JSON is tracked in Git alongside application templates
5. **Consistent pattern** - Matches existing CNPG dashboard implementation

---

## Prerequisites

### For Keycloak Dashboards

1. **Keycloak deployed** with `keycloak_enabled: true`
2. **Metrics enabled** in Keycloak CR (already configured: `metrics-enabled: "true"`)
3. **ServiceMonitor automatically created** by Keycloak Operator when metrics enabled
4. **kube-prometheus-stack deployed** with `monitoring_enabled: true`

> **Note:** The Keycloak Operator automatically creates a ServiceMonitor when `metrics-enabled: "true"` is set in the Keycloak CR. We do NOT need to create a separate ServiceMonitor template.

### For RustFS Dashboard

> **⚠️ IMPORTANT LIMITATION:** RustFS does **NOT** support Prometheus pull-based metrics like MinIO. It uses OpenTelemetry (OTLP) push mode instead. The dashboard ConfigMap is deployed but will not show data without additional OTEL collector configuration.
>
> **References:**
> - [GitHub Issue #1228](https://github.com/rustfs/rustfs/issues/1228) - Confirms OTLP-only metrics
> - [RustFS Observability Stack](https://github.com/rustfs/rustfs/tree/main/.docker/observability) - Reference configuration

1. **RustFS deployed** with `rustfs_enabled: true`
2. **OpenTelemetry Collector configured** to receive OTLP and export to Prometheus (NOT yet implemented)
3. **kube-prometheus-stack deployed** with `monitoring_enabled: true`

**Implementation Guide:** See [RustFS OTLP Metrics Integration via Alloy](../research/archive/completed/rustfs-otlp-metrics-alloy-integration-jan-2026.md) for the complete solution.

---

## Implementation

### Part 1: Keycloak Dashboards

#### Step 1.1: Keycloak ServiceMonitor (Operator-Managed)

> **Note:** The **Keycloak Operator automatically creates a ServiceMonitor** when `metrics-enabled: "true"` is set in the Keycloak CR's `additionalOptions`. We do NOT need to create a separate ServiceMonitor template.
>
> The operator-created ServiceMonitor:
> - Scrapes the management interface (port 9000)
> - Uses path `/metrics`
> - Has proper label selectors for Keycloak service

**No template required** - the ServiceMonitor is managed by the Keycloak Operator.

**Verify the operator-created ServiceMonitor:**
```bash
kubectl get servicemonitor -n identity keycloak -o yaml
```

#### Step 1.2: Create Keycloak Dashboard ConfigMaps

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/dashboard-troubleshooting.yaml.j2`

> **Note:** The dashboard JSON is large (~204KB). This template fetches the official dashboard and embeds it. For the actual implementation, download from:
> `https://raw.githubusercontent.com/keycloak/keycloak-grafana-dashboard/main/dashboards/keycloak-troubleshooting-dashboard.json`

```yaml
#% if keycloak_enabled | default(false) and monitoring_enabled | default(false) %#
---
#| ============================================================================= #|
#| KEYCLOAK TROUBLESHOOTING DASHBOARD                                            #|
#| ============================================================================= #|
#| Source: https://github.com/keycloak/keycloak-grafana-dashboard                #|
#| Version: Match keycloak_operator_version (26.5.0)                             #|
#| Metrics: SLO, JVM, Database, HTTP, Cluster                                    #|
#| ============================================================================= #|
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-troubleshooting-dashboard
  namespace: identity
  labels:
    grafana_dashboard: "1"
    app.kubernetes.io/name: keycloak
  annotations:
    grafana_folder: "Identity"
data:
  keycloak-troubleshooting.json: |
    #| INSERT DASHBOARD JSON HERE - Download from GitHub #|
    #| https://raw.githubusercontent.com/keycloak/keycloak-grafana-dashboard/main/dashboards/keycloak-troubleshooting-dashboard.json #|
#% endif %#
```

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/dashboard-capacity-planning.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and monitoring_enabled | default(false) %#
---
#| ============================================================================= #|
#| KEYCLOAK CAPACITY PLANNING DASHBOARD                                          #|
#| ============================================================================= #|
#| Source: https://github.com/keycloak/keycloak-grafana-dashboard                #|
#| Version: Match keycloak_operator_version (26.5.0)                             #|
#| Metrics: Event metrics (requires event listeners enabled in Keycloak)         #|
#| ============================================================================= #|
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-capacity-planning-dashboard
  namespace: identity
  labels:
    grafana_dashboard: "1"
    app.kubernetes.io/name: keycloak
  annotations:
    grafana_folder: "Identity"
data:
  keycloak-capacity-planning.json: |
    #| INSERT DASHBOARD JSON HERE - Download from GitHub #|
    #| https://raw.githubusercontent.com/keycloak/keycloak-grafana-dashboard/main/dashboards/keycloak-capacity-planning-dashboard.json #|
#% endif %#
```

#### Step 1.3: Update Keycloak App Kustomization

**Edit:** `templates/config/kubernetes/apps/identity/keycloak/app/kustomization.yaml.j2`

Add the new resources:

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./secret.sops.yaml
#% if (keycloak_db_mode | default('embedded')) == 'embedded' %#
  - ./postgres-embedded.yaml
#% else %#
  - ./postgres-cnpg.yaml
#% endif %#
  - ./keycloak-cr.yaml
  - ./httproute.yaml
#% if monitoring_enabled | default(false) %#
  - ./servicemonitor.yaml
  - ./dashboard-troubleshooting.yaml
  - ./dashboard-capacity-planning.yaml
#% endif %#
#% endif %#
```

---

### Part 2: RustFS Dashboard

#### Step 2.1: RustFS Metrics (OTLP Push Mode)

> **⚠️ IMPORTANT:** Unlike MinIO, RustFS does **NOT** support Prometheus pull-based metrics via `/minio/v2/metrics/cluster`. RustFS uses OpenTelemetry (OTLP) push mode exclusively.
>
> **Current Status:** The RustFS dashboard ConfigMap is deployed but will show no data until an OTEL collector is configured to:
> 1. Receive OTLP metrics from RustFS (ports 4317 gRPC / 4318 HTTP)
> 2. Export to Prometheus via a Prometheus exporter (typically port 8889)
>
> **Reference:** [RustFS OTEL Collector Config](https://raw.githubusercontent.com/rustfs/rustfs/main/.docker/observability/otel-collector-config.yaml)

**ServiceMonitor Removed:** The original ServiceMonitor template has been removed since RustFS doesn't support Prometheus scraping.

#### Step 2.2: Create RustFS Dashboard ConfigMap

**File:** `templates/config/kubernetes/apps/storage/rustfs/app/dashboard-storage.yaml.j2`

> **Note:** RustFS does not have an official Grafana dashboard yet. Since RustFS is MinIO-compatible, we can adapt the MinIO dashboard. The community maintains a v3 metrics dashboard at:
> `https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3`

```yaml
#% if rustfs_enabled | default(false) and monitoring_enabled | default(false) %#
---
#| ============================================================================= #|
#| RUSTFS STORAGE DASHBOARD                                                       #|
#| ============================================================================= #|
#| Based on: MinIO Dashboard (adapted for RustFS S3-compatible metrics)           #|
#| Source: https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3 #|
#| Metrics: Storage capacity, S3 API, I/O, connections                            #|
#| NOTE: RustFS uses MinIO-compatible metrics API at /minio/v2/metrics/cluster    #|
#| ============================================================================= #|
apiVersion: v1
kind: ConfigMap
metadata:
  name: rustfs-storage-dashboard
  namespace: storage
  labels:
    grafana_dashboard: "1"
    app.kubernetes.io/name: rustfs
  annotations:
    grafana_folder: "Storage"
data:
  rustfs-storage.json: |
    #| INSERT DASHBOARD JSON HERE - Download and adapt from MinIO dashboard #|
    #| https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3 #|
    #| Modifications needed: #|
    #|   1. Update title to "RustFS Storage" #|
    #|   2. Change uid to "rustfs-storage" #|
    #|   3. Update job selector to match RustFS ServiceMonitor job name #|
#% endif %#
```

#### Step 2.3: Update RustFS App Kustomization

**Edit:** `templates/config/kubernetes/apps/storage/rustfs/app/kustomization.yaml.j2`

Add the dashboard resource:

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
  - ./secret.sops.yaml
  - ./httproute-console.yaml
#% if monitoring_enabled | default(false) %#
  - ./servicemonitor.yaml
  - ./dashboard-storage.yaml
#% endif %#
#% endif %#
```

---

### Part 3: Loki Stack Monitoring Dashboard

#### Assessment: Why Add This Dashboard?

The Loki Helm chart already provides built-in dashboards via `monitoring.dashboards.enabled: true` (currently configured). However, dashboard **14055** provides **complementary operational monitoring**:

| Built-in Loki Dashboards | Dashboard 14055 |
| ------------------------ | --------------- |
| Loki internals (ingester, querier, distributor) | Error metrics from Promtail/Loki |
| Query performance | Resource usage vs K8s limits/requests |
| Storage backend metrics | Warning/error logs correlation |

**Recommendation:** ADD as supplemental dashboard - provides operational visibility not covered by built-in dashboards.

#### Step 3.1: Create Loki Stack Monitoring Dashboard ConfigMap

**File:** `templates/config/kubernetes/apps/monitoring/loki/app/dashboard-stack-monitoring.yaml.j2`

> **Note:** This dashboard is from Grafana Labs (official) and available via gnetId. Can use either ConfigMap or gnetId reference.

**Option A: Using gnetId (Recommended - auto-updates)**

Add to kube-prometheus-stack HelmRelease `dashboards:` section:

```yaml
#% if loki_enabled | default(false) %#
      dashboards:
        loki-stack:
          gnetId: 14055
          revision: 1
          datasource: Prometheus
#% endif %#
```

**Option B: Using ConfigMap (GitOps-managed)**

```yaml
#% if loki_enabled | default(false) and monitoring_enabled | default(false) %#
---
#| ============================================================================= #|
#| LOKI STACK MONITORING DASHBOARD                                                #|
#| ============================================================================= #|
#| Source: https://grafana.com/grafana/dashboards/14055                           #|
#| Author: Grafana Labs (official)                                                #|
#| Metrics: Promtail/Loki errors, resource usage vs K8s limits                    #|
#| ============================================================================= #|
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-stack-monitoring-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
    app.kubernetes.io/name: loki
  annotations:
    grafana_folder: "Logging"
data:
  loki-stack-monitoring.json: |
    #| Download from: https://grafana.com/api/dashboards/14055/revisions/1/download #|
    #| INSERT DASHBOARD JSON HERE #|
#% endif %#
```

#### Step 3.2: Download Loki Stack Monitoring Dashboard

```bash
# Download from Grafana.com API
curl -sL "https://grafana.com/api/dashboards/14055/revisions/1/download" \
  -o /tmp/loki-stack-monitoring.json

# Verify download
cat /tmp/loki-stack-monitoring.json | jq '.title'
# Expected: "Loki stack monitoring (Promtail, Loki)"
```

---

### Part 4: CoreDNS Dashboard Assessment

#### Current State

kube-prometheus-stack **already includes** a comprehensive CoreDNS dashboard with 10 panels:

| Panel | Metrics |
| ----- | ------- |
| Requests (total) | `coredns_dns_requests_total` by protocol (UDP/TCP) |
| Requests (by qtype) | Query type distribution |
| Requests (by zone) | Zone-based metrics |
| Requests (DO bit) | DNSSEC enablement tracking |
| Requests (size, UDP/TCP) | p50, p90, p99 percentiles |
| Responses (by rcode) | Response codes breakdown |
| Responses (duration) | Latency percentiles |
| Cache (size) | Cache entries by type |
| Cache (hitrate) | Hit/miss rate |

#### Dashboard 14981 Comparison

| Aspect | Built-in (kube-prometheus-stack) | Dashboard 14981 |
| ------ | -------------------------------- | --------------- |
| **Author** | prometheus-community | Grafana Labs |
| **Last Updated** | Continuously maintained with chart | September 2021 |
| **CoreDNS Version** | 1.7.0+ compatible | 1.7.0+ compatible |
| **Panels** | 10 comprehensive panels | Similar panel set |
| **Multi-cluster** | Yes (cluster variable) | Yes |
| **Customization** | Chart-managed | Requires manual updates |

#### Recommendation: NO CHANGE

**Keep the built-in kube-prometheus-stack CoreDNS dashboard** because:

1. **Same functionality** - Both dashboards cover identical metrics
2. **Maintained upstream** - Built-in dashboard is updated with chart releases
3. **Already deployed** - No additional ConfigMap needed
4. **Folder organization** - Already in "Monitoring" folder via `grafana_folder` annotation

> **Note:** If specific CoreDNS insights are missing, consider [dotdc's modern dashboard](https://grafana.com/grafana/dashboards/15762-kubernetes-system-coredns/) which uses latest Grafana features.

---

## Keycloak Metrics Requirements

### Metrics Exposed by Keycloak

Keycloak 26.5.0 exposes metrics via Micrometer when `metrics-enabled: "true"`:

| Metric Category | Example Metrics | Dashboard |
| --------------- | --------------- | --------- |
| **SLO/Availability** | `up{container="keycloak"}` | Troubleshooting |
| **HTTP Requests** | `http_server_requests_seconds_*` | Troubleshooting |
| **JVM Memory** | `jvm_memory_used_bytes`, `jvm_memory_committed_bytes` | Troubleshooting |
| **JVM GC** | `jvm_gc_pause_seconds_*`, `jvm_gc_overhead` | Troubleshooting |
| **Database Pools** | `agroal_active_count`, `agroal_available_count` | Troubleshooting |
| **Cluster** | `vendor_cluster_size`, `vendor_jgroups_stats_*` | Troubleshooting |
| **User Events** | `keycloak_user_events_total` | Capacity Planning |
| **Password Hashing** | `keycloak_credentials_password_hashing_validations_total` | Capacity Planning |

### Enabling HTTP Latency Histograms

For detailed latency percentile panels, enable histograms in the Keycloak CR:

```yaml
additionalOptions:
  - name: http-metrics-histograms-enabled
    value: "true"
```

### Enabling Event Metrics

For the Capacity Planning dashboard, event metrics must be enabled. This is done by configuring event listeners in the realm (Admin Console or KeycloakRealmImport).

### Keycloak 26.5.0 Observability Updates (January 2026)

Keycloak 26.5.0 introduced significant observability enhancements:

| Feature | Status | Description |
| ------- | ------ | ----------- |
| **OpenTelemetry Logs** | Preview | Export logs to OTLP collectors for centralized management |
| **OpenTelemetry Metrics** | Experimental | Micrometer-to-OTLP bridge for unified metrics |
| **Custom OTLP Headers** | Supported | `tracing-header-<name>` for auth tokens |
| **MDC Logging** | Supported | Contextual data (realm, client, user, IP) in logs |

> **Note:** If using `tracing_enabled: true` and `keycloak_tracing_enabled: true` in cluster.yaml, Keycloak will export traces to Tempo. The Grafana dashboards can then correlate traces with metrics.

---

## RustFS Metrics Requirements

> **⚠️ IMPORTANT:** RustFS does **NOT** expose MinIO-compatible metrics at `/minio/v2/metrics/cluster`. Unlike MinIO, RustFS uses OpenTelemetry (OTLP) push mode exclusively.

### RustFS Metrics Architecture

```
RustFS App → OTLP (4317/4318) → OTEL Collector → Prometheus Exporter (8889) → Prometheus scrapes
```

**Reference:** [RustFS Observability Stack](https://github.com/rustfs/rustfs/tree/main/.docker/observability)

### Required Configuration for RustFS Metrics

To enable RustFS metrics in Prometheus, you need:

1. **Deploy an OpenTelemetry Collector** with:
   - OTLP receivers on ports 4317 (gRPC) and 4318 (HTTP)
   - Prometheus exporter on port 8889

2. **Configure RustFS environment variables:**
   ```yaml
   RUSTFS_OBS_METRIC_ENDPOINT: "http://otel-collector:4318/v1/metrics"
   OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: "http://otel-collector:4318/v1/metrics"
   ```

3. **Add Prometheus scrape config** or ServiceMonitor for `otel-collector:8889`

### Current Status (IMPLEMENTED - PENDING VERIFICATION)

The RustFS OTLP metrics integration has been implemented:
- ✅ Alloy extended with OTLP metrics receiver and Prometheus pipeline
- ✅ RustFS configured with `RUSTFS_OBS_METRIC_ENDPOINT` environment variable
- ⏳ Pending: `task configure -y` to render templates
- ⏳ Pending: Cluster deployment and verification

**Implementation Details:** See [RustFS OTLP Metrics Integration via Alloy](../research/archive/completed/rustfs-otlp-metrics-alloy-integration-jan-2026.md) for the complete solution.

### Current RustFS Metrics Available

Per [GitHub Discussion #601](https://github.com/orgs/rustfs/discussions/601), RustFS currently exports basic metrics via OpenTelemetry:
- cpu usage, cpu util percent, io read, io write
- memory usage, virtual memory, network io
- process status, request body len, request total

Additional metrics (disk bytes total, disk usage, buckets num, objects num) are being considered.

---

## Dashboard JSON Download Instructions

### Keycloak Dashboards

```bash
# Download troubleshooting dashboard
curl -sL https://raw.githubusercontent.com/keycloak/keycloak-grafana-dashboard/main/dashboards/keycloak-troubleshooting-dashboard.json \
  -o /tmp/keycloak-troubleshooting.json

# Download capacity planning dashboard
curl -sL https://raw.githubusercontent.com/keycloak/keycloak-grafana-dashboard/main/dashboards/keycloak-capacity-planning-dashboard.json \
  -o /tmp/keycloak-capacity-planning.json

# Verify downloads
ls -la /tmp/keycloak-*.json
```

### MinIO/RustFS Dashboard

```bash
# Clone the v3 metrics dashboard repo
git clone https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3 /tmp/minio-dashboard

# The dashboard JSON is in the repo root or needs to be exported from Grafana
```

---

## Template Variable Adjustments

### Keycloak Dashboards

The official Keycloak dashboards use these template variables:

```json
"templating": {
  "list": [
    {
      "name": "namespace",
      "type": "query",
      "query": "label_values(up{job=~\".*keycloak.*\"}, namespace)"
    },
    {
      "name": "realm",
      "type": "query",
      "query": "label_values(keycloak_user_events_total, realm)"
    }
  ]
}
```

These should work with the ServiceMonitor configuration.

### RustFS Dashboard

Update the MinIO dashboard's job selector:

```json
"templating": {
  "list": [
    {
      "name": "scrape_jobs",
      "type": "query",
      "query": "label_values(minio_cluster_health_status, job)",
      "current": {
        "text": "storage/rustfs",
        "value": "storage/rustfs"
      }
    }
  ]
}
```

---

## Verification

### After Deployment

```bash
# Verify ServiceMonitors are created
kubectl get servicemonitor -A | grep -E "keycloak|rustfs"

# Verify ConfigMaps are created
kubectl get configmap -A -l grafana_dashboard=1

# Check Grafana sidecar logs for dashboard discovery
kubectl -n monitoring logs -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard

# Verify dashboards appear in Grafana
# 1. Open Grafana UI
# 2. Navigate to Dashboards
# 3. Look for "Identity" folder (Keycloak) and "Storage" folder (RustFS)
```

### Verify Metrics Are Being Scraped

```bash
# Check Prometheus targets
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Open http://localhost:9090/targets
# Look for keycloak and rustfs targets

# Query test metrics
# Keycloak: up{job="identity/keycloak"}
# RustFS: minio_cluster_health_status{job="storage/rustfs"}
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| Dashboard not appearing | ConfigMap not labeled | Verify `grafana_dashboard: "1"` label |
| Dashboard in wrong folder | Missing annotation | Add `grafana_folder` annotation |
| No metrics in panels | ServiceMonitor not scraping | Check Prometheus targets, verify endpoints |
| Keycloak metrics empty | Metrics not enabled | Verify `metrics-enabled: "true"` in Keycloak CR |
| Keycloak ServiceMonitor missing | Operator doesn't create it | Ensure Keycloak CR has `metrics-enabled: "true"` in additionalOptions |
| RustFS metrics empty | **RustFS uses OTLP push, not Prometheus pull** | Deploy OTEL Collector and configure RustFS env vars (see RustFS Metrics Requirements) |
| Template variables empty | Job label mismatch | Update dashboard queries to match ServiceMonitor job name |

---

## Security Considerations

### Dashboard Access

- Dashboards are read-only by default (Grafana `viewers_can_edit: false`)
- No sensitive data in dashboards (metrics are aggregated)
- Dashboard JSON is stored in ConfigMaps (visible via kubectl)

### Metrics Exposure

- Keycloak metrics do NOT include PII
- RustFS metrics do NOT include object content/keys
- Both expose operational metrics only

---

## Future Enhancements

### RustFS Official Dashboard

Monitor [GitHub Discussion #601](https://github.com/orgs/rustfs/discussions/601) for:
- Official RustFS Grafana dashboard
- Additional metrics (disk usage, bucket/object counts)

### Keycloak Event Dashboard

Consider creating a custom dashboard for:
- Failed login attempts by IP
- User registration trends
- Token refresh patterns
- Admin API usage

---

## References

### Keycloak
- [Keycloak Metrics Documentation](https://www.keycloak.org/observability/metrics)
- [Keycloak Grafana Dashboards](https://www.keycloak.org/observability/grafana-dashboards)
- [keycloak-grafana-dashboard Repository](https://github.com/keycloak/keycloak-grafana-dashboard)

### RustFS
- [RustFS Logging Documentation](https://docs.rustfs.com/features/logging/)
- [RustFS GitHub Discussions](https://github.com/orgs/rustfs/discussions/601)
- [RustFS Observability Stack](https://github.com/rustfs/rustfs/tree/main/.docker/observability)

### MinIO (RustFS-compatible)
- [MinIO Dashboard v3](https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3)
- [MinIO Grafana Integration](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/integrations/integration-reference/integration-minio/)

### Loki
- [Loki Stack Monitoring Dashboard (14055)](https://grafana.com/grafana/dashboards/14055-loki-stack-monitoring-promtail-loki/)
- [Loki Helm Chart Monitoring](https://grafana.com/docs/loki/latest/setup/install/helm/monitor-and-alert/)
- [Loki Mixin Dashboards](https://grafana.com/docs/loki/latest/operations/meta-monitoring/mixins/)

### CoreDNS
- [kube-prometheus-stack CoreDNS Dashboard](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/templates/grafana/dashboards-1.14/k8s-coredns.yaml)
- [dotdc Modern CoreDNS Dashboard (15762)](https://grafana.com/grafana/dashboards/15762-kubernetes-system-coredns/)
- [CoreDNS Metrics Plugin](https://coredns.io/plugins/metrics/)

### Project Documentation
- [Keycloak Implementation Guide](./completed/keycloak-implementation.md) - Keycloak deployment and tracing configuration
- [CNPG Implementation Guide](./completed/cnpg-implementation.md) - Dashboard ConfigMap pattern reference
- [Envoy Gateway Observability](./envoy-gateway-observability-security.md) - Gateway metrics integration

---

## Known Issues and Caveats

### Keycloak Dashboard Version Compatibility

| Keycloak Version | Dashboard Version | Notes |
| ---------------- | ----------------- | ----- |
| 26.1 - 26.2 | Tag `26.2.0` | Use specific tag |
| 26.3+ | Branch `main` | Latest dashboards |
| 26.5.0 (current) | Tag `26.4.0` | Latest release as of January 2026 |

> **Note:** The dashboard repository release (26.4.0) lags behind Keycloak releases (26.5.0). The dashboards should still be compatible as metrics APIs are stable.

### RustFS Dashboard Limitations

1. **No official dashboard** - RustFS team is considering community requests (GitHub Discussion #601)
2. **MinIO dashboard adaptation** - May require metric name adjustments if RustFS diverges from MinIO API
3. **Limited metrics** - Current RustFS metrics are basic; advanced storage metrics pending implementation

### Large ConfigMap Sizes

The Keycloak troubleshooting dashboard JSON is ~204KB, which:
- Exceeds typical ConfigMap "best practice" of <1MB (still well within limits)
- May cause slow Git operations if many changes
- Alternative: Use `gnetId` references when dashboards are published to Grafana.net

---

## Configuration

### cluster.yaml Variables

Enable dashboards by setting the following in `cluster.yaml`:

```yaml
# Global monitoring (required for all dashboards)
monitoring_enabled: true

# Component-specific monitoring flags
keycloak_monitoring_enabled: true   # Keycloak ServiceMonitor + dashboards
rustfs_monitoring_enabled: true     # RustFS ServiceMonitor + dashboard
loki_monitoring_enabled: true       # Loki stack monitoring dashboard
```

### Derived Variables (plugin.py)

The following are computed automatically:
- `keycloak_monitoring_enabled` - true when `monitoring_enabled` AND `keycloak_monitoring_enabled` both true
- `rustfs_monitoring_enabled` - true when `monitoring_enabled` AND `rustfs_monitoring_enabled` both true
- `loki_monitoring_enabled` - true when `monitoring_enabled` AND `loki_monitoring_enabled` both true

---

## Deployment Checklist

Before deploying:

- [x] `monitoring_enabled: true` in cluster.yaml
- [x] kube-prometheus-stack deployed and healthy
- [x] Grafana sidecar configured with `label: grafana_dashboard`
- [x] For Keycloak: `keycloak_enabled: true` and `keycloak_monitoring_enabled: true`
- [x] For RustFS: `rustfs_enabled: true` and `rustfs_monitoring_enabled: true`
- [x] For Loki: `loki_enabled: true` and `loki_monitoring_enabled: true`

After deploying:

- [ ] Run `task configure -y` to generate templates
- [ ] Run `task reconcile` or wait for Flux reconciliation
- [ ] Verify ConfigMaps created: `kubectl get cm -A -l grafana_dashboard=1`
- [ ] Check ServiceMonitors: `kubectl get servicemonitor -A`
- [ ] Verify Prometheus targets: port-forward to Prometheus UI
- [ ] Confirm dashboards in Grafana: Check "Identity", "Storage", and "Logging" folders

---

## Files Created

| File | Description |
| ---- | ----------- |
| `templates/config/kubernetes/apps/identity/keycloak/app/servicemonitor.yaml.j2` | ~~Keycloak metrics scraping~~ **REMOVED** - Operator creates automatically |
| `templates/config/kubernetes/apps/identity/keycloak/app/dashboard-troubleshooting.yaml.j2` | Keycloak SLO/JVM/HTTP dashboard (~6.6K lines) |
| `templates/config/kubernetes/apps/identity/keycloak/app/dashboard-capacity-planning.yaml.j2` | Keycloak events dashboard (~887 lines) |
| `templates/config/kubernetes/apps/storage/rustfs/app/servicemonitor.yaml.j2` | ~~RustFS metrics scraping~~ **REMOVED** - RustFS uses OTLP push |
| `templates/config/kubernetes/apps/storage/rustfs/app/dashboard-storage.yaml.j2` | RustFS/MinIO storage dashboard (~3.6K lines) - **No data until OTEL configured** |
| `templates/config/kubernetes/apps/monitoring/loki/app/dashboard-stack-monitoring.yaml.j2` | Loki stack monitoring (~2.4K lines) |

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-07 | **IMPLEMENTED** - RustFS OTLP metrics via Alloy (Alloy HelmRelease + RustFS env var) |
| 2026-01-07 | **UPDATED** - Removed Keycloak ServiceMonitor from kustomization (operator creates automatically) |
| 2026-01-07 | **UPDATED** - Removed RustFS ServiceMonitor (RustFS uses OTLP push, not Prometheus pull) |
| 2026-01-07 | **RESEARCHED** - RustFS OTLP metrics via Alloy integration documented (see research doc) |
| 2026-01-07 | **IMPLEMENTED** - All dashboard templates created with embedded JSON |
| 2026-01-07 | Added `*_monitoring_enabled` derived variables to plugin.py |
| 2026-01-07 | Updated kustomization files with conditional resource inclusion |
| 2026-01-07 | Added Loki Stack Monitoring dashboard (14055) - supplemental operational monitoring |
| 2026-01-07 | Assessed CoreDNS dashboard (14981) - NO CHANGE recommended, keep built-in |
| 2026-01-07 | Added Keycloak 26.5.0 observability updates |
| 2026-01-07 | Fixed Keycloak ServiceMonitor port (9000 management, not 8080 http) |
| 2026-01-07 | Initial research and implementation guide created |
