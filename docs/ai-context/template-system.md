# Template System Guide

> Deep-dive documentation for AI assistants working with the makejinja template system.

## Overview

This project uses [makejinja](https://github.com/mirkolenz/makejinja) for templating. It's a Jinja2-based tool with custom delimiters designed to avoid conflicts with YAML and Helm templating.

## Configuration

### makejinja.toml

```toml
[makejinja]
inputs = ["./templates/overrides", "./templates/config"]
output = "./"
exclude_patterns = ["*.partial.yaml.j2"]
data = ["./cluster.yaml", "./nodes.yaml"]
import_paths = ["./templates/scripts"]
loaders = ["plugin:Plugin"]
jinja_suffix = ".j2"
copy_metadata = true
force = true
undefined = "chainable"

[makejinja.delimiter]
block_start = "#%"
block_end = "%#"
comment_start = "#|"
comment_end = "#|"
variable_start = "#{"
variable_end = "}#"
```

### Why Custom Delimiters?

Standard Jinja delimiters (`{{ }}`, `{% %}`) conflict with:

- YAML multiline strings
- Helm template syntax
- Go templates

Custom delimiters allow templates to be valid YAML while containing Jinja logic.

## Syntax Reference

### Variable Interpolation

```yaml
# Standard
domain: "#{ cloudflare_domain }#"

# With filter
gateway: "#{ node_cidr | nthhost(1) }#"

# With default
timeout: "#{ custom_timeout | default('30m') }#"
```

### Conditionals

```yaml
#% if cilium_bgp_enabled %#
bgpControlPlane:
  enabled: true
#% endif %#

#% if repository_visibility == 'private' %#
  secretRef:
    name: github-deploy-key
#% endif %#
```

### Loops

```yaml
#% for node in nodes %#
  - hostname: "#{ node.name }#"
    address: "#{ node.address }#"
#% endfor %#

#% for node in nodes if node.controller %#
  - name: "#{ node.name }#"
#% endfor %#
```

### Comments

**IMPORTANT: Comment delimiters are SYMMETRICAL** - both start AND end use `#|`

Unlike blocks (`#%`/`%#`) and variables (`#{`/`}#`) which mirror, comments use the SAME delimiter on both ends:

```yaml
#| This is a template comment - not rendered #|
#| Multi-line comments work too
   Just keep using the same delimiters #|
```

⚠️ **Common Mistake**: Do NOT use `|#` for comment end - that's incorrect extrapolation from the block/variable pattern.

## Data Sources

### cluster.yaml

Primary cluster configuration:

```yaml
# Required
node_cidr: "192.168.1.0/24"
cluster_api_addr: "192.168.1.100"
cluster_gateway_addr: "192.168.1.101"
cluster_dns_gateway_addr: "192.168.1.102"
cloudflare_gateway_addr: "192.168.1.103"
cloudflare_domain: "example.com"
cloudflare_token: "abc123..."
repository_name: "user/repo"

# Optional with defaults
repository_branch: "main"
cluster_pod_cidr: "10.42.0.0/16"
cluster_svc_cidr: "10.43.0.0/16"
cilium_loadbalancer_mode: "dsr"
```

### nodes.yaml

Node definitions:

```yaml
nodes:
  - name: "k8s-node-1"
    address: "192.168.1.10"
    controller: true
    disk: "/dev/nvme0n1"
    mac_addr: "aa:bb:cc:dd:ee:01"
    schematic_id: "a1b2c3d4..."
```

Both files are loaded and merged. Use `nodes` to iterate over nodes.

## Plugin Functions

Located at `templates/scripts/plugin.py`:

### Filters

| Filter | Usage | Description |
| -------- | ------- | ------------- |
| `basename` | `path \| basename` | Extract filename, remove .j2 |
| `nthhost` | `cidr \| nthhost(n)` | Get nth IP in CIDR |

Examples:

```yaml
# Get first IP in network
gateway: "#{ node_cidr | nthhost(1) }#"  # 192.168.1.1

# Get 10th IP
vip: "#{ node_cidr | nthhost(10) }#"  # 192.168.1.10
```

### Functions

| Function | Description |
| ---------- | ------------- |
| `age_key('public')` | Public key from age.key |
| `age_key('private')` | Private key from age.key |
| `cloudflare_tunnel_id()` | Tunnel ID from cloudflare-tunnel.json |
| `cloudflare_tunnel_secret()` | Base64 tunnel secret |
| `github_deploy_key()` | SSH key from github-deploy.key |
| `github_push_token()` | Token from github-push-token.txt |
| `talos_patches(type)` | List patch files for type |
| `infrastructure_enabled()` | Check if Proxmox infrastructure is configured |

Examples:

```yaml
# SOPS configuration
age: "#{ age_key('public') }#"

# Talos patches
#% for patch in talos_patches('global') %#
  - @./patches/global/#{ patch | basename }#
#% endfor %#
```

### Computed Defaults

**Simple Defaults** - Set automatically if not defined in cluster.yaml:

| Variable | Default Value |
| ---------- | -------------- |
| `node_default_gateway` | First IP in node_cidr (via nthhost) |
| `node_dns_servers` | `["1.1.1.1", "1.0.0.1"]` |
| `node_ntp_servers` | `["162.159.200.1", "162.159.200.123"]` |
| `cluster_pod_cidr` | `10.42.0.0/16` |
| `cluster_svc_cidr` | `10.43.0.0/16` |
| `repository_branch` | `main` |
| `repository_visibility` | `public` |
| `cilium_loadbalancer_mode` | `dsr` |

**Network & Infrastructure** - Computed from configuration:

| Variable | Computed When |
| ---------- | --------------- |
| `cilium_bgp_enabled` | All BGP keys present (router_addr, router_asn, node_asn) |
| `spegel_enabled` | More than 1 node (or explicitly set) |
| `unifi_dns_enabled` | unifi_host + unifi_api_key set |
| `k8s_gateway_enabled` | unifi_dns_enabled is false (mutually exclusive) |
| `talos_backup_enabled` | backup_s3_endpoint + backup_s3_bucket set |
| `backup_s3_internal` | backup_s3_endpoint contains `.svc.cluster.local` |
| `infrastructure_enabled` | proxmox_api_url + proxmox_node set |

**Authentication & OIDC** - Auto-derived from Keycloak or explicit config:

| Variable | Computed When |
| ---------- | --------------- |
| `oidc_enabled` | oidc_issuer_url + oidc_jwks_uri set |
| `oidc_sso_enabled` | oidc_sso_enabled + issuer_url + client_id + client_secret set |
| `keycloak_enabled` | keycloak_enabled explicitly true |
| `keycloak_hostname` | `{keycloak_subdomain}.{cloudflare_domain}` |
| `keycloak_issuer_url` | `https://{keycloak_hostname}/realms/{keycloak_realm}` |
| `keycloak_internal_issuer_url` | `http://keycloak-service.identity.svc.cluster.local:8080/realms/{keycloak_realm}` |
| `keycloak_jwks_uri` | `{keycloak_issuer_url}/protocol/openid-connect/certs` |
| `keycloak_bootstrap_oidc_client` | keycloak_enabled + oidc_sso_enabled + oidc_client_secret set |
| `grafana_oidc_enabled` | monitoring + keycloak + grafana_oidc_enabled + client_secret set |

**Database (CNPG)** - PostgreSQL operator features:

| Variable | Computed When |
| ---------- | --------------- |
| `cnpg_enabled` | cnpg_enabled explicitly true |
| `cnpg_backup_enabled` | cnpg + rustfs + cnpg_backup_enabled + S3 credentials set |
| `cnpg_barman_plugin_enabled` | cnpg_enabled + cnpg_barman_plugin_enabled both true |
| `cnpg_pgvector_enabled` | cnpg_enabled + cnpg_pgvector_enabled both true |
| `cnpg_postgres_image` | `ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie` |
| `cnpg_pgvector_image` | `ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie` |

**Storage & Caching**:

| Variable | Computed When |
| ---------- | --------------- |
| `rustfs_enabled` | rustfs_enabled explicitly true |
| `rustfs_storage_class` | Defaults to `storage_class` or `local-path` when rustfs_enabled |
| `dragonfly_enabled` | dragonfly_enabled explicitly true |
| `dragonfly_backup_enabled` | dragonfly + rustfs + dragonfly_backup_enabled + S3 credentials set |
| `dragonfly_monitoring_enabled` | monitoring_enabled + dragonfly_monitoring_enabled both true |

**Observability**:

| Variable | Computed When |
| ---------- | --------------- |
| `loki_deployment_mode` | `SimpleScalable` when rustfs_enabled, else `SingleBinary` |
| `loki_monitoring_enabled` | monitoring_enabled + loki_monitoring_enabled both true |
| `keycloak_monitoring_enabled` | monitoring_enabled + keycloak_monitoring_enabled both true |
| `keycloak_tracing_enabled` | tracing_enabled + keycloak_tracing_enabled both true |
| `rustfs_monitoring_enabled` | monitoring_enabled + rustfs_monitoring_enabled both true |
| `keycloak_backup_enabled` | rustfs_enabled + keycloak S3 credentials set |

**AI & LLM Platform**:

| Variable | Computed When |
| ---------- | --------------- |
| `litellm_enabled` | litellm_enabled explicitly true |
| `litellm_hostname` | `{litellm_subdomain}.{cloudflare_domain}` |
| `litellm_oidc_enabled` | keycloak_enabled + litellm_oidc_enabled + client_secret set |
| `litellm_backup_enabled` | rustfs_enabled + litellm S3 credentials set |
| `litellm_monitoring_enabled` | monitoring_enabled + litellm_monitoring_enabled both true |
| `litellm_tracing_enabled` | tracing_enabled + litellm_tracing_enabled both true |
| `litellm_langfuse_enabled` | litellm_langfuse_enabled + public_key + secret_key set |
| `langfuse_enabled` | langfuse_enabled explicitly true |
| `langfuse_sso_enabled` | keycloak_enabled + langfuse_sso_enabled + client_secret set |
| `obot_enabled` | obot_enabled explicitly true |
| `obot_keycloak_enabled` | keycloak_enabled + obot_keycloak_enabled + client_secret set |

**REF:** Complete variable reference in `docs/ai-context/configuration-variables.md`

## Template Structure

### Directory Layout

```
templates/
├── config/
│   ├── kubernetes/           # K8s manifests
│   │   ├── apps/
│   │   │   ├── kube-system/
│   │   │   │   ├── cilium/
│   │   │   │   │   ├── ks.yaml.j2
│   │   │   │   │   └── app/
│   │   │   │   │       ├── kustomization.yaml.j2
│   │   │   │   │       ├── helmrelease.yaml.j2
│   │   │   │   │       └── ocirepository.yaml.j2
│   │   │   │   └── ...
│   │   │   └── ...
│   │   └── flux/
│   ├── talos/                # Talos configs
│   │   ├── talconfig.yaml.j2
│   │   └── patches/
│   │       ├── global/
│   │       ├── controller/
│   │       └── ...
│   └── bootstrap/            # Bootstrap resources
└── scripts/
    └── plugin.py             # Custom functions
```

### Naming Conventions

- Template files: `*.yaml.j2`, `*.json.j2`
- Output removes `.j2`: `helmrelease.yaml.j2` → `helmrelease.yaml`
- Some files don't need templating: copied as-is

### Application Template Pattern

Standard structure for Flux applications:

```
<app-name>/
├── ks.yaml.j2              # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2
    ├── ocirepository.yaml.j2
    └── secret.sops.yaml.j2  # If secrets needed
```

## CUE Validation

Schemas validate configuration:

```
.taskfiles/template/resources/
├── cluster.schema.cue    # cluster.yaml schema
└── nodes.schema.cue      # nodes.yaml schema
```

Validation runs during `task configure`.

### cluster.schema.cue (excerpt)

```cue
#Cluster: {
    node_cidr: =~"^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+$"
    cluster_api_addr: =~"^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"
    cloudflare_domain: =~"^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$"
    ...
}
```

### nodes.schema.cue (excerpt)

```cue
#Node: {
    name: =~"^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$"
    address: =~"^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"
    controller: bool
    disk: string
    mac_addr: =~"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$"
    schematic_id: =~"^[0-9a-f]{64}$"
    ...
}
```

## Common Patterns

### Conditional Application

```yaml
# kustomization.yaml.j2
resources:
  - ./namespace.yaml
  - ./required-app/ks.yaml
#% if spegel_enabled %#
  - ./spegel/ks.yaml
#% endif %#
```

### Node Iteration with Filter

```yaml
# Only controller nodes
#% for node in nodes if node.controller %#
  - hostname: "#{ node.name }#"
#% endfor %#
```

### Dynamic Secrets

```yaml
# Using plugin functions
apiVersion: v1
kind: Secret
metadata:
  name: tunnel-credentials
stringData:
  credentials.json: |
    {
      "AccountTag": "...",
      "TunnelID": "#{ cloudflare_tunnel_id() }#",
      "TunnelSecret": "#{ cloudflare_tunnel_secret() }#"
    }
```

### Array/List Handling

```yaml
nameservers:
#% for dns in node_dns_servers %#
  - "#{ dns }#"
#% endfor %#
```

## Troubleshooting

### Render Errors

```bash
# Run configure to see errors
task configure

# Common issues:
# - Missing closing delimiter
# - Undefined variable
# - Invalid filter/function
```

### Debugging Variables

```yaml
#| Debug: #{ variable | default('UNDEFINED') }# #|
```

### Template Not Rendering

Check:

1. File has `.j2` extension
2. File is in `templates/config/` tree
3. `makejinja.toml` includes the path

### Validation Failures

```bash
# CUE errors show specific field issues
task configure

# Example output:
# cluster.yaml: field 'node_cidr': invalid value "bad"
```

## Workflow

### Adding a New Template Variable

1. Add to `cluster.yaml`:

   ```yaml
   my_new_var: "value"
   ```

2. Use in templates:

   ```yaml
   config: "#{ my_new_var }#"
   ```

3. (Optional) Add default in `plugin.py`

4. (Optional) Add validation in CUE schema

5. Render:

   ```bash
   task configure
   ```

### Creating New Application

1. Create directory structure
2. Add templates with `.j2` extension
3. Add to namespace `kustomization.yaml.j2`
4. Run `task configure`
5. Commit and push

## Task Commands

| Command | Description |
| --------- | ------------- |
| `task configure` | Render all templates |
| `task template:debug` | Debug template variables |
| `task template:tidy` | Archive template files |
| `task template:reset` | Remove generated files |

---

**Last Updated:** January 13, 2026
**makejinja Version:** Configured in `.mise.toml`
**Template Delimiters:** `#%`/`%#` (blocks), `#{`/`}#` (variables), `#|`/`#|` (comments)
**Data Sources:** `cluster.yaml`, `nodes.yaml`
**Plugin:** `templates/scripts/plugin.py` (2 filters, 8 functions, 60+ computed variables)
