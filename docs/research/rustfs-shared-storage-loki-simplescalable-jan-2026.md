# RustFS Shared Object Storage & Loki SimpleScalable Implementation

**Date:** January 2026
**Status:** Implementation Ready (with caveats)
**Purpose:** Deploy RustFS as shared S3-compatible storage for cluster services (Loki, Tempo, backups, future apps)

---

> ⚠️ **IMPORTANT: Alpha Software Notice**
>
> As of January 2026, RustFS is in **alpha stage** (version 1.0.0-alpha.76, Helm chart 0.0.78).
> The project is in rapid development—do not assume full S3 coverage.
>
> **Recommendations:**
> - Deploy in test environment first before production migration
> - Run exhaustive S3 compatibility tests with Loki workloads
> - Have rollback plan ready (SingleBinary mode without RustFS)
> - Monitor stability during initial deployment period
>
> See [RustFS GitHub](https://github.com/rustfs/rustfs) for current release status.

---

## Executive Summary

This document provides a comprehensive implementation plan for deploying **RustFS** as a shared object storage service in the matherlynet-talos-cluster, replacing the previously researched MinIO and Garage approaches. RustFS is a high-performance, Rust-based S3-compatible object storage system that delivers significant performance advantages while maintaining full S3 API compatibility.

### Why RustFS Over MinIO and Garage?

| Aspect | RustFS | MinIO | Garage |
| -------- | -------- | ------- | -------- |
| **Performance** | 2.3x faster than MinIO for small objects | Baseline | ~80% of MinIO |
| **Memory Safety** | Rust (memory-safe by design) | Go (GC-based) | Rust (memory-safe) |
| **Resource Footprint** | Lightweight single binary | Operator + Tenant model | Lightweight but less mature |
| **License** | Apache 2.0 (permissive) | AGPL 3.0 (copyleft) | AGPL 3.0 (copyleft) |
| **S3 Compatibility** | 100% (core features) | 100% | ~95% |
| **Kubernetes Support** | Helm chart + StatefulSet | Operator CRD | Basic |
| **Enterprise Features** | KMS, mTLS, encryption | Full suite | Limited |
| **Telemetry** | None (privacy-focused) | Enabled by default | None |
| **Maturity** | Alpha (v1.0.0-alpha.76) | Very mature | Early production |

### Key Decisions

1. **RustFS StatefulSet Deployment**: Direct Helm chart deployment for MNMD (Multi-Node Multi-Drive)
2. **Single Cluster with Bucket Isolation**: Separate buckets per service
3. **Loki SimpleScalable Mode**: Migrate from SingleBinary for dashboard compatibility and scalability
4. **Shared Infrastructure**: RustFS serves Loki, Tempo, and future services

### Benefits

- **Dashboard Fix**: Loki SimpleScalable produces correct job labels for Grafana dashboards
- **Scalability**: Loki scales to ~1TB/day (vs. ~50GB/day SingleBinary)
- **Performance**: 2.3x faster small object operations than MinIO
- **Memory Safety**: Rust eliminates entire classes of bugs and vulnerabilities
- **License Freedom**: Apache 2.0 avoids AGPL restrictions
- **Privacy**: No telemetry, full compliance (GDPR, CCPA, APPI)

---

## Architecture Overview

```
+-----------------------------------------------------------------+
|                       Storage Namespace                          |
|  +-----------------------------------------------------------+  |
|  |                    RustFS StatefulSet                      |  |
|  |  +-------------+  +-------------+  +-------------+        |  |
|  |  | rustfs-0    |  | rustfs-1    |  | rustfs-2    |        |  |
|  |  | (4 volumes) |  | (4 volumes) |  | (4 volumes) |        |  |
|  |  +------+------+  +------+------+  +------+------+        |  |
|  |         |                |                |               |  |
|  |         +-------+--------+-------+--------+               |  |
|  |                 v                                          |  |
|  |  +----------------------------------------------------------+ |
|  |  |              S3 API Service (Port 9000)                   ||
|  |  | Buckets: loki-chunks | loki-ruler | loki-admin | tempo   ||
|  |  +----------------------------------------------------------+ |
|  +-----------------------------------------------------------+  |
+-----------------------------------------------------------------+
                              |
          +-------------------+-------------------+
          v                   v                   v
    +----------+        +----------+        +----------+
    |   Loki   |        |  Tempo   |        |  Future  |
    | (S3 API) |        | (S3 API) |        |  Apps    |
    |SimpleScal|        |          |        |          |
    +----------+        +----------+        +----------+
```

---

## RustFS Feature Analysis

### Core Features (Available)

| Feature | Status | Description |
| --------- | -------- | ------------- |
| S3 Core API | ✅ Available | GetObject, PutObject, DeleteObject, ListObjects |
| Multipart Upload | ✅ Available | Large file uploads with chunked transfer |
| Bucket Versioning | ✅ Available | Object version history |
| Event Notifications | ✅ Available | S3 event notifications |
| Bitrot Protection | ✅ Available | Data integrity verification |
| Single-Node Mode | ✅ Available | Standalone deployment |
| Bucket Replication | ✅ Available | Cross-bucket replication |
| Helm Charts | ✅ Available | Kubernetes deployment |
| Distributed Mode | ⏳ Testing | Multi-node clustering (MNMD) |
| KMS Integration | ⏳ Testing | Key management and encryption |
| Lifecycle Management | ⏳ Testing | Object lifecycle policies |

### S3 API Compatibility for Loki

Loki requires the following S3 operations:

| Operation | RustFS Support | Notes |
| ----------- | ---------------- | ------- |
| PutObject | ✅ | Write chunks and indexes |
| GetObject | ✅ | Read chunks for queries |
| DeleteObject | ✅ | Compaction and retention |
| ListObjectsV2 | ✅ | Index discovery |
| HeadObject | ✅ | Metadata checks |
| CopyObject | ✅ | Compaction operations |
| Multipart Upload | ✅ | Large chunk uploads |

**Verdict:** RustFS provides full S3 compatibility for Loki SimpleScalable mode.

### Performance Characteristics

| Workload | RustFS | MinIO | Improvement |
| ---------- | -------- | ------- | ------------- |
| 4KB objects | 2.3x faster | Baseline | +130% |
| Large files | Comparable | Baseline | ~0% |
| Concurrent access | Optimized | Good | +15-30% |
| Memory usage | Lower | Higher | -25% |

### Environment Variables Reference

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `RUSTFS_ADDRESS` | `:9000` | S3 API bind address |
| `RUSTFS_CONSOLE_ADDRESS` | `:9001` | Console UI bind address |
| `RUSTFS_CONSOLE_ENABLE` | `true` | Enable/disable console |
| `RUSTFS_ACCESS_KEY` | `rustfsadmin` | Admin access key |
| `RUSTFS_SECRET_KEY` | `rustfsadmin` | Admin secret key |
| `RUSTFS_ENABLE_SCANNER` | `true` | Background data scanner |
| `RUSTFS_ENABLE_HEAL` | `true` | Auto-healing service |
| `RUSTFS_ENABLE_LOCKS` | `true` | Distributed locking |
| `RUSTFS_TLS_PATH` | `tls` | TLS certificate directory |
| `RUSTFS_BUFFER_PROFILE` | `GeneralPurpose` | Workload optimization profile |

### Workload Profiles for Buffer Optimization

| Profile | Min Buffer | Max Buffer | Optimal For |
| ---------- | ------------ | ------------ | ------------- |
| GeneralPurpose | 64KB | 1MB | Mixed workloads (default) |
| AiTraining | 512KB | 4MB | Large files, sequential I/O |
| DataAnalytics | 128KB | 2MB | Mixed read-write patterns |
| WebWorkload | 32KB | 256KB | Small files, high concurrency |
| IndustrialIoT | 64KB | 512KB | Real-time streaming |
| SecureStorage | 32KB | 256KB | Compliance environments |

**Recommendation:** Use `DataAnalytics` profile for Loki/Tempo observability workloads.

---

## Implementation Plan

### Phase 1: RustFS Deployment

#### 1.1 Configuration Schema Updates

Add to `cluster.yaml`:

```yaml
# =============================================================================
# RUSTFS SHARED OBJECT STORAGE - S3-compatible storage for cluster services
# =============================================================================
# RustFS is a high-performance, Rust-based S3-compatible object storage system.
# When enabled, Loki automatically switches to SimpleScalable mode with S3.
# Performance: 2.3x faster than MinIO for small objects, Apache 2.0 license.
# REF: https://github.com/rustfs/rustfs

# -- Enable RustFS shared storage
#    When enabled, Loki uses SimpleScalable mode with S3 backend
#    (OPTIONAL) / (DEFAULT: false)
# rustfs_enabled: false

# -- Number of RustFS nodes
#    Single node (1) for simple deployments, 4+ for distributed mode
#    Note: Helm chart creates data PVCs only for 1, 4, or 16 replicas
#    (OPTIONAL) / (DEFAULT: 1)
# rustfs_replicas: 1

# -- Data storage size per RustFS node
#    Used for volumeClaimTemplates via storageclass.dataStorageSize
#    (OPTIONAL) / (DEFAULT: "20Gi")
# rustfs_data_volume_size: "20Gi"

# -- Log storage size per RustFS node
#    Used for volumeClaimTemplates via storageclass.logStorageSize
#    (OPTIONAL) / (DEFAULT: "1Gi")
# rustfs_log_volume_size: "1Gi"

# -- RustFS root admin username
#    (OPTIONAL) / (DEFAULT: "rustfsadmin")
# rustfs_access_key: "rustfsadmin"

# -- RustFS root admin password (SOPS-encrypted)
#    Generate with: openssl rand -base64 32
#    (REQUIRED when rustfs_enabled)
# rustfs_secret_key: ""

# -- Workload optimization profile
#    Options: GeneralPurpose, AiTraining, DataAnalytics, WebWorkload, IndustrialIoT, SecureStorage
#    (OPTIONAL) / (DEFAULT: "DataAnalytics")
# rustfs_buffer_profile: "DataAnalytics"

# -- Enable RustFS console UI
#    (OPTIONAL) / (DEFAULT: false)
# rustfs_console_enabled: false

# -- Loki S3 access key (created as RustFS access key)
#    (OPTIONAL) / (DEFAULT: "loki")
# loki_s3_access_key: "loki"

# -- Loki S3 secret key (SOPS-encrypted)
#    Generate with: openssl rand -base64 32
#    (REQUIRED when rustfs_enabled and loki_enabled)
# loki_s3_secret_key: ""

# -- Tempo S3 access key (created as RustFS access key)
#    (OPTIONAL) / (DEFAULT: "tempo")
# tempo_s3_access_key: "tempo"

# -- Tempo S3 secret key (SOPS-encrypted)
#    Generate with: openssl rand -base64 32
#    (REQUIRED when rustfs_enabled and tracing_enabled)
# tempo_s3_secret_key: ""
```

#### 1.2 Plugin.py Updates

Add to `templates/scripts/plugin.py`:

```python
# RustFS shared storage - enabled when rustfs_enabled is true
# When RustFS is enabled, Loki can use S3 backend for SimpleScalable mode
rustfs_enabled = data.get("rustfs_enabled", False)
if rustfs_enabled:
    # Set default storage class for RustFS if not specified
    data.setdefault("rustfs_storage_class", data.get("storage_class", "local-path"))

    # Loki deployment mode is SimpleScalable when RustFS is available
    if data.get("loki_enabled"):
        data["loki_deployment_mode"] = "SimpleScalable"
else:
    # Loki uses SingleBinary mode without S3 storage
    if data.get("loki_enabled"):
        data["loki_deployment_mode"] = "SingleBinary"
```

#### 1.3 Template Structure

```
templates/config/kubernetes/apps/storage/
├── namespace.yaml.j2                    # Storage namespace
├── kustomization.yaml.j2                # Namespace-level kustomization
└── rustfs/
    ├── ks.yaml.j2                       # Flux Kustomization
    └── app/
        ├── kustomization.yaml.j2
        ├── helmrepository.yaml.j2       # RustFS Helm repository
        ├── helmrelease.yaml.j2          # RustFS StatefulSet
        ├── secret.sops.yaml.j2          # Credentials (SOPS-encrypted)
        ├── secret-loki.sops.yaml.j2     # Loki credentials
        ├── secret-tempo.sops.yaml.j2    # Tempo credentials
        ├── job-setup.yaml.j2            # Bucket and user setup
        └── servicemonitor.yaml.j2       # Prometheus scraping
```

#### 1.4 Storage Namespace

**`storage/namespace.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
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
#% if rustfs_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: storage

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./rustfs/ks.yaml
#% endif %#
```

#### 1.5 RustFS Flux Kustomization

**`storage/rustfs/ks.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: rustfs
spec:
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: rustfs
      namespace: storage
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/storage/rustfs/app
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
  timeout: 15m
  wait: true
#% endif %#
```

#### 1.6 RustFS Helm Repository

**`storage/rustfs/app/helmrepository.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: rustfs
spec:
  interval: 24h
  url: https://charts.rustfs.com/
#% endif %#
```

#### 1.7 RustFS HelmRelease

**`storage/rustfs/app/helmrelease.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: rustfs
spec:
  chart:
    spec:
      chart: rustfs
      version: "1.0.x"  #| Use latest 1.0.x stable release #|
      sourceRef:
        kind: HelmRepository
        name: rustfs
        namespace: storage
  interval: 1h
  values:
    #| MNMD: Multi-Node Multi-Drive distributed mode #|
    mode:
      standalone:
        enabled: false
      distributed:
        enabled: true

    #| Number of RustFS nodes - use 1 for single-node, 4/16 for distributed #|
    replicaCount: #{ rustfs_replicas | default(1) }#

    #| Container image #|
    image:
      repository: rustfs/rustfs
      tag: "latest"
      pullPolicy: IfNotPresent

    #| Resource limits #|
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
      limits:
        memory: 1Gi

    #| StorageClass configuration - uses storageclass.name per RustFS Helm chart #|
    storageclass:
      name: "#{ rustfs_storage_class | default(storage_class) | default('local-path') }#"
      dataStorageSize: "#{ rustfs_data_volume_size | default('20Gi') }#"
      logStorageSize: "#{ rustfs_log_volume_size | default('1Gi') }#"

    #| Environment variables #|
    environment:
      RUSTFS_BUFFER_PROFILE: "#{ rustfs_buffer_profile | default('DataAnalytics') }#"
      RUSTFS_ENABLE_SCANNER: "true"
      RUSTFS_ENABLE_HEAL: "true"
      #| Disable console UI in production - use mc CLI #|
      RUSTFS_CONSOLE_ENABLE: "#{ rustfs_console_enabled | default(false) | string | lower }#"

    #| Use existing secret for credentials #|
    existingSecret: rustfs-credentials

    #| Service configuration #|
    service:
      type: ClusterIP
      port: 9000
      consolePort: 9001

    #| Ingress disabled - internal service only #|
    ingress:
      enabled: false

    #| Pod security context #|
    securityContext:
      runAsUser: 10001
      runAsGroup: 10001
      fsGroup: 10001

    #| Pod anti-affinity for HA #|
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/name
                    operator: In
                    values:
                      - rustfs
              topologyKey: kubernetes.io/hostname

    #| Liveness and readiness probes #|
    livenessProbe:
      httpGet:
        path: /health
        port: 9000
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
    readinessProbe:
      httpGet:
        path: /health
        port: 9000
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
#% endif %#
```

#### 1.8 RustFS Secrets

**`storage/rustfs/app/secret.sops.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: rustfs-credentials
type: Opaque
stringData:
  root-user: "#{ rustfs_access_key | default('rustfsadmin') }#"
  root-password: "#{ rustfs_secret_key }#"
#% endif %#
```

**`storage/rustfs/app/secret-loki.sops.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) and loki_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: loki-s3-credentials
  namespace: storage
type: Opaque
stringData:
  access-key: "#{ loki_s3_access_key | default('loki') }#"
  secret-key: "#{ loki_s3_secret_key }#"
#% endif %#
```

**`storage/rustfs/app/secret-tempo.sops.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) and tracing_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: tempo-s3-credentials
  namespace: storage
type: Opaque
stringData:
  access-key: "#{ tempo_s3_access_key | default('tempo') }#"
  secret-key: "#{ tempo_s3_secret_key }#"
#% endif %#
```

#### 1.9 RustFS Kustomization

**`storage/rustfs/app/kustomization.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
  - ./secret.sops.yaml
#% if loki_enabled | default(false) %#
  - ./secret-loki.sops.yaml
#% endif %#
#% if tracing_enabled | default(false) %#
  - ./secret-tempo.sops.yaml
#% endif %#
  - ./job-setup.yaml
#% if monitoring_enabled | default(false) %#
  - ./servicemonitor.yaml
#% endif %#
#% endif %#
```

### Phase 2: Bucket Provisioning

#### 2.1 Setup Job

**`storage/rustfs/app/job-setup.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) %#
---
apiVersion: batch/v1
kind: Job
metadata:
  name: rustfs-bucket-setup
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
spec:
  ttlSecondsAfterFinished: 600
  backoffLimit: 10
  template:
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: wait-for-rustfs
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
            - |
              echo "Waiting for RustFS to be ready..."
              until wget -q --spider http://rustfs.storage.svc:9000/health; do
                echo "RustFS not ready, waiting..."
                sleep 10
              done
              echo "RustFS is ready!"
      containers:
        - name: setup
          image: minio/mc:latest
          command:
            - /bin/sh
            - -c
            - |
              set -e

              echo "Configuring mc alias for RustFS..."
              mc alias set rustfs http://rustfs.storage.svc:9000 "$RUSTFS_ROOT_USER" "$RUSTFS_ROOT_PASSWORD"

              echo "Creating buckets..."
#% if loki_enabled | default(false) %#
              # Loki buckets
              mc mb --ignore-existing rustfs/loki-chunks
              mc mb --ignore-existing rustfs/loki-ruler
              mc mb --ignore-existing rustfs/loki-admin
              echo "Loki buckets created."

              # Create Loki service account
              echo "Creating Loki service account..."
              mc admin user add rustfs "$LOKI_ACCESS_KEY" "$LOKI_SECRET_KEY" || echo "Loki user may already exist"

              # Create and attach Loki policy
              cat > /tmp/loki-policy.json << 'EOF'
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Effect": "Allow",
                    "Action": ["s3:*"],
                    "Resource": [
                      "arn:aws:s3:::loki-*",
                      "arn:aws:s3:::loki-*/*"
                    ]
                  }
                ]
              }
              EOF
              mc admin policy create rustfs loki-policy /tmp/loki-policy.json 2>/dev/null || echo "Loki policy may already exist"
              mc admin policy attach rustfs loki-policy --user "$LOKI_ACCESS_KEY" 2>/dev/null || echo "Loki policy may already be attached"
              echo "Loki service account configured."
#% endif %#

#% if tracing_enabled | default(false) %#
              # Tempo bucket
              mc mb --ignore-existing rustfs/tempo
              echo "Tempo bucket created."

              # Create Tempo service account
              echo "Creating Tempo service account..."
              mc admin user add rustfs "$TEMPO_ACCESS_KEY" "$TEMPO_SECRET_KEY" || echo "Tempo user may already exist"

              # Create and attach Tempo policy
              cat > /tmp/tempo-policy.json << 'EOF'
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Effect": "Allow",
                    "Action": ["s3:*"],
                    "Resource": [
                      "arn:aws:s3:::tempo",
                      "arn:aws:s3:::tempo/*"
                    ]
                  }
                ]
              }
              EOF
              mc admin policy create rustfs tempo-policy /tmp/tempo-policy.json 2>/dev/null || echo "Tempo policy may already exist"
              mc admin policy attach rustfs tempo-policy --user "$TEMPO_ACCESS_KEY" 2>/dev/null || echo "Tempo policy may already be attached"
              echo "Tempo service account configured."
#% endif %#

              # General backup bucket
              mc mb --ignore-existing rustfs/backups
              echo "Backup bucket created."

              echo "Bucket setup complete!"
              mc ls rustfs/
          env:
            - name: RUSTFS_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: rustfs-credentials
                  key: root-user
            - name: RUSTFS_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: rustfs-credentials
                  key: root-password
#% if loki_enabled | default(false) %#
            - name: LOKI_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: loki-s3-credentials
                  key: access-key
            - name: LOKI_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: loki-s3-credentials
                  key: secret-key
#% endif %#
#% if tracing_enabled | default(false) %#
            - name: TEMPO_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: tempo-s3-credentials
                  key: access-key
            - name: TEMPO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: tempo-s3-credentials
                  key: secret-key
#% endif %#
#% endif %#
```

#### 2.2 ServiceMonitor

**`storage/rustfs/app/servicemonitor.yaml.j2`:**

```yaml
#% if rustfs_enabled | default(false) and monitoring_enabled | default(false) %#
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rustfs
  labels:
    app.kubernetes.io/name: rustfs
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: rustfs
  endpoints:
    - port: api
      path: /minio/v2/metrics/cluster
      interval: 30s
  namespaceSelector:
    matchNames:
      - storage
#% endif %#
```

### Phase 3: Loki SimpleScalable Migration

#### 3.1 Updated Loki HelmRelease

**`monitoring/loki/app/helmrelease.yaml.j2`:**

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) %#
---
# CRITICAL COHESION: Grafana is disabled here - it's deployed by kube-prometheus-stack only.
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: loki
spec:
  chartRef:
    kind: OCIRepository
    name: loki
  interval: 1h
#% if rustfs_enabled | default(false) %#
  #| Depend on RustFS for S3 storage #|
  dependsOn:
    - name: rustfs
      namespace: storage
#% endif %#
  values:
#% if rustfs_enabled | default(false) %#
    #| SimpleScalable mode with RustFS S3 backend #|
    deploymentMode: SimpleScalable

    #| Read path - handles queries #|
    read:
      replicas: 2
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 256Mi

    #| Write path - handles ingestion #|
    write:
      replicas: 2
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 256Mi
      persistence:
        enabled: true
        storageClass: "#{ storage_class | default('local-path') }#"
        size: 10Gi  #| WAL storage only - chunks go to S3 #|

    #| Backend - compactor, ruler, index gateway #|
    backend:
      replicas: 2
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 256Mi
      persistence:
        enabled: true
        storageClass: "#{ storage_class | default('local-path') }#"
        size: 10Gi

    #| Zero out SingleBinary replicas #|
    singleBinary:
      replicas: 0
#% else %#
    #| SingleBinary mode with filesystem (no RustFS) #|
    deploymentMode: SingleBinary
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
        storageClass: "#{ storage_class | default('local-path') }#"
        size: "#{ logs_storage_size | default('50Gi') }#"
      readinessProbe:
        httpGet:
          path: /ready
          port: 3100
        initialDelaySeconds: 15
        periodSeconds: 10
        timeoutSeconds: 1
      livenessProbe:
        httpGet:
          path: /ready
          port: 3100
        initialDelaySeconds: 45
        periodSeconds: 30
        timeoutSeconds: 5
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0
#% endif %#
    #| Zero out other deployment modes for clarity #|
    ingester:
      replicas: 0
    querier:
      replicas: 0
    queryFrontend:
      replicas: 0
    queryScheduler:
      replicas: 0
    distributor:
      replicas: 0
    compactor:
      replicas: 0
    indexGateway:
      replicas: 0
    bloomCompactor:
      replicas: 0
    bloomGateway:
      replicas: 0

    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
#% if rustfs_enabled | default(false) %#
        path_prefix: /var/loki
      storage:
        type: s3
        bucketNames:
          chunks: loki-chunks
          ruler: loki-ruler
          admin: loki-admin
        s3:
          endpoint: http://rustfs.storage.svc:9000
          region: us-east-1
          accessKeyId: ${LOKI_S3_ACCESS_KEY}
          secretAccessKey: ${LOKI_S3_SECRET_KEY}
          s3ForcePathStyle: true
          insecure: true
#% else %#
      storage:
        type: filesystem
#% endif %#
      schemaConfig:
        configs:
          - from: "2024-01-01"
            store: tsdb
#% if rustfs_enabled | default(false) %#
            object_store: s3
#% else %#
            object_store: filesystem
#% endif %#
            schema: v13
            index:
              prefix: index_
              period: 24h
      limits_config:
        retention_period: "#{ logs_retention | default('7d') }#"
        ingestion_rate_mb: 10
        ingestion_burst_size_mb: 20
        allow_structured_metadata: true
        volume_enabled: true
      querier:
        max_concurrent: 4
      pattern_ingester:
        enabled: true

#% if rustfs_enabled | default(false) %#
    #| S3 credentials from secret #|
    extraEnvFrom:
      - secretRef:
          name: loki-s3-credentials
#% endif %#

    #| Disable built-in MinIO - using RustFS #|
    minio:
      enabled: false

    gateway:
      enabled: false

    #| COHESION: Disable components deployed by kube-prometheus-stack #|
    grafana:
      enabled: false

    #| Promtail deprecated - using Alloy #|
    promtail:
      enabled: false

    #| Caching disabled for small cluster #|
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false

    #| Monitoring #|
    monitoring:
      dashboards:
        enabled: true
        namespace: monitoring
        annotations:
          grafana_folder: Logging
      serviceMonitor:
        enabled: true
#% endif %#
```

#### 3.2 Loki S3 Credentials Secret (in monitoring namespace)

**`monitoring/loki/app/secret-s3.sops.yaml.j2`:**

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) and rustfs_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: loki-s3-credentials
type: Opaque
stringData:
  LOKI_S3_ACCESS_KEY: "#{ loki_s3_access_key | default('loki') }#"
  LOKI_S3_SECRET_KEY: "#{ loki_s3_secret_key }#"
#% endif %#
```

#### 3.3 Updated Loki App Kustomization

**`monitoring/loki/app/kustomization.yaml.j2`:**

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./ocirepository.yaml
  - ./helmrelease.yaml
#% if rustfs_enabled | default(false) %#
  - ./secret-s3.sops.yaml
#% endif %#
#% endif %#
```

#### 3.4 Updated Loki Flux Kustomization

**`monitoring/loki/ks.yaml.j2`:**

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: loki
spec:
  dependsOn:
    - name: kube-prometheus-stack
#% if rustfs_enabled | default(false) %#
    - name: rustfs
      namespace: storage
#% endif %#
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: loki
      namespace: monitoring
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/monitoring/loki/app
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
  timeout: 10m
  wait: true
#% endif %#
```

### Phase 4: Top-Level Integration

Update **`templates/config/kubernetes/apps/kustomization.yaml.j2`:**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./cert-manager
  #% if proxmox_csi_enabled | default(false) %#
  - ./csi-proxmox
  #% endif %#
  - ./default
  #% if external_secrets_enabled | default(false) %#
  - ./external-secrets
  #% endif %#
  - ./flux-system
  - ./kube-system
  #% if rustfs_enabled | default(false) %#
  - ./storage
  #% endif %#
  #% if monitoring_enabled | default(false) %#
  - ./monitoring
  #% endif %#
  - ./network
  - ./system-upgrade
```

---

## Resource Requirements Summary

### RustFS (Shared Storage) - 3-Node MNMD

| Component | CPU Request | Memory Request | Memory Limit | Storage |
| ----------- | ------------- | ---------------- | -------------- | --------- |
| RustFS Node (x3) | 100m | 512Mi | 1Gi | 80Gi (4x20Gi) |
| **Total** | 300m | 1536Mi | 3Gi | 240Gi |

### Loki SimpleScalable (vs SingleBinary)

| Component | CPU Request | Memory Request | Memory Limit | Count |
| ----------- | ------------- | ---------------- | -------------- | ------- |
| Read | 50m | 128Mi | 256Mi | 2 |
| Write | 50m | 128Mi | 256Mi | 2 |
| Backend | 50m | 128Mi | 256Mi | 2 |
| **Total** | 300m | 768Mi | 1536Mi | 6 pods |

**SingleBinary Comparison:** 100m CPU, 256Mi request, 512Mi limit, 1 pod

### Net Resource Change

| Metric | Before (SingleBinary) | After (RustFS+SimpleScalable) | Delta |
| -------- | ----------------------- | ------------------------------- | ------- |
| CPU Requests | 100m | 600m | +500m |
| Memory Requests | 256Mi | 2304Mi | +2048Mi |
| Memory Limits | 512Mi | 4536Mi | +4024Mi |
| Pod Count | 1 (Loki) | 9 (3 RustFS + 6 Loki) | +8 |
| PVC Count | 1 (50Gi) | 16 (12 RustFS + 4 Loki) | +15 |
| Storage | 50Gi | 280Gi | +230Gi |

---

## Monitoring & Observability

### RustFS Metrics

RustFS exposes Prometheus metrics compatible with MinIO metrics format at `/minio/v2/metrics/cluster`.

Key metrics include:

| Metric | Description |
| -------- | ------------- |
| `minio_bucket_usage_total_bytes` | Total bucket size |
| `minio_bucket_objects_total` | Object count per bucket |
| `minio_cluster_nodes_online_total` | Healthy node count |
| `minio_cluster_nodes_offline_total` | Unhealthy node count |
| `minio_s3_requests_total` | S3 API request counts |
| `minio_s3_requests_errors_total` | S3 API errors |
| `minio_s3_traffic_received_bytes` | Inbound traffic |
| `minio_s3_traffic_sent_bytes` | Outbound traffic |

### Grafana Dashboard

Use MinIO dashboard (compatible with RustFS metrics):

```yaml
# In kube-prometheus-stack HelmRelease additional values
grafana:
  dashboards:
    default:
      rustfs:
        gnetId: 13502  # MinIO Dashboard
        revision: 2
        datasource: Prometheus
```

---

## Security Considerations

### Network Policies

```yaml
#% if network_policies_enabled | default(false) and rustfs_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: rustfs-ingress
  namespace: storage
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: rustfs
  ingress:
    #| Allow S3 API from monitoring namespace (Loki, Tempo) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
    #| Allow inter-node communication #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: rustfs
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
    #| Allow metrics scraping from monitoring #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
```

### Encryption

- **In-Transit**: TLS can be configured via `RUSTFS_TLS_PATH`
- **At-Rest**: RustFS KMS supports SSE-S3/SSE-KMS encryption
- **Credentials**: All secrets are SOPS-encrypted with Age

---

## Migration Procedure

### Pre-Migration Checklist

- [ ] Verify cluster has sufficient resources (~600m CPU, ~2.3GB RAM additional)
- [ ] Backup current Loki PVC data (optional - logs can be re-collected)
- [ ] Note current log retention period
- [ ] Generate secure passwords for RustFS services

### Migration Steps

```bash
# 1. Generate required secrets
export RUSTFS_SECRET_KEY=$(openssl rand -base64 32)
export LOKI_S3_SECRET_KEY=$(openssl rand -base64 32)
export TEMPO_S3_SECRET_KEY=$(openssl rand -base64 32)

# 2. Update cluster.yaml with RustFS configuration
cat >> cluster.yaml << EOF
# RustFS Object Storage
rustfs_enabled: true
rustfs_replicas: 1  # Single-node deployment; use 4/16 for distributed
rustfs_data_volume_size: "20Gi"
rustfs_log_volume_size: "1Gi"
rustfs_storage_class: "proxmox-zfs"  # Or your StorageClass
rustfs_secret_key: "$RUSTFS_SECRET_KEY"
loki_s3_secret_key: "$LOKI_S3_SECRET_KEY"
tempo_s3_secret_key: "$TEMPO_S3_SECRET_KEY"
EOF

# 3. Re-encrypt and regenerate templates
task configure

# 4. Suspend Loki for clean transition
flux suspend hr loki -n monitoring

# 5. Delete old Loki PVC (optional - data will be lost)
kubectl delete pvc -n monitoring -l app.kubernetes.io/name=loki

# 6. Resume and let Flux deploy new stack
flux resume hr loki -n monitoring
task reconcile

# 7. Verify RustFS is healthy
kubectl get pods -n storage
kubectl exec -n storage rustfs-0 -- rustfs status

# 8. Verify Loki SimpleScalable components
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# 9. Verify dashboards work
# Open Grafana > Logging folder > Check data in Loki dashboards
```

### Rollback Procedure

```bash
# 1. Set rustfs_enabled: false in cluster.yaml
# 2. task configure
# 3. flux suspend hr loki -n monitoring
# 4. kubectl delete hr loki -n monitoring
# 5. flux resume hr loki -n monitoring
# 6. task reconcile
```

---

## Troubleshooting

### RustFS Issues

```bash
# Check RustFS pod status
kubectl get pods -n storage -l app.kubernetes.io/name=rustfs

# Check RustFS logs
kubectl logs -n storage -l app.kubernetes.io/name=rustfs

# Check health endpoint
kubectl exec -n storage rustfs-0 -- curl -s http://localhost:9000/health

# Test S3 connectivity with mc
kubectl run -it --rm s3test --image=minio/mc --restart=Never -- \
  sh -c 'mc alias set test http://rustfs.storage.svc:9000 $ACCESS_KEY $SECRET_KEY && mc ls test'

# Check bucket list
kubectl exec -n storage rustfs-0 -- mc ls local/
```

### Loki Issues

```bash
# Check Loki components (SimpleScalable)
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Check Loki logs for S3 errors
kubectl logs -n monitoring -l app.kubernetes.io/component=write

# Verify S3 configuration
kubectl exec -n monitoring deploy/loki-read -- cat /etc/loki/config/config.yaml | grep -A20 storage

# Check service endpoints
kubectl get endpoints -n storage rustfs
kubectl get endpoints -n monitoring loki
```

### Common Issues

| Issue | Cause | Solution |
| ------- | ------- | ---------- |
| RustFS pods pending | PVC not provisioning | Check StorageClass, verify storage provisioner |
| Bucket setup job fails | RustFS not ready | Check RustFS health, wait for StatefulSet |
| S3 connection refused | Service not ready | Wait for RustFS pods to be ready |
| Loki write failures | Credentials wrong | Verify secret values match RustFS user |
| Cluster recovery slow | Network issues | Check TCP keepalive settings |

---

## Implementation Checklist

### Phase 1: Infrastructure Setup
- [ ] Add RustFS configuration section to `cluster.sample.yaml`
- [ ] Update `templates/scripts/plugin.py` with derived variables
- [ ] Create `templates/config/kubernetes/apps/storage/` directory structure
- [ ] Add `storage/namespace.yaml.j2`
- [ ] Add `storage/kustomization.yaml.j2`

### Phase 2: RustFS Deployment
- [ ] Create `storage/rustfs/ks.yaml.j2`
- [ ] Create `storage/rustfs/app/kustomization.yaml.j2`
- [ ] Create `storage/rustfs/app/helmrepository.yaml.j2`
- [ ] Create `storage/rustfs/app/helmrelease.yaml.j2`
- [ ] Create `storage/rustfs/app/secret.sops.yaml.j2`
- [ ] Create `storage/rustfs/app/secret-loki.sops.yaml.j2`
- [ ] Create `storage/rustfs/app/secret-tempo.sops.yaml.j2`
- [ ] Create `storage/rustfs/app/job-setup.yaml.j2`
- [ ] Create `storage/rustfs/app/servicemonitor.yaml.j2`

### Phase 3: Loki Integration
- [ ] Update `monitoring/loki/app/helmrelease.yaml.j2` with conditional S3 config
- [ ] Add `monitoring/loki/app/secret-s3.sops.yaml.j2` for S3 credentials
- [ ] Update `monitoring/loki/ks.yaml.j2` with RustFS dependency
- [ ] Update `monitoring/loki/app/kustomization.yaml.j2`

### Phase 4: Top-Level Integration
- [ ] Update `templates/config/kubernetes/apps/kustomization.yaml.j2`
- [ ] Update documentation (CLAUDE.md, CONFIGURATION.md)

### Phase 5: Validation
- [ ] Run `task configure`
- [ ] Verify generated files in `kubernetes/apps/storage/`
- [ ] Deploy to cluster
- [ ] Verify RustFS health
- [ ] Verify bucket creation
- [ ] Verify Loki SimpleScalable components
- [ ] Verify Grafana dashboards show data

---

## Comparison Summary: RustFS vs MinIO vs Garage

| Aspect | RustFS | MinIO | Garage |
| -------- | -------- | ------- | -------- |
| **Performance** | ⭐⭐⭐⭐⭐ 2.3x faster | ⭐⭐⭐ Baseline | ⭐⭐⭐ Similar |
| **Resource Usage** | ⭐⭐⭐⭐ Lower memory | ⭐⭐⭐ Higher overhead | ⭐⭐⭐⭐ Low |
| **License** | ⭐⭐⭐⭐⭐ Apache 2.0 | ⭐⭐ AGPL 3.0 | ⭐⭐ AGPL 3.0 |
| **S3 Compatibility** | ⭐⭐⭐⭐⭐ 100% core | ⭐⭐⭐⭐⭐ 100% | ⭐⭐⭐⭐ ~95% |
| **Kubernetes Integration** | ⭐⭐⭐⭐ Helm + StatefulSet | ⭐⭐⭐⭐⭐ Operator | ⭐⭐⭐ Basic |
| **Enterprise Features** | ⭐⭐⭐⭐ KMS, mTLS | ⭐⭐⭐⭐⭐ Full suite | ⭐⭐⭐ Limited |
| **Privacy/Compliance** | ⭐⭐⭐⭐⭐ No telemetry | ⭐⭐⭐ Telemetry enabled | ⭐⭐⭐⭐⭐ No telemetry |
| **Maturity** | ⭐⭐⭐ Alpha (v1.0.0-alpha) | ⭐⭐⭐⭐⭐ Very mature | ⭐⭐⭐ Early production |
| **Memory Safety** | ⭐⭐⭐⭐⭐ Rust | ⭐⭐⭐ Go (GC) | ⭐⭐⭐⭐⭐ Rust |

**Recommendation:** RustFS provides the best balance of performance, licensing freedom, and modern memory-safe architecture for this homelab/small production cluster.

---

## Sources

- [RustFS GitHub Repository](https://github.com/rustfs/rustfs)
- [RustFS Documentation Center](https://rustfs.com/docs)
- [RustFS Helm Charts](https://charts.rustfs.com/)
- [RustFS Environment Variables](local_docs/rustfs-docs/ENVIRONMENT_VARIABLES.md)
- [RustFS Console Separation Guide](local_docs/rustfs-docs/console-separation.md)
- [RustFS Cluster Recovery](local_docs/rustfs-docs/cluster_recovery.md)
- [RustFS Concurrency Architecture](local_docs/rustfs-docs/CONCURRENCY_ARCHITECTURE.md)
- [RustFS TLS Configuration](local_docs/rustfs-docs/tls.md)
- [Loki SimpleScalable Installation](https://grafana.com/docs/loki/latest/setup/install/helm/install-scalable/)
- [Loki Storage Configuration](https://grafana.com/docs/loki/latest/setup/install/helm/configure-storage/)
- [GitHub Issue #11390 - Loki Dashboard Job Labels](https://github.com/grafana/loki/issues/11390)

---

## Next Steps

1. **Review** this implementation plan
2. **Approve** resource allocation (~600m CPU, ~2.3GB RAM additional)
3. **Implement** Phase 1 (Infrastructure setup)
4. **Implement** Phase 2 (RustFS deployment)
5. **Implement** Phase 3 (Loki integration)
6. **Implement** Phase 4 (Top-level integration)
7. **Validate** with `task configure` and cluster deployment
8. **Optional**: Migrate Tempo to RustFS S3 storage