# Obot MCP Gateway Configuration

## Overview

Obot is an AI agent platform with Model Context Protocol (MCP) server hosting capabilities. It enables:
- Building and deploying AI agents with tool integrations
- Hosting MCP servers in isolated Kubernetes namespaces
- Keycloak SSO authentication via custom auth provider
- LiteLLM integration for unified AI model access

**Fork:** Uses `jrmatherly/obot-entraid` fork with Keycloak auth provider support.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ai-system namespace                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────────────────────┐   │
│  │      Obot       │  │    CloudNativePG PostgreSQL     │   │
│  │  (jrmatherly/   │  │      obot-postgresql            │   │
│  │  obot-entraid)  │  │   (pgvector for embeddings)     │   │
│  │   Port 8080     │  │        Port 5432                │   │
│  └────────┬────────┘  └─────────────────────────────────┘   │
│           │                                                 │
│           │     ┌────────────────────────────────────┐      │
│           └────►│         Shared Infrastructure      │      │
│                 │  cache/dragonfly, identity/keycloak│      │
│                 │       ai-system/litellm            │      │
│                 └────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
                                │
                    MCP Server Orchestration
                                │
┌───────────────────────────────▼─────────────────────────────┐
│                      obot-mcp namespace                     │
├─────────────────────────────────────────────────────────────┤
│  ResourceQuota: 4 CPU req, 8 CPU limit, 8Gi/16Gi memory     │
│  LimitRange: 100m-500m CPU, 256Mi-512Mi memory per pod      │
│  Pod Security: restricted (runAsNonRoot, seccomp, etc.)     │
│  NetworkPolicy: Obot-only ingress, DNS-only egress          │
│                                                             │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ MCP     │  │ MCP     │  │ MCP     │  │  ...    │         │
│  │ Server 1│  │ Server 2│  │ Server 3│  │(max 20) │         │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Variables

### Enable/Disable
```yaml
obot_enabled: true           # Enable Obot deployment
obot_subdomain: "obot"       # Creates obot.${cloudflare_domain}
obot_version: "0.2.33"       # jrmatherly/obot-entraid image tag
obot_replicas: 1             # Pod replicas
```

### Database (CloudNativePG with pgvector)
```yaml
obot_db_password: "..."            # SOPS-encrypted PostgreSQL password
obot_postgres_user: "obot"         # Database username
obot_postgres_db: "obot"           # Database name
obot_postgresql_replicas: 1        # PostgreSQL instances
obot_postgresql_storage_size: "10Gi"
obot_storage_size: "20Gi"          # Workspace PVC size
```

**Password Rotation:** Uses CNPG managed roles with automatic sync. Update `obot_db_password` in `cluster.yaml`, run `task configure && task reconcile`. Pods restart via Reloader annotation. See: `docs/research/cnpg-managed-roles-password-rotation-jan-2026.md`

### Encryption & Bootstrap
```yaml
obot_encryption_key: "..."     # Base64 32 bytes, generate: openssl rand -base64 32
obot_bootstrap_token: "..."    # Optional, hex 32 bytes, generate: openssl rand -hex 32
```

The bootstrap token is used for initial API authentication before OIDC is configured.

### Keycloak SSO (requires keycloak_enabled)
```yaml
obot_keycloak_enabled: true
obot_keycloak_client_id: "obot"
obot_keycloak_client_secret: "..."    # SOPS-encrypted
obot_keycloak_cookie_secret: "..."    # Min 32 chars, generate: openssl rand -base64 32
obot_keycloak_allowed_groups: ""      # Optional group restrictions
obot_keycloak_allowed_roles: ""       # Optional role restrictions
obot_allowed_email_domains: "*"       # Email domain restrictions (default: all)
```

Uses custom Keycloak auth provider from jrmatherly/obot-entraid fork with two env var patterns:
- `OBOT_KEYCLOAK_AUTH_PROVIDER_*` - Keycloak-specific vars (URL, REALM, CLIENT_ID, CLIENT_SECRET)
- `OBOT_AUTH_PROVIDER_*` - Shared auth provider vars (COOKIE_SECRET, EMAIL_DOMAINS)

### MCP Namespace Resource Quotas
```yaml
obot_mcp_namespace: "obot-mcp"        # Namespace for MCP servers
obot_mcp_cpu_requests_quota: "4"      # Total CPU requests
obot_mcp_cpu_limits_quota: "8"        # Total CPU limits
obot_mcp_memory_requests_quota: "8Gi"
obot_mcp_memory_limits_quota: "16Gi"
obot_mcp_max_pods: "20"               # Maximum MCP server pods
```

### MCP Container Defaults
```yaml
obot_mcp_default_cpu_request: "100m"
obot_mcp_default_cpu_limit: "500m"
obot_mcp_default_memory_request: "256Mi"
obot_mcp_default_memory_limit: "512Mi"
obot_mcp_max_cpu: "1000m"             # Per-container max
obot_mcp_max_memory: "1Gi"
```

### PostgreSQL Backups (requires rustfs_enabled)
```yaml
obot_s3_access_key: "..."    # Create via RustFS Console
obot_s3_secret_key: "..."    # SOPS-encrypted
# Required bucket: obot-postgres-backups
```

### Audit Log Export (requires rustfs_enabled)
```yaml
obot_audit_s3_access_key: "..."    # Create via RustFS Console
obot_audit_s3_secret_key: "..."    # SOPS-encrypted
# Required bucket: obot-audit-logs
```

Audit log export allows you to automatically export Obot platform audit logs to S3-compatible storage for compliance, analysis, and long-term retention.

#### RustFS IAM Setup (Principle of Least Privilege)

> All user/policy operations must be performed via the **RustFS Console UI** (port 9001).
> The RustFS bucket setup job automatically creates the `obot-postgres-backups` bucket.

**1. Create Custom Policy**

Navigate to **Identity** → **Policies** → **Create Policy**

**Policy Name:** `obot-storage`

```json
{
  "ID": "",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "NotAction": [],
      "Resource": [
        "arn:aws:s3:::obot-postgres-backups"
      ],
      "NotResource": [],
      "Condition": {}
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "NotAction": [],
      "Resource": [
        "arn:aws:s3:::obot-postgres-backups/*"
      ],
      "NotResource": [],
      "Condition": {}
    }
  ]
}
```

| Permission | Purpose |
| ---------- | ------- |
| `s3:ListBucket` | List backup files for WAL management |
| `s3:GetObject` | Download backups for restore (PITR) |
| `s3:PutObject` | Upload WAL segments and base backups |
| `s3:DeleteObject` | Retention cleanup of old WAL files |
| `s3:GetBucketLocation` | AWS SDK compatibility |

**2. Create Group (or use existing `ai-system` group)**

Navigate to **Identity** → **Groups** → **Create Group**

- **Name:** `ai-system` (shared with LiteLLM, Langfuse)
- **Assign Policy:** `obot-storage` (add to existing policies if group exists)
- Click **Save**

**3. Create Obot Backup User**

Navigate to **Identity** → **Users** → **Create User**

- **Access Key:** (auto-generated, copy this)
- **Secret Key:** (auto-generated, copy this)
- **Assign Group:** `ai-system`
- Click **Save**

**4. Update cluster.yaml**

```yaml
obot_s3_access_key: "<paste-access-key>"
obot_s3_secret_key: "<paste-secret-key>"
```

Then run: `task configure && task reconcile`

#### Audit Log Export RustFS IAM Setup

> The RustFS bucket setup job automatically creates the `obot-audit-logs` bucket when `obot_audit_logs_enabled` is true.

**1. Create Custom Policy**

Navigate to **Identity** → **Policies** → **Create Policy**

**Policy Name:** `obot-audit-storage`

```json
{
  "ID": "",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "NotAction": [],
      "Resource": [
        "arn:aws:s3:::obot-audit-logs"
      ],
      "NotResource": [],
      "Condition": {}
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "NotAction": [],
      "Resource": [
        "arn:aws:s3:::obot-audit-logs/*"
      ],
      "NotResource": [],
      "Condition": {}
    }
  ]
}
```

| Permission | Purpose |
| ---------- | ------- |
| `s3:ListBucket` | List audit log files |
| `s3:GetObject` | Download audit logs for analysis |
| `s3:PutObject` | Upload audit log exports |
| `s3:DeleteObject` | Retention cleanup of old logs |
| `s3:GetBucketLocation` | AWS SDK compatibility |

**2. Create Group (or use existing `ai-system` group)**

Navigate to **Identity** → **Groups**

- If `ai-system` group exists: Edit and add `obot-audit-storage` policy
- If creating new: **Name:** `ai-system`, **Assign Policies:** `obot-audit-storage` (+ others)
- Click **Save**

**3. Create Obot Audit User**

Navigate to **Identity** → **Users** → **Create User**

- **Access Key:** (auto-generated, copy this)
- **Secret Key:** (auto-generated, copy this)
- **Assign Group:** `ai-system`
- Click **Save**

**4. Update cluster.yaml**

```yaml
obot_audit_s3_access_key: "<paste-access-key>"
obot_audit_s3_secret_key: "<paste-secret-key>"
```

Then run: `task configure && task reconcile`

**5. Configure in Obot UI**

After deployment, configure the audit log export in Obot:

1. Navigate to **Admin Settings** → **Audit Logs** → **Export Audit Logs**
2. Select **Custom S3 Compatible** as the storage provider
3. Enter the following configuration:
   - **Endpoint:** `http://rustfs-svc.storage.svc.cluster.local:9000`
   - **Region:** `us-east-1` (or your configured region)
   - **Access Key ID:** `<obot_audit_s3_access_key>`
   - **Secret Access Key:** `<obot_audit_s3_secret_key>`
   - **Bucket:** `obot-audit-logs`
4. Click **Save** to enable automatic audit log exports

> **Note:** The endpoint uses the internal cluster DNS name for RustFS. If accessing from outside the cluster, use `https://rustfs.<cloudflare_domain>` instead.

### Observability
```yaml
obot_monitoring_enabled: true   # ServiceMonitor + Grafana dashboard
obot_tracing_enabled: true      # OTLP traces to Tempo
obot_litellm_enabled: true      # Use LiteLLM as model gateway
```

## File Structure

```
templates/config/kubernetes/apps/ai-system/obot/
├── ks.yaml.j2                  # Flux Kustomization (main + mcp-namespace + mcp-policies)
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2     # bjw-s/app-template deployment
    ├── ocirepository.yaml.j2   # OCI chart source
    ├── postgresql.yaml.j2      # CloudNativePG Cluster + Database
    ├── secret.sops.yaml.j2     # Encrypted credentials
    ├── referencegrant.yaml.j2  # Gateway API cross-namespace
    └── networkpolicy.yaml.j2   # CiliumNetworkPolicy

templates/config/kubernetes/apps/ai-system/obot/mcp-namespace/
└── app/
    ├── kustomization.yaml.j2
    └── namespace.yaml.j2       # MCP namespace with pod security labels

templates/config/kubernetes/apps/ai-system/obot/mcp-policies/
└── app/
    ├── kustomization.yaml.j2
    ├── resourcequota.yaml.j2   # CPU/memory/pod limits
    ├── networkpolicy.yaml.j2   # Obot-only ingress, DNS egress
    └── rbac.yaml.j2            # Obot ServiceAccount permissions

# HTTPRoute centralized in:
templates/config/kubernetes/apps/network/envoy-gateway/app/httproutes.yaml.j2

# Keycloak client config:
templates/config/kubernetes/apps/identity/keycloak/realm-config/app/realm-import.yaml.j2
```

## Keycloak Integration

### Hairpin NAT and External URL Requirement

**Critical:** Obot uses the `jrmatherly/obot-entraid` fork which performs strict OIDC issuer validation.
The Keycloak URL configured in Obot MUST be the **external URL** (`https://sso.matherly.net`) because:

1. **Hairpin NAT**: Pods cannot reach LoadBalancer IPs from inside the cluster
2. **Issuer validation**: Keycloak returns external issuer URL in tokens; Obot validates this matches
3. **Token exchange**: Obot contacts Keycloak directly (not via Envoy Gateway) for token validation

**Traffic flow:**
```
User Browser → Cloudflare Tunnel → envoy-external → Keycloak (login)
                                          ↓
                               redirect with code to Obot
                                          ↓
Obot pod → https://sso.matherly.net → Cloudflare → Keycloak (token exchange)
```

**Network Policy:** Obot egress to Keycloak uses FQDN matching (`toFQDNs`) on port 443,
routing through Cloudflare Tunnel to avoid hairpin NAT.

### Custom Auth Provider

Obot uses `jrmatherly/obot-entraid` fork which adds Keycloak auth provider support via environment variables:

```yaml
# In HelmRelease config section
config:
  OBOT_SERVER_AUTH_PROVIDER: "keycloak"
  # MUST be external URL - fork constructs issuer URL and validates against Keycloak response
  OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "https://sso.${cloudflare_domain}"
  OBOT_KEYCLOAK_AUTH_PROVIDER_REALM: "${keycloak_realm}"
  OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID: "obot"
  # Allow all email domains (explicitly configured for clarity)
  OBOT_AUTH_PROVIDER_EMAIL_DOMAINS: "*"

# In Secret (via extraEnvFrom)
stringData:
  OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET: "<from-sops>"
  # NOTE: Cookie secret is NOT prefixed with KEYCLOAK - it's the shared auth provider cookie secret
  OBOT_AUTH_PROVIDER_COOKIE_SECRET: "<from-sops>"
```

> **REF:** See `docs/research/obot-keycloak-oidc-integration-jan-2026.md` for complete integration details.
> **REF:** See `docs/research/obot-keycloak-oidc-remediation-jan-2026.md` for hairpin NAT solution.

### Client Configuration
When `obot_keycloak_enabled: true`, a Keycloak client is created in realm-import.yaml.j2:

```yaml
clientId: obot
protocol: openid-connect
publicClient: false
standardFlowEnabled: true
implicitFlowEnabled: false
directAccessGrantsEnabled: false
redirectUris:
  - "https://obot.${cloudflare_domain}/*"
webOrigins:
  - "https://obot.${cloudflare_domain}"
attributes:
  pkce.code.challenge.method: "S256"
```

## MCP Namespace Security

### Pod Security Standards
The obot-mcp namespace enforces `restricted` Pod Security Standard:
- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `seccompProfile: RuntimeDefault`
- `capabilities.drop: ["ALL"]`

### ResourceQuota Enforcement
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: obot-mcp-quota
  namespace: obot-mcp
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    pods: "20"
```

### LimitRange Defaults
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: obot-mcp-limits
  namespace: obot-mcp
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "256Mi"
    max:
      cpu: "1000m"
      memory: "1Gi"
    type: Container
```

### Network Isolation
CiliumNetworkPolicy for obot-mcp namespace:
- **Ingress:** Only from Obot pods in ai-system namespace
- **Egress:** DNS (kube-dns:53) only, no internet access

## LiteLLM Integration

When `obot_litellm_enabled: true`:
- Obot routes LLM requests through internal LiteLLM proxy
- Uses `http://litellm.ai-system.svc.cluster.local:4000` as base URL
- Inherits LiteLLM's model routing, caching, and cost tracking

## Health Check Endpoints

| Endpoint | Purpose |
| -------- | ------- |
| `/healthz` | Liveness check |
| `/readyz` | Readiness check |

## Testing

```bash
# Check pods
kubectl get pods -n ai-system -l app.kubernetes.io/name=obot

# Check PostgreSQL
kubectl get clusters -n ai-system obot-postgresql

# Check MCP namespace
kubectl get pods -n obot-mcp
kubectl get resourcequota -n obot-mcp

# Check logs
kubectl logs -n ai-system -l app.kubernetes.io/name=obot

# Access via HTTPRoute
https://obot.<domain>/
```

## Troubleshooting

### Obot CrashLoopBackOff
- Verify PostgreSQL is ready: `kubectl get clusters -n ai-system obot-postgresql`
- Check secrets are mounted: `kubectl exec -n ai-system <pod> -- env | grep OBOT`
- Verify encryption key format (64 hex chars)

### Keycloak Auth Fails
- Verify Keycloak is healthy: `kubectl get keycloak -n identity`
- Check client secret matches in both secrets and realm-import
- Verify pod can reach Keycloak **externally**: `kubectl exec -n ai-system <pod> -- wget -qO- https://sso.matherly.net/health`
- **Note:** Obot must use external URL due to hairpin NAT and issuer validation requirements
- Check CiliumNetworkPolicy allows egress to Keycloak FQDN on port 443

### MCP Servers Not Starting
- Check ResourceQuota: `kubectl describe resourcequota -n obot-mcp`
- Verify NetworkPolicy allows Obot→MCP traffic
- Check RBAC permissions: `kubectl auth can-i create pods --as=system:serviceaccount:ai-system:obot -n obot-mcp`

### Database Connection Issues
- Verify pgvector extension loaded: `kubectl exec -n ai-system obot-postgresql-1 -- psql -U obot -c "SELECT extname FROM pg_extension"`
- Check connection pooler: `kubectl get pods -n ai-system -l cnpg.io/cluster=obot-postgresql`

## NetworkPolicy Considerations

Obot requires egress to:

| Destination | Namespace/FQDN | Port | Purpose |
| ----------- | -------------- | ---- | ------- |
| PostgreSQL | ai-system | 5432 | Database |
| LiteLLM | ai-system | 4000 | AI models |
| Keycloak | `sso.matherly.net` (FQDN) | 443 | OIDC auth (external via Cloudflare) |
| MCP servers | obot-mcp | 8080+ | MCP orchestration |
| Tempo | monitoring | 4318 | OTEL traces |

**Note:** Keycloak egress uses FQDN-based CiliumNetworkPolicy (`toFQDNs`) to route through Cloudflare,
avoiding hairpin NAT issues with internal LoadBalancer IPs.

## Dependencies

- **CloudNativePG** (`cnpg_enabled: true`): PostgreSQL with pgvector
- **pgvector** (`cnpg_pgvector_enabled: true`): Vector embeddings support
- **Keycloak** (`keycloak_enabled: true`): OIDC authentication
- **LiteLLM** (`litellm_enabled: true`): AI model gateway (optional)
- **Envoy Gateway**: HTTPRoute for external access
- **RustFS** (`rustfs_enabled: true`): PostgreSQL backups + audit log export (optional)
- **Prometheus** (`monitoring_enabled: true`): Metrics (optional)
- **Tempo** (`tracing_enabled: true`): Tracing (optional)
- **SOPS/Age**: Secret encryption

## Quick Reference

### Service DNS Names

| Service | DNS | Port |
| ------- | --- | ---- |
| Obot | `obot.ai-system.svc.cluster.local` | 8080 |
| PostgreSQL RW | `obot-postgresql-rw.ai-system.svc.cluster.local` | 5432 |
| PostgreSQL RO | `obot-postgresql-ro.ai-system.svc.cluster.local` | 5432 |

### Derived Variables (computed in plugin.py)
- `obot_enabled` - true when obot_enabled is explicitly set
- `obot_hostname` - `${obot_subdomain}.${cloudflare_domain}`
- `obot_keycloak_enabled` - true when keycloak + obot_keycloak_enabled + client_secret
- `obot_backup_enabled` - true when rustfs + obot S3 credentials
- `obot_audit_logs_enabled` - true when rustfs + obot audit S3 credentials
- `obot_monitoring_enabled` - true when monitoring + obot_monitoring_enabled
- `obot_tracing_enabled` - true when tracing + obot_tracing_enabled
- `obot_litellm_enabled` - true when litellm + obot_litellm_enabled
