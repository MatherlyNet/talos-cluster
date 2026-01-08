# Envoy Gateway + Keycloak OIDC Integration Research

**Date:** January 2026
**Last Validated:** January 7, 2026
**Envoy Gateway Version:** 0.0.0-latest (for Kubernetes 1.35 support; stable is 1.6.x)
**API Version:** v1alpha1 (SecurityPolicy has not graduated to v1)
**Keycloak Version:** 26.5.0
**Scope:** Social IdP integration (Google, GitHub, Microsoft Entra ID) via Keycloak with Envoy Gateway SecurityPolicy

> [!NOTE]
> **Implementation Complete (January 2026)** - All components from this research have been fully implemented:
> - OIDC SecurityPolicy template (`securitypolicy-oidc.yaml.j2`) with dynamic redirect URL support
> - JWT SecurityPolicy template (`securitypolicy-jwt.yaml.j2`) with claim-to-header extraction
> - Keycloak realm-import with auto-bootstrapped OIDC client and social IdP support
> - HTTPRoute labeling (`security: oidc-protected`) for Hubble, Grafana, RustFS
> - Cookie domain configuration for cross-subdomain SSO
>
> See `docs/guides/native-oidc-securitypolicy-implementation.md` for implementation details.

## Executive Summary

This research document provides a comprehensive guide for integrating Envoy Gateway's SecurityPolicy with Keycloak as the OIDC provider, enabling social identity provider authentication (Google, GitHub, Microsoft Entra ID) for all protected applications.

**Key Findings:**
- Envoy Gateway supports two distinct security approaches: **OIDC Authentication** (browser-based SSO) and **JWT Authentication** (API/programmatic access)
- The current cluster implementation already has both SecurityPolicy types configured correctly
- Social IdP integration happens at the **Keycloak layer**, not the Envoy Gateway layer
- Users authenticate via Keycloak's login page, which presents social IdP options
- Seamless SSO across applications is achieved via Keycloak's session management + `cookieDomain` configuration

**Validation Status:** ✅ All configurations validated against official Envoy Gateway documentation and source code (January 7, 2026)

**Architecture Overview:**
```
User Browser
     │
     ▼
Envoy Gateway (SecurityPolicy: OIDC)
     │
     ▼ (redirect if unauthenticated)
Keycloak Login Page
     │
     ├─► Google IdP
     ├─► GitHub IdP
     └─► Microsoft Entra ID
     │
     ▼ (after authentication)
Envoy Gateway (validates tokens)
     │
     ▼
Backend Service (Hubble UI, Grafana, RustFS)
```

## Table of Contents

1. [Version Compatibility](#version-compatibility)
2. [Envoy Gateway Security Options](#envoy-gateway-security-options)
3. [OIDC vs JWT: When to Use Which](#oidc-vs-jwt-when-to-use-which)
4. [Current Cluster Implementation](#current-cluster-implementation)
5. [New Features in v1.5/v1.6/latest](#new-features-in-v15v16latest)
6. [Social IdP Integration Flow](#social-idp-integration-flow)
7. [Cookie Domain Configuration](#cookie-domain-configuration)
8. [Implementation Requirements](#implementation-requirements)
9. [Security Considerations](#security-considerations)
10. [Testing and Validation](#testing-and-validation)

---

## Version Compatibility

### Why v0.0.0-latest?

This cluster uses Envoy Gateway `v0.0.0-latest` (main branch builds) specifically for **Kubernetes 1.35 support**.

**Compatibility Matrix (from [official docs](https://gateway.envoyproxy.io/news/releases/matrix/)):**

| EG Version | Kubernetes Support | Gateway API | Status |
| ------------ | ------------------- | ------------- | -------- |
| **latest** | **v1.32-v1.35** | v1.4.1 | ✅ Used by this cluster |
| v1.6 | v1.30-v1.33 | v1.4.0 | Current stable (EOL 2026/05) |
| v1.5 | v1.30-v1.33 | v1.3.0 | Previous stable (EOL 2026/02) |
| v1.3 | v1.29-v1.32 | v1.2.1 | Outdated (EOL 2025/07) |

**Key Insight:** Stable v1.6.x does NOT support Kubernetes 1.35. The `latest` track is required for K8s 1.35 clusters.

### Project Configuration

```yaml
# kubernetes/apps/network/envoy-gateway/app/ocirepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: envoy-gateway
spec:
  ref:
    tag: v0.0.0-latest  # Required for K8s 1.35
  url: oci://docker.io/envoyproxy/gateway-helm
```

### API Version Status

- **SecurityPolicy**: `gateway.envoyproxy.io/v1alpha1` (has NOT graduated to v1)
- **Gateway API**: v1.4.1 in latest track
- All CRDs remain in alpha stage

---

## Envoy Gateway Security Options

Envoy Gateway provides multiple security mechanisms via SecurityPolicy CRD. Based on analysis of the official documentation:

### 1. OIDC Authentication (Browser SSO)

**Reference:** [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/latest/tasks/security/oidc/)

Handles complete browser-based authentication flow:
- Redirects unauthenticated users to identity provider
- Manages OAuth2 authorization code flow
- Stores tokens in secure HTTP-only cookies
- Supports logout flow

**Use Case:** Web applications accessed via browser (Grafana, Hubble UI, RustFS Console)

### 2. JWT Authentication (API/Programmatic)

**Reference:** [Envoy Gateway JWT Authentication](https://gateway.envoyproxy.io/latest/tasks/security/jwt-authentication/)

Validates pre-existing JWT tokens:
- Extracts bearer token from Authorization header
- Validates signature against JWKS
- Extracts claims to headers for backend services
- Returns 401 for invalid/missing tokens

**Use Case:** API endpoints, machine-to-machine communication, CLI tools

### 3. JWT Claim-Based Authorization

**Reference:** [Envoy Gateway JWT Claim Authorization](https://gateway.envoyproxy.io/latest/tasks/security/jwt-claim-authorization/)

Enables fine-grained access control based on JWT claims:
- Role-based access control via claim inspection
- Scope validation for specific permissions
- Default deny with explicit allow rules

**Use Case:** Restricting API access based on user roles/groups

### 4. External Authorization

**Reference:** [Envoy Gateway External Auth](https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/)

Delegates authorization decisions to external service:
- HTTP or gRPC backend for custom logic
- Flexible policy evaluation
- Custom header propagation

**Use Case:** Complex authorization rules, legacy auth systems

---

## OIDC vs JWT: When to Use Which

| Aspect | OIDC SecurityPolicy | JWT SecurityPolicy |
| -------- | ------------------- | ------------------ |
| **Primary Use** | Browser-based web apps | API/programmatic access |
| **Authentication Flow** | Full OAuth2 code flow | Token validation only |
| **User Interaction** | Redirects to login page | None (expects token) |
| **Token Handling** | Manages tokens in cookies | Expects `Authorization: Bearer` header |
| **Session Management** | Cookie-based sessions | Stateless (per-request) |
| **Social IdP Support** | Via IdP's login page | Via pre-obtained tokens |
| **Label Selector** | `security: oidc-protected` | `security: jwt-protected` |

### Current Cluster Configuration

Your cluster correctly implements **both** approaches:

1. **`securitypolicy-oidc.yaml`** - For browser-based applications
   - Targets: `security: oidc-protected` label
   - Flow: Redirect → Keycloak → Social IdP → Callback → Backend

2. **`securitypolicy-jwt.yaml`** - For API/programmatic access
   - Targets: `security: jwt-protected` label
   - Flow: Validate token → Extract claims → Forward to backend

---

## Current Cluster Implementation

### SecurityPolicy: OIDC (Browser SSO)

```yaml
# Current implementation in securitypolicy-oidc.yaml.j2
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: oidc-sso
  namespace: network
spec:
  targetSelectors:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      matchLabels:
        security: oidc-protected
  oidc:
    provider:
      issuer: "https://sso.matherly.net/realms/matherlynet"
    clientID: "envoy-gateway"
    clientSecret:
      name: oidc-client-secret
    redirectURL: "..."
    logoutPath: "/logout"
    cookieDomain: ".matherly.net"  # Enables cross-subdomain SSO
    scopes:
      - openid
      - profile
      - email
    forwardAccessToken: true
```

### SecurityPolicy: JWT (API Access)

```yaml
# Current implementation in securitypolicy-jwt.yaml.j2
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-auth
  namespace: network
spec:
  targetSelectors:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      matchLabels:
        security: jwt-protected
  jwt:
    providers:
      - name: keycloak
        issuer: "https://sso.matherly.net/realms/matherlynet"
        remoteJWKS:
          uri: "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs"
          cacheDuration: 300s
        claimToHeaders:
          - claim: sub
            header: X-User-ID
          - claim: email
            header: X-User-Email
          - claim: groups
            header: X-User-Groups
```

### Protected HTTPRoutes

```yaml
# internal-httproutes.yaml.j2 - Routes labeled for OIDC protection
metadata:
  labels:
    security: oidc-protected  # Triggers OIDC SecurityPolicy
```

---

## New Features in v1.5/v1.6/latest

Since this cluster uses `v0.0.0-latest`, the following features are available but may not be in the current templates:

### OIDC Enhancements (v1.5+)

| Feature | Version | Description | Current Status |
| --------- | --------- | ------------- | ---------------- |
| `refreshToken` | v1.6 | Auto-refresh tokens when expired | **Breaking**: Now defaults to `true` |
| `SameSite` | v1.5 | Cookie SameSite attribute | Optional enhancement |
| `CSRFTokenTTL` | v1.6 | Custom CSRF token lifetime | Optional |
| `DisableTokenEncryption` | v1.6 | Skip token encryption in cookies | Not recommended |
| OIDC bypass for Bearer | v1.5 | Defer to JWT when Bearer header present | Useful for APIs |
| RP-initiated logout | v1.5 | Invoke end_session_endpoint on logout | Recommended |
| Secret-based clientID | v1.5 | Store clientID in Secret | Optional |

### Breaking Change Alert: refreshToken

**v1.6 changed default behavior:**
```yaml
# OLD behavior (v1.5 and earlier): No automatic token refresh
# NEW behavior (v1.6+): Auto-refresh enabled by default

oidc:
  refreshToken: true  # Now the default - tokens auto-refresh on expiry
```

If you want the old behavior, explicitly set `refreshToken: false`.

### JWT Enhancements (v1.6+)

| Feature | Version | Description |
| --------- | --------- | ------------- |
| Multi-listener fix | v1.6 | JWT provider config now works across multiple HTTP listeners on same port |
| RetryPolicy for ExtAuth | v1.6 | gRPC external auth callouts support retries |

### Recommended Template Updates

Consider adding these optional fields to `securitypolicy-oidc.yaml.j2`:

```yaml
oidc:
  # ... existing fields ...

  # NEW: Explicit refresh token behavior (v1.6 default is true)
  #% if oidc_refresh_token is defined %#
  refreshToken: #{ oidc_refresh_token }#
  #% endif %#

  # NEW: RP-initiated logout (v1.5+)
  # Automatically calls Keycloak's end_session_endpoint
  # (Requires logoutPath to be configured)

  # NEW: SameSite cookie attribute (v1.5+)
  #% if oidc_cookie_samesite is defined %#
  cookieSameSite: "#{ oidc_cookie_samesite }#"
  #% endif %#
```

---

## Social IdP Integration Flow

### Understanding the Authentication Chain

**Critical Insight:** Social IdP integration (Google, GitHub, Microsoft) is configured in **Keycloak**, NOT in Envoy Gateway.

Envoy Gateway only knows about Keycloak as its OIDC provider. When users click "Sign in with Google", the flow is:

```
1. User → Envoy Gateway (no session)
2. Envoy Gateway → Keycloak (redirect to login page)
3. Keycloak → User (displays login options: local + social IdPs)
4. User clicks "Google" → Google OAuth consent screen
5. Google → Keycloak (authorization code callback)
6. Keycloak creates/links user account, issues tokens
7. Keycloak → Envoy Gateway (authorization code)
8. Envoy Gateway exchanges code for tokens
9. Envoy Gateway stores tokens in cookies
10. User → Backend Service (authenticated)
```

### Why This Architecture Works

1. **Envoy Gateway doesn't need to know about social IdPs** - It only talks to Keycloak
2. **Keycloak handles IdP complexity** - Token exchange, user provisioning, account linking
3. **SSO is managed by Keycloak** - Single session across all applications
4. **Adding new IdPs is easy** - Configure in Keycloak, no Envoy changes needed

---

## Cookie Domain Configuration

### The cookieDomain Field

**Reference:** [Envoy Gateway OIDC Cookie Domain](https://gateway.envoyproxy.io/latest/tasks/security/oidc/)

The `cookieDomain` field is critical for seamless SSO across subdomains:

```yaml
oidc:
  cookieDomain: ".matherly.net"  # Note the leading dot
```

### How It Enables Seamless SSO

| Without cookieDomain | With cookieDomain: ".matherly.net" |
| --------------------- | ----------------------------------- |
| Cookie set for `hubble.matherly.net` only | Cookie set for `*.matherly.net` |
| Must re-authenticate for `grafana.matherly.net` | Token shared across all subdomains |
| Separate session per subdomain | Single session across cluster |

### Current Configuration

Your templates already support this via `oidc_cookie_domain`:

```jinja2
#% if oidc_cookie_domain is defined %#
cookieDomain: "#{ oidc_cookie_domain }#"
#% endif %#
```

**Required cluster.yaml setting:**
```yaml
oidc_cookie_domain: ".matherly.net"
```

### Important Note

From the documentation: "Existing cookies must be cleared in the browser before applying a new cookieDomain configuration."

---

## Implementation Requirements

### What's Already Done

| Component | Status | Notes |
| ----------- | -------- | ------- |
| SecurityPolicy OIDC | Implemented | `securitypolicy-oidc.yaml.j2` |
| SecurityPolicy JWT | Implemented | `securitypolicy-jwt.yaml.j2` |
| OIDC Client in Keycloak | Implemented | `envoy-gateway` client in realm |
| HTTPRoute Labels | Implemented | `security: oidc-protected` |
| Token Exchange Feature | Enabled | In `keycloak-cr.yaml` |

### What Needs Configuration

| Component | Status | Action Required |
| ----------- | -------- | ----------------- |
| Google IdP in Keycloak | Not configured | Create OAuth app, configure in Keycloak |
| GitHub IdP in Keycloak | Not configured | Create OAuth app, configure in Keycloak |
| Microsoft IdP in Keycloak | Not configured | Create app registration, configure in Keycloak |
| cookieDomain | May need setting | Add `oidc_cookie_domain: ".matherly.net"` to cluster.yaml |

### Envoy Gateway Variables Required

Add/verify in `cluster.yaml`:

```yaml
# OIDC SSO Configuration
oidc_sso_enabled: true
oidc_issuer_url: "https://sso.matherly.net/realms/matherlynet"
oidc_client_id: "envoy-gateway"
oidc_client_secret: "YOUR_SECRET"  # SOPS-encrypted
# oidc_redirect_url: OMIT for dynamic redirect (RECOMMENDED)
# IMPORTANT: Wildcards are NOT supported - Envoy Gateway will URL-encode them!
# When omitted, Envoy Gateway uses: %REQ(:authority)%/oauth2/callback
oidc_logout_path: "/logout"
oidc_cookie_domain: "matherly.net"  # Enables SSO across all *.matherly.net apps
oidc_scopes:
  - openid
  - profile
  - email
```

---

## Security Considerations

### HTTPS Requirement

From documentation: "OIDC will not work in a plaintext HTTP listener environment." The cluster's `envoy-internal` gateway uses HTTPS with valid certificates.

### Token Storage

Envoy Gateway manages three cookies:
- `OauthHMAC` - Token verification
- `OauthExpires` - Token lifetime tracking
- `IdToken` - The actual JWT

All cookies are:
- HttpOnly (no JavaScript access)
- Secure (HTTPS only)
- SameSite=Lax (CSRF protection)

### Client Secret Management

The client secret must be stored in a Kubernetes secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oidc-client-secret
  namespace: network
type: Opaque
data:
  client-secret: <base64-encoded-secret>
```

Your cluster already manages this via `secret-oidc.sops.yaml`.

### Logout Considerations

The `logoutPath` configuration triggers OAuth2 filter cleanup, but for complete logout:
1. Envoy Gateway clears its cookies
2. User should also be logged out of Keycloak (RP-initiated logout)
3. Optionally, logout from upstream IdP (Google, etc.)

The current implementation handles #1. Full federated logout may require additional configuration.

---

## Testing and Validation

### Pre-Implementation Checklist

- [ ] `oidc_sso_enabled: true` in cluster.yaml
- [ ] `oidc_cookie_domain: ".matherly.net"` in cluster.yaml
- [ ] OIDC client secret matches between Keycloak and cluster secret
- [ ] At least one social IdP configured in Keycloak

### Test Procedure

1. **Clear all browser cookies** for `*.matherly.net`

2. **Navigate to first protected app:**
   ```
   https://hubble.matherly.net
   ```
   - Should redirect to `sso.matherly.net`
   - Should show login options (local + configured social IdPs)

3. **Authenticate via social IdP:**
   - Click Google/GitHub/Microsoft
   - Complete external authentication
   - Should redirect back to Hubble UI

4. **Test SSO (without logging out):**
   ```
   https://grafana.matherly.net
   ```
   - Should NOT show login page
   - Should be automatically authenticated

5. **Test another app:**
   ```
   https://rustfs.matherly.net
   ```
   - Should also be automatically authenticated

6. **Test logout:**
   - Navigate to logout path
   - Clear session from Keycloak
   - Verify re-authentication required

### Troubleshooting Commands

```bash
# Check SecurityPolicy status
kubectl get securitypolicy -n network -o yaml

# Check HTTPRoute labels
kubectl get httproute -n network -o yaml | grep -A5 labels

# Check Envoy proxy logs for OIDC errors
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=envoy -c envoy | grep -i oauth

# Verify Keycloak realm configuration
curl -s https://sso.matherly.net/realms/matherlynet/.well-known/openid-configuration | jq .

# Check if JWKS is accessible
curl -s https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs | jq .
```

---

## Sources

### Official Documentation (Validated January 2026)
- [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/latest/tasks/security/oidc/)
- [Envoy Gateway JWT Authentication](https://gateway.envoyproxy.io/latest/tasks/security/jwt-authentication/)
- [Envoy Gateway JWT Claim Authorization](https://gateway.envoyproxy.io/latest/tasks/security/jwt-claim-authorization/)
- [Envoy Gateway External Authorization](https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/)
- [SecurityPolicy API Reference](https://gateway.envoyproxy.io/latest/api/extension_types/)
- [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/) - **Critical for K8s version support**

### Release Notes (Version Research)
- [v1.6.0 Release Notes](https://gateway.envoyproxy.io/news/releases/notes/v1.6.0/) - refreshToken breaking change
- [v1.5.0 Release Notes](https://gateway.envoyproxy.io/news/releases/notes/v1.5.0/) - SameSite, RP-initiated logout
- [v1.3.0 Release Notes](https://gateway.envoyproxy.io/news/releases/notes/v1.3.0/) - API Key auth, cookieDomain docs
- [Release Announcements](https://gateway.envoyproxy.io/news/releases/)
- [GitHub Releases](https://github.com/envoyproxy/gateway/releases)

### Community Resources
- [Jimmy Song - Envoy Gateway OIDC Tutorial](https://jimmysong.io/blog/envoy-gateway-oidc/)
- [JBW - Integrating Keycloak OIDC with Envoy Gateway](https://www.jbw.codes/blog/Integrating-Keycloak-OIDC-with-Envoy-API-Gateway)
- [Envoy Gateway OIDC Demo by Zhaohuabing](https://www.zhaohuabing.com/post/2025-04-20-envoy-gateway-oidc-demo/)
- [Authelia - Envoy Gateway OIDC Integration](https://www.authelia.com/integration/openid-connect/clients/envoy-gateway/)

### GitHub Discussions
- [OIDC authentication using Entra ID](https://github.com/envoyproxy/gateway/discussions/4686)
- [Envoy Gateway Self-Signed Certificate Issue](https://github.com/envoyproxy/gateway/issues/4838)
- [Combining OIDC and JWT authentication](https://github.com/envoyproxy/gateway/discussions/2425)

---

## Appendix A: Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER BROWSER                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 1. Request hubble.matherly.net
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ENVOY GATEWAY                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ SecurityPolicy: oidc-sso                                              │   │
│  │ Target: HTTPRoute with label security: oidc-protected                 │   │
│  │                                                                       │   │
│  │ Check: Valid session cookie?                                          │   │
│  │   NO → Redirect to Keycloak                                           │   │
│  │   YES → Forward to backend                                            │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 2. Redirect (no session)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            KEYCLOAK                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Realm: matherlynet                                                    │   │
│  │ Client: envoy-gateway                                                 │   │
│  │                                                                       │   │
│  │ Login Page Options:                                                   │   │
│  │   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │   │
│  │   │   Google    │ │   GitHub    │ │  Microsoft  │ │    Local    │    │   │
│  │   └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 3. User clicks "Google"
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GOOGLE OAUTH                                          │
│  - User authenticates with Google credentials                                │
│  - Google returns authorization code to Keycloak callback                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 4. Auth code callback
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            KEYCLOAK                                          │
│  - Exchanges auth code for Google tokens                                     │
│  - Creates/updates local user account                                        │
│  - Issues Keycloak tokens (ID token, access token)                          │
│  - Redirects to Envoy Gateway callback URL                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 5. Auth code to Envoy
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ENVOY GATEWAY                                       │
│  - Exchanges auth code for Keycloak tokens                                   │
│  - Stores tokens in secure cookies:                                          │
│      • OauthHMAC (verification)                                              │
│      • OauthExpires (lifetime)                                               │
│      • IdToken (JWT)                                                         │
│  - Cookie domain: .matherly.net (shared across subdomains)                  │
│  - Redirects to original URL (hubble.matherly.net)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 6. Authenticated request
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HUBBLE UI                                           │
│  - Receives authenticated request                                            │
│  - Access token forwarded in header (forwardAccessToken: true)              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 7. User navigates to grafana.matherly.net
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ENVOY GATEWAY                                       │
│  - Checks session cookie (shared via cookieDomain: .matherly.net)           │
│  - Cookie valid → Forward directly to backend                                │
│  - NO REDIRECT TO KEYCLOAK (seamless SSO!)                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 8. Direct access (authenticated)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            GRAFANA                                           │
│  - Receives authenticated request                                            │
│  - User seamlessly logged in                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Appendix B: Key Differences from Previous Research

After reviewing the existing research document (`keycloak-social-identity-providers-integration-jan-2026.md`), the following clarifications/corrections should be noted:

### Clarification 1: SSO Cookie Mechanism

The previous document mentioned:
> "Keycloak uses the `KEYCLOAK_IDENTITY` cookie to maintain SSO sessions"

**Clarification:** When using Envoy Gateway OIDC SecurityPolicy, the SSO session is managed by **Envoy Gateway's cookies** (`OauthHMAC`, `OauthExpires`, `IdToken`), not Keycloak's cookies. The Keycloak session is used during the authentication flow, but subsequent requests are validated by Envoy Gateway using its own cookie-based session.

### Clarification 2: Token Flow

The previous document's "Seamless SSO Implementation" section correctly describes the high-level flow but could benefit from noting that:

- Envoy Gateway handles the OAuth2 authorization code flow
- Envoy Gateway stores and validates tokens, not individual applications
- The `cookieDomain` setting is what enables cross-subdomain SSO at the gateway level

### Clarification 3: Application-Specific OAuth

The previous document's section on "Native Grafana OAuth + Gateway" is correct but should note:

- Using native Grafana OAuth **in addition to** gateway-level OIDC creates two authentication layers
- For most use cases, gateway-level OIDC alone is sufficient
- Native OAuth is only needed for Grafana-specific role mapping from IdP claims

### No Corrections Needed

The core content of the previous research document is accurate:
- Identity provider configuration in Keycloak
- Token exchange capabilities
- Security considerations
- Implementation plan phases

These remain valid and should be followed for the Keycloak-side configuration.
