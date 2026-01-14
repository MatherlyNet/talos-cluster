# CloudNativePG Implementation Guide

> **Created:** January 2026
> **Status:** Deployed ✅ (January 6, 2026)
> **Dependencies:** Flux CD, SOPS/Age encryption, Storage class (local-path or Proxmox CSI)
> **Effort:** Complete - Operator operational, Keycloak PostgreSQL cluster running

---

## Overview

This guide implements **CloudNativePG (CNPG)** as a shared PostgreSQL operator for the cluster. CNPG provides production-grade PostgreSQL clusters with automated failover, backups, and monitoring.

### Why CloudNativePG?

| Feature | Benefit |
| ------- | ------- |
| **CNCF Incubating** | Kubernetes-native, community-backed |
| **PostgreSQL 18 Support** | Latest PostgreSQL with extension_control_path |
| **Automated HA** | Quorum-based failover (stable in 1.28) |
| **Barman Cloud Backups** | S3-compatible backup to RustFS |
| **Self-Healing** | Automatic replica recreation |
| **Multi-tenant** | Single operator serves multiple databases |

### Shared Resource Pattern

Like RustFS, CNPG is deployed as a **shared cluster resource**:
- Single operator in `cnpg-system` namespace
- Cluster CRs deployed per-application in their respective namespaces
- Centralized operator management, distributed data ownership

```
cnpg-system/              # Operator namespace
├── cloudnative-pg        # Operator deployment
└── ConfigMap             # Operator configuration

identity/                 # Keycloak database
└── keycloak-postgres     # CNPG Cluster CR

future-app/               # Future application
└── app-postgres          # Another CNPG Cluster CR
```

---

## Version Information (January 2026)

| Component | Version | Notes |
| --------- | ------- | ----- |
| **CNPG Operator** | 1.28.0 | Stable quorum failover, Foreign Data Wrapper support |
| **Helm Chart** | 0.27.0 | Latest operator chart |
| **PostgreSQL** | 18.1 | Default with `extension_control_path` support |
| **Image** | `ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie` | JIT support included |
| **Barman Cloud Plugin** | 0.4.0 | For S3 backups (optional) |

### PostgreSQL 18 Image Options

| Image Type | Tag Example | Size | Use Case |
| ---------- | ----------- | ---- | -------- |
| **Standard** | `18.1-standard-trixie` | ~400MB | Production (includes JIT) |
| **Minimal** | `18.1-minimal-trixie` | ~260MB | Resource-constrained |
| **System** (deprecated) | `18.1-system-trixie` | ~500MB | Legacy with Barman in-core |

---

## Configuration Variables

### Required Variables (cluster.yaml)

```yaml
# =============================================================================
# CLOUDNATIVEPG OPERATOR - PostgreSQL Operator for Kubernetes
# =============================================================================
# CloudNativePG provides production-grade PostgreSQL clusters with automated
# failover, backups, and monitoring. Deployed as a shared cluster resource.
# REF: https://cloudnative-pg.io/docs/1.28/
# REF: docs/guides/cnpg-implementation.md

# -- Enable CloudNativePG operator deployment
#    (OPTIONAL) / (DEFAULT: false)
cnpg_enabled: false

# -- PostgreSQL image to use for new clusters
#    Options: 18.1-standard-trixie (default), 18.1-minimal-trixie
#    (OPTIONAL) / (DEFAULT: "ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie")
cnpg_postgres_image: "ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie"

# -- Default storage class for CNPG clusters
#    (OPTIONAL) / (DEFAULT: uses storage_class variable)
cnpg_storage_class: ""

# -- Enable CNPG backups to RustFS S3
#    Requires rustfs_enabled: true
#    (OPTIONAL) / (DEFAULT: false)
cnpg_backup_enabled: false

# -- S3 credentials for CNPG backups (SOPS-encrypted)
#    Create access key via RustFS Console UI
#    (REQUIRED when cnpg_backup_enabled: true)
# cnpg_s3_access_key: ""
# cnpg_s3_secret_key: ""

# -- Operator priority class
#    (OPTIONAL) / (DEFAULT: "system-cluster-critical")
cnpg_priority_class: "system-cluster-critical"

# -- Deploy operator on control-plane nodes
#    (OPTIONAL) / (DEFAULT: true for homelab single control-plane)
cnpg_control_plane_only: true
```

### Derived Variables (plugin.py)

Add to `templates/scripts/plugin.py`:

```python
# CloudNativePG - enabled when cnpg_enabled is true
cnpg_enabled = data.get("cnpg_enabled", False)
variables["cnpg_enabled"] = cnpg_enabled

# CNPG backup - enabled when both cnpg and rustfs are enabled with backup flag
cnpg_backup_enabled = (
    cnpg_enabled and
    data.get("rustfs_enabled", False) and
    data.get("cnpg_backup_enabled", False) and
    data.get("cnpg_s3_access_key") and
    data.get("cnpg_s3_secret_key")
)
variables["cnpg_backup_enabled"] = cnpg_backup_enabled

# Default PostgreSQL image
cnpg_postgres_image = data.get(
    "cnpg_postgres_image",
    "ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie"
)
variables["cnpg_postgres_image"] = cnpg_postgres_image
```

---

## Template Implementation

### Directory Structure

```
templates/config/kubernetes/apps/cnpg-system/
├── kustomization.yaml.j2
├── namespace.yaml.j2
└── cloudnative-pg/
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── helmrepository.yaml.j2
        ├── helmrelease.yaml.j2
        └── configmap.yaml.j2      # Operator configuration
```

### Step 1: Create Namespace Kustomization

**File:** `templates/config/kubernetes/apps/cnpg-system/kustomization.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: cnpg-system

resources:
  - ./namespace.yaml
  - ./cloudnative-pg/ks.yaml
#% endif %#
```

### Step 2: Create Namespace

**File:** `templates/config/kubernetes/apps/cnpg-system/namespace.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: cnpg-system
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
#% endif %#
```

### Step 3: Create Flux Kustomization

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/ks.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cloudnative-pg
spec:
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: cloudnative-pg
      namespace: cnpg-system
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/cnpg-system/cloudnative-pg/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: cnpg-system
  timeout: 15m
  wait: true
#% endif %#
```

### Step 4: Create HelmRepository

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/helmrepository.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: cloudnative-pg
spec:
  interval: 24h
  url: https://cloudnative-pg.github.io/charts
#% endif %#
```

### Step 5: Create HelmRelease

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/helmrelease.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cloudnative-pg
spec:
  chart:
    spec:
      chart: cloudnative-pg
      version: "0.27.0"
      sourceRef:
        kind: HelmRepository
        name: cloudnative-pg
        namespace: cnpg-system
  interval: 1h
  install:
    crds: CreateReplace
    remediation:
      retries: 3
  upgrade:
    crds: CreateReplace
    cleanupOnFail: true
    remediation:
      retries: 3
  values:
    #| Priority class for operator #|
    priorityClassName: #{ cnpg_priority_class | default('system-cluster-critical') }#

    #| Operator configuration via ConfigMap #|
    config:
      data:
        #| Certificate validity (days) #|
        CERTIFICATE_DURATION: "180"
        #| Kubernetes cluster domain #|
        KUBERNETES_CLUSTER_DOMAIN: "cluster.local"
        #| Node drain taints to monitor #|
        DRAIN_TAINTS: "node.kubernetes.io/unschedulable,ToBeDeletedByClusterAutoscaler"
        #| Default PostgreSQL image for new clusters #|
        POSTGRES_IMAGE_NAME: "#{ cnpg_postgres_image }#"

    #| Resource requests/limits for operator #|
    resources:
      requests:
        cpu: 100m
        memory: 100Mi
      limits:
        memory: 256Mi

    #| Prometheus annotations for scraping #|
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "8080"

    #% if cnpg_control_plane_only | default(true) %#
    #| Schedule operator on control-plane nodes #|
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""

    tolerations:
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
    #% endif %#

    #| Pod security context #|
    podSecurityContext:
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault

    #| Container security context #|
    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: true
      runAsNonRoot: true
#% endif %#
```

### Step 6: Create App Kustomization

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/kustomization.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
#% endif %#
```

### Step 7: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add the cnpg-system namespace:

```yaml
resources:
  # ... existing resources ...
#% if cnpg_enabled | default(false) %#
  - ./cnpg-system
#% endif %#
```

---

## Creating PostgreSQL Clusters

Once the operator is deployed, create CNPG Cluster CRs in application namespaces.

### Basic Cluster Template

This is a reusable pattern for applications needing PostgreSQL:

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <app>-postgres
  namespace: <app-namespace>
spec:
  #| Number of instances (1 for dev, 3 for HA production) #|
  instances: 3

  #| PostgreSQL 18 image #|
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie

  #| Bootstrap with initial database and owner #|
  bootstrap:
    initdb:
      database: <database_name>
      owner: <database_user>
      secret:
        name: <app>-db-credentials

  #| Storage configuration #|
  storage:
    size: 10Gi
    storageClass: <storage_class>

  #| Resource limits #|
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 1000m

  #| Enable Prometheus PodMonitor #|
  monitoring:
    enablePodMonitor: true

  #| PostgreSQL configuration #|
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
      effective_cache_size: "768MB"
      maintenance_work_mem: "128MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
      work_mem: "4MB"
      huge_pages: "off"
      min_wal_size: "1GB"
      max_wal_size: "4GB"

  #| Pod anti-affinity for HA #|
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
```

### Keycloak Integration Example

Update the Keycloak implementation to use CNPG:

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/postgres-cnpg.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and (keycloak_db_mode | default('embedded')) == 'cnpg' %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: keycloak-postgres
  namespace: identity
spec:
  instances: #{ keycloak_db_instances | default(3) }#
  imageName: #{ cnpg_postgres_image | default('ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie') }#

  bootstrap:
    initdb:
      database: #{ keycloak_db_name | default('keycloak') }#
      owner: #{ keycloak_db_user | default('keycloak') }#
      secret:
        name: keycloak-db-secret

  storage:
    size: #{ keycloak_storage_size | default('10Gi') }#
    storageClass: #{ cnpg_storage_class | default(storage_class) | default('local-path') }#

  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 1000m

  monitoring:
    enablePodMonitor: #{ 'true' if monitoring_enabled | default(false) else 'false' }#

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"

  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname

#% if cnpg_backup_enabled | default(false) %#
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/keycloak"
      endpointURL: "http://rustfs.storage.svc.cluster.local:9000"
      s3Credentials:
        accessKeyId:
          name: cnpg-backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: cnpg-backup-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
        maxParallel: 2
    retentionPolicy: "7d"
#% endif %#
#% endif %#
```

---

## Backup Configuration with RustFS

> ⚠️ **IMPORTANT**: RustFS does NOT support `mc admin` commands for IAM management.
> All user/policy operations must be performed via the **RustFS Console UI** (port 9001).
> See [RustFS IAM Documentation](https://docs.rustfs.com/administration/iam/access-token.html)

### Create RustFS Bucket

Add `cnpg-backups` to the RustFS bucket setup job:

**Edit:** `templates/config/kubernetes/apps/storage/rustfs/setup/job-setup.yaml.j2`

```yaml
env:
  - name: BUCKETS
    value: "loki-chunks,loki-ruler,loki-admin,etcd-backups,cnpg-backups"
```

### Create RustFS Access Key (Console UI)

Following the same IAM pattern used for Loki (`monitoring` group) and Talos Backup (`backups` group), create a custom scoped policy for CNPG database backups.

#### Step 1: Create Custom Policy

Create this policy in RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `database-storage`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::cnpg-backups"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::cnpg-backups/*"
      ]
    }
  ]
}
```

**Why This Policy:**

| Requirement | Permission | Purpose |
| ----------- | ---------- | ------- |
| List objects | `s3:ListBucket` | List WAL files and base backups for retention |
| Read backups | `s3:GetObject` | Download backups for restore/PITR |
| Write backups | `s3:PutObject` | Upload base backups and WAL segments |
| Delete objects | `s3:DeleteObject` | Retention cleanup of old backups |
| Bucket location | `s3:GetBucketLocation` | Barman Cloud SDK compatibility |

**Why Not Built-in `readwrite`:**
- The `readwrite` policy grants access to **ALL** buckets
- The custom `database-storage` policy scopes access to only `cnpg-backups` bucket
- This protects other buckets (loki-chunks, etcd-backups, etc.) from database backup access (principle of least privilege)

#### Step 2: Create Database Group

1. Navigate to **Identity** → **Groups** → **Create Group**
2. **Name:** `databases`
3. **Assign Policy:** `database-storage`
4. Click **Save**

#### Step 3: Create CNPG Service Account

1. Navigate to **Identity** → **Users** → **Create User**
2. **Access Key:** `cnpg-backup` (or any meaningful name)
3. **Assign to Group:** `databases`
4. Click **Save**

#### Step 4: Generate Access Key

1. Click on the newly created user (`cnpg-backup`)
2. Navigate to **Service Accounts** tab
3. Click **Create Access Key**
4. ⚠️ **Copy and save both keys immediately** - the secret key won't be shown again!

#### Step 5: Update cluster.yaml

```yaml
cnpg_s3_access_key: "<access-key-from-step-4>"
cnpg_s3_secret_key: "<secret-key-from-step-4>"
```

#### Step 6: Apply Changes

```bash
task configure
task reconcile
```

### IAM Architecture Summary

The CNPG IAM structure mirrors Loki and Talos Backup:

| Component | Loki (Monitoring) | Talos Backup | CNPG |
| --------- | ----------------- | ------------ | ---- |
| **Policy** | `loki-storage` | `backup-storage` | `database-storage` |
| **Scoped Buckets** | `loki-chunks`, `loki-ruler`, `loki-admin` | `etcd-backups` | `cnpg-backups` |
| **Group** | `monitoring` | `backups` | `databases` |
| **User** | `loki` | `talos-backup` | `cnpg-backup` |
| **Permissions** | Full CRUD on loki-* | Full CRUD on etcd-backups | Full CRUD on cnpg-backups |

This pattern ensures:
- **Principle of least privilege**: Each service only accesses its own buckets
- **Audit trail**: User/group structure enables access tracking
- **Scalability**: Future PostgreSQL clusters can share the same credentials or have dedicated users in the `databases` group

### Create Backup Credentials Secret

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/secret-backup.sops.yaml.j2`

```yaml
#% if cnpg_backup_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: cnpg-backup-credentials
  namespace: cnpg-system
type: Opaque
stringData:
  ACCESS_KEY_ID: "#{ cnpg_s3_access_key }#"
  SECRET_ACCESS_KEY: "#{ cnpg_s3_secret_key }#"
#% endif %#
```

### Scheduled Backup Configuration

CNPG supports ScheduledBackup CRs:

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: keycloak-backup-daily
  namespace: identity
spec:
  schedule: "0 0 * * *"  # Daily at midnight
  backupOwnerReference: self
  cluster:
    name: keycloak-postgres
  method: barmanObjectStore
```

---

## Cilium Network Policies

When network policies are enabled, CNPG requires specific access rules.

### Operator Access Policy

```yaml
#% if network_policies_enabled | default(false) and cnpg_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cnpg-operator-egress
  namespace: cnpg-system
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: cloudnative-pg
  egress:
    #| Allow operator to access all CNPG cluster pods on port 8000 #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: ""
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    #| Allow DNS resolution #|
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    #| Allow Kubernetes API access #|
    - toEntities:
        - kube-apiserver
#% endif %#
```

### PostgreSQL Cluster Access Policy (Example for Keycloak)

```yaml
#% if network_policies_enabled | default(false) and keycloak_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: keycloak-postgres-access
  namespace: identity
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: keycloak-postgres
  ingress:
    #| Allow CNPG operator health checks #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: cloudnative-pg
            k8s:io.kubernetes.pod.namespace: cnpg-system
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    #| Allow Keycloak access to PostgreSQL #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloakx
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| Allow inter-pod replication #|
    - fromEndpoints:
        - matchLabels:
            cnpg.io/cluster: keycloak-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| Allow Prometheus scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            k8s:io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9187"
              protocol: TCP
#% endif %#
```

---

## Deployment

### Step 1: Configure Variables

Edit `cluster.yaml`:

```yaml
# Enable CloudNativePG
cnpg_enabled: true
cnpg_postgres_image: "ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie"
cnpg_control_plane_only: true

# Optional: Enable backups to RustFS
cnpg_backup_enabled: true
cnpg_s3_access_key: "cnpg-backup"  # Will be SOPS-encrypted
cnpg_s3_secret_key: "your-secret-key"  # Will be SOPS-encrypted
```

### Step 2: Generate and Encrypt

```bash
# Regenerate templates
task configure

# Verify generated files
ls kubernetes/apps/cnpg-system/
```

### Step 3: Deploy

```bash
# Commit and push
git add -A
git commit -m "feat: add CloudNativePG operator for shared PostgreSQL clusters"
git push

# Reconcile
task reconcile

# Watch deployment
kubectl -n cnpg-system get pods -w
```

### Step 4: Verify Operator

```bash
# Check operator is running
kubectl -n cnpg-system get pods

# Check CRDs installed
kubectl get crd | grep cnpg

# Expected CRDs:
# backups.postgresql.cnpg.io
# clusters.postgresql.cnpg.io
# poolers.postgresql.cnpg.io
# scheduledbackups.postgresql.cnpg.io
```

---

## Verification

### Check Operator Status

```bash
# View operator logs
kubectl -n cnpg-system logs -l app.kubernetes.io/name=cloudnative-pg --tail=50

# Check operator metrics
kubectl -n cnpg-system port-forward svc/cloudnative-pg-webhook-service 8080:443
curl -k https://localhost:8080/metrics
```

### Check Cluster Status

```bash
# List all CNPG clusters
kubectl get clusters -A

# Describe a specific cluster
kubectl -n identity describe cluster keycloak-postgres

# Check cluster status
kubectl cnpg status keycloak-postgres -n identity
```

### Test Database Connectivity

```bash
# Get connection info
kubectl -n identity get secret keycloak-postgres-app -o jsonpath='{.data.uri}' | base64 -d

# Port-forward to primary
kubectl -n identity port-forward svc/keycloak-postgres-rw 5432:5432

# Connect with psql
psql postgresql://keycloak:password@localhost:5432/keycloak
```

---

## Operations

### Manual Failover

```bash
# Promote a specific replica to primary
kubectl cnpg promote keycloak-postgres replica-2 -n identity
```

### Manual Backup

```bash
# Trigger an immediate backup
kubectl cnpg backup keycloak-postgres -n identity
```

### Restore from Backup

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: keycloak-postgres-restored
  namespace: identity
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie

  bootstrap:
    recovery:
      source: keycloak-postgres-backup
      # Optional: Point-in-time recovery
      # recoveryTarget:
      #   targetTime: "2026-01-06 12:00:00.000000+00"

  externalClusters:
    - name: keycloak-postgres-backup
      barmanObjectStore:
        destinationPath: "s3://cnpg-backups/keycloak"
        endpointURL: "http://rustfs.storage.svc.cluster.local:9000"
        s3Credentials:
          accessKeyId:
            name: cnpg-backup-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: cnpg-backup-credentials
            key: SECRET_ACCESS_KEY

  storage:
    size: 10Gi
    storageClass: local-path
```

### Scaling

```bash
# Scale up replicas
kubectl -n identity patch cluster keycloak-postgres --type=merge -p '{"spec":{"instances":5}}'

# Scale down (careful - data loss possible if removing primary)
kubectl -n identity patch cluster keycloak-postgres --type=merge -p '{"spec":{"instances":3}}'
```

---

## Monitoring

### ServiceMonitor (Already enabled via PodMonitor)

CNPG automatically creates PodMonitors when `monitoring.enablePodMonitor: true`.

### Grafana Dashboards

Import the official CNPG Grafana dashboard:
- Dashboard ID: `20417` (CloudNativePG)
- Source: grafana.com/grafana/dashboards/20417

### Key Metrics

| Metric | Description |
| ------ | ----------- |
| `cnpg_collector_up` | Collector availability |
| `cnpg_pg_replication_lag` | Replication lag (seconds) |
| `cnpg_pg_database_size_bytes` | Database size |
| `cnpg_pg_stat_statements_*` | Query performance |
| `cnpg_pg_wal_*` | WAL statistics |

### Prometheus Alerts

```yaml
groups:
  - name: cnpg
    rules:
      - alert: CNPGClusterNotHealthy
        expr: cnpg_cluster_status != 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "CNPG cluster {{ $labels.cluster }} is not healthy"

      - alert: CNPGReplicationLagHigh
        expr: cnpg_pg_replication_lag > 60
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CNPG cluster {{ $labels.cluster }} has high replication lag"

      - alert: CNPGBackupFailed
        expr: cnpg_pg_backup_last_failed_time > cnpg_pg_backup_last_successful_time
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "CNPG backup failed for {{ $labels.cluster }}"
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| Cluster stuck in "Setting up primary" | PVC not binding | Check storage class, verify PV availability |
| Replica not connecting | Network policy blocking | Add CNPG operator to ingress policy |
| Backup failing | S3 credentials wrong | Verify secret values, test mc connectivity |
| High replication lag | Slow storage | Use faster storage class, check IOPs |
| Pod evicted | Resource limits | Increase memory limits |
| Connection refused | Wrong service name | Use `-rw` for primary, `-ro` for replicas |

### Debug Commands

```bash
# Check CNPG operator logs
kubectl -n cnpg-system logs -l app.kubernetes.io/name=cloudnative-pg -f

# Check cluster status with kubectl plugin
kubectl cnpg status <cluster-name> -n <namespace>

# Check PostgreSQL logs
kubectl -n identity logs keycloak-postgres-1 -c postgres

# Describe failing pod
kubectl -n identity describe pod keycloak-postgres-1

# Check events
kubectl -n identity get events --sort-by='.lastTimestamp' | grep -i postgres

# Test S3 connectivity for backups
kubectl run mc-test --rm -it --image=minio/mc -- \
  mc alias set rustfs http://rustfs.storage.svc.cluster.local:9000 $KEY $SECRET && mc ls rustfs/cnpg-backups/
```

---

## Security Considerations

### Pod Security

CNPG enforces restricted pod security by default:
- Runs as non-root user `postgres`
- Read-only root filesystem
- No privilege escalation
- Dropped all capabilities

### TLS

All connections use TLS by default:
- Client-to-PostgreSQL (port 5432)
- Operator-to-instance (port 8000)
- Replication between nodes

### Secrets

- Database credentials stored in Kubernetes Secrets
- Use SOPS/Age encryption in GitOps
- Rotate credentials via `cnpg.io/reload: "true"` label

### Network Isolation

- Deploy network policies to restrict PostgreSQL access
- Only allow application pods to connect on 5432
- Restrict operator access to port 8000

---

## pgvector Extension with ImageVolume

PostgreSQL 18 introduces `extension_control_path`, enabling CloudNativePG to mount extensions from dedicated container images using Kubernetes ImageVolume. This eliminates custom image builds.

### Version Information (January 2026)

| Component | Version | Notes |
| --------- | ------- | ----- |
| **pgvector** | 0.8.1 | Latest release, iterative index scans |
| **Extension Image** | `ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie` | Official CNPG community image |
| **Kubernetes** | 1.35+ | ImageVolume beta, enabled by default |
| **Container Runtime** | containerd 2.1.0+ or CRI-O 1.31+ | subPath support required |

### Requirements

ImageVolume extension mounting requires:

1. **PostgreSQL 18+** - `extension_control_path` GUC support
2. **Kubernetes 1.35+** - ImageVolume feature enabled by default (beta)
3. **CloudNativePG 1.27+** - Extension mounting support
4. **Compatible extension images** - Matching PostgreSQL version, OS, and architecture

> **Note:** This project uses Kubernetes 1.35.0 and PostgreSQL 18, meeting all requirements.

### Configuration Variables

Add to `cluster.yaml` when pgvector is needed:

```yaml
# =============================================================================
# PGVECTOR EXTENSION - Vector similarity search for AI/ML workloads
# =============================================================================
# pgvector provides native vector data types for similarity search, embedding
# storage, and AI-driven use cases. Mounted via ImageVolume (no custom images).
# REF: https://github.com/pgvector/pgvector
# REF: https://cloudnative-pg.io/docs/1.28/imagevolume_extensions/

# -- Enable pgvector extension for CNPG clusters
#    (OPTIONAL) / (DEFAULT: false)
cnpg_pgvector_enabled: false

# -- pgvector extension image
#    (OPTIONAL) / (DEFAULT: "ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie")
cnpg_pgvector_image: "ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie"

# -- pgvector version (must match image tag)
#    (OPTIONAL) / (DEFAULT: "0.8.1")
cnpg_pgvector_version: "0.8.1"
```

### Derived Variables (plugin.py)

Add to `templates/scripts/plugin.py`:

```python
# pgvector extension - enabled when cnpg and pgvector are both enabled
cnpg_pgvector_enabled = (
    data.get("cnpg_enabled", False) and
    data.get("cnpg_pgvector_enabled", False)
)
variables["cnpg_pgvector_enabled"] = cnpg_pgvector_enabled

# Default pgvector image
cnpg_pgvector_image = data.get(
    "cnpg_pgvector_image",
    "ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie"
)
variables["cnpg_pgvector_image"] = cnpg_pgvector_image

cnpg_pgvector_version = data.get("cnpg_pgvector_version", "0.8.1")
variables["cnpg_pgvector_version"] = cnpg_pgvector_version
```

### Cluster with pgvector Extension

**Example:** AI/ML database cluster with vector search capabilities:

> **IMPORTANT:** Use `postgresql.extensions` (ImageVolume) to mount extensions, NOT `imageCatalogRef`.
> The extension images (e.g., `ghcr.io/cloudnative-pg/pgvector:*`) are scratch-based images containing only
> extension files - they are NOT full PostgreSQL images and cannot be used as the main container image.

```yaml
#% if cnpg_enabled | default(false) %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ai-postgres
  namespace: ai-workloads
spec:
  instances: 3
  #| Always use full PostgreSQL image - extensions mount via ImageVolume #|
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie

  bootstrap:
    initdb:
      database: vectors
      owner: ai_app
      secret:
        name: ai-db-credentials

  storage:
    size: 50Gi
    storageClass: #{ storage_class | default('local-path') }#

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
#% if cnpg_pgvector_enabled | default(false) %#
    #| Mount pgvector extension via ImageVolume (K8s 1.35+, PostgreSQL 18+) #|
    extensions:
      - name: pgvector
        image:
          reference: #{ cnpg_pgvector_image }#
#% endif %#

  monitoring:
    enablePodMonitor: #{ 'true' if monitoring_enabled | default(false) else 'false' }#

  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
#% endif %#
```

### Database Resource with Extension Activation

CloudNativePG's `Database` CRD declaratively creates extensions:

```yaml
#% if cnpg_enabled | default(false) and cnpg_pgvector_enabled | default(false) %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: ai-vectors-db
  namespace: ai-workloads
spec:
  name: vectors
  owner: ai_app
  cluster:
    name: ai-postgres
  extensions:
    - name: vector
      version: '#{ cnpg_pgvector_version }#'
#% endif %#
```

This executes: `CREATE EXTENSION vector VERSION '0.8.1'`

### How ImageVolume Works

1. **Extension images mount at** `/extensions/<EXTENSION_NAME>`
2. **CloudNativePG automatically sets**:
   - `extension_control_path` → `/extensions/pgvector/share`
   - `dynamic_library_path` → `/extensions/pgvector/lib`
3. **PostgreSQL locates** extension control files and shared libraries
4. **Extensions mount read-only** - immutable, no runtime modification

```
PostgreSQL Pod
├── /extensions/pgvector/           # ImageVolume mount (read-only)
│   ├── share/extension/
│   │   ├── vector.control
│   │   └── vector--0.8.1.sql
│   └── lib/
│       └── vector.so
└── /var/lib/postgresql/data/       # PVC (read-write)
```

### Multiple Extensions Example

Mount multiple extensions for complex workloads:

```yaml
postgresql:
  extensions:
    - name: pgvector
      image:
        reference: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie
    - name: postgis
      image:
        reference: ghcr.io/cloudnative-pg/postgis-extension:3.6.1-18-trixie
      #| PostGIS requires system libraries #|
      ld_library_path:
        - system
```

> **Note:** `ld_library_path: [system]` ensures PostGIS finds GEOS, PROJ, and GDAL libraries.

### Verification

**Check extension volumes are mounted:**

```bash
# List mounted extensions
kubectl exec -ti ai-postgres-1 -c postgres -- ls /extensions/

# Expected output:
# pgvector

# Verify extension files
kubectl exec -ti ai-postgres-1 -c postgres -- ls /extensions/pgvector/share/extension/

# Expected:
# vector.control
# vector--0.8.1.sql
```

**Verify extension is activated:**

```bash
# Connect and list extensions
kubectl cnpg psql ai-postgres -- vectors -c '\dx'

# Expected output includes:
#  Name   | Version |   Schema   |         Description
# --------+---------+------------+------------------------------
#  vector | 0.8.1   | public     | vector data type and ivfflat and hnsw access methods
```

**Test vector operations:**

```bash
kubectl cnpg psql ai-postgres -- vectors -c "
  CREATE TABLE items (id SERIAL PRIMARY KEY, embedding vector(3));
  INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
  SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
"
```

### pgvector Use Cases

| Use Case | Description | Index Type |
| -------- | ----------- | ---------- |
| **Semantic Search** | Text embedding similarity | HNSW |
| **Image Search** | Image embedding matching | HNSW |
| **Recommendation** | User/item embeddings | IVFFlat |
| **RAG Applications** | LLM context retrieval | HNSW |
| **Anomaly Detection** | Distance from normal vectors | IVFFlat |

### Performance Tuning for pgvector

Add PostgreSQL parameters for vector workloads:

```yaml
postgresql:
  parameters:
    # Increase for vector operations
    maintenance_work_mem: "512MB"
    # HNSW index build parallelism
    max_parallel_maintenance_workers: "4"
    # Query parallelism
    max_parallel_workers_per_gather: "4"
    # pgvector-specific (0.8.0+)
    # Enable iterative index scans to prevent overfiltering
    # hnsw.iterative_scan: "relaxed_order"
  extensions:
    - name: pgvector
      image:
        reference: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie
```

### Upgrading pgvector

To upgrade pgvector versions:

1. **Update image reference** in Cluster spec:
   ```yaml
   extensions:
     - name: pgvector
       image:
         reference: ghcr.io/cloudnative-pg/pgvector:0.9.0-18-trixie  # New version
   ```

2. **Update Database extension version**:
   ```yaml
   extensions:
     - name: vector
       version: '0.9.0'  # New version
   ```

3. **Apply changes** - CloudNativePG performs rolling update

> **Note:** Adding/removing extensions triggers pod rolling updates. Plan upgrades during maintenance windows.

### Troubleshooting pgvector

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| `initdb: executable file not found` | Using extension image as main image | Use full PostgreSQL image (`imageName`), mount extension via `postgresql.extensions` |
| `imageName and imageCatalogRef are mutually exclusive` | Using ImageCatalog instead of ImageVolume | Remove `imageCatalogRef`, use `postgresql.extensions` block instead |
| Extension not found | ImageVolume not mounted | Verify K8s 1.35+, check pod events |
| CREATE EXTENSION fails | Version mismatch | Ensure Database version matches image |
| Slow vector queries | Missing index | Create HNSW or IVFFlat index |
| OOM during index build | Insufficient memory | Increase `maintenance_work_mem` |
| Extension mount timeout | Large image pull | Pre-pull image on nodes |

**Debug commands:**

```bash
# Check ImageVolume mount status
kubectl describe pod ai-postgres-1 | grep -A5 "Volumes:"

# Check extension_control_path is set
kubectl cnpg psql ai-postgres -- vectors -c "SHOW extension_control_path;"

# Check available extensions
kubectl cnpg psql ai-postgres -- vectors -c "SELECT * FROM pg_available_extensions WHERE name = 'vector';"

# Check operator logs for extension errors
kubectl -n cnpg-system logs -l app.kubernetes.io/name=cloudnative-pg | grep -i extension
```

---

## References

### External Documentation
- [CloudNativePG Documentation](https://cloudnative-pg.io/docs/1.28/)
- [CloudNativePG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
- [Helm Chart Repository](https://github.com/cloudnative-pg/charts)
- [PostgreSQL 18 Release Notes](https://www.postgresql.org/docs/18/release-18.html)
- [Barman Cloud Plugin](https://cloudnative-pg.io/docs/1.28/backup_recovery#barman-cloud)
- [ImageVolume Extensions](https://cloudnative-pg.io/docs/1.28/imagevolume_extensions/) - Extension mounting via Kubernetes ImageVolume
- [pgvector GitHub](https://github.com/pgvector/pgvector) - Open-source vector similarity search
- [CNPG Recipe 23](https://www.gabrielebartolini.it/articles/2025/12/cnpg-recipe-23-managing-extensions-with-imagevolume-in-cloudnativepg/) - ImageVolume extension tutorial

### Project Documentation
- [Keycloak Implementation](./keycloak-implementation.md) - Primary CNPG consumer
- [RustFS Implementation](../research/archive/completed/rustfs-shared-storage-loki-simplescalable-jan-2026.md) - Backup storage
- [Talos Backup with RustFS](./talos-backup-rustfs-implementation.md) - IAM pattern reference
- [Cilium Network Policies](../research/archive/cilium-network-policies-jan-2026.md) - Network isolation

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial implementation guide created |
| 2026-01-06 | Added pgvector extension with ImageVolume support |
| 2026-01-06 | Added comprehensive RustFS IAM instructions (database-storage policy, databases group, cnpg-backup user) |
| 2026-01-06 | Fixed pgvector config: Use `postgresql.extensions` (ImageVolume), NOT `imageCatalogRef` - extension images are scratch-based |
