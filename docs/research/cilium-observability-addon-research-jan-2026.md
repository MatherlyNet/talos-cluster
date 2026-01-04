# Cilium Prometheus/Grafana Addon Research Report

> **Date:** 2026-01-03
> **Status:** ✅ Implementation Complete
> **Completed:** 2026-01-03
> **Reference:** [cilium/cilium/examples/kubernetes/addons/prometheus](https://github.com/cilium/cilium/tree/v1.19.0-pre.3/examples/kubernetes/addons/prometheus)

## Executive Summary

After comprehensive analysis of the official Cilium Prometheus/Grafana addon examples and comparison with our current VictoriaMetrics-based observability stack, I've identified several valuable improvements we can adopt. Our current implementation is **well-aligned** with best practices, but there are **specific enhancements** for Cilium/Hubble observability that would improve network visibility.

### Key Findings

| Category | Current State | Recommendation | Priority |
| ---------- | -------------- | ---------------- | ---------- |
| **Cilium Agent Dashboard** | **BUG: Using 16612 (Operator)** | Fix to 16611 (Agent) | **P0** |
| **Hubble Dashboards** | Using Grafana.com ID 16613 (v1.12) | OK - add native dashboards for redundancy | P2 |
| **Cilium Operator Dashboard** | Incorrectly labeled as "Agent" (16612) | Rename label to "cilium-operator" | **P0** |
| **Network Policy Verdicts** | Missing | Add dashboard ID 18015 | P1 |
| **Cilium Network Monitoring** | Missing | Add dashboard ID 24056 | P1 |
| **Hubble Metrics Configuration** | Good (6 metrics) | Add `port-distribution`, `policy` | P2 |
| **OpenMetrics/Exemplars** | Enabled | Add trace context labels | P2 |
| **Cilium Dashboard ConfigMaps** | `dashboards.enabled: true` | Already correct | OK |

> **CRITICAL FINDING**: Our current templates have a **dashboard ID mismatch**. The entry labeled `cilium-agent` is using gnetId 16612, which is actually the **Cilium Operator** dashboard. The correct Cilium Agent dashboard is **16611**.

---

## Detailed Analysis

### 1. Official Cilium Dashboards vs Grafana.com Dashboards

#### What Cilium Provides Natively

When `dashboards.enabled: true` is set in the Cilium Helm chart (which we have), Cilium automatically creates ConfigMaps with the **official, up-to-date dashboards**:

| ConfigMap | Dashboard | Description |
| ----------- | ----------- | ------------- |
| `grafana-cilium-dashboard` | Cilium Agent | 39 panels: BPF operations, API latency, forwarding stats, errors/warnings |
| `grafana-cilium-operator-dashboard` | Cilium Operator | IPAM management, EC2 API interactions, node inventory |
| `grafana-hubble-dashboard` | Hubble | 26 panels: flows, drops, DNS, HTTP, TCP, ICMP, network policies |

#### Our Current Grafana.com Dashboards

| Dashboard Label | gnetId | Actual Dashboard | Issue |
| ----------------- | -------- | ------------------ | ------- |
| `cilium-agent` | 16612 | **Cilium v1.12 OPERATOR** | **BUG: Wrong dashboard!** Should be 16611 |
| `cilium-hubble` | 16613 | Cilium v1.12 Hubble | Correct, but outdated for newer Cilium |

**Critical Bug:** Our templates incorrectly use gnetId 16612 labeled as "cilium-agent", but 16612 is the **Cilium Operator** dashboard, not the Agent dashboard. The correct Cilium Agent dashboard is **16611**.

**Additional Issue:** The Grafana.com dashboards (16611, 16612, 16613) are designed for Cilium v1.12, while we're running a newer version. The native Helm-deployed dashboards are always version-matched.

### 2. Dashboard Corrections & Missing Dashboards

#### P0: Fix Cilium Agent Dashboard (BUG)

**Current (WRONG):**
```yaml
cilium-agent:
  gnetId: 16612  # This is OPERATOR, not Agent!
```

**Corrected:**
```yaml
cilium-agent:
  gnetId: 16611  # Correct Agent dashboard
  revision: 1
  datasource: VictoriaMetrics
cilium-operator:
  gnetId: 16612  # Rename existing entry
  revision: 1
  datasource: VictoriaMetrics
```

#### Cilium Operator Dashboard (Already in templates, just mislabeled)

The dashboard at gnetId 16612 (which we already have, just mislabeled) tracks:
- CPU/memory usage of operator pods
- IPAM IP address allocation by type
- EC2 API interactions (if using AWS)
- Number of nodes managed
- Interface creation operations
- Metadata resync operations

**Impact:** The operator dashboard exists but is mislabeled as "cilium-agent". Need to rename and add correct agent dashboard.

#### Network Policy Verdicts Dashboard (ID 18015)

This dashboard uses `hubble_policy_verdicts_total` to show:
- Policy enforcement decisions (allow/deny)
- Source/destination workload context
- Namespace-level policy visibility

**Impact:** Essential for security monitoring and network policy auditing.

### 3. Hubble Metrics Configuration Gap

#### Current Configuration (from `cilium/app/helmrelease.yaml.j2`)
```yaml
hubble:
  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - icmp
      - http
```

#### Recommended Addition
```yaml
hubble:
  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - icmp
      - http
      - port-distribution  # NEW: Enables port distribution tracking
      - httpV2:exemplars=true;labelsContext=source_namespace,source_workload,destination_namespace,destination_workload  # NEW: L7 with trace context
```

**Why `port-distribution`?**
- Enables the "Top 10 Port Distribution" panel in the Hubble dashboard
- Helps identify unusual port usage patterns (security visibility)

**Why `httpV2` with exemplars?**
- Links HTTP metrics to distributed traces (Tempo integration)
- Adds workload context labels for better filtering
- Required for the L7 observability demonstrated in the [Isovalent demo](https://github.com/isovalent/cilium-grafana-observability-demo)

### 4. Dashboard Loading Strategy

There are two approaches to loading Cilium dashboards:

| Approach | Source | Pros | Cons |
| ---------- | -------- | ------ | ------ |
| **Helm-native ConfigMaps** | Cilium chart creates them | Always version-matched, auto-updated | Requires Grafana sidecar discovery |
| **Grafana.com imports** | Our current approach | Simple, declarative | May drift from Cilium version |

**Recommendation:** Use a hybrid approach:
1. Keep `dashboards.enabled: true` in Cilium (creates ConfigMaps)
2. Configure Grafana sidecar to discover these ConfigMaps
3. Remove duplicate Grafana.com dashboard imports
4. Keep Grafana.com dashboards only for things Cilium doesn't provide (e.g., Network Monitoring 24056)

### 5. Grafana Sidecar Configuration

To auto-discover Cilium's dashboard ConfigMaps, Grafana needs the sidecar enabled:

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard  # Cilium ConfigMaps use this label
      labelValue: "1"
      searchNamespace: ALL  # Or specify kube-system
      folderAnnotation: grafana_folder
```

---

## Recommendations

### P0 - Critical Bug Fix (Immediate)

#### 1. Fix Dashboard ID Mismatch

The entry labeled `cilium-agent` is incorrectly using gnetId 16612 (Operator dashboard). Must fix:

**In `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2`:**
```yaml
dashboards:
  network:
    # Cilium - CORRECTED IDs
    cilium-agent:
      gnetId: 16611   # CHANGED from 16612 - Agent dashboard
      revision: 1
      datasource: VictoriaMetrics
    cilium-operator:  # NEW - relabel existing 16612
      gnetId: 16612
      revision: 1
      datasource: VictoriaMetrics
    cilium-hubble:
      gnetId: 16613
      revision: 1
      datasource: VictoriaMetrics
```

**Same fix needed in `kube-prometheus-stack/app/helmrelease.yaml.j2`**

### P1 - High Priority (Immediate Value)

#### 2. Add Network Policy Verdicts Dashboard

Add to the Grafana dashboard configuration:

```yaml
dashboards:
  network:
    # ... existing ...
    cilium-policy-verdicts:
      gnetId: 18015
      revision: 1
      datasource: VictoriaMetrics
```

#### 3. Add Cilium Network Monitoring Dashboard (ID 24056)

This modern dashboard provides:
- Endpoint state monitoring
- BPF map capacity tracking
- Node connectivity status
- Bootstrap time tracking

```yaml
dashboards:
  network:
    cilium-network-monitoring:
      gnetId: 24056
      revision: 1
      datasource: VictoriaMetrics
```

#### 4. Enable Grafana Sidecar for Auto-Discovery

Configure Grafana to auto-discover Cilium-generated ConfigMaps:

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
      provider:
        foldersFromFilesStructure: true
```

### P2 - Medium Priority (Enhanced Visibility)

#### 5. Expand Hubble Metrics Configuration

Update the Cilium HelmRelease Hubble metrics:

```yaml
hubble:
  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - icmp
      - http
      - port-distribution
      - policy:sourceContext=workload-name|reserved-identity;destinationContext=workload-name|reserved-identity
    enableOpenMetrics: true
```

The `policy` metric is required for the Network Policy Verdicts dashboard.

#### 5. Add Cilium Operator Dashboard

```yaml
dashboards:
  network:
    cilium-operator:
      gnetId: 16612  # Note: This ID may need verification
      revision: 1
      datasource: VictoriaMetrics
```

Or rely on the Helm-native dashboard via sidecar discovery.

### P3 - Future Enhancement

#### 6. Integrate L7 Observability with Tempo

If tracing is enabled (`tracing_enabled: true`), update Hubble to export exemplars:

```yaml
hubble:
  metrics:
    enabled:
      - httpV2:exemplars=true;labelsContext=source_namespace,source_workload,destination_namespace,destination_workload
```

This enables linking from Hubble HTTP metrics directly to traces in Tempo.

---

## Implementation Checklist

### P0 - Critical Bug Fix (Do First) ✅ COMPLETE

- [x] **FIX BUG**: Change `cilium-agent` gnetId from 16612 → 16611 in `victoria-metrics/app/helmrelease.yaml.j2`
- [x] **FIX BUG**: Change `cilium-agent` gnetId from 16612 → 16611 in `kube-prometheus-stack/app/helmrelease.yaml.j2`
- [x] **ADD**: `cilium-operator` entry with gnetId 16612 (the existing entry, properly labeled)

### P1 - Immediate Actions ✅ COMPLETE

- [x] Add `cilium-policy-verdicts` dashboard (gnetId: 18015)
- [x] Add `cilium-network-monitoring` dashboard (gnetId: 24056)
- [x] Enable Grafana sidecar for dashboard auto-discovery
- [x] Add `port-distribution` Hubble metric
- [x] Add `policy` Hubble metric (for policy verdicts dashboard)

### P2 - Follow-up Actions (Partial)

- [ ] Verify Cilium-generated ConfigMaps are discovered by Grafana *(requires live cluster testing)*
- [ ] Evaluate removing duplicate Grafana.com imports if native dashboards are better *(future consideration)*
- [x] Add `httpV2:exemplars=true` if Tempo tracing is enabled *(implemented 2026-01-04)*
- [x] Document new dashboards in observability guide
- [x] Update observability-stack-implementation.md with correct dashboard IDs

---

## Implementation Summary

**Completed:** 2026-01-03

### Files Modified

| File | Changes |
| ------ | --------- |
| `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2` | Fixed dashboard IDs, added missing dashboards, enabled Grafana sidecar |
| `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app/helmrelease.yaml.j2` | Same dashboard fixes and sidecar configuration |
| `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2` | Added `port-distribution` and `policy` Hubble metrics, enabled OpenMetrics |
| `docs/guides/observability-stack-implementation.md` | Updated dashboard table with correct IDs |

### Dashboards Now Configured

| Dashboard | gnetId | Purpose |
| ----------- | -------- | --------- |
| `cilium-agent` | 16611 | Agent-level BPF, API latency, forwarding stats |
| `cilium-operator` | 16612 | IPAM, node management, operator metrics |
| `cilium-hubble` | 16613 | Network flows, drops, DNS, HTTP, TCP |
| `cilium-policy-verdicts` | 18015 | Network policy enforcement tracking |
| `cilium-network-monitoring` | 24056 | Endpoints, BPF maps, connectivity status |

### Hubble Metrics Enabled

```yaml
hubble:
  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - icmp
      - http
      - port-distribution        # NEW
      - policy:sourceContext=... # NEW
    enableOpenMetrics: true      # NEW
```

### Remaining Work (P2)

1. **Live cluster verification** of Cilium ConfigMap auto-discovery by Grafana sidecar
2. **Evaluate** removing Grafana.com dashboard imports if native Cilium dashboards prove sufficient

### Completed on 2026-01-04

- ✅ Added `httpV2:exemplars=true` conditional on `tracing_enabled` for Tempo trace linking

---

## References

### Official Cilium Resources
- [Cilium Prometheus Examples](https://github.com/cilium/cilium/tree/main/examples/kubernetes/addons/prometheus)
- [Cilium Dashboard JSON](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/cilium-agent/dashboards/cilium-dashboard.json)
- [Hubble Dashboard JSON](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/hubble/dashboards/hubble-dashboard.json)
- [Cilium Metrics Documentation](https://docs.cilium.io/en/stable/observability/metrics/)
- [Cilium Grafana Guide](https://docs.cilium.io/en/stable/observability/grafana/)

### Grafana Labs Dashboards
- [Cilium v1.12 Agent (16612)](https://grafana.com/grafana/dashboards/16612-cilium-agent/)
- [Cilium v1.12 Hubble (16613)](https://grafana.com/grafana/dashboards/16613-hubble/)
- [Cilium Policy Verdicts (18015)](https://grafana.com/grafana/dashboards/18015-cilium-policy-verdicts/)
- [Cilium Network Monitoring (24056)](https://grafana.com/grafana/dashboards/24056-cilium-network-monitoring/)
- [Cilium Metrics (21431)](https://grafana.com/grafana/dashboards/21431-cilium-metrics/)

### Additional Resources
- [Isovalent Cilium Grafana Observability Demo](https://github.com/isovalent/cilium-grafana-observability-demo)
- [Cilium Dashboard Feature Request (GitHub #20354)](https://github.com/cilium/cilium/issues/20354)

---

## Appendix: Metric Reference

### Cilium Agent Metrics (39 panels)

| Metric | Description |
| -------- | ------------- |
| `cilium_errors_warnings_total` | Error and warning counts |
| `cilium_process_cpu_seconds_total` | CPU usage |
| `cilium_process_resident_memory_bytes` | Memory usage |
| `cilium_bpf_maps_virtual_memory_max_bytes` | BPF memory usage |
| `cilium_bpf_map_pressure` | BPF map pressure |
| `cilium_agent_api_process_time_seconds_*` | API latency |
| `cilium_bpf_syscall_duration_seconds_*` | BPF syscall latency |
| `cilium_forward_count_total` | Forwarded packets |
| `cilium_forward_bytes_total` | Forwarded bytes |

### Hubble Metrics (26 panels)

| Metric | Description |
| -------- | ------------- |
| `hubble_flows_processed_total` | Total flows processed |
| `hubble_drop_total` | Dropped packets by reason |
| `hubble_tcp_flags_total` | TCP flag distribution |
| `hubble_icmp_total` | ICMP messages |
| `hubble_port_distribution_total` | Port usage distribution |
| `hubble_http_requests_total` | HTTP requests (L7) |
| `hubble_http_responses_total` | HTTP responses (L7) |
| `hubble_http_request_duration_seconds_bucket` | HTTP latency histograms |
| `hubble_dns_queries_total` | DNS queries |
| `hubble_dns_responses_total` | DNS responses |
| `hubble_policy_verdicts_total` | Network policy decisions |
