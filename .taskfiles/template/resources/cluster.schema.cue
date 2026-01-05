package config

import (
	"net"
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

	// Observability - Monitoring Stack (VictoriaMetrics + Grafana + AlertManager)
	// Full-stack observability with metrics, logs, and distributed tracing
	monitoring_enabled?:      *false | bool
	monitoring_stack?:        *"victoriametrics" | "prometheus"
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
}

#Config
