# Claude Code Skills Recommendations

> Research findings and recommendations for implementing specialized skills to enhance the matherlynet-talos-cluster project workflow.
>
> **Updated:** January 2026 (Revised after deeper project analysis)

## Executive Summary

This document analyzes the current AI assistant configuration, existing automation, and identifies opportunities for implementing Claude Code Skills. Skills are **model-invoked** capabilities that activate automatically based on context, complementing the existing **user-invoked** slash commands and **deep expertise** agents.

**Key Finding:** This project has extensive automation via `go-task`. Any skill recommendations must add value beyond what's already automated.

---

## Current State Analysis

### Existing Automation (go-task)

The project has sophisticated automation that handles many workflows automatically:

| Task | Automation |
| ------ | ------------ |
| `task configure` | Renders templates, validates CUE schemas, validates K8s manifests (kubeconform), validates Talos config (talhelper), **auto-encrypts all `*.sops.*` files**, conditionally initializes OpenTofu |
| `task init` | Generates Age key, deploy key, push token, creates config from samples |
| `task bootstrap:talos` | Full Talos installation workflow |
| `task bootstrap:apps` | Deploys Cilium, CoreDNS, Spegel, Flux |
| `task talos:*` | Node management, upgrades |
| `task infra:*` | OpenTofu operations with auto-credential injection |

### Existing AI Tooling

| Type | Count | Purpose |
| ------ | ------- | --------- |
| **Slash Commands** | 5 | Quick status checks |
| **Agents** | 5 | Deep expertise for troubleshooting |
| **AI Context Docs** | 10 | Domain-specific knowledge |

### templates/scripts/plugin.py Automation

The plugin.py provides extensive derived configuration logic:

- **60+ computed variables** from cluster.yaml inputs
- **Feature enablement chains** (e.g., `cnpg_enabled` → `cnpg_backup_enabled` → `cnpg_barman_plugin_enabled`)
- **OIDC URL derivation** (hostnames, issuer URLs, JWKS URIs)
- **Conditional defaults** based on what's configured
- **Proxmox VM defaults** with role-based overrides

### What's Already Automated (NOT Skill Candidates)

| Workflow | Automated By | Why NOT a Skill |
| ---------- | -------------- | ----------------- |
| **Secret encryption** | `task configure` → `encrypt-secrets` | Automatic for all `*.sops.*` files |
| **Template validation** | `task configure` → CUE + kubeconform + talhelper | Built into central workflow |
| **Schema validation** | CUE schemas in `.taskfiles/template/resources/` | Runs automatically |
| **Pre-commit checks** | `task configure` does most validation | Already comprehensive |
| **Derived variable computation** | plugin.py | Automatic on `task configure` |

---

## Gap Analysis

### What's Missing (Actual Gaps)

| Gap | Description | Impact |
| ----- | ------------- | -------- |
| **Application scaffolding** | No automation for creating new Flux app structure | Manual 15-20 min per app |
| **Feature impact understanding** | plugin.py logic is complex, effects unclear | Configuration errors |
| **Network policy generation** | CiliumNetworkPolicies require deep knowledge | Security gaps or blocking |
| **OIDC integration patterns** | Split-path architecture is complex | Integration failures |
| **Database provisioning** | CNPG patterns vary by use case | Inconsistent setups |
| **Helm chart discovery** | Finding correct OCI repo + values | Configuration research |

### What Exists But Could Be Enhanced

| Area | Current State | Enhancement Opportunity |
| ------ | --------------- | ------------------------- |
| **Debugging** | Agents + docs | Auto-loading relevant context |
| **Upgrades** | tuppr (automated) + manual tasks | Pre-upgrade compatibility checking |

---

## Recommended Skills

### Priority 1: High-Impact (Genuine Gaps)

#### 1. `scaffold-flux-app`

**Purpose:** Generate new Flux application with correct project structure.

**Why Needed:** No existing automation for this. Every new app requires manually creating 4+ template files following specific patterns.

**Activation Triggers:**

- "add a new application", "create app", "deploy new app"
- "add helmrelease", "scaffold app"

**Workflow:**

1. Gather info: namespace, app name, OCI chart source, chart version
2. Create directory structure in `templates/config/kubernetes/apps/`:

   ```
   <namespace>/<app>/
   ├── ks.yaml.j2              # Flux Kustomization
   └── app/
       ├── kustomization.yaml.j2
       ├── helmrelease.yaml.j2
       └── ocirepository.yaml.j2
   ```

3. Add to namespace `kustomization.yaml.j2` resources list
4. Use project template delimiters (`#{ }#`, `#% %#`)
5. Run `task configure` to validate

**Resources to Include:**

- `references/app-structure.md` - Complete template patterns
- `assets/*.j2.template` - Boilerplate templates

**Estimated Value:** Saves 15-20 minutes per new application.

---

#### 2. `feature-advisor`

**Purpose:** Explain what happens when enabling features in cluster.yaml.

**Why Needed:** The plugin.py has 800+ lines of derived configuration logic. Understanding what `keycloak_enabled: true` triggers (and its prerequisites) requires reading complex Python code.

**Activation Triggers:**

- "what happens if I enable X"
- "how do I enable X", "what does X need"
- "prerequisites for", "dependencies for"

**Workflow:**

1. Identify the feature being queried
2. Load relevant plugin.py logic understanding
3. Explain:
   - Required fields in cluster.yaml
   - What derived variables are computed
   - What templates are conditionally rendered
   - What Kubernetes resources are created
4. Provide example configuration

**Feature Categories:**

- **Core:** cilium_bgp_enabled, spegel_enabled, unifi_dns_enabled
- **Storage:** rustfs_enabled, talos_backup_enabled
- **Database:** cnpg_enabled, cnpg_backup_enabled, cnpg_pgvector_enabled
- **Identity:** keycloak_enabled, oidc_sso_enabled, grafana_oidc_enabled
- **AI:** litellm_enabled, langfuse_enabled, obot_enabled, dragonfly_enabled
- **Security:** network_policies_enabled
- **Infrastructure:** infrastructure_enabled (Proxmox)

**Resources to Include:**

- `references/feature-matrix.md` - Feature dependencies and effects
- Direct reference to plugin.py computed variables

**Estimated Value:** Prevents configuration errors, reduces trial-and-error.

---

#### 3. `network-policy-helper`

**Purpose:** Generate CiliumNetworkPolicy for applications.

**Why Needed:** Network policies require understanding:

- Application ports and protocols
- Required egress (DNS, API server, external endpoints)
- Inter-namespace communication
- The audit vs enforce modes

**Activation Triggers:**

- "add network policy", "create networkpolicy"
- "secure traffic for", "restrict access to"
- "zero-trust for"

**Workflow:**

1. Identify application and namespace
2. Analyze HelmRelease for service ports
3. Determine required egress:
   - Always: kube-dns (53/UDP, 53/TCP)
   - Often: API server, Keycloak, external HTTPS
4. Check `network_policies_mode` (audit vs enforce)
5. Generate CiliumNetworkPolicy template
6. Add to app directory

**Resources to Include:**

- `references/policy-patterns.md` - Common policy patterns
- `references/common-ports.md` - Standard ports by service type
- Reference to `docs/NETWORK-INVENTORY.md`

**Estimated Value:** Correct policies without deep Cilium expertise.

---

### Priority 2: Enhanced Workflows

#### 4. `oidc-integration`

**Purpose:** Configure OIDC/SSO for applications using project patterns.

**Why Needed:** The project uses a **split-path OIDC architecture**:

- External authorization endpoint (browser → Keycloak via Cloudflare)
- Internal token endpoint (Envoy → Keycloak via K8s service)

This pattern is documented but complex to implement correctly.

**Activation Triggers:**

- "add oidc to", "enable sso for"
- "keycloak integration", "protect with authentication"

**Workflow:**

1. Determine integration pattern:
   - **Gateway OIDC** (SecurityPolicy) - Hubble UI pattern
   - **Native SSO** - Grafana, LiteLLM, Langfuse, Obot pattern
2. For Gateway OIDC:
   - Generate SecurityPolicy with split-path URLs
   - Generate ReferenceGrant for cross-namespace access
   - Add route label `security: oidc-protected`
3. For Native SSO:
   - Add Keycloak client to `keycloak-config`
   - Configure app-specific env vars
4. Add required cluster.yaml variables

**Resources to Include:**

- `references/oidc-patterns.md` - Both patterns with examples
- Reference to `docs/guides/completed/native-oidc-securitypolicy-implementation.md`

**Estimated Value:** Correct OIDC setup without debugging TLS/hairpin issues.

---

#### 5. `cnpg-database`

**Purpose:** Provision CloudNativePG databases for applications.

**Why Needed:** Database provisioning requires:

- Correct Cluster CR structure
- Backup configuration (barman + RustFS)
- Credential secret management
- PgBouncer pooler setup (optional)

**Activation Triggers:**

- "add database", "create postgres cluster"
- "cnpg for", "postgresql for"

**Workflow:**

1. Verify `cnpg_enabled: true` in cluster.yaml
2. Gather: database name, user, instances, storage size
3. Generate Cluster CR following project patterns
4. If backup needed: configure barmanObjectStore
5. Generate credentials secret template
6. Provide connection string format

**Resources to Include:**

- `references/cnpg-patterns.md` - Cluster configurations
- Keycloak, LiteLLM, Langfuse, Obot patterns as examples

**Estimated Value:** Consistent, backup-enabled database provisioning.

---

#### 6. `helm-chart-lookup`

**Purpose:** Find OCI repository and values for Helm charts.

**Why Needed:** Adding applications requires finding:

- Correct OCI registry URL
- Chart version/tag
- Available values and their meanings

**Activation Triggers:**

- "find helm chart for", "what's the oci repo for"
- "helm values for", "configure X chart"

**Workflow:**

1. Identify chart name and source
2. Search common registries (ghcr.io/bjw-s, ghcr.io/onedr0p, etc.)
3. Fetch values.yaml or schema
4. Explain key configuration options
5. Generate OCIRepository template

**Resources to Include:**

- `references/common-charts.md` - Frequently used charts
- Registry patterns for ghcr.io, docker.io

**Estimated Value:** Faster chart discovery and configuration.

---

### Priority 3: Operational Enhancement

#### 7. `debug-context`

**Purpose:** Auto-load relevant debugging context based on error domain.

**Why Needed:** Debugging requires knowing which agent, command, and ai-context to load. Auto-detection speeds resolution.

**Activation Triggers:**

- "debug", "troubleshoot", "not working"
- Error messages in conversation
- "why is X failing"

**Workflow:**

1. Detect domain from context:
   - Flux errors → flux-expert + flux-gitops.md
   - Network/DNS → network-debugger + cilium-networking.md
   - Node issues → talos-expert + talos-operations.md
   - Template errors → template-expert + template-system.md
   - Infrastructure → infra-expert + infrastructure-opentofu.md
2. Load relevant agent expertise
3. Suggest diagnostic commands from CLI_REFERENCE.md
4. Reference TROUBLESHOOTING.md decision trees

**Estimated Value:** Faster time-to-resolution with pre-loaded context.

---

#### 8. `node-config-helper`

**Purpose:** Help configure new nodes correctly in nodes.yaml.

**Why Needed:** Node configuration requires:

- Correct schematic_id from Image Factory
- Proper MAC address format
- Disk device path
- Optional VM overrides for Proxmox

**Activation Triggers:**

- "add node", "configure new node"
- "nodes.yaml help"

**Workflow:**

1. Guide through required fields: name, address, controller, disk, mac_addr, schematic_id
2. Explain optional fields: mtu, secureboot, encrypt_disk, vm_* overrides
3. Validate format (MAC lowercase + colons, schematic_id 64 chars)
4. Suggest `talosctl get disks/links` commands for discovery
5. Explain VM resource defaults for Proxmox

**Resources to Include:**

- `references/node-schema.md` - Complete field reference

**Estimated Value:** Correct node configuration on first attempt.

---

## Skills NOT Recommended (Already Automated)

| Original Proposal | Why NOT Needed |
| ------------------- | ---------------- |
| `encrypt-secret` | `task configure` auto-encrypts ALL `*.sops.*` files |
| `template-lint` | `task configure` validates CUE + kubeconform + talhelper |
| `pre-commit-validator` | `task configure` does comprehensive validation |
| `upgrade-planner` | tuppr handles automated upgrades; manual upgrades are task-driven |

---

## Implementation Architecture

### Directory Structure

```
.claude/skills/
├── scaffold-flux-app/
│   ├── SKILL.md
│   ├── references/
│   │   └── app-structure.md
│   └── assets/
│       ├── ks.yaml.j2.template
│       ├── kustomization.yaml.j2.template
│       ├── helmrelease.yaml.j2.template
│       └── ocirepository.yaml.j2.template
├── feature-advisor/
│   ├── SKILL.md
│   └── references/
│       └── feature-matrix.md
├── network-policy-helper/
│   ├── SKILL.md
│   └── references/
│       ├── policy-patterns.md
│       └── common-ports.md
├── oidc-integration/
│   ├── SKILL.md
│   └── references/
│       └── oidc-patterns.md
├── cnpg-database/
│   ├── SKILL.md
│   └── references/
│       └── cnpg-patterns.md
├── helm-chart-lookup/
│   ├── SKILL.md
│   └── references/
│       └── common-charts.md
├── debug-context/
│   ├── SKILL.md
│   └── references/
│       └── domain-mapping.md
└── node-config-helper/
    ├── SKILL.md
    └── references/
        └── node-schema.md
```

### SKILL.md Template

```yaml
---
name: scaffold-flux-app
description: >
  Scaffold new Flux CD applications with correct project template structure.
  This skill should be used when the user asks to "add an application",
  "create a new app", "scaffold app", or "add a helmrelease". Creates
  ks.yaml.j2, helmrelease.yaml.j2, ocirepository.yaml.j2, and kustomization.yaml.j2
  in templates/config/kubernetes/apps/.
---

# Scaffold Flux Application

Create new Flux application following project conventions.

## Prerequisites
- Confirm namespace exists or needs creation
- Identify Helm chart OCI source and version
- Determine if secrets are required

## Workflow

### 1. Gather Information
Ask for:
- Namespace name
- Application name
- OCI repository URL (e.g., `oci://ghcr.io/bjw-s/helm/app-template`)
- Chart version/tag

### 2. Create Directory Structure
Create `templates/config/kubernetes/apps/<namespace>/<app>/`:

[See references/app-structure.md for complete patterns]

### 3. Update Namespace Kustomization
Add to `templates/config/kubernetes/apps/<namespace>/kustomization.yaml.j2`:
```yaml
resources:
  - ./<app>/ks.yaml
```

### 4. Validate

Run `task configure` to render and validate.

## Template Delimiters

- Variable: `#{ variable }#`
- Block: `#% if condition %# ... #% endif %#`
- Comment: `#| comment #|`

```

---

## Implementation Priority

### Phase 1: Core Gaps

| Skill | Effort | Impact | Reason |
|-------|--------|--------|--------|
| `scaffold-flux-app` | Medium | High | Most frequent manual workflow |
| `feature-advisor` | Medium | High | Prevents configuration errors |
| `network-policy-helper` | Medium | Medium | Complex, error-prone |

### Phase 2: Integration Patterns

| Skill | Effort | Impact | Reason |
|-------|--------|--------|--------|
| `oidc-integration` | Medium | Medium | Complex split-path architecture |
| `cnpg-database` | Medium | Medium | Consistent provisioning |
| `helm-chart-lookup` | Low | Medium | Faster chart discovery |

### Phase 3: Operational

| Skill | Effort | Impact | Reason |
|-------|--------|--------|--------|
| `debug-context` | Low | Medium | Faster debugging |
| `node-config-helper` | Low | Medium | Correct node setup |

---

## Integration Matrix

| Skill | Related Agent | Related AI Context |
|-------|---------------|-------------------|
| `scaffold-flux-app` | flux-expert | flux-gitops.md |
| `feature-advisor` | template-expert | configuration-variables.md |
| `network-policy-helper` | network-debugger | cilium-networking.md |
| `oidc-integration` | network-debugger | cilium-networking.md |
| `cnpg-database` | - | (new doc: cnpg.md) |
| `helm-chart-lookup` | flux-expert | flux-gitops.md |
| `debug-context` | All agents | All ai-context docs |
| `node-config-helper` | talos-expert | talos-operations.md |

---

## Key Project Patterns to Encode

### Template Delimiters
```

Variable: #{ variable }#
Block:    #% if/for %# ... #% endif/endfor %#
Comment:  #| comment #|

```

### App Structure
```

templates/config/kubernetes/apps/<namespace>/<app>/
├── ks.yaml.j2
└── app/
    ├── kustomization.yaml.j2
    ├── helmrelease.yaml.j2
    ├── ocirepository.yaml.j2
    └── secret.sops.yaml.j2  # (if secrets)

```

### Feature Enablement Pattern
```yaml
# cluster.yaml
feature_enabled: true
feature_option_a: "value"
feature_option_b: "value"

# plugin.py computes derived values
# Templates conditionally render based on feature_enabled
```

### Generated vs Source

- **EDIT:** `templates/config/`
- **NEVER EDIT:** `kubernetes/`, `talos/`, `bootstrap/`, `infrastructure/`

---

## Next Steps

1. **Prototype `scaffold-flux-app`** - Highest impact, clear workflow
2. **Document feature matrix** for `feature-advisor`
3. **Extract network policy patterns** from existing apps
4. **Test skill activation** with realistic prompts
5. **Iterate based on usage**

---

## References

- [Agent Skills Specification](https://agentskills.io/specification)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- Project automation: `Taskfile.yaml`, `.taskfiles/`
- Template logic: `templates/scripts/plugin.py`
- AI context: `docs/ai-context/`
- Existing agents: `.claude/agents/`
- Existing commands: `.claude/commands/`
