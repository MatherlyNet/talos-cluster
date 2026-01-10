# Langfuse-Keycloak SSO Remediation Plan

**Date:** January 2026
**Status:** ✅ **IMPLEMENTED** - Awaiting deployment verification
**Related:** `docs/research/langfuse-keycloak-sso-validation-jan-2026.md`

## Summary

This document provides the implementation steps to fix the Langfuse-Keycloak SSO configuration conflict identified during production testing.

## Issue

**Error:** `OAuthCreateAccount - Contact support if this error is unexpected`

**Root Cause:** `langfuse_disable_signup: true` in `cluster.yaml` blocks ALL new user creation, including SSO users authenticating for the first time.

## Required Changes

### 1. Update cluster.yaml

**File:** `cluster.yaml`
**Line:** ~1818

```yaml
# CHANGE FROM:
langfuse_disable_signup: true

# CHANGE TO:
langfuse_disable_signup: false
```

### 2. Regenerate Manifests

```bash
task configure
```

**Expected:** `kubernetes/apps/ai-system/langfuse/app/helmrelease.yaml` will be updated with `signUpDisabled: false`.

### 3. Deploy Changes

```bash
task reconcile
```

**Expected:** Langfuse pods will restart with the new configuration.

## Verification Steps

### Pre-Deployment

```bash
# Verify manifest was updated correctly
grep -A5 "signUpDisabled" kubernetes/apps/ai-system/langfuse/app/helmrelease.yaml
# Should show: signUpDisabled: false
```

### Post-Deployment

```bash
# Wait for pods to restart
kubectl -n ai-system rollout status deploy/langfuse-web

# Verify environment variable
kubectl -n ai-system exec deploy/langfuse-web -- printenv | grep DISABLE_SIGNUP
# Should NOT show AUTH_DISABLE_SIGNUP=true (or show =false)

# Test SSO login
# 1. Navigate to https://langfuse.matherly.net
# 2. Click "Login with Keycloak"
# 3. Authenticate via Google IdP
# 4. Should successfully log in (no OAuthCreateAccount error)
```

## Optional Enhancements

After fixing the core issue, consider enabling these optional features:

### Auto-Redirect to Keycloak (Seamless UX)

```yaml
# In cluster.yaml:
langfuse_sso_domain_enforcement: "matherly.net"
```

This skips the "Login with Keycloak" button and auto-redirects `@matherly.net` users to Keycloak.

### Project Auto-Provisioning

```yaml
# In cluster.yaml:
langfuse_default_project_id: "default-project"
langfuse_default_project_role: "VIEWER"
```

This auto-assigns new SSO users to a default project.

## Security Considerations

Setting `langfuse_disable_signup: false` is secure when combined with `langfuse_disable_password_auth: true` because:

1. **No email/password form** - `AUTH_DISABLE_USERNAME_PASSWORD=true` hides the signup form
2. **SSO-only authentication** - Users can ONLY log in via Keycloak
3. **Keycloak access control** - Keycloak realm settings determine who can authenticate
4. **IdP restrictions** - Google, GitHub, Microsoft IdPs are configured in Keycloak

## Rollback Plan

If issues occur after deployment:

```bash
# Revert cluster.yaml change
langfuse_disable_signup: true

# Regenerate and deploy
task configure
task reconcile
```

## Completion Checklist

- [x] Update `langfuse_disable_signup: false` in `cluster.yaml`
- [x] Run `task configure` to regenerate manifests
- [x] Verify `signUpDisabled: false` in generated helmrelease
- [ ] Run `task reconcile` to deploy
- [ ] Wait for pod rollout completion
- [ ] Test SSO login with a non-admin user
- [ ] (Optional) Enable `langfuse_sso_domain_enforcement` for auto-redirect
- [ ] Archive this document after successful verification
