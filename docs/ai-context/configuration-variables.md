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

#### Barman Cloud Plugin (PostgreSQL Backups)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `cnpg_barman_plugin_enabled` | Enable Barman plugin | false |
| `cnpg_barman_plugin_version` | Plugin version | 0.10.0 |
| `cnpg_barman_plugin_log_level` | Log level | info |

Requires cert-manager for mTLS. REF: https://cloudnative-pg.io/plugin-barman-cloud/docs/

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
| `keycloak_subdomain` | Subdomain | "sso" |
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

#### Keycloak Config-CLI (GitOps Realm Management)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `keycloak_config_cli_version` | CLI version | "6.4.0-26.1.0" |

Replaces KeycloakRealmImport CRD. Supports incremental updates.

See: `docs/research/keycloak-configuration-as-code-gitops-jan-2026.md`

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
| `litellm_subdomain` | Subdomain | "llms" |
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
| `obot_version` | Image version | "0.2.30" |
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

RustFS IAM setup:
- Bucket: `obot-audit-logs` (auto-created by RustFS setup job)
- Policy: `obot-audit-storage` (scoped to obot-audit-logs bucket)
- User: `obot-audit` in `ai-system` group

See: `docs/ai-context/obot.md#audit-log-export`

#### Obot OpenTelemetry Tracing

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_tracing_enabled` | Enable Tempo tracing | false |

#### Obot LiteLLM Integration

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `obot_litellm_enabled` | Use LiteLLM gateway | true (when litellm_enabled) |

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
