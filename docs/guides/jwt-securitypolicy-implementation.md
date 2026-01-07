# JWT SecurityPolicy Implementation Guide

> **Created:** January 2026
> **Status:** Templates Complete, Configuration Pending
> **Dependencies:** OIDC Provider (Keycloak), Envoy Gateway v1.6.1+
> **Effort:** ~1 hour (excluding OIDC provider setup)

---

## Overview

This guide implements **JWT SecurityPolicy** for API/service-to-service authentication using Envoy Gateway. JWT validation is stateless and ideal for:

- **REST APIs:** Bearer token authentication
- **gRPC services:** Metadata-based token validation
- **Microservice communication:** Service-to-service auth
- **Mobile/SPA backends:** Token-based access

### JWT vs OIDC Authentication

| Feature | JWT SecurityPolicy (This Guide) | OIDC SecurityPolicy |
| ------- | ------------------------------- | ------------------- |
| **Use Case** | API authentication | Web browser SSO |
| **Token Location** | `Authorization: Bearer <token>` | Session cookie |
| **Validation** | JWKS endpoint (stateless) | IdP session check |
| **User Interaction** | None (pre-obtained token) | Required (login form) |
| **Best For** | APIs, microservices | Web applications |

---

## Current Implementation Status

The project already has JWT SecurityPolicy templates:

- **Template:** `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-jwt.yaml.j2`
- **Status:** Complete, pending OIDC provider configuration
- **Activation:** Set `oidc_enabled: true` in cluster.yaml when OIDC provider is deployed

---

## Configuration Variables

### Required Variables (cluster.yaml)

```yaml
# =============================================================================
# OIDC/JWT CONFIGURATION - API authentication via SecurityPolicy
# =============================================================================
# JWT-based authentication for API endpoints, validating tokens against JWKS.
# When configured, creates a SecurityPolicy targeting HTTPRoutes with
# label "security: jwt-protected".
# REF: https://gateway.envoyproxy.io/docs/tasks/security/jwt-authentication/

# -- OIDC provider name (used in SecurityPolicy)
#    (OPTIONAL) / (DEFAULT: "keycloak")
oidc_provider_name: "keycloak"

# -- OIDC issuer URL (JWT token issuer - must match "iss" claim in tokens)
#    (REQUIRED for JWT auth)
#    Example: "https://auth.example.com/realms/myrealm"
oidc_issuer_url: "https://sso.matherly.net/realms/matherlynet"

# -- OIDC JWKS URI for JWT validation (public keys endpoint)
#    (REQUIRED for JWT auth)
#    Example: "https://auth.example.com/realms/myrealm/protocol/openid-connect/certs"
oidc_jwks_uri: "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs"

# -- Additional claims to extract from JWT and pass as headers
#    Headers must start with "X-"
#    (OPTIONAL)
oidc_additional_claims:
  - name: "preferred_username"
    header: "X-Username"
  - name: "realm_access.roles"
    header: "X-User-Roles"
```

### Derived Variables (plugin.py)

The existing `plugin.py` handles enabling:

```python
# OIDC - enabled when issuer and JWKS are both set
oidc_enabled = (
    data.get("oidc_issuer_url") and
    data.get("oidc_jwks_uri")
)
variables["oidc_enabled"] = oidc_enabled
```

---

## Existing Template

**File:** `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-jwt.yaml.j2`

```yaml
#% if oidc_enabled %#
---
# SecurityPolicy for JWT-based API authentication
# REF: https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-auth
  namespace: network
spec:
  # Target HTTPRoutes with the security: jwt-protected label
  targetSelectors:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      matchLabels:
        security: jwt-protected
  jwt:
    providers:
      - name: #{ oidc_provider_name | default('keycloak') }#
        issuer: "#{ oidc_issuer_url }#"
        remoteJWKS:
          uri: "#{ oidc_jwks_uri }#"
          cacheDuration: 300s
        claimToHeaders:
          - claim: sub
            header: X-User-ID
          - claim: email
            header: X-User-Email
          - claim: groups
            header: X-User-Groups
          #% if oidc_additional_claims is defined %#
          #% for claim in oidc_additional_claims %#
          - claim: #{ claim.name }#
            header: #{ claim.header }#
          #% endfor %#
          #% endif %#
#% endif %#
```

---

## Usage

### Protecting HTTPRoutes

Add the `security: jwt-protected` label to any HTTPRoute requiring JWT authentication:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-api
  namespace: default
  labels:
    security: jwt-protected  # Triggers JWT validation
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "api.${SECRET_DOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: my-api-service
          port: 8080
```

### Backend Header Access

After JWT validation, your backend receives these headers:

| Header | Claim Source | Example Value |
| ------ | ------------ | ------------- |
| `X-User-ID` | `sub` | `user-uuid-123` |
| `X-User-Email` | `email` | `user@example.com` |
| `X-User-Groups` | `groups` | `admin,users` |
| Custom headers | Via `oidc_additional_claims` | Configurable |

---

## OIDC Provider Setup

### Keycloak Configuration

1. **Create Realm:** `matherlynet` (or your realm name)

2. **Create Client:**
   - **Client ID:** `api-clients` (for API consumers)
   - **Client Authentication:** OFF (public client for JWT)
   - **Direct Access Grants:** ON (for testing)

3. **Configure Token Claims:**
   - Add "groups" mapper to include user groups
   - Add any custom mappers for additional claims

4. **Note Endpoints:**
   - **Issuer URL:** `https://sso.matherly.net/realms/matherlynet`
   - **JWKS URI:** `https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs`

### Test Token Generation

```bash
# Get a test token (password grant - for testing only)
TOKEN=$(curl -s -X POST \
  "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=api-clients" \
  -d "username=testuser" \
  -d "password=testpass" | jq -r '.access_token')

# Verify token claims
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq
```

---

## Deployment

### Step 1: Configure cluster.yaml

```yaml
# JWT Authentication Configuration
oidc_provider_name: "keycloak"
oidc_issuer_url: "https://sso.matherly.net/realms/matherlynet"
oidc_jwks_uri: "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs"
oidc_additional_claims:
  - name: "preferred_username"
    header: "X-Username"
```

### Step 2: Regenerate and Deploy

```bash
# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "feat: enable JWT SecurityPolicy for API authentication"
git push

# Reconcile
task reconcile

# Verify SecurityPolicy
kubectl get securitypolicy -n network
kubectl describe securitypolicy jwt-auth -n network
```

---

## Verification

### Test Without Token (Should Fail)

```bash
curl -v https://api.matherly.net/api/protected
# Expected: 401 Unauthorized
```

### Test With Valid Token

```bash
curl -v https://api.matherly.net/api/protected \
  -H "Authorization: Bearer $TOKEN"
# Expected: 200 OK (if backend allows)
```

### Test With Invalid Token

```bash
curl -v https://api.matherly.net/api/protected \
  -H "Authorization: Bearer invalid-token"
# Expected: 401 Unauthorized
```

### Verify Headers in Backend

In your backend application, log incoming headers:

```python
# Python/Flask example
@app.route('/api/protected')
def protected():
    user_id = request.headers.get('X-User-ID')
    email = request.headers.get('X-User-Email')
    groups = request.headers.get('X-User-Groups')
    return jsonify({'user_id': user_id, 'email': email, 'groups': groups})
```

---

## Advanced Configuration

### JWT Claim-Based Authorization

Envoy Gateway 1.2+ supports authorization based on JWT claims:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-auth-with-authz
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
  authorization:
    rules:
      - action: Allow
        principal:
          jwt:
            provider: keycloak
            scopes: ["api:read"]
            claims:
              - name: groups
                values: ["admin", "api-users"]
```

### Multiple JWT Providers

Support tokens from multiple IdPs:

```yaml
jwt:
  providers:
    - name: keycloak
      issuer: "https://sso.matherly.net/realms/matherlynet"
      remoteJWKS:
        uri: "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs"
    - name: auth0
      issuer: "https://your-tenant.auth0.com/"
      remoteJWKS:
        uri: "https://your-tenant.auth0.com/.well-known/jwks.json"
```

### JWKS Caching

Adjust cache duration for performance vs freshness:

```yaml
remoteJWKS:
  uri: "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs"
  cacheDuration: 300s  # 5 minutes (default)
  # Use shorter duration if keys rotate frequently
  # Use longer duration for better performance
```

### Route Rerouting with JWT Claims

Use `recomputeRoute: true` to route based on claims:

```yaml
jwt:
  providers:
    - name: keycloak
      issuer: "https://sso.matherly.net/realms/matherlynet"
      remoteJWKS:
        uri: "https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs"
      recomputeRoute: true
      claimToHeaders:
        - claim: user_tier
          header: x-user-tier
```

Then route based on the header:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  rules:
    - matches:
        - headers:
            - name: x-user-tier
              value: premium
      backendRefs:
        - name: premium-backend
    - matches:
        - headers:
            - name: x-user-tier
              value: free
      backendRefs:
        - name: free-backend
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| 401 on all requests | JWKS fetch failed | Check network access to JWKS endpoint |
| 403 after valid token | Issuer mismatch | Verify `iss` claim matches `issuer` config |
| Claims not in headers | Wrong claim path | Check claim names in token match config |
| Stale JWKS | Cache not refreshed | Wait for `cacheDuration` or restart Envoy |
| Token expired | Short-lived token | Refresh token or increase token lifetime |

### Debug Commands

```bash
# Check SecurityPolicy status
kubectl describe securitypolicy jwt-auth -n network

# Test JWKS endpoint accessibility
kubectl run curl-test --rm -it --image=curlimages/curl -- \
  curl -v https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs

# View Envoy logs for auth events
kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-internal -c envoy | grep -i jwt

# Decode JWT token locally
echo "$TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq
```

---

## Security Considerations

### Token Validation

- **Always use HTTPS** for JWKS endpoint
- **Verify issuer** matches expected IdP
- **Check audience** claim if using multiple clients
- **Validate token expiration** (handled automatically by Envoy)

### JWKS Security

- **Cache appropriately:** Short cache = more requests, fresher keys
- **Monitor JWKS errors:** Log failures to detect IdP issues
- **Rotate keys:** Follow IdP key rotation procedures

### Header Security

- **Strip upstream headers:** Ensure backends don't trust headers from clients
- **Use unique header names:** Avoid collision with existing headers
- **Log access:** Track who accessed what APIs

---

## References

### External Documentation
- [Envoy Gateway JWT Authentication](https://gateway.envoyproxy.io/docs/tasks/security/jwt-authentication/)
- [JWT Claim-Based Authorization](https://gateway.envoyproxy.io/docs/tasks/security/jwt-claim-authorization/)
- [SecurityPolicy API Reference](https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/)

### Project Documentation
- [Envoy Gateway Observability & Security](./envoy-gateway-observability-security.md) - Phase 2 implementation
- [Native OIDC SecurityPolicy](./native-oidc-securitypolicy-implementation.md) - Web SSO alternative

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial implementation guide created |
| 2026-01-03 | Template implemented in project |
