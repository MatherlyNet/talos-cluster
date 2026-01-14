# Configuration Reference

> Complete configuration reference for cluster.yaml and nodes.yaml

## IDE Schema Validation

Both `cluster.yaml` and `nodes.yaml` support IDE schema validation for autocomplete and error checking.

**Modeline Support:** Add this comment at the top of your YAML file for inline schema validation:
```yaml
# yaml-language-server: $schema=./.taskfiles/template/resources/cluster.schema.json
---
```

**VS Code Integration:** The `.vscode/settings.json` already configures schema associations for:
- `cluster.yaml`, `cluster.sample.yaml` → `cluster.schema.json`
- `nodes.yaml`, `nodes.sample.yaml` → `nodes.schema.json`

**Schema Regeneration:** Schemas are auto-generated from CUE during `task configure`, or manually via:
```bash
task template:schema
```

## cluster.yaml Schema

Configuration validated by CUE schema at `.taskfiles/template/resources/cluster.schema.cue`.

### Required Fields

| Field | Type | Example | Description |
| ------- | ------ | --------- | ------------- |
| `node_cidr` | CIDR | `192.168.1.0/24` | Network CIDR where nodes reside |
| `cluster_api_addr` | IPv4 | `192.168.1.100` | Virtual IP for Kubernetes API |
| `cluster_gateway_addr` | IPv4 | `192.168.1.101` | LoadBalancer IP for internal gateway |
| `repository_name` | string | `user/repo` | GitHub repository (owner/name format) |
| `cloudflare_domain` | FQDN | `example.com` | Cloudflare-managed domain |
| `cloudflare_token` | string | `abc123...` | Cloudflare API token |
| `cloudflare_gateway_addr` | IPv4 | `192.168.1.103` | LoadBalancer IP for external gateway |

### Conditional Fields

| Field | Type | Example | Required When | Description |
| ------- | ------ | --------- | --------------- | ------------- |
| `cluster_dns_gateway_addr` | IPv4 | `192.168.1.102` | NOT using UniFi DNS | LoadBalancer IP for k8s-gateway (split DNS) |

**Note:** When `unifi_host` and `unifi_api_key` are both set, k8s-gateway is replaced by external-dns-unifi and `cluster_dns_gateway_addr` is ignored.

### Optional Fields

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `node_dns_servers` | IPv4[] | `["1.1.1.1", "1.0.0.1"]` | DNS servers for nodes |
| `node_ntp_servers` | IPv4[] | `["162.159.200.1", "162.159.200.123"]` | NTP servers |
| `node_default_gateway` | IPv4 | First IP in `node_cidr` | Default gateway |
| `node_vlan_tag` | string | - | VLAN ID for tagged ports |
| `proxmox_vlan_mode` | bool | `false` | When `true`, Proxmox handles VLAN tagging (access port mode). When `false`, Talos creates VLAN sub-interfaces (trunk port / bare-metal mode). Set to `true` when using Proxmox VM provisioning with `node_vlan_tag`. |
| `cluster_pod_cidr` | CIDR | `10.42.0.0/16` | Pod network CIDR |
| `cluster_svc_cidr` | CIDR | `10.43.0.0/16` | Service network CIDR |
| `cluster_api_tls_sans` | FQDN[] | - | Additional API server SANs |
| `repository_branch` | string | `main` | Git branch to track |
| `repository_visibility` | enum | `public` | `public` or `private` |
| `cilium_loadbalancer_mode` | enum | `dsr` | `dsr` or `snat` |

### Cilium BGP Configuration (Optional)

When all three required BGP fields are set, BGP Control Plane v2 is enabled and L2 announcements are disabled.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `cilium_bgp_router_addr` | IPv4 | - | BGP router peer address (gateway on node VLAN) |
| `cilium_bgp_router_asn` | string | - | BGP router ASN (private range: 64512-65534) |
| `cilium_bgp_node_asn` | string | - | BGP node ASN (must differ from router ASN for eBGP) |
| `cilium_lb_pool_cidr` | CIDR | - | Dedicated LoadBalancer IP pool (separate from node_cidr) |
| `cilium_bgp_hold_time` | int | `30` | BGP hold time in seconds (3-300) |
| `cilium_bgp_keepalive_time` | int | `10` | BGP keepalive interval in seconds (1-100) |
| `cilium_bgp_graceful_restart` | bool | `false` | Enable BGP graceful restart for smoother failover |
| `cilium_bgp_graceful_restart_time` | int | `120` | Graceful restart timeout in seconds (30-600) |
| `cilium_bgp_ecmp_max_paths` | int | `3` | Maximum ECMP paths for load balancing (1-16) |
| `cilium_bgp_password` | string | - | BGP MD5 authentication password (RFC 2385, SOPS-encrypted) |

**Note:** When BGP is enabled, `templates/config/unifi/bgp.conf.j2` generates FRR configuration for UniFi gateways

### UniFi DNS Integration (Optional)

When configured, replaces k8s-gateway with native UniFi DNS record management. Requires UniFi Network v9.0.0+ for API key authentication.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `unifi_host` | string | - | UniFi controller URL (e.g., `https://192.168.1.1`) |
| `unifi_api_key` | string | - | API key from UniFi Admin → Control Plane → Integrations |
| `unifi_site` | string | `default` | UniFi site identifier |
| `unifi_external_controller` | bool | `false` | Set `true` for Cloud Key/self-hosted controller |

**Note:** When `unifi_host` and `unifi_api_key` are both configured, unifi-dns is deployed and k8s-gateway is disabled.

### Talos Upgrade Controller (tuppr) Configuration

Automated Talos OS and Kubernetes version management via GitOps.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `talos_version` | string | `1.12.0` | Target Talos OS version for automated upgrades |
| `kubernetes_version` | string | `1.35.0` | Target Kubernetes version for automated upgrades |

**Note:** Update these values and run `task configure` to trigger automated rolling upgrades via tuppr.

### Talos Backup Configuration (Optional)

Automated etcd snapshots with S3 storage and Age encryption. All fields required when enabling backup.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `backup_s3_endpoint` | string | - | S3-compatible endpoint URL (e.g., `https://<account>.r2.cloudflarestorage.com`) |
| `backup_s3_bucket` | string | - | Bucket name for backup storage |
| `backup_s3_access_key` | string | - | S3 access key ID (SOPS-encrypted after configure) |
| `backup_s3_secret_key` | string | - | S3 secret access key (SOPS-encrypted after configure) |
| `backup_age_public_key` | string | - | Age public key for backup encryption (e.g., `age1...`) |

**Note:** When `backup_s3_endpoint` and `backup_s3_bucket` are both configured, talos-backup is deployed with a CronJob for periodic etcd snapshots.

### Observability Configuration (Optional)

Full-stack observability with metrics, logs, and distributed tracing.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `monitoring_enabled` | bool | `false` | Enable monitoring stack (Prometheus + Grafana + AlertManager) |
| `monitoring_stack` | enum | `prometheus` | `prometheus` (kube-prometheus-stack) |
| `hubble_enabled` | bool | `false` | Enable Cilium Hubble network observability |
| `hubble_ui_enabled` | bool | `false` | Enable Hubble UI web interface |
| `grafana_subdomain` | string | `grafana` | Subdomain for Grafana (creates `grafana.<cloudflare_domain>`) |
| `metrics_retention` | string | `7d` | Metrics retention period (e.g., `7d`, `14d`, `30d`) |
| `metrics_storage_size` | string | `50Gi` | PV size for metrics storage |
| `storage_class` | string | `local-path` | Storage class for monitoring PVs |

#### Log Aggregation (Loki + Alloy)

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `loki_enabled` | bool | `false` | Enable log aggregation (requires `monitoring_enabled`) |
| `logs_retention` | string | `7d` | Log retention period |
| `logs_storage_size` | string | `50Gi` | PV size for log storage |

#### Infrastructure Alerts (PrometheusRule)

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `monitoring_alerts_enabled` | bool | `true` | Enable infrastructure alerting rules |
| `node_memory_threshold` | int | `90` | Memory utilization % threshold for alerts |
| `node_cpu_threshold` | int | `90` | CPU utilization % threshold for alerts |

#### Distributed Tracing (Tempo)

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `tracing_enabled` | bool | `false` | Enable distributed tracing (requires `monitoring_enabled`) |
| `tracing_sample_rate` | int | `10` | Trace sample percentage (1-100) |
| `trace_retention` | string | `72h` | Trace retention period |
| `trace_storage_size` | string | `10Gi` | PV size for trace storage |
| `cluster_name` | string | `matherlynet` | Cluster name for trace metadata |
| `observability_namespace` | string | `monitoring` | Namespace for monitoring components |
| `environment` | string | `production` | Environment tag for traces (`production`, `staging`, `development`) |

**Note:** See `docs/guides/observability-stack-implementation.md` for deployment details and component architecture.

#### OIDC/JWT Authentication (Envoy Gateway SecurityPolicy)

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `oidc_provider_name` | string | `keycloak` | Provider name in SecurityPolicy |
| `oidc_issuer_url` | string | - | JWT issuer URL (must match token `iss` claim) |
| `oidc_jwks_uri` | string | - | JWKS endpoint for JWT validation |
| `oidc_additional_claims` | list | `[]` | Additional claims to extract to headers |

When `oidc_issuer_url` and `oidc_jwks_uri` are both set, a SecurityPolicy is created targeting HTTPRoutes with label `security: jwt-protected`.

**Note:** See `docs/guides/envoy-gateway-observability-security.md` for implementation details.

### CiliumNetworkPolicies (Optional)

Zero-trust network segmentation with L3-L7 policy enforcement.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `network_policies_enabled` | bool | `false` | Enable CiliumNetworkPolicies |
| `network_policies_mode` | enum | `audit` | `audit` (observe only) or `enforce` (block traffic) |

**Modes:**
- `audit`: Policies deployed with `enableDefaultDeny: false` - traffic is observed via Hubble but not blocked
- `enforce`: Policies deployed with `enableDefaultDeny: true` - non-matching traffic is actively blocked

**Covered Namespaces:** cluster-policies, kube-system, monitoring, flux-system, cert-manager, network

**Recommended Workflow:**
1. Deploy with `network_policies_mode: "audit"`
2. Monitor for 24-48 hours via `hubble observe --verdict AUDIT`
3. Review traffic patterns and adjust policies as needed
4. Switch to `network_policies_mode: "enforce"` after validation

**Note:** See `docs/research/cilium-network-policies-jan-2026.md` for policy designs and implementation details.

### VolSync PVC Backup (Optional)

Automated PVC backups with restic to S3-compatible storage.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `volsync_enabled` | bool | `false` | Enable VolSync PVC backup |
| `volsync_s3_endpoint` | string | - | S3-compatible endpoint URL |
| `volsync_s3_bucket` | string | - | Bucket name for PVC backups |
| `volsync_restic_password` | string | - | Restic repository password (SOPS-encrypted) |
| `volsync_schedule` | string | `0 */6 * * *` | Backup schedule (cron format) |
| `volsync_copy_method` | enum | `Clone` | `Clone` or `Snapshot` |
| `volsync_retain_daily` | int | `7` | Daily backup retention count |
| `volsync_retain_weekly` | int | `4` | Weekly backup retention count |
| `volsync_retain_monthly` | int | `3` | Monthly backup retention count |

**Copy Method Selection:**
- `Clone`: Works with any CSI driver supporting volume cloning (e.g., Proxmox CSI)
- `Snapshot`: Requires CSI driver with VolumeSnapshot support (e.g., Longhorn, Rook-Ceph)

**Note:** See `docs/guides/k8s-at-home-remaining-implementation.md` for implementation details.

### External Secrets Operator (Optional)

Sync secrets from external secret management providers.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `external_secrets_enabled` | bool | `false` | Enable External Secrets Operator |
| `external_secrets_provider` | enum | `1password` | `1password`, `bitwarden`, or `vault` |
| `onepassword_connect_host` | string | - | 1Password Connect host URL |

**Note:** See `docs/guides/k8s-at-home-remaining-implementation.md` for implementation details.

### Proxmox Infrastructure (Optional)

VM provisioning via OpenTofu for Proxmox VE environments.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `proxmox_api_url` | string | - | Proxmox API URL (e.g., `https://pve.example.com:8006/api2/json`) |
| `proxmox_node` | string | - | Proxmox node name for VM creation |
| `proxmox_iso_storage` | string | `local` | Storage for ISO images |
| `proxmox_disk_storage` | string | `local-lvm` | Storage for VM disks |

When `proxmox_api_url` and `proxmox_node` are both set, `infrastructure_enabled` becomes `true` and OpenTofu configuration is generated.

#### Infrastructure Credentials

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `cf_account_id` | string | - | Cloudflare account ID (Dashboard → Overview → right sidebar) |
| `tfstate_username` | string | `terraform` | HTTP backend auth username (must match tfstate-worker) |
| `tfstate_password` | string | - | HTTP backend auth password (must match tfstate-worker) |
| `proxmox_api_token_id` | string | - | Proxmox API token ID (format: `user@realm!token-name`) |
| `proxmox_api_token_secret` | string | - | Proxmox API token secret |

**Note:** These credentials are stored in `cluster.yaml` (gitignored) and flow to `infrastructure/secrets.sops.yaml` during `task configure`. When `tfstate_password` is set, `task configure` automatically runs `tofu init`.

#### VM Defaults (Global Fallback)

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `proxmox_vm_defaults.cores` | int | `4` | CPU cores |
| `proxmox_vm_defaults.sockets` | int | `1` | CPU sockets |
| `proxmox_vm_defaults.memory` | int | `8192` | Memory in MB |
| `proxmox_vm_defaults.disk_size` | int | `128` | Disk size in GB |

#### Controller Node VM Defaults (Etcd/Control Plane Optimized)

Used for nodes with `controller: true`. Smaller disk since controllers don't run workloads.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `proxmox_vm_controller_defaults.cores` | int | `4` | CPU cores (etcd is single-threaded) |
| `proxmox_vm_controller_defaults.sockets` | int | `1` | CPU sockets |
| `proxmox_vm_controller_defaults.memory` | int | `8192` | Memory in MB (8GB sufficient) |
| `proxmox_vm_controller_defaults.disk_size` | int | `64` | Disk size in GB (etcd only) |

#### Worker Node VM Defaults (Workload Optimized)

Used for nodes with `controller: false`. Larger resources for application pods.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `proxmox_vm_worker_defaults.cores` | int | `8` | CPU cores (workload scheduling) |
| `proxmox_vm_worker_defaults.sockets` | int | `1` | CPU sockets |
| `proxmox_vm_worker_defaults.memory` | int | `16384` | Memory in MB (16GB for pods) |
| `proxmox_vm_worker_defaults.disk_size` | int | `256` | Disk size in GB (images + workloads) |

**Fallback Chain:** per-node value → role-defaults → global-defaults

```yaml
# Example: Custom worker defaults for GPU cluster
proxmox_vm_worker_defaults:
  cores: 16
  memory: 32768
  disk_size: 512
```

#### VM Advanced Settings (Talos-Optimized)

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `proxmox_vm_advanced.bios` | enum | `ovmf` | BIOS type (`ovmf`, `seabios`) |
| `proxmox_vm_advanced.machine` | enum | `q35` | Machine type (`q35`, `i440fx`) |
| `proxmox_vm_advanced.cpu_type` | string | `host` | CPU type |
| `proxmox_vm_advanced.scsi_hw` | enum | `virtio-scsi-pci` | SCSI controller |
| `proxmox_vm_advanced.balloon` | int | `0` | Balloon memory (0 = disabled) |
| `proxmox_vm_advanced.numa` | bool | `true` | NUMA optimization |
| `proxmox_vm_advanced.qemu_agent` | bool | `true` | QEMU guest agent |
| `proxmox_vm_advanced.net_queues` | int | `4` | Network queues |
| `proxmox_vm_advanced.disk_discard` | bool | `true` | SSD TRIM support |
| `proxmox_vm_advanced.disk_ssd` | bool | `true` | SSD emulation |
| `proxmox_vm_advanced.tags` | string[] | `["kubernetes", "linux", "talos"]` | VM tags |
| `proxmox_vm_advanced.network_bridge` | string | `vmbr0` | Proxmox bridge interface |
| `proxmox_vm_advanced.ostype` | string | `l26` | Guest OS type (Linux 2.6+) |
| `proxmox_vm_advanced.disk_backup` | bool | `false` | Include in Proxmox backups |
| `proxmox_vm_advanced.disk_replicate` | bool | `false` | Enable Proxmox replication |

**Note:** See `templates/config/infrastructure/tofu/` for OpenTofu configuration.
**REF:** `docs/research/proxmox-vm-configuration-gap-analysis-jan-2026.md` for detailed analysis.

### IP Address Constraints

All LoadBalancer IPs must be:
- Within `node_cidr`
- Unique (no overlapping)
- Not assigned to any node

```yaml
# Example with constraints:
node_cidr: "192.168.1.0/24"           # Network range

# These must all be different:
cluster_api_addr: "192.168.1.100"      # API VIP
cluster_gateway_addr: "192.168.1.101"  # Internal LB
cluster_dns_gateway_addr: "192.168.1.102"  # DNS LB
cloudflare_gateway_addr: "192.168.1.103"   # External LB
```

### CIDR Constraints

Pod and Service CIDRs must not overlap with `node_cidr`:

```yaml
node_cidr: "192.168.1.0/24"      # ✓ Node network
cluster_pod_cidr: "10.42.0.0/16" # ✓ Separate range
cluster_svc_cidr: "10.43.0.0/16" # ✓ Separate range
```

### Complete Example

```yaml
---
# Network Configuration
node_cidr: "192.168.1.0/24"
node_dns_servers:
  - "1.1.1.1"
  - "1.0.0.1"
node_ntp_servers:
  - "162.159.200.1"
  - "162.159.200.123"
node_default_gateway: "192.168.1.1"

# Cluster Configuration
cluster_api_addr: "192.168.1.100"
cluster_api_tls_sans:
  - "k8s.example.com"
cluster_pod_cidr: "10.42.0.0/16"
cluster_svc_cidr: "10.43.0.0/16"
cluster_dns_gateway_addr: "192.168.1.102"
cluster_gateway_addr: "192.168.1.101"

# Repository Configuration
repository_name: "myuser/home-cluster"
repository_branch: "main"
repository_visibility: "public"

# Cloudflare Configuration
cloudflare_domain: "example.com"
cloudflare_token: "your-cloudflare-api-token"
cloudflare_gateway_addr: "192.168.1.103"

# Cilium Configuration (optional BGP)
cilium_loadbalancer_mode: "dsr"
# cilium_bgp_router_addr: "192.168.1.1"
# cilium_bgp_router_asn: "64512"
# cilium_bgp_node_asn: "64513"
```

---

## nodes.yaml Schema

Configuration validated by CUE schema at `.taskfiles/template/resources/nodes.schema.cue`.

### Node Fields

| Field | Type | Required | Description |
| ------- | ------ | ---------- | ------------- |
| `name` | string | Yes | Hostname (lowercase alphanumeric, max 63 chars) |
| `address` | IPv4 | Yes | Node IP address (must be in `node_cidr`) |
| `controller` | bool | Yes | `true` for control plane nodes |
| `disk` | string | Yes | Install disk path or serial number |
| `mac_addr` | string | Yes | NIC MAC address (lowercase, colon-separated) |
| `schematic_id` | string | Yes | 64-char hex from Talos Image Factory |
| `mtu` | int | No | NIC MTU (1450-9000, default: 1500) |
| `secureboot` | bool | No | Enable UEFI Secure Boot |
| `encrypt_disk` | bool | No | Enable TPM-based disk encryption |
| `kernel_modules` | string[] | No | Additional kernel modules to load |

### VM-Specific Fields (OpenTofu/Proxmox)

Per-node overrides for VM provisioning. Fallback chain: per-node → role-defaults → global-defaults.

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `vm_id` | int | auto-assigned | Proxmox VM ID (100-999999999, auto-assigned if not set) |
| `vm_cores` | int | role-based | CPU cores (controller: 4, worker: 8) |
| `vm_sockets` | int | `1` | CPU sockets |
| `vm_memory` | int | role-based | Memory in MB (controller: 8192, worker: 16384) |
| `vm_disk_size` | int | role-based | Disk size in GB (controller: 64, worker: 256) |
| `vm_startup_order` | int | node index + 3 | Boot order (lower = earlier) |
| `vm_startup_delay` | int | `15` | Seconds before starting next VM |
| `vm_shutdown_delay` | int | `60` | Graceful shutdown timeout in seconds |

**Note:** When `controller: true`, uses `proxmox_vm_controller_defaults`. When `controller: false`, uses `proxmox_vm_worker_defaults`.

### Name Constraints

Node names must:
- Match pattern: `^[a-z0-9][a-z0-9\-]{0,61}[a-z0-9]$`
- Not be reserved: `global`, `controller`, `worker`
- Be unique across all nodes

### Disk Specification

Two formats supported:

```yaml
# Path-based (starts with /)
disk: "/dev/sda"
disk: "/dev/nvme0n1"

# Serial-based (any other string)
disk: "S4EVNF0M123456"
```

### Getting Node Information

While node is in maintenance mode:

```bash
# Get disk information
talosctl get disks -n <ip> --insecure

# Get NIC MAC addresses
talosctl get links -n <ip> --insecure
```

### Schematic ID

Obtain from [Talos Image Factory](https://factory.talos.dev/):

1. Select Talos version
2. Choose system extensions (start minimal)
3. Generate → Copy 64-character schematic ID

### Complete Example

```yaml
---
nodes:
  # Control plane nodes (recommend 3 for HA)
  - name: "k8s-cp-1"
    address: "192.168.1.10"
    controller: true
    disk: "/dev/nvme0n1"
    mac_addr: "aa:bb:cc:dd:ee:01"
    schematic_id: "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"
    mtu: 1500

  - name: "k8s-cp-2"
    address: "192.168.1.11"
    controller: true
    disk: "S4EVNF0M123456"  # Serial number
    mac_addr: "aa:bb:cc:dd:ee:02"
    schematic_id: "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"

  - name: "k8s-cp-3"
    address: "192.168.1.12"
    controller: true
    disk: "/dev/sda"
    mac_addr: "aa:bb:cc:dd:ee:03"
    schematic_id: "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"
    secureboot: true
    encrypt_disk: true

  # Worker nodes (optional)
  - name: "k8s-worker-1"
    address: "192.168.1.20"
    controller: false
    disk: "/dev/nvme0n1"
    mac_addr: "aa:bb:cc:dd:ee:10"
    schematic_id: "f1e2d3c4b5a6789012345678901234567890123456789012345678901234wxyz"
    kernel_modules:
      - nvidia
      - nvidia_uvm
      - nvidia_drm
      - nvidia_modeset
```

---

## Template Plugin Functions

Available in Jinja2 templates via `templates/scripts/plugin.py`:

### Filters

| Filter | Usage | Description |
| -------- | ------- | ------------- |
| `basename` | `path \| basename` | Get filename without .j2 extension |
| `nthhost` | `cidr \| nthhost(n)` | Get nth IP in CIDR range |

### Functions

| Function | Usage | Description |
| -------- | ------- | ------------- |
| `age_key('public')` | Get Age public key | Reads from `age.key` |
| `age_key('private')` | Get Age private key | Reads from `age.key` |
| `cloudflare_tunnel_id()` | Get tunnel ID | Reads from `cloudflare-tunnel.json` |
| `cloudflare_tunnel_secret()` | Get tunnel token | Base64-encoded tunnel secret |
| `github_deploy_key()` | Get SSH key | Reads from `github-deploy.key` |
| `github_push_token()` | Get webhook token | Reads from `github-push-token.txt` |
| `talos_patches(type)` | List patch files | `global`, `controller`, `worker`, or node name |

### Computed Defaults

Set automatically by the plugin:

| Variable | Default | Condition |
| ---------- | --------- | ----------- |
| `node_default_gateway` | `nthhost(node_cidr, 1)` | First IP in CIDR |
| `node_dns_servers` | `["1.1.1.1", "1.0.0.1"]` | Cloudflare DNS |
| `node_ntp_servers` | `["162.159.200.1", "162.159.200.123"]` | Cloudflare NTP |
| `cluster_pod_cidr` | `10.42.0.0/16` | Standard pod range |
| `cluster_svc_cidr` | `10.43.0.0/16` | Standard svc range |
| `repository_branch` | `main` | Default branch |
| `repository_visibility` | `public` | Public repo |
| `cilium_loadbalancer_mode` | `dsr` | Direct Server Return |

### Derived Variables

Computed from configuration and used in templates:

| Variable | Value | Condition |
| ---------- | ------- | ----------- |
| `cilium_bgp_enabled` | `true` | All 3 BGP keys set (`cilium_bgp_router_addr`, `cilium_bgp_router_asn`, `cilium_bgp_node_asn`) |
| `unifi_dns_enabled` | `true` | Both `unifi_host` and `unifi_api_key` set |
| `k8s_gateway_enabled` | `true` | `unifi_dns_enabled` is `false` (mutually exclusive) |
| `talos_backup_enabled` | `true` | Both `backup_s3_endpoint` and `backup_s3_bucket` set |
| `oidc_enabled` | `true` | Both `oidc_issuer_url` and `oidc_jwks_uri` set |
| `spegel_enabled` | `true` | More than 1 node (can be overridden by user) |
| `infrastructure_enabled` | `true` | Both `proxmox_api_url` and `proxmox_node` set |

**Note:** Derived variables simplify template conditionals and ensure consistent behavior. For example, templates use `#% if oidc_enabled %#` instead of `#% if oidc_issuer_url is defined and oidc_jwks_uri is defined %#`.

---

## Template Delimiters

Custom Jinja2 delimiters to avoid conflicts with YAML/Helm:

| Type | Start | End | Example |
| ------ | ------- | ----- | --------- |
| Block | `#%` | `%#` | `#% if condition %#...#% endif %#` |
| Variable | `#{` | `}#` | `#{ variable }#` |
| Comment | `#\|` | `#\|` | `#\| This is a comment #\|` |

### Example Template

```yaml
#% if cilium_bgp_enabled %#
bgpControlPlane:
  enabled: true
#% endif %#

ipv4NativeRoutingCIDR: "#{ cluster_pod_cidr }#"

#% for node in nodes %#
#% if node.controller %#
  - hostname: "#{ node.name }#"
#% endif %#
#% endfor %#
```

---

## Environment Variables

Required for operations:

| Variable | Source | Used By |
| ---------- | -------- | --------- |
| `KUBECONFIG` | `./kubeconfig` | kubectl, flux, helm |
| `TALOSCONFIG` | `./talos/clusterconfig/talosconfig` | talosctl |
| `SOPS_AGE_KEY_FILE` | `./age.key` | sops |

Set automatically by:
- Taskfile.yaml (`env:` block)
- .mise.toml (`[env]` section)

---

## Generated Files

After `task configure`:

| File/Directory | Description |
| ---------------- | ------------- |
| `.sops.yaml` | SOPS encryption rules |
| `kubernetes/` | Rendered K8s manifests |
| `talos/talconfig.yaml` | Rendered Talos config |
| `talos/talenv.yaml` | Version pins |
| `talos/clusterconfig/` | Generated node configs |
| `bootstrap/` | Rendered bootstrap resources |

After `task bootstrap:talos`:

| File | Description |
| ---------------- | ------------- |
| `kubeconfig` | Cluster access credentials |
| `talos/talsecret.sops.yaml` | Encrypted Talos secrets |

---

**Last Updated:** January 13, 2026
**Schema Files:** cluster.schema.cue, nodes.schema.cue (.taskfiles/template/resources/)
**Plugin:** templates/scripts/plugin.py (60+ computed variables)
**Default Versions:** Talos 1.12.0, Kubernetes 1.35.0 (tuppr targets)
