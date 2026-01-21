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

### Resource Configuration

```yaml
obot_cpu_request: "500m"     # Obot CPU request
obot_cpu_limit: "2000m"      # Obot CPU limit
obot_memory_request: "1Gi"   # Obot memory request
obot_memory_limit: "4Gi"     # Obot memory limit
```

Configure resource requests and limits for the Obot pod. Defaults are suitable for development/small production deployments. Increase for high-concurrency production workloads.

### Database (CloudNativePG with pgvector)

```yaml
obot_db_password: "..."            # SOPS-encrypted PostgreSQL password
obot_postgres_user: "obot"         # Database username
obot_postgres_db: "obot"           # Database name
obot_postgresql_replicas: 1        # PostgreSQL instances
obot_postgresql_storage_size: "10Gi"
obot_storage_size: "20Gi"          # Workspace PVC size
obot_storage_class: ""             # Optional override (defaults to global storage_class)
```

**Password Rotation:** See [CNPG Password Rotation Pattern](./patterns/cnpg-password-rotation.md) for complete procedure.

### Workspace Provider Configuration

```yaml
obot_workspace_provider: "directory"  # "directory" or "s3"
obot_s3_bucket: "obot-workspaces"     # S3 bucket for workspace storage
obot_s3_endpoint: "http://rustfs-svc.storage.svc.cluster.local:9000"
obot_s3_region: "us-east-1"
obot_workspace_s3_access_key: "..."   # SOPS-encrypted (required for S3 mode)
obot_workspace_s3_secret_key: "..."   # SOPS-encrypted (required for S3 mode)
```

**Workspace Provider Options:**

- **`directory`** (default): Single PVC storage, requires `updateStrategy: Recreate` and `replicas: 1`
- **`s3`**: S3-compatible storage, enables multi-replica deployments with `RollingUpdate` strategy

**When to use S3 mode:**

- Multi-replica deployments for high availability
- Shared workspace state across pod restarts
- Large-scale deployments with many concurrent users

### Encryption & Bootstrap

```yaml
obot_encryption_provider: "custom"  # Options: custom, aws, gcp, azure
obot_encryption_key: "..."          # Base64 32 bytes (for "custom" mode), generate: openssl rand -base64 32
obot_bootstrap_token: "..."         # Optional, hex 32 bytes, generate: openssl rand -hex 32
```

**Encryption Provider:** Configures the encryption provider for data at rest. Use `custom` for self-managed encryption keys, or cloud provider options (`aws`, `gcp`, `azure`) for cloud-managed key services.

The bootstrap token is used for initial API authentication before OIDC is configured.

### Authentication & Access Control

```yaml
obot_admin_emails: "admin@example.com"     # Comma-separated admin email addresses
obot_owner_emails: "owner@example.com"     # Comma-separated owner email addresses
obot_allowed_email_domains: "*"            # Allowed domains or "*" for all
```

**Access Levels:**

- **Admin**: Full platform access for administrative tasks
- **Owner**: Highest privilege level with ownership capabilities
- **Email Domains**: Restrict authentication to specific email domains (e.g., `"example.com,company.org"`)

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

### Entra ID (Azure AD) SSO - Alternative to Keycloak

```yaml
obot_entra_tenant_id: "..."     # Azure AD tenant ID
obot_entra_client_id: "..."     # OIDC client ID (SOPS-encrypted)
obot_entra_client_secret: "..." # OIDC client secret (SOPS-encrypted)
```

**NOTE:** Use either Keycloak OR Entra ID authentication, not both. When `obot_entra_tenant_id` is set, `OBOT_SERVER_AUTH_PROVIDER` will be configured as `entra-id`.

**Use Cases:**

- Organizations already using Azure AD/Entra ID
- Microsoft 365 integration scenarios
- Enterprise deployments with Azure infrastructure

### Tool Registry Configuration (Optional)

```yaml
obot_tool_registries:
  - "github.com/obot-platform/tools"      # Official tools
  - "/obot-tools/tools"                   # Entraid fork custom tools
  - "github.com/yourorg/custom-tools"     # Organization-specific tools
```

Specify additional gptscript tool registries. Supports GitHub repos, HTTP URLs, or local paths.

**Default:** `["/obot-tools/tools"]` (jrmatherly/obot-entraid fork embedded tools)

**Use Cases:**

- Add custom tool repositories (GitHub, GitLab, etc.)
- Include organization-specific gptscript tools
- Enable beta/experimental tool registries for testing

**Security:** Only add registries from trusted sources - accessible to all authenticated users

### MCP Catalog Configuration (Optional)

```yaml
obot_default_mcp_catalog: "https://github.com/obot-platform/mcp-catalog"
# or use custom catalog:
# obot_default_mcp_catalog: "https://github.com/yourorg/mcp-catalog"
```

Provides a default MCP server catalog accessible to all users for tool discovery.

**Default:** `""` (no default catalog)

**Use Cases:**

- Pre-populate MCP server catalog for all users
- Point to organization-specific MCP catalog repository
- Enable curated tool discovery experience
- Enterprise deployments with approved-tools-only policies

**Supported Formats:** GitHub repo URL, HTTP(S) URL, or local path

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

#### RustFS IAM Setup

**Bucket:** `obot-postgres-backups` (auto-created by RustFS setup job)

**Required S3 Permissions:**

- `s3:ListBucket`, `s3:GetBucketLocation` - WAL management
- `s3:GetObject` - PITR restore
- `s3:PutObject` - Base backups and WAL segments
- `s3:DeleteObject` - Retention cleanup

**Setup Procedure:**

See [RustFS IAM Setup Pattern](./patterns/rustfs-iam-setup.md) for complete Console UI procedure including:

1. Creating `obot-storage` policy scoped to `obot-postgres-backups`
2. Creating service account user
3. Updating `cluster.yaml` with `obot_s3_access_key` and `obot_s3_secret_key`
4. Verifying S3 connectivity

#### Audit Log Export RustFS IAM Setup

**Bucket:** `obot-audit-logs` (auto-created by RustFS setup job when `obot_audit_logs_enabled: true`)

**Required S3 Permissions:**

- `s3:ListBucket`, `s3:GetBucketLocation` - Browse audit logs
- `s3:GetObject` - Download audit logs for analysis
- `s3:PutObject` - Upload audit log exports
- `s3:DeleteObject` - Retention cleanup

**Setup Procedure:**

See [RustFS IAM Setup Pattern](./patterns/rustfs-iam-setup.md) for complete Console UI procedure including:

1. Creating `obot-audit-storage` policy scoped to `obot-audit-logs`
2. Creating service account user
3. Updating `cluster.yaml` with `obot_audit_s3_access_key` and `obot_audit_s3_secret_key`

**Configure in Obot UI:**

After deployment, enable audit log export in Obot:

1. Navigate to **Admin Settings** → **Audit Logs** → **Export Audit Logs**
2. Select **Custom S3 Compatible** as the storage provider
3. Configure:
   - **Endpoint:** `http://rustfs-svc.storage.svc.cluster.local:9000`
   - **Region:** `us-east-1` (or your configured region)
   - **Access Key ID:** `<obot_audit_s3_access_key>`
   - **Secret Access Key:** `<obot_audit_s3_secret_key>`
   - **Bucket:** `obot-audit-logs`
4. Click **Save**

> **Note:** The endpoint uses the internal cluster DNS name for RustFS. If accessing from outside the cluster, use `https://rustfs.<cloudflare_domain>` instead.

### Observability

```yaml
obot_monitoring_enabled: true   # ServiceMonitor + Grafana dashboard
obot_tracing_enabled: true      # OTLP traces to Tempo
obot_otel_sample_prob: "0.1"    # OpenTelemetry sampling probability (0.0-1.0)
obot_litellm_enabled: true      # Use LiteLLM as model gateway
```

**OpenTelemetry Sampling:** Controls what percentage of traces are exported to reduce overhead. Lower values (e.g., `0.1` = 10%) reduce data volume, higher values (e.g., `1.0` = 100%) provide complete trace coverage. Adjust based on traffic volume and observability requirements.

**Note:** Tempo only supports traces, not metrics. The "failed to upload metrics" error in Obot logs is expected and non-fatal - traces still work correctly.

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
    ├── networkpolicy.yaml.j2   # CiliumNetworkPolicy
    ├── servicemonitor.yaml.j2  # Prometheus metrics
    └── dashboard-configmap.yaml.j2  # Grafana dashboard (when monitoring enabled)

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

---

**Last Updated:** January 13, 2026
**Default Image:** jrmatherly/obot-entraid:0.2.33
**Default Subdomain:** obot
**Chart Template:** bjw-s/app-template (via OCI)
**MCP Namespace:** obot-mcp (20 pods max, 4 CPU req / 8 CPU limit)
