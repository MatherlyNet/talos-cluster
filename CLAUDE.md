# CLAUDE.md

Claude Code-specific guidance for the matherlynet-talos-cluster repository. This file complements `AGENTS.md` with Claude-specific tooling and context.

> **Important**: For universal project guidelines (commands, code patterns, dos/don'ts), see `AGENTS.md` at the repository root. This file contains only Claude Code-specific information.

## Quick Start

1. **Universal guidelines**: Read `AGENTS.md` for project structure, commands, and conventions
2. **Claude-specific**: This file for Serena MCP, memories, skills, and Claude Code features
3. **Initialization**: Run `/expert-mode` to activate full context efficiently

## Repository Overview

GitOps-driven Kubernetes cluster template on Talos Linux with Flux CD. All cluster state is declarative YAML generated from Jinja2 templates and reconciled via GitOps.

**Stack:** Talos Linux v1.12.0, Kubernetes v1.35.0, Flux CD, Cilium CNI (kube-proxy replacement, BGP optional), Gateway API + Envoy, SOPS/Age encryption, Cloudflare (DNS + Tunnel), UniFi DNS (optional), makejinja templating, OpenTofu v1.11+ (IaC)

**Upstream:** Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)

**Control Plane:** Does NOT run workloads by default (`allowSchedulingOnControlPlanes: false`)

## When to Read What

| Task | Read | Don't Read |
|------|------|------------|
| **Any task** | `AGENTS.md` (auto-loaded) | Full architecture docs |
| **Quick fix / simple edit** | `CLAUDE.md` only | Memories, deep docs |
| **New application** | `/scaffold-flux-app` skill | Full Flux documentation |
| **Template work** | `docs/ai-context/template-system.md` | All ai-context files |
| **Debugging Flux** | `docs/ai-context/flux-gitops.md` | Unrelated domains |
| **Node operations** | `docs/ai-context/talos-operations.md` | Network docs |
| **Network issues** | `docs/ai-context/cilium-networking.md` | Template docs |
| **OIDC integration** | `/oidc-integration` skill | All OIDC research docs |
| **Architecture design** | `docs/ARCHITECTURE.md` + relevant ai-context | Quick references |
| **Deep project work** | Load relevant Serena memory | All memories upfront |

## Serena MCP Integration

This project uses [Serena MCP](https://github.com/serena-ai/serena) for enhanced code intelligence. Serena provides memories for deep context.

### Available Serena Memories

Load on-demand based on task requirements:

| Memory | When to Load |
|--------|--------------|
| `codebase_architecture` | Deep architectural patterns, design decisions, dependency chains |
| `task_completion_checklist` | Before completing any task (pre-commit validation) |
| `documentation_best_practices` | Creating formal documentation, analysis reports |
| `style_and_conventions` | Detailed style rules beyond AGENTS.md |
| `flux_dependency_patterns` | Working with Flux dependencies, app ordering |
| `network_policy_patterns` | Creating CiliumNetworkPolicies |
| `authentication_architecture` | OIDC, Keycloak, SSO integration |
| `tech_stack_and_dependencies` | Tool versions, upgrade paths, compatibility |
| `project_overview` | Quick project context |

**Note**: `AGENTS.md` contains essential commands and conventions. Serena memories provide deeper context when needed.

## Claude Code Directory Structure

```
.claude/
├── commands/                     # Slash commands
│   ├── expert-mode.md            # Session initialization
│   ├── flux-status.md            # GitOps health check
│   ├── talos-status.md           # Node health check
│   ├── infra-status.md           # Infrastructure check
│   └── network-status.md         # Network diagnostics
├── agents/                       # Custom subagents
│   ├── talos-expert.md           # Talos operations
│   ├── flux-expert.md            # Flux troubleshooting
│   ├── template-expert.md        # makejinja patterns
│   ├── network-debugger.md       # Cilium/Gateway debugging
│   ├── infra-expert.md           # OpenTofu/Proxmox
│   └── context-forge-expert.md   # MCP Context Forge
├── skills/                       # Progressive disclosure skills
│   ├── scaffold-flux-app/        # New app scaffolding
│   ├── helm-chart-lookup/        # Chart discovery
│   ├── oidc-integration/         # OIDC configuration
│   ├── network-policy-helper/    # Policy generation
│   ├── node-config-helper/       # Node configuration
│   ├── cnpg-database/            # PostgreSQL provisioning
│   ├── feature-advisor/          # Feature enablement
│   ├── debug-context/            # Context loading
│   └── mcp-context-forge/        # MCP gateway config
├── rules/                        # Path-specific auto-activated rules
│   ├── kubernetes.md             # K8s manifest patterns
│   ├── flux-apps.md              # Flux app structure
│   ├── talos-patches.md          # Talos patch patterns
│   ├── makejinja.md              # Template delimiters
│   └── mcp-context-forge.md      # MCP template rules
├── output-styles/                # Response formatting
│   ├── minimal.md                # Terse responses
│   ├── debugging.md              # Structured debugging
│   └── ops-runbook.md            # Operations format
├── instructions/                 # General instructions
│   ├── context-optimization-guide.md
│   ├── documentation-standards.md
│   └── gitops-patterns.md
├── settings.json                 # Hooks configuration
└── settings.local.json           # Local overrides
```

### Slash Commands

| Command | Purpose |
|---------|---------|
| `/expert-mode` | Initialize session with efficient context loading |
| `/flux-status` | Quick GitOps health check |
| `/talos-status` | Quick node health check |
| `/infra-status` | Quick infrastructure health check |
| `/network-status` | Quick network diagnostics |

### Custom Agents

| Agent | Purpose |
|-------|---------|
| `talos-expert` | Talos node operations, upgrades, patches |
| `flux-expert` | Flux troubleshooting, reconciliation issues |
| `template-expert` | makejinja templates, Jinja2 patterns |
| `network-debugger` | Cilium/Gateway debugging, connectivity, OIDC |
| `infra-expert` | OpenTofu/Proxmox IaC operations |
| `context-forge-expert` | MCP Context Forge gateway, federation, SSO |

### Skills

| Skill | Purpose |
|-------|---------|
| `/scaffold-flux-app` | Scaffold new Flux CD application structure |
| `/helm-chart-lookup` | Find OCI repository URLs for Helm charts |
| `/oidc-integration` | Configure OIDC/SSO for applications |
| `/network-policy-helper` | Generate CiliumNetworkPolicy |
| `/node-config-helper` | Help configure nodes in nodes.yaml |
| `/cnpg-database` | Provision CloudNativePG PostgreSQL database |
| `/feature-advisor` | Explain feature effects and prerequisites |
| `/debug-context` | Auto-load debugging context based on error |

### Output Styles

| Style | When to Use |
|-------|-------------|
| `minimal` | Quick answers, simple tasks |
| `debugging` | Structured problem analysis |
| `ops-runbook` | Operations procedures, step-by-step guides |

### Path-Specific Rules

Rules auto-activate based on file patterns:

| Rule | Glob Pattern | Purpose |
|------|--------------|---------|
| `kubernetes.md` | `**/*.yaml.j2` in kubernetes/ | K8s manifest patterns |
| `flux-apps.md` | `**/apps/**` | Flux app structure |
| `talos-patches.md` | `**/talos/**` | Talos patch patterns |
| `makejinja.md` | `**/*.j2` | Template delimiters |

## Context Optimization

Claude Code automatically injects this file (~1,500 tokens) into every conversation. To minimize context usage:

1. **Don't re-read CLAUDE.md** - it's already in context
2. **Reference AGENTS.md** - universal content is there
3. **Load memories on-demand** - not upfront
4. **Use skills** - they have built-in context

See `.claude/instructions/context-optimization-guide.md` for detailed strategies.

## Domain Documentation

Deep context in `docs/ai-context/`:

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

## Documentation Standards

When creating comprehensive documentation:

- Apply standards from `.claude/instructions/documentation-standards.md`
- Load `documentation_best_practices` memory for detailed templates
- Core: Evidence-based, specific file refs, copy-paste ready code, validation commands
- Enhanced: Diagnostic flowcharts, error catalogs (when relevant)

## Troubleshooting Quick Reference

| Issue | Command |
|-------|---------|
| Template errors | `task configure` (check output) |
| Flux not syncing | `flux get ks -A`, `task reconcile` |
| Node not ready | `talosctl health -n <ip>` |
| CNI issues | `cilium status`, `cilium connectivity test` |
| Network policy blocking | `hubble observe --verdict DROPPED` |
| OIDC "OAuth flow failed" | Check envoy logs; verify SecurityPolicy internal `tokenEndpoint` |
| PostgreSQL issues | `kubectl cnpg status <cluster> -n <namespace>` |

For comprehensive troubleshooting, see `docs/TROUBLESHOOTING.md`.

## Key Files Reference

| Purpose | Path |
|---------|------|
| **Universal guidelines** | `AGENTS.md` |
| **Task runner** | `Taskfile.yaml`, `.taskfiles/` |
| **Dev tools** | `.mise.toml` (managed by mise) |
| **Cluster config** | `cluster.yaml` |
| **Node config** | `nodes.yaml` |
| **Template engine** | `makejinja.toml` |
| **SOPS rules** | `.sops.yaml` (generated) |
| **CLI reference** | `docs/CLI_REFERENCE.md` |
| **Troubleshooting** | `docs/TROUBLESHOOTING.md` |

## Template Delimiters (CRITICAL)

```text
Block:    #% ... %#     (NOT {% ... %})
Variable: #{ ... }#     (NOT {{ ... }})
Comment:  #| ... #|     (SYMMETRICAL - both ends use #|)
```

> **CRITICAL**: Comments use the SAME delimiter on both ends (`#|`). The correct comment is `#| comment here #|`, **never** `#| comment here |#`.

---

*For universal project guidelines, commands, code patterns, and conventions, see `AGENTS.md`.*
