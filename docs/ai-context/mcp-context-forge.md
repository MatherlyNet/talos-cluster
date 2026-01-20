# MCP Context Forge Configuration

## Overview

MCP Context Forge is IBM's centralized MCP (Model Context Protocol) server registry and gateway platform. It provides:
- Multi-tenant MCP server management with team-based access control
- Centralized gateway for MCP server routing and discovery
- Role-based authentication via Keycloak SSO integration
- Comprehensive audit logging and usage analytics

**Source:** [IBM/mcp-context-forge](https://github.com/IBM/mcp-context-forge)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       ai-system namespace                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────┐  ┌─────────────────────────────────┐  │
│  │  MCP Context Forge   │  │    CloudNativePG PostgreSQL     │  │
│  │  (ghcr.io/ibm/       │  │  mcp-context-forge-postgresql   │  │
│  │  mcp-context-forge)  │  │       Port 5432                 │  │
│  │     Port 4444        │  └─────────────────────────────────┘  │
│  └──────────┬───────────┘                                       │
│             │                                                    │
│             │     ┌────────────────────────────────────────┐    │
│             └────►│         Shared Infrastructure          │    │
│                   │  cache/dragonfly, identity/keycloak    │    │
│                   │       monitoring/tempo                  │    │
│                   └────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                               │
                    External MCP Clients
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      network namespace                           │
├─────────────────────────────────────────────────────────────────┤
│  HTTPRoute: mcp.${cloudflare_domain} → mcp-context-forge:4444   │
│  ReferenceGrant: Allow network → ai-system service access       │
│  (Native SSO - no Gateway OIDC, Keycloak handles auth)          │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration Variables

### Enable/Disable
```yaml
mcp_context_forge_enabled: true           # Enable MCP Context Forge deployment
mcp_context_forge_subdomain: "mcp"        # Creates mcp.${cloudflare_domain}
mcp_context_forge_version: "latest"        # Image tag (uses commit SHAs, not semver)
mcp_context_forge_replicas: 1             # Pod replicas
```

### Resource Configuration
```yaml
mcp_context_forge_cpu_request: "100m"     # CPU request
mcp_context_forge_cpu_limit: "1000m"      # CPU limit
mcp_context_forge_memory_request: "512Mi" # Memory request
mcp_context_forge_memory_limit: "1Gi"     # Memory limit
```

### Database (CloudNativePG)
```yaml
mcp_context_forge_db_user: "mcpgateway"        # Database username
mcp_context_forge_db_password: "..."           # SOPS-encrypted password
mcp_context_forge_db_name: "mcpgateway"        # Database name
mcp_context_forge_db_instances: 1              # PostgreSQL instances
mcp_context_forge_storage_size: "10Gi"         # PostgreSQL storage
```

**Password Rotation:** See [CNPG Password Rotation Pattern](./patterns/cnpg-password-rotation.md) for complete procedure.

### Core Credentials (SOPS-encrypted)
```yaml
# Platform admin password (minimum 16 characters)
# Generate: openssl rand -base64 24
mcp_context_forge_admin_password: "..."

# JWT signing secret (minimum 32 characters)
# Generate: openssl rand -base64 48
mcp_context_forge_jwt_secret: "..."

# Auth encryption secret for stored credentials (minimum 32 characters)
# Generate: openssl rand -base64 48
mcp_context_forge_auth_encryption_secret: "..."
```

### Dragonfly Cache
```yaml
# MCP Gateway cache password (requires dragonfly_acl_enabled: true)
# Generate: openssl rand -base64 24
dragonfly_mcpgateway_password: "..."
```

MCP Context Forge uses shared Dragonfly in the cache namespace for session storage and caching. When `dragonfly_acl_enabled: true`, each application gets its own ACL user with key prefix isolation.

### Keycloak SSO Integration
```yaml
mcp_context_forge_keycloak_enabled: true              # Enable Keycloak SSO
mcp_context_forge_keycloak_client_id: "mcp-context-forge"  # OIDC client ID
mcp_context_forge_keycloak_client_secret: "..."       # SOPS-encrypted client secret
```

**Authentication Architecture:**
- **Native SSO:** MCP Context Forge handles OIDC directly via `KEYCLOAK_*` environment variables
- **No Gateway OIDC:** HTTPRoute has no security label to avoid dual authentication
- **Token Validation:** Uses internal Keycloak endpoint for backchannel validation

**Keycloak Client Configuration:**
- Auto-created when `mcp_context_forge_keycloak_enabled: true`
- Configured in `realm-config.yaml.j2` with protocol mappers for roles/groups claims
- Available MCP scopes: `mcp:read`, `mcp:tools`, `mcp:prompts`, `mcp:resources`

### Dynamic Client Registration (DCR)
```yaml
mcp_context_forge_dcr_enabled: true            # Enable RFC 7591 DCR
mcp_context_forge_dcr_default_scopes: "mcp:read"  # Default scopes for registered clients
mcp_context_forge_dcr_allowed_issuers: []      # Empty = Keycloak issuer auto-added
```

**DCR Architecture:**
- **RFC 7591 Compliant:** MCP clients can self-register without manual configuration
- **Least Privilege:** Default scope is `mcp:read` (read-only access)
- **Elevated Access:** Additional scopes (`mcp:tools`, `mcp:prompts`, `mcp:resources`) granted via Keycloak roles

### PostgreSQL Backups
```yaml
mcp_context_forge_backup_enabled: true        # Enable S3 backups (requires rustfs_enabled)
mcp_context_forge_s3_access_key: "..."        # SOPS-encrypted (create in RustFS Console)
mcp_context_forge_s3_secret_key: "..."        # SOPS-encrypted (create in RustFS Console)
```

**RustFS IAM Setup:** Backups use the `mcpgateway-postgres-backups` bucket with a scoped `mcp-context-forge-storage` policy.
- **Policy:** `mcp-context-forge-storage` (scoped to `mcpgateway-postgres-backups` bucket only)
- **Group:** `databases` (shared with CNPG) or `ai-system-backups` (dedicated)
- **User:** `mcpgateway-backup`

See [RustFS IAM Setup Pattern](./patterns/rustfs-iam-setup.md) and [MCP Context Forge Deployment Guide](../research/mcp-context-forge-deployment-guide-jan-2026.md#rustfs-iam-setup-for-postgresql-backups) for detailed setup instructions.

### Observability
```yaml
mcp_context_forge_monitoring_enabled: true    # ServiceMonitor for Prometheus (/metrics/prometheus)
mcp_context_forge_tracing_enabled: true       # External OpenTelemetry traces to Tempo (requires custom image with OTLP exporter)
mcp_context_forge_tracing_sample_rate: "0.1"  # Sampling rate (0.0-1.0)
mcp_context_forge_internal_observability_enabled: true  # Built-in database-backed tracing with Admin UI (/admin/observability)
```

**Observability Architecture:**
- **Internal Observability:** `OBSERVABILITY_ENABLED=true` enables built-in database-backed tracing with Admin UI at `/admin/observability`
- **Prometheus Metrics:** Exposed at `/metrics/prometheus` (no authentication required)
- **External OTEL Tracing:** Requires `opentelemetry-exporter-otlp-proto-grpc` package which is NOT included in official image 1.0.0-BETA-1

## Dependencies

**Required:**
- `cnpg_enabled: true` - CloudNativePG operator for PostgreSQL
- `dragonfly_enabled: true` - Dragonfly cache with ACL enabled

**Optional:**
- `keycloak_enabled: true` - Keycloak for SSO authentication
- `rustfs_enabled: true` - RustFS S3 for PostgreSQL backups
- `monitoring_enabled: true` - Prometheus metrics collection
- `tracing_enabled: true` - OpenTelemetry distributed tracing

## Computed Values (plugin.py)

The following values are automatically computed:

```python
# Full hostname derived from subdomain + domain
mcp_context_forge_hostname = f"{mcp_context_forge_subdomain}.{cloudflare_domain}"

# Keycloak URLs (when mcp_context_forge_keycloak_enabled)
mcp_context_forge_keycloak_issuer_url = f"https://{keycloak_hostname}/realms/{keycloak_realm}"
mcp_context_forge_keycloak_token_endpoint = f"http://keycloak-service.identity.svc.cluster.local:8080/realms/{keycloak_realm}/protocol/openid-connect/token"

# Feature flags
mcp_context_forge_backup_enabled = rustfs_enabled and mcp_context_forge_s3_access_key and mcp_context_forge_s3_secret_key
mcp_context_forge_monitoring_enabled = monitoring_enabled and mcp_context_forge_monitoring_enabled
mcp_context_forge_tracing_enabled = tracing_enabled and mcp_context_forge_tracing_enabled

# Defaults
mcp_context_forge_internal_observability_enabled = True  # Built-in observability always defaults to enabled
```

## File Structure

```
templates/config/kubernetes/apps/ai-system/mcp-context-forge/
├── ks.yaml.j2                    # Flux Kustomization with dependencies
└── app/
    ├── kustomization.yaml.j2     # Kustomize resources list
    ├── deployment.yaml.j2        # Deployment with env vars
    ├── service.yaml.j2           # ClusterIP service (port 4444)
    ├── postgresql.yaml.j2        # CloudNativePG Cluster
    ├── secret.sops.yaml.j2       # Application secrets
    ├── referencegrant.yaml.j2    # Cross-namespace service access
    ├── networkpolicy.yaml.j2     # CiliumNetworkPolicy
    └── servicemonitor.yaml.j2    # Prometheus scraping
```

## Keycloak Client Scopes

MCP Context Forge defines custom Keycloak scopes for fine-grained MCP access control:

| Scope | Description |
| ------- | ------------- |
| `mcp:tools` | Access to MCP server tools |
| `mcp:prompts` | Access to MCP server prompts |
| `mcp:resources` | Access to MCP server resources |

These scopes are defined in `realm-config.yaml.j2` under `clientScopes` and can be assigned to clients for granular permission control.

## Network Policy

The CiliumNetworkPolicy allows:

**Ingress:**
- Envoy Gateway proxy (port 4444)
- Prometheus scraping (port 4444)

**Egress:**
- DNS resolution (kube-dns)
- PostgreSQL (mcp-context-forge-postgresql:5432)
- Dragonfly cache (dragonfly:6379)
- Keycloak (when SSO enabled, port 8080)
- Tempo tracing (when tracing enabled, port 4317)
- External HTTPS/HTTP (for upstream MCP servers)

## Troubleshooting

### Common Issues

**Application not starting:**
```bash
kubectl logs -n ai-system deploy/mcp-context-forge
kubectl describe pod -n ai-system -l app.kubernetes.io/name=mcp-context-forge
```

**Database connection issues:**
```bash
kubectl cnpg status mcp-context-forge-postgresql -n ai-system
kubectl logs -n ai-system -l cnpg.io/cluster=mcp-context-forge-postgresql
```

**Cache connection issues:**
```bash
kubectl logs -n cache -l app.kubernetes.io/name=dragonfly
# Verify ACL user exists for mcpgateway
```

**SSO authentication failures:**
```bash
# Check Keycloak client configuration
kubectl logs -n identity deploy/keycloak
# Verify OIDC endpoints are reachable from pod
kubectl exec -n ai-system deploy/mcp-context-forge -- curl -s http://keycloak-service.identity.svc.cluster.local:8080/realms/matherlynet/.well-known/openid-configuration
```

**Network policy blocking traffic:**
```bash
# Check for dropped packets
hubble observe --verdict DROPPED -n ai-system
# Verify policy is in audit mode during testing
kubectl get ciliumnetworkpolicies -n ai-system
```

## Reference Documentation

- [MCP Context Forge Deployment Guide](../research/mcp-context-forge-deployment-guide-jan-2026.md)
- [CloudNativePG Implementation](../guides/cnpg-implementation.md)
- [CNPG Password Rotation Pattern](./patterns/cnpg-password-rotation.md)
- [Network Policy Patterns](../research/cilium-network-policies-jan-2026.md)
