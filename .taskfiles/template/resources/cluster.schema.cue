package config

import (
	"net"
)

#Config: {
	node_cidr: net.IPCIDR & !=cluster_pod_cidr & !=cluster_svc_cidr
	node_dns_servers?: [...net.IPv4]
	node_ntp_servers?: [...net.IPv4]
	node_default_gateway?: net.IPv4 & !=""
	node_vlan_tag?: string & !=""
	cluster_pod_cidr: *"10.42.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_svc_cidr
	cluster_svc_cidr: *"10.43.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_pod_cidr
	cluster_api_addr: net.IPv4
	cluster_api_tls_sans?: [...net.FQDN]
	cluster_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr
	cluster_dns_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cloudflare_gateway_addr
	repository_name: string
	repository_branch?: string & !=""
	repository_visibility?: *"public" | "private"
	cloudflare_domain: net.FQDN
	cloudflare_token: string
	cloudflare_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr
	// Cilium LoadBalancer configuration
	cilium_loadbalancer_mode?: *"dsr" | "snat"

	// Cilium BGP Configuration - Optional for multi-VLAN environments
	// REF: https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/
	cilium_bgp_router_addr?:          net.IPv4 & !=""
	cilium_bgp_router_asn?:           string & =~"^[0-9]+$"
	cilium_bgp_node_asn?:             string & =~"^[0-9]+$"
	cilium_lb_pool_cidr?:             net.IPCIDR
	cilium_bgp_hold_time?:            *30 | int & >=3 & <=300
	cilium_bgp_keepalive_time?:       *10 | int & >=1 & <=100
	cilium_bgp_graceful_restart?:     *false | bool
	cilium_bgp_graceful_restart_time?: *120 | int & >=30 & <=600

	// UniFi DNS Integration - Optional for internal DNS via external-dns webhook
	// Requires UniFi Network v9.0.0+ for API key authentication (current stable: 9.5.21)
	unifi_host?:                string & =~"^https?://"
	unifi_api_key?:             string & !=""
	unifi_site?:                *"default" | string & !=""
	unifi_external_controller?: *false | bool

	// Infrastructure (OpenTofu/Proxmox) - Optional for VM deployments
	proxmox_api_url?:      string & =~"^https?://"
	proxmox_node?:         string & !=""
	proxmox_iso_storage?:  *"local" | string & !=""
	proxmox_disk_storage?: *"local-lvm" | string & !=""
	proxmox_vm_defaults?: {
		cores?:     *4 | int & >=1 & <=64
		sockets?:   *1 | int & >=1 & <=4
		memory?:    *8192 | int & >=1024 & <=262144
		disk_size?: *128 | int & >=32 & <=4096
	}
	proxmox_vm_advanced?: {
		bios?:         *"ovmf" | "seabios"
		machine?:      *"q35" | "i440fx"
		cpu_type?:     *"host" | string & !=""
		scsi_hw?:      *"virtio-scsi-pci" | "virtio-scsi-single" | "lsi"
		balloon?:      *0 | int & >=0
		numa?:         *true | bool
		qemu_agent?:   *true | bool
		net_queues?:   *4 | int & >=1 & <=16
		disk_discard?: *true | bool
		disk_ssd?:     *true | bool
		tags?: [...string]
	}
}

#Config
