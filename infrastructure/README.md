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

# Create and configure secrets
task infra:secrets-create
task infra:secrets-edit
# Update: tfstate_username, tfstate_password (and optionally proxmox creds)

# Initialize backend
task infra:init
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
| `task infra:secrets-edit` | Edit encrypted secrets |
| `task infra:secrets-create` | Create secrets file from template |

## File Structure

```
infrastructure/
├── README.md              # This file
├── secrets.sops.yaml      # Encrypted credentials (committed)
├── .gitignore             # Ignore patterns
└── tofu/
    ├── backend.tf         # HTTP backend configuration (R2 + Worker)
    ├── versions.tf        # OpenTofu and provider versions
    ├── providers.tf       # Provider configurations
    ├── variables.tf       # Input variables
    ├── main.tf            # Main configuration / resources
    └── .gitignore         # Tofu-specific ignores
```

## Secrets Management

Secrets are stored encrypted in `secrets.sops.yaml` using Age encryption:

```yaml
# After decryption, contains:
cf_account_id: "..."
tfstate_username: "terraform"
tfstate_password: "..."
# proxmox_api_url: "..."       # Optional
# proxmox_api_token_id: "..."  # Optional
# proxmox_api_token_secret: "..." # Optional
```

**Important:** The `age.key` file in the repo root is gitignored. Never commit it.

## Troubleshooting

### "Error acquiring state lock"
```bash
# Get the lock ID from the error message, then:
task infra:force-unlock LOCK_ID=<lock-id>
```

### "401 Unauthorized"
```bash
# Verify credentials are correct
task infra:secrets-edit
# Check the tfstate_username and tfstate_password values
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

## Next Steps

1. **Verify Backend** - Run `task infra:init` and `task infra:plan` to confirm connectivity
2. **Add Proxmox Provider** - Uncomment provider in `providers.tf`, add credentials to secrets
3. **Create VM Modules** - Define Talos node configurations in `tofu/modules/`
4. **Integrate with Bootstrap** - Connect to `task bootstrap:talos` workflow

## References

- [Implementation Guide](../docs/guides/opentofu-r2-state-backend.md)
- [Research Document](../docs/research/cloudflare-r2-terraform-state.md)
- [tfstate-worker](https://github.com/MatherlyNet/matherlynet-tfstate)
- [OpenTofu HTTP Backend](https://opentofu.org/docs/language/settings/backends/http/)
