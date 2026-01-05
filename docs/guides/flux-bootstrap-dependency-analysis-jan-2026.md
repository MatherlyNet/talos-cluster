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

### Issue 14: UniFi DNS API Permission Error

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** UniFi external-dns webhook returns 403 "No permission" when accessing static-dns API

**Error:**
```
API error during GET to https://192.168.23.254/proxy/network/v2/api/site/Matherly-UDM/static-dns/ (status 403): No permission
```

**Analysis:** The UniFi API key may not have the correct permissions or the site name may be incorrect.

**Diagnostic Commands:**
```bash
# Test 1: Basic connectivity with default site
curl -k -X GET \
  "https://192.168.23.254/proxy/network/v2/api/site/default/static-dns/" \
  -H "X-API-KEY: <your-api-key>"

# Test 2: List sites to find correct site name
curl -k -X GET \
  "https://192.168.23.254/proxy/network/api/s/default/self" \
  -H "X-API-KEY: <your-api-key>"
```

**Possible Causes:**
1. API key lacks DNS management permissions
2. Site name mismatch (configured `Matherly-UDM` vs actual site ID)
3. UniFi Network version < v9.0.0 (API key auth requires v9.0.0+)

**Solution:** Verify API key permissions and site name in UniFi Console:
- Admin → Control Plane → API Keys → Create with "Full Management Access"
- Check actual site ID in Settings → System → Network Application

### Issue 15: Grafana Uses Legacy Ingress Instead of Gateway API

**Severity:** High
**Discovery:** During actual cluster bootstrap
**Problem:** Grafana inaccessible via `envoy-internal` because VictoriaMetrics Helm chart creates legacy Ingress, not HTTPRoute

**Error:** Cloudflare Error 1033 when accessing `grafana.matherly.net`

**Analysis:** The architecture uses two Envoy Gateways:
- `envoy-external` (192.168.22.90): Public access via Cloudflare Tunnel
- `envoy-internal` (192.168.22.80): Local network access via UniFi DNS + BGP

The VictoriaMetrics Helm chart creates a legacy `Ingress` resource for Grafana. However:
1. There's no Ingress controller (Envoy Gateway uses Gateway API)
2. UniFi external-dns watches `gateway-httproute`, not `ingress`
3. Result: No DNS record created, no routing available

**Solution:** Disable Helm chart Ingress and create explicit HTTPRoute:

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2
grafana:
  enabled: true
  ingress:
    enabled: false  # Disable legacy Ingress
```

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/httproute.yaml.j2
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
spec:
  hostnames:
    - "grafana.${SECRET_DOMAIN}"
  parentRefs:
    - name: envoy-internal
      namespace: network
      sectionName: https
  rules:
    - backendRefs:
        - name: victoria-metrics-k8s-stack-grafana
          port: 80
```

**Lesson:** When using Gateway API, always prefer explicit HTTPRoute resources over Helm chart Ingress configurations.

### Issue 16: Grafana Admin Credentials Configuration

**Severity:** Medium
**Discovery:** During actual cluster bootstrap
**Problem:** Grafana uses auto-generated admin password stored in a Kubernetes secret, requiring manual retrieval

**Context:** The default VictoriaMetrics Helm chart generates a random admin password stored in a secret. While secure, this creates friction for GitOps workflows where credentials should be managed declaratively.

**Solution:** Create SOPS-encrypted secret and reference via `admin.existingSecret`:

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/secret.sops.yaml.j2
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-secret
stringData:
  admin-user: "#{ grafana_admin_user | default('admin') }#"
  admin-password: "#{ grafana_admin_password | default('admin') }#"
```

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2
grafana:
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
```

**Configuration (cluster.yaml):**
```yaml
# Grafana admin credentials
grafana_admin_user: "admin"           # (OPTIONAL) / (DEFAULT: "admin")
grafana_admin_password: "securepass"  # (OPTIONAL) / Set for GitOps-managed credentials
```

**Important Caveat:** Grafana stores the admin password in its internal database after first login. Changing `grafana_admin_password` in cluster.yaml will NOT update an existing Grafana installation. To change the password after initial deployment:

```bash
# Option 1: Reset via Grafana CLI inside pod
kubectl -n monitoring exec -it deploy/victoria-metrics-k8s-stack-grafana -- grafana-cli admin reset-admin-password <new-password>

# Option 2: Delete the Grafana PVC and redeploy (loses dashboard customizations)
kubectl -n monitoring delete pvc victoria-metrics-k8s-stack-grafana
flux reconcile hr victoria-metrics-k8s-stack -n monitoring
```

**Lesson:** For Grafana admin credentials, set the password in cluster.yaml BEFORE initial deployment. Post-deployment password changes require CLI reset or data wipe.

### Issue 17: VictoriaMetrics Dashboard Datasource Compatibility

**Severity:** Medium
**Discovery:** During dashboard testing after deployment
**Problem:** Many Grafana dashboards use `${DS_PROMETHEUS}` variable which doesn't match our "VictoriaMetrics" datasource name

**Symptoms:**
- Dashboard dropdown selectors showing "datasource ${DS_PROMETHEUS} was not found"
- "No data" in panels expecting Prometheus datasource

**Solution:** Add a Prometheus datasource alias pointing to VictoriaMetrics:

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2
grafana:
  additionalDataSources:
    - name: Prometheus
      type: prometheus
      url: http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8429
      access: proxy
      isDefault: false
```

**Lesson:** When using VictoriaMetrics with community Grafana dashboards, add a "Prometheus" datasource alias for dashboard compatibility.

### Issue 18: Talos Control Plane Metrics TLS Configuration

**Severity:** High
**Discovery:** During VictoriaMetrics target analysis
**Problem:** kube-controller-manager and kube-scheduler metrics scraping fails with TLS certificate errors

**Error:**
```
tls: failed to verify certificate: x509: certificate is valid for localhost, localhost, not kubernetes
tls: failed to verify certificate: x509: certificate is valid for 127.0.0.1, not 192.168.22.101
```

**Analysis:** Talos Linux already configures `bind-address: 0.0.0.0` for controller-manager and scheduler in the machineConfig (see `templates/config/talos/patches/controller/cluster.yaml.j2`), making them accessible on node IPs. However, the TLS certificates are only valid for `localhost`/`127.0.0.1`, not the node IP addresses.

**Solution:** Configure VictoriaMetrics to skip TLS verification with correct serverName:

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2
kubeControllerManager:
  enabled: true
  spec:
    endpoints:
      - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
        port: http-metrics
        scheme: https
        tlsConfig:
          caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          serverName: localhost
          insecureSkipVerify: true

kubeScheduler:
  enabled: true
  spec:
    endpoints:
      - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
        port: http-metrics
        scheme: https
        tlsConfig:
          caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          serverName: "127.0.0.1"
          insecureSkipVerify: true
```

**Reference:** [VictoriaMetrics GitHub Issue #6476](https://github.com/VictoriaMetrics/VictoriaMetrics/issues/6476)

**Lesson:** Talos control plane components use self-signed certificates valid only for localhost. Use `insecureSkipVerify: true` with appropriate `serverName` when scraping these endpoints.

### Issue 19: Talos etcd Metrics HTTP Endpoint Configuration

**Severity:** High
**Discovery:** During VictoriaMetrics target analysis
**Problem:** etcd metrics endpoint shows "No endpoint defined" in scrape targets

**Analysis:** Talos already exposes etcd metrics on HTTP port 2381 via machineConfig (`listen-metrics-urls: http://0.0.0.0:2381`). The issue was VictoriaMetrics helm chart defaults expecting HTTPS on port 2379.

**Solution:** Configure kubeEtcd with explicit controller node endpoints and HTTP scheme:

```yaml
# templates/config/kubernetes/apps/monitoring/victoria-metrics/app/helmrelease.yaml.j2
kubeEtcd:
  enabled: true
  endpoints:
#% for node in nodes %#
#% if node.controller %#
    - #{ node.address }#
#% endif %#
#% endfor %#
  service:
    enabled: true
    port: 2381
    targetPort: 2381
  spec:
    endpoints:
      - port: http-metrics
        scheme: http
```

**Reference:** [Talos etcd Metrics Documentation](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/etcd-metrics)

**Lesson:** Talos etcd exposes metrics on HTTP:2381, not the default etcd client port 2379/HTTPS. Configure explicit endpoints and HTTP scheme.

### Issue 20: flux-operator NetworkPolicy Blocks Metrics Port

**Severity:** High
**Discovery:** During VictoriaMetrics target analysis
**Problem:** flux-operator metrics endpoint (port 8080) times out while the pod is healthy

**Error:**
```
net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)
```

**Analysis:** The flux-operator helm chart creates a NetworkPolicy (`flux-operator-web`) that only allows ingress on port 9080 (web UI), blocking the metrics port 8080.

**Solution:** Disable the built-in NetworkPolicy:

```yaml
# templates/config/kubernetes/apps/flux-system/flux-operator/app/helmrelease.yaml.j2
values:
  webui:
    networkPolicy:
      create: false
```

**Alternative:** If NetworkPolicies are managed at the CiliumNetworkPolicy level, disabling the chart's NetworkPolicy is appropriate. Otherwise, create a custom NetworkPolicy that allows both ports.

**Lesson:** Always check if helm charts create NetworkPolicies that may block metrics ports. The chart's default NetworkPolicy configuration may not include all necessary ports.

### Issue 21: Hubble L7 Metrics Require CiliumNetworkPolicies

**Severity:** Low (Documentation)
**Discovery:** During dashboard analysis
**Problem:** Cilium Hubble HTTP and DNS metrics panels show "No data" despite metrics being scraped

**Analysis:** Hubble L7 metrics (HTTP, DNS) require CiliumNetworkPolicies with L7 rules to enable visibility. Without L7 policies, Hubble only provides L3/L4 visibility.

From [Cilium L7 Protocol Visibility Documentation](https://docs.cilium.io/en/stable/observability/visibility/):
> L7 metrics such as HTTP are only emitted for pods that enable Layer 7 Protocol Visibility.

**Metrics that work without L7 policies:**
- `drop`, `tcp`, `flow`, `icmp`, `port-distribution`

**Metrics that require L7 policies:**
- `http`, `dns`

**Example L7 Visibility Policy:**
```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: l7-visibility
spec:
  endpointSelector: {}
  egress:
    - toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*"
```

**Lesson:** Hubble L7 metrics require explicit L7 network policies. This is by design - L7 visibility implies L7 inspection which has performance implications. The `hubble.metrics.enabled` array only configures which metrics to export, not which traffic to inspect.

### Issue 22: Envoy Gateway Control Plane Metrics Missing

**Severity:** Medium
**Discovery:** During dashboard analysis
**Problem:** Envoy Gateway Overview dashboard shows "No data" for gateway controller metrics

**Analysis:** The existing PodMonitor only targets envoy proxy pods (`app.kubernetes.io/component: proxy`), not the envoy-gateway controller pod (`app.kubernetes.io/name: envoy-gateway`).

**Solution:** Add a second PodMonitor for the gateway controller:

```yaml
# templates/config/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml.j2
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: envoy-gateway
spec:
  jobLabel: envoy-gateway
  namespaceSelector:
    matchNames:
      - network
  podMetricsEndpoints:
    - port: metrics
      path: /metrics
      honorLabels: true
  selector:
    matchLabels:
      app.kubernetes.io/name: envoy-gateway
```

**Note:** The gateway controller exposes metrics at `/metrics`, while proxy pods expose at `/stats/prometheus`.

**Lesson:** Envoy Gateway has two distinct metric sources - the control plane (envoy-gateway pod) and data plane (envoy-* proxy pods). Both need separate monitors.

## Lessons Learned

1. **Cross-Namespace Dependencies**: Always specify explicit `namespace` field in `dependsOn` when referencing Kustomizations in different namespaces
2. **CRD Installation Order**: When deploying CRDs via HelmRelease and CRs in the same Kustomization, split them and use `dependsOn`
3. **Dry-Run Validation**: Flux validates ALL resources before applying ANY - CRDs must exist before CRs can be validated
4. **healthChecks**: Use `healthChecks` with `wait: true` when subsequent Kustomizations depend on resources being fully deployed
5. **StorageClass Specification**: Always explicitly set `storageClassName` on persistence configurations - don't rely on default StorageClass
6. **PodSecurity for Monitoring**: Monitoring namespaces typically require `privileged` PodSecurity level for node-exporter and similar host-access workloads
7. **Loki Deployment Modes**: When using SingleBinary mode, explicitly disable all other deployment mode components by setting `replicas: 0`
8. **Chart Parameter Names**: Don't assume consistency - Loki uses `storageClass`, most charts use `storageClassName`
9. **YAML Date Quoting**: Always quote date values in configuration to prevent YAML type coercion issues
10. **UniFi API Authentication**: API keys require UniFi Network v9.0.0+ and correct site ID configuration
11. **Gateway API over Ingress**: When using Envoy Gateway with external-dns, use HTTPRoute resources instead of Helm chart Ingress configurations
12. **Grafana Credentials Timing**: Set `grafana_admin_password` in cluster.yaml BEFORE initial deployment - post-deployment changes require CLI reset
13. **Datasource Aliases**: Add "Prometheus" datasource alias when using VictoriaMetrics for community dashboard compatibility
14. **Talos TLS Certificates**: Control plane component certs are localhost-only - use `insecureSkipVerify: true` with serverName
15. **etcd HTTP Metrics**: Talos etcd uses HTTP:2381 for metrics, not the default 2379/HTTPS - configure explicit endpoints
16. **Chart NetworkPolicies**: Check if helm charts create NetworkPolicies that block metrics ports before deployment
17. **Hubble L7 Visibility**: L7 metrics (HTTP/DNS) require CiliumNetworkPolicies with L7 rules - metrics config alone is insufficient
18. **Envoy Gateway Metrics**: Control plane and data plane have separate metric endpoints requiring distinct PodMonitors

## References

- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux Health Checks](https://fluxcd.io/flux/components/kustomize/kustomizations/#health-checks)
- [Kubernetes CCM Chicken-Egg Problem](https://kubernetes.io/blog/2025/02/14/cloud-controller-manager-chicken-egg-problem/)
- [Helm CRD Best Practices](https://helm.sh/docs/v3/chart_best_practices/custom_resource_definitions/)
- [VictoriaMetrics K8s Stack Documentation](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/)
- [tuppr GitHub Repository](https://github.com/home-operations/tuppr)
- Project Research: `docs/research/talos-kubernetes-interoperability-jan-2026.md`
