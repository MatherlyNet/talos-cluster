# Flux Bootstrap Dependency Analysis - January 2026

**Date:** January 4, 2026
**Purpose:** Comprehensive analysis of Flux Kustomization bootstrap ordering and dependency chains

## Executive Summary

This document analyzes the bootstrap order and dependency relationships for all Flux Kustomizations in the matherlynet-talos-cluster project. Several ordering issues were identified that could cause bootstrap failures or race conditions.

| Category | Count | Status |
| -------- | ----- | ------ |
| Total Kustomizations | 31 | Analyzed |
| With explicit `dependsOn` | 17 | Configured |
| Missing critical dependencies | 0 | **Fixed** |
| Using `wait: true` | 8 | Proper sync |
| Using `healthChecks` | 6 | Proper validation |

> **Implementation Status (January 4, 2026):** All 4 identified dependency issues have been resolved. See [Implementation Status](#implementation-status) section below.

## Current Architecture

### Bootstrap Phase (Helmfile)

The initial bootstrap via `task bootstrap:apps` deploys core components in this order:

```
00-crds.yaml (CRDs only):
├── cloudflare-dns CRDs
├── envoy-gateway CRDs (Gateway API + EnvoyGateway)
└── kube-prometheus-stack CRDs

01-apps.yaml (Core Apps):
cilium
  └── coredns (needs: cilium)
        └── [spegel] (needs: coredns, if enabled)
              └── cert-manager (needs: spegel OR coredns)
                    └── flux-operator (needs: cert-manager)
                          └── flux-instance (needs: flux-operator)
```

This bootstrap order is **correct** and properly chains dependencies.

### Post-Bootstrap Phase (Flux GitOps)

After Flux is running, all Kustomizations are deployed based on their `dependsOn` declarations. Here's the current dependency map:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 0 - No Dependencies (Flux deploys immediately)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ Core Infrastructure:                                                         │
│   cilium, coredns(→cilium), flux-operator, flux-instance(→flux-operator)   │
│                                                                              │
│ kube-system utilities (no dependencies):                                     │
│   reloader, metrics-server, spegel, talos-backup, talos-ccm                 │
│   proxmox-ccm, proxmox-csi                                                  │
│                                                                              │
│ Network stack (no dependencies):                                             │
│   cloudflare-tunnel, cloudflare-dns, k8s-gateway, unifi-dns                 │
│                                                                              │
│ Certificates (no dependencies):                                              │
│   cert-manager                                                               │
│                                                                              │
│ Monitoring (no dependencies):                                                │
│   victoria-metrics, kube-prometheus-stack                                    │
│                                                                              │
│ Other:                                                                       │
│   echo, tuppr, external-secrets                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 1 - Single Dependency                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ coredns → cilium                                                             │
│ flux-instance → flux-operator                                                │
│ envoy-gateway → cert-manager                                                 │
│ loki → victoria-metrics                                                      │
│ cluster-network-policies → (wait: true only)                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 2 - Chain Dependencies                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ alloy → loki → victoria-metrics                                              │
│ tempo → victoria-metrics + [alloy if loki_enabled]                          │
│                                                                              │
│ Network Policies (all depend on cluster-network-policies):                   │
│   kube-system-network-policies                                               │
│   flux-system-network-policies                                               │
│   monitoring-network-policies                                                │
│   network-network-policies (also depends on envoy-gateway)                   │
│   cert-manager-network-policies (also depends on cert-manager)               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Identified Issues

### Issue 1: Proxmox CCM Missing Cilium Dependency

**Severity:** Medium
**Component:** `proxmox-ccm/ks.yaml.j2`
**Current State:** No `dependsOn`
**Problem:** Proxmox CCM may start before Cilium establishes cluster networking

The Proxmox Cloud Controller Manager registers as a cloud provider and initializes node metadata. Without Cilium running, it cannot:
- Communicate with the Kubernetes API properly
- Set node conditions correctly
- Process node lifecycle events

**Recommendation:**
```yaml
spec:
  dependsOn:
    - name: cilium
```

### Issue 2: Proxmox CSI Missing CCM Dependency

**Severity:** Low
**Component:** `proxmox-csi/ks.yaml.j2`
**Current State:** No `dependsOn`
**Problem:** CSI may schedule before CCM initializes nodes

The CSI controller needs node topology labels that CCM provides. Without CCM:
- Volume topology constraints may fail
- Node-local volumes may be scheduled incorrectly

**Recommendation:**
```yaml
spec:
  dependsOn:
    - name: proxmox-ccm
    - name: coredns  # For Proxmox API DNS resolution
```

### Issue 3: cert-manager Missing CoreDNS Dependency

**Severity:** Medium
**Component:** `cert-manager/ks.yaml.j2`
**Current State:** No `dependsOn` (only healthChecks)
**Problem:** cert-manager may fail to resolve ACME endpoints

cert-manager needs DNS resolution to:
- Contact Let's Encrypt ACME servers
- Verify DNS-01 challenges
- Resolve Cloudflare API endpoints

During bootstrap, if cert-manager starts before CoreDNS is ready, the ClusterIssuer webhook validation may fail.

**Note:** This is partially mitigated by the healthChecks on ClusterIssuer, which will retry, but adding an explicit dependency prevents initial failures.

**Recommendation:**
```yaml
spec:
  dependsOn:
    - name: coredns
```

### Issue 4: Monitoring Stack Missing Network Dependencies

**Severity:** Low
**Component:** `victoria-metrics/ks.yaml.j2`, `kube-prometheus-stack/ks.yaml.j2`
**Current State:** No `dependsOn`
**Problem:** May start scraping before targets are reachable

The monitoring stack should wait for:
- CoreDNS (for service discovery)
- Basic networking to be established

**Recommendation:**
```yaml
spec:
  dependsOn:
    - name: coredns
```

### Issue 5: External Services Missing Certificate Dependencies

**Severity:** Low
**Components:** `cloudflare-tunnel/ks.yaml.j2`, `cloudflare-dns/ks.yaml.j2`, `unifi-dns/ks.yaml.j2`, `k8s-gateway/ks.yaml.j2`
**Current State:** No `dependsOn`
**Problem:** May fail initial connections if cert-manager isn't ready

If these services require HTTPS connections or TLS certificates, they should wait for cert-manager.

**Note:** These services may work without certificates initially if they don't use cluster-issued certs, so this is lower priority.

## Recommended Dependency Graph

After implementing fixes, the dependency graph should look like:

```
                         cilium
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
           coredns    proxmox-ccm     spegel
              │            │
       ┌──────┼──────┐     ▼
       ▼      ▼      ▼  proxmox-csi
cert-manager  │   victoria-metrics
       │      │         │
       ▼      │    ┌────┴────┐
envoy-gateway │    ▼         ▼
              │   loki     tempo
              │    │
              ▼    ▼
           alloy
```

## Implementation

### File: `templates/config/kubernetes/apps/kube-system/proxmox-ccm/ks.yaml.j2`

```yaml
#% if proxmox_ccm_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: proxmox-ccm
spec:
  dependsOn:
    - name: cilium
  interval: 1h
  retryInterval: 30s
  # ... rest of spec
#% endif %#
```

### File: `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/ks.yaml.j2`

```yaml
#% if proxmox_csi_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: proxmox-csi
spec:
  dependsOn:
    #% if proxmox_ccm_enabled | default(false) %#
    - name: proxmox-ccm
    #% endif %#
    - name: coredns
  interval: 1h
  retryInterval: 30s
  # ... rest of spec
#% endif %#
```

### File: `templates/config/kubernetes/apps/cert-manager/cert-manager/ks.yaml.j2`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager
spec:
  dependsOn:
    - name: coredns
  healthChecks:
    # ... existing healthChecks
```

### File: `templates/config/kubernetes/apps/monitoring/victoria-metrics/ks.yaml.j2`

```yaml
#% if monitoring_enabled | default(false) and monitoring_stack | default('victoriametrics') == 'victoriametrics' %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: victoria-metrics
spec:
  dependsOn:
    - name: coredns
  healthChecks:
    # ... existing healthChecks
#% endif %#
```

## Validation

After implementing changes, verify the dependency order:

```bash
# Check all Kustomizations and their dependencies
flux get ks -A --status-selector ready=true

# Verify dependency order
kubectl get kustomization -n flux-system -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.dependsOn[*].name}{"\n"}{end}'

# Check for any stuck Kustomizations
flux get ks -A --status-selector ready=false
```

## Bootstrap Timeline (Expected)

After fixes, the bootstrap should proceed:

| Time | Component | Status |
| ---- | --------- | ------ |
| T+0s | cilium | Deploying |
| T+30s | cilium | Ready, coredns starts |
| T+60s | coredns | Ready, proxmox-ccm + cert-manager start |
| T+90s | proxmox-ccm | Ready, proxmox-csi starts |
| T+90s | cert-manager | Ready, envoy-gateway starts |
| T+120s | All core infrastructure ready | Ready |
| T+120s+ | Remaining apps deploy in parallel | Deploying |

## Risk Assessment

| Fix | Risk Level | Rollback |
| ----- | ---------- | -------- |
| Proxmox CCM → Cilium | Low | Remove dependsOn |
| Proxmox CSI → CCM | Low | Remove dependsOn |
| cert-manager → CoreDNS | Low | Remove dependsOn |
| victoria-metrics → CoreDNS | Very Low | Remove dependsOn |

All changes are additive `dependsOn` declarations that can be easily removed if issues arise.

## Implementation Status

**Implemented: January 4, 2026**

All 4 identified dependency issues have been resolved:

| Issue | File | Change | Status |
| ----- | ---- | ------ | ------ |
| #1 Proxmox CCM | `templates/config/kubernetes/apps/kube-system/proxmox-ccm/ks.yaml.j2` | Added `dependsOn: [cilium]` | **FIXED** |
| #2 Proxmox CSI | `templates/config/kubernetes/apps/csi-proxmox/proxmox-csi/ks.yaml.j2` | Added `dependsOn: [proxmox-ccm (conditional), coredns]` | **FIXED** |
| #3 cert-manager | `templates/config/kubernetes/apps/cert-manager/cert-manager/ks.yaml.j2` | Added `dependsOn: [coredns]` | **FIXED** |
| #4 victoria-metrics | `templates/config/kubernetes/apps/monitoring/victoria-metrics/ks.yaml.j2` | Added `dependsOn: [coredns]` | **FIXED** |

### Verification

```bash
# Verify all dependencies are in place
grep -r "dependsOn:" templates/config/kubernetes/apps/**/ks.yaml.j2 -A 3

# After running task configure, verify generated manifests
grep -r "dependsOn:" kubernetes/apps/**/ks.yaml -A 3
```

## Additional Issues Found During Bootstrap (January 4, 2026)

### Issue 6: Cross-Namespace dependsOn Requires Explicit Namespace

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** Kustomizations are deployed to their `targetNamespace`, NOT `flux-system`

When a Kustomization uses `dependsOn` to reference a Kustomization in a different namespace, the `namespace` field **must** be explicitly specified:

```yaml
# WRONG - looks for coredns in same namespace as this Kustomization
dependsOn:
  - name: coredns

# CORRECT - explicitly specifies the namespace
dependsOn:
  - name: coredns
    namespace: kube-system
```

**Affected Kustomizations Fixed:**

| Kustomization | Target NS | Dependency | Dependency NS | Fix Applied |
| ------------- | --------- | ---------- | ------------- | ----------- |
| cert-manager | cert-manager | coredns | kube-system | Added `namespace: kube-system` |
| proxmox-csi | csi-proxmox | coredns | kube-system | Added `namespace: kube-system` |
| proxmox-csi | csi-proxmox | proxmox-ccm | kube-system | Added `namespace: kube-system` |
| victoria-metrics | monitoring | coredns | kube-system | Added `namespace: kube-system` |
| envoy-gateway | network | cert-manager | cert-manager | Changed from `flux-system` to `cert-manager` |

### Issue 7: tuppr CRD Race Condition

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** Flux server-side dry-run validates TalosUpgrade/KubernetesUpgrade CRs before HelmRelease installs CRDs

**Error:**
```
TalosUpgrade/system-upgrade/talos dry-run failed: no matches for kind "TalosUpgrade" in version "tuppr.home-operations.com/v1alpha1"
```

**Solution:** Split tuppr into two Kustomizations:

1. **tuppr** - HelmRelease only (installs operator + CRDs)
   - Uses `healthChecks` to wait for HelmRelease
   - Uses `wait: true` with 5m timeout

2. **tuppr-upgrades** - TalosUpgrade/KubernetesUpgrade CRs
   - Uses `dependsOn: [tuppr]` to ensure CRDs exist
   - Deployed after tuppr is Ready

**Directory Structure:**
```
tuppr/
├── ks.yaml.j2              # Contains BOTH Kustomizations
├── app/
│   ├── kustomization.yaml.j2  # HelmRelease + OCIRepository only
│   ├── helmrelease.yaml.j2
│   └── ocirepository.yaml.j2
└── upgrades/
    ├── kustomization.yaml.j2  # Upgrade CRs only
    ├── talosupgrade.yaml.j2
    └── kubernetesupgrade.yaml.j2
```

This pattern follows [Helm CRD best practices](https://helm.sh/docs/v3/chart_best_practices/custom_resource_definitions/) for ensuring CRDs exist before CRs are applied.

### Issue 8: Missing storageClassName on Persistence Configurations

**Severity:** Medium
**Discovery:** During actual cluster bootstrap
**Problem:** PVCs created without storageClassName cannot bind when no default StorageClass exists

**Error:**
```
0/6 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
no persistent volumes available for this claim and no storage class is set
```

**Affected Components:**
- Grafana (victoria-metrics-k8s-stack)
- Loki
- Tempo

**Solution:** Add `storageClassName` to all persistence configurations:

```yaml
persistence:
  enabled: true
  storageClassName: "#{ storage_class | default('local-path') }#"
  size: 5Gi
```

**Files Fixed:**
- `templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2` (Grafana)
- `templates/config/kubernetes/apps/monitoring/loki/app/helmrelease.yaml.j2`
- `templates/config/kubernetes/apps/monitoring/tempo/app/helmrelease.yaml.j2`

### Issue 9: victoria-metrics Grafana Dashboard Conflict

**Severity:** Medium
**Discovery:** During actual cluster bootstrap
**Problem:** Chart disallows both `sidecar.dashboards.enabled: true` AND `grafana.dashboards` configuration

**Error:**
```
execution error at (victoria-metrics-k8s-stack/templates/grafana/dashboard.yaml:38:3):
It is not possible to use both "grafana.sidecar.dashboards.enabled: true" and "grafana.dashboards" at the same time.
```

**Solution:** Disabled sidecar and use explicit grafana.com dashboard IDs:

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: false  # Disabled - using dashboards: instead
  dashboards:
    infrastructure:
      kubernetes-global:
        gnetId: 15757
        # ...
```

**Trade-off:** This approach uses explicit dashboard IDs from grafana.com rather than auto-discovering dashboards from ConfigMaps (sidecar approach). For future Cilium Hubble integration that creates its own dashboard ConfigMaps, the sidecar approach may need to be reconsidered.

See [VictoriaMetrics K8s Stack Documentation](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/) for more details.

### Issue 10: PodSecurity Blocking Monitoring DaemonSets

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** Monitoring namespace had `baseline` PodSecurity which blocks node-exporter

**Error:**
```
pods "victoria-metrics-k8s-stack-prometheus-node-exporter-xxx" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true, hostPID=true), hostPath volumes (volumes "proc", "sys", "root"), hostPort (container "node-exporter" uses hostPort 9100)
```

**Analysis:** Node-exporter legitimately requires:
- `hostNetwork=true` - access to host network metrics
- `hostPID=true` - access to host process metrics
- `hostPath` volumes - access to `/proc`, `/sys`, `/` for system metrics
- `hostPort` - expose metrics on node port 9100

**Solution:** Set monitoring namespace to `privileged` PodSecurity level:

```yaml
# templates/config/kubernetes/apps/monitoring/namespace.yaml.j2
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    #| Privileged required for node-exporter (hostNetwork, hostPID, hostPath, hostPort) #|
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

**Note:** This is standard practice for monitoring namespaces. The `privileged` level allows workloads that genuinely need host access (node-exporter, kube-state-metrics scraping, etc.).

### Issue 11: Loki 6.x SingleBinary Deployment Mode Validation

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** Loki chart 6.x requires explicit disabling of non-active deployment modes

**Error:**
```
execution error at (loki/templates/validate.yaml:31:4): You have more than zero replicas configured for both the single binary and simple scalable targets. If this was intentional change the deploymentMode to the transitional 'SingleBinary<->SimpleScalable' mode
```

**Analysis:** Loki 6.x chart validates that only ONE deployment mode is active. The chart has non-zero default replicas for `read`, `write`, `backend`, and other distributed components that conflict with `SingleBinary` mode.

**Solution:** Explicitly set all other deployment mode components to `replicas: 0`:

```yaml
# templates/config/kubernetes/apps/monitoring/loki/app/helmrelease.yaml.j2
values:
  deploymentMode: SingleBinary
  #| Zero out replica counts of other deployment modes for SingleBinary #|
  backend:
    replicas: 0
  read:
    replicas: 0
  write:
    replicas: 0
  ingester:
    replicas: 0
  querier:
    replicas: 0
  queryFrontend:
    replicas: 0
  queryScheduler:
    replicas: 0
  distributor:
    replicas: 0
  compactor:
    replicas: 0
  indexGateway:
    replicas: 0
  bloomCompactor:
    replicas: 0
  bloomGateway:
    replicas: 0
  loki:
    # ... rest of config
```

**Reference:** [Loki Helm Chart - Install Monolithic](https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/)

### Issue 12: Loki Chart Uses Different StorageClass Parameter Name

**Severity:** Medium
**Discovery:** During actual cluster bootstrap
**Problem:** Loki 6.x chart uses `storageClass` while most Helm charts use `storageClassName`

**Error:**
```
0/6 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
```

**Analysis:** Even with persistence configuration set, the PVC was created without a storageClass because the parameter name was wrong:
- **Most Helm charts:** `persistence.storageClassName`
- **Loki 6.x chart:** `persistence.storageClass` (no "Name" suffix)
- **Tempo chart:** `persistence.storageClassName` (standard)

**Solution:** Use `storageClass` for Loki, `storageClassName` for other charts:

```yaml
# Loki (different parameter name)
singleBinary:
  persistence:
    enabled: true
    storageClass: "#{ storage_class | default('local-path') }#"  # Note: no "Name"
    size: "50Gi"

# Tempo and most other charts (standard parameter name)
persistence:
  enabled: true
  storageClassName: "#{ storage_class | default('local-path') }#"
  size: "10Gi"
```

**Lesson:** Always verify the exact parameter names in each chart's values.yaml - don't assume consistency across charts.

### Issue 13: Loki SchemaConfig Date Parsing

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** Loki 6.x requires date values in schemaConfig to be explicitly quoted strings

**Error:**
```
failed parsing config: parsing time "2024-01-01T00:00:00Z": extra text: "T00:00:00Z"
```

**Analysis:** YAML interprets unquoted `2024-01-01` as a date type, which Loki's Go parser then converts to `2024-01-01T00:00:00Z`. When Loki tries to parse this back, it fails because it expects a simple date string.

**Solution:** Quote the date value in schemaConfig:

```yaml
# WRONG - YAML interprets as date type
schemaConfig:
  configs:
    - from: 2024-01-01
      store: tsdb

# CORRECT - Explicit string ensures proper parsing
schemaConfig:
  configs:
    - from: "2024-01-01"
      store: tsdb
```

**Lesson:** Always quote date values in Loki schemaConfig to prevent YAML type coercion issues.

## Lessons Learned

1. **Cross-Namespace Dependencies**: Always specify explicit `namespace` field in `dependsOn` when referencing Kustomizations in different namespaces
2. **CRD Installation Order**: When deploying CRDs via HelmRelease and CRs in the same Kustomization, split them and use `dependsOn`
3. **Dry-Run Validation**: Flux validates ALL resources before applying ANY - CRDs must exist before CRs can be validated
4. **healthChecks**: Use `healthChecks` with `wait: true` when subsequent Kustomizations depend on resources being fully deployed
5. **StorageClass Specification**: Always explicitly set `storageClassName` on persistence configurations - don't rely on default StorageClass
6. **PodSecurity for Monitoring**: Monitoring namespaces typically require `privileged` PodSecurity level for node-exporter and similar host-access workloads
7. **Loki Deployment Modes**: When using SingleBinary mode, explicitly disable all other deployment mode components by setting `replicas: 0`

## References

- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux Health Checks](https://fluxcd.io/flux/components/kustomize/kustomizations/#health-checks)
- [Kubernetes CCM Chicken-Egg Problem](https://kubernetes.io/blog/2025/02/14/cloud-controller-manager-chicken-egg-problem/)
- [Helm CRD Best Practices](https://helm.sh/docs/v3/chart_best_practices/custom_resource_definitions/)
- [VictoriaMetrics K8s Stack Documentation](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/)
- [tuppr GitHub Repository](https://github.com/home-operations/tuppr)
- Project Research: `docs/research/talos-kubernetes-interoperability-jan-2026.md`
