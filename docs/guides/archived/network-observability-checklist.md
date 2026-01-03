# Network Observability Implementation Checklist

> **Quick-start checklist** for [network-observability-implementation.md](./network-observability-implementation.md)

## Prerequisites Validation

### Required Components

- [ ] **kube-prometheus-stack CRDs installed**
  ```bash
  kubectl get crd prometheusrules.monitoring.coreos.com
  kubectl get crd servicemonitors.monitoring.coreos.com
  kubectl get crd podmonitors.monitoring.coreos.com
  ```

- [ ] **Prometheus-compatible scraper deployed**
  - See [k8s-at-home-patterns-implementation.md](./k8s-at-home-patterns-implementation.md#phase-3-observability-stack)
  - Options: VictoriaMetrics or kube-prometheus-stack

- [ ] **Grafana deployed** (optional but recommended)
  ```bash
  kubectl get deployment -n monitoring grafana
  ```

---

## Phase 1: Enable Hubble (Priority: P0)

### File Modifications

- [ ] **Edit:** `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`

  Add after existing values (line 39):
  ```yaml
  hubble:
    enabled: true
    metrics:
      enabled:
        - dns:query;ignoreAAAA
        - drop
        - tcp
        - flow
        - port-distribution
        - icmp
      enableOpenMetrics: true
      serviceMonitor:
        enabled: true
        labels:
          prometheus: kube-prometheus
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
  ```

### Optional: Expose Hubble UI

- [ ] **Create:** `templates/config/kubernetes/apps/kube-system/cilium/app/httproute.yaml.j2`
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

- [ ] **Edit:** `templates/config/kubernetes/apps/kube-system/cilium/app/kustomization.yaml.j2`

  Add resource:
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

- [ ] **Edit:** `cluster.yaml` (if exposing Hubble UI)

  Add variable:
  ```yaml
  # =============================================================================
  # OBSERVABILITY CONFIGURATION - Optional
  # =============================================================================

  # -- Enable Hubble UI via HTTPRoute
  #    (OPTIONAL) / (DEFAULT: false)
  hubble_ui_enabled: true
  ```

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **Hubble Relay pod running**
  ```bash
  kubectl get pods -n kube-system -l k8s-app=hubble-relay
  # Expected: Running, 1/1 ready
  ```

- [ ] **Hubble UI pod running** (if enabled)
  ```bash
  kubectl get pods -n kube-system -l k8s-app=hubble-ui
  # Expected: Running, 1/1 ready
  ```

- [ ] **ServiceMonitors created**
  ```bash
  kubectl get servicemonitor -n kube-system -l app.kubernetes.io/name=cilium
  # Expected: cilium-agent, hubble-relay
  ```

- [ ] **Prometheus scraping Hubble metrics**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus 9090:9090
  # Open: http://localhost:9090/targets
  # Look for: kube-system/cilium-agent, kube-system/hubble-relay
  ```

- [ ] **Metrics available**
  ```bash
  # Port-forward Hubble Relay
  kubectl port-forward -n kube-system svc/hubble-relay 4245:80
  curl http://localhost:4245/metrics | grep hubble_
  # Expected: hubble_dns_queries_total, hubble_drop_total, etc.
  ```

- [ ] **Hubble CLI works** (optional)
  ```bash
  kubectl port-forward -n kube-system svc/hubble-relay 4245:80
  hubble status
  hubble observe --last 10
  ```

---

## Phase 2: Add CoreDNS ServiceMonitor (Priority: P0)

### File Modifications

- [ ] **Create:** `templates/config/kubernetes/apps/kube-system/coredns/app/servicemonitor.yaml.j2`
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

- [ ] **Edit:** `templates/config/kubernetes/apps/kube-system/coredns/app/kustomization.yaml.j2`

  Add resource:
  ```yaml
  ---
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - ./helmrelease.yaml
    - ./ocirepository.yaml
    - ./servicemonitor.yaml
  ```

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **ServiceMonitor created**
  ```bash
  kubectl get servicemonitor -n kube-system coredns
  # Expected: NAME=coredns, AGE=<time>
  ```

- [ ] **Prometheus scraping CoreDNS**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus 9090:9090
  # Open: http://localhost:9090/targets
  # Look for: kube-system/coredns
  ```

- [ ] **Metrics available**
  ```bash
  # Test metrics endpoint
  kubectl exec -n kube-system <coredns-pod> -- wget -qO- localhost:9153/metrics | head -20
  # Expected: coredns_dns_requests_total, coredns_cache_hits_total, etc.
  ```

- [ ] **Query in Prometheus**
  ```promql
  # Prometheus UI: Query
  sum(rate(coredns_dns_requests_total[5m]))
  # Expected: Graph showing DNS request rate
  ```

---

## Phase 3: Enhance Envoy Gateway Metrics (Priority: P1)

### File Modifications

- [ ] **Edit:** `templates/config/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml.j2`

  Replace entire file:
  ```yaml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: PodMonitor
  metadata:
    name: envoy-proxy
    namespace: network
    labels:
      prometheus: kube-prometheus
  spec:
    jobLabel: envoy-proxy
    namespaceSelector:
      matchNames:
        - network
    podMetricsEndpoints:
      - port: metrics
        path: /stats/prometheus
        interval: 30s
        honorLabels: true
        relabelings:
          - sourceLabels: [__meta_kubernetes_pod_label_gateway_envoyproxy_io_owning_gateway_name]
            targetLabel: gateway
          - sourceLabels: [__meta_kubernetes_namespace]
            targetLabel: namespace
    selector:
      matchLabels:
        app.kubernetes.io/component: proxy
        app.kubernetes.io/name: envoy
  ```

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **PodMonitor updated**
  ```bash
  kubectl get podmonitor -n network envoy-proxy -o yaml | grep -A 10 relabelings
  # Expected: See gateway and namespace relabelings
  ```

- [ ] **Prometheus scraping with labels**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus 9090:9090
  # Open: http://localhost:9090/targets
  # Check: Labels include "gateway" and "namespace"
  ```

- [ ] **Query with labels**
  ```promql
  # Prometheus UI: Query
  sum by (gateway) (rate(envoy_http_downstream_rq_total[5m]))
  # Expected: Metrics labeled by gateway name (envoy-internal, envoy-external)
  ```

---

## Phase 4: Enable external-dns Metrics (Priority: P2)

### File Modifications

- [ ] **Edit:** `templates/config/kubernetes/apps/network/cloudflare-dns/app/helmrelease.yaml.j2`

  Add to values:
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

- [ ] **Edit:** `templates/config/kubernetes/apps/network/unifi-dns/app/helmrelease.yaml.j2` (if enabled)

  Add to values:
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

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **ServiceMonitors created**
  ```bash
  kubectl get servicemonitor -n network
  # Expected: cloudflare-dns, unifi-dns (if enabled)
  ```

- [ ] **Prometheus scraping external-dns**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus 9090:9090
  # Open: http://localhost:9090/targets
  # Look for: network/cloudflare-dns, network/unifi-dns
  ```

---

## Phase 5: Create PrometheusRules (Priority: P0)

### File Modifications

- [ ] **Create:** `templates/config/kubernetes/apps/monitoring/prometheus/app/rules-network.yaml.j2`

  Full content in [network-observability-implementation.md Phase 6](./network-observability-implementation.md#prometheus-recording-rules)

  Includes:
  - Recording rules for Envoy RED metrics
  - Recording rules for CoreDNS performance
  - Alert rules for infrastructure failures
  - Alert rules for performance degradation

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **PrometheusRule created**
  ```bash
  kubectl get prometheusrule -n monitoring network-infrastructure
  # Expected: NAME=network-infrastructure, AGE=<time>
  ```

- [ ] **Rules loaded in Prometheus**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus 9090:9090
  # Open: http://localhost:9090/rules
  # Look for: envoy_gateway_red, coredns_performance, coredns_alerts, etc.
  ```

- [ ] **Recording rules evaluating**
  ```promql
  # Prometheus UI: Query
  envoy:gateway:request_rate
  # Expected: Pre-calculated request rate per gateway
  ```

- [ ] **Alert rules configured**
  ```bash
  # Prometheus UI: Alerts
  # Expected: See alerts like CiliumAgentDown, CoreDNSHighErrorRate, etc.
  ```

---

## Phase 6: Import Grafana Dashboards (Priority: P1)

### Dashboard Download

- [ ] **Download official dashboards from Grafana.com:**
  - Cilium Agent: https://grafana.com/grafana/dashboards/16612
  - Hubble Network: https://grafana.com/grafana/dashboards/16613
  - CoreDNS: https://grafana.com/grafana/dashboards/5926
  - Envoy Global: https://grafana.com/grafana/dashboards/11021

### File Modifications

- [ ] **Create:** `templates/config/kubernetes/apps/monitoring/grafana/app/dashboards-network.yaml.j2`

  Create ConfigMaps for each dashboard:
  ```yaml
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
      # Paste dashboard JSON from Grafana.com

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
      # Paste dashboard JSON from Grafana.com

  # Repeat for CoreDNS and Envoy dashboards
  ```

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **ConfigMaps created**
  ```bash
  kubectl get configmap -n monitoring | grep grafana-dashboard
  # Expected: grafana-dashboard-cilium-agent, grafana-dashboard-hubble, etc.
  ```

- [ ] **Dashboards imported in Grafana**
  ```bash
  kubectl port-forward -n monitoring svc/grafana 3000:80
  # Open: http://localhost:3000
  # Navigate: Dashboards → Browse
  # Expected: See "Cilium Agent", "Hubble Network", "CoreDNS", "Envoy Global"
  ```

- [ ] **Dashboards show data**
  - Open each dashboard
  - Verify panels populate with metrics
  - Check time range selector works

---

## Phase 7: Configure BGP Monitoring (Optional, if BGP enabled)

### File Modifications

- [ ] **Edit:** `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`

  Add debug logging (only if BGP enabled):
  ```yaml
  values:
    # ... existing values ...

    #% if cilium_bgp_enabled %#
    debug:
      enabled: true
      verbose: "bgp-control-plane"
    #% endif %#
  ```

### Deploy

- [ ] **Run:** `task configure`
- [ ] **Run:** `task reconcile`

### Verification

- [ ] **BGP debug logs visible**
  ```bash
  kubectl -n kube-system logs ds/cilium | grep -i bgp
  # Expected: BGP peering logs, route advertisements
  ```

- [ ] **Manual BGP status check**
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- cilium bgp peers
  # Expected:
  # Node   Local AS  Peer AS  Peer Addr    State        Uptime
  # k8s-1  64514     64513    192.168.1.1  established  5h
  ```

- [ ] **BGP routes advertised**
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- cilium bgp routes advertised ipv4 unicast
  # Expected: LoadBalancer IPs advertised to peer
  ```

- [ ] **Log-based alert configured** (requires Loki)
  - Add LogQL alert for BGP peer down
  - Test alert fires when peer fails

---

## Final Verification

### Complete Health Check

- [ ] **All components running**
  ```bash
  kubectl get pods -n kube-system -l k8s-app=cilium
  kubectl get pods -n kube-system -l k8s-app=hubble-relay
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  kubectl get pods -n network -l app.kubernetes.io/name=envoy
  ```

- [ ] **All ServiceMonitors/PodMonitors created**
  ```bash
  kubectl get servicemonitor -A | grep -E 'cilium|coredns|external-dns'
  kubectl get podmonitor -A | grep envoy
  ```

- [ ] **Prometheus scraping all targets**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus 9090:9090
  # Open: http://localhost:9090/targets
  # Check: All targets UP (green)
  ```

- [ ] **Recording rules evaluating**
  ```promql
  # Test queries in Prometheus:
  envoy:gateway:request_rate
  envoy:gateway:error_rate
  coredns:error_rate
  coredns:cache_hit_rate
  ```

- [ ] **Alert rules configured**
  ```bash
  # Prometheus UI: Alerts
  # Expected: All rules listed (may be green/inactive if no issues)
  ```

- [ ] **Grafana dashboards populated**
  ```bash
  # Open each dashboard, verify data visible
  # Check time range selector works
  # Verify panels refresh
  ```

### Generate Test Traffic

- [ ] **Test Envoy metrics**
  ```bash
  # Generate HTTP traffic to gateway
  curl https://internal.example.com

  # Check metrics increment
  # Prometheus query:
  sum(rate(envoy_http_downstream_rq_total[1m]))
  ```

- [ ] **Test CoreDNS metrics**
  ```bash
  # Generate DNS queries
  kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local

  # Check metrics increment
  # Prometheus query:
  sum(rate(coredns_dns_requests_total[1m]))
  ```

- [ ] **Test Hubble flows**
  ```bash
  # Port-forward Hubble Relay
  kubectl port-forward -n kube-system svc/hubble-relay 4245:80

  # Observe flows
  hubble observe --last 20

  # Expected: See DNS, TCP flows from test traffic
  ```

### Alert Testing

- [ ] **Test critical alert** (optional, destructive)
  ```bash
  # Scale down CoreDNS to trigger alert
  kubectl scale deployment -n kube-system coredns --replicas=0

  # Wait 2 minutes
  # Check: Prometheus UI: Alerts
  # Expected: CoreDNSTotalOutage FIRING

  # Restore
  kubectl scale deployment -n kube-system coredns --replicas=2
  ```

---

## Troubleshooting Quick Reference

### Issue: Hubble not collecting flows

- [ ] Check Hubble Relay pod: `kubectl get pods -n kube-system -l k8s-app=hubble-relay`
- [ ] Check Hubble Relay logs: `kubectl logs -n kube-system deployment/hubble-relay`
- [ ] Test gRPC connection: `hubble status` (requires port-forward)

### Issue: Envoy metrics missing

- [ ] Check PodMonitor: `kubectl get podmonitor -n network envoy-proxy -o yaml`
- [ ] Test metrics endpoint: `kubectl exec -n network <envoy-pod> -- wget -qO- localhost:19001/stats/prometheus | head`
- [ ] Check Prometheus targets: Port-forward and visit `/targets`

### Issue: CoreDNS metrics not scraped

- [ ] Check ServiceMonitor: `kubectl get servicemonitor -n kube-system coredns`
- [ ] Test metrics endpoint: `kubectl exec -n kube-system <coredns-pod> -- wget -qO- localhost:9153/metrics | head`
- [ ] Verify Prometheus plugin loaded: `kubectl get configmap -n kube-system coredns -o yaml | grep prometheus`

### Issue: PrometheusRules not evaluating

- [ ] Check rule syntax: `kubectl describe prometheusrule -n monitoring network-infrastructure`
- [ ] Check Prometheus logs: `kubectl logs -n monitoring prometheus-<pod> | grep -i error`
- [ ] Verify label selector matches Prometheus: `kubectl get prometheus -o yaml | grep ruleSelector`

### Issue: Grafana dashboards missing

- [ ] Check ConfigMaps: `kubectl get configmap -n monitoring | grep grafana-dashboard`
- [ ] Verify label: `kubectl get configmap <dashboard-name> -o yaml | grep grafana_dashboard`
- [ ] Check Grafana sidecar logs: `kubectl logs -n monitoring deployment/grafana -c grafana-sc-dashboard`

---

## Success Criteria

You have successfully implemented network observability when:

1. **Hubble provides network flow visibility**
   - Can observe pod-to-pod communication
   - Can see DNS queries and responses
   - Network policy drops are visible

2. **CoreDNS metrics available**
   - Query rate tracked
   - Error rate calculated
   - Cache hit rate monitored

3. **Envoy Gateway metrics enhanced**
   - RED metrics (Rate, Errors, Duration) available
   - Backend health visible
   - Metrics labeled by gateway name

4. **Prometheus scraping all targets**
   - All ServiceMonitors/PodMonitors discovered
   - Targets show UP in /targets page
   - No scrape errors

5. **Recording rules pre-calculate key metrics**
   - envoy:gateway:* metrics available
   - coredns:* metrics available
   - Queries fast and efficient

6. **Alerts configured and routing**
   - Critical alerts would page (if Alertmanager configured)
   - Warning alerts would notify (if Slack configured)
   - Test alerts fire correctly

7. **Grafana dashboards show infrastructure health**
   - Network flow visualization
   - DNS performance trends
   - Gateway latency and errors
   - Backend health status

8. **BGP monitoring operational** (if enabled)
   - Peer status visible via CLI
   - Logs captured for alerting
   - Manual verification documented

---

## Next Steps After Implementation

1. **Establish baselines**
   - Record normal request rates, error rates, latencies
   - Document expected DNS query patterns
   - Note typical network policy drop rates

2. **Tune alert thresholds**
   - Adjust error rate thresholds based on baseline
   - Fine-tune latency alerts for your workloads
   - Reduce alert noise by increasing "for" duration

3. **Configure Alertmanager routing**
   - Set up PagerDuty integration for critical alerts
   - Configure Slack webhook for warnings
   - Route info alerts to ticketing system

4. **Create runbooks**
   - Document response procedures for each alert
   - Link alerts to troubleshooting guides
   - Include escalation paths

5. **Schedule periodic reviews**
   - Weekly: Review alert accuracy (false positives?)
   - Monthly: Check dashboard relevance
   - Quarterly: Validate baseline metrics still accurate

---

## Reference Documentation

- [Network Observability Implementation](./network-observability-implementation.md) - Full implementation guide
- [Network Observability Summary](./network-observability-summary.md) - Executive summary
- [Network Observability Diagrams](./network-observability-diagram.md) - Architecture diagrams
- [Cilium Networking Guide](../ai-context/cilium-networking.md) - Cilium architecture
- [Envoy Gateway Observability](./envoy-gateway-observability-security.md) - Access logging and tracing
- [k8s-at-home Patterns](./k8s-at-home-patterns-implementation.md) - Monitoring stack deployment

---

## Completion Sign-off

- [ ] **All phases implemented**
- [ ] **All verification steps passed**
- [ ] **Test traffic generated successfully**
- [ ] **Dashboards showing data**
- [ ] **Alerts configured and tested**
- [ ] **Documentation updated with cluster-specific details**
- [ ] **Team trained on new dashboards and alerts**
- [ ] **Runbooks created for critical alerts**

**Implementation completed by:** ________________
**Date:** ________________
**Review scheduled for:** ________________
