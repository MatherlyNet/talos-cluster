# Infrastructure as Code (OpenTofu)

This directory contains OpenTofu configurations for managing infrastructure, starting with the state backend on Cloudflare R2.

## Architecture

```
Developer / CI Pipeline
         │
         │ tofu plan/apply
         ▼
┌─────────────────────┐
│   tfstate-worker    │  ◄── Cloudflare Worker (free tier)
│   (HTTP Backend)    │      - Basic Auth
│   - State locking   │      - Concurrent access protection
└──────────┬──────────┘
           │
           ▼
┌──────────────────────────────┐
│   Cloudflare R2              │  ◄── Free: 10GB, unlimited egress
│   matherlynet-tfstate        │
│   └── proxmox/               │
│       └── terraform.tfstate  │
└──────────────────────────────┘
```

## Prerequisites

### 1. External Setup (One-Time)

Before using these configurations, complete the following in Cloudflare:

1. **Create R2 Bucket**

   ```bash
   npx wrangler login
   npx wrangler r2 bucket create matherlynet-tfstate
   ```

2. **Deploy tfstate-worker**
   - Clone: https://github.com/MatherlyNet/matherlynet-tfstate
   - Configure `wrangler.toml` with your account ID
   - Set secrets: `npx wrangler secret put TFSTATE_USERNAME` / `TFSTATE_PASSWORD`
   - Deploy: `npx wrangler deploy`
   - (Optional) Configure custom domain: `tfstate.matherly.net`

3. **Regenerate SOPS config** (if not done already)

   ```bash
   task configure  # This regenerates .sops.yaml with infrastructure rules
   ```

### 2. Local Setup

```bash
# Install tools via mise
mise install

# Initialize config files (creates cluster.yaml, nodes.yaml)
task init

# Edit cluster.yaml - add infrastructure settings:
#   proxmox_api_url, proxmox_node - Enable infrastructure provisioning
#   tfstate_username, tfstate_password - R2 backend auth
#   proxmox_api_token_id, proxmox_api_token_secret - Proxmox API auth

# Edit nodes.yaml - add VM specs per node (vm_cores, vm_memory, etc.)

# Generate all configs and auto-initialize backend (if credentials configured)
task configure
```

## Available Tasks

| Command | Description |
| --------- | ------------- |
| `task infra:init` | Initialize OpenTofu with R2 backend |
| `task infra:plan` | Create execution plan |
| `task infra:apply` | Apply saved plan |
| `task infra:apply-auto` | Apply changes directly (with confirmation) |
| `task infra:destroy` | Destroy all managed resources |
| `task infra:output` | Show outputs |
| `task infra:state-list` | List resources in state |
| `task infra:force-unlock LOCK_ID=xxx` | Force unlock state |
| `task infra:validate` | Validate configuration |
| `task infra:fmt` | Format configuration |
| `task infra:fmt-check` | Check formatting |
| `task infra:secrets-edit` | Edit encrypted secrets (for rotation) |

## File Structure

All files in `infrastructure/` are **generated** by `task configure` from templates.

```
infrastructure/                      # GENERATED directory
├── README.md                        # This documentation
├── secrets.sops.yaml                # Encrypted credentials
└── tofu/
    ├── backend.tf                   # HTTP backend configuration
    ├── versions.tf                  # OpenTofu/provider versions
    ├── providers.tf                 # Provider configurations
    ├── variables.tf                 # Input variables
    ├── main.tf                      # Resources
    └── terraform.tfvars             # VM and node configuration

templates/config/infrastructure/     # Source templates
├── README.md                        # This file (copied as-is)
├── secrets.sops.yaml.j2             # Secrets template
└── tofu/
    ├── backend.tf.j2                # Backend template
    ├── versions.tf.j2               # Versions template
    ├── providers.tf.j2              # Providers template (conditional)
    ├── variables.tf.j2              # Variables template
    ├── main.tf.j2                   # Main config template (conditional)
    └── terraform.tfvars.j2          # tfvars template
```

## Template Generation

All files in `infrastructure/` are **auto-generated** from templates using makejinja. This follows the same pattern as `kubernetes/`, `talos/`, and `bootstrap/` directories.

**Source files:**

- `cluster.yaml` - Proxmox connection, VM defaults, network configuration
- `nodes.yaml` - Per-node specifications (cores, memory, disk, startup order)

**Conditional templates:** Some templates (providers.tf.j2, main.tf.j2) generate different content based on `infrastructure_enabled` (when `proxmox_api_url` and `proxmox_node` are set in cluster.yaml).

**Generation:**

```bash
task configure  # Regenerates all templates and encrypts secrets
```

**Important:** Never edit files in `infrastructure/` directly. Changes will be overwritten. Instead:

1. Edit `cluster.yaml` for Proxmox settings, VM defaults, and credentials
2. Edit `nodes.yaml` for per-node resource overrides
3. Edit templates in `templates/config/infrastructure/` for structural changes
4. Run `task configure` to regenerate (auto-initializes backend if credentials present)
5. Use `task infra:secrets-edit` only for credential rotation

### Enabling Infrastructure Provisioning

To enable Proxmox VM provisioning, add the following to `cluster.yaml`:

```yaml
# Required for infrastructure provisioning
proxmox_api_url: "https://pve.example.com:8006/api2/json"
proxmox_node: "pve"

# Optional - defaults shown
proxmox_iso_storage: "local"
proxmox_disk_storage: "local-lvm"

# Optional - override VM defaults
proxmox_vm_defaults:
  cores: 4
  sockets: 1
  memory: 8192
  disk_size: 128
```

Per-node overrides in `nodes.yaml`:

```yaml
nodes:
  - name: k8s-0
    vm_cores: 8          # Override default cores
    vm_memory: 16384     # Override default memory
    vm_startup_order: 1  # Boot order (lower = earlier)
    vm_startup_delay: 30 # Seconds to wait before next VM
```

### Proxmox API Token Permissions (CRITICAL)

The bpg/proxmox provider requires specific privileges. The `download_file` resource (for ISO downloads) requires `Sys.Audit` and `Sys.Modify` on the root path (`/`).

**Create a dedicated role on Proxmox:**

```bash
# SSH to Proxmox server
pveum role add TerraformProv -privs "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,SDN.Use,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.GuestAgent.Audit,VM.Migrate,VM.PowerMgmt"
```

**Option A: Use existing root token with role assignment**

```bash
# Assign role to root token on root path
pveum aclmod / -token 'root@pam!k8s-gitops' -role TerraformProv
```

**Option B: Create dedicated user and token**

```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role TerraformProv
pveum user token add terraform@pve terraform-token --privsep=0
# Use terraform@pve!terraform-token as proxmox_api_token_id
```

**Critical privileges for ISO downloads:**

| Privilege | Purpose |
| ----------- | --------- |
| `Datastore.AllocateTemplate` | Upload ISOs to storage |
| `Sys.Audit` | Query system metadata |
| `Sys.Modify` | Required by query-url-metadata API |

> **Reference:** [bpg/proxmox download_file docs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_download_file)

**Proxmox VE 9+ QEMU Guest Agent privileges:**

| Privilege | Purpose |
| ----------- | --------- |
| `VM.GuestAgent.Audit` | Query VM network interfaces via guest agent (new in PVE 9) |

> **Note:** If your Talos schematic includes `siderolabs/qemu-guest-agent`, this privilege is required for the bpg/proxmox provider to query network interfaces. Without it, you'll see "Permission check failed" warnings during `tofu plan/apply`.

## Secrets Management

Infrastructure secrets are **auto-generated** from `cluster.yaml` during `task configure`, following the same pattern as other Kubernetes secrets.

**Source:** `cluster.yaml` (gitignored)
**Template:** `templates/config/infrastructure/secrets.sops.yaml.j2`
**Generated:** `infrastructure/secrets.sops.yaml` (encrypted)

The template pulls credentials from `cluster.yaml` and conditionally includes Proxmox credentials based on `infrastructure_enabled`.

```yaml
# In cluster.yaml (add these values):
cf_account_id: "your-cloudflare-account-id"
tfstate_username: "terraform"            # Default
tfstate_password: "your-strong-password" # Required for R2 backend
proxmox_api_token_id: "root@pam!terraform"     # Required when infrastructure_enabled
proxmox_api_token_secret: "your-api-secret"    # Required when infrastructure_enabled
```

**Workflow:**

1. Add credentials to `cluster.yaml`
2. Run `task configure` - Generates and encrypts `infrastructure/secrets.sops.yaml`, auto-runs `tofu init`
3. Use `task infra:secrets-edit` only for credential rotation (not initial setup)

**Important:** The `age.key` file in the repo root is gitignored. Never commit it.

## Troubleshooting

### "Error acquiring state lock"

```bash
# Get the lock ID from the error message, then:
task infra:force-unlock LOCK_ID=<lock-id>
```

### "401 Unauthorized"

```bash
# Verify credentials in cluster.yaml match tfstate-worker secrets
# Then regenerate:
task configure
```

### "Checksum validation failed"

The Taskfile sets `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` automatically. If running tofu manually:

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
tofu init
```

### Backend configuration changed

```bash
task infra:init -- -reconfigure
# or for state migration:
task infra:init -- -migrate-state
```

### "403 Permission check failed" on ISO download

The bpg/proxmox provider's `download_file` resource requires `Sys.Audit` and `Sys.Modify` privileges on the root path (`/`):

```bash
# On Proxmox server - add privileges to your token
pveum aclmod / -token 'root@pam!k8s-gitops' -role TerraformProv
# Or use PVEDatastoreAdmin role if TerraformProv doesn't exist:
pveum aclmod / -token 'root@pam!k8s-gitops' -role PVEDatastoreAdmin
```

See [Proxmox API Token Permissions](#proxmox-api-token-permissions-critical) for creating the role.

## Next Steps

1. **Configure cluster.yaml** - Add `proxmox_api_url`, `proxmox_node`, and all credentials
2. **Run task configure** - Generates secrets, auto-runs `tofu init` if credentials present
3. **Verify Backend** - Run `task infra:plan` to confirm connectivity
4. **Create VM Modules** - Define Talos node configurations in `templates/config/infrastructure/tofu/modules/`
5. **Integrate with Bootstrap** - Connect to `task bootstrap:talos` workflow

## References

- [Implementation Guide](../../../docs/guides/opentofu-r2-state-backend.md)
- [Research Document](../../../docs/research/cloudflare-r2-terraform-state.md)
- [tfstate-worker](https://github.com/MatherlyNet/matherlynet-tfstate)
- [OpenTofu HTTP Backend](https://opentofu.org/docs/language/settings/backends/http/)
