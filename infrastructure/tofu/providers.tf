# Provider Configurations
#
# Credentials are loaded from infrastructure/secrets.sops.yaml
# Use task infra:secrets-edit to configure

# Proxmox Provider Configuration
# Uncomment and configure when ready to manage Proxmox VMs
#
# provider "proxmox" {
#   endpoint  = var.proxmox_api_url
#   api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
#   insecure  = var.proxmox_insecure
#
#   ssh {
#     agent = true
#   }
# }