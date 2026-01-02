# Ansible + Proxmox VM Automation Research

> **Research Date:** January 2026
> **Status:** Complete - Comprehensive Analysis for Talos Linux Cluster Provisioning
> **Environment:** Proxmox VE 9.x, Talos Linux 1.12.0, Kubernetes 1.35.0
> **Schematic ID:** `29d123fd0e746fccd5ff52d37c0cdbd2d653e10ae29c39276b6edb9ffbd56cf4`

## Executive Summary

This document provides a comprehensive analysis of using **Ansible with the community.proxmox collection** for automating Proxmox VM provisioning for Talos Linux clusters. This approach is evaluated as the **SECONDARY RECOMMENDATION** from the original research (`proxmox-vm-automation.md`), positioned as a stateless alternative to Terraform/OpenTofu.

### Key Findings

| Criteria | Assessment |
| -------- | ---------- |
| **State Management** | Truly stateless - no state files required |
| **Maturity** | High - Ansible is battle-tested, collection is actively developed |
| **Talos Integration** | Limited - Talos doesn't support SSH for post-boot config |
| **GitOps Compatibility** | Good - Via CI/CD pipelines, not native like Crossplane |
| **Learning Curve** | Low - Familiar YAML syntax, widely known in DevOps |
| **Production Readiness** | High for VM provisioning, considerations for Talos specifics |

### Verified Tool Versions (January 2026)

| Tool/Component | Version | Notes |
| -------------- | ------- | ----- |
| [community.proxmox](https://galaxy.ansible.com/ui/repo/published/community/proxmox/) | 1.5.0 | Released December 27, 2025 |
| [Ansible Core](https://docs.ansible.com/ansible-core/devel/index.html) | 2.17+ | Required minimum |
| [proxmoxer](https://pypi.org/project/proxmoxer/) | 2.0+ | Python library for Proxmox API |
| [Talos Linux](https://www.talos.dev/) | 1.12.0 | NoCloud image required |

---

## Why Ansible for Proxmox VM Provisioning?

### Stateless Architecture

Ansible is **truly stateless** - it determines current state at runtime and applies changes idempotently. This eliminates:

- State file management complexity
- Remote state backends (S3, GCS, etc.)
- State locking for concurrent access
- State drift detection mechanisms
- Secrets exposure in state files

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ANSIBLE STATELESS WORKFLOW                             │
└─────────────────────────────────────────────────────────────────────────────┘

  nodes.yaml                    Ansible Playbook              Proxmox API
      │                              │                            │
      │   ┌──────────────────────────┼────────────────────────────┤
      ▼   ▼                          ▼                            ▼
  ┌─────────┐    ┌──────────────────────────────┐    ┌────────────────┐
  │ Desired │───▶│   For each node:             │───▶│   Query VMs    │
  │  State  │    │   1. Check if VM exists      │    │   via API      │
  └─────────┘    │   2. Compare specs           │    └────────────────┘
                 │   3. Create/Update if needed │           │
                 │   4. Start if not running    │           ▼
                 └──────────────────────────────┘    ┌────────────────┐
                              │                      │ Create/Update  │
                              │                      │ VM if needed   │
                              ▼                      └────────────────┘
                 ┌──────────────────────────────┐
                 │   VMs ready for Talos        │
                 │   bootstrap                  │
                 └──────────────────────────────┘
```

### Multi-Team Friendly

Unlike Terraform/OpenTofu with state locking, Ansible doesn't block concurrent runs:

- No state locks to acquire or release
- Multiple team members can run playbooks independently
- Idempotent by design - safe to run repeatedly
- No remote backend infrastructure required

---

## community.proxmox Collection

### Migration Notice

> **IMPORTANT:** The `community.general.proxmox_kvm` module redirect has been deprecated. Update tasks to use `community.proxmox.proxmox_kvm`. The redirect will be removed in version 15.0.0 of community.general.

```bash
# Install the dedicated collection
ansible-galaxy collection install community.proxmox --upgrade
```

### Available Modules (37+ total)

The [community.proxmox collection](https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/index.html) provides comprehensive Proxmox management:

#### VM & Instance Management

| Module | Description |
| ------ | ----------- |
| `proxmox` | Instance management in Proxmox VE clusters |
| `proxmox_kvm` | Qemu(KVM) virtual machine management |
| `proxmox_vm_info` | Retrieve VM information |
| `proxmox_disk` | Manage Qemu VM disks |
| `proxmox_nic` | Manage VM network interfaces |
| `proxmox_snap` | Snapshot management |
| `proxmox_template` | Manage OS templates |

#### Backup & Storage

| Module | Description |
| ------ | ----------- |
| `proxmox_backup` | Start VM backups |
| `proxmox_backup_info` | Retrieve scheduled backup information |
| `proxmox_backup_schedule` | Schedule and manage backups |
| `proxmox_storage` | Manage cluster and node storage |
| `proxmox_storage_info` | Retrieve storage information |
| `proxmox_storage_contents_info` | List storage contents |

#### Cluster & HA

| Module | Description |
| ------ | ----------- |
| `proxmox_cluster` | Create and join clusters |
| `proxmox_cluster_ha_groups` | Manage HA groups |
| `proxmox_cluster_ha_resources` | Manage HA resources |
| `proxmox_cluster_ha_rules` | Manage HA rules |

#### Network & Firewall

| Module | Description |
| ------ | ----------- |
| `proxmox_firewall` | Manage firewall rules |
| `proxmox_firewall_info` | Retrieve firewall information |
| `proxmox_vnet` | Manage SDN virtual networks |
| `proxmox_subnet` | Create/update/delete SDN subnets |

#### Access Control

| Module | Description |
| ------ | ----------- |
| `proxmox_access_acl` | Manage ACLs |
| `proxmox_user` | User management |
| `proxmox_group` | Group management |
| `proxmox_pool` | Pool management |

### Collection Statistics

| Metric | Value |
| ------ | ----- |
| GitHub Stars | ~50 |
| Forks | ~79 |
| Contributors | ~80 |
| Latest Version | 1.5.0 (Dec 2025) |
| Ansible Core Required | 2.17+ |
| Python Required | 3.7+ |
| License | GPL-3.0+ |

---

## Talos Linux Integration Considerations

### The SSH Challenge

Talos Linux is an **immutable, API-driven operating system** that deliberately removes:
- SSH access
- Shell access
- Package managers
- Traditional configuration management

This means **Ansible cannot be used for post-boot Talos configuration**. Its role is limited to:

1. ✅ VM provisioning on Proxmox
2. ✅ Template creation and management
3. ✅ Network preparation (DHCP reservations if using pfSense)
4. ❌ Talos machine configuration (use `talosctl` instead)
5. ❌ Kubernetes configuration (handled by Talos API)

### NoCloud Image Requirements

For cloud-init integration with Talos on Proxmox:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TALOS IMAGE TYPE COMPATIBILITY                           │
└─────────────────────────────────────────────────────────────────────────────┘

  Talos Version      Image Type        Cloud-Init Support    Ansible Use Case
  ─────────────────────────────────────────────────────────────────────────────
  1.7.x and earlier  nocloud           ✓ Native              Clone from template
  1.8.0+             metal (default)   ✗ No cloud-init       Must use nocloud from Factory
  1.12.0 (current)   nocloud           ✓ Via Image Factory   Clone from template
```

**Critical:** Download the **nocloud** image variant from [Talos Image Factory](https://factory.talos.dev/), not the default metal image.

### NoCloud Configuration Methods

#### Method 1: Cloud-Init Drive with cicustom

```bash
# Place Talos machine config as cloud-init snippet
cp controlplane-1.yaml /var/lib/vz/snippets/controlplane-1.yml

# Configure VM to use the snippet
qm set 100 --cicustom user=local:snippets/controlplane-1.yml
```

#### Method 2: SMBIOS Serial (nocloud-net)

```bash
# Base64-encode the nocloud-net datasource URL
SERIAL=$(printf 'ds=nocloud-net;s=http://10.10.0.1/configs/' | base64)

# Set via Proxmox API
qm set $VM_ID --smbios1 "uuid=$(uuidgen),serial=${SERIAL},base64=1"
```

Talos fetches configuration from:
- `http://10.10.0.1/configs/user-data` (machine config)
- `http://10.10.0.1/configs/network-config` (optional)

---

## Implementation Architecture

### Directory Structure

```
matherlynet-talos-cluster/
├── infrastructure/
│   └── ansible/
│       ├── ansible.cfg
│       ├── inventory/
│       │   └── proxmox.yml              # Proxmox inventory
│       ├── playbooks/
│       │   ├── provision-vms.yaml       # Main VM provisioning
│       │   ├── destroy-vms.yaml         # VM cleanup
│       │   ├── status-vms.yaml          # Status check
│       │   └── create-template.yaml     # Template creation
│       ├── roles/
│       │   └── proxmox_vm/
│       │       ├── tasks/main.yaml
│       │       ├── defaults/main.yaml
│       │       └── vars/main.yaml
│       └── group_vars/
│           └── all/
│               ├── vars.yaml
│               └── vault.yaml           # SOPS-encrypted
├── nodes.yaml                           # Node definitions (shared)
└── cluster.yaml                         # Cluster config (shared)
```

### Workflow Integration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ANSIBLE + TALOS PROVISIONING FLOW                        │
└─────────────────────────────────────────────────────────────────────────────┘

                    cluster.yaml + nodes.yaml
                              │
                              ▼
              ┌───────────────────────────────────┐
              │         task configure            │
              │   (existing makejinja templating) │
              └───────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    kubernetes/          talos/             infrastructure/
    (K8s manifests)   (Talos configs)       ansible/
                                                  │
                                                  ▼
              ┌───────────────────────────────────┐
              │   task infrastructure:provision   │
              │     (ansible-playbook)            │
              └───────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────────┐
              │       task bootstrap:talos        │
              │   (existing - applies Talos cfg)  │
              └───────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────────┐
              │        task bootstrap:apps        │
              │   (existing - deploys apps)       │
              └───────────────────────────────────┘
```

---

## Example Playbooks

### VM Provisioning Playbook

**File: `infrastructure/ansible/playbooks/provision-vms.yaml`**

```yaml
---
- name: Provision Talos VMs on Proxmox
  hosts: localhost
  gather_facts: false
  vars_files:
    - "{{ playbook_dir }}/../../../nodes.yaml"
  vars:
    proxmox_host: "{{ lookup('env', 'PROXMOX_HOST') | default('proxmox.local') }}"
    proxmox_token_id: "{{ lookup('env', 'PROXMOX_TOKEN_ID') }}"
    proxmox_token_secret: "{{ lookup('env', 'PROXMOX_TOKEN_SECRET') }}"
    proxmox_node: "pve"
    talos_template: "talos-1.12.0"
    storage_pool: "local-zfs"
    network_bridge: "vmbr0"

  tasks:
    - name: Validate Proxmox credentials
      ansible.builtin.assert:
        that:
          - proxmox_token_id | length > 0
          - proxmox_token_secret | length > 0
        fail_msg: "Proxmox API credentials not configured. Set PROXMOX_TOKEN_ID and PROXMOX_TOKEN_SECRET."

    - name: Ensure Talos template exists
      community.proxmox.proxmox_vm_info:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        node: "{{ proxmox_node }}"
        name: "{{ talos_template }}"
      register: template_check
      failed_when: template_check.proxmox_vms | length == 0

    - name: Clone and configure Talos VMs
      community.proxmox.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        node: "{{ proxmox_node }}"
        name: "{{ item.name }}"
        clone: "{{ talos_template }}"
        full: true
        storage: "{{ storage_pool }}"
        cores: "{{ item.cores | default(4) }}"
        memory: "{{ item.memory | default(8192) }}"
        net:
          net0: "virtio,bridge={{ network_bridge }},macaddr={{ item.mac_addr }}"
        scsihw: virtio-scsi-pci
        boot: order=scsi0
        bios: ovmf
        agent: true
        tags:
          - talos
          - "{{ 'control-plane' if item.controller | default(false) else 'worker' }}"
          - kubernetes
        state: present
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"
      register: vm_create_results

    - name: Resize VM disks
      community.proxmox.proxmox_disk:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        vmid: "{{ vm_create_results.results[idx].vmid }}"
        disk: scsi0
        size: "{{ item.disk_size | default(100) }}G"
        state: resized
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"
        index_var: idx
      when: vm_create_results.results[idx].changed

    - name: Start VMs
      community.proxmox.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        node: "{{ proxmox_node }}"
        name: "{{ item.name }}"
        state: started
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"

    - name: Wait for VMs to be reachable (Talos API port)
      ansible.builtin.wait_for:
        host: "{{ item.address }}"
        port: 50000
        timeout: 300
        state: started
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"

    - name: Display VM status
      ansible.builtin.debug:
        msg: |
          VM Provisioning Complete!

          Nodes ready for Talos bootstrap:
          {% for node in nodes %}
          - {{ node.name }}: {{ node.address }}
          {% endfor %}

          Next step: task bootstrap:talos
```

### Template Creation Playbook

**File: `infrastructure/ansible/playbooks/create-template.yaml`**

```yaml
---
- name: Create Talos VM Template
  hosts: localhost
  gather_facts: false
  vars:
    proxmox_host: "{{ lookup('env', 'PROXMOX_HOST') }}"
    proxmox_token_id: "{{ lookup('env', 'PROXMOX_TOKEN_ID') }}"
    proxmox_token_secret: "{{ lookup('env', 'PROXMOX_TOKEN_SECRET') }}"
    proxmox_node: "pve"
    storage_pool: "local-zfs"
    talos_version: "1.12.0"
    talos_schematic_id: "29d123fd0e746fccd5ff52d37c0cdbd2d653e10ae29c39276b6edb9ffbd56cf4"
    template_vmid: 9000

  tasks:
    - name: Download Talos nocloud image
      ansible.builtin.get_url:
        url: "https://factory.talos.dev/image/{{ talos_schematic_id }}/v{{ talos_version }}/nocloud-amd64.raw.xz"
        dest: "/tmp/talos-{{ talos_version }}.raw.xz"
        mode: '0644'

    - name: Extract Talos image
      ansible.builtin.command:
        cmd: "xz -dk /tmp/talos-{{ talos_version }}.raw.xz"
        creates: "/tmp/talos-{{ talos_version }}.raw"

    - name: Create base VM for template
      community.proxmox.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        node: "{{ proxmox_node }}"
        vmid: "{{ template_vmid }}"
        name: "talos-{{ talos_version }}"
        cores: 2
        memory: 4096
        bios: ovmf
        scsihw: virtio-scsi-pci
        net:
          net0: "virtio,bridge=vmbr0"
        agent: true
        state: present

    # Note: Image import requires Proxmox host access
    # This step typically requires running on Proxmox node or SSH access
    - name: Import disk (requires Proxmox host execution)
      ansible.builtin.debug:
        msg: |
          Manual step required on Proxmox host:

          qm importdisk {{ template_vmid }} /tmp/talos-{{ talos_version }}.raw {{ storage_pool }}
          qm set {{ template_vmid }} --scsi0 {{ storage_pool }}:vm-{{ template_vmid }}-disk-0
          qm set {{ template_vmid }} --boot order=scsi0
          qm template {{ template_vmid }}
```

### Status Check Playbook

**File: `infrastructure/ansible/playbooks/status-vms.yaml`**

```yaml
---
- name: Check Talos VM Status
  hosts: localhost
  gather_facts: false
  vars_files:
    - "{{ playbook_dir }}/../../../nodes.yaml"
  vars:
    proxmox_host: "{{ lookup('env', 'PROXMOX_HOST') }}"
    proxmox_token_id: "{{ lookup('env', 'PROXMOX_TOKEN_ID') }}"
    proxmox_token_secret: "{{ lookup('env', 'PROXMOX_TOKEN_SECRET') }}"
    proxmox_node: "pve"

  tasks:
    - name: Get VM information
      community.proxmox.proxmox_vm_info:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        node: "{{ proxmox_node }}"
        name: "{{ item.name }}"
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"
      register: vm_info

    - name: Display VM status
      ansible.builtin.debug:
        msg: |
          {% for result in vm_info.results %}
          {{ result.item.name }}:
            Status: {{ result.proxmox_vms[0].status | default('NOT FOUND') }}
            VMID: {{ result.proxmox_vms[0].vmid | default('N/A') }}
            Expected IP: {{ result.item.address }}
          {% endfor %}
```

---

## Go-Task Integration

**File: `.taskfiles/infrastructure/Taskfile.yaml`**

```yaml
---
version: "3"

vars:
  ANSIBLE_DIR: "{{.ROOT_DIR}}/infrastructure/ansible"

env:
  ANSIBLE_CONFIG: "{{.ANSIBLE_DIR}}/ansible.cfg"

tasks:
  # ─────────────────────────────────────────────────────────────────────────
  # VM Provisioning Tasks
  # ─────────────────────────────────────────────────────────────────────────

  provision:
    desc: Provision Talos VMs on Proxmox (stateless/idempotent)
    dir: "{{.ANSIBLE_DIR}}"
    cmds:
      - |
        export PROXMOX_TOKEN_ID=$(sops -d secrets.sops.yaml | yq '.proxmox_token_id')
        export PROXMOX_TOKEN_SECRET=$(sops -d secrets.sops.yaml | yq '.proxmox_token_secret')
        export PROXMOX_HOST=$(sops -d secrets.sops.yaml | yq '.proxmox_host')
        ansible-playbook playbooks/provision-vms.yaml
    preconditions:
      - test -f {{.ROOT_DIR}}/nodes.yaml
      - which ansible-playbook
      - test -f {{.ANSIBLE_DIR}}/secrets.sops.yaml

  destroy:
    desc: Destroy all Talos VMs
    dir: "{{.ANSIBLE_DIR}}"
    prompt: This will DESTROY all VMs. Are you absolutely sure?
    cmds:
      - |
        export PROXMOX_TOKEN_ID=$(sops -d secrets.sops.yaml | yq '.proxmox_token_id')
        export PROXMOX_TOKEN_SECRET=$(sops -d secrets.sops.yaml | yq '.proxmox_token_secret')
        export PROXMOX_HOST=$(sops -d secrets.sops.yaml | yq '.proxmox_host')
        ansible-playbook playbooks/destroy-vms.yaml
    preconditions:
      - which ansible-playbook

  status:
    desc: Show VM status
    dir: "{{.ANSIBLE_DIR}}"
    cmds:
      - |
        export PROXMOX_TOKEN_ID=$(sops -d secrets.sops.yaml | yq '.proxmox_token_id')
        export PROXMOX_TOKEN_SECRET=$(sops -d secrets.sops.yaml | yq '.proxmox_token_secret')
        export PROXMOX_HOST=$(sops -d secrets.sops.yaml | yq '.proxmox_host')
        ansible-playbook playbooks/status-vms.yaml
    preconditions:
      - which ansible-playbook

  # ─────────────────────────────────────────────────────────────────────────
  # Template Management
  # ─────────────────────────────────────────────────────────────────────────

  template:create:
    desc: Create Talos VM template
    dir: "{{.ANSIBLE_DIR}}"
    cmds:
      - |
        export PROXMOX_TOKEN_ID=$(sops -d secrets.sops.yaml | yq '.proxmox_token_id')
        export PROXMOX_TOKEN_SECRET=$(sops -d secrets.sops.yaml | yq '.proxmox_token_secret')
        export PROXMOX_HOST=$(sops -d secrets.sops.yaml | yq '.proxmox_host')
        ansible-playbook playbooks/create-template.yaml
    preconditions:
      - which ansible-playbook
```

---

## Credential Management

### SOPS Integration (Recommended)

**File: `infrastructure/ansible/secrets.sops.yaml`**

```yaml
proxmox_host: ENC[AES256_GCM,data:...,type:str]
proxmox_token_id: ENC[AES256_GCM,data:...,type:str]
proxmox_token_secret: ENC[AES256_GCM,data:...,type:str]
```

**Create and encrypt:**
```bash
# Create plaintext
cat > infrastructure/ansible/secrets.yaml <<EOF
proxmox_host: "192.168.22.10"
proxmox_token_id: "automation@pve!ansible"
proxmox_token_secret: "your-secret-token-here"
EOF

# Encrypt with SOPS
sops --encrypt --age $(cat age.key | grep -o 'age1.*') \
  infrastructure/ansible/secrets.yaml > infrastructure/ansible/secrets.sops.yaml

# Remove plaintext
rm infrastructure/ansible/secrets.yaml
```

### Proxmox API Token Setup

```bash
# On Proxmox host
pveum user add automation@pve
pveum role add AnsibleProvisioner -privs "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory VM.Config.Network VM.Config.Options VM.PowerMgmt Datastore.AllocateSpace Datastore.AllocateTemplate SDN.Use"
pveum aclmod /vms -user automation@pve -role AnsibleProvisioner
pveum aclmod /storage/local-zfs -user automation@pve -role AnsibleProvisioner
pveum user token add automation@pve ansible -privsep 1
```

---

## Known Limitations

### 1. VM Hardware Updates

The `proxmox_kvm` module has limitations updating existing VM hardware. The Proxmox API historically only supported hardware modification during VM creation.

**Workaround:** Destroy and recreate VMs for hardware changes, or use direct API calls.

### 2. No Post-Boot Talos Configuration

Ansible cannot configure Talos after VM boot due to lack of SSH access.

**Solution:** Use `talosctl` and the existing `task bootstrap:talos` workflow.

### 3. Template Disk Import

Importing disk images to Proxmox typically requires host-level access. The Proxmox API doesn't fully support disk import operations.

**Workaround:** Use Packer for template creation, or run import commands via Proxmox SSH.

### 4. Concurrent Clone Issues

Running playbooks against multiple Proxmox nodes can cause lock errors when cloning VMs with the same ID.

**Solution:** Use `serial: 1` in playbooks or implement node-specific VMID allocation.

---

## Comparison: Ansible vs OpenTofu

| Aspect | Ansible | OpenTofu |
| ------ | ------- | -------- |
| **State Management** | None (stateless) | Required (local/remote) |
| **Idempotency** | Built-in | Via state comparison |
| **Learning Curve** | Lower (YAML) | Medium (HCL) |
| **Talos Provider** | None | siderolabs/talos |
| **Proxmox Provider** | community.proxmox | bpg/proxmox |
| **Plan/Preview** | `--check` mode | `tofu plan` |
| **Drift Detection** | Per-run only | Continuous via state |
| **GitOps Integration** | Via CI/CD | Via CI/CD |
| **Multi-team** | No locks needed | State locking |

---

## Recommendations

### Use Ansible When

1. **Multi-team environments** where state locking is problematic
2. **Simple VM lifecycle** without complex dependencies
3. **Existing Ansible infrastructure** in your organization
4. **Quick iteration** needed without state management overhead
5. **Hybrid workflows** combining VM provisioning with other Ansible tasks

### Consider OpenTofu/Terraform When

1. **Complex dependencies** between infrastructure resources
2. **Drift detection** is critical for compliance
3. **Preview changes** before applying is mandatory
4. **Talos-specific features** (config generation) are needed
5. **State-based rollback** capability is required

### Recommended Hybrid Approach

Use Ansible for:
- VM provisioning on Proxmox
- Template management
- Network preparation (DHCP, DNS)

Use existing project tools for:
- Talos configuration (`talosctl` via `task bootstrap:talos`)
- Kubernetes deployment (Flux via `task bootstrap:apps`)
- Secrets management (SOPS/Age)

---

## Sources

### Official Documentation
- [community.proxmox Collection](https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/index.html)
- [community.proxmox GitHub Repository](https://github.com/ansible-collections/community.proxmox)
- [Talos Linux NoCloud Documentation](https://docs.siderolabs.com/talos/v1.11/platform-specific-installations/cloud-platforms/nocloud)

### Community Examples
- [jdefreeuw/talos-ansible](https://github.com/jdefreeuw/talos-ansible) - Talos deployment on Proxmox using Ansible
- [Proxmox VM Deployment with Ansible](https://joshrnoll.com/deploying-proxmox-vms-with-ansible/)
- [Automate Proxmox VM Deployment with Ansible Cloud-Init](https://www.uncommonengineer.com/docs/engineer/LAB/proxmox-cloudinit/)
- [Automation in Action: Proxmox and Ansible](https://dev.to/serafiev/automation-in-action-scenarios-with-proxmox-and-ansible-3dno)

### Proxmox Forums
- [Ansible Proxmox Forum Tag](https://forum.proxmox.com/tags/ansible/)
- [VM Provisioning from Template Discussion](https://forum.proxmox.com/threads/provision-vm-from-template-using-ansible.130596/)
- [Network Configuration with Ansible](https://forum.proxmox.com/threads/how-to-configure-network-settings-using-ansible-community-general-proxmox_kvm-module.156466/)
