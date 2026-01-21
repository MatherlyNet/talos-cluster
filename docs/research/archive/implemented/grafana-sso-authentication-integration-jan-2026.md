# Grafana SSO Authentication Integration Research

**Date:** January 2026
**Last Validated:** January 10, 2026
**Grafana Version:** 12.x (via kube-prometheus-stack)
**Envoy Gateway Version:** 0.0.0-latest (for Kubernetes 1.35 support)
**Keycloak Version:** 26.5.0
**Scope:** Seamless SSO for Grafana with OIDC/Keycloak integration and RBAC

> [!NOTE]
> **Status:** ✅ IMPLEMENTATION COMPLETE (January 8, 2026)
>
> **Update (January 10, 2026):** Added `oauth_allow_insecure_email_lookup: true` to handle
> Keycloak recreation scenarios where users receive new subject IDs. This provides resilience
> for self-hosted Keycloak deployments without compromising security.
>
> This research guide has been fully implemented using **Option 3: Gateway OIDC +
> Grafana Native OAuth**. All template files, secrets, schema validation, and
> documentation have been integrated into the project.
>
> **Implementation Details:**
>
> - `grafana_oidc_enabled` and `grafana_oidc_client_secret` variables in cluster.yaml
> - Keycloak OIDC client with realm-roles protocol mapper
> - Grafana `auth.generic_oauth` configuration with JMESPath role mapping
> - SOPS-encrypted client secret management
> - Derived variable logic in plugin.py for conditional enablement
>
> **Role Mapping Adaptation:** The implementation uses existing generic roles
> (`admin`, `operator`, `developer`) instead of Grafana-specific roles, making
> configuration simpler by leveraging the default `keycloak_realm_roles`.
>
> **Configuration:** See `cluster.sample.yaml` lines 440-475 for setup instructions.
>
> [!IMPORTANT]
> **Critical Insight:** The "ideal state" of sharing Envoy Gateway's OIDC session
> directly with Grafana is technically possible via **Option 2 (auth.jwt)** since
> `forwardAccessToken: true` is already configured. Grafana can validate the
> forwarded JWT directly without any redirects.

## Executive Summary

This research document analyzes the optimal approach for securing Grafana with seamless SSO integration, leveraging the existing Keycloak + Envoy Gateway OIDC infrastructure. The goal is to provide users who have already authenticated to other protected applications (Hubble UI, RustFS) with automatic access to Grafana without re-authentication.

### Key Findings

| Approach | SSO Experience | RBAC Support | Implementation Complexity |
| -------- | -------------- | ------------ | ------------------------- |
| **Option 1: Gateway OIDC + Grafana auth.proxy** | Seamless (header-based) | Via Keycloak roles | Medium |
| **Option 2: Gateway OIDC + Grafana auth.jwt** | Seamless (token-based) | Via JWT claims | Medium |
| **Option 3: Gateway OIDC + Grafana Native OAuth** | Near-seamless (auto_login) | Full RBAC + Groups | Medium-High |
| **Option 4: Gateway OIDC Only (current)** | Seamless at gateway | No Grafana RBAC | Already implemented |

### Recommended Approach

**Option 3: Gateway OIDC + Grafana Native OAuth** provides the best balance of:

- Seamless SSO via `auto_login: true` (no Grafana login page shown)
- Full RBAC support with role mapping from Keycloak
- Groups/teams mapping capability
- Consistent with existing project patterns (separate OIDC clients per app)

For simpler deployments, **Option 1 (auth.proxy)** or **Option 2 (auth.jwt)** provides true single-cookie SSO with gateway-forwarded user information.

---

## Table of Contents

1. [Current Architecture Analysis](#current-architecture-analysis)
2. [Authentication Options Deep Dive](#authentication-options-deep-dive)
3. [Option 1: Gateway OIDC + Grafana auth.proxy](#option-1-gateway-oidc--grafana-authproxy)
4. [Option 2: Gateway OIDC + Grafana auth.jwt](#option-2-gateway-oidc--grafana-authjwt)
5. [Option 3: Gateway OIDC + Grafana Native OAuth](#option-3-gateway-oidc--grafana-native-oauth)
6. [RBAC and Role Mapping](#rbac-and-role-mapping)
7. [Implementation Recommendations](#implementation-recommendations)
8. [Security Considerations](#security-considerations)
9. [Testing and Validation](#testing-and-validation)
10. [Sources](#sources)

---

## Current Architecture Analysis

### Existing OIDC Infrastructure

The cluster currently has a fully implemented OIDC SSO infrastructure:

```
User Browser
     |
     v
Envoy Gateway (SecurityPolicy: oidc-sso)
     |
     v (redirect if unauthenticated)
Keycloak Login Page
     |
     +-> Google IdP
     +-> GitHub IdP
     +-> Microsoft Entra ID
     |
     v (after authentication)
Envoy Gateway (stores tokens in cookies)
     |
     v
Backend Service (Hubble UI, Grafana, RustFS)
```

### Current Grafana HTTPRoute Configuration

From `internal-httproutes.yaml.j2`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: network
  labels:
    security: oidc-protected  # Triggers OIDC SecurityPolicy
spec:
  hostnames:
    - "grafana.${SECRET_DOMAIN}"
  parentRefs:
    - name: envoy-internal
      namespace: network
      sectionName: https
  rules:
    - backendRefs:
        - name: kube-prometheus-stack-grafana
          namespace: monitoring
          port: 80
```

### Current SecurityPolicy Configuration

From `securitypolicy-oidc.yaml.j2`:

```yaml
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
      issuer: "https://sso.${SECRET_DOMAIN}/realms/matherlynet"
    clientID: "envoy-gateway"
    clientSecret:
      name: oidc-client-secret
    cookieDomain: ".${SECRET_DOMAIN}"  # Enables cross-subdomain SSO
    scopes:
      - openid
      - profile
      - email
    forwardAccessToken: true  # KEY: Forwards access token to backend
```

### Current State: What Works

| Feature | Status | Notes |
| ------- | ------ | ----- |
| Gateway-level authentication | Working | Users must authenticate via Keycloak |
| Cross-subdomain SSO | Working | Cookie domain enables shared session |
| Social IdP login | Working | Google, GitHub, Microsoft configured |
| Grafana access | Working | Users can access after gateway auth |
| Grafana RBAC | **Not Working** | All users are anonymous/admin |

### The Gap: Grafana User Identity

Currently, Grafana receives requests that have passed gateway authentication, but it doesn't know **who** the user is. The `forwardAccessToken: true` setting forwards the JWT in the `Authorization: Bearer` header, but Grafana isn't configured to read it.

---

## Authentication Options Deep Dive

### How Envoy Gateway OIDC Token Forwarding Works

When `forwardAccessToken: true` is set in the SecurityPolicy:

1. User authenticates via Keycloak
2. Envoy Gateway stores tokens in cookies (`OauthHMAC`, `OauthExpires`, `IdToken`)
3. On subsequent requests, Envoy Gateway validates the cookie
4. If valid, forwards the access token to the backend via `Authorization: Bearer <token>` header

**Key Insight:** The access token is a JWT containing user claims (sub, email, groups, roles) that Grafana can use for authentication.

### Grafana Authentication Methods

Grafana supports multiple authentication mechanisms, each with different SSO and RBAC capabilities:

| Method | Header/Token | SSO Experience | RBAC | OSS Support |
| ------ | ------------ | -------------- | ---- | ----------- |
| `auth.proxy` | `X-WEBAUTH-USER` header | True SSO (no redirect) | Via headers | Yes |
| `auth.jwt` | `Authorization: Bearer` | True SSO (no redirect) | Via JWT claims | Yes |
| `auth.generic_oauth` | OAuth2 flow | Near SSO (`auto_login`) | Full RBAC | Yes |
| Team Sync | N/A | N/A | Groups -> Teams | **Enterprise only** |

---

## Option 1: Gateway OIDC + Grafana auth.proxy

### Overview

Use Envoy Gateway's JWT SecurityPolicy to extract claims from the access token and forward them as headers to Grafana, which then uses `auth.proxy` to authenticate based on those headers.

### Architecture

```
User -> Envoy Gateway (OIDC) -> JWT Validation -> Add Headers -> Grafana (auth.proxy)
              |                      |
              v                      v
         Cookie Auth          X-WEBAUTH-USER: user@example.com
         + Token Forward      X-WEBAUTH-GROUPS: admin,viewer
```

### Implementation Requirements

#### 1. Update SecurityPolicy to Forward Claims as Headers

The existing `securitypolicy-jwt.yaml.j2` already extracts claims to headers:

```yaml
jwt:
  providers:
    - name: keycloak
      issuer: "https://sso.${SECRET_DOMAIN}/realms/matherlynet"
      remoteJWKS:
        uri: "https://sso.${SECRET_DOMAIN}/realms/matherlynet/protocol/openid-connect/certs"
      claimToHeaders:
        - claim: sub
          header: X-User-ID
        - claim: email
          header: X-User-Email
        - claim: groups
          header: X-User-Groups
```

**Issue:** This targets `security: jwt-protected`, not `security: oidc-protected`. We need both OIDC (for browser auth) AND JWT claim extraction.

#### 2. Create Combined SecurityPolicy (OIDC + JWT Claim Extraction)

Envoy Gateway does **not** support combining OIDC and JWT in a single SecurityPolicy. The workaround:

- Use OIDC SecurityPolicy for authentication (creates session cookies)
- Access token is forwarded to backend via `Authorization: Bearer` header
- Grafana validates the JWT itself using `auth.jwt`

#### 3. Configure Grafana auth.proxy

Add to `helmrelease.yaml.j2`:

```yaml
grafana:
  grafana.ini:
    auth.proxy:
      enabled: true
      header_name: X-User-Email
      header_property: email
      auto_sign_up: true
      headers: "Groups:X-User-Groups"
      whitelist: ""  # Trust all (gateway already authenticated)
    auth:
      disable_login_form: true
```

### Pros and Cons

| Pros | Cons |
| ---- | ---- |
| True SSO (no Grafana login page) | Requires separate JWT claim extraction |
| Simple header-based auth | Limited role mapping (no JMESPath) |
| Works with OSS Grafana | Requires careful header security |
| Low latency (no redirect) | Can't use Team Sync (Enterprise) |

### Security Considerations

- **Header Spoofing:** Grafana's `whitelist` setting should restrict to gateway IP
- **Trust Boundary:** Gateway must be the only path to Grafana (no direct access)

---

## Option 2: Gateway OIDC + Grafana auth.jwt

### Overview

Grafana directly validates the JWT access token forwarded by Envoy Gateway, extracting user identity and roles from claims.

### Architecture

```
User -> Envoy Gateway (OIDC) -> Forward Access Token -> Grafana (auth.jwt)
              |                          |
              v                          v
         Cookie Auth              Authorization: Bearer <JWT>
         + Token Forward          Grafana validates JWT via JWKS
```

### Implementation Requirements

#### 1. Enable forwardAccessToken in SecurityPolicy

Already configured in `securitypolicy-oidc.yaml.j2`:

```yaml
oidc:
  forwardAccessToken: true
```

#### 2. Configure Grafana auth.jwt

Add to `helmrelease.yaml.j2`:

```yaml
grafana:
  grafana.ini:
    auth.jwt:
      enabled: true
      header_name: Authorization
      # Keycloak JWKS endpoint for token validation
      jwk_set_url: "https://sso.${SECRET_DOMAIN}/realms/matherlynet/protocol/openid-connect/certs"
      cache_ttl: 60m
      # Claim mappings
      username_claim: preferred_username
      email_claim: email
      # Role mapping from Keycloak roles
      role_attribute_path: "contains(realm_access.roles[*], 'grafana-admin') && 'GrafanaAdmin' || contains(realm_access.roles[*], 'grafana-editor') && 'Editor' || 'Viewer'"
      auto_sign_up: true
      allow_assign_grafana_admin: true
    auth:
      disable_login_form: true
```

#### 3. Configure Keycloak Roles

Add roles to Keycloak realm for Grafana access control:

```yaml
# In cluster.yaml
keycloak_realm_roles:
  - name: grafana-admin
    description: "Grafana Server Administrator"
  - name: grafana-editor
    description: "Grafana Dashboard Editor"
  - name: grafana-viewer
    description: "Grafana Dashboard Viewer"
```

### Pros and Cons

| Pros | Cons |
| ---- | ---- |
| True SSO (no Grafana login page) | Requires Keycloak role configuration |
| Full JMESPath role mapping | JWT must be forwarded correctly |
| Stateless validation | Token expiry handling complexity |
| Works with OSS Grafana | Debugging harder than OAuth |

### JWT Token Structure (Keycloak)

The access token from Keycloak contains:

```json
{
  "sub": "user-uuid",
  "preferred_username": "john.doe",
  "email": "john@example.com",
  "realm_access": {
    "roles": ["grafana-admin", "default-roles-matherlynet"]
  },
  "resource_access": {
    "account": {
      "roles": ["manage-account"]
    }
  }
}
```

---

## Option 3: Gateway OIDC + Grafana Native OAuth

### Overview

Configure Grafana with its own OIDC client in Keycloak. Users are already authenticated at the gateway level (cookie SSO), and Grafana's `auto_login: true` setting automatically redirects to Keycloak, which returns immediately (already authenticated) without showing a login page.

### Architecture

```
User -> Envoy Gateway (OIDC) -> Grafana -> auto_login redirect -> Keycloak (already authenticated) -> Grafana
              |                                                        |
              v                                                        v
         Cookie Auth                                           No login page shown
         (session established)                                 (Keycloak session exists)
```

### Flow Explanation

1. User authenticates to Hubble UI via gateway OIDC
2. Keycloak session established, Envoy cookies set
3. User navigates to Grafana
4. Gateway validates Envoy OIDC cookies - passes
5. Grafana has `auto_login: true` - redirects to Keycloak
6. Keycloak detects existing session - issues tokens immediately
7. Grafana receives tokens - user logged in
8. **Total visible delay: ~200-500ms redirect (no login form)**

### Implementation Requirements

#### 1. Create Grafana OIDC Client in Keycloak

Add to `realm-import.sops.yaml.j2`:

```yaml
clients:
  # ... existing envoy-gateway client ...

  - clientId: "grafana"
    name: "Grafana"
    description: "Grafana dashboard access"
    enabled: true
    publicClient: false
    clientAuthenticatorType: "client-secret"
    secret: "#{ grafana_oidc_client_secret }#"
    standardFlowEnabled: true
    directAccessGrantsEnabled: false
    serviceAccountsEnabled: false
    protocol: "openid-connect"
    redirectUris:
      - "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#/login/generic_oauth"
    webOrigins:
      - "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#"
    defaultClientScopes:
      - "openid"
      - "profile"
      - "email"
      - "roles"  # Include realm roles in token
    optionalClientScopes:
      - "offline_access"
    # Mapper to include realm roles in token
    protocolMappers:
      - name: "realm-roles"
        protocol: "openid-connect"
        protocolMapper: "oidc-usermodel-realm-role-mapper"
        config:
          claim.name: "roles"
          jsonType.label: "String"
          multivalued: "true"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
      - name: "groups"
        protocol: "openid-connect"
        protocolMapper: "oidc-group-membership-mapper"
        config:
          claim.name: "groups"
          full.path: "false"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
```

#### 2. Add Grafana OIDC Secret to cluster.yaml

```yaml
# cluster.yaml (SOPS-encrypted)
grafana_oidc_enabled: true
grafana_oidc_client_secret: "generated-secret-here"
```

#### 3. Update Grafana HelmRelease

Add to `helmrelease.yaml.j2`:

```yaml
grafana:
  grafana.ini:
    server:
      root_url: "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#"

    auth:
      # Disable login form - OAuth only
      disable_login_form: true
      # Disable signout button (handled by gateway)
      disable_signout_menu: false

    auth.generic_oauth:
      enabled: true
      name: "Keycloak"
      allow_sign_up: true
      auto_login: true  # KEY: Automatic redirect to Keycloak

      # OIDC Client Configuration
      client_id: "grafana"
      client_secret: "${GRAFANA_OIDC_SECRET}"  # From secret

      # Keycloak endpoints
      auth_url: "https://#{ keycloak_subdomain | default('auth') }#.#{ cloudflare_domain }#/realms/#{ keycloak_realm | default('matherlynet') }#/protocol/openid-connect/auth"
      token_url: "https://#{ keycloak_subdomain | default('auth') }#.#{ cloudflare_domain }#/realms/#{ keycloak_realm | default('matherlynet') }#/protocol/openid-connect/token"
      api_url: "https://#{ keycloak_subdomain | default('auth') }#.#{ cloudflare_domain }#/realms/#{ keycloak_realm | default('matherlynet') }#/protocol/openid-connect/userinfo"

      # Scopes
      scopes: "openid profile email roles"

      # Claim mappings
      email_attribute_path: email
      login_attribute_path: preferred_username
      name_attribute_path: name

      # Role mapping using JMESPath
      role_attribute_path: "contains(roles[*], 'grafana-admin') && 'GrafanaAdmin' || contains(roles[*], 'grafana-editor') && 'Editor' || 'Viewer'"
      role_attribute_strict: false
      allow_assign_grafana_admin: true

      # Groups for organization mapping (OSS feature)
      groups_attribute_path: groups

      # Token handling
      use_refresh_token: true

      # Skip org role sync if you want to manage roles manually
      # skip_org_role_sync: false

  # Secret containing OIDC client secret
  envFromSecret: grafana-oidc-secret
```

#### 4. Create SOPS-Encrypted Secret

Add `secret-grafana-oidc.sops.yaml.j2`:

```yaml
#% if grafana_oidc_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-oidc-secret
  namespace: #{ observability_namespace | default('monitoring') }#
type: Opaque
stringData:
  GRAFANA_OIDC_SECRET: "#{ grafana_oidc_client_secret }#"
#% endif %#
```

### Pros and Cons

| Pros | Cons |
| ---- | ---- |
| Full RBAC support via JMESPath | Slight redirect delay (~200-500ms) |
| Groups attribute for org mapping | Requires separate OIDC client |
| Refresh token support | More configuration required |
| Standard OAuth2 flow | Two auth layers (gateway + Grafana) |
| Grafana session management | Token sync complexity |
| Works with OSS Grafana | |

### SSO Experience with auto_login

With `auto_login: true`:

1. User visits `https://grafana.matherly.net`
2. Gateway validates OIDC session (from previous Hubble/RustFS login)
3. Grafana detects unauthenticated (no Grafana session)
4. Grafana redirects to Keycloak authorization endpoint
5. Keycloak detects existing session (same `KEYCLOAK_IDENTITY` cookie domain)
6. Keycloak issues authorization code immediately
7. Grafana exchanges code for tokens
8. User is logged in

**Result:** User sees a brief redirect flash but no login form.

---

## RBAC and Role Mapping

### Keycloak Role Configuration

Add to `keycloak_realm_roles` in `cluster.yaml`:

```yaml
keycloak_realm_roles:
  # Existing roles...
  - name: grafana-admin
    description: "Grafana Server Administrator - Full administrative access"
  - name: grafana-editor
    description: "Grafana Editor - Can create and modify dashboards"
  - name: grafana-viewer
    description: "Grafana Viewer - Read-only dashboard access"
```

### Role Mapping Expression (JMESPath)

The `role_attribute_path` uses JMESPath to evaluate roles:

```
contains(roles[*], 'grafana-admin') && 'GrafanaAdmin' ||
contains(roles[*], 'grafana-editor') && 'Editor' ||
'Viewer'
```

This evaluates to:

- `GrafanaAdmin` if user has `grafana-admin` role
- `Editor` if user has `grafana-editor` role
- `Viewer` otherwise (default)

### IdP-Based Role Assignment

Leverage existing IdP mappers from `realm-import.sops.yaml.j2`:

```yaml
# Assign grafana-admin to Google Workspace domain users
google_domain_role_mapping:
  domain: "matherly.net"
  role: "grafana-admin"

# Assign grafana-editor to GitHub org members
github_org_role_mapping:
  org: "my-org"
  role: "grafana-editor"

# Assign grafana-viewer to all Microsoft users
microsoft_default_role: "grafana-viewer"
```

### Organization Mapping (OSS Feature)

Grafana OSS supports organization mapping via `org_mapping`:

```yaml
auth.generic_oauth:
  org_mapping: "grafana-admin:Main Org.:GrafanaAdmin grafana-editor:Main Org.:Editor *:Main Org.:Viewer"
```

### Team Sync Limitation

**Important:** Team Sync (mapping IdP groups to Grafana teams) is **Enterprise only**.

For OSS Grafana, you can:

1. Use organization mapping (org_mapping)
2. Use role-based access control
3. Manually create teams and assign users after login

---

## Implementation Recommendations

### Recommended: Option 3 (Gateway OIDC + Grafana Native OAuth)

This approach is recommended because:

1. **Consistent with project patterns** - Uses OIDC clients like other apps
2. **Full RBAC support** - JMESPath role mapping works
3. **Near-seamless SSO** - `auto_login` minimizes friction
4. **Future-proof** - Can add Team Sync with Enterprise upgrade
5. **Logout handling** - Grafana manages its own session

### Implementation Steps

#### Phase 1: Keycloak Client Setup

1. Add `grafana_oidc_enabled: true` to `cluster.yaml`
2. Generate and add `grafana_oidc_client_secret` (SOPS-encrypted)
3. Add Grafana roles to `keycloak_realm_roles`
4. Update `realm-import.sops.yaml.j2` with Grafana client
5. Run `task configure` to regenerate templates

#### Phase 2: Grafana Configuration

1. Create `secret-grafana-oidc.sops.yaml.j2`
2. Update `helmrelease.yaml.j2` with OAuth configuration
3. Update kustomization to include new secret
4. Run `task configure` and `task reconcile`

#### Phase 3: Testing

1. Clear browser cookies for `*.matherly.net`
2. Login to Hubble UI via social IdP
3. Navigate to Grafana - should auto-login
4. Verify role assignment matches Keycloak roles

### Configuration Variables Summary

Add to `cluster.yaml`:

```yaml
# Grafana OIDC Configuration
grafana_oidc_enabled: true
grafana_oidc_client_secret: "your-generated-secret"  # SOPS-encrypted

# Grafana Roles (add to keycloak_realm_roles)
keycloak_realm_roles:
  - name: grafana-admin
    description: "Grafana Server Administrator"
  - name: grafana-editor
    description: "Grafana Dashboard Editor"
  - name: grafana-viewer
    description: "Grafana Dashboard Viewer"
```

### Alternative: Option 2 (auth.jwt) for Simpler Setup

If you prefer true SSO without any redirect:

1. Keep `forwardAccessToken: true` in OIDC SecurityPolicy
2. Configure Grafana `auth.jwt` with Keycloak JWKS
3. Map roles from `realm_access.roles` claim

This approach is simpler but has less flexibility for role management.

---

## Security Considerations

### Token Security

| Consideration | Mitigation |
| ------------- | ---------- |
| Token exposure in headers | HTTPS required, internal network only |
| Token lifetime | Use short-lived access tokens (5 min) |
| Refresh tokens | Enable `use_refresh_token` for session longevity |
| Token validation | Always validate via JWKS, never trust headers blindly |

### Network Security

| Consideration | Mitigation |
| ------------- | ---------- |
| Direct Grafana access | Use NetworkPolicy to restrict ingress to gateway only |
| Header spoofing (auth.proxy) | Whitelist gateway IP in Grafana |
| Session fixation | Regenerate session on login |

### Existing Network Policy

From `monitoring/network-policies/app/grafana.yaml.j2`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: grafana
  namespace: monitoring
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: envoy
            io.kubernetes.pod.namespace: envoy-gateway-system
```

This already restricts Grafana access to Envoy Gateway only, which is critical for auth.proxy security.

### Logout Handling

For complete logout across all applications:

1. Grafana logout clears Grafana session
2. User should also logout from Keycloak
3. Consider implementing RP-initiated logout via `logoutPath` in SecurityPolicy

---

## Operational Considerations

### Keycloak Realm Import Limitation

> [!CAUTION]
> **Critical:** Changes to the Keycloak realm configuration (adding Grafana client, modifying
> IdP mappers, updating roles) require **complete removal and redeployment** of Keycloak.

#### Why This Happens

The Keycloak realm is bootstrapped via `KeycloakRealmImport` CR during initial deployment. This is a **one-time import process**:

1. The realm import job runs on first deployment
2. If the realm already exists, the import is **skipped** (not updated)
3. Re-executing the realm import job results in: `"Realm 'matherlynet' already exists, skipping import"`
4. There is currently no "update" or "merge" mode for realm imports

#### Required Cleanup Procedure

When modifying `realm-import.sops.yaml.j2` (e.g., adding the Grafana OIDC client), you must completely remove the Keycloak deployment:

```bash
#| Delete all Keycloak resources in the identity namespace #|

#| 1. Suspend Flux reconciliation to prevent recreation #|
flux suspend ks keycloak-operator -n identity
flux suspend ks keycloak -n identity

#| 2. Delete HelmReleases and Kustomizations #|
kubectl delete helmrelease keycloak-operator -n identity --ignore-not-found
kubectl delete kustomization keycloak -n identity --ignore-not-found
kubectl delete kustomization keycloak-operator -n identity --ignore-not-found

#| 3. Delete Keycloak CRs (this triggers cascading deletion) #|
kubectl delete keycloak keycloak -n identity --ignore-not-found
kubectl delete keycloakrealmimport -n identity --all --ignore-not-found

#| 4. Delete remaining resources #|
kubectl delete jobs -n identity --all
kubectl delete pods -n identity --all --force --grace-period=0
kubectl delete secrets -n identity --all
kubectl delete configmaps -n identity --all
kubectl delete pvc -n identity --all

#| 5. If using CNPG, delete the PostgreSQL cluster #|
kubectl delete cluster keycloak-postgres -n identity --ignore-not-found

#| 6. Wait for cleanup #|
kubectl get all -n identity  # Should show nothing

#| 7. Resume Flux reconciliation #|
flux resume ks keycloak-operator -n flux-system
flux resume ks keycloak -n flux-system

#| 8. Force reconciliation #|
task reconcile
```

#### Impact Assessment

| Resource | Action | Data Loss |
| -------- | ------ | --------- |
| Keycloak Pods | Deleted | None (stateless) |
| PostgreSQL PVC | Deleted | **Yes - all user data** |
| Realm Configuration | Re-imported | Reset to template |
| User Accounts | Lost | **Yes - re-create required** |
| IdP Connections | Re-created | Tokens refreshed |
| Client Sessions | Terminated | Users must re-authenticate |

#### Mitigation Strategies

1. **Plan realm changes carefully** - Batch multiple changes together to minimize cleanup cycles
2. **Document manual user accounts** - Any manually created Keycloak users will be lost
3. **Use IdP-based authentication** - Users authenticated via Google/GitHub/Microsoft can simply re-login
4. **Test in non-production first** - Validate realm-import changes before applying to production

#### Future Improvement

A potential enhancement would be to implement realm configuration via Keycloak Admin REST API or Terraform provider instead of `KeycloakRealmImport`, which would allow incremental updates without full redeployment. This is tracked as a future enhancement opportunity.

---

## Testing and Validation

### Pre-Implementation Checklist

- [ ] `grafana_oidc_enabled: true` in cluster.yaml
- [ ] `grafana_oidc_client_secret` generated and SOPS-encrypted
- [ ] Grafana roles added to `keycloak_realm_roles`
- [ ] Grafana client added to Keycloak realm
- [ ] Grafana HelmRelease updated with OAuth config
- [ ] SOPS secret template created

### Test Procedure

1. **Clear browser state:**

   ```bash
   # Clear cookies for *.matherly.net in browser
   ```

2. **Initial authentication:**
   - Navigate to `https://hubble.matherly.net`
   - Authenticate via social IdP
   - Verify Hubble UI access

3. **Test SSO to Grafana:**
   - Navigate to `https://grafana.matherly.net`
   - **Expected (Option 3):** Brief redirect, then logged in
   - **Expected (Option 2):** Immediate login, no redirect
   - Verify username shown in Grafana matches Keycloak

4. **Test role mapping:**
   - Verify Grafana role matches Keycloak role assignment
   - Test with different users having different roles

5. **Test session persistence:**
   - Close browser, reopen
   - Navigate to Grafana
   - Should remain authenticated (if within session lifetime)

### Keycloak Recreation - Subject ID Mismatch

> [!WARNING]
> **Critical Issue:** When Keycloak is deleted and recreated (identity namespace reset), all
> users receive NEW subject IDs (the `sub` claim in OAuth tokens). If Grafana's PVC survived
> (monitoring namespace was NOT deleted), the existing user records have stale subject IDs.
>
> **Symptom:** "Login failed - User sync failed" error after Keycloak recreation
>
> **Log Evidence:**
>
> ```
> logger=user.sync t=... level=error msg="Failed to create user" error="user not found"
> auth_module=oauth_generic_oauth auth_id=<new-subject-id>
> ```
>
> **Root Cause:** Grafana matches OAuth users by subject ID, not email by default. When
> Keycloak is recreated, users get new `sub` claims that don't match existing Grafana records.

#### Permanent Fix (Implemented)

The `oauth_allow_insecure_email_lookup` setting is enabled in the HelmRelease template:

```yaml
auth:
  oauth_allow_insecure_email_lookup: true
```

This allows Grafana to match OAuth users to existing accounts by email address instead of
subject ID, providing resilience when Keycloak is recreated.

**Security Note:** This is safe for self-hosted Keycloak deployments where you control
the email claims. It prevents account hijacking scenarios that could occur with public
identity providers.

**REF:** https://github.com/grafana/grafana/issues/111139

#### Manual Fix (Delete Stale User)

If the permanent fix isn't deployed yet, delete the stale user via API:

```bash
# List Grafana users to find the stale one
kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -- \
  curl -s -u "admin:$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" \
  http://localhost:3000/api/users | jq .

# Delete the stale user (replace ID with actual user ID)
kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -- \
  curl -s -X DELETE \
  -u "admin:$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" \
  http://localhost:3000/api/admin/users/<USER_ID>
```

### Troubleshooting Commands

```bash
# Check Grafana OAuth configuration
kubectl exec -n monitoring -it deploy/kube-prometheus-stack-grafana -- \
  grafana-cli admin settings | grep auth

# Check Grafana logs for OAuth errors
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana | grep -i oauth

# Verify Keycloak client configuration
curl -s https://sso.matherly.net/realms/matherlynet/.well-known/openid-configuration | jq .

# Check JWKS endpoint
curl -s https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs | jq .

# Test token validation (replace with actual token)
curl -s https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/userinfo \
  -H "Authorization: Bearer <access_token>" | jq .

# Check Envoy Gateway SecurityPolicy
kubectl get securitypolicy -n network oidc-sso -o yaml

# Check HTTPRoute labels
kubectl get httproute -n network grafana -o yaml | grep -A5 labels
```

---

## Validation & Review Notes

> [!NOTE]
> **Reviewed:** January 7, 2026 via `/sc:reflect`
> This section documents validation findings and identified improvements.

### Validated Against Project Patterns

| Aspect | Status | Notes |
| ------ | ------ | ----- |
| Template delimiters | Compliant | Uses `#{ }#` for variables, `#% %#` for blocks |
| Secret patterns | Compliant | Uses SOPS encryption, `existingSecret` pattern |
| Conditional guards | Compliant | Uses `#% if grafana_oidc_enabled \| default(false) %#` |
| Flux dependencies | Documented | Keycloak → Grafana OIDC dependency noted |
| cluster.yaml schema | **Needs Addition** | New variables must be added to `cluster.sample.yaml` |

### Identified Issues & Resolutions

#### Issue 1: Missing cluster.sample.yaml Schema

**Status:** Documentation includes variables but they need to be added to the actual schema.

**Resolution:** The following variables need to be added to `cluster.sample.yaml` in the OBSERVABILITY section:

- `grafana_oidc_enabled`
- `grafana_oidc_client_secret`

#### Issue 2: Keycloak Client Protocol Mappers

**Status:** The realm-import client definition needs protocol mappers for roles claim.

**Resolution:** The Grafana client in Keycloak needs:

```yaml
protocolMappers:
  - name: "realm-roles"
    protocol: "openid-connect"
    protocolMapper: "oidc-usermodel-realm-role-mapper"
    config:
      claim.name: "roles"
      jsonType.label: "String"
      multivalued: "true"
      id.token.claim: "true"
      access.token.claim: "true"
```

#### Issue 3: auth.jwt Option (Option 2) - Simplest for Ideal State

**Status:** The user's ideal state (Envoy session recognized by Grafana) is achievable with Option 2.

**Key Insight:** Since `forwardAccessToken: true` already forwards the JWT to Grafana:

- Configure `auth.jwt` in Grafana to read `Authorization` header
- Grafana validates JWT against Keycloak's JWKS endpoint
- **No redirects needed** - true seamless SSO
- This is actually the simplest implementation matching the user's ideal state

#### Issue 4: Option 3 Has Double-Authentication

**Status:** Option 3 (Native OAuth) creates two authentication sessions:

1. Envoy Gateway OIDC session (cookies)
2. Grafana OAuth session (separate tokens)

**Trade-off:** More configuration complexity but better RBAC integration and Grafana session management.

### Recommendations Summary

| Priority | Recommendation |
| -------- | -------------- |
| **High** | For ideal SSO (no redirects): Implement **Option 2 (auth.jwt)** |
| Medium | For full RBAC/groups: Implement **Option 3 (Native OAuth)** |
| Low | For simple setup: **Option 4 (current)** with admin-only access |

### Implementation Complexity Comparison

```
Option 2 (auth.jwt) - SIMPLEST for seamless SSO:
  - Add ~15 lines to helmrelease.yaml.j2
  - No new secrets needed
  - No Keycloak changes needed
  - Uses existing forwardAccessToken: true

Option 3 (Native OAuth) - BEST for full RBAC:
  - Add ~50 lines to helmrelease.yaml.j2
  - Add new SOPS secret template
  - Add Grafana client to realm-import
  - Add 3 cluster.yaml variables
```

---

## Sources

### Official Documentation

- [Grafana Generic OAuth Configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/)
- [Grafana JWT Authentication](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/jwt/)
- [Grafana Auth Proxy](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/auth-proxy/)
- [Grafana Keycloak OAuth2](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/keycloak/)
- [Grafana Team Sync (Enterprise)](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-team-sync/)
- [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/latest/tasks/security/oidc/)
- [Envoy Gateway JWT Authentication](https://gateway.envoyproxy.io/latest/tasks/security/jwt-authentication/)
- [Envoy Gateway SecurityPolicy API](https://gateway.envoyproxy.io/latest/api/extension_types/)

### Project Documentation

- [Envoy Gateway + Keycloak OIDC Integration](./envoy-gateway-keycloak-oidc-integration-jan-2026.md)
- [Keycloak Social Identity Providers Integration](./keycloak-social-identity-providers-integration-jan-2026.md)

### Community Resources

- [Grafana Keycloak Role Mapping - Community Forums](https://community.grafana.com/t/grafana-keycloak-role-mapping/41191)
- [Securing Grafana with Pomerium](https://www.pomerium.com/docs/guides/grafana)
- [OAuth2 Authentication for Grafana with Keycloak](https://nsalexamy.github.io/service-foundry/pages/documents/sso-foundry/kc-grafana-oauth2/)
- [Configure JWT Auth Grafana - Tanmay Bhat](https://tanmay-bhat.github.io/posts/configure-jwt-auth-grafana/)

---

## Appendix A: Complete Template Changes

### cluster.yaml Additions

```yaml
# =============================================================================
# GRAFANA OIDC CONFIGURATION
# =============================================================================

# Enable Grafana native OAuth (creates dedicated Keycloak client)
grafana_oidc_enabled: true

# Client secret for Grafana OIDC client (SOPS-encrypted)
# Generate with: openssl rand -base64 32
grafana_oidc_client_secret: "your-generated-secret"

# Grafana roles for RBAC
keycloak_realm_roles:
  # ... existing roles ...
  - name: grafana-admin
    description: "Grafana Server Administrator - Full administrative access"
  - name: grafana-editor
    description: "Grafana Dashboard Editor - Can create and modify dashboards"
  - name: grafana-viewer
    description: "Grafana Dashboard Viewer - Read-only dashboard access"
```

### Derived Variables (plugin.py)

```python
# Grafana OIDC
if user_config.get("grafana_oidc_enabled") and user_config.get("grafana_oidc_client_secret"):
    user_config["grafana_oidc_enabled"] = True
else:
    user_config["grafana_oidc_enabled"] = False
```

## Appendix B: Comparison Summary

| Feature | Option 1 (auth.proxy) | Option 2 (auth.jwt) | Option 3 (Native OAuth) |
| ------- | --------------------- | ------------------- | ----------------------- |
| SSO Experience | True SSO | True SSO | Near SSO (auto_login) |
| Login Page | Never shown | Never shown | Brief redirect |
| RBAC | Via headers | Via JWT claims | Full JMESPath |
| Groups Support | Via header | Via JWT claim | Full groups mapping |
| Team Sync | No | No | Enterprise only |
| Refresh Tokens | N/A | No | Yes |
| Session Management | Gateway only | Stateless | Grafana manages |
| Complexity | Low | Medium | Medium-High |
| Recommended | Simple setups | API-heavy | Production |

## Appendix C: Future Enhancements

1. **Team Sync (Enterprise):** If upgraded to Grafana Enterprise, enable Team Sync for IdP groups -> Grafana teams mapping

2. **RP-Initiated Logout:** Implement coordinated logout across all OIDC-protected apps

3. **Service Account Integration:** For programmatic Grafana access, use Keycloak service accounts with JWT authentication

4. **Dashboard Provisioning by Role:** Use Grafana's folder permissions with RBAC roles for fine-grained dashboard access
