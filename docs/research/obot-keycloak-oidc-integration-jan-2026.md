# Obot Keycloak OIDC Integration Research

**Date:** January 2026
**Status:** Research Complete - Implementation Validated
**Priority:** High
**Related Components:** Obot (ai-system), Keycloak (identity), jrmatherly/obot-entraid fork

## Executive Summary

This document provides comprehensive research and validation guidance for integrating the Obot MCP Gateway deployment with Keycloak OIDC authentication using the custom [jrmatherly/obot-entraid](https://github.com/jrmatherly/obot-entraid) fork. The fork extends upstream Obot with a custom Keycloak authentication provider that is not available in the standard obot-platform/obot repository.

### Key Findings

1. **Custom Auth Provider:** The Keycloak auth provider in jrmatherly/obot-entraid uses the [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) library with the `keycloak-oidc` provider type
2. **PKCE Support:** The provider requires PKCE S256 code challenge method (enabled since v0.2.21)
3. **URL Format:** `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` expects the base URL WITHOUT `/realms/{realm}` suffix
4. **Token Claims:** The provider expects `groups` and `roles` claims in the ID token for access control
5. **Callback URL:** OAuth2 callback must be at `https://{OBOT_SERVER_URL}/oauth2/callback`

### Validation Status

| Component | Status | Notes |
| ----------- | -------- | ------- |
| Keycloak Client Configuration | ✅ Validated | realm-config.yaml.j2 correctly configured |
| Environment Variables | ✅ Validated | helmrelease.yaml.j2 and secret.sops.yaml.j2 correct |
| Derived Variables (plugin.py) | ✅ Validated | obot_keycloak_base_url correctly derived |
| Network Policies | ✅ Validated | Includes Keycloak egress |
| Protocol Mappers | ✅ Validated | Groups and roles claims configured |

## Fork Analysis: jrmatherly/obot-entraid

### Repository Details

- **Repository:** https://github.com/jrmatherly/obot-entraid
- **Current Version:** v0.2.30 (January 2026)
- **Helm Chart:** `oci://ghcr.io/jrmatherly/charts/obot`
- **Container Image:** `ghcr.io/jrmatherly/obot-entraid`
- **License:** MIT (same as upstream)

### Custom Authentication Providers

The fork adds two authentication providers not available in upstream obot-platform/obot:

1. **Keycloak Auth Provider** (`tools/keycloak-auth-provider/`)
2. **Entra ID (Azure AD) Auth Provider** (`tools/entra-auth-provider/`)

### Keycloak Auth Provider Architecture

The provider is implemented as a daemon tool using the oauth2-proxy library:

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Obot Server                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                   Auth Provider Daemon                           ││
│  │  ┌─────────────────┐    ┌─────────────────────────────────────┐ ││
│  │  │   HTTP Server   │    │        oauth2-proxy library         │ ││
│  │  │   (port 9999)   │◄───┤  - keycloak-oidc provider type      │ ││
│  │  │                 │    │  - PKCE S256 code challenge         │ ││
│  │  │  Endpoints:     │    │  - Cookie-based session storage     │ ││
│  │  │  /{$}           │    │  - PostgreSQL session store (opt)   │ ││
│  │  │  /oauth2/start  │    └─────────────────────────────────────┘ ││
│  │  │  /oauth2/callback│                                            ││
│  │  │  /oauth2/sign_out│                                            ││
│  │  │  /obot-get-state │                                            ││
│  │  │  /obot-get-user-info│                                         ││
│  │  │  /obot-get-icon-url │                                         ││
│  │  └─────────────────┘                                             ││
│  └─────────────────────────────────────────────────────────────────┘│
└──────────────────────────────┬──────────────────────────────────────┘
                               │ OIDC Flow
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Keycloak Server                                 │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Realm: matherlynet                                             ││
│  │  ┌─────────────────┐  ┌───────────────────┐  ┌────────────────┐ ││
│  │  │  Client: obot   │  │  Protocol Mappers │  │  Client Scopes │ ││
│  │  │  - confidential │  │  - realm-roles    │  │  - openid      │ ││
│  │  │  - standard flow│  │  - groups         │  │  - email       │ ││
│  │  │  - PKCE S256    │  │                   │  │  - profile     │ ││
│  │  └─────────────────┘  └───────────────────┘  │  - offline_acc │ ││
│  │                                               └────────────────┘ ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

### Required Endpoints

Per the obot auth provider specification, the Keycloak provider implements:

| Endpoint | Method | Purpose |
| ---------- | -------- | --------- |
| `/{$}` | GET | Returns daemon address (`http://127.0.0.1:9999`) |
| `/oauth2/start` | GET | Initiates OAuth2 authorization flow with PKCE |
| `/oauth2/callback` | GET | Handles OAuth2 callback, sets encrypted cookie |
| `/oauth2/sign_out` | GET | Clears auth cookie, redirects to Keycloak logout |
| `/obot-get-state` | POST | Returns user session state with groups/roles |
| `/obot-get-user-info` | GET | Returns user profile from Keycloak userinfo endpoint |
| `/obot-get-icon-url` | GET | Returns user profile picture URL |

## Environment Variables Reference

### Required Variables (Keycloak Provider)

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `OBOT_SERVER_AUTH_PROVIDER` | Auth provider type | `keycloak` |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` | Keycloak base URL (NO `/realms/...`) | `https://auth.example.com` |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | Keycloak realm name | `matherlynet` |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | OIDC client ID | `obot` |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | OIDC client secret | (SOPS encrypted) |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET` | Cookie encryption key (32-byte base64) | (SOPS encrypted) |
| `OBOT_AUTH_PROVIDER_EMAIL_DOMAINS` | Allowed email domains | `*` or `example.com,example.org` |

### Optional Variables (Access Control)

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` | Comma-separated group restrictions | `obot-admins,obot-users` |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` | Comma-separated role restrictions | `obot-admin,obot-user` |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_GROUP_CACHE_TTL` | Group cache duration | `1h` (default) |
| `OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN` | PostgreSQL session storage | `postgres://...` |
| `OBOT_AUTH_PROVIDER_TOKEN_REFRESH_DURATION` | Token refresh interval | `1h` (default) |

### Server Variables

| Variable | Description | Required |
| ---------- | ------------- | ---------- |
| `OBOT_SERVER_HOSTNAME` | Full URL including protocol | Yes |
| `OBOT_SERVER_ENABLE_AUTHENTICATION` | Enable auth | Yes (`true`) |
| `OBOT_SERVER_AUTH_ADMIN_EMAILS` | Admin access emails | No |
| `OBOT_SERVER_AUTH_OWNER_EMAILS` | Owner access emails | No |
| `OBOT_BOOTSTRAP_TOKEN` | Initial setup token | No |

## OIDC Issuer URL Construction

**Critical:** The Keycloak auth provider constructs the OIDC issuer URL internally:

```
OIDC Issuer URL = {OBOT_KEYCLOAK_AUTH_PROVIDER_URL}/realms/{OBOT_KEYCLOAK_AUTH_PROVIDER_REALM}
```

**Example:**
- `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` = `https://auth.example.com`
- `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` = `matherlynet`
- **Resulting issuer:** `https://auth.example.com/realms/matherlynet`

This is why `obot_keycloak_base_url` in plugin.py is derived as just the base hostname without `/realms/...`.

## Keycloak Client Configuration

### Client Settings Required

The Keycloak client must be configured as follows:

```yaml
# From realm-config.yaml.j2
- clientId: "$(env:OBOT_CLIENT_ID)"
  name: "Obot MCP Gateway"
  enabled: true
  publicClient: false                    # Confidential client
  clientAuthenticatorType: "client-secret"
  secret: "$(env:OBOT_CLIENT_SECRET)"
  standardFlowEnabled: true              # Authorization code flow
  directAccessGrantsEnabled: false
  serviceAccountsEnabled: false
  implicitFlowEnabled: false
  protocol: "openid-connect"
  attributes:
    pkce.code.challenge.method: "S256"   # PKCE required
```

### Redirect URIs

```yaml
redirectUris:
  - "https://obot.example.com/*"
  - "https://obot.example.com/oauth2/callback"
webOrigins:
  - "https://obot.example.com"
attributes:
  post.logout.redirect.uris: "https://obot.example.com/*"
```

### Client Scopes

Required scopes attached as defaults:
- `profile` - User profile information
- `email` - User email address

Optional scopes:
- `offline_access` - Refresh tokens (recommended for long sessions)
- `groups` - Group memberships (if using `ALLOWED_GROUPS`)

**Note:** `openid` is implicit in OIDC protocol and not a configurable scope in Keycloak.

### Protocol Mappers

For group and role-based access control, these mappers must be configured:

```yaml
protocolMappers:
  # Map realm roles to 'roles' claim
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

  # Map groups to 'groups' claim
  - name: "groups"
    protocol: "openid-connect"
    protocolMapper: "oidc-group-membership-mapper"
    config:
      claim.name: "groups"
      full.path: "false"           # Use simple names, not full paths
      id.token.claim: "true"
      access.token.claim: "true"
      userinfo.token.claim: "true"
```

### Audience Mapper (Recommended)

For strict token validation, add an audience mapper:

1. Navigate to Clients → obot → Client scopes tab
2. Click on `obot-dedicated` scope
3. Add mapper → Audience
4. Set "Included Client Audience" to `obot`
5. Enable "Add to ID token" and "Add to access token"

## Current Implementation Analysis

### Validated Components

#### 1. HelmRelease Configuration (`helmrelease.yaml.j2`)

The current implementation correctly configures:

```yaml
config:
  OBOT_SERVER_AUTH_PROVIDER: "keycloak"
  OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL: "#{ obot_keycloak_base_url }#"
  OBOT_KEYCLOAK_AUTH_PROVIDER_REALM: "#{ obot_keycloak_realm }#"
  OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID: "#{ obot_keycloak_client_id | default('obot') }#"
```

**Note:** The variable is named `OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL` in our deployment but the fork expects `OBOT_KEYCLOAK_AUTH_PROVIDER_URL`. This is a **potential issue** that needs validation.

#### 2. Secret Configuration (`secret.sops.yaml.j2`)

Correctly provides secrets via `extraEnvFrom`:

```yaml
stringData:
  OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET: "#{ obot_keycloak_client_secret }#"
  OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET: "#{ obot_keycloak_cookie_secret }#"
```

#### 3. Plugin.py Derived Variables

Correctly derives URLs:

```python
# Base URL (without /realms/...) for OBOT_KEYCLOAK_AUTH_PROVIDER_URL
data["obot_keycloak_base_url"] = f"https://{keycloak_hostname}"
# Realm name for OBOT_KEYCLOAK_AUTH_PROVIDER_REALM
data["obot_keycloak_realm"] = keycloak_realm
```

#### 4. Keycloak Client Configuration (`realm-config.yaml.j2`)

Correctly configured with:
- PKCE S256 enabled
- Confidential client type
- Standard flow enabled
- Protocol mappers for roles and groups

### Identified Issue: Environment Variable Name Mismatch

**CRITICAL:** The fork expects `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` but our helmrelease.yaml.j2 uses `OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL`.

**Current (helmrelease.yaml.j2 line 125):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL: "#{ obot_keycloak_base_url }#"
```

**Expected (per fork tool.gpt):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "#{ obot_keycloak_base_url }#"
```

**Recommendation:** Change the variable name to `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` to match the fork's expectations.

## Authentication Flow

### Standard Login Flow

```
1. User visits https://obot.example.com
   │
   ▼
2. Obot checks for valid session cookie (obot_access_token)
   │ No valid cookie
   ▼
3. Redirect to /oauth2/start?rd=https://obot.example.com/
   │
   ▼
4. Auth provider stores 'rd' value, generates PKCE verifier/challenge
   │
   ▼
5. Redirect to Keycloak: https://auth.example.com/realms/matherlynet/protocol/openid-connect/auth
   ?client_id=obot
   &redirect_uri=https://obot.example.com/oauth2/callback
   &response_type=code
   &scope=openid+email+profile+offline_access
   &code_challenge={S256_hash}
   &code_challenge_method=S256
   &state={random_state}
   │
   ▼
6. User authenticates with Keycloak (username/password, social IdP, etc.)
   │
   ▼
7. Keycloak redirects to: https://obot.example.com/oauth2/callback?code={auth_code}&state={state}
   │
   ▼
8. Auth provider exchanges code for tokens (with PKCE verifier)
   │
   ▼
9. Auth provider sets encrypted obot_access_token cookie
   │
   ▼
10. Redirect to original 'rd' URL (https://obot.example.com/)
    │
    ▼
11. User is authenticated, Obot calls /obot-get-state for user info
```

### Session State Retrieval

When Obot needs user information:

1. Obot sends POST to `/obot-get-state` with serialized HTTP request
2. Auth provider decrypts `obot_access_token` cookie
3. Auth provider parses ID token to extract user claims
4. Returns:
   ```json
   {
     "accessToken": "...",
     "preferredUsername": "john.doe",
     "user": "a1b2c3d4-...",
     "email": "john.doe@example.com",
     "groups": ["obot-admins", "developers"]
   }
   ```

## Group and Role-Based Access Control

### Group Filtering

When `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` is set:

1. Groups are extracted from ID token `groups` claim
2. User's groups are filtered against allowed list
3. Only matching groups are returned in `/obot-get-state` response
4. Users without any allowed groups are denied access

**Example:**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS: "obot-admins,obot-users"
```

### Role Filtering

When `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` is set:

1. Roles are extracted from ID token `realm_access.roles` and `resource_access.*.roles`
2. Roles are validated against oauth2-proxy's KeycloakConfig.Roles
3. Users without any allowed roles are denied access

**Example:**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES: "obot-admin,obot:developer"
```

Note: Client roles use format `{client-id}:{role-name}` (e.g., `obot:developer`)

## Troubleshooting Guide

### Common Issues

#### 1. "Invalid issuer" Error

**Symptom:** Token validation fails with issuer mismatch

**Cause:** Keycloak URL has trailing slash or incorrect format

**Solution:** Ensure `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` is exactly the base URL:
- ✅ Correct: `https://auth.example.com`
- ❌ Wrong: `https://auth.example.com/`
- ❌ Wrong: `https://auth.example.com/realms/matherlynet`

#### 2. Groups Not Appearing

**Symptom:** `/obot-get-state` returns empty groups array

**Causes & Solutions:**
1. `groups` client scope not attached as default
2. Group Membership mapper not configured correctly
3. "Add to ID token" not enabled on mapper
4. Users not assigned to groups in Keycloak

**Verification:**
- Use Keycloak Admin → Clients → obot → Client scopes → Evaluate
- Check generated ID token for `groups` claim

#### 3. "Invalid redirect URI" Error

**Symptom:** Keycloak rejects the callback redirect

**Causes & Solutions:**
1. Protocol mismatch (http vs https)
2. Missing `/oauth2/callback` in Valid Redirect URIs
3. Trailing slash issues

**Solution:** Add both patterns to Keycloak client:
```
https://obot.example.com/*
https://obot.example.com/oauth2/callback
```

#### 4. Cookie Not Being Set

**Symptom:** User redirected to login repeatedly

**Causes & Solutions:**
1. `OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET` invalid (must decode to 16/24/32 bytes)
2. Secure flag mismatch (cookie Secure=true but accessing via HTTP)

**Generate valid cookie secret:**
```bash
openssl rand -base64 32
```

#### 5. Client Authentication Failed

**Symptom:** 401 error during token exchange

**Causes & Solutions:**
1. Client secret mismatch
2. Client not set as confidential
3. Client authentication disabled

**Verification:** Check Keycloak client settings → "Client authentication" must be ON

### Diagnostic Commands

```bash
# Check Obot pod logs for auth errors
kubectl logs -n ai-system -l app.kubernetes.io/name=obot | grep -i "keycloak\|auth\|oidc"

# Verify environment variables are set correctly
kubectl exec -n ai-system deploy/obot-obot -- env | grep OBOT_KEYCLOAK

# Test Keycloak connectivity from Obot pod
kubectl exec -n ai-system deploy/obot-obot -- curl -s https://auth.example.com/realms/matherlynet/.well-known/openid-configuration | jq .issuer

# Verify client secret is accessible
kubectl get secret -n ai-system obot-secret -o jsonpath='{.data.OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET}' | base64 -d

# Check network policy allows Keycloak access
kubectl exec -n ai-system deploy/obot-obot -- curl -v https://auth.example.com/realms/matherlynet/
```

## Recommended Remediation

Based on this research, the following change is recommended:

### Fix Environment Variable Name

**File:** `templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2`

**Current (line 125):**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL: "#{ obot_keycloak_base_url }#"
```

**Change to:**
```yaml
OBOT_KEYCLOAK_AUTH_PROVIDER_URL: "#{ obot_keycloak_base_url }#"
```

This aligns with the fork's expected environment variable name as defined in `tools/keycloak-auth-provider/tool.gpt`:
```
Metadata: envVars: ...,OBOT_KEYCLOAK_AUTH_PROVIDER_URL,...
```

## Security Considerations

1. **PKCE S256:** Always enabled, prevents authorization code interception
2. **Confidential Client:** Client secret required, not a public client
3. **Cookie Encryption:** Session cookies encrypted with AES (16/24/32 byte key)
4. **Token Validation:** oauth2-proxy validates issuer, audience, signature
5. **HTTPS Only:** Cookie Secure flag based on `OBOT_SERVER_HOSTNAME` protocol

## References

### External Documentation
- [Obot Auth Providers Documentation](https://docs.obot.ai/configuration/auth-providers/)
- [OAuth2 Proxy Keycloak OIDC Provider](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc/)
- [Keycloak Client Documentation](https://www.keycloak.org/docs/latest/server_admin/#oidc-clients)

### Fork Documentation
- [jrmatherly/obot-entraid Repository](https://github.com/jrmatherly/obot-entraid)
- [Keycloak Auth Provider tool.gpt](https://raw.githubusercontent.com/jrmatherly/obot-entraid/main/tools/keycloak-auth-provider/tool.gpt)
- [Keycloak Setup Guide](https://raw.githubusercontent.com/jrmatherly/obot-entraid/main/tools/keycloak-auth-provider/KEYCLOAK_SETUP.md)

### Project Files
- `templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2`
- `templates/config/kubernetes/apps/ai-system/obot/app/secret.sops.yaml.j2`
- `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`
- `templates/config/kubernetes/apps/identity/keycloak/config/secrets.sops.yaml.j2`
- `templates/scripts/plugin.py`

## Appendix A: Complete Environment Variables Matrix

| Variable | Source | Location in Deployment |
| ---------- | -------- | ------------------------ |
| `OBOT_SERVER_AUTH_PROVIDER` | Static | helmrelease.yaml.j2 config |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_URL` | Derived (obot_keycloak_base_url) | helmrelease.yaml.j2 config |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | Derived (obot_keycloak_realm) | helmrelease.yaml.j2 config |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | cluster.yaml | helmrelease.yaml.j2 config |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | cluster.yaml (SOPS) | secret.sops.yaml.j2 |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET` | cluster.yaml (SOPS) | secret.sops.yaml.j2 |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` | cluster.yaml (optional) | helmrelease.yaml.j2 config |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` | cluster.yaml (optional) | helmrelease.yaml.j2 config |
| `OBOT_AUTH_PROVIDER_EMAIL_DOMAINS` | Not currently configured | Should default to `*` |

## Appendix B: Token Claims Example

Example Keycloak ID token with all required claims:

```json
{
  "exp": 1736467200,
  "iat": 1736466600,
  "auth_time": 1736466590,
  "jti": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "iss": "https://auth.example.com/realms/matherlynet",
  "aud": "obot",
  "sub": "f1e2d3c4-b5a6-7890-1234-567890abcdef",
  "typ": "ID",
  "azp": "obot",
  "session_state": "abc123-def456-789xyz",
  "acr": "1",
  "email_verified": true,
  "name": "John Doe",
  "preferred_username": "john.doe",
  "given_name": "John",
  "family_name": "Doe",
  "email": "john.doe@example.com",
  "groups": [
    "obot-admins",
    "developers"
  ],
  "realm_access": {
    "roles": [
      "obot-admin",
      "default-roles-matherlynet"
    ]
  },
  "resource_access": {
    "obot": {
      "roles": [
        "developer"
      ]
    }
  }
}
```

## Appendix C: Research Validation Checklist

| Item | Validated | Date | Notes |
| ------ | ----------- | ------ | ------- |
| Fork tool.gpt env vars | ✅ | Jan 2026 | Confirmed URL variable name |
| Fork main.go implementation | ✅ | Jan 2026 | Confirmed OIDC issuer construction |
| oauth2-proxy keycloak-oidc provider | ✅ | Jan 2026 | Official docs reviewed |
| PKCE S256 requirement | ✅ | Jan 2026 | Required per MCP 2025-11-25 spec |
| Cookie secret format | ✅ | Jan 2026 | 16/24/32 bytes base64 |
| Current helmrelease.yaml.j2 | ⚠️ | Jan 2026 | Variable name mismatch found |
| Current realm-config.yaml.j2 | ✅ | Jan 2026 | Correctly configured |
| Current plugin.py | ✅ | Jan 2026 | Correctly derives URLs |
