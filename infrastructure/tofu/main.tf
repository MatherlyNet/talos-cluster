# Main OpenTofu Configuration
#
# This file provisions Talos Linux VMs on Proxmox VE.

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Extract unique schematic IDs for ISO downloads
  # This ensures we only download each unique ISO once
  unique_schematics = distinct([for node in var.nodes : node.schematic_id])

  # Create node map for for_each
  nodes_map = { for node in var.nodes : node.name => node }

  # Talos Image Factory URL base
  talos_factory_url = "https://factory.talos.dev/image"
}

# -----------------------------------------------------------------------------
# Talos ISO Download from Image Factory
# -----------------------------------------------------------------------------
# Downloads Talos ISOs from Image Factory using schematic IDs.
# Each unique schematic_id results in one ISO download.
# Multiple nodes with the same schematic share the same ISO.

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  for_each = toset(local.unique_schematics)

  content_type = "iso"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  # Talos Image Factory URL format:
  # https://factory.talos.dev/image/{schematic_id}/v{version}/nocloud-amd64.iso
  # Using nocloud for Proxmox/QEMU compatibility
  url = "${local.talos_factory_url}/${each.key}/v${var.talos_version}/nocloud-amd64.iso"

  # Use schematic ID prefix for filename (first 12 chars for readability)
  file_name = "talos-v${var.talos_version}-${substr(each.key, 0, 12)}.iso"

  # Overwrite if ISO already exists with different content
  overwrite = true

  # 10 minute timeout for large ISOs
  upload_timeout = 600
}

# -----------------------------------------------------------------------------
# Talos Node VMs
# -----------------------------------------------------------------------------
# Creates VMs for each node defined in nodes.yaml.
# VMs boot from the Talos ISO and enter maintenance mode.

resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each = local.nodes_map

  name        = each.value.name
  node_name   = var.proxmox_node
  description = "Talos Linux ${each.value.controller ? "control plane" : "worker"} node"

  # Tags for organization
  tags = concat(
    var.vm_advanced.tags,
    [each.value.controller ? "controller" : "worker"]
  )

  # VM should start after creation
  started = true
  on_boot = true

  # BIOS and Machine Type (Talos requires OVMF/UEFI)
  bios    = var.vm_advanced.bios
  machine = var.vm_advanced.machine

  # Guest OS type
  operating_system {
    type = var.vm_advanced.ostype
  }

  # Startup/Shutdown order
  startup {
    order      = each.value.vm_startup_order
    up_delay   = each.value.vm_startup_delay
    down_delay = each.value.vm_shutdown_delay
  }

  # CPU Configuration
  cpu {
    cores   = each.value.vm_cores
    sockets = each.value.vm_sockets
    type    = var.vm_advanced.cpu_type
    numa    = var.vm_advanced.numa
  }

  # Memory Configuration (no ballooning for Kubernetes)
  memory {
    dedicated = each.value.vm_memory
    floating  = var.vm_advanced.balloon
  }

  # QEMU Guest Agent
  agent {
    enabled = var.vm_advanced.qemu_agent
  }

  # EFI Disk (required for OVMF BIOS)
  efi_disk {
    datastore_id      = var.proxmox_disk_storage
    type              = "4m"
    pre_enrolled_keys = each.value.secureboot
  }

  # Boot ISO (Talos nocloud image)
  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso[each.value.schematic_id].id
    interface = "ide2"
  }

  # Primary disk
  disk {
    datastore_id = var.proxmox_disk_storage
    interface    = "scsi0"
    size         = each.value.vm_disk_size
    file_format  = "raw"
    ssd          = var.vm_advanced.disk_ssd
    discard      = var.vm_advanced.disk_discard ? "on" : "ignore"
    backup       = var.vm_advanced.disk_backup
    replicate    = var.vm_advanced.disk_replicate
    iothread     = true
  }

  # SCSI Controller
  scsi_hardware = var.vm_advanced.scsi_hw

  # Network Device
  network_device {
    bridge      = var.vm_advanced.network_bridge
    mac_address = upper(each.value.mac_addr)
    model       = "virtio"
    queues      = var.vm_advanced.net_queues
    vlan_id     = var.node_vlan_tag
  }

  # Serial device (required for console access)
  serial_device {}

  # VGA (minimal for Talos - use serial console)
  vga {
    type = "serial0"
  }

  # Lifecycle: Ignore changes to started state after creation
  lifecycle {
    ignore_changes = [
      started,
      cdrom, # ISO may be detached after Talos install
    ]
  }

  # Wait for ISO download
  depends_on = [proxmox_virtual_environment_download_file.talos_iso]
}

