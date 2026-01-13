# Kubescape and Trivy Security Operators Integration Guide
**Date:** January 2026
**Purpose:** Integration guidance for adding Kubescape and Trivy security scanning operators with Headlamp plugins

---

## Executive Summary

This guide provides step-by-step integration instructions for deploying **Kubescape** and **Trivy** security scanning operators into the matherlynet-talos-cluster, enabling comprehensive security visibility through Headlamp plugins.

**Target State:**
- ✅ Kubescape Operator v1.22.0+ for configuration scanning and compliance
- ✅ Trivy Operator v0.24.1+ for CVE vulnerability scanning
- ✅ Headlamp plugins for visual security dashboard
- ✅ Network policies for zero-trust security scanning
- ✅ Integration with existing monitoring stack (Alloy/Prometheus)

**Security Scanning Coverage:**
| Operator | Focus Area | Key Features |
|----------|------------|--------------|
| **Kubescape** | Configuration & Compliance | NSA/CISA guidelines, CIS benchmarks, network policy analysis, admission policy playground |
| **Trivy** | Vulnerabilities & CVEs | Container image scanning, SBOM generation, secret detection, IaC scanning |

---

## Table of Contents

1. [Kubescape Operator Integration](#kubescape-operator-integration)
2. [Trivy Operator Integration](#trivy-operator-integration)
3. [Network Policies](#network-policies)
4. [Headlamp Plugin Configuration](#headlamp-plugin-configuration)
5. [Monitoring Integration](#monitoring-integration)
6. [Validation and Testing](#validation-and-testing)
7. [Troubleshooting](#troubleshooting)

---

## Kubescape Operator Integration

### Overview

**Kubescape** is a CNCF Incubating project (as of Feb 2025) providing Kubernetes security posture management.

**Key Capabilities:**
- Configuration scanning (NSA/CISA, CIS benchmarks)
- Network policy visualization
- Admission policy testing with CEL expressions (WASM-based)
- RBAC analysis
- Multi-tenant namespace views

### Prerequisites

- Kubernetes v1.35.0+ ✅ (cluster has v1.35.0)
- Helm v3+ ✅
- Network policies enabled ✅
- Persistent storage (optional for results retention)

### Step 1: Create Directory Structure

Following project conventions, security tools are grouped in a shared `security` namespace:

```bash
# Create directory structure
mkdir -p templates/config/kubernetes/apps/security/{kubescape,trivy}/{app,repositories}
```

### Step 2: Create Parent Kustomization

Create: `templates/config/kubernetes/apps/security/kustomization.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) or trivy_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
#% if kubescape_enabled | default(false) %#
  - ./kubescape/ks.yaml
#% endif %#
#% if trivy_enabled | default(false) %#
  - ./trivy/ks.yaml
#% endif %#
#% endif %#
```

### Step 3: Create Namespace

Create: `templates/config/kubernetes/apps/security/namespace.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) or trivy_enabled | default(false) %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: security
  labels:
    kubernetes.io/metadata.name: security
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
#% endif %#
```

**Note:** Both operators require `privileged` PSS profile for node-level scanning.

### Step 4: Add Flux Kustomization (Kubescape)

Create: `templates/config/kubernetes/apps/security/kubescape/ks.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app kubescape
  namespace: flux-system
spec:
  targetNamespace: security
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: kubescape-repositories
  path: ./kubernetes/apps/security/kubescape/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: false
  interval: 30m
  retryInterval: 1m
  timeout: 5m
#% endif %#
```

### Step 5: Create Repositories Kustomization (Kubescape)

Create: `templates/config/kubernetes/apps/security/kubescape/repositories/ks.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app kubescape-repositories
  namespace: flux-system
spec:
  targetNamespace: security
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/security/kubescape/repositories
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  interval: 12h
  retryInterval: 1m
  timeout: 3m
#% endif %#
```

Create: `templates/config/kubernetes/apps/security/kubescape/repositories/helmrepository.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: kubescape
  namespace: security
spec:
  interval: 12h
  url: https://kubescape.github.io/helm-charts/
#% endif %#
```

Create: `templates/config/kubernetes/apps/security/kubescape/repositories/kustomization.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
#% endif %#
```

### Step 6: Create HelmRelease

Create: `templates/config/kubernetes/apps/security/kubescape/app/helmrelease.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) %#
---
#| ============================================================================= #|
#| KUBESCAPE OPERATOR - Kubernetes Security Posture Management                  #|
#| CNCF Incubating project for security scanning and compliance                 #|
#| REF: https://kubescape.io/                                                    #|
#| REF: https://github.com/kubescape/kubescape                                  #|
#| ============================================================================= #|
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kubescape
  namespace: security
spec:
  chart:
    spec:
      chart: kubescape-operator
      version: #{ kubescape_chart_version | default('1.22.0') }#
      sourceRef:
        kind: HelmRepository
        name: kubescape
        namespace: security
  interval: 1h
  timeout: 15m
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
      remediateLastFailure: true

  values:
    #| ========================================================================= #|
    #| Operator Configuration                                                    #|
    #| ========================================================================= #|
    operator:
      replicaCount: #{ kubescape_operator_replicas | default(2) }#

    #| ========================================================================= #|
    #| Capabilities Configuration                                                #|
    #| Enable continuous scanning and network policy service for Headlamp plugin #|
    #| ========================================================================= #|
    capabilities:
      #| Continuous scanning of cluster resources #|
      continuousScan: enable

      #| Network policy analysis and visualization #|
      networkPolicyService: enable

      #| Configuration scanning schedule (daily at 2 AM) #|
      configurationScan: "0 2 * * *"

      #| Vulnerability scanning (integrates with Trivy) #|
      vulnerabilityScan: #{ kubescape_vulnerability_scan_enabled | default(true) | lower }#

      #| RBAC visualizer #|
      rbacVisualizer: enable

    #| ========================================================================= #|
    #| Compliance Frameworks                                                     #|
    #| ========================================================================= #|
    clusterScanScheduler:
      scanFrameworks:
        - nsa  # NSA/CISA Kubernetes Hardening Guide
        - cis-v1.23  # CIS Kubernetes Benchmark
        - mitre  # MITRE ATT&CK Framework

    #| ========================================================================= #|
    #| Storage Configuration                                                     #|
    #| Store scan results for historical analysis                               #|
    #| ========================================================================= #|
    storage:
      enabled: #{ kubescape_storage_enabled | default(true) }#
      size: #{ kubescape_storage_size | default('20Gi') }#
      storageClass: #{ kubescape_storage_class | default('local-path') }#

#% if monitoring_enabled | default(false) %#
    #| ========================================================================= #|
    #| Prometheus Integration                                                    #|
    #| ========================================================================= #|
    serviceMonitor:
      enabled: true
      interval: 30s
#% endif %#

    #| ========================================================================= #|
    #| Resource Configuration                                                    #|
    #| ========================================================================= #|
    kubescape:
      resources:
        requests:
          cpu: #{ kubescape_cpu_request | default('100m') }#
          memory: #{ kubescape_memory_request | default('256Mi') }#
        limits:
          cpu: #{ kubescape_cpu_limit | default('1000m') }#
          memory: #{ kubescape_memory_limit | default('1Gi') }#

    #| ========================================================================= #|
    #| Security Context                                                          #|
    #| ========================================================================= #|
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 100
      capabilities:
        drop:
          - ALL

#% if network_policies_enabled | default(false) %#
    #| ========================================================================= #|
    #| Network Policy Labels                                                     #|
    #| ========================================================================= #|
    podLabels:
      network.cilium.io/api-access: "true"
#% endif %#
#% endif %#
```

### Step 4: Create Kustomization

Create: `templates/config/kubernetes/apps/security/kubescape/app/kustomization.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./helmrelease.yaml
#% if network_policies_enabled | default(false) %#
  - ./networkpolicy.yaml
#% endif %#
#% endif %#
```

### Step 5: Network Policies

Create: `templates/config/kubernetes/apps/security/kubescape/app/networkpolicy.yaml.j2`

```yaml
#% if kubescape_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - Kubescape Operator                                     #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: kubescape-operator
  namespace: security
  labels:
    app.kubernetes.io/name: kubescape
    app.kubernetes.io/component: network-policy
spec:
  description: "Kubescape: Security scanning operator network access"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubescape-operator
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
#% if monitoring_enabled | default(false) %#
    #| Prometheus scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
#% endif %#
  egress:
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    #| Kubernetes API (required for cluster scanning) #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| Kubescape backend (optional cloud sync) #|
    - toFQDNs:
        - matchPattern: "*.kubescape.io"
        - matchPattern: "*.armo.cloud"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% if not enforce %#
    #| AUDIT MODE: Allow all other egress #|
    - toEntities:
        - world
#% endif %#
---
#| ============================================================================= #|
#| NetworkPolicy - Kubescape (Standard K8s)                                     #|
#| ============================================================================= #|
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kubescape
  namespace: security
  labels:
    app.kubernetes.io/name: kubescape
    app.kubernetes.io/component: network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: kubescape-operator
  policyTypes:
    - Ingress
    - Egress
  ingress:
#% if monitoring_enabled | default(false) %#
    #| Allow Prometheus scraping #|
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 8080
#% endif %#
  egress:
    #| Allow DNS queries #|
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    #| Allow external access (Kubescape backend sync) #|
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
#% endif %#
```

### Step 6: Configuration Variables

Add to `cluster.yaml`:

```yaml
#| ============================================================================= #|
#| KUBESCAPE - Kubernetes Security Posture Management                           #|
#| CNCF Incubating project for security scanning                               #|
#| REF: https://kubescape.io/                                                    #|
#| ============================================================================= #|
kubescape_enabled: true
kubescape_chart_version: "1.22.0"
kubescape_operator_replicas: 2

#| Scanning Configuration #|
kubescape_vulnerability_scan_enabled: true
kubescape_scan_schedule: "0 2 * * *"  # Daily at 2 AM

#| Storage Configuration #|
kubescape_storage_enabled: true
kubescape_storage_size: "20Gi"
kubescape_storage_class: "local-path"

#| Resource Configuration #|
kubescape_cpu_request: "100m"
kubescape_memory_request: "256Mi"
kubescape_cpu_limit: "1000m"
kubescape_memory_limit: "1Gi"
```

### Step 7: Deploy Kubescape

```bash
# 1. Update cluster.yaml with kubescape_enabled: true

# 2. Regenerate manifests
task configure

# 3. Verify generated manifests
ls -la kubernetes/apps/security/

# 4. Apply via Flux
task reconcile

# 5. Monitor deployment
kubectl get helmrelease -n security kubescape -w

# 6. Verify pods are running
kubectl get pods -n security

# 7. Check operator logs
kubectl logs -n security -l app.kubernetes.io/name=kubescape-operator --tail=100
```

### Step 8: Verify Scanning

```bash
# Check CRDs are installed
kubectl get crd | grep kubescape

# Trigger manual scan
kubectl create job -n security manual-scan --image=quay.io/kubescape/kubescape:latest -- scan framework nsa

# View scan results
kubectl get configurationscansummaries -A
kubectl get vulnerabilityreports -A

# Check scan schedules
kubectl get cronjobs -n security
```

---

## Trivy Operator Integration

### Overview

**Trivy** is an Aqua Security open-source project for comprehensive vulnerability and misconfiguration scanning.

**Key Capabilities:**
- Container image CVE scanning
- SBOM (Software Bill of Materials) generation
- Secret detection in containers and IaC
- Kubernetes misconfiguration scanning
- IaC scanning (Terraform, CloudFormation, etc.)

### Prerequisites

- Kubernetes v1.35.0+ ✅
- Helm v3+ ✅
- Network policies enabled ✅

### Step 1: Create Flux Kustomization (Trivy)

**Note:** The parent kustomization and namespace were already created in the Kubescape section above.

#### Flux Kustomization (Trivy Operator)

Create: `templates/config/kubernetes/apps/security/trivy/ks.yaml.j2`

```yaml
#% if trivy_enabled | default(false) %#
---
#| ============================================================================= #|
#| Trivy Operator - Flux Kustomization                                          #|
#| ============================================================================= #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app trivy
  namespace: flux-system
spec:
  targetNamespace: security
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/security/trivy/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: false
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: trivy-repositories
#% endif %#
```

#### Flux Kustomization (Repositories)

Create: `templates/config/kubernetes/apps/security/trivy/repositories/ks.yaml.j2`

```yaml
#% if trivy_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app trivy-repositories
  namespace: flux-system
spec:
  targetNamespace: security
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  interval: 12h
  prune: false
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/apps/security/trivy/repositories
#% endif %#
```

Create: `templates/config/kubernetes/apps/security/trivy/repositories/kustomization.yaml.j2`

```yaml
#% if trivy_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
#% endif %#
```

Create: `templates/config/kubernetes/apps/security/trivy/repositories/helmrepository.yaml.j2`

```yaml
#% if trivy_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: trivy
  namespace: security
spec:
  interval: 12h
  url: https://aquasecurity.github.io/helm-charts/
#% endif %#
```

### Step 2: Create App Kustomization

Create: `templates/config/kubernetes/apps/security/trivy/app/kustomization.yaml.j2`

```yaml
#% if trivy_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./networkpolicy.yaml
#% endif %#
```

### Step 3: Create HelmRelease

Create: `templates/config/kubernetes/apps/security/trivy/app/helmrelease.yaml.j2`

Create: `templates/config/kubernetes/apps/security/trivy/app/helmrelease.yaml.j2`

```yaml
#% if trivy_enabled | default(false) %#
---
#| ============================================================================= #|
#| TRIVY OPERATOR - Kubernetes Security Scanner                                 #|
#| Comprehensive vulnerability and misconfiguration scanning                    #|
#| REF: https://aquasecurity.github.io/trivy-operator/                          #|
#| ============================================================================= #|
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: trivy-operator
  namespace: trivy-system
spec:
  chart:
    spec:
      chart: trivy-operator
      version: #{ trivy_chart_version | default('0.24.1') }#
      sourceRef:
        kind: HelmRepository
        name: trivy
        namespace: trivy-system
  interval: 1h
  timeout: 15m
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
      remediateLastFailure: true

  values:
    #| ========================================================================= #|
    #| Operator Configuration                                                    #|
    #| ========================================================================= #|
    operator:
      replicas: #{ trivy_operator_replicas | default(2) }#

    #| ========================================================================= #|
    #| Scanning Configuration                                                    #|
    #| ========================================================================= #|
    trivy:
      #| Scan mode: Standalone (serverless) or ClientServer (centralized DB) #|
      mode: Standalone

      #| Ignore unfixed vulnerabilities (reduces noise) #|
      ignoreUnfixed: #{ trivy_ignore_unfixed | default(true) | lower }#

      #| Vulnerability severity levels to report #|
      severity: #{ trivy_severity | default('CRITICAL,HIGH,MEDIUM') }#

      #| Scan all namespaces by default #|
      scanJobsConcurrentLimit: #{ trivy_scan_jobs_concurrent | default(10) }#

      #| Database update schedule (daily) #|
      dbRepository: ghcr.io/aquasecurity/trivy-db
      javaDbRepository: ghcr.io/aquasecurity/trivy-java-db

    #| ========================================================================= #|
    #| SBOM Generation                                                           #|
    #| ========================================================================= #|
    compliance:
      enabled: #{ trivy_compliance_enabled | default(true) | lower }#
      formats:
        - json
        - cyclonedx

    #| ========================================================================= #|
    #| RBAC Assessment                                                           #|
    #| ========================================================================= #|
    rbacAssessment:
      enabled: #{ trivy_rbac_assessment_enabled | default(true) | lower }#

    #| ========================================================================= #|
    #| Infrastructure Assessment                                                 #|
    #| ========================================================================= #|
    infraAssessment:
      enabled: #{ trivy_infra_assessment_enabled | default(true) | lower }#

    #| ========================================================================= #|
    #| Config Audit                                                              #|
    #| ========================================================================= #|
    configAudit:
      enabled: #{ trivy_config_audit_enabled | default(true) | lower }#
      scannerReportTTL: #{ trivy_report_ttl | default('24h') }#

#% if monitoring_enabled | default(false) %#
    #| ========================================================================= #|
    #| Prometheus Integration                                                    #|
    #| ========================================================================= #|
    serviceMonitor:
      enabled: true
      interval: 30s
      labels:
        prometheus: monitoring
#% endif %#

    #| ========================================================================= #|
    #| Resource Configuration                                                    #|
    #| ========================================================================= #|
    resources:
      requests:
        cpu: #{ trivy_cpu_request | default('100m') }#
        memory: #{ trivy_memory_request | default('256Mi') }#
      limits:
        cpu: #{ trivy_cpu_limit | default('1000m') }#
        memory: #{ trivy_memory_limit | default('1Gi') }#

    #| ========================================================================= #|
    #| Security Context                                                          #|
    #| ========================================================================= #|
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
          - ALL

#% if network_policies_enabled | default(false) %#
    #| ========================================================================= #|
    #| Network Policy Labels                                                     #|
    #| ========================================================================= #|
    podLabels:
      network.cilium.io/api-access: "true"
#% endif %#
#% endif %#
```

### Step 4: Network Policies

Create: `templates/config/kubernetes/apps/trivy-system/trivy-operator/app/networkpolicy.yaml.j2`

```yaml
#% if trivy_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - Trivy Operator                                         #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: trivy-operator
  namespace: trivy-system
  labels:
    app.kubernetes.io/name: trivy-operator
    app.kubernetes.io/component: network-policy
spec:
  description: "Trivy: Vulnerability scanning operator network access"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: trivy-operator
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
#% if monitoring_enabled | default(false) %#
    #| Prometheus scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
#% endif %#
  egress:
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    #| Kubernetes API (required for scanning) #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| Trivy database updates (GitHub Container Registry) #|
    - toFQDNs:
        - matchPattern: "ghcr.io"
        - matchPattern: "*.ghcr.io"
        - matchPattern: "github.com"
        - matchPattern: "*.github.com"
        - matchPattern: "*.githubusercontent.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% if not enforce %#
    #| AUDIT MODE: Allow all other egress #|
    - toEntities:
        - world
#% endif %#
---
#| ============================================================================= #|
#| NetworkPolicy - Trivy (Standard K8s)                                         #|
#| ============================================================================= #|
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: trivy
  namespace: trivy-system
  labels:
    app.kubernetes.io/name: trivy-operator
    app.kubernetes.io/component: network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: trivy-operator
  policyTypes:
    - Ingress
    - Egress
  ingress:
#% if monitoring_enabled | default(false) %#
    #| Allow Prometheus scraping #|
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 8080
#% endif %#
  egress:
    #| Allow DNS queries #|
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    #| Allow external access (Trivy DB updates) #|
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
#% endif %#
```

### Step 5: Configuration Variables

Add to `cluster.yaml`:

```yaml
#| ============================================================================= #|
#| TRIVY - Kubernetes Security Scanner                                          #|
#| Aqua Security open-source vulnerability scanner                             #|
#| REF: https://aquasecurity.github.io/trivy-operator/                          #|
#| ============================================================================= #|
trivy_enabled: true
trivy_chart_version: "0.24.1"
trivy_operator_replicas: 2

#| Scanning Configuration #|
trivy_ignore_unfixed: true
trivy_severity: "CRITICAL,HIGH,MEDIUM"
trivy_scan_jobs_concurrent: 10

#| Feature Toggles #|
trivy_compliance_enabled: true
trivy_rbac_assessment_enabled: true
trivy_infra_assessment_enabled: true
trivy_config_audit_enabled: true
trivy_report_ttl: "24h"

#| Resource Configuration #|
trivy_cpu_request: "100m"
trivy_memory_request: "256Mi"
trivy_cpu_limit: "1000m"
trivy_memory_limit: "1Gi"
```

### Step 6: Deploy Trivy

```bash
# 1. Update cluster.yaml with trivy_enabled: true

# 2. Regenerate manifests
task configure

# 3. Apply via Flux
task reconcile

# 4. Monitor deployment
kubectl get helmrelease -n trivy-system trivy-operator -w

# 5. Verify pods
kubectl get pods -n trivy-system

# 6. Check operator logs
kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator --tail=100
```

### Step 7: Verify Scanning

```bash
# Check CRDs
kubectl get crd | grep trivy

# View vulnerability reports
kubectl get vulnerabilityreports -A

# View config audit reports
kubectl get configauditreports -A

# View RBAC assessment reports
kubectl get rbacassessmentreports -A

# View SBOM reports
kubectl get sbomreports -A

# Trigger manual scan of a namespace
kubectl label namespace default trivy-operator.aquasecurity.github.io/scan=true
```

---

## Headlamp Plugin Configuration

### Enable Kubescape Plugin

Update `templates/config/kubernetes/apps/kube-system/headlamp/app/helmrelease.yaml.j2`:

```yaml
plugins:
  # ... existing plugins ...

#% if kubescape_enabled | default(false) %#
  # Kubescape Security Scanning
  - name: kubescape
    source: https://github.com/kubescape/headlamp-plugin/releases/download/v0.10.3/kubescape.tgz
    version: 0.10.3
#% endif %#
```

### Enable Trivy Plugin

```yaml
#% if trivy_enabled | default(false) %#
  # Trivy Vulnerability Scanning
  - name: trivy
    source: https://github.com/kubebeam/trivy-headlamp-plugin/releases/download/v0.1.0/trivy.tgz
    version: 0.1.0
#% endif %#
```

### Complete Plugin Section

```yaml
plugins:
  # Prometheus
  - name: prometheus
    source: https://github.com/headlamp-k8s/plugins/releases/download/prometheus-0.8.1/prometheus-0.8.1.tar.gz
    version: 0.8.1

  # Flux GitOps Visualization
  - name: flux
    source: https://github.com/headlamp-k8s/plugins/releases/download/flux-0.5.0/headlamp-k8s-flux-0.5.0.tar.gz
    version: 0.5.0

  # Certificate Management UI
  - name: cert-manager
    source: https://github.com/headlamp-k8s/plugins/releases/download/cert-manager-0.1.0/headlamp-k8s-cert-manager-0.1.0.tar.gz
    version: 0.1.0

  # AI Assistant
  - name: ai-assistant
    source: https://github.com/headlamp-k8s/plugins/releases/download/ai-assistant-0.1.0-alpha/headlamp-k8s-ai-assistant-0.1.0-alpha.tar.gz
    version: 0.1.0-alpha

#% if kubescape_enabled | default(false) %#
  # Kubescape Security Scanning
  - name: kubescape
    source: https://github.com/kubescape/headlamp-plugin/releases/download/v0.10.3/kubescape.tgz
    version: 0.10.3
#% endif %#

#% if trivy_enabled | default(false) %#
  # Trivy Vulnerability Scanning
  - name: trivy
    source: https://github.com/kubebeam/trivy-headlamp-plugin/releases/download/v0.1.0/trivy.tgz
    version: 0.1.0
#% endif %#
```

---

## Monitoring Integration

### Prometheus ServiceMonitors

Both operators expose Prometheus metrics:

**Kubescape metrics:**
- Endpoint: `http://kubescape-operator:8080/metrics`
- ServiceMonitor: Auto-created by Helm chart when `serviceMonitor.enabled: true`

**Trivy metrics:**
- Endpoint: `http://trivy-operator:8080/metrics`
- ServiceMonitor: Auto-created by Helm chart when `serviceMonitor.enabled: true`

### Grafana Dashboards

Create custom dashboards for security scanning metrics:

1. **Security Posture Overview**
   - Critical vulnerabilities by namespace
   - Configuration scan compliance scores
   - RBAC risk assessment

2. **Vulnerability Trends**
   - CVE severity distribution
   - Time-to-remediation tracking
   - New vulnerabilities per week

3. **Compliance Status**
   - Framework compliance (NSA/CISA, CIS)
   - Failed controls by severity
   - Remediation progress

---

## Validation and Testing

### Post-Deployment Checks

```bash
# 1. Verify operators are running
kubectl get pods -n kubescape
kubectl get pods -n trivy-system

# 2. Check CRDs are installed
kubectl get crd | grep -E 'kubescape|trivy'

# 3. Trigger test scans
kubectl create job -n kubescape test-scan --image=quay.io/kubescape/kubescape:latest -- scan framework nsa

# 4. View scan results
kubectl get configurationscansummaries -A
kubectl get vulnerabilityreports -A

# 5. Verify Headlamp plugins loaded
kubectl logs -n kube-system -l app.kubernetes.io/name=headlamp --tail=50 | grep -i plugin

# 6. Access Headlamp UI
# Navigate to https://headlamp.<your-domain>
# Check sidebar for "Kubescape" and "Trivy" menu items
```

### Network Policy Validation

```bash
# Enable Hubble for network flow visibility
cilium hubble ui

# Test Kubescape operator can reach API server
kubectl exec -n kubescape -it deployment/kubescape-operator -- curl -k https://kubernetes.default.svc.cluster.local:443

# Test Trivy operator can fetch DB updates
kubectl exec -n trivy-system -it deployment/trivy-operator -- curl -I https://ghcr.io

# Verify no unexpected denied connections
hubble observe --namespace kubescape --verdict DROPPED
hubble observe --namespace trivy-system --verdict DROPPED
```

---

## Troubleshooting

### Common Issues

#### Kubescape Operator Issues

**Problem:** Operator pods CrashLoopBackOff
```bash
# Check logs
kubectl logs -n kubescape -l app.kubernetes.io/name=kubescape-operator --tail=100

# Common causes:
# 1. Insufficient memory (increase kubescape_memory_limit)
# 2. API server unreachable (check network policy)
# 3. Missing RBAC permissions (check ClusterRole)

# Solution: Increase resources
# In cluster.yaml:
kubescape_memory_limit: "2Gi"
```

**Problem:** Scans not running
```bash
# Check CronJobs
kubectl get cronjobs -n kubescape

# Manually trigger scan
kubectl create job -n kubescape manual-scan --from=cronjob/kubescape-scan-cron

# Check job logs
kubectl logs -n kubescape job/manual-scan
```

#### Trivy Operator Issues

**Problem:** Vulnerability reports not generating
```bash
# Check operator status
kubectl get pods -n trivy-system

# Check operator logs
kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator --tail=200

# Common causes:
# 1. Database not downloaded (check ghcr.io access)
# 2. Scan jobs failing (check job pods)

# Force database update
kubectl delete pod -n trivy-system -l app.kubernetes.io/name=trivy-operator
```

**Problem:** Network policy blocking DB updates
```bash
# Temporarily allow all egress for testing
kubectl label namespace trivy-system network-policies-audit=true

# Test ghcr.io access
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n trivy-system -- curl -I https://ghcr.io

# If successful, check CiliumNetworkPolicy toFQDNs rules
kubectl get ciliumnetworkpolicies -n trivy-system trivy-operator -o yaml
```

#### Headlamp Plugin Issues

**Problem:** Plugins not showing in UI
```bash
# Check plugin loading in Headlamp logs
kubectl logs -n kube-system -l app.kubernetes.io/name=headlamp --tail=100 | grep -i plugin

# Verify plugin downloads succeeded
kubectl exec -n kube-system deployment/headlamp -- ls -la /headlamp/plugins/

# Check for plugin errors
kubectl logs -n kube-system -l app.kubernetes.io/name=headlamp --tail=500 | grep -i error
```

**Problem:** Kubescape plugin shows "No data"
```bash
# Verify Kubescape scans have run
kubectl get configurationscansummaries -A

# If no results, trigger manual scan
kubectl create job -n kubescape test-scan --image=quay.io/kubescape/kubescape:latest -- scan framework nsa

# Wait a few minutes and refresh Headlamp
```

---

## Security Best Practices

### 1. Least Privilege RBAC

Both operators require cluster-wide read access for scanning. Review and restrict permissions:

```bash
# Review Kubescape ClusterRole
kubectl get clusterrole kubescape-operator -o yaml

# Review Trivy ClusterRole
kubectl get clusterrole trivy-operator -o yaml

# Ensure no write permissions except for CRD updates
```

### 2. Network Segmentation

Keep security operators in dedicated namespaces with restrictive network policies:

- ✅ `kubescape` namespace for Kubescape
- ✅ `trivy-system` namespace for Trivy
- ✅ Network policies in enforce mode after validation
- ✅ FQDN-based egress restrictions via CiliumNetworkPolicy

### 3. Scan Result Retention

Configure appropriate TTLs for scan results:

```yaml
# Kubescape - retain for historical analysis
kubescape_storage_enabled: true
kubescape_storage_size: "50Gi"  # Increase if needed

# Trivy - automatic cleanup after 24 hours
trivy_report_ttl: "24h"
```

### 4. Alert on Critical Findings

Configure alerts in Prometheus/Alertmanager:

```yaml
# Example alert rule
- alert: CriticalVulnerabilitiesDetected
  expr: sum(trivy_vulnerability_severity{severity="CRITICAL"}) > 0
  for: 5m
  annotations:
    summary: "Critical vulnerabilities detected"
```

---

## Parent Kustomization Updates

### Update apps/kustomization.yaml.j2

After creating the namespace directories, update the parent kustomization to include the new namespaces.

Edit: `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add the following conditional includes:

```yaml
#% if kubescape_enabled | default(false) %#
- ./kubescape
#% endif %#

#% if trivy_enabled | default(false) %#
- ./trivy-system
#% endif %#
```

**Complete example with alphabetical ordering:**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # ... existing namespaces ...
  
#% if keycloak_enabled | default(false) %#
  - ./identity
#% endif %#
  
#% if kubescape_enabled | default(false) %#
  - ./kubescape
#% endif %#
  
  - ./kube-system
  - ./monitoring
  - ./network
  - ./storage
  
#% if trivy_enabled | default(false) %#
  - ./trivy-system
#% endif %#
  
  # ... remaining namespaces ...
```

### Regenerate and Validate

After updating the parent kustomization:

```bash
# 1. Regenerate all manifests
task configure

# 2. Verify generated directory structure
tree kubernetes/apps/kubescape/
tree kubernetes/apps/trivy-system/

# 3. Validate Kustomize builds successfully
kubectl kustomize kubernetes/apps/kubescape/
kubectl kustomize kubernetes/apps/trivy-system/

# 4. Check Git status for new files
git status kubernetes/apps/

# 5. Review generated manifests before committing
git diff kubernetes/apps/kustomization.yaml
git diff kubernetes/apps/kubescape/
git diff kubernetes/apps/trivy-system/
```

---

## References

### Official Documentation
- [Kubescape Documentation](https://kubescape.io/docs/)
- [Kubescape GitHub](https://github.com/kubescape/kubescape)
- [Trivy Operator Documentation](https://aquasecurity.github.io/trivy-operator/)
- [Trivy Documentation](https://trivy.dev/)

### Headlamp Plugins
- [Kubescape Headlamp Plugin](https://github.com/kubescape/headlamp-plugin)
- [Trivy Headlamp Plugin](https://github.com/kubebeam/trivy-headlamp-plugin)

### CNCF Resources
- [Kubescape CNCF Incubating Announcement](https://www.cncf.io/blog/2025/02/26/kubescape-becomes-a-cncf-incubating-project/)
- [Kubescape Headlamp Integration Announcement](https://kubescape.io/blog/2025/04/30/kubescape-headlamp/)

### Compliance Frameworks
- [NSA/CISA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---

## Appendix: Cluster.yaml Complete Configuration

```yaml
#| ============================================================================= #|
#| SECURITY SCANNING OPERATORS                                                  #|
#| ============================================================================= #|

#| Kubescape - Configuration Scanning and Compliance #|
kubescape_enabled: true
kubescape_chart_version: "1.22.0"
kubescape_operator_replicas: 2
kubescape_vulnerability_scan_enabled: true
kubescape_scan_schedule: "0 2 * * *"
kubescape_storage_enabled: true
kubescape_storage_size: "20Gi"
kubescape_storage_class: "local-path"
kubescape_cpu_request: "100m"
kubescape_memory_request: "256Mi"
kubescape_cpu_limit: "1000m"
kubescape_memory_limit: "1Gi"

#| Trivy - Vulnerability and CVE Scanning #|
trivy_enabled: true
trivy_chart_version: "0.24.1"
trivy_operator_replicas: 2
trivy_ignore_unfixed: true
trivy_severity: "CRITICAL,HIGH,MEDIUM"
trivy_scan_jobs_concurrent: 10
trivy_compliance_enabled: true
trivy_rbac_assessment_enabled: true
trivy_infra_assessment_enabled: true
trivy_config_audit_enabled: true
trivy_report_ttl: "24h"
trivy_cpu_request: "100m"
trivy_memory_request: "256Mi"
trivy_cpu_limit: "1000m"
trivy_memory_limit: "1Gi"
```

---

**Last Updated:** January 2026
**Status:** Ready for implementation
**Prerequisites:** cluster.yaml configured, network policies enabled, monitoring stack deployed
