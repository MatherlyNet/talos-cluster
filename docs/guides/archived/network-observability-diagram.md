# Network Observability Architecture Diagram

## High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    NETWORK INFRASTRUCTURE LAYER                             │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐           │
│  │  Cilium CNI     │  │ Envoy Gateway   │  │    CoreDNS      │           │
│  │  + Hubble       │  │                 │  │                 │           │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤           │
│  │ Metrics:        │  │ Metrics:        │  │ Metrics:        │           │
│  │ - Flow logs     │  │ - RED metrics   │  │ - Query rate    │           │
│  │ - DNS queries   │  │ - Latency       │  │ - Error rate    │           │
│  │ - Policy drops  │  │ - Backend health│  │ - Cache hits    │           │
│  │ - TCP stats     │  │ - Connections   │  │ - Latency       │           │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘           │
│           │                     │                     │                     │
│           │   ServiceMonitor    │   PodMonitor        │   ServiceMonitor   │
│           └─────────────────────┼─────────────────────┘                     │
│                                 │                                           │
└─────────────────────────────────┼───────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      PROMETHEUS OPERATOR                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                      Prometheus / VictoriaMetrics                     │ │
│  │                                                                        │ │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐        │ │
│  │  │ ServiceMonitor │  │  PodMonitor    │  │ PrometheusRule │        │ │
│  │  │   Discovery    │  │   Discovery    │  │   Evaluation   │        │ │
│  │  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘        │ │
│  │          │                    │                    │                  │ │
│  │          └────────────────────┼────────────────────┘                  │ │
│  │                               ▼                                       │ │
│  │                   ┌───────────────────────┐                          │ │
│  │                   │  Metrics Storage      │                          │ │
│  │                   │  - cilium_*           │                          │ │
│  │                   │  - hubble_*           │                          │ │
│  │                   │  - envoy_*            │                          │ │
│  │                   │  - coredns_*          │                          │ │
│  │                   │  - Recording rules    │                          │ │
│  │                   └───────────┬───────────┘                          │ │
│  └───────────────────────────────┼──────────────────────────────────────┘ │
│                                  │                                         │
│                                  ├──────────────┐                          │
│                                  │              │                          │
│                                  ▼              ▼                          │
│                    ┌──────────────────┐  ┌─────────────────┐             │
│                    │  Alertmanager    │  │    Grafana      │             │
│                    │                  │  │                 │             │
│                    │ - Critical alerts│  │ - Dashboards    │             │
│                    │ - Warning alerts │  │ - Visualization │             │
│                    │ - Info alerts    │  │ - Ad-hoc queries│             │
│                    └────────┬─────────┘  └─────────────────┘             │
│                             │                                              │
└─────────────────────────────┼──────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      NOTIFICATION CHANNELS                                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐           │
│  │   PagerDuty     │  │     Slack       │  │   Ticketing     │           │
│  │   (Critical)    │  │   (Warning)     │  │     (Info)      │           │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘           │
│                                                                              │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              METRICS FLOW                                     │
└──────────────────────────────────────────────────────────────────────────────┘

1. COLLECTION PHASE
   ─────────────────

   ┌─────────────┐
   │ Cilium Pod  │──────┐
   └─────────────┘      │
                        │ :9962/metrics (ServiceMonitor)
   ┌─────────────┐      ├──────────────────────┐
   │ Hubble Relay│──────┘                      │
   └─────────────┘                             │
                                                ▼
   ┌─────────────┐                   ┌──────────────────┐
   │ Envoy Proxy │─────────────────▶ │   Prometheus     │
   └─────────────┘  :19001/stats     │   (Scraper)      │
       (PodMonitor)   /prometheus     │                  │
                                      │  Scrape every    │
   ┌─────────────┐                   │  30s             │
   │  CoreDNS    │─────────────────▶ │                  │
   └─────────────┘  :9153/metrics    └────────┬─────────┘
       (ServiceMonitor)                       │
                                               │
2. PROCESSING PHASE                           │
   ────────────────                           │
                                               ▼
                                    ┌───────────────────┐
                                    │ Recording Rules   │
                                    │                   │
                                    │ Execute every 30s │
                                    │ - envoy:*         │
                                    │ - coredns:*       │
                                    │ - cilium:*        │
                                    └────────┬──────────┘
                                             │
3. ALERTING PHASE                           │
   ──────────────                           │
                                             ▼
                                    ┌───────────────────┐
                                    │  Alert Rules      │
                                    │                   │
                                    │ Evaluate every 30s│
                                    │ - Critical        │
                                    │ - Warning         │
                                    │ - Info            │
                                    └────────┬──────────┘
                                             │
                                             ▼
                                    ┌───────────────────┐
                                    │  Alertmanager     │
                                    │                   │
                                    │ - Route by        │
                                    │   severity        │
                                    │ - Deduplicate     │
                                    │ - Group           │
                                    └────────┬──────────┘
                                             │
4. NOTIFICATION PHASE                       │
   ──────────────────                       │
                                             ▼
                           ┌─────────────────┴─────────────────┐
                           │                                   │
                           ▼                                   ▼
                 ┌──────────────────┐            ┌──────────────────┐
                 │   PagerDuty      │            │      Slack       │
                 │   (Critical)     │            │    (Warning)     │
                 └──────────────────┘            └──────────────────┘
```

---

## Component Interaction Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        HUBBLE ARCHITECTURE                                  │
└────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│                          K8s Node                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Cilium Agent (DaemonSet)                    │ │
│  │                                                           │ │
│  │  ┌──────────────┐          ┌──────────────┐            │ │
│  │  │   eBPF       │          │   Hubble     │            │ │
│  │  │   Programs   │─────────▶│   Server     │            │ │
│  │  │              │  events  │              │            │ │
│  │  │ - L3/L4/L7   │          │ - Flow logs  │◀───────┐   │ │
│  │  │ - DNS        │          │ - Metrics    │        │   │ │
│  │  │ - TCP stats  │          │              │        │   │ │
│  │  └──────────────┘          └──────┬───────┘        │   │ │
│  │                                    │                │   │ │
│  │                                    │ gRPC           │   │ │
│  └────────────────────────────────────┼────────────────┼───┘ │
│                                       │                │     │
└───────────────────────────────────────┼────────────────┼─────┘
                                        │                │
                                        │                │
                         ┌──────────────▼────────────┐   │
                         │   Hubble Relay            │   │
                         │   (Deployment)            │   │
                         │                           │   │
                         │ - Aggregates flows from   │   │
                         │   all nodes               │   │
                         │ - Provides unified API    │   │
                         │ - Exports Prometheus      │◀──┘ Metrics scrape
                         │   metrics                 │     (:4245/metrics)
                         └──────────┬────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
           ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
           │ Hubble CLI  │  │  Hubble UI  │  │ Prometheus  │
           │             │  │             │  │             │
           │ kubectl     │  │ Web UI for  │  │ Metrics     │
           │ port-forward│  │ flow viz    │  │ collection  │
           └─────────────┘  └─────────────┘  └─────────────┘
```

---

## Alert Routing Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          ALERT FLOW                                         │
└────────────────────────────────────────────────────────────────────────────┘

                        ┌──────────────────┐
                        │ PrometheusRule   │
                        │                  │
                        │ - CiliumDown     │
                        │ - CoreDNSDown    │
                        │ - EnvoyDown      │
                        │ - HighErrorRate  │
                        │ - BGPPeerDown    │
                        └────────┬─────────┘
                                 │ Alert fires
                                 ▼
                        ┌──────────────────┐
                        │  Alertmanager    │
                        │                  │
                        │  Route by:       │
                        │  - severity      │
                        │  - component     │
                        └────────┬─────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 │               │               │
                 ▼               ▼               ▼
        ┌────────────────┐  ┌────────────┐  ┌─────────────┐
        │   CRITICAL     │  │  WARNING   │  │    INFO     │
        │                │  │            │  │             │
        │ severity:      │  │ severity:  │  │ severity:   │
        │ critical       │  │ warning    │  │ info        │
        └───────┬────────┘  └──────┬─────┘  └──────┬──────┘
                │                  │                │
                ▼                  ▼                ▼
        ┌────────────────┐  ┌────────────┐  ┌─────────────┐
        │   PagerDuty    │  │   Slack    │  │  Ticketing  │
        │                │  │            │  │             │
        │ - Page on-call │  │ #network-  │  │ - Jira      │
        │ - Phone/SMS    │  │  alerts    │  │ - GitHub    │
        │                │  │            │  │   Issues    │
        └────────────────┘  └────────────┘  └─────────────┘

        Response time:      Response time:   Response time:
        Immediate           15 minutes       Next business day


Examples by severity:

CRITICAL (Page immediately)
├─ CiliumAgentDown
├─ CoreDNSTotalOutage
├─ EnvoyGatewayDown
├─ EnvoyBackendUnhealthy (<50%)
└─ CiliumBGPPeerDown (if BGP enabled)

WARNING (Slack notification)
├─ CoreDNSHighErrorRate (>5%)
├─ EnvoyGatewayHighErrorRate (>5%)
├─ EnvoyGatewayHighLatency (P95 >1s)
├─ CiliumHighPolicyDropRate (>10/sec)
└─ ExternalDNSNotSyncing (>10min)

INFO (Ticket for follow-up)
├─ CoreDNSLowCacheHitRate (<50%)
└─ CiliumLoadBalancerBackendErrors (>1/sec)
```

---

## Metric Collection Timeline

```
Time: 0s        30s       60s       90s       120s      150s      180s
      │         │         │         │         │         │         │
      ▼         ▼         ▼         ▼         ▼         ▼         ▼

┌─────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────────┐
│                    Prometheus Scrape Cycle                           │
│                    (every 30 seconds)                                │
│                                                                       │
│  T+0s:  Scrape cilium-agent:9962/metrics                            │
│  T+0s:  Scrape hubble-relay:4245/metrics                            │
│  T+0s:  Scrape envoy-proxy:19001/stats/prometheus                   │
│  T+0s:  Scrape coredns:9153/metrics                                 │
│                                                                       │
│  T+30s: Next scrape cycle begins                                    │
└───────────────────────────────────────────────────────────────────────┘

┌─────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────────┐
│                Recording Rule Evaluation                             │
│                (every 30 seconds)                                    │
│                                                                       │
│  T+0s:  Calculate envoy:gateway:request_rate (5m window)            │
│  T+0s:  Calculate envoy:gateway:error_rate (5m window)              │
│  T+0s:  Calculate coredns:error_rate (5m window)                    │
│  T+0s:  Calculate coredns:cache_hit_rate (5m window)                │
│                                                                       │
│  T+30s: Next evaluation cycle                                       │
└───────────────────────────────────────────────────────────────────────┘

┌─────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────────┐
│                    Alert Rule Evaluation                             │
│                    (every 30 seconds)                                │
│                                                                       │
│  T+0s:  Check EnvoyGatewayHighErrorRate (for: 5m)                   │
│  T+0s:  Check CoreDNSHighErrorRate (for: 5m)                        │
│  T+0s:  Check CiliumAgentDown (for: 2m)                             │
│                                                                       │
│  If condition met for "for: duration" → FIRE ALERT                  │
│                                                                       │
│  T+30s: Next evaluation cycle                                       │
└───────────────────────────────────────────────────────────────────────┘


Example Alert Firing Timeline:

T+0s:   Error rate = 6% (exceeds 5% threshold)
T+30s:  Error rate = 6.2% (still exceeds, counter: 30s)
T+60s:  Error rate = 6.5% (still exceeds, counter: 60s)
T+90s:  Error rate = 6.1% (still exceeds, counter: 90s)
T+120s: Error rate = 5.9% (still exceeds, counter: 120s)
T+150s: Error rate = 6.0% (still exceeds, counter: 150s)
T+180s: Error rate = 5.8% (still exceeds, counter: 180s)
T+210s: Error rate = 5.7% (still exceeds, counter: 210s)
T+240s: Error rate = 5.6% (still exceeds, counter: 240s)
T+270s: Error rate = 5.5% (still exceeds, counter: 270s)
T+300s: *** ALERT FIRES *** (for: 5m threshold met)
        └──▶ Send to Alertmanager
             └──▶ Route to Slack (#network-alerts)
```

---

## BGP Monitoring Architecture (Special Case)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    BGP MONITORING LIMITATION                                │
└────────────────────────────────────────────────────────────────────────────┘

NO NATIVE PROMETHEUS METRICS FOR BGP IN CILIUM (as of Jan 2026)

Workaround Architecture:

┌─────────────────────────────────────────────────────────────────────┐
│                          K8s Node                                    │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │              Cilium Agent (DaemonSet)                           │ │
│  │                                                                  │ │
│  │  ┌────────────────────┐                                        │ │
│  │  │  BGP Control Plane │                                        │ │
│  │  │  (GoBGP backend)   │                                        │ │
│  │  │                    │                                        │ │
│  │  │  ❌ NO METRICS     │                                        │ │
│  │  │  ✅ LOGS ONLY      │──────┐                                │ │
│  │  └────────────────────┘      │ debug logs                     │ │
│  │                               │                                 │ │
│  └───────────────────────────────┼─────────────────────────────────┘ │
│                                  │                                   │
└──────────────────────────────────┼───────────────────────────────────┘
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │  kubectl logs           │
                      │  (stderr output)        │
                      │                         │
                      │  BGP peer 192.168.1.1   │
                      │  established            │
                      └────────┬────────────────┘
                               │
                               │ If log aggregation deployed
                               ▼
                      ┌─────────────────────────┐
                      │  Loki / Promtail        │
                      │  (Log aggregation)      │
                      │                         │
                      │  LogQL alert:           │
                      │  {app="cilium"}         │
                      │  |~ "BGP.*peer.*down"   │
                      └────────┬────────────────┘
                               │
                               ▼
                      ┌─────────────────────────┐
                      │  Alertmanager           │
                      │  (via Loki ruler)       │
                      └─────────────────────────┘


Manual Verification (Required):

┌───────────────────────────────────────────────────────────────┐
│  Operator Action                                               │
│                                                                 │
│  kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers│
│                                                                 │
│  Expected output:                                               │
│  Node   Local AS  Peer AS  Peer Addr    State        Uptime   │
│  k8s-1  64514     64513    192.168.1.1  established  5h       │
│  k8s-2  64514     64513    192.168.1.1  established  5h       │
│  k8s-3  64514     64513    192.168.1.1  established  5h       │
└───────────────────────────────────────────────────────────────┘


Alternative (Advanced): External FRR Exporter on UniFi Gateway

┌────────────────────────┐
│   UniFi Gateway        │     ┌─────────────────────────┐
│   (192.168.1.1)        │     │   Prometheus            │
│                        │     │   (External scrape)     │
│  ┌──────────────────┐ │     │                         │
│  │  FRRouting (FRR) │ │     │  - BGP peer count       │
│  │                  │ │     │  - BGP routes received  │
│  └────────┬─────────┘ │     │  - BGP session state    │
│           │           │     │                         │
│  ┌────────▼─────────┐ │     │  scrape_configs:        │
│  │  frr_exporter    │◀┼─────┤    - job: unifi-bgp     │
│  │  :9342/metrics   │ │     │      static_configs:    │
│  └──────────────────┘ │     │      - 192.168.1.1:9342 │
└────────────────────────┘     └─────────────────────────┘

NOTE: This requires custom installation on UniFi gateway
      (outside scope of K8s cluster template)
```

---

## Dashboard Layout Example

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE NETWORK HEALTH                            │
│                         (Custom Grafana Dashboard)                          │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│ ROW 1: COMPONENT STATUS                                                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐│
│  │ Cilium Agent  │  │   CoreDNS     │  │ Envoy Gateway │  │ BGP Peers   ││
│  │               │  │               │  │               │  │             ││
│  │   ✅ 3/3     │  │   ✅ 2/2     │  │   ✅ 2/2     │  │  ✅ 3/3    ││
│  │   UP         │  │   UP         │  │   UP         │  │  ESTAB.    ││
│  └───────────────┘  └───────────────┘  └───────────────┘  └─────────────┘│
│                                                                              │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│ ROW 2: TRAFFIC PATTERNS                                                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐        │
│  │ Gateway Request Rate        │  │ DNS Query Rate              │        │
│  │ (requests/sec)              │  │ (queries/sec)               │        │
│  │                             │  │                             │        │
│  │     1200 ▲                  │  │      450 ▲                  │        │
│  │          │     ╱╲           │  │          │    ╱╲╱╲          │        │
│  │      800 ┼────╱  ╲          │  │      300 ┼───╱    ╲         │        │
│  │          │   ╱    ╲         │  │          │  ╱      ╲        │        │
│  │      400 ┼──╱      ╲────    │  │      150 ┼─╱        ╲───    │        │
│  │          │                   │  │          │                  │        │
│  │        0 └──────────────────▶│  │        0 └─────────────────▶│        │
│  │          12h    6h     now   │  │          12h    6h    now   │        │
│  └─────────────────────────────┘  └─────────────────────────────┘        │
│                                                                              │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│ ROW 3: ERROR TRACKING                                                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐        │
│  │ HTTP 5xx Rate (%)           │  │ DNS Error Rate (%)          │        │
│  │                             │  │                             │        │
│  │   5.0% ┬───────────────────▶│  │   5.0% ┬───────────────────▶│        │
│  │        │  THRESHOLD          │  │        │  THRESHOLD          │        │
│  │   2.5% ┼        ▲            │  │   2.5% ┼                     │        │
│  │        │       ╱│            │  │        │         ╱╲          │        │
│  │   1.0% ┼──────╱ │            │  │   1.0% ┼────────╱  ╲         │        │
│  │        │                     │  │        │                     │        │
│  │   0.0% └──────────────────▶ │  │   0.0% └────────────────────▶│        │
│  │        12h    6h     now    │  │        12h    6h     now    │        │
│  └─────────────────────────────┘  └─────────────────────────────┘        │
│                                                                              │
│  ┌─────────────────────────────┐                                           │
│  │ Network Policy Drops/sec    │                                           │
│  │                             │                                           │
│  │     20 ┬───────────────────▶│                                           │
│  │        │  THRESHOLD          │                                           │
│  │     10 ┼                     │                                           │
│  │        │      ▲              │                                           │
│  │      5 ┼─────╱│              │                                           │
│  │        │                     │                                           │
│  │      0 └──────────────────▶ │                                           │
│  │        12h    6h     now    │                                           │
│  └─────────────────────────────┘                                           │
│                                                                              │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│ ROW 4: LATENCY                                                              │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐        │
│  │ Envoy P95 Latency (ms)      │  │ CoreDNS P95 Latency (ms)    │        │
│  │                             │  │                             │        │
│  │ 1000ms ┬───────────────────▶│  │  500ms ┬───────────────────▶│        │
│  │        │  THRESHOLD          │  │        │  THRESHOLD          │        │
│  │  500ms ┼                     │  │  250ms ┼                     │        │
│  │        │          ╱╲         │  │        │                     │        │
│  │  250ms ┼─────────╱  ╲────    │  │  100ms ┼─────────────────    │        │
│  │        │                     │  │        │                     │        │
│  │    0ms └──────────────────▶ │  │    0ms └────────────────────▶│        │
│  │        12h    6h     now    │  │        12h    6h     now    │        │
│  └─────────────────────────────┘  └─────────────────────────────┘        │
│                                                                              │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│ ROW 5: BACKEND HEALTH                                                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐│
│  │ Envoy Backend Health Ratio                                             ││
│  │                                                                         ││
│  │ Cluster              │ Healthy │ Total │ Ratio  │ Status              ││
│  │ ────────────────────┼─────────┼───────┼────────┼──────────────────   ││
│  │ echo-default         │    2    │   2   │ 100%   │ ✅ Healthy         ││
│  │ flux-webhook         │    1    │   1   │ 100%   │ ✅ Healthy         ││
│  │ hubble-ui            │    1    │   1   │ 100%   │ ✅ Healthy         ││
│  │                                                                         ││
│  └───────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└────────────────────────────────────────────────────────────────────────────┘
```
