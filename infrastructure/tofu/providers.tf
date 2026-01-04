# Provider Configurations
#
# Credentials are loaded from infrastructure/secrets.sops.yaml
# Source: cluster.yaml (gitignored) - configure there, then run task configure

# Proxmox Provider Configuration
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_insecure

  ssh {
    agent = true
  }
}
