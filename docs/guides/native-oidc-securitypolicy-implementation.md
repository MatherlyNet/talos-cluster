# Native OIDC SecurityPolicy Implementation Guide

> **Created:** January 2026
> **Status:** Implemented
> **Dependencies:** OIDC Provider (Keycloak), Envoy Gateway v1.6.1+
> **Effort:** ~2-3 hours (excluding OIDC provider setup)

---

## Overview

This guide implements **Native OIDC SecurityPolicy** for web browser SSO (Single Sign-On) using Envoy Gateway. This is distinct from JWT SecurityPolicy (which handles API/service-to-service authentication with Bearer tokens).

### OIDC vs JWT Authentication

| Feature | OIDC SecurityPolicy (This Guide) | JWT SecurityPolicy (Existing) |
| ------- | -------------------------------- | ----------------------------- |
| **Use Case** | Web browser SSO, user login | API/service-to-service auth |
| **Flow** | Redirect to IdP login page | Bearer token validation |
| **Session** | Cookie-based sessions | Stateless tokens |
| **User Interaction** | Required (login form) | None (token passed in header) |
| **Template** | `securitypolicy-oidc.yaml.j2` | `securitypolicy-jwt.yaml.j2` |

### Prerequisites

- Envoy Gateway v1.6.1+ deployed (current: v0.0.0-latest)
- OIDC provider deployed and configured (e.g., Keycloak)
- HTTPRoutes configured for protected applications
- TLS certificates configured for HTTPS

---

## Configuration Variables

### Required Variables (cluster.yaml)

```yaml
# =============================================================================
# OIDC WEB SSO CONFIGURATION - Session-based authentication for web apps
# =============================================================================
# Native OIDC authentication for browser-based SSO with cookie sessions.
# Distinct from JWT SecurityPolicy which handles API token validation.
# REF: https://gateway.envoyproxy.io/docs/tasks/security/oidc/

# -- Enable OIDC Web SSO (creates SecurityPolicy for session-based auth)
#    (OPTIONAL) / (DEFAULT: false)
# oidc_sso_enabled: false

# -- OIDC provider issuer URL (authorization server)
#    Must match the "iss" claim in tokens from this provider
#    (REQUIRED when oidc_sso_enabled: true)
#    Example: "https://auth.example.com/realms/myrealm"
# oidc_issuer_url: ""

# -- OIDC client ID (application identifier from IdP)
#    (REQUIRED when oidc_sso_enabled: true)
# oidc_client_id: ""

# -- OIDC client secret (SOPS-encrypted)
#    (REQUIRED when oidc_sso_enabled: true)
# oidc_client_secret: ""

# -- Redirect URL for OAuth2 callback (OPTIONAL - omit for dynamic redirect)
#    IMPORTANT: Wildcards (*.domain.com) are NOT supported - will break authentication!
#    RECOMMENDED: Omit this field to use dynamic redirect based on request hostname
#    When omitted, Envoy Gateway uses: %REQ(:authority)%/oauth2/callback
#    (OPTIONAL) / Example: "https://app.example.com/oauth2/callback"
# oidc_redirect_url: ""

# -- Cookie domain for session sharing across subdomains
#    Set to base domain to share auth across *.example.com
#    (OPTIONAL) / Example: "example.com"
# oidc_cookie_domain: ""

# -- Logout path (must match HTTPRoute for routing)
#    (OPTIONAL) / (DEFAULT: "/logout")
# oidc_logout_path: "/logout"

# -- OAuth2 scopes to request
#    (OPTIONAL) / (DEFAULT: ["openid", "profile", "email"])
# oidc_scopes:
#   - openid
#   - profile
#   - email
```

### Derived Variables (plugin.py)

Add to `templates/scripts/plugin.py`:

```python
# OIDC SSO - enabled when required fields are set (redirect_url is optional)
oidc_sso_enabled = (
    data.get("oidc_sso_enabled", False) and
    data.get("oidc_issuer_url") and
    data.get("oidc_client_id") and
    data.get("oidc_client_secret")
    # oidc_redirect_url is optional - omit for dynamic redirect
)
variables["oidc_sso_enabled"] = oidc_sso_enabled
```

---

## Template Implementation

### Step 1: Create Client Secret Template

**File:** `templates/config/kubernetes/apps/network/envoy-gateway/app/secret-oidc.sops.yaml.j2`

```yaml
#% if oidc_sso_enabled %#
---
apiVersion: v1
kind: Secret
metadata:
  name: oidc-client-secret
  namespace: network
type: Opaque
stringData:
  client-secret: "#{ oidc_client_secret }#"
#% endif %#
```

### Step 2: Create OIDC SecurityPolicy Template

**File:** `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-oidc.yaml.j2`

```yaml
#% if oidc_sso_enabled %#
---
# SecurityPolicy for OIDC-based Web SSO authentication
# REF: https://gateway.envoyproxy.io/docs/tasks/security/oidc/
# REF: docs/guides/native-oidc-securitypolicy-implementation.md
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: oidc-sso
  namespace: network
spec:
  # Target HTTPRoutes with the security: oidc-protected label
  # NOTE: SecurityPolicy can only target resources in the same namespace
  targetSelectors:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      matchLabels:
        security: oidc-protected
  oidc:
    provider:
      issuer: "#{ oidc_issuer_url }#"
      #% if oidc_authorization_endpoint is defined %#
      authorizationEndpoint: "#{ oidc_authorization_endpoint }#"
      #% endif %#
      #% if oidc_token_endpoint is defined %#
      tokenEndpoint: "#{ oidc_token_endpoint }#"
      #% endif %#
    clientID: "#{ oidc_client_id }#"
    clientSecret:
      name: oidc-client-secret
    #| redirectURL is OPTIONAL - omit for dynamic redirect (recommended)       #|
    #| If omitted, Envoy Gateway uses: %REQ(:authority)%/oauth2/callback        #|
    #| IMPORTANT: Wildcards (*.domain.com) are NOT supported in redirectURL!    #|
    #% if oidc_redirect_url is defined and oidc_redirect_url and '*' not in oidc_redirect_url %#
    redirectURL: "#{ oidc_redirect_url }#"
    #% endif %#
    logoutPath: "#{ oidc_logout_path | default('/logout') }#"
    #% if oidc_cookie_domain is defined %#
    cookieDomain: "#{ oidc_cookie_domain }#"
    #% endif %#
    scopes:
    #% for scope in oidc_scopes | default(['openid', 'profile', 'email']) %#
      - "#{ scope }#"
    #% endfor %#
    # Forward user info to backend via headers
    forwardAccessToken: true
#% endif %#
```

### Step 3: Update Kustomization

**Edit:** `templates/config/kubernetes/apps/network/envoy-gateway/app/kustomization.yaml.j2`

Add the new resources:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./envoy.yaml
  - ./certificate.yaml
  - ./podmonitor.yaml
  - ./pdb.yaml
#% if oidc_enabled %#
  - ./securitypolicy-jwt.yaml
#% endif %#
#% if oidc_sso_enabled %#
  - ./secret-oidc.sops.yaml
  - ./securitypolicy-oidc.yaml
#% endif %#
```

---

## Usage

### Protecting HTTPRoutes

Add the `security: oidc-protected` label to any HTTPRoute that should require OIDC authentication:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-web-app
  namespace: network
  labels:
    security: oidc-protected  # Triggers OIDC SecurityPolicy
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "app.${SECRET_DOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-web-app
          port: 8080
```

### OAuth2 Callback Route

The HTTPRoute must include the OAuth2 callback path. Either:

1. Use a PathPrefix that includes `/oauth2/callback`:
   ```yaml
   - path:
       type: PathPrefix
       value: /
   ```

2. Or explicitly add a callback rule:
   ```yaml
   - matches:
       - path:
           type: Exact
           value: /oauth2/callback
     backendRefs:
       - name: my-web-app
         port: 8080
   ```

---

## OIDC Provider Configuration

### Keycloak Setup

1. Create a new client in your realm
2. Configure client settings:
   - **Client ID:** Match `oidc_client_id`
   - **Client Authentication:** ON (confidential)
   - **Valid Redirect URIs:** Use wildcard `https://*.matherly.net/oauth2/callback` (Keycloak supports wildcards)
   - **Web Origins:** Your application domain (wildcard supported: `https://*.matherly.net`)

3. Copy client secret to `oidc_client_secret`

### Example cluster.yaml Configuration

```yaml
# OIDC Web SSO Configuration
oidc_sso_enabled: true
oidc_issuer_url: "https://auth.matherly.net/realms/matherlynet"
oidc_client_id: "envoy-gateway"
oidc_client_secret: "ENC[AES256_GCM,...]"  # SOPS encrypted
# oidc_redirect_url: OMIT for dynamic redirect (RECOMMENDED)
# IMPORTANT: Do NOT use wildcards here - they are NOT supported by Envoy Gateway!
# When omitted, Envoy Gateway automatically uses the request hostname for redirect
oidc_cookie_domain: "matherly.net"  # Enables SSO across all *.matherly.net apps
oidc_logout_path: "/logout"
oidc_scopes:
  - openid
  - profile
  - email
  - groups
```

---

## Self-Signed Certificates

For OIDC providers with self-signed certificates:

### Step 1: Create Backend Resource

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: oidc-provider
  namespace: network
spec:
  endpoints:
    - fqdn:
        hostname: auth.example.com
        port: 443
```

### Step 2: Create BackendTLSPolicy

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: BackendTLSPolicy
metadata:
  name: oidc-tls
  namespace: network
spec:
  targetRefs:
    - group: gateway.envoyproxy.io
      kind: Backend
      name: oidc-provider
  validation:
    caCertificateRefs:
      - group: ""
        kind: ConfigMap
        name: oidc-ca-cert
    hostname: auth.example.com
```

### Step 3: Update SecurityPolicy

Add `backendRefs` to the OIDC provider configuration:

```yaml
oidc:
  provider:
    issuer: "https://auth.example.com/realms/myrealm"
    backendRefs:
      - name: oidc-provider
        namespace: network
        group: gateway.envoyproxy.io
        kind: Backend
```

---

## Deployment

```bash
# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "feat: add OIDC Web SSO SecurityPolicy for browser authentication"
git push

# Reconcile
task reconcile

# Verify SecurityPolicy
kubectl get securitypolicy -n network
kubectl describe securitypolicy oidc-sso -n network
```

---

## Verification

### Test Authentication Flow

1. **Access protected route without session:**
   ```bash
   curl -v https://app.matherly.net/
   # Should redirect to OIDC provider login page (302)
   ```

2. **Complete login in browser:**
   - Navigate to protected URL
   - Should redirect to Keycloak login
   - After login, redirected back to application

3. **Verify session cookie:**
   ```bash
   # Check browser cookies for the domain
   # Should see session cookie from Envoy Gateway
   ```

4. **Test logout:**
   ```bash
   curl -v https://app.matherly.net/logout
   # Should clear session and redirect to IdP logout
   ```

### Debug Commands

```bash
# Check SecurityPolicy status
kubectl describe securitypolicy oidc-sso -n network

# View Envoy logs for auth events
kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-internal -c envoy | grep -i oauth

# Test OIDC discovery endpoint
curl https://auth.matherly.net/realms/matherlynet/.well-known/openid-configuration
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| Redirect loop | Cookie domain mismatch | Verify `cookieDomain` matches application domain |
| 403 after login | Client secret incorrect | Regenerate secret in IdP, update cluster.yaml |
| Callback not found | HTTPRoute missing callback path | Ensure route matches `/oauth2/callback` |
| Session not persisting | Cookie cleared | Clear browser cookies, check `cookieDomain` |
| JWKS fetch failed | Network/TLS issue | Check Backend and BackendTLSPolicy for self-signed certs |

---

## Advanced: Combining OIDC and JWT

You can use both OIDC (for web browsers) and JWT (for APIs) on the same application by:

1. Using different labels:
   - `security: oidc-protected` for web routes
   - `security: jwt-protected` for API routes

2. Using different route paths:
   - `/` - OIDC protected (web UI)
   - `/api/*` - JWT protected (API endpoints)

3. Using header-based bypass (v1.5.0+):
   - OIDC can be configured to bypass when `Authorization: Bearer` header is present
   - Defers to JWT validation for API requests

---

## References

### External Documentation
- [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)
- [SecurityPolicy API Reference](https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/)
- [Release Notes v1.6.1](https://docs.tetrate.io/envoy-gateway/release-announcement)

### Project Documentation
- [Envoy Gateway Observability & Security](./envoy-gateway-observability-security.md) - JWT SecurityPolicy (Phase 2)
- [OIDC Integration Research](../research/envoy-gateway-oidc-integration.md) - Research analysis

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-07 | Schema validation and JSON schema generator fixes |
| 2026-01 | Initial implementation guide created |
