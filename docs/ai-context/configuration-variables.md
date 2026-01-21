# Configuration Variables Reference

> AI Context: Complete reference for all cluster.yaml configuration variables

## Overview

This document provides comprehensive documentation for all configuration variables in `cluster.yaml`. Variables are organized by feature/component, with derived variables computed automatically by `templates/scripts/plugin.py`.

## Required Variables

These variables must be defined in `cluster.yaml`:

```yaml
# Network
node_cidr: "192.168.1.0/24"
cluster_api_addr: "192.168.1.10"
cluster_gateway_addr: "192.168.1.1"

# Cloudflare
cloudflare_domain: "example.com"
cloudflare_token: "xxx"  # SOPS-encrypted
cloudflare_gateway_addr: "192.168.1.90"

# Repository
repository_name: "github.com/user/repo"
```

---

## Optional Features

### UniFi DNS (replaces k8s_gateway)

Replaces k8s_gateway with UniFi Network DNS provider. Makes `cluster_dns_gateway_addr` unnecessary.

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `unifi_host` | UniFi Network hostname/IP | - |
| `unifi_api_key` | API key (requires v9.0.0+) | - |

**Derived:** `unifi_dns_enabled=true`, `k8s_gateway_enabled=false`

See: `docs/research/archive/implemented/external-dns-unifi-integration.md`

---

### Cilium BGP Control Plane v2

Multi-VLAN routing via BGP peering.

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `cilium_bgp_router_addr` | Router IP address | - |
| `cilium_bgp_router_asn` | Router ASN | - |
| `cilium_bgp_node_asn` | Node ASN | - |
| `cilium_lb_pool_cidr` | LoadBalancer IP pool | - |
| `cilium_bgp_hold_time` | BGP hold time | - |
| `cilium_bgp_keepalive_time` | BGP keepalive time | - |
| `cilium_bgp_graceful_restart` | Enable graceful restart | - |

**Derived:** `cilium_bgp_enabled=true` when all 3 required keys set

See: `docs/guides/bgp-unifi-cilium-implementation.md`

---

### Observability Stack

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `monitoring_enabled` | Enable kube-prometheus-stack | false |
| `hubble_enabled` | Enable Cilium Hubble | false |
| `loki_enabled` | Enable Loki log aggregation | false |
| `tracing_enabled` | Enable Tempo tracing | false |

See: `docs/guides/observability-stack-implementation.md`

---

### RustFS Shared Object Storage (S3-compatible)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `rustfs_enabled` | Enable RustFS | false |
| `rustfs_subdomain` | Console UI subdomain | "rustfs" |
| `rustfs_secret_key` | Root secret key (SOPS) | - |
| `loki_s3_access_key` | Loki S3 access key (SOPS) | - |
| `loki_s3_secret_key` | Loki S3 secret key (SOPS) | - |

**Notes:**

- RustFS does NOT support `mc admin` commands
- Loki access keys must be created via RustFS Console UI (port 9001)
- Currently alpha software (v1.0.0-alpha.78)

**Derived:** `loki_deployment_mode="SimpleScalable"` when enabled

See: `docs/research/rustfs-shared-storage-loki-simplescalable-jan-2026.md`

---

### CiliumNetworkPolicies (Zero-Trust Networking)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `network_policies_enabled` | Enable network policies | false |
| `network_policies_mode` | "audit" or "enforce" | "audit" |

See: `docs/research/cilium-network-policies-jan-2026.md`

---

### Talos Backup (etcd snapshots to S3)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `backup_s3_endpoint` | S3 endpoint URL | - |
| `backup_s3_bucket` | Bucket name | - |
| `backup_s3_region` | AWS SDK region | "us-east-1" |

**Derived:** `talos_backup_enabled=true` when endpoint + bucket set

---

### CloudNativePG Operator (Production PostgreSQL)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `cnpg_enabled` | Enable CNPG operator | false |
| `cnpg_postgres_image` | PostgreSQL image | ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie |
| `cnpg_storage_class` | Storage class for data | - |
| `cnpg_control_plane_only` | Run on control-plane | true |

See: `docs/guides/cnpg-implementation.md`

#### CNPG Managed Roles (Password Rotation)

All CNPG clusters use **declarative role management** via `spec.managed.roles` for automatic password synchronization. This enables password rotation without manual `ALTER USER` commands.

**Implemented clusters:** Obot, LiteLLM, Langfuse, Keycloak

**Complete Procedure:** See [CNPG Password Rotation Pattern](./patterns/cnpg-password-rotation.md) for:

- Prerequisites and architecture
- Step-by-step rotation workflow
- Troubleshooting authentication failures
- Verification and testing procedures

#### Barman Cloud Plugin (PostgreSQL Backups)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `cnpg_barman_plugin_enabled` | Enable Barman plugin | false |
| `cnpg_barman_plugin_version` | Plugin version | 0.10.0 |
| `cnpg_barman_plugin_log_level` | Log level | info |

Requires cert-manager for mTLS. REF: https://cloudnative-pg.io/docs/1.28/backup_recovery

#### CloudNativePG Backups (requires RustFS + Barman)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `cnpg_backup_enabled` | Enable PostgreSQL backups | false |
| `cnpg_s3_access_key` | S3 access key (SOPS) | - |
| `cnpg_s3_secret_key` | S3 secret key (SOPS) | - |

#### pgvector Extension (AI/ML Vector Search)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `cnpg_pgvector_enabled` | Enable pgvector | false |
| `cnpg_pgvector_image` | pgvector image | ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie |
| `cnpg_pgvector_version` | pgvector version | 0.8.1 |

Uses ImageVolume pattern (Kubernetes 1.35+, PostgreSQL 18+)

---

### Keycloak OIDC Provider (Identity Management)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_enabled` | Enable Keycloak | false |
| `keycloak_subdomain` | Subdomain | "auth" |
| `keycloak_realm` | Realm name | "matherlynet" |
| `keycloak_db_mode` | "embedded" or "cnpg" | "embedded" |

**Derived:** `keycloak_hostname`, `keycloak_issuer_url`, `keycloak_jwks_uri`

CNPG mode requires `cnpg_enabled: true`. Uses CRD split pattern.

See: `docs/guides/keycloak-implementation.md`

#### Keycloak PostgreSQL Backup (requires RustFS)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_s3_access_key` | S3 access key (SOPS) | - |
| `keycloak_s3_secret_key` | S3 secret key (SOPS) | - |
| `keycloak_backup_schedule` | Embedded pg_dump cron | "0 2 ** *" |
| `keycloak_backup_retention_days` | Embedded retention | 7 |

#### Keycloak OpenTelemetry Tracing

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_tracing_enabled` | Enable Tempo tracing | false |
| `keycloak_tracing_sample_rate` | Sample rate 0.0-1.0 | "0.1" |

#### Keycloak Email/SMTP Configuration

Enables password reset, email verification, and admin notifications. All variables are optional - when `keycloak_smtp_host` is not set, email functionality is disabled.

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_smtp_host` | SMTP server hostname | not configured |
| `keycloak_smtp_port` | SMTP port (25, 587, 465) | "587" |
| `keycloak_smtp_from` | From email address | "noreply@${domain}" |
| `keycloak_smtp_from_display_name` | From display name | "Keycloak" |
| `keycloak_smtp_reply_to` | Reply-to address | not set |
| `keycloak_smtp_reply_to_display_name` | Reply-to display name | not set |
| `keycloak_smtp_envelope_from` | SMTP envelope sender | not set |
| `keycloak_smtp_starttls` | Enable STARTTLS (port 587) | true |
| `keycloak_smtp_ssl` | Enable SSL/TLS (port 465) | false |
| `keycloak_smtp_auth` | Enable SMTP authentication | false |
| `keycloak_smtp_user` | SMTP username (SOPS) | required if auth=true |
| `keycloak_smtp_password` | SMTP password (SOPS) | required if auth=true |

**Configuration Flow:**

1. Set `keycloak_smtp_host` to enable email functionality
2. Configure `keycloak_smtp_auth: true` if your SMTP server requires authentication
3. Add `keycloak_smtp_user` and `keycloak_smtp_password` to cluster.yaml (SOPS-encrypted)
4. Run `task configure -y` to generate templates and encrypt secrets

**Common Configurations:**

- **Gmail**: `smtp.gmail.com:587` with STARTTLS and authentication
- **SendGrid**: `smtp.sendgrid.net:587` with STARTTLS and authentication
- **AWS SES**: `email-smtp.region.amazonaws.com:587` with STARTTLS and authentication
- **Mailgun**: `smtp.mailgun.org:587` with STARTTLS and authentication

#### Keycloak Config-CLI (GitOps Realm Management)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_config_cli_version` | CLI version | "6.4.0-26.1.0" |

Replaces KeycloakRealmImport CRD. Supports incremental updates.

See: `docs/research/keycloak-configuration-as-code-gitops-jan-2026.md`

#### Keycloak Events Retention

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_events_retention_days` | Automatically delete events older than N days | - (indefinite) |

**Purpose:** Compliance and storage management by automatically cleaning up old authentication events.

**Example:**

```yaml
keycloak_events_retention_days: 7  # Retain events for 7 days
```

Converted to seconds internally (`days * 86400`). Valid range: 1-365 days. If not set, events are retained indefinitely.

See: `docs/guides/keycloak-security-hardening-jan-2026.md`

#### Social Identity Providers

| Variable | Description |
| -------- | ----------- |
| `google_idp_enabled`, `google_client_id`, `google_client_secret` | Google OAuth |
| `github_idp_enabled`, `github_client_id`, `github_client_secret` | GitHub OAuth |
| `microsoft_idp_enabled`, `microsoft_client_id`, `microsoft_client_secret`, `microsoft_tenant_id` | Microsoft Entra ID |

See: `docs/research/keycloak-social-identity-providers-integration-jan-2026.md`

#### IdP Role Mappers

| Variable | Description |
| -------- | ----------- |
| `google_default_role` | Hardcoded role for Google users |
| `google_domain_role_mapping` | Map Google Workspace domain to role |
| `github_default_role` | Hardcoded role for GitHub users |
| `github_org_role_mapping` | Map GitHub org to role |
| `microsoft_default_role` | Hardcoded role for Microsoft users |
| `microsoft_group_role_mappings` | Map Entra ID groups to roles |

#### Realm Roles and Groups (RBAC)

| Variable | Description |
| -------- | ----------- |
| `keycloak_realm_roles` | List of realm roles with name and description |
| `keycloak_realm_groups` | List of groups with name, description, realm_roles, and optional subgroups |

**Purpose:** Defines RBAC structure for user access control across all OIDC-protected applications.

**keycloak_realm_roles** - Individual permissions:

```yaml
keycloak_realm_roles:
  - name: "admin"
    description: "Full administrative access"
  - name: "developer"
    description: "Development team access"
```

**keycloak_realm_groups** - Organizational structure with role inheritance:

```yaml
keycloak_realm_groups:
  - name: "admins"
    description: "Platform administrators"
    realm_roles:
      - "admin"
  - name: "developers"
    description: "Development team"
    realm_roles:
      - "developer"
    subgroups:  # Optional nested groups
      - name: "frontend"
        realm_roles:
          - "frontend-developer"
```

Users inherit all roles from their group membership. Groups are optional and provide enterprise-grade RBAC when teams scale beyond individual role assignment.

See: `docs/guides/keycloak-security-hardening-jan-2026.md`

#### Kubernetes API Server OIDC Authentication

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `kubernetes_oidc_enabled` | Enable OIDC authentication on API Server | false |
| `kubernetes_oidc_client_id` | Audience claim expected in tokens | "kubernetes" |
| `kubernetes_oidc_client_secret` | Client secret (SOPS-encrypted) | - |
| `kubernetes_oidc_username_claim` | Claim for Kubernetes username | "email" |
| `kubernetes_oidc_username_prefix` | Prefix for OIDC usernames | "oidc:" |
| `kubernetes_oidc_groups_claim` | Claim for RBAC group membership | "groups" |
| `kubernetes_oidc_groups_prefix` | Prefix for OIDC groups | "oidc:" |
| `kubernetes_oidc_signing_algs` | Accepted token signing algorithms | "RS256" |

**Purpose:** Enables user authentication to Kubernetes API Server via Keycloak OIDC tokens. Creates dedicated "kubernetes" client in Keycloak for token validation.

**Used by:**

- Headlamp (web UI)
- kubectl with oidc-login plugin (CLI)
- kubelogin (alternative CLI)
- Future Kubernetes tools requiring OIDC authentication

**Configuration:**

- Configures kube-apiserver with `--oidc-*` flags via Talos patches
- Updates Headlamp to use "kubernetes" client instead of separate "headlamp" client
- Creates Keycloak client with proper protocol mappers (groups, email, roles)

**RBAC Setup Required:** After enabling, create ClusterRoleBinding for admin group:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-cluster-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: Group
    name: oidc:admin  # Keycloak "admin" group
    apiGroup: rbac.authorization.k8s.io
```

See:

- `docs/research/kubernetes-api-server-oidc-authentication-jan-2026.md` (implementation guide)
- `docs/guides/kubectl-oidc-login-setup.md` (CLI setup)

---

### Grafana Dashboards (requires monitoring_enabled)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_monitoring_enabled` | Keycloak dashboards | false |
| `rustfs_monitoring_enabled` | RustFS dashboards | false |
| `loki_monitoring_enabled` | Loki dashboards | false |
| `litellm_monitoring_enabled` | LiteLLM dashboards | false |
| `dragonfly_monitoring_enabled` | Dragonfly dashboards | false |
| `langfuse_monitoring_enabled` | Langfuse dashboards | false |
| `obot_monitoring_enabled` | Obot dashboards | false |

See: `docs/guides/grafana-dashboards-implementation.md`

---

### LiteLLM Proxy Gateway (AI Model Gateway)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `litellm_enabled` | Enable LiteLLM | false |
| `litellm_subdomain` | Subdomain | "litellm" |
| `litellm_master_key` | API master key (SOPS) | - |
| `litellm_salt_key` | Credential salt (SOPS) | - |
| `litellm_db_password` | PostgreSQL password (SOPS) | - |

Requires: `cnpg_enabled`, `dragonfly_enabled`, `dragonfly_acl_enabled`

**Derived:** `litellm_hostname`

See: `docs/research/litellm-proxy-gateway-integration-jan-2026.md`

#### LiteLLM AI Provider API Keys (SOPS-encrypted)

| Variable | Description |
| -------- | ----------- |
| `azure_openai_us_east_api_key` | Azure OpenAI US East |
| `azure_openai_us_east2_api_key` | Azure OpenAI US East2 |
| `azure_anthropic_api_key` | Azure AI Services (Claude) |
| `azure_cohere_embed_api_key` | Azure Cohere Embed |
| `azure_cohere_rerank_api_key` | Azure Cohere Rerank |

#### LiteLLM OIDC SSO

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `litellm_oidc_enabled` | Enable Keycloak SSO | false |
| `litellm_oidc_client_secret` | Client secret (SOPS) | - |

#### LiteLLM Langfuse Integration

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `litellm_langfuse_enabled` | Enable Langfuse | false |
| `litellm_langfuse_public_key` | Langfuse public key (SOPS) | - |
| `litellm_langfuse_secret_key` | Langfuse secret key (SOPS) | - |
| `litellm_langfuse_host` | Langfuse host (auto-derived) | - |

#### LiteLLM PostgreSQL Backup

| Variable | Description |
| -------- | ----------- |
| `litellm_s3_access_key` | S3 access key (SOPS) |
| `litellm_s3_secret_key` | S3 secret key (SOPS) |

#### LiteLLM OpenTelemetry Tracing

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `litellm_tracing_enabled` | Enable Tempo tracing | false |

---

### Dragonfly Cache (Redis-compatible)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `dragonfly_enabled` | Enable Dragonfly | false |
| `dragonfly_version` | Image tag | "v1.36.0" |
| `dragonfly_operator_version` | Operator chart version | "1.3.1" |
| `dragonfly_replicas` | Instance count | 1 |
| `dragonfly_maxmemory` | Max memory | "512mb" |
| `dragonfly_password` | Default password (SOPS) | - |

25x better performance than Redis with full API compatibility.

See: `docs/research/dragonfly-redis-alternative-integration-jan-2026.md`

#### Dragonfly Backups

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `dragonfly_backup_enabled` | Enable S3 snapshots | false |
| `dragonfly_s3_access_key` | S3 access key (SOPS) | - |
| `dragonfly_s3_secret_key` | S3 secret key (SOPS) | - |
| `dragonfly_snapshot_cron` | Snapshot schedule | "0 */6* **" |

#### Dragonfly ACL (Multi-Tenant Access Control)

| Variable | Description |
| -------- | ----------- |
| `dragonfly_acl_enabled` | Enable per-app ACL |
| `dragonfly_keycloak_password` | Keycloak cache password (SOPS) |
| `dragonfly_appcache_password` | App cache password (SOPS) |
| `dragonfly_litellm_password` | LiteLLM cache password (SOPS) |
| `dragonfly_langfuse_password` | Langfuse cache password (SOPS) |

**Complete Configuration:** See [Dragonfly ACL Configuration Pattern](./patterns/dragonfly-acl-configuration.md) for:

- ACL secret format and syntax
- Key namespace isolation patterns
- Testing and troubleshooting procedures

---

### Langfuse LLM Observability Platform

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_enabled` | Enable Langfuse | false |
| `langfuse_subdomain` | Subdomain | "langfuse" |
| `langfuse_nextauth_secret` | Session secret (SOPS) | - |
| `langfuse_salt` | API key salt (SOPS) | - |
| `langfuse_encryption_key` | 256-bit hex key (SOPS) | - |
| `langfuse_postgres_password` | PostgreSQL password (SOPS) | - |
| `langfuse_clickhouse_password` | ClickHouse password (SOPS) | - |
| `langfuse_clickhouse_cluster_enabled` | ClickHouse cluster mode | false |
| `langfuse_log_level` | trace/debug/info/warn/error/fatal | "info" |
| `langfuse_log_format` | text or json | "text" |

Requires: `cnpg_enabled`, `dragonfly_enabled`

**Derived:** `langfuse_hostname`, `langfuse_url`

See: `docs/research/langfuse-llm-observability-integration-jan-2026.md`

#### Langfuse S3 Storage

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_s3_access_key` | S3 access key (SOPS) | - |
| `langfuse_s3_secret_key` | S3 secret key (SOPS) | - |
| `langfuse_s3_concurrent_writes` | S3 write pool | 50 |
| `langfuse_s3_concurrent_reads` | S3 read pool | 50 |
| `langfuse_media_bucket` | Media uploads bucket | "langfuse-media" |
| `langfuse_export_bucket` | Batch exports bucket | "langfuse-exports" |
| `langfuse_media_max_size` | Max file size bytes | 1GB |
| `langfuse_batch_export_enabled` | Enable batch export | true |

Required buckets: `langfuse-events`, `langfuse-media`, `langfuse-exports`

#### Langfuse PostgreSQL Backup

| Variable | Description |
| -------- | ----------- |
| `langfuse_backup_enabled` | Enable PostgreSQL backups |
| `langfuse_backup_s3_access_key` | S3 access key (SOPS) |
| `langfuse_backup_s3_secret_key` | S3 secret key (SOPS) |

Required bucket: `langfuse-postgres-backups`

#### Langfuse SSO

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_sso_enabled` | Enable Keycloak OIDC | false |
| `langfuse_keycloak_client_secret` | Client secret (SOPS) | - |

#### Langfuse Authentication

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_disable_password_auth` | SSO-only mode | false |
| `langfuse_sso_domain_enforcement` | Domains requiring SSO | - |

**CRITICAL:** When using `langfuse_sso_enabled: true`, set `langfuse_disable_signup: false` to allow SSO user creation. Setting both `langfuse_sso_enabled: true` and `langfuse_disable_signup: true` causes `OAuthCreateAccount` errors.

#### Langfuse Caching

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_cache_api_key_enabled` | Enable API key caching | true |
| `langfuse_cache_api_key_ttl` | API key cache TTL | 300 |
| `langfuse_cache_prompt_enabled` | Enable prompt caching | true |
| `langfuse_cache_prompt_ttl` | Prompt cache TTL | 300 |

#### Langfuse OpenTelemetry Tracing

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_tracing_enabled` | Enable Tempo tracing | false |

#### Langfuse Email

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_smtp_url` | SMTP URL (SOPS) | - |
| `langfuse_email_from` | Sender address | noreply@${domain} |

#### Langfuse Session

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_session_max_age` | Session duration seconds | 2592000 |

#### Langfuse Headless Initialization

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_init_org_id` | Organization ID (slug) | - |
| `langfuse_init_org_name` | Organization name | cluster_name |
| `langfuse_init_user_email` | Admin email (SOPS) | - |
| `langfuse_init_user_password` | Admin password (SOPS) | - |
| `langfuse_init_user_name` | Admin display name | "Admin" |
| `langfuse_disable_signup` | Disable signups | false |

All three required (org_id, user_email, user_password) to enable headless init.

#### Langfuse Project Initialization

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_init_project_id` | Project ID (slug) | - |
| `langfuse_init_project_name` | Project name | "Default Project" |
| `langfuse_init_project_retention` | Retention days | indefinite |
| `langfuse_init_project_public_key` | Public API key (SOPS) | - |
| `langfuse_init_project_secret_key` | Secret API key (SOPS) | - |

#### Langfuse Auto-Provisioning

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_default_org_id` | Default org for SSO users | langfuse_init_org_id |
| `langfuse_default_org_role` | Default org role | - |
| `langfuse_default_project_id` | Default project | langfuse_init_project_id |
| `langfuse_default_project_role` | Default project role | - |

Roles: OWNER, ADMIN, MEMBER, VIEWER, NONE

See: https://langfuse.com/self-hosting/administration/automated-access-provisioning

#### Langfuse SCIM Role Sync (Enterprise License Required)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `langfuse_scim_sync_enabled` | Enable SCIM sync | false |
| `langfuse_scim_sync_schedule` | Cron schedule | "*/5* ** *" |
| `langfuse_scim_public_key` | Org API public key (SOPS) | - |
| `langfuse_scim_secret_key` | Org API secret key (SOPS) | - |
| `langfuse_sync_keycloak_client_id` | Keycloak SA client ID | "langfuse-sync" |
| `langfuse_sync_keycloak_client_secret` | Keycloak client secret (SOPS) | - |
| `langfuse_role_mapping` | Role mapping YAML | - |

See: `docs/research/langfuse-scim-role-sync-implementation-jan-2026.md`

---

### Obot MCP Gateway (AI Agent Platform)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_enabled` | Enable Obot | false |
| `obot_subdomain` | Subdomain | "obot" |
| `obot_version` | Image version | "0.2.33" |
| `obot_replicas` | Pod replicas | 1 |
| `obot_db_password` | PostgreSQL password (SOPS) | - |
| `obot_encryption_key` | Data encryption key (SOPS) | - |
| `obot_bootstrap_token` | Bootstrap token (SOPS) | - |

Requires: `cnpg_enabled` with pgvector

**Derived:** `obot_hostname`

See: `docs/research/obot-mcp-gateway-integration-jan-2026.md`

#### Obot Keycloak SSO

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_keycloak_enabled` | Enable Keycloak auth | false |
| `obot_keycloak_client_id` | Client ID | "obot" |
| `obot_keycloak_client_secret` | Client secret (SOPS) | - |
| `obot_keycloak_cookie_secret` | Cookie encryption (SOPS) | - |
| `obot_keycloak_allowed_groups` | Group restrictions | - |
| `obot_keycloak_allowed_roles` | Role restrictions | - |
| `obot_allowed_email_domains` | Email domain filter | "*" |

See: `docs/research/obot-keycloak-oidc-integration-jan-2026.md`

#### Obot MCP Namespace

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_mcp_namespace` | MCP namespace | "obot-mcp" |
| `obot_mcp_cpu_requests_quota` | CPU requests quota | "4" |
| `obot_mcp_cpu_limits_quota` | CPU limits quota | "8" |
| `obot_mcp_memory_requests_quota` | Memory requests quota | "8Gi" |
| `obot_mcp_memory_limits_quota` | Memory limits quota | "16Gi" |
| `obot_mcp_max_pods` | Max MCP pods | 20 |
| `obot_mcp_default_cpu_request` | Default CPU request | "100m" |
| `obot_mcp_default_cpu_limit` | Default CPU limit | "500m" |
| `obot_mcp_default_memory_request` | Default memory request | "256Mi" |
| `obot_mcp_default_memory_limit` | Default memory limit | "512Mi" |
| `obot_mcp_max_cpu` | Max container CPU | "1000m" |
| `obot_mcp_max_memory` | Max container memory | "1Gi" |

#### Obot PostgreSQL Backup

| Variable | Description |
| -------- | ----------- |
| `obot_s3_access_key` | S3 access key (SOPS) |
| `obot_s3_secret_key` | S3 secret key (SOPS) |

#### Obot Audit Log Export

| Variable | Description |
| -------- | ----------- |
| `obot_audit_s3_access_key` | S3 access key for audit log export (SOPS) |
| `obot_audit_s3_secret_key` | S3 secret key for audit log export (SOPS) |

**Derived:** `obot_audit_logs_enabled=true` when both keys set + `rustfs_enabled: true`

Configure via Obot UI: Admin Settings → Audit Logs → Export Audit Logs

**RustFS IAM Setup:** See [RustFS IAM Setup Pattern](./patterns/rustfs-iam-setup.md) for Console UI procedure:

- Bucket: `obot-audit-logs` (auto-created)
- Policy: `obot-audit-storage` scoped to bucket
- Service account user with SOPS-encrypted credentials

#### Obot OpenTelemetry Tracing

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_tracing_enabled` | Enable Tempo tracing | false |

#### Obot LiteLLM Integration

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_litellm_enabled` | Use LiteLLM gateway | true (when litellm_enabled) |

---

### MCP Context Forge (MCP Gateway Platform)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `mcp_context_forge_enabled` | Enable MCP Context Forge | false |
| `mcp_context_forge_subdomain` | Subdomain | "mcp" |
| `mcp_context_forge_version` | Image tag | "1.0.0-BETA-1" |
| `mcp_context_forge_replicas` | Pod replicas | 1 |
| `mcp_context_forge_db_user` | Database username | "mcpgateway" |
| `mcp_context_forge_db_password` | Database password (SOPS) | - |
| `mcp_context_forge_db_name` | Database name | "mcpgateway" |
| `mcp_context_forge_db_instances` | PostgreSQL instances | 1 |
| `mcp_context_forge_storage_size` | PostgreSQL storage | "10Gi" |
| `mcp_context_forge_admin_email` | Platform admin email | - |
| `mcp_context_forge_admin_password` | Platform admin password (SOPS, min 16 chars) | - |
| `mcp_context_forge_jwt_secret` | JWT signing secret (SOPS, min 32 chars) | - |
| `mcp_context_forge_auth_encryption_secret` | Auth encryption secret (SOPS, min 32 chars) | - |

Requires: `cnpg_enabled`, `dragonfly_enabled`, `dragonfly_acl_enabled`

**Derived:** `mcp_context_forge_hostname`

See: `docs/research/mcp-context-forge-deployment-guide-jan-2026.md`, `docs/ai-context/mcp-context-forge.md`

#### MCP Context Forge Keycloak SSO

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `mcp_context_forge_keycloak_enabled` | Enable Keycloak auth | false |
| `mcp_context_forge_keycloak_client_id` | Client ID | "mcp-context-forge" |
| `mcp_context_forge_keycloak_client_secret` | Client secret (SOPS) | - |

**Derived:** `mcp_context_forge_keycloak_issuer_url`, `mcp_context_forge_keycloak_token_endpoint`

#### MCP Context Forge DCR (Dynamic Client Registration)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `mcp_context_forge_dcr_enabled` | Enable RFC 7591 DCR | true |
| `mcp_context_forge_dcr_default_scopes` | Default scopes | "mcp:read" |
| `mcp_context_forge_dcr_allowed_issuers` | Allowed issuers (empty = Keycloak auto) | [] |

#### MCP Context Forge PostgreSQL Backup

| Variable | Description |
| -------- | ----------- |
| `mcp_context_forge_backup_enabled` | Enable S3 backups |
| `mcp_context_forge_s3_access_key` | S3 access key (SOPS) |
| `mcp_context_forge_s3_secret_key` | S3 secret key (SOPS) |

#### MCP Context Forge Observability

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `mcp_context_forge_monitoring_enabled` | ServiceMonitor for Prometheus | false |
| `mcp_context_forge_tracing_enabled` | External OTEL traces to Tempo | false |
| `mcp_context_forge_tracing_sample_rate` | Tracing sample rate | "0.1" |
| `mcp_context_forge_internal_observability_enabled` | Built-in observability (/admin/observability) | true |
| `mcp_context_forge_internal_observability_sample_rate` | Internal span sampling rate (0.0-1.0) | "0.1" |
| `mcp_context_forge_plugins_enabled` | Enable MCP server plugins/extensions | true |
| `mcp_context_forge_passthrough_enabled` | Enable header passthrough to MCP servers | false |
| `mcp_context_forge_passthrough_headers` | JSON array of headers to forward | `["X-Trace-Id", "X-Span-Id", "X-Request-Id"]` |
| `mcp_context_forge_passthrough_source` | Header config source: db, env, or merge | "env" |

**Metrics endpoint:** `/metrics/prometheus` (no authentication required)

**Header passthrough:** Enables forwarding of HTTP headers to backend MCP servers for distributed tracing, auth context, and multi-tenancy.

**Note:** External OTEL tracing requires `opentelemetry-exporter-otlp-proto-grpc` package which is NOT included in official image 1.0.0-BETA-1.

#### MCP Context Forge Dragonfly Cache

| Variable | Description |
| -------- | ----------- |
| `dragonfly_mcpgateway_password` | Dragonfly ACL password (SOPS) |

Requires `dragonfly_acl_enabled: true`. Uses broad ACL pattern `~* +@all -@dangerous +INFO` for leader election and session management.

---

### OIDC/JWT Authentication (Envoy Gateway)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `oidc_issuer_url` | OIDC issuer URL | - |
| `oidc_jwks_uri` | JWKS endpoint | - |

**Derived:** `oidc_enabled=true` when both set

Creates SecurityPolicy targeting HTTPRoutes with label `security: oidc-protected`.

Note: Keycloak auto-derives these values when `keycloak_enabled: true`.

#### OIDC Split-Path Architecture (Hairpin NAT Workaround)

- HTTPRoutes with `security: oidc-protected` use Envoy Gateway SecurityPolicy
- User auth flows through Cloudflare Tunnel → envoy-external → Keycloak
- Token exchange uses internal Keycloak service via `backendRefs` + `tokenEndpoint`
- ReferenceGrant in identity namespace allows cross-namespace reference
- Keycloak HTTPRoute uses envoy-external only (no internal route)

See: `docs/ai-context/cilium-networking.md#oidc-authentication-integration`

---

### Proxmox Infrastructure (OpenTofu)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `proxmox_api_url` | Proxmox API URL | - |
| `proxmox_node` | Target node | - |
| `proxmox_vlan_mode` | Proxmox handles VLAN tagging | false |

**Derived:** `infrastructure_enabled=true` when api_url + node set

#### VM Defaults (3-tier fallback chain)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `proxmox_vm_controller_defaults` | Controller VM settings | 4 cores, 8GB, 64GB |
| `proxmox_vm_worker_defaults` | Worker VM settings | 8 cores, 16GB, 256GB |
| `proxmox_vm_defaults` | Global fallback | - |

Per-node overrides via `vm_cores`, `vm_memory`, `vm_disk_size` in nodes.yaml.

Fallback chain: per-node → role-defaults → global-defaults

See: `docs/CONFIGURATION.md`

---

## Derived Variables

Computed automatically by `templates/scripts/plugin.py`:

### Core Infrastructure

| Variable | Derived When |
| -------- | ------------ |
| `cilium_bgp_enabled` | All 3 BGP keys set |
| `unifi_dns_enabled` | unifi_host + unifi_api_key set |
| `k8s_gateway_enabled` | unifi_dns_enabled is false |
| `talos_backup_enabled` | backup_s3_endpoint + backup_s3_bucket set |
| `oidc_enabled` | oidc_issuer_url + oidc_jwks_uri set |
| `spegel_enabled` | >1 node (can override) |
| `infrastructure_enabled` | proxmox_api_url + proxmox_node set |

### Storage

| Variable | Derived When |
| -------- | ------------ |
| `rustfs_enabled` | Explicitly set to true |
| `loki_deployment_mode` | "SimpleScalable" when rustfs_enabled |

### CNPG

| Variable | Derived When |
| -------- | ------------ |
| `cnpg_enabled` | Explicitly set to true |
| `cnpg_barman_plugin_enabled` | cnpg + barman_plugin both true |
| `cnpg_backup_enabled` | cnpg + rustfs + backup + credentials |
| `cnpg_pgvector_enabled` | cnpg + pgvector both true |

### Keycloak

| Variable | Derived When |
| -------- | ------------ |
| `keycloak_enabled` | Explicitly set to true |
| `keycloak_hostname` | keycloak_subdomain + cloudflare_domain |
| `keycloak_issuer_url` | Auto-derived OIDC issuer |
| `keycloak_jwks_uri` | Auto-derived JWKS endpoint |
| `keycloak_backup_enabled` | rustfs + keycloak S3 credentials |
| `keycloak_tracing_enabled` | tracing + keycloak_tracing both true |
| `keycloak_monitoring_enabled` | monitoring + keycloak_monitoring both true |

### Grafana

| Variable | Derived When |
| -------- | ------------ |
| `grafana_oidc_enabled` | monitoring + keycloak + grafana_oidc + client_secret |
| `rustfs_monitoring_enabled` | monitoring + rustfs_monitoring both true |
| `loki_monitoring_enabled` | monitoring + loki_monitoring both true |

### LiteLLM

| Variable | Derived When |
| -------- | ------------ |
| `litellm_enabled` | Explicitly set to true |
| `litellm_hostname` | litellm_subdomain + cloudflare_domain |
| `litellm_oidc_enabled` | keycloak + litellm_oidc + client_secret |
| `litellm_backup_enabled` | rustfs + litellm S3 credentials |
| `litellm_monitoring_enabled` | monitoring + litellm_monitoring both true |
| `litellm_tracing_enabled` | tracing + litellm_tracing both true |
| `litellm_langfuse_enabled` | langfuse_enabled + public_key + secret_key |
| `litellm_langfuse_host` | Internal URL when langfuse_enabled, else cloud |

### Dragonfly

| Variable | Derived When |
| -------- | ------------ |
| `dragonfly_enabled` | Explicitly set to true |
| `dragonfly_backup_enabled` | rustfs + backup + S3 credentials |
| `dragonfly_monitoring_enabled` | monitoring + dragonfly_monitoring both true |
| `dragonfly_acl_enabled` | Explicitly set to true |

### Langfuse

| Variable | Derived When |
| -------- | ------------ |
| `langfuse_enabled` | Explicitly set to true |
| `langfuse_hostname` | langfuse_subdomain + cloudflare_domain |
| `langfuse_url` | HTTPS URL for web UI |
| `langfuse_sso_enabled` | keycloak + sso + client_secret |
| `langfuse_backup_enabled` | rustfs + backup + S3 credentials |
| `langfuse_monitoring_enabled` | monitoring + langfuse_monitoring both true |
| `langfuse_tracing_enabled` | tracing + langfuse_tracing both true |
| `langfuse_scim_sync_enabled` | keycloak + scim + all SCIM credentials |

### Obot

| Variable | Derived When |
| -------- | ------------ |
| `obot_enabled` | Explicitly set to true |
| `obot_hostname` | obot_subdomain + cloudflare_domain |
| `obot_keycloak_enabled` | keycloak + obot_keycloak + client_secret |
| `obot_keycloak_base_url` | Auto-derived Keycloak base URL |
| `obot_keycloak_issuer_url` | Auto-derived OIDC issuer |
| `obot_keycloak_realm` | Auto-derived from keycloak_realm |
| `obot_backup_enabled` | rustfs + obot S3 credentials |
| `obot_monitoring_enabled` | monitoring + obot_monitoring both true |
| `obot_tracing_enabled` | tracing + obot_tracing both true |
| `obot_litellm_enabled` | litellm + obot_litellm both true |

---

**Last Updated:** January 13, 2026
**Plugin Version:** templates/scripts/plugin.py (60+ computed variables)
**Configuration Files:** cluster.yaml, nodes.yaml
