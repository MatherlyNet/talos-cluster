# Langfuse Seamless SSO Integration with Envoy Gateway + Keycloak

**Date:** January 2026
**Status:** ✅ **IMPLEMENTED** (Bug Fixed)
**Related:**
- `docs/research/archive/implemented/grafana-sso-authentication-integration-jan-2026.md`
- `docs/research/archive/completed/oidc-keycloak-implementation-review-jan-2026.md`
- `docs/research/langfuse-llm-observability-integration-jan-2026.md`

## Executive Summary

This document analyzes how to achieve the most seamless SSO experience for Langfuse users by leveraging the existing Envoy Gateway + Keycloak OIDC infrastructure. **A critical bug was identified: the current template uses an incorrect Helm chart values structure that prevents SSO from working.**

## Critical Bug: SSO Configuration Not Working

### Problem Statement

The current Langfuse deployment shows **only email/password login** - there is no "Login with Keycloak" button visible. This is because the template uses an incorrect values structure that the Langfuse Helm chart doesn't recognize.

### Root Cause Analysis

**Current Template (`helmrelease.yaml.j2:192-209`):**
```yaml
auth:
  disableUsernamePassword: false
  additionalProviders:
    - id: keycloak
      name: "Keycloak"
      clientId: "langfuse"
      clientSecret:
        secretKeyRef:
          name: langfuse-keycloak-credentials
          key: client-secret
      issuer: "{{ keycloak_issuer_url }}"
      allowDangerousEmailAccountLinking: true
```

**Problem:** The Langfuse Helm chart does NOT support `auth.additionalProviders`. This is not a valid values schema.

**Correct Configuration (Environment Variables):**
The Langfuse Helm chart expects SSO providers to be configured via environment variables:
- `AUTH_KEYCLOAK_CLIENT_ID`
- `AUTH_KEYCLOAK_CLIENT_SECRET`
- `AUTH_KEYCLOAK_ISSUER`
- `AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING` (optional)

These should be added to `langfuse.additionalEnv`, NOT as nested `auth.additionalProviders`.

**Important Prerequisite:**
The Langfuse documentation states:
> "Make sure that NEXTAUTH_URL environment variable is configured correctly if you want to use any authentication method other than email/password."

The current Helm chart values set `langfuse.nextauth.url: "https://langfuse.matherly.net"` which should translate to `NEXTAUTH_URL`. However, if SSO still doesn't work after fixing the environment variables, verify that `NEXTAUTH_URL` is correctly set in the pod's environment by checking:
```bash
kubectl -n ai-system exec -it deploy/langfuse-web -- env | grep NEXTAUTH
```

### What's Actually Deployed

Looking at the generated `kubernetes/apps/ai-system/langfuse/app/helmrelease.yaml`:
- Lines 106-117 contain the `auth.additionalProviders` block
- This block is **silently ignored** by the Langfuse Helm chart
- Result: Only email/password login is available

## Current Implementation Analysis

### What IS Correctly Configured

1. **Keycloak Client Configuration** (`realm-config.yaml.j2:311-346`)
   - Client: `langfuse` with PKCE enabled (`S256`)
   - Redirect URI: `https://langfuse.${cloudflare_domain}/api/auth/callback/keycloak`
   - Standard OIDC scopes: `openid`, `profile`, `email`
   - ✅ This is correct and ready to use

2. **Keycloak Credentials Secret** (`secrets.sops.yaml`)
   - `LANGFUSE_CLIENT_ID` and `LANGFUSE_CLIENT_SECRET` exist
   - ✅ Credentials are in place

3. **HTTPRoute** (`network/envoy-gateway/app/httproutes.yaml.j2`)
   - ✅ Centralized in network namespace, no `security: oidc-protected` label
   - ✅ Langfuse handles its own authentication via native SSO

4. **Auto-Provisioning Support** (`helmrelease.yaml.j2:174-189`)
   - `LANGFUSE_DEFAULT_ORG_ID/ROLE` for automatic org membership
   - ✅ Correctly configured via environment variables

### What IS NOT Working

1. **Langfuse Native SSO via Keycloak** (`helmrelease.yaml.j2:192-209`)
   - ❌ Uses incorrect `auth.additionalProviders` structure
   - ❌ Langfuse Helm chart ignores this configuration
   - ❌ No "Login with Keycloak" button appears

### Current User Experience

Users visiting the Langfuse URL see:
1. A login form with **only email/password fields**
2. **No SSO provider buttons** (no "Login with Keycloak")
3. If Gateway OIDC is enabled, users are first redirected to Keycloak, then see the email/password form anyway

## SSO Integration Options

### Option 1: Gateway OIDC Only (Not Recommended for Langfuse)

**How it works:**
- Remove Langfuse's native SSO (`langfuse_sso_enabled: false`)
- Keep Gateway OIDC protection (`security: oidc-protected` label)
- Langfuse receives `forwardAccessToken: true` JWT in request headers

**Why it doesn't work for Langfuse:**
- Langfuse's backend is a Next.js application using NextAuth.js
- It doesn't support extracting user identity from JWT headers natively
- Langfuse requires its own session management for API keys, project membership, etc.
- The `/api/auth/*` endpoints expect NextAuth.js session flow

**Verdict:** ❌ Not viable without significant application modifications

### Option 2: Native SSO Only (Current Behavior Without Gateway OIDC)

**How it works:**
- Remove Gateway OIDC label (`security: oidc-protected`)
- Keep only Langfuse's native Keycloak provider
- Users see Langfuse login page first

**Pros:**
- Simple configuration
- Full Langfuse RBAC via org/project roles
- Account linking works seamlessly

**Cons:**
- Users must click "Login with Keycloak" button manually
- No automatic SSO from other protected services
- Extra click compared to Grafana's `auto_login: true`

**Verdict:** ⚠️ Functional but not optimal UX

### Option 3: Native SSO with Auto-Login (Recommended)

**How it works:**
- Configure Langfuse to automatically redirect to Keycloak on unauthenticated access
- Similar to Grafana's `auto_login: true` pattern
- Remove Gateway OIDC to avoid double authentication

**Research Finding - Langfuse Environment Variables:**

From the Langfuse documentation and `local_docs/langfuse_example_env_prod.md`:

```
# Auth configuration
AUTH_DISABLE_SIGNUP=true                    # Disable self-registration
AUTH_DISABLE_USERNAME_PASSWORD=true         # Force SSO-only
AUTH_DOMAINS_WITH_SSO_ENFORCEMENT=domain.com  # Auto-redirect for domain
AUTH_SESSION_MAX_AGE=43200                  # 30 days in minutes
```

**Key Variables for Seamless SSO:**

| Variable | Purpose | Current Support |
| ---------- | --------- | ----------------- |
| `AUTH_DISABLE_USERNAME_PASSWORD` | Hide email/password form, force SSO | ✅ Implemented |
| `AUTH_DOMAINS_WITH_SSO_ENFORCEMENT` | Auto-redirect to SSO for specific domains | ✅ Implemented |
| `AUTH_DISABLE_SIGNUP` | Prevent self-registration | ✅ Implemented |

**User Experience with Option 3:**
1. User visits `langfuse.example.com`
2. Langfuse sees no session, automatically redirects to Keycloak (no login form shown)
3. If user has Keycloak session (from Grafana, RustFS, etc.), immediate return
4. If no session, Keycloak login page appears
5. After authentication, user is logged into Langfuse

**This matches Grafana's ~200-500ms redirect experience.**

**Verdict:** ✅ **Recommended approach**

### Option 4: Dual-Layer with Session Sharing (Complex)

**How it works:**
- Keep both Gateway OIDC and Langfuse native SSO
- Configure `cookieDomain: ".${cloudflare_domain}"` for cross-subdomain session
- Langfuse recognizes Gateway's OIDC session

**Why it's problematic:**
- Langfuse/NextAuth.js doesn't recognize external OIDC sessions
- Double redirect still occurs
- Increased complexity with no UX benefit

**Verdict:** ❌ Not recommended

## Recommended Configuration

### Bug Fix Required

#### 1. Fix the Langfuse SSO Configuration (CRITICAL)

The `auth.additionalProviders` structure must be replaced with environment variables in `additionalEnv`.

**Current broken code (`helmrelease.yaml.j2:192-209`):**
```jinja
#% if langfuse_sso_enabled | default(false) %#
      auth:
        disableUsernamePassword: false
        additionalProviders:
          - id: keycloak
            ...
#% endif %#
```

**Correct fix - Replace with environment variables:**
```jinja
#% if langfuse_sso_enabled | default(false) %#
        #| ===================================================================== #|
        #| Keycloak SSO Configuration                                            #|
        #| REF: https://langfuse.com/self-hosting/authentication-and-sso         #|
        #| ===================================================================== #|
        - name: AUTH_KEYCLOAK_CLIENT_ID
          value: "langfuse"
        - name: AUTH_KEYCLOAK_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: langfuse-keycloak-credentials
              key: client-secret
        - name: AUTH_KEYCLOAK_ISSUER
          value: "#{ keycloak_issuer_url }#"
        - name: AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING
          value: "true"
        #| ===================================================================== #|
        #| PKCE Configuration (adds security layer to confidential client)      #|
        #| Keycloak client has: pkce.code.challenge.method: S256                 #|
        #| NOTE: Confidential client = uses client_secret + PKCE (both)         #|
        #| ===================================================================== #|
        - name: AUTH_KEYCLOAK_CHECKS
          value: "pkce,state"
        #| AUTH_KEYCLOAK_CLIENT_AUTH_METHOD omitted = uses default client_secret_basic #|
        #| This is correct for confidential clients (publicClient: false)              #|
#% endif %#
```

This adds the SSO environment variables to the existing `additionalEnv` section instead of using the non-existent `auth.additionalProviders` values structure.

**PKCE Configuration with Confidential Client:**
The Keycloak client in `realm-config.yaml.j2` is configured as a **confidential client with PKCE**:
```yaml
publicClient: false                           # Confidential client (uses client_secret)
clientAuthenticatorType: "client-secret"      # Token endpoint uses client_secret_basic
attributes:
  pkce.code.challenge.method: "S256"          # PKCE as additional security layer
```

**Understanding Confidential vs Public Client PKCE:**

| Client Type | `publicClient` | Client Secret Used | PKCE Purpose | `CLIENT_AUTH_METHOD` |
| ------------- | ---------------- | ------------------- | -------------- | --------------------- |
| **Public** | `true` | No | Primary auth | `none` |
| **Confidential** | `false` | Yes | Additional security | `client_secret_basic` (default) |

Our Keycloak client is **confidential** (`publicClient: false`), meaning:
- The client secret IS used for token endpoint authentication
- PKCE provides an **additional** security layer, not a replacement
- `AUTH_KEYCLOAK_CLIENT_AUTH_METHOD` should be **omitted** (uses default `client_secret_basic`)
- `AUTH_KEYCLOAK_CHECKS=pkce,state` enables PKCE verification alongside client secret auth

**Common Mistake:** Setting `AUTH_KEYCLOAK_CLIENT_AUTH_METHOD=none` with a confidential client will cause authentication to fail because Keycloak expects the client secret.

#### 2. HTTPRoute Centralization (Implemented)

✅ Langfuse HTTPRoute is now centralized in `network/envoy-gateway/app/httproutes.yaml.j2` with:
- No `security: oidc-protected` label (Langfuse handles its own auth via native SSO)
- Both `envoy-external` and `envoy-internal` parentRefs (split-horizon DNS)
- Cross-namespace reference to `langfuse-web` service via ReferenceGrant

#### 3. Configure SSO-Only Mode with Auto-Redirect (Optional but Recommended)

For the most seamless experience, configure Langfuse to auto-redirect to Keycloak:

**Update `cluster.yaml`:**
```yaml
# Langfuse SSO Configuration
langfuse_sso_enabled: true
langfuse_keycloak_client_secret: "<SOPS-encrypted>"

# Force SSO-only mode (hide username/password form)
langfuse_disable_password_auth: true

# Auto-redirect to Keycloak for your domain
langfuse_sso_domain_enforcement: "example.com"

# Disable self-registration (users must exist in Keycloak first)
langfuse_disable_signup: true

# Auto-provision new SSO users into default org/project
langfuse_default_org_id: "matherlynet"
langfuse_default_org_role: "MEMBER"
langfuse_default_project_id: "default-project"
langfuse_default_project_role: "VIEWER"
```

#### 4. Verify Environment Variables in Template

Ensure the following environment variables are correctly rendered in `additionalEnv`:

```jinja
#% if langfuse_disable_password_auth | default(false) %#
        - name: AUTH_DISABLE_USERNAME_PASSWORD
          value: "true"
#% endif %#
#% if langfuse_sso_domain_enforcement | default('') %#
        - name: AUTH_DOMAINS_WITH_SSO_ENFORCEMENT
          value: "#{ langfuse_sso_domain_enforcement }#"
#% endif %#
```

### Resulting User Experience

| Scenario | User Action | Experience |
| ---------- | ------------- | ------------ |
| First visit (no session) | Visit langfuse.example.com | Auto-redirect to Keycloak → Login → Return to Langfuse |
| Existing Keycloak session | Visit langfuse.example.com | Auto-redirect to Keycloak → Immediate return (no form) → Logged in |
| Cross-service SSO | Login at Grafana first, then visit Langfuse | Auto-redirect to Keycloak → Immediate return → Logged in |

**Expected latency for users with existing session: ~200-500ms (same as Grafana)**

## Implementation Checklist

### Critical Bug Fix (Required)
- [ ] **FIX: Replace `auth.additionalProviders` with environment variables in `helmrelease.yaml.j2`**
  - Remove the entire `auth:` block (lines 192-209)
  - Add `AUTH_KEYCLOAK_*` environment variables to `additionalEnv` section:
    - `AUTH_KEYCLOAK_CLIENT_ID` = "langfuse"
    - `AUTH_KEYCLOAK_CLIENT_SECRET` (from secret)
    - `AUTH_KEYCLOAK_ISSUER` = keycloak_issuer_url
    - `AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING` = "true"
    - `AUTH_KEYCLOAK_CHECKS` = "pkce,state" **(enables PKCE verification)**
  - **Note:** Do NOT set `AUTH_KEYCLOAK_CLIENT_AUTH_METHOD` - use default `client_secret_basic` for confidential clients
- [ ] Remove `security: oidc-protected` label from Langfuse HTTPRoute (avoid dual auth)
- [ ] Run `task configure` to regenerate templates
- [ ] Verify `NEXTAUTH_URL` is set correctly: `kubectl -n ai-system exec -it deploy/langfuse-web -- env | grep NEXTAUTH`
- [ ] Deploy and verify "Login with Keycloak" button appears

### Seamless SSO Enhancement (Recommended)
- [ ] Set `langfuse_disable_password_auth: true` in cluster.yaml (hide password form)
- [ ] Set `langfuse_sso_domain_enforcement: "your-domain.com"` for auto-redirect
- [ ] Set `langfuse_disable_signup: true` for security hardening
- [ ] Configure auto-provisioning with `langfuse_default_org_*` and `langfuse_default_project_*`
- [ ] Re-run `task configure` and deploy
- [ ] Verify seamless SSO flow (auto-redirect to Keycloak)

## Comparison with Other SSO Integrations

| Service | SSO Type | Auto-Login | Gateway OIDC | Native SSO |
| --------- | ---------- | ---------- | ------------ | ---------- |
| **Grafana** | Native OAuth | ✅ `auto_login: true` | ❌ Not needed | ✅ Full RBAC |
| **Hubble UI** | Gateway | N/A | ✅ Required | ❌ No native |
| **RustFS** | Gateway | N/A | ✅ Required | ❌ No native |
| **LiteLLM** | Native OIDC | ✅ Via OIDC config | ❌ Not needed | ✅ Team mapping |
| **Langfuse** | Native Keycloak | ✅ Via domain enforcement | ❌ Remove | ✅ Org/Project RBAC |

## Security Considerations

1. **Account Linking**: `allowDangerousEmailAccountLinking: true` is enabled. This allows users with existing email/password accounts to link their Keycloak identity. After SSO-only mode is enabled, new users can only authenticate via Keycloak.

2. **Domain Enforcement**: `AUTH_DOMAINS_WITH_SSO_ENFORCEMENT` only triggers auto-redirect for users whose email matches the specified domain. Users with emails from other domains would still see the login form (though with password auth disabled, they'd need to click "Login with Keycloak").

3. **Session Duration**: Configure `langfuse_session_max_age` (in minutes) to match your security requirements. Default is 30 days (43200 minutes).

## Conclusion

The recommended approach is **Option 3: Native SSO with Auto-Login** using:
- `AUTH_DISABLE_USERNAME_PASSWORD=true` to hide the password form
- `AUTH_DOMAINS_WITH_SSO_ENFORCEMENT` to auto-redirect to Keycloak
- Removal of Gateway-level OIDC protection to avoid double authentication

This achieves the same seamless SSO experience as Grafana (~200-500ms redirect for users with existing session) while maintaining Langfuse's full RBAC capabilities for organizations and projects.

## Complete Environment Variable Reference

### Core SSO Provider Variables (Keycloak)

| Variable | Required | Description |
| ---------- | ---------- | ------------- |
| `AUTH_KEYCLOAK_CLIENT_ID` | ✅ | OIDC client ID registered in Keycloak |
| `AUTH_KEYCLOAK_CLIENT_SECRET` | ✅ | OIDC client secret |
| `AUTH_KEYCLOAK_ISSUER` | ✅ | Keycloak realm URL (e.g., `https://sso.example.com/realms/matherlynet`) |
| `AUTH_KEYCLOAK_ALLOW_ACCOUNT_LINKING` | ⚠️ | `true` to allow merging accounts with same email |
| `AUTH_KEYCLOAK_CLIENT_AUTH_METHOD` | | `none` for public clients, `client_secret_basic` (default) for confidential clients |
| `AUTH_KEYCLOAK_CHECKS` | ⚠️ | `pkce,state` to enable PKCE verification (works with both client types) |
| `AUTH_KEYCLOAK_SCOPE` | | Custom scopes (default: `openid email profile`) |
| `AUTH_KEYCLOAK_ID_TOKEN` | | `false` to use userinfo endpoint instead of id_token claims |

### Global Auth Variables

| Variable | Description |
| ---------- | ------------- |
| `NEXTAUTH_URL` | **Required for SSO** - Public URL of Langfuse (e.g., `https://langfuse.example.com`) |
| `AUTH_DISABLE_USERNAME_PASSWORD` | `true` to hide email/password form (SSO-only mode) |
| `AUTH_DISABLE_SIGNUP` | `true` to prevent new user registration |
| `AUTH_DOMAINS_WITH_SSO_ENFORCEMENT` | Comma-separated domains forced to use SSO (e.g., `example.com,corp.com`) |
| `AUTH_SESSION_MAX_AGE` | Session duration in **minutes** (default: 43200 = 30 days, minimum: 5) |
| `AUTH_IGNORE_ACCOUNT_FIELDS` | Comma-separated fields to ignore from SSO IDP account |

### PKCE Configuration by Client Type

**Confidential Client with PKCE (Our Keycloak Config - Recommended):**
```yaml
# Keycloak: publicClient=false + pkce.code.challenge.method=S256
# Client secret provides primary auth, PKCE adds extra security
AUTH_KEYCLOAK_CHECKS: "pkce,state"
# AUTH_KEYCLOAK_CLIENT_AUTH_METHOD: omit (uses default client_secret_basic)
```

**Public Client with PKCE (Browser Apps, SPAs):**
```yaml
# Keycloak: publicClient=true + pkce.code.challenge.method=S256
# No client secret - PKCE is the primary authentication method
AUTH_KEYCLOAK_CLIENT_AUTH_METHOD: "none"
AUTH_KEYCLOAK_CHECKS: "pkce,state"
```

**Confidential Client without PKCE (Legacy):**
```yaml
# Keycloak: publicClient=false, no PKCE attribute
AUTH_KEYCLOAK_CHECKS: "state"  # or "nonce,state"
# AUTH_KEYCLOAK_CLIENT_AUTH_METHOD: omit (uses default client_secret_basic)
```

## Cookie Domain Isolation (Session Collision Fix)

### Problem: Gateway OIDC and Native SSO Cookie Collision

When accessing Langfuse after visiting another app with Gateway OIDC protection (e.g., Hubble), users may experience unexpected session behavior:
- Being auto-logged in as the local admin account instead of Keycloak user
- Session conflicts between Gateway OIDC cookies and NextAuth.js cookies

**Root Cause:**
Both Gateway OIDC and Langfuse's NextAuth.js set session cookies on the `*.matherly.net` domain:
- Gateway OIDC: `IdToken`, `AccessToken`, `RefreshToken`
- NextAuth.js: `next-auth.session-token`, `next-auth.csrf-token`

Without explicit domain isolation, these cookies can interfere with each other.

### Solution: NEXTAUTH_COOKIE_DOMAIN

Langfuse supports the `NEXTAUTH_COOKIE_DOMAIN` environment variable to scope NextAuth.js cookies to a specific domain.

**Implementation (`helmrelease.yaml.j2`):**
```yaml
additionalEnv:
  - name: NEXTAUTH_COOKIE_DOMAIN
    value: "langfuse.${cloudflare_domain}"
```

This ensures Langfuse's session cookies are scoped to `langfuse.matherly.net` only, preventing collision with Gateway OIDC cookies from other subdomains.

### How Cookie Isolation Works

**Langfuse Cookie Configuration (`web/src/server/utils/cookies.ts`):**
```typescript
export const getCookieOptions = () => ({
  domain: env.NEXTAUTH_COOKIE_DOMAIN ?? undefined,
  httpOnly: true,
  sameSite: "lax" as const,
  path: env.NEXT_PUBLIC_BASE_PATH || "/",
  secure: shouldSecureCookies(),
});

export const getCookieName = (name: string) =>
  [
    shouldSecureCookies() ? "__Secure-" : "",
    name,
    env.NEXT_PUBLIC_LANGFUSE_CLOUD_REGION
      ? `.${env.NEXT_PUBLIC_LANGFUSE_CLOUD_REGION}`
      : "",
  ].join("");
```

**Cookie Scope Comparison:**

| Scenario | Cookie Domain | Visibility |
| -------- | ------------- | ---------- |
| Default (no NEXTAUTH_COOKIE_DOMAIN) | Browser default | Depends on browser |
| `NEXTAUTH_COOKIE_DOMAIN=langfuse.example.com` | `langfuse.example.com` | Only Langfuse |
| `NEXTAUTH_COOKIE_DOMAIN=.example.com` | `.example.com` | All subdomains |

**Our configuration uses explicit hostname** (`langfuse.matherly.net`) to isolate cookies.

### References

- [Langfuse GitHub: cookies.ts](https://github.com/langfuse/langfuse/blob/main/web/src/server/utils/cookies.ts)
- [NextAuth.js Cookie Configuration](https://next-auth.js.org/configuration/options#cookies)

## References

- [Langfuse SSO Documentation](https://langfuse.com/self-hosting/authentication-and-sso)
- [Langfuse SCIM and Org API](https://langfuse.com/docs/administration/scim-and-org-api)
- [NextAuth.js Providers](https://next-auth.js.org/providers/)
- [Keycloak OIDC Documentation](https://www.keycloak.org/docs/latest/server_admin/#_oidc-clients)
