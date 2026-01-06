# Talos Backup with RustFS Implementation Guide

> **Created:** January 2026
> **Status:** Implementation Ready
> **Dependencies:** RustFS deployed, Talos API access patch applied
> **Effort:** ~1-2 hours

---

## Overview

This guide implements **Talos Backup with RustFS** as the S3-compatible backend for etcd snapshots. Using RustFS instead of Cloudflare R2 provides:

- **Self-hosted storage:** No external dependencies
- **Zero egress costs:** All traffic stays within cluster
- **Unified storage:** Same backend for logs (Loki), backups, and other services
- **Performance:** RustFS is 2.3x faster than MinIO for small objects

### Architecture

```
talos-backup CronJob → etcd snapshot → Age encryption → RustFS S3 API
                                                           ↓
                                               rustfs-etcd-backups bucket
```

---

## Prerequisites

### RustFS Deployed

Verify RustFS is running:

```bash
kubectl -n storage get pods -l app.kubernetes.io/name=rustfs
kubectl -n storage get svc rustfs
```

### Talos API Access

Verify machine patch includes `os:etcd:backup` role:

```bash
talosctl get machineconfig -n $(yq '.nodes[0].ip' nodes.yaml) -o yaml | grep -A10 kubernetesTalosAPIAccess
```

---

## Configuration Changes

### Step 1: Update cluster.yaml

Modify the backup configuration to use RustFS:

```yaml
# =============================================================================
# TALOS BACKUP - Automated etcd snapshots with S3 storage
# =============================================================================
# Talos Backup creates periodic etcd snapshots and uploads them to S3-compatible
# storage with Age encryption. Required for disaster recovery.
#
# OPTION A: Cloudflare R2 (external)
# backup_s3_endpoint: "https://<account-id>.r2.cloudflarestorage.com"
# backup_s3_bucket: "cluster-backups"
#
# OPTION B: RustFS (internal - this guide)
# Uses internal RustFS S3 endpoint

# -- S3-compatible endpoint for backups
#    For RustFS internal: "http://rustfs.storage.svc.cluster.local:9000"
#    For R2 external: "https://<account-id>.r2.cloudflarestorage.com"
backup_s3_endpoint: "http://rustfs.storage.svc.cluster.local:9000"

# -- S3 bucket name for backups
#    Will be created by RustFS bucket setup job
backup_s3_bucket: "etcd-backups"

# -- S3 access key ID (RustFS admin credentials or dedicated user)
#    (Will be SOPS-encrypted after task configure)
backup_s3_access_key: "talos-backup"

# -- S3 secret access key
#    (Will be SOPS-encrypted after task configure)
backup_s3_secret_key: "ENC[AES256_GCM,...]"

# -- Age public key for backup encryption (use same as cluster Age key)
#    Get from: cat age.key | grep public
backup_age_public_key: "age1..."
```

### Step 2: Create RustFS Access Key (Console UI)

> ⚠️ **IMPORTANT**: RustFS does NOT support `mc admin` commands for IAM management.
> All user/policy operations must be performed via the **RustFS Console UI** (port 9001).
> See [RustFS IAM Documentation](https://docs.rustfs.com/administration/iam/access-token.html)

The built-in `readwrite` policy is too permissive (grants access to ALL buckets). Following the same pattern used for Loki, create a custom scoped policy for backup operations.

#### 2.1 Custom Backup Policy (Recommended)

Create this policy in RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `backup-storage`

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
        "arn:aws:s3:::etcd-backups"
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
        "arn:aws:s3:::etcd-backups/*"
      ]
    }
  ]
}
```

**Why This Policy:**

| Requirement | Permission | Purpose |
| ----------- | ---------- | ------- |
| List objects | `s3:ListBucket` | List backup files for retention cleanup |
| Read backups | `s3:GetObject` | Download backups for restore |
| Write backups | `s3:PutObject` | Upload new backup snapshots |
| Delete objects | `s3:DeleteObject` | Retention cleanup of old backups |
| Bucket location | `s3:GetBucketLocation` | AWS SDK compatibility |

**Why Not Built-in `readwrite`:**
- The `readwrite` policy grants access to **ALL** buckets
- The custom `backup-storage` policy scopes access to only `etcd-backups` bucket
- This protects other buckets (loki-chunks, tempo, etc.) from backup job access (principle of least privilege)

#### 2.2 Step-by-Step Console UI Instructions

1. **Access RustFS Console**
   ```
   https://rustfs.<your-domain>
   ```
   Login with `RUSTFS_ACCESS_KEY` / `RUSTFS_SECRET_KEY` from `cluster.yaml`

2. **Create Custom Policy**
   - Navigate to **Identity** → **Policies**
   - Click **Create Policy**
   - Name: `backup-storage`
   - Paste the JSON policy above
   - Click **Save**

3. **Create Backups Group** (Recommended)
   - Navigate to **Identity** → **Groups**
   - Click **Create Group**
   - Name: `backups`
   - Assign Policy: `backup-storage`
   - Click **Save**

4. **Create Talos Backup Service Account**
   - Navigate to **Identity** → **Users**
   - Click **Create User**
   - Access Key: `talos-backup` (or any meaningful name)
   - Assign to Group: `backups`
   - Click **Save**

5. **Generate Access Key**
   - Click on the newly created user (`talos-backup`)
   - Navigate to **Service Accounts** tab
   - Click **Create Access Key**
   - ⚠️ **Copy and save both keys immediately** - the secret key won't be shown again!

6. **Update cluster.yaml**
   ```yaml
   backup_s3_access_key: "<access-key-from-step-5>"
   backup_s3_secret_key: "<secret-key-from-step-5>"
   ```

7. **Apply Changes**
   ```bash
   task configure
   task reconcile
   ```

#### 2.3 IAM Architecture Summary

The backup IAM structure mirrors the Loki setup:

| Component | Loki (Monitoring) | Talos Backup |
| --------- | ----------------- | ------------ |
| **Policy** | `loki-storage` | `backup-storage` |
| **Scoped Buckets** | `loki-chunks`, `loki-ruler`, `loki-admin` | `etcd-backups` |
| **Group** | `monitoring` | `backups` |
| **User** | `loki` | `talos-backup` |
| **Permissions** | Full CRUD on loki-* | Full CRUD on etcd-backups |

This pattern ensures:
- **Principle of least privilege**: Each service only accesses its own buckets
- **Audit trail**: User/group structure enables access tracking
- **Scalability**: New backup consumers can be added to the `backups` group

### Step 3: Add etcd-backups Bucket to RustFS Setup

Update the RustFS bucket setup job to include the etcd-backups bucket:

**Edit:** `templates/config/kubernetes/apps/storage/rustfs/setup/job-setup.yaml.j2`

Add `etcd-backups` to the bucket list:

```yaml
#| Create buckets for cluster services #|
#| NOTE: Add new buckets here as needed #|
env:
  - name: BUCKETS
    value: "loki-chunks,loki-ruler,loki-admin,etcd-backups"
```

---

## Template Updates

### Update HelmRelease for Internal S3

**Edit:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/helmrelease.yaml.j2`

The template already supports internal endpoints. Verify the configuration:

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: talos-backup
spec:
  chartRef:
    kind: OCIRepository
    name: talos-backup
  interval: 12h
  values:
    priorityClassName: system-cluster-critical
    schedule: "0 */6 * * *"  # Every 6 hours
    env:
      - name: CLUSTER_NAME
        value: "#{ cluster_name | default('talos-cluster') }#"
      - name: S3_ENDPOINT
        value: "#{ backup_s3_endpoint }#"
      - name: S3_BUCKET
        value: "#{ backup_s3_bucket }#"
      - name: S3_PREFIX
        value: "#{ cluster_name | default('talos-cluster') }#/etcd-backups"
      # For internal RustFS, disable SSL verification
      #% if 'svc.cluster.local' in backup_s3_endpoint %#
      - name: S3_FORCE_PATH_STYLE
        value: "true"
      - name: S3_USE_SSL
        value: "false"
      #% endif %#
      - name: AGE_X25519_PUBLIC_KEY
        valueFrom:
          secretKeyRef:
            name: talos-backup-secrets
            key: age-public-key
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: talos-backup-secrets
            key: aws-access-key-id
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: talos-backup-secrets
            key: aws-secret-access-key
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
```

### Conditional Logic for RustFS

Add derived variable for internal backup endpoint detection:

**Edit:** `templates/scripts/plugin.py`

```python
# Talos Backup - detect internal vs external S3
backup_s3_endpoint = data.get("backup_s3_endpoint", "")
backup_s3_internal = "svc.cluster.local" in backup_s3_endpoint
variables["backup_s3_internal"] = backup_s3_internal
```

---

## Deployment

### Step 1: Create RustFS Access Key

```bash
# Port-forward to RustFS Console
kubectl -n storage port-forward svc/rustfs 9001:9001

# Open browser: http://localhost:9001
# Login with admin credentials
# Create access key for talos-backup
```

### Step 2: Update Configuration

```bash
# Edit cluster.yaml with RustFS endpoint and credentials
# Regenerate templates
task configure

# Verify generated secret
cat kubernetes/apps/kube-system/talos-backup/app/secret.sops.yaml
```

### Step 3: Deploy

```bash
git add -A
git commit -m "feat: configure Talos backup to use RustFS S3 backend"
git push
task reconcile
```

### Step 4: Verify Bucket Creation

```bash
# Check RustFS bucket setup job completed
kubectl -n storage get jobs | grep rustfs-bucket-setup

# Verify etcd-backups bucket exists (via mc or Console)
```

---

## Verification

### Test Manual Backup

```bash
# Trigger a manual backup job
kubectl -n kube-system create job --from=cronjob/talos-backup manual-backup-test

# Watch job progress
kubectl -n kube-system logs -l job-name=manual-backup-test -f

# Check job status
kubectl -n kube-system get jobs manual-backup-test
```

### Verify Backup in RustFS

```bash
# Using mc (MinIO Client) - works with RustFS
mc alias set rustfs http://rustfs.storage.svc.cluster.local:9000 $ACCESS_KEY $SECRET_KEY

# List backups
mc ls rustfs/etcd-backups/matherlynet/etcd-backups/

# Or via kubectl exec
kubectl -n storage exec -it deploy/rustfs -- ls /data/etcd-backups/
```

### Check CronJob Schedule

```bash
kubectl -n kube-system get cronjob talos-backup
kubectl -n kube-system describe cronjob talos-backup
```

---

## Backup Retention

### Manual Cleanup

RustFS doesn't have built-in lifecycle policies. Implement retention with a cleanup job:

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/cronjob-cleanup.yaml.j2`

```yaml
#% if talos_backup_enabled and backup_retention_days is defined %#
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: talos-backup-cleanup
spec:
  schedule: "0 4 * * *"  # Daily at 4 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: cleanup
              image: minio/mc:latest
              command:
                - /bin/sh
                - -c
                - |
                  mc alias set rustfs http://rustfs.storage.svc.cluster.local:9000 $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY
                  mc rm --recursive --older-than #{ backup_retention_days | default(30) }#d rustfs/#{ backup_s3_bucket }#/#{ cluster_name }#/
              env:
                - name: AWS_ACCESS_KEY_ID
                  valueFrom:
                    secretKeyRef:
                      name: talos-backup-secrets
                      key: aws-access-key-id
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: talos-backup-secrets
                      key: aws-secret-access-key
          restartPolicy: OnFailure
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
#% endif %#
```

---

## Disaster Recovery

### Restore Procedure

1. **List available backups:**
   ```bash
   mc ls rustfs/etcd-backups/matherlynet/etcd-backups/
   ```

2. **Download backup:**
   ```bash
   mc cp rustfs/etcd-backups/matherlynet/etcd-backups/latest.tar.age ./
   ```

3. **Decrypt backup:**
   ```bash
   age -d -i age.key latest.tar.age > latest.tar
   tar -xvf latest.tar
   ```

4. **Restore to Talos:**
   ```bash
   talosctl -n <control-plane-ip> etcd restore latest.snapshot
   ```

See [Talos etcd Disaster Recovery](https://www.talos.dev/v1.12/advanced/disaster-recovery/) for complete restore procedures.

---

## Monitoring

### Backup Job Alerts

Add Prometheus alerting rules for backup failures:

```yaml
groups:
  - name: talos-backup
    rules:
      - alert: TalosBackupFailed
        expr: kube_job_status_failed{job_name=~"talos-backup.*"} > 0
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "Talos etcd backup failed"
          description: "The talos-backup job has failed. Check logs for details."

      - alert: TalosBackupMissing
        expr: time() - kube_cronjob_status_last_successful_time{cronjob="talos-backup"} > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Talos backup not completed in 24h"
          description: "No successful talos-backup run in the last 24 hours."
```

### Dashboard Queries

```promql
# Last successful backup time
kube_cronjob_status_last_successful_time{cronjob="talos-backup"}

# Backup job duration
histogram_quantile(0.95, sum(rate(job_duration_seconds_bucket{job_name=~"talos-backup.*"}[1h])) by (le))
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| Backup job fails with S3 error | Wrong endpoint or credentials | Verify RustFS access key, check service DNS |
| Connection refused | RustFS not ready | Check RustFS pods, wait for startup |
| Access denied | Missing bucket or permissions | Create bucket via Console, verify access key and policy |
| Access denied (specific bucket) | Policy not scoped correctly | Verify `backup-storage` policy includes `etcd-backups` bucket |
| User has no access | User not in group | Verify `talos-backup` user is in `backups` group |
| Policy not attached | Group missing policy | Verify `backups` group has `backup-storage` policy attached |
| Age encryption fails | Missing or wrong public key | Verify `backup_age_public_key` matches age.key |
| Job stuck pending | Node selector mismatch | Check control-plane node labels |

### Debug Commands

```bash
# Check talos-backup pod logs
kubectl -n kube-system logs -l job-name=manual-backup-test

# Test S3 connectivity
kubectl -n kube-system run s3-test --rm -it --image=minio/mc -- \
  mc alias set rustfs http://rustfs.storage.svc.cluster.local:9000 $KEY $SECRET && mc ls rustfs/

# Verify Talos ServiceAccount
kubectl -n kube-system get serviceaccount talos-backup -o yaml

# Check secret values (base64 decode)
kubectl -n kube-system get secret talos-backup-secrets -o jsonpath='{.data.aws-access-key-id}' | base64 -d
```

---

## Comparison: RustFS vs R2

| Feature | RustFS (Internal) | Cloudflare R2 (External) |
| ------- | ----------------- | ------------------------ |
| **Latency** | Low (cluster-local) | Higher (internet) |
| **Egress Cost** | None | None (R2 is free egress) |
| **Availability** | Tied to cluster | Independent |
| **Setup** | Deploy RustFS | Create R2 bucket + API token |
| **DR Scenario** | Lost if cluster lost | Survives cluster loss |
| **Best For** | Dev/staging, cost-sensitive | Production, true DR |

**Recommendation:** Use RustFS for development and testing. For production disaster recovery, consider R2 or another external S3 provider as a secondary backup location.

---

## References

### External Documentation
- [talos-backup GitHub](https://github.com/siderolabs/talos-backup)
- [RustFS Documentation](https://docs.rustfs.com/)
- [RustFS IAM Access Tokens](https://docs.rustfs.com/administration/iam/access-token.html)
- [Talos etcd Disaster Recovery](https://www.talos.dev/v1.12/advanced/disaster-recovery/)

### Project Documentation
- [GitOps Components Implementation](./gitops-components-implementation.md#12-talos-backup)
- [RustFS Research](../research/rustfs-shared-storage-loki-simplescalable-jan-2026.md)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial implementation guide for RustFS backend |
| 2026-01-06 | Enhanced IAM configuration with custom `backup-storage` policy, `backups` group, and step-by-step Console UI instructions (mirrors Loki IAM pattern) |
