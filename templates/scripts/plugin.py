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
            data.setdefault(
                "rustfs_storage_class", data.get("storage_class", "local-path")
            )

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

        # CloudNativePG - enabled when cnpg_enabled is true
        cnpg_enabled = data.get("cnpg_enabled", False)
        data["cnpg_enabled"] = cnpg_enabled

        # CNPG backup - enabled when cnpg, rustfs, and backup flag are all enabled with credentials
        cnpg_backup_enabled = (
            cnpg_enabled
            and data.get("rustfs_enabled", False)
            and data.get("cnpg_backup_enabled", False)
            and data.get("cnpg_s3_access_key")
            and data.get("cnpg_s3_secret_key")
        )
        data["cnpg_backup_enabled"] = cnpg_backup_enabled

        # Default PostgreSQL image for CNPG clusters
        cnpg_postgres_image = data.get(
            "cnpg_postgres_image",
            "ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie",
        )
        data["cnpg_postgres_image"] = cnpg_postgres_image

        # Barman Cloud Plugin - enabled when explicitly set or any backup is enabled
        # Plugin provides barman-cloud binaries via sidecar (no -system- images needed)
        # Requires cnpg_enabled for the operator to be present
        cnpg_barman_plugin_enabled = cnpg_enabled and data.get(
            "cnpg_barman_plugin_enabled", False
        )
        data["cnpg_barman_plugin_enabled"] = cnpg_barman_plugin_enabled

        # pgvector extension - enabled when cnpg and pgvector are both enabled
        cnpg_pgvector_enabled = cnpg_enabled and data.get(
            "cnpg_pgvector_enabled", False
        )
        data["cnpg_pgvector_enabled"] = cnpg_pgvector_enabled

        # Default pgvector image and version
        cnpg_pgvector_image = data.get(
            "cnpg_pgvector_image",
            "ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie",
        )
        data["cnpg_pgvector_image"] = cnpg_pgvector_image
        data.setdefault("cnpg_pgvector_version", "0.8.1")

        # Keycloak OIDC Provider - enabled when keycloak_enabled is true
        keycloak_enabled = data.get("keycloak_enabled", False)
        data["keycloak_enabled"] = keycloak_enabled

        if keycloak_enabled:
            # Derive full hostname from subdomain + cloudflare_domain
            keycloak_subdomain = data.get("keycloak_subdomain", "auth")
            cloudflare_domain = data.get("cloudflare_domain", "")
            keycloak_hostname = f"{keycloak_subdomain}.{cloudflare_domain}"
            data["keycloak_hostname"] = keycloak_hostname

            # Derive OIDC endpoints for SecurityPolicy integration
            keycloak_realm = data.get("keycloak_realm", "matherlynet")
            data["keycloak_realm"] = keycloak_realm
            data["keycloak_issuer_url"] = (
                f"https://{keycloak_hostname}/realms/{keycloak_realm}"
            )
            # Internal issuer URL for backchannel OIDC discovery (pod-to-pod)
            # Used by apps like Langfuse that need to reach Keycloak from inside the cluster
            # Keycloak's backchannelDynamic:true returns external issuer in tokens but
            # internal URLs for token/userinfo endpoints when queried via internal URL
            data["keycloak_internal_issuer_url"] = (
                f"http://keycloak-service.identity.svc.cluster.local:8080/realms/{keycloak_realm}"
            )
            data["keycloak_jwks_uri"] = (
                f"https://{keycloak_hostname}/realms/{keycloak_realm}/protocol/openid-connect/certs"
            )

            # Auto-populate OIDC JWT variables from Keycloak if not explicitly set
            # This enables JWT SecurityPolicy when Keycloak is deployed without
            # requiring manual oidc_* configuration in cluster.yaml
            if not data.get("oidc_issuer_url"):
                data["oidc_issuer_url"] = data["keycloak_issuer_url"]
            if not data.get("oidc_jwks_uri"):
                data["oidc_jwks_uri"] = data["keycloak_jwks_uri"]
            if not data.get("oidc_provider_name"):
                data["oidc_provider_name"] = "keycloak"

            # Recalculate oidc_enabled now that Keycloak values may have been applied
            # This must happen here (inside keycloak block) to override the earlier check
            data["oidc_enabled"] = bool(
                data.get("oidc_issuer_url") and data.get("oidc_jwks_uri")
            )

            # Default operator version
            data.setdefault("keycloak_operator_version", "26.5.0")

            # Default database settings
            data.setdefault("keycloak_db_mode", "embedded")
            data.setdefault("keycloak_db_name", "keycloak")
            data.setdefault("keycloak_db_user", "keycloak")
            data.setdefault("keycloak_db_instances", 1)
            data.setdefault("keycloak_replicas", 1)
            data.setdefault("keycloak_storage_size", "5Gi")

            # When Keycloak uses CNPG mode, require cnpg_enabled
            keycloak_db_mode = data.get("keycloak_db_mode", "embedded")
            if keycloak_db_mode == "cnpg" and not cnpg_enabled:
                # This will be caught by CUE validation, but set a flag for clarity
                data["keycloak_cnpg_missing"] = True

            # Keycloak PostgreSQL backup - enabled when RustFS and credentials are provided
            # Works with both CNPG mode (barmanObjectStore) and embedded mode (pg_dump CronJob)
            keycloak_backup_enabled = (
                data.get("rustfs_enabled", False)
                and data.get("keycloak_s3_access_key")
                and data.get("keycloak_s3_secret_key")
            )
            data["keycloak_backup_enabled"] = keycloak_backup_enabled

            # Keycloak OpenTelemetry tracing - requires global tracing_enabled
            # When both are true, Keycloak exports traces to Tempo via OTLP gRPC
            keycloak_tracing_enabled = data.get("tracing_enabled", False) and data.get(
                "keycloak_tracing_enabled", False
            )
            data["keycloak_tracing_enabled"] = keycloak_tracing_enabled

            # Keycloak Grafana monitoring - requires global monitoring_enabled
            # When both are true, Keycloak deploys ServiceMonitor and dashboards
            keycloak_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("keycloak_monitoring_enabled", False)
            data["keycloak_monitoring_enabled"] = keycloak_monitoring_enabled
        else:
            data["keycloak_backup_enabled"] = False
            data["keycloak_tracing_enabled"] = False
            data["keycloak_monitoring_enabled"] = False

        # RustFS Grafana monitoring - requires global monitoring_enabled
        # When both are true, RustFS deploys ServiceMonitor and dashboards
        if data.get("rustfs_enabled", False):
            rustfs_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("rustfs_monitoring_enabled", False)
            data["rustfs_monitoring_enabled"] = rustfs_monitoring_enabled
        else:
            data["rustfs_monitoring_enabled"] = False

        # Loki Grafana monitoring - requires global monitoring_enabled
        # When both are true, Loki deploys supplemental stack monitoring dashboard
        if data.get("loki_enabled", False):
            loki_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("loki_monitoring_enabled", False)
            data["loki_monitoring_enabled"] = loki_monitoring_enabled
        else:
            data["loki_monitoring_enabled"] = False

        # Grafana OIDC - native OAuth for Grafana RBAC
        # Requires monitoring_enabled, keycloak_enabled, and explicit enable with client secret
        # When enabled, creates dedicated Keycloak client and configures Grafana auth.generic_oauth
        grafana_oidc_enabled = (
            data.get("monitoring_enabled", False)
            and data.get("keycloak_enabled", False)
            and data.get("grafana_oidc_enabled", False)
            and data.get("grafana_oidc_client_secret")
        )
        data["grafana_oidc_enabled"] = grafana_oidc_enabled

        # OIDC SSO (Web browser authentication) - requires explicit enable and client credentials
        # Distinct from oidc_enabled (JWT API auth) - this enables session-based browser SSO
        # Requires: oidc_issuer_url (shared with JWT), client_id, client_secret
        # Optional: oidc_redirect_url (omit for dynamic redirect based on request hostname)
        oidc_sso_enabled = (
            data.get("oidc_sso_enabled", False)
            and data.get("oidc_issuer_url")
            and data.get("oidc_client_id")
            and data.get("oidc_client_secret")
        )
        data["oidc_sso_enabled"] = oidc_sso_enabled

        # Keycloak OIDC client bootstrap - auto-create envoy-gateway client in realm import
        # When keycloak_enabled + oidc_sso_enabled + oidc_client_secret are all set,
        # the OIDC client is automatically bootstrapped with the provided secret.
        # This eliminates manual Keycloak admin console setup for the Envoy Gateway client.
        keycloak_bootstrap_oidc_client = (
            keycloak_enabled and oidc_sso_enabled and data.get("oidc_client_secret")
        )
        data["keycloak_bootstrap_oidc_client"] = keycloak_bootstrap_oidc_client

        # Dragonfly cache - Redis-compatible in-memory data store
        # Enabled when dragonfly_enabled is true
        dragonfly_enabled = data.get("dragonfly_enabled", False)
        data["dragonfly_enabled"] = dragonfly_enabled

        if dragonfly_enabled:
            # Default versions
            data.setdefault("dragonfly_version", "v1.36.0")
            data.setdefault("dragonfly_operator_version", "1.3.1")
            data.setdefault("dragonfly_replicas", 1)
            data.setdefault("dragonfly_maxmemory", "512mb")
            data.setdefault("dragonfly_threads", 2)

            # Performance and debugging defaults
            data.setdefault("dragonfly_cache_mode", False)
            data.setdefault("dragonfly_slowlog_threshold", 10000)
            data.setdefault("dragonfly_slowlog_max_len", 128)

            # Backup configuration - requires RustFS and credentials
            dragonfly_backup_enabled = (
                data.get("rustfs_enabled", False)
                and data.get("dragonfly_backup_enabled", False)
                and data.get("dragonfly_s3_access_key")
                and data.get("dragonfly_s3_secret_key")
            )
            data["dragonfly_backup_enabled"] = dragonfly_backup_enabled

            # Monitoring configuration - requires global monitoring_enabled
            dragonfly_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("dragonfly_monitoring_enabled", False)
            data["dragonfly_monitoring_enabled"] = dragonfly_monitoring_enabled

            # ACL configuration - enabled when explicitly set
            dragonfly_acl_enabled = data.get("dragonfly_acl_enabled", False)
            data["dragonfly_acl_enabled"] = dragonfly_acl_enabled
        else:
            data["dragonfly_backup_enabled"] = False
            data["dragonfly_monitoring_enabled"] = False
            data["dragonfly_acl_enabled"] = False

        # LiteLLM Proxy Gateway - AI model gateway with multi-provider support
        # Enabled when litellm_enabled is true
        litellm_enabled = data.get("litellm_enabled", False)
        data["litellm_enabled"] = litellm_enabled

        if litellm_enabled:
            # Derive full hostname from subdomain + cloudflare_domain
            litellm_subdomain = data.get("litellm_subdomain", "litellm")
            cloudflare_domain = data.get("cloudflare_domain", "")
            litellm_hostname = f"{litellm_subdomain}.{cloudflare_domain}"
            data["litellm_hostname"] = litellm_hostname

            # Default settings
            data.setdefault("litellm_replicas", 1)
            data.setdefault("litellm_db_name", "litellm")
            data.setdefault("litellm_db_user", "litellm")
            data.setdefault("litellm_db_instances", 1)

            # Azure OpenAI API version defaults
            # These are used in credential_list for centralized credential management
            data.setdefault("azure_openai_us_east_api_version", "2025-01-01-preview")
            data.setdefault("azure_openai_us_east2_api_version", "2025-04-01-preview")

            # LiteLLM OIDC - native SSO for LiteLLM UI
            # Requires keycloak_enabled and explicit enable with client secret
            litellm_oidc_enabled = (
                data.get("keycloak_enabled", False)
                and data.get("litellm_oidc_enabled", False)
                and data.get("litellm_oidc_client_secret")
            )
            data["litellm_oidc_enabled"] = litellm_oidc_enabled

            # LiteLLM backup - enabled when RustFS and credentials are provided
            litellm_backup_enabled = (
                data.get("rustfs_enabled", False)
                and data.get("litellm_s3_access_key")
                and data.get("litellm_s3_secret_key")
            )
            data["litellm_backup_enabled"] = litellm_backup_enabled

            # LiteLLM Grafana monitoring - requires global monitoring_enabled
            litellm_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("litellm_monitoring_enabled", False)
            data["litellm_monitoring_enabled"] = litellm_monitoring_enabled

            # LiteLLM OpenTelemetry tracing - requires global tracing_enabled
            litellm_tracing_enabled = data.get("tracing_enabled", False) and data.get(
                "litellm_tracing_enabled", False
            )
            data["litellm_tracing_enabled"] = litellm_tracing_enabled

            # Langfuse observability - optional LLM observability
            # Can connect to self-hosted Langfuse (langfuse_enabled) or Langfuse Cloud
            litellm_langfuse_enabled = (
                data.get("litellm_langfuse_enabled", False)
                and data.get("litellm_langfuse_public_key")
                and data.get("litellm_langfuse_secret_key")
            )
            data["litellm_langfuse_enabled"] = litellm_langfuse_enabled

            # Auto-derive Langfuse host URL for self-hosted Langfuse
            # If langfuse_enabled (self-hosted), use internal cluster URL
            # Otherwise, use the configured host (defaults to cloud.langfuse.com)
            if data.get("langfuse_enabled", False):
                data.setdefault(
                    "litellm_langfuse_host",
                    "http://langfuse-web.ai-system.svc.cluster.local:3000",
                )
            else:
                data.setdefault("litellm_langfuse_host", "https://cloud.langfuse.com")

            # LiteLLM Alerting - Slack/Discord webhook notifications
            # Enabled when alerting flag is set and at least one webhook is configured
            litellm_alerting_enabled = data.get("litellm_alerting_enabled", False) and (
                data.get("litellm_slack_webhook_url")
                or data.get("litellm_discord_webhook_url")
            )
            data["litellm_alerting_enabled"] = litellm_alerting_enabled
            data.setdefault("litellm_alerting_threshold", 300)

            # LiteLLM Guardrails - content safety and security
            # Each guardrail feature can be independently enabled
            litellm_guardrails_enabled = data.get("litellm_guardrails_enabled", False)
            data["litellm_guardrails_enabled"] = litellm_guardrails_enabled

            litellm_presidio_enabled = data.get("litellm_presidio_enabled", False)
            data["litellm_presidio_enabled"] = litellm_presidio_enabled

            litellm_prompt_injection_check = data.get(
                "litellm_prompt_injection_check", False
            )
            data["litellm_prompt_injection_check"] = litellm_prompt_injection_check
        else:
            data["litellm_oidc_enabled"] = False
            data["litellm_backup_enabled"] = False
            data["litellm_monitoring_enabled"] = False
            data["litellm_tracing_enabled"] = False
            data["litellm_langfuse_enabled"] = False
            data["litellm_alerting_enabled"] = False
            data["litellm_guardrails_enabled"] = False
            data["litellm_presidio_enabled"] = False
            data["litellm_prompt_injection_check"] = False

        # Obot MCP Gateway - AI agent platform with MCP server hosting
        # Enabled when obot_enabled is true
        obot_enabled = data.get("obot_enabled", False)
        data["obot_enabled"] = obot_enabled

        if obot_enabled:
            # Derive full hostname from subdomain + cloudflare_domain
            obot_subdomain = data.get("obot_subdomain", "obot")
            cloudflare_domain = data.get("cloudflare_domain", "")
            obot_hostname = f"{obot_subdomain}.{cloudflare_domain}"
            data["obot_hostname"] = obot_hostname

            # Default settings
            data.setdefault("obot_version", "0.2.31")
            data.setdefault("obot_replicas", 1)
            data.setdefault("obot_mcp_namespace", "obot-mcp")
            data.setdefault("obot_postgres_user", "obot")
            data.setdefault("obot_postgres_db", "obot")
            data.setdefault("obot_postgresql_replicas", 1)
            data.setdefault("obot_postgresql_storage_size", "10Gi")
            data.setdefault("obot_storage_size", "20Gi")
            data.setdefault("obot_keycloak_client_id", "obot")

            # Keycloak integration - derive URLs for custom auth provider
            # Uses jrmatherly/obot-entraid fork with OBOT_KEYCLOAK_AUTH_PROVIDER_* vars
            if data.get("obot_keycloak_enabled") and data.get("keycloak_enabled"):
                keycloak_realm = data.get("keycloak_realm", "matherlynet")
                keycloak_hostname = data.get("keycloak_hostname")
                # External base URL for OBOT_KEYCLOAK_AUTH_PROVIDER_URL
                # All traffic routes through Cloudflare Tunnel to avoid hairpin NAT
                # and ensure OIDC issuer consistency (Keycloak returns external issuer)
                data["obot_keycloak_base_url"] = f"https://{keycloak_hostname}"
                # Issuer URL for reference (external - matches Keycloak's returned issuer)
                data["obot_keycloak_issuer_url"] = (
                    f"https://{keycloak_hostname}/realms/{keycloak_realm}"
                )
                # Realm name for OBOT_KEYCLOAK_AUTH_PROVIDER_REALM
                data["obot_keycloak_realm"] = keycloak_realm
                data["obot_keycloak_enabled"] = True
            else:
                data["obot_keycloak_enabled"] = False

            # Backup enabled when RustFS + credentials configured
            obot_backup_enabled = (
                data.get("rustfs_enabled", False)
                and data.get("obot_s3_access_key")
                and data.get("obot_s3_secret_key")
            )
            data["obot_backup_enabled"] = obot_backup_enabled

            # Audit log export enabled when RustFS + audit credentials configured
            obot_audit_logs_enabled = (
                data.get("rustfs_enabled", False)
                and data.get("obot_audit_s3_access_key")
                and data.get("obot_audit_s3_secret_key")
            )
            data["obot_audit_logs_enabled"] = obot_audit_logs_enabled

            # Monitoring enabled when both flags set
            obot_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("obot_monitoring_enabled", False)
            data["obot_monitoring_enabled"] = obot_monitoring_enabled

            # Tracing enabled when both flags set
            obot_tracing_enabled = data.get("tracing_enabled", False) and data.get(
                "obot_tracing_enabled", False
            )
            data["obot_tracing_enabled"] = obot_tracing_enabled
        else:
            data["obot_keycloak_enabled"] = False
            data["obot_backup_enabled"] = False
            data["obot_audit_logs_enabled"] = False
            data["obot_monitoring_enabled"] = False
            data["obot_tracing_enabled"] = False

        # Langfuse LLM Observability - tracing, prompts, evaluation, analytics
        # Enabled when langfuse_enabled is true
        langfuse_enabled = data.get("langfuse_enabled", False)
        data["langfuse_enabled"] = langfuse_enabled

        if langfuse_enabled:
            # Derive full hostname from subdomain + cloudflare_domain
            langfuse_subdomain = data.get("langfuse_subdomain", "langfuse")
            cloudflare_domain = data.get("cloudflare_domain", "")
            langfuse_hostname = f"{langfuse_subdomain}.{cloudflare_domain}"
            data["langfuse_hostname"] = langfuse_hostname
            data["langfuse_url"] = f"https://{langfuse_hostname}"

            # Default settings
            data.setdefault("langfuse_subdomain", "langfuse")
            data.setdefault("langfuse_postgres_instances", 1)
            data.setdefault("langfuse_postgres_storage", "10Gi")
            data.setdefault("langfuse_clickhouse_storage", "20Gi")
            data.setdefault("langfuse_clickhouse_replicas", 1)
            data.setdefault("langfuse_log_level", "info")
            data.setdefault("langfuse_trace_sampling_ratio", "0.1")
            data.setdefault("langfuse_web_replicas", 1)
            data.setdefault("langfuse_worker_replicas", 1)

            # Headless initialization defaults
            # Default admin display name
            data.setdefault("langfuse_init_user_name", "Admin")
            # Default org name derived from cluster_name
            data.setdefault(
                "langfuse_init_org_name", data.get("cluster_name", "Langfuse")
            )
            # Disable signup defaults to false (allow signups unless explicitly disabled)
            data.setdefault("langfuse_disable_signup", False)

            # Langfuse SSO - Keycloak OIDC integration
            # Requires keycloak_enabled and explicit enable with client secret
            langfuse_sso_enabled = (
                data.get("keycloak_enabled", False)
                and data.get("langfuse_sso_enabled", False)
                and data.get("langfuse_keycloak_client_secret")
            )
            data["langfuse_sso_enabled"] = langfuse_sso_enabled

            # Langfuse backup - enabled when RustFS and credentials are provided
            langfuse_backup_enabled = (
                data.get("rustfs_enabled", False)
                and data.get("langfuse_backup_enabled", False)
                and data.get("langfuse_s3_access_key")
                and data.get("langfuse_s3_secret_key")
            )
            data["langfuse_backup_enabled"] = langfuse_backup_enabled

            # Langfuse Grafana monitoring - requires global monitoring_enabled
            langfuse_monitoring_enabled = data.get(
                "monitoring_enabled", False
            ) and data.get("langfuse_monitoring_enabled", False)
            data["langfuse_monitoring_enabled"] = langfuse_monitoring_enabled

            # Langfuse OpenTelemetry tracing - requires global tracing_enabled
            langfuse_tracing_enabled = data.get("tracing_enabled", False) and data.get(
                "langfuse_tracing_enabled", False
            )
            data["langfuse_tracing_enabled"] = langfuse_tracing_enabled

            # Langfuse SCIM role sync - requires keycloak_enabled and explicit enable
            # Syncs Keycloak realm roles to Langfuse organization roles via SCIM API
            # REF: docs/research/langfuse-scim-role-sync-implementation-jan-2026.md
            langfuse_scim_sync_enabled = (
                data.get("keycloak_enabled", False)
                and data.get("langfuse_scim_sync_enabled", False)
                and data.get("langfuse_scim_public_key")
                and data.get("langfuse_scim_secret_key")
                and data.get("langfuse_sync_keycloak_client_secret")
            )
            data["langfuse_scim_sync_enabled"] = langfuse_scim_sync_enabled

            # Default SCIM sync schedule (every 5 minutes)
            data.setdefault("langfuse_scim_sync_schedule", "*/5 * * * *")

            # Default Keycloak sync client ID
            data.setdefault("langfuse_sync_keycloak_client_id", "langfuse-sync")

            # Default role mapping (Keycloak roles → Langfuse roles)
            # admin → ADMIN, operator/developer → MEMBER, default → VIEWER
            data.setdefault(
                "langfuse_role_mapping",
                {
                    "admin": "ADMIN",
                    "operator": "MEMBER",
                    "developer": "MEMBER",
                    "default": "VIEWER",
                },
            )
        else:
            data["langfuse_sso_enabled"] = False
            data["langfuse_backup_enabled"] = False
            data["langfuse_monitoring_enabled"] = False
            data["langfuse_tracing_enabled"] = False
            data["langfuse_scim_sync_enabled"] = False

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
