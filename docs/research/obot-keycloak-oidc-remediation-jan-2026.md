# Obot Keycloak OIDC Integration - Remediation Findings

**Date:** January 9, 2026
**Status:** ✅ IMPLEMENTED
**Priority:** CRITICAL (Resolved)
**Source Document:** [obot-keycloak-oidc-integration-jan-2026.md](./obot-keycloak-oidc-integration-jan-2026.md)
**Related Components:** Obot (ai-system), Keycloak (identity), jrmatherly/obot-entraid fork

> **Architecture Note:** Obot uses **native OAuth** via its built-in Keycloak auth provider, NOT Envoy Gateway SecurityPolicy.
> This is fundamentally different from Hubble/Grafana which use gateway-level OIDC (split-path architecture).
> - **Native OAuth apps** (Obot, LiteLLM, Langfuse, Grafana native): Handle their own OAuth flow directly with Keycloak
> - **Gateway-level OIDC apps** (Hubble, Grafana if using SecurityPolicy): Use Envoy Gateway SecurityPolicy with split-path architecture
> - For split-path OIDC details, see: [native-oidc-securitypolicy-implementation.md](../guides/completed/native-oidc-securitypolicy-implementation.md)

## Executive Summary

A systematic validation of the Obot-Keycloak OIDC integration research document against the actual project codebase has revealed **two critical environment variable naming mismatches** that will prevent Keycloak authentication from functioning. Additionally, one recommended improvement was identified.

### Critical Issues Found

| Issue | Severity | Status | Impact |
| ------- | ---------- | -------- | -------- |
| URL environment variable name mismatch | **CRITICAL** | ✅ Fixed | Authentication will fail |
| Cookie secret environment variable name mismatch | **CRITICAL** | ✅ Fixed | Authentication will fail |
| EMAIL_DOMAINS not explicitly configured | Recommended | ✅ Fixed | Security clarity |

### Validated Components (No Issues)

| Component | Status | Notes |
| ----------- | -------- | ------- |
| Keycloak Client Configuration | **VALIDATED** | Protocol mappers correctly configured for roles/groups claims |
| plugin.py derived variables | **VALIDATED** | `obot_keycloak_base_url` and `obot_keycloak_realm` correctly derived |
| Network policies | **VALIDATED** | Keycloak egress rules correctly include both internal and external FQDN |
| Client scopes (optional scope position) | **VALIDATED** | `offline_access` in optional scopes works with oauth2-proxy explicit request |
| Redirect URIs | **VALIDATED** | Both wildcard and explicit `/oauth2/callback` configured |
| PKCE S256 | **VALIDATED** | Correctly configured on Keycloak client |

---

## Critical Issue #1: URL Environment Variable Name Mismatch

### Discovery

Cross-referencing the upstream [jrmatherly/obot-entraid](https://github.com/jrmatherly/obot-entraid) fork's source code against our project configuration revealed a critical naming mismatch.

### Evidence

**Upstream fork expects (from tool.gpt and main.go):**
```
OBOT_KEYCLOAK_AUTH_PROVIDER_URL
```

**Our project uses (helmrelease.yaml.j2 line 125):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL: "#{ obot_keycloak_base_url }#"
```

### Impact

The Keycloak auth provider will fail to initialize because it will not find the expected `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` environment variable. Authentication will be completely non-functional.

### Remediation

**File:** `templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2`

**Current (line 125):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL: "#{ obot_keycloak_base_url }#"
```

**Change to:**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "#{ obot_keycloak_base_url }#"
```

---

## Critical Issue #2: Cookie Secret Environment Variable Name Mismatch

### Discovery

Further analysis of the fork's source code revealed another naming mismatch for the cookie secret variable.

### Evidence

**Upstream fork expects (from main.go):**
```go
AuthCookieSecret string `env:"OBOT_AUTH_PROVIDER_COOKIE_SECRET"`
```

**Our project uses (secret.sops.yaml.j2 line 38):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
```

### Impact

The cookie encryption will fail because the expected `OBOT_AUTH_PROVIDER_COOKIE_SECRET` environment variable will not be found. Session cookies cannot be encrypted, causing authentication failures.

### Remediation

**File:** `templates/config/kubernetes/apps/ai-system/obot/app/secret.sops.yaml.j2`

**Current (line 38):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
```

**Change to:**
```yaml
OBOT_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
```

---

## Recommended Issue: EMAIL_DOMAINS Not Configured

### Discovery

The fork's oauth2-proxy integration supports email domain filtering, but our configuration does not explicitly set this variable.

### Evidence

**Upstream fork supports (from main.go):**
```go
AuthEmailDomains string `env:"OBOT_AUTH_PROVIDER_EMAIL_DOMAINS" default:"*"`
```

**Our project:** Variable not configured (defaults to `*` which allows all domains)

### Impact

Low - the default `*` allows all email domains which is likely the intended behavior. However, explicit configuration improves security documentation and enables future domain restrictions without code changes.

### Recommended Remediation

**File:** `templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2`

**Add after OBOT_SERVER_AUTH_PROVIDER (line 124):**
```yaml
#| Allow all email domains (explicitly configured for clarity) #|
OBOT_AUTH_PROVIDER_EMAIL_DOMAINS: "*"
```

Or for configurable deployments:
```yaml
OBOT_AUTH_PROVIDER_EMAIL_DOMAINS: "#{ obot_allowed_email_domains | default('*') }#"
```

---

## Original Research Document Validation

### Correctly Identified Issues (Still Unfixed)

The original research document correctly identified:

1. **Issue #1 (URL variable)** - Documented as "CRITICAL" but **not yet fixed** in codebase
2. **Issue #4 (EMAIL_DOMAINS)** - Documented as "RECOMMENDED" but **not yet added** to codebase

### Incorrectly Documented Issues

The original research document identified the cookie secret variable issue incorrectly:

- **Document states:** Cookie secret is correctly configured
- **Reality:** The variable name `OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET` does not match the expected `OBOT_AUTH_PROVIDER_COOKIE_SECRET`

### Validated Recommendations (Already Implemented)

1. **Protocol Mappers:** Correctly configured on obot client in realm-config.yaml.j2 (lines 384-407)
2. **Network Policies:** Correctly include both internal Keycloak endpoint and external FQDN (lines 111-134)
3. **PKCE S256:** Correctly enabled in Keycloak client attributes (line 373)
4. **Redirect URIs:** Correctly include both wildcard and explicit callback URL (lines 368-369)

### Low Priority Recommendations (Optional) - ✅ IMPLEMENTED

The following items from the original research were low priority but have now been implemented for OIDC compliance and configuration clarity:

1. **'groups' Client Scope Definition:** ✅ **IMPLEMENTED** - Added realm-level `groups` clientScope in realm-config.yaml.j2. The scope is now included in defaultClientScopes for Grafana, LiteLLM, and Obot clients, providing OIDC-compliant group membership claims.

2. **Move offline_access to defaultClientScopes:** ✅ **IMPLEMENTED** - Moved `offline_access` from optionalClientScopes to defaultClientScopes for all OIDC clients. This enables refresh tokens by default for better session persistence.

---

## Implementation Checklist

### Critical (Must Fix Before Deployment)

- [x] **Fix OBOT_KEYCLOAK_AUTH_PROVIDER_URL** in helmrelease.yaml.j2 ✅ Implemented Jan 2026
- [x] **Fix OBOT_AUTH_PROVIDER_COOKIE_SECRET** in secret.sops.yaml.j2 ✅ Implemented Jan 2026

### Recommended (Should Fix)

- [x] **Add OBOT_AUTH_PROVIDER_EMAIL_DOMAINS** to helmrelease.yaml.j2 ✅ Implemented Jan 2026

### Optional (Nice to Have)

- [x] Define 'groups' clientScope in realm-config.yaml.j2 for OIDC compliance ✅ Implemented Jan 2026
- [x] Move offline_access to defaultClientScopes for configuration clarity ✅ Implemented Jan 2026

---

## Post-Remediation Testing

After applying the critical fixes, verify authentication with:

```bash
# Check environment variables are set correctly
kubectl exec -n ai-system deploy/obot -- env | grep OBOT_KEYCLOAK
kubectl exec -n ai-system deploy/obot -- env | grep OBOT_AUTH_PROVIDER

# Expected output should include:
# OBOT_KEYCLOAK_AUTH_PROVIDER_URL=https://auth.example.com
# OBOT_KEYCLOAK_AUTH_PROVIDER_REALM=matherlynet
# OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID=obot
# OBOT_AUTH_PROVIDER_COOKIE_SECRET=<base64-encoded-secret>
# OBOT_AUTH_PROVIDER_EMAIL_DOMAINS=*

# Test Keycloak connectivity
kubectl exec -n ai-system deploy/obot -- curl -s https://auth.example.com/realms/matherlynet/.well-known/openid-configuration | jq .issuer

# Check Obot logs for auth errors
kubectl logs -n ai-system -l app.kubernetes.io/name=obot | grep -i "keycloak\|auth\|oidc"
```

---

## Document Status Update

The original research document `obot-keycloak-oidc-integration-jan-2026.md` should be updated to:

1. Add status header indicating "Remediation Required - See obot-keycloak-oidc-remediation-jan-2026.md"
2. Correct the cookie secret variable name documentation
3. Mark as "Pending Implementation" until fixes are applied

Once fixes are applied and tested, both documents should be moved to `docs/research/archive/implemented/`.

---

## References

- [jrmatherly/obot-entraid Repository](https://github.com/jrmatherly/obot-entraid)
- [Keycloak Auth Provider tool.gpt](https://raw.githubusercontent.com/jrmatherly/obot-entraid/main/tools/keycloak-auth-provider/tool.gpt)
- [Keycloak Auth Provider main.go](https://raw.githubusercontent.com/jrmatherly/obot-entraid/main/tools/keycloak-auth-provider/main.go)
- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)

---

## Appendix: Complete Environment Variables Matrix

| Variable | Expected Name | Current Name | Status |
| ---------- | --------------- | -------------- | -------- |
| Keycloak URL | `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` | `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` | ✅ Correct |
| Realm | `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | ✅ Correct |
| Client ID | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | ✅ Correct |
| Client Secret | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | ✅ Correct |
| Cookie Secret | `OBOT_AUTH_PROVIDER_COOKIE_SECRET` | `OBOT_AUTH_PROVIDER_COOKIE_SECRET` | ✅ Correct |
| Email Domains | `OBOT_AUTH_PROVIDER_EMAIL_DOMAINS` | `OBOT_AUTH_PROVIDER_EMAIL_DOMAINS` | ✅ Correct |
| Allowed Groups | `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` | `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` | ✅ Correct |
| Allowed Roles | `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` | `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` | ✅ Correct |
