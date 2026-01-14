# OAuth2-Proxy External Authorization Implementation Guide

> **Created:** January 2026
> **Status:** Implementation Ready
> **Dependencies:** OAuth2-Proxy, OIDC Provider (Keycloak), Envoy Gateway v1.6.1+
> **Effort:** ~3-4 hours

---

## Overview

This guide implements **OAuth2-Proxy with ext_authz** for Envoy Gateway. This approach provides:

- **Claims forwarding to backends:** OAuth2-Proxy extracts user claims and forwards them as headers
- **Fine-grained authorization:** Authorization decisions based on user groups, roles, or custom claims
- **Session management:** OAuth2-Proxy handles session cookies and token refresh
- **Multi-backend support:** Single OAuth2-Proxy instance can protect multiple applications

### When to Use OAuth2-Proxy vs Native OIDC

| Feature | OAuth2-Proxy ext_authz (This Guide) | Native OIDC SecurityPolicy |
| ------- | ----------------------------------- | -------------------------- |
| **Claims to headers** | Full control over header mapping | Limited to `forwardAccessToken` |
| **Group/role filtering** | Advanced `--allowed-groups` rules | Requires JWT claim authorization |
| **Token refresh** | Automatic background refresh | Limited control |
| **Complexity** | Higher (separate deployment) | Lower (built-in) |
| **Best for** | Complex authorization requirements | Simple SSO needs |

---

## Architecture

```
User Request → Envoy Gateway → ext_authz (OAuth2-Proxy) → Decision
                                    ↓
                            If not authenticated → Redirect to IdP
                            If authenticated → Allow + Add Headers
                                    ↓
                            Backend receives X-Auth-* headers
```

---

## Configuration Variables

### cluster.yaml Variables

```yaml
# =============================================================================
# OAUTH2-PROXY EXTERNAL AUTHORIZATION - Advanced claims forwarding
# =============================================================================
# OAuth2-Proxy provides enhanced OIDC integration with claims-to-headers,
# group-based authorization, and automatic token refresh.
# REF: https://oauth2-proxy.github.io/oauth2-proxy/
# REF: https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/

# -- Enable OAuth2-Proxy external authorization
#    (OPTIONAL) / (DEFAULT: false)
# oauth2_proxy_enabled: false

# -- OIDC provider issuer URL
#    (REQUIRED when oauth2_proxy_enabled: true)
# oauth2_proxy_oidc_issuer: ""

# -- OIDC client ID for OAuth2-Proxy
#    (REQUIRED when oauth2_proxy_enabled: true)
# oauth2_proxy_client_id: ""

# -- OIDC client secret (SOPS-encrypted)
#    (REQUIRED when oauth2_proxy_enabled: true)
# oauth2_proxy_client_secret: ""

# -- Cookie secret for session encryption (32 bytes, base64)
#    Generate with: openssl rand -base64 32
#    (REQUIRED when oauth2_proxy_enabled: true)
# oauth2_proxy_cookie_secret: ""

# -- Cookie domain for session sharing
#    (OPTIONAL) / Example: "example.com"
# oauth2_proxy_cookie_domain: ""

# -- Allowed email domains (empty = all allowed)
#    (OPTIONAL) / Example: ["example.com", "corp.example.com"]
# oauth2_proxy_email_domains: ["*"]

# -- Allowed groups (OIDC groups claim)
#    (OPTIONAL) / Example: ["admin", "developers"]
# oauth2_proxy_allowed_groups: []

# -- OAuth2-Proxy replicas
#    (OPTIONAL) / (DEFAULT: 2)
# oauth2_proxy_replicas: 2

# -- Headers to pass to backend after authentication
#    (OPTIONAL) / (DEFAULT: see below)
# oauth2_proxy_set_headers:
#   - "X-Auth-Request-User"
#   - "X-Auth-Request-Email"
#   - "X-Auth-Request-Groups"
#   - "X-Auth-Request-Preferred-Username"
#   - "Authorization"
```

---

## Template Implementation

### Step 1: Create Directory Structure

```bash
mkdir -p templates/config/kubernetes/apps/network/oauth2-proxy/app
```

### Step 2: Create Namespace Entry

OAuth2-Proxy runs in the `network` namespace alongside Envoy Gateway for low-latency ext_authz calls.

### Step 3: Create OAuth2-Proxy Kustomization

**File:** `templates/config/kubernetes/apps/network/oauth2-proxy/ks.yaml.j2`

```yaml
#% if oauth2_proxy_enabled | default(false) %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: oauth2-proxy
spec:
  interval: 1h
  path: ./kubernetes/apps/network/oauth2-proxy/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: network
  wait: false
#% endif %#
```

**File:** `templates/config/kubernetes/apps/network/oauth2-proxy/app/kustomization.yaml.j2`

```yaml
#% if oauth2_proxy_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./secret.sops.yaml
  - ./securitypolicy-extauth.yaml
#% endif %#
```

### Step 4: Create OCIRepository

**File:** `templates/config/kubernetes/apps/network/oauth2-proxy/app/ocirepository.yaml.j2`

```yaml
#% if oauth2_proxy_enabled | default(false) %#
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: oauth2-proxy
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 7.11.0
  url: oci://ghcr.io/oauth2-proxy/helm-charts/oauth2-proxy
#% endif %#
```

### Step 5: Create HelmRelease

**File:** `templates/config/kubernetes/apps/network/oauth2-proxy/app/helmrelease.yaml.j2`

```yaml
#% if oauth2_proxy_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: oauth2-proxy
spec:
  chartRef:
    kind: OCIRepository
    name: oauth2-proxy
  interval: 1h
  values:
    replicaCount: #{ oauth2_proxy_replicas | default(2) }#

    config:
      clientID: "#{ oauth2_proxy_client_id }#"
      clientSecret: ""  # Use existingSecret instead
      cookieSecret: ""  # Use existingSecret instead

    extraArgs:
      # OIDC Configuration
      provider: oidc
      oidc-issuer-url: "#{ oauth2_proxy_oidc_issuer }#"

      # Cookie Configuration
      cookie-secure: "true"
      cookie-httponly: "true"
      cookie-samesite: "lax"
      #% if oauth2_proxy_cookie_domain is defined %#
      cookie-domain: "#{ oauth2_proxy_cookie_domain }#"
      #% endif %#

      # Email Domain Filtering
      #% if oauth2_proxy_email_domains is defined %#
      email-domain: "#{ oauth2_proxy_email_domains | join(',') }#"
      #% else %#
      email-domain: "*"
      #% endif %#

      # Group-based Authorization
      #% if oauth2_proxy_allowed_groups is defined and oauth2_proxy_allowed_groups | length > 0 %#
      #% for group in oauth2_proxy_allowed_groups %#
      allowed-group: "#{ group }#"
      #% endfor %#
      #% endif %#

      # Header Configuration for ext_authz
      set-xauthrequest: "true"
      set-authorization-header: "true"
      pass-authorization-header: "true"
      pass-access-token: "true"
      pass-user-headers: "true"

      # Reverse Proxy Mode (for ext_authz)
      reverse-proxy: "true"
      real-client-ip-header: "X-Forwarded-For"

      # Skip auth for health endpoints
      skip-auth-regex: "^/health$"

    existingSecret: oauth2-proxy-secrets

    service:
      type: ClusterIP
      port: 4180

    resources:
      requests:
        cpu: 10m
        memory: 64Mi
      limits:
        memory: 128Mi

    metrics:
      enabled: true
      servicemonitor:
        enabled: true

    podDisruptionBudget:
      enabled: true
      minAvailable: 1

    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: oauth2-proxy
              topologyKey: kubernetes.io/hostname
#% endif %#
```

### Step 6: Create Secrets

**File:** `templates/config/kubernetes/apps/network/oauth2-proxy/app/secret.sops.yaml.j2`

```yaml
#% if oauth2_proxy_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secrets
type: Opaque
stringData:
  client-id: "#{ oauth2_proxy_client_id }#"
  client-secret: "#{ oauth2_proxy_client_secret }#"
  cookie-secret: "#{ oauth2_proxy_cookie_secret }#"
#% endif %#
```

### Step 7: Create ext_authz SecurityPolicy

**File:** `templates/config/kubernetes/apps/network/oauth2-proxy/app/securitypolicy-extauth.yaml.j2`

```yaml
#% if oauth2_proxy_enabled | default(false) %#
---
# SecurityPolicy for OAuth2-Proxy external authorization
# REF: https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/
# REF: docs/guides/oauth2-proxy-ext-authz-implementation.md
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: oauth2-proxy-extauth
  namespace: network
spec:
  # Target HTTPRoutes with the security: oauth2-protected label
  targetSelectors:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      matchLabels:
        security: oauth2-protected
  extAuth:
    http:
      backendRefs:
        - name: oauth2-proxy
          namespace: network
          port: 4180
      # Headers to send to OAuth2-Proxy for auth decision
      headersToBackend:
        - Cookie
        - Authorization
        - X-Forwarded-For
        - X-Forwarded-Host
        - X-Forwarded-Proto
        - X-Original-URL
      # Path prefix for auth requests
      path: /oauth2/auth
      # Headers from OAuth2-Proxy response to forward to backend
      headersToExtAuth:
      #% for header in oauth2_proxy_set_headers | default(['X-Auth-Request-User', 'X-Auth-Request-Email', 'X-Auth-Request-Groups', 'X-Auth-Request-Preferred-Username', 'Authorization']) %#
        - "#{ header }#"
      #% endfor %#
#% endif %#
```

### Step 8: Update Network Kustomization

**Edit:** `templates/config/kubernetes/apps/network/kustomization.yaml.j2`

Add OAuth2-Proxy to resources:

```yaml
resources:
  - ./namespace.yaml
  - ./envoy-gateway/ks.yaml
  - ./external-dns/ks.yaml
  # ... other entries ...
#% if oauth2_proxy_enabled | default(false) %#
  - ./oauth2-proxy/ks.yaml
#% endif %#
```

---

## Usage

### Protecting HTTPRoutes

Add the `security: oauth2-protected` label:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: network
  labels:
    security: oauth2-protected  # Triggers OAuth2-Proxy ext_authz
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
        - name: my-app
          port: 8080
```

### Backend Header Access

Your backend application receives these headers after authentication:

| Header | Content | Example |
| ------ | ------- | ------- |
| `X-Auth-Request-User` | User ID from IdP | `user123` |
| `X-Auth-Request-Email` | User email | `user@example.com` |
| `X-Auth-Request-Groups` | User groups (comma-separated) | `admin,developers` |
| `X-Auth-Request-Preferred-Username` | Display name | `John Doe` |
| `Authorization` | Bearer token (if `pass-access-token`) | `Bearer eyJ...` |

---

## OIDC Provider Configuration

### Keycloak Setup

1. Create a new client:
   - **Client ID:** Match `oauth2_proxy_client_id`
   - **Client Authentication:** ON
   - **Valid Redirect URIs:** `https://*/oauth2/callback`

2. Configure mappers for groups claim:
   - Add "groups" mapper to include user groups in tokens

3. Copy client secret to `oauth2_proxy_client_secret`

### Example cluster.yaml

```yaml
# OAuth2-Proxy Configuration
oauth2_proxy_enabled: true
oauth2_proxy_oidc_issuer: "https://auth.matherly.net/realms/matherlynet"
oauth2_proxy_client_id: "oauth2-proxy"
oauth2_proxy_client_secret: "ENC[AES256_GCM,...]"
oauth2_proxy_cookie_secret: "ENC[AES256_GCM,...]"  # openssl rand -base64 32
oauth2_proxy_cookie_domain: "matherly.net"
oauth2_proxy_allowed_groups:
  - admin
  - developers
oauth2_proxy_email_domains:
  - "matherly.net"
```

---

## Deployment

```bash
# Generate cookie secret
openssl rand -base64 32

# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "feat: add OAuth2-Proxy ext_authz for advanced OIDC claims forwarding"
git push

# Reconcile
task reconcile

# Verify deployment
kubectl -n network get pods -l app.kubernetes.io/name=oauth2-proxy
kubectl get securitypolicy -n network
```

---

## Verification

### Test Authentication

1. **Access protected route:**
   ```bash
   curl -v https://app.matherly.net/
   # Should redirect to OAuth2-Proxy → IdP login
   ```

2. **Check headers after auth:**
   ```bash
   # In your backend application, log incoming headers
   # Should see X-Auth-Request-* headers
   ```

3. **Test group restriction:**
   - Login as user NOT in allowed groups
   - Should receive 403 Forbidden

### Debug Commands

```bash
# Check OAuth2-Proxy logs
kubectl -n network logs -l app.kubernetes.io/name=oauth2-proxy -f

# Test auth endpoint directly
kubectl -n network port-forward svc/oauth2-proxy 4180:4180
curl -v http://localhost:4180/oauth2/auth

# Check SecurityPolicy status
kubectl describe securitypolicy oauth2-proxy-extauth -n network
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| 401 Unauthorized | ext_authz service unreachable | Check OAuth2-Proxy pods, verify service |
| 403 Forbidden | User not in allowed groups | Check `allowed-group` args, verify IdP groups |
| Redirect loop | Cookie domain mismatch | Verify `cookie-domain` matches app domain |
| Headers missing in backend | `headersToExtAuth` misconfigured | Check SecurityPolicy header configuration |
| Session not persisting | Cookie secret changed | Ensure consistent `cookie-secret` |

---

## Advanced Configuration

### Custom Claim Mapping

For custom claims, use OAuth2-Proxy's `--extra-jwt-issuers` and claim configuration:

```yaml
extraArgs:
  oidc-extra-audience: "my-custom-audience"
  insecure-oidc-skip-issuer-verification: "false"
```

### Multiple Protected Domains

Use `cookie-domain` to share sessions:

```yaml
oauth2_proxy_cookie_domain: "matherly.net"
# Sessions work for app.matherly.net, api.matherly.net, etc.
```

### Health Check Bypass

OAuth2-Proxy automatically skips auth for `/health` via `skip-auth-regex`.

---

## References

### External Documentation
- [OAuth2-Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Envoy Gateway External Authorization](https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/)
- [OAuth2-Proxy Helm Chart](https://github.com/oauth2-proxy/manifests)

### Project Documentation
- [Native OIDC SecurityPolicy](./completed/native-oidc-securitypolicy-implementation.md) - Simpler SSO alternative
- [JWT SecurityPolicy](./envoy-gateway-observability-security.md) - API token validation

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial implementation guide created |
