# Flux GitOps Architecture

> Deep-dive documentation for AI assistants working with Flux CD in this project.

## Overview

This project uses **Flux CD v2.7.5** (via Flux Operator v0.38.1) for GitOps-based continuous delivery. The cluster state is defined in Git, and Flux automatically reconciles the cluster to match.

**Key Architecture:**

- **Flux Operator** (OCI-based deployment) manages Flux installation lifecycle
- **Flux Instance** (FluxInstance CR) configures Flux to sync from GitHub repository
- **Interval-based reconciliation**: 1h for Kustomizations/HelmReleases, 30m for OCIRepository sources
- **Tolerations**: Flux controllers tolerate `node.cloudprovider.kubernetes.io/uninitialized` for CCM chicken-egg problem

## Flux Components

### Flux Operator

Manages Flux installation and lifecycle. Deployed via Helm during bootstrap.

```
kubernetes/apps/flux-system/flux-operator/
├── ks.yaml                    # Kustomization
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml       # flux-operator Helm chart
    └── ocirepository.yaml     # Chart source
```

### Flux Instance

Configures Flux to sync from the GitHub repository.

```
kubernetes/apps/flux-system/flux-instance/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── flux-instance.yaml     # FluxInstance CR
    ├── github-deploy-key.sops.yaml  # Encrypted SSH key
    ├── receiver-token.sops.yaml     # Webhook secret
    └── receiver-route.yaml    # HTTPRoute for webhook
```

## Resource Types

### GitRepository

Points to the source Git repository:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 30m
  url: ssh://git@github.com/<owner>/<repo>.git
  ref:
    branch: main
  secretRef:
    name: github-deploy-key
```

### Kustomization

Applies manifests from a path in the Git repo:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager
  namespace: flux-system
spec:
  targetNamespace: cert-manager
  path: ./kubernetes/apps/cert-manager/cert-manager/app
  sourceRef:
    kind: GitRepository
    name: flux-system
  prune: true
  wait: true
  interval: 30m
  dependsOn:
    - name: flux-instance
```

### HelmRelease

Deploys Helm charts with values:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cilium
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: cilium
  values:
    kubeProxyReplacement: true
    # ... more values
```

### OCIRepository

Sources Helm charts from OCI registries:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: cilium
spec:
  interval: 12h
  url: oci://ghcr.io/onedr0p/charts/cilium
  ref:
    tag: 1.16.0
```

## Dependency Management

Applications declare dependencies via `dependsOn`:

```yaml
spec:
  dependsOn:
    - name: envoy-gateway      # Wait for gateway
    - name: cert-manager       # Wait for certs
```

### Dependency Chain

```
cilium
  └─> coredns
        └─> flux-operator
              └─> flux-instance
                    ├─> cert-manager
                    │     └─> envoy-gateway
                    │           ├─> external-dns
                    │           ├─> k8s-gateway
                    │           ├─> cloudflare-tunnel
                    │           └─> echo
                    ├─> spegel (if >1 node)
                    ├─> cloudnative-pg (if cnpg_enabled)
                    │     ├─> barman-cloud-plugin (if cnpg_barman_plugin_enabled)
                    │     └─> keycloak (if keycloak_enabled && db_mode=cnpg)
                    ├─> keycloak-operator (if keycloak_enabled)
                    │     └─> keycloak (keycloak CR)
                    └─> rustfs (if rustfs_enabled)
```

## Secret Management

### SOPS Encryption

Secrets are encrypted with Age and stored in Git:

```yaml
# secret.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-token
stringData:
  token: ENC[AES256_GCM,data:...,iv:...,tag:...]
sops:
  age:
    - recipient: age1...
  lastmodified: "2024-01-01T00:00:00Z"
  mac: ENC[AES256_GCM,data:...,iv:...,tag:...]
```

### Decryption

Flux decrypts secrets using the Age private key stored in a Kubernetes secret:

```yaml
# Created during bootstrap
apiVersion: v1
kind: Secret
metadata:
  name: sops-age
  namespace: flux-system
stringData:
  age.agekey: AGE-SECRET-KEY-1...
```

## Webhook Integration

### Receiver

Listens for GitHub push events:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: flux-system
  namespace: flux-system
spec:
  type: github
  events:
    - ping
    - push
  secretRef:
    name: receiver-token
  resources:
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: flux-system
```

### HTTPRoute

Exposes webhook via Envoy Gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: flux-receiver
spec:
  parentRefs:
    - name: envoy-external
      namespace: network
  hostnames:
    - "flux-webhook.<domain>"
  rules:
    - backendRefs:
        - name: receiver
          port: 80
```

## Reconciliation

### Automatic

**Actual Intervals (as configured):**

- **Kustomizations**: Every 1 hour (`interval: 1h`)
- **HelmReleases**: Every 1 hour (`interval: 1h`)
- **OCIRepository** (chart sources): Every 30 minutes (`interval: 30m`)
- **GitRepository** (flux-system): Configured in FluxInstance, syncs kubernetes/flux/cluster path

**Performance Tuning:**

- Flux controllers run with `--concurrent=10` (10 parallel reconciliations)
- `--requeue-dependency=5s` for faster dependency resolution
- Memory limits: 1Gi per controller

### Manual

```bash
# Force all reconciliation
task reconcile

# Specific resources
flux reconcile source git flux-system
flux reconcile ks <name> --with-source
flux reconcile hr -n <namespace> <name>
```

## Adding Applications

### Directory Structure

```
templates/config/kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml.j2
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2
    ├── ocirepository.yaml.j2
    └── secret.sops.yaml.j2  # If needed
```

### Template Patterns

Use project template delimiters:

```yaml
#% if some_condition %#
  value: "#{ some_variable }#"
#% endif %#
```

### Namespace Kustomization

Add to `kustomization.yaml.j2`:

```yaml
resources:
  - ./namespace.yaml
  - ./<app-name>/ks.yaml
```

## Troubleshooting

### Common Issues

| Symptom | Check | Fix |
| --------- | ------- | ----- |
| Source not syncing | `flux get sources git` | Check deploy key |
| Kustomization failed | `kubectl describe ks` | Fix YAML/dependencies |
| HelmRelease stuck | `kubectl describe hr` | Check values/chart |
| Secrets not decrypting | `flux logs source-controller` | Verify sops-age secret |

### Logs

```bash
kubectl -n flux-system logs deploy/source-controller
kubectl -n flux-system logs deploy/kustomize-controller
kubectl -n flux-system logs deploy/helm-controller
```

### Events

```bash
kubectl get events -n flux-system --sort-by='.metadata.creationTimestamp'
```

## Network Policies

When `network_policies_enabled: true`, Flux controllers have dedicated CiliumNetworkPolicies:

**Location:** `templates/config/kubernetes/apps/flux-system/network-policies/app/flux-controllers.yaml.j2`

**Traffic Allowed:**

- **Ingress**: Prometheus metrics scraping (GET /metrics on port 8080)
- **Egress**:
  - DNS resolution (CoreDNS on port 53 UDP/TCP)
  - Kubernetes API server (ports 443, 6443)
  - External HTTPS (port 443) for OCI registries and GitHub

**Mode-Based Enforcement:**

- `audit` mode: Policies observe without blocking
- `enforce` mode: Default deny with explicit allow rules

**REF:** `.serena/memories/network_policy_patterns.md`

---

## MCP Tools (if available)

- `get_flux_instance` - Check installation status and configuration
- `reconcile_flux_kustomization` - Force Kustomization sync (with optional --with-source)
- `reconcile_flux_helmrelease` - Force HelmRelease sync
- `reconcile_flux_source` - Force source sync (GitRepository, OCIRepository)
- `search_flux_docs` - Search official Flux documentation for patterns

---

**Last Updated:** January 13, 2026
**Flux CD Version:** v2.7.5
**Flux Operator Version:** v0.38.1
