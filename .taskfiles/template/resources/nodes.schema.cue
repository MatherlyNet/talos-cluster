package config

import (
	"net"
	"list"
)

#Config: {
	nodes: [...#Node]
	_nodes_check: {
		name: list.UniqueItems() & [for item in nodes {item.name}]
		address: list.UniqueItems() & [for item in nodes {item.address}]
		mac_addr: list.UniqueItems() & [for item in nodes {item.mac_addr}]
	}
}

#Node: {
	name:          =~"^[a-z0-9][a-z0-9\\-]{0,61}[a-z0-9]$|^[a-z0-9]$" & !="global" & !="controller" & !="worker"
	address:       net.IPv4
	controller:    bool
	disk:          string
	mac_addr:      =~"^([0-9a-f]{2}[:]){5}([0-9a-f]{2})$"
	schematic_id:  =~"^[a-z0-9]{64}$"
	mtu?:            >=1450 & <=9000
	secureboot?:     bool
	encrypt_disk?:   bool
	kernel_modules?: [...string]

	// VM-specific settings (only used when provisioning via OpenTofu)
	vm_cores?:          int & >=1 & <=64
	vm_sockets?:        int & >=1 & <=4
	vm_memory?:         int & >=1024 & <=262144
	vm_disk_size?:      int & >=32 & <=4096
	vm_startup_order?:  int & >=1 & <=100
	vm_startup_delay?:  int & >=0 & <=300
	vm_shutdown_delay?: int & >=0 & <=600  // Graceful shutdown timeout
}

#Config
