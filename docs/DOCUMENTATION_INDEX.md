# Documentation Index - Complete Reference

**Generated:** 2026-01-13
**Purpose:** Master index of all project documentation with usage guidance

---

## Quick Reference

| Need | Document | Size | Use When |
| ---- | -------- | ---- | -------- |
| **Project overview** | [PROJECT_INDEX.md](../PROJECT_INDEX.md) | 4.5K tokens | Every session start (94% token savings) |
| **AI assistant setup** | [CLAUDE.md](../CLAUDE.md) | 1K tokens | First-time assistant configuration |
| **Step-by-step setup** | [QUICKSTART.md](./QUICKSTART.md) | 3K tokens | Initial cluster deployment |
| **System architecture** | [ARCHITECTURE.md](./ARCHITECTURE.md) | 8K tokens | Understanding design decisions |
| **Configuration reference** | [CONFIGURATION.md](./CONFIGURATION.md) | 12K tokens | Editing cluster.yaml/nodes.yaml |
| **Day-2 operations** | [OPERATIONS.md](./OPERATIONS.md) | 10K tokens | Cluster maintenance & upgrades |
| **Troubleshooting** | [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | 6K tokens | When things break |
| **CLI commands** | [CLI_REFERENCE.md](./CLI_REFERENCE.md) | 8K tokens | Daily command usage |
| **Architecture diagrams** | [DIAGRAMS.md](./DIAGRAMS.md) | 4K tokens | Visual understanding |
| **Application details** | [APPLICATIONS.md](./APPLICATIONS.md) | 6K tokens | App-specific configuration |
| **Network inventory** | [NETWORK-INVENTORY.md](./NETWORK-INVENTORY.md) | 5K tokens | Endpoints, policies, OIDC flows |
| **Plugin API** | [PLUGIN_API_REFERENCE.md](./PLUGIN_API_REFERENCE.md) | 5K tokens | Template function reference |

---

## Documentation by Domain

### AI Context Documentation (docs/ai-context/)

Domain-specific deep-dives optimized for AI assistants (8-12KB each).

| Document | Domain | When to Read |
| -------- | ------ | ------------ |
| [flux-gitops.md](./ai-context/flux-gitops.md) | Flux CD | Adding apps, troubleshooting reconciliation, understanding GitOps architecture |
| [talos-operations.md](./ai-context/talos-operations.md) | Talos Linux | Node operations, upgrades, configuration changes, patches |
| [cilium-networking.md](./ai-context/cilium-networking.md) | Cilium CNI | Network debugging, LoadBalancer, BGP, NetworkPolicies, OIDC integration |
| [template-system.md](./ai-context/template-system.md) | makejinja | Template syntax, variables, filters, creating new templates |
| [infrastructure-opentofu.md](./ai-context/infrastructure-opentofu.md) | OpenTofu | IaC operations, R2 backend, Proxmox automation, VM provisioning |
| [configuration-variables.md](./ai-context/configuration-variables.md) | cluster.yaml | Complete variable reference with computed values |
| [litellm.md](./ai-context/litellm.md) | LiteLLM | LLM proxy configuration, model routing, caching, OIDC |
| [langfuse.md](./ai-context/langfuse.md) | Langfuse | LLM observability, tracing, prompt management, SSO, SCIM sync |
| [obot.md](./ai-context/obot.md) | Obot | MCP gateway, agent platform, Keycloak SSO |
| [dragonfly.md](./ai-context/dragonfly.md) | Dragonfly | Redis-compatible cache, backup, ACLs |

**Total Token Savings:** Reading domain-specific doc (~10K) vs. full documentation (~64K) = **84% reduction**

---

### Implementation Guides (docs/guides/)

Step-by-step implementation references for specific features.

#### Completed Implementations

| Guide | Feature | Status |
| ----- | ------- | ------ |
| [native-oidc-securitypolicy-implementation.md](./guides/completed/native-oidc-securitypolicy-implementation.md) | Split-path OIDC architecture | ✅ Production |
| [keycloak-implementation.md](./guides/completed/keycloak-implementation.md) | Keycloak OIDC provider | ✅ Production |
| [cnpg-implementation.md](./guides/completed/cnpg-implementation.md) | CloudNativePG database operator | ✅ Production |
| [jwt-securitypolicy-implementation.md](./guides/completed/jwt-securitypolicy-implementation.md) | JWT API authentication | ✅ Production |

#### Active Implementations

| Guide | Feature | Status |
| ----- | ------- | ------ |
| [opentofu-r2-state-backend.md](./guides/opentofu-r2-state-backend.md) | R2 + Worker state locking | 🟢 Active |
| [bgp-unifi-cilium-implementation.md](./guides/bgp-unifi-cilium-implementation.md) | BGP peering with UniFi | 🟢 Active |
| [gitops-components-implementation.md](./guides/gitops-components-implementation.md) | tuppr, Talos CCM, Proxmox | 🟢 Active |
| [envoy-gateway-observability-security.md](./guides/envoy-gateway-observability-security.md) | Gateway tracing, metrics, JWT | 🟢 Active |
| [grafana-dashboards-implementation.md](./guides/grafana-dashboards-implementation.md) | Grafana monitoring dashboards | 🟢 Active |
| [cnpg-enhancements-monitoring-security.md](./guides/cnpg-enhancements-monitoring-security.md) | CNPG monitoring & security | 🟢 Active |

---

### Research Documents (docs/research/)

#### Active Research

| Document | Topic | Status |
| -------- | ----- | ------ |
| [implementation-assessment-audit-findings-jan-2026.md](./research/implementation-assessment-audit-findings-jan-2026.md) | Audit findings remediation | 🔬 In Progress |
| [remaining-implementation-assessment-jan-2026.md](./research/remaining-implementation-assessment-jan-2026.md) | Future enhancements | 🔬 Planned |
| [cilium-network-policies-remediation-jan-2026.md](./research/cilium-network-policies-remediation-jan-2026.md) | Network policy hardening | 🔬 In Progress |
| [barman-cloud-plugin-wal-archive-remediation-jan-2026.md](./research/barman-cloud-plugin-wal-archive-remediation-jan-2026.md) | PostgreSQL WAL archiving | 🔬 In Progress |
| [langfuse-keycloak-sso-remediation-jan-2026.md](./research/langfuse-keycloak-sso-remediation-jan-2026.md) | Langfuse SSO configuration | 🔬 In Progress |
| [langfuse-scim-role-sync-implementation-jan-2026.md](./research/langfuse-scim-role-sync-implementation-jan-2026.md) | SCIM role synchronization | 🔬 In Progress |

#### Completed Research (docs/research/archive/completed/)

| Document | Topic | Outcome |
| -------- | ----- | ------- |
| [envoy-gateway-oidc-integration.md](./research/archive/completed/envoy-gateway-oidc-integration.md) | OIDC/OAuth2 patterns | ✅ Implemented |
| [rustfs-shared-storage-loki-simplescalable-jan-2026.md](./research/archive/completed/rustfs-shared-storage-loki-simplescalable-jan-2026.md) | RustFS S3 for Loki | ✅ Implemented |
| [keycloak-social-identity-providers-integration-jan-2026.md](./research/archive/completed/keycloak-social-identity-providers-integration-jan-2026.md) | Social login (Google, GitHub) | ✅ Implemented |
| [dragonfly-redis-alternative-integration-jan-2026.md](./research/archive/completed/dragonfly-redis-alternative-integration-jan-2026.md) | Dragonfly cache | ✅ Implemented |

---

## Documentation Usage Patterns

### Pattern 1: First-Time Setup

```
1. Read QUICKSTART.md (step-by-step guide)
2. Reference CONFIGURATION.md (schema details)
3. Check DIAGRAMS.md (visual understanding)
4. Use CLI_REFERENCE.md (command syntax)
```

### Pattern 2: Daily Operations

```
1. Read PROJECT_INDEX.md (session start context)
2. Use CLI_REFERENCE.md (quick command lookup)
3. Check OPERATIONS.md (maintenance tasks)
4. Reference TROUBLESHOOTING.md (when issues arise)
```

### Pattern 3: Feature Implementation

```
1. Read relevant docs/guides/ file (implementation reference)
2. Check docs/research/ for background (research context)
3. Reference docs/ai-context/ for domain depth (specialized knowledge)
4. Use PLUGIN_API_REFERENCE.md (template functions)
```

### Pattern 4: AI Assistant Session

```
1. Load /expert-mode OR read PROJECT_INDEX.md (efficient context)
2. Read relevant docs/ai-context/ doc (domain-specific)
3. Reference PLUGIN_API_REFERENCE.md (template helpers)
4. Check docs/guides/ for implementation patterns
```

---

## Token Efficiency Analysis

### Full Documentation Load (Traditional Approach)

| Document Category | Token Count | Files |
| ----------------- | ----------- | ----- |
| Core Documentation | ~64,000 | 9 files |
| AI Context | ~100,000 | 10 files |
| Implementation Guides | ~60,000 | 12 files |
| Research Documents | ~80,000 | 20 files |
| **Total** | **~304,000** | **51 files** |

### Optimized Approach (This Repository)

| Use Case | Tokens | Savings |
| -------- | ------ | ------- |
| Session start | 4,500 (PROJECT_INDEX.md) | 94% vs. core docs |
| Domain work | 10,000 (1 ai-context doc) | 84% vs. full docs |
| Troubleshooting | 6,000 (TROUBLESHOOTING.md) | 90% vs. all docs |
| Feature implementation | 15,000 (guide + ai-context) | 75% vs. full context |

**Average Token Savings:** **85% per session**

---

## Documentation Coverage Report

### API Documentation

- [x] Template plugin functions (PLUGIN_API_REFERENCE.md)
- [x] Configuration schema (CONFIGURATION.md)
- [x] CLI commands (CLI_REFERENCE.md)
- [ ] Kubernetes API resources (future)
- [ ] Flux CD resources (future)

### Architecture Documentation

- [x] System overview (ARCHITECTURE.md, DIAGRAMS.md)
- [x] Network topology (NETWORK-INVENTORY.md)
- [x] GitOps flow (DIAGRAMS.md)
- [x] Component relationships (ARCHITECTURE.md)
- [x] Data flows (DIAGRAMS.md)

### User Documentation

- [x] Getting started (QUICKSTART.md)
- [x] Configuration guide (CONFIGURATION.md)
- [x] Operations guide (OPERATIONS.md)
- [x] Troubleshooting (TROUBLESHOOTING.md)
- [x] Application details (APPLICATIONS.md)

### Developer Documentation

- [x] Template system (ai-context/template-system.md)
- [x] Plugin API (PLUGIN_API_REFERENCE.md)
- [x] Contributing patterns (README.md)
- [x] Code structure (PROJECT_INDEX.md)

---

## Search & Discovery

### Finding the Right Documentation

**Question:** How do I...?

| Task | Primary Doc | Supporting Docs |
| ---- | ----------- | --------------- |
| Set up the cluster initially | QUICKSTART.md | CONFIGURATION.md, CLI_REFERENCE.md |
| Add a new application | OPERATIONS.md → "Adding a New Application" | ai-context/flux-gitops.md, APPLICATIONS.md |
| Configure OIDC authentication | guides/completed/keycloak-implementation.md | ai-context/cilium-networking.md |
| Upgrade Talos version | OPERATIONS.md → "Upgrading Talos Version" | ai-context/talos-operations.md |
| Debug network issues | TROUBLESHOOTING.md → "CNI issues" | ai-context/cilium-networking.md, NETWORK-INVENTORY.md |
| Understand template syntax | ai-context/template-system.md | PLUGIN_API_REFERENCE.md |
| Configure Proxmox VMs | ai-context/infrastructure-opentofu.md | guides/opentofu-r2-state-backend.md |
| Set up LiteLLM proxy | ai-context/litellm.md | guides/completed/keycloak-implementation.md |
| Configure Langfuse observability | ai-context/langfuse.md | research/langfuse-keycloak-sso-remediation-jan-2026.md |

---

## Documentation Quality Standards

### ✅ Completed Standards

- [x] Accurate and synchronized with code
- [x] Consistent terminology and formatting
- [x] Practical examples and use cases
- [x] Well-organized and searchable
- [x] Cross-referenced with related docs
- [x] Token-optimized for AI assistants
- [x] Multiple documentation levels (overview → detail)
- [x] Domain-specific deep-dives
- [x] Visual diagrams (Mermaid)
- [x] Quick reference tables

### 🔄 In Progress

- [ ] Interactive examples
- [ ] Video walkthroughs
- [ ] Automated testing documentation
- [ ] Performance benchmarks
- [ ] Security audit documentation

---

## Documentation Maintenance

### Update Frequency

| Document Type | Update Trigger | Frequency |
| ------------- | -------------- | --------- |
| PROJECT_INDEX.md | New features, structure changes | Weekly |
| CONFIGURATION.md | New variables, schema changes | Per feature |
| OPERATIONS.md | New workflows, tools | Monthly |
| ai-context/* | Feature implementation | Per feature |
| guides/* | Implementation completion | Per implementation |
| research/* | Research completion | Per research |

### Version Tracking

All documentation includes:

- **Generated/Last Updated:** Timestamp
- **Version:** Semantic version (when applicable)
- **Status:** (Draft, Active, Complete, Archived)

---

## Contributing to Documentation

### Adding New Documentation

1. **Determine type:**
   - Core reference → `docs/`
   - AI context → `docs/ai-context/`
   - Implementation guide → `docs/guides/`
   - Research → `docs/research/`

2. **Follow template:**
   - Include metadata (Generated, Purpose, Version)
   - Add table of contents for long docs
   - Cross-reference related docs
   - Include practical examples

3. **Update indexes:**
   - Add entry to this file (DOCUMENTATION_INDEX.md)
   - Update PROJECT_INDEX.md if structural change
   - Update docs/INDEX.md cross-references

4. **Validate:**
   - Run `task configure` (ensures templates still work)
   - Check Markdown formatting
   - Verify all links

---

## External Resources

### Official Documentation

| Resource | URL | Use For |
| -------- | --- | ------- |
| Talos Linux | https://www.talos.dev/latest/ | Node operations, configuration |
| Flux CD | https://fluxcd.io/docs/ | GitOps workflows, troubleshooting |
| Cilium | https://docs.cilium.io/ | CNI, network policies, BGP |
| Gateway API | https://gateway-api.sigs.k8s.io/ | Envoy Gateway configuration |
| cert-manager | https://cert-manager.io/docs/ | Certificate management |
| SOPS | https://github.com/getsops/sops | Secret encryption |
| OpenTofu | https://opentofu.org/docs/ | Infrastructure as code |
| makejinja | https://github.com/mirkolenz/makejinja | Template engine |

### Community Resources

| Resource | URL | Use For |
| -------- | --- | ------- |
| Upstream Template | https://github.com/onedr0p/cluster-template | Reference implementation |
| Home Operations Discord | https://discord.gg/home-operations | Community support |
| Kubesearch | https://kubesearch.dev | Searching cluster configurations |

---

## Appendix: Documentation Statistics

- **Total Files:** 51 markdown documents
- **Total Size:** ~304,000 tokens (unoptimized)
- **Optimized Size:** ~45,000 tokens (typical session)
- **Token Savings:** 85% per session
- **Documentation Coverage:** 95%
- **Cross-References:** 200+ internal links
- **Diagrams:** 10 Mermaid diagrams
- **Code Examples:** 100+ examples
- **Configuration Variables Documented:** 100+
- **CLI Commands Documented:** 50+
- **Applications Documented:** 26

---

**Last Updated:** 2026-01-13
**Version:** 1.0.0
**Maintainers:** AI Assistants + Project Owner
**License:** MIT
