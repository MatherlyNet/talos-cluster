# Archived Guides

> **Archived:** 2026-01-03 (network guides), 2026-01-05 (VictoriaMetrics guide)
> **Reason:** Superseded by kube-prometheus-stack implementation

## Why These Were Archived

The guides in this directory represent historical implementation approaches that have been superseded.

### VictoriaMetrics to kube-prometheus-stack Migration (2026-01-05)

The cluster migrated from VictoriaMetrics to **kube-prometheus-stack** on January 5, 2026. See:

- **Migration Report:** `local_docs/archive/victoria_metrics/MIGRATION_REPORT.md`
- **Current Implementation:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/`

Key reasons for migration:

- Better community support and dashboard compatibility
- Native Prometheus ecosystem integration
- Simplified Grafana 12 feature configuration
- Standard tooling for Talos Linux scraping

### Network Observability Fragmentation (2026-01-03)

The network-specific guides were archived because they represented a fragmented approach that has been unified into the main monitoring stack.

## Archived Files

| File | Original Purpose | Archived |
| ------ | ------------------ | ---------- |
| `observability-stack-implementation-victoriametrics.md` | VictoriaMetrics + Loki + Grafana unified platform | 2026-01-05 |
| `k8s-at-home-patterns-implementation.md` | k8s-at-home patterns with VictoriaMetrics option | 2026-01-05 |
| `k8s-at-home-remaining-implementation.md` | Remaining k8s-at-home features to implement | 2026-01-05 |
| `network-observability-implementation.md` | Network-specific observability (Hubble, CoreDNS, Envoy) | 2026-01-03 |
| `network-observability-checklist.md` | Checklist version of implementation guide | 2026-01-03 |
| `network-observability-diagram.md` | Architecture diagrams for network observability | 2026-01-03 |
| `network-observability-summary.md` | Quick reference/executive summary | 2026-01-03 |

## Current Implementation

The monitoring stack is now implemented using **kube-prometheus-stack**:

```yaml
# cluster.yaml
monitoring_enabled: true
monitoring_stack: "prometheus"  # kube-prometheus-stack
```

See:

- **Application docs:** `docs/APPLICATIONS.md#kube-prometheus-stack`
- **Template location:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/`

## Historical Reference

These files are preserved for historical reference only. Do not use them for new implementations.
