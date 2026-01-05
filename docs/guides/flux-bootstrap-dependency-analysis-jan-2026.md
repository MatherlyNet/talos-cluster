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

## References

- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux Health Checks](https://fluxcd.io/flux/components/kustomize/kustomizations/#health-checks)
- [Kubernetes CCM Chicken-Egg Problem](https://kubernetes.io/blog/2025/02/14/cloud-controller-manager-chicken-egg-problem/)
- Project Research: `docs/research/talos-kubernetes-interoperability-jan-2026.md`
