# Keycloak Security Hardening Implementation Guide (UPDATED)

**Date:** January 12, 2026 (Updated: January 12, 2026)
**Status:** Implementation Guide - Updated for Kubernetes API Server OIDC
**Based On:** Security Analysis Report (January 12, 2026)
**Keycloak Version:** 26.5.0
**Effort:** 1-2 hours

> **UPDATE (January 13, 2026):** This guide has been corrected to reflect the actual SHARED CLIENT architecture for Headlamp and Kubernetes API Server OIDC authentication. Previous documentation incorrectly described a separate `headlamp` client that caused authentication failures. The following architectural changes were implemented:
>
> 1. **Single shared `kubernetes` OIDC client** for ALL Kubernetes API Server authentication
> 2. **Headlamp uses the shared `kubernetes` client** (NOT a separate client) to ensure tokens have correct audience claims
> 3. **Architecture rationale:** Headlamp passes OIDC tokens to the Kubernetes API Server, which only accepts tokens with `aud: ["kubernetes"]`
> 4. **Multiple redirect URIs** in the single `kubernetes` client support both CLI (localhost) and web UI (Headlamp) OAuth flows
>
> The security analysis and implementation steps remain valid and have been updated to reflect the correct shared-client architecture.

---

## Overview

This guide implements three security improvements identified in the comprehensive Keycloak authentication security analysis:

1. **HIGH PRIORITY:** Enable realm events logging for security auditing
2. **MEDIUM PRIORITY:** Implement realm groups for enterprise RBAC
3. **LOW PRIORITY:** Add explicit network policy for Keycloak application

All changes follow GitOps principles and are implemented via Jinja2 templates.

---

## Prerequisites

- Keycloak 26.5+ deployed and operational
- Network policies enabled (`network_policies_enabled: true` in cluster.yaml)
- Access to modify templates and run `task configure`
- Understanding of Keycloak realm configuration
- **NEW:** Kubernetes API Server OIDC enabled (`kubernetes_oidc_enabled: true`)

---

## Architecture (January 2026)

### Shared Client Architecture (Current Implementation)

```
┌─────────────────────────────────────────────────────────────────┐
│                    SINGLE KEYCLOAK CLIENT                        │
│                    clientId: "kubernetes"                        │
│                    aud: ["kubernetes"]                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                │                               │
        ┌───────▼────────┐            ┌────────▼─────────┐
        │   Headlamp     │            │     kubectl      │
        │   (Web UI)     │            │  (CLI + oidc)    │
        └───────┬────────┘            └────────┬─────────┘
                │                               │
                └───────────────┬───────────────┘
                                │
                    ┌───────────▼────────────┐
                    │  Kubernetes API Server │
                    │  Validates aud claim:  │
                    │  aud == "kubernetes"   │
                    └────────────────────────┘
```

**Why Shared Client:**

1. ✅ **Token validation requirement:** API Server only accepts tokens with `aud: ["kubernetes"]`
2. ✅ **Headlamp architecture:** Headlamp passes OIDC tokens directly to Kubernetes API for all operations
3. ✅ **Audience claim consistency:** All users (web + CLI) use same client, ensuring consistent token validation
4. ✅ **Multiple redirect URIs:** Single client supports both localhost (CLI) and Headlamp web (browser) flows

**Benefits:**

- ✅ All tokens have correct `aud: ["kubernetes"]` claim for API Server validation
- ✅ No 401 Unauthorized errors from audience claim mismatches
- ✅ Simplified configuration with single client for all K8s access
- ✅ Standard OIDC pattern (multiple redirect URIs in one client)

### OIDC Client Matrix

| Client | Used By | Redirect URIs | PKCE | Audience |
| ------ | ------- | ------------- | ---- | -------- |
| **kubernetes** | Headlamp (web), kubectl (CLI), kubelogin, oidc-login | `http://localhost:8000/*`, `http://localhost:18000/*`, `https://headlamp.domain/oidc-callback` | Disabled | `kubernetes` |

---

## Implementation Priority Matrix

| Priority | Feature | Impact | Complexity | Time |
| -------- | ------- | ------ | ---------- | ---- |
| HIGH | Realm Events Logging | Security/Compliance | Low | 15 min |
| MEDIUM | Realm Groups | RBAC/Usability | Medium | 30 min |
| LOW | Network Policy | Defense-in-Depth | Low | 20 min |

---

## Part 1: Enable Realm Events Logging (HIGH PRIORITY)

### Why This Matters

**Security Benefits:**

- Audit trail for login/logout/admin events
- Compliance requirements (SOC2, ISO 27001)
- Troubleshooting authentication failures
- Detecting suspicious login patterns
- Integration with existing Grafana dashboards

**Current State:** No events logging configured
**Target State:** All authentication events logged to Keycloak server logs

### Implementation Steps

#### Step 1.1: Edit Realm Configuration Template

**File:** `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`

**Location:** After line 47 (end of `bruteForceProtected` section)

**Add the following configuration:**

```yaml
    #| =========================================================================== #|
    #| EVENTS CONFIGURATION - Security Auditing                                   #|
    #| Logs authentication events for compliance and troubleshooting               #|
    #| Events are written to Keycloak server logs and available via Admin API      #|
    #| =========================================================================== #|
    eventsEnabled: true
    eventsListeners:
      - "jboss-logging"
    adminEventsEnabled: true
    adminEventsDetailsEnabled: true

    #| Event types to capture (authentication and token lifecycle) #|
    enabledEventTypes:
      - "LOGIN"
      - "LOGIN_ERROR"
      - "LOGOUT"
      - "LOGOUT_ERROR"
      - "CODE_TO_TOKEN"
      - "CODE_TO_TOKEN_ERROR"
      - "REFRESH_TOKEN"
      - "REFRESH_TOKEN_ERROR"
      - "UPDATE_PASSWORD"
      - "UPDATE_PASSWORD_ERROR"
      - "REGISTER"
      - "REGISTER_ERROR"
      - "IDENTITY_PROVIDER_LOGIN"
      - "IDENTITY_PROVIDER_LOGIN_ERROR"
      - "UPDATE_PROFILE"
      - "UPDATE_PROFILE_ERROR"
```

**Complete Context (lines 40-72):**

```yaml
    #| =========================================================================== #|
    #| BRUTE FORCE PROTECTION                                                      #|
    #| =========================================================================== #|
    bruteForceProtected: true
    permanentLockout: false
    maxFailureWaitSeconds: 900
    minimumQuickLoginWaitSeconds: 60
    waitIncrementSeconds: 60
    quickLoginCheckMilliSeconds: 1000
    maxDeltaTimeSeconds: 43200
    failureFactor: 5

    #| =========================================================================== #|
    #| EVENTS CONFIGURATION - Security Auditing                                   #|
    #| Logs authentication events for compliance and troubleshooting               #|
    #| Events are written to Keycloak server logs and available via Admin API      #|
    #| =========================================================================== #|
    eventsEnabled: true
    eventsListeners:
      - "jboss-logging"
    adminEventsEnabled: true
    adminEventsDetailsEnabled: true

    #| Event types to capture (authentication and token lifecycle) #|
    enabledEventTypes:
      - "LOGIN"
      - "LOGIN_ERROR"
      - "LOGOUT"
      - "LOGOUT_ERROR"
      - "CODE_TO_TOKEN"
      - "CODE_TO_TOKEN_ERROR"
      - "REFRESH_TOKEN"
      - "REFRESH_TOKEN_ERROR"
      - "UPDATE_PASSWORD"
      - "UPDATE_PASSWORD_ERROR"
      - "REGISTER"
      - "REGISTER_ERROR"
      - "IDENTITY_PROVIDER_LOGIN"
      - "IDENTITY_PROVIDER_LOGIN_ERROR"
      - "UPDATE_PROFILE"
      - "UPDATE_PROFILE_ERROR"

    #| =========================================================================== #|
    #| REALM ROLES - Including auto-added IdP mapper roles                         #|
    #| =========================================================================== #|
```

#### Step 1.2: Apply Configuration

```bash
# Regenerate templates
task configure -y

# Verify generated file
cat kubernetes/apps/identity/keycloak/config/realm-config.yaml | grep -A 20 "eventsEnabled"

# Commit changes
git add templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2
git commit -m "feat(keycloak): enable realm events logging for security auditing"
git push

# Reconcile Flux
task reconcile

# Wait for keycloak-config-cli job to complete
kubectl wait --for=condition=complete job/keycloak-config-cli -n identity --timeout=120s
```

#### Step 1.3: Verify Events Logging

```bash
# Check if events are being logged
kubectl logs -n identity -l app.kubernetes.io/instance=keycloak | grep -i "event"

# Test login event (open browser, login to any OIDC-protected app)
# Then check logs:
kubectl logs -n identity -l app.kubernetes.io/instance=keycloak --tail=50 | grep "type=LOGIN"

# View events via Admin API (requires admin credentials)
kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get events \
  -r matherlynet \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n identity -o jsonpath='{.data.password}' | base64 -d)
```

#### Step 1.4: Configure Event Retention (Optional)

By default, Keycloak retains events indefinitely. To configure retention:

**Add to realm configuration (after `enabledEventTypes`):**

```yaml
    #| Event retention policy #|
    eventsExpiration: 604800  # 7 days in seconds
```

---

## Part 2: Implement Realm Groups (MEDIUM PRIORITY)

### Why This Matters

**Organizational Benefits:**

- Industry-standard RBAC pattern (groups → roles)
- Easier bulk user management
- Clearer access control policies
- Better scalability (20+ users)
- Separation of organizational structure from permissions

**Decision Point:** Choose between two architectures:

| Architecture | Best For | Complexity |
| ------------ | -------- | ---------- |
| **Roles-Only** (current) | Small teams (<20 users), simple structure | Low |
| **Groups + Roles** (recommended) | Growing teams, multiple access tiers | Medium |

### Implementation Steps (Groups + Roles Architecture)

#### Step 2.1: Define Group Structure

**Recommended Groups for matherlynet-talos-cluster:**

```yaml
groups:
  - name: "admin"
    path: "/admin"
    attributes:
      description: ["Platform administrators with full access"]
    realmRoles:
      - "platform-admin"
      - "grafana-admin"

  - name: "developer"
    path: "/developer"
    attributes:
      description: ["Development team with edit access"]
    realmRoles:
      - "grafana-editor"

  - name: "operators"
    path: "/operators"
    attributes:
      description: ["Operations/SRE team with operational access"]
    realmRoles:
      - "grafana-editor"

  - name: "viewers"
    path: "/viewers"
    attributes:
      description: ["Read-only access to dashboards and metrics"]
    realmRoles:
      - "grafana-viewer"
```

#### Step 2.2: Edit Realm Configuration Template

**File:** `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`

**Location:** After line 105 (end of roles section)

**Add the following configuration:**

```yaml
    #| =========================================================================== #|
    #| REALM GROUPS - Organizational Structure                                     #|
    #| Groups provide organizational hierarchy and default role assignment         #|
    #| Users inherit roles from their group membership                             #|
    #| REF: https://www.keycloak.org/docs/latest/server_admin/#groups              #|
    #| =========================================================================== #|
#% if keycloak_realm_groups is defined and keycloak_realm_groups %#
    groups:
#%   for group in keycloak_realm_groups %#
      - name: "#{ group.name }#"
        path: "/#{ group.name }#"
#%     if group.description is defined %#
        attributes:
          description: ["#{ group.description }#"]
#%     endif %#
#%     if group.realm_roles is defined and group.realm_roles %#
        realmRoles:
#%       for role in group.realm_roles %#
          - "#{ role }#"
#%       endfor %#
#%     endif %#
#%     if group.subgroups is defined and group.subgroups %#
        subGroups:
#%       for subgroup in group.subgroups %#
          - name: "#{ subgroup.name }#"
            path: "/#{ group.name }#/#{ subgroup.name }#"
#%         if subgroup.realm_roles is defined and subgroup.realm_roles %#
            realmRoles:
#%           for role in subgroup.realm_roles %#
              - "#{ role }#"
#%           endfor %#
#%         endif %#
#%       endfor %#
#%     endif %#
#%   endfor %#
#% endif %#
```

#### Step 2.3: Update cluster.yaml Configuration

**File:** `cluster.yaml`

**Add after the Keycloak roles configuration:**

```yaml
# =============================================================================
# KEYCLOAK REALM GROUPS - Optional organizational structure
# =============================================================================
# Groups provide organizational hierarchy with default role assignments.
# Users inherit roles from group membership for easier access management.
# (OPTIONAL) / Only needed when using groups-based RBAC
keycloak_realm_groups:
  - name: "admin"
    description: "Platform administrators with full access"
    realm_roles:
      - "platform-admin"
      - "grafana-admin"

  - name: "developer"
    description: "Development team with edit access"
    realm_roles:
      - "grafana-editor"

  - name: "operator"
    description: "Operations/SRE team with operational access"
    realm_roles:
      - "grafana-editor"

  - name: "viewer"
    description: "Read-only access to dashboards and metrics"
    realm_roles:
      - "grafana-viewer"
```

#### Step 2.4: Update JSON Schema (Optional but Recommended)

**File:** `.taskfiles/template/resources/cluster.schema.json`

**Add to properties section:**

```json
"keycloak_realm_groups": {
  "type": "array",
  "description": "Keycloak realm groups for organizational RBAC structure",
  "items": {
    "type": "object",
    "required": ["name"],
    "properties": {
      "name": {
        "type": "string",
        "description": "Group name"
      },
      "description": {
        "type": "string",
        "description": "Group description"
      },
      "realm_roles": {
        "type": "array",
        "description": "Realm roles assigned to group members",
        "items": {
          "type": "string"
        }
      },
      "subgroups": {
        "type": "array",
        "description": "Nested subgroups",
        "items": {
          "type": "object",
          "properties": {
            "name": {
              "type": "string"
            },
            "realm_roles": {
              "type": "array",
              "items": {
                "type": "string"
              }
            }
          }
        }
      }
    }
  }
}
```

#### Step 2.5: Apply Configuration

```bash
# Regenerate templates
task configure -y

# Verify generated groups
cat kubernetes/apps/identity/keycloak/config/realm-config.yaml | grep -A 30 "groups:"

# Commit changes
git add \
  cluster.yaml \
  templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2 \
  .taskfiles/template/resources/cluster.schema.json
git commit -m "feat(keycloak): add realm groups for enterprise RBAC structure"
git push

# Reconcile Flux
task reconcile

# Wait for config-cli job
kubectl wait --for=condition=complete job/keycloak-config-cli -n identity --timeout=120s
```

#### Step 2.6: Verify Groups Configuration

```bash
# List groups via Admin API
kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get groups \
  -r matherlynet \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n identity -o jsonpath='{.data.password}' | base64 -d)

# Expected output:
# [
#   {
#     "id": "...",
#     "name": "admin",
#     "path": "/admin",
#     "realmRoles": ["platform-admin", "grafana-admin"]
#   },
#   ...
# ]
```

#### Step 2.7: Assign Users to Groups

**Via Keycloak Admin Console:**

1. Navigate to: `https://sso.matherly.net/admin/master/console/#/matherlynet/users`
2. Select user → **Groups** tab
3. Click **Join Group**
4. Select group (`admin`, `developer`, etc.)
5. User now inherits all roles from that group

**Via Admin API:**

```bash
# Get user ID
USER_ID=$(kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get users \
  -r matherlynet \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n identity -o jsonpath='{.data.password}' | base64 -d) \
  -q username=jason@matherly.net \
  --fields id \
  --format csv --noquotes | tail -1)

# Get group ID
GROUP_ID=$(kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get groups \
  -r matherlynet \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n identity -o jsonpath='{.data.password}' | base64 -d) \
  -q name=admin \
  --fields id \
  --format csv --noquotes | tail -1)

# Add user to group
kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh update users/$USER_ID/groups/$GROUP_ID \
  -r matherlynet \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n identity -o jsonpath='{.data.password}' | base64 -d) \
  -s realm=matherlynet \
  -s userId=$USER_ID \
  -s groupId=$GROUP_ID \
  -n
```

---

## Part 3: Add Keycloak Network Policy (LOW PRIORITY)

### Why This Matters

**Security Benefits:**

- Explicit egress rules (defense-in-depth)
- Prevents unauthorized external connections
- Documents allowed network paths
- Complies with zero-trust networking principles

**Current State:** No explicit network policy for Keycloak app pods
**Target State:** CiliumNetworkPolicy with explicit egress rules

### Implementation Steps

#### Step 3.1: Create Network Policy Template

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/networkpolicy.yaml.j2`

**Create new file with the following content:**

```yaml
#% if keycloak_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CILIUM NETWORK POLICY - Keycloak Application                                  #|
#| Controls egress for Keycloak pods to database, external IdPs, and services    #|
#| REF: docs/guides/keycloak-security-hardening-jan-2026.md                      #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: keycloak
  namespace: identity
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/component: idp
spec:
  description: "Keycloak Application: Database access, external IdP federation, internal services"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: keycloak
  enableDefaultDeny:
    egress: #{ enforce | lower }#
  egress:
    #| =========================================================================== #|
    #| DNS RESOLUTION                                                              #|
    #| =========================================================================== #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP

    #| =========================================================================== #|
    #| POSTGRESQL DATABASE ACCESS                                                  #|
    #| =========================================================================== #|
#% if (keycloak_db_mode | default('embedded')) == 'cnpg' %#
    #| CloudNativePG cluster access #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: keycloak-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% else %#
    #| Embedded PostgreSQL StatefulSet access #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% endif %#

    #| =========================================================================== #|
    #| KEYCLOAK CLUSTER REPLICATION (HA mode with Infinispan)                     #|
    #| =========================================================================== #|
#% if (keycloak_replicas | default(1)) > 1 %#
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/instance: keycloak
      toPorts:
        - ports:
            - port: "7800"
              protocol: TCP
#% endif %#

    #| =========================================================================== #|
    #| EXTERNAL IDENTITY PROVIDER FEDERATION                                       #|
    #| Required when google_idp_enabled, github_idp_enabled, or                   #|
    #| microsoft_idp_enabled are true                                              #|
    #| =========================================================================== #|
#% if google_idp_enabled | default(false) %#
    #| Google OAuth/OIDC endpoints #|
    - toFQDNs:
        - matchPattern: "*.googleapis.com"
        - matchName: "accounts.google.com"
        - matchName: "oauth2.googleapis.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#
#% if github_idp_enabled | default(false) %#
    #| GitHub OAuth endpoints #|
    - toFQDNs:
        - matchPattern: "*.github.com"
        - matchName: "github.com"
        - matchName: "api.github.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#
#% if microsoft_idp_enabled | default(false) %#
    #| Microsoft Entra ID (Azure AD) endpoints #|
    - toFQDNs:
        - matchName: "login.microsoftonline.com"
        - matchName: "graph.microsoft.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#

    #| =========================================================================== #|
    #| OBSERVABILITY - Metrics and Tracing                                         #|
    #| =========================================================================== #|
#% if tracing_enabled | default(false) and keycloak_tracing_enabled | default(false) %#
    #| OpenTelemetry tracing to Tempo #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: tempo
            io.kubernetes.pod.namespace: #{ observability_namespace | default('monitoring') }#
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
#% endif %#
#% endif %#
```

#### Step 3.2: Update Kustomization

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/kustomization.yaml.j2`

**Add `networkpolicy.yaml` to resources list:**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./keycloak-cr.yaml
  - ./httproute.yaml
  - ./referencegrant.yaml
  - ./servicemonitor.yaml
  - ./dashboard-troubleshooting.yaml
  - ./dashboard-capacity-planning.yaml
#% if (keycloak_db_mode | default('embedded')) == 'cnpg' %#
  - ./postgres-cnpg.yaml
  - ./networkpolicy-postgres.yaml
#% else %#
  - ./postgres-embedded.yaml
#% endif %#
#% if keycloak_backup_enabled | default(false) and (keycloak_db_mode | default('embedded')) == 'cnpg' %#
  - ./postgres-backup-cronjob.yaml
#% endif %#
#% if network_policies_enabled | default(false) %#
  - ./networkpolicy.yaml
#% endif %#
```

#### Step 3.3: Apply Configuration

```bash
# Regenerate templates
task configure -y

# Verify generated network policy
cat kubernetes/apps/identity/keycloak/app/networkpolicy.yaml

# Commit changes
git add \
  templates/config/kubernetes/apps/identity/keycloak/app/networkpolicy.yaml.j2 \
  templates/config/kubernetes/apps/identity/keycloak/app/kustomization.yaml.j2
git commit -m "feat(keycloak): add explicit network policy for defense-in-depth"
git push

# Reconcile Flux
task reconcile
```

#### Step 3.4: Verify Network Policy

```bash
# List Keycloak network policies
kubectl get ciliumnetworkpolicy -n identity

# Expected output:
# NAME                    AGE
# keycloak                10s  ← NEW
# keycloak-config-cli     5h
# keycloak-postgres       5h

# Describe policy
kubectl describe ciliumnetworkpolicy keycloak -n identity

# Test connectivity (should succeed)
kubectl exec -n identity -it keycloak-0 -- curl -s http://keycloak-postgres-rw:5432

# Test unauthorized egress (should fail if enforce mode)
kubectl exec -n identity -it keycloak-0 -- curl -s https://example.com --max-time 5
```

#### Step 3.5: Troubleshoot Network Policy (If Issues Occur)

```bash
# Check Cilium logs for policy drops
kubectl logs -n kube-system -l k8s-app=cilium | grep "Policy denied"

# Use Hubble to observe dropped packets
hubble observe --namespace identity --verdict DROPPED --pod keycloak

# Temporarily switch to audit mode (if enforce mode is too restrictive)
# Edit cluster.yaml:
# network_policies_mode: "audit"  # Change from "enforce"
# Then run: task configure -y && git commit && git push && task reconcile
```

---

## Post-Implementation Verification

### Verification Checklist

```bash
# 1. Events Logging
echo "=== Testing Events Logging ==="
kubectl logs -n identity -l app.kubernetes.io/instance=keycloak --tail=100 | grep -i "event" | head -10
echo "✓ Events should appear in logs after authentication"

# 2. Realm Groups (if implemented)
echo -e "\n=== Verifying Realm Groups ==="
kubectl exec -n identity keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get groups -r matherlynet \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n identity -o jsonpath='{.data.password}' | base64 -d) \
  --fields name,path,realmRoles
echo "✓ Groups should be listed with their role assignments"

# 3. Network Policy
echo -e "\n=== Checking Network Policy ==="
kubectl get ciliumnetworkpolicy keycloak -n identity
echo "✓ Policy should exist"

# 4. End-to-End Authentication Test
echo -e "\n=== Testing Authentication Flow ==="
echo "Open browser and test login to: https://grafana.matherly.net"
echo "Expected: Successful login, events logged, no network policy blocks"

# 5. NEW: Kubernetes API Server OIDC Validation
echo -e "\n=== Verifying Kubernetes API Server OIDC ==="
kubectl get --raw /.well-known/openid-configuration | jq .issuer
echo "Expected: https://sso.matherly.net/realms/matherlynet"
```

### Monitoring Integration

**Grafana Dashboard Queries (Already Exists):**

```promql
# Refresh token success rate
sum(rate(keycloak_user_events_total{event="refresh_token", error=""}[5m]))
/ sum(rate(keycloak_user_events_total{event="refresh_token"}[5m]))

# Login events per minute
sum(rate(keycloak_user_events_total{event="LOGIN"}[5m])) * 60

# Failed login attempts
sum(rate(keycloak_user_events_total{event="LOGIN_ERROR"}[5m])) * 60
```

**Dashboard Location:**
`kubernetes/apps/identity/keycloak/app/dashboard-capacity-planning.yaml` (lines 465-477)

---

## Rollback Procedures

### Rollback Events Logging

```bash
# Remove events configuration from realm-config.yaml.j2
# (Delete lines added in Step 1.1)
git revert <commit-hash>
task configure -y
git push
task reconcile
```

### Rollback Realm Groups

```bash
# Remove groups from cluster.yaml and realm-config.yaml.j2
git revert <commit-hash>
task configure -y
git push
task reconcile

# Note: Existing group assignments will remain until realm re-import
# To force removal, delete and recreate the realm (NOT RECOMMENDED in production)
```

### Rollback Network Policy

```bash
# Remove networkpolicy.yaml.j2 and kustomization.yaml.j2 changes
git revert <commit-hash>
task configure -y
git push
task reconcile

# Policy will be automatically deleted by Flux
```

---

## Security Validation

### Security Checklist

- [ ] **Events logging enabled:** Login/logout events appear in Keycloak logs
- [ ] **Events retention configured:** Events expire after 30 days (optional)
- [ ] **Realm groups created:** Groups match organizational structure
- [ ] **Role assignments verified:** Users inherit roles from group membership
- [ ] **Network policy applied:** Keycloak pods have explicit egress rules
- [ ] **External IdP access tested:** Google/GitHub/Microsoft federation works
- [ ] **Token refresh functional:** Existing sessions survive policy application
- [ ] **Monitoring dashboards updated:** Grafana shows event metrics
- [ ] **NEW: Kubernetes OIDC clients validated:** Both `kubernetes` and `headlamp` clients exist
- [ ] **NEW: Headlamp authentication tested:** Web UI login works with dedicated client
- [ ] **NEW: PKCE configuration verified:** Headlamp PKCE disabled as expected

### Compliance Mapping

| Requirement | Control | Implementation |
| ----------- | ------- | -------------- |
| **Audit Logging** | SOC2 CC7.2 | Realm events logging |
| **Access Control** | ISO 27001 A.9.1 | Realm groups + roles |
| **Network Segmentation** | NIST 800-53 SC-7 | Cilium network policy |
| **Least Privilege** | CIS Kubernetes 5.1 | Explicit egress rules |

---

## Future Enhancements

### Phase 2: Advanced Security Features

1. **Event Storage and Retention**
   - Configure PostgreSQL event store (instead of in-memory)
   - Implement event archival to S3/RustFS
   - Create Grafana Loki integration for log aggregation

2. **Advanced RBAC**
   - Client-level role mappings (not just realm roles)
   - Composite roles (role hierarchies)
   - Dynamic role assignment based on IdP attributes

3. **Network Security**
   - Mutual TLS between Keycloak and databases
   - Certificate-based authentication for admin API
   - Rate limiting via Cilium network policy

4. **Monitoring and Alerting**
   - PrometheusRule for high failure rates
   - PagerDuty integration for critical events
   - Automated security reports

### Phase 3: Zero Trust Architecture

1. **Service Mesh Integration**
   - Istio/Linkerd authorization policies
   - mTLS for all Keycloak connections
   - Request-level authentication

2. **Policy as Code**
   - Open Policy Agent (OPA) integration
   - Fine-grained authorization policies
   - Automated policy testing

---

## Appendix: OIDC Client Configuration Reference

### Current OIDC Client Configuration (January 2026)

| Client Name | Client ID Variable | Used By | Redirect URIs | PKCE | Notes |
| ----------- | ------------------ | ------- | ------------- | ---- | ----- |
| **Envoy Gateway SSO** | `oidc_client_id` | Hubble, Grafana (gateway), RustFS | Dynamic per-service | S256 | Browser SSO via SecurityPolicy |
| **Grafana Native** | `grafana_oidc_client_id` | Grafana (native OAuth) | `/login/generic_oauth` | S256 | Direct Grafana RBAC |
| **LiteLLM** | `litellm_oidc_client_id` | LiteLLM Proxy UI | `/sso/callback` | S256 | Admin UI SSO |
| **Langfuse** | `langfuse_keycloak_client_id` | Langfuse UI | `/api/auth/callback/keycloak` | S256 | LLM observability SSO |
| **Obot** | `obot_keycloak_client_id` | Obot MCP Gateway | `/oauth2/callback` | S256 | AI agent platform SSO |
| **Kubernetes API Server** | `kubernetes_oidc_client_id` | **Headlamp (web), kubectl (CLI), kubelogin, oidc-login** | `localhost:8000/*`, `localhost:18000/*`, `https://headlamp.domain/oidc-callback` | Disabled | **SHARED client** - All K8s API authentication |
| **Langfuse Sync** | `langfuse_sync_keycloak_client_id` | SCIM sync CronJob | None (service account) | N/A | Service account for role sync |

### Architecture Correction (January 13, 2026)

**Previous (INCORRECT) Documentation:**

```yaml
# Headlamp uses separate dedicated client (WRONG)
clientID: headlamp_oidc_client_id
clientSecret: headlamp_oidc_client_secret
```

**Current (CORRECT) Implementation:**

```yaml
# Headlamp uses SHARED kubernetes client (CORRECT)
clientID: kubernetes_oidc_client_id
clientSecret: kubernetes_oidc_client_secret

# RATIONALE:
# - Headlamp passes OIDC tokens to Kubernetes API Server
# - API Server validates tokens with aud: ["kubernetes"]
# - Separate client would cause 401 Unauthorized errors
# - Single kubernetes client supports multiple redirect URIs
```

**Key Point:** The `kubernetes` client definition in `realm-config.yaml.j2` includes ALL redirect URIs (localhost for CLI + Headlamp web URL) to support both authentication flows with a single client.

---

## References

### Documentation

- [Keycloak Events Documentation](https://www.keycloak.org/docs/latest/server_admin/#auditing-and-events)
- [Keycloak Groups and Roles](https://www.keycloak.org/docs/latest/server_admin/#groups)
- [Cilium Network Policy](https://docs.cilium.io/en/stable/security/policy/)
- **NEW:** [Kubernetes API Server OIDC](../research/kubernetes-api-server-oidc-authentication-jan-2026.md)
- **NEW:** [Headlamp OIDC Configuration](https://headlamp.dev/docs/latest/installation/in-cluster/keycloak/)

### Project Files

- Security Analysis Report (January 12, 2026)
- [Obot OIDC Remediation](../research/obot-keycloak-oidc-remediation-jan-2026.md)
- [Split-Path OIDC Implementation](./completed/native-oidc-securitypolicy-implementation.md)
- **NEW:** [Kubernetes API Server OIDC Authentication](../research/kubernetes-api-server-oidc-authentication-jan-2026.md)

### External Resources

- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [NIST Digital Identity Guidelines](https://pages.nist.gov/800-63-3/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---

## Changelog

| Date | Change | Author |
| ---- | ------ | ------ |
| 2026-01-12 | Initial implementation guide created | Security Analysis |
| 2026-01-12 | ~~UPDATED: Added Kubernetes API Server OIDC architecture changes, dedicated Headlamp client~~ (INCORRECT) | Architecture Update |
| 2026-01-13 | **CORRECTED:** Fixed architecture to reflect SHARED client design - Headlamp uses `kubernetes` client (NOT separate client). Updated all documentation to match actual implementation. | Architecture Correction |

---

## Support

For issues or questions:

1. Review [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
2. Check Keycloak logs: `kubectl logs -n identity -l app.kubernetes.io/instance=keycloak`
3. Verify Flux reconciliation: `flux get ks -A`
4. Check OIDC client configuration: `kubectl exec -n identity keycloak-0 -- /opt/keycloak/bin/kcadm.sh get clients -r matherlynet --fields clientId,enabled`
5. Open GitHub issue with logs and error messages

**End of Implementation Guide (UPDATED)**
