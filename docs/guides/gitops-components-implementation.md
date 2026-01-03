# GitOps Components Implementation Guide

> **Guide Version:** 1.0.0
> **Last Updated:** January 2026
> **Status:** Ready for Implementation
> **Source Research:** [gitops-examples-integration.md](../research/gitops-examples-integration.md)

---

## Overview

This guide provides step-by-step implementation instructions for integrating cloud-native components researched from community GitOps repositories. All implementations follow the project's established template patterns and conventions.

### Priority Components

| Priority | Component | Value Proposition | Complexity |
| -------- | --------- | ----------------- | ---------- |
| **P0** | tuppr (Talos Upgrade Controller) | Automated OS/K8s upgrades | Low |
| **P1** | Talos CCM | Node labeling, lifecycle management | Low |
| **P1** | Talos Backup | etcd backup with Age encryption | Low-Medium |
| **P2** | Proxmox CSI | Persistent storage from Proxmox | Medium |
| **P3** | Proxmox CCM | Cloud-provider integration | Medium |

### Chart Versions (January 2026)

| Chart | Registry | Version |
| ----- | -------- | ------- |
| tuppr | `ghcr.io/home-operations/charts` | **0.0.51** |
| talos-cloud-controller-manager | `ghcr.io/siderolabs/charts` | **0.5.2** |
| talos-backup | `ghcr.io/sergelogvinov/charts` | **0.1.2** |
| proxmox-csi-plugin | `ghcr.io/sergelogvinov/charts` | **0.5.4** |
| proxmox-cloud-controller-manager | `ghcr.io/sergelogvinov/charts` | **0.2.23** |

> **Tip:** Check for updates with `skopeo list-tags docker://ghcr.io/<org>/charts/<chart>`

---

## Phase 1: Essential Operations

### 1.1 Talos Upgrade Controller (tuppr)

tuppr automates Talos OS and Kubernetes version upgrades through GitOps-driven CRs (Custom Resources).

#### Prerequisites

1. **Talos API Access** - Add machine patch for `kubernetesTalosAPIAccess`
2. **New Namespace** - `system-upgrade` for upgrade controller

#### Step 1: Add Talos Machine Patch

Create the patch file to enable Talos API access from the cluster:

**File:** `templates/config/talos/patches/global/machine-talos-api.yaml.j2`

```yaml
machine:
  features:
    kubernetesTalosAPIAccess:
      allowedKubernetesNamespaces:
        - system-upgrade
        - kube-system
      allowedRoles:
        - os:admin
        - os:etcd:backup
      enabled: true
```

> **Note:** This patch must be applied to all nodes. It will take effect after `task talos:apply-node` or during the next upgrade.

**Role Explanations:**
- `os:admin` - Required for tuppr to perform Talos OS and Kubernetes upgrades
- `os:etcd:backup` - Required for talos-backup to create etcd snapshots

**Namespace Explanations:**
- `system-upgrade` - Where tuppr runs
- `kube-system` - Where talos-backup runs

#### Step 2: Create Namespace Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/system-upgrade/tuppr/app
```

#### Step 3: Create Namespace Files

**File:** `templates/config/kubernetes/apps/system-upgrade/namespace.yaml.j2`

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: system-upgrade
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

**File:** `templates/config/kubernetes/apps/system-upgrade/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: system-upgrade

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./tuppr/ks.yaml
```

#### Step 4: Create tuppr Templates

**File:** `templates/config/kubernetes/apps/system-upgrade/tuppr/ks.yaml.j2`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tuppr
spec:
  interval: 1h
  path: ./kubernetes/apps/system-upgrade/tuppr/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: system-upgrade
  wait: false
```

**File:** `templates/config/kubernetes/apps/system-upgrade/tuppr/app/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./talosupgrade.yaml
  - ./kubernetesupgrade.yaml
```

**File:** `templates/config/kubernetes/apps/system-upgrade/tuppr/app/ocirepository.yaml.j2`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: tuppr
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.0.51
  url: oci://ghcr.io/home-operations/charts/tuppr
```

**File:** `templates/config/kubernetes/apps/system-upgrade/tuppr/app/helmrelease.yaml.j2`

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tuppr
spec:
  chartRef:
    kind: OCIRepository
    name: tuppr
  interval: 1h
  values:
    fullnameOverride: tuppr
    serviceMonitor:
      enabled: true
```

**File:** `templates/config/kubernetes/apps/system-upgrade/tuppr/app/talosupgrade.yaml.j2`

```yaml
---
apiVersion: tuppr.home-operations.com/v1alpha1
kind: TalosUpgrade
metadata:
  name: talos
spec:
  talos:
    version: "#{ talos_version }#"
  policy:
    rebootMode: default
  healthChecks:
    - apiVersion: v1
      kind: Node
      expr: status.conditions.exists(c, c.type == "Ready" && c.status == "True")
      timeout: 10m
```

**File:** `templates/config/kubernetes/apps/system-upgrade/tuppr/app/kubernetesupgrade.yaml.j2`

```yaml
---
apiVersion: tuppr.home-operations.com/v1alpha1
kind: KubernetesUpgrade
metadata:
  name: kubernetes
spec:
  kubernetes:
    version: "#{ kubernetes_version }#"
  healthChecks:
    - apiVersion: v1
      kind: Node
      expr: status.conditions.exists(c, c.type == "Ready" && c.status == "True")
      timeout: 10m
```

#### Step 5: Add cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# Talos Upgrade Controller (tuppr)
# =============================================================================
# Versions for automated upgrades via tuppr CRs
talos_version: "1.12.0"
kubernetes_version: "1.35.0"
```

#### Step 6: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  - ./system-upgrade
```

#### Step 7: Deploy

```bash
# Regenerate templates
task configure

# Apply Talos patch to all nodes
for ip in $(yq '.nodes[].ip' nodes.yaml); do
  task talos:apply-node IP=$ip
done

# Commit and push
git add -A
git commit -m "feat: add tuppr for automated Talos/K8s upgrades"
git push

# Reconcile
task reconcile
```

#### Verification

```bash
# Check tuppr deployment
kubectl -n system-upgrade get pods

# Check upgrade CRs
kubectl get talosupgrade,kubernetesupgrade

# View tuppr metrics
kubectl -n system-upgrade port-forward svc/tuppr 8080:8080
curl http://localhost:8080/metrics | grep tuppr
```

---

### 1.2 Talos Backup

Talos Backup provides automated etcd snapshots with S3 storage and Age encryption.

#### Prerequisites

1. **Talos API Access** - Already configured in Section 1.1, Step 1 (includes `os:etcd:backup` role and `kube-system` namespace)
2. **S3 Storage** - Cloudflare R2 recommended (free tier, zero egress fees)
3. **Age Keypair** - Reuse existing or generate new

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/kube-system/talos-backup/app
```

#### Step 2: Create Template Files

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/ks.yaml.j2`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: talos-backup
spec:
  interval: 12h
  path: ./kubernetes/apps/kube-system/talos-backup/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: kube-system
  wait: false
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./secret.sops.yaml
  - ./serviceaccount.yaml
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/serviceaccount.yaml.j2`

This Talos ServiceAccount grants the backup job permission to access the Talos API with the `os:etcd:backup` role:

```yaml
---
apiVersion: talos.dev/v1alpha1
kind: ServiceAccount
metadata:
  name: talos-backup
spec:
  roles:
    - os:etcd:backup
```

> **Note:** The `talos.dev/v1alpha1 ServiceAccount` is a Talos-specific CRD that bridges Kubernetes ServiceAccounts with Talos API roles. This is different from core Kubernetes ServiceAccounts.

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/ocirepository.yaml.j2`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: talos-backup
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.1.2
  url: oci://ghcr.io/sergelogvinov/charts/talos-backup
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/helmrelease.yaml.j2`

```yaml
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
            name: talos-backup-secrets
            key: age-public-key
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: talos-backup-secrets
            key: aws-access-key-id
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: talos-backup-secrets
            key: aws-secret-access-key
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-backup/app/secret.sops.yaml.j2`

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: talos-backup-secrets
type: Opaque
stringData:
  age-public-key: "#{ backup_age_public_key }#"
  aws-access-key-id: "#{ backup_s3_access_key }#"
  aws-secret-access-key: "#{ backup_s3_secret_key }#"
```

#### Step 3: Add cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# Talos Backup Configuration
# =============================================================================
# S3-compatible storage for etcd backups (Cloudflare R2 recommended)
backup_s3_endpoint: "https://<account-id>.r2.cloudflarestorage.com"
backup_s3_bucket: "cluster-backups"
backup_s3_access_key: "ENC[AES256_GCM,...]"  # SOPS encrypted
backup_s3_secret_key: "ENC[AES256_GCM,...]"  # SOPS encrypted

# Age public key for backup encryption (use same as cluster Age key)
backup_age_public_key: "age1..."
```

#### Step 4: Update kube-system Kustomization

**Edit:** `templates/config/kubernetes/apps/kube-system/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  - ./talos-backup/ks.yaml
```

> **Note:** The Talos machine patch for `kubernetesTalosAPIAccess` was already configured in Section 1.1, Step 1, which includes both the `os:etcd:backup` role and the `kube-system` namespace required for talos-backup.

#### Step 5: Deploy

```bash
# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "feat: add talos-backup for etcd disaster recovery"
git push

# Reconcile
task reconcile
```

> **Note:** If you haven't yet applied the Talos machine patch from Section 1.1, you'll need to apply it to all nodes before talos-backup will work:
> ```bash
> for ip in $(yq '.nodes[].ip' nodes.yaml); do
>   task talos:apply-node IP=$ip
> done
> ```

#### Verification

```bash
# Check backup job
kubectl -n kube-system get cronjobs | grep talos-backup

# Manual backup trigger
kubectl -n kube-system create job --from=cronjob/talos-backup manual-backup

# Check backup status
kubectl -n kube-system logs job/manual-backup

# Verify in S3 (using aws-cli or rclone)
rclone ls r2:cluster-backups/
```

#### Restore Procedure

See [Disaster Recovery: Talos Backup Restore Procedure](../research/gitops-examples-integration.md#disaster-recovery-talos-backup-restore-procedure) in the research document.

---

## Phase 2: Cloud Integration

### 2.1 Talos Cloud Controller Manager

Talos CCM provides node labeling, lifecycle management, and topology awareness for Talos Linux clusters.

> **Talos CCM vs Proxmox CCM:** Use **Talos CCM** (this section) for generic/multi-cloud Talos deployments. Use **Proxmox CCM** (section 2.3) when you need Proxmox-specific features like VM ID-based provider IDs, automatic zone detection from hypervisor hostname, or integration with Proxmox CSI for storage topology. Both CCMs should NOT run simultaneously.

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/kube-system/talos-ccm/app
```

#### Step 2: Create Template Files

**File:** `templates/config/kubernetes/apps/kube-system/talos-ccm/ks.yaml.j2`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: talos-ccm
spec:
  interval: 1h
  path: ./kubernetes/apps/kube-system/talos-ccm/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: kube-system
  wait: false
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-ccm/app/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-ccm/app/ocirepository.yaml.j2`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: talos-ccm
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.5.2
  url: oci://ghcr.io/siderolabs/charts/talos-cloud-controller-manager
```

**File:** `templates/config/kubernetes/apps/kube-system/talos-ccm/app/helmrelease.yaml.j2`

```yaml
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
    logVerbosityLevel: 2
    useDaemonSet: true
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
```

#### Step 3: Update kube-system Kustomization

**Edit:** `templates/config/kubernetes/apps/kube-system/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  - ./talos-ccm/ks.yaml
```

#### Step 4: Deploy

```bash
task configure
git add -A
git commit -m "feat: add Talos CCM for node labeling and lifecycle"
git push
task reconcile
```

#### Verification

```bash
# Check CCM deployment
kubectl -n kube-system get pods -l app.kubernetes.io/name=talos-cloud-controller-manager

# Verify node labels
kubectl get nodes -o yaml | grep -A5 "labels:"

# Expected labels include:
# - node.kubernetes.io/instance-type
# - topology.kubernetes.io/region
# - topology.kubernetes.io/zone
```

---

### 2.2 Proxmox CSI Driver

Proxmox CSI provisions PersistentVolumes directly on Proxmox storage.

#### Prerequisites

1. **Proxmox API Token** - With storage permissions (see below)
2. **Privileged Namespace** - CSI requires privileged pod security

##### Create Proxmox CSI Role and Token (Proxmox v8/v9)

Run these commands on any Proxmox node via SSH or the web console Shell:

**Step 1: Create CSI Role with Required Permissions**

```bash
# Basic CSI permissions (standard storage operations)
pveum role add CSI -privs "Sys.Audit VM.Audit VM.Config.Disk Datastore.Allocate Datastore.AllocateSpace Datastore.Audit"
```

**Extended permissions** (if using ZFS replication or VM migration):

```bash
# Extended CSI permissions (includes VM operations for ZFS replication)
pveum role add CSI -privs "Sys.Audit VM.Audit VM.Allocate VM.Clone VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Options VM.Migrate VM.PowerMgmt Datastore.Allocate Datastore.AllocateSpace Datastore.Audit"
```

**Step 2: Create Dedicated User**

```bash
# Create user for CSI (realm: pve = Proxmox VE authentication)
pveum user add kubernetes-csi@pve
```

**Step 3: Assign Role to User**

```bash
# Grant CSI role cluster-wide (/ = root path)
pveum aclmod / -user kubernetes-csi@pve -role CSI
```

**Step 4: Create API Token**

```bash
# Create API token (privsep=0 means token inherits user permissions)
pveum user token add kubernetes-csi@pve csi -privsep 0
```

> **Important:** Save the token output! The secret is only shown once. Format: `kubernetes-csi@pve!csi` (token_id) and a UUID secret.

**Permission Reference:**

| Permission | Purpose |
| ------------ | --------- |
| `Sys.Audit` | Read system configuration |
| `VM.Audit` | Read VM configuration |
| `VM.Config.Disk` | Attach/detach disks to VMs |
| `Datastore.Allocate` | Create volumes on datastore |
| `Datastore.AllocateSpace` | Allocate space on datastore |
| `Datastore.Audit` | Read datastore configuration |

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/app
```

#### Step 2: Create Namespace Files

**File:** `templates/config/kubernetes/apps/csi-proxmox/namespace.yaml.j2`

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: csi-proxmox
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

**File:** `templates/config/kubernetes/apps/csi-proxmox/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: csi-proxmox

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  #% if proxmox_csi_enabled is defined and proxmox_csi_enabled %#
  - ./proxmox-csi/ks.yaml
  #% endif %#
```

#### Step 3: Create Proxmox CSI Templates

**File:** `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/ks.yaml.j2`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: proxmox-csi
spec:
  interval: 1h
  path: ./kubernetes/apps/csi-proxmox/proxmox-csi/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: csi-proxmox
  wait: false
```

**File:** `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/app/kustomization.yaml.j2`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./secret.sops.yaml
```

**File:** `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/app/ocirepository.yaml.j2`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: proxmox-csi
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.5.4
  url: oci://ghcr.io/sergelogvinov/charts/proxmox-csi-plugin
```

**File:** `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/app/helmrelease.yaml.j2`

```yaml
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
        storage: "#{ proxmox_csi_storage }#"
        reclaimPolicy: Delete
        fstype: ext4
        ssd: true
    config:
      clusters:
        - url: "#{ proxmox_endpoint }#"
          insecure: false
          token_id: "#{ proxmox_token_id }#"
          token_secret: "#{ proxmox_token_secret }#"
          region: "#{ proxmox_region | default('pve') }#"
```

**File:** `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/app/secret.sops.yaml.j2`

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-csi-config
type: Opaque
stringData:
  token_id: "#{ proxmox_token_id }#"
  token_secret: "#{ proxmox_token_secret }#"
```

#### Step 4: Add cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# Proxmox CSI Configuration
# =============================================================================
# Enable Proxmox CSI for persistent storage
proxmox_csi_enabled: true

# Proxmox API endpoint
proxmox_endpoint: "https://pve.example.com:8006"

# Proxmox API token (format: user@realm!token-name)
proxmox_token_id: "kubernetes-csi@pve!csi"
proxmox_token_secret: "ENC[AES256_GCM,...]"  # SOPS encrypted

# Proxmox storage pool for PVs
proxmox_csi_storage: "local-zfs"

# Proxmox region identifier
proxmox_region: "pve"
```

#### Step 5: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  - ./csi-proxmox
```

#### Step 6: Deploy

```bash
task configure
git add -A
git commit -m "feat: add Proxmox CSI for persistent storage"
git push
task reconcile
```

#### Verification

```bash
# Check CSI deployment
kubectl -n csi-proxmox get pods

# Verify storage class
kubectl get storageclass proxmox-zfs

# Test PVC creation
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: proxmox-zfs
  resources:
    requests:
      storage: 1Gi
EOF

# Verify PV was created
kubectl get pv,pvc

# Clean up test
kubectl delete pvc test-pvc
```

---

### 2.3 Proxmox Cloud Controller Manager

Proxmox CCM provides node labeling, lifecycle management, and topology awareness for Kubernetes clusters running on Proxmox infrastructure.

#### Features

- **Node Initialization**: Automatically initializes new nodes when they join the cluster
- **Label Assignment**: Applies topology and instance-type labels based on Proxmox VM configuration
- **Node Cleanup**: Removes node resources when VMs are deleted from Proxmox
- **Multi-cluster Support**: Supports single Kubernetes cluster spanning multiple Proxmox clusters
- **Provider ID**: Sets `providerID` in format `proxmox://region/vmid`

**Labels Applied:**
- `topology.kubernetes.io/region` - Proxmox cluster name
- `topology.kubernetes.io/zone` - Proxmox hypervisor hostname
- `node.kubernetes.io/instance-type` - Generated from CPU/RAM configuration

#### Prerequisites

1. **Proxmox API Token** - With audit permissions (see below)
2. **Talos Configuration** - External cloud provider enabled (optional but recommended)

##### Create Proxmox CCM Role and Token (Proxmox v8/v9)

Run these commands on any Proxmox node via SSH or the web console Shell:

**Step 1: Create CCM Role with Required Permissions**

```bash
# CCM only needs audit permissions (read-only)
pveum role add CCM -privs "VM.Audit Sys.Audit"
```

**Step 2: Create Dedicated User**

```bash
# Create user for CCM (realm: pve = Proxmox VE authentication)
pveum user add kubernetes-ccm@pve
```

**Step 3: Assign Role to User**

```bash
# Grant CCM role cluster-wide (/ = root path)
pveum aclmod / -user kubernetes-ccm@pve -role CCM
```

**Step 4: Create API Token**

```bash
# Create API token (privsep=0 means token inherits user permissions)
pveum user token add kubernetes-ccm@pve ccm -privsep 0
```

> **Important:** Save the token output! The secret is only shown once. Format: `kubernetes-ccm@pve!ccm` (token_id) and a UUID secret.

**Permission Reference:**

| Permission | Purpose |
| ------------ | --------- |
| `VM.Audit` | Read VM configuration and metadata |
| `Sys.Audit` | Read system/cluster configuration |

> **Note:** CCM permissions are read-only unlike CSI which needs storage write permissions.

##### Optional: Enable External Cloud Provider in Talos

For full integration, add a Talos machine patch to enable external cloud provider mode:

**File:** `templates/config/talos/patches/global/machine-cloud-provider.yaml.j2`

```yaml
#% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
cluster:
  externalCloudProvider:
    enabled: true
#% endif %#
```

> **Note:** This patch tells kubelet to wait for CCM to initialize node labels before scheduling workloads. Without it, nodes may briefly schedule pods before labels are applied.

#### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/kube-system/proxmox-ccm/app
```

#### Step 2: Create Template Files

**File:** `templates/config/kubernetes/apps/kube-system/proxmox-ccm/ks.yaml.j2`

```yaml
#% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: proxmox-ccm
spec:
  interval: 1h
  path: ./kubernetes/apps/kube-system/proxmox-ccm/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: kube-system
  wait: false
#% endif %#
```

**File:** `templates/config/kubernetes/apps/kube-system/proxmox-ccm/app/kustomization.yaml.j2`

```yaml
#% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./secret.sops.yaml
#% endif %#
```

**File:** `templates/config/kubernetes/apps/kube-system/proxmox-ccm/app/ocirepository.yaml.j2`

```yaml
#% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: proxmox-ccm
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 0.2.23
  url: oci://ghcr.io/sergelogvinov/charts/proxmox-cloud-controller-manager
#% endif %#
```

**File:** `templates/config/kubernetes/apps/kube-system/proxmox-ccm/app/helmrelease.yaml.j2`

```yaml
#% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
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
    logVerbosityLevel: 2
    useDaemonSet: true
    enabledControllers:
      - cloud-node
      - cloud-node-lifecycle
    existingConfigSecret: proxmox-ccm-config
    existingConfigSecretKey: config.yaml
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
      - effect: NoSchedule
        key: node.cloudprovider.kubernetes.io/uninitialized
        operator: Exists
#% endif %#
```

**File:** `templates/config/kubernetes/apps/kube-system/proxmox-ccm/app/secret.sops.yaml.j2`

```yaml
#% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
---
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-ccm-config
type: Opaque
stringData:
  config.yaml: |
    clusters:
      - url: "#{ proxmox_endpoint }#/api2/json"
        insecure: false
        token_id: "#{ proxmox_ccm_token_id }#"
        token_secret: "#{ proxmox_ccm_token_secret }#"
        region: "#{ proxmox_region | default('pve') }#"
#% endif %#
```

#### Step 3: Add cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# Proxmox CCM Configuration (Optional)
# =============================================================================
# Enable Proxmox CCM for node labeling and lifecycle management
proxmox_ccm_enabled: true

# Proxmox API endpoint (shared with CSI if both enabled)
proxmox_endpoint: "https://pve.example.com:8006"

# Proxmox CCM API token (format: user@realm!token-name)
# Note: Use separate token from CSI for least-privilege principle
proxmox_ccm_token_id: "kubernetes-ccm@pve!ccm"
proxmox_ccm_token_secret: "ENC[AES256_GCM,...]"  # SOPS encrypted

# Proxmox region identifier (cluster name)
proxmox_region: "pve"
```

#### Step 4: Update kube-system Kustomization

**Edit:** `templates/config/kubernetes/apps/kube-system/kustomization.yaml.j2`

Add to resources list:

```yaml
resources:
  # ... existing entries ...
  #% if proxmox_ccm_enabled is defined and proxmox_ccm_enabled %#
  - ./proxmox-ccm/ks.yaml
  #% endif %#
```

#### Step 5: Deploy

```bash
task configure
git add -A
git commit -m "feat: add Proxmox CCM for node labeling and lifecycle"
git push
task reconcile
```

#### Verification

```bash
# Check CCM deployment
kubectl -n kube-system get pods -l app.kubernetes.io/name=proxmox-cloud-controller-manager

# Verify node labels
kubectl get nodes -o yaml | grep -A10 "labels:"

# Expected labels:
# - topology.kubernetes.io/region: pve
# - topology.kubernetes.io/zone: <proxmox-host>
# - node.kubernetes.io/instance-type: <cpu-ram-based>

# Check provider ID
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'
# Expected format: proxmox://pve/100 (where 100 is VM ID)

# View CCM logs
kubectl -n kube-system logs -l app.kubernetes.io/name=proxmox-cloud-controller-manager -f
```

#### Troubleshooting

| Issue | Solution |
| ------- | --------- |
| Nodes not getting labels | Check CCM logs for API errors, verify token permissions |
| `node.cloudprovider.kubernetes.io/uninitialized` taint persists | CCM not running or cannot reach Proxmox API |
| Wrong region/zone labels | ProviderID is immutable; delete node resource and restart kubelet |
| Multiple CCM pods fighting | Ensure only one CCM deployment (Talos CCM vs Proxmox CCM) |

---

## Configuration Reference

### cluster.yaml Additions Summary

```yaml
# =============================================================================
# Talos Upgrade Controller (tuppr)
# =============================================================================
talos_version: "1.12.0"
kubernetes_version: "1.35.0"

# =============================================================================
# Talos Backup Configuration
# =============================================================================
backup_s3_endpoint: "https://<account-id>.r2.cloudflarestorage.com"
backup_s3_bucket: "cluster-backups"
backup_s3_access_key: "ENC[AES256_GCM,...]"
backup_s3_secret_key: "ENC[AES256_GCM,...]"
backup_age_public_key: "age1..."

# =============================================================================
# Proxmox CSI Configuration (Optional)
# =============================================================================
proxmox_csi_enabled: false  # Set to true when needed
proxmox_endpoint: "https://pve.example.com:8006"
proxmox_token_id: "kubernetes-csi@pve!csi"
proxmox_token_secret: "ENC[AES256_GCM,...]"
proxmox_csi_storage: "local-zfs"
proxmox_region: "pve"

# =============================================================================
# Proxmox CCM Configuration (Optional)
# =============================================================================
proxmox_ccm_enabled: false  # Set to true when needed
# proxmox_endpoint shared with CSI above
proxmox_ccm_token_id: "kubernetes-ccm@pve!ccm"
proxmox_ccm_token_secret: "ENC[AES256_GCM,...]"
# proxmox_region shared with CSI above
```

### Template Directory Structure

After implementation, the template structure should be:

```
templates/config/
├── kubernetes/apps/
│   ├── system-upgrade/
│   │   ├── namespace.yaml.j2
│   │   ├── kustomization.yaml.j2
│   │   └── tuppr/
│   │       ├── ks.yaml.j2
│   │       └── app/
│   │           ├── kustomization.yaml.j2
│   │           ├── ocirepository.yaml.j2
│   │           ├── helmrelease.yaml.j2
│   │           ├── talosupgrade.yaml.j2
│   │           └── kubernetesupgrade.yaml.j2
│   ├── kube-system/
│   │   ├── talos-backup/
│   │   │   ├── ks.yaml.j2
│   │   │   └── app/
│   │   │       ├── kustomization.yaml.j2
│   │   │       ├── ocirepository.yaml.j2
│   │   │       ├── helmrelease.yaml.j2
│   │   │       ├── serviceaccount.yaml.j2
│   │   │       └── secret.sops.yaml.j2
│   │   ├── talos-ccm/
│   │   │   ├── ks.yaml.j2
│   │   │   └── app/
│   │   │       ├── kustomization.yaml.j2
│   │   │       ├── ocirepository.yaml.j2
│   │   │       └── helmrelease.yaml.j2
│   │   └── proxmox-ccm/
│   │       ├── ks.yaml.j2
│   │       └── app/
│   │           ├── kustomization.yaml.j2
│   │           ├── ocirepository.yaml.j2
│   │           ├── helmrelease.yaml.j2
│   │           └── secret.sops.yaml.j2
│   └── csi-proxmox/
│       ├── namespace.yaml.j2
│       ├── kustomization.yaml.j2
│       └── proxmox-csi/
│           ├── ks.yaml.j2
│           └── app/
│               ├── kustomization.yaml.j2
│               ├── ocirepository.yaml.j2
│               ├── helmrelease.yaml.j2
│               └── secret.sops.yaml.j2
└── talos/patches/global/
    ├── machine-talos-api.yaml.j2
    └── machine-cloud-provider.yaml.j2  # Optional: for Proxmox CCM
```

---

## Implementation Checklist

### Phase 1: Essential Operations

- [ ] **tuppr (Talos Upgrade Controller)**
  - [ ] Create `machine-talos-api.yaml.j2` Talos patch (includes both `os:admin` and `os:etcd:backup` roles)
  - [ ] Create `system-upgrade` namespace templates
  - [ ] Create tuppr HelmRelease and CRs
  - [ ] Add `talos_version` and `kubernetes_version` to cluster.yaml
  - [ ] Apply Talos patches to all nodes
  - [ ] Deploy and verify

- [ ] **Talos Backup**
  - [ ] Configure S3 storage (Cloudflare R2 recommended)
  - [ ] Create talos-backup templates in kube-system (includes Talos ServiceAccount)
  - [ ] Add backup configuration to cluster.yaml
  - [ ] Deploy and test backup job

### Phase 2: Cloud Integration

- [ ] **Talos CCM**
  - [ ] Create talos-ccm templates in kube-system
  - [ ] Deploy and verify node labels

- [ ] **Proxmox CSI** (when persistent storage needed)
  - [ ] Create Proxmox API token with storage permissions
  - [ ] Create `csi-proxmox` namespace with privileged PSS
  - [ ] Create proxmox-csi templates
  - [ ] Add Proxmox configuration to cluster.yaml
  - [ ] Deploy and test PVC creation

- [ ] **Proxmox CCM** (when topology labels needed)
  - [ ] Create Proxmox API token with audit permissions
  - [ ] Create proxmox-ccm templates in kube-system
  - [ ] Add Proxmox CCM configuration to cluster.yaml
  - [ ] Optional: Add external cloud provider Talos patch
  - [ ] Deploy and verify node labels

---

## References

### Component Documentation

- [tuppr](https://github.com/home-operations/tuppr) - Talos Upgrade Controller
- [Talos CCM](https://github.com/siderolabs/talos-cloud-controller-manager) - Official Talos Cloud Controller Manager
- [talos-backup](https://github.com/sergelogvinov/helm-charts/tree/master/charts/talos-backup) - Talos etcd Backup
- [Proxmox CSI](https://github.com/sergelogvinov/proxmox-csi-plugin) - Proxmox CSI Driver
- [Proxmox CCM](https://github.com/sergelogvinov/proxmox-cloud-controller-manager) - Proxmox Cloud Controller Manager

### Project Documentation

- [Research: GitOps Examples Integration](../research/gitops-examples-integration.md) - Source research document
- [Architecture](../ARCHITECTURE.md) - System design
- [Configuration](../CONFIGURATION.md) - Schema reference
- [Talos Operations](../ai-context/talos-operations.md) - Talos patterns
