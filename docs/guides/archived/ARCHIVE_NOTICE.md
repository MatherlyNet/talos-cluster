# Archived Guides

> **Archived:** 2026-01-03
> **Reason:** Superseded by unified observability stack implementation

## Why These Were Archived

The guides in this directory were created as a fragmented network-only observability approach. They have been superseded by the **unified, cohesive observability platform** documented in:

**`../observability-stack-implementation.md`**

The new guide provides:
- **Unified Stack**: VictoriaMetrics + Loki + Grafana as a single cohesive platform
- **Component Ownership**: Clear ownership matrix preventing duplicate deployments
- **Cohesion Verification**: Checklist to validate no overlapping technologies
- **Community Dashboards**: Curated list of Grafana dashboards (dotdc collection, etc.)
- **Complete Configuration**: Full HelmRelease templates ready for implementation

## Archived Files

| File | Original Purpose |
|------|------------------|
| `network-observability-implementation.md` | Network-specific observability (Hubble, CoreDNS, Envoy) |
| `network-observability-checklist.md` | Checklist version of implementation guide |
| `network-observability-diagram.md` | Architecture diagrams for network observability |
| `network-observability-summary.md` | Quick reference/executive summary |

## Key Differences

| Aspect | Old Approach | New Unified Approach |
|--------|-------------|---------------------|
| **Scope** | Network metrics only | Full cluster observability |
| **Grafana** | Assumed separate deployment | Deployed by VictoriaMetrics stack |
| **Logs** | Not addressed | Loki + Alloy integrated |
| **Dashboards** | Manual ConfigMaps | Grafana provisioner with gnetId |
| **Cohesion** | Not considered | Explicit ownership matrix |

## Migration

If you previously implemented the archived guides, migrate to the unified stack:

1. **Read:** `../observability-stack-implementation.md`
2. **Enable:** `monitoring_enabled: true` in `cluster.yaml`
3. **Verify:** Run the Cohesion Verification Checklist
4. **Remove:** Any standalone Grafana/Prometheus deployments

## Historical Reference

These files are preserved for historical reference only. Do not use them for new implementations.
