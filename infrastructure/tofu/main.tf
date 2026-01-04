# Main OpenTofu Configuration
#
# This is the entry point for infrastructure management.
# Add resources here or organize into modules.

# -----------------------------------------------------------------------------
# Talos Node VM Definitions
# -----------------------------------------------------------------------------
# Infrastructure provisioning is enabled. Add Proxmox VM resources here.
#
# Example module structure:
#
# module "talos_nodes" {
#   source = "./modules/talos-vm"
#
#   for_each = { for node in var.nodes : node.name => node }
#
#   name        = each.value.name
#   target_node = var.proxmox_node
#   cores       = each.value.vm_cores
#   memory      = each.value.vm_memory
#   disk_size   = each.value.vm_disk_size
#   ip_address  = each.value.address
#   mac_address = each.value.mac_addr
# }

