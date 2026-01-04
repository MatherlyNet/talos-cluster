# Infrastructure & OpenTofu Architecture

> Deep-dive documentation for AI assistants working with infrastructure as code in this project.

## Overview

This project uses OpenTofu v1.11+ for infrastructure as code, with Cloudflare R2 providing state storage via an HTTP backend (tfstate-worker). The infrastructure layer manages resources outside Kubernetes, starting with Proxmox VM automation.

## Architecture

### State Backend

```
┌─────────────────────────────────────────────────────────────────┐
│                     State Management Flow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Developer Workstation                                          │
│  ┌──────────────────┐                                           │
│  │  task infra:*    │                                           │
│  │  ┌────────────┐  │                                           │
│  │  │  OpenTofu  │  │                                           │
│  │  │  v1.11+    │  │                                           │
│  │  └─────┬──────┘  │                                           │
│  └────────┼─────────┘                                           │
│           │ HTTP (Basic Auth)                                   │
│           ▼                                                      │
│  ┌──────────────────┐                                           │
│  │  tfstate-worker  │  Cloudflare Worker                        │
│  │  ┌────────────┐  │  - Request validation                     │
│  │  │   Lock     │  │  - State locking (KV)                     │
│  │  │  Manager   │  │  - Concurrent access protection           │
│  │  └─────┬──────┘  │                                           │
│  └────────┼─────────┘                                           │
│           │ S3 API                                              │
│           ▼                                                      │
│  ┌──────────────────┐                                           │
│  │  Cloudflare R2   │  Object Storage                          │
│  │  ┌────────────┐  │  - 10GB free tier                         │
│  │  │ tfstate/   │  │  - Unlimited egress                       │
│  │  │ proxmox/   │  │  - S3-compatible API                      │
│  │  │ *.tfstate  │  │                                           │
│  │  └────────────┘  │                                           │
│  └──────────────────┘                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why HTTP Backend (Not S3)?

1. **State Locking**: R2 doesn't support DynamoDB-style locking; the worker provides it
2. **Authentication**: Simpler Basic Auth vs S3 signing
3. **Flexibility**: Custom logic for encryption, validation, logging
4. **Cost**: Worker + R2 both on Cloudflare free tier

## Directory Structure

All infrastructure files are **generated** by `task configure` from templates:

```
templates/config/infrastructure/          # SOURCE templates
├── README.md                             # Documentation (copied as-is)
├── secrets.sops.yaml.j2                  # Secrets template (conditional)
└── tofu/
    ├── backend.tf.j2                     # HTTP backend config
    ├── versions.tf.j2                    # OpenTofu/provider versions
    ├── providers.tf.j2                   # Provider configurations (conditional)
    ├── variables.tf.j2                   # Input variable definitions
    ├── main.tf.j2                        # Resource definitions (conditional)
    └── terraform.tfvars.j2               # VM/node configuration

infrastructure/                           # GENERATED directory
├── README.md                             # Copied from templates
├── secrets.sops.yaml                     # Encrypted credentials
└── tofu/
    ├── backend.tf                        # HTTP backend config
    ├── versions.tf                       # OpenTofu/provider versions
    ├── providers.tf                      # Provider configurations
    ├── variables.tf                      # Input variable definitions
    ├── main.tf                           # Resource definitions
    ├── terraform.tfvars                  # VM/node configuration
    ├── tfplan                            # Generated plan (gitignored)
    └── .terraform/                       # Provider cache (gitignored)
```

**Important:** Never edit files in `infrastructure/` directly. Edit templates and run `task configure`.

## Template Generation

The `terraform.tfvars` file is **auto-generated** by makejinja from:
- `cluster.yaml` - Proxmox connection settings, VM defaults, network configuration
- `nodes.yaml` - Per-node specifications (cores, memory, disk, startup order)

### Enabling Infrastructure Provisioning

Infrastructure templating is conditional. To enable, add to `cluster.yaml`:

```yaml
proxmox_api_url: "https://pve.example.com:8006/api2/json"
proxmox_node: "pve"
```

When both are present, `task configure` generates `infrastructure/tofu/terraform.tfvars`.

### Template Variables

**From cluster.yaml:**
- `proxmox_api_url`, `proxmox_node` - Required for enabling
- `proxmox_iso_storage` (default: "local")
- `proxmox_disk_storage` (default: "local-lvm")
- `proxmox_vm_defaults` - Default VM resources
- `proxmox_vm_advanced` - Talos-optimized VM settings

**From nodes.yaml (per-node overrides):**
- `vm_cores`, `vm_sockets`, `vm_memory`, `vm_disk_size`
- `vm_startup_order`, `vm_startup_delay`

### Default VM Settings (Talos-optimized)

Defined in `templates/scripts/plugin.py`:

```python
PROXMOX_VM_DEFAULTS = {
    "cores": 4, "sockets": 1, "memory": 8192, "disk_size": 128
}
PROXMOX_VM_ADVANCED = {
    "bios": "ovmf", "machine": "q35", "cpu_type": "host",
    "scsi_hw": "virtio-scsi-pci", "balloon": 0, "numa": True,
    "qemu_agent": True, "net_queues": 4, "disk_discard": True,
    "disk_ssd": True, "tags": ["kubernetes", "linux", "talos"]
}
```

**Important:** Never edit `terraform.tfvars` directly. Edit `cluster.yaml`/`nodes.yaml` and run `task configure`.

## Configuration Files

### backend.tf

Configures the HTTP backend pointing to tfstate-worker:

```hcl
terraform {
  backend "http" {
    address        = "https://tfstate.matherlynet.io/tfstate/states/proxmox"
    lock_address   = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    lock_method    = "LOCK"
    unlock_address = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    unlock_method  = "UNLOCK"
  }
}
```

Authentication is provided via environment variables:
- `TF_HTTP_USERNAME` - Basic auth username
- `TF_HTTP_PASSWORD` - Basic auth password

### versions.tf

```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
  }
}
```

### providers.tf

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true  # Self-signed cert
  ssh {
    agent = true
  }
}
```

### variables.tf

```hcl
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = ""
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (e.g., user@pam!token-name)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
  default     = ""
}
```

## Secrets Management

### Unified Secrets Architecture

All infrastructure secrets are configured in `cluster.yaml` (gitignored) and flow through the template system:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Unified Secrets Flow                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  cluster.yaml (gitignored) ─────────────────────────────────────│
│  ├── cloudflare_token ──────────► kubernetes/*.sops.yaml        │
│  ├── tfstate_username ──────────► infrastructure/secrets.sops   │
│  ├── tfstate_password ──────────► infrastructure/secrets.sops   │
│  ├── proxmox_api_token_id ──────► infrastructure/secrets.sops   │
│  └── proxmox_api_token_secret ──► infrastructure/secrets.sops   │
│                                                                  │
│  NOTE: `task configure` auto-runs `tofu init` if credentials    │
│        are present in cluster.yaml                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Sources

Infrastructure follows the same templating pattern as kubernetes/talos:

| Source | Purpose | Contents |
| ------ | ------- | -------- |
| `cluster.yaml` | Config + credentials | `proxmox_api_url`, `proxmox_node`, `proxmox_vm_defaults`, `tfstate_*`, `proxmox_api_token_*` |
| `nodes.yaml` | Per-node VM specs | `vm_cores`, `vm_memory`, `vm_disk_size` |

### Secrets Template

The infrastructure secrets file is **auto-generated** from `cluster.yaml`:

**Source:** `cluster.yaml` (gitignored)
**Template:** `templates/config/infrastructure/secrets.sops.yaml.j2`
**Generated:** `infrastructure/secrets.sops.yaml` (encrypted)

The template conditionally includes Proxmox credentials based on `infrastructure_enabled`.

### secrets.sops.yaml Schema

```yaml
# Decrypted view
cf_account_id: "abc123..."           # Cloudflare account
tfstate_username: "terraform"        # HTTP backend auth
tfstate_password: "secret..."        # HTTP backend auth

# Proxmox credentials (sensitive only)
proxmox_api_token_id: "root@pam!terraform"
proxmox_api_token_secret: "xxx-yyy-zzz"

# Optional (for client-side state encryption)
state_encryption_passphrase: "..."
```

> **Note:** Non-sensitive Proxmox config (`proxmox_api_url`, `proxmox_node`, storage settings) goes in `cluster.yaml`, not here.

### SOPS Configuration

Handled by `.sops.yaml` rule:

```yaml
- path_regex: infrastructure/.*\.sops\.ya?ml
  mac_only_encrypted: true
  age: "age1..."
```

## Task Automation

### Available Tasks

| Task | Description |
| ---- | ----------- |
| `task infra:init` | Initialize backend connection |
| `task infra:plan` | Generate execution plan |
| `task infra:apply` | Apply saved plan |
| `task infra:apply-auto` | Apply with auto-approve |
| `task infra:destroy` | Destroy all resources |
| `task infra:output` | Show outputs |
| `task infra:state-list` | List managed resources |
| `task infra:force-unlock` | Release stuck lock |
| `task infra:validate` | Validate configuration |
| `task infra:fmt` | Format HCL files |
| `task infra:fmt-check` | Check formatting |
| `task infra:secrets-edit` | Edit encrypted secrets (rotation) |

### How Tasks Handle Secrets

Each task that needs backend access:

1. Decrypts `secrets.sops.yaml` with SOPS
2. Extracts credentials with yq
3. Exports as `TF_HTTP_*` environment variables
4. Runs OpenTofu command

```yaml
cmds:
  - |
    export TF_HTTP_USERNAME=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_username')
    export TF_HTTP_PASSWORD=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_password')
    tofu init
```

## OpenTofu 1.11+ Considerations

### Checksum Workaround

R2's S3 API implementation requires these environment variables:

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

The Taskfile sets these automatically for all `task infra:*` commands.

### Feature Requirements

OpenTofu 1.11+ is required for:
- Enhanced S3 backend compatibility
- Provider-defined functions
- Improved state encryption options

## Proxmox VM Automation

OpenTofu automates the complete VM lifecycle for Proxmox-based deployments:

1. **Talos ISO Management**: Downloads Talos ISO from Image Factory using schematic ID
2. **SecureBoot Support**: Automatically downloads correct ISO variant (standard or secureboot)
3. **ISO Upload**: Uploads ISO to Proxmox storage
4. **VM Creation**: Creates VMs with specified resources (cores, memory, disk)
5. **Boot Configuration**: Attaches ISO with UEFI/OVMF settings
6. **Node Provisioning**: Boots VMs into Talos maintenance mode

### ISO Download (SecureBoot-Aware)

```hcl
locals {
  # Extract unique schematic+secureboot combinations
  # SecureBoot nodes require different ISO (nocloud-amd64-secureboot.iso)
  schematic_secureboot_map = {
    for combo in distinct([
      for node in var.nodes : {
        schematic_id = node.schematic_id
        secureboot   = node.secureboot
      }
    ]) :
    "${combo.schematic_id}-${combo.secureboot}" => combo
  }
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  for_each = local.schematic_secureboot_map

  content_type = "iso"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  # Talos Image Factory URL format:
  # Standard:   .../nocloud-amd64.iso
  # SecureBoot: .../nocloud-amd64-secureboot.iso
  url = each.value.secureboot ? (
    "https://factory.talos.dev/image/${each.value.schematic_id}/v${var.talos_version}/nocloud-amd64-secureboot.iso"
  ) : (
    "https://factory.talos.dev/image/${each.value.schematic_id}/v${var.talos_version}/nocloud-amd64.iso"
  )
}
```

### VM Resources

```hcl
resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each = local.nodes_map

  name        = each.value.name
  node_name   = var.proxmox_node
  bios        = "ovmf"        # UEFI required for Talos
  machine     = "q35"

  # EFI Disk - pre_enrolled_keys must be false for Talos SecureBoot
  # Talos uses its own signing keys, not Microsoft's
  efi_disk {
    datastore_id      = var.proxmox_disk_storage
    type              = "4m"
    pre_enrolled_keys = false
  }

  # Boot ISO (standard or secureboot variant)
  cdrom {
    file_id = proxmox_virtual_environment_download_file.talos_iso[
      "${each.value.schematic_id}-${each.value.secureboot}"
    ].id
  }

  cpu {
    cores = each.value.vm_cores
    type  = "host"
    numa  = true
  }

  memory {
    dedicated = each.value.vm_memory
    floating  = 0  # No ballooning for Kubernetes
  }

  disk {
    datastore_id = var.proxmox_disk_storage
    size         = each.value.vm_disk_size
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge  = var.vm_advanced.network_bridge
    model   = "virtio"
    queues  = var.vm_advanced.net_queues
    vlan_id = var.node_vlan_tag  # Optional VLAN tagging
    mtu     = each.value.mtu     # Optional per-node MTU
  }
}
```

### Integration with Talos

The infrastructure layer:
1. Downloads correct ISO from Image Factory (standard or secureboot variant)
2. Creates VMs with UEFI/OVMF and proper SecureBoot settings
3. Configures networking (MAC addresses, VLAN, MTU)
4. Boots nodes into Talos maintenance mode
5. Ready for `task bootstrap:talos` to complete installation

### Deployment Paths

| Path | Use Case | Infrastructure Step |
| ---- | -------- | ------------------- |
| Bare Metal | Physical servers | Skip OpenTofu, manual ISO boot |
| Proxmox VM | Virtualized cluster | `task infra:apply` automates everything |

## Troubleshooting

### Common Issues

| Error | Cause | Solution |
| ----- | ----- | -------- |
| `401 Unauthorized` | Bad credentials | Check cluster.yaml, run `task configure` |
| `Error acquiring lock` | Stale lock | `task infra:force-unlock LOCK_ID=xxx` |
| `Checksum mismatch` | R2 API quirk | Env vars set by Taskfile |
| `Backend config changed` | Modified backend.tf | `task infra:init -- -reconfigure` |
| `Missing provider` | Not initialized | `task infra:init` |

### Debug Commands

```bash
# Check OpenTofu version
tofu version

# Validate without backend
tofu validate

# Show state (after init)
task infra:state-list

# View plan details
task infra:plan -- -detailed-exitcode
```

### Logs

The tfstate-worker can be monitored in Cloudflare Dashboard:
- Workers & Pages → tfstate-worker → Logs

## External Dependencies

### tfstate-worker

Repository: `github.com/MatherlyNet/matherlynet-tfstate`

Deployed to Cloudflare Workers with:
- R2 bucket binding
- KV namespace for locks
- Basic auth secrets

### R2 Bucket

Bucket: `matherlynet-tfstate`
- Free tier: 10GB storage, 1M Class A, 10M Class B ops/month
- Unlimited egress
- No versioning (handled by worker if needed)

## Best Practices

1. **Always use tasks**: Never run `tofu` directly; tasks handle auth
2. **Plan before apply**: `task infra:plan` then `task infra:apply`
3. **Commit after changes**: State is remote, but .tf files need version control
4. **Lock awareness**: If interrupted, use `force-unlock` carefully
5. **Secrets rotation**: Update passwords in both worker secrets and SOPS file
