# Context Loading Strategy

**Purpose**: Optimize token usage when working with this project by loading only necessary context based on task type.

**Target**: Maximize efficiency while maintaining sufficient context for high-quality responses.

**Token Budget**: 200K tokens per conversation (Claude Sonnet 4.5)

---

## 🎯 Context Loading Philosophy

**Principle**: Load progressively - start minimal, expand as needed.

**Anti-Pattern**: Loading all documentation upfront (wastes 40K+ tokens on potentially irrelevant context)

**Best Practice**: Use decision tree to determine optimal context set for each task type

---

## 📊 Token Cost Reference

Quick reference for planning context loads:

| Document | Token Cost (Approx) | Purpose |
|----------|---------------------|---------|
| `expert-mode.md` | ~3K | Quick reference, always load first |
| `PROJECT_INDEX.json` | ~2K | Machine-readable metadata |
| `docs/INDEX.md` | ~4K | Documentation cross-reference |
| `CLAUDE.md` | ~2K | Project instructions |
| `QUICKSTART.md` | ~8K | Step-by-step setup guide |
| `CLI_REFERENCE.md` | ~10K | Complete command reference |
| `TROUBLESHOOTING.md` | ~12K | Diagnostic flowcharts |
| `ARCHITECTURE.md` | ~15K | System design deep-dive |
| `CONFIGURATION.md` | ~12K | Schema reference |
| `OPERATIONS.md` | ~10K | Day-2 operations |
| `APPLICATIONS.md` | ~8K | Application catalog |
| `DIAGRAMS.md` | ~6K | Mermaid architecture diagrams |
| `DOCUMENTATION_STANDARDS.md` | ~8K | Standards for creating docs |
| `docs/ai-context/*.md` (each) | ~5-10K | Domain-specific deep dives |
| `docs/guides/*.md` (each) | ~8-15K | Implementation guides |

**Total if loading everything**: ~150K+ tokens (75% of budget before any work!)

---

## 🌲 Context Loading Decision Tree

```
                         Start: User Request
                                  |
                                  v
                    ┌─────────────────────────┐
                    │  What type of task?     │
                    └────────────┬────────────┘
                                 |
        ┌────────────────────────┼────────────────────────┐
        |                        |                        |
        v                        v                        v
   Quick Question         Configuration           Implementation
   (e.g., versions)       (e.g., add app)        (e.g., new feature)
        |                        |                        |
        v                        v                        v
  expert-mode only       expert-mode +            expert-mode +
     (~3K)              task-specific            ARCHITECTURE +
                          docs                   ai-context/* +
                         (~10-20K)               standards
                                                  (~40-50K)
                                 |
                                 v
                    More decision branches below...
```

---

## 🎯 Task-Based Context Loading Patterns

### Pattern 1: Quick Information Queries

**Examples**:
- "What version of Talos is this cluster running?"
- "How many nodes are in the cluster?"
- "What's the command to force Flux reconciliation?"

**Context to Load**:
```
✅ expert-mode.md (~3K tokens)
```

**Total**: ~3K tokens

**Rationale**: Expert-mode contains all high-level info and quick references

---

### Pattern 2: Simple Configuration Changes

**Examples**:
- "Add a new simple application"
- "Update an existing HelmRelease version"
- "Create a new namespace"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ APPLICATIONS.md (~8K) - if adding/modifying apps
✅ CLI_REFERENCE.md (~10K) - if unfamiliar with commands
```

**Total**: ~3-20K tokens (progressive loading)

**Workflow**:
1. Start with expert-mode only
2. If user asks about app patterns → load APPLICATIONS.md
3. If user asks about specific commands → load CLI_REFERENCE.md

---

### Pattern 3: Complex Configuration (Network/Security/OIDC)

**Examples**:
- "Configure OIDC authentication for new app"
- "Set up Cilium network policies"
- "Add Gateway API route with TLS"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ Relevant ai-context doc (~8K):
   - cilium-networking.md for network/OIDC issues
   - flux-gitops.md for Flux patterns
   - template-system.md for template questions
✅ APPLICATIONS.md (~8K) - for app patterns
✅ TROUBLESHOOTING.md (~12K) - if debugging
```

**Total**: ~20-30K tokens

**Decision Logic**:
- **Network/OIDC issues** → cilium-networking.md
- **Template questions** → template-system.md
- **Flux issues** → flux-gitops.md
- **Talos node issues** → talos-operations.md
- **Infrastructure** → infrastructure-opentofu.md

---

### Pattern 4: Troubleshooting

**Examples**:
- "Flux kustomization failing to reconcile"
- "Pods not starting in namespace X"
- "Network policy blocking traffic"
- "SOPS decryption errors"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ TROUBLESHOOTING.md (~12K) - diagnostic flowcharts
✅ Relevant ai-context doc (~8K):
   - flux-gitops.md for Flux issues
   - cilium-networking.md for network issues
   - talos-operations.md for node issues
✅ DIAGRAMS.md (~6K) - for architecture understanding
```

**Total**: ~20-30K tokens

**Progressive Loading**:
1. Start with expert-mode + TROUBLESHOOTING.md
2. If issue domain-specific → load relevant ai-context doc
3. If architecture understanding needed → load DIAGRAMS.md

---

### Pattern 5: New Feature Implementation

**Examples**:
- "Implement a new database-backed application"
- "Add monitoring for custom metrics"
- "Create multi-tenant namespace isolation"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ ARCHITECTURE.md (~15K) - understand system design
✅ DOCUMENTATION_STANDARDS.md (~8K) - for documenting work
✅ Relevant ai-context docs (~15K total):
   - 2-3 domain-specific docs
✅ Relevant implementation guides (~10K)
✅ APPLICATIONS.md (~8K)
```

**Total**: ~40-60K tokens

**Justification**: Complex implementations require comprehensive understanding

---

### Pattern 6: Documentation Creation

**Examples**:
- "Document the OIDC implementation"
- "Create troubleshooting guide for database issues"
- "Write implementation guide for new feature"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ DOCUMENTATION_STANDARDS.md (~8K) - CRITICAL
✅ Relevant domain ai-context (~8K)
✅ Existing related documentation (~10K) - for consistency
```

**Total**: ~20-30K tokens

**Critical**: ALWAYS load DOCUMENTATION_STANDARDS.md when creating comprehensive documentation

---

### Pattern 7: Infrastructure Changes (OpenTofu/Proxmox)

**Examples**:
- "Modify Proxmox VM configuration"
- "Update R2 backend settings"
- "Add new infrastructure resources"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ infrastructure-opentofu.md (~8K)
✅ CONFIGURATION.md (~12K) - for variable reference
✅ CLI_REFERENCE.md (~10K) - for task infra:* commands
```

**Total**: ~30-35K tokens

---

### Pattern 8: Template System Work

**Examples**:
- "Fix makejinja template rendering error"
- "Add new computed variable in plugin.py"
- "Create new app template following project patterns"

**Context to Load**:
```
✅ expert-mode.md (~3K)
✅ template-system.md (~8K)
✅ CONFIGURATION.md (~12K) - for variable schema
✅ Existing template examples (~5K) - read actual templates
```

**Total**: ~25-30K tokens

---

## 🔄 Progressive Loading Workflow

**Step 1: Always Start Minimal**
```
Load: expert-mode.md (~3K)
```

**Step 2: Assess Task Complexity**
```
if simple_query:
    proceed with expert-mode only
elif configuration_change:
    load APPLICATIONS.md or CLI_REFERENCE.md
elif troubleshooting:
    load TROUBLESHOOTING.md + domain ai-context
elif implementation:
    load ARCHITECTURE.md + STANDARDS + ai-context
elif documentation:
    load DOCUMENTATION_STANDARDS.md + domain context
```

**Step 3: Expand Context As Needed**
```
# User asks follow-up question needing deeper context
if additional_context_needed:
    load specific doc(s)
    keep running token count
```

**Step 4: Monitor Token Budget**
```
# Approaching limits
if tokens_used > 150K:
    summarize and compress context
    retain only critical information
```

---

## 📋 Quick Reference: Load This Doc When...

| User Says... | Load Context Set | Token Cost |
|-------------|------------------|------------|
| "What version..." | expert-mode | 3K |
| "How do I..." | expert-mode + CLI_REFERENCE | 13K |
| "Add simple app" | expert-mode + APPLICATIONS | 11K |
| "Fix Flux error" | expert-mode + TROUBLESHOOTING + flux-gitops | 23K |
| "Configure OIDC" | expert-mode + cilium-networking + APPLICATIONS | 19K |
| "Implement feature" | expert-mode + ARCHITECTURE + STANDARDS + ai-context | 45K |
| "Document this" | expert-mode + DOCUMENTATION_STANDARDS + domain | 25K |
| "Debug network" | expert-mode + TROUBLESHOOTING + cilium-networking + DIAGRAMS | 29K |
| "Modify Talos config" | expert-mode + talos-operations + CONFIGURATION | 23K |
| "Change infrastructure" | expert-mode + infrastructure-opentofu + CLI_REFERENCE | 21K |

---

## 🎓 Best Practices

### DO ✅

1. **Start with expert-mode**: Always begin with minimal context
2. **Load progressively**: Add context as conversation develops
3. **Ask before loading**: "Should I load ARCHITECTURE.md for deeper context?"
4. **Track token usage**: Keep mental note of accumulated tokens
5. **Prioritize relevance**: Only load docs directly related to task
6. **Use decision tree**: Follow patterns above for consistency

### DON'T ❌

1. **Don't load everything upfront**: Wastes majority of token budget
2. **Don't skip expert-mode**: It's the efficient foundation
3. **Don't load docs "just in case"**: Only load when truly needed
4. **Don't ignore token costs**: Each doc has a cost
5. **Don't load multiple implementation guides**: Choose most relevant one
6. **Don't forget DOCUMENTATION_STANDARDS**: Critical for creating docs

---

## 🧪 Example Context Loading Sessions

### Example 1: Quick Question

**User**: "What's the command to upgrade Talos?"

**Context Loaded**:
- expert-mode.md (3K)

**Response**: Check expert-mode quick reference → `task talos:upgrade-node IP=<ip>`

**Tokens Used**: ~3K

---

### Example 2: App Deployment Troubleshooting

**User**: "My HelmRelease isn't reconciling, getting 'chart not found' error"

**Context Loaded (Progressive)**:
1. expert-mode.md (3K)
2. *Assess: Flux issue, need troubleshooting*
3. TROUBLESHOOTING.md (12K)
4. *User mentions OCI repository*
5. flux-gitops.md (8K)

**Tokens Used**: ~23K

**Outcome**: Identified missing OCIRepository resource, provided fix with validation commands

---

### Example 3: New Feature Implementation

**User**: "I want to implement PostgreSQL database for new application with OIDC authentication"

**Context Loaded**:
1. expert-mode.md (3K)
2. *Assess: Complex implementation*
3. ARCHITECTURE.md (15K)
4. DOCUMENTATION_STANDARDS.md (8K) - will document work
5. docs/guides/cnpg-implementation.md (10K) - PostgreSQL pattern
6. cilium-networking.md (8K) - OIDC pattern
7. APPLICATIONS.md (8K) - app structure

**Tokens Used**: ~52K

**Outcome**: Comprehensive implementation with documentation following standards

---

### Example 4: Template Syntax Error

**User**: "Getting Jinja2 syntax error when running task configure"

**Context Loaded**:
1. expert-mode.md (3K)
2. *Assess: Template system issue*
3. template-system.md (8K)
4. *Read actual template file* (2K)

**Tokens Used**: ~13K

**Outcome**: Identified incorrect delimiter usage (`{{ }}` instead of `#{ }#`), provided fix

---

## 🎯 Token Budget Optimization Tips

1. **Use expert-mode's pointers**: It references deeper docs - only load if needed
2. **Read selectively**: Use Read tool with offset/limit for large docs
3. **Prefer CLI_REFERENCE**: More concise than full OPERATIONS.md
4. **Use QUICKSTART for setup questions**: More targeted than ARCHITECTURE
5. **Leverage TROUBLESHOOTING flowcharts**: Visual guidance without full context
6. **DIAGRAMS.md for architecture questions**: Visual > text for system understanding
7. **Check PROJECT_INDEX.json first**: May answer question without loading full docs

---

## 📈 Success Metrics

**Efficient Context Loading** achieves:
- < 20K tokens for simple tasks
- < 50K tokens for complex implementations
- > 150K tokens remaining for actual work
- Minimal context re-loading between questions
- High relevance of loaded context

**Warning Signs of Inefficiency**:
- Loading > 50K tokens before starting work
- Loading multiple full guides when only one relevant
- Re-loading same docs multiple times
- Token budget exhausted before task completion

---

## 🔗 Related Documentation

- **expert-mode.md**: Start here (always)
- **DOCUMENTATION_STANDARDS.md**: When creating comprehensive docs
- **docs/INDEX.md**: Documentation cross-reference
- **PROJECT_INDEX.json**: Machine-readable project metadata
- **All ai-context docs**: Domain-specific deep dives (load selectively)

---

**Last Updated**: 2026-01-16
**Version**: 1.0
**Token Budget Target**: Use < 25% of budget on context loading for typical tasks
**Review Cycle**: Monthly or when documentation structure changes
