# Input Variables
#
# Sensitive values should be loaded from secrets.sops.yaml via the task commands.
# Non-sensitive defaults can be overridden via terraform.tfvars or CLI.

# -----------------------------------------------------------------------------
# Proxmox Provider Variables (for future VM management)
# -----------------------------------------------------------------------------

variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
  default     = ""
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID (e.g., root@pam!terraform)"
  default     = ""
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API token secret"
  default     = ""
  sensitive   = true
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification for Proxmox API"
  default     = false
}

# -----------------------------------------------------------------------------
# State Encryption (Optional - OpenTofu 1.7+)
# -----------------------------------------------------------------------------

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for client-side state encryption (optional)"
  default     = ""
  sensitive   = true
}