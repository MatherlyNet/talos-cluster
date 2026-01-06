import base64
import ipaddress
import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

import makejinja


# Cached file readers for 20-30% render improvement
# See: docs/REVIEW-FOLLOWUP-JAN-2026.md item #10
@lru_cache(maxsize=8)
def _read_file_cached(file_path: str) -> str:
    """Read and cache file contents. Cached for performance during template rendering."""
    with open(file_path, "r") as file:
        return file.read().strip()


@lru_cache(maxsize=4)
def _read_json_cached(file_path: str) -> str:
    """Read and cache JSON file contents as string. Parsed by caller."""
    with open(file_path, "r") as file:
        return file.read()


# Return the filename of a path without the j2 extension
def basename(value: str) -> str:
    return Path(value).stem


# Return the nth host in a CIDR range
def nthhost(value: str, query: int) -> str:
    try:
        network = ipaddress.ip_network(value, strict=False)
        if 0 <= query < network.num_addresses:
            return str(network[query])
    except ValueError:
        pass
    return False


# Return the age public or private key from age.key
def age_key(key_type: str, file_path: str = "age.key") -> str:
    try:
        file_content = _read_file_cached(file_path)
        if key_type == "public":
            key_match = re.search(r"# public key: (age1[\w]+)", file_content)
            if not key_match:
                raise ValueError("Could not find public key in the age key file.")
            return key_match.group(1)
        elif key_type == "private":
            key_match = re.search(r"(AGE-SECRET-KEY-[\w]+)", file_content)
            if not key_match:
                raise ValueError("Could not find private key in the age key file.")
            return key_match.group(1)
        else:
            raise ValueError("Invalid key type. Use 'public' or 'private'.")
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return cloudflare tunnel fields from cloudflare-tunnel.json
def cloudflare_tunnel_id(file_path: str = "cloudflare-tunnel.json") -> str:
    try:
        data = json.loads(_read_json_cached(file_path))
        tunnel_id = data.get("TunnelID")
        if tunnel_id is None:
            raise KeyError(f"Missing 'TunnelID' key in {file_path}")
        return tunnel_id

    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except json.JSONDecodeError:
        raise ValueError(f"Could not decode JSON file: {file_path}")
    except KeyError as e:
        raise KeyError(f"Error in JSON structure: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return cloudflare tunnel fields from cloudflare-tunnel.json in TUNNEL_TOKEN format
def cloudflare_tunnel_secret(file_path: str = "cloudflare-tunnel.json") -> str:
    try:
        data = json.loads(_read_json_cached(file_path))
        transformed_data = {
            "a": data["AccountTag"],
            "t": data["TunnelID"],
            "s": data["TunnelSecret"],
        }
        json_string = json.dumps(transformed_data, separators=(",", ":"))
        return base64.b64encode(json_string.encode("utf-8")).decode("utf-8")

    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except json.JSONDecodeError:
        raise ValueError(f"Could not decode JSON file: {file_path}")
    except KeyError as e:
        raise KeyError(f"Missing key in JSON file {file_path}: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return the GitHub deploy key from github-deploy.key
def github_deploy_key(file_path: str = "github-deploy.key") -> str:
    try:
        return _read_file_cached(file_path)
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while reading {file_path}: {e}")


# Return the Flux / GitHub push token from github-push-token.txt
def github_push_token(file_path: str = "github-push-token.txt") -> str:
    try:
        return _read_file_cached(file_path)
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while reading {file_path}: {e}")


# Return a list of files in the talos patches directory
def talos_patches(value: str) -> list[str]:
    path = Path(f"templates/config/talos/patches/{value}")
    if not path.is_dir():
        return []
    return [str(f) for f in sorted(path.glob("*.yaml.j2")) if f.is_file()]


# Check if infrastructure provisioning is enabled (Proxmox)
def infrastructure_enabled(data: dict[str, Any]) -> bool:
    """Check if Proxmox infrastructure provisioning is configured."""
    return bool(data.get("proxmox_api_url") and data.get("proxmox_node"))


# Default VM settings for Proxmox (Talos-optimized)
# These are global defaults; role-based defaults below take precedence
PROXMOX_VM_DEFAULTS = {
    "cores": 4,
    "sockets": 1,
    "memory": 8192,
    "disk_size": 128,
}

# Controller node VM defaults (optimized for etcd and control plane)
# Controllers typically need fewer resources but fast disk for etcd
PROXMOX_VM_CONTROLLER_DEFAULTS = {
    "cores": 4,
    "sockets": 1,
    "memory": 8192,
    "disk_size": 64,  # Smaller disk - etcd only, no workloads
}

# Worker node VM defaults (optimized for running workloads)
# Workers typically need more resources for application pods
PROXMOX_VM_WORKER_DEFAULTS = {
    "cores": 8,
    "sockets": 1,
    "memory": 16384,
    "disk_size": 256,  # Larger disk for container images and workloads
}

# Advanced VM settings for Proxmox (Talos-optimized)
PROXMOX_VM_ADVANCED = {
    "bios": "ovmf",
    "machine": "q35",
    "cpu_type": "host",
    "scsi_hw": "virtio-scsi-pci",
    "balloon": 0,
    "numa": True,
    "qemu_agent": True,
    "net_queues": 4,
    "disk_discard": True,
    "disk_ssd": True,
    "tags": ["kubernetes", "linux", "talos"],
    # Network configuration
    "network_bridge": "vmbr0",  # Proxmox bridge interface for VM networking
    # Guest OS configuration
    "ostype": "l26",  # Linux 2.6/3.x/4.x/5.x/6.x kernel
    # Storage flags (Talos is immutable, skip backups/replication)
    "disk_backup": False,  # Exclude from Proxmox backup jobs
    "disk_replicate": False,  # Disable Proxmox replication (K8s handles HA)
}


class Plugin(makejinja.plugin.Plugin):
    def __init__(self, data: dict[str, Any]):
        self._data = data

    def data(self) -> makejinja.plugin.Data:
        data = self._data

        # Set default values for optional fields
        data.setdefault("node_default_gateway", nthhost(data.get("node_cidr"), 1))
        data.setdefault("node_dns_servers", ["1.1.1.1", "1.0.0.1"])
        data.setdefault("node_ntp_servers", ["162.159.200.1", "162.159.200.123"])
        data.setdefault("cluster_pod_cidr", "10.42.0.0/16")
        data.setdefault("cluster_svc_cidr", "10.43.0.0/16")
        data.setdefault("repository_branch", "main")
        data.setdefault("repository_visibility", "public")
        data.setdefault("cilium_loadbalancer_mode", "dsr")

        # If all BGP keys are set, enable BGP
        bgp_keys = [
            "cilium_bgp_router_addr",
            "cilium_bgp_router_asn",
            "cilium_bgp_node_asn",
        ]
        bgp_enabled = all(data.get(key) for key in bgp_keys)
        data.setdefault("cilium_bgp_enabled", bgp_enabled)

        # UniFi DNS integration - when enabled, replaces k8s-gateway
        # Both unifi_host and unifi_api_key must be set to enable
        unifi_dns_enabled = bool(data.get("unifi_host") and data.get("unifi_api_key"))
        data["unifi_dns_enabled"] = unifi_dns_enabled

        # k8s-gateway is only enabled when UniFi DNS is NOT configured
        # This is mutually exclusive with unifi_dns_enabled
        k8s_gateway_enabled = not unifi_dns_enabled
        data["k8s_gateway_enabled"] = k8s_gateway_enabled

        # Talos Backup - enabled when S3 endpoint and bucket are configured
        # Both backup_s3_endpoint and backup_s3_bucket must be set to enable
        talos_backup_enabled = bool(
            data.get("backup_s3_endpoint") and data.get("backup_s3_bucket")
        )
        data["talos_backup_enabled"] = talos_backup_enabled

        # Talos Backup - detect internal vs external S3 endpoint
        # Internal RustFS uses .svc.cluster.local DNS, requires path-style URLs and no SSL
        backup_s3_endpoint = data.get("backup_s3_endpoint", "")
        backup_s3_internal = "svc.cluster.local" in backup_s3_endpoint
        data["backup_s3_internal"] = backup_s3_internal

        # OIDC/JWT authentication - enabled when issuer URL and JWKS URI are configured
        # Both oidc_issuer_url and oidc_jwks_uri must be set to enable
        oidc_enabled = bool(data.get("oidc_issuer_url") and data.get("oidc_jwks_uri"))
        data["oidc_enabled"] = oidc_enabled

        # RustFS shared storage - enabled when rustfs_enabled is true
        # When RustFS is enabled, Loki uses S3 backend for SimpleScalable mode
        rustfs_enabled = data.get("rustfs_enabled", False)
        data["rustfs_enabled"] = rustfs_enabled
        if rustfs_enabled:
            # Set default storage class for RustFS if not specified
            data.setdefault("rustfs_storage_class", data.get("storage_class", "local-path"))

        # Loki deployment mode is determined by RustFS availability
        # SimpleScalable mode when RustFS is available, SingleBinary otherwise
        if data.get("loki_enabled"):
            if rustfs_enabled:
                data["loki_deployment_mode"] = "SimpleScalable"
            else:
                data["loki_deployment_mode"] = "SingleBinary"

        # If there is more than one node, enable spegel (can be overridden by user)
        if "spegel_enabled" not in data:
            data["spegel_enabled"] = len(data.get("nodes", [])) > 1

        # Infrastructure (OpenTofu/Proxmox) defaults
        # Check if infrastructure provisioning is enabled
        data["infrastructure_enabled"] = infrastructure_enabled(data)

        if data["infrastructure_enabled"]:
            # Set Proxmox storage defaults
            data.setdefault("proxmox_iso_storage", "local")
            data.setdefault("proxmox_disk_storage", "local-lvm")

            # Merge user-provided vm_defaults with our defaults (global fallback)
            user_vm_defaults = data.get("proxmox_vm_defaults", {})
            merged_vm_defaults = {**PROXMOX_VM_DEFAULTS, **user_vm_defaults}
            data["proxmox_vm_defaults"] = merged_vm_defaults

            # Merge user-provided controller VM defaults with our defaults
            # Fallback chain: user controller -> built-in controller -> global defaults
            user_vm_controller = data.get("proxmox_vm_controller_defaults", {})
            merged_vm_controller = {
                **merged_vm_defaults,  # Start with global defaults
                **PROXMOX_VM_CONTROLLER_DEFAULTS,  # Apply built-in controller defaults
                **user_vm_controller,  # Apply user overrides
            }
            data["proxmox_vm_controller_defaults"] = merged_vm_controller

            # Merge user-provided worker VM defaults with our defaults
            # Fallback chain: user worker -> built-in worker -> global defaults
            user_vm_worker = data.get("proxmox_vm_worker_defaults", {})
            merged_vm_worker = {
                **merged_vm_defaults,  # Start with global defaults
                **PROXMOX_VM_WORKER_DEFAULTS,  # Apply built-in worker defaults
                **user_vm_worker,  # Apply user overrides
            }
            data["proxmox_vm_worker_defaults"] = merged_vm_worker

            # Merge user-provided vm_advanced with our defaults
            user_vm_advanced = data.get("proxmox_vm_advanced", {})
            merged_vm_advanced = {**PROXMOX_VM_ADVANCED, **user_vm_advanced}
            data["proxmox_vm_advanced"] = merged_vm_advanced

        return data

    def filters(self) -> makejinja.plugin.Filters:
        return [basename, nthhost]

    def functions(self) -> makejinja.plugin.Functions:
        return [
            age_key,
            cloudflare_tunnel_id,
            cloudflare_tunnel_secret,
            github_deploy_key,
            github_push_token,
            talos_patches,
            infrastructure_enabled,
        ]
