# Application Reference

> Detailed documentation for all included applications

## Application Index

| Namespace | Application | Purpose | Dependencies |
| ----------- | ------------- | --------- | -------------- |
| `kube-system` | [Cilium](#cilium) | CNI + Load Balancer | None (bootstrapped) |
| `kube-system` | [CoreDNS](#coredns) | Cluster DNS | Cilium |
| `kube-system` | [Spegel](#spegel) | P2P Image Distribution | Cilium |
| `kube-system` | [Metrics Server](#metrics-server) | Resource Metrics | Cilium |
| `kube-system` | [Reloader](#reloader) | ConfigMap/Secret Reload | Cilium |
| `kube-system` | [Talos CCM](#talos-ccm) | Node Lifecycle Management | Cilium |
| `kube-system` | [Talos Backup](#talos-backup) | Automated etcd Backups | Cilium (optional) |
| `system-upgrade` | [tuppr](#tuppr) | Automated Talos/K8s Upgrades | Flux |
| `flux-system` | [Flux Operator](#flux-operator) | Flux Installation | Cilium, CoreDNS |
| `flux-system` | [Flux Instance](#flux-instance) | GitOps Configuration | Flux Operator |
| `cert-manager` | [cert-manager](#cert-manager) | TLS Certificates | Flux |
| `network` | [Envoy Gateway](#envoy-gateway) | Gateway API Ingress | cert-manager |
| `network` | [cloudflare-dns](#cloudflare-dns) | Public DNS Records | Flux |
| `network` | [unifi-dns](#unifi-dns) | Internal DNS (UniFi) | Flux (optional) |
| `network` | [k8s-gateway](#k8s-gateway) | Split DNS Fallback | Flux (if no UniFi) |
| `network` | [Cloudflare Tunnel](#cloudflare-tunnel) | External Access | Flux |
| `monitoring` | [VictoriaMetrics](#victoriametrics) | Metrics + Grafana + AlertManager | Flux (optional) |
| `monitoring` | [kube-prometheus-stack](#kube-prometheus-stack) | Prometheus-based Metrics (alt) | Flux (optional) |
| `monitoring` | [Loki](#loki) | Log Aggregation | VictoriaMetrics (optional) |
| `monitoring` | [Alloy](#alloy) | Unified Telemetry Collector | Loki (optional) |
| `monitoring` | [Tempo](#tempo) | Distributed Tracing | VictoriaMetrics (optional) |
| `kube-system` | [Hubble](#hubble) | Network Observability (Cilium) | Cilium (optional) |
| `external-secrets` | [External Secrets](#external-secrets) | Secret sync from external providers | Flux (optional) |
| `default` | [Echo](#echo) | Test Application | Envoy Gateway |

---

## kube-system Namespace

### Cilium

**Purpose:** Container Network Interface (CNI) and kube-proxy replacement with eBPF.

**Template:** `templates/config/kubernetes/apps/kube-system/cilium/`

**Key Features:**
- Native routing (no overlay)
- L2 load balancer announcements (MetalLB replacement)
- kube-proxy replacement
- Optional BGP peering
- Optional CiliumNetworkPolicies (zero-trust networking)

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cluster_pod_cidr` | ipv4NativeRoutingCIDR |
| `cilium_loadbalancer_mode` | DSR or SNAT mode |
| `cilium_bgp_enabled` | Enable BGP control plane |
| `network_policies_enabled` | Enable CiliumNetworkPolicies |
| `network_policies_mode` | `audit` (observe) or `enforce` (block) |

**Helm Values Highlights:**
```yaml
kubeProxyReplacement: true
l2announcements:
  enabled: true
loadBalancer:
  algorithm: maglev
  mode: "dsr"  # or "snat"
routingMode: native
```

**Troubleshooting:**
```bash
cilium status
cilium connectivity test
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list

# Network policies (when enabled)
kubectl get cnp -A                    # List namespace policies
kubectl get ccnp -A                   # List cluster-wide policies
hubble observe --verdict DROPPED      # View blocked traffic
hubble observe --verdict AUDIT        # View audit events
```

---

### CoreDNS

**Purpose:** Cluster DNS server for service discovery.

**Template:** `templates/config/kubernetes/apps/kube-system/coredns/`

**Notes:**
- Replaces Talos-bundled CoreDNS
- Managed by Flux for consistent configuration

**Troubleshooting:**
```bash
kubectl -n kube-system logs deploy/coredns
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes
```

---

### Spegel

**Purpose:** Peer-to-peer container image distribution.

**Template:** `templates/config/kubernetes/apps/kube-system/spegel/`

**Condition:** Only enabled when `nodes | length > 1`

**Benefits:**
- Reduces external registry bandwidth
- Faster image pulls from peer nodes
- Works with any OCI registry

---

### Metrics Server

**Purpose:** Provides resource metrics for `kubectl top` and HPA.

**Template:** `templates/config/kubernetes/apps/kube-system/metrics-server/`

**Usage:**
```bash
kubectl top nodes
kubectl top pods -A
```

---

### Reloader

**Purpose:** Automatically restarts pods when ConfigMaps or Secrets change.

**Template:** `templates/config/kubernetes/apps/kube-system/reloader/`

**Usage:** Add annotation to deployment:
```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

---

### Talos CCM

**Purpose:** Talos Cloud Controller Manager for node lifecycle management.

**Template:** `templates/config/kubernetes/apps/kube-system/talos-ccm/`

**What it does:**
- Labels nodes with Talos-specific metadata
- Manages node lifecycle events
- Provides cloud provider integration for Talos

**Helm Values Highlights:**
```yaml
logVerbosityLevel: 2
useDaemonSet: true
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
    operator: Exists
```

**Troubleshooting:**
```bash
kubectl -n kube-system logs ds/talos-cloud-controller-manager
kubectl get nodes --show-labels | grep talos
```

---

### Talos Backup

**Purpose:** Automated etcd snapshots with S3 storage and Age encryption.

**Template:** `templates/config/kubernetes/apps/kube-system/talos-backup/`

**Condition:** Only enabled when `backup_s3_endpoint` AND `backup_s3_bucket` are defined in `cluster.yaml`

**Requirements:**
- S3-compatible storage (Cloudflare R2 recommended)
- Age public key for encryption (same as cluster SOPS key)
- Talos API access enabled via machine patch

**Configuration Variables:**

| Variable | Usage | Required |
| ---------- | ------- | -------- |
| `backup_s3_endpoint` | S3 endpoint URL | Yes |
| `backup_s3_bucket` | Bucket name | Yes |
| `backup_s3_access_key` | S3 access key | Yes |
| `backup_s3_secret_key` | S3 secret key | Yes |
| `backup_age_public_key` | Age encryption key | Yes |

**How it works:**
1. Runs as a CronJob in kube-system
2. Uses Talos API to create etcd snapshots
3. Encrypts snapshots with Age
4. Uploads to S3-compatible storage

**Troubleshooting:**
```bash
kubectl -n kube-system get cronjob talos-backup
kubectl -n kube-system logs job/talos-backup-<timestamp>
```

---

## system-upgrade Namespace

### tuppr

**Purpose:** Talos Upgrade Controller for automated OS and Kubernetes upgrades.

**Template:** `templates/config/kubernetes/apps/system-upgrade/tuppr/`

**What it does:**
- Manages Talos OS version upgrades via `TalosUpgrade` CRs
- Manages Kubernetes version upgrades via `KubernetesUpgrade` CRs
- Performs rolling upgrades with proper drain/cordon
- Integrates with Talos Image Factory for schematic-based images

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `talos_version` | Target Talos OS version | `1.12.0` |
| `kubernetes_version` | Target Kubernetes version | `1.35.0` |

**Custom Resources:**

```yaml
# TalosUpgrade - Manages Talos OS version
apiVersion: tuppr.io/v1alpha1
kind: TalosUpgrade
metadata:
  name: talos-upgrade
spec:
  version: "1.12.0"

# KubernetesUpgrade - Manages Kubernetes version
apiVersion: tuppr.io/v1alpha1
kind: KubernetesUpgrade
metadata:
  name: kubernetes-upgrade
spec:
  version: "1.35.0"
```

**Upgrade Workflow:**
1. Update `talos_version` or `kubernetes_version` in `cluster.yaml`
2. Run `task configure` to regenerate manifests
3. Commit and push to Git
4. tuppr detects CR changes and initiates rolling upgrade

**Troubleshooting:**
```bash
kubectl -n system-upgrade get talosupgrade
kubectl -n system-upgrade get kubernetesupgrade
kubectl -n system-upgrade logs deploy/tuppr
kubectl get nodes -o wide  # Check node versions
```

---

## flux-system Namespace

### Flux Operator

**Purpose:** Manages Flux installation and lifecycle.

**Template:** `templates/config/kubernetes/apps/flux-system/flux-operator/`

**What it does:**
- Installs Flux controllers
- Manages Flux CRDs
- Handles upgrades

---

### Flux Instance

**Purpose:** Configures Flux to sync from GitHub repository.

**Template:** `templates/config/kubernetes/apps/flux-system/flux-instance/`

**Components:**
- `GitRepository` - Points to your repo
- `Receiver` - Webhook for push events
- `HTTPRoute` - Exposes webhook externally

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `repository_name` | GitHub repo (owner/name) |
| `repository_branch` | Branch to track |
| `repository_visibility` | public/private |

**Secrets Required:**
- `github-deploy-key.sops.yaml` - SSH key for Git access
- `flux-instance` secret - Webhook token

---

## cert-manager Namespace

### cert-manager

**Purpose:** Automates TLS certificate management.

**Template:** `templates/config/kubernetes/apps/cert-manager/cert-manager/`

**Features:**
- Let's Encrypt ACME issuer
- Cloudflare DNS-01 challenge
- Wildcard certificate for domain

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cloudflare_domain` | Certificate domain |
| `cloudflare_token` | API token for DNS challenge |

**ClusterIssuer:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-token
              key: token
```

**Troubleshooting:**
```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl -n cert-manager logs deploy/cert-manager
```

---

## network Namespace

### Envoy Gateway

**Purpose:** Gateway API implementation for ingress traffic.

**Template:** `templates/config/kubernetes/apps/network/envoy-gateway/`

**Gateways Created:**

| Gateway | IP Variable | Purpose |
| --------- | ------------- | --------- |
| `envoy-internal` | `cluster_gateway_addr` | Private access |
| `envoy-external` | `cloudflare_gateway_addr` | Public access (via tunnel) |

**Usage - Creating HTTPRoute:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-namespace
spec:
  parentRefs:
    - name: envoy-internal  # or envoy-external
      namespace: network
  hostnames:
    - "myapp.example.com"
  rules:
    - backendRefs:
        - name: my-service
          port: 80
```

**TLS Certificate:**
- Wildcard certificate: `*.cloudflare_domain`
- Managed by cert-manager
- Shared across all routes

**Observability Features:**
- **JSON Access Logging**: Always enabled, logs to stdout for Alloy/Loki collection
- **Distributed Tracing**: Conditional on `tracing_enabled`, sends Zipkin spans to Tempo (port 9411)
- **Prometheus Metrics**: PodMonitor scrapes Envoy metrics for VictoriaMetrics

**Security Features (Optional):**
- **JWT SecurityPolicy**: Enabled when `oidc_issuer_url` and `oidc_jwks_uri` are set
- Targets HTTPRoutes with label `security: jwt-protected`
- Extracts claims to X-User-* headers for backend services

See `docs/guides/envoy-gateway-observability-security.md` for implementation details.

---

### cloudflare-dns

**Purpose:** Automatically manages public DNS records in Cloudflare.

**Template:** `templates/config/kubernetes/apps/network/cloudflare-dns/`

**How it works:**
1. Watches HTTPRoutes with `envoy-external` parent
2. Creates/updates Cloudflare DNS records
3. Points to `cloudflare_gateway_addr` (tunnel ingress)

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cloudflare_domain` | Zone to manage |
| `cloudflare_token` | API token |

---

### unifi-dns

**Purpose:** Automatically manages internal DNS records in UniFi Network controller.

**Template:** `templates/config/kubernetes/apps/network/unifi-dns/`

**Condition:** Only enabled when `unifi_host` AND `unifi_api_key` are defined in `cluster.yaml`

**How it works:**
1. Watches HTTPRoutes with `envoy-internal` parent
2. Creates/updates DNS records directly in UniFi controller
3. Points to `cluster_gateway_addr` (internal LoadBalancer IP)
4. Uses [external-dns-unifi-webhook](https://github.com/kashalls/external-dns-unifi-webhook) v0.8.0

**Requirements:**
- UniFi Network v9.0.0+ (for API key authentication)
- API key created in UniFi Admin → Control Plane → Integrations

**Configuration Variables:**

| Variable | Usage | Required |
| ---------- | ------- | -------- |
| `unifi_host` | Controller URL (e.g., `https://192.168.1.1`) | Yes |
| `unifi_api_key` | API key for authentication | Yes |
| `unifi_site` | Site identifier (default: `default`) | No |
| `unifi_external_controller` | `true` for Cloud Key/self-hosted | No |

**Advantages over k8s-gateway:**
- Native UniFi DNS integration (no split-DNS router config)
- Persistent records (survives cluster restarts)
- Visible in UniFi Dashboard

**Limitations:**
- No wildcard DNS support (UniFi uses dnsmasq)
- No duplicate CNAME records

**Reference:** See `docs/research/external-dns-unifi-integration.md` for detailed setup guide.

---

### k8s-gateway

**Purpose:** Split-horizon DNS for internal service discovery (fallback when UniFi not configured).

**Template:** `templates/config/kubernetes/apps/network/k8s-gateway/`

**Condition:** Only enabled when `unifi_host` OR `unifi_api_key` are NOT defined

**How it works:**
1. Runs as DNS server on `cluster_dns_gateway_addr`
2. Resolves `*.cloudflare_domain` to gateway IPs
3. Home DNS forwards domain queries here

**Configuration:**
```yaml
# In your home router/Pi-hole/AdGuard:
# Forward cloudflare_domain → cluster_dns_gateway_addr
```

**Note:** Consider migrating to [unifi-dns](#unifi-dns) for cleaner integration if using UniFi Network.

---

### Cloudflare Tunnel

**Purpose:** Secure external access without exposing ports.

**Template:** `templates/config/kubernetes/apps/network/cloudflare-tunnel/`

**How it works:**
1. `cloudflared` connects outbound to Cloudflare
2. Traffic flows: Internet → Cloudflare → Tunnel → `envoy-external`
3. No inbound ports required

**Required Files:**
- `cloudflare-tunnel.json` - Tunnel credentials

**Configuration Variables:**

| Variable | Usage |
| ---------- | ------- |
| `cloudflare_domain` | Tunnel hostname |
| `cloudflare_gateway_addr` | Ingress destination |

---

## monitoring Namespace

### VictoriaMetrics

**Purpose:** Full-stack metrics with Grafana, AlertManager, and infrastructure alerting (VictoriaMetrics is 10x more memory-efficient than Prometheus).

**Template:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/`

**Condition:** Only enabled when `monitoring_enabled: true` in `cluster.yaml`

**Components:**
- VictoriaMetrics Single (metrics storage)
- Grafana (visualization with pre-configured dashboards)
- AlertManager (alerting)
- VMAgent (metric collection)
- PrometheusRule (infrastructure alerts - auto-converted to VMRule)

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `monitoring_enabled` | Enable monitoring stack | `false` |
| `monitoring_stack` | Backend choice (`victoriametrics` or `prometheus`) | `victoriametrics` |
| `grafana_subdomain` | Grafana subdomain | `grafana` |
| `metrics_retention` | Retention period | `7d` |
| `metrics_storage_size` | PV size | `50Gi` |
| `storage_class` | Storage class | `local-path` |
| `monitoring_alerts_enabled` | Enable infrastructure alerts | `true` |
| `node_memory_threshold` | Memory % threshold for alerts | `90` |
| `node_cpu_threshold` | CPU % threshold for alerts | `90` |

**Infrastructure Alerts:**

When `monitoring_alerts_enabled: true` (default), a PrometheusRule with 30+ alerts is created covering:
- Node health (memory, CPU, disk, filesystem, network)
- Control Plane (API server, scheduler, controller-manager)
- etcd (membership, health, latency)
- Cilium (agent health, endpoint issues, policy errors)
- CoreDNS (health, query latency)
- Envoy Gateway (connection issues, config errors)
- Certificates (expiration warnings)
- Flux GitOps (reconciliation failures)
- Workloads (pod crashes, deployment issues)
- Storage (PV usage)

**Note:** VictoriaMetrics Operator auto-converts PrometheusRule to VMRule - no special labels required.

**Troubleshooting:**
```bash
flux get hr -n monitoring victoria-metrics-k8s-stack
kubectl -n monitoring get pods
kubectl -n monitoring port-forward svc/vmsingle-victoria-metrics-k8s-stack 8429:8429
# Visit http://localhost:8429 for VictoriaMetrics UI
kubectl -n monitoring port-forward svc/victoria-metrics-k8s-stack-grafana 3000:80
# Visit http://localhost:3000 for Grafana (admin/admin)
```

---

### kube-prometheus-stack

**Purpose:** Full-stack Prometheus monitoring with Grafana and AlertManager (alternative to VictoriaMetrics).

**Template:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/`

**Condition:** Only enabled when `monitoring_enabled: true` AND `monitoring_stack: "prometheus"` in `cluster.yaml`

**Components:**
- Prometheus Operator
- Prometheus Server (metrics storage)
- Grafana (visualization with pre-configured dashboards)
- AlertManager (alerting)
- Node Exporter (node metrics)
- kube-state-metrics (Kubernetes object metrics)
- Default PrometheusRules (30+ alerting rules)

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `monitoring_enabled` | Enable monitoring stack | `false` |
| `monitoring_stack` | Set to `prometheus` | `victoriametrics` |
| `grafana_subdomain` | Grafana subdomain | `grafana` |
| `metrics_retention` | Retention period | `7d` |
| `metrics_storage_size` | PV size | `50Gi` |
| `storage_class` | Storage class | `local-path` |

**Pre-configured Grafana Dashboards:**
- **Infrastructure:** Kubernetes Global, Nodes, Pods, etcd, CoreDNS, Node Exporter, cert-manager
- **Network:** Cilium Agent, Cilium Hubble, Envoy Gateway, Envoy Proxy
- **GitOps:** Flux2

**Integration with Loki/Tempo:**
When `loki_enabled` or `tracing_enabled` are set, Grafana automatically includes datasources for:
- Loki (log aggregation)
- Tempo (distributed tracing with traces-to-logs correlation)

**Troubleshooting:**
```bash
flux get hr -n monitoring kube-prometheus-stack
kubectl -n monitoring get pods
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090 for Prometheus UI
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# Visit http://localhost:3000 for Grafana (admin/prom-operator)
```

---

### Loki

**Purpose:** Log aggregation using SimpleScalable mode (homelab-appropriate).

**Template:** `templates/config/kubernetes/apps/monitoring/loki/`

**Condition:** Only enabled when `monitoring_enabled: true` AND `loki_enabled: true`

**Features:**
- SimpleScalable mode (read/write/backend separation)
- Filesystem storage (no object storage required)
- Grafana datasource auto-configured

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `loki_enabled` | Enable log aggregation | `false` |
| `logs_retention` | Retention period | `7d` |
| `logs_storage_size` | PV size | `50Gi` |

**Troubleshooting:**
```bash
flux get hr -n monitoring loki
kubectl -n monitoring get pods -l app.kubernetes.io/name=loki
kubectl -n monitoring logs -l app.kubernetes.io/name=loki-read
```

---

### Alloy

**Purpose:** Unified telemetry collector (replaces deprecated Promtail and Grafana Agent).

**Template:** `templates/config/kubernetes/apps/monitoring/alloy/`

**Condition:** Only enabled when `loki_enabled: true` (requires Loki as destination)

**Note:** Alloy uses HelmRepository (not OCI) as the Grafana Helm chart doesn't support OCI registry.

**Features:**
- Collects logs from all pods
- Discovers Kubernetes metadata
- Forwards to Loki

**Troubleshooting:**
```bash
flux get hr -n monitoring alloy
kubectl -n monitoring get pods -l app.kubernetes.io/name=alloy
kubectl -n monitoring logs ds/alloy
```

---

### Tempo

**Purpose:** Distributed tracing in single binary mode (homelab-appropriate).

**Template:** `templates/config/kubernetes/apps/monitoring/tempo/`

**Condition:** Only enabled when `monitoring_enabled: true` AND `tracing_enabled: true`

**Note:** Tempo uses HelmRepository (not OCI) as the Grafana Helm chart doesn't support OCI registry.

**Features:**
- OTLP gRPC/HTTP receivers (ports 4317/4318)
- Zipkin receiver (port 9411, for Envoy Gateway)
- Metrics generation (RED metrics from traces)
- Grafana datasource auto-configured

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `tracing_enabled` | Enable tracing | `false` |
| `tracing_sample_rate` | Sample percentage | `10` |
| `trace_retention` | Retention period | `72h` |
| `trace_storage_size` | PV size | `10Gi` |
| `cluster_name` | Cluster identifier | `matherlynet` |

**Troubleshooting:**
```bash
flux get hr -n monitoring tempo
kubectl -n monitoring get pods -l app.kubernetes.io/name=tempo
kubectl -n monitoring port-forward svc/tempo 3200:3200
# Visit http://localhost:3200 for Tempo API
```

---

### Hubble

**Purpose:** Network observability for Cilium with flow visibility.

**Template:** Integrated into `templates/config/kubernetes/apps/kube-system/cilium/app/helmrelease.yaml.j2`

**Condition:** Only enabled when `hubble_enabled: true` in `cluster.yaml`

**Components:**
- Hubble Relay (aggregates flows from all nodes)
- Hubble UI (optional, enabled with `hubble_ui_enabled: true`)
- Hubble metrics (exported to VictoriaMetrics when monitoring enabled)

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `hubble_enabled` | Enable Hubble | `false` |
| `hubble_ui_enabled` | Enable Hubble UI | `false` |

**Features:**
- Real-time network flow visibility
- DNS query tracking
- Drop reason analysis
- TCP/HTTP flow metrics

**Troubleshooting:**
```bash
hubble status
hubble observe --namespace default
hubble observe --verdict DROPPED
kubectl -n kube-system port-forward svc/hubble-relay 4245:80
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
# Visit http://localhost:12000 for Hubble UI
```

**Reference:** See `docs/guides/observability-stack-implementation.md` for full implementation guide.

---

## external-secrets Namespace

### External Secrets

**Purpose:** Sync secrets from external providers (1Password, Bitwarden, Vault) into Kubernetes secrets.

**Template:** `templates/config/kubernetes/apps/external-secrets/external-secrets/`

**Condition:** Only enabled when `external_secrets_enabled: true` in `cluster.yaml`

**Components:**
- External Secrets Operator (controller)
- Webhook (validation/mutation webhooks)
- Cert Controller (certificate management)

**Configuration Variables:**

| Variable | Usage | Default |
| ---------- | ------- | ------- |
| `external_secrets_enabled` | Enable operator | `false` |
| `external_secrets_provider` | Provider type | `1password` |
| `onepassword_connect_host` | 1Password Connect URL | - |

**Supported Providers:**
- **1Password** - Via 1Password Connect server
- **Bitwarden** - Via Bitwarden Secrets Manager
- **HashiCorp Vault** - Direct Vault integration

**Usage - Creating an ExternalSecret:**

1. First, create a SecretStore (cluster-scoped or namespace-scoped):
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect:8080
      vaults:
        my-vault: 1
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-token
            namespace: external-secrets
            key: token
```

1. Then create ExternalSecrets that sync from your provider:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: my-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: my-app
        property: database-password
```

**Integration with Monitoring:**
When `monitoring_enabled: true`, ServiceMonitors are automatically created for:
- Main controller metrics
- Webhook metrics
- Cert controller metrics

**Troubleshooting:**
```bash
flux get hr -n external-secrets external-secrets
kubectl -n external-secrets get pods
kubectl get externalsecrets -A
kubectl get secretstores -A
kubectl get clustersecretstores
kubectl -n external-secrets logs deploy/external-secrets
```

**Reference:** See `docs/guides/k8s-at-home-remaining-implementation.md` for provider-specific setup guides.

---

## default Namespace

### Echo

**Purpose:** Test application to verify ingress and DNS.

**Template:** `templates/config/kubernetes/apps/default/echo/`

**Endpoints:**
- Internal: `echo.cloudflare_domain` (via `envoy-internal`)
- External: `echo.cloudflare_domain` (via `envoy-external` + tunnel)

**Testing:**
```bash
# Internal (from network with split DNS)
curl https://echo.example.com

# External (from internet)
curl https://echo.example.com

# Both should return echo server response
```

---

## Adding Custom Applications

### Template Structure

```
templates/config/kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml.j2              # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2   # For Helm charts
    ├── ocirepository.yaml.j2 # OCI source
    └── secret.sops.yaml.j2   # Optional secrets
```

### Kustomization Template (ks.yaml.j2)

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  namespace: flux-system
spec:
  targetNamespace: my-namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/my-namespace/myapp/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: envoy-gateway  # If needs ingress
```

### HelmRelease Template

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: myapp
  values:
    # Your Helm values here
```

### OCI Repository Template

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: myapp
spec:
  interval: 12h
  url: oci://ghcr.io/myorg/charts/myapp
  ref:
    tag: 1.0.0
```

### Adding to Namespace Kustomization

```yaml
# templates/config/kubernetes/apps/<namespace>/kustomization.yaml.j2
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./existing-app/ks.yaml
  - ./myapp/ks.yaml  # Add your app
```
