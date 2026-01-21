# Network Observability Summary

> **Quick Reference** for [network-observability-implementation.md](./network-observability-implementation.md)

## Executive Summary

Comprehensive network observability for your Talos/Cilium/Envoy Gateway infrastructure cluster. Focuses on **infrastructure health monitoring** rather than application-level metrics.

---

## Quick Start (Recommended Order)

### Phase 1: Enable Hubble (Highest Priority)

**Impact:** Network flow visibility at L3/L4/DNS level

```yaml
# Edit: templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2
hubble:
  enabled: true
  metrics:
    enabled:
      - dns:query;ignoreAAAA    # DNS queries
      - drop                     # Network policy drops
      - tcp                      # TCP connections
      - flow                     # Network flows
    serviceMonitor:
      enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
```

**Why:** Hubble provides critical visibility into network policy enforcement, DNS failures, and pod-to-pod communication patterns.

---

### Phase 2: CoreDNS Monitoring

**Impact:** DNS resolution health tracking

```yaml
# Create: templates/config/kubernetes/apps/kube-system/coredns/app/servicemonitor.yaml.j2
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: coredns
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-dns
  endpoints:
    - port: metrics
      interval: 30s
```

**Why:** DNS is critical path for all services. Monitor NXDOMAIN rate, cache hits, and query latency.

---

### Phase 3: Enhance Envoy Metrics

**Impact:** Gateway-level RED metrics (Rate, Errors, Duration)

```yaml
# Edit: templates/config/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml.j2
# Add relabelings for gateway name and namespace labels
relabelings:
  - sourceLabels: [__meta_kubernetes_pod_label_gateway_envoyproxy_io_owning_gateway_name]
    targetLabel: gateway
```

**Why:** Track ingress/egress gateway performance, error rates, and backend health.

---

## Critical Infrastructure Alerts

### Severity Levels

| Severity | Response Time | Notification | Example |
| -------- | ------------- | ------------ | ------- |
| **Critical** | Immediate (page) | PagerDuty/Phone | CoreDNS all pods down |
| **Warning** | 15 minutes | Slack/Email | Envoy error rate >5% |
| **Info** | Next business day | Ticket | DNS cache hit <50% |

### Top 7 Infrastructure Alerts

1. **CiliumAgentDown** (Critical)
   - **Condition:** No Cilium agents running
   - **Impact:** Pod networking broken
   - **Threshold:** Absent for 2m

2. **CoreDNSTotalOutage** (Critical)
   - **Condition:** All CoreDNS pods down
   - **Impact:** DNS resolution fails
   - **Threshold:** All pods down for 1m

3. **EnvoyGatewayDown** (Critical)
   - **Condition:** No Envoy proxies reachable
   - **Impact:** Ingress/egress traffic broken
   - **Threshold:** Absent for 2m

4. **CoreDNSHighErrorRate** (Warning)
   - **Condition:** >5% NXDOMAIN or SERVFAIL
   - **Impact:** Service discovery degraded
   - **Threshold:** >5% for 5m

5. **EnvoyGatewayHighErrorRate** (Warning)
   - **Condition:** >5% HTTP 5xx responses
   - **Impact:** Application errors visible to users
   - **Threshold:** >5% for 5m

6. **EnvoyBackendUnhealthy** (Critical)
   - **Condition:** <50% healthy backends
   - **Impact:** Reduced capacity or service down
   - **Threshold:** <50% for 2m

7. **CiliumBGPPeerDown** (Critical, if BGP enabled)
   - **Condition:** BGP peering with gateway failed
   - **Impact:** LoadBalancer IPs unreachable from other VLANs
   - **Threshold:** Peer down for 2m

---

## Key Metrics to Watch

### Cilium + Hubble

| Metric | Type | Alert Threshold |
| ------ | ---- | --------------- |
| `hubble_drop_total{reason="POLICY_DENIED"}` | Counter | >10 drops/sec for 10m |
| `cilium_loadbalancer_backend_errors_total` | Counter | >1 error/sec for 5m |
| `cilium_agent_api_process_time_seconds` | Histogram | P95 >1s |

### Envoy Gateway

| Metric | Type | Alert Threshold |
| ------ | ---- | --------------- |
| `envoy_http_downstream_rq_5xx` / `_total` | Ratio | >5% for 5m |
| `envoy_http_downstream_rq_time_bucket` | Histogram | P95 >1000ms for 10m |
| `envoy_cluster_membership_healthy` / `_total` | Ratio | <50% for 2m |

### CoreDNS

| Metric | Type | Alert Threshold |
| ------ | ---- | --------------- |
| `coredns_dns_responses_total{rcode="NXDOMAIN"}` / `_total` | Ratio | >5% for 5m |
| `coredns_cache_hits_total` / (`_hits` + `_misses`) | Ratio | <50% for 30m (info) |
| `coredns_dns_request_duration_seconds` | Histogram | P95 >500ms |

---

## Grafana Dashboards (Recommended)

### Official Dashboards

| Dashboard | Grafana ID | Priority | Purpose |
| --------- | ---------- | -------- | ------- |
| **Cilium Agent** | 16612 | P0 | eBPF metrics, endpoint health |
| **Hubble Network Overview** | 16613 | P0 | L3/L4/L7 flow visualization |
| **Hubble DNS** | 16614 | P0 | DNS query patterns |
| **CoreDNS** | 5926 | P1 | DNS performance, cache hits |
| **Envoy Global** | 11021 | P1 | Gateway-level stats |
| **Envoy Clusters** | 11022 | P2 | Backend health details |

### Custom Dashboard Panels

Create a single **Infrastructure Network Health** dashboard with:

1. **Status Row**
   - Cilium agent count (up/down)
   - CoreDNS pod count (up/down)
   - Envoy gateway count (up/down)
   - BGP peer status (if enabled)

2. **Traffic Row**
   - Request rate (Envoy)
   - DNS query rate (CoreDNS)
   - Network flow rate (Hubble)

3. **Errors Row**
   - HTTP 5xx rate (Envoy)
   - DNS NXDOMAIN rate (CoreDNS)
   - Network policy drops (Hubble)

4. **Latency Row**
   - Envoy P50/P95/P99
   - CoreDNS P95
   - TCP connection time

5. **Backend Health Row**
   - Envoy cluster health ratio
   - LoadBalancer backend count
   - Service endpoint availability

---

## Recording Rules (Performance Optimization)

### Top 6 Recording Rules

```yaml
# 1. Envoy request rate
- record: envoy:gateway:request_rate
  expr: sum by (gateway) (rate(envoy_http_downstream_rq_total[5m]))

# 2. Envoy error rate
- record: envoy:gateway:error_rate
  expr: |
    sum by (gateway) (rate(envoy_http_downstream_rq_5xx[5m])) /
    sum by (gateway) (rate(envoy_http_downstream_rq_total[5m]))

# 3. Envoy P95 latency
- record: envoy:gateway:latency_p95
  expr: histogram_quantile(0.95, sum by (gateway, le) (rate(envoy_http_downstream_rq_time_bucket[5m])))

# 4. CoreDNS error rate
- record: coredns:error_rate
  expr: |
    sum(rate(coredns_dns_responses_total{rcode=~"NXDOMAIN|SERVFAIL"}[5m])) /
    sum(rate(coredns_dns_responses_total[5m]))

# 5. CoreDNS cache hit rate
- record: coredns:cache_hit_rate
  expr: |
    sum(rate(coredns_cache_hits_total[5m])) /
    (sum(rate(coredns_cache_hits_total[5m])) + sum(rate(coredns_cache_misses_total[5m])))

# 6. Envoy backend health ratio
- record: envoy:cluster:health_ratio
  expr: |
    sum by (cluster) (envoy_cluster_membership_healthy) /
    sum by (cluster) (envoy_cluster_membership_total)
```

---

## BGP Monitoring (Special Case)

### Current Limitation

**Cilium does NOT expose native BGP metrics to Prometheus** as of January 2026.

### Workaround: Log-Based + CLI

1. **Enable BGP debug logging:**

   ```yaml
   # cilium helmrelease.yaml.j2
   debug:
     enabled: true
     verbose: "bgp-control-plane"
   ```

2. **Manual verification:**

   ```bash
   kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers
   ```

3. **Log-based alert (requires Loki):**

   ```yaml
   - alert: CiliumBGPPeerDown
     expr: count_over_time({app="cilium"} |~ "BGP.*peer.*down" [5m]) > 0
   ```

4. **External monitoring:** Deploy FRR exporter on UniFi gateway (advanced).

---

## Resource Overhead

### Hubble Components

| Component | CPU | Memory | Notes |
| --------- | --- | ------ | ----- |
| Hubble Relay | 10-20m | 50-100Mi | Per replica (1 recommended) |
| Hubble UI | 5-10m | 30-50Mi | Per replica (1 recommended) |
| Hubble metrics | 1-2m/node | 10-20Mi/node | In Cilium agent |

**Total:** ~30-50m CPU, ~100-200Mi memory for 3-node cluster.

### Prometheus Storage

- **Additional time series:** ~1000-2000 (3-node cluster)
- **Storage estimate:** ~1-2 GB/month (15d retention)

---

## Deployment Checklist

### Prerequisites

- [ ] kube-prometheus-stack CRDs installed (`kubectl get crd prometheusrules.monitoring.coreos.com`)
- [ ] Prometheus deployed and scraping
- [ ] Grafana deployed (optional but recommended)

### Phase 1: Hubble

- [ ] Update Cilium HelmRelease with Hubble config
- [ ] Run `task configure && task reconcile`
- [ ] Verify: `kubectl get pods -n kube-system -l k8s-app=hubble-relay`
- [ ] Verify metrics: Port-forward and check `http://localhost:4245/metrics`

### Phase 2: CoreDNS

- [ ] Create ServiceMonitor for CoreDNS
- [ ] Update kustomization.yaml.j2
- [ ] Run `task configure && task reconcile`
- [ ] Verify: `kubectl get servicemonitor -n kube-system coredns`

### Phase 3: Envoy

- [ ] Update PodMonitor with relabelings
- [ ] Run `task configure && task reconcile`
- [ ] Verify: `kubectl get podmonitor -n network envoy-proxy -o yaml`

### Phase 4: PrometheusRules

- [ ] Create rules-network.yaml.j2 with alerts
- [ ] Run `task configure && task reconcile`
- [ ] Verify: `kubectl get prometheusrule -n monitoring network-infrastructure`
- [ ] Check Prometheus UI: Status → Rules

### Phase 5: Grafana Dashboards

- [ ] Download dashboard JSONs from Grafana.com
- [ ] Create ConfigMaps with `grafana_dashboard: "1"` label
- [ ] Apply to cluster
- [ ] Verify dashboards appear in Grafana UI

---

## Quick Troubleshooting

### No Hubble flows visible

```bash
# Check Hubble Relay
kubectl get pods -n kube-system -l k8s-app=hubble-relay
kubectl logs -n kube-system deployment/hubble-relay

# Test locally
kubectl port-forward -n kube-system svc/hubble-relay 4245:80
hubble status
hubble observe
```

### Envoy metrics not in Prometheus

```bash
# Check PodMonitor
kubectl get podmonitor -n network envoy-proxy -o yaml

# Test metrics endpoint
kubectl exec -n network <envoy-pod> -- wget -qO- localhost:19001/stats/prometheus | head
```

### CoreDNS metrics missing

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n kube-system coredns -o yaml

# Test metrics endpoint
kubectl exec -n kube-system <coredns-pod> -- wget -qO- localhost:9153/metrics | head
```

### BGP peer not establishing

```bash
# Check Cilium logs
kubectl -n kube-system logs ds/cilium | grep -i bgp

# Check peer status
kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers

# Verify UniFi FRR config
# SSH to gateway: vtysh -c 'show bgp summary'
```

---

## Next Steps

1. **Deploy monitoring stack** (if not already deployed)
   - See [k8s-at-home-patterns-implementation.md](./k8s-at-home-patterns-implementation.md#phase-3-observability-stack)
   - Options: VictoriaMetrics or kube-prometheus-stack

2. **Enable Hubble** (Phase 1 - highest priority)
   - Immediate network flow visibility
   - Critical for debugging network policy issues

3. **Add ServiceMonitors** (Phases 2-3)
   - CoreDNS and Envoy metrics
   - Foundation for alerting

4. **Create PrometheusRules** (Phase 4)
   - Recording rules for performance
   - Alert rules for incidents

5. **Import Grafana Dashboards** (Phase 5)
   - Visualization for operators
   - Historical trend analysis

6. **Configure AlertmanagerConfig** (Phase 7)
   - Route critical alerts to PagerDuty
   - Warning alerts to Slack
   - Info alerts to ticketing system

---

## References

- **Full Implementation Guide:** [network-observability-implementation.md](./network-observability-implementation.md)
- **Cilium Networking:** [cilium-networking.md](../ai-context/cilium-networking.md)
- **Envoy Gateway Observability:** [envoy-gateway-observability-security.md](../envoy-gateway-observability-security.md)
- **k8s-at-home Patterns:** [k8s-at-home-patterns-implementation.md](./k8s-at-home-patterns-implementation.md)

---

## Key Takeaways

1. **Hubble is critical** - Network flow visibility is the highest priority for infrastructure monitoring
2. **DNS monitoring is non-negotiable** - DNS failures cascade to all services
3. **Gateway metrics matter** - Envoy is the front door; track RED metrics
4. **BGP needs manual monitoring** - No native Prometheus metrics; use logs and CLI
5. **Recording rules improve performance** - Pre-calculate common queries
6. **Alert on infrastructure, not application metrics** - Focus on CNI, DNS, and gateway health
7. **Grafana dashboards for visibility** - Use official dashboards + custom infrastructure overview
