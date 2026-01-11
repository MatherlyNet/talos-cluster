# Obot Keycloak Configuration Variable Analysis

## Executive Summary

This document analyzes the Keycloak authentication configuration variables used in the `jrmatherly/obot-entraid` fork, comparing the OLD project configuration (talos-k8s-cluster) with the CURRENT project (matherlynet-talos-cluster).

**Key Finding:** The CURRENT project's variable naming (`OBOT_KEYCLOAK_AUTH_PROVIDER_*`) actually **matches the fork's source code** more closely than the OLD project's naming (`OBOT_SERVER_AUTH_KEYCLOAK_*`).

---

## Fork Source Code Analysis

### Definitive Variable Reference

From `tools/keycloak-auth-provider/main.go` in the `jrmatherly/obot-entraid` fork:

```go
type Options struct {
    ClientID                  string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID"`
    ClientSecret              string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET"`
    KeycloakURL               string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_URL"`
    KeycloakRealm             string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_REALM"`
    ObotServerURL             string `env:"OBOT_SERVER_PUBLIC_URL,OBOT_SERVER_URL"`
    PostgresConnectionDSN     string `env:"OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN" optional:"true"`
    AuthCookieSecret          string `env:"OBOT_AUTH_PROVIDER_COOKIE_SECRET"`
    AuthEmailDomains          string `env:"OBOT_AUTH_PROVIDER_EMAIL_DOMAINS" default:"*"`
    AuthTokenRefreshDuration  string `env:"OBOT_AUTH_PROVIDER_TOKEN_REFRESH_DURATION" optional:"true" default:"1h"`
    AllowedGroups             string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS" optional:"true"`
    AllowedRoles              string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES" optional:"true"`
    GroupCacheTTL             string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_GROUP_CACHE_TTL" optional:"true" default:"1h"`
}
```

### Required Variables (from fork source)

| Variable | Required | Default | Description |
| ---------- | ---------- | --------- | ------------- |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | Yes | - | Keycloak client ID |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | Yes | - | Keycloak client secret |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` | Yes | - | Base Keycloak URL (without `/realms/xxx`) |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | Yes | - | Keycloak realm name |
| `OBOT_SERVER_PUBLIC_URL` or `OBOT_SERVER_URL` | Yes | - | Public Obot URL (fallback supported) |
| `OBOT_AUTH_PROVIDER_COOKIE_SECRET` | Yes | - | Cookie encryption secret |
| `OBOT_AUTH_PROVIDER_EMAIL_DOMAINS` | No | `*` | Allowed email domains |
| `OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN` | No | - | PostgreSQL DSN for session storage |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` | No | - | Restrict to specific Keycloak groups |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` | No | - | Restrict to specific Keycloak roles |

---

## Configuration Comparison

### OLD Project Variables (talos-k8s-cluster)

```yaml
# Lines 86-95 of helmrelease.yaml.j2
OBOT_SERVER_AUTH_PROVIDER: "keycloak"
OBOT_SERVER_AUTH_KEYCLOAK_ISSUER_URL: "https://auth.${SECRET_DOMAIN}/realms/k8s-cluster"
OBOT_SERVER_AUTH_KEYCLOAK_CLIENT_ID: "#{ obot_keycloak_client_id | default('obot') }#"
OBOT_SERVER_AUTH_KEYCLOAK_CLIENT_SECRET: "${OBOT_KEYCLOAK_CLIENT_SECRET}"
OBOT_SERVER_AUTH_REDIRECT_URL: "https://#{ obot_hostname | default('obot') }#.${SECRET_DOMAIN}/oauth2/callback"
OBOT_SERVER_AUTH_AUDIENCE: "#{ obot_keycloak_client_id | default('obot') }#"
OBOT_SERVER_AUTH_REQUIRED_CLAIMS: "email,preferred_username"
```

### CURRENT Project Variables (matherlynet-talos-cluster)

```yaml
# Lines 118-142 of helmrelease.yaml.j2
OBOT_SERVER_AUTH_PROVIDER: "keycloak"
OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "#{ obot_keycloak_base_url }#"
OBOT_KEYCLOAK_AUTH_PROVIDER_REALM: "#{ obot_keycloak_realm }#"
OBOT_AUTH_PROVIDER_EMAIL_DOMAINS: "#{ obot_allowed_email_domains | default('*') }#"
OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID: "#{ obot_keycloak_client_id | default('obot') }#"
OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN: "postgresql://..."

# In secret.sops.yaml.j2
OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET: "#{ obot_keycloak_client_secret }#"
OBOT_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
```

### Variable Naming Pattern Comparison

| Purpose | Fork Expects | OLD Project Uses | CURRENT Project Uses |
| --------- | -------------- | ------------------ | --------------------- |
| Client ID | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | `OBOT_SERVER_AUTH_KEYCLOAK_CLIENT_ID` | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` |
| Client Secret | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | `OBOT_SERVER_AUTH_KEYCLOAK_CLIENT_SECRET` | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` |
| Keycloak URL | `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` | `OBOT_SERVER_AUTH_KEYCLOAK_ISSUER_URL` | `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` |
| Realm | `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | (embedded in issuer URL) | `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` |
| Server URL | `OBOT_SERVER_PUBLIC_URL` | (not explicit) | (uses `OBOT_SERVER_HOSTNAME`) |
| Cookie Secret | `OBOT_AUTH_PROVIDER_COOKIE_SECRET` | (not present) | `OBOT_AUTH_PROVIDER_COOKIE_SECRET` |
| Redirect URL | (auto-generated) | `OBOT_SERVER_AUTH_REDIRECT_URL` | (not present) |

---

## Critical Findings

### Finding 1: CURRENT Project Naming is Correct

The CURRENT project's variable naming pattern (`OBOT_KEYCLOAK_AUTH_PROVIDER_*`) **matches the fork's source code**. The OLD project's pattern (`OBOT_SERVER_AUTH_KEYCLOAK_*`) does **NOT** match.

### Finding 2: OLD Project Variables Not in Fork

The following OLD project variables are **NOT referenced** in the fork's keycloak-auth-provider source:
- `OBOT_SERVER_AUTH_KEYCLOAK_ISSUER_URL`
- `OBOT_SERVER_AUTH_KEYCLOAK_CLIENT_ID`
- `OBOT_SERVER_AUTH_KEYCLOAK_CLIENT_SECRET`
- `OBOT_SERVER_AUTH_REDIRECT_URL`
- `OBOT_SERVER_AUTH_AUDIENCE`
- `OBOT_SERVER_AUTH_REQUIRED_CLAIMS`

### Finding 3: Missing Variable in CURRENT Project

The fork expects `OBOT_SERVER_PUBLIC_URL` or `OBOT_SERVER_URL` but CURRENT project uses `OBOT_SERVER_HOSTNAME`. This may cause issues as the keycloak-auth-provider tool looks for:
```go
ObotServerURL string `env:"OBOT_SERVER_PUBLIC_URL,OBOT_SERVER_URL"`
```

---

## Recommendations for Option A

### Action Items

1. **Add Missing Server URL Variable**

   The keycloak-auth-provider expects `OBOT_SERVER_PUBLIC_URL` or `OBOT_SERVER_URL`. Add one of these to the HelmRelease config section:

   ```yaml
   # In helmrelease.yaml.j2 config section
   OBOT_SERVER_URL: "https://#{ obot_hostname }#"
   ```

2. **Verify Keycloak URL Format**

   The fork expects a **base URL without realm path**:
   ```yaml
   # Correct (current project approach)
   OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "https://auth.matherlynet.dev"
   OBOT_KEYCLOAK_AUTH_PROVIDER_REALM: "matherlynet"

   # Incorrect (old project approach - combined)
   OBOT_SERVER_AUTH_KEYCLOAK_ISSUER_URL: "https://auth.${SECRET_DOMAIN}/realms/k8s-cluster"
   ```

3. **Ensure Cookie Secret is Set**

   The `OBOT_AUTH_PROVIDER_COOKIE_SECRET` is required. Verify it's properly set in `secret.sops.yaml.j2`:
   ```yaml
   OBOT_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
   ```

4. **Optional: Add PostgreSQL Session Storage**

   For large Keycloak tokens (with many groups/roles), PostgreSQL session storage prevents cookie overflow:
   ```yaml
   OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN: "postgresql://..."
   ```
   (Already configured in CURRENT project)

---

## cluster.yaml and plugin.py Analysis

### OLD Project Configuration (talos-k8s-cluster)

**cluster.yaml variables:**
```yaml
obot_keycloak_enabled: true
obot_keycloak_client_id: "obot"  # via default
obot_keycloak_client_secret: "..."
# NOTE: NO obot_keycloak_base_url
# NOTE: NO obot_keycloak_realm
# NOTE: NO obot_keycloak_cookie_secret
# NOTE: NO obot_allowed_email_domains
```

**plugin.py computed values:**
```python
# OLD project plugin.py (lines 378-387)
data.setdefault("obot_enabled", False)
data.setdefault("obot_hostname", "obot")
data.setdefault("obot_keycloak_enabled", False)
data.setdefault("obot_keycloak_client_id", "obot")
data.setdefault("obot_keycloak_client_secret", "")
# NOTE: NO obot_keycloak_base_url computation
# NOTE: NO obot_keycloak_realm computation
# NOTE: NO obot_keycloak_issuer_url computation
```

**Key Observation:** The OLD project's `plugin.py` does NOT compute Keycloak URLs or realm. Instead, the HelmRelease template constructs the issuer URL directly using `${SECRET_DOMAIN}` Flux substitution and hardcodes the realm name `k8s-cluster`.

### CURRENT Project Configuration (matherlynet-talos-cluster)

**cluster.yaml variables:**
```yaml
obot_keycloak_enabled: true
obot_keycloak_client_id: "obot"
obot_keycloak_client_secret: "..."
obot_keycloak_cookie_secret: "..."  # NEW - required by fork
# NOTE: obot_keycloak_base_url computed in plugin.py
# NOTE: obot_keycloak_realm computed in plugin.py
```

**plugin.py computed values:**
```python
# CURRENT project plugin.py (lines 616-635)
# Keycloak integration - derive URLs for custom auth provider
# Uses jrmatherly/obot-entraid fork with OBOT_KEYCLOAK_AUTH_PROVIDER_* vars
if data.get("obot_keycloak_enabled") and data.get("keycloak_enabled"):
    keycloak_realm = data.get("keycloak_realm", "matherlynet")
    keycloak_hostname = data.get("keycloak_hostname")
    # External base URL for OBOT_KEYCLOAK_AUTH_PROVIDER_URL
    data["obot_keycloak_base_url"] = f"https://{keycloak_hostname}"
    # Issuer URL for reference
    data["obot_keycloak_issuer_url"] = f"https://{keycloak_hostname}/realms/{keycloak_realm}"
    # Realm name for OBOT_KEYCLOAK_AUTH_PROVIDER_REALM
    data["obot_keycloak_realm"] = keycloak_realm
    data["obot_keycloak_enabled"] = True
```

**Key Observation:** The CURRENT project's `plugin.py` correctly computes:
- `obot_keycloak_base_url` - for `OBOT_KEYCLOAK_AUTH_PROVIDER_URL`
- `obot_keycloak_realm` - for `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM`
- `obot_keycloak_issuer_url` - for reference/documentation

### plugin.py Comparison Summary

| Computed Variable | OLD Project | CURRENT Project |
| ------------------- | ------------- | ----------------- |
| `obot_hostname` | Default `"obot"` | Computed as `{subdomain}.{domain}` |
| `obot_keycloak_base_url` | Not computed | Computed as `https://{keycloak_hostname}` |
| `obot_keycloak_realm` | Not computed | Derived from `keycloak_realm` |
| `obot_keycloak_issuer_url` | Not computed | Computed for reference |
| `obot_keycloak_cookie_secret` | Not defined | Required in cluster.yaml |

### Critical Architectural Difference

**OLD Project Approach:**
- Relies on Flux `${VAR}` substitution for secrets
- Constructs URLs directly in HelmRelease templates
- Hardcodes realm name in templates
- Uses `OBOT_SERVER_AUTH_KEYCLOAK_*` variable naming (NOT fork-compatible)

**CURRENT Project Approach:**
- Computes all derived values in `plugin.py`
- Uses pure Jinja2 templating in HelmRelease
- Realm name flows from `keycloak_realm` cluster variable
- Uses `OBOT_KEYCLOAK_AUTH_PROVIDER_*` variable naming (fork-compatible)

---

## Template Variable Differences

### Templating Approach Comparison

| Aspect | OLD Project | CURRENT Project |
| -------- | ------------- | ----------------- |
| Secret substitution | Flux `${VAR}` pattern | Jinja2 inline `#{ var }#` |
| Computed variables | None (manual) | `plugin.py` computed values |
| Domain handling | `${SECRET_DOMAIN}` | Pre-computed in cluster.yaml |
| Default values | Inline `\| default()` | Computed or explicit |

### Example: Hostname Construction

**OLD Project:**
```yaml
OBOT_SERVER_HOSTNAME: "https://#{ obot_hostname | default('obot') }#.${SECRET_DOMAIN}"
```
- Uses Jinja2 for app name with default
- Uses Flux substitution for domain
- Results in: `https://obot.example.com`

**CURRENT Project:**
```yaml
OBOT_SERVER_HOSTNAME: "https://#{ obot_hostname }#"
```
- `obot_hostname` is pre-computed in `plugin.py` to include full hostname
- Results in: `https://obot.matherlynet.dev`

---

## Recommended HelmRelease Configuration

Based on fork source code analysis, here is the recommended Keycloak configuration:

```yaml
#% if obot_keycloak_enabled | default(false) %#
      #| Keycloak Auth Provider Configuration |#
      #| REF: https://github.com/jrmatherly/obot-entraid/blob/main/tools/keycloak-auth-provider/main.go |#
      OBOT_SERVER_AUTH_PROVIDER: "keycloak"

      #| Keycloak Connection |#
      OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "#{ obot_keycloak_base_url }#"
      OBOT_KEYCLOAK_AUTH_PROVIDER_REALM: "#{ obot_keycloak_realm }#"
      OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID: "#{ obot_keycloak_client_id | default('obot') }#"

      #| Server URL - Required by keycloak-auth-provider tool |#
      OBOT_SERVER_URL: "https://#{ obot_hostname }#"

      #| Email Domain Restriction |#
      OBOT_AUTH_PROVIDER_EMAIL_DOMAINS: "#{ obot_allowed_email_domains | default('*') }#"

      #| PostgreSQL Session Storage (prevents cookie overflow with large tokens) |#
      OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN: "postgresql://#{ obot_postgres_user | default('obot') }#:#{ obot_db_password }#@obot-postgresql-rw.ai-system.svc.cluster.local:5432/#{ obot_postgres_db | default('obot') }#?sslmode=require"

#% if obot_keycloak_allowed_groups | default('') %#
      #| Optional: Restrict access to specific Keycloak groups |#
      OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS: "#{ obot_keycloak_allowed_groups }#"
#% endif %#
#% if obot_keycloak_allowed_roles | default('') %#
      #| Optional: Restrict access to specific Keycloak roles |#
      OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES: "#{ obot_keycloak_allowed_roles }#"
#% endif %#
#% endif %#
```

### Required Secrets (in secret.sops.yaml.j2)

```yaml
#% if obot_keycloak_enabled | default(false) %#
  #| Keycloak OIDC client secret |#
  OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET: "#{ obot_keycloak_client_secret }#"

  #| Cookie encryption secret (32 bytes base64) |#
  OBOT_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
#% endif %#
```

---

## Conclusion

### Summary of Findings

After comprehensive analysis of the fork's source code, cluster.yaml configurations, plugin.py computed values, and HelmRelease templates from both projects:

1. **The CURRENT project's configuration is MORE CORRECT than the OLD project**
   - Uses `OBOT_KEYCLOAK_AUTH_PROVIDER_*` naming (matches fork)
   - Computes derived values in `plugin.py` (cleaner architecture)
   - Includes required `obot_keycloak_cookie_secret`

2. **The OLD project's configuration would NOT work with current fork**
   - Uses `OBOT_SERVER_AUTH_KEYCLOAK_*` naming (NOT in fork source)
   - Hardcodes realm name `k8s-cluster` in templates
   - Missing required `OBOT_AUTH_PROVIDER_COOKIE_SECRET`

3. **Single Missing Variable in CURRENT Project**
   - Add `OBOT_SERVER_URL: "https://#{ obot_hostname }#"` to HelmRelease
   - This is the only change needed for fork compatibility

### Action Required

**Add one line to `helmrelease.yaml.j2`:**

```yaml
#| Server URL - Required by keycloak-auth-provider tool |#
OBOT_SERVER_URL: "https://#{ obot_hostname }#"
```

### Why the OLD Project's Pattern Would Not Work

The OLD project uses `OBOT_SERVER_AUTH_KEYCLOAK_*` variables which are NOT referenced anywhere in the fork's keycloak-auth-provider source code. The fork explicitly reads:

```go
// From tools/keycloak-auth-provider/main.go
ClientID     string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID"`
ClientSecret string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET"`
KeycloakURL  string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_URL"`
KeycloakRealm string `env:"OBOT_KEYCLOAK_AUTH_PROVIDER_REALM"`
```

If the OLD project was working, it was either:
- Using a different (older) version of the fork
- Using a different authentication mechanism
- Not actually tested with Keycloak authentication

---

## References

- Fork Repository: https://github.com/jrmatherly/obot-entraid
- Keycloak Auth Provider Source: `tools/keycloak-auth-provider/main.go`
- Keycloak Setup Guide: `tools/keycloak-auth-provider/KEYCLOAK_SETUP.md`
- Auth Provider Handlers: `pkg/api/handlers/providers/authproviders.go`

---

*Document created: January 2026*
*Analysis based on: jrmatherly/obot-entraid fork source code*
