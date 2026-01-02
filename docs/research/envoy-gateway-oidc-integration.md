# Envoy Gateway OIDC/OAuth2 Integration Research

> **Research Date:** 2026-01-01
> **Status:** Research Complete - Ready for Implementation Planning
> **Priority:** High - Native Integration Approach Recommended

## Executive Summary

This document analyzes integration strategies for adding OIDC/OAuth2 authentication to the matherlynet-talos-cluster via Envoy Gateway. After evaluating multiple approaches, **Envoy Gateway's native SecurityPolicy OIDC** emerges as the recommended solution for seamless, "native-feeling" integration with the existing cluster architecture.

### Key Finding

Envoy Gateway (already deployed in this cluster) natively supports OIDC authentication via the `SecurityPolicy` CRD. This eliminates the need for external proxies like OAuth2-Proxy and provides a cleaner, more maintainable architecture.

---

## Table of Contents

1. [Current Cluster Architecture](#current-cluster-architecture)
2. [Integration Approaches Evaluated](#integration-approaches-evaluated)
3. [Approach 1: Native SecurityPolicy OIDC (Recommended)](#approach-1-native-securitypolicy-oidc-recommended)
4. [Approach 2: SecurityPolicy ext_authz with OAuth2-Proxy](#approach-2-securitypolicy-ext_authz-with-oauth2-proxy)
5. [Approach 3: SecurityPolicy ext_authz with Authelia](#approach-3-securitypolicy-ext_authz-with-authelia)
6. [Comparison Matrix](#comparison-matrix)
7. [Implementation Recommendations](#implementation-recommendations)
8. [Template Integration Patterns](#template-integration-patterns)
9. [References](#references)

---

## Current Cluster Architecture

### Existing Envoy Gateway Setup

The cluster already has a mature Envoy Gateway deployment:

```
kubernetes/apps/network/envoy-gateway/
├── ks.yaml.j2
└── app/
    ├── helmrelease.yaml.j2     # Envoy Gateway Helm deployment
    ├── envoy.yaml.j2           # Gateway, GatewayClass, policies
    ├── certificate.yaml.j2     # Wildcard TLS certificate
    ├── kustomization.yaml.j2
    └── ocirepository.yaml.j2
```

**Key Components Already Configured:**

| Component | Status | Details |
| ----------- | -------- | --------- |
| `GatewayClass` | ✅ Deployed | `envoy` class with custom EnvoyProxy |
| `Gateway (external)` | ✅ Deployed | HTTPS on port 443, wildcard TLS |
| `Gateway (internal)` | ✅ Deployed | HTTPS on port 443, wildcard TLS |
| `ClientTrafficPolicy` | ✅ Deployed | Client IP detection, HTTP/2, TLS 1.2+ |
| `BackendTrafficPolicy` | ✅ Deployed | Compression, timeouts, keepalive |
| `HTTPRoute (redirect)` | ✅ Deployed | HTTP→HTTPS redirect |
| Wildcard Certificate | ✅ Deployed | `*.${SECRET_DOMAIN}` via cert-manager |

**Template Variables Available:**
- `#{ cloudflare_domain }#` → Domain name
- `#{ cloudflare_gateway_addr }#` → External gateway LoadBalancer IP
- `#{ cluster_gateway_addr }#` → Internal gateway LoadBalancer IP
- `#{ cluster_pod_cidr }#` → Pod network for client IP detection

---

## Integration Approaches Evaluated

### Summary

| Approach | Complexity | Native Feel | Maintenance | Flexibility |
| ---------- | ---------- | ----------- | ----------- | ----------- |
| SecurityPolicy OIDC | Low | ⭐⭐⭐⭐⭐ | Low | Medium |
| ext_authz + OAuth2-Proxy | Medium | ⭐⭐⭐ | Medium | High |
| ext_authz + Authelia | Medium-High | ⭐⭐⭐⭐ | Medium | Very High |

---

## Approach 1: Native SecurityPolicy OIDC (Recommended)

### Overview

Envoy Gateway's built-in OIDC support via `SecurityPolicy` provides authentication without additional components. The OIDC filter runs directly in the Envoy proxy.

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           OIDC Authentication Flow                          │
└─────────────────────────────────────────────────────────────────────────────┘

  User                 Envoy Gateway            OIDC Provider        Backend
   │                        │                        │                  │
   │── GET /app ──────────►│                        │                  │
   │                        │ (no session cookie)   │                  │
   │◄─ 302 Redirect ───────│                        │                  │
   │                        │                        │                  │
   │── GET /authorize ─────────────────────────────►│                  │
   │                        │                        │                  │
   │◄─ Login Page ─────────────────────────────────│                  │
   │                        │                        │                  │
   │── POST credentials ───────────────────────────►│                  │
   │                        │                        │                  │
   │◄─ 302 + code ─────────────────────────────────│                  │
   │                        │                        │                  │
   │── GET /callback?code= ►│                        │                  │
   │                        │── POST /token ────────►│                  │
   │                        │◄─ id_token ───────────│                  │
   │                        │                        │                  │
   │◄─ 302 + cookies ──────│                        │                  │
   │                        │                        │                  │
   │── GET /app + cookies ─►│                        │                  │
   │                        │── (validated) ───────────────────────────►│
   │                        │◄──────────────────────────────────────────│
   │◄─ Response ───────────│                        │                  │
   │                        │                        │                  │
```

### Configuration Template

```yaml
# templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-oidc.yaml.j2
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: oidc-auth
  namespace: network
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: envoy-internal  # or envoy-external
  oidc:
    provider:
      issuer: "https://auth.#{ cloudflare_domain }#/realms/matherlynet"
      # For self-hosted OIDC with self-signed certs, add:
      # authorizationEndpoint: "https://..."
      # tokenEndpoint: "https://..."
      # backendRefs:
      #   - group: gateway.envoyproxy.io
      #     kind: Backend
      #     name: oidc-provider
    clientID: "envoy-gateway"
    clientSecret:
      name: oidc-client-secret
    redirectURL: "https://internal.#{ cloudflare_domain }#/oauth2/callback"
    logoutPath: "/oauth2/logout"
    cookieDomain: "#{ cloudflare_domain }#"  # Share across subdomains
```

### Secret Template

```yaml
# templates/config/kubernetes/apps/network/envoy-gateway/app/secret-oidc.sops.yaml.j2
---
apiVersion: v1
kind: Secret
metadata:
  name: oidc-client-secret
  namespace: network
type: Opaque
stringData:
  client-secret: "#{ oidc_client_secret }#"
```

### Targeting Patterns

**Gateway-level (protect all routes):**
```yaml
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: envoy-internal
```

**HTTPRoute-level (protect specific routes):**
```yaml
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: admin-dashboard
```

### Advantages

- **Zero additional deployments** - Uses existing Envoy Gateway
- **Native Kubernetes resources** - Follows established patterns
- **Session management built-in** - Cookies handled automatically
- **Subdomain cookie sharing** - `cookieDomain` enables SSO across apps
- **Works with any OIDC provider** - Keycloak, Auth0, Azure AD, Google, Okta
- **Consistent with project template structure**

### Limitations

- **Per-Gateway or per-Route only** - Cannot mix auth/no-auth on same route path
- **Limited claim extraction** - Cannot easily pass user claims to backends
- **No fine-grained authorization** - Pure authentication, no RBAC

---

## Approach 2: SecurityPolicy ext_authz with OAuth2-Proxy

### Overview

Deploy OAuth2-Proxy as a dedicated authentication service, with Envoy Gateway delegating auth decisions via the `ext_authz` filter.

### Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        ext_authz Authentication Flow                         │
└──────────────────────────────────────────────────────────────────────────────┘

  User              Envoy Gateway         OAuth2-Proxy       OIDC Provider
   │                     │                     │                   │
   │── Request ─────────►│                     │                   │
   │                     │── Check ───────────►│                   │
   │                     │                     │ (no session)      │
   │                     │◄─ 302 to IdP ──────│                   │
   │◄─ 302 ─────────────│                     │                   │
   │                     │                     │                   │
   │── Authenticate ───────────────────────────────────────────────►│
   │◄─ Callback ───────────────────────────────────────────────────│
   │                     │                     │                   │
   │── Callback ────────►│── Check ───────────►│                   │
   │                     │                     │── Token ─────────►│
   │                     │                     │◄─ JWT ───────────│
   │                     │◄─ 200 + Headers ───│                   │
   │                     │                     │                   │
   │◄─ Response + Cookies─│                     │                   │
   │                     │                     │                   │
```

### OAuth2-Proxy Deployment Template

```yaml
# templates/config/kubernetes/apps/auth/oauth2-proxy/app/helmrelease.yaml.j2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: oauth2-proxy
  namespace: auth
spec:
  chartRef:
    kind: OCIRepository
    name: oauth2-proxy
  interval: 1h
  values:
    config:
      clientID: "#{ oidc_client_id }#"
      clientSecret: "#{ oidc_client_secret }#"
      cookieSecret: "#{ oauth2_proxy_cookie_secret }#"
    extraArgs:
      provider: oidc
      oidc-issuer-url: "https://auth.#{ cloudflare_domain }#/realms/matherlynet"
      upstream: static://200  # Auth-only mode
      cookie-domain: ".#{ cloudflare_domain }#"
      cookie-secure: "true"
      cookie-samesite: lax
      set-xauthrequest: "true"  # Pass user info in headers
      set-authorization-header: "true"
      pass-access-token: "true"
      email-domain: "*"
      skip-provider-button: "true"
    service:
      type: ClusterIP
```

### SecurityPolicy for ext_authz

```yaml
# templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-extauth.yaml.j2
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: oauth2-proxy-auth
  namespace: network
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: envoy-internal
  extAuth:
    http:
      backendRefs:
        - name: oauth2-proxy
          namespace: auth
          port: 4180
      headersToBackend:
        - X-Auth-Request-User
        - X-Auth-Request-Email
        - X-Auth-Request-Groups
        - Authorization
    failOpen: false
```

### ReferenceGrant for Cross-Namespace Access

```yaml
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-extauth-from-network
  namespace: auth
spec:
  from:
    - group: gateway.envoyproxy.io
      kind: SecurityPolicy
      namespace: network
  to:
    - group: ""
      kind: Service
      name: oauth2-proxy
```

### Advantages

- **Rich header forwarding** - User info passed to backends
- **Flexible authentication** - OAuth2-Proxy supports 15+ providers
- **Group-based access control** - Restrict by OIDC groups
- **Mature, well-documented** - Large community

### Limitations

- **Additional deployment** - Requires managing OAuth2-Proxy
- **More moving parts** - Potential failure points
- **Redirect handling complexity** - Must configure properly

---

## Approach 3: SecurityPolicy ext_authz with Authelia

### Overview

Authelia provides both authentication AND authorization with multi-factor support, access control policies, and session management.

### Key Differentiators

| Feature | OAuth2-Proxy | Authelia |
| --------- | ---------- | ---------- |
| MFA/2FA | Limited | Full (TOTP, WebAuthn, Duo) |
| Access Policies | Group-based only | Rules engine (domain, user, group, network) |
| Session Portal | No | Yes (user dashboard) |
| Password Reset | No | Yes |
| Registration | Via IdP only | Self-service option |

### SecurityPolicy Configuration

```yaml
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: authelia-auth
  namespace: network
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: envoy-internal
  extAuth:
    headersToExtAuth:
      - accept
      - cookie
      - authorization
      - x-forwarded-proto
      - x-forwarded-host
      - x-forwarded-uri
    failOpen: false
    http:
      backendRefs:
        - name: authelia
          namespace: auth
          port: 80
      path: /api/authz/ext-authz/
      headersToBackend:
        - Remote-User
        - Remote-Groups
        - Remote-Name
        - Remote-Email
```

### When to Choose Authelia

- Need MFA/2FA support
- Complex authorization rules required
- Self-hosted user management preferred
- Multiple authentication methods needed

---

## Comparison Matrix

| Criterion | Native OIDC | OAuth2-Proxy | Authelia |
| ----------- | ------------- | -------------- | ---------- |
| **Deployment Complexity** | None | Low-Medium | Medium |
| **Template Integration** | Excellent | Good | Good |
| **Maintenance Burden** | Minimal | Low | Medium |
| **Provider Flexibility** | Any OIDC | Any OAuth2/OIDC | OIDC + Local |
| **Header Forwarding** | Limited | Full | Full |
| **MFA Support** | Via IdP | Via IdP | Native |
| **Authorization Rules** | None | Group-based | Rich ACL |
| **Self-Signed Cert Support** | Yes (Backend+TLS) | Yes | Yes |
| **Subdomain SSO** | Yes | Yes | Yes |
| **Resource Overhead** | None | ~100Mi RAM | ~200Mi RAM |

---

## Implementation Recommendations

### Recommended Path: Phased Approach

#### Phase 1: Native SecurityPolicy OIDC

**Why start here:**
- Minimal changes to existing cluster
- Validates OIDC provider setup
- Establishes patterns for secrets and policies

**Implementation Steps:**

1. **Add OIDC provider configuration to `cluster.yaml`:**
   ```yaml
   # OIDC Provider Configuration
   oidc_issuer_url: "https://auth.example.com/realms/matherlynet"
   oidc_client_id: "envoy-gateway"
   oidc_client_secret: ""  # Encrypted via SOPS
   ```

2. **Create SecurityPolicy template:**
   ```
   templates/config/kubernetes/apps/network/envoy-gateway/app/
   ├── securitypolicy-oidc.yaml.j2
   └── secret-oidc.sops.yaml.j2
   ```

3. **Update kustomization to include new resources**

4. **Apply to internal gateway first** (lower risk)

5. **Test with a single HTTPRoute before gateway-wide**

#### Phase 2: Evaluate ext_authz (If Needed)

**Triggers for Phase 2:**
- Need to pass user claims to backend services
- Require group-based authorization
- Want unified logout across multiple apps

**Implementation:**
- Deploy OAuth2-Proxy in `auth` namespace
- Create ext_authz SecurityPolicy
- Gradually migrate routes from native OIDC

---

## Template Integration Patterns

### Pattern 1: Global OIDC Protection

Add to Envoy Gateway app for gateway-wide authentication:

```
templates/config/kubernetes/apps/network/envoy-gateway/app/
├── kustomization.yaml.j2  (add new resources)
├── securitypolicy-oidc.yaml.j2
└── secret-oidc.sops.yaml.j2
```

### Pattern 2: Per-Application Authentication

For apps requiring auth, add SecurityPolicy alongside HTTPRoute:

```
templates/config/kubernetes/apps/<namespace>/<app>/app/
├── httproute.yaml.j2
├── securitypolicy.yaml.j2  (targetRef: HTTPRoute)
└── ...
```

### Pattern 3: Shared Authentication Namespace

For ext_authz approaches:

```
templates/config/kubernetes/apps/auth/
├── namespace.yaml.j2
├── kustomization.yaml.j2
├── oauth2-proxy/
│   ├── ks.yaml.j2
│   └── app/
│       ├── helmrelease.yaml.j2
│       ├── secret.sops.yaml.j2
│       └── referencegrant.yaml.j2
```

### Adding Variables to cluster.yaml

```yaml
# cluster.sample.yaml additions

# -- OIDC Provider Configuration
#    (OPTIONAL) / Enable OIDC authentication for protected apps

# -- OIDC Issuer URL (e.g., Keycloak realm, Auth0 domain)
#    (OPTIONAL) / (e.g., "https://auth.example.com/realms/matherlynet")
# oidc_issuer_url: ""

# -- OIDC Client ID for Envoy Gateway
#    (OPTIONAL) / (e.g., "envoy-gateway")
# oidc_client_id: ""

# -- OIDC Client Secret
#    (OPTIONAL) / (NOTE: Will be encrypted via SOPS)
# oidc_client_secret: ""

# -- Cookie domain for SSO across subdomains
#    (OPTIONAL) / (DEFAULT: cloudflare_domain value)
# oidc_cookie_domain: ""
```

---

## References

### Primary Sources

- [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/docs/tasks/security/oidc/) - Official documentation
- [Envoy Gateway External Authorization](https://gateway.envoyproxy.io/docs/tasks/security/ext-auth/) - ext_authz documentation
- [SecurityPolicy Design](https://gateway.envoyproxy.io/contributions/design/security-policy/) - Architecture overview
- [Jimmy Song: Envoy Gateway OIDC Guide](https://jimmysong.io/blog/envoy-gateway-oidc/) - Auth0 implementation example

### OAuth2-Proxy Resources

- [breadnet.co.uk: Kubernetes Native OAuth2-Proxy](https://breadnet.co.uk/kubernetes-native-oauth2-proxy/) - Deployment patterns
- [OAuth2-Proxy + Envoy ext_authz Issue](https://github.com/oauth2-proxy/oauth2-proxy/issues/862) - Integration details
- [Istio + OAuth2-Proxy Guide](https://napo.io/posts/istio-oidc-authn--authz-with-oauth2-proxy/) - Similar patterns

### Authelia Resources

- [Authelia + Envoy Gateway Integration](https://www.authelia.com/integration/kubernetes/envoy/gateway/) - Official integration docs
- [Authelia OpenID Connect](https://www.authelia.com/integration/openid-connect/clients/envoy-gateway/) - OIDC client setup

### Gateway API Resources

- [GEP-1494: HTTP Auth in Gateway API](https://gateway-api.sigs.k8s.io/geps/gep-1494/) - Future standards
- [Keycloak + Envoy Integration](https://www.jbw.codes/blog/Integrating-Keycloak-OIDC-with-Envoy-API-Gateway) - Keycloak patterns

---

## Next Steps

1. **Choose OIDC Provider** - Keycloak, Auth0, or existing IdP
2. **Create Implementation Plan** - Based on chosen approach
3. **Template Development** - Follow patterns above
4. **Testing Strategy** - Start with internal gateway, single route
5. **Documentation** - Update CLAUDE.md with OIDC commands

---

## Appendix: OIDC Provider Considerations

### Self-Hosted Options

| Provider | Complexity | Features | Resource Usage |
| ---------- | ---------- | ---------- | ---------------- |
| **Keycloak** | Medium | Full IdP, LDAP, social login | ~500Mi-1Gi |
| **Authentik** | Medium | Modern UI, self-service | ~300Mi-500Mi |
| **Zitadel** | Low-Medium | Cloud-native, multi-tenant | ~200Mi-400Mi |

### Managed Options

| Provider | Free Tier | Integration |
| ---------- | ---------- | ---------- |
| **Auth0** | 7,500 MAU | Excellent docs |
| **Okta** | 15,000 MAU | Enterprise focus |
| **Azure AD** | Included w/M365 | Microsoft ecosystem |
| **Google** | Unlimited (own users) | Simple setup |

### For This Cluster

Given the GitOps approach and self-hosted nature, **Keycloak** or **Authentik** deployed via Flux would align well with existing patterns. Alternatively, if quick setup is preferred, **Auth0** free tier provides immediate functionality.

---

## Appendix B: January 2026 Updates & Considerations

> **Added:** 2026-01-01 via `/sc:reflect` validation

### Envoy Gateway Version Considerations

#### Breaking Changes: v1.5 → v1.6

| Change | Impact | Action Required |
| ------ | ------ | --------------- |
| **XDS Listener Naming** | EnvoyPatchPolicies break | Migrate before v1.6 (use `XDSNameSchemeV2` flag) |
| **OIDC Token Refresh** | Now automatic via refresh tokens | Can disable if unwanted |
| **Token Encryption** | Optional `DisableTokenEncryption` added | Review security posture |

#### OIDC-Specific Features in v1.5+

- **RP-Initiated Logout**: End session endpoint auto-discovered or configurable
- **OIDC/JWT Bypass**: Defer to JWT when `Authorization: Bearer` header present
- **Secret-based Client ID**: Client ID can now come from Secret (not just inline)

#### Known Issues to Monitor

1. **Endpoint Override Bug** (Fixed in v1.5.6): If specifying `authorizationEndpoint`, you MUST also specify `tokenEndpoint` - otherwise both are ignored
2. **Token Forwarding Limitation** ([Issue #7343](https://github.com/envoyproxy/gateway/issues/7343)): Cannot forward ID token to custom header (October 2025 - check if resolved)

### Gateway API v1.4 - GEP-1494 Now Experimental

**Status Update**: GEP-1494 (HTTP External Auth) achieved **EXPERIMENTAL** status in Gateway API v1.4.0 (October 2025).

**What This Means**:
- Standard `ExternalAuth` filter now available in HTTPRoute
- Uses Envoy's ext_authz protocol (community consensus from KubeCon London 2025)
- Future: A Policy object for Gateway/HTTPRoute-level auth targeting

**Implication for This Cluster**:
- Current approach using Envoy Gateway's SecurityPolicy remains valid
- Future option: Migrate to portable Gateway API `ExternalAuth` filter when it stabilizes

### OIDC Provider Updates

#### Keycloak Deployment Changes (Critical)

| Provider | Status | Recommendation |
| -------- | ------ | -------------- |
| **Bitnami Helm Charts** | ⚠️ Requires subscription (Aug 2025) | Avoid for new deployments |
| **Official Keycloak Operator** | ✅ Recommended | Use OLM or kubectl install |
| **Community Helm Chart** | ✅ Available | From Artifact Hub |
| **EPAM EDP Operator** | ✅ Alternative | Helm-based operator |

**Action**: Do NOT use `bitnami/keycloak` - images no longer receive public security updates.

#### Authentik with FluxCD

Authentik has mature Flux/GitOps integration:
- Official Helm chart at `charts.goauthentik.io`
- Use `valuesFrom` for secret injection
- Requires PostgreSQL (deploy separately or use operator)

Reference: [Setting up Authentik with FluxCD](https://timvw.be/2025/03/17/setting-up-authentik-with-kubernetes-and-fluxcd/)

### OAuth2-Proxy Security Updates

**CVE-2025-64484** (Security Advisory): Review and update if using OAuth2-Proxy.

**Session Validation Change**:
- Now uses `access_token` (not `id_token`) for validating refreshed sessions
- Aligns with OIDC specification
- Future releases may remove `id_token` validation entirely

### JWT Claims to Headers (Native Alternative)

For backends needing user claims, Envoy Gateway now supports **JWT claim-to-header injection**:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-claims-injection
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: backend
  jwt:
    providers:
      - name: keycloak
        issuer: "https://auth.example.com/realms/matherlynet"
        remoteJWKS:
          uri: "https://auth.example.com/realms/matherlynet/protocol/openid-connect/certs"
        claimToHeaders:
          - claim: sub
            header: X-User-ID
          - claim: email
            header: X-User-Email
          - claim: groups
            header: X-User-Groups
```

**When to Use This Instead of OAuth2-Proxy**:
- Only need specific claims forwarded (not full token)
- Want to avoid additional deployment
- JWT validation is sufficient (no session management needed)

### Scope-Based Authorization

Envoy Gateway supports **JWT scope-based authorization**:

```yaml
authorization:
  defaultAction: Deny
  rules:
    - name: "require-read-scope"
      action: Allow
      principal:
        jwt:
          provider: keycloak
          scopes: ["read", "api:access"]
          claims:
            - name: realm_access.roles
              valueType: StringArray
              values: ["user", "admin"]
```

This enables RBAC without external auth services.

### Updated Recommendation Matrix

| Need | 2025 Recommendation | 2026 Recommendation |
| ---- | ------------------- | ------------------- |
| **Simple auth, any OIDC** | SecurityPolicy OIDC | SecurityPolicy OIDC ✅ |
| **Claims to backends** | OAuth2-Proxy ext_authz | **JWT claimToHeaders** (native) |
| **Scope-based RBAC** | OAuth2-Proxy groups | **JWT authorization rules** (native) |
| **MFA required** | Authelia | Authelia (or IdP-based MFA) |
| **Complex ACLs** | Authelia | Authelia |

### Pre-Implementation Checklist (Updated)

- [ ] Verify Envoy Gateway version (recommend v1.5.6+ for OIDC fixes)
- [ ] Check for `XDSNameSchemeV2` migration if using EnvoyPatchPolicy
- [ ] Avoid Bitnami Keycloak images - use official operator or community charts
- [ ] Consider JWT claimToHeaders before adding OAuth2-Proxy
- [ ] Review OAuth2-Proxy CVE-2025-64484 if using that approach
- [ ] Test OIDC endpoint override behavior (both endpoints required if either specified)
