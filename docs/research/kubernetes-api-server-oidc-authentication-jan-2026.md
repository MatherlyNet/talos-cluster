# Kubernetes API Server OIDC Authentication Implementation

**Date**: January 12, 2026
**Status**: Implementation Required
**Priority**: Critical - Blocks Headlamp authentication
**Related Issue**: Headlamp "invalid request" callback error

## Executive Summary

This document provides a comprehensive implementation guide for configuring Kubernetes API Server OIDC authentication using Keycloak as the identity provider. The implementation creates a dedicated `kubernetes` OIDC client in Keycloak that enables Kubernetes web UIs (like Headlamp) and CLI tools to authenticate users via OIDC tokens.

### Current State

- ✅ Keycloak deployed and operational (`keycloak_enabled: true`)
- ✅ Headlamp deployed with OIDC configuration
- ✅ Keycloak client `headlamp` exists with proper redirect URIs
- ❌ **Kubernetes API Server lacks OIDC configuration** (root cause)
- ❌ Headlamp authentication fails with "invalid request" after OAuth callback

### Root Cause

Headlamp uses a two-phase authentication flow:
1. **Phase 1** (Browser): User authenticates with Keycloak → Gets authorization code ✅ Works
2. **Phase 2** (API Access): Headlamp exchanges code for ID token → Uses token to access Kubernetes API ❌ **Fails**

The Kubernetes API Server **rejects the ID token** because it has no OIDC configuration and doesn't know about Keycloak as an identity provider.

## Architecture Overview

### Authentication Flow

```
┌─────────────┐
│   Browser   │
│    (User)   │
└──────┬──────┘
       │ 1. Click "Sign in with Keycloak"
       ▼
┌─────────────────────────────────────────────┐
│           Headlamp (Web UI)                 │
│  Redirects to Keycloak /auth endpoint       │
└──────┬──────────────────────────────────────┘
       │ 2. Redirect to Keycloak
       ▼
┌─────────────────────────────────────────────┐
│          Keycloak OIDC Provider             │
│ https://sso.matherly.net/realms/matherlynet │
└──────┬──────────────────────────────────────┘
       │ 3. User logs in (Google IdP)
       │ 4. Returns authorization code
       ▼
┌─────────────────────────────────────────────┐
│           Headlamp (Callback)               │
│  /oidc-callback?code=xxx&state=yyy          │
│  - Exchanges code for ID token              │
│  - Stores token in browser                  │
└──────┬──────────────────────────────────────┘
       │ 5. Uses ID token in Authorization header
       ▼
┌─────────────────────────────────────────────┐
│      Kubernetes API Server                  │
│  ❌ REJECTS: No OIDC config!                │
│  ✅ WITH OIDC: Validates token against      │
│     Keycloak issuer, maps claims to user    │
└─────────────────────────────────────────────┘
```

### Why API Server OIDC Configuration Is Required

When a user authenticates:
1. Headlamp receives an **ID token** from Keycloak (JWT format)
2. Headlamp sends Kubernetes API requests with: `Authorization: Bearer <id_token>`
3. API Server must:
   - Verify token signature against Keycloak's public keys
   - Validate issuer (`iss` claim) matches configured `--oidc-issuer-url`
   - Validate audience (`aud` claim) matches configured `--oidc-client-id`
   - Extract username from configured claim (e.g., `email`)
   - Extract groups from configured claim (e.g., `groups`)
   - Apply Kubernetes RBAC based on mapped user/groups

**Without OIDC configuration**, the API Server has no way to validate tokens and will reject all requests with bearer tokens.

## Implementation Plan

### Prerequisites

- Talos Linux cluster (v1.12.0+)
- Keycloak deployed and operational
- `kubectl` and `talosctl` CLI access
- Admin access to update Talos configuration

### Phase 1: Create Dedicated Kubernetes Client in Keycloak

#### 1.1 Add Configuration Variables to cluster.yaml

```yaml
# =============================================================================
# KUBERNETES API SERVER OIDC AUTHENTICATION
# =============================================================================
# -- Enable OIDC authentication on Kubernetes API Server
#    When enabled, configures kube-apiserver with OIDC provider settings
#    (OPTIONAL) / (DEFAULT: false) / (REQUIRES: keycloak_enabled: true)
kubernetes_oidc_enabled: true

# -- OIDC client ID for Kubernetes API Server token validation
#    This is the audience (aud) claim expected in ID tokens
#    (REQUIRED when kubernetes_oidc_enabled: true) / (DEFAULT: "kubernetes")
kubernetes_oidc_client_id: "kubernetes"

# -- OIDC client secret for the Kubernetes client
#    Used for token introspection and client authentication
#    Generate with: openssl rand -hex 32
#    (REQUIRED when kubernetes_oidc_enabled: true)
kubernetes_oidc_client_secret: "CHANGEME_RUN_openssl_rand_hex_32"

# -- OIDC username claim to use for Kubernetes user identity
#    Common values: "email", "preferred_username", "sub"
#    (OPTIONAL) / (DEFAULT: "email")
kubernetes_oidc_username_claim: "email"

# -- OIDC username prefix to avoid conflicts with other auth methods
#    Set to "-" to disable prefixing
#    (OPTIONAL) / (DEFAULT: "oidc:")
kubernetes_oidc_username_prefix: "oidc:"

# -- OIDC groups claim to use for Kubernetes RBAC group membership
#    (OPTIONAL) / (DEFAULT: "groups")
kubernetes_oidc_groups_claim: "groups"

# -- OIDC groups prefix to avoid conflicts with other auth methods
#    (OPTIONAL) / (DEFAULT: "oidc:")
kubernetes_oidc_groups_prefix: "oidc:"

# -- OIDC signing algorithms accepted by API Server
#    (OPTIONAL) / (DEFAULT: "RS256")
kubernetes_oidc_signing_algs: "RS256"
```

#### 1.2 Update Keycloak Realm Configuration

Add to `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`:

```yaml
#% if kubernetes_oidc_enabled | default(false) %#
      #| =========================================================================== #|
      #| KUBERNETES API SERVER OIDC CLIENT                                           #|
      #| Dedicated client for Kubernetes API Server OIDC authentication              #|
      #| Used by: Headlamp, kubectl with oidc-login, kubelogin, and future tools    #|
      #| clientId and secret use $(env:VAR) substitution from keycloak-realm-secrets #|
      #| REF: docs/research/kubernetes-api-server-oidc-authentication-jan-2026.md    #|
      #| =========================================================================== #|
      - clientId: "$(env:KUBERNETES_CLIENT_ID)"
        name: "Kubernetes API Server"
        description: "OIDC client for Kubernetes API Server authentication - enables kubectl and web UI access via OIDC tokens"
        enabled: true
        publicClient: false
        clientAuthenticatorType: "client-secret"
        secret: "$(env:KUBERNETES_CLIENT_SECRET)"
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        serviceAccountsEnabled: false
        implicitFlowEnabled: false
        protocol: "openid-connect"
        #| Redirect URIs for kubectl oidc-login and kubelogin plugins #|
        redirectUris:
          - "http://localhost:8000/*"
          - "http://localhost:18000/*"
        #| Web origins not critical for API server validation #|
        webOrigins:
          - "+"
        #| No PKCE required for confidential client with client_secret #|
        attributes:
          pkce.code.challenge.method: ""
          post.logout.redirect.uris: "http://localhost:8000/*"
        #| Default scopes for Kubernetes authentication #|
        defaultClientScopes:
          - "profile"
          - "email"
          - "offline_access"
          - "groups"  # Critical for RBAC group membership
        optionalClientScopes:
          - "address"
          - "phone"
        #| Protocol mappers to include required claims in tokens #|
        protocolMappers:
          - name: "realm-roles"
            protocol: "openid-connect"
            protocolMapper: "oidc-usermodel-realm-role-mapper"
            consentRequired: false
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
            consentRequired: false
            config:
              claim.name: "groups"
              full.path: "false"
              id.token.claim: "true"
              access.token.claim: "true"
              userinfo.token.claim: "true"
          - name: "email"
            protocol: "openid-connect"
            protocolMapper: "oidc-usermodel-property-mapper"
            consentRequired: false
            config:
              user.attribute: "email"
              claim.name: "email"
              id.token.claim: "true"
              access.token.claim: "true"
              userinfo.token.claim: "true"
              jsonType.label: "String"
          - name: "email_verified"
            protocol: "openid-connect"
            protocolMapper: "oidc-usermodel-property-mapper"
            consentRequired: false
            config:
              user.attribute: "emailVerified"
              claim.name: "email_verified"
              id.token.claim: "true"
              access.token.claim: "true"
              userinfo.token.claim: "true"
              jsonType.label: "boolean"
#% endif %#
```

#### 1.3 Update Keycloak Realm Secrets

Add to `templates/config/kubernetes/apps/identity/keycloak/config/secrets.sops.yaml.j2`:

```yaml
#% if kubernetes_oidc_enabled | default(false) %#
  #| Kubernetes API Server OIDC client credentials #|
  KUBERNETES_CLIENT_ID: "#{ kubernetes_oidc_client_id | default('kubernetes') }#"
  KUBERNETES_CLIENT_SECRET: "#{ kubernetes_oidc_client_secret }#"
#% endif %#
```

#### 1.4 Update Conditional Check

Modify the conditional check at line 136 to include `kubernetes_oidc_enabled`:

```yaml
#% if keycloak_bootstrap_oidc_client | default(false) or grafana_oidc_enabled | default(false) or litellm_oidc_enabled | default(false) or obot_keycloak_enabled | default(false) or headlamp_enabled | default(false) or langfuse_scim_sync_enabled | default(false) or kubernetes_oidc_enabled | default(false) %#
```

### Phase 2: Configure Talos API Server

#### 2.1 Update Talos Cluster Patch

Edit `/Users/jason/dev/IaC/matherlynet-talos-cluster/talos/patches/controller/cluster.yaml`:

```yaml
cluster:
  allowSchedulingOnControlPlanes: false
  apiServer:
    admissionControl:
      $$patch: delete
    extraArgs:
      # https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/
      enable-aggregator-routing: true
      # Enable ImageVolume feature gate for CNPG managed extensions
      feature-gates: ImageVolume=true
      # OIDC Authentication Configuration
      oidc-issuer-url: "https://sso.matherly.net/realms/matherlynet"
      oidc-client-id: "kubernetes"
      oidc-username-claim: "email"
      oidc-username-prefix: "oidc:"
      oidc-groups-claim: "groups"
      oidc-groups-prefix: "oidc:"
      oidc-signing-algs: "RS256"
  controllerManager:
    extraArgs:
      bind-address: 0.0.0.0
  coreDNS:
    disabled: true
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
    advertisedSubnets:
      - 192.168.20.0/22
  proxy:
    disabled: true
  scheduler:
    extraArgs:
      bind-address: 0.0.0.0
```

**Note**: Values should be **hardcoded** in Talos patches, not templated. Talos doesn't support Jinja2 templating.

### Phase 3: Update Headlamp Configuration

#### 3.1 Update Headlamp to Use Kubernetes Client ID

Edit `templates/config/kubernetes/apps/kube-system/headlamp/app/helmrelease.yaml.j2`:

Change the OIDC client configuration:

```yaml
config:
  oidc:
    clientID: kubernetes  # Changed from "headlamp"
    clientSecret: #{ kubernetes_oidc_client_secret }#  # Use kubernetes client secret
    issuerURL: https://sso.matherly.net/realms/matherlynet
    scopes: openid,profile,email,groups
    secret:
      create: true
      name: headlamp-oidc
```

**Rationale**: Headlamp should use the same client ID that the API Server validates against. This ensures token audience (`aud`) matches API Server expectations.

### Phase 4: Implementation Steps

#### 4.1 Generate Client Secret

```bash
# Generate a secure random secret
openssl rand -hex 32
# Example output: a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

#### 4.2 Update cluster.yaml

```bash
cd /Users/jason/dev/IaC/matherlynet-talos-cluster

# Add configuration to cluster.yaml
vim cluster.yaml

# Add these lines (replace secret with generated value):
kubernetes_oidc_enabled: true
kubernetes_oidc_client_id: "kubernetes"
kubernetes_oidc_client_secret: "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456"
kubernetes_oidc_username_claim: "email"
kubernetes_oidc_username_prefix: "oidc:"
kubernetes_oidc_groups_claim: "groups"
kubernetes_oidc_groups_prefix: "oidc:"
kubernetes_oidc_signing_algs: "RS256"
```

#### 4.3 Update Templates

```bash
# Update Keycloak realm config template
vim templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2
# Add kubernetes client configuration (see Phase 1.2)

# Update Keycloak secrets template
vim templates/config/kubernetes/apps/identity/keycloak/config/secrets.sops.yaml.j2
# Add kubernetes client secret mapping (see Phase 1.3)

# Update Headlamp HelmRelease
vim templates/config/kubernetes/apps/kube-system/headlamp/app/helmrelease.yaml.j2
# Update clientID to "kubernetes" (see Phase 3.1)
```

#### 4.4 Update Talos Patch (Hardcoded Values)

```bash
# Update Talos controller patch
vim talos/patches/controller/cluster.yaml
# Add OIDC extraArgs to apiServer section (see Phase 2.1)
```

#### 4.5 Regenerate and Apply Configuration

```bash
# Regenerate all configurations
task configure -y

# Verify SOPS encryption worked
sops -d kubernetes/identity/keycloak/config/secrets.sops.yaml | grep KUBERNETES

# Apply Talos configuration to control plane nodes
task talos:apply-node IP=192.168.22.101
task talos:apply-node IP=192.168.22.102
task talos:apply-node IP=192.168.22.103

# Verify API Server restarted with new config
kubectl get pods -n kube-system | grep kube-apiserver
```

**Note**: Talos applies changes on-the-fly. No reboot required. API Server pods will restart automatically.

#### 4.6 Verify API Server Configuration

```bash
# Check API Server command line (from any control plane node)
talosctl -n 192.168.22.101 get manifests

# Or inspect kube-apiserver process
talosctl -n 192.168.22.101 logs controller-runtime | grep oidc
```

Expected output should show:
```
--oidc-issuer-url=https://sso.matherly.net/realms/matherlynet
--oidc-client-id=kubernetes
--oidc-username-claim=email
--oidc-groups-claim=groups
```

#### 4.7 Apply Keycloak Configuration

```bash
# Force reconciliation of Keycloak config
flux reconcile kustomization keycloak-config -n identity

# Verify Job runs
kubectl get jobs -n identity keycloak-config-apply

# Check Job logs
kubectl logs -n identity job/keycloak-config-apply --tail=50

# Verify kubernetes client exists in Keycloak
kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get clients -r matherlynet \
  --fields clientId,enabled | grep kubernetes
```

Expected output:
```json
{
  "clientId": "kubernetes",
  "enabled": true
}
```

#### 4.8 Reconcile Headlamp

```bash
# Force Headlamp HelmRelease reconciliation
flux reconcile helmrelease headlamp -n kube-system

# Verify Headlamp pods restart with new config
kubectl get pods -n kube-system -l app.kubernetes.io/name=headlamp

# Check Headlamp secret has new clientID
kubectl get secret -n kube-system headlamp-oidc -o jsonpath='{.data.clientID}' | base64 -d
```

Expected output: `kubernetes`

### Phase 5: Testing and Validation

#### 5.1 Test Headlamp Login

1. Navigate to `https://headlamp.matherly.net`
2. Click "Sign in with Keycloak"
3. Log in with Google account
4. **Expected**: Successful redirect to Headlamp dashboard
5. **Expected**: No "invalid request" error

#### 5.2 Verify Token Validation

```bash
# Get a token using kubectl oidc-login (if installed)
kubectl oidc-login setup \
  --oidc-issuer-url=https://sso.matherly.net/realms/matherlynet \
  --oidc-client-id=kubernetes \
  --oidc-client-secret=<secret>

# Test API access with token
kubectl get nodes --token=<token-from-oidc-login>
```

#### 5.3 Check API Server Logs

```bash
# Look for OIDC authentication success/failure
talosctl -n 192.168.22.101 logs controller-runtime | grep -i "oidc\|authentication"
```

#### 5.4 Verify RBAC Mapping

```bash
# Check user identity as seen by Kubernetes
kubectl auth whoami

# Expected output (after successful OIDC login):
# Username: oidc:user@matherly.net
# Groups:   [oidc:admin system:authenticated]
```

#### 5.5 Test Group-Based RBAC

Create a test RoleBinding:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: oidc:admin
  apiGroup: rbac.authorization.k8s.io
```

Apply and test:
```bash
kubectl apply -f test-rolebinding.yaml
# Log in via Headlamp as user with "admin" group
# Verify full cluster access
```

## Configuration Reference

### API Server OIDC Flags

| Flag | Value | Purpose |
| ------ | ------- | --------- |
| `oidc-issuer-url` | `https://sso.matherly.net/realms/matherlynet` | OIDC provider URL for token validation |
| `oidc-client-id` | `kubernetes` | Expected audience (`aud`) in ID tokens |
| `oidc-username-claim` | `email` | Token claim to use as Kubernetes username |
| `oidc-username-prefix` | `oidc:` | Prefix added to usernames to avoid conflicts |
| `oidc-groups-claim` | `groups` | Token claim containing group memberships |
| `oidc-groups-prefix` | `oidc:` | Prefix added to groups to avoid conflicts |
| `oidc-signing-algs` | `RS256` | Accepted JWT signing algorithms |

### Keycloak Client Configuration

| Setting | Value | Purpose |
| --------- | ------- | --------- |
| Client ID | `kubernetes` | Identifier for API Server token validation |
| Client Type | Confidential | Requires client_secret for authentication |
| Standard Flow | Enabled | Supports authorization code flow |
| Direct Access Grants | Disabled | Disables password grant (security best practice) |
| Service Accounts | Disabled | Not needed for user authentication |
| Redirect URIs | `http://localhost:8000/*` | For kubectl oidc-login plugin |
| Default Scopes | `profile`, `email`, `offline_access`, `groups` | Claims included in tokens |

### Token Claims Structure

Example ID token claims after successful authentication:

```json
{
  "iss": "https://sso.matherly.net/realms/matherlynet",
  "aud": "kubernetes",
  "sub": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
  "email": "user@matherly.net",
  "email_verified": true,
  "groups": ["admin", "operators"],
  "roles": ["admin"],
  "preferred_username": "user@matherly.net",
  "exp": 1736707200,
  "iat": 1736707140
}
```

Mapped to Kubernetes:
- **Username**: `oidc:user@matherly.net` (from `email` claim)
- **Groups**: `["oidc:admin", "oidc:operators"]` (from `groups` claim)

## Security Considerations

### 1. Token Validation

- API Server validates token signature using Keycloak's public keys (JWKS endpoint)
- Issuer (`iss`) must exactly match `--oidc-issuer-url`
- Audience (`aud`) must exactly match `--oidc-client-id`
- Token expiration (`exp`) enforced - expired tokens rejected

### 2. Transport Security

- All Keycloak communication via HTTPS (TLS)
- API Server fetches JWKS over HTTPS
- Client secret transmitted only during token exchange (encrypted in transit)

### 3. RBAC Best Practices

```yaml
# Use group-based RBAC (scalable)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: oidc:admin  # Keycloak group "admin" → "oidc:admin"
  apiGroup: rbac.authorization.k8s.io
```

### 4. Secret Management

- Client secret SOPS-encrypted in Git
- Secret rotation: Update in Keycloak and cluster.yaml, then `task configure`
- Use strong secrets: `openssl rand -hex 32`

### 5. User Prefixes

Using `oidc:` prefix for usernames and groups prevents conflicts with:
- Kubernetes system users (`system:*`)
- Service accounts (`system:serviceaccount:*`)
- Node identities (`system:node:*`)
- Other authentication methods (certificates, tokens)

## Troubleshooting

### Issue: "invalid request" Error After Callback

**Symptom**: Headlamp redirects to `/oidc-callback?code=...` but shows "invalid request"

**Diagnosis**:
```bash
# Check Headlamp logs
kubectl logs -n kube-system -l app.kubernetes.io/name=headlamp --tail=100

# Check API Server logs
talosctl -n 192.168.22.101 logs controller-runtime | grep -i "oidc\|authentication" | tail -50
```

**Common Causes**:
1. API Server OIDC not configured → **Implement this guide**
2. Wrong client ID in token audience → Verify `oidc-client-id` matches token `aud`
3. Token expired → Check token expiration (`exp` claim)
4. Signature validation failed → Verify issuer URL accessibility

### Issue: API Server Fails to Start After OIDC Configuration

**Symptom**: kube-apiserver pods CrashLoopBackOff

**Diagnosis**:
```bash
talosctl -n 192.168.22.101 logs controller-runtime | grep -i error
```

**Common Causes**:
1. Invalid `oidc-issuer-url` → Must be HTTPS, accessible from control plane
2. JWKS endpoint unreachable → API Server must reach `{issuer}/.well-known/openid-configuration`
3. Syntax error in extraArgs → Verify YAML formatting

**Solution**: Remove OIDC config from Talos patch, reapply, debug issuer connectivity

### Issue: Token Rejected - "Unable to authenticate the request"

**Symptom**: kubectl or Headlamp shows 401 Unauthorized

**Diagnosis**:
```bash
# Decode token to inspect claims
echo "<token>" | cut -d. -f2 | base64 -d | jq

# Check issuer
jq -r '.iss'

# Check audience
jq -r '.aud'

# Check expiration
jq -r '.exp' | xargs -I{} date -r {}
```

**Common Causes**:
1. Issuer mismatch → `iss` claim ≠ `--oidc-issuer-url`
2. Audience mismatch → `aud` claim ≠ `--oidc-client-id`
3. Token expired → `exp` claim in past
4. Wrong client used → Token from `headlamp` client, API Server expects `kubernetes` client

### Issue: User Has No Permissions

**Symptom**: Authentication succeeds but "Forbidden" on all operations

**Diagnosis**:
```bash
# Check user identity
kubectl auth whoami

# Check effective permissions
kubectl auth can-i --list --as=oidc:user@matherly.net
```

**Solution**: Create RoleBinding/ClusterRoleBinding for user or group:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-user-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: User
  name: oidc:user@matherly.net
  apiGroup: rbac.authorization.k8s.io
```

### Issue: Groups Not Working

**Symptom**: User authenticated but groups not applied to RBAC

**Diagnosis**:
```bash
# Check token groups claim
echo "<token>" | cut -d. -f2 | base64 -d | jq -r '.groups'

# Verify groups-claim configured
talosctl -n 192.168.22.101 get manifests | grep oidc-groups-claim
```

**Common Causes**:
1. `groups` not in token → Verify Keycloak client has groups scope
2. Wrong claim name → Check `--oidc-groups-claim` matches token claim
3. Missing protocol mapper → Add groups mapper to Keycloak client

## Future Enhancements

### 1. Multiple OIDC Providers

Use modern `--authentication-config` file approach (Kubernetes 1.26+):

```yaml
# /etc/kubernetes/oidc-config.yaml
apiVersion: apiserver.config.k8s.io/v1alpha1
kind: AuthenticationConfiguration
jwt:
- issuer:
    url: https://sso.matherly.net/realms/matherlynet
    audiences:
    - kubernetes
  claimMappings:
    username:
      claim: email
      prefix: "oidc:"
    groups:
      claim: groups
      prefix: "oidc:"
- issuer:
    url: https://github-idp.example.com
    audiences:
    - kubernetes-github
  claimMappings:
    username:
      claim: sub
      prefix: "github:"
```

### 2. kubectl oidc-login Plugin

Install for CLI authentication:

```bash
# Install plugin
kubectl krew install oidc-login

# Configure kubeconfig
kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url=https://sso.matherly.net/realms/matherlynet \
  --exec-arg=--oidc-client-id=kubernetes \
  --exec-arg=--oidc-client-secret=<secret>
```

### 3. Service Account Token Federation

Keycloak 26.5.0+ supports authenticating clients with Kubernetes service account tokens, eliminating static client secrets.

## References

### Official Documentation

- [Kubernetes Authentication - OIDC](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens)
- [kube-apiserver OIDC Flags](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)
- [Keycloak Server Configuration](https://www.keycloak.org/server/configuration)
- [Talos Kubernetes Customization](https://www.talos.dev/latest/kubernetes-guides/configuration/)

### Implementation Guides

- [Kubernetes API-Server with Multiple IdPs](https://a-cup-of.coffee/blog/apiserver-multi-idp/)
- [Enable OIDC Server - Cozystack](https://cozystack.io/docs/operations/oidc/enable_oidc/)
- [Kubernetes Authentication: OIDC with Keycloak](https://fenyuk.medium.com/kubernetes-authentication-oidc-with-keycloak-47c4d02133e2)
- [Configuring Talos for OIDC Authentication](https://documentation.breadnet.co.uk/kubernetes/oidc/talos-oidc-pocket-id/)
- [OIDC setup for K8s apiserver - Talos Discussion](https://github.com/siderolabs/talos/discussions/6880)

### Project Documentation

- `/docs/guides/native-oidc-securitypolicy-implementation.md` - Gateway OIDC patterns
- `/docs/ai-context/cilium-networking.md` - Split-path OIDC architecture
- `/templates/config/kubernetes/apps/identity/keycloak/` - Keycloak templates

### Tools

- [kubectl oidc-login](https://github.com/int128/kubelogin) - kubectl OIDC authentication plugin
- [kubelogin](https://github.com/Azure/kubelogin) - Alternative OIDC plugin (Azure-focused)
- [SOPS](https://github.com/getsops/sops) - Secrets encryption

## Conclusion

This implementation establishes Kubernetes API Server OIDC authentication using Keycloak, enabling:

1. ✅ Headlamp web UI authentication via OIDC
2. ✅ kubectl CLI authentication via oidc-login plugin
3. ✅ Group-based RBAC using Keycloak groups
4. ✅ Centralized identity management through Keycloak
5. ✅ Federation with external IdPs (Google, GitHub, Microsoft)
6. ✅ Scalable authentication for future Kubernetes tools

**Next Steps**: Follow Phase 4 implementation steps to deploy this configuration.

---

**Document Version**: 1.0
**Last Updated**: January 12, 2026
**Author**: AI Research Agent (Claude Sonnet 4.5)
**Review Status**: Ready for Implementation
