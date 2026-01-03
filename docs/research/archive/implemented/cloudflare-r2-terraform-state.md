# Cloudflare R2 as Terraform/OpenTofu State Backend

> **Research Date:** January 2026
> **Status:** Complete - Validated
> **Validation Date:** January 2026
> **Context:** Follow-up to `proxmox-vm-automation.md` - Revisiting OpenTofu recommendation now that Cloudflare R2 is available for free state storage
> **Previous Recommendation:** Ansible (stateless) due to state management complexity
> **New Recommendation:** OpenTofu + R2 with optional Worker-based locking

---

## Executive Summary

The availability of **free Cloudflare R2 storage** fundamentally changes the cost-benefit analysis for Terraform/OpenTofu state management. This research validates R2 as a viable state backend and provides implementation guidance.

### Key Findings

| Concern | Previous Status | With R2 |
| ------- | --------------- | ------- |
| **Cost** | S3 + DynamoDB = ~$5-20/mo | **Free** (within free tier) |
| **Egress Fees** | AWS charges for retrieval | **$0** (always free) |
| **State Locking** | Requires DynamoDB | Worker-based solution available |
| **Multi-team Access** | Complex S3 IAM setup | Simple API token |
| **CI/CD Integration** | Well-documented | Works with standard S3 backend |

### Updated Recommendation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    REVISED INFRASTRUCTURE AUTOMATION STACK                  │
└─────────────────────────────────────────────────────────────────────────────┘

  PRIMARY: OpenTofu + Cloudflare R2 (S3-compatible backend)
  ─────────────────────────────────────────────────────────
  ✓ Zero cost for storage and egress
  ✓ S3-compatible API (works with existing S3 backend)
  ✓ OpenTofu state encryption for security
  ✓ Optional: Worker-based locking for team environments

  SECONDARY: Ansible (unchanged from previous recommendation)
  ───────────────────────────────────────────────────────────
  ✓ Truly stateless alternative
  ✓ Simple go-task integration
  ✓ No external dependencies
```

---

## Cloudflare R2 Free Tier Analysis

### Free Tier Limits (Permanent, No Expiration)

| Resource | Free Allowance | Typical State Usage |
| -------- | -------------- | ------------------- |
| **Storage** | 10 GB/month | ~100 KB (negligible) |
| **Class A Ops** (write) | 1 million/month | ~100/month |
| **Class B Ops** (read) | 10 million/month | ~1000/month |
| **Egress** | **Unlimited** | N/A |

**Verdict:** A Terraform state file for this project will never exceed free tier limits. Even with 100 applies/day, you'd use <1% of the free operations quota.

> **Note:** The free tier only applies to **Standard storage class**. Infrequent Access storage is not included in the free tier. For Terraform state (frequently accessed), Standard storage is the correct choice anyway.

### Comparison with AWS S3

| Feature | AWS S3 + DynamoDB | Cloudflare R2 |
| ------- | ----------------- | ------------- |
| **Storage Cost** | $0.023/GB | **Free** (10GB) |
| **Egress Cost** | $0.09/GB | **Free** |
| **State Locking** | DynamoDB (~$1.25/mo) | Worker (~$0) or none |
| **Free Tier Duration** | 12 months only | **Permanent** |
| **Setup Complexity** | IAM + bucket + DynamoDB | Bucket + API token |

**Source:** [Cloudflare R2 Pricing](https://developers.cloudflare.com/r2/pricing/)

### R2 Operational Limits (Important for Teams)

| Limit | Value | Impact |
| ----- | ----- | ------ |
| **Per-bucket throughput** | ~5k PUTs/second | Practical limit, not hard cap |
| **Bucket management ops** | 50/second | Negligible for state ops |
| **Object size** | 5 TiB | State files are ~KB-MB |
| **r2.dev endpoint** | Hundreds req/sec | Testing only, use custom domain |

> **Note:** While R2 doesn't impose hard rate limits on the S3 API, simultaneous `tofu apply` operations on the same state file risk **state corruption** (not rate limiting). This reinforces the value of state locking for team environments or CI/CD pipelines.

---

## Implementation Options

### Option A: Simple R2 Backend (No Locking)

**Best for:** Single-user, local development, small teams with coordination

```hcl
# infrastructure/tofu/backend.tf
terraform {
  backend "s3" {
    bucket = "matherlynet-tfstate"
    key    = "proxmox/terraform.tfstate"
    region = "auto"

    # R2 S3-compatibility requirements
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    endpoints = {
      s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
    }
  }
}
```

**Pros:**
- Zero additional infrastructure
- Simple configuration
- Works immediately

**Cons:**
- No state locking (concurrent applies could corrupt state)
- Requires team coordination ("announce before applying")

> **Important:** OpenTofu 1.11+ and Terraform 1.11+ have known checksum validation issues with R2. Add these environment variables:
> ```bash
> export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
> export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
> ```

---

### Option B: R2 + Worker-based Locking (Recommended for Teams)

**Best for:** Multi-user environments, CI/CD pipelines, production use

Several open-source projects provide Terraform HTTP backends with locking backed by R2:

#### Recommended: tfstate-worker

**Repository:** [cmackenzie1/tfstate-worker](https://github.com/cmackenzie1/tfstate-worker)

```hcl
# infrastructure/tofu/backend.tf
terraform {
  backend "http" {
    address        = "https://tfstate.matherlynet.io/tfstate/states/proxmox"
    lock_address   = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    lock_method    = "LOCK"
    unlock_address = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    unlock_method  = "UNLOCK"
    username       = "terraform"
    password       = "<PSK_FROM_SOPS>"
  }
}
```

**Deployment:**
```bash
# Clone the tfstate-worker repository
git clone https://github.com/cmackenzie1/tfstate-worker
cd tfstate-worker

# Create R2 bucket
npx wrangler r2 bucket create matherlynet-tfstate

# Configure secrets
npx wrangler secret put TFSTATE_USERNAME
npx wrangler secret put TFSTATE_PASSWORD

# Deploy worker
npx wrangler deploy
```

**Pros:**
- Full state locking support
- Still uses free R2 storage
- Worker runs on free tier
- Supports multiple state files

**Cons:**
- Additional infrastructure to maintain
- Requires Cloudflare Workers deployment

#### Alternative: tfstate-backend-r2

**Repository:** [leonbreedt/tfstate-backend-r2](https://github.com/leonbreedt/tfstate-backend-r2)

Similar functionality, written in Rust, uses pre-shared key authentication.

> **Maintenance Note (Validated Jan 2026):**
> - **tfstate-worker**: Actively maintained (19 stars, 0 open issues, regular PRs)
> - **tfstate-backend-r2**: Dormant since Aug 2023 (0 stars, no recent activity)
>
> **Recommendation:** Use tfstate-worker for production deployments.

---

### Option C: R2 + OpenTofu State Encryption

**Best for:** Security-conscious environments, compliance requirements

OpenTofu 1.7+ supports client-side state encryption, adding a layer of security regardless of locking:

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
```

**Benefits:**
- State file is encrypted at rest
- Secrets in state are protected even if R2 bucket is compromised
- Works with any backend (R2, S3, local, etc.)

**Source:** [OpenTofu State Encryption](https://opentofu.org/docs/language/state/encryption/)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OPENTOFU + R2 STATE MANAGEMENT                           │
└─────────────────────────────────────────────────────────────────────────────┘

                            ┌─────────────────────┐
                            │   Git Repository    │
                            │  (Infrastructure    │
                            │     as Code)        │
                            └──────────┬──────────┘
                                       │
           ┌───────────────────────────┼───────────────────────────┐
           │                           │                           │
           ▼                           ▼                           ▼
   ┌───────────────┐          ┌───────────────┐          ┌───────────────┐
   │   Developer   │          │   Developer   │          │   GitHub      │
   │   Workstation │          │   Workstation │          │   Actions     │
   └───────┬───────┘          └───────┬───────┘          └───────┬───────┘
           │                           │                         │
           │ tofu plan/apply           │                         │
           │                           │                         │
           └───────────────────────────┼─────────────────────────┘
                                       │
                                       ▼
                    ┌──────────────────────────────────────┐
                    │         OPTION A: Direct R2          │
                    │  ┌────────────────────────────────┐  │
                    │  │   Cloudflare R2 Bucket         │  │
                    │  │   (S3-compatible API)          │  │
                    │  │   terraform.tfstate            │  │
                    │  └────────────────────────────────┘  │
                    │       ⚠️  No locking (coordinate).   │
                    └──────────────────────────────────────┘
                                       │
                                      OR
                                       │
                    ┌──────────────────────────────────────┐
                    │      OPTION B: Worker + R2           │
                    │  ┌────────────────────────────────┐  │
                    │  │   Cloudflare Worker            │  │
                    │  │   (tfstate-worker)             │  │
                    │  │   HTTP Backend + Locking       │  │
                    │  └──────────────┬─────────────────┘  │
                    │                 │                    │
                    │                 ▼                    │
                    │  ┌────────────────────────────────┐  │
                    │  │   Cloudflare R2 Bucket         │  │
                    │  │   terraform.tfstate            │  │
                    │  │   terraform.tfstate.lock       │  │
                    │  └────────────────────────────────┘  │
                    │       ✓ Full locking support         │
                    └──────────────────────────────────────┘
                                       │
                                       ▼
                    ┌──────────────────────────────────────┐
                    │           Proxmox VE                 │
                    │  ┌──────┐ ┌──────┐ ┌──────┐          │
                    │  │ VM 1 │ │ VM 2 │ │ VM 3 │          │
                    │  │Talos │ │Talos │ │Talos │          │
                    │  └──────┘ └──────┘ └──────┘          │
                    └──────────────────────────────────────┘
```

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
  TF_VAR_proxmox_api_token: ${{ secrets.PROXMOX_API_TOKEN }}

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}

      - name: Configure R2 Backend
        run: |
          cat > infrastructure/tofu/backend_override.tf <<EOF
          terraform {
            backend "s3" {
              bucket = "matherlynet-tfstate"
              key    = "proxmox/terraform.tfstate"
              region = "auto"

              skip_credentials_validation = true
              skip_metadata_api_check     = true
              skip_region_validation      = true
              skip_requesting_account_id  = true
              skip_s3_checksum            = true
              use_path_style              = true

              access_key = "${{ secrets.R2_ACCESS_KEY_ID }}"
              secret_key = "${{ secrets.R2_SECRET_ACCESS_KEY }}"

              endpoints = {
                s3 = "https://${{ secrets.CF_ACCOUNT_ID }}.r2.cloudflarestorage.com"
              }
            }
          }
          EOF

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

---

## Security Considerations

### Critical Security Notes

1. **HTTP Backend Exposure:** If using tfstate-worker, the Worker is exposed to the public internet. You MUST configure authentication (basic auth and/or mTLS).

2. **State Encryption is Client-Side:** OpenTofu encrypts before upload—R2 only stores the encrypted blob. Loss of encryption keys = permanent state loss.

3. **R2 Has NO Object Versioning:** Unlike AWS S3, R2 does **not support object versioning** at all (as of Jan 2026). This means:
   - Accidental overwrites or deletions are **permanent**
   - Consider implementing your own backup strategy (e.g., periodic state copies to a separate bucket)
   - Alternatively, use tfstate-worker which may support state history

4. **API Token Secret Shown Once:** When creating R2 API tokens, the Secret Access Key is only displayed once. Store it immediately in SOPS or your secret manager.

### R2 API Token Permissions

Create a scoped API token with minimal permissions:

```bash
# Via Cloudflare Dashboard: R2 > Manage R2 API Tokens
# Available permission levels:
#   - Admin Read & Write (full bucket + object management)
#   - Admin Read only (list and view only)
#   - Object Read & Write (recommended for Terraform state)
#   - Object Read only
#
# For Terraform state: "Object Read & Write" scoped to bucket is sufficient
```

> **Note:** Unauthorized requests to R2 are not charged, so a leaked token with wrong permissions won't incur costs—but still rotate it immediately.

**Best Practices for CI/CD:**
- Use **Account API tokens** (not User API tokens) for CI/CD pipelines — they survive user account changes
- Scope tokens to specific buckets using "Object Read & Write" permission
- Consider setting token expiration dates for security
- For advanced use cases, temporary credentials are available via the `temp-access-credentials` API

### Secret Management Integration

Integrate with project's existing SOPS/Age encryption:

```yaml
# infrastructure/secrets.sops.yaml
r2_access_key_id: ENC[AES256_GCM,data:...,type:str]
r2_secret_access_key: ENC[AES256_GCM,data:...,type:str]
cf_account_id: ENC[AES256_GCM,data:...,type:str]
```

### Task Integration

```yaml
# .taskfiles/infrastructure/Taskfile.yaml
tasks:
  tofu:init:
    desc: Initialize OpenTofu with R2 backend
    dir: "{{.TOFU_DIR}}"
    cmds:
      - |
        export AWS_ACCESS_KEY_ID=$(sops -d {{.ROOT_DIR}}/infrastructure/secrets.sops.yaml | yq '.r2_access_key_id')
        export AWS_SECRET_ACCESS_KEY=$(sops -d {{.ROOT_DIR}}/infrastructure/secrets.sops.yaml | yq '.r2_secret_access_key')
        tofu init
    preconditions:
      - test -f {{.ROOT_DIR}}/infrastructure/secrets.sops.yaml
```

---

## Migration Path

### From Ansible-Only to OpenTofu + R2

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MIGRATION PATH                                      │
└─────────────────────────────────────────────────────────────────────────────┘

  PHASE 1 (Current)              PHASE 2 (Transition)        PHASE 3 (Target)
  ────────────────────           ────────────────────        ────────────────

  ┌─────────────────┐           ┌─────────────────────┐     ┌─────────────────┐
  │ Manual VM       │           │ OpenTofu provisions │     │ Full IaC        │
  │ Creation        │──────────▶│ VMs, stores state   │────▶│ Pipeline        │
  │                 │           │ in R2               │     │                 │
  ├─────────────────┤           ├─────────────────────┤     ├─────────────────┤
  │ task bootstrap: │           │ task infra:provision│     │ task bootstrap: │
  │   talos         │           │ task bootstrap:talos│     │   full          │
  │ task bootstrap: │           │ task bootstrap:apps │     │ (single command)│
  │   apps          │           │                     │     │                 │
  └─────────────────┘           └─────────────────────┘     └─────────────────┘
```

### Implementation Steps

1. **Create R2 Bucket**
   ```bash
   npx wrangler r2 bucket create matherlynet-tfstate
   ```

2. **Generate R2 API Token**
   - Dashboard → R2 → Manage R2 API Tokens
   - Create token with Object Read & Write permissions

3. **Add Secrets to SOPS**
   ```bash
   sops infrastructure/secrets.sops.yaml
   # Add: r2_access_key_id, r2_secret_access_key, cf_account_id
   ```

4. **Configure Backend**
   - Add `backend.tf` as shown in Option A or B

5. **Test with Empty State**
   ```bash
   task infrastructure:tofu:init
   task infrastructure:plan
   ```

6. **(Optional) Deploy tfstate-worker for Locking**

---

## Comparison: Ansible vs OpenTofu + R2

| Criteria | Ansible (Stateless) | OpenTofu + R2 |
| -------- | ------------------- | ------------- |
| **State Management** | None | R2 (free) |
| **Locking** | N/A | Optional (Worker) |
| **Drift Detection** | On-run only | `tofu plan` anytime |
| **Resource Graph** | None | Automatic dependency resolution |
| **Destroy Support** | Manual playbook | `tofu destroy` |
| **Learning Curve** | Low | Medium |
| **Community Adoption** | High | Higher (Proxmox IaC) |
| **bpg/proxmox Provider** | N/A | Excellent support |
| **Talos Provider** | N/A | Full integration |

---

## Final Recommendation

### For This Project: OpenTofu + R2 (Option A or B)

Given the new availability of free R2 storage, **OpenTofu with R2 backend is now the recommended approach** for VM provisioning:

1. **Immediate (Phase 1):** Implement OpenTofu + R2 without locking
   - Simple setup, zero cost
   - Suitable for single-user development
   - Team coordination via communication

2. **If Needed (Phase 2):** Add tfstate-worker for locking
   - Only if concurrent applies become an issue
   - Still free (Worker free tier)
   - Full team/CI support

3. **Security Enhancement:** Add OpenTofu state encryption
   - Protects secrets at rest
   - Independent of backend choice

### Keep Ansible as Fallback

The Ansible implementation from `proxmox-vm-automation.md` remains valid as:
- Backup approach if R2/OpenTofu issues arise
- Option for users preferring truly stateless operation
- Educational/comparison purposes

---

## Sources

### Primary Documentation
- [Cloudflare R2 Remote Backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Cloudflare R2 Pricing](https://developers.cloudflare.com/r2/pricing/)
- [OpenTofu State Encryption](https://opentofu.org/docs/v1.9/language/state/encryption/)

### State Backend Solutions
- [tfstate-worker (cmackenzie1)](https://github.com/cmackenzie1/tfstate-worker) - HTTP backend with locking
- [tfstate-backend-r2 (leonbreedt)](https://github.com/leonbreedt/tfstate-backend-r2) - Rust-based backend
- [Terraform State with Cloudflare Workers (dev.to)](https://dev.to/adrienf/use-cloudflare-workers-to-store-your-terraform-states-1kkc)

### Provider Documentation
- [bpg/proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) (v0.89.x as of Jan 2026)
- [siderolabs/talos Provider](https://registry.terraform.io/providers/siderolabs/talos/latest)

### Community Discussions
- [OpenTofu R2 Native Backend Request](https://github.com/opentofu/opentofu/issues/3075)
- [Terraform R2 Support Issue](https://github.com/hashicorp/terraform/issues/33847)
- [Proxmox Forum - Best Terraform Provider](https://forum.proxmox.com/threads/best-terraform-provider.116152/)

### Tutorials
- [Terraform State Management with R2 (Medium)](https://medium.com/@GarisSpace/terraform-state-management-integrating-cloudflare-r2-b2e82798896d)
- [Using R2 for TF State (wreckitrob.dev)](https://wreckitrob.dev/posts/2-using-r2-for-tf-state)
- [Cole's Blog - Terraform Backend on Workers](https://mirio.dev/2022/09/18/implementing-a-terraform-state-backend/)

---

## Appendix: Validation Report

> **Validation performed:** January 2026
> **Method:** Cross-reference with official documentation, GitHub repositories, and live search verification

### Claims Validated ✓

| Claim | Source | Status |
| ----- | ------ | ------ |
| R2 free tier: 10GB storage | [Cloudflare R2 Pricing](https://developers.cloudflare.com/r2/pricing/) | ✓ Confirmed |
| R2 free tier: 1M Class A ops | Cloudflare R2 Pricing | ✓ Confirmed |
| R2 free tier: 10M Class B ops | Cloudflare R2 Pricing | ✓ Confirmed |
| R2 egress: Always free | Cloudflare R2 Pricing | ✓ Confirmed |
| R2 free tier: Permanent (no expiry) | Cloudflare R2 Pricing | ✓ Confirmed |
| S3 backend skip_* flags | [OpenTofu S3 Backend](https://opentofu.org/docs/language/settings/backends/s3/) | ✓ Confirmed |
| OpenTofu state encryption works with S3 backends | [OpenTofu Encryption](https://opentofu.org/docs/language/state/encryption/) | ✓ Confirmed |
| tfstate-worker actively maintained | [GitHub Repository](https://github.com/cmackenzie1/tfstate-worker) | ✓ Confirmed (19 stars, 0 issues) |

### Corrections Applied

| Original | Corrected |
| -------- | --------- |
| bpg/proxmox v0.90.0 | v0.89.x (as of Jan 2026) |
| OpenTofu 1.9+ state encryption | 1.7+ (feature introduced in v1.7.0) |
| 1/second concurrent write limit | Removed - R2 has ~5k PUTs/sec practical limit |

### Additions from Validation

1. **Rate limit clarification** - Updated operational limits with accurate R2 throughput info
2. **S3 checksum workaround** - Added environment variables for OpenTofu/Terraform 1.11+
3. **Account API token best practice** - Added CI/CD recommendations
4. **Maintenance status** of locking solutions - Added comparison note
5. **Security warnings** - Added critical notes about Worker exposure and versioning
6. **Client-side encryption** clarification - Added to security section
