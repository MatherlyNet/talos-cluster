# AGENTS.md

> AI Assistant Instructions for matherlynet-talos-cluster

This file provides context and instructions for AI coding assistants working with this Talos Linux Kubernetes cluster repository.

## Project Overview

**Type:** GitOps-driven Kubernetes cluster on Talos Linux
**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI, Gateway API + Envoy Gateway, SOPS/Age encryption, Cloudflare (DNS + Tunnel), UniFi DNS (optional internal)
**Platform Components:** talos-ccm (node lifecycle), tuppr (automated upgrades), talos-backup (etcd snapshots, optional)
**Deployment Model:** 7-stage workflow with Jinja2 templating via makejinja
**Infrastructure:** Optional OpenTofu v1.11+ for Proxmox VM automation with Cloudflare R2 state backend
**Upstream:** Forked from [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

## Quick Context Loading

**ALWAYS READ FIRST:** `PROJECT_INDEX.md` - Provides complete project understanding in ~3K tokens (94% token reduction)

**Domain-Specific Context:** `docs/ai-context/` directory contains deep-dive documentation:
- `flux-gitops.md` - Flux CD architecture & patterns
- `talos-operations.md` - Talos node operations
- `cilium-networking.md` - Cilium CNI & networking
- `template-system.md` - makejinja templating system
- `infrastructure-opentofu.md` - OpenTofu IaC & R2 backend

## Project Structure

```
matherlynet-talos-cluster/
├── templates/config/          # SOURCE: Jinja2 templates (EDIT THESE)
│   ├── kubernetes/apps/       # K8s application manifests
│   ├── talos/                 # Talos configuration
│   ├── bootstrap/             # Bootstrap resources
│   └── infrastructure/        # OpenTofu configs
├── kubernetes/                # GENERATED: K8s manifests (DO NOT EDIT)
├── talos/                     # GENERATED: Talos configs (DO NOT EDIT)
├── bootstrap/                 # GENERATED: Bootstrap resources (DO NOT EDIT)
├── infrastructure/            # GENERATED: OpenTofu configs (DO NOT EDIT)
├── docs/                      # Documentation
├── .taskfiles/                # Task automation
├── cluster.yaml               # Main cluster configuration
├── nodes.yaml                 # Node definitions
└── Taskfile.yaml              # Task runner entry point
```

## Essential Commands

### Core Workflow
```bash
task --list                    # List all available tasks
task init                      # Initialize config files from samples
task configure                 # Render templates, validate, encrypt secrets
task reconcile                 # Force Flux to sync from Git
```

### Bootstrap (New Cluster)
```bash
task bootstrap:talos           # Install Talos on nodes
task bootstrap:apps            # Deploy Cilium, CoreDNS, Spegel, Flux
```

### Talos Operations
```bash
task talos:generate-config     # Regenerate Talos configs
task talos:apply-node IP=<ip>  # Apply config to running node
task talos:upgrade-node IP=<ip> # Upgrade Talos version
task talos:upgrade-k8s         # Upgrade Kubernetes version
task talos:reset               # Reset cluster to maintenance mode
```

### Infrastructure (OpenTofu)
```bash
task infra:init                # Initialize OpenTofu with R2 backend
task infra:plan                # Create execution plan
task infra:apply               # Apply saved plan
task infra:apply-auto          # Apply with auto-approve
task infra:destroy             # Destroy managed resources
task infra:secrets-edit        # Edit encrypted secrets (for rotation)
task infra:validate            # Validate configuration
task infra:fmt                 # Format configuration
```

### Verification
```bash
kubectl get nodes -o wide
kubectl get pods -A
flux check
flux get ks -A
flux get hr -A
cilium status
cilium connectivity test
```

## Template System

**Delimiters (makejinja):**
- Block: `#% ... %#` (e.g., `#% if condition %#`)
- Variable: `#{ ... }#` (e.g., `#{ cluster_api_addr }#`)
- Comment: `#| ... #|`

**Configuration Files:**
- `cluster.yaml` - Network settings, Cloudflare config, repository info, optional UniFi DNS
- `nodes.yaml` - Node names, IPs, disks, MAC addresses, schematic IDs

**After editing templates or config:**
```bash
task configure  # Regenerates all files in kubernetes/, talos/, bootstrap/, infrastructure/
```

## Code Standards

### Configuration Files (YAML)
- Use 2-space indentation
- Follow existing patterns in `cluster.yaml` and `nodes.yaml`
- All secrets must be encrypted with SOPS (files ending in `.sops.yaml`)
- Validate with: `task configure` (includes schema validation)

### Template Files (Jinja2)
- Use custom delimiters: `#% %#`, `#{ }#`, `#| #|`
- Follow existing template structure in `templates/config/`
- Test templates by running: `task configure`
- Never edit generated files directly

### Kubernetes Manifests
- Use HelmReleases with OCI repositories
- Follow the standard app structure:
  ```
  templates/config/kubernetes/apps/<namespace>/<app>/
  ├── ks.yaml.j2              # Flux Kustomization
  └── app/
      ├── kustomization.yaml.j2
      ├── helmrelease.yaml.j2
      ├── ocirepository.yaml.j2
      └── secret.sops.yaml.j2  # (if secrets needed)
  ```

### Documentation
- Use Markdown with clear headers
- Include practical examples and commands
- Update `docs/INDEX.md` when adding new docs
- Keep token efficiency in mind (concise, value-dense)

## Boundaries

### ✅ Always Do
- Read `PROJECT_INDEX.md` first for context
- Edit templates in `templates/config/`, never generated files
- Run `task configure` after template changes
- Encrypt secrets with SOPS (`.sops.yaml` files)
- Follow existing patterns and conventions
- Run verification commands after changes
- Update documentation when making significant changes

### ⚠️ Ask First
- Modifying core infrastructure (Talos, Cilium, Flux)
- Changing network CIDRs or IP addresses
- Adding new dependencies or tools
- Modifying GitHub Actions workflows
- Changes to OpenTofu state backend configuration
- Upgrading major versions (Talos, Kubernetes, Flux)

### 🚫 Never Do
- Edit files in `kubernetes/`, `talos/`, `bootstrap/`, or `infrastructure/` directories (they are GENERATED)
- Commit unencrypted secrets or API keys
- Modify `age.key`, `github-deploy.key`, or other secret files
- Change template delimiters in `makejinja.toml`
- Remove or weaken security configurations
- Bypass SOPS encryption for secrets
- Modify `.git/` or `.github/workflows/` without explicit request

## Common Patterns

### Adding a New Application
1. Create directory: `templates/config/kubernetes/apps/<namespace>/<app>/`
2. Add `ks.yaml.j2` (Flux Kustomization)
3. Create `app/` subdirectory with manifests
4. Run `task configure` to generate
5. Commit and push to trigger Flux sync

### Modifying Node Configuration
1. Edit `nodes.yaml` with node changes
2. Run `task configure` to regenerate Talos configs
3. Apply to specific node: `task talos:apply-node IP=<ip>`

### Adding Infrastructure Resources
1. Edit templates in `templates/config/infrastructure/tofu/`
2. Run `task configure` to regenerate
3. Plan changes: `task infra:plan`
4. Apply changes: `task infra:apply`

### Troubleshooting
1. Check `docs/TROUBLESHOOTING.md` for diagnostic flowcharts
2. Use domain-specific context from `docs/ai-context/`
3. Run relevant verification commands
4. Check logs: `kubectl logs -n <namespace> <pod>`

## Key Constraints

**Control Plane:** Does NOT run workloads by default (`allowSchedulingOnControlPlanes: false`)

**GitOps Flow:** All cluster state is declarative YAML reconciled via Flux CD from Git

**Template-Driven:** All Kubernetes, Talos, and Infrastructure configs are generated from templates

**Secret Management:** All secrets encrypted with SOPS/Age, never committed in plaintext

**State Management:** OpenTofu state stored in Cloudflare R2 via HTTP backend with locking

## Documentation Reference

| Document | Purpose | When to Read |
| -------- | ------- | ------------ |
| `PROJECT_INDEX.md` | Token-efficient project summary | Every session start |
| `README.md` | Complete setup guide | Initial deployment |
| `docs/ARCHITECTURE.md` | System design and diagrams | Understanding architecture |
| `docs/CONFIGURATION.md` | Configuration reference | Editing cluster.yaml/nodes.yaml |
| `docs/OPERATIONS.md` | Day-2 operations | Maintenance and upgrades |
| `docs/TROUBLESHOOTING.md` | Diagnostic flowcharts | When issues occur |
| `docs/CLI_REFERENCE.md` | Complete command reference | Daily operations |
| `docs/APPLICATIONS.md` | Application details | Adding/modifying apps |
| `CLAUDE.md` | Claude-specific guidance | Using Claude Code |

## Tool Dependencies

Managed via `mise` (`.mise.toml`):
- talosctl 1.12.0, talhelper 3.0.44
- kubectl 1.35.0, flux 2.7.5
- helm 3.19.4, helmfile 1.2.3
- sops 3.11.0, age 1.3.1
- cilium 0.18.9, cloudflared 2025.11.1
- opentofu 1.11.2
- kustomize 5.8.0, kubeconform 0.7.0, cue 0.15.3
- yq, jq (latest)

Install all tools: `mise trust && mise install`

## Security Considerations

- All secrets must be encrypted with SOPS before committing
- Age encryption key (`age.key`) is gitignored and must never be committed
- Cloudflare API tokens should have minimal required permissions
- GitHub deploy keys should be read-only for public repos, read-write for private
- OpenTofu state backend credentials stored in `infrastructure/secrets.sops.yaml`
- Never commit credentials, tokens, or keys in plaintext

## Success Criteria

Your work is successful when:
- Templates render without errors: `task configure` succeeds
- All secrets are encrypted: `find . -name "*.sops.*" -exec sops filestatus {} \;`
- Flux reconciles successfully: `flux get ks -A` shows all healthy
- Nodes are ready: `kubectl get nodes` shows all Ready
- Applications are running: `kubectl get pods -A` shows all Running
- Documentation is updated for significant changes

## Getting Help

- **Comprehensive docs:** `docs/` directory
- **AI context:** `docs/ai-context/` for domain-specific knowledge
- **Troubleshooting:** `docs/TROUBLESHOOTING.md` with decision trees
- **Upstream community:** [Home Operations Discord](https://discord.gg/home-operations)
- **GitHub Discussions:** [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template/discussions)

---

**Remember:** This is a GitOps cluster. All changes should be declarative, version-controlled, and reconciled through Flux CD. When in doubt, read `PROJECT_INDEX.md` first, then consult the relevant domain documentation in `docs/ai-context/`.
