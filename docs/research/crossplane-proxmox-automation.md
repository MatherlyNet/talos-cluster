# Crossplane + Proxmox VM Automation Research

> **Research Date:** January 2026
> **Status:** Complete - Comprehensive Analysis for Talos Linux Cluster Provisioning
> **Environment:** Proxmox VE 9.x, Talos Linux 1.12.0, Kubernetes 1.35.0
> **Crossplane Status:** CNCF Graduated (October 2025)
> **Schematic ID:** `29d123fd0e746fccd5ff52d37c0cdbd2d653e10ae29c39276b6edb9ffbd56cf4`

## Executive Summary

This document provides a comprehensive analysis of using **Crossplane with Proxmox providers** for automating VM provisioning for Talos Linux clusters. This approach was originally evaluated as a "FUTURE" option in the initial research (`proxmox-vm-automation.md`), but the ecosystem has matured significantly with Crossplane's CNCF graduation in October 2025.

### Key Findings

| Criteria | Assessment |
| -------- | ---------- |
| **State Management** | Kubernetes etcd (no separate state files) |
| **Crossplane Maturity** | Very High - CNCF Graduated, 100M+ downloads |
| **Proxmox Provider Maturity** | Low-Medium - v1.0.0 released, community maintained |
| **Talos Integration** | Indirect - Requires management cluster first |
| **GitOps Compatibility** | Excellent - Native Kubernetes manifests |
| **Learning Curve** | Steep - Requires Crossplane expertise |
| **Production Readiness** | Crossplane: Yes, Proxmox Provider: Experimental |

### Verified Tool Versions (January 2026)

| Tool/Component | Version | Notes |
| -------------- | ------- | ----- |
| [Crossplane](https://www.crossplane.io/) | 2.0+ | CNCF Graduated October 2025 |
| [provider-proxmox-bpg](https://github.com/valkiriaaquatica/provider-proxmox-bpg) | 1.0.0 | Released December 25, 2025 |
| [provider-proxmoxve](https://github.com/dougsong/provider-proxmoxve) | 0.0.1 | Alternative provider |
| [Upjet](https://github.com/crossplane/upjet) | 2.0.0 | Crossplane provider generator |
| [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) | 0.90.0+ | Upstream Terraform provider |

---

## Crossplane Overview

### What is Crossplane?

Crossplane is a **Kubernetes-native infrastructure-as-code framework** that extends Kubernetes to orchestrate external resources. Instead of Terraform state files, Crossplane uses Kubernetes etcd as the state store.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CROSSPLANE ARCHITECTURE                                  │
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
              │       KUBERNETES CLUSTER       │
              │      (Management Cluster)      │
              ├────────────────────────────────┤
              │  • Crossplane Core             │
              │  • provider-proxmox-bpg        │
              │  • Compositions & XRDs         │
              │  • Managed Resources           │
              └──────────────┬─────────────────┘
                             │ reconcile
                             ▼
              ┌──────────────────────────────┐
              │        PROXMOX VE            │
              │  ┌────┐ ┌────┐ ┌────┐        │
              │  │VM1 │ │VM2 │ │VM3 │        │
              │  └────┘ └────┘ └────┘        │
              └──────────────────────────────┘
```

### CNCF Graduation (October 2025)

Crossplane achieved [CNCF Graduation](https://www.cncf.io/announcements/2025/11/06/cloud-native-computing-foundation-announces-graduation-of-crossplane/) in October 2025, signifying:

- **Production-hardened foundation** for building internal platforms
- **Wide adoption**: 100M+ downloads, 1000+ organizations in production
- **Strong governance**: Vendor-neutral, Apache 2.0 licensed
- **Active community**: 3,000+ contributors from 450+ organizations
- **Enterprise adoption**: Nike, Apple, Autodesk, NASA, IBM, VMware Tanzu, Nokia

### Key Benefits

| Benefit | Description |
| ------- | ----------- |
| **Kubernetes-Native** | Uses familiar kubectl, RBAC, namespaces |
| **No State Files** | etcd IS the state store |
| **Continuous Reconciliation** | Auto-corrects drift without manual intervention |
| **Composable** | Build custom APIs with Compositions |
| **Multi-Provider** | AWS, Azure, GCP, and 300+ providers |
| **Self-Healing** | Automatically repairs failed infrastructure |

---

## Proxmox Providers for Crossplane

### Provider Comparison

| Provider | Maintainer | Version | Status | Resources |
| -------- | ---------- | ------- | ------ | --------- |
| [provider-proxmox-bpg](https://github.com/valkiriaaquatica/provider-proxmox-bpg) | valkiriaaquatica | 1.0.0 | Active | 31 |
| [provider-proxmoxve](https://github.com/dougsong/provider-proxmoxve) | dougsong | 0.0.1 | Experimental | ~20 |

### provider-proxmox-bpg (Recommended)

This is the most active Crossplane provider for Proxmox, built using [Upjet](https://github.com/crossplane/upjet) from the [bpg/terraform-provider-proxmox](https://github.com/bpg/terraform-provider-proxmox).

#### Key Features

- **Automated releases**: Syncs with upstream Terraform provider via Renovate Bot
- **Upbound Marketplace**: Published at `xpkg.upbound.io/valkiriaaquaticamendi/provider-proxmox-bpg`
- **Upjet-generated**: Inherits Terraform provider maturity
- **Apache 2.0 license**: Open source, community-friendly

#### Available Managed Resources (31 total)

**Virtual Environment Core:**
- `EnvironmentVM` - Virtual machine management
- `EnvironmentContainer` - LXC container management
- `EnvironmentFile` - File management
- `EnvironmentDownloadFile` - Download file management

**Networking:**
- `EnvironmentNetworkLinuxBridge` - Linux bridge configuration
- `EnvironmentNetworkLinuxVlan` - VLAN configuration
- `EnvironmentClusterFirewall` - Cluster-level firewall

**Security & Access Control:**
- `EnvironmentACL` - Access control lists
- `EnvironmentUser` - User management
- `EnvironmentGroup` - Group management
- `EnvironmentRole` - Role management
- `EnvironmentClusterFirewallSecurityGroup` - Security groups

**Firewall Management:**
- `EnvironmentFirewallAlias` - Firewall aliases
- `EnvironmentFirewallIPSet` - IP sets
- `EnvironmentFirewallOptions` - Firewall options
- `EnvironmentFirewallRules` - Firewall rules

**System Administration:**
- `EnvironmentCertificate` - Certificate management
- `EnvironmentDNS` - DNS configuration
- `EnvironmentHosts` - Hosts file management
- `EnvironmentTime` - Time synchronization
- `EnvironmentMetricsServer` - Metrics server configuration
- `EnvironmentAptRepository` - APT repository management
- `EnvironmentAptStandardRepository` - Standard APT repos

**ACME & DNS:**
- `EnvironmentAcmeAccount` - ACME account management
- `EnvironmentAcmeDNSPlugin` - ACME DNS plugins

**High Availability:**
- `EnvironmentHagroup` - HA group configuration
- `EnvironmentHaresource` - HA resource management

**Resource Organization:**
- `EnvironmentPool` - Resource pool management

---

## Implementation Architecture

### Management Cluster Requirement

Crossplane requires a **management cluster** to run its controllers. This creates a "chicken-and-egg" problem for bootstrapping.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT CLUSTER BOOTSTRAP STRATEGIES                  │
└─────────────────────────────────────────────────────────────────────────────┘

  STRATEGY 1: K3s on Proxmox VM          STRATEGY 2: Local Kind + Pivot
  ─────────────────────────────          ─────────────────────────────
  ┌─────────────────┐                    ┌─────────────────┐
  │ Ansible creates │                    │ Kind cluster    │
  │ K3s VM manually │                    │ on workstation  │
  └────────┬────────┘                    └────────┬────────┘
           │                                      │
           │ Install Crossplane                   │ Install Crossplane
           ▼                                      ▼
  ┌─────────────────┐                    ┌─────────────────┐
  │ Crossplane      │                    │ Apply Proxmox   │
  │ controllers     │                    │ VM manifests    │
  │ running         │                    └────────┬────────┘
  └────────┬────────┘                             │
           │                                      │ Create workload cluster
           │ Apply Proxmox VM manifests           ▼
           ▼                             ┌─────────────────┐
  ┌─────────────────┐                    │ Move Crossplane │
  │ Talos VMs       │                    │ to workload     │
  │ created         │                    │ cluster         │
  └─────────────────┘                    └─────────────────┘
```

### Recommended Bootstrap Flow

1. **Create lightweight management cluster** (K3s VM via Ansible or local Kind)
2. **Install Crossplane** with Proxmox provider
3. **Apply VM manifests** for Talos workload cluster
4. **Bootstrap Talos** using `talosctl`
5. **(Optional) Pivot** Crossplane to workload cluster

---

## Installation & Configuration

### Step 1: Install Crossplane

```bash
# Add Crossplane Helm repository
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Install Crossplane
helm install crossplane \
  --namespace crossplane-system \
  --create-namespace \
  crossplane-stable/crossplane
```

### Step 2: Install Proxmox Provider

**Declarative Installation:**

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-proxmox-bpg
spec:
  package: xpkg.upbound.io/valkiriaaquaticamendi/provider-proxmox-bpg:v1.0.0
```

**Using `up` CLI:**

```bash
up ctp provider install xpkg.upbound.io/valkiriaaquaticamendi/provider-proxmox-bpg:v1.0.0
```

### Step 3: Configure Provider Credentials

**Create Proxmox API Secret:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-credentials
  namespace: crossplane-system
type: Opaque
stringData:
  credentials: |
    {
      "endpoint": "https://proxmox.local:8006",
      "api_token": "automation@pve!crossplane=secret-token",
      "insecure": true
    }
```

**Create ProviderConfig:**

```yaml
apiVersion: proxmox.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      name: proxmox-credentials
      namespace: crossplane-system
      key: credentials
```

---

## Example Manifests

### VM Creation (Conceptual)

> **Note:** The exact CRD schema depends on the provider version. Check the [examples directory](https://github.com/valkiriaaquatica/provider-proxmox-bpg/tree/main/examples) for current syntax.

```yaml
apiVersion: virtualenvironment.proxmox.upbound.io/v1alpha1
kind: EnvironmentVM
metadata:
  name: talos-cp-1
  labels:
    role: control-plane
    cluster: matherlynet
spec:
  forProvider:
    nodeName: pve
    vmId: 101
    name: talos-cp-1
    description: "Talos Linux Control Plane Node 1"
    tags:
      - talos
      - control-plane
      - kubernetes

    # Clone from template
    clone:
      vmId: 9000  # Talos template
      full: true
      storage: local-zfs

    # Hardware configuration
    cpu:
      cores: 4
      type: host
    memory:
      dedicated: 8192

    # Boot disk
    disk:
      - storage: local-zfs
        interface: scsi0
        size: 100
        discard: true
        ssd: true

    # Network
    network:
      - bridge: vmbr0
        model: virtio
        macaddr: "BC:24:11:00:01:01"

    # Cloud-init
    initialization:
      ipConfig:
        - ipv4:
            address: "192.168.22.10/24"
            gateway: "192.168.22.1"
      dns:
        servers:
          - "192.168.22.1"

    # QEMU settings
    agent: true
    bios: ovmf
    started: true

  providerConfigRef:
    name: default
```

### Composition Example

Crossplane Compositions allow you to create custom APIs:

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xtalosnodes.infrastructure.matherlynet.io
spec:
  group: infrastructure.matherlynet.io
  names:
    kind: XTalosNode
    plural: xtalosnodes
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                role:
                  type: string
                  enum: [control-plane, worker]
                resources:
                  type: object
                  properties:
                    cores:
                      type: integer
                      default: 4
                    memory:
                      type: integer
                      default: 8192
                    diskSize:
                      type: integer
                      default: 100
                network:
                  type: object
                  properties:
                    ipAddress:
                      type: string
                    macAddress:
                      type: string
              required:
                - role
                - network
---
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: talosnode.infrastructure.matherlynet.io
spec:
  compositeTypeRef:
    apiVersion: infrastructure.matherlynet.io/v1alpha1
    kind: XTalosNode
  resources:
    - name: vm
      base:
        apiVersion: virtualenvironment.proxmox.upbound.io/v1alpha1
        kind: EnvironmentVM
        spec:
          forProvider:
            nodeName: pve
            clone:
              vmId: 9000
              full: true
              storage: local-zfs
            cpu:
              type: host
            agent: true
            bios: ovmf
            started: true
      patches:
        - fromFieldPath: spec.resources.cores
          toFieldPath: spec.forProvider.cpu.cores
        - fromFieldPath: spec.resources.memory
          toFieldPath: spec.forProvider.memory.dedicated
        - fromFieldPath: spec.network.ipAddress
          toFieldPath: spec.forProvider.initialization.ipConfig[0].ipv4.address
        - fromFieldPath: spec.network.macAddress
          toFieldPath: spec.forProvider.network[0].macaddr
```

### Using the Custom API

```yaml
apiVersion: infrastructure.matherlynet.io/v1alpha1
kind: XTalosNode
metadata:
  name: talos-cp-1
spec:
  role: control-plane
  resources:
    cores: 4
    memory: 8192
    diskSize: 100
  network:
    ipAddress: "192.168.22.10/24"
    macAddress: "BC:24:11:00:01:01"
```

---

## Go-Task Integration

**File: `.taskfiles/crossplane/Taskfile.yaml`**

```yaml
---
version: "3"

vars:
  CROSSPLANE_DIR: "{{.ROOT_DIR}}/infrastructure/crossplane"

tasks:
  # ─────────────────────────────────────────────────────────────────────────
  # Crossplane Setup
  # ─────────────────────────────────────────────────────────────────────────

  install:
    desc: Install Crossplane in management cluster
    cmds:
      - helm repo add crossplane-stable https://charts.crossplane.io/stable
      - helm repo update
      - |
        helm upgrade --install crossplane \
          --namespace crossplane-system \
          --create-namespace \
          --wait \
          crossplane-stable/crossplane
    preconditions:
      - which helm
      - kubectl cluster-info

  provider:install:
    desc: Install Proxmox provider
    cmds:
      - kubectl apply -f {{.CROSSPLANE_DIR}}/provider.yaml
      - kubectl wait --for=condition=healthy --timeout=300s provider.pkg/provider-proxmox-bpg
    preconditions:
      - test -f {{.CROSSPLANE_DIR}}/provider.yaml

  provider:configure:
    desc: Configure Proxmox provider credentials
    cmds:
      - |
        PROXMOX_TOKEN=$(sops -d {{.ROOT_DIR}}/infrastructure/secrets.sops.yaml | yq '.proxmox_api_token')
        PROXMOX_ENDPOINT=$(sops -d {{.ROOT_DIR}}/infrastructure/secrets.sops.yaml | yq '.proxmox_endpoint')
        kubectl create secret generic proxmox-credentials \
          --namespace crossplane-system \
          --from-literal=credentials="{\"endpoint\":\"${PROXMOX_ENDPOINT}\",\"api_token\":\"${PROXMOX_TOKEN}\",\"insecure\":true}" \
          --dry-run=client -o yaml | kubectl apply -f -
      - kubectl apply -f {{.CROSSPLANE_DIR}}/providerconfig.yaml
    preconditions:
      - test -f {{.ROOT_DIR}}/infrastructure/secrets.sops.yaml

  # ─────────────────────────────────────────────────────────────────────────
  # VM Provisioning
  # ─────────────────────────────────────────────────────────────────────────

  provision:
    desc: Apply Talos VM manifests
    cmds:
      - kubectl apply -f {{.CROSSPLANE_DIR}}/vms/
    preconditions:
      - test -d {{.CROSSPLANE_DIR}}/vms

  status:
    desc: Show Crossplane managed resources status
    cmds:
      - kubectl get managed -l cluster=matherlynet
      - kubectl get events --field-selector involvedObject.kind=EnvironmentVM

  destroy:
    desc: Delete all Talos VMs
    prompt: This will DELETE all managed VMs. Continue?
    cmds:
      - kubectl delete -f {{.CROSSPLANE_DIR}}/vms/

  # ─────────────────────────────────────────────────────────────────────────
  # Debugging
  # ─────────────────────────────────────────────────────────────────────────

  logs:
    desc: Show Crossplane provider logs
    cmds:
      - kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-proxmox-bpg --tail=100 -f

  describe:
    desc: Describe all managed VMs
    cmds:
      - kubectl describe environmentvm -l cluster=matherlynet
```

---

## Comparison: Crossplane vs Cluster API (CAPMOX)

Both Crossplane and Cluster API use Kubernetes as the state store, but they have different focuses:

| Aspect | Crossplane | Cluster API (CAPMOX) |
| ------ | ---------- | -------------------- |
| **Primary Focus** | General infrastructure | Kubernetes cluster lifecycle |
| **VM Management** | Direct VM CRDs | Machine/MachineSet abstractions |
| **Talos Support** | Manual config | CABPT/CACPPT providers |
| **Self-Healing** | Resource-level | Cluster-level (node replacement) |
| **Composition** | Custom XRDs | Limited customization |
| **Maturity** | CNCF Graduated | CAPMOX v1alpha1 |
| **Proxmox Issues** | Limited provider | Known cloud-init issues |

### Known CAPMOX Issues (January 2026)

From our research, CAPMOX has several documented problems:

1. **Cloud-Init ISO on Shared Storage** ([#569](https://github.com/ionos-cloud/cluster-api-provider-proxmox/issues/569))
   - Fails on multi-node Proxmox clusters with CephFS storage

2. **Network Connectivity Issues** ([#12097](https://github.com/siderolabs/talos/issues/12097))
   - Talos 1.11.3 fails to start after upgrade

3. **Machine Stuck in Provisioning** ([#291](https://github.com/ionos-cloud/cluster-api-provider-proxmox/issues/291))
   - VMs created but bootstrap stalls

4. **Cloud-Init Format Incompatibility** ([#51](https://github.com/ionos-cloud/cluster-api-provider-proxmox/issues/51))
   - Talos complains about network-config format

---

## Known Limitations

### 1. Management Cluster Dependency

Crossplane requires a running Kubernetes cluster. For initial bootstrap:

- Use K3s/Kind locally or on a dedicated VM
- Consider Ansible for initial management cluster provisioning

### 2. Proxmox Provider Maturity

The `provider-proxmox-bpg` is community-maintained:

- v1.0.0 is recent (December 2025)
- Limited production deployments
- May have undiscovered edge cases
- Depends on upstream bpg Terraform provider

### 3. Talos Cloud-Init Complexity

Talos requires specific NoCloud configuration:

- Must use NoCloud images from Image Factory
- Cloud-init snippets require manual placement
- SMBIOS serial method needs base64 encoding

### 4. Drift Detection Timing

Crossplane reconciles on intervals (default: 60s):

- Not instant drift detection like admission webhooks
- May miss short-lived manual changes

### 5. Debugging Complexity

Multi-layer abstraction can complicate troubleshooting:

```
User YAML → Crossplane → Upjet → Terraform Schema → Proxmox API
```

---

## Production Readiness Assessment

### Crossplane: Production Ready ✅

- CNCF Graduated project
- 100M+ downloads
- 1000+ production organizations
- Strong governance and security audits

### provider-proxmox-bpg: Experimental ⚠️

| Criterion | Status |
| --------- | ------ |
| Version stability | v1.0.0 (recent) |
| Production users | Unknown/limited |
| Security audit | None documented |
| Support model | Community only |
| Documentation | Minimal examples |
| Test coverage | Unknown |

### Recommendation

**For this project (January 2026):**

1. **Primary**: Ansible (stable, well-documented)
2. **Secondary**: OpenTofu with bpg provider (if state management acceptable)
3. **Future**: Crossplane when Proxmox provider matures (6-12 months)

**Consider Crossplane when:**
- Provider reaches v1.x stable with documented production use
- Your organization already uses Crossplane for other infrastructure
- GitOps-native VM management is a hard requirement
- Management cluster already exists

---

## Alternative: Kubemox Operator

[Kubemox](https://github.com/alperencelik/kubemox) is another Kubernetes operator for Proxmox:

### Current Status (v0.5.2, December 2025)

- **Active development** but explicitly not production-ready
- **No CRD versioning guarantees**
- **Limited feature coverage**
- Built with Kubebuilder + go-proxmox

### Roadmap Features

- Additional CRD types (LXC, storage, networking)
- Enhanced authentication methods
- HA features
- Better documentation

### Verdict

Kubemox is interesting for experimentation but not suitable for production infrastructure management.

---

## Implementation Phases

### Phase 1: Foundation (If Proceeding)

1. **Set up management cluster** (K3s or Kind)
2. **Install Crossplane** core
3. **Install provider-proxmox-bpg**
4. **Test basic VM creation/deletion**

### Phase 2: Integration

1. **Create Compositions** for Talos nodes
2. **Integrate with GitOps** (Flux/ArgoCD)
3. **Add to go-task** workflow
4. **Document procedures**

### Phase 3: Production (Future)

1. **Migrate from Ansible** once provider stabilizes
2. **Implement self-healing** policies
3. **Add monitoring** (Prometheus metrics)
4. **Create runbooks** for operations

---

## Comparison: Crossplane vs Ansible vs OpenTofu

| Aspect | Crossplane | Ansible | OpenTofu |
| ------ | ---------- | ------- | -------- |
| **State Management** | K8s etcd | None | File-based |
| **Learning Curve** | Steep | Low | Medium |
| **Proxmox Maturity** | Low | High | High |
| **GitOps Native** | Yes | Via CI/CD | Via CI/CD |
| **Continuous Reconciliation** | Yes | No | No |
| **Talos Provider** | No | No | Yes |
| **Multi-team** | RBAC | No locks | State locks |
| **Management Cluster** | Required | No | No |
| **Production Ready** | Crossplane: Yes, Provider: No | Yes | Yes |

---

## Sources

### Crossplane
- [Crossplane Official Website](https://www.crossplane.io/)
- [CNCF Graduation Announcement](https://www.cncf.io/announcements/2025/11/06/cloud-native-computing-foundation-announces-graduation-of-crossplane/)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [Crossplane GitHub](https://github.com/crossplane/crossplane)
- [Upjet Framework](https://github.com/crossplane/upjet)

### Proxmox Providers
- [provider-proxmox-bpg GitHub](https://github.com/valkiriaaquatica/provider-proxmox-bpg)
- [Upbound Marketplace - provider-proxmox-bpg](https://marketplace.upbound.io/providers/valkiriaaquaticamendi/provider-proxmox-bpg/v0.11.1)
- [provider-proxmoxve GitHub](https://github.com/dougsong/provider-proxmoxve)
- [bpg/proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest)

### Kubemox
- [Kubemox GitHub](https://github.com/alperencelik/kubemox)
- [Kubemox Documentation](https://alperencelik.github.io/kubemox/)
- [Kubemox Roadmap](https://alperencelik.github.io/kubemox/roadmap/)

### Community Discussions
- [Proxmox Forum - Kubernetes Operator](https://forum.proxmox.com/threads/kubernetes-proxmox-operator.125268/)
- [Crossplane vs Terraform Comparison](https://spacelift.io/blog/crossplane-vs-terraform)
- [Crossplane vs Terraform vs Ansible](https://devopstoolkit.live/infrastructure-as-code/ansible-vs-terraform-vs-crossplane/index.html)

### Talos Integration
- [Talos NoCloud Documentation](https://docs.siderolabs.com/talos/v1.11/platform-specific-installations/cloud-platforms/nocloud)
- [JYSK Tech - Talos NoCloud Boot](https://jysk.tech/3000-clusters-part-3-how-to-boot-talos-linux-nodes-with-cloud-init-and-nocloud-acdce36f60c0)

### Cluster API (CAPMOX)
- [IONOS CAPMOX](https://github.com/ionos-cloud/cluster-api-provider-proxmox)
- [Cluster API + Talos + Proxmox Guide](https://a-cup-of.coffee/blog/talos-capi-proxmox/)
- [CAPMOX Cloud-Init Issue #569](https://github.com/ionos-cloud/cluster-api-provider-proxmox/issues/569)
- [Talos Network Issue #12097](https://github.com/siderolabs/talos/issues/12097)
