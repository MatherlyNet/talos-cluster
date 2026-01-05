# Garage Shared Object Storage & Loki SimpleScalable Implementation

**Date:** January 2026
**Status:** Implementation Ready
**Purpose:** Deploy Garage as shared S3-compatible storage for cluster services (Loki, Tempo, backups, future apps)

---

## Executive Summary

This document provides a comprehensive implementation plan for deploying **Garage** as a shared object storage service in the matherlynet-talos-cluster, replacing the previously researched MinIO approach. Garage is a lightweight, geo-distributed S3-compatible object storage solution optimized for self-hosting at small-to-medium scale.

### Why Garage Over MinIO?

| Aspect | Garage | MinIO |
| -------- | -------- | ------- |
| **Resource Footprint** | ~50MB binary, minimal overhead | Operator + Tenant model, higher overhead |
| **Architecture** | Single binary, no external dependencies | Operator CRDs required |
| **Geo-Distribution** | Built-in, core design goal | Requires additional configuration |
| **Complexity** | Simple TOML config | Multiple CRDs and configurations |
| **Kubernetes Integration** | Helm chart with StatefulSet | Operator + Tenant CR pattern |
| **Target Use Case** | Self-hosted, small-medium scale | Enterprise-grade, large scale |

### Key Decisions

1. **Garage StatefulSet Deployment**: Direct Helm chart deployment (no operator)
2. **Single Cluster with Bucket Isolation**: Separate buckets per service
3. **Loki SimpleScalable Mode**: Migrate from SingleBinary for dashboard compatibility and scalability
4. **Shared Infrastructure**: Garage serves Loki, Tempo, and future services

### Benefits

- **Dashboard Fix**: Loki SimpleScalable produces correct job labels for Grafana dashboards
- **Scalability**: Loki scales to ~1TB/day (vs. ~50GB/day SingleBinary)
- **Lightweight**: Garage uses ~60% less resources than MinIO Operator approach
- **Self-Contained**: Single binary, no external dependencies
- **Future-Proof**: Foundation for backup storage, application data

---

## Architecture Overview

```
+-----------------------------------------------------------------+
|                       Storage Namespace                          |
|  +-----------------------------------------------------------+  |
|  |                    Garage StatefulSet                      |  |
|  |  +-------------+  +-------------+  +-------------+        |  |
|  |  | garage-0    |  | garage-1    |  | garage-2    |        |  |
|  |  | (meta+data) |  | (meta+data) |  | (meta+data) |        |  |
|  |  +------+------+  +------+------+  +------+------+        |  |
|  |         |                |                |               |  |
|  |         +-------+--------+-------+--------+               |  |
|  |                 v                                          |  |
|  |  +----------------------------------------------------------+ |
|  |  |              S3 API Service (Port 3900)                   ||
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

## Garage vs MinIO Comparison

### Resource Requirements

| Component | Garage (3 nodes) | MinIO (Operator+2 nodes) |
| ----------- | ------------------ | -------------------------- |
| CPU Request | 150m (3x50m) | 250m (50m+2x100m) |
| Memory Request | 768Mi (3x256Mi) | 1152Mi (128Mi+2x512Mi) |
| Memory Limit | 1536Mi (3x512Mi) | 2560Mi (256Mi+2x1Gi) |
| Pod Count | 3 | 3 (1 operator + 2 servers) |
| PVC Count | 6 (3 meta + 3 data) | 2-4 |
| CRDs Required | 1 (GarageNode) | 2+ (Tenant, etc.) |

**Net Savings:** ~40% less CPU, ~33% less memory with Garage

### Feature Comparison

| Feature | Garage | MinIO |
| --------- | -------- | ------- |
| S3 API v4 Signature | ✅ | ✅ |
| Multipart Upload | ✅ | ✅ |
| Bucket Versioning | ❌ | ✅ |
| Object Locking | ❌ | ✅ |
| ACL/Policies | ❌ (per-key-per-bucket) | ✅ |
| Prometheus Metrics | ✅ | ✅ |
| Web Console | ❌ | ✅ |
| CLI Management | ✅ (garage CLI) | ✅ (mc CLI) |

**Loki Compatibility:** Both provide all required S3 operations for Loki storage.

---

## Garage Configuration Deep Dive

### Core Configuration Parameters

```toml
# Replication factor - how many copies of each data block
# For 3-node cluster with high availability: 3
# For 2-node cluster: 2 (reduced redundancy)
replication_factor = 3

# Consistency mode affects read/write quorums
# "consistent" - read-after-write consistency (recommended)
# "degraded" - allows reads when quorum unavailable
# "dangerous" - allows reads AND writes with single node
consistency_mode = "consistent"

# Metadata storage - fast SSD recommended
metadata_dir = "/var/lib/garage/meta"

# Data storage - can be HDD, bulk storage
data_dir = "/var/lib/garage/data"

# Database engine options:
# "lmdb" - fastest, default (not portable between architectures)
# "sqlite" - more robust to unclean shutdowns
db_engine = "lmdb"

# Enable metadata snapshots for recovery (recommended)
metadata_auto_snapshot_interval = "6h"

# Compression level (1=fast, 19=small, 0=default, 'none'=disabled)
compression_level = 1

# Block size for object chunking (default 1M, increase for large files)
block_size = "1M"
```

### Network Configuration

```toml
# RPC for inter-node communication
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "<pod-ip>:3901"
rpc_secret = "<32-byte-hex-secret>"

# S3 API endpoint
[s3_api]
api_bind_addr = "[::]:3900"
s3_region = "garage"
root_domain = ".s3.garage.localhost"

# Admin API with Prometheus metrics
[admin]
api_bind_addr = "0.0.0.0:3903"
metrics_token = "<metrics-bearer-token>"
admin_token = "<admin-bearer-token>"
```

### Kubernetes Discovery

Garage supports automatic node discovery in Kubernetes using a CRD:

```toml
[kubernetes_discovery]
namespace = "storage"
service_name = "garage"
skip_crd = false  # Let Helm chart manage CRD
```

This eliminates the need for manual `bootstrap_peers` configuration.

---

## Implementation Plan

### Phase 1: Garage Deployment

#### 1.1 Configuration Schema Updates

Add to `cluster.yaml`:

```yaml
# =============================================================================
# GARAGE SHARED OBJECT STORAGE - S3-compatible storage for cluster services
# =============================================================================
# Garage is a lightweight, self-hosted S3-compatible object storage service.
# When enabled, Loki automatically switches to SimpleScalable mode with S3.
# REF: https://garagehq.deuxfleurs.fr/

# -- Enable Garage shared storage
#    When enabled, Loki uses SimpleScalable mode with S3 backend
#    (OPTIONAL) / (DEFAULT: false)
# garage_enabled: false

# -- Number of Garage nodes (2-4 recommended for redundancy)
#    (OPTIONAL) / (DEFAULT: 3)
# garage_replicas: 3

# -- Replication factor (copies of each data block)
#    Must be <= garage_replicas. Use 2 or 3 for redundancy.
#    (OPTIONAL) / (DEFAULT: 2)
# garage_replication_factor: 2

# -- Metadata storage size per node (fast SSD recommended)
#    (OPTIONAL) / (DEFAULT: "1Gi")
# garage_meta_storage_size: "1Gi"

# -- Data storage size per node (bulk storage)
#    (OPTIONAL) / (DEFAULT: "50Gi")
# garage_data_storage_size: "50Gi"

# -- S3 region name (used in bucket operations)
#    (OPTIONAL) / (DEFAULT: "garage")
# garage_s3_region: "garage"

# -- RPC secret for inter-node communication (32-byte hex)
#    Generate with: openssl rand -hex 32
#    (REQUIRED when garage_enabled)
# garage_rpc_secret: ""

# -- Admin API token for management operations
#    Generate with: openssl rand -base64 32
#    (REQUIRED when garage_enabled)
# garage_admin_token: ""

# -- Metrics token for Prometheus scraping
#    Generate with: openssl rand -base64 32
#    (OPTIONAL - if not set, metrics are public)
# garage_metrics_token: ""

# -- Loki S3 access key (created as Garage key)
#    (OPTIONAL) / (DEFAULT: "loki")
# loki_s3_access_key: "loki"

# -- Loki S3 secret key (SOPS-encrypted)
#    Generate with: openssl rand -hex 32
#    (REQUIRED when garage_enabled and loki_enabled)
# loki_s3_secret_key: ""

# -- Tempo S3 access key (created as Garage key)
#    (OPTIONAL) / (DEFAULT: "tempo")
# tempo_s3_access_key: "tempo"

# -- Tempo S3 secret key (SOPS-encrypted)
#    Generate with: openssl rand -hex 32
#    (REQUIRED when garage_enabled and tracing_enabled)
# tempo_s3_secret_key: ""
```

#### 1.2 Plugin.py Updates

Add to `templates/scripts/plugin.py`:

```python
# Garage shared storage - enabled when garage_enabled is true
# When Garage is enabled, Loki can use S3 backend for SimpleScalable mode
garage_enabled = data.get("garage_enabled", False)
if garage_enabled:
    # Set default storage class for Garage if not specified
    data.setdefault("garage_storage_class", data.get("storage_class", "local-path"))

    # Loki deployment mode is SimpleScalable when Garage is available
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
└── garage/
    ├── ks.yaml.j2                       # Flux Kustomization
    └── app/
        ├── kustomization.yaml.j2
        ├── helmrelease.yaml.j2          # Garage Helm chart
        ├── configmap.yaml.j2            # Garage configuration
        ├── secret.sops.yaml.j2          # Credentials (SOPS-encrypted)
        └── servicemonitor.yaml.j2       # Prometheus scraping
```

#### 1.4 Storage Namespace

**`storage/namespace.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
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
#% if garage_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: storage

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./garage/ks.yaml
#% endif %#
```

#### 1.5 Garage Flux Kustomization

**`storage/garage/ks.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: garage
spec:
  dependsOn:
    - name: cert-manager
      namespace: cert-manager
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: garage
      namespace: storage
  healthCheckExprs:
    - apiVersion: apps/v1
      kind: StatefulSet
      name: garage
      namespace: storage
      current: status.readyReplicas == status.replicas
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/storage/garage/app
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

#### 1.6 Garage HelmRelease

**`storage/garage/app/helmrelease.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: garage
spec:
  chart:
    spec:
      chart: garage
      version: "1.0.0"  #| Update to latest stable #|
      sourceRef:
        kind: HelmRepository
        name: garage
        namespace: flux-system
  interval: 1h
  values:
    garage:
      #| Replication settings #|
      replicationMode: "#{ garage_replication_factor | default(2) }#"

    deployment:
      #| Number of Garage nodes #|
      replicaCount: #{ garage_replicas | default(3) }#

    #| Container image - use stable release #|
    image:
      repository: dxflrs/garage
      tag: "v1.0.1"
      pullPolicy: IfNotPresent

    #| Resource limits #|
    resources:
      requests:
        cpu: 50m
        memory: 256Mi
      limits:
        memory: 512Mi

    #| Persistence configuration #|
    persistence:
      meta:
        enabled: true
        storageClass: "#{ storage_class | default('local-path') }#"
        size: "#{ garage_meta_storage_size | default('1Gi') }#"
      data:
        enabled: true
        storageClass: "#{ storage_class | default('local-path') }#"
        size: "#{ garage_data_storage_size | default('50Gi') }#"

    #| Service configuration #|
    service:
      s3:
        api:
          port: 3900
      admin:
        port: 3903

    #| Admin API for metrics #|
    admin:
      enabled: true

    #| Use existing secrets for credentials #|
    existingSecret:
      name: garage-secrets
      rpcSecretKey: rpc-secret
      adminTokenKey: admin-token
      metricsTokenKey: metrics-token

    #| ConfigMap for Garage configuration #|
    configurationConfigMap:
      name: garage-config

    #| Kubernetes discovery for automatic node connection #|
    kubernetesDiscovery:
      enabled: true
#% endif %#
```

#### 1.7 Garage ConfigMap

**`storage/garage/app/configmap.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: garage-config
data:
  garage.toml: |
    metadata_dir = "/var/lib/garage/meta"
    data_dir = "/var/lib/garage/data"
    db_engine = "lmdb"
    metadata_auto_snapshot_interval = "6h"

    replication_factor = #{ garage_replication_factor | default(2) }#
    consistency_mode = "consistent"

    compression_level = 1
    block_size = "1M"

    rpc_bind_addr = "[::]:3901"
    rpc_public_addr_subnet = "#{ cluster_pod_cidr | default('10.42.0.0/16') }#"

    [kubernetes_discovery]
    namespace = "storage"
    service_name = "garage"
    skip_crd = false

    [s3_api]
    api_bind_addr = "[::]:3900"
    s3_region = "#{ garage_s3_region | default('garage') }#"
    root_domain = ".s3.garage.storage.svc.cluster.local"

    [admin]
    api_bind_addr = "0.0.0.0:3903"
#% endif %#
```

#### 1.8 Garage Secrets

**`storage/garage/app/secret.sops.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: garage-secrets
type: Opaque
stringData:
  rpc-secret: "#{ garage_rpc_secret }#"
  admin-token: "#{ garage_admin_token }#"
#% if garage_metrics_token | default('') %#
  metrics-token: "#{ garage_metrics_token }#"
#% endif %#
#% endif %#
```

#### 1.9 Garage ServiceMonitor

**`storage/garage/app/servicemonitor.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) and monitoring_enabled | default(false) %#
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: garage
  namespace: storage
  labels:
    app.kubernetes.io/name: garage
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: garage
  endpoints:
    - port: admin
      path: /metrics
      interval: 30s
#% if garage_metrics_token | default('') %#
      authorization:
        type: Bearer
        credentials:
          name: garage-secrets
          key: metrics-token
#% endif %#
  namespaceSelector:
    matchNames:
      - storage
#% endif %#
```

### Phase 2: Bucket Provisioning Job

Since Garage doesn't support declarative bucket/key creation like MinIO Tenant CR, we need a post-install Job:

**`storage/garage/app/job-setup.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
---
apiVersion: batch/v1
kind: Job
metadata:
  name: garage-bucket-setup
  annotations:
    #| Run after HelmRelease is ready #|
    kustomize.toolkit.fluxcd.io/prune: disabled
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 5
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: setup
          image: dxflrs/garage:v1.0.1
          command:
            - /bin/sh
            - -c
            - |
              set -e

              # Wait for Garage to be ready
              echo "Waiting for Garage to be ready..."
              until garage status 2>/dev/null | grep -q "HEALTHY"; do
                sleep 5
              done

              echo "Garage is ready. Configuring layout..."

              # Get node IDs and assign layout
              # The Helm chart should have already configured layout via kubernetes_discovery
              # But we verify and apply if needed
              NODE_COUNT=$(garage status | grep -c "HEALTHY NODES" || echo 0)
              if [ "$NODE_COUNT" -lt "#{ garage_replicas | default(3) }#" ]; then
                echo "Warning: Only $NODE_COUNT nodes healthy, expected #{ garage_replicas | default(3) }#"
              fi

              # Apply layout if not already configured
              LAYOUT_VERSION=$(garage layout show 2>/dev/null | grep -oP 'Current cluster layout version: \K\d+' || echo "0")
              if [ "$LAYOUT_VERSION" = "0" ]; then
                echo "Configuring initial cluster layout..."
                for NODE_ID in $(garage status | grep -oP '^\S{16}'); do
                  garage layout assign -z dc1 -c #{ garage_data_storage_size | default('50G') | regex_replace('i$', '') }# $NODE_ID || true
                done
                garage layout apply --version 1 || true
              fi

              echo "Creating buckets..."

#% if loki_enabled | default(false) %#
              # Loki buckets
              garage bucket create loki-chunks 2>/dev/null || echo "Bucket loki-chunks exists"
              garage bucket create loki-ruler 2>/dev/null || echo "Bucket loki-ruler exists"
              garage bucket create loki-admin 2>/dev/null || echo "Bucket loki-admin exists"

              # Loki access key
              if ! garage key info "#{ loki_s3_access_key | default('loki') }#" 2>/dev/null; then
                echo "Creating Loki access key..."
                garage key import -n "#{ loki_s3_access_key | default('loki') }#" "$LOKI_S3_ACCESS_KEY" "$LOKI_S3_SECRET_KEY"
              fi

              # Grant Loki key access to buckets
              garage bucket allow --read --write --owner loki-chunks --key "#{ loki_s3_access_key | default('loki') }#"
              garage bucket allow --read --write --owner loki-ruler --key "#{ loki_s3_access_key | default('loki') }#"
              garage bucket allow --read --write --owner loki-admin --key "#{ loki_s3_access_key | default('loki') }#"
#% endif %#

#% if tracing_enabled | default(false) %#
              # Tempo bucket
              garage bucket create tempo 2>/dev/null || echo "Bucket tempo exists"

              # Tempo access key
              if ! garage key info "#{ tempo_s3_access_key | default('tempo') }#" 2>/dev/null; then
                echo "Creating Tempo access key..."
                garage key import -n "#{ tempo_s3_access_key | default('tempo') }#" "$TEMPO_S3_ACCESS_KEY" "$TEMPO_S3_SECRET_KEY"
              fi

              # Grant Tempo key access to bucket
              garage bucket allow --read --write --owner tempo --key "#{ tempo_s3_access_key | default('tempo') }#"
#% endif %#

              # General backup bucket
              garage bucket create backups 2>/dev/null || echo "Bucket backups exists"

              echo "Bucket setup complete!"
              garage bucket list
          env:
            - name: GARAGE_RPC_SECRET
              valueFrom:
                secretKeyRef:
                  name: garage-secrets
                  key: rpc-secret
            - name: GARAGE_ADMIN_TOKEN
              valueFrom:
                secretKeyRef:
                  name: garage-secrets
                  key: admin-token
#% if loki_enabled | default(false) %#
            - name: LOKI_S3_ACCESS_KEY
              value: "#{ loki_s3_access_key | default('loki') }#"
            - name: LOKI_S3_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: garage-service-credentials
                  key: loki-secret-key
#% endif %#
#% if tracing_enabled | default(false) %#
            - name: TEMPO_S3_ACCESS_KEY
              value: "#{ tempo_s3_access_key | default('tempo') }#"
            - name: TEMPO_S3_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: garage-service-credentials
                  key: tempo-secret-key
#% endif %#
#% endif %#
```

**`storage/garage/app/secret-credentials.sops.yaml.j2`:**

```yaml
#% if garage_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: garage-service-credentials
type: Opaque
stringData:
#% if loki_enabled | default(false) %#
  loki-secret-key: "#{ loki_s3_secret_key }#"
#% endif %#
#% if tracing_enabled | default(false) %#
  tempo-secret-key: "#{ tempo_s3_secret_key }#"
#% endif %#
#% endif %#
```

### Phase 3: Loki SimpleScalable Migration

Update the existing Loki HelmRelease to support both modes:

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
#% if garage_enabled | default(false) %#
  #| Depend on Garage for S3 storage #|
  dependsOn:
    - name: garage
      namespace: storage
#% endif %#
  values:
#% if garage_enabled | default(false) %#
    #| SimpleScalable mode with Garage S3 backend #|
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
    #| SingleBinary mode with filesystem (no Garage) #|
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
#% if garage_enabled | default(false) %#
        path_prefix: /var/loki
      storage:
        type: s3
        bucketNames:
          chunks: loki-chunks
          ruler: loki-ruler
          admin: loki-admin
        s3:
          endpoint: http://garage.storage.svc.cluster.local:3900
          region: "#{ garage_s3_region | default('garage') }#"
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
#% if garage_enabled | default(false) %#
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

#% if garage_enabled | default(false) %#
    #| S3 credentials from secret #|
    extraEnvFrom:
      - secretRef:
          name: loki-s3-credentials
#% endif %#

    #| Disable built-in MinIO - using Garage #|
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

**`monitoring/loki/app/secret.sops.yaml.j2`:**

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) and garage_enabled | default(false) %#
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

Update **`monitoring/loki/ks.yaml.j2`:**

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
#% if garage_enabled | default(false) %#
    - name: garage
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
  #% if garage_enabled | default(false) %#
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

### Garage (Shared Storage)

| Component | CPU Request | Memory Request | Memory Limit | Storage |
| ----------- | ------------- | ---------------- | -------------- | --------- |
| Garage Node (x3) | 50m | 256Mi | 512Mi | 1Gi meta + 50Gi data |
| **Total** | 150m | 768Mi | 1536Mi | 153Gi |

### Loki SimpleScalable (vs SingleBinary)

| Component | CPU Request | Memory Request | Memory Limit | Count |
| ----------- | ------------- | ---------------- | -------------- | ------- |
| Read | 50m | 128Mi | 256Mi | 2 |
| Write | 50m | 128Mi | 256Mi | 2 |
| Backend | 50m | 128Mi | 256Mi | 2 |
| **Total** | 300m | 768Mi | 1536Mi | 6 pods |

**SingleBinary Comparison:** 100m CPU, 256Mi request, 512Mi limit, 1 pod

### Net Resource Change

| Metric | Before (SingleBinary) | After (Garage+SimpleScalable) | Delta |
| -------- | ----------------------- | ------------------------------- | ------- |
| CPU Requests | 100m | 450m | +350m |
| Memory Requests | 256Mi | 1536Mi | +1280Mi |
| Memory Limits | 512Mi | 3072Mi | +2560Mi |
| Pod Count | 1 (Loki) | 9 (3 Garage + 6 Loki) | +8 |
| PVC Count | 1 (50Gi) | 10 (6 Garage + 4 Loki) | +9 |

---

## Monitoring & Observability

### Garage Metrics

Garage exposes Prometheus metrics at `:3903/metrics`. Key metrics include:

| Metric | Description |
| -------- | ------------- |
| `garage_build_info` | Version information |
| `garage_replication_factor` | Configured replication |
| `garage_local_disk_avail` | Available disk space |
| `garage_local_disk_total` | Total disk space |
| `cluster_healthy` | Cluster health status (0/1) |
| `cluster_available` | Can serve requests (0/1) |
| `cluster_connected_nodes` | Connected node count |
| `api_s3_request_counter` | S3 API request counts |
| `api_s3_request_duration` | S3 API latency histogram |
| `block_bytes_read/written` | I/O throughput |

### Grafana Dashboard

Import the official Garage dashboard:
- **Dashboard JSON:** https://git.deuxfleurs.fr/Deuxfleurs/garage/raw/branch/main/script/telemetry/grafana-garage-dashboard-prometheus.json
- **Grafana ID:** N/A (self-hosted)

Add as ConfigMap:

```yaml
#% if garage_enabled | default(false) and monitoring_enabled | default(false) %#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: garage-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: Storage
data:
  garage-dashboard.json: |
    # Paste dashboard JSON here
#% endif %#
```

---

## Migration Procedure

### Pre-Migration Checklist

- [ ] Verify cluster has sufficient resources (~450m CPU, ~1.5GB RAM additional)
- [ ] Backup current Loki PVC data (optional - logs can be re-collected)
- [ ] Note current log retention period
- [ ] Generate secure secrets for Garage

### Migration Steps

```bash
# 1. Generate required secrets
export GARAGE_RPC_SECRET=$(openssl rand -hex 32)
export GARAGE_ADMIN_TOKEN=$(openssl rand -base64 32)
export GARAGE_METRICS_TOKEN=$(openssl rand -base64 32)
export LOKI_S3_SECRET_KEY=$(openssl rand -hex 32)
export TEMPO_S3_SECRET_KEY=$(openssl rand -hex 32)

# 2. Update cluster.yaml with Garage configuration
cat >> cluster.yaml << EOF
# Garage Object Storage
garage_enabled: true
garage_replicas: 3
garage_replication_factor: 2
garage_meta_storage_size: "1Gi"
garage_data_storage_size: "50Gi"
garage_rpc_secret: "$GARAGE_RPC_SECRET"
garage_admin_token: "$GARAGE_ADMIN_TOKEN"
garage_metrics_token: "$GARAGE_METRICS_TOKEN"
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

# 7. Verify Garage is healthy
kubectl get pods -n storage
kubectl exec -n storage garage-0 -- garage status
kubectl exec -n storage garage-0 -- garage bucket list

# 8. Verify Loki SimpleScalable components
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# 9. Verify dashboards work
# Open Grafana > Logging folder > Check data in Loki dashboards
```

### Rollback Procedure

```bash
# 1. Set garage_enabled: false in cluster.yaml
# 2. task configure
# 3. flux suspend hr loki -n monitoring
# 4. kubectl delete hr loki -n monitoring
# 5. flux resume hr loki -n monitoring
# 6. task reconcile
```

---

## Troubleshooting

### Garage Issues

```bash
# Check Garage pod status
kubectl get pods -n storage -l app.kubernetes.io/name=garage

# Check Garage logs
kubectl logs -n storage -l app.kubernetes.io/name=garage

# Check cluster status from any Garage pod
kubectl exec -n storage garage-0 -- garage status

# Check layout configuration
kubectl exec -n storage garage-0 -- garage layout show

# List buckets
kubectl exec -n storage garage-0 -- garage bucket list

# List keys
kubectl exec -n storage garage-0 -- garage key list

# Test S3 connectivity (requires AWS CLI or mc)
kubectl run -it --rm s3test --image=amazon/aws-cli --restart=Never -- \
  s3 ls --endpoint-url http://garage.storage.svc:3900
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
kubectl get endpoints -n storage garage
kubectl get endpoints -n monitoring loki
```

### Common Issues

| Issue | Cause | Solution |
| ------- | ------- | ---------- |
| Garage pods pending | PVC not provisioning | Check StorageClass, verify storage provisioner |
| Layout not applied | Nodes not discovered | Check kubernetes_discovery config, verify CRD |
| S3 connection refused | Service not ready | Wait for Garage pods to be ready, check service |
| Bucket not found | Setup job not run | Manually run bucket creation commands |
| Loki write failures | Credentials wrong | Verify secret values match Garage key |

---

## Security Considerations

### Network Policies

```yaml
#% if network_policies_enabled | default(false) and garage_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: garage-ingress
  namespace: storage
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: garage
  ingress:
    #| Allow S3 API from monitoring namespace (Loki) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "3900"
              protocol: TCP
    #| Allow inter-node RPC #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: garage
      toPorts:
        - ports:
            - port: "3901"
              protocol: TCP
    #| Allow metrics scraping from monitoring #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "3903"
              protocol: TCP
#% endif %#
```

### Encryption

- **In-Transit**: TLS can be configured but disabled for internal cluster traffic
- **At-Rest**: Use filesystem-level encryption (LUKS) or storage class encryption
- **Credentials**: All secrets are SOPS-encrypted with Age

---

## Sources

- [Garage Documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [Garage GitHub Repository](https://github.com/deuxfleurs-org/garage)
- [Garage Kubernetes Deployment](https://garagehq.deuxfleurs.fr/documentation/cookbook/kubernetes/)
- [Garage Configuration Reference](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
- [Garage Monitoring](https://garagehq.deuxfleurs.fr/documentation/cookbook/monitoring/)
- [Garage S3 Compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [Loki SimpleScalable Installation](https://grafana.com/docs/loki/latest/setup/install/helm/install-scalable/)
- [Loki Storage Configuration](https://grafana.com/docs/loki/latest/setup/install/helm/configure-storage/)
- [GitHub Issue #11390 - Loki Dashboard Job Labels](https://github.com/grafana/loki/issues/11390)

---

## Implementation Checklist

### Phase 1: Infrastructure Setup
- [ ] Add Garage configuration section to `cluster.sample.yaml`
- [ ] Update `templates/scripts/plugin.py` with derived variables
- [ ] Create `templates/config/kubernetes/apps/storage/` directory structure
- [ ] Add `storage/namespace.yaml.j2`
- [ ] Add `storage/kustomization.yaml.j2`

### Phase 2: Garage Deployment
- [ ] Create `storage/garage/ks.yaml.j2`
- [ ] Create `storage/garage/app/kustomization.yaml.j2`
- [ ] Create `storage/garage/app/helmrelease.yaml.j2`
- [ ] Create `storage/garage/app/configmap.yaml.j2`
- [ ] Create `storage/garage/app/secret.sops.yaml.j2`
- [ ] Create `storage/garage/app/servicemonitor.yaml.j2`
- [ ] Create `storage/garage/app/job-setup.yaml.j2`
- [ ] Create `storage/garage/app/secret-credentials.sops.yaml.j2`

### Phase 3: Loki Integration
- [ ] Update `monitoring/loki/app/helmrelease.yaml.j2` with conditional S3 config
- [ ] Add `monitoring/loki/app/secret.sops.yaml.j2` for S3 credentials
- [ ] Update `monitoring/loki/ks.yaml.j2` with Garage dependency

### Phase 4: Top-Level Integration
- [ ] Update `templates/config/kubernetes/apps/kustomization.yaml.j2`
- [ ] Update documentation (CLAUDE.md, CONFIGURATION.md)
- [ ] Add Garage dashboard ConfigMap

### Phase 5: Validation
- [ ] Run `task configure`
- [ ] Verify generated files in `kubernetes/apps/storage/`
- [ ] Deploy to cluster
- [ ] Verify Garage health and layout
- [ ] Verify bucket creation
- [ ] Verify Loki SimpleScalable components
- [ ] Verify Grafana dashboards show data

---

## Next Steps

1. **Review** this implementation plan
2. **Approve** resource allocation (~450m CPU, ~1.5GB RAM additional)
3. **Implement** Phase 1 (Infrastructure setup)
4. **Implement** Phase 2 (Garage deployment)
5. **Implement** Phase 3 (Loki integration)
6. **Implement** Phase 4 (Top-level integration)
7. **Validate** with `task configure` and cluster deployment
8. **Optional**: Migrate Tempo to Garage S3 storage
