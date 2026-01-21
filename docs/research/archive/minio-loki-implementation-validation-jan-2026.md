# MinIO & Loki Implementation Validation Report

**Date:** January 2026
**Status:** Validation Complete
**Source Document:** `docs/research/minio-shared-storage-loki-simplescalable-jan-2026.md`

---

## Executive Summary

This report validates the MinIO Shared Object Storage & Loki SimpleScalable Migration research document against current best practices, project template patterns, and January 2026 software releases. The core architectural decisions are **sound and validated**, but several implementation details require revision for Flux GitOps compatibility and project pattern alignment.

### Validation Outcome

| Category | Status | Items |
| ---------- | -------- | ------- |
| Architecture Decisions | ✅ Validated | 10 |
| Critical Revisions Needed | ❌ Required | 5 |
| Moderate Updates Needed | ⚠️ Recommended | 4 |
| Minor Enhancements | ℹ️ Optional | 4 |

---

## Part 1: Validated Findings

The following aspects of the research document are **confirmed correct** and should be retained:

### 1.1 MinIO Operator + Tenant Model ✅

**Validated:** The MinIO Operator approach is the recommended production pattern for Kubernetes deployments.

**Evidence:**

- MinIO official documentation recommends Operator for production ([MinIO Kubernetes Docs](https://min.io/docs/minio/kubernetes/upstream/index.html))
- Operator v7.1.1 (April 2025) provides automated lifecycle management
- Tenant CR enables declarative bucket and user provisioning
- Multi-tenancy capability supports future expansion

### 1.2 Single-Tenant with Bucket Isolation ✅

**Validated:** Single MinIO Tenant with separate buckets per service is appropriate for this cluster scale.

**Rationale:**

- Simpler operational model than multi-tenant
- Bucket-level IAM policies provide sufficient isolation
- Lower resource overhead
- Future services (backups, Harbor, Velero) easily accommodated

### 1.3 Loki SimpleScalable Mode ✅

**Validated:** Migration from SingleBinary to SimpleScalable resolves dashboard compatibility and improves scalability.

**Evidence:**

- GitHub Issue [#11390](https://github.com/grafana/loki/issues/11390) confirms job label mismatch in SingleBinary
- SimpleScalable produces correct labels: `job=~"loki-read"`, `job=~"loki-write"`, `job=~"loki-backend"`
- Scalability improvement: ~50GB/day (SingleBinary) → ~1TB/day (SimpleScalable)
- Current project Loki chart version 6.49.0 supports SimpleScalable

### 1.4 S3 Configuration Pattern ✅

**Validated:** The S3 storage configuration structure is correct for Loki 6.x.

```yaml
loki:
  storage:
    type: s3
    s3:
      endpoint: http://minio.storage.svc:9000
      region: us-east-1
      s3ForcePathStyle: true  # Required for MinIO
      insecure: true          # Internal cluster traffic
```

### 1.5 TLS Disabled for Internal Traffic ✅

**Validated:** Disabling TLS for internal cluster traffic is acceptable.

**Rationale:**

- All traffic is within cluster network (10.43.0.0/16)
- Cilium provides network-level encryption option if needed
- Reduces certificate management complexity
- Production pattern for internal S3-compatible storage

### 1.6 Resource Estimates ✅

**Validated:** Resource requirements are reasonable for homelab/small production.

| Component | CPU Request | Memory Limit | Validated |
| ----------- | ------------- | -------------- | ----------- |
| MinIO Operator | 50m | 256Mi | ✅ |
| MinIO Server (x2) | 100m each | 1Gi each | ✅ |
| Loki Read (x2) | 50m each | 256Mi each | ✅ |
| Loki Write (x3) | 50m each | 256Mi each | ✅ |
| Loki Backend (x2) | 50m each | 256Mi each | ✅ |

**Net increase:** +600m CPU, ~2GB memory, +9 pods (acceptable for cluster with workers)

### 1.7 SOPS Encryption Pattern ✅

**Validated:** Using SOPS/Age encryption for credentials aligns with project patterns.

### 1.8 Prometheus Integration ✅

**Validated:** `prometheusOperator: true` on Tenant CR and ServiceMonitor for Loki are correct.

### 1.9 Dashboard Folder Organization ✅

**Validated:** Using `grafana_folder: Logging` annotation matches project's folder organization pattern.

### 1.10 Caching Disabled ✅

**Validated:** Disabling memcached caching is appropriate for resource-constrained environments.

```yaml
chunksCache:
  enabled: false
resultsCache:
  enabled: false
```

---

## Part 2: Critical Revisions Required

The following issues **must be addressed** before implementation:

### 2.1 ❌ Helm Hooks Incompatibility with Flux

**Problem:** The research document proposes a Kubernetes Job with Helm hooks (`helm.sh/hook: post-install`) for bucket provisioning. Flux does not process Helm lifecycle hooks.

**Impact:** Buckets and service users will not be created, breaking Loki connectivity.

**Solution:** Use MinIO Tenant CR's declarative `buckets` and `users` fields:

```yaml
apiVersion: minio.min.io/v2
kind: Tenant
spec:
  # Declarative bucket creation (no Job needed)
  buckets:
    - name: loki-chunks
    - name: loki-ruler
    - name: loki-admin  # NEW: Required by Loki 6.x
    - name: tempo
    - name: backups

  # Declarative user creation (references Secrets)
  users:
    - name: loki-user-secret
    - name: tempo-user-secret
```

**Source:** [MinIO Tenant Helm Chart](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-minio-tenant-helm.html)

### 2.2 ❌ Missing Admin Bucket for Loki

**Problem:** The research document only specifies `loki-chunks` and `loki-ruler` buckets.

**Impact:** Loki 6.x requires three buckets: chunks, ruler, and admin.

**Solution:** Add the admin bucket to configuration:

```yaml
# cluster.yaml variables
loki_s3_bucket_chunks: "loki-chunks"
loki_s3_bucket_ruler: "loki-ruler"
loki_s3_bucket_admin: "loki-admin"

# Loki HelmRelease values
loki:
  storage:
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
      admin: loki-admin
```

**Source:** [Loki Storage Configuration](https://grafana.com/docs/loki/latest/setup/install/helm/configure-storage/)

### 2.3 ❌ Template Structure Misalignment

**Problem:** The proposed directory structure doesn't match project patterns.

**Research Document Proposes:**

```
storage/minio/
├── ks.yaml.j2
└── app/
    ├── helmrelease-operator.yaml.j2
    ├── tenant.yaml.j2
    └── secret.sops.yaml.j2
```

**Project Pattern Requires:**

```
storage/
├── namespace.yaml.j2                    # MISSING
├── kustomization.yaml.j2                # MISSING - namespace level
├── minio-operator/                      # Separate from tenant
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── ocirepository.yaml.j2
│       └── helmrelease.yaml.j2
└── minio-tenant/                        # Separate app
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── tenant.yaml.j2
        └── secret.sops.yaml.j2
```

**Rationale:**

- Separating operator and tenant allows independent health checks
- Clear dependency ordering (tenant `dependsOn` operator)
- Matches project pattern (kube-prometheus-stack vs loki separation)
- Enables granular troubleshooting

### 2.4 ❌ Missing Namespace Infrastructure

**Problem:** The research document omits required namespace-level files.

**Missing Files:**

**`storage/namespace.yaml.j2`:**

```yaml
#% if minio_enabled | default(false) %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: storage
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
#% endif %#
```

**`storage/kustomization.yaml.j2`:**

```yaml
#% if minio_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: storage

components:
  - ../../components/sops  # CRITICAL: Enables SOPS decryption

resources:
  - ./namespace.yaml
  - ./minio-operator/ks.yaml
  - ./minio-tenant/ks.yaml
#% endif %#
```

**Top-level `apps/kustomization.yaml.j2` integration:**

```yaml
resources:
  - ./cert-manager
  #% if minio_enabled | default(false) %#
  - ./storage
  #% endif %#
  #% if monitoring_enabled | default(false) %#
  - ./monitoring
  #% endif %#
```

### 2.5 ❌ Missing plugin.py Derived Variable Logic

**Problem:** The research document doesn't include plugin.py updates for derived variables.

**Solution:** Add to `templates/scripts/plugin.py`:

```python
# MinIO shared storage - enabled when minio_enabled is true
# When MinIO is enabled, Loki can use S3 backend for SimpleScalable mode
minio_enabled = data.get("minio_enabled", False)
if minio_enabled:
    # Set default storage class for MinIO if not specified
    data.setdefault("minio_storage_class", data.get("storage_class", "local-path"))

    # Loki deployment mode is SimpleScalable when MinIO is available
    if data.get("loki_enabled"):
        data["loki_deployment_mode"] = "SimpleScalable"
else:
    # Loki uses SingleBinary mode without S3 storage
    if data.get("loki_enabled"):
        data["loki_deployment_mode"] = "SingleBinary"
```

---

## Part 3: Moderate Updates Recommended

### 3.1 ⚠️ MinIO Operator Version Update

**Issue:** Document references older image tags.

**Current Stable Versions (January 2026):**

- MinIO Operator: v7.1.1
- MinIO Server: RELEASE.2025-01-xx (verify latest)

**Required Changes:**

1. Update Operator Helm chart reference
2. Verify Tenant CR schema compatibility with v7.x
3. Remove references to deprecated `spec.features` section (removed in v7.0.0)

### 3.2 ⚠️ OCI Repository URL Verification

**Issue:** Need to verify MinIO Helm chart OCI location.

**Verified URLs:**

```yaml
# MinIO Operator (verify current version)
url: oci://quay.io/minio/operator
tag: "v7.1.1"

# Alternative: Helm repository
url: https://operator.min.io
```

### 3.3 ⚠️ Health Check Patterns

**Issue:** Research document lacks Flux Kustomization health check patterns.

**Add to `minio-operator/ks.yaml.j2`:**

```yaml
spec:
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: minio-operator
      namespace: storage
  healthCheckExprs:
    - apiVersion: apps/v1
      kind: Deployment
      name: minio-operator
      namespace: storage
      current: status.readyReplicas == status.replicas
```

**Add to `minio-tenant/ks.yaml.j2`:**

```yaml
spec:
  healthChecks:
    - apiVersion: minio.min.io/v2
      kind: Tenant
      name: minio
      namespace: storage
```

### 3.4 ⚠️ Cross-Namespace Dependencies

**Issue:** Loki needs to depend on MinIO Tenant being ready.

**Update `monitoring/loki/ks.yaml.j2`:**

```yaml
#% if minio_enabled | default(false) %#
spec:
  dependsOn:
    - name: kube-prometheus-stack
    - name: minio-tenant
      namespace: storage  # Cross-namespace dependency
#% else %#
spec:
  dependsOn:
    - name: kube-prometheus-stack
#% endif %#
```

---

## Part 4: Minor Enhancements (Optional)

### 4.1 ℹ️ Reduced Initial Replicas

For initial testing, consider starting with minimal replicas:

```yaml
# Loki SimpleScalable - minimal
read:
  replicas: 1
write:
  replicas: 1
backend:
  replicas: 1
```

Scale up once validated.

### 4.2 ℹ️ MinIO Grafana Dashboard

Add MinIO dashboard for monitoring:

```yaml
# In kube-prometheus-stack HelmRelease additional values
grafana:
  dashboards:
    default:
      minio:
        gnetId: 13502
        revision: 2
        datasource: Prometheus
```

### 4.3 ℹ️ ServiceMonitor for MinIO

Add ServiceMonitor for MinIO metrics scraping:

```yaml
# minio-tenant/app/servicemonitor.yaml.j2
#% if minio_enabled | default(false) and monitoring_enabled | default(false) %#
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: minio
  namespace: storage
spec:
  selector:
    matchLabels:
      app: minio
  endpoints:
    - port: http
      path: /minio/v2/metrics/cluster
      interval: 30s
#% endif %#
```

### 4.4 ℹ️ Network Policy Integration

If `network_policies_enabled: true`, add CiliumNetworkPolicy:

```yaml
# storage/network-policies/app/minio.yaml.j2
#% if network_policies_enabled | default(false) and minio_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: minio-ingress
  namespace: storage
spec:
  endpointSelector:
    matchLabels:
      app: minio
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
```

---

## Part 5: Revised Configuration Schema

### cluster.yaml Variables (Updated)

```yaml
# =============================================================================
# MINIO SHARED OBJECT STORAGE - S3-compatible storage for cluster services
# =============================================================================
# MinIO provides shared S3-compatible storage for Loki, Tempo, backups, and
# future applications. Uses MinIO Operator for lifecycle management.
# When enabled, Loki automatically switches to SimpleScalable mode with S3.
# REF: https://min.io/docs/minio/kubernetes/upstream/

# -- Enable MinIO shared storage
#    When enabled, Loki uses SimpleScalable mode with S3 backend
#    (OPTIONAL) / (DEFAULT: false)
# minio_enabled: false

# -- MinIO storage size per server (PV size)
#    (OPTIONAL) / (DEFAULT: "50Gi")
# minio_storage_size: "50Gi"

# -- Number of MinIO servers (2 or 4 recommended for erasure coding)
#    (OPTIONAL) / (DEFAULT: 2)
# minio_replicas: 2

# -- Number of drives per server (affects erasure coding)
#    (OPTIONAL) / (DEFAULT: 1)
# minio_volumes_per_server: 1

# -- MinIO root admin username
#    (OPTIONAL) / (DEFAULT: "minio")
# minio_root_user: "minio"

# -- MinIO root admin password (SOPS-encrypted)
#    (REQUIRED when minio_enabled)
# minio_root_password: ""

# -- Loki S3 access key (service account username)
#    (OPTIONAL) / (DEFAULT: "loki-user")
# loki_s3_access_key: "loki-user"

# -- Loki S3 secret key (SOPS-encrypted)
#    (REQUIRED when minio_enabled and loki_enabled)
# loki_s3_secret_key: ""

# -- Tempo S3 access key (service account username)
#    (OPTIONAL) / (DEFAULT: "tempo-user")
# tempo_s3_access_key: "tempo-user"

# -- Tempo S3 secret key (SOPS-encrypted)
#    (REQUIRED when minio_enabled and tracing_enabled)
# tempo_s3_secret_key: ""
```

---

## Part 6: Implementation Checklist

### Phase 1: Infrastructure Setup

- [ ] Add MinIO configuration section to `cluster.sample.yaml`
- [ ] Update `templates/scripts/plugin.py` with derived variables
- [ ] Create `templates/config/kubernetes/apps/storage/` directory structure
- [ ] Add `storage/namespace.yaml.j2`
- [ ] Add `storage/kustomization.yaml.j2`

### Phase 2: MinIO Operator

- [ ] Create `storage/minio-operator/ks.yaml.j2`
- [ ] Create `storage/minio-operator/app/kustomization.yaml.j2`
- [ ] Create `storage/minio-operator/app/ocirepository.yaml.j2`
- [ ] Create `storage/minio-operator/app/helmrelease.yaml.j2`

### Phase 3: MinIO Tenant

- [ ] Create `storage/minio-tenant/ks.yaml.j2`
- [ ] Create `storage/minio-tenant/app/kustomization.yaml.j2`
- [ ] Create `storage/minio-tenant/app/tenant.yaml.j2` (with buckets and users)
- [ ] Create `storage/minio-tenant/app/secret.sops.yaml.j2`

### Phase 4: Loki Integration

- [ ] Update `monitoring/loki/app/helmrelease.yaml.j2` with conditional S3 config
- [ ] Add `monitoring/loki/app/secret.sops.yaml.j2` for S3 credentials
- [ ] Update `monitoring/loki/ks.yaml.j2` with MinIO dependency

### Phase 5: Top-Level Integration

- [ ] Update `templates/config/kubernetes/apps/kustomization.yaml.j2`
- [ ] Update documentation (CLAUDE.md, CONFIGURATION.md)

### Phase 6: Validation

- [ ] Run `task configure`
- [ ] Verify generated files in `kubernetes/apps/storage/`
- [ ] Deploy to cluster
- [ ] Verify MinIO health
- [ ] Verify Loki SimpleScalable components
- [ ] Verify Grafana dashboards show data

---

## Sources

- [MinIO Operator GitHub Releases](https://github.com/minio/operator/releases) - v7.1.1 changes
- [MinIO Tenant Helm Charts](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-minio-tenant-helm.html)
- [Loki SimpleScalable Installation](https://grafana.com/docs/loki/latest/setup/install/helm/install-scalable/)
- [Loki Storage Configuration](https://grafana.com/docs/loki/latest/setup/install/helm/configure-storage/)
- [Loki Helm Chart 6.x Upgrade Guide](https://grafana.com/docs/loki/latest/setup/upgrade/upgrade-to-6x/)
- [Loki Helm Chart 6.49.0](https://artifacthub.io/packages/helm/grafana/loki)
- [GitHub Issue #11390 - Loki Dashboard Job Labels](https://github.com/grafana/loki/issues/11390)

---

## Conclusion

The research document provides a **solid architectural foundation** for MinIO shared storage and Loki SimpleScalable migration. The core decisions are validated and recommended for implementation.

**Key Actions Required:**

1. Replace Helm hook Job with declarative Tenant CR buckets/users
2. Restructure templates to match project patterns
3. Add missing namespace infrastructure files
4. Update plugin.py with derived variable logic
5. Add missing `admin` bucket for Loki

Once these revisions are implemented, the solution will integrate seamlessly with the project's GitOps workflow and feel natively engrained from the start.
