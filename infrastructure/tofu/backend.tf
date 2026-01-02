# OpenTofu HTTP Backend Configuration
# Uses tfstate-worker on Cloudflare R2 for state storage with locking
#
# Prerequisites:
# 1. Deploy tfstate-worker: https://github.com/MatherlyNet/matherlynet-tfstate
# 2. Create secrets: task infra:secrets-create && task infra:secrets-edit
# 3. Initialize: task infra:init
#
# Authentication is handled via environment variables:
# - TF_HTTP_USERNAME: Set from secrets.sops.yaml by task
# - TF_HTTP_PASSWORD: Set from secrets.sops.yaml by task

terraform {
  backend "http" {
    # State endpoint - change 'proxmox' to your project name for multiple states
    address = "https://tfstate.matherlynet.io/tfstate/states/proxmox"

    # Lock endpoints for concurrent access protection
    lock_address   = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    lock_method    = "LOCK"
    unlock_address = "https://tfstate.matherlynet.io/tfstate/states/proxmox/lock"
    unlock_method  = "UNLOCK"

    # Credentials set via environment variables:
    # TF_HTTP_USERNAME and TF_HTTP_PASSWORD
  }
}