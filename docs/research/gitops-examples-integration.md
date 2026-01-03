# GitOps Examples Integration Research

> **Research Date:** January 2026
> **Status:** Complete - Validated and Recommendations Ready
> **Sources:** [sergelogvinov/gitops-examples](https://github.com/sergelogvinov/gitops-examples), [billimek/k8s-gitops](https://github.com/billimek/k8s-gitops), [home-operations/tuppr](https://github.com/home-operations/tuppr)
> **Context:** Evaluating cloud-native components for Proxmox + Talos clusters
> **Validation:** Patterns verified against project conventions (Jan 2026)

## Executive Summary

This research analyzes GitOps reference implementations to identify technologies that can enhance our cluster's capabilities. The focus is on components that integrate natively with Proxmox virtualization and Talos Linux, while maintaining our GitOps-first philosophy.

### Priority Recommendations

| Priority | Component | Value Proposition | Complexity | Recommendation |
| ---------- | ----------- | ------------------- | ------------ | ---------------- |
| **P0** | Talos Upgrade Controller (tuppr) | Automated, safe OS/K8s upgrades | Low | **Immediate adoption** |
| **P1** | Talos CCM | Node labeling, lifecycle management | Low | **High value** |
| **P1** | Talos Backup | etcd backup with Age encryption | Low | **Critical for DR** |
| **P2** | Proxmox CSI | Persistent storage from Proxmox | Medium | **When storage needed** |
| **P3** | Proxmox CCM | Cloud-provider integration | Medium | **Nice to have** |
| **P4** | Proxmox Karpenter | Auto-scaling VMs | High | **Future consideration** |

---

## Version Notes

### Latest Chart Versions (January 2026)

| Chart | Registry | Chart Version | App Version |
| ------- | ---------- | --------------- | ------------- |
| tuppr | `ghcr.io/home-operations/charts` | **0.0.51** | 0.0.51 |
| talos-cloud-controller-manager | `ghcr.io/siderolabs/charts` | **0.5.2** | v1.11.0 |
| talos-backup | `ghcr.io/sergelogvinov/charts` | **0.1.2** | 0.1.2 |
| proxmox-csi-plugin | `ghcr.io/sergelogvinov/charts` | **0.5.4** | v0.17.1 |
| proxmox-cloud-controller-manager | `ghcr.io/sergelogvinov/charts` | **0.2.23** | v0.12.3 |
| karpenter-provider-proxmox | `ghcr.io/sergelogvinov/charts` | **0.4.1** | 0.4.1 |

> **Note:** Chart versions may differ from application release versions on GitHub. To check for updates:
>
> ```bash
> # Check latest chart version
> skopeo list-tags docker://ghcr.io/<org>/charts/<chart-name>
> ```
>
> **Recommendation:** Use [Renovate](https://docs.renovatebot.com/) to automatically track and update chart versions in your GitOps repository.

---

## Components Analysis

### 1. Talos Upgrade Controller (tuppr)

**Source:** [home-operations/tuppr](https://github.com/home-operations/tuppr) (recommended over sergelogvinov's system-upgrade-controller)

**What It Does:**
- Automates Talos OS and Kubernetes version upgrades
- Orchestrates upgrades safely across nodes (never self-upgrades)
- Supports CEL-based health checks before/during upgrades
- Provides Prometheus metrics for monitoring

**Why We Need It:**
Currently, upgrades require manual execution of `task talos:upgrade-node` per node. tuppr enables GitOps-driven upgrades where version changes in a CR trigger automated, rolling updates.

**Integration Pattern:**
```yaml
# templates/config/kubernetes/apps/system-upgrade/tuppr/app/talosupgrade.yaml.j2
---
apiVersion: tuppr.home-operations.com/v1alpha1
kind: TalosUpgrade
metadata:
  name: talos
spec:
  talos:
    version: "#{ talos_version }#"  # From cluster.yaml
  policy:
    rebootMode: default
  healthChecks:
    - apiVersion: v1
      kind: Node
      expr: status.conditions.exists(c, c.type == "Ready" && c.status == "True")
      timeout: 10m
```

**Advanced Health Checks Example (from billimek/k8s-gitops):**

For clusters with storage replication or Ceph, add additional safety checks:
```yaml
  healthChecks:
    # Ensure nodes are ready
    - apiVersion: v1
      kind: Node
      expr: status.conditions.exists(c, c.type == "Ready" && c.status == "True")
      timeout: 10m
    # Ensure VolSync replication is not in progress (optional)
    - apiVersion: volsync.backube/v1alpha1
      kind: ReplicationSource
      expr: status.conditions.exists(c, c.type == "Synchronizing" && c.status == "False")
      timeout: 5m
    # Ensure Ceph cluster is healthy (optional)
    - apiVersion: ceph.rook.io/v1
      kind: CephCluster
      expr: status.ceph.health == "HEALTH_OK"
      timeout: 5m
```

**Helm Chart:**
- Repository: `oci://ghcr.io/home-operations/charts/tuppr`
- Latest Version: **0.0.51** (as of January 2026)

**Prerequisites:**
Talos API access configuration in machine config (add to `templates/config/talos/patches/global/`):
```yaml
# templates/config/talos/patches/global/machine-talos-api.yaml.j2
machine:
  features:
    kubernetesTalosAPIAccess:
      allowedKubernetesNamespaces:
        - system-upgrade
      allowedRoles:
        - os:admin
      enabled: true
```

> **Note:** This patch must be applied to all nodes and requires a Talos config apply/upgrade cycle.

**Adoption Effort:** Low - Single namespace, 2 CRs (TalosUpgrade, KubernetesUpgrade), plus Talos patch

---

### 2. Talos Cloud Controller Manager

**Source:** [siderolabs/talos-cloud-controller-manager](https://github.com/siderolabs/talos-cloud-controller-manager)

**What It Does:**
- Transforms Talos-specific node information into Kubernetes labels
- Manages node lifecycle (cordons unresponsive nodes)
- Applies platform-specific labels (Proxmox VM ID, region, zone)
- Provides node topology awareness for scheduling

**Why We Need It:**
Without a CCM, nodes lack cloud-provider metadata. The Talos CCM adds:
- `node.kubernetes.io/instance-type` labels
- `topology.kubernetes.io/region` and `zone` labels
- Proper node condition management
- Foundation for future topology-aware scheduling

**Integration Pattern:**
```yaml
# templates/config/kubernetes/apps/kube-system/talos-ccm/app/helmrelease.yaml.j2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: talos-cloud-controller-manager
spec:
  chartRef:
    kind: OCIRepository
    name: talos-ccm
  interval: 1h
  values:
    logVerbosityLevel: 4
    useDaemonSet: true
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
```

**Helm Chart:**
- Repository: `oci://ghcr.io/siderolabs/charts/talos-cloud-controller-manager`
- Latest Version: **0.5.2** (as of January 2026)

**Adoption Effort:** Low - DaemonSet on control-plane nodes only

---

### 3. Talos Backup

**Source:** [sergelogvinov/talos-backup](https://github.com/sergelogvinov/helm-charts) (part of his helm-charts repo)

**What It Does:**
- Automated etcd snapshots on schedule
- Uploads to S3-compatible storage
- Encrypts backups with Age (same as SOPS)
- Validates backup integrity

**Why We Need It:**
etcd is the critical state store. Without backups:
- Control plane failure = cluster rebuild
- No point-in-time recovery
- Certificate expiration = disaster

**Integration Pattern:**
```yaml
# templates/config/kubernetes/apps/kube-system/talos-backup/app/helmrelease.yaml.j2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: talos-backup
spec:
  chartRef:
    kind: OCIRepository
    name: talos-backup
  interval: 12h
  values:
    priorityClassName: system-cluster-critical
    schedule: "0 */6 * * *"  # Every 6 hours
    env:
      - name: CLUSTER_NAME
        value: "#{ cluster_name }#"
      - name: S3_ENDPOINT
        value: "#{ backup_s3_endpoint }#"
      - name: S3_BUCKET
        value: "#{ backup_s3_bucket }#"
      - name: S3_PREFIX
        value: "#{ cluster_name }#/etcd-backups"
      - name: AGE_X25519_PUBLIC_KEY
        valueFrom:
          secretKeyRef:
            name: talos-backup-age
            key: public-key
```

**Helm Chart:**
- Repository: `oci://ghcr.io/sergelogvinov/charts/talos-backup`
- Latest Version: **0.1.2** (as of January 2026)

**Prerequisites:**
- S3-compatible storage (MinIO, Cloudflare R2, AWS S3)
- Age keypair for backup encryption

**Adoption Effort:** Low-Medium - Requires S3 storage configuration

---

### 4. Proxmox CSI Driver

**Source:** [sergelogvinov/proxmox-csi-plugin](https://github.com/sergelogvinov/proxmox-csi-plugin)

**What It Does:**
- Provisions PersistentVolumes directly on Proxmox storage
- Supports LVM, LVM-thin, ZFS, NFS storage backends
- Provides topology-aware provisioning (volumes stay on same node as pod)
- Enables volume snapshots and expansion
- LUKS encryption support for sensitive data
- Bandwidth control for storage I/O limits

**Recent Changes (v0.17.x - January 2026):**
- v0.17.1 removed the previously required `Sys.Audit` permission (breaking change from v0.16.0 now resolved)
- Fixed storage topology and VM lock race conditions

**Why We Might Need It:**
When applications require persistent storage, options include:
1. **Proxmox CSI** - Uses hypervisor storage directly
2. **Longhorn/Rook-Ceph** - In-cluster distributed storage
3. **NFS provisioner** - External NFS server

Proxmox CSI is simpler if you trust hypervisor storage and don't need replication across nodes.

**Integration Pattern:**
```yaml
# templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/app/helmrelease.yaml.j2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: proxmox-csi-plugin
spec:
  chartRef:
    kind: OCIRepository
    name: proxmox-csi
  interval: 1h
  values:
    replicaCount: 1
    metrics:
      enabled: true
    storageClass:
      - name: proxmox-zfs
        storage: local-zfs
        reclaimPolicy: Delete
        fstype: ext4
        ssd: true
    config:
      clusters:
        - url: "#{ proxmox_endpoint }#"
          insecure: false
          token_id: "#{ proxmox_token_id }#"
          token_secret: "#{ proxmox_token_secret }#"
          region: "#{ proxmox_region }#"
```

**Helm Chart:**
- Repository: `oci://ghcr.io/sergelogvinov/charts/proxmox-csi-plugin`
- Latest Version: **0.5.4** (as of January 2026)

**Prerequisites:**
- Proxmox API token with storage permissions
- `csi-proxmox` namespace with privileged pod security

**Adoption Effort:** Medium - Requires Proxmox API configuration and storage planning

---

### 5. Proxmox Cloud Controller Manager

**Source:** [sergelogvinov/proxmox-cloud-controller-manager](https://github.com/sergelogvinov/proxmox-cloud-controller-manager)

**What It Does:**
- Initializes nodes with Proxmox-specific labels
- Manages node lifecycle based on VM state
- Removes nodes when VMs are deleted
- Supports multi-cluster Proxmox environments

**Why We Might Need It:**
Provides tighter integration between K8s and Proxmox:
- Automatic node removal when VM is destroyed
- VM metadata as node labels
- Foundation for Karpenter integration

**Integration Pattern:**
```yaml
# templates/config/kubernetes/apps/kube-system/proxmox-ccm/app/helmrelease.yaml.j2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: proxmox-cloud-controller-manager
spec:
  chartRef:
    kind: OCIRepository
    name: proxmox-ccm
  interval: 1h
  values:
    useDaemonSet: true
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    enabledControllers:
      - cloud-node
      - cloud-node-lifecycle
    config:
      clusters:
        - url: "#{ proxmox_endpoint }#"
          insecure: false
          token_id: "#{ proxmox_token_id }#"
          token_secret: "#{ proxmox_token_secret }#"
          region: "#{ proxmox_region }#"
```

**Helm Chart:**
- Repository: `oci://ghcr.io/sergelogvinov/charts/proxmox-cloud-controller-manager`
- Latest Version: **0.2.23** (as of January 2026)

**Adoption Effort:** Medium - Overlaps with Talos CCM, careful coordination needed

---

### 6. Proxmox Karpenter Provider

**Source:** [sergelogvinov/karpenter-provider-proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox)

**What It Does:**
- Automatically provisions VMs on Proxmox when pods are pending
- Scales down by terminating empty VMs
- Supports Talos Linux node templates
- Enables cost-aware scheduling and bin-packing

**Why We Might Need It (Future):**
For dynamic workloads that need burst capacity:
- CI/CD runners that scale to zero
- Development environments on-demand
- GPU workloads that scale with usage

**When NOT to Use:**
- Fixed node count homelab
- Predictable workload patterns
- No Proxmox API access from cluster

**Integration Pattern:**
```yaml
# Future implementation - requires ProxmoxNodeClass and NodePool CRDs
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.proxmox.io
        kind: ProxmoxNodeClass
        name: talos
      requirements:
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
  limits:
    cpu: 100
    memory: 256Gi
```

**Helm Chart:**
- Repository: `oci://ghcr.io/sergelogvinov/charts/karpenter-provider-proxmox`
- Latest Version: **0.4.1** (as of January 2026)

**Adoption Effort:** High - Requires Proxmox CCM, CSI, templates, and careful planning

---

## Integration Strategy

### Phase 1: Essential Operations (Immediate)

**Goal:** Automated upgrades and disaster recovery

1. **tuppr (Talos Upgrade Controller)**
   - Add `system-upgrade` namespace template
   - Configure Talos API access in machine patches
   - Deploy tuppr HelmRelease
   - Create TalosUpgrade and KubernetesUpgrade CRs

2. **Talos Backup**
   - Choose S3 storage (Cloudflare R2 recommended - already using Cloudflare)
   - Add `talos-backup` to kube-system namespace
   - Configure Age encryption key

**Files to Add:**
```
templates/config/kubernetes/apps/system-upgrade/
├── namespace.yaml.j2
├── kustomization.yaml.j2
└── tuppr/
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── ocirepository.yaml.j2
        ├── helmrelease.yaml.j2
        ├── talosupgrade.yaml.j2
        └── kubernetesupgrade.yaml.j2

templates/config/kubernetes/apps/kube-system/talos-backup/
├── ks.yaml.j2
└── app/
    ├── kustomization.yaml.j2
    ├── ocirepository.yaml.j2
    ├── helmrelease.yaml.j2
    └── secret.sops.yaml.j2
```

**cluster.yaml Additions:**
```yaml
# Talos Upgrade Controller
talos_version: "1.12.0"
kubernetes_version: "1.35.0"

# Talos Backup
backup_s3_endpoint: "https://r2.cloudflarestorage.com"
backup_s3_bucket: "cluster-backups"
backup_age_public_key: "age1..."
```

### Phase 2: Cloud Integration (When Needed)

**Goal:** Proper cloud-provider integration for topology and lifecycle

1. **Talos CCM**
   - Deploy as DaemonSet on control-plane
   - Enable node labeling and lifecycle management

2. **Proxmox CSI** (if persistent storage needed)
   - Create `csi-proxmox` namespace with privileged PSS
   - Configure Proxmox API credentials
   - Define storage classes

**Files to Add:**
```
templates/config/kubernetes/apps/kube-system/talos-ccm/
├── ks.yaml.j2
└── app/
    ├── kustomization.yaml.j2
    ├── ocirepository.yaml.j2
    └── helmrelease.yaml.j2

templates/config/kubernetes/apps/csi-proxmox/
├── namespace.yaml.j2
├── kustomization.yaml.j2
└── proxmox-csi/
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── ocirepository.yaml.j2
        ├── helmrelease.yaml.j2
        └── secret.sops.yaml.j2
```

### Phase 3: Advanced Automation (Future)

**Goal:** Dynamic infrastructure scaling

1. **Proxmox CCM** (prerequisite for Karpenter)
2. **Proxmox Karpenter** (when auto-scaling needed)

This phase requires the infrastructure automation from `proxmox-vm-automation.md` to be in place first.

---

## Template Patterns

### OCI Repository Pattern (Existing)

Our project uses OCI repositories for Helm charts:

```yaml
# templates/config/kubernetes/apps/<namespace>/<app>/app/ocirepository.yaml.j2
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <app>
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: <version>
  url: oci://ghcr.io/<org>/charts/<chart>
```

### HelmRelease Pattern (Existing)

```yaml
# templates/config/kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml.j2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app>
spec:
  chartRef:
    kind: OCIRepository
    name: <app>
  interval: 1h
  values:
    # Chart-specific values with Jinja2 templating
    someValue: "#{ cluster_variable }#"
```

### sergelogvinov Repository

For charts from sergelogvinov, the OCI URL pattern is:
```
oci://ghcr.io/sergelogvinov/charts/<chart-name>
```

Available charts include:
- `talos-backup`
- `proxmox-csi-plugin`
- `proxmox-cloud-controller-manager`
- `karpenter-provider-proxmox`

### Siderolabs Repository

For official Talos charts:
```
oci://ghcr.io/siderolabs/charts/<chart-name>
```

Available charts include:
- `talos-cloud-controller-manager`

### home-operations Repository

For community tools like tuppr:
```
oci://ghcr.io/home-operations/charts/<chart-name>
```

---

## Dependency Graph

```
                        ┌─────────────────────────────────────┐
                        │           Phase 1 (Core)            │
                        │                                     │
                        │   ┌─────────┐    ┌──────────────┐   │
                        │   │  tuppr  │    │ talos-backup │   │
                        │   └─────────┘    └──────────────┘   │
                        │        │                  │         │
                        │        └──────┬───────────┘         │
                        │               │                     │
                        └───────────────┼─────────────────────┘
                                        │
                                        ▼
                        ┌─────────────────────────────────────┐
                        │         Phase 2 (Optional)          │
                        │                                     │
                        │   ┌──────────┐    ┌─────────────┐   │
                        │   │ talos-ccm│    │ proxmox-csi │   │
                        │   └──────────┘    └─────────────┘   │
                        │        │                  │         │
                        │        └──────┬───────────┘         │
                        │               │                     │
                        └───────────────┼─────────────────────┘
                                        │
                                        ▼
                        ┌─────────────────────────────────────┐
                        │         Phase 3 (Advanced)          │
                        │                                     │
                        │   ┌────────────┐  ┌──────────────┐  │
                        │   │ proxmox-ccm│─▶│ proxmox-     │  │
                        │   │            │  │ karpenter    │  │
                        │   └────────────┘  └──────────────┘  │
                        │                                     │
                        └─────────────────────────────────────┘
```

---

## Comparison: sergelogvinov vs billimek Approaches

| Aspect | sergelogvinov/gitops-examples | billimek/k8s-gitops |
| -------- | ----------------------------- | --------------------- |
| **Upgrade Controller** | system-upgrade-controller (older) | tuppr (newer, recommended) |
| **Helm Repository** | Custom HelmRepository | OCIRepository pattern |
| **Secret Management** | External values from Secrets/ConfigMaps | Inline SOPS encryption |
| **Structure** | Modular per-cloud-provider | Flat structure |
| **Talos Integration** | Deep (CCM, backup, upgrades) | Deep (tuppr focus) |
| **Best For** | Reference implementations | Production patterns |

**Recommendation:** Use tuppr from billimek's approach for upgrades, but use sergelogvinov's charts for Proxmox-specific components.

---

## Risk Assessment

### Low Risk
- **tuppr**: Well-maintained, simple CRs, rollback possible
- **Talos CCM**: Official Siderolabs, minimal footprint
- **Talos Backup**: Passive component, doesn't affect runtime

### Medium Risk
- **Proxmox CSI**: Storage driver can cause data issues if misconfigured
- **Proxmox CCM**: Overlaps with Talos CCM, requires careful coordination

### High Risk
- **Proxmox Karpenter**: Complex automation, can create/destroy VMs unexpectedly

---

## Implementation Checklist

### Phase 1 Prerequisites

- [ ] Verify S3 storage available (R2, MinIO, etc.)
- [ ] Generate Age keypair for backup encryption
- [ ] Update Talos machine patches for API access
- [ ] Add `system-upgrade` namespace template
- [ ] Create tuppr HelmRelease and CRs
- [ ] Create talos-backup HelmRelease
- [ ] Test upgrade workflow in staging

### Phase 2 Prerequisites

- [ ] Create Proxmox API token for K8s access
- [ ] Determine storage strategy (CSI vs in-cluster)
- [ ] Add `csi-proxmox` namespace if CSI needed
- [ ] Deploy Talos CCM
- [ ] Test node lifecycle management

### Phase 3 Prerequisites

- [ ] Complete infrastructure automation (OpenTofu/Packer)
- [ ] Define VM templates for Karpenter
- [ ] Create NodePool and ProxmoxNodeClass resources
- [ ] Configure resource limits
- [ ] Test scale-up and scale-down

---

## Sources

### Primary Repositories
- [sergelogvinov/gitops-examples](https://github.com/sergelogvinov/gitops-examples) - Reference GitOps implementation
- [billimek/k8s-gitops](https://github.com/billimek/k8s-gitops) - Production homelab GitOps
- [home-operations/tuppr](https://github.com/home-operations/tuppr) - Talos upgrade controller

### Helm Charts
- [sergelogvinov/helm-charts](https://github.com/sergelogvinov/helm-charts) - Proxmox and Talos charts
- [siderolabs/talos-cloud-controller-manager](https://github.com/siderolabs/talos-cloud-controller-manager) - Official CCM

### Documentation
- [Proxmox CSI Installation](https://github.com/sergelogvinov/proxmox-csi-plugin/blob/main/docs/install.md)
- [Proxmox CCM Installation](https://github.com/sergelogvinov/proxmox-cloud-controller-manager/blob/main/docs/install.md)
- [Karpenter Proxmox Deployment](https://deepwiki.com/sergelogvinov/karpenter-provider-proxmox/4-deployment)
- [tuppr Documentation](https://github.com/home-operations/tuppr#readme)

### Artifact Hub
- [proxmox-csi-plugin](https://artifacthub.io/packages/helm/proxmox-csi/proxmox-csi-plugin)
- [proxmox-cloud-controller-manager](https://artifacthub.io/packages/helm/proxmox-ccm/proxmox-cloud-controller-manager)

---

## Validation Summary

> **Last Validated:** January 3, 2026
> **Validation Method:** Serena MCP reflection tools, OCI registry verification, upstream GitHub release checks

This research document has been validated against the project's conventions and structure:

### Template Pattern Validation

| Aspect | Status | Notes |
| -------- | -------- | ------- |
| Jinja2 Delimiters | :white_check_mark: Correct | Uses `#{ }#` for variables, `#% %#` for blocks |
| Directory Structure | :white_check_mark: Correct | Follows `apps/<namespace>/<app>/ks.yaml.j2` pattern |
| OCIRepository Pattern | :white_check_mark: Correct | Matches existing apps (reloader, cilium, etc.) |
| HelmRelease Pattern | :white_check_mark: Correct | Uses `chartRef` referencing OCIRepository |
| Kustomization Pattern | :white_check_mark: Correct | Standard resources list with namespace targeting |

### Integration Strategy Validation

| Phase | Components | Structure Valid | Prerequisites Clear |
| ------- | ------------ | ----------------- | --------------------- |
| Phase 1 | tuppr, talos-backup | :white_check_mark: | :white_check_mark: |
| Phase 2 | talos-ccm, proxmox-csi | :white_check_mark: | :white_check_mark: |
| Phase 3 | proxmox-ccm, karpenter | :white_check_mark: | :white_check_mark: |

### Recommendations Confidence

| Component | Recommendation | Confidence | Rationale |
| ----------- | --------------- | ------------ | ----------- |
| tuppr | Immediate adoption | High | Active development, simple CRs, low risk |
| Talos Backup | Critical for DR | High | Standard etcd backup, uses existing Age keys |
| Talos CCM | High value | High | Official Siderolabs, minimal footprint |
| Proxmox CSI | When needed | Medium | Depends on storage requirements |
| Proxmox CCM | Nice to have | Medium | Overlaps with Talos CCM |
| Proxmox Karpenter | Future | Low | High complexity, requires infrastructure automation |

### Open Questions for Implementation

1. **S3 Storage Selection:** Cloudflare R2 recommended (already using Cloudflare), but MinIO or other S3-compatible options are viable.

2. **Talos API Access Timing:** The machine patch for kubernetesTalosAPIAccess should be added before or during cluster bootstrap for seamless tuppr deployment.

3. **CCM Coordination:** If deploying both Talos CCM and Proxmox CCM, ensure they don't conflict on node labeling.

4. **Storage Strategy:** Evaluate whether Proxmox CSI, in-cluster storage (Longhorn/Rook-Ceph), or NFS best fits workload requirements.

---

## Additional Considerations

### Version Compatibility

**Talos 1.12.0 + Kubernetes 1.35.0 Compatibility:**
- Talos 1.12.0 ships with Kubernetes 1.35.0 by default ([release notes](https://github.com/siderolabs/talos/releases/tag/v1.12.0))
- All researched components are Kubernetes-version-agnostic controllers
- Ensure `talosctl` version matches cluster version when using tuppr

**Component Compatibility Matrix:**

| Component | Min Talos | Min K8s | Notes |
| ----------- | ----------- | --------- | ------- |
| tuppr | Any | 1.25+ | Uses Talos API, version-agnostic |
| Talos CCM | 1.0+ | 1.25+ | Official Siderolabs, tested with latest |
| Talos Backup | 1.0+ | 1.25+ | Uses `os:etcd:backup` role |
| Proxmox CSI | Any | 1.25+ | CSI spec 1.5+ |
| Proxmox CCM | Any | 1.25+ | Standard CCM interface |
| Karpenter Proxmox | Any | 1.25+ | Karpenter v1 API |

### Disaster Recovery: Talos Backup Restore Procedure

**Critical:** Talos-backup is only useful if you know how to restore. Document this runbook:

#### Creating Backups

```bash
# Manual snapshot (without talos-backup helm chart)
talosctl -n <control-plane-ip> etcd snapshot ./etcd-backup.db

# Or copy directly (less consistent but works when etcd is unhealthy)
talosctl -n <control-plane-ip> cp /var/lib/etcd/member/snap/db ./etcd-backup.db
```

#### Restore Procedure

1. **Assess Damage:**
   ```bash
   # Check etcd health across control plane nodes
   talosctl -n <ip1>,<ip2>,<ip3> service etcd
   talosctl -n <ip1>,<ip2>,<ip3> etcd members
   ```

2. **If Quorum Lost (>50% nodes down):**
   ```bash
   # Wipe etcd data on remaining nodes (AFTER taking snapshot!)
   talosctl -n <ip> reset --system-labels-to-wipe=EPHEMERAL --reboot
   ```

3. **Bootstrap from Snapshot:**
   ```bash
   # On ONE control plane node
   talosctl -n <ip> etcd bootstrap --from-backup=./etcd-backup.db

   # If snapshot was copied directly (not via `etcd snapshot`)
   talosctl -n <ip> etcd bootstrap --from-backup=./etcd-backup.db --recover-skip-hash-check
   ```

4. **Verify Recovery:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   flux get ks -A
   ```

**Backup Testing:** Schedule quarterly restore tests to a staging environment.

### Cross-Reference: Infrastructure Automation

This research complements `docs/research/ansible-proxmox-automation.md` (the validated PRIMARY recommendation):

| Aspect | ansible-proxmox-automation.md | This Document |
| -------- | ----------------------------- | --------------- |
| **Focus** | VM provisioning (before K8s) | K8s components (after bootstrap) |
| **Tools** | Ansible + community.proxmox v1.5.0 | Helm charts, Flux, Karpenter |
| **When to Use** | Initial cluster setup, manual scaling | Day-2 operations, auto-scaling |
| **State** | Stateless (no state files) | Kubernetes etcd |

**Decision Tree: Karpenter vs Ansible**

```
Need to add nodes?
├── Is workload predictable/static?
│   └── YES → Use Ansible (ansible-proxmox-automation.md)
│       - Stateless VM provisioning
│       - No state file management
│       - Good for planned capacity
│       - Run `task infrastructure:provision`
│
└── Is workload dynamic/bursty?
    └── YES → Use Karpenter (this document)
        - Auto-scaling based on pending pods
        - Scale to zero capability
        - Good for CI/CD runners, dev environments
        - Requires VM templates created by Ansible
```

### Karpenter + Ansible Integration Strategy

> **Updated January 2026:** Based on our decision to use Ansible + community.proxmox for VM automation instead of OpenTofu/Terraform.

**Key Insight:** Karpenter Proxmox provider uses the **Proxmox API directly** - it does NOT require Terraform or OpenTofu. This makes it fully compatible with our Ansible-based approach.

**How Karpenter Works with Ansible:**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                ANSIBLE + KARPENTER INTEGRATION ARCHITECTURE                  │
└─────────────────────────────────────────────────────────────────────────────┘

  INITIAL PROVISIONING (Ansible)           DYNAMIC SCALING (Karpenter)
  ───────────────────────────────          ─────────────────────────────

  cluster.yaml + nodes.yaml                 Pod pending (unschedulable)
         │                                           │
         ▼                                           ▼
  ┌─────────────────┐                      ┌─────────────────┐
  │ Ansible Playbook│                      │   Karpenter     │
  │ provision-vms   │                      │   Controller    │
  └────────┬────────┘                      └────────┬────────┘
           │                                        │
           ▼                                        ▼
  ┌─────────────────┐                      ┌─────────────────┐
  │  Proxmox API    │◄─────────────────────│  Proxmox API    │
  │  (direct calls) │                      │  (direct calls) │
  └────────┬────────┘                      └────────┬────────┘
           │                                        │
           ▼                                        ▼
  ┌─────────────────┐                      ┌─────────────────┐
  │  Clone from     │                      │  Clone from     │
  │  Talos Template │                      │  Talos Template │
  │  (fixed nodes)  │                      │  (auto-scaled)  │
  └─────────────────┘                      └─────────────────┘

  USE CASE: Initial cluster setup          USE CASE: CI/CD runners, burst
            Planned capacity changes                  Scale to zero workloads
```

**Shared Prerequisite: Talos VM Template**

Both Ansible and Karpenter require a Talos VM template in Proxmox. Use the Ansible playbook to create it:

```bash
# Create Talos template (one-time setup)
task infrastructure:template:create
```

This template is then referenced by:
- **Ansible**: In `provision-vms.yaml` playbook (`talos_template` variable)
- **Karpenter**: In `ProxmoxNodeClass` CR (`instanceTemplateRef` field)

**Karpenter-Specific Requirements:**

1. **Proxmox CCM** (mandatory) - Provides node lifecycle management
2. **VM Template with cloud-init** - Uses NoCloud image from Talos Image Factory
3. **Proxmox API credentials** - Same token as Ansible (stored in SOPS)

**ProxmoxNodeClass Example for Talos:**

```yaml
apiVersion: karpenter.proxmox.sinextra.dev/v1alpha1
kind: ProxmoxNodeClass
metadata:
  name: talos-workers
spec:
  tags:
    - talos
    - karpenter
    - worker
  instanceTemplateRef:
    kind: ProxmoxTemplate
    name: talos-1.12.0  # Same template used by Ansible
  metadataOptions:
    type: cdrom  # NoCloud cloud-init delivery
    templatesRef:
      name: talos-machine-config
      namespace: kube-system
  storage: local-zfs
  memoryMB: 8192
  cores: 4
```

**When to Use Each:**

| Scenario | Use Ansible | Use Karpenter |
| -------- | ----------- | ------------- |
| Initial cluster bootstrap | ✅ | ❌ |
| Add 2 permanent worker nodes | ✅ | ❌ |
| CI/CD runners (scale to zero) | ❌ | ✅ |
| GPU workloads on-demand | ❌ | ✅ |
| Dev environments ephemeral | ❌ | ✅ |
| Replace failed static node | ✅ | ❌ |
| Handle traffic spike | ❌ | ✅ |

**Note:** Karpenter requires Proxmox CCM and VM templates. The template can be created using the Ansible playbook from `ansible-proxmox-automation.md`.

### Renovate Configuration for OCI Charts

Add this to your Renovate config to track Helm chart versions:

```json
{
  "extends": ["config:base"],
  "kubernetes": {
    "fileMatch": ["kubernetes/.+\\.yaml$"]
  },
  "customManagers": [
    {
      "customType": "regex",
      "fileMatch": ["kubernetes/.+ocirepository\\.yaml$"],
      "matchStrings": [
        "url: oci://(?<registryUrl>[^/]+)/(?<depName>.+?)\\s+ref:\\s+tag: (?<currentValue>\\S+)"
      ],
      "datasourceTemplate": "docker",
      "packageNameTemplate": "{{registryUrl}}/{{depName}}"
    }
  ],
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackagePatterns": ["ghcr.io/.*/charts/.*"],
      "groupName": "Helm OCI Charts"
    }
  ]
}
```

### Monitoring and Metrics

**tuppr Prometheus Metrics:**
- Exposes metrics on `/metrics` endpoint
- Key metrics: upgrade progress, health check status, job execution time
- Compatible with Prometheus ServiceMonitor

**Talos CCM Metrics:**
- Exposes standard CCM metrics
- Node lifecycle events, CIDR allocations

**Recommended Alerting:**
```yaml
# Example PrometheusRule for tuppr
groups:
  - name: tuppr
    rules:
      - alert: TalosUpgradeFailed
        expr: tuppr_upgrade_failed_total > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Talos upgrade failed"
      - alert: TalosUpgradeStuck
        expr: tuppr_upgrade_in_progress == 1
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Talos upgrade has been running for over 30 minutes"
```

### S3 Storage Options for Talos Backup

| Provider | Pros | Cons | Recommended For | Monthly Cost |
| ---------- | ------ | ------ | ----------------- | ------------ |
| **Cloudflare R2** | No egress fees, generous free tier | Newer service | Production (if using Cloudflare) | **$0** (free tier) |
| **MinIO (self-hosted)** | Full control, local | Maintenance overhead | Air-gapped environments | Hardware only |
| **Backblaze B2** | Cheap, S3-compatible | Egress fees | Budget-conscious | ~$0.005/GB |
| **AWS S3** | Most mature, reliable | Egress fees, vendor lock-in | Enterprise/AWS shops | ~$0.023/GB + egress |

#### Cloudflare R2 Free Tier (Validated January 2026)

> **Source:** [Cloudflare R2 Pricing](https://developers.cloudflare.com/r2/pricing/)

| Resource | Free Allowance | Our Use Case | Status |
| -------- | -------------- | ------------ | ------ |
| **Storage** | 10 GB-month/month | ~1-2 GB etcd snapshots | ✅ Well within limit |
| **Class A ops** (writes) | 1 million/month | ~180 backups/month (6-hourly) | ✅ Well within limit |
| **Class B ops** (reads) | 10 million/month | Occasional restores | ✅ Well within limit |
| **Egress** | **Always free** | Restore downloads | ✅ No fees ever |

**Cost Estimate for Talos Backup:**
- 6-hourly backups × 30 days = 180 snapshots/month
- Each snapshot ~50-100 MB compressed
- Total storage: ~2-3 GB
- **Monthly cost: $0** (fits entirely within free tier)

**Key Advantage:** Unlike AWS S3/Backblaze, R2 has **zero egress fees**. Restoring backups (even large ones) costs nothing.

**Recommendation:** Cloudflare R2 is **free for our use case** and the project already uses Cloudflare for DNS and tunnels. No additional billing configuration required beyond enabling R2 in the Cloudflare dashboard.
