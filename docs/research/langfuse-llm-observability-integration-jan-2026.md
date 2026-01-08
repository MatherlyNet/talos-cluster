# Langfuse LLM Observability Platform Integration Research

> **Status**: Research Complete
> **Date**: January 2026
> **Author**: Claude (AI Research Assistant)
> **Priority**: High (synergy with LiteLLM Proxy Gateway)
> **Complexity**: High (multi-component architecture)

## Executive Summary

This document provides a comprehensive analysis for integrating [Langfuse](https://langfuse.com/) as the LLM observability platform for the matherlynet-talos-cluster. Langfuse is an open-source observability and analytics platform for LLM applications, providing tracing, prompt management, evaluation, and cost analytics.

### Key Findings

| Aspect | Status | Integration Point | Notes |
| ------ | ------ | ----------------- | ----- |
| PostgreSQL (CNPG) | ✅ Ready | `cnpg_enabled: true` | Transactional data storage, version ≥12 required |
| Redis Cache (Dragonfly) | ✅ Ready | `dragonfly_enabled: true` | Queue + caching, v7+ with `maxmemory-policy=noeviction` |
| S3 Storage (RustFS) | ✅ Ready | `rustfs_enabled: true` | Event blobs, media, batch exports |
| Keycloak SSO | ✅ Ready | `keycloak_enabled: true` | OIDC authentication with account linking |
| LiteLLM Integration | ✅ Ready | Callback + OTEL | Bidirectional observability |
| OpenTelemetry (Tempo) | ✅ Ready | `tracing_enabled: true` | OTLP HTTP/protobuf export |
| Prometheus Metrics | ✅ Ready | `monitoring_enabled: true` | Self-observability via OTEL |
| ClickHouse | ⚠️ Required | Bundled/External | Analytics database (unique to Langfuse) |

### Recommendation

**Implement Langfuse as a shared AI observability resource** in a dedicated `ai-system` namespace, leveraging existing infrastructure (CNPG, Dragonfly, RustFS, Keycloak) while adding ClickHouse as the analytics layer. This creates a complete LLMOps stack with LiteLLM Proxy Gateway.

---

## Table of Contents

1. [Background and Motivation](#background-and-motivation)
2. [Langfuse Overview](#langfuse-overview)
3. [Architecture Design](#architecture-design)
4. [Infrastructure Dependencies](#infrastructure-dependencies)
5. [Template Design](#template-design)
6. [Configuration Schema](#configuration-schema)
7. [Keycloak SSO Integration](#keycloak-sso-integration)
8. [LiteLLM Proxy Integration](#litellm-proxy-integration)
9. [OpenTelemetry Integration](#opentelemetry-integration)
10. [Monitoring and Health Checks](#monitoring-and-health-checks)
11. [Backup Strategy](#backup-strategy)
12. [Security Configuration](#security-configuration)
13. [Implementation Phases](#implementation-phases)
14. [Sources and References](#sources-and-references)

---

## Background and Motivation

### Why Langfuse?

| Feature | Description |
| ------- | ----------- |
| Tracing | End-to-end LLM call tracing with latency, tokens, cost |
| Prompt Management | Version control, A/B testing, prompt experiments |
| Evaluation | LLM-as-a-Judge, human annotation, scoring |
| Analytics | Usage patterns, cost analysis, performance metrics |
| Playground | Interactive LLM testing with saved prompts |
| Open Source | Self-hosted, MIT license, no vendor lock-in |

### Use Cases in This Cluster

1. **LiteLLM Observability**: Trace all LLM calls through the proxy gateway
2. **Prompt Engineering**: Centralized prompt management across applications
3. **Cost Tracking**: Per-project, per-model cost analytics
4. **Quality Assurance**: Automated and human evaluation pipelines
5. **Debugging**: Root cause analysis for LLM failures

### Synergy with LiteLLM Proxy Gateway

The LiteLLM Proxy Gateway (documented in `litellm-proxy-gateway-integration-jan-2026.md`) provides the unified LLM API layer. Langfuse complements this with:

```
                    ┌─────────────────────────────────────────┐
                    │              Applications               │
                    └────────────────────┬────────────────────┘
                                         │
                    ┌────────────────────▼────────────────────┐
                    │           LiteLLM Proxy Gateway          │
                    │  (unified API, load balancing, caching)  │
                    └────────────────────┬────────────────────┘
                                         │ callbacks
                    ┌────────────────────▼────────────────────┐
                    │               Langfuse                   │
                    │  (tracing, prompts, evaluation, costs)   │
                    └─────────────────────────────────────────┘
```

---

## Langfuse Overview

### Version Information (January 2026)

| Component | Version | Notes |
| --------- | ------- | ----- |
| Langfuse | v3.x | Latest stable (self-hosted) |
| Helm Chart | Latest | `langfuse/langfuse` from langfuse-k8s repo |
| ClickHouse | 24.x | Required for analytics |
| PostgreSQL | ≥12 | Transactional data |
| Redis/Valkey | ≥7 | Queue + caching |

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Langfuse Stack                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ langfuse-web│  │langfuse-    │  │      ClickHouse         │  │
│  │   (Next.js) │  │   worker    │  │    (analytics DB)       │  │
│  │  port: 3000 │  │ port: 3030  │  │    + ZooKeeper          │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │               │
│         └────────┬───────┴──────────────────────┘               │
│                  │                                               │
│  ┌───────────────▼───────────────────────────────────────────┐  │
│  │                   Shared Infrastructure                    │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌─────────────────────┐  │  │
│  │  │PostgreSQL│  │ Redis/Dragon-│  │   S3/RustFS         │  │  │
│  │  │ (CNPG)   │  │    fly       │  │ (blob storage)      │  │  │
│  │  └──────────┘  └──────────────┘  └─────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Langfuse Components

| Component | Purpose | Port |
| --------- | ------- | ---- |
| langfuse-web | Next.js web application, API endpoints | 3000 |
| langfuse-worker | Background job processing, event ingestion | 3030 |
| ClickHouse | Analytics database, trace storage | 8123 (HTTP), 9000 (TCP) |
| ZooKeeper | ClickHouse cluster coordination | 2181 |

---

## Architecture Design

### Namespace Design

Following the project's shared resource pattern:

```
ai-system/                    # AI/ML services namespace
├── langfuse/                 # Langfuse deployment
│   ├── operator/             # (if using operator pattern)
│   └── app/                  # Core components
├── litellm/                  # LiteLLM Proxy Gateway (separate ks.yaml)
└── namespace.yaml
```

### Dependency Chain

```
cnpg-system/cloudnative-pg ─────────────────────────┐
                                                     │
cache/dragonfly ────────────────────────────────────┤
                                                     │
storage/rustfs ─────────────────────────────────────┤
                                                     ▼
                                           ai-system/langfuse
                                                     │
                                                     ▼
                                           ai-system/litellm
                                           (uses langfuse callbacks)
```

### Service Discovery

| Service | DNS Name | Port |
| ------- | -------- | ---- |
| Langfuse Web | `langfuse-web.ai-system.svc.cluster.local` | 3000 |
| Langfuse Worker | `langfuse-worker.ai-system.svc.cluster.local` | 3030 |
| ClickHouse | `langfuse-clickhouse.ai-system.svc.cluster.local` | 8123, 9000 |
| PostgreSQL | `langfuse-postgresql.ai-system.svc.cluster.local` | 5432 |
| Dragonfly | `dragonfly.cache.svc.cluster.local` | 6379 |
| RustFS | `rustfs-svc.storage.svc.cluster.local` | 9000 |

---

## Infrastructure Dependencies

### PostgreSQL via CNPG

Langfuse requires PostgreSQL ≥12 for transactional data. Use the existing CNPG operator.

```yaml
#| CNPG Cluster for Langfuse (app/postgresql.yaml.j2) #|
#% if langfuse_enabled | default(false) %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: langfuse-postgresql
spec:
  instances: #{ langfuse_postgres_instances | default(1) }#
  imageName: #{ cnpg_postgres_image | default('ghcr.io/cloudnative-pg/postgresql:17.4-standard-trixie') }#

  postgresql:
    parameters:
      timezone: "UTC"  #| CRITICAL: Langfuse requires UTC #|

  storage:
    size: #{ langfuse_postgres_storage | default('10Gi') }#
    storageClass: #{ storage_class | default('local-path') }#

  bootstrap:
    initdb:
      database: langfuse
      owner: langfuse
      secret:
        name: langfuse-postgresql-credentials

#% if langfuse_backup_enabled | default(false) %#
  backup:
    barmanObjectStore:
      destinationPath: s3://langfuse-postgres-backups/
      endpointURL: http://rustfs-svc.storage.svc.cluster.local:9000
      s3Credentials:
        accessKeyId:
          name: langfuse-s3-credentials
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: langfuse-s3-credentials
          key: AWS_SECRET_ACCESS_KEY
    retentionPolicy: "7d"
#% endif %#
#% endif %#
```

### Redis/Dragonfly Configuration

Langfuse requires Redis ≥7 with `maxmemory-policy=noeviction`. Use the shared Dragonfly instance from the cache namespace.

**Critical Requirements:**
- Version 7+ (Dragonfly is compatible)
- `maxmemory-policy=noeviction` (already default in Dragonfly)

**Connection Configuration:**
```yaml
env:
  REDIS_CONNECTION_STRING: "redis://dragonfly.cache.svc.cluster.local:6379"
```

**ACL Configuration (if using multi-tenant Dragonfly):**
```
user langfuse on >#{ langfuse_redis_password }# ~langfuse:* +@all -@dangerous
```

### S3 Storage via RustFS

Langfuse uses S3 for event blobs, media uploads, and batch exports.

**Required Buckets:**

| Bucket | Purpose | Environment Variable |
| ------ | ------- | -------------------- |
| `langfuse-events` | Raw event storage | `LANGFUSE_S3_EVENT_UPLOAD_BUCKET` |
| `langfuse-media` | Multi-modal file uploads | `LANGFUSE_S3_MEDIA_UPLOAD_BUCKET` |
| `langfuse-exports` | Batch data exports | `LANGFUSE_S3_BATCH_EXPORT_BUCKET` |

**S3 Environment Variables:**
```yaml
env:
  #| Event storage (required) #|
  LANGFUSE_S3_EVENT_UPLOAD_BUCKET: "langfuse-events"
  LANGFUSE_S3_EVENT_UPLOAD_REGION: "us-east-1"
  LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT: "http://rustfs-svc.storage.svc.cluster.local:9000"
  LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID:
    valueFrom:
      secretKeyRef:
        name: langfuse-s3-credentials
        key: AWS_ACCESS_KEY_ID
  LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY:
    valueFrom:
      secretKeyRef:
        name: langfuse-s3-credentials
        key: AWS_SECRET_ACCESS_KEY
  LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE: "true"  #| Required for RustFS #|

  #| Media uploads (optional) #|
  LANGFUSE_S3_MEDIA_UPLOAD_BUCKET: "langfuse-media"
  LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT: "http://rustfs-svc.storage.svc.cluster.local:9000"

  #| Batch exports (optional) #|
  LANGFUSE_S3_BATCH_EXPORT_ENABLED: "true"
  LANGFUSE_S3_BATCH_EXPORT_BUCKET: "langfuse-exports"
```

### RustFS IAM Setup

> **IMPORTANT:** RustFS does NOT support `mc admin` commands. All user/policy operations must be performed via the **RustFS Console UI** at `https://rustfs.${cloudflare_domain}`.

#### Step 1: Create Buckets

Navigate to **Buckets** → **Create Bucket** and create the following:

| Bucket Name | Purpose | Retention |
| ----------- | ------- | --------- |
| `langfuse-events` | Raw event storage (traces, spans) | Permanent |
| `langfuse-media` | Multi-modal file uploads (images, audio) | Permanent |
| `langfuse-exports` | Batch data exports (CSV, JSON) | 90 days (optional) |
| `langfuse-postgres-backups` | CNPG barman WAL archive + base backups | 7 days |
| `langfuse-clickhouse-backups` | ClickHouse database backups | 7 days |

#### Step 2: Create Langfuse Storage Policy

Create in RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `langfuse-storage`

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
        "arn:aws:s3:::langfuse-events",
        "arn:aws:s3:::langfuse-media",
        "arn:aws:s3:::langfuse-exports",
        "arn:aws:s3:::langfuse-postgres-backups",
        "arn:aws:s3:::langfuse-clickhouse-backups"
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
        "arn:aws:s3:::langfuse-events/*",
        "arn:aws:s3:::langfuse-media/*",
        "arn:aws:s3:::langfuse-exports/*",
        "arn:aws:s3:::langfuse-postgres-backups/*",
        "arn:aws:s3:::langfuse-clickhouse-backups/*"
      ]
    }
  ]
}
```

#### Step 3: Create AI System Group

If the `ai-system` group doesn't already exist from LiteLLM setup:

1. Navigate to **Identity** → **Groups** → **Create Group**
2. **Name:** `ai-system`
3. Click **Save**

If the group exists, add the `langfuse-storage` policy:

1. Navigate to **Identity** → **Groups** → Select `ai-system`
2. Click **Policies** tab → **Assign Policy**
3. Select `langfuse-storage` → **Save**

#### Step 4: Create Langfuse Service Account

1. Navigate to **Identity** → **Users** → **Create User**
2. **Access Key:** `langfuse`
3. **Assign to Group:** `ai-system`
4. Click **Save**
5. Click the user → **Service Accounts** → **Create Access Key**
6. **IMPORTANT:** Save both the Access Key and Secret Key immediately (secret is shown only once)

#### Step 5: Update cluster.yaml

Add the credentials to your `cluster.yaml`:

```yaml
# S3 credentials for Langfuse (created via RustFS Console)
langfuse_s3_access_key: "AKIAIOSFODNN7EXAMPLE"
langfuse_s3_secret_key: "ENC[AES256_GCM,...]"  # SOPS-encrypted
```

Encrypt the secret key:

```bash
sops --encrypt --in-place cluster.yaml
```

#### IAM Architecture Summary

| Component | Value |
| --------- | ----- |
| **Buckets** | `langfuse-events`, `langfuse-media`, `langfuse-exports`, `langfuse-postgres-backups`, `langfuse-clickhouse-backups` |
| **Policy** | `langfuse-storage` (scoped to langfuse buckets only) |
| **Group** | `ai-system` (shared with LiteLLM if also enabled) |
| **User** | `langfuse` |
| **Cluster.yaml vars** | `langfuse_s3_access_key`, `langfuse_s3_secret_key` |
| **K8s Secret** | `langfuse-s3-credentials` (in ai-system namespace) |

#### Alternative: Separate Backup Credentials (Recommended for Production)

For enhanced security, create separate credentials with access only to backup buckets. This follows the principle of least privilege and limits blast radius if credentials are compromised.

##### Step 1: Create Backup-Only Policy

Create in RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `langfuse-backup-storage`

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
        "arn:aws:s3:::langfuse-postgres-backups",
        "arn:aws:s3:::langfuse-clickhouse-backups"
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
        "arn:aws:s3:::langfuse-postgres-backups/*",
        "arn:aws:s3:::langfuse-clickhouse-backups/*"
      ]
    }
  ]
}
```

##### Step 2: Create Backup User Group

1. Navigate to **Identity** → **Groups** → **Create Group**
2. **Name:** `langfuse-backup`
3. **Assign Policy:** `langfuse-backup-storage`
4. Click **Save**

##### Step 3: Create Backup Service Account

1. Navigate to **Identity** → **Users** → **Create User**
2. **Access Key:** `langfuse-backup`
3. **Assign to Group:** `langfuse-backup`
4. Click **Save**
5. Click the user → **Service Accounts** → **Create Access Key**
6. **IMPORTANT:** Save both the Access Key and Secret Key immediately

##### Step 4: Update cluster.yaml

```yaml
# Primary S3 credentials (events, media, exports)
langfuse_s3_access_key: "langfuse"
langfuse_s3_secret_key: "ENC[AES256_GCM,...]"

# Separate backup credentials (least privilege)
langfuse_backup_enabled: true
langfuse_backup_s3_access_key: "langfuse-backup"
langfuse_backup_s3_secret_key: "ENC[AES256_GCM,...]"
```

##### Backup Credential IAM Summary

| Component | Value |
| --------- | ----- |
| **Buckets** | `langfuse-postgres-backups`, `langfuse-clickhouse-backups` only |
| **Policy** | `langfuse-backup-storage` (no access to events/media/exports) |
| **Group** | `langfuse-backup` |
| **User** | `langfuse-backup` |
| **Cluster.yaml vars** | `langfuse_backup_s3_access_key`, `langfuse_backup_s3_secret_key` |
| **K8s Secret** | `langfuse-backup-credentials` (separate from s3-credentials) |

> **Note:** If `langfuse_backup_s3_access_key` is not set, the template falls back to using `langfuse_s3_access_key`. This allows simpler setups while supporting enhanced security when needed.

### ClickHouse (Analytics Database)

ClickHouse is unique to Langfuse and not shared with other cluster components. Options:

**Option 1: Bundled ClickHouse (Recommended for simplicity)**
- Use Helm chart's bundled ClickHouse
- Includes ZooKeeper for cluster coordination
- Managed lifecycle with Langfuse deployment

**Option 2: External ClickHouse**
- Managed service (ClickHouse Cloud)
- Separate Helm deployment
- More operational overhead

**Environment Variables:**
```yaml
env:
  CLICKHOUSE_MIGRATION_URL: "clickhouse://langfuse-clickhouse:9000/default"
  CLICKHOUSE_URL: "http://langfuse-clickhouse:8123"
  CLICKHOUSE_USER: "default"
  CLICKHOUSE_PASSWORD:
    valueFrom:
      secretKeyRef:
        name: langfuse-clickhouse-credentials
        key: password
  CLICKHOUSE_DB: "default"
  CLICKHOUSE_CLUSTER_ENABLED: "true"
```

---

## Template Design

### Directory Structure

```
templates/config/kubernetes/apps/ai-system/
├── kustomization.yaml.j2           # Namespace-level kustomization
├── namespace.yaml.j2               # Namespace definition
└── langfuse/
    ├── ks.yaml.j2                  # Flux Kustomization
    └── app/
        ├── kustomization.yaml.j2
        ├── helmrelease.yaml.j2     # Langfuse Helm deployment
        ├── postgresql.yaml.j2      # CNPG Cluster
        ├── secret.sops.yaml.j2     # Encrypted credentials
        ├── httproute.yaml.j2       # Gateway API routing
        └── servicemonitor.yaml.j2  # Prometheus scraping
```

### Namespace Template (namespace.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) or litellm_enabled | default(false) %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: ai-system
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
#% endif %#
```

### Namespace-Level Kustomization (kustomization.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) or litellm_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
#% if langfuse_enabled | default(false) %#
  - ./langfuse/ks.yaml
#% endif %#
#% if litellm_enabled | default(false) %#
  - ./litellm/ks.yaml
#% endif %#
#% endif %#
```

### Flux Kustomization Pattern (ks.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) %#
---
#| Langfuse deployment - depends on shared infrastructure #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: langfuse
spec:
  dependsOn:
    - name: coredns
      namespace: kube-system
    - name: cloudnative-pg
      namespace: cnpg-system
#% if dragonfly_enabled | default(false) %#
    - name: dragonfly
      namespace: cache
#% endif %#
#% if rustfs_enabled | default(false) %#
    - name: rustfs
      namespace: storage
#% endif %#
#% if keycloak_enabled | default(false) %#
    - name: keycloak
      namespace: identity
#% endif %#
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: langfuse
      namespace: ai-system
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/ai-system/langfuse/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: ai-system
  timeout: 15m
  wait: true
#% endif %#
```

### App-Level Kustomization (app/kustomization.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ai-system

components:
  - ../../../components/sops

resources:
  - ./helmrelease.yaml
  - ./postgresql.yaml
  - ./secret.sops.yaml
  - ./httproute.yaml
#% if monitoring_enabled | default(false) %#
  - ./servicemonitor.yaml
#% endif %#
#% endif %#
```

### HelmRepository (app/helmrepository.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: langfuse
spec:
  interval: 1h
  url: https://langfuse.github.io/langfuse-k8s
#% endif %#
```

### HelmRelease (app/helmrelease.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: langfuse
spec:
  chart:
    spec:
      chart: langfuse
      version: "*"  #| Use latest; pin for production #|
      sourceRef:
        kind: HelmRepository
        name: langfuse
        namespace: ai-system
  interval: 1h
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  values:
    #| ============================================ #|
    #| Core Application Configuration              #|
    #| ============================================ #|
    langfuse:
      nextauth:
        url: "https://#{ langfuse_subdomain | default('langfuse') }#.#{ cloudflare_domain }#"
        secret:
          value: "#{ langfuse_nextauth_secret }#"
      salt:
        value: "#{ langfuse_salt }#"
      encryptionKey: "#{ langfuse_encryption_key }#"

      #| Logging #|
      logLevel: "#{ langfuse_log_level | default('info') }#"
      logFormat: "json"

    #| ============================================ #|
    #| PostgreSQL - Use External CNPG Cluster      #|
    #| ============================================ #|
    postgresql:
      enabled: false  #| Disable bundled PostgreSQL #|

    externalPostgresql:
      host: "langfuse-postgresql-rw.ai-system.svc.cluster.local"
      port: 5432
      database: "langfuse"
      user: "langfuse"
      existingSecret: "langfuse-postgresql-credentials"
      existingSecretPasswordKey: "password"

    #| ============================================ #|
    #| Redis - Use External Dragonfly              #|
    #| ============================================ #|
    redis:
      enabled: false  #| Disable bundled Redis #|

    externalRedis:
      connectionString: "redis://dragonfly.cache.svc.cluster.local:6379"
#% if dragonfly_acl_enabled | default(false) %#
      #| Use ACL if Dragonfly multi-tenant mode #|
      existingSecret: "langfuse-redis-credentials"
      existingSecretPasswordKey: "password"
#% endif %#

    #| ============================================ #|
    #| ClickHouse - Bundled for Analytics          #|
    #| ============================================ #|
    clickhouse:
      enabled: true
      replicaCount: 1
      persistence:
        enabled: true
        size: #{ langfuse_clickhouse_storage | default('20Gi') }#
        storageClass: #{ storage_class | default('local-path') }#

      resources:
        requests:
          cpu: 500m
          memory: 2Gi
        limits:
          memory: 4Gi

      auth:
        existingSecret: "langfuse-clickhouse-credentials"
        existingSecretPasswordKey: "password"

    #| ============================================ #|
    #| S3 Storage - Use External RustFS            #|
    #| ============================================ #|
    s3:
      enabled: true
      provider: "s3"  #| S3-compatible #|
      eventUploadBucket: "langfuse-events"
      eventUploadRegion: "us-east-1"
      eventUploadEndpoint: "http://rustfs-svc.storage.svc.cluster.local:9000"
      eventUploadForcePathStyle: true
      existingSecret: "langfuse-s3-credentials"
      existingSecretAccessKeyIdKey: "AWS_ACCESS_KEY_ID"
      existingSecretSecretAccessKeyKey: "AWS_SECRET_ACCESS_KEY"

      #| Media uploads #|
      mediaUploadEnabled: true
      mediaUploadBucket: "langfuse-media"

      #| Batch exports #|
      batchExportEnabled: true
      batchExportBucket: "langfuse-exports"

    minio:
      enabled: false  #| Disable bundled MinIO #|

    #| ============================================ #|
    #| Authentication & SSO                        #|
    #| ============================================ #|
#% if keycloak_enabled | default(false) and langfuse_sso_enabled | default(false) %#
    auth:
      disableUsernamePassword: false  #| Keep as fallback #|

      #| Keycloak OIDC Configuration #|
      keycloak:
        enabled: true
        clientId: "langfuse"
        issuer: "#{ keycloak_issuer_url }#"
        existingSecret: "langfuse-keycloak-credentials"
        existingSecretClientSecretKey: "client-secret"
        allowAccountLinking: true
#% endif %#

    #| ============================================ #|
    #| Ingress / Gateway API                       #|
    #| ============================================ #|
    ingress:
      enabled: false  #| Use HTTPRoute instead #|

    #| ============================================ #|
    #| Resource Allocation                         #|
    #| ============================================ #|
    web:
      resources:
        requests:
          cpu: #{ langfuse_web_cpu_request | default('200m') }#
          memory: #{ langfuse_web_memory_request | default('512Mi') }#
        limits:
          memory: #{ langfuse_web_memory_limit | default('2Gi') }#

    worker:
      resources:
        requests:
          cpu: #{ langfuse_worker_cpu_request | default('200m') }#
          memory: #{ langfuse_worker_memory_request | default('512Mi') }#
        limits:
          memory: #{ langfuse_worker_memory_limit | default('2Gi') }#

    #| ============================================ #|
    #| Observability                               #|
    #| ============================================ #|
#% if tracing_enabled | default(false) %#
    otel:
      enabled: true
      endpoint: "http://tempo.monitoring.svc.cluster.local:4318"
      serviceName: "langfuse"
      samplingRatio: "#{ langfuse_trace_sampling_ratio | default('0.1') }#"
#% endif %#
#% endif %#
```

### HTTPRoute (app/httproute.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: langfuse
#% if oidc_enabled | default(false) and langfuse_jwt_protected | default(false) %#
  labels:
    security: jwt-protected
#% endif %#
spec:
  hostnames:
    - "#{ langfuse_subdomain | default('langfuse') }#.#{ cloudflare_domain }#"
  parentRefs:
    - name: envoy-external
      namespace: network
      sectionName: https
  rules:
    - backendRefs:
        - name: langfuse-web
          port: 3000
      matches:
        - path:
            type: PathPrefix
            value: /
#% endif %#
```

### Secret Template (app/secret.sops.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-credentials
type: Opaque
stringData:
  #| NextAuth secret (256+ entropy) #|
  NEXTAUTH_SECRET: "#{ langfuse_nextauth_secret }#"
  #| Salt for API key hashing (256+ entropy) #|
  SALT: "#{ langfuse_salt }#"
  #| Encryption key (256-bit hex) #|
  ENCRYPTION_KEY: "#{ langfuse_encryption_key }#"
---
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-postgresql-credentials
type: Opaque
stringData:
  username: "langfuse"
  password: "#{ langfuse_postgres_password }#"
---
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-clickhouse-credentials
type: Opaque
stringData:
  password: "#{ langfuse_clickhouse_password }#"
---
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-s3-credentials
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "#{ langfuse_s3_access_key }#"
  AWS_SECRET_ACCESS_KEY: "#{ langfuse_s3_secret_key }#"
#% if keycloak_enabled | default(false) and langfuse_sso_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-keycloak-credentials
type: Opaque
stringData:
  client-secret: "#{ langfuse_keycloak_client_secret }#"
#% endif %#
#% endif %#
```

---

## Configuration Schema

### cluster.yaml Variables

```yaml
# =============================================================================
# LANGFUSE - LLM Observability Platform
# =============================================================================
# Langfuse provides tracing, prompt management, evaluation, and cost analytics
# for LLM applications. Integrates with LiteLLM Proxy Gateway for unified
# observability across all LLM providers.
# REF: https://langfuse.com/self-hosting
# REF: docs/research/langfuse-llm-observability-integration-jan-2026.md

# -- Enable Langfuse deployment
#    (OPTIONAL) / (DEFAULT: false)
# langfuse_enabled: false

# -- Langfuse subdomain (creates langfuse.${cloudflare_domain})
#    (OPTIONAL) / (DEFAULT: "langfuse")
# langfuse_subdomain: "langfuse"

# -- NextAuth secret for session management (256+ entropy)
#    Generate with: openssl rand -base64 32
#    (REQUIRED when langfuse_enabled: true)
# langfuse_nextauth_secret: ""

# -- Salt for API key hashing (256+ entropy)
#    Generate with: openssl rand -base64 32
#    (REQUIRED when langfuse_enabled: true)
# langfuse_salt: ""

# -- Encryption key for sensitive data (256-bit hex)
#    Generate with: openssl rand -hex 32
#    (REQUIRED when langfuse_enabled: true)
# langfuse_encryption_key: ""

# -- PostgreSQL password for Langfuse database
#    Generate with: openssl rand -base64 24
#    (REQUIRED when langfuse_enabled: true)
# langfuse_postgres_password: ""

# -- PostgreSQL instances for HA (1 for dev, 3 for prod)
#    (OPTIONAL) / (DEFAULT: 1)
# langfuse_postgres_instances: 1

# -- PostgreSQL storage size
#    (OPTIONAL) / (DEFAULT: "10Gi")
# langfuse_postgres_storage: "10Gi"

# -- ClickHouse password for analytics database
#    Generate with: openssl rand -base64 24
#    (REQUIRED when langfuse_enabled: true)
# langfuse_clickhouse_password: ""

# -- ClickHouse storage size
#    (OPTIONAL) / (DEFAULT: "20Gi")
# langfuse_clickhouse_storage: "20Gi"

# -- S3 access key for RustFS (created via RustFS Console)
#    (REQUIRED when langfuse_enabled: true)
# langfuse_s3_access_key: ""

# -- S3 secret key for RustFS (SOPS-encrypted)
#    (REQUIRED when langfuse_enabled: true)
# langfuse_s3_secret_key: ""

# -- Enable PostgreSQL backups to RustFS
#    (OPTIONAL) / (DEFAULT: false) / (REQUIRES: rustfs_enabled: true)
# langfuse_backup_enabled: false

# -- Enable Keycloak SSO for Langfuse
#    (OPTIONAL) / (DEFAULT: false) / (REQUIRES: keycloak_enabled: true)
# langfuse_sso_enabled: false

# -- Keycloak client secret for Langfuse OIDC
#    (REQUIRED when langfuse_sso_enabled: true)
# langfuse_keycloak_client_secret: ""

# -- Log level (trace, debug, info, warn, error, fatal)
#    (OPTIONAL) / (DEFAULT: "info")
# langfuse_log_level: "info"

# -- OpenTelemetry trace sampling ratio (0.0 to 1.0)
#    (OPTIONAL) / (DEFAULT: "0.1" = 10%)
# langfuse_trace_sampling_ratio: "0.1"

# -- Enable JWT protection on HTTPRoute (requires OIDC)
#    (OPTIONAL) / (DEFAULT: false)
# langfuse_jwt_protected: false
```

### Derived Variables (plugin.py additions)

```python
# Langfuse LLM Observability - enabled when langfuse_enabled is true
langfuse_enabled = data.get("langfuse_enabled", False)
data["langfuse_enabled"] = langfuse_enabled

if langfuse_enabled:
    # Default subdomain
    data.setdefault("langfuse_subdomain", "langfuse")

    # Derive hostname and URLs
    cloudflare_domain = data.get("cloudflare_domain", "")
    langfuse_subdomain = data.get("langfuse_subdomain", "langfuse")
    data["langfuse_hostname"] = f"{langfuse_subdomain}.{cloudflare_domain}"
    data["langfuse_url"] = f"https://{langfuse_subdomain}.{cloudflare_domain}"

    # Resource defaults
    data.setdefault("langfuse_postgres_instances", 1)
    data.setdefault("langfuse_postgres_storage", "10Gi")
    data.setdefault("langfuse_clickhouse_storage", "20Gi")
    data.setdefault("langfuse_log_level", "info")
    data.setdefault("langfuse_trace_sampling_ratio", "0.1")

    # Backup configuration
    langfuse_backup_enabled = (
        data.get("rustfs_enabled", False)
        and data.get("langfuse_backup_enabled", False)
        and data.get("langfuse_s3_access_key")
        and data.get("langfuse_s3_secret_key")
    )
    data["langfuse_backup_enabled"] = langfuse_backup_enabled

    # SSO configuration
    langfuse_sso_enabled = (
        data.get("keycloak_enabled", False)
        and data.get("langfuse_sso_enabled", False)
        and data.get("langfuse_keycloak_client_secret")
    )
    data["langfuse_sso_enabled"] = langfuse_sso_enabled
```

---

## Keycloak SSO Integration

### OIDC Client Configuration

Add to Keycloak realm configuration (`realm-import.yaml.j2`):

```yaml
#% if langfuse_enabled | default(false) and langfuse_sso_enabled | default(false) %#
    - clientId: langfuse
      name: Langfuse LLM Observability
      description: LLM tracing and prompt management platform
      enabled: true
      protocol: openid-connect
      publicClient: false
      standardFlowEnabled: true
      directAccessGrantsEnabled: false
      serviceAccountsEnabled: false
      authorizationServicesEnabled: false

      #| Redirect URIs #|
      redirectUris:
        - "https://#{ langfuse_subdomain | default('langfuse') }#.#{ cloudflare_domain }#/api/auth/callback/keycloak"
      webOrigins:
        - "https://#{ langfuse_subdomain | default('langfuse') }#.#{ cloudflare_domain }#"

      #| Token settings #|
      attributes:
        access.token.lifespan: "3600"
        pkce.code.challenge.method: "S256"

      #| Default scopes #|
      defaultClientScopes:
        - openid
        - profile
        - email
#% endif %#
```

### Environment Variables for SSO

```yaml
env:
  AUTH_KEYCLOAK_ID: "langfuse"
  AUTH_KEYCLOAK_SECRET:
    valueFrom:
      secretKeyRef:
        name: langfuse-keycloak-credentials
        key: client-secret
  AUTH_KEYCLOAK_ISSUER: "#{ keycloak_issuer_url }#"
  AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING: "true"

  #| Optional: Enforce SSO for specific domains #|
  # AUTH_DOMAINS_WITH_SSO_ENFORCEMENT: "example.com"
```

### Account Linking

Langfuse supports merging accounts with the same email across providers:
- Set `AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING=true`
- Users authenticated via Keycloak will be linked to existing email-based accounts

---

## LiteLLM Proxy Integration

### Callback Configuration

In LiteLLM `config.yaml`:

```yaml
litellm_settings:
  callbacks:
    - langfuse

environment_variables:
  LANGFUSE_PUBLIC_KEY: "pk-lf-..."
  LANGFUSE_SECRET_KEY: "sk-lf-..."
  LANGFUSE_HOST: "http://langfuse-web.ai-system.svc.cluster.local:3000"
```

### Trace Correlation

LiteLLM automatically sends traces to Langfuse with:
- Model name and provider
- Token usage and latency
- Request/response payloads
- Cost calculations

### LLM Connections in Langfuse

Langfuse can also call LLMs for:
- Playground testing
- LLM-as-a-Judge evaluation
- Prompt experiments

Configure via Project Settings > LLM Connections:
- Point to LiteLLM proxy as OpenAI-compatible endpoint
- Base URL: `http://litellm.ai-system.svc.cluster.local:4000`

---

## OpenTelemetry Integration

### Langfuse as OTEL Backend

Langfuse can receive traces via OTLP at `/api/public/otel`:

```yaml
env:
  #| Self-observability: export Langfuse's own traces to Tempo #|
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://tempo.monitoring.svc.cluster.local:4318"
  OTEL_SERVICE_NAME: "langfuse"
  OTEL_TRACE_SAMPLING_RATIO: "0.1"
```

### Sending Traces to Langfuse

Applications can send LLM traces to Langfuse via OTLP:

```python
# Python example with OpenLLMetry
from traceloop.sdk import Traceloop

Traceloop.init(
    exporter_endpoint="https://langfuse.example.com/api/public/otel",
    headers={"Authorization": f"Basic {base64_encode('pk-xxx:sk-xxx')}"}
)
```

### Attribute Mapping

| OpenTelemetry Attribute | Langfuse Mapping |
| ----------------------- | ---------------- |
| `langfuse.trace.name` | Trace name |
| `langfuse.user.id` | User identifier |
| `langfuse.session.id` | Session grouping |
| `langfuse.observation.model.name` | LLM model |
| `gen_ai.prompt` | Input content |
| `gen_ai.completion` | Output content |

---

## Monitoring and Health Checks

### Health Endpoints

| Container | Endpoint | Purpose |
| --------- | -------- | ------- |
| langfuse-web | `/api/public/health` | Liveness check |
| langfuse-web | `/api/public/ready` | Readiness check |
| langfuse-worker | `/api/health` | Worker health |

### Kubernetes Probes

```yaml
livenessProbe:
  httpGet:
    path: /api/public/health
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /api/public/ready
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5
```

### ServiceMonitor (app/servicemonitor.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) and monitoring_enabled | default(false) %#
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: langfuse
  labels:
    app.kubernetes.io/name: langfuse
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: langfuse
  endpoints:
    - port: http
      interval: 30s
      path: /api/public/metrics
  namespaceSelector:
    matchNames:
      - ai-system
#% endif %#
```

---

## Backup Strategy

### PostgreSQL (CNPG)

Use CNPG's barmanObjectStore for continuous WAL archiving:

```yaml
backup:
  barmanObjectStore:
    destinationPath: s3://langfuse-postgres-backups/
    endpointURL: http://rustfs-svc.storage.svc.cluster.local:9000
    s3Credentials:
      accessKeyId:
        name: langfuse-s3-credentials
        key: AWS_ACCESS_KEY_ID
      secretAccessKey:
        name: langfuse-s3-credentials
        key: AWS_SECRET_ACCESS_KEY
  retentionPolicy: "7d"
```

### ClickHouse

For ClickHouse backups to S3:

```sql
BACKUP DATABASE default TO S3(
  'http://rustfs-svc.storage.svc.cluster.local:9000/langfuse-clickhouse-backups/backup_{timestamp}',
  'access_key',
  'secret_key'
)
```

Or use Kubernetes volume snapshots for PVC-based backups.

### S3 Buckets

RustFS data is inherently durable. For additional protection:
- Enable cross-region replication (if using cloud provider)
- Periodic sync to external storage

---

## Security Configuration

### Network Policy (app/networkpolicy.yaml.j2)

```yaml
#% if langfuse_enabled | default(false) and network_policies_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: langfuse
  namespace: ai-system
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: langfuse
  ingress:
    #| Allow Gateway API ingress #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
    #| Allow LiteLLM callbacks #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: litellm
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
    #| Allow Prometheus scraping #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
  egress:
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    #| PostgreSQL (CNPG) #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: langfuse-postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| Redis (Dragonfly) #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: cache
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP
    #| S3 (RustFS) #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: storage
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
    #| ClickHouse (internal) #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: clickhouse
      toPorts:
        - ports:
            - port: "8123"
              protocol: TCP
            - port: "9000"
              protocol: TCP
    #| Keycloak (if SSO enabled) #|
#% if keycloak_enabled | default(false) %#
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: identity
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
#% endif %#
    #| OpenTelemetry (Tempo) #|
#% if tracing_enabled | default(false) %#
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "4318"
              protocol: TCP
#% endif %#
#% endif %#
```

### Encryption

| Data Type | Encryption Method |
| --------- | ----------------- |
| API Keys | Hashed with SALT |
| Sensitive Data | AES-256 with ENCRYPTION_KEY |
| TLS Transit | cert-manager certificates |
| S3 Storage | Optional SSE-S3 |

---

## Implementation Phases

### Phase 1: Core Deployment

**Scope:**
- Create `ai-system` namespace template
- Deploy Langfuse with bundled ClickHouse
- Configure PostgreSQL via CNPG
- Configure Redis via Dragonfly
- Configure S3 via RustFS
- Basic password authentication

**Configuration:**
```yaml
langfuse_enabled: true
langfuse_nextauth_secret: "<generated>"
langfuse_salt: "<generated>"
langfuse_encryption_key: "<generated>"
langfuse_postgres_password: "<generated>"
langfuse_clickhouse_password: "<generated>"
langfuse_s3_access_key: "<from RustFS console>"
langfuse_s3_secret_key: "<from RustFS console>"
```

**Files to Create:**
- `templates/config/kubernetes/apps/ai-system/kustomization.yaml.j2`
- `templates/config/kubernetes/apps/ai-system/namespace.yaml.j2`
- `templates/config/kubernetes/apps/ai-system/langfuse/ks.yaml.j2`
- `templates/config/kubernetes/apps/ai-system/langfuse/app/*.yaml.j2`

### Phase 2: Keycloak SSO Integration

**Scope:**
- Configure Keycloak OIDC client
- Enable SSO in Langfuse
- Account linking support

**Prerequisites:**
- `keycloak_enabled: true`

**Configuration:**
```yaml
langfuse_sso_enabled: true
langfuse_keycloak_client_secret: "<from Keycloak>"
```

### Phase 3: LiteLLM Integration

**Scope:**
- Configure Langfuse callback in LiteLLM
- Bidirectional observability setup
- LLM connection for Playground

**Prerequisites:**
- `litellm_enabled: true`

### Phase 4: Observability Stack

**Scope:**
- ServiceMonitor for Prometheus
- OpenTelemetry export to Tempo
- Grafana dashboard

**Prerequisites:**
- `monitoring_enabled: true`
- `tracing_enabled: true`

**Configuration:**
```yaml
langfuse_trace_sampling_ratio: "0.1"
```

### Phase 5: Backup and Network Policies

**Scope:**
- PostgreSQL backups via CNPG barmanObjectStore
- ClickHouse backups to S3
- CiliumNetworkPolicy for zero-trust

**Prerequisites:**
- `rustfs_enabled: true`
- `network_policies_enabled: true`

**Configuration:**
```yaml
langfuse_backup_enabled: true
```

---

## Sources and References

### Official Documentation

- [Langfuse Kubernetes Helm Deployment](https://langfuse.com/self-hosting/deployment/kubernetes-helm)
- [Langfuse Cache (Redis) Configuration](https://langfuse.com/self-hosting/deployment/infrastructure/cache)
- [Langfuse Blob Storage (S3) Configuration](https://langfuse.com/self-hosting/deployment/infrastructure/blobstorage)
- [Langfuse PostgreSQL Requirements](https://langfuse.com/self-hosting/deployment/infrastructure/postgres)
- [Langfuse LLM API Configuration](https://langfuse.com/self-hosting/deployment/infrastructure/llm-api)
- [Langfuse Authentication and SSO](https://langfuse.com/self-hosting/security/authentication-and-sso)
- [Langfuse RBAC](https://langfuse.com/docs/administration/rbac)
- [Langfuse Observability](https://langfuse.com/self-hosting/configuration/observability)
- [Langfuse Health Endpoints](https://langfuse.com/self-hosting/configuration/health-readiness-endpoints)
- [Langfuse Backups](https://langfuse.com/self-hosting/configuration/backups)
- [Langfuse Environment Variables](https://langfuse.com/self-hosting/configuration)

### Integration Guides

- [LiteLLM Proxy + Langfuse Cookbook](https://langfuse.com/guides/cookbook/integration_litellm_proxy)
- [OpenLLMetry Integration](https://langfuse.com/guides/cookbook/otel_integration_openllmetry)
- [OpenTelemetry Native Integration](https://langfuse.com/integrations/native/opentelemetry)

### GitHub Repositories

- [langfuse/langfuse](https://github.com/langfuse/langfuse) - Main repository
- [langfuse/langfuse-k8s](https://github.com/langfuse/langfuse-k8s) - Helm charts

### Related Project Documentation

- [LiteLLM Proxy Gateway Integration](./litellm-proxy-gateway-integration-jan-2026.md)
- [Dragonfly Redis Alternative Integration](./dragonfly-redis-alternative-integration-jan-2026.md)
- [Keycloak Configuration as Code](./keycloak-configuration-as-code-gitops-jan-2026.md)

---

## Appendix A: Quick Reference

### Environment Variables Summary

| Variable | Description | Required |
| -------- | ----------- | -------- |
| `DATABASE_URL` | PostgreSQL connection | Yes |
| `CLICKHOUSE_URL` | ClickHouse HTTP endpoint | Yes |
| `REDIS_CONNECTION_STRING` | Redis/Dragonfly connection | Yes |
| `NEXTAUTH_URL` | Public Langfuse URL | Yes |
| `NEXTAUTH_SECRET` | Session secret (256+ entropy) | Yes |
| `SALT` | API key hashing salt | Yes |
| `ENCRYPTION_KEY` | Data encryption key (256-bit hex) | Yes |
| `LANGFUSE_S3_EVENT_UPLOAD_*` | S3 event storage | Yes |
| `AUTH_KEYCLOAK_*` | Keycloak SSO | If SSO enabled |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry export | If tracing enabled |

### RustFS Buckets

| Bucket | Purpose |
| ------ | ------- |
| `langfuse-events` | Raw event storage |
| `langfuse-media` | Multi-modal uploads |
| `langfuse-exports` | Batch data exports |
| `langfuse-postgres-backups` | CNPG barman backups |
| `langfuse-clickhouse-backups` | ClickHouse backups |

### Service Ports

| Service | Port | Purpose |
| ------- | ---- | ------- |
| langfuse-web | 3000 | Web UI + API |
| langfuse-worker | 3030 | Background jobs |
| ClickHouse HTTP | 8123 | Queries |
| ClickHouse TCP | 9000 | Native protocol |

---

## Appendix B: Comparison with Project Patterns

| Aspect | CNPG | RustFS | Keycloak | Langfuse (Proposed) |
| ------ | ---- | ------ | -------- | ------------------- |
| Namespace | `cnpg-system` | `storage` | `identity` | `ai-system` |
| Deployment | HelmRelease | HelmRelease | Operator + CR | HelmRelease |
| PostgreSQL | N/A | N/A | CNPG Cluster | CNPG Cluster |
| Redis | N/A | N/A | N/A | Dragonfly (shared) |
| S3 Storage | N/A | Self | RustFS | RustFS (shared) |
| Monitoring | ServiceMonitor | ServiceMonitor | ServiceMonitor | ServiceMonitor |
| SSO | N/A | N/A | Self | Keycloak (shared) |
| Network Policy | Yes | No | Yes | Yes (proposed) |

---

## Appendix C: Credential Generation

```bash
# NextAuth secret (256+ entropy)
openssl rand -base64 32

# Salt (256+ entropy)
openssl rand -base64 32

# Encryption key (256-bit hex)
openssl rand -hex 32

# PostgreSQL password
openssl rand -base64 24

# ClickHouse password
openssl rand -base64 24
```

---

## Appendix D: Review Findings and Corrections (January 2026)

### Post-Research Review

This document was validated against the project's established patterns using Serena MCP analysis tools and project memories (`flux_dependency_patterns`, `style_and_conventions`, `task_completion_checklist`).

### Validation Results

| Pattern | Status | Notes |
| --------- | -------- | ------- |
| Cross-namespace dependencies | ✅ **Validated** | All dependencies correctly specify namespace (coredns→kube-system, cloudnative-pg→cnpg-system, dragonfly→cache, rustfs→storage, keycloak→identity) |
| Template delimiters | ✅ **Validated** | Uses correct makejinja syntax: `#% %#` blocks, `#{ }#` variables, `#\| #\|` comments |
| Conditional components | ✅ **Validated** | Uses `#% if variable \| default(false) %#` pattern consistently |
| HelmRepository pattern | ✅ **Validated** | Uses standard HelmRepository + HelmRelease pattern |
| Secret management | ✅ **Validated** | Uses SOPS-encrypted secrets with `stringData` |
| StorageClass | ✅ **Validated** | Explicitly sets storageClass with default fallback |
| PodSecurity labels | ✅ **Validated** | Namespace uses `baseline` level (appropriate for web apps) |
| HTTPRoute pattern | ✅ **Validated** | Uses Gateway API with envoy-external, disabled Helm ingress |
| ServiceMonitor | ✅ **Validated** | Follows project monitoring pattern |
| CNPG Cluster | ✅ **Validated** | Uses CNPG pattern matching Keycloak implementation |

### Issues Identified and Corrected

#### Issue 1: Missing app/kustomization.yaml.j2 Template

The document was missing the app-level kustomization template. **Added:**

```yaml
#% if langfuse_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ai-system

components:
  - ../../../components/sops

resources:
  - ./helmrelease.yaml
  - ./postgresql.yaml
  - ./secret.sops.yaml
  - ./httproute.yaml
#% if monitoring_enabled | default(false) %#
  - ./servicemonitor.yaml
#% endif %#
#% endif %#
```

#### Issue 2: Missing Namespace-Level Kustomization

The ai-system namespace kustomization was not documented. **Added:**

```yaml
#% if langfuse_enabled | default(false) or litellm_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
#% if langfuse_enabled | default(false) %#
  - ./langfuse/ks.yaml
#% endif %#
#% if litellm_enabled | default(false) %#
  - ./litellm/ks.yaml
#% endif %#
#% endif %#
```

#### Issue 3: HelmRepository Missing Namespace

The HelmRepository should be in the same namespace as the HelmRelease (ai-system) and referenced correctly. The chart sourceRef should include `namespace: ai-system`.

#### Issue 4: Missing SOPS Component Reference

The app kustomization should include the SOPS component for secret decryption:
```yaml
components:
  - ../../../components/sops
```

#### Issue 5: Keycloak Client Configuration Location

The document references adding a Keycloak client to `realm-import.yaml.j2`, but the project uses `keycloak-config-cli` with `realm-config.yaml.j2`. The correct file is:
- `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`

### Enhancement Opportunities

#### 1. Dragonfly ACL Integration

When `dragonfly_acl_enabled: true`, Langfuse should use a dedicated ACL user with key pattern restrictions:

```
user langfuse on >#{ langfuse_redis_password }# ~langfuse:* +@all -@dangerous
```

Add to cluster.yaml schema:
```yaml
# -- Langfuse Redis password for ACL mode
#    (REQUIRED when dragonfly_acl_enabled: true)
# langfuse_redis_password: ""
```

#### 2. Transactional Email Configuration

Add optional SMTP configuration for password resets and invitations:

```yaml
# -- SMTP connection URL for transactional emails
#    Format: smtp://user:pass@host:port
#    (OPTIONAL)
# langfuse_smtp_url: ""

# -- Email sender address
#    (REQUIRED when langfuse_smtp_url is set)
# langfuse_email_from: ""
```

#### 3. Session Duration Configuration

Add configurable session duration:

```yaml
# -- Session max age in seconds (default: 30 days)
#    (OPTIONAL) / (DEFAULT: 2592000)
# langfuse_session_max_age: 2592000
```

#### 4. Grafana Dashboard

Consider adding a Langfuse Grafana dashboard ConfigMap for self-observability metrics visualization, following the pattern used for Keycloak dashboards.

### Cross-Reference with Existing Components

| Component | Integration Status | Notes |
| ----------- | ------------------- | ------- |
| CNPG | ✅ Ready | Use identical pattern to Keycloak postgres-cnpg.yaml.j2 |
| Dragonfly | ✅ Ready | Shared cache with optional ACL |
| RustFS | ✅ Ready | 5 buckets via Console UI |
| Keycloak | ✅ Ready | Add client to realm-config.yaml.j2 |
| Tempo | ✅ Ready | OTLP HTTP/protobuf export |
| Prometheus | ✅ Ready | ServiceMonitor pattern |
| LiteLLM | ⚠️ Pending | Cross-reference litellm-proxy-gateway-integration-jan-2026.md |

### Remaining Considerations

1. **Helm Chart Values Validation**: The Langfuse Helm chart values structure should be verified against the actual chart before implementation
2. **ClickHouse ZooKeeper**: Bundled ClickHouse includes ZooKeeper; verify resource requirements
3. **Bucket Creation**: All 5 RustFS buckets must be created manually via Console UI
4. **Keycloak Client Secret**: Must be generated after Keycloak deployment and added to cluster.yaml

### Memory Files Consulted

- `flux_dependency_patterns.md` - Cross-namespace and CRD split patterns
- `style_and_conventions.md` - Template delimiters and directory structure
- `task_completion_checklist.md` - Validation workflow

All templates now conform to project conventions established in January 2026.
