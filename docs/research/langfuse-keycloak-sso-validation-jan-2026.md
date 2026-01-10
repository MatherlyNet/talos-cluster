# Langfuse-Keycloak SSO Integration Validation Report

**Date:** January 2026
**Status:** ✅ **FIX IMPLEMENTED** - Awaiting deployment verification via `task reconcile`
**Related:**
- `docs/research/archive/implemented/langfuse-seamless-sso-integration-jan-2026.md`
- `docs/research/archive/implemented/langfuse-llm-observability-integration-jan-2026.md`

> **Architecture Note:** Langfuse uses **native SSO** via NextAuth.js with Keycloak provider (`AUTH_KEYCLOAK_*` env vars).
> This is different from gateway-level OIDC (Envoy SecurityPolicy) used by Hubble UI.
> - **Native SSO** (Langfuse, Obot, LiteLLM, Grafana): Application handles its own OAuth flow
> - **Gateway OIDC** (Hubble UI): Envoy Gateway SecurityPolicy with split-path architecture
> - For split-path architecture details, see: [native-oidc-securitypolicy-implementation.md](../guides/completed/native-oidc-securitypolicy-implementation.md)

## Executive Summary

Initial validation indicated the Langfuse-Keycloak SSO integration was fully implemented. However, **production testing revealed a critical configuration conflict** that prevents SSO users from logging in.

**Error Observed:** `OAuthCreateAccount - Contact support if this error is unexpected`

**Root Cause:** `langfuse_disable_signup: true` blocks ALL new user creation, including SSO users authenticating for the first time.

## Critical Issue

### Observed Behavior

| Step | Expected | Actual |
| ------ | ---------- | -------- |
| Navigate to langfuse.matherly.net | Redirect to Keycloak | ✅ Shows "Login with Keycloak" button |
| Click "Login with Keycloak" | Redirect to Keycloak | ✅ Redirects to Keycloak |
| Authenticate via Google IdP | Return to Langfuse, logged in | ❌ `OAuthCreateAccount` error |

### Error Log

```
[next-auth][error][adapter_error_createUser]
https://next-auth.js.org/errors#adapter_error_createuser Sign up is disabled. {
  message: 'Sign up is disabled.',
  ...
}
```

### Root Cause Analysis

**Conflicting Configuration:**

| Setting | Value | Effect |
| --------- | ------- | -------- |
| `langfuse_disable_password_auth` | `true` | ✅ Hides email/password form (correct) |
| `langfuse_disable_signup` | `true` | ❌ **Blocks SSO user creation!** |

When a user authenticates via Keycloak for the first time:
1. Keycloak authenticates successfully
2. Langfuse receives OAuth callback with user info
3. NextAuth.js attempts to create user account
4. **BLOCKED** by `AUTH_DISABLE_SIGNUP=true`

**Why this wasn't caught:**
- The headless init creates `admin@matherly.net`
- This user CAN log in because they already exist
- NEW users (different email) cannot be created

## Remediation

### Immediate Fix

Change `langfuse_disable_signup` from `true` to `false` in `cluster.yaml`:

```yaml
# BEFORE (broken)
langfuse_disable_signup: true

# AFTER (working)
langfuse_disable_signup: false
```

Then regenerate and deploy:

```bash
task configure
task reconcile
```

### Understanding the Settings

| Configuration | `disable_password_auth` | `disable_signup` | Result |
| -------------- | ------------------------- | ------------------ | -------- |
| **SSO-Only (Correct)** | `true` | `false` | Users authenticate via SSO only; new SSO users are created |
| **Current (Broken)** | `true` | `true` | SSO button shows but new users blocked |
| **Open Registration** | `false` | `false` | Both SSO and email/password allowed |
| **Locked Down** | `true` | `true` | Only pre-existing users can login |

### Security Consideration

Setting `langfuse_disable_signup: false` with `langfuse_disable_password_auth: true` is secure because:
- The email/password signup form is **hidden** (AUTH_DISABLE_USERNAME_PASSWORD=true)
- Only SSO authentication is available
- Users can only be created through Keycloak authentication
- Keycloak controls who can authenticate (via IdP restrictions, realm access, etc.)

## Comparison with Working Services

### Why Grafana SSO Works

Grafana uses a different approach:
- `auto_login: true` - Auto-redirects to Keycloak
- No equivalent to `disable_signup` - new OAuth users are always created
- RBAC is handled via role mapping, not signup blocking

### Why Hubble SSO Works

Hubble uses Gateway OIDC (Envoy SecurityPolicy with **split-path architecture**):
- User is authenticated at the gateway level
- No application-level user creation needed
- Keycloak session is the only requirement
- Uses external authorizationEndpoint (browser) + internal tokenEndpoint (server-to-server)
- REF: [native-oidc-securitypolicy-implementation.md](../guides/completed/native-oidc-securitypolicy-implementation.md)

## Updated Validation Checklist

### Template Configuration (VERIFIED ✅)

| Requirement | Status | Evidence |
| ------------- | -------- | ---------- |
| `AUTH_KEYCLOAK_*` env vars | ✅ Correct | `helmrelease.yaml.j2:209-227` |
| Keycloak client with PKCE | ✅ Correct | `realm-config.yaml.j2:319-345` |
| No Gateway OIDC label | ✅ Correct | `httproutes.yaml.j2:160-171` |
| Cookie domain isolation | ✅ Correct | `NEXTAUTH_COOKIE_DOMAIN` set |

### Runtime Configuration (ISSUE FOUND ⚠️)

| Requirement | Status | Issue |
| ------------- | -------- | ------- |
| SSO enabled | ✅ Working | Button appears |
| User creation | ❌ **BLOCKED** | `langfuse_disable_signup: true` |
| Account linking | N/A | Can't test until user exists |

## Action Items

1. **REQUIRED:** Change `langfuse_disable_signup: false` in `cluster.yaml`
2. **REQUIRED:** Run `task configure` to regenerate manifests
3. **REQUIRED:** Run `task reconcile` to deploy changes
4. **OPTIONAL:** Enable `langfuse_sso_domain_enforcement: "matherly.net"` for auto-redirect

## Enhancement Opportunities

### Already Configured ✅

The following SSO enhancements are already properly configured in `cluster.yaml`:

| Feature | Setting | Value | Effect |
| ------- | ------- | ----- | ------ |
| Auto-provisioning | `langfuse_default_org_id` | `matherly-net` | New SSO users auto-join org |
| Default role | `langfuse_default_org_role` | `VIEWER` | New users get VIEWER access |
| Account linking | `AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING` | `true` | Email-match links accounts |

### Optional Enhancements

| Enhancement | Setting | Current | Recommendation |
| ----------- | ------- | ------- | -------------- |
| Auto-redirect to Keycloak | `langfuse_sso_domain_enforcement` | Disabled | Enable for seamless UX |
| Project auto-provisioning | `langfuse_default_project_id` | Disabled | Consider for default project access |
| Project default role | `langfuse_default_project_role` | Disabled | Consider if enabling project provisioning |

**Auto-Redirect Configuration:**

To enable automatic redirect to Keycloak (skip the "Login with Keycloak" button):

```yaml
langfuse_sso_domain_enforcement: "matherly.net"
```

This enforces SSO for all `@matherly.net` email addresses and auto-redirects them to Keycloak.

## Post-Fix Verification

After applying the fix, verify SSO works:

```bash
# Check pod logs for successful auth
kubectl -n ai-system logs -l app.kubernetes.io/name=langfuse --tail=50 | grep -i auth

# Verify environment variable
kubectl -n ai-system exec -it deploy/langfuse-web -- env | grep DISABLE_SIGNUP
# Should show: AUTH_DISABLE_SIGNUP=false (or not present)
```

## Document Status

- **Original research doc:** Archived in `docs/research/archive/implemented/` (template configuration is correct)
- **This validation doc:** Updated to reflect production issue
- **Status:** Awaiting remediation deployment

## Conclusion

The Langfuse-Keycloak SSO integration templates are correctly configured, but the **runtime configuration** in `cluster.yaml` has a conflict. The `langfuse_disable_signup: true` setting is incompatible with first-time SSO authentication because it blocks user creation.

**Fix:** Set `langfuse_disable_signup: false` to allow SSO users to be created while still preventing email/password signup (which is separately disabled by `langfuse_disable_password_auth: true`).
