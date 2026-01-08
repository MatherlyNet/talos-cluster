# Langfuse LLM Observability Configuration

## Overview

Langfuse is an open-source LLM observability platform providing tracing, prompt management, evaluation, and cost analytics. It enables:
- End-to-end LLM call tracing with latency, tokens, and cost
- Prompt version control, A/B testing, and experiments
- LLM-as-a-Judge and human annotation evaluation
- Usage patterns, cost analysis, and performance metrics
- Interactive LLM testing playground

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ai-system namespace                  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │langfuse-web │  │langfuse-    │  │     ClickHouse      │  │
│  │  (Next.js)  │  │   worker    │  │   (analytics DB)    │  │
│  │  Port 3000  │  │ Port 3030   │  │  Ports 8123, 9000   │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────┘  │
│         │                │                      │            │
│         └────────┬───────┴──────────────────────┘            │
│                  │                                           │
│  ┌───────────────▼───────────────────────────────────────┐  │
│  │               CloudNativePG PostgreSQL                │  │
│  │            langfuse-postgresql (Port 5432)            │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           │
        Cross-namespace connections (ACL: langfuse user)
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                      Shared Infrastructure                   │
├─────────────────────────────────────────────────────────────┤
│  cache/dragonfly        storage/rustfs       identity/keycloak│
│  (Redis-compatible)     (S3-compatible)      (OIDC SSO)       │
│  Port 6379              Port 9000            Port 8080        │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Variables

### Enable/Disable
```yaml
langfuse_enabled: true         # Enable Langfuse deployment
langfuse_subdomain: "langfuse" # Creates langfuse.${cloudflare_domain}
```

### Security Keys (SOPS-encrypted)
```yaml
langfuse_nextauth_secret: "..."    # Session secret (min 32 chars)
langfuse_salt: "..."               # API key hashing salt (min 32 chars)
langfuse_encryption_key: "..."     # AES-256 key (64 hex chars)
```

Generate with:
```bash
openssl rand -base64 32  # nextauth_secret, salt
openssl rand -hex 32     # encryption_key
```

### PostgreSQL Database (CNPG)
```yaml
langfuse_postgres_password: "..."  # SOPS-encrypted
langfuse_postgres_instances: 1     # 1 for dev, 3+ for HA
langfuse_postgres_storage: "10Gi"
```

### ClickHouse Analytics
```yaml
langfuse_clickhouse_password: "..."   # SOPS-encrypted
langfuse_clickhouse_storage: "20Gi"
```

### S3 Storage (RustFS)
```yaml
langfuse_s3_access_key: ""      # Create via RustFS Console
langfuse_s3_secret_key: ""      # SOPS-encrypted

# Required buckets (create via RustFS Console):
# - langfuse-events (raw event storage)
# - langfuse-media (multi-modal uploads)
# - langfuse-exports (batch data exports)
# - langfuse-postgres-backups (if backup enabled)
```

### Dragonfly Cache (Shared)
Langfuse uses the shared Dragonfly deployment in the `cache` namespace.

```yaml
dragonfly_enabled: true            # Enable shared Dragonfly
dragonfly_acl_enabled: true        # Enable ACL for multi-tenant access
dragonfly_langfuse_password: "..." # SOPS-encrypted, ACL user password
```

Connection: `dragonfly.cache.svc.cluster.local:6379`
- **User:** `langfuse` (ACL-authenticated)
- **Key prefix:** `langfuse:*` (namespace isolation via ACL)

### SSO Authentication (requires keycloak_enabled)
```yaml
langfuse_sso_enabled: true
langfuse_keycloak_client_secret: "..."  # SOPS-encrypted
```

### Observability
```yaml
# OpenTelemetry Tracing (requires tracing_enabled)
langfuse_tracing_enabled: true
langfuse_trace_sampling_ratio: "0.1"  # 10% sampling

# Prometheus Monitoring (requires monitoring_enabled)
langfuse_monitoring_enabled: true     # ServiceMonitor + Dashboard
```

### Backups (requires rustfs_enabled)
```yaml
langfuse_backup_enabled: true
# Uses langfuse S3 credentials for CNPG barmanObjectStore
```

## File Structure

```
templates/config/kubernetes/apps/ai-system/langfuse/
├── ks.yaml.j2                  # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── helmrepository.yaml.j2  # langfuse/langfuse-k8s
    ├── helmrelease.yaml.j2     # Langfuse Helm chart
    ├── postgresql.yaml.j2      # CloudNativePG Cluster + Database
    ├── secret.sops.yaml.j2     # Encrypted credentials
    ├── httproute.yaml.j2       # Gateway API routing
    ├── networkpolicy.yaml.j2   # Cilium NetworkPolicy
    └── servicemonitor.yaml.j2  # Prometheus scraping
```

## LiteLLM Integration

### Callback Configuration
Langfuse integrates with LiteLLM as a callback for automatic trace collection:

```yaml
# In LiteLLM config.yaml
litellm_settings:
  callbacks:
    - langfuse

environment_variables:
  LANGFUSE_PUBLIC_KEY: "pk-lf-..."
  LANGFUSE_SECRET_KEY: "sk-lf-..."
  LANGFUSE_HOST: "http://langfuse-web.ai-system.svc.cluster.local:3000"
```

### Trace Data Collected
- Model name and provider
- Token usage and latency
- Request/response payloads
- Cost calculations
- Metadata and tags

### LLM Connections in Langfuse
Configure via Project Settings > LLM Connections for:
- Playground testing
- LLM-as-a-Judge evaluation
- Prompt experiments

Point to LiteLLM proxy:
- Base URL: `http://litellm.ai-system.svc.cluster.local:4000`

## Keycloak OIDC Integration

### Client Configuration
When `langfuse_sso_enabled: true`, a Keycloak client is created:

```yaml
clientId: langfuse
redirectUris:
  - "https://langfuse.${cloudflare_domain}/api/auth/callback/keycloak"
webOrigins:
  - "https://langfuse.${cloudflare_domain}"
```

### Account Linking
Langfuse supports merging accounts with the same email:
- Existing email-based users are linked to Keycloak identity
- Set `AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING=true`

## Health Check Endpoints

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

readinessProbe:
  httpGet:
    path: /api/public/ready
    port: 3000
  initialDelaySeconds: 10
```

## Testing

```bash
# Check pods
kubectl get pods -n ai-system -l app.kubernetes.io/name=langfuse

# Check health
kubectl port-forward -n ai-system svc/langfuse-web 3000:3000
curl http://localhost:3000/api/public/health
curl http://localhost:3000/api/public/ready

# Check ClickHouse
kubectl exec -n ai-system -it langfuse-clickhouse-0 -- \
  clickhouse-client --query "SELECT count() FROM traces"

# Access via HTTPRoute
https://langfuse.<domain>/
```

## Troubleshooting

### Web Pod CrashLoopBackOff
If langfuse-web crashes on startup:
- Verify PostgreSQL is ready: `kubectl get clusters -n ai-system`
- Verify ClickHouse is ready: `kubectl get pods -n ai-system -l app.kubernetes.io/name=clickhouse`
- Check secrets are mounted: `kubectl exec -n ai-system <pod> -- env | grep NEXTAUTH`

### Worker Not Processing Events
If events are not appearing in traces:
- Check Redis connection: `kubectl logs -n ai-system -l app.kubernetes.io/component=worker`
- Verify Dragonfly is accessible from ai-system namespace
- Check ACL permissions if `dragonfly_acl_enabled: true`

### ClickHouse Query Timeouts
If analytics are slow:
- Check ClickHouse memory: `kubectl top pods -n ai-system -l app.kubernetes.io/name=clickhouse`
- Increase ClickHouse resources in HelmRelease values
- Verify storage performance (NVMe recommended)

### SSO Login Fails
If Keycloak redirect fails:
- Verify Keycloak is healthy: `kubectl get keycloak -n identity`
- Check client secret matches: `langfuse_keycloak_client_secret`
- Verify redirect URI in Keycloak client configuration

### Traces Not Appearing from LiteLLM
If LiteLLM callbacks are not working:
- Verify Langfuse host is reachable from LiteLLM pod
- Check public/secret keys match Langfuse project
- Verify network policies allow ai-system→ai-system traffic

### S3 Upload Failures
If event uploads fail:
- Verify RustFS buckets exist (langfuse-events, langfuse-media, langfuse-exports)
- Check S3 credentials: `kubectl get secret -n ai-system langfuse-s3-credentials`
- Verify `LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE: "true"` is set

## NetworkPolicy Considerations

Langfuse requires egress to multiple services:

| Destination | Namespace | Port | Purpose |
| ----------- | --------- | ---- | ------- |
| PostgreSQL | ai-system | 5432 | Transactional data |
| ClickHouse | ai-system | 8123, 9000 | Analytics |
| Dragonfly | cache | 6379 | Queue + cache |
| RustFS | storage | 9000 | Blob storage |
| Keycloak | identity | 8080 | OIDC (if SSO) |
| Tempo | monitoring | 4318 | OTEL traces (if tracing) |

When `network_policies_enabled: true`:
- CiliumNetworkPolicy allows required egress
- Labels added for Kubernetes API access if needed

## Dependencies

- **CloudNativePG** (`cnpg_enabled: true`): PostgreSQL database for transactional data
- **Dragonfly** (`dragonfly_enabled: true`, `dragonfly_acl_enabled: true`): Shared Redis-compatible cache
- **RustFS** (`rustfs_enabled: true`): S3-compatible blob storage for events and media
- **ClickHouse**: Bundled analytics database (managed by Helm chart)
- **Envoy Gateway**: HTTPRoute support for external access via Gateway API
- **Keycloak** (`keycloak_enabled`): OIDC authentication (optional)
- **Prometheus/Grafana** (`monitoring_enabled`): Metrics and dashboards
- **Tempo** (`tracing_enabled`): Self-observability via OpenTelemetry
- **SOPS/Age**: Secret encryption for credentials

## Quick Reference

### Service DNS Names
| Service | DNS | Port |
| ------- | --- | ---- |
| Web UI/API | `langfuse-web.ai-system.svc.cluster.local` | 3000 |
| Worker | `langfuse-worker.ai-system.svc.cluster.local` | 3030 |
| PostgreSQL | `langfuse-postgresql-rw.ai-system.svc.cluster.local` | 5432 |
| ClickHouse | `langfuse-clickhouse.ai-system.svc.cluster.local` | 8123, 9000 |

### Derived Variables (computed in plugin.py)
- `langfuse_hostname` - `${langfuse_subdomain}.${cloudflare_domain}`
- `langfuse_url` - `https://${langfuse_hostname}`
- `langfuse_sso_enabled` - true when keycloak + sso flag + client secret
- `langfuse_backup_enabled` - true when rustfs + backup flag + S3 credentials
- `langfuse_monitoring_enabled` - true when monitoring + langfuse_monitoring_enabled
- `langfuse_tracing_enabled` - true when tracing + langfuse_tracing_enabled
