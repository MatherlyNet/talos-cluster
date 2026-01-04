
# =============================================================================
# Proxmox Configuration
# =============================================================================

proxmox_api_url = "https://vs01.matherly.net:8006/api2/json"
proxmox_node    = "vs01"

# Storage Configuration
proxmox_iso_storage  = "local"
proxmox_disk_storage = "local-zfs"

# =============================================================================
# VM Default Settings
# =============================================================================
# Global defaults (fallback for all nodes)
vm_defaults = {
  cores     = 4
  sockets   = 1
  memory    = 8192
  disk_size = 128
}

# Controller node defaults (optimized for etcd and control plane)
vm_controller_defaults = {
  cores     = 4
  sockets   = 1
  memory    = 8192
  disk_size = 64
}

# Worker node defaults (optimized for running workloads)
vm_worker_defaults = {
  cores     = 8
  sockets   = 1
  memory    = 16384
  disk_size = 256
}

# =============================================================================
# VM Advanced Settings (Talos-optimized)
# =============================================================================

vm_advanced = {
  bios           = "ovmf"
  machine        = "q35"
  cpu_type       = "host"
  scsi_hw        = "virtio-scsi-pci"
  balloon        = 0
  numa           = true
  qemu_agent     = true
  net_queues     = 4
  disk_discard   = true
  disk_ssd       = true
  tags           = ["kubernetes", "linux", "talos"]
  # Network configuration
  network_bridge = "vmbr0"
  # Guest OS configuration
  ostype         = "l26"
  # Storage flags
  disk_backup    = false
  disk_replicate = false
}

# =============================================================================
# Network Configuration
# =============================================================================

node_cidr            = "192.168.20.0/22"
node_default_gateway = "192.168.23.254"
node_vlan_tag        = "7"

# =============================================================================
# Node Definitions
# =============================================================================

nodes = [
  {
    name             = "matherlynet-cp-1"
    address          = "192.168.22.101"
    controller       = true
    mac_addr         = "bc:24:11:62:36:01"
    schematic_id     = "a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca"
    disk             = "/dev/sda"
    # VM resource overrides (fallback chain: per-node -> role-defaults -> global-defaults)
    vm_cores         = 4
    vm_sockets       = 1
    vm_memory        = 8192
    vm_disk_size     = 100
    # Startup/shutdown configuration
    vm_startup_order  = 1
    vm_startup_delay  = 15
    vm_shutdown_delay = 60
    # Optional node settings
    mtu              = 1500
    secureboot       = true
    # VM ID (null = auto-assign by Proxmox)
    vm_id            = 7001
  },
  {
    name             = "matherlynet-cp-2"
    address          = "192.168.22.102"
    controller       = true
    mac_addr         = "bc:24:11:62:36:02"
    schematic_id     = "a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca"
    disk             = "S4EVNF0M123456"
    # VM resource overrides (fallback chain: per-node -> role-defaults -> global-defaults)
    vm_cores         = 4
    vm_sockets       = 1
    vm_memory        = 8192
    vm_disk_size     = 100
    # Startup/shutdown configuration
    vm_startup_order  = 2
    vm_startup_delay  = 15
    vm_shutdown_delay = 60
    # Optional node settings
    mtu              = 1500
    secureboot       = true
    # VM ID (null = auto-assign by Proxmox)
    vm_id            = 7002
  },
  {
    name             = "matherlynet-cp-3"
    address          = "192.168.22.103"
    controller       = true
    mac_addr         = "bc:24:11:62:36:03"
    schematic_id     = "a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca"
    disk             = "/dev/sda"
    # VM resource overrides (fallback chain: per-node -> role-defaults -> global-defaults)
    vm_cores         = 4
    vm_sockets       = 1
    vm_memory        = 8192
    vm_disk_size     = 100
    # Startup/shutdown configuration
    vm_startup_order  = 3
    vm_startup_delay  = 15
    vm_shutdown_delay = 60
    # Optional node settings
    mtu              = 1500
    secureboot       = true
    # VM ID (null = auto-assign by Proxmox)
    vm_id            = 7003
  },
  {
    name             = "matherlynet-wrkr-1"
    address          = "192.168.22.111"
    controller       = false
    mac_addr         = "bc:24:11:62:36:04"
    schematic_id     = "a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca"
    disk             = "/dev/sda"
    # VM resource overrides (fallback chain: per-node -> role-defaults -> global-defaults)
    vm_cores         = 8
    vm_sockets       = 1
    vm_memory        = 24576
    vm_disk_size     = 256
    # Startup/shutdown configuration
    vm_startup_order  = 10
    vm_startup_delay  = 15
    vm_shutdown_delay = 60
    # Optional node settings
    mtu              = 1500
    secureboot       = true
    # VM ID (null = auto-assign by Proxmox)
    vm_id            = 7011
  },
  {
    name             = "matherlynet-wrkr-2"
    address          = "192.168.22.112"
    controller       = false
    mac_addr         = "bc:24:11:62:36:05"
    schematic_id     = "a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca"
    disk             = "/dev/sda"
    # VM resource overrides (fallback chain: per-node -> role-defaults -> global-defaults)
    vm_cores         = 8
    vm_sockets       = 1
    vm_memory        = 24576
    vm_disk_size     = 256
    # Startup/shutdown configuration
    vm_startup_order  = 11
    vm_startup_delay  = 15
    vm_shutdown_delay = 60
    # Optional node settings
    mtu              = 1500
    secureboot       = true
    # VM ID (null = auto-assign by Proxmox)
    vm_id            = 7012
  },
  {
    name             = "matherlynet-wrkr-3"
    address          = "192.168.22.113"
    controller       = false
    mac_addr         = "bc:24:11:62:36:06"
    schematic_id     = "a7f294c4436e874167652f711750f9bc607c89f12f7c27f183584a25763a2bca"
    disk             = "/dev/sda"
    # VM resource overrides (fallback chain: per-node -> role-defaults -> global-defaults)
    vm_cores         = 8
    vm_sockets       = 1
    vm_memory        = 24576
    vm_disk_size     = 256
    # Startup/shutdown configuration
    vm_startup_order  = 12
    vm_startup_delay  = 15
    vm_shutdown_delay = 60
    # Optional node settings
    mtu              = 1500
    secureboot       = true
    # VM ID (null = auto-assign by Proxmox)
    vm_id            = 7013
  },
]

# =============================================================================
# Cluster Network Configuration (for reference in VM provisioning)
# =============================================================================

cluster_api_addr = "192.168.22.100"
cluster_pod_cidr = "10.42.0.0/16"
cluster_svc_cidr = "10.43.0.0/16"

# =============================================================================
# Talos Version (for ISO download from Image Factory)
# =============================================================================

talos_version = "1.12.0"

