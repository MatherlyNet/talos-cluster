# CLAUDE.md

Claude Code-specific guidance for the matherlynet-talos-cluster repository.

> **Universal guidelines** (commands, patterns, dos/don'ts): See `AGENTS.md`

## Quick Start

1. Run `/expert-mode` to initialize session with efficient context loading
2. Use skills and agents for common tasks
3. Serena memories load on-demand for deep context

## Repository Overview

GitOps-driven Kubernetes cluster on Talos Linux with Flux CD. All cluster state is declarative YAML generated from Jinja2 templates.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI, Envoy Gateway, SOPS/Age, makejinja, OpenTofu

## Serena MCP Memories

Load on-demand based on task:

| Memory | When to Load |
|--------|--------------|
| `codebase_architecture` | Deep architectural patterns |
| `task_completion_checklist` | Before completing any task |
| `network_policy_patterns` | Creating CiliumNetworkPolicies |
| `authentication_architecture` | OIDC, Keycloak, SSO |
| `tech_stack_and_dependencies` | Tool versions, upgrades |

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/expert-mode` | Initialize session with context |
| `/flux-status` | GitOps health check |
| `/talos-status` | Node health check |
| `/infra-status` | Infrastructure check |
| `/network-status` | Network diagnostics |

## Custom Agents

| Agent | Purpose |
|-------|---------|
| `talos-expert` | Talos operations, upgrades |
| `flux-expert` | Flux troubleshooting |
| `template-expert` | makejinja patterns |
| `network-debugger` | Cilium/Gateway debugging |
| `infra-expert` | OpenTofu/Proxmox |
| `context-forge-expert` | MCP Context Forge |

## Skills

| Skill | Purpose |
|-------|---------|
| `/scaffold-flux-app` | Scaffold new Flux app |
| `/helm-chart-lookup` | Find OCI chart URLs |
| `/oidc-integration` | Configure OIDC/SSO |
| `/network-policy-helper` | Generate CiliumNetworkPolicy |
| `/node-config-helper` | Node configuration |
| `/cnpg-database` | Provision PostgreSQL |
| `/feature-advisor` | Explain feature effects |
| `/debug-context` | Auto-load debug context |

## Path-Specific Rules

Rules in `.claude/rules/` auto-activate based on file patterns:

| Rule | When Active |
|------|-------------|
| `kubernetes.md` | Editing `**/kubernetes/**/*.yaml.j2` |
| `flux-apps.md` | Editing `**/apps/**` |
| `makejinja.md` | Editing `**/*.j2` |
| `talos-patches.md` | Editing `**/talos/**` |

These provide comprehensive patterns that load only when needed.

## Context Optimization

1. **Don't re-read CLAUDE.md/AGENTS.md** - already in context
2. **Load memories on-demand** - not upfront
3. **Use skills** - they have built-in context
4. **Use agents** - they have specialized tools

## Domain Documentation

Deep context in `docs/ai-context/`:

- `flux-gitops.md` - Flux patterns
- `talos-operations.md` - Talos workflows
- `cilium-networking.md` - Network policies
- `template-system.md` - makejinja
- `infrastructure-opentofu.md` - IaC

## Quick Troubleshooting

| Issue | Command |
|-------|---------|
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| Network blocking | `hubble observe --verdict DROPPED` |
| OIDC failure | Check envoy logs, verify SecurityPolicy |

See `docs/TROUBLESHOOTING.md` for comprehensive diagnostics.

---

*For universal guidelines, see `AGENTS.md`. Detailed patterns auto-load via `.claude/rules/`.*
