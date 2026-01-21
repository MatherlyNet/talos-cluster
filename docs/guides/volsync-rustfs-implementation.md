# VolSync PVC Backup with RustFS Implementation Guide

> **Created:** January 2026
> **Status:** Implementation Ready
> **Dependencies:** RustFS deployed, VolSync operator installed
> **Effort:** ~2-3 hours

---

## Overview

This guide implements **VolSync with RustFS** as the S3-compatible backend for PVC (PersistentVolumeClaim) backups. VolSync provides:

- **Point-in-time recovery:** Restic-based deduplication and versioning
- **Scheduled backups:** CronJob-like scheduling via ReplicationSource
- **Encryption:** Restic repository encryption
- **Retention policies:** Hourly, daily, weekly, monthly snapshots

### Architecture

```
VolSync Controller → ReplicationSource CR → Clone PVC → Restic backup → RustFS S3
                                                                            ↓
                                                               rustfs-volsync bucket
                                                                            ↓
                                              Restore via ReplicationDestination → New PVC
```

---

## Prerequisites

### RustFS Deployed

```bash
kubectl -n storage get pods -l app.kubernetes.io/name=rustfs
kubectl -n storage get svc rustfs
```

### Storage Class with Clone Support

VolSync's `Clone` copyMethod requires CSI driver support for volume cloning:

```bash
# Verify Proxmox CSI supports cloning
kubectl get storageclass proxmox-zfs -o yaml | grep -A5 "provisioner"
```

---

## Configuration Variables

### cluster.yaml Variables

```yaml
# =============================================================================
# VOLSYNC PVC BACKUP - Automated PVC backups with restic to S3
# =============================================================================
# VolSync provides restic-based PVC backups to S3-compatible storage.
# Enables point-in-time recovery for stateful applications.
# REF: https://volsync.readthedocs.io/en/stable/

# -- Enable VolSync PVC backup
#    (OPTIONAL) / (DEFAULT: false)
volsync_enabled: true

# -- S3-compatible endpoint for backups
#    For RustFS internal: "http://rustfs.storage.svc.cluster.local:9000"
#    For R2 external: "https://<account-id>.r2.cloudflarestorage.com"
volsync_s3_endpoint: "http://rustfs.storage.svc.cluster.local:9000"

# -- S3 bucket name for VolSync backups
volsync_s3_bucket: "volsync-backups"

# -- S3 access key ID (created in RustFS Console)
#    (Will be SOPS-encrypted after task configure)
volsync_s3_access_key: "volsync"

# -- S3 secret access key
#    (Will be SOPS-encrypted after task configure)
volsync_s3_secret_key: "ENC[AES256_GCM,...]"

# -- Restic repository password for encryption
#    Generate with: openssl rand -base64 32
#    (Will be SOPS-encrypted after task configure)
volsync_restic_password: "ENC[AES256_GCM,...]"

# -- Default backup schedule (cron format)
#    (OPTIONAL) / (DEFAULT: "0 */6 * * *" - every 6 hours)
volsync_schedule: "0 */6 * * *"

# -- Copy method for backups: "Clone" or "Snapshot"
#    Clone: Works with any CSI driver supporting volume cloning (Proxmox CSI)
#    Snapshot: Requires CSI VolumeSnapshot support (faster but less compatible)
#    (OPTIONAL) / (DEFAULT: "Clone")
volsync_copy_method: "Clone"

# -- Default retention policy
volsync_retain_hourly: 6
volsync_retain_daily: 7
volsync_retain_weekly: 4
volsync_retain_monthly: 2
volsync_retain_yearly: 1
```

---

## Template Implementation

### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/storage/volsync/app
```

### Step 2: Create Namespace Entry

VolSync runs in the `storage` namespace.

**Edit:** `templates/config/kubernetes/apps/storage/kustomization.yaml.j2`

```yaml
#% if rustfs_enabled | default(false) or volsync_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: storage

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
#% if rustfs_enabled | default(false) %#
  - ./rustfs/ks.yaml
#% endif %#
#% if volsync_enabled | default(false) %#
  - ./volsync/ks.yaml
#% endif %#
#% endif %#
```

### Step 3: Create Kustomization

**File:** `templates/config/kubernetes/apps/storage/volsync/ks.yaml.j2`

```yaml
#% if volsync_enabled | default(false) %#
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
#% if volsync_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./secret.sops.yaml
#% endif %#
```

### Step 4: Create OCIRepository

**File:** `templates/config/kubernetes/apps/storage/volsync/app/ocirepository.yaml.j2`

```yaml
#% if volsync_enabled | default(false) %#
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

### Step 5: Create HelmRelease

**File:** `templates/config/kubernetes/apps/storage/volsync/app/helmrelease.yaml.j2`

```yaml
#% if volsync_enabled | default(false) %#
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
    resources:
      requests:
        cpu: 10m
        memory: 64Mi
      limits:
        memory: 256Mi
#% endif %#
```

### Step 6: Create Secrets

**File:** `templates/config/kubernetes/apps/storage/volsync/app/secret.sops.yaml.j2`

```yaml
#% if volsync_enabled | default(false) %#
---
# Default restic-config secret for VolSync ReplicationSources
# Individual applications can override with app-specific secrets
apiVersion: v1
kind: Secret
metadata:
  name: volsync-restic-config
  namespace: storage
type: Opaque
stringData:
  RESTIC_REPOSITORY: "s3:#{ volsync_s3_endpoint }#/#{ volsync_s3_bucket }#"
  RESTIC_PASSWORD: "#{ volsync_restic_password }#"
  AWS_ACCESS_KEY_ID: "#{ volsync_s3_access_key }#"
  AWS_SECRET_ACCESS_KEY: "#{ volsync_s3_secret_key }#"
#% endif %#
```

### Step 7: Add RustFS Bucket

Update RustFS bucket setup job to include volsync bucket:

**Edit:** `templates/config/kubernetes/apps/storage/rustfs/setup/job-setup.yaml.j2`

```yaml
env:
  - name: BUCKETS
    value: "loki-chunks,loki-ruler,loki-admin,etcd-backups,volsync-backups"
```

---

## Creating ReplicationSources

### Per-Application Secret

For each application, create a namespace-specific secret:

**File:** `templates/config/kubernetes/apps/<namespace>/<app>/app/volsync-secret.sops.yaml.j2`

```yaml
#% if volsync_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: #{ app_name }#-restic-config
type: Opaque
stringData:
  # Include app name in repository path for isolation
  RESTIC_REPOSITORY: "s3:#{ volsync_s3_endpoint }#/#{ volsync_s3_bucket }#/#{ namespace }#/#{ app_name }#"
  RESTIC_PASSWORD: "#{ volsync_restic_password }#"
  AWS_ACCESS_KEY_ID: "#{ volsync_s3_access_key }#"
  AWS_SECRET_ACCESS_KEY: "#{ volsync_s3_secret_key }#"
#% endif %#
```

### ReplicationSource Template

**File:** `templates/config/kubernetes/apps/<namespace>/<app>/app/replicationsource.yaml.j2`

```yaml
#% if volsync_enabled | default(false) %#
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: #{ app_name }#-backup
spec:
  # PVC to backup
  sourcePVC: #{ pvc_name | default(app_name + '-data') }#

  # Backup schedule
  trigger:
    schedule: "#{ backup_schedule | default(volsync_schedule) | default('0 */6 * * *') }#"

  restic:
    # Prune old snapshots periodically
    pruneIntervalDays: 7

    # Reference to restic-config secret
    repository: #{ app_name }#-restic-config

    # Retention policy
    retain:
      hourly: #{ volsync_retain_hourly | default(6) }#
      daily: #{ volsync_retain_daily | default(7) }#
      weekly: #{ volsync_retain_weekly | default(4) }#
      monthly: #{ volsync_retain_monthly | default(2) }#
      yearly: #{ volsync_retain_yearly | default(1) }#

    # Copy method - Clone works with Proxmox CSI
    copyMethod: "#{ volsync_copy_method | default('Clone') }#"

    # Storage class for temporary clone PVC
    storageClassName: "#{ storage_class | default('proxmox-zfs') }#"

    # Access mode for backup operations
    accessModes:
      - ReadWriteOnce

    # Backup capacity (should match or exceed source PVC)
    capacity: "#{ pvc_capacity | default('10Gi') }#"
#% endif %#
```

---

## Example: Grafana PVC Backup

### Complete Example

**File:** `templates/config/kubernetes/apps/monitoring/kube-prometheus-stack/app/volsync-grafana.yaml.j2`

```yaml
#% if volsync_enabled | default(false) and monitoring_enabled | default(false) %#
---
# Restic config secret for Grafana backup
apiVersion: v1
kind: Secret
metadata:
  name: grafana-restic-config
  namespace: monitoring
type: Opaque
stringData:
  RESTIC_REPOSITORY: "s3:#{ volsync_s3_endpoint }#/#{ volsync_s3_bucket }#/monitoring/grafana"
  RESTIC_PASSWORD: "#{ volsync_restic_password }#"
  AWS_ACCESS_KEY_ID: "#{ volsync_s3_access_key }#"
  AWS_SECRET_ACCESS_KEY: "#{ volsync_s3_secret_key }#"
---
# ReplicationSource for Grafana PVC
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: grafana-backup
  namespace: monitoring
spec:
  sourcePVC: kube-prometheus-stack-grafana
  trigger:
    schedule: "0 */6 * * *"
  restic:
    pruneIntervalDays: 7
    repository: grafana-restic-config
    retain:
      hourly: 6
      daily: 7
      weekly: 4
      monthly: 2
    copyMethod: Clone
    storageClassName: proxmox-zfs
    accessModes:
      - ReadWriteOnce
    capacity: 5Gi
#% endif %#
```

---

## RustFS Access Key Setup

### Create Access Key via Console

1. Access RustFS Console: `https://rustfs.matherly.net` (or port-forward)
2. Login with admin credentials
3. Navigate to: **Identity → Users → Create Access Key**
4. Create key with description: "volsync"
5. Copy access key and secret key
6. Update `volsync_s3_access_key` and `volsync_s3_secret_key` in cluster.yaml

---

## Deployment

### Step 1: Generate Restic Password

```bash
# Generate secure password
openssl rand -base64 32
```

### Step 2: Configure cluster.yaml

```yaml
volsync_enabled: true
volsync_s3_endpoint: "http://rustfs.storage.svc.cluster.local:9000"
volsync_s3_bucket: "volsync-backups"
volsync_s3_access_key: "volsync"
volsync_s3_secret_key: "generated-secret-from-rustfs"
volsync_restic_password: "generated-password-above"
```

### Step 3: Deploy

```bash
task configure
git add -A
git commit -m "feat: add VolSync PVC backup with RustFS S3 backend"
git push
task reconcile
```

### Step 4: Verify

```bash
# Check VolSync deployment
kubectl -n storage get pods -l app.kubernetes.io/name=volsync

# Verify CRDs
kubectl get crd | grep volsync

# Check ReplicationSources
kubectl get replicationsource -A
```

---

## Restore Procedure

### Option 1: ReplicationDestination (Recommended)

Create a ReplicationDestination to restore to a new PVC:

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: grafana-restore
  namespace: monitoring
spec:
  trigger:
    manual: restore-once  # Trigger name for manual restore
  restic:
    repository: grafana-restic-config
    destinationPVC: grafana-restored  # New PVC name
    copyMethod: Direct
    storageClassName: proxmox-zfs
    accessModes:
      - ReadWriteOnce
    capacity: 5Gi
```

Trigger the restore:

```bash
# Update the manual trigger to initiate restore
kubectl -n monitoring patch replicationdestination grafana-restore \
  --type=merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

### Option 2: Direct Restic Restore

```bash
# Get restic credentials
export RESTIC_REPOSITORY="s3:http://rustfs.storage.svc.cluster.local:9000/volsync-backups/monitoring/grafana"
export RESTIC_PASSWORD="your-password"
export AWS_ACCESS_KEY_ID="volsync"
export AWS_SECRET_ACCESS_KEY="your-secret"

# List snapshots
restic snapshots

# Restore specific snapshot
restic restore <snapshot-id> --target /restore-path
```

---

## Monitoring

### Check Backup Status

```bash
# Get all ReplicationSources
kubectl get replicationsource -A

# Detailed status
kubectl describe replicationsource grafana-backup -n monitoring
```

### Prometheus Metrics

VolSync exports metrics via ServiceMonitor:

```promql
# Backup success rate
volsync_replication_source_status{status="Completed"}

# Last sync time
volsync_replication_source_last_sync_time

# Backup duration
volsync_replication_source_duration_seconds
```

### Alerting Rules

```yaml
groups:
  - name: volsync
    rules:
      - alert: VolSyncBackupFailed
        expr: volsync_replication_source_status{status="Failed"} == 1
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "VolSync backup failed for {{ $labels.name }}"

      - alert: VolSyncBackupStale
        expr: time() - volsync_replication_source_last_sync_time > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "VolSync backup stale for {{ $labels.name }}"
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| ReplicationSource stuck | Clone failed | Check CSI driver, verify storage class |
| S3 access denied | Wrong credentials | Verify RustFS access key and bucket |
| Restic init failed | Wrong password or repo | Check RESTIC_PASSWORD in secret |
| PVC clone pending | Insufficient storage | Check Proxmox storage capacity |
| Backup incomplete | Timeout | Increase resources or reduce PVC size |

### Debug Commands

```bash
# Check VolSync controller logs
kubectl -n storage logs -l app.kubernetes.io/name=volsync -f

# Check ReplicationSource events
kubectl -n monitoring describe replicationsource grafana-backup

# Test S3 connectivity from cluster
kubectl -n storage run s3-test --rm -it --image=minio/mc -- \
  mc alias set rustfs http://rustfs.storage.svc.cluster.local:9000 $KEY $SECRET && \
  mc ls rustfs/volsync-backups/

# Initialize restic repo manually (for testing)
kubectl -n storage run restic-init --rm -it --image=restic/restic \
  --env="RESTIC_REPOSITORY=s3:http://rustfs.storage.svc.cluster.local:9000/volsync-backups/test" \
  --env="RESTIC_PASSWORD=test123" \
  --env="AWS_ACCESS_KEY_ID=volsync" \
  --env="AWS_SECRET_ACCESS_KEY=secret" \
  -- init
```

---

## Best Practices

### PVC Naming Convention

Use consistent naming for backup identification:

```
<namespace>/<app-name>/<pvc-name>
```

Example: `monitoring/grafana/grafana-data`

### Retention Strategy

| Environment | Hourly | Daily | Weekly | Monthly | Yearly |
| ----------- | ------ | ----- | ------ | ------- | ------ |
| Development | 3 | 3 | 2 | 1 | 0 |
| Staging | 6 | 7 | 4 | 2 | 0 |
| Production | 12 | 14 | 8 | 6 | 2 |

### Backup Window

Schedule backups during low-activity periods:

```yaml
# Stagger backups to avoid I/O contention
grafana:   "0 2 * * *"   # 2 AM
prometheus: "0 3 * * *"  # 3 AM
loki:      "0 4 * * *"   # 4 AM
```

---

## References

### External Documentation

- [VolSync Documentation](https://volsync.readthedocs.io/en/stable/)
- [Restic-based Backup](https://volsync.readthedocs.io/en/latest/usage/restic/)
- [VolSync Helm Chart](https://github.com/backube/volsync)

### Project Documentation

- [k8s-at-home Remaining Implementation](./k8s-at-home-remaining-implementation.md#phase-2-volsync-pvc-backup)
- [RustFS Research](../research/archive/completed/rustfs-shared-storage-loki-simplescalable-jan-2026.md)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial implementation guide for RustFS backend |
