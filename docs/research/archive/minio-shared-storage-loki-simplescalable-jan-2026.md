# MinIO Shared Object Storage & Loki SimpleScalable Migration

**Date:** January 2026
**Status:** Implementation Ready
**Purpose:** Deploy MinIO as shared S3-compatible storage for cluster services (Loki, Tempo, backups, future apps)

---

## Executive Summary

This document provides a comprehensive implementation plan for deploying MinIO as a shared object storage service in the matherlynet-talos-cluster, with an immediate use case of migrating Loki from SingleBinary to SimpleScalable mode to resolve dashboard compatibility issues.

### Key Decisions

1. **MinIO Operator + Tenant Model**: Use the MinIO Operator deployed via Helm for lifecycle management
2. **Single-Tenant with Bucket Isolation**: Single MinIO Tenant with separate buckets per service (vs. multi-tenant)
3. **Loki SimpleScalable Mode**: Migrate from SingleBinary to SimpleScalable for dashboard compatibility and scalability
4. **Shared Infrastructure**: MinIO serves Loki, Tempo, and future services via bucket policies

### Benefits

- **Dashboard Fix**: Loki SimpleScalable produces correct job labels for Grafana dashboards
- **Scalability**: Loki scales to ~1TB/day (vs. ~50GB/day SingleBinary)
- **Shared Storage**: Single MinIO instance serves multiple observability services
- **Future-Proof**: Foundation for backup storage, application data, ML artifacts

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                       Storage Namespace                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    MinIO Tenant                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │ minio-pool-0│  │ minio-pool-0│  │   Console   │        │  │
│  │  │   (data)    │  │   (data)    │  │   (web UI)  │        │  │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────┘        │  │
│  │         │                │                                 │  │
│  │         └────────┬───────┘                                 │  │
│  │                  ▼                                         │  │
│  │  ┌──────────────────────────────────────────────────────┐ │  │
│  │  │                    S3 API (9000)                      │ │  │
│  │  │  Buckets: loki-chunks | loki-ruler | tempo | backups  │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌──────────┐        ┌──────────┐        ┌──────────┐
    │   Loki   │        │  Tempo   │        │  Future  │
    │ (S3 API) │        │ (S3 API) │        │  Apps    │
    │SimpleScal│        │          │        │          │
    └──────────┘        └──────────┘        └──────────┘
```

---

## Component Analysis

### Current State (Problem)

| Component | Mode | Storage | Dashboard Status |
| ----------- | ------ | --------- | ------------------ |
| Loki | SingleBinary | Filesystem PVC | **Broken** - job label mismatch |
| Tempo | Monolithic | Filesystem PVC | Limited |

**Root Cause:** Loki SingleBinary produces `job="monitoring/loki"` but dashboards expect `job=~"loki-read"`, `job=~"loki-write"`, etc.

### Target State (Solution)

| Component | Mode | Storage | Dashboard Status |
| ----------- | ------ | --------- | ------------------ |
| Loki | SimpleScalable | MinIO S3 | **Working** - proper job labels |
| Tempo | Distributed (optional) | MinIO S3 | Full functionality |

---

## MinIO Deployment Options Analysis

### Option A: MinIO Operator + Tenant (Recommended)

**Pros:**
- Kubernetes-native lifecycle management
- Multi-tenant capable (future expansion)
- Enterprise features (encryption, IAM, tiering)
- Automatic upgrades and scaling
- Production-grade patterns

**Cons:**
- More resources than standalone
- Operator overhead

**Verdict:** Best for production clusters expecting growth

### Option B: Standalone MinIO Helm Chart

**Pros:**
- Simpler deployment
- Lower resource overhead
- Good for small/homelab clusters

**Cons:**
- Manual lifecycle management
- No operator for advanced features
- Limited scaling options

**Verdict:** Suitable for very small deployments

### Option C: Loki's Built-in MinIO Subchart

**Pros:**
- Zero additional configuration
- Tightly integrated

**Cons:**
- Not shared with other services
- Lifecycle tied to Loki
- Can't use for Tempo/backups

**Verdict:** Not suitable for shared storage requirement

---

## Implementation Plan

### Phase 1: MinIO Operator Deployment

#### 1.1 Configuration Schema Updates

Add to `cluster.yaml`:

```yaml
# MinIO Object Storage Configuration (Optional)
minio_enabled: true                    # Enable MinIO deployment
minio_storage_size: "50Gi"             # PV size per MinIO server
minio_replicas: 2                      # Number of MinIO servers (2 or 4 recommended)
minio_volumes_per_server: 1            # Drives per server (increase for erasure coding)
minio_root_user: "minio"               # Root admin username
minio_root_password: ""                # SOPS-encrypted root password
```

**Derived Variables** (add to `plugin.py`):
```python
# MinIO enabled when minio_enabled is true
if data.get("minio_enabled"):
    data["minio_storage_class"] = data.get("storage_class", "local-path")
```

#### 1.2 Template Structure

```
templates/config/kubernetes/apps/storage/minio/
├── ks.yaml.j2                         # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── namespace.yaml.j2
    ├── helmrelease-operator.yaml.j2   # MinIO Operator
    ├── tenant.yaml.j2                  # MinIO Tenant CR
    └── secret.sops.yaml.j2             # Credentials (SOPS-encrypted)
```

#### 1.3 MinIO Operator HelmRelease

```yaml
#% if minio_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: minio-operator
  namespace: storage
spec:
  chartRef:
    kind: OCIRepository
    name: minio-operator
  interval: 1h
  values:
    operator:
      replicaCount: 1
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 256Mi
    console:
      enabled: false  #| Disable console - use mc CLI or Grafana #|
#% endif %#
```

#### 1.4 MinIO Tenant CR

```yaml
#% if minio_enabled | default(false) %#
---
apiVersion: minio.min.io/v2
kind: Tenant
metadata:
  name: minio
  namespace: storage
spec:
  image: quay.io/minio/minio:RELEASE.2025-10-15T17-29-55Z  #| Latest stable release #|
  pools:
    - servers: #{ minio_replicas | default(2) }#
      name: pool-0
      volumesPerServer: #{ minio_volumes_per_server | default(1) }#
      volumeClaimTemplate:
        metadata:
          name: data
        spec:
          accessModes:
            - ReadWriteOnce
          storageClassName: "#{ storage_class | default('local-path') }#"
          resources:
            requests:
              storage: "#{ minio_storage_size | default('50Gi') }#"
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
        limits:
          memory: 1Gi
  #| Configuration secret for root credentials #|
  configuration:
    name: minio-config
  #| Service configuration #|
  requestAutoCert: false  #| Disable TLS - internal cluster traffic #|
  exposeServices:
    minio: true
    console: false
  #| Prometheus metrics #|
  prometheusOperator: true
#% endif %#
```

#### 1.5 MinIO Secrets

```yaml
#% if minio_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-config
  namespace: storage
type: Opaque
stringData:
  config.env: |
    export MINIO_ROOT_USER="#{ minio_root_user | default('minio') }#"
    export MINIO_ROOT_PASSWORD="#{ minio_root_password }#"
    export MINIO_PROMETHEUS_AUTH_TYPE="public"
#% endif %#
```

### Phase 2: Bucket Provisioning

#### 2.1 Bucket Job (Post-Install)

Create buckets using a Kubernetes Job after MinIO is ready:

```yaml
#% if minio_enabled | default(false) %#
---
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-bucket-setup
  namespace: storage
  annotations:
    helm.sh/hook: post-install,post-upgrade
    helm.sh/hook-weight: "5"
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: mc
          image: minio/mc:latest
          command:
            - /bin/sh
            - -c
            - |
              set -e
              mc alias set minio http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

              # Create Loki buckets
              mc mb --ignore-existing minio/loki-chunks
              mc mb --ignore-existing minio/loki-ruler

              # Create Tempo bucket
              mc mb --ignore-existing minio/tempo

              # Create backup bucket (for future talos-backup integration)
              mc mb --ignore-existing minio/backups

              # Create service users with scoped policies
              mc admin user add minio loki-user $LOKI_PASSWORD || true
              mc admin user add minio tempo-user $TEMPO_PASSWORD || true

              # Loki policy - access only loki-* buckets
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
              mc admin policy create minio loki-policy /tmp/loki-policy.json || true
              mc admin policy attach minio loki-policy --user loki-user || true

              # Tempo policy - access only tempo bucket
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
              mc admin policy create minio tempo-policy /tmp/tempo-policy.json || true
              mc admin policy attach minio tempo-policy --user tempo-user || true

              echo "Bucket and user setup complete!"
          envFrom:
            - secretRef:
                name: minio-config
          env:
            - name: LOKI_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-service-credentials
                  key: loki-password
            - name: TEMPO_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-service-credentials
                  key: tempo-password
#% endif %#
```

### Phase 3: Loki SimpleScalable Migration

#### 3.1 Updated Loki HelmRelease

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) %#
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
  #| Depend on MinIO for S3 storage #|
#% if minio_enabled | default(false) %#
  dependsOn:
    - name: minio-operator
      namespace: storage
#% endif %#
  values:
#% if minio_enabled | default(false) %#
    #| SimpleScalable mode with MinIO S3 backend #|
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
      replicas: 3
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
    #| SingleBinary mode with filesystem (no MinIO) #|
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
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0
#% endif %#

    #| Loki configuration #|
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
#% if minio_enabled | default(false) %#
        path_prefix: /var/loki
      storage:
        type: s3
        bucketNames:
          chunks: loki-chunks
          ruler: loki-ruler
        s3:
          endpoint: http://minio.storage.svc:9000
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
#% if minio_enabled | default(false) %#
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

#% if minio_enabled | default(false) %#
    #| S3 credentials from secret #|
    extraEnvFrom:
      - secretRef:
          name: loki-s3-credentials
#% endif %#

    #| Disable MinIO subchart - using shared MinIO #|
    minio:
      enabled: false

    #| Gateway disabled - internal service only #|
    gateway:
      enabled: false

    #| Grafana disabled - deployed by kube-prometheus-stack #|
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

#### 3.2 Loki S3 Credentials Secret

```yaml
#% if monitoring_enabled | default(false) and loki_enabled | default(false) and minio_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: loki-s3-credentials
  namespace: monitoring
type: Opaque
stringData:
  LOKI_S3_ACCESS_KEY: "#{ loki_s3_access_key | default('loki-user') }#"
  LOKI_S3_SECRET_KEY: "#{ loki_s3_secret_key }#"
#% endif %#
```

### Phase 4: Tempo S3 Migration (Optional)

#### 4.1 Updated Tempo Configuration

```yaml
#% if tracing_enabled | default(false) and minio_enabled | default(false) %#
    storage:
      trace:
        backend: s3
        s3:
          endpoint: minio.storage.svc:9000
          bucket: tempo
          access_key: ${TEMPO_S3_ACCESS_KEY}
          secret_key: ${TEMPO_S3_SECRET_KEY}
          insecure: true
          forcepathstyle: true
#% endif %#
```

---

## Configuration Variables Summary

### New cluster.yaml Variables

| Variable | Type | Default | Description |
| ---------- | ------ | --------- | ------------- |
| `minio_enabled` | bool | `false` | Enable MinIO deployment |
| `minio_storage_size` | string | `50Gi` | PV size per MinIO server |
| `minio_replicas` | int | `2` | Number of MinIO servers |
| `minio_volumes_per_server` | int | `1` | Drives per server |
| `minio_root_user` | string | `minio` | Root admin username |
| `minio_root_password` | string | - | Root password (SOPS-encrypted) |
| `loki_s3_access_key` | string | `loki-user` | Loki S3 username |
| `loki_s3_secret_key` | string | - | Loki S3 password (SOPS-encrypted) |
| `tempo_s3_access_key` | string | `tempo-user` | Tempo S3 username |
| `tempo_s3_secret_key` | string | - | Tempo S3 password (SOPS-encrypted) |

### Derived Variables (plugin.py)

```python
# When MinIO is enabled, Loki automatically uses SimpleScalable mode
if data.get("minio_enabled") and data.get("loki_enabled"):
    data["loki_deployment_mode"] = "SimpleScalable"
else:
    data["loki_deployment_mode"] = "SingleBinary"
```

---

## Resource Requirements

### MinIO (Shared Storage)

| Component | CPU Request | Memory Request | Memory Limit | Storage |
| ----------- | ------------ | ---------------- | -------------- | --------- |
| MinIO Operator | 50m | 128Mi | 256Mi | - |
| MinIO Server (x2) | 100m | 512Mi | 1Gi | 50Gi each |
| **Total** | 250m | 1152Mi | 1.5Gi | 100Gi |

### Loki SimpleScalable (vs SingleBinary)

| Component | CPU Request | Memory Request | Memory Limit | Count |
| ----------- | ------------ | ---------------- | -------------- | ------- |
| Read | 50m | 128Mi | 256Mi | 2 |
| Write | 50m | 128Mi | 256Mi | 3 |
| Backend | 50m | 128Mi | 256Mi | 2 |
| **Total** | 350m | 896Mi | 1792Mi | 7 pods |

**SingleBinary Comparison:** 100m CPU, 256Mi request, 512Mi limit, 1 pod

### Net Resource Change

| Metric | Before | After | Delta |
| -------- | -------- | ------- | ------- |
| CPU Requests | 100m | 600m | +500m |
| Memory Requests | 256Mi | 2048Mi | +1792Mi |
| Memory Limits | 512Mi | 3292Mi | +2780Mi |
| Pod Count | 1 (Loki) | 10 (MinIO+Loki) | +9 |
| PVC Count | 1 (50Gi) | 7 (100Gi+20Gi) | +6 |

---

## Migration Procedure

### Pre-Migration Checklist

- [ ] Verify cluster has sufficient resources (see above)
- [ ] Backup current Loki PVC data (optional - logs can be re-collected)
- [ ] Note current log retention period
- [ ] Generate secure passwords for MinIO services

### Migration Steps

```bash
# 1. Update cluster.yaml with MinIO configuration
cat >> cluster.yaml << EOF
# MinIO Object Storage
minio_enabled: true
minio_storage_size: "50Gi"
minio_replicas: 2
minio_root_user: "minio"
minio_root_password: "$(openssl rand -base64 32)"
loki_s3_access_key: "loki-user"
loki_s3_secret_key: "$(openssl rand -base64 32)"
tempo_s3_access_key: "tempo-user"
tempo_s3_secret_key: "$(openssl rand -base64 32)"
EOF

# 2. Re-encrypt secrets
task configure

# 3. Suspend Loki for clean transition
flux suspend hr loki -n monitoring

# 4. Delete old Loki PVC (optional - data will be lost)
kubectl delete pvc -n monitoring -l app.kubernetes.io/name=loki

# 5. Resume and let Flux deploy new stack
flux resume hr loki -n monitoring
task reconcile

# 6. Verify MinIO is healthy
kubectl get pods -n storage
kubectl logs -n storage -l app=minio -f

# 7. Verify Loki SimpleScalable components
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# 8. Verify dashboards work
# Open Grafana → Logging folder → Check data in Loki dashboards
```

### Rollback Procedure

```bash
# 1. Set minio_enabled: false in cluster.yaml
# 2. task configure
# 3. flux suspend hr loki -n monitoring
# 4. kubectl delete hr loki -n monitoring
# 5. flux resume hr loki -n monitoring
# 6. task reconcile
```

---

## Service Integration Matrix

### Current Integrations

| Service | Bucket | Access User | Status |
| --------- | -------- | ------------- | -------- |
| Loki | loki-chunks, loki-ruler | loki-user | Primary use case |
| Tempo | tempo | tempo-user | Optional |

### Future Integrations

| Service | Bucket | Access User | Use Case |
| --------- | -------- | ------------- | ---------- |
| Talos Backup | backups | backup-user | etcd snapshots (replace R2) |
| Harbor | registry | harbor-user | Container image cache |
| Velero | velero | velero-user | Cluster backups |
| MLflow | mlflow | mlflow-user | ML artifacts |

---

## Monitoring & Observability

### MinIO Metrics

MinIO exposes Prometheus metrics at `:9000/minio/v2/metrics/cluster`.

```yaml
# ServiceMonitor for MinIO
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
```

### Grafana Dashboards

- **MinIO Dashboard**: gnetId 13502 - MinIO cluster overview
- **Loki Dashboard**: Built-in (should work with SimpleScalable)

---

## Security Considerations

### Network Policies

```yaml
# Allow only monitoring namespace to access MinIO
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
```

### Encryption

- **In-Transit**: Optional TLS (disabled for internal cluster traffic)
- **At-Rest**: MinIO supports SSE-S3, SSE-C, SSE-KMS (not enabled by default)

---

## Troubleshooting

### MinIO Issues

```bash
# Check operator logs
kubectl logs -n storage -l app.kubernetes.io/name=minio-operator

# Check tenant status
kubectl get tenant -n storage

# Check MinIO server logs
kubectl logs -n storage -l app=minio

# Test S3 connectivity
kubectl run -it --rm mc --image=minio/mc --restart=Never -- \
  sh -c 'mc alias set test http://minio.storage.svc:9000 minio $MINIO_PASSWORD && mc ls test'
```

### Loki Issues

```bash
# Check Loki components
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Check Loki logs for S3 errors
kubectl logs -n monitoring -l app.kubernetes.io/component=write

# Verify S3 configuration
kubectl exec -n monitoring deploy/loki-read -- cat /etc/loki/config/config.yaml | grep -A20 storage
```

---

## Sources

- [MinIO Operator Documentation](https://docs.min.io/community/minio-object-store/reference/operator-chart-values.html)
- [MinIO Tenant Deployment](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-minio-tenant-helm.html)
- [Loki SimpleScalable Installation](https://grafana.com/docs/loki/latest/setup/install/helm/install-scalable/)
- [Loki Storage Configuration](https://grafana.com/docs/loki/latest/setup/install/helm/configure-storage/)
- [MinIO Multi-Tenant Architecture](https://blog.min.io/single-vs-multi-tenant/)
- [GitHub Issue #11390 - Loki Dashboard Job Labels](https://github.com/grafana/loki/issues/11390)
- [GitHub Issue #9183 - SingleBinary Dashboard ConfigMaps](https://github.com/grafana/loki/issues/9183)
- [Grafana Loki 3.6 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-6/)
- [MinIO GitHub Releases](https://github.com/minio/minio/releases)

---

## Next Steps

1. **Review** this implementation plan
2. **Approve** resource allocation (~600m CPU, ~2GB RAM additional)
3. **Implement** Phase 1 (MinIO Operator + Tenant)
4. **Implement** Phase 2 (Bucket provisioning)
5. **Implement** Phase 3 (Loki SimpleScalable migration)
6. **Verify** dashboards work correctly
7. **Optional**: Implement Phase 4 (Tempo S3 migration)
