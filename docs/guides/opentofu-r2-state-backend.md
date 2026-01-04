# OpenTofu State Backend with Cloudflare R2 + Worker Locking

> **Implementation Guide** | Based on [cloudflare-r2-terraform-state.md](../research/cloudflare-r2-terraform-state.md)
> **Last Updated:** January 2026
> **Status:** Implemented
> **Approach:** Option B - R2 + Worker-based Locking (Recommended for Teams)

---

## Overview

This guide implements a **free, production-ready** OpenTofu state backend using:

- **Cloudflare R2** — S3-compatible object storage (free tier: 10GB, unlimited egress)
- **tfstate-worker** — Cloudflare Worker providing HTTP backend with state locking
- **SOPS/Age** — Secret encryption (existing project pattern)

```
┌─────────────────────────────────────────────────────────────────┐
│                     ARCHITECTURE                                │
└─────────────────────────────────────────────────────────────────┘

   Developer / CI Pipeline
            │
            │ tofu plan/apply
            ▼
   ┌─────────────────────┐
   │   tfstate-worker    │  ◄── Cloudflare Worker (free tier)
   │   (HTTP Backend)    │      - Basic Auth
   │   - State locking   │      - Optional mTLS
   │   - Lock management │
   └──────────┬──────────┘
              │
              ▼
   ┌──────────────────────────────────┐
   │   Cloudflare R2                  │  ◄── Free: 10GB storage, unlimited egress
   │   matherlynet-tfstate            │
   │   ├── proxmox/                   │
   │   │   └── terraform.tfstate.     │
   │   │   └── terraform.tfstate.lock │
   │   └── other-project/             │
   └──────────────────────────────────┘
```

---

## Project Secrets Architecture

This project uses a **unified secrets architecture** where all credentials are configured in `cluster.yaml` (gitignored) and flow through the template system:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    UNIFIED SECRETS FLOW                                 │
│                    (All from cluster.yaml via `task configure`)         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   cluster.yaml (gitignored) ─────────────────────────────────────────┐  │
│   ├── cloudflare_token ──────────────► kubernetes/*.sops.yaml        │  │
│   ├── tfstate_username ──────────────► infrastructure/secrets.sops   │  │
│   ├── tfstate_password ──────────────► infrastructure/secrets.sops   │  │
│   ├── proxmox_api_token_id ──────────► infrastructure/secrets.sops   │  │
│   └── proxmox_api_token_secret ──────► infrastructure/secrets.sops   │  │
│                                                                         │
│   External Files:                                                       │
│   • age.key ─────────────────────────► SOPS encryption                  │
│   • cloudflare-tunnel.json ──────────► kubernetes/*.sops.yaml          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    RUNTIME USAGE                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   infrastructure/secrets.sops.yaml (generated, encrypted)               │
│            │                                                            │
│            ├───► task infra:init ───► TF_HTTP_USERNAME/PASSWORD         │
│            ├───► task infra:plan                                        │
│            └───► task infra:apply                                       │
│                                                                         │
│   NOTE: `task configure` auto-runs `tofu init` if credentials present  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**All secrets flow through cluster.yaml:**

| Secret | In cluster.yaml | Generated To |
| ------ | --------------- | ------------ |
| `cloudflare_token` | ✅ | kubernetes/*.sops.yaml |
| `tfstate_username` | ✅ | infrastructure/secrets.sops.yaml |
| `tfstate_password` | ✅ | infrastructure/secrets.sops.yaml |
| `proxmox_api_token_id` | ✅ | infrastructure/secrets.sops.yaml |
| `proxmox_api_token_secret` | ✅ | infrastructure/secrets.sops.yaml |

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
| ------ | --------- | --------- |
| **OpenTofu** | 1.11.2+ | Infrastructure as Code |
| **Wrangler** | 4.x | Cloudflare Workers CLI |
| **Node.js** | 18+ | Required for Wrangler |
| **SOPS** | 3.x | Secret encryption |
| **Age** | 1.x | Encryption key management |

```bash
# Verify installations
tofu version      # OpenTofu v1.11.2+
npx wrangler -v   # wrangler 4.x
sops --version    # sops 3.x
age --version     # age v1.x
```

### Required Accounts

- **Cloudflare Account** with R2 enabled (free)
- **Custom Domain** (optional but recommended for Worker URL)

### Required Information

Gather these before starting:

| Item | Where to Find | Example |
| ------ | -------------- | --------- |
| **Cloudflare Account ID** | Dashboard → Overview → Account ID | `a1b2c3d4e5f6...` |
| **R2 Bucket Name** | You choose | `matherlynet-tfstate` |
| **Worker Subdomain** | You choose | `tfstate.matherlynet.io` |
| **Auth Username** | You choose | `terraform` |
| **Auth Password** | Generate securely | `<strong-random-password>` |

---

## Phase 1: Cloudflare R2 Setup

### Step 1.1: Create R2 Bucket

```bash
# Login to Cloudflare (opens browser)
npx wrangler login

# Create the state bucket
npx wrangler r2 bucket create matherlynet-tfstate

# Verify creation
npx wrangler r2 bucket list
```

**Expected Output:**
```
Creating bucket 'matherlynet-tfstate'...
Created bucket 'matherlynet-tfstate'.
```

### Step 1.2: Create R2 API Token (for direct access if needed)

1. Go to **Cloudflare Dashboard** → **R2** → **Manage R2 API Tokens**
2. Click **Create API Token**
3. Configure:
   - **Token name:** `matherlynet-tfstate-rw`
   - **Permissions:** Object Read & Write
   - **Bucket scope:** Specific bucket → `matherlynet-tfstate`
   - **TTL:** Optional expiration for security
4. Click **Create API Token**
5. **IMMEDIATELY** copy the Access Key ID and Secret Access Key

> **Warning:** The Secret Access Key is shown only once. Store it immediately.

### Step 1.3: Configure Credentials in cluster.yaml

> **Architecture Note:** All infrastructure secrets are now configured in `cluster.yaml` (gitignored), following the same pattern as other secrets in this project. The `task configure` command generates the encrypted `infrastructure/secrets.sops.yaml` automatically.

**Prerequisites:**
1. Ensure `age.key` exists (created by `task init`)

```bash
# Initialize config files if not done (creates age.key, cluster.yaml, nodes.yaml)
task init
```

Add the following to your `cluster.yaml`:

```yaml
# =============================================================================
# INFRASTRUCTURE CREDENTIALS (OpenTofu R2 State Backend)
# =============================================================================

# -- Cloudflare Account ID
#    Dashboard → Overview → Account ID (right sidebar)
cf_account_id: "your-cloudflare-account-id"

# -- tfstate-worker Basic Auth credentials
#    Must match secrets configured in your tfstate-worker deployment
tfstate_username: "terraform"  # Default
tfstate_password: "your-strong-random-password"  # Generate with: openssl rand -base64 32

# -- Proxmox API token (required when infrastructure_enabled)
proxmox_api_token_id: "root@pam!terraform"
proxmox_api_token_secret: "your-api-token-secret"
```

Then run `task configure` to generate encrypted secrets and auto-initialize the backend:

```bash
# Generates infrastructure/secrets.sops.yaml and runs tofu init
task configure
```

> **Tip:** Generate a secure password: `openssl rand -base64 32`
>
> **Note:** Proxmox API token credentials are only required when `infrastructure_enabled` (when `proxmox_api_url` and `proxmox_node` are set in `cluster.yaml`).

---

## Phase 2: Deploy tfstate-worker

### Step 2.1: Clone Your Repository

```bash
# Clone your tfstate-worker repository (created from template)
git clone https://github.com/MatherlyNet/matherlynet-tfstate
cd matherlynet-tfstate
```

> **Note:** This repository was created from the [cmackenzie1/tfstate-worker](https://github.com/cmackenzie1/tfstate-worker) template.

### Step 2.2: Configure wrangler.toml

Edit `wrangler.toml`:

```toml
name = "tfstate-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

# Your Cloudflare Account ID
account_id = "YOUR_ACCOUNT_ID"

# R2 bucket binding
[[r2_buckets]]
binding = "TFSTATE_BUCKET"
bucket_name = "matherlynet-tfstate"

# Custom domain (recommended)
# routes = [
#   { pattern = "tfstate.matherly.net", custom_domain = true }
# ]

# Or use workers.dev subdomain (simpler for testing)
# The worker will be available at: tfstate-worker.<your-subdomain>.workers.dev
```

### Step 2.3: Set Worker Secrets

```bash
# Set authentication credentials as Worker secrets
npx wrangler secret put TFSTATE_USERNAME
# Enter: terraform

npx wrangler secret put TFSTATE_PASSWORD
# Enter: <your-strong-random-password>
```

### Step 2.4: Deploy Worker

```bash
# Deploy to Cloudflare
npx wrangler deploy

# Note the deployment URL
# Example: https://tfstate-worker.your-subdomain.workers.dev
```

**Expected Output:**
```
Uploaded tfstate-worker (1.23 sec)
Published tfstate-worker (0.45 sec)
  https://tfstate-worker.your-subdomain.workers.dev
```

### Step 2.5: (Optional) Configure Custom Domain

For production, use a custom domain instead of `workers.dev`:

1. Go to **Cloudflare Dashboard** → **Workers & Pages** → **tfstate-worker**
2. Click **Settings** → **Triggers** → **Custom Domains**
3. Add: `tfstate.matherlynet.io`
4. Update `wrangler.toml` with the routes configuration

---

## Phase 3: OpenTofu Backend Configuration

### Step 3.1: Create Backend Configuration

The backend is defined in `templates/config/infrastructure/tofu/backend.tf.j2` and generated to `infrastructure/tofu/backend.tf` by `task configure`:

```hcl
# Generated: infrastructure/tofu/backend.tf
terraform {
  backend "http" {
    # State endpoint
    address = "https://tfstate.matherlynet.io/tfstate/states/proxmox"

    # Lock endpoints
    lock_address   = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    lock_method    = "LOCK"
    unlock_address = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    unlock_method  = "UNLOCK"

    # Authentication (use environment variables in practice)
    # username = "terraform"  # Set via TF_HTTP_USERNAME
    # password = "..."        # Set via TF_HTTP_PASSWORD
  }
}
```

### Step 3.2: (Optional) Add State Encryption

For additional security, add client-side encryption with OpenTofu 1.7+:

```hcl
# infrastructure/tofu/encryption.tf
terraform {
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method = method.aes_gcm.default
    }

    plan {
      method = method.aes_gcm.default
    }
  }
}

variable "state_encryption_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for state file encryption"
}
```

### Step 3.3: Create Task Integration

Add to `.taskfiles/infrastructure/Taskfile.yaml`:

```yaml
# .taskfiles/infrastructure/Taskfile.yaml
version: "3"

vars:
  TOFU_DIR: "{{.ROOT_DIR}}/infrastructure/tofu"
  SECRETS_FILE: "{{.ROOT_DIR}}/infrastructure/secrets.sops.yaml"

tasks:
  tofu:init:
    desc: Initialize OpenTofu with R2 backend
    dir: "{{.TOFU_DIR}}"
    cmds:
      - |
        export TF_HTTP_USERNAME=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_username')
        export TF_HTTP_PASSWORD=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_password')
        tofu init
    preconditions:
      - test -f {{.SECRETS_FILE}}

  tofu:plan:
    desc: Run OpenTofu plan
    dir: "{{.TOFU_DIR}}"
    cmds:
      - |
        export TF_HTTP_USERNAME=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_username')
        export TF_HTTP_PASSWORD=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_password')
        tofu plan -out=tfplan
    preconditions:
      - test -f {{.SECRETS_FILE}}

  tofu:apply:
    desc: Apply OpenTofu plan
    dir: "{{.TOFU_DIR}}"
    cmds:
      - |
        export TF_HTTP_USERNAME=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_username')
        export TF_HTTP_PASSWORD=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_password')
        tofu apply tfplan
    preconditions:
      - test -f {{.TOFU_DIR}}/tfplan

  tofu:destroy:
    desc: Destroy OpenTofu-managed resources
    dir: "{{.TOFU_DIR}}"
    prompt: "This will destroy all managed resources. Continue?"
    cmds:
      - |
        export TF_HTTP_USERNAME=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_username')
        export TF_HTTP_PASSWORD=$(sops -d {{.SECRETS_FILE}} | yq -r '.tfstate_password')
        tofu destroy
```

---

## Phase 4: Verification

### Step 4.1: Test Worker Health

```bash
# Test the worker endpoint (should return 401 without auth)
curl -s -o /dev/null -w "%{http_code}" https://tfstate.matherlynet.io/health
# Expected: 200 or 401

# Test with authentication
curl -u terraform:YOUR_PASSWORD https://tfstate.matherlynet.io/health
# Expected: 200
```

### Step 4.2: Initialize OpenTofu

```bash
# Navigate to infrastructure directory
cd infrastructure/tofu

# Set credentials
export TF_HTTP_USERNAME=terraform
export TF_HTTP_PASSWORD="$(sops -d ../secrets.sops.yaml | yq '.tfstate_password')"

# Initialize backend
tofu init
```

**Expected Output:**
```
Initializing the backend...

Successfully configured the backend "http"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

### Step 4.3: Verify State Locking

Open two terminals and try to run `tofu plan` simultaneously:

**Terminal 1:**
```bash
tofu plan  # This should acquire lock
```

**Terminal 2:**
```bash
tofu plan  # This should wait or show lock error
```

**Expected behavior:** Second command waits for lock or shows:
```
Error: Error acquiring the state lock
Lock Info:
  ID:        <lock-id>
  Path:      proxmox/terraform.tfstate
  Operation: OperationTypePlan
```

### Step 4.4: Verify State Storage in R2

```bash
# Via Cloudflare Dashboard: R2 → matherlynet-tfstate → Objects

# Or via S3 API (requires R2 API token configured as AWS credentials)
aws s3 ls s3://matherlynet-tfstate/ \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

> **Note:** Wrangler does not have a native `r2 object list` command. Use the Dashboard or S3 API.

---

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/infrastructure.yaml
name: Infrastructure

on:
  push:
    branches: [main]
    paths:
      - 'infrastructure/**'
  pull_request:
    paths:
      - 'infrastructure/**'

env:
  TOFU_VERSION: "1.11.2"
  TF_HTTP_USERNAME: ${{ secrets.TFSTATE_USERNAME }}
  TF_HTTP_PASSWORD: ${{ secrets.TFSTATE_PASSWORD }}

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}

      - name: Setup SOPS
        uses: mdgreenwald/mozilla-sops-action@v1.6.0

      - name: Import Age Key
        run: |
          echo "${{ secrets.AGE_SECRET_KEY }}" > /tmp/age.key
          echo "SOPS_AGE_KEY_FILE=/tmp/age.key" >> $GITHUB_ENV

      - name: Tofu Init
        working-directory: infrastructure/tofu
        run: tofu init

      - name: Tofu Plan
        working-directory: infrastructure/tofu
        run: tofu plan -out=tfplan

      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: infrastructure/tofu/tfplan
          retention-days: 5

  apply:
    needs: plan
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: infrastructure/tofu

      - name: Tofu Apply
        working-directory: infrastructure/tofu
        run: tofu apply -auto-approve tfplan
```

### Required GitHub Secrets

| Secret | Description |
| -------- | ------------- |
| `TFSTATE_USERNAME` | Worker auth username (`terraform`) |
| `TFSTATE_PASSWORD` | Worker auth password |
| `AGE_SECRET_KEY` | Age private key for SOPS decryption |
| `PROXMOX_API_TOKEN` | Proxmox API token (for provider) |

---

## Troubleshooting

### Common Issues

#### 1. "Error acquiring state lock"

**Cause:** Previous operation crashed without releasing lock

**Solution:**
```bash
# Force unlock (use with caution)
tofu force-unlock <LOCK_ID>

# Or manually delete lock file in R2 (bucket/object format)
npx wrangler r2 object delete matherlynet-tfstate/proxmox/terraform.tfstate.lock
```

#### 2. "401 Unauthorized"

**Cause:** Incorrect credentials

**Solution:**
```bash
# Verify credentials are set
echo $TF_HTTP_USERNAME
echo $TF_HTTP_PASSWORD | head -c 5  # Show first 5 chars only

# Test directly
curl -u $TF_HTTP_USERNAME:$TF_HTTP_PASSWORD \
  https://tfstate.matherlynet.io/health
```

#### 3. "Checksum validation failed" (OpenTofu 1.11+)

**Cause:** Known R2 compatibility issue with checksums

**Solution:**
```bash
# Add to environment before running tofu commands
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

#### 4. "Backend configuration changed"

**Cause:** Backend URL or settings modified

**Solution:**
```bash
# Reinitialize with reconfigure
tofu init -reconfigure

# Or migrate state
tofu init -migrate-state
```

#### 5. Worker not responding

**Check Worker logs:**
```bash
npx wrangler tail tfstate-worker
```

**Verify deployment:**
```bash
npx wrangler deployments list
```

### State Recovery

> **Critical:** R2 has NO object versioning. Implement backups!

**Manual Backup Strategy:**
```bash
# Download state file locally (bucket/object format)
npx wrangler r2 object get matherlynet-tfstate/proxmox/terraform.tfstate \
  --file backup-$(date +%Y%m%d).tfstate

# Upload to backup bucket
npx wrangler r2 object put matherlynet-tfstate-backup/backup/proxmox/$(date +%Y%m%d).tfstate \
  --file backup-$(date +%Y%m%d).tfstate
```

**Automated Backup (Cron Worker):**

Consider deploying a scheduled Worker to copy state files daily.

---

## Security Hardening

### 1. Enable mTLS (Recommended for Production)

1. Go to **Cloudflare Dashboard** → **SSL/TLS** → **Client Certificates**
2. Create a client certificate
3. Configure Worker to require client certificates
4. Distribute certificates to authorized clients

### 2. IP Allowlisting

Configure Worker to only accept requests from known IPs:

```typescript
// Add to tfstate-worker src/index.ts
const ALLOWED_IPS = ['1.2.3.4', '5.6.7.8'];

if (!ALLOWED_IPS.includes(request.headers.get('CF-Connecting-IP'))) {
  return new Response('Forbidden', { status: 403 });
}
```

### 3. Rotate Credentials Regularly

```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update Worker secret
npx wrangler secret put TFSTATE_PASSWORD
# Enter new password

# Update SOPS file
sops infrastructure/secrets.sops.yaml
# Update tfstate_password value
```

---

## Cost Analysis

| Component | Free Tier | Monthly Cost |
| ----------- | ----------- | -------------- |
| **R2 Storage** | 10 GB | $0 (state files ~KB) |
| **R2 Class A Ops** | 1M/month | $0 (~100 writes/day max) |
| **R2 Class B Ops** | 10M/month | $0 (~1000 reads/day max) |
| **R2 Egress** | Unlimited | $0 |
| **Worker Requests** | 100K/day | $0 |
| **Worker Duration** | 10ms CPU/req | $0 |
| **Total** | — | **$0** |

---

## Next Steps

1. **Add Proxmox Provider** — Configure bpg/proxmox provider for VM management
2. **Create VM Modules** — Define Talos node configurations
3. **Integrate with Bootstrap** — Connect to `task bootstrap:talos` workflow
4. **Set up CI/CD** — Automate plan/apply on merge to main

---

## References

- [Research Document](../research/cloudflare-r2-terraform-state.md) — Full analysis and alternatives
- [MatherlyNet tfstate Repository](https://github.com/MatherlyNet/matherlynet-tfstate) — Our tfstate-worker deployment
- [tfstate-worker Upstream](https://github.com/cmackenzie1/tfstate-worker) — Original template
- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)
- [OpenTofu HTTP Backend](https://opentofu.org/docs/language/settings/backends/http/)
- [OpenTofu State Encryption](https://opentofu.org/docs/language/state/encryption/)
