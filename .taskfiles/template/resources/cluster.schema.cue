package config

import (
	"net"
	"strings"
)

#Config: {
	node_cidr: net.IPCIDR & !=cluster_pod_cidr & !=cluster_svc_cidr
	node_dns_servers?: [...net.IPv4]
	node_ntp_servers?: [...net.IPv4]
	node_default_gateway?: net.IPv4 & !=""
	node_vlan_tag?: string & !=""
	// When true, Proxmox handles VLAN tagging (access port mode) and Talos sees untagged traffic
	// When false (default), Talos creates VLAN sub-interfaces (trunk port / bare-metal mode)
	proxmox_vlan_mode?: *false | bool
	cluster_pod_cidr: *"10.42.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_svc_cidr
	cluster_svc_cidr: *"10.43.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_pod_cidr
	cluster_api_addr: net.IPv4
	cluster_api_tls_sans?: [...net.FQDN]
	cluster_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cloudflare_gateway_addr
	// cluster_dns_gateway_addr is only required when NOT using UniFi DNS integration
	// When unifi_host and unifi_api_key are set, k8s-gateway is replaced by external-dns-unifi
	cluster_dns_gateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cloudflare_gateway_addr
	repository_name: string
	repository_branch?: string & !=""
	repository_visibility?: *"public" | "private"
	cloudflare_domain: net.FQDN
	cloudflare_token: string
	// NOTE: Cannot constrain against optional cluster_dns_gateway_addr - that constraint is on line 20 instead
	cloudflare_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr
	// Cilium LoadBalancer configuration
	cilium_loadbalancer_mode?: *"dsr" | "snat"

	// Cilium BGP Configuration - Optional for multi-VLAN environments
	// REF: https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/
	cilium_bgp_router_addr?:          net.IPv4 & !=""
	cilium_bgp_router_asn?:           string & =~"^[0-9]+$"
	cilium_bgp_node_asn?:             string & =~"^[0-9]+$"
	cilium_lb_pool_cidr?:             net.IPCIDR
	cilium_bgp_hold_time?:            *30 | int & >=3 & <=300
	cilium_bgp_keepalive_time?:       *10 | int & >=1 & <=100
	cilium_bgp_graceful_restart?:     *false | bool
	cilium_bgp_graceful_restart_time?: *120 | int & >=30 & <=600
	cilium_bgp_ecmp_max_paths?:       *3 | int & >=1 & <=16
	cilium_bgp_password?:             string & !=""

	// UniFi DNS Integration - Optional for internal DNS via external-dns webhook
	// Requires UniFi Network v9.0.0+ for API key authentication (current stable: 9.5.21)
	unifi_host?:                string & =~"^https?://"
	unifi_api_key?:             string & !=""
	unifi_site?:                *"default" | string & !=""
	unifi_external_controller?: *false | bool

	// Talos Upgrade Controller (tuppr) - Automated OS/K8s upgrades
	talos_version?:      *"1.12.0" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"
	kubernetes_version?: *"1.35.0" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"

	// Talos Backup - Automated etcd snapshots with S3 storage
	backup_s3_endpoint?:    string & =~"^https?://"
	backup_s3_bucket?:      string & !=""
	backup_s3_access_key?:  string & !=""
	backup_s3_secret_key?:  string & !=""
	backup_s3_region?:      *"us-east-1" | string & !=""  // Required by AWS SDK, any value works for S3-compatible
	backup_age_public_key?: string & =~"^age1"

	// Proxmox CSI Configuration - Optional for persistent storage
	// Requires Proxmox API token with storage permissions
	proxmox_csi_enabled?:      *false | bool
	proxmox_endpoint?:         string & =~"^https?://"
	proxmox_csi_token_id?:     string & =~"^.+@.+!.+$"  // format: user@realm!token-name
	proxmox_csi_token_secret?: string & !=""
	proxmox_csi_storage?:      string & !=""
	proxmox_region?:           *"pve" | string & !=""

	// Proxmox CCM Configuration - Optional for node labeling/lifecycle
	// Use Proxmox CCM instead of Talos CCM when running on Proxmox infrastructure
	// NOTE: Talos CCM and Proxmox CCM are mutually exclusive
	proxmox_ccm_enabled?:      *false | bool
	proxmox_ccm_token_id?:     string & =~"^.+@.+!.+$"  // format: user@realm!token-name
	proxmox_ccm_token_secret?: string & !=""

	// Infrastructure (OpenTofu/Proxmox) - Optional for VM deployments
	proxmox_api_url?:      string & =~"^https?://"
	proxmox_node?:         string & !=""
	proxmox_iso_storage?:  *"local" | string & !=""
	proxmox_disk_storage?: *"local-lvm" | string & !=""
	proxmox_vm_defaults?: {
		cores?:     *4 | int & >=1 & <=64
		sockets?:   *1 | int & >=1 & <=4
		memory?:    *8192 | int & >=1024 & <=262144
		disk_size?: *128 | int & >=32 & <=4096
	}
	// Controller node VM defaults (optimized for etcd and control plane)
	// Fallback chain: per-node -> controller-defaults -> global-defaults
	proxmox_vm_controller_defaults?: {
		cores?:     *4 | int & >=1 & <=64
		sockets?:   *1 | int & >=1 & <=4
		memory?:    *8192 | int & >=1024 & <=262144
		disk_size?: *64 | int & >=32 & <=4096
	}
	// Worker node VM defaults (optimized for running workloads)
	// Fallback chain: per-node -> worker-defaults -> global-defaults
	proxmox_vm_worker_defaults?: {
		cores?:     *8 | int & >=1 & <=64
		sockets?:   *1 | int & >=1 & <=4
		memory?:    *16384 | int & >=1024 & <=262144
		disk_size?: *256 | int & >=32 & <=4096
	}
	proxmox_vm_advanced?: {
		bios?:         *"ovmf" | "seabios"
		machine?:      *"q35" | "i440fx"
		cpu_type?:     *"host" | string & !=""
		scsi_hw?:      *"virtio-scsi-pci" | "virtio-scsi-single" | "lsi"
		balloon?:      *0 | int & >=0
		numa?:         *true | bool
		qemu_agent?:   *true | bool
		net_queues?:   *4 | int & >=1 & <=16
		disk_discard?: *true | bool
		disk_ssd?:     *true | bool
		tags?: [...string]
		// Network configuration
		network_bridge?: *"vmbr0" | string & !=""
		// Guest OS configuration
		ostype?: *"l26" | "l24" | "win10" | "win11" | string & !=""
		// Storage flags (Talos-optimized defaults)
		disk_backup?:    *false | bool
		disk_replicate?: *false | bool
	}
	// Infrastructure API Token - for OpenTofu VM provisioning
	// NOTE: Separate from proxmox_csi_token and proxmox_ccm_token for least-privilege
	proxmox_api_token_id?:     string & =~"^.+@.+!.+$"  // format: user@realm!token-name
	proxmox_api_token_secret?: string & !=""

	// Cloudflare Account (for R2 state backend)
	// Dashboard → Overview → Account ID (right sidebar)
	cf_account_id?: string & !=""

	// OpenTofu R2 State Backend Credentials
	// Must match secrets configured in your tfstate-worker deployment
	tfstate_username?: *"terraform" | string & !=""
	tfstate_password?: string & !=""

	// Observability - Monitoring Stack (kube-prometheus-stack: Prometheus + Grafana + AlertManager)
	// Full-stack observability with metrics, logs, and distributed tracing
	monitoring_enabled?:      *false | bool
	monitoring_stack?:        *"prometheus" | string & =~"^prometheus$"
	hubble_enabled?:          *false | bool
	hubble_ui_enabled?:       *false | bool
	grafana_subdomain?:       *"grafana" | string & !=""
	grafana_admin_user?:      *"admin" | string & !=""
	grafana_admin_password?:  string & =~".{8,}"  // Minimum 8 characters
	metrics_retention?:       *"7d" | string & =~"^[0-9]+[dhw]$"
	metrics_storage_size?:    *"50Gi" | string & =~"^[0-9]+[KMGT]i$"
	storage_class?:           *"local-path" | string & !=""

	// Observability - Infrastructure Alerts (PrometheusRule)
	monitoring_alerts_enabled?: *true | bool
	node_memory_threshold?:     *90 | int & >=50 & <=99
	node_cpu_threshold?:        *90 | int & >=50 & <=99

	// Observability - Log Aggregation (Loki + Alloy)
	loki_enabled?:       *false | bool
	logs_retention?:     *"7d" | string & =~"^[0-9]+[dhw]$"
	logs_storage_size?:  *"50Gi" | string & =~"^[0-9]+[KMGT]i$"

	// Observability - Distributed Tracing (Tempo)
	tracing_enabled?:        *false | bool
	tracing_sample_rate?:    *10 | int & >=1 & <=100
	trace_retention?:        *"72h" | string & =~"^[0-9]+[hd]$"
	trace_storage_size?:     *"10Gi" | string & =~"^[0-9]+[KMGT]i$"
	cluster_name?:           *"matherlynet" | string & !=""
	observability_namespace?: *"monitoring" | string & !=""
	environment?:            *"production" | "staging" | "development"

	// OIDC/JWT Configuration - Optional for API authentication via SecurityPolicy
	// REF: https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/
	oidc_provider_name?: *"keycloak" | string & !=""
	oidc_issuer_url?:    string & =~"^https?://"
	oidc_jwks_uri?:      string & =~"^https?://"
	oidc_additional_claims?: [...{
		name:   string & !=""
		header: string & =~"^X-"
	}]

	// OIDC Web SSO Configuration - Session-based authentication for web apps
	// Distinct from JWT SecurityPolicy - this enables browser-based SSO with cookie sessions
	// REF: https://gateway.envoyproxy.io/docs/tasks/security/oidc/
	// REF: docs/guides/native-oidc-securitypolicy-implementation.md
	oidc_sso_enabled?:   *false | bool
	oidc_client_id?:     string
	oidc_client_secret?: string  // Generate: openssl rand -hex 32 (MUST use hex, NOT base64)
	oidc_redirect_url?:  string & =~"^https?://"
	oidc_cookie_domain?:   string
	oidc_cookie_samesite?: *"Lax" | "Strict" | "None"  // Cookie SameSite attribute (v1.5+)
	oidc_refresh_token?:   *true | bool                // Enable automatic token refresh (v1.6+)
	oidc_logout_path?:     *"/logout" | string & =~"^/"
	oidc_scopes?: [...string & !=""]

	// VolSync - PVC Backup with restic to S3-compatible storage
	// REF: https://volsync.readthedocs.io/en/stable/
	volsync_enabled?:         *false | bool
	volsync_s3_endpoint?:     string & =~"^https?://"
	volsync_s3_bucket?:       string & !=""
	volsync_restic_password?: string & !=""
	volsync_schedule?:        *"0 */6 * * *" | string & =~"^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$"
	volsync_copy_method?:     *"Clone" | "Snapshot"
	volsync_retain_daily?:    *7 | int & >=1 & <=365
	volsync_retain_weekly?:   *4 | int & >=1 & <=52
	volsync_retain_monthly?:  *3 | int & >=1 & <=24

	// External Secrets Operator - Sync secrets from external providers
	// REF: https://external-secrets.io/
	external_secrets_enabled?:  *false | bool
	external_secrets_provider?: *"1password" | "bitwarden" | "vault"
	onepassword_connect_host?:  string & =~"^https?://"

	// CiliumNetworkPolicies - Zero-Trust Network Security
	// REF: https://docs.cilium.io/en/stable/security/policy/
	// REF: docs/research/cilium-network-policies-jan-2026.md
	network_policies_enabled?: *false | bool
	network_policies_mode?:    *"audit" | "enforce"

	// RustFS Shared Object Storage - S3-compatible storage for cluster services
	// REF: https://rustfs.com/
	// REF: docs/research/rustfs-shared-storage-loki-simplescalable-jan-2026.md
	// WARNING: RustFS is currently alpha software (v1.0.0-alpha.78) - test before production
	// NOTE: RustFS does NOT support 'mc admin' commands for user/policy management.
	//       Loki access keys must be created manually via RustFS Console UI.
	//       Tempo uses local filesystem storage, not RustFS/S3.
	rustfs_enabled?:           *false | bool
	rustfs_subdomain?:         *"rustfs" | string & !=""
	rustfs_replicas?:          *1 | int & >=1 & <=16
	rustfs_data_volume_size?:  *"20Gi" | string & =~"^[0-9]+[KMGT]i$"
	rustfs_log_volume_size?:   *"1Gi" | string & =~"^[0-9]+[KMGT]i$"
	rustfs_storage_class?:     string & !=""
	rustfs_access_key?:       *"rustfsadmin" | string & !=""
	rustfs_secret_key?:       string & !=""
	rustfs_buffer_profile?:   *"DataAnalytics" | "General" | "Streaming" | "Archival"

	// RustFS Service Account Credentials for Loki (when rustfs_enabled && loki_enabled)
	// Must be created manually via RustFS Console UI (Identity -> Users -> Create Access Key)
	loki_s3_access_key?: string & !=""
	loki_s3_secret_key?: string & !=""

	// CloudNativePG Operator - Production PostgreSQL for Kubernetes
	// REF: https://cloudnative-pg.io/
	// REF: docs/guides/cnpg-implementation.md
	// Provides automated HA, backups, and monitoring for PostgreSQL clusters
	// Shared infrastructure dependency for Keycloak and other database-backed apps
	cnpg_enabled?:           *false | bool
	cnpg_postgres_image?:    *"ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie" | string & =~"^ghcr\\.io/cloudnative-pg/"
	cnpg_storage_class?:     string & !=""
	cnpg_priority_class?:    *"system-cluster-critical" | string & !=""
	cnpg_control_plane_only?: *true | bool

	// CNPG Backups to RustFS S3 (requires rustfs_enabled: true)
	// Credentials must be created manually via RustFS Console UI
	cnpg_backup_enabled?:   *false | bool
	cnpg_s3_access_key?:    string & !=""
	cnpg_s3_secret_key?:    string & !=""

	// pgvector Extension - Vector similarity search for AI/ML workloads
	// REF: https://github.com/pgvector/pgvector
	// Mounted via ImageVolume (Kubernetes 1.35+, PostgreSQL 18+)
	cnpg_pgvector_enabled?: *false | bool
	cnpg_pgvector_image?:   *"ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie" | string & =~"^ghcr\\.io/cloudnative-pg/"
	cnpg_pgvector_version?: *"0.8.1" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"

	// Barman Cloud Plugin - External plugin for PostgreSQL backups to S3
	// REF: https://cloudnative-pg.io/plugin-barman-cloud/docs/
	// Replaces deprecated in-tree barmanObjectStore (removal in CNPG 1.29)
	// Provides barman-cloud binaries via sidecar container (no -system- images needed)
	cnpg_barman_plugin_enabled?:   *false | bool
	cnpg_barman_plugin_version?:   *"0.10.0" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"
	cnpg_barman_plugin_log_level?: *"info" | "trace" | "debug" | "info" | "warn" | "error"

	// Keycloak OIDC Provider - Identity and Access Management
	// REF: https://www.keycloak.org/operator/installation
	// REF: docs/guides/keycloak-implementation.md
	// Provides OIDC/OAuth2 authentication for JWT SecurityPolicy and web SSO
	keycloak_enabled?:          *false | bool
	keycloak_subdomain?:        *"auth" | string & !=""
	keycloak_realm?:            *"matherlynet" | string & !=""
	keycloak_admin_password?:   string & =~".{8,}"  // Minimum 8 characters
	keycloak_db_mode?:          *"embedded" | "cnpg"
	keycloak_db_user?:          *"keycloak" | string & !=""
	keycloak_db_password?:      string & !=""
	keycloak_db_name?:          *"keycloak" | string & !=""
	keycloak_storage_size?:     *"5Gi" | string & =~"^[0-9]+[KMGT]i$"
	keycloak_replicas?:         *1 | int & >=1 & <=10
	keycloak_db_instances?:     *1 | int & >=1 & <=5  // Only for cnpg mode
	keycloak_operator_version?: *"26.5.0" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"
	// Keycloak PostgreSQL Backup - S3 credentials for RustFS
	// Works with both embedded (pg_dump CronJob) and cnpg (barmanObjectStore) modes
	// Requires rustfs_enabled: true and credentials created via RustFS Console
	keycloak_s3_access_key?:    string & !=""
	keycloak_s3_secret_key?:    string & !=""
	// Backup schedule for embedded mode pg_dump (cron format)
	// CNPG mode uses continuous WAL archiving instead
	keycloak_backup_schedule?:       *"0 2 * * *" | string & =~"^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$"
	keycloak_backup_retention_days?: *7 | int & >=1 & <=365
	// Keycloak OpenTelemetry Tracing (requires tracing_enabled: true)
	// REF: https://www.keycloak.org/observability/tracing
	keycloak_tracing_enabled?:     *false | bool
	keycloak_tracing_sample_rate?: *"0.1" | string & =~"^[01](\\.\\d+)?$"
	// Keycloak Config-CLI - GitOps realm management via keycloak-config-cli
	// Replaces KeycloakRealmImport CRD which only supports one-time imports
	// REF: https://github.com/adorsys/keycloak-config-cli
	// REF: docs/research/keycloak-configuration-as-code-gitops-jan-2026.md
	keycloak_config_cli_version?:  *"6.4.0-26.1.0" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+\\.[0-9]+\\.[0-9]+$"

	// Keycloak Realm Roles - RBAC role hierarchy following Kubernetes patterns
	// Roles are created during realm import and used by IdP mappers/JWT claims
	// REF: https://kubernetes.io/docs/concepts/security/rbac-good-practices/
	keycloak_realm_roles?: [...{
		name:        string & !="" & =~"^[a-z][a-z0-9-]*$"  // lowercase, alphanumeric, hyphens
		description: string & !=""
	}]

	// Grafana Dashboard Monitoring - Component-specific dashboard toggles
	// Each requires monitoring_enabled: true as a prerequisite
	// REF: docs/guides/grafana-dashboards-implementation.md

	// Keycloak Grafana Monitoring - ServiceMonitor + Dashboards
	// When enabled (and monitoring_enabled: true), deploys Keycloak metrics and dashboards
	keycloak_monitoring_enabled?: *false | bool

	// RustFS Grafana Monitoring - ServiceMonitor + Dashboard
	// When enabled (and monitoring_enabled: true), deploys RustFS S3 storage dashboard
	rustfs_monitoring_enabled?: *false | bool

	// Loki Grafana Monitoring - Stack Monitoring Dashboard
	// When enabled (and monitoring_enabled: true), deploys Loki stack monitoring dashboard
	loki_monitoring_enabled?: *false | bool

	// Grafana OIDC Authentication - Native OAuth for Grafana RBAC
	// REF: docs/research/grafana-sso-authentication-integration-jan-2026.md
	// Enables Grafana's native OAuth with Keycloak for role-based access control
	// Requires: monitoring_enabled, keycloak_enabled
	grafana_oidc_enabled?:        *false | bool
	grafana_oidc_client_secret?:  string & !=""

	// Social Identity Providers - OAuth/OIDC Federation with Keycloak
	// REF: docs/research/keycloak-social-identity-providers-integration-jan-2026.md
	google_idp_enabled?:    *false | bool
	google_client_id?:      string & !=""
	google_client_secret?:  string & !=""
	github_idp_enabled?:    *false | bool
	github_client_id?:      string & !=""
	github_client_secret?:  string & !=""
	microsoft_idp_enabled?: *false | bool
	microsoft_client_id?:   string & !=""
	microsoft_client_secret?: string & !=""
	microsoft_tenant_id?:   *"common" | string & !=""

	// Identity Provider Role Mappers - Automatic role assignment based on IdP attributes
	// REF: docs/research/keycloak-social-identity-providers-integration-jan-2026.md#phase-3-rolegroup-mappers
	// Google role mappers
	google_default_role?:   string & !=""
	google_domain_role_mapping?: {
		domain: string & !=""
		role:   string & !=""
	}
	// GitHub role mappers
	github_default_role?:   string & !=""
	github_org_role_mapping?: {
		org:  string & !=""
		role: string & !=""
	}
	// Microsoft role mappers
	microsoft_default_role?: string & !=""
	microsoft_group_role_mappings?: [...{
		group_id: string & =~"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
		role:     string & !=""
	}]

	// LiteLLM Proxy Gateway - Unified AI Model Gateway
	// REF: https://docs.litellm.ai/docs/proxy/quick_start
	// REF: docs/research/litellm-proxy-gateway-integration-jan-2026.md
	// Provides unified API for Azure OpenAI, Anthropic, Cohere models with caching and observability
	litellm_enabled?:    *false | bool
	litellm_subdomain?:  *"litellm" | string & !=""
	litellm_replicas?:   *1 | int & >=1 & <=10
	litellm_master_key?: string & =~"^sk-" & =~".{32,}"  // Must start with sk- and be at least 32 chars
	litellm_salt_key?:   string & =~".{32,}"  // At least 32 characters for encryption

	// LiteLLM PostgreSQL Database (CloudNativePG)
	// Requires cnpg_enabled: true
	litellm_db_user?:       *"litellm" | string & !=""
	litellm_db_password?:   string & !=""
	litellm_db_name?:       *"litellm" | string & !=""
	litellm_db_instances?:  *1 | int & >=1 & <=5
	litellm_storage_size?:  *"10Gi" | string & =~"^[0-9]+[KMGT]i$"

	// LiteLLM Cache - Uses shared Dragonfly in cache namespace
	// Requires dragonfly_enabled: true and dragonfly_acl_enabled: true
	// Set dragonfly_litellm_password for ACL authentication with litellm:* key prefix

	// LiteLLM OIDC Authentication (requires keycloak_enabled: true)
	// Integrates with Keycloak for SSO admin UI access
	litellm_oidc_enabled?:       *false | bool
	litellm_oidc_client_secret?: string & !=""

	// LiteLLM PostgreSQL Backups (requires rustfs_enabled: true)
	// Credentials must be created via RustFS Console UI
	litellm_backup_enabled?:  *false | bool
	litellm_s3_access_key?:   string & !=""
	litellm_s3_secret_key?:   string & !=""

	// LiteLLM Observability (requires monitoring_enabled and/or tracing_enabled)
	litellm_monitoring_enabled?: *false | bool  // ServiceMonitor for Prometheus metrics
	litellm_tracing_enabled?:    *false | bool  // OpenTelemetry traces to Tempo

	// LiteLLM Langfuse Observability (external LLM analytics)
	// REF: https://docs.litellm.ai/docs/observability/langfuse_integration
	litellm_langfuse_enabled?:    *false | bool
	// Langfuse host URL - auto-derived in plugin.py:
	// - Self-hosted (langfuse_enabled: true): http://langfuse-web.ai-system.svc.cluster.local:3000
	// - Langfuse Cloud: https://cloud.langfuse.com
	litellm_langfuse_host?: string & =~"^https?://"
	litellm_langfuse_public_key?: string & !=""
	litellm_langfuse_secret_key?: string & !=""

	// LiteLLM Alerting (Slack/Discord webhook notifications)
	// REF: https://docs.litellm.ai/docs/proxy/alerting
	litellm_alerting_enabled?:      *false | bool
	litellm_slack_webhook_url?:     string & =~"^https://hooks\\.slack\\.com/"
	litellm_discord_webhook_url?:   string & =~"^https://discord\\.com/api/webhooks/"
	litellm_alerting_threshold?:    *300 | int & >=60 & <=3600  // Slow request threshold in seconds

	// LiteLLM Guardrails (content filtering, PII masking, prompt injection detection)
	// REF: https://docs.litellm.ai/docs/proxy/guardrails/
	litellm_guardrails_enabled?:      *false | bool  // Enable built-in content filter
	litellm_presidio_enabled?:        *false | bool  // Enable Presidio PII masking (adds sidecars)
	litellm_prompt_injection_check?:  *false | bool  // Enable prompt injection detection

	// Azure OpenAI US East Configuration
	// Resource name is the Azure OpenAI resource name (e.g., "my-openai-eastus")
	// API version defaults to latest stable preview
	azure_openai_us_east_api_key?:       string & !=""
	azure_openai_us_east_resource_name?: string & !=""
	azure_openai_us_east_api_version?:   *"2025-01-01-preview" | string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}(-preview)?$"

	// Azure OpenAI US East2 Configuration (GPT-5 series, secondary region)
	azure_openai_us_east2_api_key?:       string & !=""
	azure_openai_us_east2_resource_name?: string & !=""
	azure_openai_us_east2_api_version?:   *"2025-04-01-preview" | string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}(-preview)?$"

	// Azure AI Services API Keys and Endpoints (Anthropic, Cohere)
	// These use Azure AI Services, not Azure OpenAI - full base URL required
	azure_anthropic_api_key?:      string & !=""
	azure_anthropic_api_base?:     string & =~"^https://"
	azure_cohere_embed_api_key?:   string & !=""
	azure_cohere_embed_api_base?:  string & =~"^https://"
	azure_cohere_rerank_api_key?:  string & !=""
	azure_cohere_rerank_api_base?: string & =~"^https://"

	// Dragonfly Cache - Redis-compatible in-memory data store
	// REF: https://www.dragonflydb.io/
	// REF: docs/research/dragonfly-redis-alternative-integration-jan-2026.md
	// Provides Redis API compatibility with 25x performance improvement
	dragonfly_enabled?:           *false | bool
	dragonfly_version?:           *"v1.36.0" | string & =~"^v[0-9]+\\.[0-9]+\\.[0-9]+$"
	dragonfly_operator_version?:  *"1.3.1" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"
	dragonfly_replicas?:          *1 | int & >=1 & <=10
	dragonfly_maxmemory?:         *"512mb" | string & =~"^[0-9]+[kmgt]b$"
	dragonfly_threads?:           *2 | int & >=1 & <=16
	dragonfly_password?:          string & !=""
	dragonfly_control_plane_only?: *false | bool
	dragonfly_cpu_request?:       *"100m" | string & =~"^[0-9]+m?$"      // CPU resource request
	dragonfly_memory_request?:    *"256Mi" | string & =~"^[0-9]+[KMGT]i$" // Memory resource request
	dragonfly_memory_limit?:      *"1Gi" | string & =~"^[0-9]+[KMGT]i$"   // Memory resource limit
	dragonfly_cache_mode?:        *false | bool  // Enable LRU eviction for pure cache use
	dragonfly_slowlog_threshold?: *10000 | int & >=0  // microseconds
	dragonfly_slowlog_max_len?:   *128 | int & >=0 & <=1000

	// Dragonfly S3 Backups (requires rustfs_enabled: true)
	// Credentials must be created via RustFS Console UI
	dragonfly_backup_enabled?:    *false | bool
	dragonfly_s3_endpoint?:       *"rustfs-svc.storage.svc.cluster.local:9000" | string & !=""
	dragonfly_s3_access_key?:     string & !=""
	dragonfly_s3_secret_key?:     string & !=""
	dragonfly_snapshot_cron?:     *"0 */6 * * *" | string & =~"^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$"

	// Dragonfly Monitoring (requires monitoring_enabled: true)
	dragonfly_monitoring_enabled?: *false | bool

	// Dragonfly ACL - Multi-tenant access control
	// Per-application passwords for secure namespace isolation
	dragonfly_acl_enabled?:         *false | bool
	dragonfly_keycloak_password?:   string & !=""  // Keycloak session cache user
	dragonfly_appcache_password?:   string & !=""  // General application cache user
	dragonfly_litellm_password?:    string & !=""  // LiteLLM cache user
	dragonfly_langfuse_password?:   string & !=""  // Langfuse cache user (if ACL enabled)

	// Langfuse LLM Observability Platform
	// REF: https://langfuse.com/self-hosting
	// REF: docs/research/langfuse-llm-observability-integration-jan-2026.md
	// Provides LLM tracing, prompt management, evaluation, and cost analytics
	langfuse_enabled?:   *false | bool
	langfuse_subdomain?: *"langfuse" | string & !=""

	// Langfuse Core Credentials (SOPS-encrypted)
	// Generate with: openssl rand -base64 32 (nextauth_secret, salt)
	// Generate with: openssl rand -hex 32 (encryption_key)
	langfuse_nextauth_secret?:   string & =~".{32,}"  // Session management secret
	langfuse_salt?:              string & =~".{32,}"  // API key hashing salt
	langfuse_encryption_key?:    string & =~"^[a-f0-9]{64}$"  // 256-bit hex encryption key

	// Langfuse PostgreSQL Database (CloudNativePG)
	// Requires cnpg_enabled: true
	langfuse_postgres_password?:  string & !=""
	langfuse_postgres_instances?: *1 | int & >=1 & <=5
	langfuse_postgres_storage?:   *"10Gi" | string & =~"^[0-9]+[KMGT]i$"

	// Langfuse ClickHouse (bundled analytics database)
	langfuse_clickhouse_password?:        string & !=""
	langfuse_clickhouse_storage?:         *"20Gi" | string & =~"^[0-9]+[KMGT]i$"
	langfuse_clickhouse_replicas?:        *1 | int & >=1 & <=5
	langfuse_clickhouse_cluster_enabled?: *false | bool  // Set true for multi-node ClickHouse

	// Langfuse S3 Storage (requires rustfs_enabled: true)
	// Credentials must be created via RustFS Console UI
	// Buckets needed: langfuse-events, langfuse-media, langfuse-exports
	langfuse_s3_access_key?:        string & !=""
	langfuse_s3_secret_key?:        string & !=""
	langfuse_s3_concurrent_writes?: int & >=1 & <=500  // S3 write connection pool (default: 50)
	langfuse_s3_concurrent_reads?:  int & >=1 & <=500  // S3 read connection pool (default: 50)

	// Langfuse S3 Buckets (optional bucket name overrides)
	langfuse_media_bucket?:  *"langfuse-media" | string & !=""   // Media/attachments bucket
	langfuse_export_bucket?: *"langfuse-exports" | string & !="" // Batch export bucket

	// Langfuse Media Upload Configuration
	langfuse_media_max_size?:            int & >=1 & <=10000000000           // Max file size in bytes (default: 1GB)
	langfuse_media_download_url_expiry?: int & >=60 & <=86400                // Presigned URL expiry in seconds (default: 3600)
	langfuse_batch_export_enabled?:      *true | bool                        // Enable batch export feature

	// Langfuse PostgreSQL Backups (requires rustfs_enabled: true)
	// Bucket needed: langfuse-postgres-backups
	langfuse_backup_enabled?:         *false | bool
	langfuse_backup_s3_access_key?:   string & !=""  // Separate credentials for backup bucket
	langfuse_backup_s3_secret_key?:   string & !=""

	// Langfuse SSO (requires keycloak_enabled: true)
	// Integrates with Keycloak for OIDC authentication
	langfuse_sso_enabled?:              *false | bool
	langfuse_keycloak_client_secret?:   string & !=""

	// Langfuse Observability (requires monitoring_enabled and/or tracing_enabled)
	langfuse_monitoring_enabled?: *false | bool  // ServiceMonitor for Prometheus metrics
	langfuse_tracing_enabled?:    *false | bool  // OpenTelemetry traces to Tempo

	// Langfuse Resource Configuration
	langfuse_log_level?:             *"info" | "trace" | "debug" | "info" | "warn" | "error" | "fatal"
	langfuse_log_format?:            *"text" | "json"  // Log output format
	langfuse_trace_sampling_ratio?:  *"0.1" | string & =~"^[01]?\\.[0-9]+$"  // 0.0 to 1.0
	langfuse_web_replicas?:          *1 | int & >=1 & <=10
	langfuse_worker_replicas?:       *1 | int & >=1 & <=10
	langfuse_chart_version?:         *"*" | string & !=""

	// Langfuse Caching Configuration (requires Redis/Dragonfly)
	// REF: https://langfuse.com/self-hosting/configuration/caching
	langfuse_cache_api_key_enabled?: bool             // Enable API key caching (default: true)
	langfuse_cache_api_key_ttl?:     int & >=1 & <=86400  // API key cache TTL in seconds (default: 300)
	langfuse_cache_prompt_enabled?:  bool             // Enable prompt caching (default: true)
	langfuse_cache_prompt_ttl?:      int & >=1 & <=86400  // Prompt cache TTL in seconds (default: 300)

	// Langfuse Authentication Configuration (optional)
	// REF: https://langfuse.com/self-hosting/security/authentication-and-sso
	langfuse_disable_password_auth?: *false | bool                   // Disable username/password login (SSO-only mode)
	langfuse_sso_domain_enforcement?: string & =~"^[a-z0-9.-]+(,[a-z0-9.-]+)*$"  // Comma-separated domains requiring SSO

	// Langfuse SMTP/Email Configuration (optional)
	langfuse_smtp_url?:       string & =~"^smtp(s)?://"  // SMTP connection URL
	langfuse_email_from?:     string & =~"^[^@]+@[^@]+$" // Sender email address

	// Langfuse Session Configuration (optional)
	langfuse_session_max_age?: *2592000 | int & >=3600 & <=31536000  // Session duration in seconds (1h to 1y)

	// Langfuse Headless Initialization (optional)
	// Bootstrap initial admin account for GitOps/non-interactive deployments
	// REF: https://langfuse.com/self-hosting/administration/headless-initialization
	// NOTE: langfuse_init_org_id is REQUIRED when using headless initialization
	langfuse_init_org_id?:        string & =~"^[a-z0-9][a-z0-9-]*[a-z0-9]$" & strings.MinRunes(2) & strings.MaxRunes(63)  // Organization identifier (slug format)
	langfuse_init_org_name?:      string & !=""               // Initial organization display name
	langfuse_init_user_email?:    string & =~"^[^@]+@[^@]+$"  // Admin email address
	langfuse_init_user_password?: string & =~".{16,}"         // Minimum 16 characters (SOPS-encrypted)
	langfuse_init_user_name?:     *"Admin" | string & !=""    // Admin display name
	langfuse_disable_signup?:     *false | bool               // Disable public registration after setup

	// Langfuse Project Initialization (optional)
	// Create initial project alongside organization for immediate API access
	// REF: https://langfuse.com/self-hosting/administration/headless-initialization
	langfuse_init_project_id?:         string & =~"^[a-z0-9][a-z0-9-]*[a-z0-9]$" & strings.MinRunes(2) & strings.MaxRunes(63)  // Project identifier (slug format)
	langfuse_init_project_name?:       string & !=""                        // Project display name
	langfuse_init_project_retention?:  int & >=1 & <=3650                   // Data retention in days (1-3650, empty=indefinite)
	langfuse_init_project_public_key?: string & =~"^lf_pk_[a-zA-Z0-9]+$"    // Public API key (format: lf_pk_*)
	langfuse_init_project_secret_key?: string & =~"^lf_sk_[a-zA-Z0-9]+$"    // Secret API key (format: lf_sk_*, SOPS-encrypted)

	// Langfuse Auto-Provisioning (optional)
	// Default roles for SSO users without existing accounts
	// REF: https://langfuse.com/self-hosting/administration/automated-access-provisioning
	// NOTE: If not specified, defaults to langfuse_init_org_id/langfuse_init_project_id
	langfuse_default_org_id?:       string & =~"^[a-z0-9][a-z0-9-]*[a-z0-9]$" & strings.MinRunes(2) & strings.MaxRunes(63)  // Organization for new users
	langfuse_default_org_role?:     *"VIEWER" | "OWNER" | "ADMIN" | "MEMBER" | "VIEWER" | "NONE"
	langfuse_default_project_id?:   string & =~"^[a-z0-9][a-z0-9-]*[a-z0-9]$" & strings.MinRunes(2) & strings.MaxRunes(63)  // Project for new users
	langfuse_default_project_role?: "OWNER" | "ADMIN" | "MEMBER" | "VIEWER"

	// Obot MCP Gateway - AI Agent Platform with MCP Server Hosting
	// REF: https://github.com/jrmatherly/obot-entraid
	// REF: docs/research/obot-mcp-gateway-integration-jan-2026.md
	// Provides AI agents with MCP (Model Context Protocol) server orchestration
	// Uses custom fork with Keycloak authentication provider
	obot_enabled?:    *false | bool
	obot_subdomain?:  *"obot" | string & !=""
	obot_version?:    *"0.2.30" | string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+$"
	obot_replicas?:   *1 | int & >=1 & <=10

	// Obot PostgreSQL Database (CloudNativePG with pgvector)
	// Requires cnpg_enabled: true and cnpg_pgvector_enabled: true
	obot_db_password?:           string & !=""
	obot_postgres_user?:         *"obot" | string & !=""
	obot_postgres_db?:           *"obot" | string & !=""
	obot_postgresql_replicas?:   *1 | int & >=1 & <=5
	obot_postgresql_storage_size?: *"10Gi" | string & =~"^[0-9]+[KMGT]i$"
	obot_storage_size?:          *"20Gi" | string & =~"^[0-9]+[KMGT]i$"

	// Obot Encryption Key for data at rest (base64-encoded 32 bytes)
	// Generate with: openssl rand -base64 32
	obot_encryption_key?: string & =~"^[A-Za-z0-9+/]{43}=$"

	// Obot Keycloak SSO (requires keycloak_enabled: true)
	// Uses custom auth provider from jrmatherly/obot-entraid fork
	obot_keycloak_enabled?:        *false | bool
	obot_keycloak_client_id?:      *"obot" | string & !=""
	obot_keycloak_client_secret?:  string & !=""
	obot_keycloak_cookie_secret?:  string & =~".{32,}"  // At least 32 characters (openssl rand -base64 32)
	obot_keycloak_allowed_groups?: string  // Comma-separated group restrictions
	obot_keycloak_allowed_roles?:  string  // Comma-separated role restrictions

	// Obot MCP Namespace Resource Quotas
	obot_mcp_namespace?:               *"obot-mcp" | string & !=""
	obot_mcp_cpu_requests_quota?:      *"4" | string & =~"^[0-9]+$"
	obot_mcp_cpu_limits_quota?:        *"8" | string & =~"^[0-9]+$"
	obot_mcp_memory_requests_quota?:   *"8Gi" | string & =~"^[0-9]+[KMGT]i$"
	obot_mcp_memory_limits_quota?:     *"16Gi" | string & =~"^[0-9]+[KMGT]i$"
	obot_mcp_max_pods?:                *"20" | string & =~"^[0-9]+$"
	obot_mcp_default_cpu_request?:     *"100m" | string & =~"^[0-9]+m?$"
	obot_mcp_default_cpu_limit?:       *"500m" | string & =~"^[0-9]+m?$"
	obot_mcp_default_memory_request?:  *"256Mi" | string & =~"^[0-9]+[KMGT]i$"
	obot_mcp_default_memory_limit?:    *"512Mi" | string & =~"^[0-9]+[KMGT]i$"
	obot_mcp_max_cpu?:                 *"1000m" | string & =~"^[0-9]+m?$"
	obot_mcp_max_memory?:              *"1Gi" | string & =~"^[0-9]+[KMGT]i$"

	// Obot PostgreSQL Backups (requires rustfs_enabled: true)
	// Credentials must be created via RustFS Console UI
	obot_s3_access_key?: string & !=""
	obot_s3_secret_key?: string & !=""

	// Obot Observability (requires monitoring_enabled and/or tracing_enabled)
	obot_monitoring_enabled?: *false | bool  // ServiceMonitor for Prometheus metrics
	obot_tracing_enabled?:    *false | bool  // OpenTelemetry traces to Tempo

	// Obot LiteLLM Integration (uses internal LiteLLM as model gateway)
	obot_litellm_enabled?: *false | bool
}

#Config
