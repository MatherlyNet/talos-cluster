# Observability Stack Implementation Guide

> **Created:** 2026-01-03
> **Updated:** 2026-01-04 - Added httpV2:exemplars conditional for Tempo trace linking
> **Status:** Fully Implemented
> **Target:** Infrastructure Foundation Monitoring
> **Stack:** VictoriaMetrics + Loki + Grafana (Unified Platform)

## Overview

This guide provides comprehensive implementation instructions for deploying a **unified, cohesive** observability platform for your Talos Linux Kubernetes cluster. The observability stack provides full visibility into the infrastructure foundation that applications will build upon.

### Design Principles

> **CRITICAL:** This is a UNIFIED platform - each component has ONE source of truth to prevent overlaps, conflicts, and duplicate resource usage.

| Principle | Implementation |
| --------- | -------------- |
| **Single Grafana** | Deployed by VictoriaMetrics stack only |
| **Single AlertManager** | VMAlertManager from VictoriaMetrics stack |
| **Single node-exporter** | Deployed by VictoriaMetrics stack only |
| **Single kube-state-metrics** | Deployed by VictoriaMetrics stack only |
| **Prometheus CRD Compatible** | VictoriaMetrics converts existing ServiceMonitors/PodMonitors |
| **No Duplicate Metrics** | Choose ONE metrics backend (VictoriaMetrics recommended) |

### Component Ownership Matrix

| Component | Deployed By | DO NOT Deploy From |
| --------- | ----------- | ------------------ |
| **Grafana** | `victoria-metrics-k8s-stack` | loki chart, standalone |
| **VMAlertManager** | `victoria-metrics-k8s-stack` | standalone AlertManager |
| **node-exporter** | `victoria-metrics-k8s-stack` | standalone |
| **kube-state-metrics** | `victoria-metrics-k8s-stack` | standalone |
| **VictoriaMetrics** | `victoria-metrics-k8s-stack` | - |
| **Loki** | `loki` chart (grafana disabled) | - |
| **Alloy** | `alloy` chart | promtail (deprecated), otel-collector standalone |
| **Hubble** | `cilium` chart | standalone |
| **Tempo** | `tempo` chart | standalone otel-collector |

### Current State

| Component | Status | Notes |
| --------- | ------ | ----- |
| **Prometheus Operator CRDs** | ✅ Installed | `00-crds.yaml.j2` v80.10.0 |
| **Cilium ServiceMonitor** | ✅ Configured | Metrics scraping enabled |
| **Envoy Gateway PodMonitor** | ✅ Configured | `/stats/prometheus` scraping |
| **VictoriaMetrics Stack** | ✅ Implemented | `monitoring/victoria-metrics/` templates |
| **Grafana + Dashboards** | ✅ Implemented | Embedded in VictoriaMetrics HelmRelease |
| **Hubble** | ✅ Implemented | Conditional in `cilium/app/helmrelease.yaml.j2` |
| **Log Aggregation (Loki)** | ✅ Implemented | `monitoring/loki/` templates |
| **Alloy Collector** | ✅ Implemented | `monitoring/alloy/` templates |
| **Distributed Tracing (Tempo)** | ✅ Implemented | `monitoring/tempo/` templates |
| **PrometheusRule Alerts** | ✅ Implemented | `victoria-metrics/app/prometheusrule.yaml.j2` |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              VISUALIZATION LAYER                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                           Grafana                                            ││
│  │  • Infrastructure Dashboards (dotdc collection)                              ││
│  │  • Cilium/Hubble Network Visibility                                          ││
│  │  • Envoy Gateway RED Metrics                                                 ││
│  │  • Flux GitOps Status                                                        ││
│  │  • Log Exploration (Loki)                                                    ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────┬─────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│  VictoriaMetrics  │   │       Loki        │   │   AlertManager    │
│  (or Prometheus)  │   │  (Log Storage)    │   │  (Alert Routing)  │
│  • 7d retention   │   │  • R2 backend     │   │  • Slack          │
│  • 50Gi storage   │   │  • Monolithic     │   │  • PagerDuty      │
└─────────┬─────────┘   └─────────┬─────────┘   └─────────┬─────────┘
          │ Scraping              │ Collection            │ Alerts
          ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DATA COLLECTION LAYER                                  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐    │
│  │   Node     │ │  Kubelet   │ │   etcd     │ │  Cilium    │ │   Envoy    │    │
│  │  Exporter  │ │  /metrics  │ │  (ctrl)    │ │  +Hubble   │ │  Gateway   │    │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘    │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐    │
│  │  CoreDNS   │ │ kube-state │ │ cert-mgr   │ │   Flux     │ │   Alloy    │    │
│  │            │ │  -metrics  │ │            │ │            │ │  (logs)    │    │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Metrics Stack Selection

### Comparison: VictoriaMetrics vs kube-prometheus-stack

| Factor | VictoriaMetrics | kube-prometheus-stack |
| ------ | --------------- | --------------------- |
| **Memory** | ~200-400MB | ~2-4GB |
| **CPU** | ~100-200m | ~500m+ |
| **Disk Compression** | 7x better | Standard |
| **PromQL Compatibility** | Full | Native |
| **Long-term Storage** | Built-in | Requires Thanos/Cortex |
| **NFS Support** | Yes | No |
| **Community Dashboards** | Compatible | Native |
| **Best For** | Homelabs, resource-constrained | Large clusters, extensive dashboards |

**Recommendation:** VictoriaMetrics for homelab infrastructure

### Helm Chart Versions (January 2026)

| Chart | Registry | Version | OCI Support |
| ----- | -------- | ------- | ----------- |
| victoria-metrics-k8s-stack | `oci://ghcr.io/victoriametrics/helm-charts` | **0.45.0** | ✅ Yes |
| kube-prometheus-stack | `oci://ghcr.io/prometheus-community/charts` | **80.10.0** | ✅ Yes |
| loki | `oci://ghcr.io/grafana/helm-charts` | **6.49.0** | ✅ Yes |
| alloy | `https://grafana.github.io/helm-charts` | **1.1.2** | ❌ No |
| tempo | `https://grafana.github.io/helm-charts` | **1.24.1** | ❌ No |

> **Note:** Grafana's Tempo and Alloy charts do not have OCI registry support yet ([GitHub Issue #3068](https://github.com/grafana/helm-charts/issues/3068)). Use HelmRepository instead of OCIRepository for these charts.

---

## Part 2: Community Grafana Dashboards Catalog

### GitHub Repositories

| Repository | Description | Stars | Best For |
| ---------- | ----------- | ----- | -------- |
| [dotdc/grafana-dashboards-kubernetes](https://github.com/dotdc/grafana-dashboards-kubernetes) | Modern K8s dashboards, kube-prometheus-stack compatible | 2.5k+ | **Recommended** - Infrastructure overview |
| [onzack/grafana-dashboards](https://github.com/onzack/grafana-dashboards) | K8s/OpenShift dashboards from LGT Bank | 100+ | Enterprise patterns |
| [grafana/kubernetes-app](https://github.com/grafana/kubernetes-app) | Official Grafana K8s plugin | 400+ | Quick start |
| [fluxcd/flux2-monitoring-example](https://github.com/fluxcd/flux2-monitoring-example) | Flux GitOps monitoring | 200+ | GitOps visibility |
| [isovalent/cilium-grafana-observability-demo](https://github.com/isovalent/cilium-grafana-observability-demo) | Cilium/Hubble observability | 50+ | Network visibility |

### Essential Infrastructure Dashboards

#### Kubernetes Core (Priority: P0)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **18283** | [Kubernetes Dashboard](https://grafana.com/grafana/dashboards/18283-kubernetes-dashboard/) | Cluster overview with drill-down | grafana.com |
| **15757** | [Kubernetes / Views / Global](https://grafana.com/grafana/dashboards/15757-kubernetes-views-global/) | Global cluster view (dotdc) | dotdc |
| **15759** | [Kubernetes / Views / Nodes](https://grafana.com/grafana/dashboards/15759-kubernetes-views-nodes/) | Node-level metrics (dotdc) | dotdc |
| **15760** | [Kubernetes / Views / Pods](https://grafana.com/grafana/dashboards/15760-kubernetes-views-pods/) | Pod-level metrics (dotdc) | dotdc |
| **15758** | Kubernetes / Views / Namespaces | Namespace-level view (dotdc) | dotdc |

#### Node & Hardware (Priority: P0)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **1860** | [Node Exporter Full](https://grafana.com/grafana/dashboards/1860-node-exporter-full/) | Comprehensive node metrics | grafana.com |
| **22413** | [K8s Node Metrics Multi Clusters 2025](https://grafana.com/grafana/dashboards/22413-k8s-node-metrics-multi-clusters-node-exporter-prometheus-grafana11-2025-en/) | Multi-cluster node metrics (2025) | grafana.com |
| **3320** | [Kubernetes Node Exporter Full](https://grafana.com/grafana/dashboards/3320-kubernetes-node-exporter-full/) | Node exporter for K8s | grafana.com |

#### Control Plane (Priority: P0)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **15761** | Kubernetes / System / API Server | API Server metrics (dotdc) | dotdc |
| **20330** | [Kubernetes / ETCD](https://grafana.com/grafana/dashboards/20330-kubernetes-etcd/) | etcd cluster health | grafana.com |
| **15308** | [Etcd Cluster Overview](https://grafana.com/grafana/dashboards/15308-etcd-cluster-overview/) | etcd detailed metrics | grafana.com |
| **12381** | [K8S - ETCD Cluster Health](https://grafana.com/grafana/dashboards/12381-etcd-cluster-health/) | etcd health monitoring | grafana.com |

#### Network / CNI (Priority: P0)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **16611** | [Cilium v1.12 Agent](https://grafana.com/grafana/dashboards/16611-cilium-metrics/) | Cilium agent metrics (BPF, API, forwarding) | Isovalent |
| **16612** | [Cilium v1.12 Operator](https://grafana.com/grafana/dashboards/16612-cilium-operator/) | Cilium operator metrics (IPAM, nodes) | Isovalent |
| **16613** | [Cilium v1.12 Hubble](https://grafana.com/grafana/dashboards/16613-hubble/) | Hubble network flows | Isovalent |
| **18015** | [Cilium Policy Verdicts](https://grafana.com/grafana/dashboards/18015-cilium-policy-verdicts/) | Network policy enforcement tracking | Isovalent |
| **24056** | [Cilium Network Monitoring](https://grafana.com/grafana/dashboards/24056-cilium-network-monitoring/) | Endpoints, BPF maps, connectivity | Community |
| **23862** | [Cilium Flows - Hubble Observer](https://grafana.com/grafana/dashboards/23862-cilium-flows-hubble-observer/) | Flow visualization | ONZACK |

> **Note:** Dashboards 16611/16612/16613 are also auto-deployed by Cilium when `dashboards.enabled: true` via ConfigMaps. Grafana sidecar auto-discovers these for version-matched dashboards.

#### DNS (Priority: P0)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **15762** | [Kubernetes / System / CoreDNS](https://grafana.com/grafana/dashboards/15762-kubernetes-system-coredns/) | CoreDNS metrics (dotdc) | dotdc |
| **7279** | [CoreDNS](https://grafana.com/grafana/dashboards/7279-coredns/) | CoreDNS detailed | grafana.com |
| **12382** | [K8S CoreDNS](https://grafana.com/grafana/dashboards/12382-k8s-coredns/) | CoreDNS overview | grafana.com |

#### Ingress / Gateway (Priority: P1)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **24460** | [Envoy Gateway / Overview](https://grafana.com/grafana/dashboards/24460-envoy-gateway-overview/) | Envoy Gateway controller | envoy-mixin |
| **21329** | [Envoy Proxy](https://grafana.com/grafana/dashboards/21329-envoy-proxy/) | Envoy proxy metrics | grafana.com |
| **11022** | [Envoy Global](https://grafana.com/grafana/dashboards/11022-envoy-global/) | Envoy service-level | grafana.com |
| **11021** | [Envoy Clusters](https://grafana.com/grafana/dashboards/11021-envoy-clusters/) | Envoy cluster metrics | grafana.com |

#### GitOps / Flux (Priority: P1)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **16714** | [Flux2](https://grafana.com/grafana/dashboards/16714-flux2/) | Flux controller metrics | grafana.com |
| - | Flux Cluster Stats | Flux sources/reconcilers | [flux2-monitoring-example](https://github.com/fluxcd/flux2-monitoring-example) |
| - | Flux Control Plane | Flux component stats | [flux2-monitoring-example](https://github.com/fluxcd/flux2-monitoring-example) |

#### Certificates (Priority: P1)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **11001** | [cert-manager](https://grafana.com/grafana/dashboards/11001-cert-manager/) | Certificate metrics | grafana.com |
| **22184** | [cert-manager2](https://grafana.com/grafana/dashboards/22184-cert-manager2/) | Updated cert-manager | grafana.com |

#### Log Aggregation (Priority: P1)

| Dashboard ID | Name | Purpose | Source |
| ------------ | ---- | ------- | ------ |
| **15141** | [Loki Kubernetes Logs](https://grafana.com/grafana/dashboards/15141-kubernetes-service-logs/) | K8s logs in Loki | grafana.com |
| **18494** | [Kubernetes Logs from Loki](https://grafana.com/grafana/dashboards/18494-kubernetes-logs-from-loki/) | Basic K8s log dashboard | grafana.com |
| **14055** | [Loki Stack Monitoring](https://grafana.com/grafana/dashboards/14055-loki-stack-monitoring-promtail-loki/) | Loki health monitoring | grafana.com |
| **14003** | [Loki v2 Events Dashboard](https://grafana.com/grafana/dashboards/14003-loki-v2-events-dashboard-for-kubernetes/) | K8s events in Loki | grafana.com |

---

## Part 3: Implementation

### Phase 1: Monitoring Stack (Priority: P0)

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/monitoring/victoria-metrics/app
# OR for kube-prometheus-stack:
mkdir -p templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app
```

#### Step 2: Create Namespace Template

**File:** `templates/config/kubernetes/apps/monitoring/namespace.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
#% endif %#
```

#### Step 3: Create Kustomization

**File:** `templates/config/kubernetes/apps/monitoring/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
#% if monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
  - ./victoria-metrics/ks.yaml
#% else %#
  - ./kube-prometheus-stack/ks.yaml
#% endif %#
#% if loki_enabled | default(false) %#
  - ./loki/ks.yaml
#% endif %#
#% endif %#
```

#### Step 4: VictoriaMetrics Templates (Recommended)

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/ks.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: victoria-metrics
  namespace: flux-system
spec:
  interval: 1h
  path: ./kubernetes/apps/monitoring/victoria-metrics/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  postBuild:
    substituteFrom:
      - kind: Secret
        name: cluster-secrets
  wait: true
  timeout: 15m
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: victoria-metrics-k8s-stack
  namespace: monitoring
spec:
  chartRef:
    kind: OCIRepository
    name: victoria-metrics-k8s-stack
  interval: 1h
  values:
    # VictoriaMetrics Single (lightweight)
    vmsingle:
      enabled: true
      spec:
        retentionPeriod: "#{ metrics_retention | default('7d') }#"
        storage:
          storageClassName: "#{ storage_class | default('local-path') }#"
          resources:
            requests:
              storage: "#{ metrics_storage_size | default('50Gi') }#"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            memory: 1Gi

    # VMAgent for scraping
    vmagent:
      enabled: true
      spec:
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            memory: 256Mi

    # Grafana
    grafana:
      enabled: true
      ingress:
        enabled: true
        ingressClassName: ""
        annotations:
          external-dns.alpha.kubernetes.io/target: "#{ cluster_gateway_addr }#"
        hosts:
          - "#{ grafana_subdomain | default('grafana') }#.${SECRET_DOMAIN}"
        tls:
          - secretName: ${SECRET_DOMAIN/./-}-production-tls
            hosts:
              - "#{ grafana_subdomain | default('grafana') }#.${SECRET_DOMAIN}"
      persistence:
        enabled: true
        size: 5Gi
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          memory: 512Mi
      # Dashboard provisioning
      dashboardProviders:
        dashboardproviders.yaml:
          apiVersion: 1
          providers:
            - name: infrastructure
              folder: Infrastructure
              type: file
              disableDeletion: false
              editable: true
              options:
                path: /var/lib/grafana/dashboards/infrastructure
            - name: network
              folder: Network
              type: file
              disableDeletion: false
              editable: true
              options:
                path: /var/lib/grafana/dashboards/network
            - name: gitops
              folder: GitOps
              type: file
              disableDeletion: false
              editable: true
              options:
                path: /var/lib/grafana/dashboards/gitops
      dashboards:
        infrastructure:
          # Kubernetes Core (dotdc collection)
          kubernetes-global:
            gnetId: 15757
            revision: 43
            datasource: VictoriaMetrics
          kubernetes-nodes:
            gnetId: 15759
            revision: 32
            datasource: VictoriaMetrics
          kubernetes-pods:
            gnetId: 15760
            revision: 36
            datasource: VictoriaMetrics
          # Node metrics
          node-exporter-full:
            gnetId: 1860
            revision: 37
            datasource: VictoriaMetrics
          # Control plane
          kubernetes-etcd:
            gnetId: 20330
            revision: 1
            datasource: VictoriaMetrics
          # CoreDNS
          kubernetes-coredns:
            gnetId: 15762
            revision: 18
            datasource: VictoriaMetrics
          # cert-manager
          cert-manager:
            gnetId: 11001
            revision: 1
            datasource: VictoriaMetrics
        network:
          # Cilium Agent (BPF operations, API latency, forwarding stats)
          cilium-agent:
            gnetId: 16611
            revision: 1
            datasource: VictoriaMetrics
          # Cilium Operator (IPAM, node management)
          cilium-operator:
            gnetId: 16612
            revision: 1
            datasource: VictoriaMetrics
          # Cilium Hubble (flows, drops, DNS, HTTP, TCP)
          cilium-hubble:
            gnetId: 16613
            revision: 1
            datasource: VictoriaMetrics
          # Cilium Network Policy Verdicts (policy enforcement tracking)
          cilium-policy-verdicts:
            gnetId: 18015
            revision: 1
            datasource: VictoriaMetrics
          # Cilium Network Monitoring (endpoints, BPF maps, connectivity)
          cilium-network-monitoring:
            gnetId: 24056
            revision: 1
            datasource: VictoriaMetrics
          # Envoy Gateway
          envoy-gateway:
            gnetId: 24460
            revision: 1
            datasource: VictoriaMetrics
          envoy-proxy:
            gnetId: 21329
            revision: 1
            datasource: VictoriaMetrics
        gitops:
          flux2:
            gnetId: 16714
            revision: 1
            datasource: VictoriaMetrics
      # =========================================================================
      # COHESION: Additional datasources for unified observability
      # =========================================================================
      # Loki datasource enables log queries from the same Grafana instance
      additionalDataSources:
        #% if loki_enabled | default(false) %#
        - name: Loki
          type: loki
          url: http://loki:3100
          access: proxy
          isDefault: false
          jsonData:
            maxLines: 1000
        #% endif %#

    # AlertManager
    alertmanager:
      enabled: true
      spec:
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            memory: 128Mi
      config:
        global:
          resolve_timeout: 5m
        route:
          group_by: ['alertname', 'namespace', 'severity']
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 12h
          receiver: 'null'
          routes:
            - match:
                alertname: Watchdog
              receiver: 'null'
            - match:
                severity: critical
              receiver: 'null'  # Replace with actual receiver
        receivers:
          - name: 'null'
        # Uncomment and configure for actual alerts:
        # - name: 'slack'
        #   slack_configs:
        #     - api_url: '${SLACK_WEBHOOK_URL}'
        #       channel: '#alerts'
        #       send_resolved: true

    # Node Exporter
    prometheus-node-exporter:
      enabled: true
      resources:
        requests:
          cpu: 20m
          memory: 32Mi
        limits:
          memory: 64Mi

    # kube-state-metrics
    kube-state-metrics:
      enabled: true
      resources:
        requests:
          cpu: 20m
          memory: 64Mi
        limits:
          memory: 128Mi

    # kubelet scraping
    kubelet:
      enabled: true
      spec:
        # For Talos Linux
        metricRelabelConfigs:
          - action: labeldrop
            regex: (uid)
          - action: labeldrop
            regex: (id|name)
          - action: drop
            source_labels: ["__name__"]
            regex: (rest_client_request_duration_seconds_bucket|rest_client_request_duration_seconds_sum|rest_client_request_duration_seconds_count)

    # etcd monitoring (Talos requires explicit endpoints)
    kubeEtcd:
      enabled: true
      # Uncomment and add control plane IPs from nodes.yaml
      # endpoints:
      #   - 192.168.1.10
      #   - 192.168.1.11
      #   - 192.168.1.12

    # API Server
    kubeApiServer:
      enabled: true

    # Controller Manager
    kubeControllerManager:
      enabled: true

    # Scheduler
    kubeScheduler:
      enabled: true
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/ocirepository.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: victoria-metrics-k8s-stack
  namespace: monitoring
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: "0.45.0"
  url: oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./ocirepository.yaml
  - ./helmrelease.yaml
#% endif %#
```

### Phase 2: Enable Hubble for Network Visibility

Update the existing Cilium HelmRelease to enable Hubble:

**Edit:** `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`

Add or update the Hubble section:

```yaml
    # Hubble - Network Observability
    hubble:
      enabled: #{ hubble_enabled | default(false) | lower }#
      relay:
        enabled: #{ hubble_enabled | default(false) | lower }#
        replicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            memory: 128Mi
      ui:
        enabled: #{ hubble_ui_enabled | default(false) | lower }#
        replicas: 1
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
#% if tracing_enabled | default(false) %#
          #| L7 HTTP metrics with exemplars for Tempo trace linking |#
          - httpV2:exemplars=true;labelsContext=source_namespace,source_workload,destination_namespace,destination_workload
#% endif %#
        enableOpenMetrics: true
        serviceMonitor:
          enabled: #{ hubble_enabled | default(false) | lower }#
        dashboards:
          enabled: #{ hubble_enabled | default(false) | lower }#
          namespace: monitoring
```

> **Note:** The `httpV2:exemplars=true` metric is conditionally enabled when `tracing_enabled: true` to support trace linking from Hubble HTTP metrics to Tempo distributed traces.

### Phase 3: Log Aggregation with Loki

**File:** `templates/config/kubernetes/apps/monitoring/loki/ks.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and loki_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: loki
  namespace: flux-system
spec:
  dependsOn:
    - name: victoria-metrics
  interval: 1h
  path: ./kubernetes/apps/monitoring/loki/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  postBuild:
    substituteFrom:
      - kind: Secret
        name: cluster-secrets
  wait: true
  timeout: 10m
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/loki/app/helmrelease.yaml.j2`

> **CRITICAL COHESION:** Grafana is disabled here - it's deployed by VictoriaMetrics stack only.

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and loki_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: loki
  namespace: monitoring
spec:
  chartRef:
    kind: OCIRepository
    name: loki
  interval: 1h
  values:
    deploymentMode: SingleBinary
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
      schemaConfig:
        configs:
          - from: 2024-01-01
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h
      storage:
        type: filesystem
      limits_config:
        retention_period: 7d
        ingestion_rate_mb: 10
        ingestion_burst_size_mb: 20
    singleBinary:
      replicas: 1
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          memory: 512Mi
      persistence:
        enabled: true
        size: 50Gi
    gateway:
      enabled: false
    # =========================================================================
    # COHESION: Disable components deployed by victoria-metrics-k8s-stack
    # =========================================================================
    # Grafana is deployed by VictoriaMetrics stack - DO NOT enable here
    grafana:
      enabled: false
    # Promtail is deprecated - use Alloy instead
    promtail:
      enabled: false
    # Chunk cache
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
    # Monitoring - ServiceMonitor for VictoriaMetrics to scrape
    monitoring:
      dashboards:
        enabled: true
        namespace: monitoring  # Same namespace as Grafana
      serviceMonitor:
        enabled: true
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/loki/app/ocirepository.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and loki_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: loki
  namespace: monitoring
spec:
  interval: 1h
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: "6.49.0"
  url: oci://ghcr.io/grafana/helm-charts/loki
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/loki/app/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and loki_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./ocirepository.yaml
  - ./helmrelease.yaml
#% endif %#
```

### Phase 4: Alloy for Logs AND Traces Collection

> **Important Status Clarification:**
> - **Promtail**: Deprecated, enters LTS Feb 2025, **EOL March 2, 2026**
> - **Grafana Agent** (Static/Flow/Operator): Deprecated, **EOL November 1, 2025**
> - **Grafana Alloy**: **ACTIVE DEVELOPMENT** - This is Grafana's distribution of the OpenTelemetry Collector and the official replacement for both Promtail and Grafana Agent. Alloy serves as a unified collector for **logs** (to Loki), **metrics** (to VictoriaMetrics), and **traces** (to Tempo).
>
> **Note:** Alloy's Helm chart does not support OCI registry ([GitHub Issue #3068](https://github.com/grafana/helm-charts/issues/3068)). Use HelmRepository instead.

**File:** `templates/config/kubernetes/apps/monitoring/alloy/app/helmrepository.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: grafana
  namespace: monitoring
spec:
  interval: 1h
  url: https://grafana.github.io/helm-charts
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/alloy/app/helmrelease.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: alloy
  namespace: monitoring
spec:
  chart:
    spec:
      chart: alloy
      version: "1.1.2"
      sourceRef:
        kind: HelmRepository
        name: grafana
  interval: 1h
  values:
    alloy:
      configMap:
        content: |
          // =========================================================================
          // LOGS PIPELINE: Kubernetes pods → Loki
          // =========================================================================
          #% if loki_enabled | default(false) %#
          loki.source.kubernetes "pods" {
            targets    = discovery.kubernetes.pods.targets
            forward_to = [loki.write.default.receiver]
          }

          discovery.kubernetes "pods" {
            role = "pod"
          }

          loki.write "default" {
            endpoint {
              url = "http://loki:3100/loki/api/v1/push"
            }
          }
          #% endif %#

          // =========================================================================
          // TRACES PIPELINE: OTLP → Tempo (when tracing enabled)
          // =========================================================================
          #% if tracing_enabled | default(false) %#
          // Receive traces via OTLP (from Envoy Gateway, applications, etc.)
          otelcol.receiver.otlp "default" {
            grpc {
              endpoint = "0.0.0.0:4317"
            }
            http {
              endpoint = "0.0.0.0:4318"
            }
            output {
              traces = [otelcol.processor.batch.default.input]
            }
          }

          // Batch processor for efficiency
          otelcol.processor.batch "default" {
            output {
              traces = [otelcol.exporter.otlp.tempo.input]
            }
          }

          // Export to Tempo
          otelcol.exporter.otlp "tempo" {
            client {
              endpoint = "tempo:4317"
              tls {
                insecure = true
              }
            }
          }
          #% endif %#
    controller:
      type: daemonset
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          memory: 128Mi
    # Service for receiving OTLP traces
    #% if tracing_enabled | default(false) %#
    service:
      enabled: true
    #% endif %#
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/alloy/app/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
#% endif %#
```

### Phase 5: Tempo for Distributed Tracing

> **Purpose:** Store and query distributed traces from Envoy Gateway and applications.
> Tempo uses object storage (filesystem for homelab) and integrates natively with Grafana.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│                    DISTRIBUTED TRACING                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    OTLP/gRPC    ┌──────────────┐              │
│  │ Envoy Gateway│ ──────────────► │    Alloy     │              │
│  │  (traces)    │    :4317        │  (collector) │              │
│  └──────────────┘                 └──────┬───────┘              │
│                                          │                       │
│  ┌──────────────┐    OTLP/gRPC          │  OTLP/gRPC            │
│  │ Applications │ ──────────────────────┤  :4317                │
│  │  (optional)  │    :4317              ▼                       │
│  └──────────────┘                 ┌──────────────┐              │
│                                   │    Tempo     │              │
│                                   │  (storage)   │              │
│                                   └──────┬───────┘              │
│                                          │                       │
│                                          ▼                       │
│                                   ┌──────────────┐              │
│                                   │   Grafana    │              │
│                                   │ (Tempo DS)   │              │
│                                   └──────────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

> **Note:** Tempo's Helm chart does not support OCI registry ([GitHub Issue #3068](https://github.com/grafana/helm-charts/issues/3068)). Use the HelmRepository created in Phase 4 (Alloy) which points to `https://grafana.github.io/helm-charts`.

**File:** `templates/config/kubernetes/apps/monitoring/tempo/app/helmrelease.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and tracing_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tempo
  namespace: monitoring
spec:
  chart:
    spec:
      chart: tempo
      version: "1.24.1"  # APP VERSION 2.9.0
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: monitoring
  interval: 1h
  timeout: 10m
  values:
    # ==========================================================================
    # TEMPO SINGLE BINARY MODE (Recommended for homelab)
    # ==========================================================================
    # For production/scale: use tempo-distributed chart instead
    tempo:
      # Server configuration
      server:
        http_listen_port: 3200
        grpc_listen_port: 9095

      # Storage configuration (filesystem for homelab)
      storage:
        trace:
          backend: local
          local:
            path: /var/tempo/traces
          wal:
            path: /var/tempo/wal

      # Retention
      compactor:
        compaction:
          block_retention: 72h  # 3 days trace retention

      # Distributor - receive traces
      distributor:
        receivers:
          otlp:
            protocols:
              grpc:
                endpoint: "0.0.0.0:4317"
              http:
                endpoint: "0.0.0.0:4318"
          # Zipkin receiver for Envoy Gateway (alternative to OTLP)
          zipkin:
            endpoint: "0.0.0.0:9411"

      # Query frontend
      query_frontend:
        search:
          max_duration: 0  # No limit

      # Metrics generation from traces
      metrics_generator:
        enabled: true
        registry:
          external_labels:
            source: tempo
            cluster: #{ cluster_name | default('matherlynet') }#
        storage:
          path: /var/tempo/metrics-generator/wal
          remote_write:
            - url: http://vmsingle-victoria-metrics-k8s-stack:8429/api/v1/write
              send_exemplars: true

    # Persistence
    persistence:
      enabled: true
      size: 10Gi

    # Resources (homelab-appropriate)
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 1Gi

    # ServiceMonitor for VictoriaMetrics to scrape Tempo metrics
    metrics:
      enabled: true
      serviceMonitor:
        enabled: true
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/tempo/app/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and tracing_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/tempo/ks.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and tracing_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tempo
  namespace: flux-system
spec:
  targetNamespace: monitoring
  commonMetadata:
    labels:
      app.kubernetes.io/name: tempo
  interval: 1h
  retryInterval: 1m
  timeout: 10m
  path: ./kubernetes/apps/monitoring/tempo/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: true
  dependsOn:
    - name: victoria-metrics-k8s-stack  # Grafana and VictoriaMetrics must be ready
#% endif %#
```

### Phase 6: Grafana Tempo Datasource

Add Tempo datasource to VictoriaMetrics Grafana (in Phase 1 HelmRelease values):

```yaml
# Add to victoria-metrics-k8s-stack HelmRelease values
grafana:
  additionalDataSources:
    #% if loki_enabled | default(false) %#
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
      isDefault: false
      jsonData:
        maxLines: 1000
    #% endif %#
    #% if tracing_enabled | default(false) %#
    - name: Tempo
      type: tempo
      url: http://tempo:3200
      access: proxy
      isDefault: false
      jsonData:
        tracesToLogs:
          datasourceUid: loki
          tags: ['namespace', 'pod']
          mappedTags: [{ key: 'service.name', value: 'service' }]
          mapTagNamesEnabled: true
          filterByTraceID: true
          filterBySpanID: true
        tracesToMetrics:
          datasourceUid: VictoriaMetrics
          tags: [{ key: 'service.name', value: 'service' }]
          queries:
            - name: 'Request Rate'
              query: 'sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))'
        serviceMap:
          datasourceUid: VictoriaMetrics
        nodeGraph:
          enabled: true
        search:
          hide: false
        lokiSearch:
          datasourceUid: loki
    #% endif %#
```

---

## Part 4: Configuration Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# OBSERVABILITY - Monitoring Stack
# =============================================================================

# -- Enable monitoring stack (Prometheus/VictoriaMetrics + Grafana + AlertManager)
#    (OPTIONAL) / (DEFAULT: false)
# monitoring_enabled: false

# -- Monitoring stack choice: "victoriametrics" or "prometheus"
#    VictoriaMetrics uses ~10x less memory, recommended for homelabs
#    (OPTIONAL) / (DEFAULT: "victoriametrics")
# monitoring_stack: "victoriametrics"

# -- Enable Hubble network observability (requires monitoring_enabled)
#    Provides network flow visibility via Cilium
#    (OPTIONAL) / (DEFAULT: false)
# hubble_enabled: false

# -- Enable Hubble UI web interface
#    (OPTIONAL) / (DEFAULT: false)
# hubble_ui_enabled: false

# -- Grafana subdomain (creates grafana.<cloudflare_domain>)
#    (OPTIONAL) / (DEFAULT: "grafana")
# grafana_subdomain: "grafana"

# -- Metrics retention period
#    (OPTIONAL) / (DEFAULT: "7d")
# metrics_retention: "7d"

# -- Metrics storage size
#    (OPTIONAL) / (DEFAULT: "50Gi")
# metrics_storage_size: "50Gi"

# -- Storage class for monitoring (uses proxmox-zfs if available)
#    (OPTIONAL) / (DEFAULT: "local-path")
# storage_class: "local-path"

# -- Enable log aggregation with Loki
#    (OPTIONAL) / (DEFAULT: false)
# loki_enabled: false

# =============================================================================
# OBSERVABILITY - Infrastructure Alerts
# =============================================================================

# -- Enable PrometheusRule infrastructure alerts
#    Creates alerting rules for: nodes, etcd, API server, Cilium, CoreDNS,
#    Envoy Gateway, certificates, Flux, and workloads
#    (OPTIONAL) / (DEFAULT: true)
# monitoring_alerts_enabled: true

# -- Node memory utilization threshold (percentage) for alert
#    (OPTIONAL) / (DEFAULT: 90)
# node_memory_threshold: 90

# -- Node CPU utilization threshold (percentage) for alert
#    (OPTIONAL) / (DEFAULT: 90)
# node_cpu_threshold: 90

# =============================================================================
# OBSERVABILITY - Distributed Tracing (Optional)
# =============================================================================

# -- Enable distributed tracing with Tempo
#    Requires monitoring_enabled: true
#    (OPTIONAL) / (DEFAULT: false)
# tracing_enabled: false

# -- Tracing sample rate (percentage, 1-100)
#    100 = trace all requests; 10 = trace 10% of requests
#    (OPTIONAL) / (DEFAULT: 10)
# tracing_sample_rate: 10

# -- Trace retention period
#    (OPTIONAL) / (DEFAULT: "72h")
# trace_retention: "72h"

# -- Trace storage size
#    (OPTIONAL) / (DEFAULT: "10Gi")
# trace_storage_size: "10Gi"
```

---

## Part 5: Critical Infrastructure Alerts

> **Status:** ✅ Implemented in `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/prometheusrule.yaml.j2`

The PrometheusRule is conditionally generated based on `monitoring_alerts_enabled` (default: `true`).

### Alert Categories

| Category | Alerts | Severity |
| -------- | ------ | -------- |
| **Node Health** | NodeDown, NodeMemoryHighUtilization, NodeCPUHighUtilization, NodeFilesystemSpaceFillingUp, NodeFilesystemAlmostOutOfSpace | critical/warning |
| **Control Plane** | KubeAPIDown, KubeAPILatencyHigh, KubeControllerManagerDown, KubeSchedulerDown | critical/warning |
| **etcd** | etcdMemberUnhealthy, etcdNoLeader, etcdHighCommitDurations, etcdHighFsyncDurations | critical/warning |
| **Cilium/Network** | CiliumAgentDown, CiliumEndpointNotReady, CiliumPolicyImportErrors | critical/warning |
| **CoreDNS** | CoreDNSDown, CoreDNSHighErrorRate, CoreDNSHighLatency | critical/warning |
| **Envoy Gateway** | EnvoyGatewayDown, EnvoyHighErrorRate, EnvoyHighLatency | critical/warning |
| **Certificates** | CertificateExpiringSoon (7d), CertificateExpiryCritical (24h), CertificateNotReady | critical/warning |
| **Flux/GitOps** | FluxReconciliationFailure, FluxSuspended, FluxSourceNotReady | warning/info |
| **Workloads** | KubePodCrashLooping, KubePodNotReady, KubeDeploymentReplicasMismatch | warning |
| **Storage** | PersistentVolumeFillingUp, PersistentVolumeAlmostFull | critical/warning |

### Customizable Thresholds

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `monitoring_alerts_enabled` | `true` | Enable/disable all infrastructure alerts |
| `node_memory_threshold` | `90` | Memory utilization % before alerting |
| `node_cpu_threshold` | `90` | CPU utilization % before alerting |

### Template Reference

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/prometheusrule.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: infrastructure-alerts
  namespace: monitoring
spec:
  groups:
    - name: infrastructure-critical
      rules:
        # Node Health
        - alert: NodeDown
          expr: up{job="node-exporter"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ $labels.instance }} is down"
            description: "Node exporter on {{ $labels.instance }} has been unreachable for 5 minutes."

        - alert: NodeMemoryHighUtilization
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ $labels.instance }} memory utilization above 90%"

        - alert: NodeFilesystemSpaceFillingUp
          expr: |
            (node_filesystem_avail_bytes / node_filesystem_size_bytes * 100 < 15)
            and predict_linear(node_filesystem_avail_bytes[6h], 4*60*60) < 0
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Filesystem on {{ $labels.instance }} predicted to run out of space"

        # Control Plane
        - alert: KubeAPIDown
          expr: absent(up{job="apiserver"} == 1)
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Kubernetes API server is unreachable"

        - alert: etcdMemberUnhealthy
          expr: etcd_server_health_success < 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "etcd cluster member unhealthy"

        # Network
        - alert: CiliumAgentDown
          expr: up{job="cilium-agent"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Cilium agent on {{ $labels.instance }} is down"

        - alert: CoreDNSDown
          expr: absent(up{job="coredns"} == 1)
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "CoreDNS is unreachable"

        - alert: CoreDNSHighErrorRate
          expr: |
            sum(rate(coredns_dns_responses_total{rcode=~"SERVFAIL|NXDOMAIN"}[5m]))
            / sum(rate(coredns_dns_responses_total[5m])) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "CoreDNS error rate above 5%"

        # Gateway
        - alert: EnvoyGatewayDown
          expr: absent(up{job="envoy-proxy"}) or up{job="envoy-proxy"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Envoy Gateway proxy is not running"

        - alert: EnvoyHighErrorRate
          expr: |
            sum(rate(envoy_http_downstream_rq_5xx[5m]))
            / sum(rate(envoy_http_downstream_rq_total[5m])) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Envoy Gateway error rate above 5%"

        # Certificates
        - alert: CertificateExpiringSoon
          expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Certificate {{ $labels.name }} expires in less than 7 days"

        # GitOps
        - alert: FluxReconciliationFailure
          expr: gotk_reconcile_condition{status="False",type="Ready"} == 1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Flux resource {{ $labels.name }} reconciliation failing"
#% endif %#
```

---

## Part 6: Resource Summary

### Total Resource Requirements

| Component | CPU Request | Memory Request | Storage |
| --------- | ----------- | -------------- | ------- |
| VictoriaMetrics Single | 100m | 256Mi | 50Gi |
| VMAgent | 50m | 128Mi | - |
| Grafana | 100m | 128Mi | 5Gi |
| AlertManager | 50m | 64Mi | 1Gi |
| Node Exporter (per node) | 20m | 32Mi | - |
| kube-state-metrics | 20m | 64Mi | - |
| Loki (optional) | 100m | 256Mi | 50Gi |
| Alloy (per node) | 50m | 64Mi | - |
| Hubble Relay | 50m | 64Mi | - |
| **Total (3 nodes, no Loki)** | ~400m | ~700Mi | ~56Gi |
| **Total (3 nodes, with Loki)** | ~600m | ~1.1Gi | ~106Gi |

---

## Part 7: Deployment

### Step 1: Enable in cluster.yaml

```yaml
monitoring_enabled: true
monitoring_stack: "victoriametrics"
hubble_enabled: true
grafana_subdomain: "grafana"
metrics_retention: "7d"
# loki_enabled: true  # Optional
```

### Step 2: Regenerate and Deploy

```bash
task configure
git add -A
git commit -m "feat: add observability stack with VictoriaMetrics and Grafana"
git push
task reconcile
```

### Step 3: Verify Deployment

```bash
# Check pods
kubectl -n monitoring get pods

# Check Grafana ingress
kubectl -n monitoring get ingress

# Access Grafana
# https://grafana.<your-domain>
# Default credentials: admin / prom-operator (change immediately)

# Verify metrics scraping
kubectl -n monitoring port-forward svc/vmsingle-victoria-metrics-k8s-stack 8428:8428
curl http://localhost:8428/api/v1/query?query=up

# Check Hubble (if enabled)
kubectl -n kube-system get pods -l k8s-app=hubble-relay
```

---

## Part 8: Cohesion Verification Checklist

After deployment, verify the stack is unified without duplications:

```bash
# =====================================================================
# STEP 1: Verify single Grafana instance
# =====================================================================
kubectl get pods -A -l app.kubernetes.io/name=grafana
# Expected: Only pods from victoria-metrics-k8s-stack in monitoring namespace

# =====================================================================
# STEP 2: Verify single node-exporter DaemonSet
# =====================================================================
kubectl get daemonset -A -l app.kubernetes.io/name=prometheus-node-exporter
# Expected: Only one DaemonSet in monitoring namespace

# =====================================================================
# STEP 3: Verify single kube-state-metrics
# =====================================================================
kubectl get deployment -A -l app.kubernetes.io/name=kube-state-metrics
# Expected: Only one Deployment in monitoring namespace

# =====================================================================
# STEP 4: Verify Loki is NOT deploying its own Grafana
# =====================================================================
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki-grafana
# Expected: No resources found (Grafana disabled in Loki chart)

# =====================================================================
# STEP 5: Verify Alloy is used instead of Promtail
# =====================================================================
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
# Expected: No resources found (Promtail deprecated, using Alloy)

kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy
# Expected: Alloy DaemonSet pods running

# =====================================================================
# STEP 6: Verify Grafana has all datasources configured
# =====================================================================
# Access Grafana UI -> Configuration -> Data Sources
# Expected: VictoriaMetrics (default) + Loki (if enabled)

# =====================================================================
# STEP 7: Verify no duplicate scrape targets
# =====================================================================
kubectl -n monitoring port-forward svc/vmagent-victoria-metrics-k8s-stack 8429:8429
curl http://localhost:8429/targets | grep -c "node-exporter"
# Expected: Number equals number of nodes (not doubled)
```

### Troubleshooting Duplicate Components

| Symptom | Cause | Resolution |
| ------- | ----- | ---------- |
| Two Grafana instances | Loki chart deploying Grafana | Set `grafana.enabled: false` in Loki HelmRelease |
| Double node metrics | Multiple node-exporter DaemonSets | Disable in non-primary chart |
| Duplicate alerts | Multiple AlertManagers | Use only VMAlertManager from VM stack |
| Promtail + Alloy running | Migration incomplete | Remove Promtail, keep only Alloy |

---

## References

### Related Project Guides
- [Envoy Gateway Observability & Security](../envoy-gateway-observability-security.md) - JSON access logging, JWT auth, tracing (extends this stack)
- [BGP/UniFi/Cilium Implementation](../bgp-unifi-cilium-implementation.md) - BGP networking with Hubble visibility

### GitHub Repositories
- [dotdc/grafana-dashboards-kubernetes](https://github.com/dotdc/grafana-dashboards-kubernetes) - Modern K8s dashboards
- [fluxcd/flux2-monitoring-example](https://github.com/fluxcd/flux2-monitoring-example) - Flux monitoring
- [isovalent/cilium-grafana-observability-demo](https://github.com/isovalent/cilium-grafana-observability-demo) - Cilium observability
- [prometheus-community/helm-charts](https://github.com/prometheus-community/helm-charts) - kube-prometheus-stack

### Documentation
- [VictoriaMetrics Helm Charts](https://victoriametrics.github.io/helm-charts/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Cilium Hubble Documentation](https://docs.cilium.io/en/stable/observability/hubble/)
- [Flux Monitoring](https://fluxcd.io/flux/monitoring/)
- [cert-manager Prometheus Metrics](https://cert-manager.io/docs/devops-tips/prometheus-metrics/)

### Grafana Dashboard Sources
- [Grafana Labs Dashboard Directory](https://grafana.com/grafana/dashboards/)
- [Isovalent Dashboards](https://grafana.com/orgs/isovalent/dashboards)
- [CoreDNS Mixin](https://monitoring.mixins.dev/coredns/)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-04 | **ADDED**: Conditional `httpV2:exemplars=true` Hubble metric for Tempo trace linking (enabled when `tracing_enabled: true`) |
| 2026-01-03 | **BUGFIX**: Fixed cilium-agent dashboard ID from 16612 (Operator) to 16611 (Agent) |
| 2026-01-03 | **ADDED**: Cilium Operator dashboard (16612) - properly labeled |
| 2026-01-03 | **ADDED**: Cilium Policy Verdicts dashboard (18015) for network policy monitoring |
| 2026-01-03 | **ADDED**: Cilium Network Monitoring dashboard (24056) for endpoints/BPF visibility |
| 2026-01-03 | **ADDED**: Grafana sidecar for auto-discovery of Cilium ConfigMap dashboards |
| 2026-01-03 | **ADDED**: Hubble `port-distribution` and `policy` metrics for enhanced visibility |
| 2026-01-03 | **IMPLEMENTED**: Added PrometheusRule infrastructure alerts with 30+ alerting rules across 10 categories |
| 2026-01-03 | **IMPLEMENTED**: Added conditional templating for alerts via `monitoring_alerts_enabled` variable |
| 2026-01-03 | **IMPLEMENTED**: Added customizable thresholds (`node_memory_threshold`, `node_cpu_threshold`) |
| 2026-01-03 | **STATUS**: Updated to "Fully Implemented" - all components now have templates |
| 2026-01-03 | **CORRECTED**: Replaced Bitnami Tempo chart with official Grafana Tempo chart (v1.24.1) using HelmRepository |
| 2026-01-03 | **CORRECTED**: Replaced non-existent Alloy OCI with HelmRepository (v1.1.2) |
| 2026-01-03 | **CORRECTED**: Updated chart versions table with accurate OCI support status |
| 2026-01-03 | **CORRECTED**: Clarified Alloy status - it is the ACTIVE replacement for Promtail/Grafana Agent, NOT deprecated |
| 2026-01-03 | **CORRECTED**: Added missing Loki OCIRepository and kustomization.yaml templates |
| 2026-01-03 | Added Tempo distributed tracing (Phase 5) with Alloy as unified collector |
| 2026-01-03 | Updated Alloy to handle both logs AND traces pipelines |
| 2026-01-03 | Added tracing configuration variables (tracing_enabled, tracing_sample_rate, etc.) |
| 2026-01-03 | Added cross-references to related project guides (Envoy, BGP) |
| 2026-01-03 | Added Loki datasource to Grafana for unified log/metric queries |
| 2026-01-03 | Added cohesion analysis and component ownership matrix |
| 2026-01-03 | Initial comprehensive observability stack guide |
