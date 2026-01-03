# K8s-at-Home Patterns: Remaining Implementation Guide

> **Guide Version:** 1.1.0
> **Last Updated:** January 2026
> **Status:** Ready for Implementation (Validated)
> **Parent Guide:** [k8s-at-home-patterns-implementation.md](./k8s-at-home-patterns-implementation.md)

---

## Overview

This guide covers the **remaining phases** from the k8s-at-home patterns implementation that have not yet been implemented in the project templates.

### Implementation Status Summary

| Phase | Component | Status | Notes |
| ----- | --------- | ------ | ----- |
| **Phase 1** | Renovate, External-DNS, tuppr, talos-backup, Proxmox CSI/CCM | ✅ **Complete** | See [gitops-components-implementation.md](./gitops-components-implementation.md) |
| **Phase 2** | VolSync (PVC Backup) | ❌ **Not Implemented** | This guide |
| **Phase 3 Option A** | VictoriaMetrics | ✅ **Complete + Enhanced** | Includes Loki, Alloy, Tempo |
| **Phase 3 Option B** | kube-prometheus-stack | ❌ **Not Implemented** | This guide (optional) |
| **Phase 4** | bjw-s App Template | ❌ **Not Implemented** | This guide |
| **Phase 4** | External Secrets Operator | ❌ **Not Implemented** | This guide |

### What's Already Enhanced Beyond Original Guide

The monitoring stack (Phase 3 Option A) was implemented with additional observability components:
- **Loki** - Log aggregation (conditional on `loki_enabled`)
- **Alloy** - OpenTelemetry collector for unified telemetry
- **Tempo** - Distributed tracing (conditional on `tracing_enabled`)
- **Pre-configured Grafana dashboards** - Infrastructure, Network, GitOps folders

---

## Phase 2: VolSync (PVC Backup)

VolSync provides scheduled PVC snapshots with restic-based deduplication and S3 storage.

### Prerequisites

1. **S3 Storage** - Cloudflare R2 recommended (reuse existing `backup_s3_*` config)
2. **Storage Class** - Proxmox CSI or similar (snapshots optional, see copyMethod note below)
3. **Restic Password** - Unique encryption key per cluster

### copyMethod Options

VolSync supports two copy methods for creating point-in-time backups:

| Method     | Requirements                           | Best For                        |
| ---------- | -------------------------------------- | ------------------------------- |
| `Snapshot` | CSI driver with VolumeSnapshot support | Production with CSI snapshots   |
| `Clone`    | Any CSI driver with volume cloning     | Proxmox CSI, simpler setups     |

> **Note:** If your CSI driver doesn't support VolumeSnapshots (common with Proxmox CSI), use `copyMethod: Clone` instead. Clone creates a PVC copy before backup, which works without snapshot support but requires additional storage during the backup window.

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
# VOLSYNC - PVC Backup
# =============================================================================
# VolSync provides PVC-level backups to S3-compatible storage.
# Can reuse existing R2 bucket from talos-backup configuration.

# -- Enable VolSync for PVC backups
#    (OPTIONAL) / (DEFAULT: false)
# volsync_enabled: false

# -- VolSync S3 endpoint (defaults to backup_s3_endpoint if not set)
#    (OPTIONAL)
# volsync_s3_endpoint: ""

# -- VolSync S3 bucket (defaults to backup_s3_bucket if not set)
#    (OPTIONAL)
# volsync_s3_bucket: ""

# -- Restic encryption password for VolSync
#    (REQUIRED when volsync_enabled: true)
# volsync_restic_password: ""

# -- Default backup schedule for VolSync ReplicationSources
#    (OPTIONAL) / (DEFAULT: "0 */6 * * *" - every 6 hours)
# volsync_schedule: "0 */6 * * *"

# -- Copy method for backups: "Clone" or "Snapshot"
#    Clone works with any CSI driver (recommended for Proxmox CSI)
#    Snapshot requires VolumeSnapshot support but is faster
#    (OPTIONAL) / (DEFAULT: "Clone")
# volsync_copy_method: "Clone"

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
task configure
git add -A
git commit -m "feat: add VolSync for PVC backup and recovery"
git push
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
    # Use 'Clone' if your CSI doesn't support VolumeSnapshots (e.g., Proxmox CSI)
    # Use 'Snapshot' if your CSI supports VolumeSnapshots for faster backups
    copyMethod: "#{ volsync_copy_method | default('Clone') }#"
    storageClassName: "#{ storage_class | default('local-path') }#"
#% endif %#
```

> **Tip:** The default `copyMethod` is set to `Clone` for broader compatibility. If you have VolumeSnapshot support, add `volsync_copy_method: "Snapshot"` to your `cluster.yaml` for faster backups.

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
```

---

## Phase 3 Option B: kube-prometheus-stack (Alternative)

> **Note:** Phase 3 Option A (VictoriaMetrics) is already implemented and enhanced. Only implement this if you need the full Prometheus ecosystem instead.

### When to Choose kube-prometheus-stack Over VictoriaMetrics

| Use Case | Recommendation |
| -------- | -------------- |
| Resource-constrained homelab | VictoriaMetrics (already implemented) |
| Need extensive community dashboards | kube-prometheus-stack |
| Require Thanos long-term storage | kube-prometheus-stack |
| Memory is not a concern (4GB+) | kube-prometheus-stack |

### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app
```

### Step 2: Create Templates

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
    tag: 80.10.0
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
        retention: "#{ metrics_retention | default('7d') }#"
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: "#{ storage_class | default('local-path') }#"
              resources:
                requests:
                  storage: "#{ metrics_storage_size | default('50Gi') }#"
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false
        resources:
          requests:
            cpu: 200m
            memory: 1Gi
          limits:
            memory: 2Gi

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
        storageClassName: "#{ storage_class | default('local-path') }#"
        size: 5Gi

    # AlertManager
    alertmanager:
      enabled: true
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: "#{ storage_class | default('local-path') }#"
              resources:
                requests:
                  storage: 1Gi

    # etcd monitoring (Talos Linux endpoints)
    kubeEtcd:
      enabled: true
#% endif %#
```

### Step 3: Update Monitoring Kustomization

**Edit:** `templates/config/kubernetes/apps/monitoring/kustomization.yaml.j2`

Ensure the conditional logic includes kube-prometheus-stack:

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
#% elif monitoring_stack == 'prometheus' %#
  - ./kube-prometheus-stack/ks.yaml
#% endif %#
#% if loki_enabled | default(false) %#
  - ./loki/ks.yaml
  - ./alloy/ks.yaml
#% endif %#
#% if tracing_enabled | default(false) %#
  - ./tempo/ks.yaml
#% endif %#
#% endif %#
```

---

## Phase 4: bjw-s App Template

The bjw-s app-template simplifies deploying containerized applications without official Helm charts.

### Placement Options

There are two approaches for adding the bjw-s app-template OCIRepository:

| Approach | When to Use | Location |
| -------- | ----------- | -------- |
| **Per-App** (Recommended) | Single app using the template | `apps/<namespace>/<app>/app/ocirepository.yaml.j2` |
| **Shared Repository** | Multiple apps using the template | `flux/cluster/repositories/bjw-s.yaml.j2` |

> **Note:** This project currently uses the **per-app pattern** where each application includes its own OCIRepository. If you plan to deploy multiple applications using bjw-s app-template, consider the shared repository approach below.

### Option A: Per-App OCIRepository (Current Project Pattern)

Include the OCIRepository in each application's `app/` directory:

**File:** `templates/config/kubernetes/apps/<namespace>/<app>/app/ocirepository.yaml.j2`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: bjw-s-app-template
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 3.7.3
  url: oci://ghcr.io/bjw-s-labs/helm-charts/app-template
```

Then reference it in the HelmRelease without a namespace (same namespace):

```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: bjw-s-app-template
    # No namespace needed - uses same namespace as HelmRelease
```

### Option B: Shared Repository (For Multiple Apps)

If deploying multiple applications with bjw-s app-template, create a shared repository:

**Step 1:** Create the repositories directory structure:

```bash
mkdir -p templates/config/kubernetes/flux/cluster/repositories
```

**Step 2:** Create the OCIRepository:

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

**Step 3:** Create kustomization for repositories:

**File:** `templates/config/kubernetes/flux/cluster/repositories/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./bjw-s.yaml
```

**Step 4:** Update `flux/cluster/ks.yaml.j2` to include repositories (if not already present).

Then reference it in HelmReleases with the flux-system namespace:

```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: bjw-s-app-template
    namespace: flux-system  # Required when using shared repository
```

### Example Application Usage

The following example shows a complete HelmRelease using bjw-s app-template. Adjust the `chartRef.namespace` based on your chosen approach:
- **Per-App (Option A):** Remove the `namespace` line (or leave empty)
- **Shared Repository (Option B):** Keep `namespace: flux-system`

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
    # For Option A (per-app): remove this line or leave empty
    # For Option B (shared): keep namespace: flux-system
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
              TZ: "#{ timezone | default('America/Chicago') }#"
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
        className: ""
        annotations:
          external-dns.alpha.kubernetes.io/target: "#{ cluster_gateway_addr }#"
        hosts:
          - host: my-app.${SECRET_DOMAIN}
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
        storageClass: "#{ storage_class | default('local-path') }#"
        accessMode: ReadWriteOnce
        size: 1Gi
```

---

## Phase 4: External Secrets Operator

External Secrets syncs secrets from external providers (1Password, Bitwarden, Vault) into Kubernetes.

### When to Use

- Managing 20+ secrets
- Need secret rotation automation
- Already using 1Password/Bitwarden/Vault
- Want audit trail for secret access

### When NOT to Use

- Small clusters with few secrets
- SOPS/Age working well for your needs
- No external secret provider

### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/external-secrets/external-secrets/app
```

### Step 2: Create Namespace Files

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

**File:** `templates/config/kubernetes/apps/external-secrets/kustomization.yaml.j2`

```yaml
#% if external_secrets_enabled is defined and external_secrets_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: external-secrets

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./external-secrets/ks.yaml
#% endif %#
```

### Step 3: Create External Secrets Templates

**File:** `templates/config/kubernetes/apps/external-secrets/external-secrets/ks.yaml.j2`

```yaml
#% if external_secrets_enabled is defined and external_secrets_enabled %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: external-secrets
spec:
  interval: 1h
  path: ./kubernetes/apps/external-secrets/external-secrets/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: external-secrets
  wait: false
#% endif %#
```

**File:** `templates/config/kubernetes/apps/external-secrets/external-secrets/app/kustomization.yaml.j2`

```yaml
#% if external_secrets_enabled is defined and external_secrets_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
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

### Step 4: Add cluster.yaml Variables

```yaml
# =============================================================================
# EXTERNAL SECRETS - Secret Management
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

### Step 5: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  #% if external_secrets_enabled is defined and external_secrets_enabled %#
  - ./external-secrets
  #% endif %#
```

---

## Implementation Checklist

### Phase 2: VolSync (PVC Backup)

- [ ] Create `storage` namespace templates
- [ ] Create VolSync HelmRelease templates
- [ ] Add `volsync_*` variables to cluster.yaml
- [ ] Update root kustomization with conditional
- [ ] Generate restic password and add to cluster.yaml
- [ ] Run `task configure`
- [ ] Deploy and verify
- [ ] Create ReplicationSource for first stateful app
- [ ] Test restore procedure

### Phase 3 Option B: kube-prometheus-stack (Optional)

- [ ] Create kube-prometheus-stack templates
- [ ] Update monitoring kustomization with conditional
- [ ] Add `monitoring_stack: "prometheus"` to cluster.yaml
- [ ] Run `task configure`
- [ ] Deploy and verify
- [ ] Verify dashboards in Grafana

### Phase 4: bjw-s App Template

- [ ] Add OCIRepository to flux/cluster/repositories
- [ ] Update repositories kustomization
- [ ] Run `task configure`
- [ ] Create first application using app-template

### Phase 4: External Secrets

- [ ] Set up secret provider (1Password/Bitwarden/Vault)
- [ ] Create `external-secrets` namespace templates
- [ ] Create External Secrets Operator templates
- [ ] Add `external_secrets_*` variables to cluster.yaml
- [ ] Update root kustomization
- [ ] Run `task configure`
- [ ] Deploy and verify
- [ ] Configure ClusterSecretStore for your provider
- [ ] Migrate first secret from SOPS

---

## Chart Versions (January 2026)

| Chart | Registry | Version |
| ----- | -------- | ------- |
| VolSync | `ghcr.io/backube/helm-charts` | **0.14.0** |
| kube-prometheus-stack | `ghcr.io/prometheus-community/helm-charts` | **80.10.0** |
| bjw-s app-template | `ghcr.io/bjw-s-labs/helm-charts` | **3.7.3** |
| External Secrets | `ghcr.io/external-secrets/charts` | **1.2.1** |

> **Tip:** Check for updates with `skopeo list-tags docker://ghcr.io/<org>/charts/<chart>`

---

## References

### Component Documentation

- [VolSync](https://volsync.readthedocs.io/en/stable/) - PVC replication and backup
- [kube-prometheus-stack](https://prometheus-operator.dev/) - Full Prometheus ecosystem
- [bjw-s App Template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) - Generic Helm wrapper
- [External Secrets](https://external-secrets.io/) - Secret synchronization

### Project Documentation

- [Parent Implementation Guide](./k8s-at-home-patterns-implementation.md) - Full patterns overview
- [Source Research](../research/k8s-at-home-patterns-research.md) - Community patterns analysis
- [GitOps Components Guide](./gitops-components-implementation.md) - Phase 1 implementation
- [Configuration](../CONFIGURATION.md) - Schema reference

### Community Resources

- [Kubesearch.dev](https://kubesearch.dev/) - Search k8s-at-home HelmReleases
- [GitHub k8s-at-home](https://github.com/topics/k8s-at-home) - Community repositories
