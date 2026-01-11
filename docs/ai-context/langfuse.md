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
│         │                │                     │            │
│         └────────┬───────┴─────────────────────┘            │
│                  │                                          │
│  ┌───────────────▼───────────────────────────────────────┐  │
│  │               CloudNativePG PostgreSQL                │  │
│  │            langfuse-postgresql (Port 5432)            │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           │
        Cross-namespace connections (ACL: langfuse user)
                           │
┌──────────────────────────▼────────────────────────────────────┐
│                      Shared Infrastructure                    │
├───────────────────────────────────────────────────────────────┤
│  cache/dragonfly        storage/rustfs       identity/keycloak│
│  (Redis-compatible)     (S3-compatible)      (OIDC SSO)       │
│  Port 6379              Port 9000            Port 8080        │
└───────────────────────────────────────────────────────────────┘
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

**Password Rotation:** Uses CNPG managed roles with automatic sync. Update `langfuse_postgres_password` in `cluster.yaml`, run `task configure && task reconcile`. Pods restart via Reloader annotation. See: `docs/research/cnpg-managed-roles-password-rotation-jan-2026.md`

### ClickHouse Analytics
```yaml
langfuse_clickhouse_password: "..."   # SOPS-encrypted
langfuse_clickhouse_storage: "20Gi"
```

### S3 Storage (RustFS)
```yaml
langfuse_s3_access_key: ""      # Create via RustFS Console
langfuse_s3_secret_key: ""      # SOPS-encrypted

# Required buckets (created by RustFS setup job):
# - langfuse-events (raw event storage)
# - langfuse-media (multi-modal uploads)
# - langfuse-exports (batch data exports)
# - langfuse-postgres-backups (if backup enabled)
```

#### RustFS IAM Setup (Principle of Least Privilege)

> All user/policy operations must be performed via the **RustFS Console UI** (port 9001).
> The RustFS bucket setup job automatically creates the required buckets.

**1. Create Custom Policy**

Navigate to **Identity** → **Policies** → **Create Policy**

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
        "arn:aws:s3:::langfuse-exports"
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
        "arn:aws:s3:::langfuse-exports/*"
      ]
    }
  ]
}
```

| Permission | Purpose |
| ---------- | ------- |
| `s3:ListBucket` | List events, media files, exports |
| `s3:GetObject` | Download media files, exports |
| `s3:PutObject` | Upload events, media, exports |
| `s3:DeleteObject` | Retention cleanup |
| `s3:GetBucketLocation` | AWS SDK compatibility |

**2. Create Group (or use existing `ai-system` group)**

Navigate to **Identity** → **Groups** → **Create Group**

- **Name:** `ai-system` (shared with LiteLLM, Obot)
- **Assign Policy:** `langfuse-storage` (add to existing policies if group exists)
- Click **Save**

**3. Create Langfuse S3 User**

Navigate to **Identity** → **Users** → **Create User**

- **Access Key:** (auto-generated, copy this)
- **Secret Key:** (auto-generated, copy this)
- **Assign Group:** `ai-system`
- Click **Save**

**4. Update cluster.yaml**

```yaml
langfuse_s3_access_key: "<paste-access-key>"
langfuse_s3_secret_key: "<paste-secret-key>"
```

Then run: `task configure && task reconcile`

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

### Cookie Domain Isolation
Langfuse automatically sets `NEXTAUTH_COOKIE_DOMAIN` to the Langfuse hostname to prevent
session cookie collision with Gateway OIDC protected apps (Hubble, RustFS, etc.) on the
same parent domain.

This is **automatically configured** - no user action required.

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
langfuse_backup_s3_access_key: ""   # Create via RustFS Console
langfuse_backup_s3_secret_key: ""   # SOPS-encrypted
# Required bucket: langfuse-postgres-backups (created by RustFS setup job)
```

#### RustFS IAM Setup for PostgreSQL Backups

> Separate user for PostgreSQL backups provides better security isolation.

**1. Create Backup Policy**

Navigate to **Identity** → **Policies** → **Create Policy**

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
        "arn:aws:s3:::langfuse-postgres-backups"
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
        "arn:aws:s3:::langfuse-postgres-backups/*"
      ]
    }
  ]
}
```

**2. Create Langfuse Backup User**

Navigate to **Identity** → **Users** → **Create User**

- **Access Key:** (auto-generated, copy this)
- **Secret Key:** (auto-generated, copy this)
- **Assign Group:** `ai-system` (add `langfuse-backup-storage` policy to group)
- Click **Save**

**3. Update cluster.yaml**

```yaml
langfuse_backup_s3_access_key: "<paste-access-key>"
langfuse_backup_s3_secret_key: "<paste-secret-key>"
```

Then run: `task configure && task reconcile`

### Headless Initialization (GitOps Bootstrap)
Bootstrap an initial admin account for GitOps/non-interactive deployments.
When both email and password are configured, Langfuse auto-creates the admin
on first startup (idempotent - only creates if not exists).

```yaml
# Initial Admin Account (SOPS-encrypted)
langfuse_init_user_email: "admin@example.com"
langfuse_init_user_password: "..."   # min 16 chars, generate: openssl rand -base64 24
langfuse_init_user_name: "Admin"     # Display name
langfuse_init_org_name: "MyOrg"      # Initial organization

# Security Hardening
langfuse_disable_signup: false       # MUST be false when using SSO!
```

> **CRITICAL SSO WARNING:** When `langfuse_sso_enabled: true`, you MUST set `langfuse_disable_signup: false`.
> Setting both to `true` causes `OAuthCreateAccount` errors because NextAuth.js cannot create
> accounts for new SSO users. The `disable_signup` setting blocks ALL new user creation, including SSO.
> See: `docs/research/langfuse-keycloak-sso-validation-jan-2026.md`

REF: https://langfuse.com/self-hosting/headless-initialization

### Auto-Provisioning (SSO Default Roles)
Configure default roles for users created via SSO (Keycloak OIDC).
These apply when a user logs in via SSO for the first time.

```yaml
langfuse_default_org_role: "VIEWER"      # OWNER|ADMIN|MEMBER|VIEWER|NONE
langfuse_default_project_role: "VIEWER"  # OWNER|ADMIN|MEMBER|VIEWER
```

- **NONE** = user must be explicitly invited to organizations
- Other roles provide that level of access to the default organization

REF: https://langfuse.com/self-hosting/automated-provisioning

### SCIM Role Sync (Keycloak → Langfuse)
Synchronize Keycloak realm roles to Langfuse organization roles via CronJob.
This enables role-based access control where Keycloak is the source of truth.

```yaml
langfuse_scim_sync_enabled: true
langfuse_scim_sync_schedule: "*/5 * * * *"  # Every 5 minutes

# Langfuse SCIM API credentials (org-scoped API keys)
langfuse_scim_public_key: "lf_pk_..."      # SOPS-encrypted
langfuse_scim_secret_key: "lf_sk_..."      # SOPS-encrypted

# Keycloak service account for Admin API access
langfuse_sync_keycloak_client_id: "langfuse-sync"
langfuse_sync_keycloak_client_secret: "..."  # SOPS-encrypted

# Role mapping: Keycloak realm role → Langfuse org role
langfuse_role_mapping:
  admin: "ADMIN"           # Keycloak 'admin' → Langfuse ADMIN
  langfuse-admin: "ADMIN"  # Alternative admin role
  operator: "MEMBER"       # Keycloak 'operator' → Langfuse MEMBER
  langfuse-member: "MEMBER"
  developer: "MEMBER"
  default: "VIEWER"        # Fallback for unmapped roles
```

**Requirements:**
- `keycloak_enabled: true` - Keycloak as identity provider
- `langfuse_sso_enabled: true` - SSO must be enabled
- Keycloak service account with `view-users` and `view-realm` roles

**Architecture:**
```
┌─────────────────┐     ┌──────────────────────┐     ┌────────────────┐
│    Keycloak     │────▶│   langfuse-sync      │────▶│    Langfuse    │
│  (Admin API)    │     │    (CronJob)         │     │   (SCIM API)   │
│                 │     │   Every 5 mins       │     │                │
│  - Users        │     │   - Fetch KC users   │     │  - Update      │
│  - Realm roles  │     │   - Map roles        │     │    org roles   │
└─────────────────┘     │   - PATCH via SCIM   │     └────────────────┘
                        └──────────────────────┘
```

**Files Generated:**
- `sync-cronjob.yaml.j2` - Kubernetes CronJob definition
- `sync-secret.sops.yaml.j2` - SOPS-encrypted API credentials
- `sync-configmap.yaml.j2` - Role mapping config + Python sync script

REF: https://langfuse.com/docs/integrations/scim

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
    ├── referencegrant.yaml.j2  # Allow network namespace HTTPRoute access
    ├── networkpolicy.yaml.j2   # Cilium NetworkPolicy
    ├── servicemonitor.yaml.j2  # Prometheus scraping
    ├── sync-cronjob.yaml.j2    # SCIM role sync CronJob (if scim_sync_enabled)
    ├── sync-secret.sops.yaml.j2    # SCIM sync credentials (if scim_sync_enabled)
    └── sync-configmap.yaml.j2  # Role mapping + Python sync script (if scim_sync_enabled)

# HTTPRoute is centralized in:
# templates/config/kubernetes/apps/network/envoy-gateway/app/httproutes.yaml.j2
# - Uses both envoy-internal and envoy-external gateways (split-horizon DNS)
# - No OIDC protection (Langfuse uses native SSO via AUTH_KEYCLOAK_* env vars)
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
- Check pod can reach internal Keycloak: `kubectl exec -n ai-system <pod> -- wget -qO- http://keycloak-service.identity.svc.cluster.local:8080/realms/matherlynet/.well-known/openid-configuration`

**OAuthCreateAccount Error:** If clicking "Login with Keycloak" returns `OAuthCreateAccount - Contact support if this error is unexpected`:
- **Root cause:** `langfuse_disable_signup: true` is blocking SSO user creation
- **Fix:** Set `langfuse_disable_signup: false` in cluster.yaml, then `task configure && task reconcile`
- **Why:** The `disable_signup` setting blocks ALL new users, including SSO users logging in for the first time
- **Note:** This is secure because `langfuse_disable_password_auth: true` still hides the password form; only SSO is available
- **REF:** `docs/research/langfuse-keycloak-sso-validation-jan-2026.md`

**Split-horizon DNS Issue**: If external Keycloak URL times out from pods (UniFi DNS resolves to LAN IP), the solution is already implemented - Langfuse uses `keycloak_internal_issuer_url` for OIDC discovery. Keycloak's `backchannelDynamic: true` returns external URLs for browser redirects and internal URLs for server-to-server token/userinfo calls.

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

### SCIM Role Sync Issues
If roles are not syncing from Keycloak:
- Check CronJob status: `kubectl get cronjobs -n ai-system -l app.kubernetes.io/name=langfuse-role-sync`
- View recent job logs: `kubectl logs -n ai-system -l job-name=langfuse-role-sync-* --tail=100`
- Verify Keycloak service account has required roles: `view-users`, `view-realm` on `realm-management` client
- Check SCIM API credentials are correct: `kubectl get secret -n ai-system langfuse-sync-credentials`
- Verify role mapping in ConfigMap: `kubectl get configmap -n ai-system langfuse-sync-config -o yaml`
- Test Keycloak connectivity from pod: `kubectl exec -n ai-system <pod> -- wget -qO- http://keycloak-service.identity.svc.cluster.local:8080/admin/realms/matherlynet/users`

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
- `langfuse_scim_sync_enabled` - true when keycloak + scim_sync_enabled + all credentials set
