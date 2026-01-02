# Configuration Reference

> Complete configuration reference for cluster.yaml and nodes.yaml

## cluster.yaml Schema

Configuration validated by CUE schema at `.taskfiles/template/resources/cluster.schema.cue`.

### Required Fields

| Field | Type | Example | Description |
| ------- | ------ | --------- | ------------- |
| `node_cidr` | CIDR | `192.168.1.0/24` | Network CIDR where nodes reside |
| `cluster_api_addr` | IPv4 | `192.168.1.100` | Virtual IP for Kubernetes API |
| `cluster_gateway_addr` | IPv4 | `192.168.1.101` | LoadBalancer IP for internal gateway |
| `cluster_dns_gateway_addr` | IPv4 | `192.168.1.102` | LoadBalancer IP for k8s-gateway (split DNS) |
| `repository_name` | string | `user/repo` | GitHub repository (owner/name format) |
| `cloudflare_domain` | FQDN | `example.com` | Cloudflare-managed domain |
| `cloudflare_token` | string | `abc123...` | Cloudflare API token |
| `cloudflare_gateway_addr` | IPv4 | `192.168.1.103` | LoadBalancer IP for external gateway |

### Optional Fields

| Field | Type | Default | Description |
| ------- | ------ | --------- | ------------- |
| `node_dns_servers` | IPv4[] | `["1.1.1.1", "1.0.0.1"]` | DNS servers for nodes |
| `node_ntp_servers` | IPv4[] | `["162.159.200.1", "162.159.200.123"]` | NTP servers |
| `node_default_gateway` | IPv4 | First IP in `node_cidr` | Default gateway |
| `node_vlan_tag` | string | - | VLAN ID for tagged ports |
| `cluster_pod_cidr` | CIDR | `10.42.0.0/16` | Pod network CIDR |
| `cluster_svc_cidr` | CIDR | `10.43.0.0/16` | Service network CIDR |
| `cluster_api_tls_sans` | FQDN[] | - | Additional API server SANs |
| `repository_branch` | string | `main` | Git branch to track |
| `repository_visibility` | enum | `public` | `public` or `private` |
| `cilium_loadbalancer_mode` | enum | `dsr` | `dsr` or `snat` |
| `cilium_bgp_router_addr` | IPv4 | - | BGP router peer address |
| `cilium_bgp_router_asn` | string | - | BGP router ASN |
| `cilium_bgp_node_asn` | string | - | BGP node ASN |

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
| `cilium_bgp_enabled` | `true/false` | All BGP keys set |
| `spegel_enabled` | `true/false` | More than 1 node |

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
