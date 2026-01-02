# AI Context Documentation

> Domain-specific documentation for AI assistants working with this project.

## Purpose

These documents provide deep-dive knowledge for AI assistants (Claude, GPT, etc.) when working on specific subsystems. They complement the main documentation with implementation details, troubleshooting flows, and contextual knowledge.

## Documents

| Document | Domain | Use When |
| ---------- | -------- | ---------- |
| [flux-gitops.md](./flux-gitops.md) | Flux CD | Adding apps, troubleshooting sync issues, understanding GitOps flow |
| [talos-operations.md](./talos-operations.md) | Talos Linux | Node operations, upgrades, configuration changes |
| [cilium-networking.md](./cilium-networking.md) | Cilium CNI | Network debugging, LoadBalancer issues, BGP config |
| [template-system.md](./template-system.md) | makejinja | Template syntax, adding variables, creating new templates |
| [infrastructure-opentofu.md](./infrastructure-opentofu.md) | OpenTofu | IaC operations, R2 backend, Proxmox automation |

## Quick Reference

### For GitOps Tasks
```
Read: docs/ai-context/flux-gitops.md
Agent: .claude/agents/flux-expert.md
```

### For Node Operations
```
Read: docs/ai-context/talos-operations.md
Agent: .claude/agents/talos-expert.md
```

### For Network Issues
```
Read: docs/ai-context/cilium-networking.md
Agent: .claude/agents/network-debugger.md
```

### For Template Changes
```
Read: docs/ai-context/template-system.md
Agent: .claude/agents/template-expert.md
```

### For Infrastructure/IaC
```
Read: docs/ai-context/infrastructure-opentofu.md
Agent: .claude/agents/infra-expert.md
```

## Complementary Documentation

For quick reference during operations:
- `docs/TROUBLESHOOTING.md` - Diagnostic flowcharts and decision trees
- `docs/CLI_REFERENCE.md` - Complete command reference for all tools
- `docs/QUICKSTART.md` - Step-by-step setup guide
- `docs/DIAGRAMS.md` - Visual architecture diagrams (Mermaid)

## Token Efficiency

These documents are designed for efficient context loading:
- Each document focuses on one domain
- Includes practical commands and examples
- Avoids redundancy with main docs
- Provides troubleshooting decision trees

For minimal context loading, start with:
1. `PROJECT_INDEX.json` (3KB)
2. Relevant ai-context document (~8-12KB each)

This is more efficient than loading full documentation (~64KB).
