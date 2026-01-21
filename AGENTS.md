# AGENTS.md

Universal AI coding agent instructions for the matherlynet-talos-cluster GitOps infrastructure project. Follows the [AGENTS.md open standard](https://agents.md).

> **Claude Code users**: See `CLAUDE.md` for Serena MCP, agents, and skills guidance.

## Project Overview

GitOps-driven **Kubernetes cluster** on **Talos Linux** with **Flux CD**. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI, Envoy Gateway, SOPS/Age, makejinja templating, OpenTofu v1.11+

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

## Context Loading

**Read first:** `PROJECT_INDEX.md` - Complete project understanding in ~3K tokens

**Domain docs:** `docs/ai-context/`

- `flux-gitops.md` - Flux CD patterns
- `talos-operations.md` - Talos workflows
- `cilium-networking.md` - Cilium CNI, network policies
- `template-system.md` - makejinja templating
- `infrastructure-opentofu.md` - IaC operations

## Critical Rules

### DO

- Edit templates in `templates/config/` - never generated files
- Run `task configure` after template changes
- Use makejinja delimiters (see below)
- Encrypt secrets in `*.sops.yaml.j2` files
- Commit generated files - Flux reads from `kubernetes/`, `talos/`

### DON'T

- Edit files in `kubernetes/`, `talos/`, `bootstrap/`, `infrastructure/` (GENERATED)
- Use standard Jinja2 delimiters (`{{ }}`, `{% %}`)
- Commit `age.key`, credentials, API keys, or `.env` files
- Skip `task configure` - validation catches errors

## Template Syntax (CRITICAL)

| Type | Correct | Wrong |
|------|---------|-------|
| **Block** | `#% ... %#` | `{% ... %}` |
| **Variable** | `#{ ... }#` | `{{ ... }}` |
| **Comment** | `#| ... #|` | `{# ... #}` |

**WARNING**: Comments use SAME delimiter on both ends (`#|`), NOT `#| ... |#`.

## Essential Commands

```bash
task configure           # Render templates, validate, encrypt secrets
task reconcile           # Force Flux to sync from Git
task bootstrap:talos     # Install Talos on nodes
task bootstrap:apps      # Deploy Cilium, CoreDNS, Spegel, Flux
```

See `docs/CLI_REFERENCE.md` for complete command reference.

## Project Structure

```
templates/config/        # SOURCE - Edit here
├── kubernetes/apps/     # K8s application templates
├── talos/               # Talos configuration templates
└── infrastructure/      # OpenTofu/IaC templates

kubernetes/              # GENERATED - Never edit
talos/                   # GENERATED - Never edit
infrastructure/          # GENERATED - Never edit

cluster.yaml             # Main cluster configuration
nodes.yaml               # Node definitions
```

## Configuration Variables

Sources (in order of precedence):

1. `cluster.yaml` - Network, cloudflare, features
2. `nodes.yaml` - Node definitions
3. `templates/scripts/plugin.py` - Computed values

See `docs/CONFIGURATION.md` for complete variable reference.

## Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| Wrong delimiters | Use `#{ }#` not `{{ }}` |
| Edited generated file | Edit in `templates/config/` instead |
| Flux not syncing | Run `task reconcile` |
| Template error | Check comment syntax: `#| ... #|` |

See `docs/TROUBLESHOOTING.md` for diagnostic flowcharts.

## Security

- Encrypt all secrets with SOPS (`*.sops.yaml.j2`)
- Never commit `age.key` (gitignored)
- Verify encryption: `sops filestatus <file>`

## Key Constraints

- **Control Plane:** Does NOT run workloads (`allowSchedulingOnControlPlanes: false`)
- **GitOps Flow:** All state reconciled via Flux from Git
- **Template-Driven:** Never edit generated files

## Documentation

| Document | When to Read |
|----------|--------------|
| `PROJECT_INDEX.md` | Session start |
| `docs/ARCHITECTURE.md` | Understanding design |
| `docs/CLI_REFERENCE.md` | Daily operations |
| `docs/TROUBLESHOOTING.md` | When issues occur |
| `CLAUDE.md` | Using Claude Code |

## Success Criteria

- `task configure` succeeds without errors
- `sops filestatus` shows all secrets encrypted
- `flux get ks -A` shows all healthy
- `kubectl get nodes` shows all Ready

---

*Detailed patterns for templates, Flux apps, and Kubernetes manifests load automatically via `.claude/rules/` when editing relevant files.*
