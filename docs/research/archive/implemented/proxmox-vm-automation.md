# Proxmox VM Automation Research: Extending GitOps to Infrastructure

> **Research Date:** January 2026
> **Status:** Complete - Updated with Stateless Alternatives and Environment-Specific Configuration
> **Sources:** Community implementations, official documentation, GitHub repositories
> **Environment:** Proxmox VE 9.x with ZFS pool storage, Talos Linux 1.12.0, Kubernetes 1.35.0
> **Schematic ID:** `29d123fd0e746fccd5ff52d37c0cdbd2d653e10ae29c39276b6edb9ffbd56cf4` (nocloud + secureboot + qemu-guest-agent)
>
> ### Verified Tool Versions (January 2026)
>
> | Tool/Provider | Version | Notes |
> | ------------- | ------- | ----- |
> | [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) | 0.90.0 | Terraform/OpenTofu provider |
> | [siderolabs/talos](https://registry.terraform.io/providers/siderolabs/talos/latest) | 0.10.0 | Terraform/OpenTofu provider |
> | [OpenTofu](https://github.com/opentofu/opentofu/releases) | 1.11.2 | IaC runtime |
> | [Packer Proxmox Plugin](https://github.com/hashicorp/packer-plugin-proxmox/releases) | 1.2.3 | Image builder |
> | [CAPMOX](https://github.com/ionos-cloud/cluster-api-provider-proxmox/releases) | 0.7.5 | Cluster API provider |
> | [community.proxmox](https://github.com/ansible-collections/community.proxmox/releases) | 1.5.0 | Ansible collection |

## Executive Summary

This document analyzes approaches to automate Proxmox VM provisioning for Talos Linux clusters, extending our GitOps workflow from "VMs ready and booted" to "bare metal/hypervisor to production cluster."

**Current Gap:** The project automates everything *after* VMs exist. Users must manually:

1. Upload Talos ISO to Proxmox
2. Create VMs with proper specifications
3. Boot VMs into Talos maintenance mode
4. Only then can `task bootstrap:talos` run

### Updated Recommendations (January 2026)

Based on the requirement to **avoid Terraform/OpenTofu state management complexity** for multi-team environments, we have evaluated stateless alternatives:

| Approach | State Mgmt | Team-Friendly | Maturity | GitOps Fit | Recommendation |
| -------- | ---------- | ------------- | -------- | ---------- | -------------- |
| **Cluster API (CAPMOX)** | K8s-native | Excellent | Medium | Excellent | **PRIMARY** |
| **Ansible + Proxmox** | Stateless | Excellent | High | Good | **SECONDARY** |
| **Crossplane + Proxmox** | K8s-native | Excellent | Low | Excellent | Future |
| **OpenTofu + bpg** | State file | Poor | High | Excellent | If state OK |
| **Sidero Omni** | SaaS | Good | High | Good | Commercial |

**Primary Recommendation:** **Cluster API with CAPMOX** - Uses Kubernetes as the state store (no separate state files), fully GitOps-native, and enables declarative VM lifecycle management.

**Secondary Recommendation:** **Ansible with community.proxmox** - Truly stateless/idempotent, simple to integrate with go-task, no external state to manage.

---

## State Management Comparison

### The Problem with Terraform/OpenTofu State

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TERRAFORM STATE MANAGEMENT CHALLENGES                    │
└─────────────────────────────────────────────────────────────────────────────┘

  Developer A                    State File                    Developer B
       │                            │                              │
       │  tofu apply ───────────────┼──────────────── tofu apply   │
       │                            │                              │
       │                     ┌──────▼──────┐                       │
       │                     │   LOCKED    │◄──────────────────────│
       │                     │   (wait)    │                       │
       │                     └─────────────┘                       │
       │                            │                              │
       ▼                            ▼                              ▼
  ┌─────────┐              ┌───────────────┐              ┌─────────┐
  │ SUCCESS │              │ STATE DRIFT?  │              │ BLOCKED │
  └─────────┘              │ CORRUPTION?   │              └─────────┘
                           │ MERGE CONFLICT│
                           └───────────────┘

  Challenges:
  • State locking for concurrent access
  • Remote state backend required (S3, GCS, etc.)
  • State drift detection and remediation
  • State file corruption recovery
  • Secrets in state files (security risk)
```

### Stateless Alternatives

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         STATELESS APPROACHES                                │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
  │   CLUSTER API       │     │      ANSIBLE        │     │     CROSSPLANE      │
  ├─────────────────────┤     ├─────────────────────┤     ├─────────────────────┤
  │ State: Kubernetes   │     │ State: NONE         │     │ State: Kubernetes   │
  │        etcd         │     │ (idempotent tasks)  │     │        etcd         │
  │                     │     │                     │     │                     │
  │ GitOps: Native      │     │ GitOps: Via CI/CD   │     │ GitOps: Native      │
  │ (K8s manifests)     │     │ (run playbooks)     │     │ (K8s manifests)     │
  │                     │     │                     │     │                     │
  │ Multi-team: ✓       │     │ Multi-team: ✓       │     │ Multi-team: ✓       │
  │ (RBAC + namespaces) │     │ (no locks needed)   │     │ (RBAC + namespaces) │
  └─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

---

## Option 1: Cluster API with CAPMOX (PRIMARY RECOMMENDATION)

### Why Cluster API?

Cluster API (CAPI) is a Kubernetes-native approach to infrastructure management. Instead of Terraform state files, **Kubernetes etcd IS the state store**.

**Key Benefits:**

- **No separate state files** - Kubernetes manages desired vs actual state
- **GitOps-native** - Cluster definitions are YAML manifests
- **Multi-team friendly** - Uses Kubernetes RBAC and namespaces
- **Self-healing** - Automatically replaces failed VMs
- **Declarative scaling** - Change replica count, apply, done

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CLUSTER API ARCHITECTURE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

                         Git Repository
                              │
                              ▼
                    ┌─────────────────┐
                    │  Flux / ArgoCD  │
                    │   (GitOps)      │
                    └────────┬────────┘
                             │ sync
                             ▼
              ┌────────────────────────────────┐
              │       MANAGEMENT CLUSTER       │
              │         (K3s/Kind)             │
              ├────────────────────────────────┤
              │  • Cluster API Operator        │
              │  • CAPMOX (Proxmox Provider)   │
              │  • CABPT (Talos Bootstrap)     │
              │  • CACPPT (Talos Control Plane)│
              └──────────────┬─────────────────┘
                             │ reconcile
                             ▼
              ┌──────────────────────────────┐
              │        PROXMOX VE            │
              │  ┌────┐ ┌────┐ ┌────┐        │
              │  │VM1 │ │VM2 │ │VM3 │        │
              │  └────┘ └────┘ └────┘        │
              └──────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │     WORKLOAD CLUSTER         │
              │   (Talos Linux + K8s)        │
              └──────────────────────────────┘
```

### CAPMOX Providers

Two Proxmox providers exist for Cluster API:

| Provider | Maintainer | Status | Notes |
| -------- | ---------- | ------ | ----- |
| [IONOS CAPMOX](https://github.com/ionos-cloud/cluster-api-provider-proxmox) | IONOS Cloud | Active | v0.7.5, CAPI 1.9, K8s 1.31+ |
| [k8s-proxmox CAPPX](https://github.com/k8s-proxmox/cluster-api-provider-proxmox) | Community | Active | Claims longer maturity |

### Talos Integration

Use the Talos-specific CAPI providers:

- **CABPT** (Cluster API Bootstrap Provider Talos) - Generates Talos machine configs
- **CACPPT** (Cluster API Control Plane Provider Talos) - Manages control plane lifecycle

### Implementation Requirements

1. **Management Cluster** - A small K3s or Kind cluster to run CAPI controllers
2. **Proxmox VM Template** - Talos nocloud image as Proxmox template
3. **CAPI Components**:

   ```bash
   clusterctl init \
     --infrastructure proxmox \
     --bootstrap talos \
     --control-plane talos
   ```

### Example Cluster Definition

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: matherlynet-cluster
  namespace: clusters
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["10.42.0.0/16"]
    services:
      cidrBlocks: ["10.43.0.0/16"]
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1alpha3
    kind: TalosControlPlane
    name: matherlynet-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
    kind: ProxmoxCluster
    name: matherlynet-proxmox
---
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: ProxmoxCluster
metadata:
  name: matherlynet-proxmox
  namespace: clusters
spec:
  controlPlaneEndpoint:
    host: 192.168.22.100
    port: 6443
  serverRef:
    endpoint: https://proxmox.local:8006
    secretRef:
      name: proxmox-credentials
---
apiVersion: controlplane.cluster.x-k8s.io/v1alpha3
kind: TalosControlPlane
metadata:
  name: matherlynet-control-plane
  namespace: clusters
spec:
  replicas: 3
  version: v1.35.0
  infrastructureTemplate:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
    kind: ProxmoxMachineTemplate
    name: control-plane-template
  controlPlaneConfig:
    controlplane:
      generateType: controlplane
---
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: ProxmoxMachineTemplate
metadata:
  name: control-plane-template
  namespace: clusters
spec:
  template:
    spec:
      sourceNode: pve
      templateID: 9000
      format: raw
      full: true
      pool: kubernetes
      numCores: 4
      numSockets: 1
      memoryMiB: 8192
      disks:
        - size: 100Gi
          storage: local-zfs
      network:
        default:
          bridge: vmbr0
          model: virtio
```

### Pros and Cons

**Pros:**

- No external state files
- True GitOps workflow
- Self-healing infrastructure
- Native Kubernetes tooling
- Multi-team via RBAC

**Cons:**

- Requires management cluster (chicken-egg problem for first cluster)
- More complex initial setup
- CAPMOX still v1alpha1 (API may change)
- Talos nocloud image required (not metal)

### Solving the Management Cluster Chicken-Egg Problem

The management cluster can be bootstrapped using several strategies:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT CLUSTER BOOTSTRAP STRATEGIES                  │
└─────────────────────────────────────────────────────────────────────────────┘

  STRATEGY 1: K3s on Proxmox VM          STRATEGY 2: Bootstrap & Pivot
  ─────────────────────────────          ─────────────────────────────
  ┌─────────────┐                        ┌─────────────┐
  │ Ansible     │                        │ Kind/K3d    │
  │ creates K3s │                        │ on laptop   │
  │ VM          │                        └──────┬──────┘
  └──────┬──────┘                               │
         │                                      │ Install CAPI
         │ Install CAPI                         ▼
         ▼                               ┌─────────────┐
  ┌─────────────┐                        │ Create      │
  │ CAPI        │                        │ workload    │
  │ controllers │                        │ cluster     │
  │ running     │                        └──────┬──────┘
  └──────┬──────┘                               │
         │                                      │ clusterctl move
         │ Create workload                      ▼
         ▼                               ┌─────────────┐
  ┌─────────────┐                        │ CAPI now    │
  │ Talos       │                        │ runs on     │
  │ workload    │                        │ workload    │
  │ cluster     │                        │ cluster     │
  └─────────────┘                        └─────────────┘
```

**Recommended: K3s Management Cluster on Proxmox**

1. **Use Ansible to create a single K3s VM:**

   ```yaml
   # infrastructure/ansible/playbooks/mgmt-cluster.yaml
   - name: Create K3s management cluster VM
     community.proxmox.proxmox_kvm:
       name: "k8s-mgmt"
       cores: 2
       memory: 4096
       # ... cloud image with K3s
   ```

2. **Install CAPI components:**

   ```bash
   clusterctl init \
     --infrastructure proxmox \
     --bootstrap talos \
     --control-plane talos
   ```

3. **Create workload clusters via GitOps:**
   - Flux syncs Cluster manifests
   - CAPI creates Talos VMs automatically

4. **(Optional) Pivot CAPI to workload cluster:**

   ```bash
   clusterctl move --to-kubeconfig workload-kubeconfig
   ```

---

## Option 2: Ansible with community.proxmox (SECONDARY RECOMMENDATION)

### Why Ansible?

Ansible is **truly stateless** - it determines current state at runtime and applies changes idempotently. No state files, no locking, no remote backends.

**Key Benefits:**

- **Zero state management** - Each run checks current state
- **Idempotent by design** - Safe to run repeatedly
- **Simple integration** - Works naturally with go-task
- **Familiar tooling** - Widely known in DevOps
- **No management cluster** - Runs from any machine

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ANSIBLE WORKFLOW                                       │
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

### Module Migration Notice

> **Important:** The `community.general.proxmox_kvm` module has been deprecated and moved to `community.proxmox.proxmox_kvm` (v1.5.0+). Update to the new collection before version 15.0.0 of community.general: `ansible-galaxy collection install community.proxmox --upgrade`

### Example Playbook

**File: `infrastructure/ansible/playbooks/provision-vms.yaml`**

```yaml
---
- name: Provision Talos VMs on Proxmox
  hosts: localhost
  gather_facts: false
  vars_files:
    - "{{ playbook_dir }}/../../../nodes.yaml"
  vars:
    proxmox_host: "{{ lookup('env', 'PROXMOX_HOST') }}"
    proxmox_token_id: "{{ lookup('env', 'PROXMOX_TOKEN_ID') }}"
    proxmox_token_secret: "{{ lookup('env', 'PROXMOX_TOKEN_SECRET') }}"
    proxmox_node: "pve"
    talos_template: "talos-1.12.0"
    storage_pool: "local-zfs"

  tasks:
    - name: Ensure Talos template exists
      community.proxmox.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        node: "{{ proxmox_node }}"
        name: "{{ talos_template }}"
        state: current
      register: template_check
      failed_when: template_check.vmid is not defined

    - name: Clone and configure VMs
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
          net0: "virtio,bridge=vmbr0,macaddr={{ item.mac_addr }}"
        scsihw: virtio-scsi-pci
        scsi:
          scsi0: "{{ storage_pool }}:{{ item.disk_size | default(100) }}"
        boot: order=scsi0
        bios: ovmf
        efidisk0:
          storage: "{{ storage_pool }}"
          efitype: 4m
        agent: true
        tags:
          - talos
          - "{{ 'control-plane' if item.controller else 'worker' }}"
          - kubernetes
        state: present
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"

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

    - name: Wait for VMs to be reachable
      ansible.builtin.wait_for:
        host: "{{ item.address }}"
        port: 50000  # Talos API port
        timeout: 300
      loop: "{{ nodes }}"
      loop_control:
        label: "{{ item.name }}"
```

### Go-Task Integration

**File: `.taskfiles/infrastructure/Taskfile.yaml`**

```yaml
---
version: "3"

vars:
  ANSIBLE_DIR: "{{.ROOT_DIR}}/infrastructure/ansible"

tasks:
  provision:
    desc: Provision Talos VMs on Proxmox (stateless/idempotent)
    dir: "{{.ANSIBLE_DIR}}"
    cmd: ansible-playbook playbooks/provision-vms.yaml
    preconditions:
      - test -f {{.ROOT_DIR}}/nodes.yaml
      - which ansible-playbook
    env:
      PROXMOX_HOST: "{{.PROXMOX_HOST}}"
      PROXMOX_TOKEN_ID: "{{.PROXMOX_TOKEN_ID}}"
      PROXMOX_TOKEN_SECRET: "{{.PROXMOX_TOKEN_SECRET}}"

  destroy:
    desc: Destroy all Talos VMs
    dir: "{{.ANSIBLE_DIR}}"
    prompt: This will DESTROY all VMs. Are you absolutely sure?
    cmd: ansible-playbook playbooks/destroy-vms.yaml

  status:
    desc: Show VM status
    dir: "{{.ANSIBLE_DIR}}"
    cmd: ansible-playbook playbooks/status-vms.yaml
```

### Pros and Cons

**Pros:**

- Truly stateless - no state files ever
- Idempotent by design
- Simple to understand and debug
- Direct go-task integration
- No management cluster needed
- Works with existing nodes.yaml

**Cons:**

- Not declarative like Kubernetes (imperative playbooks)
- No built-in drift detection (only on run)
- Talos doesn't support SSH (limited post-boot config)
- Manual GitOps integration (via CI/CD)

---

## Option 3: Crossplane with Proxmox Provider (FUTURE)

### Overview

Crossplane is a Kubernetes-native IaC framework that manages infrastructure via CRDs. Like Cluster API, it uses Kubernetes etcd as the state store.

### Available Providers

| Provider | Source | Status |
| -------- | ------ | ------ |
| [provider-proxmox-bpg](https://github.com/valkiriaaquatica/provider-proxmox-bpg) | Community | Early development |
| [provider-proxmoxve](https://github.com/dougsong/provider-proxmoxve) | Community | Experimental |

### Why Not Now?

- Proxmox providers are immature (v0.x, limited features)
- Based on Terraform providers (inherits some limitations)
- Less Talos-specific integration than Cluster API
- Requires management cluster like CAPI

### Future Consideration

When Crossplane Proxmox providers mature, they could offer:

- Kubernetes-native VM management without CAPI complexity
- Integration with broader Crossplane ecosystem
- Simpler composition patterns

---

## Option 4: Kubernetes Operators for Proxmox

### Kubemox

[Kubemox](https://github.com/alperencelik/kubemox) is a Kubernetes operator for managing Proxmox resources.

**Status:** Under active development, not production-ready

- No CRD versioning stability
- Limited feature coverage
- Missing cloud-init support

### CRASH-Tech Proxmox Operator

[proxmox-operator](https://github.com/CRASH-Tech/proxmox-operator) - Another community operator.

**Status:** Early development, used with Sidero

### Recommendation

These operators are not mature enough for production use. Monitor their development for future consideration.

---

## Comparison Matrix

| Criteria | Cluster API | Ansible | OpenTofu | Crossplane |
| -------- | ----------- | ------- | -------- | ---------- |
| **State Management** | K8s etcd | None | File-based | K8s etcd |
| **Multi-Team** | RBAC + NS | No locks | State locking | RBAC + NS |
| **GitOps Native** | Yes | Via CI/CD | Via CI/CD | Yes |
| **Maturity** | Medium | High | High | Low |
| **Complexity** | High | Low | Medium | High |
| **Mgmt Cluster** | Required | No | No | Required |
| **Talos Support** | CABPT/CACPPT | Limited | Full | Limited |
| **Self-Healing** | Yes | No | No | Yes |
| **Learning Curve** | Steep | Low | Medium | Steep |

---

## Implementation Recommendation

### For This Project: Ansible (Short-Term) → Cluster API (Long-Term)

Given the requirements:

1. **Multi-team environment** - No state locking issues
2. **GitOps alignment** - Declarative, version-controlled
3. **Minimize complexity** - Pragmatic approach

### Phase 1: Ansible (Immediate)

Start with Ansible for VM provisioning:

- Zero state management
- Simple go-task integration
- Works with existing nodes.yaml
- Low learning curve
- Production-ready today

### Phase 2: Cluster API (Future)

Migrate to Cluster API when:

- Management cluster is already running
- Self-healing/scaling is needed
- Multiple clusters are managed
- CAPMOX reaches v1beta1 stability

### Migration Path

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MIGRATION PATH                                      │
└─────────────────────────────────────────────────────────────────────────────┘

  PHASE 1 (Now)                 PHASE 2 (Future)
  ┌─────────────────┐           ┌─────────────────────────────────────────────┐
  │     Ansible     │           │            Cluster API                      │
  │  + Packer       │           │  + CAPMOX + CABPT + CACPPT                  │
  ├─────────────────┤           ├─────────────────────────────────────────────┤
  │ • Provision VMs │ ────────▶ │ • Mgmt cluster runs CAPI                    │
  │ • Stateless     │           │ • GitOps via Flux/ArgoCD                    │
  │ • go-task       │           │ • Self-healing + scaling                    │
  │ • Low complexity│           │ • Multi-cluster management                  │
  └─────────────────┘           └─────────────────────────────────────────────┘
         │                                    │
         │                                    │
         ▼                                    ▼
  task bootstrap:talos             Automatic Talos provisioning
  task bootstrap:apps              via CAPI reconciliation
```

---

## Current State Analysis

### What Works Today

```
                    ┌─────────────────────────────────────────┐
                    │           CURRENT AUTOMATION            │
                    └─────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┴──────────────────────────────┐
        ▼                                                             ▼
┌───────────────┐                                              ┌───────────────┐
│    MANUAL     │                                              │   AUTOMATED   │
│   (The Gap)   │                                              │  (GitOps)     │
├───────────────┤                                              ├───────────────┤
│ • Create VMs  │     task bootstrap:talos                     │ • Talos config│
│ • Upload ISO  │ ─────────────────────────────────────────▶   │ • K8s setup   │
│ • Boot VMs    │                                              │ • Flux sync   │
│ • Network cfg │     task bootstrap:apps                      │ • Apps deploy │
└───────────────┘ ─────────────────────────────────────────▶   └───────────────┘
```

### The Manual Steps from QUICKSTART.md (Line 183)

> "Ensure nodes are booted from Talos ISO, then..."

This requires:

1. **Download Talos ISO** from factory.talos.dev with correct schematic
2. **Upload to Proxmox** storage (local or shared)
3. **Create VMs** with specific hardware configuration:
   - CPU cores, RAM, disk size
   - Network bridge and VLAN
   - Boot order and EFI settings
4. **Start VMs** and wait for maintenance mode
5. **Note IP addresses** for `nodes.yaml`

---

## Recommended Solution: OpenTofu + bpg/proxmox + Packer

### Why This Stack?

1. **bpg/proxmox provider** is actively maintained (30+ releases/year) vs Telmate (largely unmaintained)
2. **OpenTofu** is the open-source Terraform fork, aligning with CNCF ecosystem
3. **Packer** creates reusable Talos templates with extensions pre-baked
4. **go-task integration** is straightforward via Taskfile includes

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PROPOSED AUTOMATION FLOW                             │
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
    (K8s manifests)   (Talos configs)      (NEW: OpenTofu)
                                                  │
                                                  ▼
              ┌───────────────────────────────────┐
              │      task infrastructure:plan     │
              │         (tofu plan)               │
              └───────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────────┐
              │     task infrastructure:apply     │
              │        (tofu apply)               │
              │   Creates VMs, waits for boot     │
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

## Implementation Components

### 1. Packer: Talos Image Template

Packer creates a Proxmox VM template with Talos pre-installed, avoiding ISO upload on each VM creation.

#### Why Packer?

- **One-time image build** → reuse for all VMs
- **Extensions pre-baked** (qemu-guest-agent, iscsi-tools, etc.)
- **Version controlled** schematic configuration
- **Faster VM creation** (clone vs ISO install)

#### Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PACKER BUILD PROCESS                              │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │   Arch ISO   │────▶│  Boot VM     │────▶│ Download &   │────▶│  Convert to  │
  │  (minimal)   │     │  (Packer)    │     │ dd Talos img │     │  Template    │
  └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                                   │
                                    ┌──────────────┴──────────────┐
                                    │   Talos Image Factory API   │
                                    │   with schematics:          │
                                    │   - qemu-guest-agent        │
                                    │   - iscsi-tools             │
                                    │   - zfs (for ZFS workloads) │
                                    └─────────────────────────────┘
```

#### Example Packer Configuration

**File: `infrastructure/packer/talos.pkr.hcl`**

```hcl
packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type = string
}

variable "proxmox_token_id" {
  type = string
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "talos_version" {
  type    = string
  default = "1.12.0"
}

variable "talos_schematic_id" {
  type        = string
  description = "Schematic ID from factory.talos.dev with extensions"
}

variable "proxmox_node" {
  type = string
}

variable "proxmox_storage" {
  type    = string
  default = "local-zfs"
}

source "proxmox-iso" "talos" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # Use Arch Linux as bootstrap ISO
  iso_file    = "local:iso/archlinux-x86_64.iso"
  unmount_iso = true

  # VM Configuration
  vm_id                = 9000
  vm_name              = "talos-${var.talos_version}"
  template_name        = "talos-${var.talos_version}"
  template_description = "Talos Linux ${var.talos_version} with qemu-guest-agent"

  cpu_type = "host"
  cores    = 2
  memory   = 4096
  os       = "l26"

  scsi_controller = "virtio-scsi-pci"

  disks {
    disk_size    = "20G"
    storage_pool = var.proxmox_storage
    type         = "scsi"
    format       = "raw"
    discard      = true
    ssd          = true
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  qemu_agent = true

  # UEFI/Secureboot configuration
  bios = "ovmf"

  efi_config {
    efi_storage_pool = var.proxmox_storage
    efi_type         = "4m"
  }

  # Boot commands to download and install Talos (secureboot variant)
  boot_wait = "15s"
  boot_command = [
    "<enter><wait30s>",
    "curl -LO https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/nocloud-amd64-secureboot.raw.xz<enter><wait10s>",
    "xz -d nocloud-amd64-secureboot.raw.xz<enter><wait30s>",
    "dd if=nocloud-amd64-secureboot.raw of=/dev/sda bs=4M status=progress<enter><wait60s>",
    "poweroff<enter>"
  ]

  ssh_timeout = "1s"  # Not actually using SSH, just need a timeout
}

build {
  sources = ["source.proxmox-iso.talos"]
}
```

#### Schematic Configuration

This project uses a pre-generated schematic ID with the following extensions:

**Schematic ID:** `29d123fd0e746fccd5ff52d37c0cdbd2d653e10ae29c39276b6edb9ffbd56cf4`

**File: `infrastructure/packer/talos-schematic.yaml`**

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/qemu-guest-agent
      - siderolabs/iscsi-tools
      # Add ZFS if you need in-cluster ZFS
      # - siderolabs/zfs
```

**Image URL Pattern:**

```
https://factory.talos.dev/image/29d123fd0e746fccd5ff52d37c0cdbd2d653e10ae29c39276b6edb9ffbd56cf4/v1.12.0/nocloud-amd64-secureboot.iso
```

**To generate a new schematic ID:**

```bash
curl -s -X POST https://factory.talos.dev/schematics \
  -H "Content-Type: application/json" \
  -d "$(yq -o=json infrastructure/packer/talos-schematic.yaml)"
```

> **Note:** The nocloud-secureboot image is verified working with Proxmox VE 9.x cloud-init. Use OVMF (UEFI) BIOS setting for secureboot support.

### 2. OpenTofu: VM Provisioning

OpenTofu provisions VMs from the Packer template with node-specific configurations.

#### Provider Configuration

**File: `infrastructure/tofu/providers.tf`**

```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint

  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent    = true
    username = "root"
  }
}

provider "talos" {}
```

#### Variables from nodes.yaml

**File: `infrastructure/tofu/variables.tf`**

```hcl
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint URL"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in format user@realm!tokenid=secret"
}

variable "proxmox_insecure" {
  type        = bool
  default     = false
  description = "Skip TLS verification"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to deploy VMs on"
}

variable "talos_template" {
  type        = string
  description = "Name of the Talos VM template"
  default     = "talos-1.12.0"
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for VM disks"
  default     = "local-zfs"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge for VMs"
  default     = "vmbr0"
}

variable "nodes" {
  type = list(object({
    name       = string
    address    = string
    controller = bool
    disk       = string
    mac_addr   = string
    cores      = optional(number, 4)
    memory     = optional(number, 8192)
    disk_size  = optional(number, 100)
  }))
  description = "Node definitions matching nodes.yaml schema"
}
```

#### VM Resource Definition

**File: `infrastructure/tofu/nodes.tf`**

```hcl
resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each = { for node in var.nodes : node.name => node }

  name        = each.value.name
  description = "Talos Linux node - ${each.value.controller ? "Control Plane" : "Worker"}"
  tags        = each.value.controller ? ["talos", "control-plane", "kubernetes"] : ["talos", "worker", "kubernetes"]

  node_name = var.proxmox_node
  vm_id     = 100 + index(var.nodes, each.value)

  # Clone from Packer template
  clone {
    vm_id = proxmox_virtual_environment_vm.talos_template.vm_id
    full  = true
  }

  # Hardware configuration
  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Boot disk
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    size         = each.value.disk_size
    discard      = "on"
    ssd          = true
    file_format  = "raw"
  }

  # Network with static MAC for DHCP reservations
  network_device {
    bridge      = var.network_bridge
    mac_address = each.value.mac_addr
    model       = "virtio"
  }

  # Enable QEMU agent
  agent {
    enabled = true
  }

  # EFI boot
  bios = "ovmf"

  efi_disk {
    datastore_id = var.storage_pool
    type         = "4m"
  }

  # Start on create
  started = true

  # Wait for cloud-init / QEMU agent
  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.address}/24"
        gateway = var.gateway_address
      }
    }

    dns {
      servers = var.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [
      initialization,  # Talos handles config after first boot
    ]
  }
}

# Output IP addresses for verification
output "node_ips" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.talos_node :
    name => vm.ipv4_addresses[1][0]  # First IP on first non-loopback interface
  }
}
```

### 3. Integration with nodes.yaml

Generate OpenTofu variables from existing `nodes.yaml`:

**File: `infrastructure/tofu/terraform.tfvars.j2`** (Jinja2 template)

```hcl
#| Generated by makejinja - DO NOT EDIT #|

proxmox_endpoint  = "#{ proxmox_endpoint }#"
proxmox_node      = "#{ proxmox_node }#"
storage_pool      = "#{ proxmox_storage | default('local-zfs') }#"
network_bridge    = "#{ proxmox_bridge | default('vmbr0') }#"
gateway_address   = "#{ node_gateway }#"
dns_servers       = [#% for dns in dns_servers %#"#{ dns }#"#% if not loop.last %#, #% endif %##% endfor %#]

nodes = [
#% for node in nodes %#
  {
    name       = "#{ node.name }#"
    address    = "#{ node.address }#"
    controller = #{ node.controller | default(false) | lower }#
    disk       = "#{ node.disk }#"
    mac_addr   = "#{ node.mac_addr }#"
    cores      = #{ node.cores | default(4) }#
    memory     = #{ node.memory | default(8192) }#
    disk_size  = #{ node.disk_size | default(100) }#
  },
#% endfor %#
]
```

---

## Go-Task Integration

### New Taskfile Include

**File: `.taskfiles/infrastructure/Taskfile.yaml`**

```yaml
---
version: "3"

vars:
  INFRA_DIR: "{{.ROOT_DIR}}/infrastructure"
  TOFU_DIR: "{{.INFRA_DIR}}/tofu"
  PACKER_DIR: "{{.INFRA_DIR}}/packer"

tasks:
  # ─────────────────────────────────────────────────────────────────────────
  # Packer Tasks
  # ─────────────────────────────────────────────────────────────────────────

  packer:init:
    desc: Initialize Packer plugins
    dir: "{{.PACKER_DIR}}"
    cmd: packer init .
    preconditions:
      - which packer

  packer:build:
    desc: Build Talos VM template in Proxmox
    dir: "{{.PACKER_DIR}}"
    cmds:
      - task: packer:init
      - packer build -var-file=variables.pkrvars.hcl .
    preconditions:
      - test -f {{.PACKER_DIR}}/talos.pkr.hcl
      - test -f {{.PACKER_DIR}}/variables.pkrvars.hcl
      - which packer

  packer:validate:
    desc: Validate Packer configuration
    dir: "{{.PACKER_DIR}}"
    cmd: packer validate -var-file=variables.pkrvars.hcl .
    preconditions:
      - which packer

  # ─────────────────────────────────────────────────────────────────────────
  # OpenTofu Tasks
  # ─────────────────────────────────────────────────────────────────────────

  tofu:init:
    desc: Initialize OpenTofu
    dir: "{{.TOFU_DIR}}"
    cmd: tofu init
    preconditions:
      - which tofu

  plan:
    desc: Plan infrastructure changes
    dir: "{{.TOFU_DIR}}"
    cmds:
      - task: tofu:init
      - tofu plan -out=tfplan
    preconditions:
      - test -f {{.TOFU_DIR}}/terraform.tfvars
      - which tofu

  apply:
    desc: Apply infrastructure changes (creates/updates VMs)
    dir: "{{.TOFU_DIR}}"
    prompt: This will create/modify VMs in Proxmox. Continue?
    cmds:
      - task: tofu:init
      - tofu apply -auto-approve tfplan
    preconditions:
      - test -f {{.TOFU_DIR}}/tfplan
      - which tofu

  destroy:
    desc: Destroy all infrastructure (VMs)
    dir: "{{.TOFU_DIR}}"
    prompt: This will DESTROY all VMs. Are you absolutely sure?
    cmd: tofu destroy -auto-approve
    preconditions:
      - which tofu

  show:
    desc: Show current infrastructure state
    dir: "{{.TOFU_DIR}}"
    cmd: tofu show
    preconditions:
      - which tofu

  output:
    desc: Show infrastructure outputs (IPs, etc.)
    dir: "{{.TOFU_DIR}}"
    cmd: tofu output -json
    preconditions:
      - which tofu

  # ─────────────────────────────────────────────────────────────────────────
  # Combined Workflows
  # ─────────────────────────────────────────────────────────────────────────

  provision:
    desc: Full VM provisioning workflow (plan + apply)
    cmds:
      - task: plan
      - task: apply
    preconditions:
      - test -f {{.TOFU_DIR}}/terraform.tfvars

  wait-for-nodes:
    desc: Wait for all nodes to be reachable
    cmd: |
      for ip in $(tofu -chdir={{.TOFU_DIR}} output -json node_ips | jq -r '.[]'); do
        echo "Waiting for $ip..."
        until talosctl --nodes $ip get machineconfig --insecure 2>/dev/null; do
          sleep 5
        done
        echo "$ip is ready!"
      done
    preconditions:
      - which talosctl jq tofu
```

### Update Main Taskfile

Add to `Taskfile.yaml`:

```yaml
includes:
  bootstrap: .taskfiles/bootstrap
  talos: .taskfiles/talos
  template: .taskfiles/template
  infrastructure: .taskfiles/infrastructure  # NEW
```

### New Combined Bootstrap Task

**File: `.taskfiles/bootstrap/Taskfile.yaml`** (addition)

```yaml
  full:
    desc: Complete cluster bootstrap (infrastructure + Talos + apps)
    cmds:
      - task: infrastructure:provision
      - task: infrastructure:wait-for-nodes
      - task: talos
      - task: apps
    preconditions:
      - test -f {{.ROOT_DIR}}/infrastructure/tofu/terraform.tfvars
      - test -f {{.TALOS_DIR}}/talconfig.yaml
```

---

## Tool Requirements

### .mise.toml Additions

```toml
# Add to [tools] section
"aqua:opentofu/opentofu" = "1.11.2"
"aqua:hashicorp/packer" = "1.12.0"
"pipx:ansible" = "latest"
```

> **Note:** OpenTofu 1.11.x introduces ephemeral resources for handling confidential data without persisting to state - useful for Proxmox API tokens.

### Proxmox API Token Setup

Create an API token in Proxmox with appropriate permissions:

```bash
# On Proxmox host
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role PVEAdmin
pveum user token add terraform@pve tofu -privsep 0
```

Store credentials securely using SOPS encryption (recommended) or environment variables.

### Option A: SOPS-Encrypted Credentials (Recommended)

Integrate with the project's existing SOPS/Age encryption pattern:

**File: `infrastructure/secrets.sops.yaml`**

```yaml
proxmox_api_token: ENC[AES256_GCM,data:...,type:str]
proxmox_endpoint: ENC[AES256_GCM,data:...,type:str]
```

**Create and encrypt:**

```bash
# Create plaintext file
cat > infrastructure/secrets.yaml <<EOF
proxmox_api_token: "terraform@pve!tofu=your-secret-token"
proxmox_endpoint: "https://192.168.22.10:8006"
EOF

# Encrypt with SOPS
sops --encrypt --age $(cat age.key | grep -o 'age1.*') \
  infrastructure/secrets.yaml > infrastructure/secrets.sops.yaml

# Remove plaintext
rm infrastructure/secrets.yaml
```

**Usage in Taskfile:**

```yaml
tasks:
  provision:
    desc: Provision VMs with SOPS-decrypted credentials
    cmds:
      - |
        export TF_VAR_proxmox_api_token=$(sops -d infrastructure/secrets.sops.yaml | yq '.proxmox_api_token')
        export TF_VAR_proxmox_endpoint=$(sops -d infrastructure/secrets.sops.yaml | yq '.proxmox_endpoint')
        tofu apply
```

### Option B: Environment Variables (Alternative)

**File: `infrastructure/tofu/.env` (gitignored)**

```bash
export TF_VAR_proxmox_api_token="terraform@pve!tofu=your-secret-token"
```

### Security Best Practices

| Practice | Description |
| ---------- | ------------- |
| **Minimal Privileges** | Create dedicated API token with only required permissions |
| **Privilege Separation** | Use `privsep=1` (default) - token permissions are subset of user |
| **Token Expiration** | Set expiration date for API tokens when possible |
| **Audit Logging** | Enable Proxmox audit logging for API access |
| **Network Isolation** | Restrict API access to management network/VLAN |

**Recommended ACL Setup:**

```bash
# Create dedicated user and role with minimal permissions
pveum user add automation@pve
pveum role add TalosProvisioner -privs "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory VM.Config.Network VM.Config.Options VM.PowerMgmt Datastore.AllocateSpace Datastore.AllocateTemplate SDN.Use"
pveum aclmod /vms -user automation@pve -role TalosProvisioner
pveum aclmod /storage/local-zfs -user automation@pve -role TalosProvisioner
pveum user token add automation@pve talos -privsep 1
```

---

## IP Assignment Strategy

For this project, we use **static IP assignment via cloud-init** combined with **MAC address-based DHCP reservations** as a fallback.

### Approach: Static IPs via Cloud-Init

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        IP ASSIGNMENT STRATEGY                               │
└─────────────────────────────────────────────────────────────────────────────┘

  nodes.yaml                    VM Creation                   Talos Boot
      │                              │                            │
      │ Static IP:                   │ cloud-init                 │ IP Applied
      │ 192.168.22.10                │ ipconfig0                  │ via nocloud
      │ MAC: AA:BB:CC:DD:EE:01       │                            │
      ▼                              ▼                            ▼
  ┌─────────┐              ┌─────────────────┐           ┌─────────────────┐
  │ Desired │──────────────│ Proxmox creates │───────────│ Talos boots     │
  │  State  │              │ VM with cloud-  │           │ with static IP  │
  └─────────┘              │ init IP config  │           └─────────────────┘
                           └─────────────────┘
                                    │
                                    ▼
                           ┌─────────────────┐
                           │ QEMU Guest Agent│
                           │ reports IP to   │
                           │ Proxmox UI      │
                           └─────────────────┘
```

### Why Static IPs (Not DHCP)?

| Consideration | Static IP | DHCP Reservation |
| --------------- | ----------- | ------------------ |
| **Reproducibility** | Defined in nodes.yaml | Requires router config |
| **GitOps Friendly** | Yes - in version control | No - router state |
| **Firewall Rules** | Predictable | Predictable (with reservation) |
| **Talos Requirement** | Works with nocloud | Requires DHCP server |
| **Multi-team** | Self-contained | Requires router access |

### Implementation

Static IPs are configured in the Proxmox VM's cloud-init settings:

```hcl
# In OpenTofu nodes.tf
initialization {
  ip_config {
    ipv4 {
      address = "${each.value.address}/24"
      gateway = var.gateway_address
    }
  }
  dns {
    servers = var.dns_servers
  }
}
```

```yaml
# In Ansible playbook
community.proxmox.proxmox_kvm:
  ipconfig0: "ip={{ item.address }}/24,gw={{ gateway_address }}"
```

### MAC Address Strategy

Static MAC addresses enable:

1. **Consistent VM identification** across recreations
2. **DHCP reservation fallback** if cloud-init fails
3. **Network policy enforcement** based on MAC

Define MAC addresses in `nodes.yaml`:

```yaml
nodes:
  - name: k8s-cp-1
    address: "192.168.22.10"
    mac_addr: "BC:24:11:00:01:01"
    # ...
```

---

## cluster.yaml Schema Additions

Add new variables for Proxmox configuration:

```yaml
# =============================================================================
# Proxmox Configuration (Infrastructure Automation)
# =============================================================================
# These settings enable OpenTofu/Terraform to provision VMs on Proxmox.
# See: docs/research/proxmox-vm-automation.md

# Proxmox API endpoint (e.g., https://proxmox.local:8006)
proxmox_endpoint: "https://192.168.1.10:8006"

# Proxmox node name where VMs will be created
proxmox_node: "pve"

# Storage pool for VM disks (must support ZFS or raw images)
proxmox_storage: "local-zfs"

# Network bridge for VMs
proxmox_bridge: "vmbr0"

# Talos template name (created by Packer)
talos_template: "talos-1.12.0"
```

---

## Alternative Approaches

### Cluster API (CAPMOX/CAPPX)

**When to Consider:**

- Already running a management cluster
- Need Kubernetes-native VM lifecycle
- Want to use GitOps for infrastructure (ArgoCD/Flux managing VMs)

**Providers:**

- [IONOS CAPMOX](https://github.com/ionos-cloud/cluster-api-provider-proxmox) - More active development, v0.7.x supports CAPI 1.9
- [k8s-proxmox CAPPX](https://github.com/k8s-proxmox/cluster-api-provider-proxmox) - Claims longer maturity

**Talos Integration:**

- Use [CABPT](https://github.com/siderolabs/cluster-api-bootstrap-provider-talos) (Talos Bootstrap Provider)
- Use [CACPPT](https://github.com/siderolabs/cluster-api-control-plane-provider-talos) (Talos Control Plane Provider)

**Challenges:**

- Requires management cluster first
- More complex setup (CRDs, controllers)
- Talos nocloud image required (not bare-metal)
- VIP handling needs Talos built-in solution

**Resources:**

- [Cluster API + Talos + Proxmox Guide](https://a-cup-of.coffee/blog/talos-capi-proxmox/)
- [talos-proxmox-kaas](https://github.com/kubebn/talos-proxmox-kaas)

### Sidero Omni

**When to Consider:**

- Want managed/SaaS experience
- Multiple clusters across locations
- Bare-metal server management with IPMI/Redfish

**Features:**

- PXE boot → Talos → Cluster in one flow
- Multi-datacenter support via SideroLink tunnel
- UI for cluster management
- GPU/accelerator support

**Limitations:**

- Commercial product (pricing tiers)
- Less control over provisioning details
- May be overkill for single-cluster homelab

**Resources:**

- [Sidero Omni](https://www.siderolabs.com/omni/)
- [Bare Metal Infrastructure Provider](https://docs.siderolabs.com/omni/omni-cluster-setup/setting-up-the-bare-metal-infrastructure-provider)

---

## Implementation Phases

### Phase 1: Foundation (Week 1)

1. **Add tools to mise**

   ```toml
   "aqua:opentofu/opentofu" = "1.11.2"
   "aqua:hashicorp/packer" = "1.12.0"
   ```

2. **Create directory structure**

   ```
   infrastructure/
   ├── packer/
   │   ├── talos.pkr.hcl
   │   ├── variables.pkrvars.hcl
   │   └── talos-schematic.yaml
   └── tofu/
       ├── providers.tf
       ├── variables.tf
       ├── nodes.tf
       └── outputs.tf
   ```

3. **Generate Talos schematic ID**

4. **Create Proxmox API token**

### Phase 2: Packer Template (Week 1-2)

1. **Download Arch Linux ISO** to Proxmox

2. **Configure and run Packer**

   ```bash
   task infrastructure:packer:build
   ```

3. **Verify template** in Proxmox UI

### Phase 3: OpenTofu Integration (Week 2)

1. **Add Jinja2 template** for tfvars generation

2. **Update makejinja.toml** to include infrastructure templates

3. **Test plan/apply cycle**

   ```bash
   task configure
   task infrastructure:plan
   task infrastructure:apply
   ```

### Phase 4: Workflow Integration (Week 2-3)

1. **Add Taskfile include**

2. **Create combined bootstrap task**

3. **Update documentation**
   - QUICKSTART.md
   - OPERATIONS.md
   - CLI_REFERENCE.md

4. **Test full workflow**

   ```bash
   task bootstrap:full
   ```

---

## Verification Checklist

```bash
# 1. Template exists in Proxmox
pvesh get /nodes/{node}/qemu --output-format yaml | grep talos

# 2. VMs created with correct specs
task infrastructure:show

# 3. VMs reachable in maintenance mode
for ip in $(task infrastructure:output | jq -r '.node_ips.value[]'); do
  talosctl --nodes $ip get machineconfig --insecure
done

# 4. Full bootstrap works
task bootstrap:full
kubectl get nodes
flux get ks -A
```

---

## QEMU Guest Agent Verification

The QEMU guest agent is **critical** for:

- Proxmox UI displaying VM IP addresses
- Terraform/Ansible detecting when VMs are ready
- Graceful VM shutdown/reboot from Proxmox

### Verification Steps

**1. Verify extension is installed on Talos nodes:**

```bash
talosctl get extensions -n <node-ip>
# Should show: siderolabs/qemu-guest-agent
```

**2. Verify QEMU agent is enabled in Proxmox VM options:**

```bash
# Via API
pvesh get /nodes/{node}/qemu/{vmid}/config | grep agent
# Should show: agent: 1

# Or check in Proxmox UI: VM → Options → QEMU Guest Agent → Enabled
```

**3. Verify agent is running and reporting:**

```bash
# Check if Proxmox can communicate with agent
pvesh get /nodes/{node}/qemu/{vmid}/agent/info
# Should return version info

# Check reported IP addresses
pvesh get /nodes/{node}/qemu/{vmid}/agent/network-get-interfaces
# Should list network interfaces with IPs
```

**4. Verify IP is visible in Proxmox UI:**

- Navigate to Datacenter → Node → VM → Summary
- IP address should be displayed under "IPs"

### Troubleshooting QEMU Agent

| Symptom | Cause | Fix |
| --------- | ------- | ----- |
| No IP in Proxmox UI | Agent not installed | Use nocloud image with qemu-guest-agent extension |
| Agent timeout errors | Agent not running | Check `talosctl get extensions` |
| Partial IP info | Network not ready | Wait for Talos to configure networking |
| "QEMU guest agent is not running" | VM option disabled | Enable in VM → Options |

### VM Hardware Requirements for QEMU Agent

Ensure VMs are created with:

```hcl
# OpenTofu
agent {
  enabled = true
}

bios = "ovmf"  # UEFI required for secureboot

efi_disk {
  datastore_id = var.storage_pool
  type         = "4m"
}
```

```yaml
# Ansible
community.proxmox.proxmox_kvm:
  agent: true
  bios: ovmf
  efidisk0:
    storage: "{{ storage_pool }}"
    efitype: 4m
```

---

## Security Considerations

1. **API Token Storage**
   - Use SOPS-encrypted file or environment variables
   - Never commit tokens to Git
   - Consider HashiCorp Vault for production

2. **Network Isolation**
   - Consider dedicated VLAN for management
   - Firewall Proxmox API access

3. **Template Security**
   - Regularly update Talos version
   - Audit schematic extensions

---

## Sources

### Primary References

- [terraform-proxmox-talos](https://github.com/rgl/terraform-proxmox-talos) - Reference implementation with bpg provider
- [proxmox-talos-opentofu](https://github.com/max-pfeiffer/proxmox-talos-opentofu) - OpenTofu + Talos + FluxCD
- [h3m](https://github.com/hiimluck3r/h3m) - Homelab with OpenTofu, Talos, FluxCD
- [bpg/proxmox provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) - Official documentation

### Tutorials & Guides

- [TechDufus - Building a Talos Kubernetes Homelab](https://techdufus.com/tech/2025/06/30/building-a-talos-kubernetes-homelab-on-proxmox-with-terraform.html) - June 2025
- [Stonegarden - Talos on Proxmox with OpenTofu](https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/) - Comprehensive guide
- [Suraj Remanan - Packer + Terraform + Talos](https://surajremanan.com/posts/automating-talos-installation-on-proxmox-with-packer-and-terraform/) - August 2025
- [JYSK Tech - Packer and Talos Image Factory](https://jysk.tech/packer-and-talos-image-factory-on-proxmox-76d95e8dc316) - February 2025

### Cluster API Resources

- [IONOS CAPMOX](https://github.com/ionos-cloud/cluster-api-provider-proxmox) - Active Proxmox CAPI provider
- [Cluster API + Talos + Proxmox](https://a-cup-of.coffee/blog/talos-capi-proxmox/) - Integration guide
- [talos-proxmox-kaas](https://github.com/kubebn/talos-proxmox-kaas) - Kubernetes-as-a-Service on Proxmox

### Provider Comparisons

- [Proxmox Forum - Best Terraform Provider](https://forum.proxmox.com/threads/best-terraform-provider.116152/) - bpg vs Telmate
- [Virtualization Howto - Best Terraform Modules 2025](https://www.virtualizationhowto.com/2025/10/best-terraform-modules-for-home-labs-in-2025/)

### Sidero/Omni

- [Sidero Labs Omni](https://www.siderolabs.com/omni/) - Commercial offering
- [Omni Infrastructure Providers](https://www.siderolabs.com/blog/introducing-omni-infrastructure-providers/)

---

## Appendix: Complete File Structure

After implementation, the project structure adds:

```
matherlynet-talos-cluster/
├── infrastructure/
│   ├── packer/
│   │   ├── talos.pkr.hcl              # Packer template definition
│   │   ├── variables.pkrvars.hcl       # Packer variables (gitignored)
│   │   ├── talos-schematic.yaml        # Talos extensions definition
│   │   └── .gitignore
│   └── tofu/
│       ├── providers.tf                # Provider configuration
│       ├── variables.tf                # Variable definitions
│       ├── nodes.tf                    # VM resources
│       ├── outputs.tf                  # Output definitions
│       ├── terraform.tfvars            # Generated by makejinja
│       ├── .terraform.lock.hcl         # Provider lock (committed)
│       ├── .terraform/                 # Provider cache (gitignored)
│       └── .gitignore
├── templates/
│   └── config/
│       └── infrastructure/
│           └── tofu/
│               └── terraform.tfvars.j2 # Template for tfvars
├── .taskfiles/
│   └── infrastructure/
│       └── Taskfile.yaml               # Infrastructure tasks
└── .mise.toml                          # Updated with tofu + packer
```
