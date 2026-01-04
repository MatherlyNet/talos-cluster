# OpenTofu HTTP Backend Configuration
# Uses tfstate-worker on Cloudflare R2 for state storage with locking
#
# Prerequisites:
# 1. Deploy tfstate-worker: https://github.com/MatherlyNet/matherlynet-tfstate
# 2. Configure credentials in cluster.yaml (tfstate_username, tfstate_password)
# 3. Run: task configure (generates secrets and auto-runs init if configured)
#
# Authentication is handled via environment variables:
# - TF_HTTP_USERNAME: Set from secrets.sops.yaml by task
# - TF_HTTP_PASSWORD: Set from secrets.sops.yaml by task

terraform {
  backend "http" {
    # State endpoint - change 'proxmox' to your project name for multiple states
    address = "https://tfstate.matherly.net/states/proxmox"

    # Lock endpoints for concurrent access protection
    lock_address   = "https://tfstate.matherly.net/states/proxmox/lock"
    lock_method    = "LOCK"
    unlock_address = "https://tfstate.matherly.net/states/proxmox/lock"
    unlock_method  = "UNLOCK"

    # Credentials set via environment variables:
    # TF_HTTP_USERNAME and TF_HTTP_PASSWORD
  }
}
