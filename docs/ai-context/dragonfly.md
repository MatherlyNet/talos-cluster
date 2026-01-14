# Dragonfly Cache Configuration

## Overview

Dragonfly is a Redis-compatible in-memory data store deployed via the Dragonfly Operator. It provides:
- 25x better performance than Redis with full API compatibility
- Multi-threaded architecture with optimized memory usage
- Shared cache infrastructure for cluster services (Keycloak, LiteLLM, Langfuse)
- ACL-based multi-tenant access control with per-application credentials
- S3 snapshots to RustFS for persistence
- Prometheus monitoring with Grafana dashboards

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 dragonfly-operator-system namespace         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │           Dragonfly Operator (HelmRelease)          │    │
│  │    Manages Dragonfly CR lifecycle and upgrades      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ manages
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        cache namespace                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Dragonfly Instance (CR)                │    │
│  │         Redis-compatible, 25x faster than Redis     │    │
│  │                     Port 6379                       │    │
│  │               Admin/Metrics: 9999                   │    │
│  └──────────────────────┬──────────────────────────────┘    │
│                         │                                   │
│  ┌──────────────────────┴──────────────────────────────┐    │
│  │                   ACL Users                         │    │
│  │  default    ~*           Full access                │    │
│  │  keycloak   ~keycloak:*  Keycloak sessions          │    │
│  │  appcache   ~cache:*     General app cache          │    │
│  │  litellm    ~litellm:*   LiteLLM responses          │    │
│  │  langfuse   ~*           Langfuse (BullMQ queues)   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Cross-namespace connections
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  identity/keycloak    ai-system/litellm   ai-system/langfuse│
│  (keycloak:* keys)    (litellm:* keys)    (all keys)        │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Variables

### Core Settings
```yaml
dragonfly_enabled: true           # Enable Dragonfly deployment
dragonfly_version: "v1.36.0"      # Dragonfly server version
dragonfly_operator_version: "1.3.1" # Operator Helm chart version
dragonfly_replicas: 1             # 1=standalone, 2+=HA with replication
dragonfly_password: "..."         # SOPS-encrypted default password
```

### Resource Configuration
```yaml
dragonfly_maxmemory: "512mb"      # Maximum memory allocation
dragonfly_threads: 2              # Proactor threads (match CPU cores)
dragonfly_cpu_request: "100m"     # CPU request
dragonfly_memory_request: "256Mi" # Memory request
dragonfly_memory_limit: "1Gi"     # Memory limit
dragonfly_control_plane_only: false # Schedule on control-plane nodes
```

### Performance Tuning
```yaml
dragonfly_cache_mode: true        # Enable LRU eviction (recommended for caching)
dragonfly_slowlog_threshold: 10000 # Slow query log threshold (microseconds)
dragonfly_slowlog_max_len: 128    # Maximum slow queries to retain
```

### S3 Backups (requires RustFS)
```yaml
dragonfly_backup_enabled: true
dragonfly_s3_endpoint: "rustfs-svc.storage.svc.cluster.local:9000"
dragonfly_s3_access_key: "dragonfly-backup"  # Created via RustFS Console
dragonfly_s3_secret_key: "..."                # SOPS-encrypted
dragonfly_snapshot_cron: "0 */6 * * *"        # Every 6 hours
# Required bucket: dragonfly-backups (created by RustFS setup job)
```

#### RustFS IAM Setup

**Bucket:** `dragonfly-backups` (auto-created by RustFS setup job)

**Required S3 Permissions:**
- `s3:ListBucket`, `s3:GetBucketLocation` - Browse snapshots
- `s3:GetObject` - Download snapshots for restore
- `s3:PutObject` - Upload RDB snapshots
- `s3:DeleteObject` - Retention cleanup

**Setup Procedure:**

See [RustFS IAM Setup Pattern](./patterns/rustfs-iam-setup.md) for complete Console UI procedure including:
1. Creating `dragonfly-storage` policy scoped to `dragonfly-backups`
2. Creating service account user
3. Updating `cluster.yaml` with `dragonfly_s3_access_key` and `dragonfly_s3_secret_key`
4. Verifying S3 connectivity

### Monitoring (requires monitoring_enabled)
```yaml
dragonfly_monitoring_enabled: true  # Deploy PodMonitor + PrometheusRule + Dashboard
```

### ACL Multi-Tenant Access
```yaml
dragonfly_acl_enabled: true
dragonfly_keycloak_password: "..."  # SOPS-encrypted, Keycloak sessions
dragonfly_appcache_password: "..."  # SOPS-encrypted, general app cache
dragonfly_litellm_password: "..."   # SOPS-encrypted, LiteLLM cache
dragonfly_langfuse_password: "..."  # SOPS-encrypted, Langfuse queues
```

For complete ACL configuration with key namespace isolation and testing procedures, see [Dragonfly ACL Configuration Pattern](./patterns/dragonfly-acl-configuration.md).

## Derived Variables

These are computed in `templates/scripts/plugin.py`:

| Variable | Logic |
| ---------- | ------- |
| `dragonfly_enabled` | `true` when explicitly set |
| `dragonfly_backup_enabled` | `true` when rustfs_enabled + dragonfly_backup_enabled + S3 credentials all set |
| `dragonfly_monitoring_enabled` | `true` when monitoring_enabled + dragonfly_monitoring_enabled both true |
| `dragonfly_acl_enabled` | `true` when explicitly set |

## Template Structure

```
templates/config/kubernetes/apps/cache/
├── kustomization.yaml.j2           # Namespace-level kustomization
├── namespace.yaml.j2               # cache namespace with labels
└── dragonfly/
    ├── ks.yaml.j2                  # Flux Kustomization (operator → instance)
    ├── operator/
    │   ├── kustomization.yaml.j2
    │   ├── namespace.yaml.j2       # dragonfly-operator-system
    │   ├── helmrepository.yaml.j2  # OCI registry
    │   └── helmrelease.yaml.j2     # Operator deployment
    └── app/
        ├── kustomization.yaml.j2
        ├── dragonfly-cr.yaml.j2    # Dragonfly custom resource
        ├── secret.sops.yaml.j2     # Password + ACL configuration
        ├── podmonitor.yaml.j2      # Prometheus scraping (conditional)
        ├── prometheusrule.yaml.j2  # Alert rules (conditional)
        ├── dashboard-configmap.yaml.j2  # Grafana dashboard (conditional)
        └── networkpolicy.yaml.j2   # CiliumNetworkPolicy (conditional)
```

## Key Implementation Details

### CRD Split Pattern
The deployment uses a two-phase Flux Kustomization pattern:
1. **Operator Kustomization**: Deploys Dragonfly Operator with CRDs
2. **Instance Kustomization**: Creates Dragonfly CR after operator is ready

```yaml
# ks.yaml.j2 - dependsOn ensures proper ordering
dependsOn:
  - name: coredns
    namespace: kube-system
  - name: dragonfly-operator
    namespace: cache
```

### ACL Configuration
ACL is implemented via `aclFromSecret` CRD field (not ConfigMap):
- More secure: passwords in Secret, not ConfigMap
- Cleaner: uses official Dragonfly CRD pattern
- Per-tenant isolation via key pattern restrictions

### BullMQ Compatibility
For Langfuse integration, special flags are enabled:
```yaml
args:
  - "--default_lua_flags=allow-undeclared-keys"  # BullMQ compatibility
```

Langfuse ACL user has broader permissions (`~* +@all -@dangerous +INFO +CONFIG`) for BullMQ job queues.

### Memory Management
When `dragonfly_cache_mode: true`:
- Enables LRU-like eviction when approaching maxmemory
- Recommended for session storage and caching use cases
- NOT recommended for persistent data

## Service Discovery

Applications connect via:
```
dragonfly.cache.svc.cluster.local:6379
```

With ACL authentication:
```
redis://:<password>@dragonfly.cache.svc.cluster.local:6379
```

Or with username (ACL mode):
```
redis://<username>:<password>@dragonfly.cache.svc.cluster.local:6379
```

## Network Policies

When `network_policies_enabled: true`, the following ingress is allowed:
- **identity** namespace (Keycloak) → port 6379
- **ai-system** namespace (LiteLLM, Langfuse) → port 6379
- **default** namespace → port 6379
- **monitoring** namespace → port 9999 (metrics)

Egress allowed:
- DNS (kube-dns) → port 53
- RustFS (backup) → port 9000 (conditional on backup_enabled)

## Prometheus Alerts

When `dragonfly_monitoring_enabled: true`, these alerts are deployed:

| Alert | Condition | Severity |
| ------- | ----------- | ---------- |
| DragonflyDown | Instance unreachable | critical |
| DragonflyMemoryHigh | Memory >90% of maxmemory | warning |
| DragonflyConnectionsHigh | >1000 connections | warning |
| DragonflyReplicationLag | Replica lag >10s | warning |
| DragonflyEvictionsHigh | >100 evictions/5min | warning |

## Troubleshooting

### Common Commands
```bash
# Operator status
kubectl get pods -n dragonfly-operator-system
kubectl logs -n dragonfly-operator-system -l app.kubernetes.io/name=dragonfly-operator

# Instance status
kubectl get dragonfly -n cache
kubectl describe dragonfly dragonfly -n cache
kubectl -n cache logs -l app=dragonfly

# Connectivity test
kubectl -n cache exec -it dragonfly-0 -- redis-cli -a $PASSWORD ping

# ACL users
kubectl -n cache exec -it dragonfly-0 -- redis-cli -a $PASSWORD ACL LIST

# Memory info
kubectl -n cache exec -it dragonfly-0 -- redis-cli -a $PASSWORD INFO memory

# Slow queries
kubectl -n cache exec -it dragonfly-0 -- redis-cli -a $PASSWORD SLOWLOG GET 10
```

### Decision Tree

```
Dragonfly Not Ready?
├── Check Operator: kubectl get pods -n dragonfly-operator-system
│   └── CrashLoopBackOff → Check operator logs, CRD issues
├── Check CR Status: kubectl get dragonfly -n cache
│   ├── "PasswordSecretNotFound" → Check secret exists
│   └── "InsufficientResources" → Adjust resource limits
└── Check Pods: kubectl -n cache get pods -l app=dragonfly
    ├── Pending → Check PVC, node scheduling
    └── Running but not Ready → Check readiness probe logs
```

### Authentication Issues
```
Error: WRONGPASS / NOAUTH
├── Verify ACL enabled: dragonfly_acl_enabled: true
├── Check user exists: redis-cli ACL LIST
├── Check key pattern: User may not have access to keys
└── Check password: Compare secret with configured password
```

### Memory Pressure
```
High Memory Usage / Evictions
├── Check cache_mode: dragonfly_cache_mode: true for eviction
├── Increase maxmemory: dragonfly_maxmemory: "1gb"
├── Review key patterns: redis-cli --bigkeys
└── Check eviction policy: MEMORY DOCTOR
```

## Integration Points

| Application | Namespace | ACL User | Key Pattern | Purpose |
| ------------- | ----------- | ---------- | ------------- | --------- |
| Keycloak | identity | keycloak | `keycloak:*` | Session storage, SSO state |
| LiteLLM | ai-system | litellm | `litellm:*` | Response cache |
| Langfuse | ai-system | langfuse | `*` (all) | BullMQ job queues, caching |
| Apps | default | appcache | `cache:*` | General application cache |

## Dependencies

- **Dragonfly Operator** (`dragonfly_enabled: true`): Core requirement
- **RustFS** (`rustfs_enabled: true`): Required for S3 backups
- **Monitoring** (`monitoring_enabled: true`): Required for PodMonitor/dashboards
- **Network Policies** (`network_policies_enabled: true`): Enables CiliumNetworkPolicy

## Reference

- Implementation Guide: `docs/research/archive/completed/dragonfly-redis-alternative-integration-jan-2026.md`
- Validation Report: `docs/research/dragonfly-implementation-validation-jan-2026.md`
- Dragonfly Docs: https://www.dragonflydb.io/docs
- Operator Docs: https://www.dragonflydb.io/docs/getting-started/kubernetes-operator

---

**Last Updated:** January 13, 2026
**Dragonfly Version:** v1.36.0
**Operator Version:** 1.3.1 (Helm chart)
**Default Memory:** 512mb
**Performance:** 25x faster than Redis with full API compatibility
