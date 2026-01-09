# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

GitOps-driven Kubernetes cluster template on Talos Linux with Flux CD. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI (kube-proxy replacement, BGP Control Plane v2 optional), Gateway API + Envoy, SOPS/Age encryption, Cloudflare (DNS + Tunnel), UniFi DNS (optional internal), makejinja templating, OpenTofu v1.11+ (IaC)

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

**Deployment:** 7-stage workflow (Hardware → Machine Prep → Workstation → Cloudflare → Infrastructure → Cluster Config → Bootstrap)

**Control Plane:** Does NOT run workloads by default (`allowSchedulingOnControlPlanes: false`); dedicated workers recommended

## Quick Context Loading

Run `/expert-mode` for efficient project context loading (94% token reduction).

Alternatively, read `PROJECT_INDEX.md` first - it provides complete project understanding in ~3K tokens.

## Common Commands (go-task)

This project uses **go-task** as the primary task runner. All commands via `task <name>`.

### Quick Reference
```bash
task --list              # List all available tasks
task init                # Initialize config files from samples
task configure -y        # Render templates, validate, encrypt secrets
task reconcile           # Force Flux to sync from Git
```

### Bootstrap (New Cluster)
```bash
task bootstrap:talos     # Install Talos on nodes
task bootstrap:apps      # Deploy Cilium, CoreDNS, Spegel, Flux
```

### Talos Operations
```bash
task talos:generate-config        # Regenerate Talos configs
task talos:apply-node IP=<ip>     # Apply config to running node
task talos:upgrade-node IP=<ip>   # Upgrade Talos version
task talos:upgrade-k8s            # Upgrade Kubernetes version
task talos:reset                  # Reset cluster to maintenance
```

### Infrastructure (OpenTofu)
```bash
task infra:init              # Initialize OpenTofu with R2 backend
task infra:plan              # Create execution plan
task infra:apply             # Apply saved plan
task infra:apply-auto        # Apply with auto-approve
task infra:destroy           # Destroy managed resources
task infra:secrets-edit      # Edit secrets (rotation only)
task infra:verify-nodes      # Verify nodes accessible (pre-bootstrap)
task infra:validate          # Validate configuration
task infra:fmt               # Format configuration
```

### Template Management
```bash
task template:debug      # Gather cluster resource states
task template:tidy       # Archive template files post-setup
task template:reset      # Remove all generated files
```

### Verification
```bash
kubectl get nodes -o wide
kubectl get pods -A
flux check
flux get ks -A
flux get hr -A
cilium status
```

## Architecture

### Directory Layout
- `templates/config/kubernetes/apps/<namespace>/<app>/` - Jinja2 templates for K8s manifests
- `templates/config/talos/` - Talos configuration templates
- `templates/config/bootstrap/` - Bootstrap resource templates
- `templates/config/infrastructure/` - OpenTofu/IaC templates
- `kubernetes/` - GENERATED K8s manifests (after `task configure`)
- `talos/` - GENERATED Talos configs (after `task configure`)
- `infrastructure/` - GENERATED OpenTofu configs (after `task configure`)
- `docs/` - Comprehensive documentation

### Template Flow
```
cluster.yaml + nodes.yaml → makejinja → kubernetes/ + talos/ + bootstrap/ + infrastructure/
                                            ↓
                              task bootstrap:talos → Nodes ready
                                            ↓
                              task bootstrap:apps → Flux syncs Git
```

### GitOps Flow (After Bootstrap)
```
Git Repo → GitRepository → Kustomizations → HelmReleases
                              ↓
                    ExternalSecrets (future) → Native Secrets
```

### Key Patterns

**App Template Structure:**
```
templates/config/kubernetes/apps/<namespace>/<app>/
├── ks.yaml.j2              # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2
    ├── ocirepository.yaml.j2
    └── secret.sops.yaml.j2  # (if secrets needed)
```

**Template Delimiters (makejinja):**
- Block: `#% ... %#` (e.g., `#% if condition %#`)
- Variable: `#{ ... }#` (e.g., `#{ cluster_api_addr }#`)
- Comment: `#| ... #|` ⚠️ **SYMMETRICAL** - both ends use `#|`, NOT `|#`

> **CRITICAL**: Comments use the SAME delimiter on both ends (`#|`). Do NOT extrapolate from the block/variable mirror pattern. The correct comment is `#| comment here #|`, **never** `#| comment here |#`.

**SOPS Encryption:** All `*.sops.yaml` files encrypted with Age.

### Networks (Configured via cluster.yaml)
- Node Network: `node_cidr` (e.g., 192.168.1.0/24)
- Pods: `cluster_pod_cidr` (default: 10.42.0.0/16)
- Services: `cluster_svc_cidr` (default: 10.43.0.0/16)
- LoadBalancers: `cluster_gateway_addr`, `cloudflare_gateway_addr`
- Internal DNS: `cluster_dns_gateway_addr` (only when NOT using UniFi DNS)

## Key Files

| Purpose | Path |
| ------- | ---- |
| **Task runner** | `Taskfile.yaml`, `.taskfiles/` |
| **Dev tools** | `.mise.toml` (managed by mise) |
| **AI assistants** | `.claude/` (agents, commands), `docs/ai-context/` |
| **Cluster config** | `cluster.yaml` (network, cloudflare, repo) |
| **Node config** | `nodes.yaml` (name, IP, disk, MAC, schematic) |
| **Infrastructure** | `infrastructure/` (OpenTofu configs, R2 backend) |
| **Template engine** | `makejinja.toml` |
| **SOPS rules** | `.sops.yaml` (generated) |
| Age encryption key | `age.key` (gitignored, NEVER commit) |
| **Detailed docs** | `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`, `docs/OPERATIONS.md` |

## Conventions

### Configuration
- Edit `cluster.yaml` and `nodes.yaml` for cluster settings
- NEVER edit files in `kubernetes/`, `talos/`, `bootstrap/`, or `infrastructure/` directly - they are generated
- After changes: `task configure` to regenerate

### Kubernetes/GitOps
- HelmReleases use OCI repositories for charts
- Secrets via SOPS/Age encryption
- All apps follow the standard template structure

### Template Variables
Required variables in `cluster.yaml`:
- `node_cidr`, `cluster_api_addr`, `cluster_gateway_addr`
- `cloudflare_domain`, `cloudflare_token`, `cloudflare_gateway_addr`
- `repository_name`

Optional UniFi DNS (replaces k8s_gateway - makes `cluster_dns_gateway_addr` unnecessary):
- `unifi_host`, `unifi_api_key` (requires UniFi Network v9.0.0+)
- When configured, `k8s_gateway_enabled=false` and `unifi_dns_enabled=true` (derived in plugin.py)
- See `docs/research/archive/implemented/external-dns-unifi-integration.md` for setup guide

Optional Cilium BGP Control Plane v2 (for multi-VLAN routing):
- `cilium_bgp_router_addr`, `cilium_bgp_router_asn`, `cilium_bgp_node_asn` (all three required)
- Optional: `cilium_lb_pool_cidr`, `cilium_bgp_hold_time`, `cilium_bgp_keepalive_time`, `cilium_bgp_graceful_restart`
- See `docs/guides/bgp-unifi-cilium-implementation.md` for setup guide

Optional Observability Stack (metrics, logs, traces):
- `monitoring_enabled` - Enable kube-prometheus-stack (Prometheus + Grafana + AlertManager)
- `hubble_enabled` - Enable Cilium Hubble network observability
- `loki_enabled` - Enable log aggregation with Loki + Alloy
- `tracing_enabled` - Enable distributed tracing with Tempo
- See `docs/guides/observability-stack-implementation.md` for setup guide

Optional RustFS Shared Object Storage (S3-compatible):
- `rustfs_enabled` - Enable RustFS for shared S3 storage
- `rustfs_subdomain` - Subdomain for RustFS Console UI (default: "rustfs", creates rustfs.${cloudflare_domain})
- When enabled, Loki automatically switches to SimpleScalable mode with S3 backend
- `rustfs_secret_key`, `loki_s3_access_key`, `loki_s3_secret_key` - SOPS-encrypted credentials
- ⚠️ **IMPORTANT**: RustFS does NOT support `mc admin` commands for user/policy management
- Loki access keys must be created manually via RustFS Console UI (port 9001)
- Tempo uses local filesystem storage by default, NOT RustFS/S3
- ⚠️ RustFS is currently alpha software (v1.0.0-alpha.78) - test before production
- See `docs/research/rustfs-shared-storage-loki-simplescalable-jan-2026.md` for implementation

Optional CiliumNetworkPolicies (zero-trust networking):
- `network_policies_enabled` - Enable namespace-scoped network policies
- `network_policies_mode` - "audit" (observe via Hubble) or "enforce" (active blocking)
- See `docs/research/cilium-network-policies-jan-2026.md` for policy designs

Optional Talos Backup (etcd snapshots to S3):
- `backup_s3_endpoint`, `backup_s3_bucket` (both required to enable)
- `backup_s3_region` - AWS SDK region (default: "us-east-1", any value works for S3-compatible storage)
- When configured, `talos_backup_enabled=true` (derived in plugin.py)
- See `docs/CONFIGURATION.md` for all backup settings

Optional CloudNativePG Operator (production PostgreSQL):
- `cnpg_enabled` - Enable CloudNativePG operator for PostgreSQL cluster management
- `cnpg_postgres_image` - PostgreSQL image (default: ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie)
- `cnpg_storage_class` - Storage class for PostgreSQL data volumes
- `cnpg_control_plane_only` - Run operator on control-plane nodes (default: true)
- When configured, `cnpg_enabled=true` (derived in plugin.py)
- Shared infrastructure dependency for Keycloak and other database-backed apps
- See `docs/guides/cnpg-implementation.md` for setup guide

Optional Barman Cloud Plugin (PostgreSQL backups):
- `cnpg_barman_plugin_enabled` - Enable Barman Cloud Plugin for S3 backups (requires cnpg_enabled)
- `cnpg_barman_plugin_version` - Plugin version (default: 0.10.0)
- `cnpg_barman_plugin_log_level` - Log level: debug, info, warn, error (default: info)
- Replaces deprecated in-tree barmanObjectStore with external plugin architecture
- Plugin provides barman-cloud binaries via sidecar (standard/minimal images work)
- Requires cert-manager for mTLS between plugin and CNPG operator
- Creates ObjectStore CRDs per cluster for backup destination configuration
- REF: https://cloudnative-pg.io/plugin-barman-cloud/docs/

Optional CloudNativePG Backups (requires RustFS + Barman Plugin):
- `cnpg_backup_enabled` - Enable PostgreSQL backups to RustFS S3
- `cnpg_s3_access_key`, `cnpg_s3_secret_key` - SOPS-encrypted credentials (created via RustFS Console)
- Backup credentials are separate from Loki S3 credentials

Optional pgvector Extension (AI/ML vector search):
- `cnpg_pgvector_enabled` - Enable pgvector via ImageVolume (requires cnpg_enabled)
- `cnpg_pgvector_image` - pgvector image (default: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie)
- `cnpg_pgvector_version` - pgvector version (default: 0.8.1)
- Mounted via ImageVolume pattern (Kubernetes 1.35+, PostgreSQL 18+ with extension_control_path)

Optional Keycloak OIDC Provider (Identity and Access Management):
- `keycloak_enabled` - Enable Keycloak deployment (official Keycloak Operator)
- `keycloak_subdomain` - Subdomain (default: "auth", creates auth.${cloudflare_domain})
- `keycloak_realm` - Realm name (default: "matherlynet")
- `keycloak_db_mode` - Database mode: "embedded" (dev) or "cnpg" (production)
- When keycloak_enabled, derives: `keycloak_hostname`, `keycloak_issuer_url`, `keycloak_jwks_uri`
- CNPG mode requires `cnpg_enabled: true`
- Uses CRD split pattern (operator Kustomization → instance Kustomization)
- See `docs/guides/keycloak-implementation.md` for setup guide

Optional Keycloak PostgreSQL Backup (requires RustFS):
- `keycloak_s3_access_key`, `keycloak_s3_secret_key` - SOPS-encrypted credentials (created via RustFS Console)
- `keycloak_backup_schedule` - Cron schedule for embedded mode pg_dump (default: "0 2 ** *")
- `keycloak_backup_retention_days` - Retention for embedded mode pg_dump (default: 7)
- When configured with rustfs_enabled, `keycloak_backup_enabled=true` (derived in plugin.py)
- Embedded mode: pg_dump CronJob to `keycloak-backups` bucket
- CNPG mode: barmanObjectStore with continuous WAL archiving

Optional Keycloak OpenTelemetry Tracing (requires tracing_enabled):
- `keycloak_tracing_enabled` - Enable trace export to Tempo via OTLP gRPC (default: false)
- `keycloak_tracing_sample_rate` - Sample rate 0.0-1.0 (default: "0.1" = 10%)
- When both `tracing_enabled` and `keycloak_tracing_enabled` are true, traces are exported to Tempo
- See `docs/guides/keycloak-implementation.md#opentelemetry-tracing-integration` for details

Optional Keycloak Config-CLI (GitOps realm management):
- `keycloak_config_cli_version` - Image tag format: `<cli-version>-<keycloak-version>` (default: "6.4.0-26.1.0")
- Replaces KeycloakRealmImport CRD which only supports one-time imports
- Supports incremental updates to existing realms without destroying user data
- Runs as Kubernetes Job after Keycloak is healthy via third Flux Kustomization
- See `docs/research/keycloak-configuration-as-code-gitops-jan-2026.md` for implementation details

Optional Social Identity Providers (requires keycloak_enabled):
- `google_idp_enabled`, `google_client_id`, `google_client_secret` - Google OAuth (OIDC)
- `github_idp_enabled`, `github_client_id`, `github_client_secret` - GitHub OAuth
- `microsoft_idp_enabled`, `microsoft_client_id`, `microsoft_client_secret`, `microsoft_tenant_id` - Microsoft Entra ID
- Each IdP conditionally added to Keycloak realm when `*_idp_enabled: true`
- See `docs/research/keycloak-social-identity-providers-integration-jan-2026.md` for setup guide

Optional IdP Role Mappers (automatic role assignment based on IdP attributes):
- `google_default_role` - Hardcoded role for all Google users
- `google_domain_role_mapping` - Map Google Workspace domain (`hd` claim) to role
- `github_default_role` - Hardcoded role for all GitHub users
- `github_org_role_mapping` - Map GitHub organization membership to role (requires `read:org` scope)
- `microsoft_default_role` - Hardcoded role for all Microsoft users
- `microsoft_group_role_mappings` - Map Entra ID group ObjectIDs to roles (requires Azure "groups" claim)
- Mappers are conditionally generated in `realm-import.yaml.j2` when variables are defined
- See `docs/research/keycloak-social-identity-providers-integration-jan-2026.md#phase-3-rolegroup-mappers` for details

Optional Grafana Dashboards (requires monitoring_enabled):
- `keycloak_monitoring_enabled` - Deploy Keycloak ServiceMonitor + Grafana dashboards (default: false)
- `rustfs_monitoring_enabled` - Deploy RustFS ServiceMonitor + Grafana dashboards (default: false)
- `loki_monitoring_enabled` - Deploy supplemental Loki stack monitoring dashboard (default: false)
- `litellm_monitoring_enabled` - Deploy LiteLLM ServiceMonitor + Grafana dashboards (default: false)
- When component + monitoring_enabled are both true, deploys ServiceMonitor and dashboards
- See `docs/guides/grafana-dashboards-implementation.md` for details

Optional LiteLLM Proxy Gateway (AI model gateway):
- `litellm_enabled` - Enable LiteLLM deployment (bjw-s app-template Helm chart)
- `litellm_subdomain` - Subdomain (default: "litellm", creates litellm.${cloudflare_domain})
- `litellm_master_key` - SOPS-encrypted master key for API authentication
- `litellm_salt_key` - SOPS-encrypted salt key for credential encryption
- `litellm_db_password` - SOPS-encrypted PostgreSQL password
- When litellm_enabled, derives: `litellm_hostname`
- Requires `cnpg_enabled: true` for PostgreSQL database
- Requires `dragonfly_enabled: true` and `dragonfly_acl_enabled: true` for caching
- Uses shared Dragonfly cache via `dragonfly_litellm_password` (ACL: `litellm:*` keys)
- See `docs/research/litellm-proxy-gateway-integration-jan-2026.md` for setup guide

Optional LiteLLM AI Provider API Keys (SOPS-encrypted):
- `azure_openai_us_east_api_key` - Azure OpenAI US East region
- `azure_openai_us_east2_api_key` - Azure OpenAI US East2 region
- `azure_anthropic_api_key` - Azure AI Services (Claude models)
- `azure_cohere_embed_api_key` - Azure Cohere Embed API
- `azure_cohere_rerank_api_key` - Azure Cohere Rerank API
- Provider keys are conditionally included in secrets and network policies

Optional LiteLLM OIDC SSO (requires keycloak_enabled):
- `litellm_oidc_enabled` - Enable Keycloak SSO for LiteLLM UI (default: false)
- `litellm_oidc_client_secret` - SOPS-encrypted OIDC client secret
- When enabled, creates `litellm` client in Keycloak realm-config
- See `docs/research/litellm-proxy-gateway-integration-jan-2026.md` for details

Optional LiteLLM Langfuse Observability:
- `litellm_langfuse_enabled` - Enable Langfuse LLM observability (default: false)
- `litellm_langfuse_public_key`, `litellm_langfuse_secret_key` - SOPS-encrypted API keys
- `litellm_langfuse_host` - Langfuse host URL (auto-derived: internal for self-hosted, cloud.langfuse.com otherwise)
- When enabled, `litellm_langfuse_enabled=true` (derived in plugin.py)
- See `docs/research/langfuse-llm-observability-integration-jan-2026.md` for setup guide

Optional LiteLLM PostgreSQL Backup (requires RustFS):
- `litellm_s3_access_key`, `litellm_s3_secret_key` - SOPS-encrypted S3 credentials
- When configured with rustfs_enabled, `litellm_backup_enabled=true` (derived in plugin.py)
- Uses CNPG barmanObjectStore with continuous WAL archiving

Optional LiteLLM OpenTelemetry Tracing (requires tracing_enabled):
- `litellm_tracing_enabled` - Enable trace export to Tempo via OTLP gRPC (default: false)
- When both `tracing_enabled` and `litellm_tracing_enabled` are true, traces are exported to Tempo

Optional Dragonfly Cache (Redis-compatible in-memory data store):
- `dragonfly_enabled` - Enable Dragonfly Operator for shared Redis-compatible cache
- `dragonfly_version` - Dragonfly image tag (default: "v1.36.0")
- `dragonfly_operator_version` - Operator Helm chart version (default: "1.3.1")
- `dragonfly_replicas` - Number of Dragonfly instances (default: 1)
- `dragonfly_maxmemory` - Maximum memory allocation (default: "512mb")
- `dragonfly_password` - SOPS-encrypted password for default user
- Provides 25x better performance than Redis with full API compatibility
- When configured, `dragonfly_enabled=true` (derived in plugin.py)
- See `docs/research/dragonfly-redis-alternative-integration-jan-2026.md` for setup guide

Optional Dragonfly Backups (requires RustFS):
- `dragonfly_backup_enabled` - Enable S3 snapshots to RustFS
- `dragonfly_s3_access_key`, `dragonfly_s3_secret_key` - SOPS-encrypted credentials
- `dragonfly_snapshot_cron` - Snapshot schedule (default: "0 */6* **")
- When configured with rustfs_enabled, `dragonfly_backup_enabled=true` (derived in plugin.py)

Optional Dragonfly Monitoring (requires monitoring_enabled):
- `dragonfly_monitoring_enabled` - Deploy PodMonitor + PrometheusRule + Grafana dashboard
- When both monitoring_enabled and dragonfly_monitoring_enabled are true, deploys observability

Optional Dragonfly ACL (multi-tenant access control):
- `dragonfly_acl_enabled` - Enable per-application ACL users
- `dragonfly_keycloak_password` - SOPS-encrypted password for Keycloak session cache
- `dragonfly_appcache_password` - SOPS-encrypted password for general app cache
- `dragonfly_litellm_password` - SOPS-encrypted password for LiteLLM cache
- `dragonfly_langfuse_password` - SOPS-encrypted password for Langfuse cache
- Uses ACL ConfigMap pattern for secure namespace isolation

Optional Langfuse LLM Observability Platform:
- `langfuse_enabled` - Enable Langfuse deployment for LLM tracing and analytics
- `langfuse_subdomain` - Subdomain (default: "langfuse", creates langfuse.${cloudflare_domain})
- `langfuse_nextauth_secret` - SOPS-encrypted session secret (generate with: openssl rand -base64 32)
- `langfuse_salt` - SOPS-encrypted API key salt (generate with: openssl rand -base64 32)
- `langfuse_encryption_key` - SOPS-encrypted 256-bit hex key (generate with: openssl rand -hex 32)
- `langfuse_postgres_password` - SOPS-encrypted PostgreSQL password
- `langfuse_clickhouse_password` - SOPS-encrypted ClickHouse password
- `langfuse_clickhouse_cluster_enabled` - Enable ClickHouse cluster mode (default: false)
- `langfuse_log_level` - Log level: trace, debug, info, warn, error, fatal (default: "info")
- `langfuse_log_format` - Log format: text or json (default: "text")
- When langfuse_enabled, derives: `langfuse_hostname`, `langfuse_url`
- Requires `cnpg_enabled: true` for PostgreSQL database
- Requires `dragonfly_enabled: true` for Redis-compatible caching
- Integrates with LiteLLM via callbacks for automatic trace ingestion
- See `docs/research/langfuse-llm-observability-integration-jan-2026.md` for setup guide

Optional Langfuse S3 Storage (requires RustFS):
- `langfuse_s3_access_key`, `langfuse_s3_secret_key` - SOPS-encrypted credentials
- `langfuse_s3_concurrent_writes`, `langfuse_s3_concurrent_reads` - S3 connection pool (default: 50)
- `langfuse_media_bucket` - Media uploads bucket (default: "langfuse-media")
- `langfuse_export_bucket` - Batch exports bucket (default: "langfuse-exports")
- `langfuse_media_max_size` - Max file size in bytes (default: 1GB)
- `langfuse_batch_export_enabled` - Enable batch export feature (default: true)
- Required buckets: `langfuse-events`, `langfuse-media`, `langfuse-exports`
- Create buckets and credentials via RustFS Console UI (port 9001)

Optional Langfuse PostgreSQL Backup (requires RustFS):
- `langfuse_backup_enabled` - Enable PostgreSQL backups to RustFS S3
- `langfuse_backup_s3_access_key`, `langfuse_backup_s3_secret_key` - SOPS-encrypted credentials
- Required bucket: `langfuse-postgres-backups`
- Uses CNPG barmanObjectStore with continuous WAL archiving

Optional Langfuse SSO (requires Keycloak):
- `langfuse_sso_enabled` - Enable Keycloak OIDC authentication (default: false)
- `langfuse_keycloak_client_secret` - SOPS-encrypted OIDC client secret
- When enabled, creates `langfuse` client in Keycloak realm-config
- Supports account linking with existing email-based accounts

Optional Langfuse Authentication Configuration:
- `langfuse_disable_password_auth` - Disable username/password login, SSO-only mode (default: false)
- `langfuse_sso_domain_enforcement` - Comma-separated domains requiring SSO (e.g., "example.com,company.org")

Optional Langfuse Caching Configuration (requires Redis/Dragonfly):
- `langfuse_cache_api_key_enabled` - Enable API key caching (default: true)
- `langfuse_cache_api_key_ttl` - API key cache TTL in seconds (default: 300)
- `langfuse_cache_prompt_enabled` - Enable prompt caching (default: true)
- `langfuse_cache_prompt_ttl` - Prompt cache TTL in seconds (default: 300)

Optional Langfuse Observability (requires monitoring/tracing):
- `langfuse_monitoring_enabled` - Deploy ServiceMonitor for Prometheus metrics + Grafana dashboard
- `langfuse_tracing_enabled` - Export Langfuse's own traces to Tempo via OTLP

Optional Langfuse Email (for notifications, invitations, password resets):
- `langfuse_smtp_url` - SOPS-encrypted SMTP URL (format: smtp://user:pass@host:port)
- `langfuse_email_from` - Sender address (default: noreply@${cloudflare_domain})

Optional Langfuse Session Configuration:
- `langfuse_session_max_age` - Session duration in seconds (default: 2592000 = 30 days)

Optional Langfuse Headless Initialization (Bootstrap Admin Account):
- `langfuse_init_org_id` - Organization identifier (slug format: lowercase alphanumeric with hyphens, 2-63 chars)
- `langfuse_init_org_name` - Initial organization display name (default: derived from cluster_name)
- `langfuse_init_user_email` - Initial admin email (SOPS-encrypted)
- `langfuse_init_user_password` - Initial admin password (SOPS-encrypted, generate with: openssl rand -base64 24)
- `langfuse_init_user_name` - Initial admin display name (default: "Admin")
- `langfuse_disable_signup` - Disable new user signups for security hardening (default: false)
- All three required variables (org_id, user_email, user_password) must be set to enable headless initialization
- Credentials are only used once on first startup - change via UI after first login
- See `docs/research/langfuse-llm-observability-integration-jan-2026.md` for setup guide

Optional Langfuse Project Initialization (Create Initial Project):
- `langfuse_init_project_id` - Project identifier (slug format: lowercase alphanumeric with hyphens, 2-63 chars)
- `langfuse_init_project_name` - Project display name (default: "Default Project")
- `langfuse_init_project_retention` - Data retention in days (1-3650, omit for indefinite)
- `langfuse_init_project_public_key` - Public API key (format: lf_pk_*, SOPS-encrypted)
- `langfuse_init_project_secret_key` - Secret API key (format: lf_sk_*, SOPS-encrypted)
- Requires headless initialization (org_id, user_email, user_password) to be configured
- Provides immediate API access after bootstrap without manual project creation

Optional Langfuse Auto-Provisioning (Default Access for SSO Users):
- `langfuse_default_org_id` - Organization ID for new SSO users (default: langfuse_init_org_id)
- `langfuse_default_org_role` - Default org role for new SSO users: OWNER, ADMIN, MEMBER, VIEWER, NONE
- `langfuse_default_project_id` - Project ID for new SSO users (default: langfuse_init_project_id)
- `langfuse_default_project_role` - Default project role for new SSO users: OWNER, ADMIN, MEMBER, VIEWER
- When set, new users via SSO are automatically assigned to default org/project with these roles
- See https://langfuse.com/self-hosting/administration/automated-access-provisioning for details

Optional Obot MCP Gateway (AI Agent Platform):
- `obot_enabled` - Enable Obot deployment (jrmatherly/obot-entraid Helm chart)
- `obot_subdomain` - Subdomain (default: "obot", creates obot.${cloudflare_domain})
- `obot_version` - Obot image version (default: "0.2.30")
- `obot_replicas` - Pod replicas (default: 1)
- `obot_db_password` - SOPS-encrypted PostgreSQL password
- `obot_encryption_key` - SOPS-encrypted 32-byte base64 key for data encryption (generate with: openssl rand -base64 32)
- `obot_bootstrap_token` - SOPS-encrypted bootstrap token for initial setup (generate with: openssl rand -hex 32)
- When obot_enabled, derives: `obot_hostname`
- Requires `cnpg_enabled: true` for PostgreSQL database with pgvector
- See `docs/research/obot-mcp-gateway-integration-jan-2026.md` for setup guide

Optional Obot Keycloak SSO (requires keycloak_enabled):
- `obot_keycloak_enabled` - Enable Keycloak authentication (default: false)
- `obot_keycloak_client_id` - OIDC client ID (default: "obot")
- `obot_keycloak_client_secret` - SOPS-encrypted OIDC client secret
- `obot_keycloak_cookie_secret` - SOPS-encrypted cookie encryption key (generate with: openssl rand -base64 32)
- `obot_keycloak_allowed_groups` - Optional comma-separated group restrictions
- `obot_keycloak_allowed_roles` - Optional comma-separated role restrictions
- When enabled, creates `obot` client in Keycloak realm-config with PKCE S256
- Uses custom auth provider from jrmatherly/obot-entraid fork

Optional Obot MCP Namespace (Kubernetes MCP server hosting):
- `obot_mcp_namespace` - Namespace for MCP server pods (default: "obot-mcp")
- `obot_mcp_cpu_requests_quota`, `obot_mcp_cpu_limits_quota` - CPU quotas (default: "4", "8")
- `obot_mcp_memory_requests_quota`, `obot_mcp_memory_limits_quota` - Memory quotas (default: "8Gi", "16Gi")
- `obot_mcp_max_pods` - Maximum MCP server pods (default: 20)
- `obot_mcp_default_cpu_request`, `obot_mcp_default_cpu_limit` - Default container CPU (default: "100m", "500m")
- `obot_mcp_default_memory_request`, `obot_mcp_default_memory_limit` - Default container memory (default: "256Mi", "512Mi")
- `obot_mcp_max_cpu`, `obot_mcp_max_memory` - Max container resources (default: "1000m", "1Gi")
- MCP namespace uses restricted Pod Security Standards

Optional Obot PostgreSQL Backup (requires RustFS):
- `obot_s3_access_key`, `obot_s3_secret_key` - SOPS-encrypted S3 credentials
- When configured with rustfs_enabled, `obot_backup_enabled=true` (derived in plugin.py)
- Uses CNPG barmanObjectStore with continuous WAL archiving

Optional Obot Observability (requires monitoring/tracing):
- `obot_monitoring_enabled` - Deploy ServiceMonitor for Prometheus metrics + Grafana dashboard
- `obot_tracing_enabled` - Enable trace export to Tempo via OTLP gRPC

Optional Obot LiteLLM Integration (requires litellm_enabled):
- `obot_litellm_enabled` - Use LiteLLM as model gateway (default: true when litellm_enabled)
- When enabled, configures Obot to route LLM requests through internal LiteLLM proxy

Optional OIDC/JWT Authentication (Envoy Gateway SecurityPolicy):
- `oidc_issuer_url`, `oidc_jwks_uri` (both required to enable)
- When configured, `oidc_enabled=true` (derived in plugin.py)
- Creates SecurityPolicy targeting HTTPRoutes with label `security: jwt-protected`
- Note: Keycloak auto-derives these values when keycloak_enabled is true

Optional Proxmox Infrastructure (VM provisioning via OpenTofu):
- `proxmox_api_url`, `proxmox_node` (both required to enable)
- `proxmox_vlan_mode` - When `true`, Proxmox handles VLAN tagging (access port mode); when `false` (default), Talos creates VLAN sub-interfaces (trunk port / bare-metal mode). Set to `true` when using Proxmox with `node_vlan_tag`.
- When configured, `infrastructure_enabled=true` and OpenTofu configs are generated
- Role-based VM defaults with 3-tier fallback chain:
  - `proxmox_vm_controller_defaults` - Controller nodes (4 cores, 8GB, 64GB disk)
  - `proxmox_vm_worker_defaults` - Worker nodes (8 cores, 16GB, 256GB disk)
  - `proxmox_vm_defaults` - Global fallback
- Per-node overrides via `vm_cores`, `vm_memory`, `vm_disk_size` in nodes.yaml
- Fallback chain: per-node → role-defaults → global-defaults
- See `docs/CONFIGURATION.md` for complete Proxmox settings

Derived Variables (computed in `templates/scripts/plugin.py`):
- `cilium_bgp_enabled` - true when all 3 BGP keys set
- `unifi_dns_enabled` - true when unifi_host + unifi_api_key set
- `k8s_gateway_enabled` - true when unifi_dns_enabled is false (mutually exclusive)
- `talos_backup_enabled` - true when backup_s3_endpoint + backup_s3_bucket set
- `oidc_enabled` - true when oidc_issuer_url + oidc_jwks_uri set
- `spegel_enabled` - true when >1 node (can be overridden by user)
- `infrastructure_enabled` - true when proxmox_api_url + proxmox_node set
- `proxmox_vm_controller_defaults` - Merged controller VM settings
- `proxmox_vm_worker_defaults` - Merged worker VM settings
- `rustfs_enabled` - true when rustfs_enabled is explicitly set to true
- `loki_deployment_mode` - "SimpleScalable" when rustfs_enabled, "SingleBinary" otherwise
- `cnpg_enabled` - true when cnpg_enabled is explicitly set to true
- `cnpg_barman_plugin_enabled` - true when cnpg_enabled and cnpg_barman_plugin_enabled both true
- `cnpg_backup_enabled` - true when cnpg + rustfs + backup flag + credentials all set
- `cnpg_pgvector_enabled` - true when cnpg_enabled and cnpg_pgvector_enabled both true
- `keycloak_enabled` - true when keycloak_enabled is explicitly set to true
- `keycloak_hostname` - auto-derived from keycloak_subdomain + cloudflare_domain
- `keycloak_issuer_url` - auto-derived OIDC issuer URL for SecurityPolicy
- `keycloak_jwks_uri` - auto-derived JWKS endpoint for JWT validation
- `keycloak_backup_enabled` - true when rustfs_enabled + keycloak S3 credentials set
- `keycloak_tracing_enabled` - true when tracing_enabled + keycloak_tracing_enabled both true
- `keycloak_monitoring_enabled` - true when monitoring_enabled + keycloak_monitoring_enabled both true
- `rustfs_monitoring_enabled` - true when monitoring_enabled + rustfs_monitoring_enabled both true
- `loki_monitoring_enabled` - true when monitoring_enabled + loki_monitoring_enabled both true
- `grafana_oidc_enabled` - true when monitoring_enabled + keycloak_enabled + grafana_oidc_enabled + grafana_oidc_client_secret all set
- `litellm_enabled` - true when litellm_enabled is explicitly set to true
- `litellm_hostname` - auto-derived from litellm_subdomain + cloudflare_domain
- `litellm_oidc_enabled` - true when keycloak_enabled + litellm_oidc_enabled + litellm_oidc_client_secret all set
- `litellm_backup_enabled` - true when rustfs_enabled + litellm S3 credentials set
- `litellm_monitoring_enabled` - true when monitoring_enabled + litellm_monitoring_enabled both true
- `litellm_tracing_enabled` - true when tracing_enabled + litellm_tracing_enabled both true
- `litellm_langfuse_enabled` - true when litellm_langfuse_enabled + public_key + secret_key all set
- `litellm_langfuse_host` - auto-derived: internal cluster URL when langfuse_enabled, cloud.langfuse.com otherwise
- `dragonfly_enabled` - true when dragonfly_enabled is explicitly set to true
- `dragonfly_backup_enabled` - true when rustfs_enabled + dragonfly_backup_enabled + dragonfly S3 credentials all set
- `dragonfly_monitoring_enabled` - true when monitoring_enabled + dragonfly_monitoring_enabled both true
- `dragonfly_acl_enabled` - true when dragonfly_acl_enabled is explicitly set to true
- `langfuse_enabled` - true when langfuse_enabled is explicitly set to true
- `langfuse_hostname` - auto-derived from langfuse_subdomain + cloudflare_domain
- `langfuse_url` - auto-derived HTTPS URL for Langfuse web UI
- `langfuse_sso_enabled` - true when keycloak_enabled + langfuse_sso_enabled + langfuse_keycloak_client_secret all set
- `langfuse_backup_enabled` - true when rustfs_enabled + langfuse_backup_enabled + langfuse S3 credentials all set
- `langfuse_monitoring_enabled` - true when monitoring_enabled + langfuse_monitoring_enabled both true
- `langfuse_tracing_enabled` - true when tracing_enabled + langfuse_tracing_enabled both true
- `obot_enabled` - true when obot_enabled is explicitly set to true
- `obot_hostname` - auto-derived from obot_subdomain + cloudflare_domain
- `obot_keycloak_enabled` - true when keycloak_enabled + obot_keycloak_enabled + obot_keycloak_client_secret all set
- `obot_keycloak_base_url` - auto-derived Keycloak base URL (without /realms/)
- `obot_keycloak_issuer_url` - auto-derived OIDC issuer URL
- `obot_keycloak_realm` - auto-derived from keycloak_realm
- `obot_backup_enabled` - true when rustfs_enabled + obot S3 credentials set
- `obot_monitoring_enabled` - true when monitoring_enabled + obot_monitoring_enabled both true
- `obot_tracing_enabled` - true when tracing_enabled + obot_tracing_enabled both true
- `obot_litellm_enabled` - true when litellm_enabled + obot_litellm_enabled both true

See `docs/CONFIGURATION.md` for complete schema reference.

## AI Assistants

### Slash Commands

| Command | Purpose |
| ------- | ------- |
| `/expert-mode` | Load project context efficiently |
| `/flux-status` | Check Flux GitOps health |
| `/flux-reconcile` | Force reconcile Flux resources |
| `/talos-status` | Check Talos node health |
| `/infra-status` | Check OpenTofu state/resources |
| `/deploy-check` | Verify deployment status |
| `/debug-network` | Network diagnostics |

### Agents

| Agent | Use For |
| ----- | ------- |
| `talos-expert` | Talos node operations, upgrades, patches |
| `flux-expert` | Flux troubleshooting, reconciliation issues |
| `template-expert` | makejinja templates, Jinja2 patterns |
| `network-debugger` | Cilium/Gateway debugging, connectivity |
| `infra-expert` | OpenTofu/Proxmox IaC operations |

### Domain Documentation
Deep context in `docs/ai-context/`:
- `flux-gitops.md` - Flux architecture & patterns
- `talos-operations.md` - Talos workflows
- `cilium-networking.md` - Cilium CNI patterns
- `template-system.md` - makejinja templating
- `infrastructure-opentofu.md` - OpenTofu IaC & R2 backend

## Troubleshooting Quick Reference

| Issue | Command |
| ----- | ------- |
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| CNI issues | `cilium status`, `cilium connectivity test` |
| BGP issues | `cilium bgp peers`, `kubectl get ciliumbgpclusterconfig -A` |
| Certificate issues | `kubectl get certificates -A` |
| OpenTofu state lock | `task infra:force-unlock LOCK_ID=xxx` |
| OpenTofu auth issues | Check credentials in `cluster.yaml`, run `task configure` |
| Monitoring not working | `flux get hr -n monitoring`, `kubectl -n monitoring get pods` |
| Hubble not visible | `hubble status`, `kubectl -n kube-system port-forward svc/hubble-relay 4245:80` |
| Network policy blocking | `hubble observe --verdict DROPPED`, `kubectl get cnp -A` |
| RustFS not ready | `kubectl get pods -n storage`, `kubectl logs -n storage -l app.kubernetes.io/name=rustfs` |
| Loki S3 errors | `kubectl logs -n monitoring -l app.kubernetes.io/component=write` |
| CNPG operator issues | `kubectl get pods -n cnpg-system`, `kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg` |
| PostgreSQL cluster issues | `kubectl cnpg status <cluster> -n <namespace>`, `kubectl get clusters -A` |
| Keycloak operator issues | `kubectl get pods -n identity -l app.kubernetes.io/name=keycloak-operator` |
| Keycloak CR not ready | `kubectl -n identity get keycloak keycloak -o yaml`, `kubectl -n identity logs -l app.kubernetes.io/name=keycloak` |
| Keycloak DB connection | `kubectl -n identity exec -it keycloak-postgres-0 -- psql -U keycloak -c "SELECT 1"` |
| Talos backup failing | `kubectl -n kube-system logs -l app.kubernetes.io/name=talos-backup` (check env vars: CUSTOM_S3_ENDPOINT, BUCKET, USE_PATH_STYLE=false) |
| Dragonfly operator issues | `kubectl get pods -n dragonfly-operator-system`, `kubectl logs -n dragonfly-operator-system -l app.kubernetes.io/name=dragonfly-operator` |
| Dragonfly instance issues | `kubectl get dragonfly -n cache`, `kubectl -n cache logs -l app=dragonfly` |
| Dragonfly connectivity | `kubectl -n cache exec -it dragonfly-0 -- redis-cli -a $PASSWORD ping` |
| Langfuse web not ready | `kubectl get pods -n ai-system -l app.kubernetes.io/name=langfuse`, `kubectl -n ai-system logs -l app.kubernetes.io/component=web` |
| Langfuse worker issues | `kubectl -n ai-system logs -l app.kubernetes.io/component=worker` |
| Langfuse DB connection | `kubectl -n ai-system exec -it langfuse-postgresql-1 -- psql -U langfuse -c "SELECT 1"` |
| Langfuse ClickHouse | `kubectl -n ai-system logs -l app.kubernetes.io/name=clickhouse` |
| Obot not ready | `kubectl get pods -n ai-system -l app.kubernetes.io/name=obot`, `kubectl -n ai-system logs -l app.kubernetes.io/name=obot` |
| Obot DB connection | `kubectl -n ai-system exec -it obot-postgresql-1 -- psql -U obot -d obot -c "SELECT 1"` |
| Obot Keycloak auth | `kubectl -n ai-system logs -l app.kubernetes.io/name=obot` (check OBOT_KEYCLOAK_AUTH_PROVIDER_* env vars) |
| MCP namespace issues | `kubectl get pods -n obot-mcp`, `kubectl get resourcequota -n obot-mcp` |
| MCP server network issues | `hubble observe -n obot-mcp --verdict DROPPED`, `kubectl get cnp -n obot-mcp` |

For comprehensive troubleshooting with diagnostic flowcharts and decision trees, see `docs/TROUBLESHOOTING.md`.

For complete CLI command reference, see `docs/CLI_REFERENCE.md`.
