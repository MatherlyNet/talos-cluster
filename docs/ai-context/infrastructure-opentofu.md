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

```
infrastructure/
├── README.md                    # Setup and operations guide
├── secrets.sops.yaml            # Encrypted credentials
├── .gitignore                   # Ignore patterns
└── tofu/
    ├── backend.tf               # HTTP backend config
    ├── versions.tf              # OpenTofu/provider requirements
    ├── providers.tf             # Provider configurations
    ├── variables.tf             # Input variable definitions
    ├── main.tf                  # Resource definitions
    ├── tfplan                   # Generated plan (gitignored)
    ├── .terraform/              # Provider cache (gitignored)
    └── .gitignore               # Tofu-specific ignores
```

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

### Two-Tier Architecture

This project separates secrets by lifecycle:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Secrets Architecture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────┐  ┌─────────────────────────────┐  │
│  │   Template-Time Secrets  │  │    Runtime Secrets          │  │
│  ├─────────────────────────┤  ├─────────────────────────────┤  │
│  │ Source: cluster.yaml     │  │ Source: secrets.sops.yaml   │  │
│  │ User: makejinja          │  │ User: task commands         │  │
│  │ When: task configure     │  │ When: task infra:*          │  │
│  ├─────────────────────────┤  ├─────────────────────────────┤  │
│  │ Examples:                │  │ Examples:                   │  │
│  │ - cloudflare_token       │  │ - tfstate_username          │  │
│  │ - cluster secrets        │  │ - tfstate_password          │  │
│  │                          │  │ - proxmox_api_token         │  │
│  └─────────────────────────┘  └─────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### secrets.sops.yaml Schema

```yaml
# Decrypted view
cf_account_id: "abc123..."           # Cloudflare account
tfstate_username: "terraform"        # HTTP backend auth
tfstate_password: "secret..."        # HTTP backend auth

# Optional (when Proxmox is enabled)
proxmox_api_url: "https://pve.local:8006/api2/json"
proxmox_api_token_id: "root@pam!terraform"
proxmox_api_token_secret: "xxx-yyy-zzz"

# Optional (for client-side state encryption)
state_encryption_passphrase: "..."
```

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
| `task infra:secrets-create` | Create secrets template |
| `task infra:secrets-edit` | Edit encrypted secrets |

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

## Future: Proxmox Integration

### Planned Resources

```hcl
# VM for Talos node
resource "proxmox_virtual_environment_vm" "talos_node" {
  name      = "talos-${var.node_name}"
  node_name = var.proxmox_node

  clone {
    vm_id = var.talos_template_id
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore
    size         = var.disk_gb
  }

  network_device {
    bridge = "vmbr0"
  }
}
```

### Integration with Talos

The infrastructure layer will:
1. Create VMs from Talos image template
2. Configure networking (MAC addresses for DHCP)
3. Wait for nodes to be accessible
4. Trigger Talos bootstrap

## Troubleshooting

### Common Issues

| Error | Cause | Solution |
| ----- | ----- | -------- |
| `401 Unauthorized` | Bad credentials | `task infra:secrets-edit` |
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
