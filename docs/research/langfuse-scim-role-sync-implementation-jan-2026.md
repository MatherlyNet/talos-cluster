# Langfuse SCIM Role Sync from Keycloak - Implementation Plan

**Date:** January 2026
**Status:** RESEARCH COMPLETE - Ready for Implementation Decision
**Complexity:** Medium-High
**Dependencies:** Langfuse, Keycloak, Optional: Keycloak Webhook Plugin
**Related:**

- `docs/research/langfuse-keycloak-sso-validation-jan-2026.md`
- `docs/ai-context/langfuse.md`

## Executive Summary

This document provides a comprehensive implementation plan for synchronizing Keycloak roles to Langfuse using the SCIM API. Since Langfuse does not natively support role mapping from OIDC claims, we must implement an external synchronization mechanism.

**Key Finding:** Langfuse's Keycloak integration handles authentication only, not authorization. Role assignment requires either:

1. Manual assignment via UI
2. Static defaults via environment variables (current approach)
3. **SCIM API automation** (this document's focus)

### Recommendation Summary

| Approach | Complexity | Real-time | Recommended For |
| ---------- | ---------- | ---------- | ----------------- |
| Option A: CronJob Sync | Low | No (periodic) | Most deployments |
| Option B: Keycloak Webhook | Medium-High | Yes | Enterprise/high-volume |
| Option C: Login-Time Sync | High | Yes | Custom requirements |

**Recommended:** Start with **Option A (CronJob)** for simplicity, upgrade to Option B if real-time sync is required.

---

## Current State Analysis

### Existing Langfuse SSO Configuration

From `cluster.yaml`:

```yaml
# SSO Authentication (working)
langfuse_sso_enabled: true
langfuse_keycloak_client_secret: "..."

# Default role assignment (current workaround)
langfuse_default_org_id: "matherly-net"
langfuse_default_org_role: "VIEWER"
langfuse_init_org_id: "matherly-net"
langfuse_init_project_id: "litellm"
```

### Limitations of Current Approach

| Feature | Current State | Desired State |
| --------- | --------------- | --------------- |
| SSO Authentication | Working | Working |
| Role from Keycloak claims | Not supported | Map Keycloak roles to Langfuse |
| Dynamic role updates | Not supported | Sync on role change |
| Default role for new users | VIEWER (static) | Based on Keycloak role |

### Langfuse RBAC Model

Langfuse uses a two-tier RBAC model:

**Organization Roles:**

| Role | Permissions |
| ------ | ------------- |
| `OWNER` | Full administrative access, can delete org |
| `ADMIN` | Manage members, projects, settings |
| `MEMBER` | Create traces, view dashboards |
| `VIEWER` | Read-only access |
| `NONE` | No org access (for project-only users) |

**Project Roles:**

| Role | Permissions |
| ------ | ------------- |
| `OWNER` | Full project control |
| `ADMIN` | Manage project settings, API keys |
| `MEMBER` | Submit traces, create scores |
| `VIEWER` | Read-only project access |

---

## Langfuse API Capabilities

### SCIM API Endpoints

Base URL: `https://langfuse.matherly.net/api/public/scim`

| Endpoint | Method | Purpose |
| ---------- | ---------- | --------- |
| `/ServiceProviderConfig` | GET | SCIM configuration |
| `/ResourceTypes` | GET | Available resource types |
| `/Schemas` | GET | Schema definitions |
| `/Users` | GET | List users in organization |
| `/Users` | POST | Create new user |
| `/Users/{id}` | GET | Get specific user |
| `/Users/{id}` | PATCH | Update user (including roles) |
| `/Users/{id}` | DELETE | Remove user from organization |

### Organization Management API

Base URL: `https://langfuse.matherly.net/api/public`

| Endpoint | Method | Purpose |
| ---------- | ---------- | --------- |
| `/organizations/{orgId}/memberships` | GET | List org members |
| `/organizations/{orgId}/memberships/{userId}` | PATCH | Update member role |
| `/projects/{projectId}/memberships` | GET | List project members |
| `/projects/{projectId}/memberships/{userId}` | PATCH | Update project role |

### Authentication

**SCIM/Admin API:** HTTP Basic Auth

- Username: Organization Public Key
- Password: Organization Secret Key

API keys are created via:

1. Langfuse UI: Organization Settings → API Keys
2. Instance Management API (requires `ADMIN_API_KEY` env var)

---

## Implementation Options

### Option A: Kubernetes CronJob Sync (Recommended)

**Architecture:**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Keycloak   │────▶│   CronJob   │────▶│   Langfuse  │
│  (Roles)    │     │  (Sync)     │     │  (SCIM API) │
└─────────────┘     └─────────────┘     └─────────────┘
      ▲                    │
      │                    ▼
      │             ┌─────────────┐
      └─────────────│  Compare &  │
                    │  Update     │
                    └─────────────┘
```

**Flow:**

1. CronJob runs periodically (e.g., every 5 minutes)
2. Fetches users from Keycloak Admin API
3. Fetches users from Langfuse SCIM API
4. Compares roles and updates Langfuse via SCIM PATCH

**Pros:**

- Simple deployment (single CronJob)
- No Keycloak modifications required
- Uses existing Keycloak Admin API
- Easy to debug and monitor

**Cons:**

- Not real-time (5-15 minute delay)
- Polling overhead
- Requires Keycloak service account

**Implementation Files:**

```
kubernetes/apps/ai-system/langfuse/sync/
├── cronjob.yaml           # Kubernetes CronJob
├── configmap.yaml         # Sync script
├── secret.sops.yaml       # API credentials
└── serviceaccount.yaml    # RBAC for CronJob
```

### Option B: Keycloak Webhook Event Listener

**Architecture:**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Keycloak   │────▶│  Webhook    │────▶│   Langfuse  │
│  (Events)   │     │  Receiver   │     │  (SCIM API) │
└─────────────┘     └─────────────┘     └─────────────┘
      │                    │
      │ LOGIN/             │ POST /sync
      │ ROLE_GRANT         │
      ▼                    ▼
   Event ─────────────▶ Process & Update
```

**Flow:**

1. User logs in or role changes in Keycloak
2. Keycloak fires webhook to receiver service
3. Receiver extracts user info and roles
4. Updates Langfuse via SCIM API

**Pros:**

- Real-time sync
- Only syncs on changes (efficient)
- Event-driven architecture

**Cons:**

- Requires Keycloak plugin installation
- Additional service to maintain
- More complex debugging

**Keycloak Plugin Options:**

1. [vymalo/keycloak-webhook](https://github.com/vymalo/keycloak-webhook) - Most feature-rich
2. [p2-inc/keycloak-events](https://github.com/p2-inc/keycloak-events) - Includes webhook storage
3. [jessylenne/keycloak-event-listener-http](https://github.com/jessylenne/keycloak-event-listener-http) - Simplest

### Option C: Login-Time Sync (Custom Auth Proxy)

**Architecture:**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│ Auth Proxy  │────▶│   Langfuse  │
└─────────────┘     └─────────────┘     └─────────────┘
                          │
                          ▼
                    ┌─────────────┐
                    │  Keycloak   │
                    │  (Validate) │
                    └─────────────┘
```

**Flow:**

1. User authenticates via Keycloak
2. Auth proxy intercepts callback
3. Extracts roles from ID token
4. Updates Langfuse via SCIM before redirect

**Pros:**

- Sync happens at login time
- Uses existing OIDC flow
- No polling or webhooks

**Cons:**

- Most complex to implement
- Requires custom auth proxy
- Adds latency to login

---

## Recommended Implementation: Option A (CronJob)

### Prerequisites

1. **Langfuse Organization API Key** (choose one method)

   **Method A: Via UI (Open Source / No Enterprise License)**
   - Navigate to Langfuse UI: Organization Settings → API Keys
   - Create new API key with a descriptive note (e.g., "Role Sync Service")
   - Copy the `publicKey` and `secretKey` (shown only once!)
   - Add to `cluster.yaml` as `langfuse_scim_public_key` and `langfuse_scim_secret_key`

   **Method B: Via Instance Management API (Enterprise License Required)**
   - Set `ADMIN_API_KEY` environment variable in Langfuse deployment
   - Use the API to programmatically create organization API keys:

   ```bash
   # Create organization API key
   curl -X POST "https://langfuse.matherly.net/api/admin/organizations/matherly-net/apiKeys" \
     -H "Authorization: Bearer $ADMIN_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"note": "Role Sync Service Account"}'

   # Response contains publicKey and secretKey
   ```

   **Important:** The Instance Management API (`/api/admin/*`) requires a Langfuse
   Enterprise license. Without it, these endpoints return 401/403 errors.

2. **Keycloak Service Account**
   - Client with `view-users` and `view-realm` roles
   - Service account enabled

3. **Role Mapping Configuration**
   - Define Keycloak role → Langfuse role mapping

### Role Mapping Strategy

**Keycloak Realm Roles → Langfuse Org Roles:**

| Keycloak Role | Langfuse Org Role | Description |
| --------------- | ------------------- | ------------- |
| `langfuse-admin` | `ADMIN` | Full org management |
| `langfuse-member` | `MEMBER` | Create traces, scores |
| `langfuse-viewer` | `VIEWER` | Read-only (default) |
| (no role) | `VIEWER` | Fallback for SSO users |

**Alternative: Use Existing Roles:**

If you prefer to reuse existing Keycloak roles:

| Keycloak Role | Langfuse Org Role |
| --------------- | ------------------- |
| `admin` | `ADMIN` |
| `operator` | `MEMBER` |
| `developer` | `MEMBER` |
| (default) | `VIEWER` |

### Implementation Steps

#### Step 1: Add Keycloak Realm Roles

Update `cluster.yaml` to add Langfuse-specific roles:

```yaml
keycloak_realm_roles:
  # Existing roles...
  - name: admin
    description: "Administrator - Full access to all services"
  - name: operator
    description: "Operator - Operational access to services"
  - name: developer
    description: "Developer - Development access"
  # Add Langfuse-specific roles (optional)
  - name: langfuse-admin
    description: "Langfuse Administrator - Full org management"
  - name: langfuse-member
    description: "Langfuse Member - Create traces and scores"
```

#### Step 2: Create cluster.yaml Variables

Add to `cluster.yaml`:

```yaml
# =============================================================================
# LANGFUSE SCIM ROLE SYNC
# =============================================================================

# -- Enable SCIM role sync from Keycloak
#    When enabled, a CronJob syncs Keycloak roles to Langfuse via SCIM API
#    (OPTIONAL) / (DEFAULT: false)
# langfuse_scim_sync_enabled: false

# -- Sync schedule (cron format)
#    How often to sync roles from Keycloak to Langfuse
#    (OPTIONAL) / (DEFAULT: "*/5 * * * *" = every 5 minutes)
# langfuse_scim_sync_schedule: "*/5 * * * *"

# -- Langfuse Organization API Key (public key)
#    Create in Langfuse UI: Organization Settings → API Keys
#    (REQUIRED when langfuse_scim_sync_enabled: true)
# langfuse_scim_public_key: ""

# -- Langfuse Organization API Key (secret key, SOPS-encrypted)
#    (REQUIRED when langfuse_scim_sync_enabled: true)
# langfuse_scim_secret_key: ""

# -- Keycloak service account client ID
#    Client with view-users and view-realm roles
#    (OPTIONAL) / (DEFAULT: "langfuse-sync")
# langfuse_sync_keycloak_client_id: "langfuse-sync"

# -- Keycloak service account client secret (SOPS-encrypted)
#    (REQUIRED when langfuse_scim_sync_enabled: true)
# langfuse_sync_keycloak_client_secret: ""

# -- Role mapping (YAML format)
#    Maps Keycloak realm roles to Langfuse organization roles
#    (OPTIONAL) / (DEFAULT: see below)
# langfuse_role_mapping:
#   admin: "ADMIN"
#   operator: "MEMBER"
#   developer: "MEMBER"
#   default: "VIEWER"
```

#### Step 3: Create Sync Script

Create `templates/config/kubernetes/apps/ai-system/langfuse/sync/sync-script.py.j2`:

```python
#!/usr/bin/env python3
"""
Langfuse SCIM Role Sync from Keycloak

This script syncs user roles from Keycloak to Langfuse via SCIM API.
It runs as a Kubernetes CronJob.
"""

import os
import sys
import json
import logging
import requests
from typing import Dict, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment
KEYCLOAK_URL = os.environ.get('KEYCLOAK_URL')
KEYCLOAK_REALM = os.environ.get('KEYCLOAK_REALM', 'matherlynet')
KEYCLOAK_CLIENT_ID = os.environ.get('KEYCLOAK_CLIENT_ID')
KEYCLOAK_CLIENT_SECRET = os.environ.get('KEYCLOAK_CLIENT_SECRET')

LANGFUSE_URL = os.environ.get('LANGFUSE_URL')
LANGFUSE_ORG_ID = os.environ.get('LANGFUSE_ORG_ID')
LANGFUSE_PUBLIC_KEY = os.environ.get('LANGFUSE_PUBLIC_KEY')
LANGFUSE_SECRET_KEY = os.environ.get('LANGFUSE_SECRET_KEY')

# Role mapping: Keycloak role -> Langfuse role
ROLE_MAPPING = json.loads(os.environ.get('ROLE_MAPPING', '{}'))
DEFAULT_ROLE = ROLE_MAPPING.get('default', 'VIEWER')


def get_keycloak_token() -> str:
    """Get access token from Keycloak using client credentials."""
    token_url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"

    response = requests.post(token_url, data={
        'grant_type': 'client_credentials',
        'client_id': KEYCLOAK_CLIENT_ID,
        'client_secret': KEYCLOAK_CLIENT_SECRET,
    })
    response.raise_for_status()
    return response.json()['access_token']


def get_keycloak_users(token: str) -> list:
    """Fetch all users from Keycloak with their realm roles."""
    users_url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/users"
    headers = {'Authorization': f'Bearer {token}'}

    response = requests.get(users_url, headers=headers, params={'max': 1000})
    response.raise_for_status()
    users = response.json()

    # Get roles for each user
    for user in users:
        roles_url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/users/{user['id']}/role-mappings/realm"
        roles_response = requests.get(roles_url, headers=headers)
        if roles_response.ok:
            user['realm_roles'] = [r['name'] for r in roles_response.json()]
        else:
            user['realm_roles'] = []

    return users


def get_langfuse_users() -> Dict[str, dict]:
    """Fetch all users from Langfuse SCIM API."""
    scim_url = f"{LANGFUSE_URL}/api/public/scim/Users"

    response = requests.get(
        scim_url,
        auth=(LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY)
    )
    response.raise_for_status()

    users = {}
    for user in response.json().get('Resources', []):
        email = None
        for email_entry in user.get('emails', []):
            if email_entry.get('primary'):
                email = email_entry.get('value')
                break
        if email:
            users[email.lower()] = user

    return users


def get_langfuse_memberships() -> Dict[str, str]:
    """Get current org memberships from Langfuse."""
    memberships_url = f"{LANGFUSE_URL}/api/public/organizations/{LANGFUSE_ORG_ID}/memberships"

    response = requests.get(
        memberships_url,
        auth=(LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY)
    )
    response.raise_for_status()

    return {m['userId']: m['role'] for m in response.json().get('memberships', [])}


def map_role(keycloak_roles: list) -> str:
    """Map Keycloak roles to Langfuse role."""
    for kc_role, lf_role in ROLE_MAPPING.items():
        if kc_role != 'default' and kc_role in keycloak_roles:
            return lf_role
    return DEFAULT_ROLE


def update_langfuse_role(user_id: str, new_role: str) -> bool:
    """Update user's organization role in Langfuse."""
    membership_url = f"{LANGFUSE_URL}/api/public/organizations/{LANGFUSE_ORG_ID}/memberships/{user_id}"

    response = requests.patch(
        membership_url,
        auth=(LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY),
        json={'role': new_role}
    )

    if response.ok:
        logger.info(f"Updated user {user_id} to role {new_role}")
        return True
    else:
        logger.error(f"Failed to update user {user_id}: {response.text}")
        return False


def sync_roles():
    """Main sync function."""
    logger.info("Starting Langfuse role sync from Keycloak")

    # Get Keycloak users
    kc_token = get_keycloak_token()
    kc_users = get_keycloak_users(kc_token)
    logger.info(f"Found {len(kc_users)} users in Keycloak")

    # Get Langfuse users
    lf_users = get_langfuse_users()
    lf_memberships = get_langfuse_memberships()
    logger.info(f"Found {len(lf_users)} users in Langfuse")

    # Build email -> Keycloak user mapping
    kc_by_email = {u['email'].lower(): u for u in kc_users if u.get('email')}

    # Sync roles
    updated = 0
    skipped = 0

    for email, lf_user in lf_users.items():
        kc_user = kc_by_email.get(email)
        if not kc_user:
            logger.debug(f"User {email} not found in Keycloak, skipping")
            skipped += 1
            continue

        # Determine desired role
        desired_role = map_role(kc_user.get('realm_roles', []))
        current_role = lf_memberships.get(lf_user['id'])

        if current_role != desired_role:
            if update_langfuse_role(lf_user['id'], desired_role):
                updated += 1
        else:
            logger.debug(f"User {email} already has role {current_role}")

    logger.info(f"Sync complete: {updated} updated, {skipped} skipped")


if __name__ == '__main__':
    try:
        sync_roles()
    except Exception as e:
        logger.error(f"Sync failed: {e}")
        sys.exit(1)
```

#### Step 4: Create Kubernetes Resources

**CronJob Template:** `templates/config/kubernetes/apps/ai-system/langfuse/sync/cronjob.yaml.j2`

```yaml
#% if langfuse_scim_sync_enabled | default(false) %#
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: langfuse-role-sync
  namespace: ai-system
  labels:
    app.kubernetes.io/name: langfuse-role-sync
    app.kubernetes.io/component: sync
spec:
  schedule: "#{ langfuse_scim_sync_schedule | default('*/5 * * * *') }#"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 3
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: sync
              image: python:3.12-slim
              command:
                - python
                - /scripts/sync.py
              env:
                - name: KEYCLOAK_URL
                  value: "https://#{ keycloak_subdomain | default('auth') }#.#{ cloudflare_domain }#"
                - name: KEYCLOAK_REALM
                  value: "#{ keycloak_realm | default('matherlynet') }#"
                - name: KEYCLOAK_CLIENT_ID
                  value: "#{ langfuse_sync_keycloak_client_id | default('langfuse-sync') }#"
                - name: KEYCLOAK_CLIENT_SECRET
                  valueFrom:
                    secretKeyRef:
                      name: langfuse-sync-secret
                      key: KEYCLOAK_CLIENT_SECRET
                - name: LANGFUSE_URL
                  value: "https://#{ langfuse_subdomain | default('langfuse') }#.#{ cloudflare_domain }#"
                - name: LANGFUSE_ORG_ID
                  value: "#{ langfuse_init_org_id }#"
                - name: LANGFUSE_PUBLIC_KEY
                  valueFrom:
                    secretKeyRef:
                      name: langfuse-sync-secret
                      key: LANGFUSE_PUBLIC_KEY
                - name: LANGFUSE_SECRET_KEY
                  valueFrom:
                    secretKeyRef:
                      name: langfuse-sync-secret
                      key: LANGFUSE_SECRET_KEY
                - name: ROLE_MAPPING
                  value: '#{ langfuse_role_mapping | default({"admin": "ADMIN", "operator": "MEMBER", "developer": "MEMBER", "default": "VIEWER"}) | tojson }#'
              volumeMounts:
                - name: scripts
                  mountPath: /scripts
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
                limits:
                  cpu: 200m
                  memory: 128Mi
          volumes:
            - name: scripts
              configMap:
                name: langfuse-sync-script
#% endif %#
```

**Secret Template:** `templates/config/kubernetes/apps/ai-system/langfuse/sync/secret.sops.yaml.j2`

```yaml
#% if langfuse_scim_sync_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-sync-secret
  namespace: ai-system
type: Opaque
stringData:
  KEYCLOAK_CLIENT_SECRET: "#{ langfuse_sync_keycloak_client_secret }#"
  LANGFUSE_PUBLIC_KEY: "#{ langfuse_scim_public_key }#"
  LANGFUSE_SECRET_KEY: "#{ langfuse_scim_secret_key }#"
#% endif %#
```

**ConfigMap Template:** `templates/config/kubernetes/apps/ai-system/langfuse/sync/configmap.yaml.j2`

```yaml
#% if langfuse_scim_sync_enabled | default(false) %#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: langfuse-sync-script
  namespace: ai-system
data:
  sync.py: |
    # (Include sync script content here)
#% endif %#
```

#### Step 5: Create Keycloak Sync Client

Add to Keycloak realm configuration in `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`:

```yaml
#% if langfuse_scim_sync_enabled | default(false) %#
  - clientId: "#{ langfuse_sync_keycloak_client_id | default('langfuse-sync') }#"
    name: "Langfuse Role Sync"
    description: "Service account for syncing roles to Langfuse"
    enabled: true
    publicClient: false
    serviceAccountsEnabled: true
    standardFlowEnabled: false
    directAccessGrantsEnabled: false
    protocol: "openid-connect"
    secret: "#{ langfuse_sync_keycloak_client_secret }#"
    defaultClientScopes:
      - "openid"
    #| Service account roles are assigned via realm-roles-mapping #|
#% endif %#
```

#### Step 6: Update Schema and Plugin

**Add to `cluster.schema.cue`:**

```cue
// Langfuse SCIM Role Sync
langfuse_scim_sync_enabled?:           *false | bool
langfuse_scim_sync_schedule?:          *"*/5 * * * *" | string
langfuse_scim_public_key?:             string & !=""
langfuse_scim_secret_key?:             string & !=""
langfuse_sync_keycloak_client_id?:     *"langfuse-sync" | string & !=""
langfuse_sync_keycloak_client_secret?: string & !=""
langfuse_role_mapping?:                {...}
```

**Add to `plugin.py`:**

```python
# Langfuse SCIM sync - requires all credentials
langfuse_scim_sync_enabled = (
    data.get("langfuse_enabled", False)
    and data.get("langfuse_scim_sync_enabled", False)
    and data.get("langfuse_scim_public_key")
    and data.get("langfuse_scim_secret_key")
    and data.get("langfuse_sync_keycloak_client_secret")
)
data["langfuse_scim_sync_enabled"] = langfuse_scim_sync_enabled
```

---

## Enterprise Enhancement: ADMIN_API_KEY Integration

If you have a Langfuse Enterprise license, you can use `ADMIN_API_KEY` to fully automate the API key creation process.

### Configuration

Add to `cluster.yaml`:

```yaml
# -- Langfuse Instance Admin API Key (Enterprise Only)
#    Enables programmatic management of organizations and API keys
#    Generate with: openssl rand -hex 32
#    (OPTIONAL) / (REQUIRES: Langfuse Enterprise License)
# langfuse_admin_api_key: ""
```

### Template Changes

Add to `templates/config/kubernetes/apps/ai-system/langfuse/app/helmrelease.yaml.j2`:

```yaml
#% if langfuse_admin_api_key | default('') %#
        - name: ADMIN_API_KEY
          valueFrom:
            secretKeyRef:
              name: langfuse-secrets
              key: ADMIN_API_KEY
#% endif %#
```

Add to `templates/config/kubernetes/apps/ai-system/langfuse/app/secret.sops.yaml.j2`:

```yaml
#% if langfuse_admin_api_key | default('') %#
  ADMIN_API_KEY: "#{ langfuse_admin_api_key }#"
#% endif %#
```

### Automated Bootstrap Flow

With `ADMIN_API_KEY`, the sync CronJob can self-bootstrap:

1. **First Run:** Check if org API key exists in Secret
2. **If not:** Call Instance Management API to create one
3. **Store:** Save publicKey/secretKey to Kubernetes Secret
4. **Subsequent Runs:** Use stored keys for SCIM operations

This eliminates the manual UI step entirely.

### API Endpoints Available

| Endpoint | Method | Purpose |
| ---------- | ---------- | --------- |
| `/api/admin/organizations` | POST | Create organization |
| `/api/admin/organizations/{id}` | GET | Get organization |
| `/api/admin/organizations/{id}` | PATCH | Update organization |
| `/api/admin/organizations/{id}` | DELETE | Delete organization |
| `/api/admin/organizations/{id}/apiKeys` | POST | Create org API key |
| `/api/admin/organizations/{id}/apiKeys` | GET | List org API keys |
| `/api/admin/organizations/{id}/apiKeys/{keyId}` | DELETE | Delete API key |

---

## Alternative: Option B (Keycloak Webhook)

If real-time sync is required, deploy the Keycloak webhook plugin:

### Plugin Installation

Add init container to Keycloak deployment in `templates/config/kubernetes/apps/identity/keycloak/app/keycloak-cr.yaml.j2`:

```yaml
#% if langfuse_scim_sync_enabled | default(false) and langfuse_sync_mode | default('cronjob') == 'webhook' %#
spec:
  unsupported:
    podTemplate:
      spec:
        initContainers:
          - name: download-webhook-plugin
            image: curlimages/curl:8.5.0
            command:
              - sh
              - -c
              - |
                curl -L -o /plugins/keycloak-webhook-core.jar \
                  https://github.com/vymalo/keycloak-webhook/releases/download/v1.0.0/keycloak-webhook-core-1.0.0.jar
                curl -L -o /plugins/keycloak-webhook-http.jar \
                  https://github.com/vymalo/keycloak-webhook/releases/download/v1.0.0/keycloak-webhook-http-1.0.0.jar
            volumeMounts:
              - name: plugins
                mountPath: /plugins
        volumes:
          - name: plugins
            emptyDir: {}
#% endif %#
```

### Webhook Receiver Service

Deploy a simple webhook receiver that:

1. Receives LOGIN events from Keycloak
2. Extracts user email and roles from event payload
3. Calls Langfuse SCIM API to update role

---

## Security Considerations

### API Key Management

1. **Langfuse Org API Keys:** Store in SOPS-encrypted secrets
2. **Keycloak Service Account:** Use dedicated client with minimal permissions
3. **Network Policies:** Restrict sync job to only Keycloak and Langfuse endpoints

### Audit Trail

The sync script logs all role changes. Consider:

- Sending logs to Loki for centralized monitoring
- Adding Prometheus metrics for sync success/failure
- Alerting on repeated failures

### Rate Limiting

- Langfuse API may have rate limits
- Space out user updates if syncing many users
- Consider batch operations if available

---

## Monitoring and Alerting

### Prometheus Metrics

Add to sync script:

```python
from prometheus_client import Counter, Gauge, push_to_gateway

SYNC_SUCCESS = Counter('langfuse_sync_success_total', 'Successful role syncs')
SYNC_FAILURE = Counter('langfuse_sync_failure_total', 'Failed role syncs')
SYNC_DURATION = Gauge('langfuse_sync_duration_seconds', 'Sync duration')
```

### Grafana Dashboard

Create dashboard showing:

- Sync job success/failure rate
- Number of users synced
- Role distribution
- Sync duration trends

---

## Testing Plan

### Unit Tests

1. Test role mapping logic
2. Test API response parsing
3. Test error handling

### Integration Tests

1. Deploy to staging environment
2. Create test users in Keycloak
3. Verify roles sync to Langfuse
4. Test role changes propagate

### Acceptance Criteria

- [ ] New SSO users get correct role based on Keycloak roles
- [ ] Role changes in Keycloak propagate within sync interval
- [ ] Sync failures don't affect Langfuse availability
- [ ] Logs provide clear audit trail

---

## Implementation Checklist

### Phase 1: Prerequisites

- [ ] Create Langfuse Organization API Key (UI: Settings → API Keys)
- [ ] Add Langfuse roles to `keycloak_realm_roles` in cluster.yaml
- [ ] Create Keycloak service account client for sync

### Phase 2: Configuration

- [ ] Add SCIM sync variables to cluster.yaml
- [ ] Update cluster.schema.cue with new variables
- [ ] Update plugin.py with derived variable logic

### Phase 3: Templates

- [ ] Create sync CronJob template
- [ ] Create sync secret template
- [ ] Create sync ConfigMap template
- [ ] Add Keycloak sync client to realm-config

### Phase 4: Deployment

- [ ] Run `task configure`
- [ ] Verify generated manifests
- [ ] Run `task reconcile`
- [ ] Verify CronJob runs successfully

### Phase 5: Validation

- [ ] Test with new SSO user
- [ ] Test role change in Keycloak
- [ ] Verify Langfuse role updates
- [ ] Document in CLAUDE.md

---

## Sources

- [Langfuse SCIM and Org API](https://langfuse.com/docs/administration/scim-and-org-api)
- [Langfuse Instance Management API](https://langfuse.com/self-hosting/administration/instance-management-api)
- [Langfuse Automated Access Provisioning](https://langfuse.com/self-hosting/administration/automated-access-provisioning)
- [Langfuse RBAC](https://langfuse.com/docs/administration/rbac)
- [Langfuse Admin APIs Changelog](https://langfuse.com/changelog/2025-04-15-admin-apis)
- [GitHub Discussion #10897: Keycloak SSO RBAC](https://github.com/orgs/langfuse/discussions/10897)
- [vymalo/keycloak-webhook](https://github.com/vymalo/keycloak-webhook)
- [p2-inc/keycloak-events](https://github.com/p2-inc/keycloak-events)
