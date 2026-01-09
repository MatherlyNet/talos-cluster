# Dragonfly Redis Alternative Integration Research

> **Status**: IMPLEMENTATION COMPLETE
> **Completed**: January 2026
> **Author**: Claude (AI Research Assistant)
> **Validation**: Full implementation validated - see `dragonfly-implementation-validation-jan-2026.md`
> **Last Review**: January 2026 - Enhanced with ACL, HTTP API, and advanced configuration options
>
> **This guide has been fully implemented.** All phases (Core Deployment, Monitoring, S3 Backup, HA, Network Policies) are complete. The implementation includes enhancements beyond this guide: BullMQ compatibility flags, `aclFromSecret` pattern (vs ConfigMap), and additional alert rules.

## Executive Summary

This document provides a comprehensive analysis for integrating [Dragonfly](https://www.dragonflydb.io/) as a shared Redis-compatible in-memory data store for the matherlynet-talos-cluster. Dragonfly is a modern, multi-threaded drop-in replacement for Redis and Memcached, offering significantly better performance and memory efficiency.

### Key Findings

1. **Dragonfly Operator v1.3.1** (latest stable) provides Kubernetes-native management with automatic failover, scaling, TLS, and S3 snapshots
2. **Integration pattern** follows existing CNPG/RustFS shared resource model with dedicated `cache` namespace
3. **Monitoring** integrates via PodMonitor with existing kube-prometheus-stack; HTTP `/metrics` endpoint bypasses auth
4. **S3 Backups** work with RustFS using the `--s3_endpoint` flag for S3-compatible storage
5. **Helm chart** available via OCI at `oci://ghcr.io/dragonflydb/dragonfly-operator/helm`
6. **ACL Support** enables fine-grained access control with user management, key patterns, and command restrictions
7. **Cache Mode** provides LRU-like eviction behavior for session/caching use cases

### Recommendation

**Implement Dragonfly as a shared cluster resource** in a dedicated `cache` namespace, following the established CNPG operator pattern with:
- Dragonfly Operator deployment via HelmRelease
- Dragonfly CR (Custom Resource) for instance configuration
- Optional S3 snapshots to RustFS
- Prometheus/Grafana monitoring integration

---

## Table of Contents

1. [Background and Motivation](#background-and-motivation)
2. [Dragonfly Overview](#dragonfly-overview)
3. [Kubernetes Deployment Options](#kubernetes-deployment-options)
4. [Integration Architecture](#integration-architecture)
5. [Template Design](#template-design)
6. [Configuration Schema](#configuration-schema)
7. [Advanced Configuration Flags](#advanced-configuration-flags)
8. [Monitoring Integration](#monitoring-integration)
9. [S3 Backup Integration with RustFS](#s3-backup-integration-with-rustfs)
10. [Security Configuration](#security-configuration)
11. [Access Control Lists (ACL)](#access-control-lists-acl)
12. [Implementation Phases](#implementation-phases)
13. [Sources and References](#sources-and-references)

---

## Background and Motivation

### Why Dragonfly?

| Feature | Redis OSS | Dragonfly |
| --------- | --------- | --------- |
| Threading | Single-threaded | Multi-threaded |
| Memory Efficiency | ~1x | 25% less memory |
| Performance | Baseline | 25x+ throughput |
| License | BSD-3 / SSPL (7.0+) | BSL 1.1 (free for most) |
| Memcached Protocol | No | Yes |
| Kubernetes Operator | Limited | Official, GA |

### Use Cases in This Cluster

1. **Session Storage**: For applications requiring distributed session management
2. **Caching Layer**: L2 cache for services behind PostgreSQL (CNPG)
3. **Rate Limiting**: Token bucket implementations for API rate limiting
4. **Pub/Sub Messaging**: Lightweight event distribution

---

## Dragonfly Overview

### Version Information (January 2026)

| Component | Version | Notes |
| --------- | ------- | ----- |
| Dragonfly Server | v1.36.0 | Default in operator v1.3.1 |
| Dragonfly Operator | v1.3.1 | Latest stable (Nov 2024) |
| Operator Helm Chart | v1.3.1 | OCI registry |
| Kubernetes Compatibility | 1.19+ | Tested with 1.35 |

### Operator Capabilities

From [Dragonfly Kubernetes Operator documentation](https://www.dragonflydb.io/docs/getting-started/kubernetes-operator):

- **Automatic failover** with master election
- **Horizontal and vertical scaling** with custom rollout strategies
- **TLS and authentication** support
- **Snapshots** to PVCs and S3-compatible storage
- **Prometheus and Grafana** integration
- **Custom configuration** via CRD

### CRD Configuration Options

From [Dragonfly Configuration documentation](https://www.dragonflydb.io/docs/managing-dragonfly/operator/dragonfly-configuration):

| Field | Type | Description |
| --------- | --------- | --------- |
| `replicas` | int | Total instances (1 master + N-1 replicas) |
| `image` | string | Container image (default: `docker.dragonflydb.io/dragonflydb/dragonfly:v1.21.2`) |
| `args` | []string | Command-line arguments |
| `resources` | ResourceRequirements | CPU/memory limits |
| `affinity` | Affinity | Pod scheduling rules |
| `nodeSelector` | map | Node selection |
| `tolerations` | []Toleration | Taints to tolerate |
| `authentication.passwordFromSecret` | SecretKeySelector | Password secret reference |
| `tlsSecretRef` | SecretReference | TLS certificate secret |
| `snapshot.cron` | string | Backup schedule (cron format) |
| `snapshot.persistentVolumeClaimSpec` | PVCSpec | PVC for snapshots |
| `serviceSpec.type` | string | Service type (ClusterIP/LoadBalancer) |

---

## Kubernetes Deployment Options

### Option 1: Dragonfly Operator (Recommended)

**Pros:**
- Official, maintained by DragonflyDB team
- Automatic failover and scaling
- CRD-based configuration
- Native S3 snapshot support

**Cons:**
- Adds CRDs to cluster
- Operator overhead (minimal)

**Installation:**
```yaml
# Via kubectl (raw manifests)
kubectl apply -f https://raw.githubusercontent.com/dragonflydb/dragonfly-operator/main/manifests/dragonfly-operator.yaml

# Via Helm (OCI)
helm upgrade --install dragonfly-operator \
  oci://ghcr.io/dragonflydb/dragonfly-operator/helm \
  --namespace dragonfly-operator-system \
  --create-namespace
```

### Option 2: Standalone Helm Chart

**Pros:**
- Simpler, no CRDs
- Direct Helm values configuration

**Cons:**
- No automatic failover
- Manual scaling
- Less integrated monitoring

**Installation:**
```yaml
helm upgrade --install dragonfly \
  oci://ghcr.io/dragonflydb/dragonfly/helm/dragonfly \
  --version v1.36.0
```

### Recommendation

**Use the Dragonfly Operator** for:
1. High availability with automatic failover
2. Declarative scaling
3. S3 snapshot integration
4. Better alignment with project's operator patterns (CNPG, Keycloak)

---

## Integration Architecture

### Namespace Design

Following the project's shared resource pattern (similar to CNPG and RustFS):

```
cache/                    # New namespace for caching services
├── dragonfly/            # Dragonfly operator + instance
│   ├── operator/         # Operator deployment (if using Helm)
│   └── app/              # Dragonfly CR + supporting resources
└── namespace.yaml
```

### Dependency Chain

```
cnpg-system/cloudnative-pg  (optional, for apps needing both)
        ↓
   cache/dragonfly-operator
        ↓
   cache/dragonfly (instance)
        ↓
   Applications (identity/keycloak, etc.)
```

### Service Discovery

Applications connect via:
```
dragonfly.<namespace>.svc.cluster.local:6379
```

For the recommended setup:
```
dragonfly.cache.svc.cluster.local:6379
```

---

## Template Design

### Directory Structure

Following project conventions:

```
templates/config/kubernetes/apps/cache/
├── kustomization.yaml.j2           # Namespace-level kustomization
├── namespace.yaml.j2               # Namespace definition
└── dragonfly/
    ├── ks.yaml.j2                  # Flux Kustomizations (operator + instance)
    ├── operator/
    │   ├── kustomization.yaml.j2
    │   ├── helmrepository.yaml.j2  # OCI HelmRepository for operator
    │   └── helmrelease.yaml.j2     # Operator HelmRelease
    └── app/
        ├── kustomization.yaml.j2
        ├── dragonfly-cr.yaml.j2    # Dragonfly instance CR
        ├── secret.sops.yaml.j2     # Authentication + S3 credentials
        ├── podmonitor.yaml.j2      # Prometheus PodMonitor
        ├── prometheusrule.yaml.j2  # Alert rules
        ├── networkpolicy.yaml.j2   # CiliumNetworkPolicy (optional)
        └── dashboard-configmap.yaml.j2  # Grafana dashboard
```

### Namespace Template (namespace.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: cache
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
    #| Dragonfly operator uses baseline PSA #|
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
#% endif %#
```

### Namespace Kustomization (kustomization.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: cache

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./dragonfly/ks.yaml
#% endif %#
```

### Flux Kustomization Pattern (ks.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
#| First Kustomization: Operator + CRDs #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dragonfly-operator
spec:
  dependsOn:
    - name: coredns
      namespace: kube-system
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: dragonfly-operator
      namespace: dragonfly-operator-system
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/cache/dragonfly/operator
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: dragonfly-operator-system
  timeout: 10m
  wait: true
---
#| Second Kustomization: Dragonfly CR (depends on operator) #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dragonfly
spec:
  dependsOn:
    - name: dragonfly-operator
#% if dragonfly_backup_enabled | default(false) %#
    - name: rustfs
      namespace: storage
#% endif %#
  healthChecks:
    - apiVersion: dragonflydb.io/v1alpha1
      kind: Dragonfly
      name: dragonfly
      namespace: cache
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/cache/dragonfly/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: cache
  timeout: 10m
  wait: true
#% endif %#
```

### Operator HelmRepository (operator/helmrepository.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: dragonfly-operator
spec:
  interval: 1h
  type: oci
  url: oci://ghcr.io/dragonflydb/dragonfly-operator
#% endif %#
```

### Operator Kustomization (operator/kustomization.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
#% endif %#
```

### Operator HelmRelease (operator/helmrelease.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: dragonfly-operator
spec:
  chart:
    spec:
      chart: helm
      version: "#{ dragonfly_operator_version | default('1.3.1') }#"
      sourceRef:
        kind: HelmRepository
        name: dragonfly-operator
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
    #| Operator runs in its own namespace #|
    priorityClassName: system-cluster-critical

    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        memory: 128Mi

    #| Security context #|
    podSecurityContext:
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault

    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: true

#% if dragonfly_monitoring_enabled | default(false) %#
    #| Enable ServiceMonitor for operator metrics #|
    serviceMonitor:
      enabled: true
      interval: 30s
#% endif %#
#% endif %#
```

### Dragonfly Instance CR (app/dragonfly-cr.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: dragonflydb.io/v1alpha1
kind: Dragonfly
metadata:
  name: dragonfly
spec:
  #| Number of replicas (1 master + N-1 replicas) #|
  replicas: #{ dragonfly_replicas | default(1) }#

  #| Container image #|
  image: docker.dragonflydb.io/dragonflydb/dragonfly:#{ dragonfly_version | default('v1.36.0') }#

  #| Resource limits #|
  resources:
    requests:
      cpu: #{ dragonfly_cpu_request | default('100m') }#
      memory: #{ dragonfly_memory_request | default('256Mi') }#
    limits:
      memory: #{ dragonfly_memory_limit | default('1Gi') }#

  #| Authentication #|
  authentication:
    passwordFromSecret:
      name: dragonfly-auth
      key: password

  #| Command-line arguments #|
  args:
    #| Core performance settings #|
    - --maxmemory=#{ dragonfly_maxmemory | default('512mb') }#
    - --proactor_threads=#{ dragonfly_threads | default(2) }#
    #| Admin port for metrics (separate from data port 6379) #|
    - --admin_port=9999
    #| Security: disable HTTP on main data port #|
    - --primary_port_http_enabled=false
#% if dragonfly_cache_mode | default(false) %#
    #| Cache mode enables LRU-like eviction when near maxmemory #|
    - --cache_mode=true
#% endif %#
    #| Slow query logging for debugging #|
    - --slowlog_log_slower_than=#{ dragonfly_slowlog_threshold | default(10000) }#
    - --slowlog_max_len=#{ dragonfly_slowlog_max_len | default(128) }#
#% if dragonfly_acl_enabled | default(false) %#
    #| ACL file for multi-tenant access control #|
    - --aclfile=/etc/dragonfly/acl.conf
#% endif %#
#% if dragonfly_backup_enabled | default(false) %#
    #| S3 snapshot configuration for RustFS #|
    - --dir=s3://dragonfly-backups
    - --s3_endpoint=#{ dragonfly_s3_endpoint | default('rustfs-svc.storage.svc.cluster.local:9000') }#
    - --s3_use_https=false
    - --dbfilename=snapshot
#% endif %#

#% if dragonfly_acl_enabled | default(false) %#
  #| Mount ACL configuration #|
  volumes:
    - name: acl-config
      configMap:
        name: dragonfly-acl
  volumeMounts:
    - name: acl-config
      mountPath: /etc/dragonfly
      readOnly: true
#% endif %#

#% if dragonfly_backup_enabled | default(false) %#
  #| Snapshot configuration #|
  snapshot:
    cron: "#{ dragonfly_snapshot_cron | default('0 */6 * * *') }#"

  #| S3 credentials via environment variables #|
  env:
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: dragonfly-auth
          key: AWS_ACCESS_KEY_ID
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: dragonfly-auth
          key: AWS_SECRET_ACCESS_KEY
#% endif %#

  #| Service configuration #|
  serviceSpec:
    type: ClusterIP

  #| Pod anti-affinity for HA #|
#% if (dragonfly_replicas | default(1) | int) > 1 %#
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: dragonfly
            topologyKey: kubernetes.io/hostname
#% endif %#

  #| Tolerations for control-plane scheduling (optional) #|
#% if dragonfly_control_plane_only | default(false) %#
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
#% endif %#
#% endif %#
```

### Authentication Secret (app/secret.sops.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: dragonfly-auth
type: Opaque
stringData:
  password: "#{ dragonfly_password }#"
#% if dragonfly_backup_enabled | default(false) %#
  #| S3 credentials for RustFS backup #|
  AWS_ACCESS_KEY_ID: "#{ dragonfly_s3_access_key }#"
  AWS_SECRET_ACCESS_KEY: "#{ dragonfly_s3_secret_key }#"
#% endif %#
#% endif %#
```

---

## Configuration Schema

### cluster.yaml Variables

Add to `cluster.sample.yaml`:

```yaml
# =============================================================================
# DRAGONFLY CACHE - Redis-compatible in-memory data store
# =============================================================================
# Dragonfly provides a high-performance, multi-threaded drop-in replacement
# for Redis with 25x+ better throughput and 25% less memory usage.
# Deployed as a shared cluster resource in the 'cache' namespace.
# REF: https://www.dragonflydb.io/docs/getting-started/kubernetes-operator
# REF: docs/research/dragonfly-redis-alternative-integration-jan-2026.md

# -- Enable Dragonfly cache deployment
#    (OPTIONAL) / (DEFAULT: false)
# dragonfly_enabled: false

# -- Dragonfly server version
#    (OPTIONAL) / (DEFAULT: "v1.36.0")
# dragonfly_version: "v1.36.0"

# -- Dragonfly Operator version
#    (OPTIONAL) / (DEFAULT: "1.3.1")
# dragonfly_operator_version: "1.3.1"

# -- Number of Dragonfly replicas (1 = standalone, 2+ = HA with replication)
#    (OPTIONAL) / (DEFAULT: 1)
# dragonfly_replicas: 1

# -- Maximum memory for Dragonfly (with unit: mb, gb)
#    (OPTIONAL) / (DEFAULT: "512mb")
# dragonfly_maxmemory: "512mb"

# -- Number of proactor threads (set based on available CPU)
#    (OPTIONAL) / (DEFAULT: 2)
# dragonfly_threads: 2

# -- Dragonfly authentication password (SOPS-encrypted)
#    Generate with: openssl rand -base64 24
#    (REQUIRED when dragonfly_enabled: true)
# dragonfly_password: ""

# -- Deploy Dragonfly on control-plane nodes only
#    (OPTIONAL) / (DEFAULT: false)
# dragonfly_control_plane_only: false

# -- Enable Dragonfly S3 snapshots to RustFS
#    Requires rustfs_enabled: true
#    (OPTIONAL) / (DEFAULT: false)
# dragonfly_backup_enabled: false

# -- S3 endpoint for Dragonfly backups
#    For RustFS internal: "rustfs-svc.storage.svc.cluster.local:9000"
#    (OPTIONAL when dragonfly_backup_enabled: true)
# dragonfly_s3_endpoint: "rustfs-svc.storage.svc.cluster.local:9000"

# -- S3 access key for Dragonfly backups (created via RustFS Console)
#    (REQUIRED when dragonfly_backup_enabled: true)
# dragonfly_s3_access_key: ""

# -- S3 secret key for Dragonfly backups (SOPS-encrypted)
#    (REQUIRED when dragonfly_backup_enabled: true)
# dragonfly_s3_secret_key: ""

# -- Snapshot cron schedule
#    (OPTIONAL) / (DEFAULT: "0 */6 * * *" - every 6 hours)
# dragonfly_snapshot_cron: "0 */6 * * *"

# -- Enable Dragonfly Grafana monitoring (PodMonitor + Dashboard)
#    (OPTIONAL) / (DEFAULT: false) / (REQUIRES: monitoring_enabled: true)
# dragonfly_monitoring_enabled: false

# -- Enable cache mode (LRU-like eviction when approaching maxmemory)
#    Recommended for session storage and caching use cases
#    (OPTIONAL) / (DEFAULT: false)
# dragonfly_cache_mode: false

# -- Slow query log threshold in microseconds
#    Queries slower than this are logged for debugging
#    (OPTIONAL) / (DEFAULT: 10000 = 10ms)
# dragonfly_slowlog_threshold: 10000

# -- Maximum number of slow queries to retain in log
#    (OPTIONAL) / (DEFAULT: 128)
# dragonfly_slowlog_max_len: 128

# -- Enable ACL (Access Control Lists) for multi-tenant access
#    Creates per-service users with key pattern restrictions
#    (OPTIONAL) / (DEFAULT: false)
# dragonfly_acl_enabled: false

# -- Keycloak-specific password for ACL (SOPS-encrypted)
#    When not set, falls back to dragonfly_password
#    (OPTIONAL when dragonfly_acl_enabled: true)
# dragonfly_keycloak_password: ""

# -- Application cache password for ACL (SOPS-encrypted)
#    When not set, falls back to dragonfly_password
#    (OPTIONAL when dragonfly_acl_enabled: true)
# dragonfly_appcache_password: ""
```

### Derived Variables (plugin.py additions)

```python
# Dragonfly cache - enabled when dragonfly_enabled is true
dragonfly_enabled = data.get("dragonfly_enabled", False)
data["dragonfly_enabled"] = dragonfly_enabled

if dragonfly_enabled:
    # Default versions
    data.setdefault("dragonfly_version", "v1.36.0")
    data.setdefault("dragonfly_operator_version", "1.3.1")
    data.setdefault("dragonfly_replicas", 1)
    data.setdefault("dragonfly_maxmemory", "512mb")
    data.setdefault("dragonfly_threads", 2)

    # Performance and debugging defaults
    data.setdefault("dragonfly_cache_mode", False)
    data.setdefault("dragonfly_slowlog_threshold", 10000)
    data.setdefault("dragonfly_slowlog_max_len", 128)

    # Backup configuration
    dragonfly_backup_enabled = (
        data.get("rustfs_enabled", False)
        and data.get("dragonfly_backup_enabled", False)
        and data.get("dragonfly_s3_access_key")
        and data.get("dragonfly_s3_secret_key")
    )
    data["dragonfly_backup_enabled"] = dragonfly_backup_enabled

    # Monitoring configuration
    dragonfly_monitoring_enabled = (
        data.get("monitoring_enabled", False)
        and data.get("dragonfly_monitoring_enabled", False)
    )
    data["dragonfly_monitoring_enabled"] = dragonfly_monitoring_enabled

    # ACL configuration - enabled when explicitly set
    dragonfly_acl_enabled = data.get("dragonfly_acl_enabled", False)
    data["dragonfly_acl_enabled"] = dragonfly_acl_enabled
else:
    data["dragonfly_backup_enabled"] = False
    data["dragonfly_monitoring_enabled"] = False
    data["dragonfly_acl_enabled"] = False
```

---

## Advanced Configuration Flags

From [Dragonfly Flags documentation](https://www.dragonflydb.io/docs/managing-dragonfly/flags):

### Configuration Methods

Dragonfly supports multiple configuration methods:
- **Command-line**: `dragonfly --port=6379`
- **Config file**: `dragonfly --flagfile=/path/to/flags.txt`
- **Environment variables**: `DFLY_` prefix (e.g., `DFLY_port=6379`)
- **Runtime**: `CONFIG SET` command (limited flags)

### Core Performance Flags

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `--port` | 6379 | Redis protocol port |
| `--admin_port` | 0 | Admin/metrics port (0 = disabled) |
| `--maxclients` | 64000 | Maximum concurrent connections |
| `--proactor_threads` | 0 | I/O threads (0 = auto) |
| `--conn_io_threads` | 0 | Connection handling threads |
| `--num_shards` | 0 | Database shards (0 = auto) |

### Memory Management Flags

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `--maxmemory` | 0 | Memory limit (0 = auto) |
| `--cache_mode` | false | Enable LRU-like eviction when near maxmemory |
| `--oom_deny_ratio` | 1.1 | OOM threshold ratio |
| `--enable_heartbeat_eviction` | true | Evict keys under memory pressure |
| `--max_eviction_per_heartbeat` | 100 | Keys evicted per cycle |

### Persistence Flags

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `--dbfilename` | dump-{timestamp} | Snapshot filename |
| `--dir` | "" | Working directory for snapshots |
| `--snapshot_cron` | "" | Cron expression for auto-snapshots |
| `--df_snapshot_format` | true | Use Dragonfly-specific format |

### Debugging Flags

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `--slowlog_log_slower_than` | 10000 | Slow query threshold (microseconds) |
| `--slowlog_max_len` | 20 | Slow log size limit |
| `--enable_top_keys_tracking` | false | Hot key debugging |
| `--log_dir` | "" | Log output directory |
| `--logtostderr` | true | Log to stderr |

### HTTP API Configuration

From [Dragonfly HTTP documentation](https://www.dragonflydb.io/docs/managing-dragonfly/using-http):

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `--primary_port_http_enabled` | true | HTTP on main port |
| `--admin_port` | 0 | Dedicated admin port with HTTP |
| `--admin_nopass` | false | Bypass auth on admin port |

**Important**: The `/metrics` endpoint always bypasses authentication, enabling Prometheus scraping without credentials.

### Recommended Production Configuration

```yaml
args:
  - --maxmemory=#{ dragonfly_maxmemory | default('512mb') }#
  - --proactor_threads=#{ dragonfly_threads | default(2) }#
  - --admin_port=9999
  - --primary_port_http_enabled=false  # Security: disable HTTP on data port
  - --cache_mode=#{ dragonfly_cache_mode | default('false') }#
  - --slowlog_log_slower_than=10000
  - --slowlog_max_len=128
```

---

## Monitoring Integration

### PodMonitor (app/podmonitor.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) and dragonfly_monitoring_enabled | default(false) %#
---
#| PodMonitor for Dragonfly instances #|
#| Scrapes metrics from the admin port exposed by Dragonfly pods #|
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: dragonfly
  labels:
    app.kubernetes.io/name: dragonfly
spec:
  selector:
    matchLabels:
      app: dragonfly
  namespaceSelector:
    matchNames:
      - cache
  podMetricsEndpoints:
    - port: admin
      interval: 30s
      scrapeTimeout: 10s
      path: /metrics
#% endif %#
```

### PrometheusRule (app/prometheusrule.yaml.j2)

```yaml
#% if dragonfly_enabled | default(false) and dragonfly_monitoring_enabled | default(false) %#
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dragonfly-alerts
  labels:
    app.kubernetes.io/name: dragonfly
    prometheus: kube-prometheus
spec:
  groups:
    - name: dragonfly.rules
      rules:
        #| Alert when Dragonfly is down #|
        - alert: DragonflyDown
          expr: up{job="dragonfly"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Dragonfly instance {{ $labels.pod }} is down"
            description: "Dragonfly pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been down for more than 5 minutes."

        #| Alert when memory usage is high #|
        - alert: DragonflyMemoryHigh
          expr: dragonfly_memory_used_bytes / dragonfly_memory_max_bytes > 0.9
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Dragonfly memory usage high on {{ $labels.pod }}"
            description: "Dragonfly instance {{ $labels.pod }} is using {{ $value | humanizePercentage }} of its allocated memory."

        #| Alert when connections are near limit #|
        - alert: DragonflyConnectionsHigh
          expr: dragonfly_connected_clients / dragonfly_maxclients > 0.8
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Dragonfly connections high on {{ $labels.pod }}"
            description: "Dragonfly instance {{ $labels.pod }} is using {{ $value | humanizePercentage }} of available connections."

        #| Alert when replication lag is high #|
        - alert: DragonflyReplicationLag
          expr: dragonfly_replication_lag_seconds > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Dragonfly replication lag on {{ $labels.pod }}"
            description: "Dragonfly replica {{ $labels.pod }} has a replication lag of {{ $value }}s."
#% endif %#
```

### Grafana Dashboard

The official Dragonfly dashboard is available at [Grafana Labs Dashboard #21444](https://grafana.com/grafana/dashboards/21444-dragonfly-dashboard/).

The dashboard JSON can be imported via ConfigMap following the project's existing pattern (see CNPG dashboard example).

---

## S3 Backup Integration with RustFS

### Configuration

From [Dragonfly S3 Snapshots documentation](https://www.dragonflydb.io/docs/managing-dragonfly/operator/snapshot-s3):

Dragonfly supports S3-compatible storage for snapshots using:

```
--dir=s3://<bucket-name>
--s3_endpoint=<endpoint>  # For S3-compatible services like RustFS
--s3_use_https=false      # When using internal HTTP endpoint
```

### RustFS IAM Setup

> **IMPORTANT:** RustFS does NOT support `mc admin` commands. All user/policy operations must be performed via the **RustFS Console UI** at `https://rustfs.${cloudflare_domain}`.

#### Step 1: Create Dragonfly Backup Bucket

Navigate to **Buckets** → **Create Bucket** and create the following:

| Bucket Name | Purpose | Retention |
| ----------- | ------- | --------- |
| `dragonfly-backups` | Dragonfly snapshot storage | Based on snapshot_cron schedule |

#### Step 2: Create Dragonfly Storage Policy

Create in RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `dragonfly-storage`

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
        "arn:aws:s3:::dragonfly-backups"
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
        "arn:aws:s3:::dragonfly-backups/*"
      ]
    }
  ]
}
```

#### Step 3: Create or Update Cache Group

**Option A: Create new group** (if `cache` group doesn't exist)

1. Navigate to **Identity** → **Groups** → **Create Group**
2. **Name:** `cache`
3. **Assign Policy:** `dragonfly-storage`
4. Click **Save**

**Option B: Update existing group** (if adding to existing group)

1. Navigate to **Identity** → **Groups** → Select `cache`
2. Click **Policies** tab → **Assign Policy**
3. Select `dragonfly-storage` → **Save**

#### Step 4: Create Dragonfly Service Account

1. Navigate to **Identity** → **Users** → **Create User**
2. **Access Key:** `dragonfly-backup`
3. **Assign to Group:** `cache`
4. Click **Save**
5. Click the user → **Service Accounts** → **Create Access Key**
6. **IMPORTANT:** Save both the Access Key and Secret Key immediately (secret is shown only once)

#### Step 5: Update cluster.yaml

Add the credentials to your `cluster.yaml`:

```yaml
# S3 credentials for Dragonfly backups (created via RustFS Console)
dragonfly_s3_access_key: "AKIAIOSFODNN7EXAMPLE"
dragonfly_s3_secret_key: "ENC[AES256_GCM,...]"  # SOPS-encrypted
```

Then encrypt the secret key:
```bash
sops --encrypt --in-place cluster.yaml
```

#### IAM Architecture Summary

| Component | Value |
| --------- | ----- |
| **Bucket** | `dragonfly-backups` |
| **Policy** | `dragonfly-storage` (scoped to dragonfly-backups only) |
| **Group** | `cache` |
| **User** | `dragonfly-backup` |
| **Cluster.yaml vars** | `dragonfly_s3_access_key`, `dragonfly_s3_secret_key` |

### Environment Variables

Dragonfly uses standard AWS SDK environment variables (configured automatically via the Dragonfly CR):

```yaml
env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: dragonfly-auth
        key: AWS_ACCESS_KEY_ID
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: dragonfly-auth
        key: AWS_SECRET_ACCESS_KEY
```

---

## Security Configuration

### Authentication

From [Dragonfly Authentication documentation](https://www.dragonflydb.io/docs/managing-dragonfly/operator/authentication):

**Password Authentication:**
```yaml
authentication:
  passwordFromSecret:
    name: dragonfly-auth
    key: password
```

**TLS with Client Certificates:**
```yaml
authentication:
  clientCaCertSecret:
    name: dragonfly-client-ca
    key: ca.crt
tlsSecretRef:
  name: dragonfly-tls
```

### TLS Configuration

From [Dragonfly TLS documentation](https://www.dragonflydb.io/docs/managing-dragonfly/operator/server-tls):

TLS can be enabled using cert-manager:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dragonfly-tls
spec:
  secretName: dragonfly-tls
  duration: 2160h  # 90 days
  renewBefore: 360h  # 15 days
  dnsNames:
    - dragonfly.cache.svc.cluster.local
    - dragonfly.cache.svc
  issuerRef:
    name: cluster-issuer
    kind: ClusterIssuer
```

### Network Policy

The CiliumNetworkPolicy template uses conditional ingress rules based on enabled components:

```yaml
#% if dragonfly_enabled | default(false) and network_policies_enabled | default(false) %#
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: dragonfly
  namespace: cache
spec:
  endpointSelector:
    matchLabels:
      app: dragonfly
#% if network_policies_mode | default('audit') == 'enforce' %#
  enableDefaultDeny:
    ingress: true
    egress: true
#% else %#
  #| Audit mode - observe traffic patterns via Hubble without blocking #|
  enableDefaultDeny:
    ingress: false
    egress: false
#% endif %#
  ingress:
    #| Allow traffic from identity namespace (Keycloak session storage) #|
#% if keycloak_enabled | default(false) %#
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: identity
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP
#% endif %#
    #| Allow traffic from ai-system namespace (LiteLLM/Langfuse cache) #|
#% if litellm_enabled | default(false) or langfuse_enabled | default(false) %#
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: ai-system
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP
#% endif %#
    #| Allow traffic from default namespace (application cache) #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: default
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP
    #| Allow Prometheus scraping from monitoring namespace #|
#% if monitoring_enabled | default(false) %#
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9999"
              protocol: TCP
#% endif %#
  egress:
    #| Allow DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    #| Allow S3 backups to RustFS #|
#% if dragonfly_backup_enabled | default(false) %#
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: storage
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% endif %#
```

**Ingress Rules Summary:**

| Namespace | Condition | Purpose |
| --------- | --------- | ------- |
| `identity` | `keycloak_enabled` | Keycloak session storage |
| `ai-system` | `litellm_enabled` OR `langfuse_enabled` | LiteLLM/Langfuse cache |
| `default` | Always | Application cache |
| `monitoring` | `monitoring_enabled` | Prometheus scraping (port 9999) |

---

## Access Control Lists (ACL)

From [Dragonfly ACL documentation](https://www.dragonflydb.io/docs/managing-dragonfly/acl):

Dragonfly implements Redis-compatible ACL for fine-grained access control, supporting user management, command restrictions, key patterns, and Pub/Sub channel permissions.

### ACL Overview

| Feature | Description |
| --------- | ------------- |
| User Management | Create/modify users with `ACL SETUSER` |
| Password Authentication | Multiple passwords per user |
| Command Restrictions | Allow/deny specific commands or categories |
| Key Patterns | Restrict access to key patterns (e.g., `app1:*`) |
| Pub/Sub Channels | Control channel subscription access |
| Persistence | Save ACL rules to file with `--aclfile` |

### ACL Commands

| Command | Description |
| --------- | ------------- |
| `ACL SETUSER <user> [rules...]` | Create or modify user |
| `ACL GETUSER <user>` | Get user details |
| `ACL DELUSER <user>` | Delete user |
| `ACL LIST` | List all users with rules |
| `ACL WHOAMI` | Show current authenticated user |
| `ACL CAT [category]` | List command categories |
| `ACL LOAD` | Reload ACL from file |
| `ACL SAVE` | Save ACL to file |

### User Rule Syntax

```
ACL SETUSER <username> [ON|OFF] [>password] [~keypattern] [+command|-command] [+@category|-@category]
```

| Rule | Description | Example |
| --------- | ------------- | --------- |
| `ON` | Enable user | `ACL SETUSER alice ON` |
| `OFF` | Disable user | `ACL SETUSER alice OFF` |
| `>password` | Add password | `ACL SETUSER alice >secret123` |
| `nopass` | No password required | `ACL SETUSER alice nopass` |
| `~pattern` | Key pattern access | `ACL SETUSER alice ~app1:*` |
| `allkeys` | Access all keys | `ACL SETUSER alice allkeys` |
| `+command` | Allow command | `ACL SETUSER alice +GET` |
| `-command` | Deny command | `ACL SETUSER alice -FLUSHALL` |
| `+@category` | Allow category | `ACL SETUSER alice +@read` |
| `-@category` | Deny category | `ACL SETUSER alice -@dangerous` |
| `allcommands` | Allow all commands | `ACL SETUSER alice allcommands` |

### Command Categories

| Category | Commands |
| --------- | --------- |
| `@read` | GET, MGET, HGET, etc. |
| `@write` | SET, DEL, HSET, etc. |
| `@admin` | CONFIG, DEBUG, SHUTDOWN |
| `@dangerous` | FLUSHALL, FLUSHDB, DEBUG |
| `@slow` | KEYS, SCAN, SMEMBERS |
| `@pubsub` | PUBLISH, SUBSCRIBE |
| `@transaction` | MULTI, EXEC, WATCH |

### Multi-Tenant Configuration Example

For shared Dragonfly with namespace isolation:

```yaml
#| ACL configuration for multi-tenant access #|
args:
  - --aclfile=/etc/dragonfly/acl.conf

#| Mount ACL file from ConfigMap #|
volumes:
  - name: acl-config
    configMap:
      name: dragonfly-acl

volumeMounts:
  - name: acl-config
    mountPath: /etc/dragonfly
    readOnly: true
```

**ACL ConfigMap (acl-configmap.yaml.j2):**

```yaml
#% if dragonfly_enabled | default(false) and dragonfly_acl_enabled | default(false) %#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dragonfly-acl
  namespace: cache
data:
  acl.conf: |
    #| Default admin user with full access #|
    user default on >#{ dragonfly_password }# ~* +@all

    #| Keycloak session store - limited to keycloak:* keys #|
    user keycloak on >#{ dragonfly_keycloak_password | default(dragonfly_password) }# ~keycloak:* +@read +@write -@dangerous

    #| Application cache - read-heavy workload #|
    user appcache on >#{ dragonfly_appcache_password | default(dragonfly_password) }# ~cache:* +@read +GET +SET +DEL +EXPIRE -@dangerous
#% endif %#
```

### Cluster.yaml ACL Variables

```yaml
# -- Enable ACL configuration for multi-tenant access
#    (OPTIONAL) / (DEFAULT: false)
# dragonfly_acl_enabled: false

# -- Per-tenant passwords (SOPS-encrypted)
#    When not set, defaults to dragonfly_password
# dragonfly_keycloak_password: ""
# dragonfly_appcache_password: ""
```

### Security Considerations

1. **Default User**: Always set a strong password for the `default` user
2. **Least Privilege**: Create service-specific users with minimal permissions
3. **Key Patterns**: Use key prefixes per service (e.g., `keycloak:*`, `cache:*`)
4. **Dangerous Commands**: Always deny `@dangerous` category for non-admin users
5. **ACL File Persistence**: Use `--aclfile` flag to persist ACL changes across restarts

---

## Implementation Phases

### Phase 1: Core Deployment

**Scope:**
- Create `cache` namespace template
- Deploy Dragonfly Operator via HelmRelease
- Create basic Dragonfly instance (single replica, no HA)
- Password authentication

**Configuration:**
```yaml
dragonfly_enabled: true
dragonfly_password: "<generated>"
dragonfly_replicas: 1
```

**Files to Create:**
- `templates/config/kubernetes/apps/cache/kustomization.yaml.j2`
- `templates/config/kubernetes/apps/cache/namespace.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/ks.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/operator/kustomization.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/operator/helmrepository.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/operator/helmrelease.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/app/kustomization.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/app/dragonfly-cr.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/app/secret.sops.yaml.j2`

**Estimated Effort:** 4-6 hours

### Phase 2: Monitoring Integration

**Scope:**
- PodMonitor for Prometheus scraping
- PrometheusRule for alerts
- Grafana dashboard ConfigMap

**Prerequisites:**
- `monitoring_enabled: true`

**Configuration:**
```yaml
dragonfly_monitoring_enabled: true
```

**Files to Add:**
- `templates/config/kubernetes/apps/cache/dragonfly/app/podmonitor.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/app/prometheusrule.yaml.j2`
- `templates/config/kubernetes/apps/cache/dragonfly/app/dashboard-configmap.yaml.j2`

**Estimated Effort:** 2-3 hours

### Phase 3: S3 Backup Integration

**Scope:**
- S3 snapshot configuration for RustFS
- RustFS bucket and IAM policy documentation
- Backup schedule configuration

**Prerequisites:**
- `rustfs_enabled: true`

**Configuration:**
```yaml
dragonfly_backup_enabled: true
dragonfly_s3_access_key: "<from RustFS console>"
dragonfly_s3_secret_key: "<from RustFS console>"
dragonfly_snapshot_cron: "0 */6 * * *"
```

**Estimated Effort:** 2-3 hours

### Phase 4: High Availability

**Scope:**
- Multi-replica deployment
- Pod anti-affinity
- TLS configuration (optional)

**Configuration:**
```yaml
dragonfly_replicas: 3
```

**Estimated Effort:** 1-2 hours

### Phase 5: Network Policies

**Scope:**
- CiliumNetworkPolicy for zero-trust
- Per-namespace access rules

**Prerequisites:**
- `network_policies_enabled: true`

**Files to Add:**
- `templates/config/kubernetes/apps/cache/dragonfly/app/networkpolicy.yaml.j2`

**Estimated Effort:** 1-2 hours

---

## Sources and References

### Official Documentation

- [Dragonfly Kubernetes Operator](https://www.dragonflydb.io/docs/getting-started/kubernetes-operator)
- [Install on Kubernetes with Helm Chart](https://www.dragonflydb.io/docs/getting-started/kubernetes)
- [Operator Installation](https://www.dragonflydb.io/docs/managing-dragonfly/operator/installation)
- [Dragonfly Configuration](https://www.dragonflydb.io/docs/managing-dragonfly/operator/dragonfly-configuration)
- [Authentication](https://www.dragonflydb.io/docs/managing-dragonfly/operator/authentication)
- [Snapshot to PVC](https://www.dragonflydb.io/docs/managing-dragonfly/operator/snapshot-pvc)
- [Server TLS](https://www.dragonflydb.io/docs/managing-dragonfly/operator/server-tls)
- [Prometheus Guide](https://www.dragonflydb.io/docs/managing-dragonfly/operator/prometheus-guide)
- [Grafana Guide](https://www.dragonflydb.io/docs/managing-dragonfly/operator/grafana-guide)
- [Snapshot to S3](https://www.dragonflydb.io/docs/managing-dragonfly/operator/snapshot-s3)
- [Command-Line Flags](https://www.dragonflydb.io/docs/managing-dragonfly/flags)
- [Access Control Lists (ACL)](https://www.dragonflydb.io/docs/managing-dragonfly/acl)
- [HTTP API](https://www.dragonflydb.io/docs/managing-dragonfly/using-http)

### GitHub Repositories

- [dragonflydb/dragonfly](https://github.com/dragonflydb/dragonfly) - Main Dragonfly repository
- [dragonflydb/dragonfly-operator](https://github.com/dragonflydb/dragonfly-operator) - Kubernetes Operator
- [Operator Releases](https://github.com/dragonflydb/dragonfly-operator/releases) - Version history

### Grafana Dashboards

- [Dragonfly Dashboard #21444](https://grafana.com/grafana/dashboards/21444-dragonfly-dashboard/)
- [Dragonfly Supernode #10852](https://grafana.com/grafana/dashboards/10852-dragonfly/)

### Helm Charts

- Operator: `oci://ghcr.io/dragonflydb/dragonfly-operator/helm`
- Standalone: `oci://ghcr.io/dragonflydb/dragonfly/helm/dragonfly`

---

## Appendix A: Quick Reference

### Environment Variables

| Variable | Description | Example |
| ---------- | ---------- | ---------- |
| `AWS_ACCESS_KEY_ID` | S3 access key | `dragonfly-backup` |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | `<secret>` |

### Command-Line Arguments

| Argument | Description | Default |
| ---------- | ---------- | ---------- |
| `--maxmemory` | Maximum memory | `0` (unlimited) |
| `--proactor_threads` | Worker threads | CPU count |
| `--dir` | Snapshot directory | `""` |
| `--s3_endpoint` | S3 endpoint override | AWS S3 |
| `--s3_use_https` | Use HTTPS | `true` |
| `--dbfilename` | Snapshot filename | `dump` |
| `--snapshot_cron` | Backup schedule | `""` |
| `--requirepass` | Password | `""` |

### Ports

| Port | Purpose |
| ---------- | ---------- |
| 6379 | Redis protocol |
| 9999 | Admin/metrics |
| 11211 | Memcached protocol |

### Service DNS

```
dragonfly.cache.svc.cluster.local:6379
```

---

## Appendix B: Comparison with Project Patterns

| Aspect | CNPG | RustFS | Dragonfly (Proposed) |
| ---------- | ---------- | ---------- | ---------- |
| Namespace | `cnpg-system` | `storage` | `cache` |
| Operator | HelmRelease | N/A | HelmRelease |
| Instance | Cluster CR | HelmRelease | Dragonfly CR |
| Monitoring | PodMonitor + Rules | ServiceMonitor | PodMonitor + Rules |
| Dashboard | ConfigMap | ConfigMap | ConfigMap |
| Backup | barmanObjectStore | N/A | S3 snapshot |
| Secret Pattern | SOPS | SOPS | SOPS |
| Network Policy | Yes | No | Yes (proposed) |

---

## Appendix C: Review Findings and Corrections

### Post-Research Review (January 2026)

This document was reviewed and validated against the project's established patterns using Serena MCP analysis tools. The following issues were identified and corrected:

#### Corrections Applied

1. **Missing HelmRepository Template** - Added `operator/helmrepository.yaml.j2` for OCI-based Helm chart source
2. **Missing Namespace Template** - Added complete `namespace.yaml.j2` with PodSecurity labels (baseline)
3. **Missing Kustomization Templates** - Added `kustomization.yaml.j2` for both namespace and operator directories
4. **Missing SOPS Component Reference** - Added `components: [../../components/sops]` to namespace kustomization
5. **Missing S3 Environment Variables** - Added `env` field to Dragonfly CR for AWS credentials injection
6. **Missing Operator Kustomization** - Added `operator/kustomization.yaml.j2` with resource references

#### Validation Against Project Patterns

| Pattern | Status | Notes |
| --------- | -------- | ------- |
| Cross-namespace dependencies | **Validated** | `namespace: kube-system` correctly specified for coredns |
| CRD split pattern | **Validated** | Operator and instance in separate Kustomizations with proper wait/depends |
| PodSecurity labels | **Added** | Using `baseline` level (consistent with identity namespace) |
| SOPS component | **Added** | Required for secret decryption |
| StorageClass | **N/A** | Dragonfly uses memory, no PVC needed for data |
| HelmRepository OCI type | **Added** | Using `type: oci` for ghcr.io registry |

#### Remaining Considerations

1. **API Version Stability**: The CRD uses `dragonflydb.io/v1alpha1` - monitor for beta/stable version promotion
2. **Operator Namespace**: Deploys to `dragonfly-operator-system` (upstream default), instance to `cache`
3. **RustFS Bucket Creation**: Must manually create `dragonfly-backups` bucket via RustFS Console UI
4. **Metrics Port**: Dragonfly uses port `9999` for admin/metrics (not standard Redis port)

#### Cross-Reference Verification

The following project memories were consulted:
- `flux_dependency_patterns.md` - Cross-namespace dependency and CRD split patterns
- `style_and_conventions.md` - Template delimiters and directory structure
- `task_completion_checklist.md` - Validation workflow

All templates now conform to project conventions established in January 2026.

---

## Appendix D: Second Review Enhancements (January 2026)

### Additional Documentation Reviewed

The following documentation was analyzed to enhance the integration guide:

1. **Command-Line Flags** (`https://www.dragonflydb.io/docs/managing-dragonfly/flags`)
2. **Access Control Lists** (`https://www.dragonflydb.io/docs/managing-dragonfly/acl`)
3. **HTTP API** (`https://www.dragonflydb.io/docs/managing-dragonfly/using-http`)
4. **Server TLS** (enhanced review)
5. **GitHub Monitoring Configs** (`dragonflydb/dragonfly-operator` repository)

### Enhancements Applied

| Enhancement | Section | Description |
| --------- | --------- | ------------- |
| Advanced Configuration Flags | New Section | Comprehensive table of performance, memory, persistence, and debugging flags |
| HTTP API Configuration | Advanced Flags | Admin port, HTTP control, `/metrics` auth bypass behavior |
| ACL Documentation | New Section | Complete ACL command reference, rule syntax, command categories |
| Multi-Tenant ACL Example | ACL Section | ConfigMap-based ACL for service isolation (keycloak, appcache) |
| Production Args | Dragonfly CR | Enhanced with `--admin_port`, `--primary_port_http_enabled=false`, `--cache_mode`, `--slowlog_*` |
| Cache Mode Variable | cluster.yaml | `dragonfly_cache_mode` for LRU-like eviction |
| Slow Query Variables | cluster.yaml | `dragonfly_slowlog_threshold`, `dragonfly_slowlog_max_len` |
| ACL Variables | cluster.yaml | `dragonfly_acl_enabled`, per-tenant passwords |
| Derived Variables | plugin.py | Added cache_mode, slowlog, and ACL defaults |

### Security Improvements

1. **HTTP Disabled on Data Port**: `--primary_port_http_enabled=false` prevents HTTP on port 6379
2. **Dedicated Admin Port**: Port 9999 isolated for metrics/admin access
3. **ACL Key Patterns**: Service-specific key prefixes prevent cross-tenant access
4. **Dangerous Command Denial**: ACL rules deny `@dangerous` category for non-admin users
5. **Network Policy Separation**: Data port (6379) and admin port (9999) with distinct ingress rules

### Notes

- The `/metrics` endpoint always bypasses authentication (Prometheus scraping works without credentials)
- ACL file persistence requires mounting via ConfigMap + `--aclfile` flag
- Cache mode (`--cache_mode=true`) is recommended for session storage use cases where eviction is acceptable

---

## Appendix E: Third Review - RustFS IAM and Network Policy Updates (January 2026)

### Review Context

This review was conducted to align the Dragonfly integration guide with the RustFS IAM documentation patterns established in the LiteLLM and Langfuse integration guides.

### Changes Applied

| Change | Section | Description |
| ------ | ------- | ----------- |
| **Complete RustFS IAM Setup** | S3 Backup Integration | Replaced brief bullet points with comprehensive step-by-step Console UI instructions |
| **IAM Policy Enhancement** | RustFS IAM Setup | Added `s3:GetBucketLocation` action (previously missing) |
| **IAM Architecture Summary** | RustFS IAM Setup | Added summary table matching LiteLLM/Langfuse format |
| **Network Policy Update** | Security Configuration | Updated to match actual implemented template with conditional components |
| **Langfuse Support** | Network Policy | Added `langfuse_enabled` condition for ai-system namespace ingress |

### RustFS IAM Pattern Alignment

The updated RustFS IAM section now follows the established pattern:

1. **Step-by-step instructions** via RustFS Console UI (no `mc admin` commands)
2. **Clear bucket, policy, group, user hierarchy**
3. **IAM Architecture Summary table** for quick reference
4. **SOPS encryption reminder** for credentials

### Network Policy Enhancements

The CiliumNetworkPolicy now includes:

1. **Audit/Enforce mode toggle** via `network_policies_mode`
2. **Conditional ingress rules** for each component:
   - Keycloak (`keycloak_enabled`)
   - LiteLLM/Langfuse (`litellm_enabled` OR `langfuse_enabled`)
   - Default namespace (always)
   - Monitoring (`monitoring_enabled`)
3. **Conditional egress** for RustFS backups (`dragonfly_backup_enabled`)

### Implementation Verification

All template files were cross-referenced against the codebase:

| Template | Status | Location |
| -------- | ------ | -------- |
| `networkpolicy.yaml.j2` | ✅ Updated | `templates/config/kubernetes/apps/cache/dragonfly/app/` |
| `acl-configmap.yaml.j2` | ✅ Verified | Includes LiteLLM and Langfuse users |
| `secret.sops.yaml.j2` | ✅ Verified | S3 credentials for RustFS backup |
| `dragonfly-cr.yaml.j2` | ✅ Verified | S3 endpoint and credentials configured |

### Remaining Manual Steps

1. **Create `dragonfly-backups` bucket** via RustFS Console UI
2. **Create `dragonfly-storage` policy** with provided JSON
3. **Create `cache` group** or add policy to existing group
4. **Create `dragonfly-backup` user** and generate access key
5. **Update cluster.yaml** with SOPS-encrypted credentials
