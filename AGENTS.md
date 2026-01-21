# AGENTS.md

Universal AI coding agent instructions for the matherlynet-talos-cluster GitOps infrastructure project. This file follows the [AGENTS.md open standard](https://agents.md) supported by 25+ AI coding tools.

> **Important**: For Claude Code-specific guidance (Serena MCP, custom agents, skills), see `CLAUDE.md`. This file contains universal guidelines for all AI coding assistants.

## Project Overview

GitOps-driven **Kubernetes cluster** on **Talos Linux** with **Flux CD**. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

| Component | Technology | Purpose |
|-----------|------------|---------|
| **OS** | Talos Linux v1.12.0 | Immutable, Kubernetes-native |
| **Orchestration** | Kubernetes v1.35.0 | Container orchestration |
| **GitOps** | Flux CD | Declarative reconciliation |
| **CNI** | Cilium | Networking, LoadBalancer, BGP |
| **Ingress** | Envoy Gateway | Gateway API implementation |
| **Templating** | makejinja | Jinja2 to YAML generation |
| **Secrets** | SOPS/Age | Encryption at rest |
| **IaC** | OpenTofu v1.11+ | Infrastructure automation |

**Platform Components:** talos-ccm (node lifecycle), tuppr (automated upgrades), talos-backup (etcd snapshots), dragonfly (Redis cache), litellm (LLM proxy), langfuse (LLM observability), obot (MCP gateway), mcp-context-forge (MCP registry)

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

## Quick Context Loading

**ALWAYS READ FIRST:** `PROJECT_INDEX.md` - Provides complete project understanding in ~3K tokens (94% token reduction)

**Domain-Specific Context:** `docs/ai-context/` directory:

| Document | Domain | When to Load |
|----------|--------|--------------|
| `flux-gitops.md` | Flux CD | Adding apps, sync issues |
| `talos-operations.md` | Talos Linux | Node ops, upgrades |
| `cilium-networking.md` | Cilium CNI | Network debugging, BGP |
| `template-system.md` | makejinja | Template syntax, variables |
| `infrastructure-opentofu.md` | OpenTofu | IaC operations |
| `litellm.md` | LiteLLM | LLM proxy configuration |
| `langfuse.md` | Langfuse | LLM observability |
| `mcp-context-forge.md` | MCP Context Forge | MCP gateway configuration |

## Dos and Don'ts

### DO

- **Always read `PROJECT_INDEX.md` first** for efficient context loading
- **Always edit template files** in `templates/config/` - never edit generated files
- **Run `task configure`** after any template changes to regenerate and validate
- **Use makejinja delimiters** - NOT standard Jinja2 (see Template Syntax below)
- **Declare Flux dependencies** in `ks.yaml.j2` for proper ordering
- **Reference variables from `cluster.yaml`** - never hardcode values
- **Encrypt secrets** in `*.sops.yaml.j2` files - SOPS encrypts automatically
- **Commit generated files** - Flux reads from `kubernetes/`, `talos/`, `bootstrap/`
- **Use YAML anchors** (`&name` / `*name`) to avoid repetition
- **Run verification commands** after making changes

### DON'T

- **Never edit files in** `kubernetes/`, `talos/`, `bootstrap/`, `infrastructure/` - they are GENERATED
- **Never use standard Jinja2 delimiters** (`{{ }}`, `{% %}`) - use makejinja delimiters
- **Never use `|#` for comment endings** - comments are symmetrical: `#| comment #|`
- **Never commit** `age.key`, credentials, API keys, or `.env` files
- **Never skip `task configure`** - validation catches errors before they reach the cluster
- **Never hardcode** IP addresses, domains, or secrets in templates
- **Never modify `.github/workflows/`** without explicit request
- **Never bypass SOPS encryption** for secrets

## Template Syntax (CRITICAL)

This project uses **makejinja** with custom delimiters. Using standard Jinja2 will cause errors.

| Type | Correct (makejinja) | Wrong (Jinja2) | Example |
|------|---------------------|----------------|---------|
| **Block** | `#% ... %#` | `{% ... %}` | `#% if enabled %#` |
| **Variable** | `#{ ... }#` | `{{ ... }}` | `#{ cluster_name }#` |
| **Comment** | `#| ... #|` | `{# ... #}` | `#| This is a comment #|` |

**WARNING**: Comments use the SAME delimiter on both ends (`#|`), NOT `#| ... |#`.

### Common Filters

```yaml
#| Default values #|
#{ optional_var | default("fallback") }#

#| Network operations #|
#{ node_cidr | network_prefix }#

#| String operations #|
#{ name | lower }#
#{ name | replace("-", "_") }#
```

## Common Commands

All commands use **go-task**. Run `task --list` for complete reference.

### Essential Commands

```bash
task init                # Initialize config files from samples
task configure           # Render templates, validate, encrypt secrets
task reconcile           # Force Flux to sync from Git
```

### Bootstrap

```bash
task bootstrap:talos     # Install Talos on nodes
task bootstrap:apps      # Deploy Cilium, CoreDNS, Spegel, Flux
```

### Talos Operations

```bash
task talos:generate-config        # Regenerate Talos configs
task talos:apply-node IP=<ip>     # Apply config to running node
task talos:upgrade-node IP=<ip>   # Upgrade Talos version
task talos:upgrade-k8s            # Upgrade Kubernetes version
task talos:reset                  # Reset cluster to maintenance mode
```

### Infrastructure (OpenTofu)

```bash
task infra:init          # Initialize OpenTofu with R2 backend
task infra:plan          # Create execution plan
task infra:apply         # Apply saved plan
task infra:secrets-edit  # Edit encrypted secrets (for rotation)
```

### Verification

```bash
flux check               # Verify Flux installation
flux get ks -A           # Check all Kustomizations
flux get hr -A           # Check all HelmReleases
kubectl get nodes        # Check node status
cilium status            # Check Cilium health
```

## Project Structure

```
matherlynet-talos-cluster/
├── templates/                    # SOURCE - Edit these files
│   └── config/
│       ├── kubernetes/apps/      # K8s application templates
│       ├── talos/                # Talos configuration templates
│       ├── bootstrap/            # Bootstrap resource templates
│       └── infrastructure/       # OpenTofu/IaC templates
├── kubernetes/                   # GENERATED - Never edit directly
├── talos/                        # GENERATED - Never edit directly
├── bootstrap/                    # GENERATED - Never edit directly
├── infrastructure/               # GENERATED - Never edit directly
├── docs/                         # Documentation
│   ├── ai-context/               # Domain-specific AI context
│   └── guides/                   # Implementation guides
├── cluster.yaml                  # Main cluster configuration
├── nodes.yaml                    # Node definitions
├── Taskfile.yaml                 # Task runner definitions
└── makejinja.toml                # Template engine config
```

### Application Template Structure

Every Flux application follows this structure:

```
templates/config/kubernetes/apps/<namespace>/<app>/
├── ks.yaml.j2              # Flux Kustomization (entry point)
└── app/
    ├── kustomization.yaml.j2    # Kustomize resources list
    ├── helmrelease.yaml.j2      # HelmRelease (if Helm-based)
    ├── ocirepository.yaml.j2    # OCI chart source
    └── secret.sops.yaml.j2      # Secrets (if needed)
```

## Code Patterns

### HelmRelease Pattern

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: #{ app_name }#
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: #{ app_name }#
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
```

### Flux Kustomization Pattern

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app #{ app_name }#
  namespace: flux-system
spec:
  targetNamespace: #{ namespace }#
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: cert-manager      #| Declare dependencies #|
    - name: envoy-gateway
  path: ./kubernetes/apps/#{ namespace }#/#{ app_name }#/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  interval: 30m
```

### Conditional Inclusion

```yaml
#% if feature_enabled | default(false) %#
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-config
data:
  enabled: "true"
#% endif %#
```

### Loop Pattern

```yaml
#% for node in nodes %#
- name: #{ node.name }#
  address: #{ node.address }#
#% endfor %#
```

## Configuration Variables

Variables come from these sources (in order of precedence):

1. **`cluster.yaml`** - Primary configuration (network, cloudflare, features)
2. **`nodes.yaml`** - Node definitions (name, IP, disk, MAC, schematic)
3. **`templates/scripts/plugin.py`** - Computed/derived values

### Key Variables

| Variable | Source | Example |
|----------|--------|---------|
| `cluster_name` | cluster.yaml | `matherlynet` |
| `cluster_api_addr` | cluster.yaml | `192.168.1.100` |
| `cluster_gateway_addr` | cluster.yaml | `192.168.1.1` |
| `node_cidr` | cluster.yaml | `192.168.1.0/24` |
| `cloudflare_domain` | cluster.yaml | `example.com` |
| `nodes` | nodes.yaml | List of node objects |
| `*_enabled` | plugin.py | Computed feature flags |

## Pre-Commit Checklist

Run these commands IN ORDER before every commit:

```bash
# 1. Render and validate templates
task configure

# 2. Verify encrypted secrets
find kubernetes talos bootstrap -name "*.sops.*" -exec sops filestatus {} \;

# 3. Commit changes
git add -A
git commit -m "descriptive message"
git push

# 4. Force reconciliation (if needed)
task reconcile

# 5. Verify deployment
flux get ks -A
kubectl get pods -A
```

## Common Pitfalls & Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| Wrong delimiters | `{{ }}` in output | Use `#{ }#` not `{{ }}` |
| Asymmetric comment | Template error | Use `#| comment #|` not `#| comment |#` |
| Edited generated file | Changes overwritten | Edit in `templates/config/` instead |
| Flux not syncing | Resources not updating | Run `task reconcile`, check `flux get ks -A` |
| Node not ready | Node shows NotReady | Run `talosctl health -n <ip>` |
| CNI issues | Pods stuck in ContainerCreating | Run `cilium status`, `cilium connectivity test` |
| Secret not encrypted | Plaintext in git | Check `.sops.yaml` rules, re-run `task configure` |
| Dependency not ready | App fails to deploy | Add to `dependsOn` in `ks.yaml.j2` |
| Template variable missing | Empty value in output | Check `cluster.yaml` or add default filter |
| HelmRelease stuck | Upgrade/install pending | Check `flux get hr -A`, describe HelmRelease |

## Namespace Conventions

| Namespace | Purpose |
|-----------|---------|
| `kube-system` | Core cluster components (Cilium, CoreDNS) |
| `flux-system` | Flux controllers |
| `cert-manager` | Certificate management |
| `network` | Ingress, DNS, tunnels |
| `identity` | Keycloak, OIDC |
| `storage` | RustFS, CSI drivers |
| `monitoring` | Prometheus, Loki, Grafana |
| `ai-system` | LLM workloads (LiteLLM, Langfuse) |
| `external-secrets` | External secret management |

## Common Dependency Chains

Declare these in `ks.yaml.j2` `dependsOn`:

| If App Needs | Depend On |
|--------------|-----------|
| TLS certificates | `cert-manager`, `cert-manager-issuers` |
| Ingress/Gateway | `envoy-gateway` |
| OIDC authentication | `keycloak` |
| PostgreSQL database | `cloudnative-pg` |
| Redis cache | `dragonfly-operator` |
| S3 storage | `rustfs` |
| External secrets | `external-secrets`, `external-secrets-stores` |

## Security Considerations

- **Never commit** credentials, API keys, or tokens
- **Use SOPS encryption** for all secrets (`*.sops.yaml.j2`)
- **Age key** (`age.key`) is gitignored - never commit
- **Verify encryption** with `sops filestatus <file>`
- **Cloudflare tokens** should have minimal permissions
- **GitHub deploy keys** should be read-only for public repos
- **OpenTofu state** credentials in `infrastructure/secrets.sops.yaml`

## Tool Dependencies

Managed via `mise` (`.mise.toml`):

| Tool | Version | Purpose |
|------|---------|---------|
| talosctl | 1.12.0 | Talos node management |
| kubectl | 1.35.0 | Kubernetes CLI |
| flux | 2.7.5 | Flux CD CLI |
| helm | 3.19.4 | Helm charts |
| sops | 3.11.0 | Secret encryption |
| age | 1.3.1 | Encryption backend |
| opentofu | 1.11.2 | Infrastructure as Code |
| cilium | 0.18.9 | Cilium CLI |

Install all tools: `mise trust && mise install`

## Key Constraints

- **Control Plane:** Does NOT run workloads by default (`allowSchedulingOnControlPlanes: false`)
- **GitOps Flow:** All cluster state is declarative YAML reconciled via Flux from Git
- **Template-Driven:** All configs are generated from templates - never edit generated files
- **Secret Management:** All secrets encrypted with SOPS/Age, never plaintext
- **State Management:** OpenTofu state stored in Cloudflare R2 via HTTP backend

## Documentation Reference

| Document | Purpose | When to Read |
|----------|---------|--------------|
| `PROJECT_INDEX.md` | Token-efficient project summary | Every session start |
| `docs/ARCHITECTURE.md` | System design and diagrams | Understanding architecture |
| `docs/CONFIGURATION.md` | Configuration reference | Editing cluster.yaml/nodes.yaml |
| `docs/OPERATIONS.md` | Day-2 operations | Maintenance and upgrades |
| `docs/TROUBLESHOOTING.md` | Diagnostic flowcharts | When issues occur |
| `docs/CLI_REFERENCE.md` | Complete command reference | Daily operations |
| `docs/APPLICATIONS.md` | Application details | Adding/modifying apps |
| `CLAUDE.md` | Claude-specific guidance | Using Claude Code |

## Success Criteria

Your work is successful when:

- Templates render without errors: `task configure` succeeds
- All secrets are encrypted: `sops filestatus` shows encrypted
- Flux reconciles successfully: `flux get ks -A` shows all healthy
- Nodes are ready: `kubectl get nodes` shows all Ready
- Applications are running: `kubectl get pods -A` shows all Running
- Documentation is updated for significant changes

---

*This file follows the [AGENTS.md open standard](https://agents.md) maintained by the Linux Foundation's Agentic AI Foundation.*
