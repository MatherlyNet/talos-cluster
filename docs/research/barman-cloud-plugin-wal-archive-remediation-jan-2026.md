# Barman Cloud Plugin WAL Archive Remediation Guide

> **Created:** January 2026
> **Updated:** January 10, 2026
> **Status:** Research Complete - Multiple Issues Identified
> **Issue:** WAL archiving fails with `exit status 1` for CNPG clusters using RustFS S3 backend
> **Affected:** All CNPG clusters with barman-cloud plugin backup to RustFS
> **Root Causes:**
>
> 1. boto3 1.36+ S3 Data Integrity Protection incompatibility with RustFS (RESOLVED)
> 2. Stale archive data causing "Expected empty archive" errors (NEW FINDING)

---

## Executive Summary

The CloudNativePG Barman Cloud Plugin is failing to archive WAL files to RustFS S3 storage with the error:

```
rpc error: code = Unknown desc = unexpected failure invoking barman-cloud-wal-archive: exit status 1
```

This research identifies **two distinct issues**:

1. **boto3 1.36+ S3 Data Integrity Protection** - Incompatibility with S3-compatible storage providers (including RustFS) that haven't implemented the new checksum validation features. **RESOLVED** via environment variable workaround.

2. **Stale Archive Data** - When clusters are recreated (new timeline), old WAL files in the S3 bucket cause `barman-cloud-check-wal-archive` to fail with "Expected empty archive". This is the **current blocking issue** (January 10, 2026).

---

## Error Analysis

### Observed Error Pattern

```json
{
  "level": "error",
  "ts": "2026-01-09T21:19:22.86109032Z",
  "logger": "wal-archive",
  "msg": "Error while calling ArchiveWAL, failing",
  "pluginName": "barman-cloud.cloudnative-pg.io",
  "logging_pod": "obot-postgresql-1",
  "error": "rpc error: code = Unknown desc = unexpected failure invoking barman-cloud-wal-archive: exit status 1"
}
```

### Error Characteristics

| Characteristic | Value |
| ---------------- | ------- |
| Exit Status | 1 |
| Plugin | barman-cloud.cloudnative-pg.io |
| Operation | ArchiveWAL |
| Pod | obot-postgresql-1 |
| Backend | RustFS S3-compatible storage |

---

## Root Cause Analysis

### Primary Cause: boto3 1.36+ S3 Data Integrity Protection

Starting with AWS boto3 1.36 (released early 2025), the SDK implements new S3 Data Integrity Protection features that require:

1. **`x-amz-content-sha256` header validation** on PUT operations
2. **Checksum calculation** for request integrity
3. **Response checksum validation** from the S3 provider

**Problem:** S3-compatible storage providers (RustFS, older MinIO, Linode, DigitalOcean Spaces, etc.) that haven't updated their server-side implementations fail with errors like:

- `exit status 1` (generic failure)
- `exit status 2` (specific barman-cloud error)
- `x-amz-content-sha256 must be UNSIGNED-PAYLOAD, STREAMING-AWS4-HMAC-SHA256-PAYLOAD or a valid sha256 value`
- `MissingContentLength` when calling PutObject operation

### Current Implementation Gap

The current ObjectStore configuration for Obot lacks the required environment variables to work around this compatibility issue:

**Current (`kubernetes/apps/ai-system/obot/app/postgresql.yaml`):**

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: obot-objectstore
spec:
  configuration:
    destinationPath: "s3://obot-postgres-backups"
    endpointURL: "http://rustfs-svc.storage.svc.cluster.local:9000"
    s3Credentials:
      accessKeyId:
        name: obot-backup-credentials
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: obot-backup-credentials
        key: SECRET_ACCESS_KEY
    wal:
      compression: gzip
    retentionPolicy: "7d"
  instanceSidecarConfiguration:
    retentionPolicyIntervalSeconds: 1800
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

**Missing:** The `env` block with boto3 checksum workaround variables.

---

## Prerequisites: CRD Schema Update (CRITICAL)

> **⚠️ IMPORTANT:** Before updating ObjectStore configurations, the CRD schema in the plugin deployment template **MUST** be updated. The current CRD is missing the `env`, `logLevel`, and `additionalContainerArgs` fields in `instanceSidecarConfiguration`. Without this update, Kubernetes will reject the ObjectStore configurations with validation errors.

### File: `templates/config/kubernetes/apps/cnpg-system/barman-cloud-plugin/app/plugin-deployment.yaml.j2`

The `instanceSidecarConfiguration` schema (lines ~138-160) must be updated to include the missing fields:

**Current (incomplete):**

```yaml
instanceSidecarConfiguration:
  description: Configuration for sidecar containers
  type: object
  properties:
    retentionPolicyIntervalSeconds:
      type: integer
    resources:
      type: object
      # ... (resources only)
```

**Required (complete):**

```yaml
instanceSidecarConfiguration:
  description: Configuration for sidecar containers
  type: object
  properties:
    additionalContainerArgs:
      description: Command-line arguments appended to container defaults
      type: array
      items:
        type: string
    env:
      description: Environment variables passed to the sidecar
      type: array
      items:
        type: object
        properties:
          name:
            type: string
          value:
            type: string
          valueFrom:
            type: object
            x-kubernetes-preserve-unknown-fields: true
    logLevel:
      description: Log level for the sidecar
      type: string
      enum: [error, warning, info, debug, trace]
      default: info
    retentionPolicyIntervalSeconds:
      type: integer
      default: 1800
    resources:
      type: object
      properties:
        requests:
          type: object
          additionalProperties:
            anyOf:
              - type: integer
              - type: string
            x-kubernetes-int-or-string: true
        limits:
          type: object
          additionalProperties:
            anyOf:
              - type: integer
              - type: string
            x-kubernetes-int-or-string: true
```

### Order of Operations

1. **FIRST:** Update CRD schema in `plugin-deployment.yaml.j2`
2. **SECOND:** Update ObjectStore configurations in application templates
3. **THIRD:** Run `task configure` to regenerate all manifests
4. **FOURTH:** Commit, push, and reconcile

---

## Remediation Strategy

### Solution 1: Add boto3 Checksum Workaround (Recommended)

Add the following environment variables to the ObjectStore's `instanceSidecarConfiguration` to disable strict checksum validation:

```yaml
instanceSidecarConfiguration:
  env:
    - name: AWS_REQUEST_CHECKSUM_CALCULATION
      value: when_required
    - name: AWS_RESPONSE_CHECKSUM_VALIDATION
      value: when_required
  logLevel: debug  # Enable for troubleshooting, change to 'info' after fix confirmed
  retentionPolicyIntervalSeconds: 1800
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

### Solution 2: Alternative - Path Style Enforcement (If Required)

Some S3-compatible providers also require path-style addressing. Add this if virtual-host style fails:

```yaml
instanceSidecarConfiguration:
  additionalContainerArgs:
    - "--endpoint-url-style=path"
  env:
    - name: AWS_REQUEST_CHECKSUM_CALCULATION
      value: when_required
    - name: AWS_RESPONSE_CHECKSUM_VALIDATION
      value: when_required
```

---

## Template Changes Required

### File: `templates/config/kubernetes/apps/ai-system/obot/app/postgresql.yaml.j2`

Update the ObjectStore section (lines ~127-159) to include the boto3 workaround:

```yaml
#% if obot_backup_enabled | default(false) and cnpg_barman_plugin_enabled | default(false) %#
---
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: obot-objectstore
  namespace: ai-system
  labels:
    app.kubernetes.io/name: obot-objectstore
    app.kubernetes.io/part-of: obot
spec:
  configuration:
    destinationPath: "s3://obot-postgres-backups"
    endpointURL: "http://rustfs-svc.storage.svc.cluster.local:9000"
    s3Credentials:
      accessKeyId:
        name: obot-backup-credentials
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: obot-backup-credentials
        key: SECRET_ACCESS_KEY
    wal:
      compression: gzip
    retentionPolicy: "#{ obot_backup_retention | default('7d') }#"
  instanceSidecarConfiguration:
    #| boto3 1.36+ S3 Data Integrity Protection workaround for RustFS/S3-compatible storage #|
    #| REF: https://cloudnative-pg.io/docs/1.28/backup_recovery#object-stores #|
    #| REF: docs/research/barman-cloud-plugin-wal-archive-remediation-jan-2026.md #|
    env:
      - name: AWS_REQUEST_CHECKSUM_CALCULATION
        value: when_required
      - name: AWS_RESPONSE_CHECKSUM_VALIDATION
        value: when_required
    logLevel: info
    retentionPolicyIntervalSeconds: 1800
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
#% endif %#
```

### Affected Files (In Order of Implementation)

> **⚠️ CRITICAL:** Files must be updated in this order. The CRD must be updated FIRST or Kubernetes will reject the ObjectStore configurations.

| Priority | Component | Template File | Namespace | Change Type |
| -------- | --------- | ------------- | --------- | ----------- |
| **1** | **CRD Schema** | `templates/config/kubernetes/apps/cnpg-system/barman-cloud-plugin/app/plugin-deployment.yaml.j2` | cnpg-system | Add `env`, `logLevel`, `additionalContainerArgs` to schema |
| **2** | **Obot** | `templates/config/kubernetes/apps/ai-system/obot/app/postgresql.yaml.j2` | ai-system | Add env block to ObjectStore |
| **3** | **LiteLLM** | `templates/config/kubernetes/apps/ai-system/litellm/app/postgresql.yaml.j2` | ai-system | Add env block to ObjectStore |
| **4** | **Langfuse** | `templates/config/kubernetes/apps/ai-system/langfuse/app/postgresql.yaml.j2` | ai-system | Add env block to ObjectStore |
| **5** | **Keycloak** | `templates/config/kubernetes/apps/identity/keycloak/app/postgres-cnpg.yaml.j2` | identity | Add env block to ObjectStore |

---

## Verification Steps

### Step 0: Verify CRD Schema Update (CRITICAL - Do First)

```bash
# After applying changes, verify the CRD has the new fields
kubectl get crd objectstores.barmancloud.cnpg.io -o yaml | grep -A 50 instanceSidecarConfiguration

# Expected: Should show 'env', 'logLevel', and 'additionalContainerArgs' properties
# If these are missing, the CRD update did not apply correctly
```

**Expected output should include:**

```yaml
instanceSidecarConfiguration:
  properties:
    additionalContainerArgs:
      items:
        type: string
      type: array
    env:
      items:
        properties:
          name:
            type: string
          value:
            type: string
        type: object
      type: array
    logLevel:
      enum:
      - error
      - warning
      - info
      - debug
      - trace
      type: string
```

### Step 1: Apply Changes

```bash
# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "fix: add boto3 checksum workaround for barman-cloud WAL archiving with RustFS"
git push

# Force reconcile
task reconcile
```

### Step 2: Verify ObjectStore Configuration

```bash
# Check ObjectStore has env vars
kubectl get objectstore obot-objectstore -n ai-system -o yaml | grep -A 10 instanceSidecarConfiguration
```

Expected output should include:

```yaml
instanceSidecarConfiguration:
  env:
  - name: AWS_REQUEST_CHECKSUM_CALCULATION
    value: when_required
  - name: AWS_RESPONSE_CHECKSUM_VALIDATION
    value: when_required
```

### Step 3: Restart PostgreSQL Pod

```bash
# Delete the pod to trigger sidecar recreation with new env vars
kubectl delete pod obot-postgresql-1 -n ai-system

# Watch for new pod
kubectl get pods -n ai-system -l cnpg.io/cluster=obot-postgresql -w
```

### Step 4: Monitor WAL Archiving

```bash
# Watch sidecar logs for WAL operations
kubectl logs -n ai-system obot-postgresql-1 -c plugin-barman-cloud -f --tail=100

# Check archive status
kubectl exec -n ai-system obot-postgresql-1 -- \
  psql -U postgres -c "SELECT archived_count, failed_count, last_failed_time FROM pg_stat_archiver;"

# Trigger a WAL switch to test archiving
kubectl exec -n ai-system obot-postgresql-1 -- \
  psql -U postgres -c "SELECT pg_switch_wal();"
```

### Step 5: Verify Sidecar Container Has Env Vars

```bash
# Verify the sidecar container spec includes the env vars
kubectl get pod obot-postgresql-1 -n ai-system -o jsonpath='{.spec.containers[?(@.name=="plugin-barman-cloud")].env}' | jq .

# Expected output:
# [
#   {"name": "AWS_REQUEST_CHECKSUM_CALCULATION", "value": "when_required"},
#   {"name": "AWS_RESPONSE_CHECKSUM_VALIDATION", "value": "when_required"}
# ]
```

### Step 6: Verify Cluster Status

```bash
# Check cluster conditions
kubectl get cluster obot-postgresql -n ai-system -o jsonpath='{.status.conditions}' | jq .

# Check for ContinuousArchiving status
kubectl get cluster obot-postgresql -n ai-system -o yaml | grep -A 5 ContinuousArchiving
```

**Healthy output:**

```yaml
- type: ContinuousArchiving
  status: "True"
  reason: ContinuousArchivingSuccess
```

---

## Debugging Commands

### If Issues Persist

```bash
# Enable debug logging temporarily
kubectl patch objectstore obot-objectstore -n ai-system --type merge -p '{"spec":{"instanceSidecarConfiguration":{"logLevel":"debug"}}}'

# Check detailed sidecar logs
kubectl logs -n ai-system obot-postgresql-1 -c plugin-barman-cloud --tail=200 | grep -i -E "error|warn|wal"

# Check plugin operator logs
kubectl logs -n cnpg-system deployment/barman-cloud --tail=100

# Test S3 connectivity from pod
kubectl exec -n ai-system obot-postgresql-1 -- \
  curl -v http://rustfs-svc.storage.svc.cluster.local:9000/obot-postgres-backups/

# Verify secret exists and has correct keys
kubectl get secret obot-backup-credentials -n ai-system -o jsonpath='{.data}' | jq 'keys'

# Check network policies aren't blocking
kubectl get ciliumnetworkpolicy -n ai-system
```

### Common Issues Checklist

| Issue | Check | Fix |
| ------- | ------- | ----- |
| Secret not found | `kubectl get secret obot-backup-credentials -n ai-system` | Create secret in cluster.yaml |
| Wrong S3 endpoint | Check `endpointURL` in ObjectStore | Use `http://rustfs-svc.storage.svc.cluster.local:9000` |
| Bucket doesn't exist | Check RustFS Console | Create `obot-postgres-backups` bucket |
| IAM permissions | Check RustFS user/policy | Ensure user has s3:PutObject, s3:GetObject permissions |
| Network blocked | `hubble observe -n ai-system --verdict DROPPED` | Add RustFS to network policy egress |
| DNS resolution | `kubectl exec pod -- nslookup rustfs-svc.storage.svc.cluster.local` | Check CoreDNS is healthy |

---

## Known Issues and Workarounds

### Issue 1: WAL Path Duplication Bug (Fixed in v0.10.0+)

**Symptoms:** Path duplication in WAL name like `/var/lib/postgresql/data/pgdata/var/lib/postgresql/data/pgdata/pg_wal/...`

**Status:** Fixed in plugin-barman-cloud v0.10.0 (PR #6964)

**Check version:**

```bash
kubectl get deployment barman-cloud -n cnpg-system -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Should show: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.10.0` or newer

### Issue 2: Former Primary WAL Archiving

**Symptoms:** WAL archiving fails specifically on nodes that were previously primary

**Status:** Fixed in v0.10.0+ (same PR)

### Issue 3: CNPG Operator Upgrade Hangs

**Symptoms:** After upgrading CNPG operator, clusters with >1 instance get stuck

**Workaround:**

```bash
# If upgrade hangs, manually restart remaining instances
kubectl rollout restart statefulset obot-postgresql -n ai-system
```

---

## RustFS-Specific Configuration

### S3 Compatibility Considerations

RustFS (like MinIO) uses **path-style** addressing by default, not virtual-host style.

**Current endpoint:** `http://rustfs-svc.storage.svc.cluster.local:9000` (correct for path-style)

**Bucket format:** `s3://obot-postgres-backups` (bucket name in path, not subdomain)

### RustFS IAM Setup (Console UI Required)

RustFS does NOT support `mc admin` commands. All IAM operations must be done via Console UI:

1. **Create Policy** (`database-storage`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::obot-postgres-backups"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::obot-postgres-backups/*"]
    }
  ]
}
```

1. **Create Group** (`databases`) with policy attached
2. **Create User** in group
3. **Generate Access Key** for user

---

## Configuration Variables Reference

### cluster.yaml Variables

```yaml
# Obot backup configuration
obot_backup_enabled: true
obot_s3_access_key: "<from-rustfs-console>"  # SOPS encrypted
obot_s3_secret_key: "<from-rustfs-console>"  # SOPS encrypted
obot_backup_retention: "7d"

# Required dependencies
rustfs_enabled: true
cnpg_enabled: true
cnpg_barman_plugin_enabled: true
```

### Derived Variables (plugin.py)

```python
# obot_backup_enabled - true when:
# - obot_enabled: true
# - rustfs_enabled: true
# - cnpg_barman_plugin_enabled: true
# - obot_s3_access_key defined
# - obot_s3_secret_key defined
```

---

## Plugin Version Compatibility Matrix

| Plugin Version | CNPG Version | boto3 Workaround Needed | Notes |
| ---------------- | ------------ | ------------------------- | ------- |
| v0.10.0 | 1.28+ | Yes (for RustFS) | Current version, includes WAL path fix |
| v0.9.0 | 1.27+ | Yes | barman-cloud 3.16.2 |
| v0.8.0 | 1.26+ | Yes | Breaking: resource naming change |
| v0.7.0 | 1.25+ | Yes | Added logLevel setting |

---

## References

### Official Documentation

- [Barman Cloud Plugin Troubleshooting](https://cloudnative-pg.io/docs/1.28/backup_recovery#troubleshooting)
- [Barman Cloud Plugin Object Stores](https://cloudnative-pg.io/docs/1.28/backup_recovery#object-stores)
- [CloudNativePG Documentation](https://cloudnative-pg.io/docs/1.28/)
- [Barman Cloud boto3 Compatibility](https://docs.pgbarman.org/release/3.16.1/user_guide/barman_cloud.html)

### GitHub Issues

- [Exit status 2 WAL archive error](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/535)
- [WAL archiving not working on former primary](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/164)
- [boto3 version hint](https://github.com/cloudnative-pg/cloudnative-pg/issues/8427)
- [XAmzContentSHA256Mismatch debugging](https://www.beyondwatts.com/posts/debugging-barman-xamzcontentsha256mismatch-error-after-upgrading-to-postgresql175/)

### Project Documentation

- [CNPG Implementation Guide](../guides/completed/cnpg-implementation.md)
- [RustFS Integration](./rustfs-shared-storage-loki-simplescalable-jan-2026.md)
- [Obot Integration](./obot-mcp-gateway-integration-jan-2026.md)

---

## Issue 2: Stale Archive Data (Current Blocking Issue)

### Symptoms

After resolving the boto3 checksum issue, WAL archiving continues to fail with:

```
ERROR: WAL archive check failed for server obot-postgresql: Expected empty archive
```

### Root Cause

This occurs when:

1. A CNPG cluster is recreated (e.g., pod deleted and recreated, PVC data lost)
2. The new cluster starts with timeline 1 (fresh initdb)
3. Old WAL files from the previous cluster instance still exist in S3
4. `barman-cloud-check-wal-archive` runs before every archive operation
5. The check finds existing data and expects an empty archive for a new cluster

### Evidence (January 10, 2026)

```bash
# S3 bucket contains old WAL files from January 9th
$ aws s3 ls s3://obot-postgres-backups/ --recursive
2026-01-09 21:08:59    2712544 obot-postgresql/wals/0000000100000000/000000010000000000000001.gz
2026-01-09 21:09:04    1176261 obot-postgresql/wals/0000000100000000/000000010000000000000002.gz
...

# But current pod was recreated later
$ kubectl get pod obot-postgresql-1 -o jsonpath='{.status.startTime}'
2026-01-09T23:51:38Z
```

### Remediation Options

#### Option 1: Clean S3 Bucket (Development/Fresh Start)

For development environments or when starting fresh:

```bash
# Delete all objects in the backup bucket
ACCESS_KEY=$(kubectl get secret obot-backup-credentials -n ai-system -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 -d)
SECRET_KEY=$(kubectl get secret obot-backup-credentials -n ai-system -o jsonpath='{.data.SECRET_ACCESS_KEY}' | base64 -d)

kubectl run --rm -i s3-cleanup --image=amazon/aws-cli --restart=Never --namespace=ai-system \
  --env="AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
  --env="AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
  -- s3 rm s3://obot-postgres-backups/ --recursive \
  --endpoint-url=http://rustfs-svc.storage.svc.cluster.local:9000

# Restart the PostgreSQL pod to trigger fresh archiving
kubectl delete pod obot-postgresql-1 -n ai-system
```

#### Option 2: Bootstrap from Existing Backup (Recovery Scenario)

If you want to preserve the existing backup data and restore from it, use the CNPG recovery bootstrap mode:

```yaml
spec:
  bootstrap:
    recovery:
      source: obot-postgresql-backup
  externalClusters:
    - name: obot-postgresql-backup
      barmanObjectStore:
        destinationPath: "s3://obot-postgres-backups"
        endpointURL: "http://rustfs-svc.storage.svc.cluster.local:9000"
        s3Credentials:
          accessKeyId:
            name: obot-backup-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: obot-backup-credentials
            key: SECRET_ACCESS_KEY
```

#### Option 3: Use Separate Server Name (Coexistence)

Configure the cluster to use a different server name prefix in the ObjectStore:

```yaml
# In the Cluster spec
spec:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: obot-objectstore
        serverName: obot-postgresql-v2  # Different name from previous instance
```

This allows the new cluster to archive to a separate path without conflicting with old data.

### Prevention

To prevent this issue in the future:

1. **Before deleting a cluster**, clean up or archive its S3 backup data
2. **Use unique serverName** for each cluster incarnation if data needs to be preserved
3. **Implement backup lifecycle management** to automatically clean old backups
4. **Use recovery bootstrap** when recreating a cluster that has existing backups

---

## Plugin Architecture Deep Dive

### Component Overview

The barman-cloud plugin consists of two container images:

| Image | Purpose | Location |
| ----- | ------- | -------- |
| `ghcr.io/cloudnative-pg/plugin-barman-cloud` | Plugin operator - handles gRPC communication with CNPG operator | Deployment in cnpg-system |
| `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar` | Sidecar - performs actual WAL archiving/backups | Injected as init container in PostgreSQL pods |

### Communication Flow

```
┌─────────────────────┐     gRPC/mTLS     ┌─────────────────────┐
│   CNPG Operator     │◄───────────────────►│  barman-cloud      │
│   (cnpg-system)     │                    │  Plugin Operator    │
└─────────────────────┘                    └─────────────────────┘
          │                                         │
          │ Cluster CRD                             │ ObjectStore CRD
          ▼                                         ▼
┌─────────────────────┐                    ┌─────────────────────┐
│  PostgreSQL Pod     │                    │  ObjectStore        │
│  ┌───────────────┐  │                    │  Configuration      │
│  │ Init Container│  │                    │  (S3 credentials,   │
│  │ (sidecar img) │  │                    │   env vars, etc.)   │
│  └───────────────┘  │                    └─────────────────────┘
│  ┌───────────────┐  │
│  │   postgres    │──┼──────► WAL archiver process
│  └───────────────┘  │              │
└─────────────────────┘              │
                                     ▼
                            ┌─────────────────────┐
                            │  RustFS S3 Storage  │
                            │  (WAL files +       │
                            │   base backups)     │
                            └─────────────────────┘
```

### Environment Variable Propagation

The `instanceSidecarConfiguration.env` variables in ObjectStore are passed to the **init container** (`plugin-barman-cloud-sidecar`), which:

1. Reads the ObjectStore configuration
2. Sets up environment variables for barman-cloud commands
3. Creates configuration files in `/controller/` directory
4. The main postgres container's archiver process invokes barman-cloud commands with these environment variables

### Key Discovery: Init Container vs Sidecar

Despite the name "sidecar", the plugin uses an **init container** pattern:

- `plugin-barman-cloud` runs as init container, not a continuously running sidecar
- WAL archiving is done by the main postgres container calling barman-cloud binaries
- The init container prepares the environment and configuration
- Environment variables must be available to processes spawned by the postgres container

---

## Changelog

| Date | Change |
| ------ | -------- |
| 2026-01-09 | Initial research document created |
| 2026-01-09 | Identified boto3 1.36+ checksum compatibility as root cause |
| 2026-01-09 | Added remediation steps and template changes |
| 2026-01-09 | **CRITICAL FIX:** Added prerequisite CRD schema update section - CRD is missing `env`, `logLevel`, `additionalContainerArgs` fields |
| 2026-01-09 | Updated affected files table with priority order and CRD as first entry |
| 2026-01-09 | Added Step 0 for CRD verification and Step 5 for sidecar env verification |
| 2026-01-09 | Validation completed - document ready for implementation |
| 2026-01-10 | **NEW FINDING:** Identified "Expected empty archive" error as second blocking issue |
| 2026-01-10 | Added comprehensive documentation research findings |
| 2026-01-10 | Added Plugin Architecture Deep Dive section |
| 2026-01-10 | Added Issue 2: Stale Archive Data remediation options |
| 2026-01-10 | boto3 workaround confirmed working - env vars present in init container |
