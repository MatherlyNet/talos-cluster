# Keycloak Social Identity Providers Integration Research

**Date:** January 2026
**Keycloak Version:** 26.5.0
**Scope:** Google, GitHub, Microsoft Entra ID integration with seamless SSO

> **Related Documentation:** See [Envoy Gateway + Keycloak OIDC Integration](./envoy-gateway-keycloak-oidc-integration-jan-2026.md) for details on how Envoy Gateway SecurityPolicy integrates with Keycloak for browser-based SSO.

## Executive Summary

This research document provides a comprehensive guide for integrating external identity providers (Google, GitHub, Microsoft Entra ID) with the existing Keycloak deployment. The goal is to enable users to authenticate using their existing social/enterprise credentials instead of creating local Keycloak accounts, while maintaining seamless single sign-on (SSO) across all protected applications (Grafana, Hubble UI, RustFS Console, etc.).

**Key Findings:**
- Keycloak 26.x natively supports all three identity providers with minimal configuration
- Token exchange (RFC 8693) is now officially supported in Keycloak 26.2+
- SSO session sharing works automatically across all applications in the same realm
- MCP authorization server support is available for future AI agent authentication needs

**Architecture Note:** Social IdP integration is configured in **Keycloak**, not Envoy Gateway. The flow is:
1. Envoy Gateway redirects unauthenticated users to Keycloak
2. Keycloak presents login options including configured social IdPs
3. User authenticates via chosen IdP (Google/GitHub/Microsoft)
4. Keycloak issues tokens back to Envoy Gateway
5. Envoy Gateway manages session via cookies with `cookieDomain` for cross-subdomain SSO

## Table of Contents

1. [Current Implementation Status](#current-implementation-status)
2. [Identity Provider Integration](#identity-provider-integration)
   - [Google](#google-identity-provider)
   - [GitHub](#github-identity-provider)
   - [Microsoft Entra ID](#microsoft-entra-id-identity-provider)
3. [Token Exchange](#token-exchange)
4. [Seamless SSO Implementation](#seamless-sso-implementation)
5. [Application-Specific Configuration](#application-specific-configuration)
6. [MCP Authorization Server](#mcp-authorization-server)
7. [Implementation Plan](#implementation-plan)
8. [Security Considerations](#security-considerations)

---

## Current Implementation Status

### Existing Keycloak Configuration

The cluster currently has Keycloak deployed with:

| Component | Status | Notes |
| ----------- | -------- | ------- |
| Keycloak Operator | v26.5.0 | Deployed via official Keycloak Operator |
| Database | CNPG PostgreSQL | Production-grade PostgreSQL cluster |
| Realm | `matherlynet` | Pre-configured with SSO session settings |
| OIDC Client | `envoy-gateway` | Bootstrap client for SecurityPolicy |
| Token Exchange | **Enabled** | Feature flag active in keycloak-cr.yaml |
| Admin Fine-Grained Authz | **Enabled** | Required for token exchange permissions |

**Current Feature Flags** (from `keycloak-cr.yaml`):
```yaml
features:
  enabled:
    - token-exchange
    - admin-fine-grained-authz
```

### Realm Configuration (from `realm-import.yaml.j2`)

The realm is already configured with:
- SSO Session Idle Timeout: 1800 seconds (30 minutes)
- SSO Session Max Lifespan: 36000 seconds (10 hours)
- Access Token Lifespan: 300 seconds (5 minutes)
- Brute Force Protection: Enabled
- Registration: Disabled (users must use IdP or be pre-created)

---

## Identity Provider Integration

### Google Identity Provider

**Reference:** [Keycloak Google Integration Guide](https://medium.com/@stefannovak96/signing-in-with-google-with-keycloak-bf5166e93d1e)

#### Step 1: Google Cloud Console Setup

1. Navigate to [Google Cloud Console](https://console.cloud.google.com/)
2. Create or select a project
3. Enable **Google+ API** and configure **OAuth Consent Screen**
4. Navigate to **Credentials** → **Create Credentials** → **OAuth Client ID**
5. Select **Web Application** as application type
6. Add **Authorized redirect URI**:
   ```
   https://sso.matherly.net/realms/matherlynet/broker/google/endpoint
   ```
7. Save and note the **Client ID** and **Client Secret**

#### Step 2: Keycloak Configuration

Add to `realm-import.yaml.j2` under the realm spec:

```yaml
identityProviders:
  - alias: "google"
    displayName: "Google"
    providerId: "google"
    enabled: true
    trustEmail: true
    storeToken: true
    linkOnly: false
    firstBrokerLoginFlowAlias: "first broker login"
    config:
      clientId: "${GOOGLE_CLIENT_ID}"
      clientSecret: "${GOOGLE_CLIENT_SECRET}"
      defaultScope: "openid profile email"
      syncMode: "IMPORT"
      useJwksUrl: "true"
```

#### Required Secrets

Add to `cluster.yaml`:
```yaml
# Google Identity Provider
google_client_id: "YOUR_GOOGLE_CLIENT_ID"
google_client_secret: "YOUR_GOOGLE_CLIENT_SECRET"  # SOPS-encrypted
```

---

### GitHub Identity Provider

**Reference:** [GitHub as Identity Provider in Keycloak](https://medium.com/keycloak/github-as-identity-provider-in-keyclaok-dca95a9d80ca)

#### Step 1: GitHub OAuth App Setup

1. Navigate to [GitHub Developer Settings](https://github.com/settings/developers)
2. Go to **OAuth Apps** → **New OAuth App**
3. Fill in details:
   - **Application name:** `MatherlyNet SSO`
   - **Homepage URL:** `https://matherly.net`
   - **Authorization callback URL:**
     ```
     https://sso.matherly.net/realms/matherlynet/broker/github/endpoint
     ```
4. Click **Register application**
5. Generate a **Client Secret** and note both **Client ID** and **Secret**

#### Step 2: Keycloak Configuration

Add to `realm-import.yaml.j2`:

```yaml
identityProviders:
  - alias: "github"
    displayName: "GitHub"
    providerId: "github"
    enabled: true
    trustEmail: true
    storeToken: true
    linkOnly: false
    firstBrokerLoginFlowAlias: "first broker login"
    config:
      clientId: "${GITHUB_CLIENT_ID}"
      clientSecret: "${GITHUB_CLIENT_SECRET}"
      defaultScope: "user:email read:org"
      syncMode: "IMPORT"
```

**Note:** The `read:org` scope is optional but useful if you want to map GitHub organization membership to Keycloak roles/groups.

#### Required Secrets

Add to `cluster.yaml`:
```yaml
# GitHub Identity Provider
github_client_id: "YOUR_GITHUB_CLIENT_ID"
github_client_secret: "YOUR_GITHUB_CLIENT_SECRET"  # SOPS-encrypted
```

---

### Microsoft Entra ID Identity Provider

**Reference:** [Configure Azure Entra ID as IdP on Keycloak](https://blog.ght1pc9kc.fr/en/2023/configure-azure-entra-id-as-idp-on-keycloak/)

#### Step 1: Azure Portal Configuration

1. Navigate to [Azure Portal](https://portal.azure.com/)
2. Go to **Azure Active Directory** → **App registrations** → **New registration**
3. Configure:
   - **Name:** `MatherlyNet Keycloak SSO`
   - **Supported account types:** "Accounts in any organizational directory and personal Microsoft accounts"
   - **Redirect URI:** Leave blank initially
4. After registration, note the **Application (client) ID** and **Directory (tenant) ID**
5. Go to **Certificates & secrets** → **New client secret**
6. Generate and save the **secret value** (visible only once!)
7. Go to **Authentication** → Add platform → **Web**
8. Add redirect URI:
   ```
   https://sso.matherly.net/realms/matherlynet/broker/microsoft/endpoint
   ```

#### Step 2: Get OpenID Connect Metadata

The discovery endpoint URL format:
```
https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration
```

For multi-tenant (recommended):
```
https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration
```

#### Step 3: Keycloak Configuration

**Important:** Use the generic OpenID Connect provider, NOT the built-in "Microsoft" provider, for better control over settings.

Add to `realm-import.yaml.j2`:

```yaml
identityProviders:
  - alias: "microsoft"
    displayName: "Microsoft"
    providerId: "oidc"  # Use generic OIDC, not 'microsoft'
    enabled: true
    trustEmail: true
    storeToken: true
    linkOnly: false
    firstBrokerLoginFlowAlias: "first broker login"
    config:
      clientId: "${MICROSOFT_CLIENT_ID}"
      clientSecret: "${MICROSOFT_CLIENT_SECRET}"
      authorizationUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
      tokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token"
      userInfoUrl: "https://graph.microsoft.com/oidc/userinfo"
      jwksUrl: "https://login.microsoftonline.com/common/discovery/v2.0/keys"
      issuer: "https://login.microsoftonline.com/{tenant-id}/v2.0"
      defaultScope: "openid profile email"
      syncMode: "FORCE"  # Update user data on every login
      validateSignature: "true"
      useJwksUrl: "true"
```

#### Required Secrets

Add to `cluster.yaml`:
```yaml
# Microsoft Entra ID Identity Provider
microsoft_client_id: "YOUR_APPLICATION_CLIENT_ID"
microsoft_client_secret: "YOUR_CLIENT_SECRET_VALUE"  # SOPS-encrypted
microsoft_tenant_id: "YOUR_DIRECTORY_TENANT_ID"  # Or "common" for multi-tenant
```

---

## Token Exchange

### Overview

Token Exchange (RFC 8693) allows exchanging tokens from external identity providers for Keycloak-issued tokens. This is critical for scenarios where:

1. Mobile apps authenticate directly with Google/GitHub/Microsoft and need Keycloak tokens
2. Services need to exchange client tokens for service-to-service tokens
3. You need token delegation for microservices

**Reference:** [Keycloak Token Exchange Documentation](https://www.keycloak.org/securing-apps/token-exchange)

### Token Exchange in Keycloak 26.2+

**Good news:** Standard Token Exchange V2 is now officially supported and enabled by default in Keycloak 26.2+.

**Reference:** [Standard Token Exchange in Keycloak 26.2](https://www.keycloak.org/2025/05/standard-token-exchange-kc-26-2)

#### V1 vs V2 Comparison

| Feature | V2 (Standard) | V1 (Legacy/Preview) |
| --------- | --------------- | --------------------- |
| Status | Fully supported | Preview, deprecated |
| Internal-to-Internal | Yes | Yes |
| External-to-Internal | **Not yet** | Yes |
| Impersonation | No | Yes |
| Enable Method | Toggle in client settings | `--features=token-exchange` |
| RFC Compliance | Full RFC 8693 | Partial |

#### Current Status

Your Keycloak deployment has `token-exchange` in the features list. This enables V1 (legacy) token exchange, which supports **external-to-internal** exchange - exactly what's needed for social IdP token exchange.

#### External Token Exchange Flow

When a user authenticates via Google/GitHub/Microsoft:

1. User logs in through the external IdP
2. Keycloak receives the external token and creates a linked account
3. Applications can then exchange external tokens for Keycloak tokens

**Exchange Request Example:**
```bash
curl -X POST \
  https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=envoy-gateway" \
  -d "client_secret=${OIDC_CLIENT_SECRET}" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "subject_token=${GOOGLE_ACCESS_TOKEN}" \
  -d "subject_issuer=google" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token"
```

#### JWT Authorization Grants (Alternative)

For newer deployments, Keycloak recommends **JWT Authorization Grants** as an alternative to external-to-internal token exchange:

> "JWT Authorization Grants is the recommended alternative to external to internal token exchange."

This is configured via the identity provider's settings under the "JWT Authorization Grant" section.

---

## Seamless SSO Implementation

### How SSO Works Across Applications

**Reference:** [How does Keycloak SSO work?](https://github.com/keycloak/keycloak/discussions/31428)

When properly configured, SSO works automatically:

1. **First Access (e.g., Hubble UI)**
   - User navigates to `https://hubble.matherly.net`
   - Envoy Gateway SecurityPolicy triggers OIDC redirect to Keycloak
   - Keycloak presents login options (Google, GitHub, Microsoft, local)
   - User authenticates via chosen IdP
   - Keycloak creates SSO session and issues tokens
   - User is redirected back to Hubble UI with valid session

2. **Subsequent Access (e.g., Grafana)**
   - User navigates to `https://grafana.matherly.net`
   - Browser sends Envoy Gateway's OAuth cookies (shared via `cookieDomain`)
   - Envoy Gateway validates the token from cookie
   - User is automatically authenticated - **no login prompt**
   - Grafana receives user tokens

### Key SSO Session Parameters

From your current `realm-import.yaml.j2`:

| Parameter | Value | Description |
| ----------- | ------- | ------------- |
| `ssoSessionIdleTimeout` | 1800s (30 min) | Session expires if no activity |
| `ssoSessionMaxLifespan` | 36000s (10 hours) | Absolute session limit |
| `accessTokenLifespan` | 300s (5 min) | Short-lived access tokens |
| `rememberMe` | true | Allows "Remember Me" option |

### SSO Cookie Behavior

> **Important Clarification:** When using Envoy Gateway's OIDC SecurityPolicy, SSO is managed at **two levels**:

**1. Envoy Gateway Cookies (Primary for cross-app SSO):**
- `OauthHMAC` - Token verification
- `OauthExpires` - Token lifetime tracking
- `IdToken` - The actual JWT

When `cookieDomain: ".matherly.net"` is configured, these cookies are shared across all subdomains, enabling seamless SSO between `hubble.matherly.net`, `grafana.matherly.net`, etc.

**2. Keycloak Session (During authentication flow):**
- `KEYCLOAK_IDENTITY` cookie on `sso.matherly.net`
- Used when user needs to re-authenticate (token expired)
- Enables "remember me" across browser sessions

**Key Insight:** For most requests, Envoy Gateway validates the token from its own cookies without contacting Keycloak. Keycloak is only involved during initial authentication or token refresh.

---

## Application-Specific Configuration

### Grafana OAuth Integration

**Reference:** [Configure Keycloak OAuth2 authentication | Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/keycloak/)

Since Grafana is protected by Envoy Gateway SecurityPolicy (JWT validation), the SSO flow is handled at the gateway level. However, Grafana can also be configured for native Keycloak OAuth for enhanced features.

#### Option 1: Gateway-Only (Current Implementation)

Grafana receives pre-authenticated requests via Envoy Gateway. The JWT claims are validated, but Grafana doesn't have direct Keycloak integration.

**Pros:** Simpler, centralized auth
**Cons:** No Grafana-specific role mapping from IdP

#### Option 2: Native Grafana OAuth + Gateway

For advanced role mapping, configure Grafana's native OAuth:

```yaml
# In Grafana HelmRelease values
grafana.ini:
  auth.generic_oauth:
    enabled: true
    name: Keycloak
    client_id: grafana
    client_secret: ${GRAFANA_OIDC_SECRET}
    scopes: openid profile email offline_access
    auth_url: https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/auth
    token_url: https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/token
    api_url: https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/userinfo
    role_attribute_path: contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'editor') && 'Editor' || 'Viewer'
    allow_sign_up: true
    use_refresh_token: true
```

**Note:** This requires creating a separate `grafana` client in Keycloak with appropriate role mappers.

### RustFS Console

RustFS Console uses MinIO-compatible authentication. It may not directly support OIDC SSO. Investigation needed on:
- Whether RustFS supports OpenID Connect authentication
- If gateway-level JWT validation is sufficient

### Hubble UI

Hubble UI is a static web application that doesn't have built-in OAuth support. Gateway-level protection via Envoy SecurityPolicy is the appropriate solution (current implementation).

---

## MCP Authorization Server

### Overview

Keycloak can serve as an authorization server for Model Context Protocol (MCP) resources, enabling AI agents to securely access cluster services.

**Reference:** [Keycloak as MCP Authorization Server](https://www.keycloak.org/securing-apps/mcp-authz-server)

### MCP Version Support

| MCP Version | Keycloak Support |
| ------------- | ------------------ |
| 2025-03-26 | Fully supported |
| 2025-06-18 | Partial (no RFC 8707) |
| 2025-11-25 | Partial (no RFC 8707) |

### Key Features

1. **OAuth 2.1 Authorization Framework** - Full compliance
2. **Dynamic Client Registration (RFC 7591)** - Supported
3. **Authorization Server Metadata (RFC 8414)** - Supported

### Token Audience Binding Workaround

For MCP 2025-06-18+, implement audience binding via scopes:

```yaml
# Create optional client scopes in realm
clientScopes:
  - name: "mcp:tools"
    protocol: "openid-connect"
    protocolMappers:
      - name: "audience-mapper"
        protocol: "openid-connect"
        protocolMapper: "oidc-audience-mapper"
        config:
          included.custom.audience: "https://mcp.matherly.net"
          access.token.claim: "true"
```

### SPIFFE Integration for Workload Identity

**Reference:** [Implementing MCP Dynamic Client Registration with SPIFFE](https://blog.christianposta.com/implementing-mcp-dynamic-client-registration-with-spiffe/)

For zero-trust workload authentication:

1. **SPIRE Integration** - Issue JWT SVIDs for MCP clients
2. **Dynamic Registration** - Clients register automatically with software statements
3. **No Static Secrets** - Eliminates client IDs/secrets from configs

This is advanced and recommended for future enhancement when MCP servers are deployed.

---

## Implementation Plan

### Phase 1: Identity Provider Configuration (Priority: High) ✅ IMPLEMENTED

**Status:** Implemented in `cluster.sample.yaml` and `realm-import.yaml.j2`

#### 1.1 Update cluster.yaml with IdP Secrets

```yaml
# Add to cluster.yaml (encrypt sensitive values with SOPS)

# Google Identity Provider
google_idp_enabled: true
google_client_id: "xxx.apps.googleusercontent.com"
google_client_secret: "GOCSPX-xxxxxx"  # SOPS-encrypted

# GitHub Identity Provider
github_idp_enabled: true
github_client_id: "Iv1.xxxxxx"
github_client_secret: "xxxxxx"  # SOPS-encrypted

# Microsoft Entra ID Identity Provider
microsoft_idp_enabled: true
microsoft_client_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
microsoft_client_secret: "xxxxxx"  # SOPS-encrypted
microsoft_tenant_id: "common"  # Or specific tenant ID
```

#### 1.2 Update realm-import.yaml.j2

Add identity providers section after the clients section:

```jinja2
#% if google_idp_enabled | default(false) or github_idp_enabled | default(false) or microsoft_idp_enabled | default(false) %#
    identityProviders:
#% if google_idp_enabled | default(false) %#
      - alias: "google"
        displayName: "Google"
        providerId: "google"
        enabled: true
        trustEmail: true
        storeToken: true
        linkOnly: false
        firstBrokerLoginFlowAlias: "first broker login"
        config:
          clientId: "#{ google_client_id }#"
          clientSecret: "#{ google_client_secret }#"
          defaultScope: "openid profile email"
          syncMode: "IMPORT"
#% endif %#
#% if github_idp_enabled | default(false) %#
      - alias: "github"
        displayName: "GitHub"
        providerId: "github"
        enabled: true
        trustEmail: true
        storeToken: true
        linkOnly: false
        firstBrokerLoginFlowAlias: "first broker login"
        config:
          clientId: "#{ github_client_id }#"
          clientSecret: "#{ github_client_secret }#"
          defaultScope: "user:email"
          syncMode: "IMPORT"
#% endif %#
#% if microsoft_idp_enabled | default(false) %#
      - alias: "microsoft"
        displayName: "Microsoft"
        providerId: "oidc"
        enabled: true
        trustEmail: true
        storeToken: true
        linkOnly: false
        firstBrokerLoginFlowAlias: "first broker login"
        config:
          clientId: "#{ microsoft_client_id }#"
          clientSecret: "#{ microsoft_client_secret }#"
          authorizationUrl: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/oauth2/v2.0/authorize"
          tokenUrl: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/oauth2/v2.0/token"
          userInfoUrl: "https://graph.microsoft.com/oidc/userinfo"
          jwksUrl: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/discovery/v2.0/keys"
          issuer: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/v2.0"
          defaultScope: "openid profile email"
          syncMode: "FORCE"
          validateSignature: "true"
          useJwksUrl: "true"
#% endif %#
#% endif %#
```

#### 1.3 Create External Provider OAuth Apps

| Provider | Console URL | Callback URL |
| ---------- | ------------- | -------------- |
| Google | https://console.cloud.google.com/apis/credentials | `https://sso.matherly.net/realms/matherlynet/broker/google/endpoint` |
| GitHub | https://github.com/settings/developers | `https://sso.matherly.net/realms/matherlynet/broker/github/endpoint` |
| Microsoft | https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps | `https://sso.matherly.net/realms/matherlynet/broker/microsoft/endpoint` |

### Phase 2: First Login Flow Customization (Priority: Medium)

Configure how users are handled on first social login:

```yaml
# Add to realm-import.yaml.j2
    authenticationFlows:
      - alias: "first broker login"
        description: "Actions taken after first broker login"
        providerId: "basic-flow"
        topLevel: true
        builtIn: false
        authenticationExecutions:
          - authenticator: "idp-review-profile"
            requirement: "REQUIRED"
            priority: 10
            authenticatorConfig:
              alias: "review profile config"
              config:
                update.profile.on.first.login: "missing"
          - authenticator: "idp-create-user-if-unique"
            requirement: "ALTERNATIVE"
            priority: 20
          - authenticator: "idp-confirm-link"
            requirement: "ALTERNATIVE"
            priority: 30
          - authenticator: "idp-email-verification"
            requirement: "ALTERNATIVE"
            priority: 40
          - authenticator: "idp-username-password-form"
            requirement: "ALTERNATIVE"
            priority: 50
```

### Phase 3: Role/Group Mappers (Priority: Medium) ✅ IMPLEMENTED

**Status:** Implemented via conditional templates in `realm-import.yaml.j2`

Map external IdP attributes/claims to Keycloak roles automatically. Three mapper types are supported:

#### Mapper Types

| Mapper Type | Provider ID | Use Case |
| ----------- | ----------- | -------- |
| **Hardcoded Role** | `oidc-hardcoded-role-idp-mapper` | Assign fixed role to ALL users from an IdP |
| **Claim to Role** | `oidc-role-idp-mapper` | Map specific claim values to roles (Google `hd` domain) |
| **Advanced Claim to Role** | `oidc-advanced-role-idp-mapper` | Regex-based claim matching (Microsoft groups, GitHub orgs) |

#### Configuration Variables (cluster.yaml)

```yaml
# -- Google: Assign default role to all Google users
google_default_role: "google-user"

# -- Google: Map hosted domain (hd claim) to role
google_domain_role_mapping:
  domain: "matherly.net"
  role: "domain-user"

# -- GitHub: Assign default role to all GitHub users
github_default_role: "github-user"

# -- GitHub: Map organization membership to role
#    NOTE: Requires adding "read:org" scope to GitHub IdP config
github_org_role_mapping:
  org: "my-org"
  role: "org-member"

# -- Microsoft: Assign default role to all Microsoft users
microsoft_default_role: "microsoft-user"

# -- Microsoft: Map Entra ID group ObjectID to role
#    NOTE: Requires enabling "groups" claim in Azure App Registration
microsoft_group_role_mappings:
  - group_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    role: "admin"
  - group_id: "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
    role: "user"
```

#### Generated Template (realm-import.yaml.j2)

The template conditionally generates mappers based on which variables are defined:

```yaml
identityProviderMappers:
  # Google: Hardcoded role for all users
  - name: "google-default-role"
    identityProviderAlias: "google"
    identityProviderMapper: "oidc-hardcoded-role-idp-mapper"
    config:
      syncMode: "INHERIT"
      role: "google-user"

  # Google: Domain-based role mapping (hd claim)
  - name: "google-domain-matherly-net"
    identityProviderAlias: "google"
    identityProviderMapper: "oidc-role-idp-mapper"
    config:
      syncMode: "INHERIT"
      claim: "hd"
      claim.value: "matherly.net"
      role: "domain-user"

  # Microsoft: Group ObjectID to role mapping
  - name: "microsoft-group-admin"
    identityProviderAlias: "microsoft"
    identityProviderMapper: "oidc-advanced-role-idp-mapper"
    config:
      syncMode: "FORCE"
      claims: "[{\"key\":\"groups\",\"value\":\".*xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.*\"}]"
      are.claim.values.regex: "true"
      role: "admin"
```

#### Provider-Specific Notes

**Google:**
- `hd` claim contains the hosted domain (e.g., `matherly.net`) for Google Workspace users
- Personal Gmail accounts do NOT have the `hd` claim
- Use hardcoded role for all users, domain mapping for organization-specific roles

**GitHub:**
- Requires `read:org` scope to access organization membership
- GitHub does NOT natively expose org membership as a claim
- Alternative: Use hardcoded role for all GitHub users

**Microsoft Entra ID:**
- Requires enabling "groups" claim in Azure Portal: Token Configuration → Add optional claim
- Groups are returned as an array of Object IDs (UUIDs)
- Use Advanced Claim to Role mapper with regex to match group IDs

#### SyncMode Options

| Value | Behavior |
| ----- | -------- |
| `INHERIT` | Uses the IdP's syncMode setting |
| `IMPORT` | Only assigns role on first login |
| `FORCE` | Assigns role on every login (recommended for groups) |
| `LEGACY` | Pre-17.0 behavior (deprecated) |

**Source References:**
- [Keycloak ClaimToRoleMapper](https://github.com/keycloak/keycloak/blob/main/services/src/main/java/org/keycloak/broker/oidc/mappers/ClaimToRoleMapper.java)
- [Keycloak AdvancedClaimToRoleMapper](https://github.com/keycloak/keycloak/blob/main/services/src/main/java/org/keycloak/broker/oidc/mappers/AdvancedClaimToRoleMapper.java)
- [Keycloak HardcodedRoleMapper](https://github.com/keycloak/keycloak/blob/main/services/src/main/java/org/keycloak/broker/provider/HardcodedRoleMapper.java)
- [Mapping Claims and Assertions](https://blog.elest.io/mapping-claims-and-assertions-in-keycloak/)

### Phase 4: Grafana Native OAuth (Priority: Low)

If native Grafana OAuth is desired for role mapping:

1. Create `grafana` client in Keycloak realm
2. Configure role mappers
3. Update Grafana HelmRelease with OAuth settings

---

## Security Considerations

### Email Trust

Setting `trustEmail: true` means Keycloak trusts the email provided by the IdP without verification. This is generally safe for established providers (Google, GitHub, Microsoft) but:

- Ensure only trusted IdPs have this enabled
- Consider `trustEmail: false` for less trusted providers

### Account Linking Security

The default "first broker login" flow can present security risks:

> "If there is an existing Keycloak account with the same email, automatically linking the existing local account to the external identity provider is a potential security hole as you can't always trust the information you get from the external identity provider."

**Mitigations:**
1. Require email verification before linking (`idp-email-verification` step)
2. Require password re-authentication (`idp-username-password-form` step)
3. Disable registration (`registrationAllowed: false`) - already done

### Token Storage

Setting `storeToken: true` stores the external IdP tokens in Keycloak. This:
- Enables token exchange functionality
- Allows calling external APIs on behalf of users
- Requires secure database (CNPG with encryption recommended)

### Restrict Registration

The current configuration has `registrationAllowed: false`, which means:
- Users cannot self-register local accounts
- Users can still authenticate via social IdPs (creates linked account)
- To further restrict, use `linkOnly: true` on IdPs (only existing users can link)

---

## Sources

### Primary References
- [Keycloak as MCP Authorization Server](https://www.keycloak.org/securing-apps/mcp-authz-server)
- [Keycloak Token Exchange Documentation](https://www.keycloak.org/securing-apps/token-exchange)
- [Standard Token Exchange in Keycloak 26.2](https://www.keycloak.org/2025/05/standard-token-exchange-kc-26-2)
- [Configure Keycloak OAuth2 authentication | Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/keycloak/)

### Identity Provider Guides
- [Signing in with Google with Keycloak](https://medium.com/@stefannovak96/signing-in-with-google-with-keycloak-bf5166e93d1e)
- [GitHub as Identity Provider in Keycloak](https://medium.com/keycloak/github-as-identity-provider-in-keyclaok-dca95a9d80ca)
- [Configure Azure Entra ID as IdP on Keycloak](https://blog.ght1pc9kc.fr/en/2023/configure-azure-entra-id-as-idp-on-keycloak/)
- [The simplest way to make Keycloak Microsoft Entra ID work](https://hoop.dev/blog/the-simplest-way-to-make-keycloak-microsoft-entra-id-work-like-it-should/)

### SSO and Token Exchange
- [How does Keycloak SSO work?](https://github.com/keycloak/keycloak/discussions/31428)
- [Token Exchange: Keycloak's Secret Weapon](https://keycloak-day.dev/assets/files/20250306_KeycloakDevDay_TokenExchange.pdf)
- [Implementing MCP Dynamic Client Registration with SPIFFE](https://blog.christianposta.com/implementing-mcp-dynamic-client-registration-with-spiffe/)

### Envoy Gateway Integration
- [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/latest/tasks/security/oidc/)
- [Envoy Gateway JWT Authentication](https://gateway.envoyproxy.io/latest/tasks/security/jwt-authentication/)
- [Envoy Gateway JWT Claim Authorization](https://gateway.envoyproxy.io/latest/tasks/security/jwt-claim-authorization/)
- [Envoy Gateway External Auth](https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/)
- [Jimmy Song - Envoy Gateway OIDC Tutorial](https://jimmysong.io/blog/envoy-gateway-oidc/)
- [JBW - Integrating Keycloak OIDC with Envoy Gateway](https://www.jbw.codes/blog/Integrating-Keycloak-OIDC-with-Envoy-API-Gateway)

### User-Provided References (Analyzed)
- [Keycloak Token Exchange (2018)](https://www.mathieupassenaud.fr/token-exchange-keycloak/) - Outdated (v4.8) but concepts valid; now natively supported in v26
- [Grafana OAuth with Keycloak (2020)](https://janikvonrotz.ch/2020/08/27/grafana-oauth-with-keycloak-and-how-to-validate-a-jwt-token/) - Core concepts valid; modern config differs slightly
- [Shakudo Google SSO Guide](https://docs.shakudo.io/Getting%20started/Sign%20in%20with%20external%20provider/example-1-google/) - Keycloak-specific steps applicable

---

## Appendix A: Complete Realm Import Template

See implementation branch for the complete updated `realm-import.yaml.j2` with all identity providers configured.

## Appendix B: OAuth Callback URLs Summary

| Provider | Callback URL |
| ---------- | -------------- |
| Google | `https://sso.matherly.net/realms/matherlynet/broker/google/endpoint` |
| GitHub | `https://sso.matherly.net/realms/matherlynet/broker/github/endpoint` |
| Microsoft | `https://sso.matherly.net/realms/matherlynet/broker/microsoft/endpoint` |

## Appendix C: Testing SSO Flow

After implementation, test the SSO flow:

1. Clear browser cookies/sessions
2. Navigate to `https://hubble.matherly.net`
3. Should redirect to Keycloak login page
4. Click "Google" (or GitHub/Microsoft) button
5. Complete external IdP authentication
6. Should return to Hubble UI authenticated
7. **Without logging out**, navigate to `https://grafana.matherly.net`
8. Should be automatically authenticated (no login prompt)
9. Repeat for `https://rustfs.matherly.net`
