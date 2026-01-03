# Network Observability Implementation Guide

> **Created:** 2026-01-03
> **Status:** Ready for Implementation
> **Target:** Infrastructure Network Monitoring for Talos/Cilium/Envoy Gateway

## Overview

This guide provides comprehensive network observability for the infrastructure layer, ensuring visibility into CNI performance, gateway traffic, DNS resolution, and optional BGP peering. This is **infrastructure monitoring** - focused on network health rather than application-level metrics.

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    Network Observability Stack                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Cilium +     │  │ Envoy Gateway│  │   CoreDNS    │          │
│  │ Hubble       │  │   Metrics    │  │   Metrics    │          │
│  │              │  │              │  │              │          │
│  │ - Flow logs  │  │ - RED metrics│  │ - Query rate │          │
│  │ - L3/L4/L7   │  │ - Latency    │  │ - Errors     │          │
│  │ - Policies   │  │ - Endpoints  │  │ - Cache hits │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                  │
│         └──────────────────┼──────────────────┘                  │
│                            ▼                                     │
│                  ┌──────────────────┐                           │
│                  │   Prometheus      │                           │
│                  │  (via PodMonitor/ │                           │
│                  │  ServiceMonitor)  │                           │
│                  └─────────┬─────────┘                           │
│                            ▼                                     │
│                  ┌──────────────────┐                           │
│                  │     Grafana       │                           │
│                  │   (Dashboards)    │                           │
│                  └───────────────────┘                           │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Current State

| Component | Status | Metrics Enabled | Observability Gap |
| --------- | ------ | --------------- | ----------------- |
| **Cilium** | Deployed | ServiceMonitor enabled | Hubble disabled - no flow visibility |
| **Envoy Gateway** | Deployed | PodMonitor enabled | Basic metrics only |
| **CoreDNS** | Deployed | Prometheus plugin enabled | No ServiceMonitor |
| **BGP** | Optional | N/A | No metrics collection |

### Prerequisites

- **kube-prometheus-stack CRDs installed** (via bootstrap `00-crds.yaml.j2`)
- **Prometheus-compatible scraper** deployed (see [k8s-at-home-patterns-implementation.md](./k8s-at-home-patterns-implementation.md#phase-3-observability-stack))
  - Options: VictoriaMetrics, kube-prometheus-stack, Prometheus Operator
- **Grafana** for visualization (optional but recommended)
- **Hubble CLI** for network flow debugging (optional)

---

## Phase 1: Enable Cilium Hubble

### Purpose

Hubble provides network flow visibility at L3/L4/L7, showing:
- Pod-to-pod communication patterns
- Network policy drops
- DNS queries and responses
- HTTP/gRPC request flows
- Connection latency and errors

### Implementation

#### Step 1: Update Cilium HelmRelease

Edit `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`:

```yaml
values:
  # ... existing values ...

  hubble:
    enabled: true
    metrics:
      # Infrastructure-focused metrics (not full service mesh)
      enabled:
        - dns:query;ignoreAAAA                    # DNS queries (ignore AAAA for noise reduction)
        - drop                                     # Dropped packets
        - tcp                                      # TCP connections
        - flow                                     # Network flows
        - port-distribution                        # Service port usage
        - icmp                                     # ICMP traffic
      enableOpenMetrics: true
      serviceMonitor:
        enabled: true
        labels:
          prometheus: kube-prometheus  # Match your Prometheus selector
    relay:
      enabled: true
      replicas: 1
      prometheus:
        enabled: true
        serviceMonitor:
          enabled: true
          labels:
            prometheus: kube-prometheus
    ui:
      enabled: true
      replicas: 1
      ingress:
        enabled: false  # Use Gateway API instead (see Step 3)
```

#### Step 2: Apply Changes

```bash
# Regenerate templates
task configure

# Reconcile Flux
task reconcile

# Verify Hubble deployment
kubectl get pods -n kube-system -l k8s-app=hubble-relay
kubectl get pods -n kube-system -l k8s-app=hubble-ui

# Check ServiceMonitors
kubectl get servicemonitor -n kube-system -l app.kubernetes.io/name=cilium
```

#### Step 3: Expose Hubble UI (Optional)

Create `templates/config/kubernetes/apps/kube-system/cilium/app/httproute.yaml.j2`:

```yaml
#% if hubble_ui_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "hubble.#{ cloudflare_domain }#"
  rules:
    - backendRefs:
        - name: hubble-ui
          port: 80
#% endif %#
```

Update `kustomization.yaml.j2`:

```yaml
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./networks.yaml
  - ./secret.sops.yaml
#% if hubble_ui_enabled | default(false) %#
  - ./httproute.yaml
#% endif %#
```

Add to `cluster.yaml`:

```yaml
# =============================================================================
# OBSERVABILITY CONFIGURATION - Optional
# =============================================================================

# -- Enable Hubble UI via HTTPRoute
#    (OPTIONAL) / (DEFAULT: false)
# hubble_ui_enabled: true
```

#### Step 4: Install Hubble CLI (Optional)

For ad-hoc network flow debugging:

```bash
# Install Hubble CLI
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-darwin-amd64.tar.gz{,.sha256sum}
shasum -a 256 -c hubble-darwin-amd64.tar.gz.sha256sum
tar xzvf hubble-darwin-amd64.tar.gz
sudo mv hubble /usr/local/bin

# Port-forward Hubble Relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80

# Test CLI
hubble status
hubble observe
```

### Infrastructure Flow Visibility

**What flows matter for infrastructure monitoring:**

| Flow Type | Why Monitor | Alert Condition |
| --------- | ----------- | --------------- |
| **DNS queries** | DNS is critical path for all services | >5% NXDOMAIN or SERVFAIL |
| **Network policy drops** | Security posture validation | Unexpected drops from known good sources |
| **TCP connection failures** | Service reachability | >1% connection failures to core services |
| **LoadBalancer backend health** | Gateway availability | Backend pod unreachable |
| **Control plane communication** | K8s API health | Dropped packets to API server |

### Hubble Metrics Reference

```yaml
# Full list of available Hubble metrics:
hubble:
  metrics:
    enabled:
      # DNS
      - dns:query;ignoreAAAA                    # DNS queries (A/AAAA record split)
      - dns:query:destinationContext=pod-short  # DNS queries with pod context

      # L3/L4
      - drop                                     # Dropped packets (policy, error)
      - tcp                                      # TCP connections and errors
      - flow                                     # Network flows
      - icmp                                     # ICMP traffic
      - port-distribution                        # Service port usage

      # L7 (Service Mesh - not needed for infrastructure)
      # - httpV2:exemplars=true;labelsContext=source_ip,source_namespace,destination_service_name
      # - kafka

      # Policy
      - policy:sourceContext=app|workload-name|pod|reserved-identity
      - policy:destinationContext=app|workload-name|pod|dns|reserved-identity
```

**For infrastructure monitoring, stick to L3/L4/DNS metrics.** L7 metrics (HTTP, gRPC) are for service mesh use cases.

### Verification Checklist

- [ ] Hubble Relay pod running and healthy
- [ ] Hubble UI pod running (if enabled)
- [ ] ServiceMonitors created for Hubble metrics
- [ ] Prometheus scraping Hubble metrics (check `/metrics` endpoint)
- [ ] Grafana can query `hubble_*` metrics
- [ ] Hubble CLI can observe flows (if installed)

---

## Phase 2: Enhance Envoy Gateway Metrics

### Current State

Existing `PodMonitor` scrapes `/stats/prometheus` from Envoy proxies, but lacks configuration for:
- RED metrics (Rate, Errors, Duration)
- Histogram buckets for latency percentiles
- Labeled metrics for route/cluster identification

### Implementation

#### Step 1: Configure Envoy Metrics in EnvoyProxy

Edit `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2`:

```yaml
spec:
  telemetry:
    accessLog:
      # ... existing access log config from envoy-gateway-observability-security.md ...

    metrics:
      prometheus:
        compression:
          type: Gzip
      # Enable stats for infrastructure monitoring
      sinks:
        - type: OpenTelemetry  # Optional: for OpenTelemetry Collector integration
          openTelemetry:
            host: otel-collector.monitoring.svc.cluster.local
            port: 4317
      matches:
        # Listener stats (gateway-level)
        - type: Exact
          value: http.envoy_internal.downstream_cx_total
        - type: Exact
          value: http.envoy_internal.downstream_cx_active
        - type: Exact
          value: http.envoy_external.downstream_cx_total
        - type: Exact
          value: http.envoy_external.downstream_cx_active

        # Cluster stats (backend health)
        - type: Prefix
          value: cluster.

        # Route-level RED metrics
        - type: Prefix
          value: http.envoy_internal.
        - type: Prefix
          value: http.envoy_external.
```

#### Step 2: Update PodMonitor for Additional Endpoints

Edit `templates/config/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml.j2`:

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: envoy-proxy
  namespace: network
  labels:
    prometheus: kube-prometheus  # Match your Prometheus selector
spec:
  jobLabel: envoy-proxy
  namespaceSelector:
    matchNames:
      - network
  podMetricsEndpoints:
    # Prometheus metrics (main endpoint)
    - port: metrics
      path: /stats/prometheus
      interval: 30s
      honorLabels: true
      relabelings:
        # Add gateway name label
        - sourceLabels: [__meta_kubernetes_pod_label_gateway_envoyproxy_io_owning_gateway_name]
          targetLabel: gateway
        # Add namespace label
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
  selector:
    matchLabels:
      app.kubernetes.io/component: proxy
      app.kubernetes.io/name: envoy
```

### Critical Envoy Metrics

| Metric | Type | Purpose |
| ------ | ---- | ------- |
| `envoy_http_downstream_rq_total` | Counter | Request rate (RED: Rate) |
| `envoy_http_downstream_rq_xx` | Counter | HTTP status codes (RED: Errors) |
| `envoy_http_downstream_rq_time_bucket` | Histogram | Request latency (RED: Duration) |
| `envoy_cluster_upstream_cx_active` | Gauge | Active backend connections |
| `envoy_cluster_upstream_cx_connect_fail` | Counter | Backend connection failures |
| `envoy_cluster_membership_healthy` | Gauge | Healthy backend count |
| `envoy_cluster_membership_total` | Gauge | Total backend count |
| `envoy_listener_downstream_cx_total` | Counter | Gateway-level connections |
| `envoy_listener_downstream_cx_active` | Gauge | Active gateway connections |

### Prometheus Recording Rules

Create `templates/config/kubernetes/apps/monitoring/prometheus/app/rules-network.yaml.j2`:

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: network-infrastructure
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
spec:
  groups:
    - name: envoy_gateway_red
      interval: 30s
      rules:
        # Request Rate (requests/sec by gateway)
        - record: envoy:gateway:request_rate
          expr: |
            sum by (gateway, namespace) (
              rate(envoy_http_downstream_rq_total[5m])
            )

        # Error Rate (% of 5xx responses)
        - record: envoy:gateway:error_rate
          expr: |
            sum by (gateway, namespace) (
              rate(envoy_http_downstream_rq_5xx[5m])
            ) /
            sum by (gateway, namespace) (
              rate(envoy_http_downstream_rq_total[5m])
            )

        # P95 Latency (milliseconds)
        - record: envoy:gateway:latency_p95
          expr: |
            histogram_quantile(0.95,
              sum by (gateway, namespace, le) (
                rate(envoy_http_downstream_rq_time_bucket[5m])
              )
            )

        # Backend Health Ratio
        - record: envoy:cluster:health_ratio
          expr: |
            sum by (cluster, namespace) (
              envoy_cluster_membership_healthy
            ) /
            sum by (cluster, namespace) (
              envoy_cluster_membership_total
            )

    - name: envoy_gateway_alerts
      interval: 30s
      rules:
        # High error rate alert
        - alert: EnvoyGatewayHighErrorRate
          expr: envoy:gateway:error_rate > 0.05
          for: 5m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "High error rate on {{ $labels.gateway }}"
            description: "Gateway {{ $labels.gateway }} has {{ $value | humanizePercentage }} error rate"

        # Backend unhealthy
        - alert: EnvoyBackendUnhealthy
          expr: envoy:cluster:health_ratio < 0.5
          for: 2m
          labels:
            severity: critical
            component: network
          annotations:
            summary: "Backend cluster {{ $labels.cluster }} unhealthy"
            description: "Only {{ $value | humanizePercentage }} of backends are healthy"

        # High latency
        - alert: EnvoyGatewayHighLatency
          expr: envoy:gateway:latency_p95 > 1000
          for: 10m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "High latency on {{ $labels.gateway }}"
            description: "P95 latency is {{ $value }}ms"
```

### Verification Checklist

- [ ] PodMonitor updated with labels and relabelings
- [ ] Prometheus scraping Envoy metrics (check Targets page)
- [ ] Recording rules created and evaluating
- [ ] Alerts firing correctly in Alertmanager
- [ ] Grafana can query `envoy_*` metrics

---

## Phase 3: CoreDNS Monitoring

### Purpose

Monitor DNS resolution health, cache performance, and query patterns. DNS is a critical path for all service communication.

### Implementation

#### Step 1: Create ServiceMonitor for CoreDNS

Create `templates/config/kubernetes/apps/kube-system/coredns/app/servicemonitor.yaml.j2`:

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: coredns
  namespace: kube-system
  labels:
    prometheus: kube-prometheus
spec:
  jobLabel: coredns
  selector:
    matchLabels:
      app.kubernetes.io/name: coredns
      k8s-app: kube-dns
  namespaceSelector:
    matchNames:
      - kube-system
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: node
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
```

#### Step 2: Update Kustomization

Edit `templates/config/kubernetes/apps/kube-system/coredns/app/kustomization.yaml.j2`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./servicemonitor.yaml
```

#### Step 3: Verify Prometheus Plugin

The existing CoreDNS HelmRelease already has the Prometheus plugin enabled:

```yaml
# From helmrelease.yaml.j2 line 50-51
- name: prometheus
  parameters: 0.0.0.0:9153
```

No changes needed to CoreDNS config.

### Critical CoreDNS Metrics

| Metric | Type | Purpose |
| ------ | ---- | ------- |
| `coredns_dns_requests_total` | Counter | Total DNS queries (by type) |
| `coredns_dns_responses_total` | Counter | DNS responses (by rcode) |
| `coredns_dns_request_duration_seconds` | Histogram | Query latency |
| `coredns_cache_hits_total` | Counter | Cache hit rate |
| `coredns_cache_misses_total` | Counter | Cache miss rate |
| `coredns_forward_healthcheck_failures_total` | Counter | Upstream DNS failures |
| `coredns_forward_requests_total` | Counter | Forwarded queries |

### Prometheus Recording Rules

Add to `rules-network.yaml.j2`:

```yaml
  groups:
    # ... existing envoy groups ...

    - name: coredns_performance
      interval: 30s
      rules:
        # DNS Query Rate
        - record: coredns:query_rate
          expr: |
            sum by (namespace, pod) (
              rate(coredns_dns_requests_total[5m])
            )

        # DNS Error Rate (NXDOMAIN + SERVFAIL)
        - record: coredns:error_rate
          expr: |
            (
              sum by (namespace, pod) (
                rate(coredns_dns_responses_total{rcode=~"NXDOMAIN|SERVFAIL"}[5m])
              )
            ) /
            (
              sum by (namespace, pod) (
                rate(coredns_dns_responses_total[5m])
              )
            )

        # Cache Hit Rate
        - record: coredns:cache_hit_rate
          expr: |
            sum by (namespace, pod) (
              rate(coredns_cache_hits_total[5m])
            ) /
            (
              sum by (namespace, pod) (
                rate(coredns_cache_hits_total[5m])
              ) +
              sum by (namespace, pod) (
                rate(coredns_cache_misses_total[5m])
              )
            )

        # P95 Query Latency
        - record: coredns:latency_p95
          expr: |
            histogram_quantile(0.95,
              sum by (namespace, pod, le) (
                rate(coredns_dns_request_duration_seconds_bucket[5m])
              )
            )

    - name: coredns_alerts
      interval: 30s
      rules:
        # High DNS error rate
        - alert: CoreDNSHighErrorRate
          expr: coredns:error_rate > 0.05
          for: 5m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "High DNS error rate in {{ $labels.namespace }}"
            description: "CoreDNS has {{ $value | humanizePercentage }} error rate"

        # Low cache hit rate
        - alert: CoreDNSLowCacheHitRate
          expr: coredns:cache_hit_rate < 0.5
          for: 10m
          labels:
            severity: info
            component: network
          annotations:
            summary: "Low DNS cache hit rate"
            description: "Cache hit rate is {{ $value | humanizePercentage }}"

        # CoreDNS down
        - alert: CoreDNSDown
          expr: absent(up{job="coredns"} == 1)
          for: 2m
          labels:
            severity: critical
            component: network
          annotations:
            summary: "CoreDNS is down"
            description: "No CoreDNS pods are reachable"

        # Upstream DNS failures
        - alert: CoreDNSUpstreamFailures
          expr: rate(coredns_forward_healthcheck_failures_total[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "CoreDNS upstream failures"
            description: "Upstream DNS health checks failing"
```

### Verification Checklist

- [ ] ServiceMonitor created for CoreDNS
- [ ] Prometheus scraping CoreDNS metrics
- [ ] Recording rules evaluating
- [ ] Alerts configured
- [ ] Grafana can query `coredns_*` metrics

---

## Phase 4: external-dns Monitoring

### Purpose

Monitor external-dns sync status for Cloudflare and UniFi DNS (if enabled).

### Implementation

#### Step 1: Enable Metrics in external-dns

**For Cloudflare DNS:**

Edit `templates/config/kubernetes/apps/network/cloudflare-dns/app/helmrelease.yaml.j2`:

```yaml
values:
  # ... existing values ...

  serviceMonitor:
    enabled: true
    namespace: network
    labels:
      prometheus: kube-prometheus

  metrics:
    enabled: true
    port: 7979
```

**For UniFi DNS (if enabled):**

Edit `templates/config/kubernetes/apps/network/unifi-dns/app/helmrelease.yaml.j2`:

```yaml
values:
  # ... existing values ...

  serviceMonitor:
    enabled: true
    namespace: network
    labels:
      prometheus: kube-prometheus

  metrics:
    enabled: true
    port: 7979
```

#### Step 2: Recording Rules

Add to `rules-network.yaml.j2`:

```yaml
  groups:
    # ... existing groups ...

    - name: external_dns_alerts
      interval: 30s
      rules:
        # external-dns not syncing
        - alert: ExternalDNSNotSyncing
          expr: |
            (time() - external_dns_registry_endpoints_total_timestamp) > 600
          for: 5m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "external-dns hasn't synced in 10 minutes"
            description: "Last sync was {{ $value }}s ago"

        # High error rate
        - alert: ExternalDNSHighErrorRate
          expr: |
            rate(external_dns_registry_errors_total[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "external-dns errors"
            description: "{{ $value }} errors/sec"
```

### Verification Checklist

- [ ] ServiceMonitors created for external-dns instances
- [ ] Prometheus scraping external-dns metrics
- [ ] Alerts configured
- [ ] DNS records syncing correctly (verify in Cloudflare/UniFi)

---

## Phase 5: BGP Monitoring (Optional)

### Purpose

If BGP Control Plane v2 is enabled, monitor peer status and route advertisements.

### Current Limitation

**Cilium does NOT expose native Prometheus metrics for BGP** as of January 2026. BGP monitoring requires:
1. FRRouting (FRR) exporter on UniFi gateway (external)
2. Cilium CLI commands for pod-level status
3. Custom metric collection (advanced)

### Workaround: Log-Based Monitoring

#### Step 1: Enable BGP Logging in Cilium

Edit `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`:

```yaml
values:
  # ... existing values ...

  #% if cilium_bgp_enabled %#
  debug:
    enabled: true
    # Only enable BGP subsystem logging
    verbose: "bgp-control-plane"
  #% endif %#
```

#### Step 2: Create Log-Based Alerts

Use log aggregation (Loki/Promtail) to alert on BGP peer down events:

```yaml
# Example Loki LogQL alert (requires Loki deployed)
- alert: CiliumBGPPeerDown
  expr: |
    count_over_time({app="cilium"} |~ "BGP.*peer.*down" [5m]) > 0
  for: 2m
  labels:
    severity: critical
    component: network
  annotations:
    summary: "Cilium BGP peer down"
    description: "BGP peering has failed"
```

#### Step 3: Manual BGP Verification

Add to cluster monitoring runbook:

```bash
# Check BGP peer status
kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers

# Expected output:
# Node          Local AS   Peer AS   Peer Address   Session State   Uptime   Family         Received   Advertised
# k8s-1         64514      64513     192.168.1.1    established     5h       ipv4/unicast   0          3

# Check routes advertised
kubectl -n kube-system exec -it ds/cilium -- cilium bgp routes advertised ipv4 unicast

# Check BGP cluster config status
kubectl get ciliumbgpclusterconfig bgp-cluster-config -o yaml
```

### Alternative: UniFi FRR Exporter (External)

For production BGP monitoring, deploy an FRR exporter on the UniFi gateway:

```bash
# SSH to UniFi gateway
ssh root@192.168.1.1

# Install frr_exporter (example)
# This requires custom installation on UniFi OS
# See: https://github.com/tynany/frr_exporter
```

**This is outside the scope of this K8s cluster template** but can be added to external monitoring.

### Verification Checklist

- [ ] BGP debug logging enabled in Cilium
- [ ] Log aggregation capturing BGP events
- [ ] Manual BGP verification commands documented
- [ ] Alert created for peer down events
- [ ] (Optional) External FRR exporter on UniFi gateway

---

## Phase 6: Grafana Dashboards

### Recommended Dashboards

| Dashboard | Grafana ID | Purpose |
| --------- | ---------- | ------- |
| **Cilium Operator** | 16611 | Cilium operator metrics |
| **Cilium Agent** | 16612 | Cilium agent and eBPF metrics |
| **Hubble Network Overview** | 16613 | Network flow visualization (L3/L4/L7) |
| **Hubble DNS** | 16614 | DNS query patterns and errors |
| **CoreDNS** | 5926 | DNS performance and cache hits |
| **Envoy Global** | 11021 | Envoy gateway global stats |
| **Envoy Clusters** | 11022 | Backend health and performance |

### Import Dashboards via ConfigMap

Create `templates/config/kubernetes/apps/monitoring/grafana/app/dashboards-network.yaml.j2`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-cilium-operator
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  cilium-operator.json: |-
    # Dashboard JSON from https://grafana.com/grafana/dashboards/16611
    # (Use `curl` or download from Grafana.com)

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-cilium-agent
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  cilium-agent.json: |-
    # Dashboard JSON from https://grafana.com/grafana/dashboards/16612

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-hubble
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  hubble-network.json: |-
    # Dashboard JSON from https://grafana.com/grafana/dashboards/16613

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-coredns
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  coredns.json: |-
    # Dashboard JSON from https://grafana.com/grafana/dashboards/5926
```

**Note:** Full dashboard JSONs are large. Download from Grafana.com and embed in ConfigMaps.

### Custom Infrastructure Dashboard

Create a custom dashboard with panels for:

1. **Network Health Overview**
   - Cilium agent status (up/down)
   - Hubble relay status
   - CoreDNS pod health
   - Envoy gateway health

2. **Traffic Patterns**
   - Total request rate (Envoy)
   - DNS query rate (CoreDNS)
   - Network flow rate (Hubble)

3. **Error Tracking**
   - HTTP 5xx rate (Envoy)
   - DNS NXDOMAIN/SERVFAIL rate (CoreDNS)
   - Network policy drops (Hubble)

4. **Latency**
   - Envoy P50/P95/P99 latency
   - CoreDNS query latency
   - Connection establishment time

5. **Backend Health**
   - Envoy cluster health ratio
   - LoadBalancer backend availability
   - Service endpoint count

---

## Phase 7: Critical Infrastructure Alerts

### Alert Priority Matrix

| Severity | Condition | Notification | Example |
| -------- | --------- | ------------ | ------- |
| **Critical** | Service down, total outage | Page on-call | CoreDNS all pods down |
| **Warning** | Degraded performance | Slack/email | Envoy error rate >5% |
| **Info** | Performance tuning needed | Ticket | DNS cache hit <50% |

### Infrastructure Alert Rules

Complete alert rules in `rules-network.yaml.j2`:

```yaml
spec:
  groups:
    # ... existing groups from previous phases ...

    - name: network_infrastructure_critical
      interval: 30s
      rules:
        # CRITICAL: CNI down
        - alert: CiliumAgentDown
          expr: absent(up{job="cilium-agent"} == 1)
          for: 2m
          labels:
            severity: critical
            component: network
            runbook: https://docs.cilium.io/en/stable/operations/troubleshooting/
          annotations:
            summary: "Cilium agent down"
            description: "No Cilium agents are running - pod networking broken"

        # CRITICAL: DNS total outage
        - alert: CoreDNSTotalOutage
          expr: |
            count(up{job="coredns"} == 1) == 0
          for: 1m
          labels:
            severity: critical
            component: network
          annotations:
            summary: "CoreDNS total outage"
            description: "All CoreDNS pods are down"

        # CRITICAL: Gateway down
        - alert: EnvoyGatewayDown
          expr: absent(up{job="envoy-proxy"} == 1)
          for: 2m
          labels:
            severity: critical
            component: network
          annotations:
            summary: "Envoy gateway down"
            description: "No Envoy proxy pods are reachable"

        # WARNING: Network policy drops
        - alert: CiliumHighPolicyDropRate
          expr: |
            rate(hubble_drop_total{reason=~".*POLICY_DENIED.*"}[5m]) > 10
          for: 10m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "High network policy drop rate"
            description: "{{ $value }} packets/sec dropped by policy"

        # WARNING: LoadBalancer backend failures
        - alert: CiliumLoadBalancerBackendFailures
          expr: |
            rate(cilium_loadbalancer_backend_errors_total[5m]) > 1
          for: 5m
          labels:
            severity: warning
            component: network
          annotations:
            summary: "LoadBalancer backend failures"
            description: "{{ $value }} backend errors/sec"

        # INFO: DNS cache performance
        - alert: CoreDNSCachePerformanceDegraded
          expr: coredns:cache_hit_rate < 0.5
          for: 30m
          labels:
            severity: info
            component: network
          annotations:
            summary: "CoreDNS cache hit rate low"
            description: "Consider increasing cache size or TTL"

        # CRITICAL: BGP peer down (if enabled)
        #% if cilium_bgp_enabled %#
        - alert: CiliumBGPPeerDown
          expr: |
            count_over_time({namespace="kube-system",app="cilium"} |~ "BGP.*peer.*down" [5m]) > 0
          for: 2m
          labels:
            severity: critical
            component: network
          annotations:
            summary: "Cilium BGP peer down"
            description: "BGP peering with gateway has failed - check UniFi"
        #% endif %#
```

### AlertmanagerConfig Example

```yaml
---
apiVersion: monitoring.coreos.com/v1beta1
kind: AlertmanagerConfig
metadata:
  name: network-infrastructure
  namespace: monitoring
spec:
  route:
    groupBy: ['alertname', 'component']
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 12h
    receiver: 'null'
    routes:
      # Critical network alerts -> page
      - matchers:
          - name: severity
            value: critical
          - name: component
            value: network
        receiver: pagerduty
        continue: false

      # Warning network alerts -> Slack
      - matchers:
          - name: severity
            value: warning
          - name: component
            value: network
        receiver: slack-network
        continue: false

  receivers:
    - name: 'null'

    - name: pagerduty
      pagerdutyConfigs:
        - routingKey:
            name: pagerduty-api-key
            key: token
          description: "{{ .CommonAnnotations.summary }}"

    - name: slack-network
      slackConfigs:
        - apiURL:
            name: slack-webhook
            key: url
          channel: '#network-alerts'
          title: "{{ .CommonAnnotations.summary }}"
          text: "{{ .CommonAnnotations.description }}"
```

---

## Deployment Workflow

### Prerequisites Validation

```bash
# 1. Verify kube-prometheus-stack CRDs installed
kubectl get crd prometheusrules.monitoring.coreos.com
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl get crd podmonitors.monitoring.coreos.com

# 2. Verify Prometheus deployed and scraping
kubectl get prometheus -A
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# 3. Verify Grafana deployed
kubectl get deployment -n monitoring grafana
```

### Deployment Order

1. **Phase 1: Enable Hubble**
   ```bash
   # Edit cilium helmrelease.yaml.j2
   task configure
   task reconcile
   # Verify: kubectl get pods -n kube-system -l k8s-app=hubble-relay
   ```

2. **Phase 2: Enhance Envoy Metrics**
   ```bash
   # Edit envoy.yaml.j2 and podmonitor.yaml.j2
   task configure
   task reconcile
   # Verify: kubectl get podmonitor -n network envoy-proxy -o yaml
   ```

3. **Phase 3: Add CoreDNS ServiceMonitor**
   ```bash
   # Create servicemonitor.yaml.j2
   task configure
   task reconcile
   # Verify: kubectl get servicemonitor -n kube-system coredns
   ```

4. **Phase 4: Enable external-dns Metrics**
   ```bash
   # Edit cloudflare-dns and unifi-dns helmreleases
   task configure
   task reconcile
   # Verify: kubectl get servicemonitor -n network
   ```

5. **Phase 5: BGP Monitoring (if enabled)**
   ```bash
   # Edit cilium helmrelease for debug logging
   task configure
   task reconcile
   # Verify: kubectl logs -n kube-system ds/cilium | grep -i bgp
   ```

6. **Phase 6: Create PrometheusRules**
   ```bash
   # Create rules-network.yaml.j2
   task configure
   task reconcile
   # Verify: kubectl get prometheusrule -n monitoring network-infrastructure
   ```

7. **Phase 7: Import Grafana Dashboards**
   ```bash
   # Create dashboards-network.yaml.j2 ConfigMaps
   task configure
   task reconcile
   # Verify: Check Grafana UI for imported dashboards
   ```

### Verification Commands

```bash
# Overall health check
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get pods -n kube-system -l k8s-app=hubble-relay
kubectl get pods -n kube-system -l k8s-app=hubble-ui
kubectl get pods -n network -l app.kubernetes.io/name=envoy
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Metrics endpoints
kubectl get servicemonitor -A | grep -E 'cilium|coredns|external-dns'
kubectl get podmonitor -A | grep envoy

# Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Check: http://localhost:9090/targets
# Look for: cilium-agent, hubble, coredns, envoy-proxy

# Test queries
# Prometheus: envoy_http_downstream_rq_total
# Prometheus: coredns_dns_requests_total
# Prometheus: hubble_drop_total

# Grafana dashboards
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open: http://localhost:3000
# Login: admin / <password>
# Check dashboards imported
```

---

## Troubleshooting

### Hubble Not Collecting Flows

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| `hubble observe` shows nothing | Relay not running | Check `kubectl get pods -n kube-system -l k8s-app=hubble-relay` |
| Flows visible in CLI but not Prometheus | ServiceMonitor missing | Check `kubectl get servicemonitor -n kube-system` |
| Metrics endpoint 404 | Hubble metrics not enabled | Verify `hubble.metrics.enabled` in HelmRelease |

```bash
# Debug Hubble
kubectl -n kube-system logs ds/cilium | grep -i hubble
kubectl -n kube-system logs deployment/hubble-relay
kubectl -n kube-system exec -it ds/cilium -- hubble status
```

### Envoy Metrics Not Scraped

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| No envoy_* metrics in Prometheus | PodMonitor not created | Check `kubectl get podmonitor -n network` |
| Metrics endpoint unreachable | Port name mismatch | Verify pod has port named `metrics` |
| Empty time series | No traffic | Generate test traffic to gateway |

```bash
# Debug Envoy metrics
kubectl get podmonitor envoy-proxy -n network -o yaml
kubectl get pods -n network -l app.kubernetes.io/name=envoy -o yaml | grep -A 5 "name: metrics"
kubectl exec -n network <envoy-pod> -- wget -qO- localhost:19001/stats/prometheus | head -20
```

### CoreDNS Metrics Missing

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| No coredns_* metrics | ServiceMonitor missing | Create ServiceMonitor from Phase 3 |
| Prometheus plugin not loaded | Config error | Check Corefile has `prometheus 0.0.0.0:9153` |
| Metrics port not exposed | Service missing port | Verify Service has port 9153 named `metrics` |

```bash
# Debug CoreDNS
kubectl get servicemonitor -n kube-system coredns -o yaml
kubectl get svc -n kube-system kube-dns -o yaml | grep -A 3 9153
kubectl exec -n kube-system <coredns-pod> -- wget -qO- localhost:9153/metrics | head -20
```

### PrometheusRules Not Evaluating

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| Rules not visible in Prometheus | Label mismatch | Ensure `prometheus: kube-prometheus` label |
| Rules loaded but not evaluating | Syntax error | Check `kubectl describe prometheusrule` |
| Recording rules empty | No data | Verify underlying metrics exist |

```bash
# Debug PrometheusRules
kubectl get prometheusrule -n monitoring network-infrastructure -o yaml
kubectl logs -n monitoring prometheus-<pod> | grep -i error
# Prometheus UI: Status -> Rules (check for errors)
```

### BGP Peer Down

| Symptom | Cause | Solution |
| ------- | ----- | -------- |
| `cilium bgp peers` shows Idle | UniFi config missing | Apply FRR config from `unifi/bgp.conf` |
| Peer shows Active (not Established) | ASN mismatch | Verify `cilium_bgp_router_asn` matches UniFi |
| Peer flapping | Timers too aggressive | Increase `cilium_bgp_hold_time` |
| Password auth failure | Secret mismatch | Verify `bgp-peer-password` secret |

```bash
# Debug BGP
kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers
kubectl -n kube-system logs ds/cilium | grep -i bgp
kubectl get ciliumbgpclusterconfig bgp-cluster-config -o yaml
kubectl get secret -n kube-system bgp-peer-password -o yaml

# UniFi side (SSH to gateway)
vtysh -c 'show bgp summary'
vtysh -c 'show bgp neighbors'
```

---

## Rollback Procedures

### Disable Hubble

```yaml
# Edit cilium helmrelease.yaml.j2
hubble:
  enabled: false
```

```bash
task configure && task reconcile
```

### Revert Envoy Metrics Changes

```bash
# Git revert changes to envoy.yaml.j2 and podmonitor.yaml.j2
git checkout HEAD -- templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2
git checkout HEAD -- templates/config/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml.j2
task configure && task reconcile
```

### Remove ServiceMonitors/PrometheusRules

```bash
kubectl delete servicemonitor -n kube-system coredns
kubectl delete prometheusrule -n monitoring network-infrastructure
```

---

## Performance Impact

### Resource Overhead

| Component | CPU Overhead | Memory Overhead | Notes |
| --------- | ------------ | --------------- | ----- |
| **Hubble Relay** | 10-20m | 50-100Mi | Per replica |
| **Hubble UI** | 5-10m | 30-50Mi | Per replica |
| **Hubble metrics collection** | 1-2m per node | 10-20Mi per node | In Cilium agent |
| **Envoy metrics scraping** | <1m | <10Mi | No additional pods |
| **CoreDNS metrics** | <1m | <5Mi | Already enabled |

**Total infrastructure overhead:** ~30-50m CPU, ~100-200Mi memory for Hubble.

### Prometheus Storage Impact

**Estimated additional metrics:**

- Hubble: ~50-100 time series per node
- Envoy: ~500-1000 time series per gateway
- CoreDNS: ~50-100 time series per pod
- Recording rules: ~20-30 additional time series

**Total:** ~1000-2000 additional time series for typical 3-node cluster.

**Storage estimate:** ~1-2 GB/month with 15d retention.

---

## References

### Project Documentation
- [Cilium Networking Guide](../ai-context/cilium-networking.md) - Cilium architecture and BGP setup
- [Envoy Gateway Observability](./envoy-gateway-observability-security.md) - Access logging and tracing
- [k8s-at-home Patterns](./k8s-at-home-patterns-implementation.md) - Monitoring stack deployment

### External Documentation
- [Cilium Observability](https://docs.cilium.io/en/stable/observability/) - Official Cilium observability docs
- [Hubble Metrics](https://docs.cilium.io/en/stable/observability/metrics/#hubble-exported-metrics) - Hubble metric reference
- [Envoy Statistics](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/statistics) - Envoy metrics reference
- [CoreDNS Metrics](https://github.com/coredns/coredns/tree/master/plugin/metrics) - CoreDNS Prometheus plugin
- [Prometheus Operator](https://prometheus-operator.dev/) - ServiceMonitor/PodMonitor docs
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/) - Community dashboards

### BGP Monitoring
- [Cilium BGP Control Plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/) - BGP configuration
- [FRRouting](https://docs.frrouting.org/en/latest/bgp.html) - UniFi BGP backend
- [Cilium CLI BGP Commands](https://docs.cilium.io/en/stable/cmdref/cilium_bgp_peers/) - BGP debugging

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-03 | Initial network observability implementation guide created |
