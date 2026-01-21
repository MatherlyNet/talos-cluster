# Obot Environment Variables Analysis

> Analysis of obot-entraid .envrc.dev environment variables for potential cluster.yaml integration

**Date:** January 13, 2026
**Source:** `/Users/jason/dev/AI/obot-entraid/.envrc.dev` and `.envrc.dev.example`
**Target:** `matherlynet-talos-cluster` Obot deployment configuration

## Executive Summary

Analyzed 11 environment variables from the obot-entraid development environment. **4 variables should be added** to cluster.yaml for production deployment configuration, while the remaining 7 are development-only or already handled.

## Environment Variables Analysis

### 1. KUBECONFIG (Dev-Only)

```bash
export KUBECONFIG=$(pwd)/tools/devmode-kubeconfig
```

**Purpose:** Points to development kubeconfig for local testing

**Recommendation:** ❌ **Do NOT add to cluster.yaml**

**Rationale:**

- Development-only variable for local testing
- In Kubernetes deployment, Obot uses in-cluster service account authentication
- Already configured via Helm chart serviceAccount (line 300-302 in helmrelease.yaml.j2)

---

### 2. OBOT_DEV_MODE (Dev-Only)

```bash
export OBOT_DEV_MODE=true
```

**Purpose:** Enables development mode with relaxed security and debug features

**Source Code:** `pkg/services/config.go:84, 834-852`

```go
DevMode bool `usage:"Enable development mode" default:"false" name:"dev-mode" env:"OBOT_DEV_MODE"`

func configureDevMode(config Config) (int, Config) {
    if !config.DevMode {
        return 0, config
    }
    // Sets WORKSPACE_PROVIDER_IGNORE_WORKSPACE_NOT_FOUND=true
    // Sets NAH_DEV_MODE=true
    // Enables GatewayDebug
}
```

**Recommendation:** ❌ **Do NOT add to cluster.yaml**

**Rationale:**

- Development mode should never be enabled in production
- Automatically sets `WORKSPACE_PROVIDER_IGNORE_WORKSPACE_NOT_FOUND=true`
- Enables debug logging and relaxed security
- Production deployments must have `DevMode=false` (default)

---

### 3. WORKSPACE_PROVIDER_IGNORE_WORKSPACE_NOT_FOUND (Dev-Only)

```bash
export WORKSPACE_PROVIDER_IGNORE_WORKSPACE_NOT_FOUND=true
```

**Purpose:** Suppresses errors when workspace directories don't exist during development

**Source Code:** `pkg/services/config.go:850`

```go
// Automatically set in dev mode
_ = os.Setenv("WORKSPACE_PROVIDER_IGNORE_WORKSPACE_NOT_FOUND", "true")
```

**Recommendation:** ❌ **Do NOT add to cluster.yaml**

**Rationale:**

- Automatically enabled when `OBOT_DEV_MODE=true`
- Masks real errors in production (workspace initialization failures)
- Not a production-safe configuration
- No production use case identified

---

### 4. OBOT_SERVER_TOOL_REGISTRIES ⭐ (Production-Ready)

```bash
export OBOT_SERVER_TOOL_REGISTRIES=github.com/obot-platform/tools,./tools
```

**Purpose:** Specifies gptscript tool registries for custom tools and auth providers

**Current Deployment:**

```yaml
# templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2:176
OBOT_SERVER_TOOL_REGISTRIES: "/obot-tools/tools"
```

**Source Code:** `pkg/services/config.go:88, 357-359`

```go
ToolRegistries []string `usage:"The remote tool references to the set of gptscript tool registries to use" default:"github.com/obot-platform/tools"`

if len(config.ToolRegistries) < 1 {
    config.ToolRegistries = []string{"github.com/obot-platform/tools"}
}
```

**Recommendation:** ✅ **ADD to cluster.yaml as optional array variable**

**Proposed Configuration:**

```yaml
# cluster.yaml
obot_tool_registries:
  - "github.com/obot-platform/tools"
  - "/obot-tools/tools"

# Default (plugin.py):
obot_tool_registries = data.get("obot_tool_registries", ["/obot-tools/tools"])
```

**Use Cases:**

- Add custom tool repositories (GitHub, GitLab, etc.)
- Include organization-specific gptscript tools
- Enable beta/experimental tool registries for testing

**Implementation Notes:**

- Current deployment only uses `/obot-tools/tools` (baked into container)
- Default should remain `/obot-tools/tools` for jrmatherly/obot-entraid fork
- Comma-separated string in env var, list in cluster.yaml
- Template should join array: `OBOT_SERVER_TOOL_REGISTRIES: "#{ ','.join(obot_tool_registries) }#"`

---

### 5. OBOT_SERVER_DEFAULT_MCPCATALOG_PATH ⭐ (Production-Ready)

```bash
export OBOT_SERVER_DEFAULT_MCPCATALOG_PATH=https://github.com/obot-platform/mcp-catalog
```

**Purpose:** Provides default MCP server catalog accessible to all users

**Current Deployment:** ❌ **NOT CONFIGURED** (no env var set)

**Source Code:** `pkg/services/config.go:105, 806`

```go
DefaultMCPCatalogPath string `usage:"The path to the default MCP catalog (accessible to all users)" default:""`

DefaultMCPCatalogPath: config.DefaultMCPCatalogPath,
```

**Recommendation:** ✅ **ADD to cluster.yaml as optional string variable**

**Proposed Configuration:**

```yaml
# cluster.yaml
obot_default_mcp_catalog: "https://github.com/obot-platform/mcp-catalog"

# Default (plugin.py):
obot_default_mcp_catalog = data.get("obot_default_mcp_catalog", "")
```

**Use Cases:**

- Pre-populate MCP server catalog for all users
- Point to organization-specific MCP catalog repository
- Enable curated tool discovery experience

**Implementation Notes:**

- Empty string = no default catalog (current behavior)
- Can be GitHub repo, HTTP(S) URL, or local path
- Catalog is accessible to all authenticated users
- Reduces initial setup friction for new users

---

### 6. OBOT_SERVER_ENABLE_AUTHENTICATION ⭐ (Already Configured)

```bash
export OBOT_SERVER_ENABLE_AUTHENTICATION=true
```

**Purpose:** Enables authentication requirement for API access

**Current Deployment:** ✅ **ALREADY CONFIGURED**

```yaml
# templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2:112
OBOT_SERVER_ENABLE_AUTHENTICATION: true
```

**Source Code:** `pkg/services/config.go:98`

```go
EnableAuthentication bool `usage:"Enable authentication" default:"false"`
```

**Recommendation:** ✅ **Keep current implementation (hardcoded true)**

**Rationale:**

- Production security requirement
- No valid use case for disabling authentication in cluster deployment
- Hardcoded to `true` in helmrelease.yaml.j2 is correct
- Should never be exposed as configurable variable

---

### 7. OBOT_BOOTSTRAP_TOKEN ⭐ (Already Configured)

```bash
export OBOT_BOOTSTRAP_TOKEN=aZmdYlGbolpifiPEOKFGNAErS0LDEqZ7ZIUIDsNwg
```

**Purpose:** Initial API token for pre-OIDC authentication

**Current Deployment:** ✅ **ALREADY CONFIGURED**

```yaml
# cluster.yaml
obot_bootstrap_token: "..."  # SOPS-encrypted

# templates/config/kubernetes/apps/ai-system/obot/app/secret.sops.yaml.j2:29
OBOT_BOOTSTRAP_TOKEN: "#{ obot_bootstrap_token }#"
```

**Source Code:** `pkg/bootstrap/bootstrap.go` (bootstrap user authentication)

**Recommendation:** ✅ **Keep current implementation**

**Rationale:**

- Already properly implemented as SOPS-encrypted secret
- Required for initial admin access before OIDC configuration
- Correctly documented in docs/ai-context/obot.md:75-78
- No changes needed

---

### 8. OBOT_SERVER_AUTH_ADMIN_EMAILS ⭐ (Already Configured)

```bash
# export OBOT_SERVER_AUTH_ADMIN_EMAILS=admin1@company.com,admin2@company.com
```

**Purpose:** Comma-separated list of admin user email addresses

**Current Deployment:** ✅ **ALREADY CONFIGURED**

```yaml
# cluster.yaml
obot_admin_emails: "jason@matherly.net,..."  # Optional

# templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2:114-117
#% if obot_admin_emails | default('') %#
  OBOT_SERVER_AUTH_ADMIN_EMAILS: "#{ obot_admin_emails }#"
#% endif %#
```

**Source Code:** `pkg/services/config.go:100`

```go
AuthAdminEmails []string `usage:"Emails of admin users"`
```

**Recommendation:** ✅ **Keep current implementation**

**Rationale:**

- Already properly implemented as optional conditional variable
- Correctly documented in docs/ai-context/obot.md (not explicitly listed but implied)
- Supports comma-separated email list
- No changes needed

---

### 9. OBOT_SERVER_AUTH_OWNER_EMAILS ⭐ (Already Configured)

```bash
# export OBOT_SERVER_AUTH_OWNER_EMAILS=owner@company.com
```

**Purpose:** Comma-separated list of owner user email addresses (highest privilege)

**Current Deployment:** ✅ **ALREADY CONFIGURED**

```yaml
# cluster.yaml
obot_owner_emails: "jason@matherly.net"  # Optional

# templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2:118-121
#% if obot_owner_emails | default('') %#
  OBOT_SERVER_AUTH_OWNER_EMAILS: "#{ obot_owner_emails }#"
#% endif %#
```

**Source Code:** `pkg/services/config.go:101`

```go
AuthOwnerEmails []string `usage:"Emails of owner users"`
```

**Recommendation:** ✅ **Keep current implementation**

**Rationale:**

- Already properly implemented as optional conditional variable
- Correctly documented in docs/ai-context/obot.md (not explicitly listed but implied)
- Supports comma-separated email list
- No changes needed

---

## Summary Table

| Variable | Status | Action Required | Priority |
| -------- | ------ | --------------- | -------- |
| `KUBECONFIG` | Dev-Only | None | N/A |
| `OBOT_DEV_MODE` | Dev-Only | None | N/A |
| `WORKSPACE_PROVIDER_IGNORE_WORKSPACE_NOT_FOUND` | Dev-Only | None | N/A |
| `OBOT_SERVER_TOOL_REGISTRIES` | Missing | **ADD to cluster.yaml** | Medium |
| `OBOT_SERVER_DEFAULT_MCPCATALOG_PATH` | Missing | **ADD to cluster.yaml** | Medium |
| `OBOT_SERVER_ENABLE_AUTHENTICATION` | Configured | None | N/A |
| `OBOT_BOOTSTRAP_TOKEN` | Configured | None | N/A |
| `OBOT_SERVER_AUTH_ADMIN_EMAILS` | Configured | None | N/A |
| `OBOT_SERVER_AUTH_OWNER_EMAILS` | Configured | None | N/A |

## Implementation Plan

### 1. Add New cluster.yaml Variables

```yaml
###########################################
# Obot Tool Registry Configuration
###########################################
# obot_tool_registries:
#   - "github.com/obot-platform/tools"      # Official tools
#   - "/obot-tools/tools"                   # Entraid fork custom tools
#   - "github.com/yourorg/custom-tools"     # Organization-specific tools

###########################################
# Obot MCP Catalog Configuration
###########################################
# obot_default_mcp_catalog: "https://github.com/obot-platform/mcp-catalog"
# or use custom catalog:
# obot_default_mcp_catalog: "https://github.com/yourorg/mcp-catalog"
```

### 2. Update plugin.py (templates/scripts/plugin.py)

Add after existing obot variable processing:

```python
# Obot tool registries (default: fork's embedded tools)
obot_tool_registries = data.get("obot_tool_registries", ["/obot-tools/tools"])

# Obot default MCP catalog (default: none)
obot_default_mcp_catalog = data.get("obot_default_mcp_catalog", "")
```

### 3. Update helmrelease.yaml.j2

Add to environment configuration section (after line 177):

```yaml
#% if obot_default_mcp_catalog | default('') %#
      #| ======================================================================= #|
      #| Default MCP Catalog - Pre-populated catalog for all users             #|
      #| ======================================================================= #|
      OBOT_SERVER_DEFAULT_MCPCATALOG_PATH: "#{ obot_default_mcp_catalog }#"
#% endif %#
```

Update existing OBOT_SERVER_TOOL_REGISTRIES (line 176):

```yaml
      #| ======================================================================= #|
      #| Tool Registry Configuration                                             #|
      #| ======================================================================= #|
      OBOT_SERVER_TOOL_REGISTRIES: "#{ ','.join(obot_tool_registries | default(['/obot-tools/tools'])) }#"
```

### 4. Update Documentation

Update `docs/ai-context/obot.md` to include:

```markdown
### Tool Registry Configuration (Optional)
```yaml
obot_tool_registries:
  - "github.com/obot-platform/tools"
  - "/obot-tools/tools"
  - "github.com/yourorg/custom-tools"
```

Specify additional gptscript tool registries. Supports GitHub repos, HTTP URLs, or local paths.

**Default:** `["/obot-tools/tools"]` (jrmatherly/obot-entraid fork embedded tools)

### MCP Catalog Configuration (Optional)

```yaml
obot_default_mcp_catalog: "https://github.com/obot-platform/mcp-catalog"
```

Provides a default MCP server catalog accessible to all users for tool discovery.

**Default:** `""` (no default catalog)

```

## Benefits

### 1. Tool Registry Configuration
- **Flexibility:** Organizations can add custom tool repositories
- **Extensibility:** Easy to test beta/experimental tools
- **Maintainability:** Centralized tool registry management
- **Use Case:** Add organization-specific gptscript tools without forking

### 2. MCP Catalog Configuration
- **User Experience:** Pre-populated tool catalog reduces setup friction
- **Discoverability:** Users immediately see available MCP servers
- **Customization:** Organizations can curate approved tool catalogs
- **Use Case:** Enterprise deployments with approved-tools-only policies

## Security Considerations

### Tool Registries
- ⚠️ **Trust Verification:** Only add registries from trusted sources
- ⚠️ **Access Control:** Registries are accessible to all authenticated users
- ✅ **Sandboxing:** GPTScript tools run in isolated environments
- ✅ **Audit:** Tool execution is logged via Obot audit logs

### MCP Catalog
- ⚠️ **Content Review:** Catalog should be reviewed before deployment
- ⚠️ **Repository Access:** Ensure catalog repository is properly secured
- ✅ **Read-Only:** Catalog is read-only reference, not executed code
- ✅ **User Control:** Users can add/remove individual MCP servers

## Testing Plan

### 1. Tool Registry Testing
```bash
# Test default configuration
obot_tool_registries: ["/obot-tools/tools"]

# Test multi-registry configuration
obot_tool_registries:
  - "github.com/obot-platform/tools"
  - "/obot-tools/tools"

# Verify environment variable
kubectl -n ai-system exec -it deploy/obot -- env | grep OBOT_SERVER_TOOL_REGISTRIES
# Expected: OBOT_SERVER_TOOL_REGISTRIES=github.com/obot-platform/tools,/obot-tools/tools
```

### 2. MCP Catalog Testing

```bash
# Test with catalog enabled
obot_default_mcp_catalog: "https://github.com/obot-platform/mcp-catalog"

# Verify environment variable
kubectl -n ai-system exec -it deploy/obot -- env | grep OBOT_SERVER_DEFAULT_MCPCATALOG_PATH

# Test catalog accessibility via Obot UI
# Should see pre-populated MCP server entries
```

### 3. Validation Tests

- [ ] Verify template rendering with `task configure`
- [ ] Check env vars in deployed pod
- [ ] Verify tool registry functionality in Obot UI
- [ ] Verify MCP catalog appears in Obot UI (if configured)
- [ ] Test with empty/default values
- [ ] Test with multiple registries

## Backward Compatibility

### Impact: NONE

- Both variables are optional with safe defaults
- Existing deployments continue working unchanged
- No breaking changes to existing configurations

### Migration Path

1. Current users: No action required
2. New users: Can optionally configure in cluster.yaml
3. Advanced users: Can customize tool registries and catalogs

## References

### Source Code

- `pkg/services/config.go:88, 105` - Variable definitions
- `pkg/services/config.go:357-359, 806` - Default value logic
- `.envrc.dev` - Development environment reference

### Documentation

- `docs/ai-context/obot.md` - Obot deployment configuration
- `DOCKERFILE-OPTIMIZATION.md` - Tool registry container setup
- `UPSTREAM_SYNC_ANALYSIS.md` - Upstream merge strategy

### Templates

- `templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2`
- `templates/scripts/plugin.py`

---

**Conclusion:** Add 2 new optional configuration variables to cluster.yaml for production flexibility while maintaining secure defaults and backward compatibility.
