# K8s-at-Home Community Patterns Implementation Guide

> **Guide Version:** 1.0.0
> **Last Updated:** January 2026
> **Status:** Ready for Implementation
> **Source Research:** [k8s-at-home-patterns-research.md](../research/k8s-at-home-patterns-research.md)

---

## Overview

This guide provides step-by-step implementation instructions for integrating community-validated patterns from the k8s-at-home ecosystem. All implementations follow the project's established template patterns, makejinja conventions, and OCIRepository/chartRef HelmRelease style.

### Implementation Phases

| Phase | Components | Status | Value |
| ----- | ---------- | ------ | ----- |
| **Phase 1** | ✅ Already Complete | Done | Foundation |
| **Phase 2** | VolSync (PVC Backup) | Ready | High - DR for stateful apps |
| **Phase 3** | Observability Stack | Ready | High - Metrics/Logs/Alerts |
| **Phase 4** | Optional Enhancements | Future | Medium - As needed |

### Phase 1 Status (Already Implemented)

These components were implemented via the [GitOps Components Implementation Guide](./gitops-components-implementation.md):

| Component | Location | Status |
| --------- | -------- | ------ |
| Renovate Bot | `.renovaterc.json5` | ✅ Complete |
| Dual External-DNS | `network/cloudflare-dns/`, `network/unifi-dns/` | ✅ Complete |
| tuppr (Auto-upgrades) | `system-upgrade/tuppr/` | ✅ Complete |
| talos-backup (etcd) | `kube-system/talos-backup/` | ✅ Complete |
| Proxmox CSI | `csi-proxmox/proxmox-csi/` | ✅ Complete |
| Proxmox CCM | `kube-system/proxmox-ccm/` | ✅ Complete |

### Chart Versions (January 2026)

| Chart | Registry | Version |
| ----- | -------- | ------- |
| VolSync | `ghcr.io/backube/helm-charts` | **0.14.0** |
| victoria-metrics-k8s-stack | `ghcr.io/victoriametrics/helm-charts` | **0.45.0** |
| kube-prometheus-stack | `ghcr.io/prometheus-community/helm-charts` | **80.9.2** |
| Grafana Loki | `ghcr.io/grafana/helm-charts` | **6.49.0** |
| bjw-s app-template | `ghcr.io/bjw-s-labs/helm-charts` | **3.7.3** |
| External Secrets | `ghcr.io/external-secrets/charts` | **1.2.1** |

> **Tip:** Check for updates with `skopeo list-tags docker://ghcr.io/<org>/charts/<chart>`

---

## Phase 2: VolSync (PVC Backup)

VolSync provides scheduled PVC snapshots with restic-based deduplication and S3 storage. This enables point-in-time recovery for stateful workloads.

### Why VolSync

| Feature | Without VolSync | With VolSync |
| ------- | --------------- | ------------ |
| PVC backup | Manual scripts | Automated schedules |
| Recovery | Full restore only | Point-in-time recovery |
| Deduplication | None | Restic-based (efficient) |
| Encryption | Manual | Built-in Age/GPG |

### Prerequisites

1. **S3 Storage** - Cloudflare R2 recommended (reuse existing `backup_s3_*` config)
2. **Proxmox CSI** - Already deployed for PVC provisioning
3. **Restic Password** - Unique encryption key per cluster

### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/storage/volsync/app
```

### Step 2: Create Namespace Files

**File:** `templates/config/kubernetes/apps/storage/namespace.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: storage
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
#% endif %#
```

**File:** `templates/config/kubernetes/apps/storage/kustomization.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: storage

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./volsync/ks.yaml
#% endif %#
```

### Step 3: Create VolSync Templates

**File:** `templates/config/kubernetes/apps/storage/volsync/ks.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: volsync
spec:
  interval: 1h
  path: ./kubernetes/apps/storage/volsync/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: storage
  wait: false
#% endif %#
```

**File:** `templates/config/kubernetes/apps/storage/volsync/app/kustomization.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./secret.sops.yaml
#% endif %#
```

**File:** `templates/config/kubernetes/apps/storage/volsync/app/ocirepository.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: volsync
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.14.0
  url: oci://ghcr.io/backube/helm-charts/volsync
#% endif %#
```

**File:** `templates/config/kubernetes/apps/storage/volsync/app/helmrelease.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: volsync
spec:
  chartRef:
    kind: OCIRepository
    name: volsync
  interval: 1h
  values:
    manageCRDs: true
    metrics:
      enabled: true
    serviceMonitor:
      enabled: true
#% endif %#
```

**File:** `templates/config/kubernetes/apps/storage/volsync/app/secret.sops.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: v1
kind: Secret
metadata:
  name: volsync-restic-config
type: Opaque
stringData:
  RESTIC_REPOSITORY: "s3:#{ volsync_s3_endpoint | default(backup_s3_endpoint) }#/#{ volsync_s3_bucket | default(backup_s3_bucket) }#/volsync"
  RESTIC_PASSWORD: "#{ volsync_restic_password }#"
  AWS_ACCESS_KEY_ID: "#{ backup_s3_access_key }#"
  AWS_SECRET_ACCESS_KEY: "#{ backup_s3_secret_key }#"
#% endif %#
```

### Step 4: Add cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# VOLSYNC - Phase 2: PVC Backup
# =============================================================================
# VolSync provides PVC-level backups to S3-compatible storage.
# Can reuse existing R2 bucket from talos-backup configuration.

# -- Enable VolSync for PVC backups
#    (OPTIONAL) / (DEFAULT: false)
# volsync_enabled: false

# -- VolSync S3 endpoint (defaults to backup_s3_endpoint if not set)
#    (OPTIONAL) / (e.g. same as backup_s3_endpoint)
# volsync_s3_endpoint: ""

# -- VolSync S3 bucket (defaults to backup_s3_bucket if not set)
#    (OPTIONAL) / (e.g. same as backup_s3_bucket)
# volsync_s3_bucket: ""

# -- Restic encryption password for VolSync
#    (REQUIRED when volsync_enabled: true) / (Will be SOPS-encrypted after task configure)
# volsync_restic_password: ""

# -- Default backup schedule for VolSync ReplicationSources
#    (OPTIONAL) / (DEFAULT: "0 */6 * * *" - every 6 hours)
# volsync_schedule: "0 */6 * * *"

# -- Default retention policy
#    (OPTIONAL)
# volsync_retain_daily: 7
# volsync_retain_weekly: 4
# volsync_retain_monthly: 3
```

### Step 5: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  #% if volsync_enabled is defined and volsync_enabled %#
  - ./storage
  #% endif %#
```

### Step 6: Deploy

```bash
# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "feat: add VolSync for PVC backup and recovery"
git push

# Reconcile
task reconcile
```

### Step 7: Create ReplicationSource for Apps

For each application needing backup, create a `ReplicationSource`:

**Example:** `templates/config/kubernetes/apps/<namespace>/<app>/app/replicationsource.yaml.j2`

```yaml
#% if volsync_enabled is defined and volsync_enabled %#
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: #{ app_name }#-backup
spec:
  sourcePVC: #{ app_name }#-data
  trigger:
    schedule: "#{ volsync_schedule | default('0 */6 * * *') }#"
  restic:
    pruneIntervalDays: 7
    repository: volsync-restic-config
    retain:
      daily: #{ volsync_retain_daily | default(7) }#
      weekly: #{ volsync_retain_weekly | default(4) }#
      monthly: #{ volsync_retain_monthly | default(3) }#
    copyMethod: Snapshot
    storageClassName: proxmox-zfs
#% endif %#
```

### Verification

```bash
# Check VolSync deployment
kubectl -n storage get pods

# Verify CRDs installed
kubectl get crd | grep volsync

# Check ReplicationSources
kubectl get replicationsource -A

# View backup status
kubectl describe replicationsource -n <namespace> <name>

# List snapshots in S3
rclone ls r2:cluster-backups/volsync/
```

### Restore Procedure

To restore a PVC from backup:

```yaml
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: app-data-restore
  namespace: <namespace>
spec:
  trigger:
    manual: restore-once
  restic:
    repository: volsync-restic-config
    destinationPVC: app-data-restored
    copyMethod: Direct
    storageClassName: proxmox-zfs
    capacity: 10Gi  # Match original PVC size
```

---

## Phase 3: Observability Stack

Choose ONE of the following options based on your resource constraints:

| Option | Memory Usage | Best For |
| ------ | ------------ | -------- |
| **VictoriaMetrics** (Recommended) | ~200-400MB | Homelabs, resource-constrained |
| **kube-prometheus-stack** | ~2-4GB | Large clusters, extensive dashboards |

### Option A: VictoriaMetrics (Recommended)

VictoriaMetrics provides full Prometheus/PromQL compatibility with 10x less resource usage.

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/monitoring/victoria-metrics/app
```

#### Step 2: Create Namespace Files

**File:** `templates/config/kubernetes/apps/monitoring/namespace.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: monitoring

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  #% if monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
  - ./victoria-metrics/ks.yaml
  #% else %#
  - ./kube-prometheus-stack/ks.yaml
  #% endif %#
#% endif %#
```

#### Step 3: Create VictoriaMetrics Templates

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/ks.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: victoria-metrics
spec:
  interval: 1h
  path: ./kubernetes/apps/monitoring/victoria-metrics/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: monitoring
  wait: false
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
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
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.45.0
  url: oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack
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
          storageClassName: proxmox-zfs
          resources:
            requests:
              storage: #{ metrics_storage_size | default('50Gi') }#

    # Grafana for visualization
    grafana:
      enabled: true
      ingress:
        enabled: true
        ingressClassName: internal
        annotations:
          external-dns.alpha.kubernetes.io/target: "#{ cluster_gateway_addr }#"
        hosts:
          - #{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#
      persistence:
        enabled: true
        storageClassName: proxmox-zfs
        size: 5Gi

    # AlertManager for alerting
    alertmanager:
      enabled: true
      spec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: proxmox-zfs
              resources:
                requests:
                  storage: 1Gi

    # Scrape etcd metrics from control plane nodes
    kubeEtcd:
      enabled: true
      endpoints:
        #% for node in nodes | selectattr('controller', 'equalto', true) %#
        - #{ node.address }#
        #% endfor %#

    # ServiceMonitor defaults
    serviceMonitor:
      enabled: true
#% endif %#
```

#### Step 4: Add cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# MONITORING - Phase 3: Observability Stack
# =============================================================================
# Choose either VictoriaMetrics (recommended) or kube-prometheus-stack

# -- Enable monitoring stack
#    (OPTIONAL) / (DEFAULT: false)
# monitoring_enabled: false

# -- Monitoring stack choice: "victoriametrics" or "prometheus"
#    (OPTIONAL) / (DEFAULT: "victoriametrics") - VictoriaMetrics uses ~10x less memory
# monitoring_stack: "victoriametrics"

# -- Grafana subdomain (creates grafana.<cloudflare_domain>)
#    (OPTIONAL) / (DEFAULT: "grafana")
# grafana_subdomain: "grafana"

# -- Metrics retention period
#    (OPTIONAL) / (DEFAULT: "7d")
# metrics_retention: "7d"

# -- Metrics storage size
#    (OPTIONAL) / (DEFAULT: "50Gi")
# metrics_storage_size: "50Gi"
```

#### Step 5: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  #% if monitoring_enabled is defined and monitoring_enabled %#
  - ./monitoring
  #% endif %#
```

#### Step 6: Deploy

```bash
task configure
git add -A
git commit -m "feat: add VictoriaMetrics observability stack"
git push
task reconcile
```

#### Verification

```bash
# Check monitoring pods
kubectl -n monitoring get pods

# Verify Grafana is accessible
kubectl -n monitoring get ingress

# Check VictoriaMetrics targets
kubectl -n monitoring port-forward svc/victoria-metrics-k8s-stack-vmsingle 8428:8428
curl http://localhost:8428/targets

# View metrics
curl http://localhost:8428/api/v1/query?query=up
```

### Option B: kube-prometheus-stack

For clusters with more resources, the full Prometheus stack provides extensive dashboards and community support.

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app
```

#### Step 2: Create kube-prometheus-stack Templates

**File:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/ks.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack == 'prometheus' %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: kube-prometheus-stack
spec:
  interval: 1h
  path: ./kubernetes/apps/monitoring/kube-prometheus-stack/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: monitoring
  wait: false
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app/kustomization.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack == 'prometheus' %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app/ocirepository.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack == 'prometheus' %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: kube-prometheus-stack
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 80.9.2
  url: oci://ghcr.io/prometheus-community/helm-charts/kube-prometheus-stack
#% endif %#
```

**File:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app/helmrelease.yaml.j2`

```yaml
#% if monitoring_enabled is defined and monitoring_enabled and monitoring_stack == 'prometheus' %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
spec:
  chartRef:
    kind: OCIRepository
    name: kube-prometheus-stack
  interval: 1h
  values:
    # Prometheus
    prometheus:
      prometheusSpec:
        retention: #{ metrics_retention | default('7d') }#
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: proxmox-zfs
              resources:
                requests:
                  storage: #{ metrics_storage_size | default('50Gi') }#
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false

    # Grafana
    grafana:
      enabled: true
      ingress:
        enabled: true
        ingressClassName: internal
        annotations:
          external-dns.alpha.kubernetes.io/target: "#{ cluster_gateway_addr }#"
        hosts:
          - #{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#
      persistence:
        enabled: true
        storageClassName: proxmox-zfs
        size: 5Gi

    # AlertManager
    alertmanager:
      enabled: true
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: proxmox-zfs
              resources:
                requests:
                  storage: 1Gi

    # etcd monitoring
    kubeEtcd:
      enabled: true
      endpoints:
        #% for node in nodes | selectattr('controller', 'equalto', true) %#
        - #{ node.address }#
        #% endfor %#
#% endif %#
```

---

## Phase 4: Optional Enhancements

These components can be added as needed based on your requirements.

### 4.1 bjw-s App Template

The [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) simplifies deploying containerized applications without official Helm charts.

#### When to Use

- Simple containerized applications
- Applications without official Helm charts
- Quick prototyping and testing

#### When NOT to Use

- Complex applications with official charts (cert-manager, Cilium, etc.)
- Applications requiring custom CRDs

#### Step 1: Add OCIRepository

**File:** `templates/config/kubernetes/flux/cluster/repositories/bjw-s.yaml.j2`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: bjw-s-app-template
  namespace: flux-system
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 3.7.3
  url: oci://ghcr.io/bjw-s-labs/helm-charts/app-template
```

#### Step 2: Example Application

**File:** `templates/config/kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml.j2`

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: my-app
spec:
  chartRef:
    kind: OCIRepository
    name: bjw-s-app-template
    namespace: flux-system
  interval: 1h
  values:
    controllers:
      main:
        containers:
          main:
            image:
              repository: my-app/image
              tag: v1.0.0
            env:
              TZ: America/Chicago
            resources:
              requests:
                cpu: 10m
                memory: 128Mi
              limits:
                memory: 256Mi

    service:
      main:
        controller: main
        ports:
          http:
            port: 8080

    ingress:
      main:
        enabled: true
        className: internal
        annotations:
          external-dns.alpha.kubernetes.io/target: "#{ cluster_gateway_addr }#"
        hosts:
          - host: my-app.#{ cloudflare_domain }#
            paths:
              - path: /
                pathType: Prefix
                service:
                  identifier: main
                  port: http

    persistence:
      config:
        enabled: true
        type: persistentVolumeClaim
        storageClass: proxmox-zfs
        accessMode: ReadWriteOnce
        size: 1Gi
```

### 4.2 External Secrets Operator

External Secrets syncs secrets from external providers (1Password, Bitwarden, Vault) into Kubernetes.

#### When to Use

- Managing 20+ secrets
- Need secret rotation automation
- Already using 1Password/Bitwarden
- Want audit trail for secret access

#### When NOT to Use

- Small clusters with few secrets
- SOPS/Age working well
- No external secret provider

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/external-secrets/external-secrets/app
```

#### Step 2: Create Templates

**File:** `templates/config/kubernetes/apps/external-secrets/namespace.yaml.j2`

```yaml
#% if external_secrets_enabled is defined and external_secrets_enabled %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
#% endif %#
```

**File:** `templates/config/kubernetes/apps/external-secrets/external-secrets/app/ocirepository.yaml.j2`

```yaml
#% if external_secrets_enabled is defined and external_secrets_enabled %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: external-secrets
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 1.2.1
  url: oci://ghcr.io/external-secrets/charts/external-secrets
#% endif %#
```

**File:** `templates/config/kubernetes/apps/external-secrets/external-secrets/app/helmrelease.yaml.j2`

```yaml
#% if external_secrets_enabled is defined and external_secrets_enabled %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: external-secrets
spec:
  chartRef:
    kind: OCIRepository
    name: external-secrets
  interval: 1h
  values:
    installCRDs: true
    serviceMonitor:
      enabled: true
    webhook:
      serviceMonitor:
        enabled: true
    certController:
      serviceMonitor:
        enabled: true
#% endif %#
```

#### Step 3: Add cluster.yaml Variables

```yaml
# =============================================================================
# EXTERNAL SECRETS - Phase 4: Optional Secret Management
# =============================================================================
# External Secrets syncs secrets from external providers into Kubernetes

# -- Enable External Secrets Operator
#    (OPTIONAL) / (DEFAULT: false)
# external_secrets_enabled: false

# -- External secret provider: "1password", "bitwarden", "vault"
#    (OPTIONAL) / (DEFAULT: "1password")
# external_secrets_provider: "1password"

# -- 1Password Connect server URL (when using 1password provider)
#    (OPTIONAL)
# onepassword_connect_host: "http://onepassword-connect:8080"
```

---

## Configuration Reference

### cluster.yaml Additions Summary

```yaml
# =============================================================================
# VOLSYNC - Phase 2: PVC Backup
# =============================================================================
volsync_enabled: false
# volsync_s3_endpoint: ""  # Defaults to backup_s3_endpoint
# volsync_s3_bucket: ""    # Defaults to backup_s3_bucket
# volsync_restic_password: ""  # Required when enabled
# volsync_schedule: "0 */6 * * *"
# volsync_retain_daily: 7
# volsync_retain_weekly: 4
# volsync_retain_monthly: 3

# =============================================================================
# MONITORING - Phase 3: Observability Stack
# =============================================================================
monitoring_enabled: false
# monitoring_stack: "victoriametrics"  # or "prometheus"
# grafana_subdomain: "grafana"
# metrics_retention: "7d"
# metrics_storage_size: "50Gi"

# =============================================================================
# OPTIONAL ENHANCEMENTS - Phase 4
# =============================================================================
# external_secrets_enabled: false
# external_secrets_provider: "1password"
```

### Template Directory Structure

After full implementation:

```
templates/config/kubernetes/apps/
├── storage/                          # Phase 2
│   ├── namespace.yaml.j2
│   ├── kustomization.yaml.j2
│   └── volsync/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── ocirepository.yaml.j2
│           ├── helmrelease.yaml.j2
│           └── secret.sops.yaml.j2
├── monitoring/                       # Phase 3
│   ├── namespace.yaml.j2
│   ├── kustomization.yaml.j2
│   ├── victoria-metrics/             # Option A
│   │   ├── ks.yaml.j2
│   │   └── app/
│   │       ├── kustomization.yaml.j2
│   │       ├── ocirepository.yaml.j2
│   │       └── helmrelease.yaml.j2
│   └── kube-prometheus-stack/        # Option B
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── ocirepository.yaml.j2
│           └── helmrelease.yaml.j2
├── external-secrets/                 # Phase 4 (optional)
│   ├── namespace.yaml.j2
│   ├── kustomization.yaml.j2
│   └── external-secrets/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── ocirepository.yaml.j2
│           └── helmrelease.yaml.j2
└── flux/cluster/repositories/
    └── bjw-s.yaml.j2                # Phase 4 (optional)
```

---

## Implementation Checklist

### Phase 2: VolSync (PVC Backup)

- [ ] Create `storage` namespace templates
- [ ] Create VolSync HelmRelease templates
- [ ] Add `volsync_*` variables to cluster.yaml
- [ ] Update root kustomization
- [ ] Generate restic password and add to cluster.yaml
- [ ] Deploy and verify
- [ ] Create ReplicationSource for first stateful app
- [ ] Test restore procedure

### Phase 3: Observability Stack

- [ ] Choose stack: VictoriaMetrics (recommended) or Prometheus
- [ ] Create `monitoring` namespace templates
- [ ] Create chosen stack templates (victoria-metrics OR kube-prometheus-stack)
- [ ] Add `monitoring_*` variables to cluster.yaml
- [ ] Update root kustomization
- [ ] Deploy and verify
- [ ] Access Grafana and verify dashboards
- [ ] Verify etcd metrics collection

### Phase 4: Optional Enhancements

**bjw-s App Template:**
- [ ] Add OCIRepository to flux/cluster/repositories
- [ ] Use for first simple application

**External Secrets:**
- [ ] Set up secret provider (1Password/Bitwarden/Vault)
- [ ] Create `external-secrets` namespace templates
- [ ] Create External Secrets Operator templates
- [ ] Configure ClusterSecretStore
- [ ] Migrate first secret

---

## Troubleshooting

### VolSync Issues

| Issue | Solution |
| ----- | -------- |
| ReplicationSource stuck | Check restic secret credentials, verify S3 access |
| Snapshot fails | Verify CSI snapshot support, check storage class |
| S3 permission denied | Verify bucket policy, check access keys |

### Monitoring Issues

| Issue | Solution |
| ----- | -------- |
| No metrics appearing | Check ServiceMonitor labels, verify scrape configs |
| Grafana not accessible | Check ingress, verify DNS resolution |
| etcd metrics missing | Verify control plane node IPs in config |
| High memory usage | Reduce retention period, add resource limits |

### General Issues

| Issue | Solution |
| ----- | -------- |
| Templates not generating | Check Jinja2 conditionals (`#% if ... %#`) |
| HelmRelease failing | Check `flux get hr -A`, verify chart version |
| Secret not found | Verify SOPS encryption, check `flux get sources git` |

---

## References

### Component Documentation

- [VolSync](https://volsync.readthedocs.io/en/stable/) - PVC replication and backup
- [VictoriaMetrics](https://docs.victoriametrics.com/) - Resource-efficient monitoring
- [kube-prometheus-stack](https://prometheus-operator.dev/) - Full Prometheus ecosystem
- [bjw-s App Template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) - Generic Helm wrapper
- [External Secrets](https://external-secrets.io/) - Secret synchronization

### Project Documentation

- [Source Research](../research/k8s-at-home-patterns-research.md) - Community patterns analysis
- [GitOps Components Guide](./gitops-components-implementation.md) - Phase 1 implementation
- [Architecture](../ARCHITECTURE.md) - System design
- [Configuration](../CONFIGURATION.md) - Schema reference

### Community Resources

- [Kubesearch.dev](https://kubesearch.dev/) - Search k8s-at-home HelmReleases
- [GitHub k8s-at-home](https://github.com/topics/k8s-at-home) - Community repositories
