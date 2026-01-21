# Template Plugin API Reference

**Generated:** 2026-01-13
**Module:** `templates/scripts/plugin.py`
**Purpose:** Jinja2 template helper functions for cluster configuration

---

## Overview

The template plugin provides custom Jinja2 filters and functions for use in makejinja templates. It handles cluster configuration computation, file operations, and dynamic variable derivation.

**Usage in Templates:**

```jinja2
#| Example: Get the 10th IP in the node CIDR |#
cluster_api_addr: #{ node_cidr | nthhost(10) }#

#| Example: Load Age public key |#
age_public_key: #{ age_key('public') }#

#| Example: Check if infrastructure is enabled |#
#% if infrastructure_enabled(data) %#
  proxmox_enabled: true
#% endif %#
```

---

## Filters

Filters are applied to values using the pipe (`|`) syntax.

### `basename(value: str) -> str`

Remove the `.j2` extension from a file path and return the stem.

**Parameters:**

- `value` (str): File path to process

**Returns:**

- str: Filename without `.j2` extension

**Example:**

```jinja2
#| Input: "templates/config/cluster.yaml.j2" |#
#{ "templates/config/cluster.yaml.j2" | basename }#
#| Output: "cluster.yaml" |#
```

**Source:** Line 29

---

### `nthhost(value: str, query: int) -> str | bool`

Get the nth IP address from a CIDR range.

**Parameters:**

- `value` (str): CIDR network (e.g., `192.168.1.0/24`)
- `query` (int): Zero-based index of desired IP

**Returns:**

- str: IP address at the specified index
- bool: `False` if index is out of range or invalid CIDR

**Examples:**

```jinja2
#| Get the 1st IP (gateway) |#
gateway: #{ node_cidr | nthhost(1) }#
#| node_cidr=192.168.1.0/24 → 192.168.1.1 |#

#| Get the 10th IP (VIP) |#
cluster_api_addr: #{ node_cidr | nthhost(10) }#
#| node_cidr=192.168.1.0/24 → 192.168.1.10 |#
```

**Edge Cases:**

- Index 0 is the network address
- Last index is the broadcast address
- Raises `ValueError` for invalid CIDR notation
- Returns `False` for out-of-range indices

**Source:** Line 34

---

## Functions

Functions are called directly in templates.

### `age_key(key_type: str, file_path: str = "age.key") -> str`

Extract Age encryption keys from the Age key file.

**Parameters:**

- `key_type` (str): Type of key to extract (`"public"` or `"private"`)
- `file_path` (str, optional): Path to Age key file. Default: `"age.key"`

**Returns:**

- str: Public key (format: `age1...`) or private key (format: `AGE-SECRET-KEY-...`)

**Examples:**

```jinja2
#| Public key for SOPS |#
age_public_key: #{ age_key('public') }#

#| Private key for decryption |#
age_private_key: #{ age_key('private') }#
```

**Errors:**

- `FileNotFoundError`: Age key file not found
- `ValueError`:
  - Invalid key type (not "public" or "private")
  - Public/private key not found in file
- `RuntimeError`: Unexpected processing error

**Source:** Line 45

---

### `cloudflare_tunnel_id(file_path: str = "cloudflare-tunnel.json") -> str`

Extract the Tunnel ID from Cloudflare Tunnel credentials file.

**Parameters:**

- `file_path` (str, optional): Path to Cloudflare Tunnel JSON file. Default: `"cloudflare-tunnel.json"`

**Returns:**

- str: Cloudflare Tunnel ID (UUID format)

**Example:**

```jinja2
tunnel_id: #{ cloudflare_tunnel_id() }#
#| Output: "abc123de-f456-7890-abcd-ef1234567890" |#
```

**Errors:**

- `FileNotFoundError`: Tunnel credentials file not found
- `json.JSONDecodeError`: Invalid JSON file
- `KeyError`: Missing `TunnelID` key in JSON
- `RuntimeError`: Unexpected processing error

**Source:** Line 67

---

### `cloudflare_tunnel_secret(file_path: str = "cloudflare-tunnel.json") -> str`

Generate Cloudflare Tunnel token from credentials file.

**Parameters:**

- `file_path` (str, optional): Path to Cloudflare Tunnel JSON file. Default: `"cloudflare-tunnel.json"`

**Returns:**

- str: Base64-encoded tunnel token (TUNNEL_TOKEN format)

**Example:**

```jinja2
tunnel_token: #{ cloudflare_tunnel_secret() }#
#| Output: "eyJhIjoiYWNjb3VudC10YWciLCJ0IjoidHVubmVsLWlkIiwicyI6InR1bm5lbC1zZWNyZXQifQ==" |#
```

**Format:**
The token is a base64-encoded JSON object with keys transformed:

- `AccountTag` → `a`
- `TunnelID` → `t`
- `TunnelSecret` → `s`

**Errors:**

- `FileNotFoundError`: Tunnel credentials file not found
- `json.JSONDecodeError`: Invalid JSON file
- `KeyError`: Missing required keys (`AccountTag`, `TunnelID`, `TunnelSecret`)
- `RuntimeError`: Unexpected processing error

**Source:** Line 86

---

### `github_deploy_key(file_path: str = "github-deploy.key") -> str`

Read the GitHub deploy key for Flux Git access.

**Parameters:**

- `file_path` (str, optional): Path to deploy key file. Default: `"github-deploy.key"`

**Returns:**

- str: SSH private key contents

**Example:**

```jinja2
deploy_key: #{ github_deploy_key() }#
```

**Errors:**

- `FileNotFoundError`: Deploy key file not found
- `RuntimeError`: Unexpected processing error

**Source:** Line 108

---

### `github_push_token(file_path: str = "github-push-token.txt") -> str`

Read the GitHub push token for Flux webhooks.

**Parameters:**

- `file_path` (str, optional): Path to push token file. Default: `"github-push-token.txt"`

**Returns:**

- str: GitHub personal access token

**Example:**

```jinja2
push_token: #{ github_push_token() }#
```

**Errors:**

- `FileNotFoundError`: Push token file not found
- `RuntimeError`: Unexpected processing error

**Source:** Line 118

---

### `talos_patches(value: str) -> list[str]`

List Talos patch files for the specified category.

**Parameters:**

- `value` (str): Patch category (`"global"` or `"controller"`)

**Returns:**

- list[str]: Sorted list of patch file paths
- list[str]: Empty list if directory doesn't exist

**Example:**

```jinja2
#% for patch in talos_patches('global') %#
  - #{ patch }#
#% endfor %#
#| Output:
  - templates/config/talos/patches/global/machine-time.yaml.j2
  - templates/config/talos/patches/global/machine-sysctls.yaml.j2
  - templates/config/talos/patches/global/machine-files.yaml.j2
|#
```

**Patch Categories:**

- `global`: Applied to all nodes (controller + worker)
- `controller`: Applied only to controller nodes

**Source:** Line 128

---

### `infrastructure_enabled(data: dict[str, Any]) -> bool`

Check if Proxmox infrastructure provisioning is configured.

**Parameters:**

- `data` (dict): Cluster configuration dictionary

**Returns:**

- bool: `True` if both `proxmox_api_url` and `proxmox_node` are set

**Example:**

```jinja2
#% if infrastructure_enabled(data) %#
  #| Proxmox infrastructure is enabled |#
  proxmox_node: #{ proxmox_node }#
#% endif %#
```

**Required Variables:**

- `proxmox_api_url`: Proxmox API endpoint (e.g., `https://pve.local:8006/api2/json`)
- `proxmox_node`: Proxmox node name (e.g., `pve`)

**Source:** Line 136

---

## Plugin Class

### `Plugin(data: dict[str, Any])`

Main plugin class that processes cluster configuration and computes derived variables.

**Constructor:**

```python
def __init__(self, data: dict[str, Any]):
    self._data = data
```

**Methods:**

#### `data() -> dict[str, Any]`

Process cluster configuration and compute all derived variables.

**Returns:**

- dict: Enhanced configuration with computed values

**Processing Steps:**

1. Set network defaults (`node_default_gateway`, `node_dns_servers`, `node_ntp_servers`)
2. Set Kubernetes defaults (`cluster_pod_cidr`, `cluster_svc_cidr`)
3. Set Git defaults (`repository_branch`, `repository_visibility`)
4. Compute feature enablement flags (BGP, UniFi DNS, k8s-gateway, OIDC, etc.)
5. Compute application-specific settings (Keycloak, LiteLLM, Langfuse, Obot, etc.)
6. Merge Proxmox VM defaults (if infrastructure enabled)

**Computed Variables (100+):**

| Category | Variables |
| -------- | --------- |
| **Network** | `node_default_gateway`, `cluster_pod_cidr`, `cluster_svc_cidr` |
| **DNS** | `node_dns_servers`, `node_ntp_servers` |
| **Git** | `repository_branch`, `repository_visibility` |
| **Cilium** | `cilium_loadbalancer_mode`, `cilium_bgp_enabled` |
| **DNS Services** | `unifi_dns_enabled`, `k8s_gateway_enabled` |
| **Talos** | `talos_backup_enabled`, `backup_s3_internal` |
| **OIDC/JWT** | `oidc_enabled`, `oidc_sso_enabled` |
| **Storage** | `rustfs_enabled`, `rustfs_storage_class` |
| **Observability** | `loki_deployment_mode`, `loki_monitoring_enabled` |
| **Spegel** | `spegel_enabled` (auto: `true` if > 1 node) |
| **CloudNativePG** | `cnpg_enabled`, `cnpg_backup_enabled`, `cnpg_barman_plugin_enabled`, `cnpg_pgvector_enabled` |
| **Keycloak** | `keycloak_enabled`, `keycloak_hostname`, `keycloak_issuer_url`, `keycloak_internal_issuer_url`, `keycloak_backup_enabled`, `keycloak_tracing_enabled`, `keycloak_monitoring_enabled` |
| **Dragonfly** | `dragonfly_enabled`, `dragonfly_backup_enabled`, `dragonfly_monitoring_enabled`, `dragonfly_acl_enabled` |
| **LiteLLM** | `litellm_enabled`, `litellm_hostname`, `litellm_oidc_enabled`, `litellm_backup_enabled`, `litellm_monitoring_enabled`, `litellm_tracing_enabled`, `litellm_langfuse_enabled`, `litellm_alerting_enabled`, `litellm_guardrails_enabled` |
| **Obot** | `obot_enabled`, `obot_hostname`, `obot_keycloak_enabled`, `obot_backup_enabled`, `obot_audit_logs_enabled`, `obot_monitoring_enabled`, `obot_tracing_enabled` |
| **Langfuse** | `langfuse_enabled`, `langfuse_hostname`, `langfuse_url`, `langfuse_sso_enabled`, `langfuse_backup_enabled`, `langfuse_monitoring_enabled`, `langfuse_tracing_enabled`, `langfuse_scim_sync_enabled` |
| **Grafana** | `grafana_oidc_enabled` |
| **Infrastructure** | `infrastructure_enabled`, `proxmox_vm_defaults`, `proxmox_vm_controller_defaults`, `proxmox_vm_worker_defaults`, `proxmox_vm_advanced` |

**Source:** Line 191

---

#### `filters() -> list`

Return list of Jinja2 filters.

**Returns:**

- list: `[basename, nthhost]`

**Source:** Line 812

---

#### `functions() -> list`

Return list of Jinja2 functions.

**Returns:**

- list: `[age_key, cloudflare_tunnel_id, cloudflare_tunnel_secret, github_deploy_key, github_push_token, talos_patches, infrastructure_enabled]`

**Source:** Line 815

---

## Configuration Constants

### Proxmox VM Defaults

#### `PROXMOX_VM_DEFAULTS`

Global defaults for all Proxmox VMs (Talos-optimized).

```python
{
    "cores": 4,
    "sockets": 1,
    "memory": 8192,  # MB
    "disk_size": 128,  # GB
}
```

**Source:** Line 143

---

#### `PROXMOX_VM_CONTROLLER_DEFAULTS`

Controller node VM defaults (optimized for etcd and control plane).

```python
{
    "cores": 4,
    "sockets": 1,
    "memory": 8192,  # MB
    "disk_size": 64,  # GB (smaller - etcd only, no workloads)
}
```

**Source:** Line 151

---

#### `PROXMOX_VM_WORKER_DEFAULTS`

Worker node VM defaults (optimized for running workloads).

```python
{
    "cores": 8,
    "sockets": 1,
    "memory": 16384,  # MB
    "disk_size": 256,  # GB (larger for container images and workloads)
}
```

**Source:** Line 160

---

#### `PROXMOX_VM_ADVANCED`

Advanced VM settings for Proxmox (Talos-optimized).

```python
{
    "bios": "ovmf",  # UEFI
    "machine": "q35",
    "cpu_type": "host",
    "scsi_hw": "virtio-scsi-pci",
    "balloon": 0,  # Disable memory ballooning
    "numa": True,
    "qemu_agent": True,
    "net_queues": 4,
    "disk_discard": True,
    "disk_ssd": True,
    "tags": ["kubernetes", "linux", "talos"],
    "network_bridge": "vmbr0",
    "ostype": "l26",  # Linux 2.6/3.x/4.x/5.x/6.x kernel
    "disk_backup": False,  # Exclude from Proxmox backup (K8s handles HA)
    "disk_replicate": False,  # Disable Proxmox replication
}
```

**Source:** Line 169

---

## Caching

### Performance Optimization

The plugin uses `@lru_cache` decorators for file operations to improve template rendering performance by 20-30%.

#### `_read_file_cached(file_path: str) -> str`

Cached file reader (maxsize=8).

**Source:** Line 14

---

#### `_read_json_cached(file_path: str) -> str`

Cached JSON file reader (maxsize=4).

**Source:** Line 21

---

## Error Handling

All functions raise specific exceptions for different error conditions:

| Exception | Meaning | Raised By |
| --------- | ------- | --------- |
| `FileNotFoundError` | Required file not found | `age_key`, `cloudflare_tunnel_id`, `cloudflare_tunnel_secret`, `github_deploy_key`, `github_push_token` |
| `ValueError` | Invalid input or file format | `age_key`, `cloudflare_tunnel_id`, `cloudflare_tunnel_secret`, `nthhost` |
| `json.JSONDecodeError` | Invalid JSON file | `cloudflare_tunnel_id`, `cloudflare_tunnel_secret` |
| `KeyError` | Missing required JSON key | `cloudflare_tunnel_id`, `cloudflare_tunnel_secret` |
| `RuntimeError` | Unexpected processing error | All file-reading functions |

---

## Usage Examples

### Complete Template Example

```jinja2
#| Cluster API Configuration |#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-config
data:
  #| Network configuration |#
  node_cidr: "#{ node_cidr }#"
  gateway: "#{ node_cidr | nthhost(1) }#"
  cluster_api_addr: "#{ node_cidr | nthhost(10) }#"

  #| Age encryption |#
  age_public_key: "#{ age_key('public') }#"

  #| Cloudflare Tunnel |#
  tunnel_id: "#{ cloudflare_tunnel_id() }#"
  tunnel_token: "#{ cloudflare_tunnel_secret() }#"

  #| Git deployment |#
  deploy_key: |
    #{ github_deploy_key() | indent(4) }#
  push_token: "#{ github_push_token() }#"

  #| Feature flags |#
  #% if infrastructure_enabled(data) %#
  infrastructure: "proxmox"
  #% endif %#

  #% if cilium_bgp_enabled %#
  bgp_enabled: "true"
  #% endif %#

  #% if unifi_dns_enabled %#
  dns_provider: "unifi"
  #% else %#
  dns_provider: "k8s-gateway"
  #% endif %#
```

---

## See Also

- [Template System Documentation](./ai-context/template-system.md) - Complete template system guide
- [Configuration Reference](./CONFIGURATION.md) - cluster.yaml and nodes.yaml schema
- [makejinja Documentation](https://github.com/mirkolenz/makejinja) - Template engine reference

---

**Last Updated:** 2026-01-13
**Version:** 1.0.0
**Lines of Code:** 825
**Functions:** 11
**Filters:** 2
**Computed Variables:** 100+
