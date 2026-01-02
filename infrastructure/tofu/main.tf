# Main OpenTofu Configuration
#
# This is the entry point for infrastructure management.
# Add resources here or organize into modules.

# -----------------------------------------------------------------------------
# Example: Placeholder resource to verify backend connectivity
# Remove after confirming state backend works
# -----------------------------------------------------------------------------

# Uncomment to test state backend:
# resource "null_resource" "backend_test" {
#   triggers = {
#     timestamp = timestamp()
#   }
# }

# -----------------------------------------------------------------------------
# Future: Talos Node VM Definitions
# -----------------------------------------------------------------------------

# Module structure suggestion:
#
# module "talos_controlplane" {
#   source = "./modules/talos-vm"
#
#   for_each = var.controlplane_nodes
#
#   name        = each.key
#   target_node = each.value.proxmox_node
#   cores       = each.value.cores
#   memory      = each.value.memory
#   disk_size   = each.value.disk_size
#   ip_address  = each.value.ip_address
#   mac_address = each.value.mac_address
#   talos_image = var.talos_image_url
# }