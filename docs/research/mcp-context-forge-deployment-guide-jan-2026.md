# MCP Context Forge Deployment & Integration Guide

**Date:** January 2026
**Status:** Research Complete - Implementation Ready
**Version:** latest (Container registry uses commit SHAs, not semantic versions)

## Executive Summary

This guide provides comprehensive deployment instructions for [IBM MCP Context Forge](https://github.com/IBM/mcp-context-forge) into the matherlynet-talos-cluster, leveraging existing infrastructure services (Keycloak, Dragonfly, CloudNativePG, Gateway API, etc.).

### Key Findings

1. **Keycloak Native Support**: MCP Context Forge has native Keycloak OIDC integration with role mapping - no need for Dex
2. **DCR Support**: Built-in OAuth 2.0 Dynamic Client Registration (RFC 7591) for MCP clients
3. **Multi-Tenant Ready**: v0.7.0+ includes team-based RBAC, personal teams, and invitation system
4. **Compatible Stack**: PostgreSQL + Redis (Dragonfly-compatible) + FastAPI architecture aligns with cluster patterns

### Architecture Decision

| Option | Recommendation |
| -------- | ---------------- |
| **Authentication** | Keycloak OIDC (Native SSO) - **SELECTED** |
| **DCR Proxy** | HyprMCP Gateway - Optional, only if anonymous DCR required |
| **Database** | CloudNativePG PostgreSQL with pgvector |
| **Cache** | Dragonfly (Redis-compatible) |
| **Ingress** | Gateway API HTTPRoute + Envoy |

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Keycloak Configuration](#keycloak-configuration)
   - [RustFS IAM Setup for PostgreSQL Backups](#rustfs-iam-setup-for-postgresql-backups)
4. [Deployment Configuration](#deployment-configuration)
5. [Network Policies](#network-policies)
6. [Integration Points](#integration-points)
7. [DCR Configuration](#dcr-configuration)
8. [HyprMCP Gateway (Optional)](#hyprmcp-gateway-optional)
9. [Monitoring & Observability](#monitoring--observability)
10. [Security Considerations](#security-considerations)
11. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           External Access                                   │
│                    https://mcp.matherly.net                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      network namespace                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                  Envoy Gateway (TLS Termination)                    │    │
│  │                    HTTPRoute → mcp-context-forge                    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ai-system namespace                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │              MCP Context Forge (Port 4444)                            │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐    │  │
│  │  │   Gateway Core  │  │    Admin UI     │  │   MCP Registry      │    │  │
│  │  │   (FastAPI)     │  │   (HTMX/Alpine) │  │   (Federation)      │    │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────────┘    │  │
│  │                                                                       │  │
│  │  Features:                                                            │  │
│  │  - Multi-tenant teams with RBAC                                       │  │
│  │  - DCR (Dynamic Client Registration)                                  │  │
│  │  - REST-to-MCP / gRPC-to-MCP translation                              │  │
│  │  - Virtual server composition                                         │  │
│  │  - A2A (Agent-to-Agent) integration                                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                   │                             │                           │
│        ┌──────────┴──────────┐         ┌────────┴────────┐                  │
│        ▼                     ▼         ▼                 ▼                  │
│  ┌───────────────┐   ┌───────────────────┐   ┌─────────────────────┐        │
│  │  PostgreSQL   │   │     Dragonfly     │   │      Upstream       │        │
│  │  (cnpg-system)│   │  (cache namespace)│   │    MCP Servers      │        │
│  └───────────────┘   └───────────────────┘   └─────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                        ┌───────────┴───────────┐
                        ▼                       ▼
┌───────────────────────────────┐   ┌───────────────────────────────────────┐
│     identity namespace        │   │        monitoring namespace           │
│  ┌─────────────────────────┐  │   │  ┌───────────────────────────────┐    │
│  │       Keycloak          │  │   │  │   Tempo (OTEL Traces)         │    │
│  │  SSO_KEYCLOAK_ENABLED   │  │   │  │   Prometheus (Metrics)        │    │
│  │  DCR Token Validation   │  │   │  │   Grafana (Dashboards)        │    │
│  └─────────────────────────┘  │   │  └───────────────────────────────┘    │
└───────────────────────────────┘   └───────────────────────────────────────┘
```

### Component Responsibilities

| Component | Purpose | Cluster Service |
| ----------- | --------- | ----------------- |
| **MCP Context Forge** | Gateway, Registry, Proxy | New deployment |
| **PostgreSQL** | Multi-tenant data, tools, prompts | CloudNativePG |
| **Cache** | Session, federation, metrics | Dragonfly |
| **Authentication** | SSO, JWT validation | Keycloak |
| **Ingress** | TLS, routing, auth | Envoy Gateway |
| **Observability** | Traces, metrics | Tempo + Prometheus |

---

## Prerequisites

### Required Cluster Services

Verify these services are deployed and healthy:

```bash
# Check Keycloak
kubectl get keycloak -n identity

# Check CloudNativePG operator
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Check Dragonfly
kubectl get dragonfly -n cache

# Check Envoy Gateway
kubectl get gateway -n network

# Check Tempo (for tracing)
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
```

### Required cluster.yaml Variables (Already Set)

```yaml
keycloak_enabled: true          # ✓ Identity provider
cnpg_enabled: true              # ✓ PostgreSQL operator
dragonfly_enabled: true         # ✓ Redis-compatible cache
monitoring_enabled: true        # ✓ Prometheus/Grafana
tracing_enabled: true           # ✓ Tempo distributed tracing
network_policies_enabled: true  # ✓ CiliumNetworkPolicy
```

---

## Keycloak Configuration

### Client Configuration for MCP Context Forge

Add to `cluster.yaml`:

```yaml
#| =========================================================================== #|
#| MCP CONTEXT FORGE                                                           #|
#| REF: https://github.com/IBM/mcp-context-forge                               #|
#| REF: docs/research/mcp-context-forge-deployment-guide-jan-2026.md           #|
#| =========================================================================== #|

# -- Enable MCP Context Forge deployment
#    (OPTIONAL) / (DEFAULT: false)
mcp_context_forge_enabled: true

# -- MCP Context Forge subdomain (creates mcp.${cloudflare_domain})
#    (OPTIONAL) / (DEFAULT: "mcp")
mcp_context_forge_subdomain: "mcp"

# -- MCP Context Forge version (container image tag)
#    REF: https://github.com/IBM/mcp-context-forge/pkgs/container/mcp-context-forge
#    NOTE: Container registry uses commit SHAs or 'latest', not semantic versions
#    (OPTIONAL) / (DEFAULT: "latest")
mcp_context_forge_version: "latest"

# -- MCP Context Forge replicas
#    (OPTIONAL) / (DEFAULT: 1)
mcp_context_forge_replicas: 1

#| =========================================================================== #|
#| DATABASE CONFIGURATION                                                      #|
#| =========================================================================== #|

# -- PostgreSQL database user
#    (OPTIONAL) / (DEFAULT: "mcpgateway")
mcp_context_forge_db_user: "mcpgateway"

# -- PostgreSQL database password
#    (REQUIRED when mcp_context_forge_enabled: true)
mcp_context_forge_db_password: ""  # Generate: openssl rand -base64 24

# -- PostgreSQL database name
#    (OPTIONAL) / (DEFAULT: "mcpgateway")
mcp_context_forge_db_name: "mcpgateway"

# -- PostgreSQL instances (1 for dev, 2+ for HA)
#    (OPTIONAL) / (DEFAULT: 1)
mcp_context_forge_db_instances: 1

# -- PostgreSQL storage size
#    (OPTIONAL) / (DEFAULT: "10Gi")
mcp_context_forge_storage_size: "10Gi"

#| =========================================================================== #|
#| AUTHENTICATION CONFIGURATION                                                #|
#| =========================================================================== #|

# -- Platform admin email (bootstrap admin user)
#    (REQUIRED when mcp_context_forge_enabled: true)
mcp_context_forge_admin_email: "admin@example.com"

# -- Platform admin password
#    (REQUIRED when mcp_context_forge_enabled: true)
mcp_context_forge_admin_password: ""  # Generate: openssl rand -base64 24

# -- JWT secret key (minimum 32 characters)
#    (REQUIRED when mcp_context_forge_enabled: true)
mcp_context_forge_jwt_secret: ""  # Generate: openssl rand -base64 48

# -- Auth encryption secret (AES key for secure storage)
#    (REQUIRED when mcp_context_forge_enabled: true)
mcp_context_forge_auth_encryption_secret: ""  # Generate: openssl rand -hex 32

#| =========================================================================== #|
#| KEYCLOAK SSO CONFIGURATION (requires keycloak_enabled: true)                #|
#| =========================================================================== #|

# -- Enable Keycloak SSO integration
#    (OPTIONAL) / (DEFAULT: false) / (REQUIRES: keycloak_enabled: true)
mcp_context_forge_keycloak_enabled: true

# -- Keycloak client ID
#    (OPTIONAL) / (DEFAULT: "mcp-context-forge")
mcp_context_forge_keycloak_client_id: "mcp-context-forge"

# -- Keycloak client secret
#    (REQUIRED when mcp_context_forge_keycloak_enabled: true)
mcp_context_forge_keycloak_client_secret: ""  # Generate: openssl rand -hex 32

#| =========================================================================== #|
#| DYNAMIC CLIENT REGISTRATION (DCR)                                           #|
#| REF: RFC 7591, RFC 8414                                                     #|
#| =========================================================================== #|

# -- Enable DCR for MCP clients
#    (OPTIONAL) / (DEFAULT: true)
mcp_context_forge_dcr_enabled: true

# -- DCR allowed issuers (empty = allow any trusted issuer)
#    (OPTIONAL) / (DEFAULT: [] - Keycloak issuer auto-added when keycloak_enabled)
# mcp_context_forge_dcr_allowed_issuers: []

# -- DCR default scopes
#    (OPTIONAL) / (DEFAULT: "mcp:read")
# mcp_context_forge_dcr_default_scopes: "mcp:read"

#| =========================================================================== #|
#| DRAGONFLY (REDIS) CONFIGURATION                                             #|
#| =========================================================================== #|

# -- Dragonfly password for MCP Context Forge ACL user
#    (OPTIONAL when dragonfly_acl_enabled: true)
#    When not set, uses dragonfly_password
dragonfly_mcpgateway_password: ""  # Generate: openssl rand -base64 24

#| =========================================================================== #|
#| BACKUP CONFIGURATION (requires rustfs_enabled: true)                        #|
#| =========================================================================== #|

# -- Enable PostgreSQL backups to RustFS
#    (OPTIONAL) / (DEFAULT: true when rustfs_enabled: true)
mcp_context_forge_backup_enabled: true

# -- S3 access key for backups
#    (REQUIRED when mcp_context_forge_backup_enabled: true)
mcp_context_forge_s3_access_key: "mcpgateway-backup"

# -- S3 secret key for backups
#    (REQUIRED when mcp_context_forge_backup_enabled: true)
mcp_context_forge_s3_secret_key: ""  # Generate: openssl rand -base64 24
```

### RustFS IAM Setup for PostgreSQL Backups

> ⚠️ **IMPORTANT**: RustFS does NOT support `mc admin` commands for IAM management.
> All user/policy operations must be performed via the **RustFS Console UI** (port 9001).
> See [RustFS IAM Setup Pattern](../ai-context/patterns/rustfs-iam-setup.md) for detailed reference.

Following the same IAM pattern used for CNPG and other database backups, create a scoped policy for MCP Context Forge PostgreSQL backups.

#### Step 1: Create RustFS Bucket

**Option A:** Via RustFS Console UI:
1. Navigate to **Buckets** → **Create Bucket**
2. **Name:** `mcpgateway-postgres-backups`
3. Click **Create Bucket**

**Option B:** Via RustFS setup job (if using automated bucket creation):

Add to `templates/config/kubernetes/apps/storage/rustfs/setup/job-setup.yaml.j2`:

```yaml
env:
  - name: BUCKETS
    value: "...,mcpgateway-postgres-backups"
```

#### Step 2: Create Custom Policy

Navigate to RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `mcp-context-forge-storage`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::mcpgateway-postgres-backups"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::mcpgateway-postgres-backups/*"
      ]
    }
  ]
}
```

**Why This Policy:**

| Requirement | Permission | Purpose |
| ----------- | ---------- | ------- |
| List objects | `s3:ListBucket` | List WAL files and base backups for retention |
| Read backups | `s3:GetObject` | Download backups for restore/PITR |
| Write backups | `s3:PutObject` | Upload base backups and WAL segments |
| Delete objects | `s3:DeleteObject` | Retention cleanup of old backups |
| Bucket location | `s3:GetBucketLocation` | Barman Cloud SDK compatibility |

**Why Not Built-in `readwrite`:**
- The `readwrite` policy grants access to **ALL** buckets
- The custom `mcp-context-forge-storage` policy scopes access to only `mcpgateway-postgres-backups` bucket
- This protects other buckets (cnpg-backups, etcd-backups, etc.) from MCP Context Forge access (principle of least privilege)

#### Step 3: Assign to Group (Recommended) or Create New Group

**Option A:** Reuse existing `databases` group (if CNPG is enabled):
1. Navigate to **Identity** → **Groups** → `databases`
2. **Add Policy:** `mcp-context-forge-storage`
3. Click **Save**

**Option B:** Create dedicated group:
1. Navigate to **Identity** → **Groups** → **Create Group**
2. **Name:** `ai-system-backups`
3. **Assign Policies:** `mcp-context-forge-storage`
4. Click **Save**

#### Step 4: Create MCP Context Forge Service Account

1. Navigate to **Identity** → **Users** → **Create User**
2. **Access Key:** `mcpgateway-backup` (or any meaningful name)
3. **Assign to Group:** `databases` (or `ai-system-backups` if using dedicated group)
4. Click **Save**

#### Step 5: Generate Access Key

1. Click on the newly created user (`mcpgateway-backup`)
2. Navigate to **Service Accounts** tab
3. Click **Create Access Key**
4. ⚠️ **Copy and save both keys immediately** - the secret key won't be shown again!

#### Step 6: Update cluster.yaml

```yaml
# MCP Context Forge PostgreSQL Backup Credentials
mcp_context_forge_backup_enabled: true
mcp_context_forge_s3_access_key: "<access-key-from-step-5>"
mcp_context_forge_s3_secret_key: "<secret-key-from-step-5>"  # SOPS-encrypted
```

#### Step 7: Apply Changes

```bash
task configure
task reconcile
```

### IAM Architecture Summary

The MCP Context Forge IAM structure mirrors other database backup patterns:

| Component | CNPG | MCP Context Forge |
| --------- | ---- | ----------------- |
| **Policy** | `database-storage` | `mcp-context-forge-storage` |
| **Scoped Buckets** | `cnpg-backups` | `mcpgateway-postgres-backups` |
| **Group** | `databases` | `databases` (shared) or `ai-system-backups` |
| **User** | `cnpg-backup` | `mcpgateway-backup` |
| **Permissions** | Full CRUD on cnpg-backups | Full CRUD on mcpgateway-postgres-backups |

This pattern ensures:
- **Principle of least privilege**: MCP Context Forge only accesses its own backup bucket
- **Audit trail**: User/group structure enables access tracking
- **Scalability**: Future ai-system databases can share the group with dedicated policies

```yaml
#| =========================================================================== #|
#| OBSERVABILITY CONFIGURATION                                                 #|
#| =========================================================================== #|

# -- Enable Prometheus ServiceMonitor
#    (OPTIONAL) / (DEFAULT: true when monitoring_enabled: true)
mcp_context_forge_monitoring_enabled: true

# -- Enable OpenTelemetry tracing to Tempo
#    (OPTIONAL) / (DEFAULT: true when tracing_enabled: true)
mcp_context_forge_tracing_enabled: true

# -- Tracing sample rate (0.0 - 1.0)
#    (OPTIONAL) / (DEFAULT: "0.1")
mcp_context_forge_tracing_sample_rate: "0.1"
```

### Keycloak Realm Client Definition

Add to `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`:

```yaml
#% if mcp_context_forge_keycloak_enabled | default(false) %#
      #| =========================================================================== #|
      #| MCP CONTEXT FORGE OIDC CLIENT                                               #|
      #| Gateway for MCP servers with multi-tenant authentication                    #|
      #| Auto-created when mcp_context_forge_keycloak_enabled + secret set           #|
      #| clientId and secret use $(env:VAR) substitution from keycloak-realm-secrets #|
      #| REF: docs/research/mcp-context-forge-deployment-guide-jan-2026.md           #|
      #| =========================================================================== #|
      - clientId: "$(env:MCP_CONTEXT_FORGE_CLIENT_ID)"
        name: "MCP Context Forge"
        description: "OIDC client for MCP Context Forge Gateway - enables SSO for multi-tenant MCP server registry"
        enabled: true
        publicClient: false
        clientAuthenticatorType: "client-secret"
        secret: "$(env:MCP_CONTEXT_FORGE_CLIENT_SECRET)"
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        serviceAccountsEnabled: false
        implicitFlowEnabled: false
        protocol: "openid-connect"
        redirectUris:
          - "https://#{ mcp_context_forge_subdomain | default('mcp') }#.#{ cloudflare_domain }#/*"
          - "https://#{ mcp_context_forge_subdomain | default('mcp') }#.#{ cloudflare_domain }#/auth/callback"
        webOrigins:
          - "https://#{ mcp_context_forge_subdomain | default('mcp') }#.#{ cloudflare_domain }#"
        attributes:
          pkce.code.challenge.method: "S256"
          post.logout.redirect.uris: "https://#{ mcp_context_forge_subdomain | default('mcp') }#.#{ cloudflare_domain }#/*"
        #| NOTE: 'openid' is implicit in OIDC protocol, not a configurable scope in Keycloak #|
        #| offline_access in default scopes enables refresh tokens for session persistence #|
        #| groups scope provides OIDC-compliant group membership claims #|
        defaultClientScopes:
          - "profile"
          - "email"
          - "offline_access"
          - "groups"
        optionalClientScopes:
          - "address"
          - "phone"
        #| Protocol mappers for role and group claims (used for team mapping) #|
        protocolMappers:
          #| Map realm roles to 'roles' claim for MCP Gateway team/role mapping #|
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
          #| Map groups to 'groups' claim for team assignment #|
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
#% endif %#
```

### MCP Client Scopes for DCR

Add MCP-specific scopes to enable proper audience binding for MCP 2025-06-18+ spec compliance.

**Location:** Add these scopes to the `clientScopes` array in `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2`, alongside existing scopes like `groups` and `offline_access`:

```yaml
    #| =========================================================================== #|
    #| MCP CLIENT SCOPES - For MCP Server Authorization                            #|
    #| Add to existing clientScopes array in realm-config.yaml.j2                  #|
    #| REF: https://www.keycloak.org/securing-apps/mcp-authz-server                #|
    #| =========================================================================== #|
#% if mcp_context_forge_enabled | default(false) %#
      #| MCP Tools scope - access to MCP server tools #|
      - name: "mcp:tools"
        description: "Access to MCP server tools"
        protocol: "openid-connect"
        attributes:
          include.in.token.scope: "true"
          display.on.consent.screen: "true"
          consent.screen.text: "Access to MCP server tools"
        protocolMappers:
          - name: "mcp-audience"
            protocol: "openid-connect"
            protocolMapper: "oidc-audience-mapper"
            consentRequired: false
            config:
              included.custom.audience: "https://#{ mcp_context_forge_subdomain | default('mcp') }#.#{ cloudflare_domain }#"
              id.token.claim: "true"
              access.token.claim: "true"

      #| MCP Prompts scope - access to MCP server prompts #|
      - name: "mcp:prompts"
        description: "Access to MCP server prompts"
        protocol: "openid-connect"
        attributes:
          include.in.token.scope: "true"
          display.on.consent.screen: "true"
          consent.screen.text: "Access to MCP server prompts"

      #| MCP Resources scope - access to MCP server resources #|
      - name: "mcp:resources"
        description: "Access to MCP server resources"
        protocol: "openid-connect"
        attributes:
          include.in.token.scope: "true"
          display.on.consent.screen: "true"
          consent.screen.text: "Access to MCP server resources"
#% endif %#
```

---

## Deployment Configuration

### Template Directory Structure

```
templates/config/kubernetes/apps/ai-system/mcp-context-forge/
├── ks.yaml.j2                    # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2     # Kustomize resources
    ├── deployment.yaml.j2        # Deployment manifest (bjw-s app-template alternative)
    ├── service.yaml.j2           # ClusterIP service
    ├── postgresql.yaml.j2        # CloudNativePG Cluster
    ├── secret.sops.yaml.j2       # SOPS-encrypted secrets
    ├── referencegrant.yaml.j2    # Cross-namespace reference for HTTPRoute
    ├── networkpolicy.yaml.j2     # CiliumNetworkPolicy
    └── servicemonitor.yaml.j2    # Prometheus ServiceMonitor

# HTTPRoute is CENTRALIZED (add to existing file):
templates/config/kubernetes/apps/network/envoy-gateway/app/httproutes.yaml.j2
```

**Note:** Following the cluster's centralized routing pattern, HTTPRoutes are added to `httproutes.yaml.j2` in the network namespace rather than individual app directories. This enables consistent SecurityPolicy application and simplified route management.

### Flux Kustomization (ks.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) %#
---
#| ============================================================================= #|
#| MCP CONTEXT FORGE FLUX KUSTOMIZATION                                          #|
#| REF: https://github.com/IBM/mcp-context-forge                                 #|
#| REF: docs/research/mcp-context-forge-deployment-guide-jan-2026.md             #|
#| ============================================================================= #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app mcp-context-forge
  namespace: flux-system
spec:
  targetNamespace: ai-system
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    #| Core infrastructure dependencies #|
    - name: coredns
      namespace: kube-system
    - name: cloudnative-pg
      namespace: cnpg-system
    #| Shared Dragonfly (Redis-compatible) cache in cache namespace #|
    - name: dragonfly
      namespace: cache
#% if mcp_context_forge_keycloak_enabled | default(false) %#
    #| Keycloak for SSO authentication #|
    - name: keycloak
      namespace: identity
#% endif %#
#% if mcp_context_forge_backup_enabled | default(false) %#
    #| RustFS for PostgreSQL backups #|
    - name: rustfs
      namespace: storage
#% endif %#
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: mcp-context-forge
      namespace: ai-system
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/ai-system/mcp-context-forge/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  timeout: 15m
  wait: true
#% endif %#
```

### Deployment Manifest (deployment.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) %#
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-context-forge
  namespace: ai-system
  labels:
    app.kubernetes.io/name: mcp-context-forge
    app.kubernetes.io/version: "#{ mcp_context_forge_version | default('latest') }#"
spec:
  replicas: #{ mcp_context_forge_replicas | default(1) }#
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: mcp-context-forge
  template:
    metadata:
      labels:
        app.kubernetes.io/name: mcp-context-forge
#% if network_policies_enabled | default(false) %#
        network.cilium.io/api-access: "true"
#% endif %#
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "4444"
        prometheus.io/path: "/metrics"
        secret.reloader.stakater.com/reload: "mcp-context-forge-secret,mcp-context-forge-db-secret"
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      terminationGracePeriodSeconds: 60
      containers:
        - name: mcp-context-forge
          image: ghcr.io/ibm/mcp-context-forge:#{ mcp_context_forge_version | default('1.0.0-BETA-1') }#
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 4444
              protocol: TCP
          env:
            #| Core Settings #|
            - name: HOST
              value: "0.0.0.0"
            - name: PORT
              value: "4444"
            - name: ENVIRONMENT
              value: "production"
            - name: LOG_LEVEL
              value: "INFO"
            - name: LOG_FORMAT
              value: "json"

            #| Database Configuration #|
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: mcp-context-forge-secret
                  key: DATABASE_URL
            - name: DB_POOL_SIZE
              value: "15"
            - name: DB_MAX_OVERFLOW
              value: "30"

            #| Cache Configuration (Dragonfly) #|
            - name: CACHE_TYPE
              value: "redis"
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: mcp-context-forge-secret
                  key: REDIS_URL

            #| Authentication #|
            - name: AUTH_REQUIRED
              value: "true"
            - name: EMAIL_AUTH_ENABLED
              value: "true"
            - name: PLATFORM_ADMIN_EMAIL
              value: "#{ mcp_context_forge_admin_email }#"
            - name: PLATFORM_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mcp-context-forge-secret
                  key: PLATFORM_ADMIN_PASSWORD

            #| JWT Configuration #|
            - name: JWT_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: mcp-context-forge-secret
                  key: JWT_SECRET_KEY
            - name: JWT_ALGORITHM
              value: "HS256"
            - name: JWT_AUDIENCE
              value: "mcpgateway-api"
            - name: JWT_ISSUER
              value: "mcpgateway"
            - name: TOKEN_EXPIRY
              value: "10080"

            #| Auth Encryption #|
            - name: AUTH_ENCRYPTION_SECRET
              valueFrom:
                secretKeyRef:
                  name: mcp-context-forge-secret
                  key: AUTH_ENCRYPTION_SECRET

#% if mcp_context_forge_keycloak_enabled | default(false) %#
            #| Keycloak SSO Configuration #|
            - name: SSO_ENABLED
              value: "true"
            - name: SSO_KEYCLOAK_ENABLED
              value: "true"
            - name: SSO_KEYCLOAK_BASE_URL
              value: "https://#{ keycloak_hostname }#"
            - name: SSO_KEYCLOAK_REALM
              value: "#{ keycloak_realm }#"
            - name: SSO_KEYCLOAK_CLIENT_ID
              value: "#{ mcp_context_forge_keycloak_client_id | default('mcp-context-forge') }#"
            - name: SSO_KEYCLOAK_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: mcp-context-forge-secret
                  key: KEYCLOAK_CLIENT_SECRET
            - name: SSO_KEYCLOAK_MAP_REALM_ROLES
              value: "true"
            - name: SSO_KEYCLOAK_GROUPS_CLAIM
              value: "groups"
            - name: SSO_AUTO_CREATE_USERS
              value: "true"
#% endif %#

#% if mcp_context_forge_dcr_enabled | default(true) %#
            #| Dynamic Client Registration (DCR) #|
            - name: DCR_ENABLED
              value: "true"
            - name: DCR_AUTO_REGISTER_ON_MISSING_CREDENTIALS
              value: "true"
            - name: OAUTH_DISCOVERY_ENABLED
              value: "true"
#% if mcp_context_forge_keycloak_enabled | default(false) %#
            - name: DCR_ALLOWED_ISSUERS
              value: '["https://#{ keycloak_hostname }#/realms/#{ keycloak_realm }#"]'
#% endif %#
#% endif %#

            #| Admin UI #|
            - name: MCPGATEWAY_UI_ENABLED
              value: "true"
            - name: MCPGATEWAY_ADMIN_API_ENABLED
              value: "true"
            - name: MCPGATEWAY_A2A_ENABLED
              value: "true"

#% if mcp_context_forge_tracing_enabled | default(false) %#
            #| OpenTelemetry Tracing (Tempo) #|
            - name: OTEL_ENABLE_OBSERVABILITY
              value: "true"
            - name: OTEL_TRACES_EXPORTER
              value: "otlp"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://tempo.monitoring.svc:4317"
            - name: OTEL_EXPORTER_OTLP_PROTOCOL
              value: "grpc"
            - name: OTEL_SERVICE_NAME
              value: "mcp-context-forge"
#% endif %#

            #| Prometheus Metrics #|
            - name: ENABLE_METRICS
              value: "true"

          resources:
            requests:
              cpu: #{ mcp_context_forge_cpu_request | default('200m') }#
              memory: #{ mcp_context_forge_memory_request | default('512Mi') }#
            limits:
              cpu: #{ mcp_context_forge_cpu_limit | default('1000m') }#
              memory: #{ mcp_context_forge_memory_limit | default('1Gi') }#

          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 15
            timeoutSeconds: 10
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3

          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]

          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: cache
              mountPath: /.cache

      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 100Mi
        - name: cache
          emptyDir:
            sizeLimit: 500Mi
#% endif %#
```

### Secret Template (secret.sops.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: mcp-context-forge-secret
  namespace: ai-system
type: Opaque
stringData:
  #| Database connection URL #|
  DATABASE_URL: "postgresql://#{ mcp_context_forge_db_user | default('mcpgateway') }#:#{ mcp_context_forge_db_password }#@mcp-context-forge-postgresql-rw.ai-system.svc.cluster.local:5432/#{ mcp_context_forge_db_name | default('mcpgateway') }#"

  #| Redis/Dragonfly connection URL #|
  REDIS_URL: "redis://mcpgateway:#{ dragonfly_mcpgateway_password | default(dragonfly_password) }#@dragonfly.cache.svc.cluster.local:6379/0"

  #| Platform admin password (email-based auth) #|
  PLATFORM_ADMIN_PASSWORD: "#{ mcp_context_forge_admin_password }#"

  #| Basic Auth credentials (HTTP Basic auth for admin UI) #|
  BASIC_AUTH_PASSWORD: "#{ mcp_context_forge_admin_password }#"

  #| JWT secret key #|
  JWT_SECRET_KEY: "#{ mcp_context_forge_jwt_secret }#"

  #| Auth encryption secret #|
  AUTH_ENCRYPTION_SECRET: "#{ mcp_context_forge_auth_encryption_secret }#"

#% if mcp_context_forge_keycloak_enabled | default(false) %#
  #| Keycloak client secret #|
  KEYCLOAK_CLIENT_SECRET: "#{ mcp_context_forge_keycloak_client_secret }#"
#% endif %#
#% endif %#
```

### PostgreSQL Cluster (postgresql.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) %#
---
#| ============================================================================= #|
#| MCP CONTEXT FORGE POSTGRESQL - CloudNativePG Cluster                          #|
#| REF: docs/guides/cnpg-implementation.md                                       #|
#| ============================================================================= #|
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: mcp-context-forge-postgresql
  namespace: ai-system
spec:
  instances: #{ mcp_context_forge_db_instances | default(1) }#
  imageName: #{ cnpg_postgres_image | default('ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie') }#

  bootstrap:
    initdb:
      database: #{ mcp_context_forge_db_name | default('mcpgateway') }#
      owner: #{ mcp_context_forge_db_user | default('mcpgateway') }#
      secret:
        name: mcp-context-forge-db-secret

  storage:
    size: #{ mcp_context_forge_storage_size | default('10Gi') }#
    storageClass: #{ cnpg_storage_class | default('proxmox-zfs') }#

  postgresql:
    parameters:
      shared_buffers: "256MB"
      effective_cache_size: "768MB"
      maintenance_work_mem: "128MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
      work_mem: "16MB"
      min_wal_size: "1GB"
      max_wal_size: "4GB"
      max_worker_processes: "4"
      max_parallel_workers_per_gather: "2"
      max_parallel_workers: "4"
      max_parallel_maintenance_workers: "2"

  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

#% if mcp_context_forge_backup_enabled | default(false) %#
  backup:
    barmanObjectStore:
      destinationPath: "s3://mcpgateway-postgres-backups/"
      endpointURL: "http://rustfs-svc.storage.svc.cluster.local:9000"
      s3Credentials:
        accessKeyId:
          name: mcp-context-forge-s3-secret
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: mcp-context-forge-s3-secret
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
        maxParallel: 2
      data:
        compression: gzip
    retentionPolicy: "7d"
#% endif %#

  monitoring:
    enablePodMonitor: #{ mcp_context_forge_monitoring_enabled | default(monitoring_enabled | default(false)) | lower }#
---
#| Database credentials secret #|
apiVersion: v1
kind: Secret
metadata:
  name: mcp-context-forge-db-secret
  namespace: ai-system
type: kubernetes.io/basic-auth
stringData:
  username: #{ mcp_context_forge_db_user | default('mcpgateway') }#
  password: #{ mcp_context_forge_db_password }#
#% if mcp_context_forge_backup_enabled | default(false) %#
---
#| S3 backup credentials secret #|
apiVersion: v1
kind: Secret
metadata:
  name: mcp-context-forge-s3-secret
  namespace: ai-system
type: Opaque
stringData:
  ACCESS_KEY_ID: #{ mcp_context_forge_s3_access_key }#
  SECRET_ACCESS_KEY: #{ mcp_context_forge_s3_secret_key }#
#% endif %#
#% endif %#
```

### HTTPRoute (Centralized Pattern)

**IMPORTANT:** HTTPRoutes for ai-system applications are centralized in the network namespace. Add the following to `templates/config/kubernetes/apps/network/envoy-gateway/app/httproutes.yaml.j2`:

```yaml
#| =========================================================================== #|
#| MCP CONTEXT FORGE - MCP Gateway and Registry Platform                       #|
#| Both gateways: Split-horizon DNS (prevents asymmetric routing)              #|
#|   - External users: Cloudflare DNS → envoy-external → MCP Context Forge    #|
#|   - Internal users: UniFi DNS → envoy-internal → MCP Context Forge         #|
#| NOTE: NO security label - MCP Context Forge uses native SSO via Keycloak   #|
#|       (SSO_KEYCLOAK_*). Gateway OIDC would cause dual authentication.      #|
#| REF: docs/research/mcp-context-forge-deployment-guide-jan-2026.md          #|
#| =========================================================================== #|
#% if mcp_context_forge_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mcp-context-forge
  namespace: network
  #| No OIDC protection - MCP Context Forge uses native SSO via SSO_KEYCLOAK_* #|
spec:
  hostnames:
    - "#{ mcp_context_forge_subdomain | default('mcp') }#.${SECRET_DOMAIN}"
  parentRefs:
    #| External gateway: Cloudflare DNS creates record (public access via tunnel) #|
    - name: envoy-external
      namespace: network
      sectionName: https
  rules:
    - backendRefs:
        #| MCP Context Forge service in ai-system namespace #|
        - name: mcp-context-forge
          namespace: ai-system
          port: 4444
      matches:
        - path:
            type: PathPrefix
            value: /
#% endif %#
```

**Note:** This pattern requires a ReferenceGrant in the ai-system namespace to allow cross-namespace backend references (see below).

### Service (service.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) %#
---
apiVersion: v1
kind: Service
metadata:
  name: mcp-context-forge
  namespace: ai-system
  labels:
    app.kubernetes.io/name: mcp-context-forge
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 4444
      targetPort: http
      protocol: TCP
  selector:
    app.kubernetes.io/name: mcp-context-forge
#% endif %#
```

### ReferenceGrant (referencegrant.yaml.j2)

This ReferenceGrant allows the centralized HTTPRoute in the network namespace to reference the MCP Context Forge service in the ai-system namespace:

```yaml
#% if mcp_context_forge_enabled | default(false) %#
---
#| ============================================================================= #|
#| ReferenceGrant: Allow network namespace to access MCP Context Forge          #|
#| Required for HTTPRoutes in network namespace to reference                    #|
#| the mcp-context-forge service in ai-system namespace                         #|
#| REF: https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1beta1.ReferenceGrant #|
#| ============================================================================= #|
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: network-mcp-context-forge-access
  namespace: ai-system
spec:
  from:
    #| Allow HTTPRoute from network namespace #|
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: network
  to:
    #| Grant access to MCP Context Forge service #|
    - group: ""
      kind: Service
      name: mcp-context-forge
#% endif %#
```

---

## Network Policies

### CiliumNetworkPolicy (networkpolicy.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| MCP CONTEXT FORGE NETWORK POLICY                                              #|
#| Allow: Envoy Gateway ingress, PostgreSQL, Dragonfly, Keycloak, Tempo          #|
#| Mode: {{ 'enforce' if enforce else 'audit' }}                                 #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: mcp-context-forge
  namespace: ai-system
spec:
  description: "MCP Context Forge: Gateway traffic, database, cache, auth, and tracing"
#% if enforce %#
  enableDefaultDeny:
    ingress: true
    egress: true
#% else %#
  enableDefaultDeny:
    ingress: false
    egress: false
#% endif %#
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-context-forge
  ingress:
    #| Allow ingress from Envoy Gateway proxy #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: envoy
            app.kubernetes.io/component: proxy
      toPorts:
        - ports:
            - port: "4444"
              protocol: TCP
    #| Allow Prometheus scraping #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "4444"
              protocol: TCP
  egress:
    #| Allow DNS resolution #|
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
    #| Allow PostgreSQL access #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: mcp-context-forge-postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| Allow Dragonfly (Redis) access #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: dragonfly
            io.kubernetes.pod.namespace: cache
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP
    #| Allow Keycloak access (for SSO validation) #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
            io.kubernetes.pod.namespace: identity
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    #| Allow Tempo access (for tracing) #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: tempo
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
    #| Allow egress to upstream MCP servers (external) #|
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "80"
              protocol: TCP
#% endif %#
```

---

## DCR Configuration

### Understanding DCR in MCP Context Forge

Dynamic Client Registration (DCR) allows MCP clients to automatically register with the gateway without manual client configuration. This is essential for the MCP ecosystem where arbitrary clients need to connect.

```
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│   MCP Client     │      │  MCP Context     │      │    Keycloak      │
│  (Claude, etc.)  │      │    Forge         │      │  (Auth Server)   │
└────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘
         │                         │                         │
         │  1. Discovery Request   │                         │
         │  GET /.well-known/      │                         │
         │  oauth-authorization-   │                         │
         │  server                 │                         │
         │─────────────────────────>                         │
         │                         │  2. Fetch Metadata      │
         │                         │  GET /.well-known/      │
         │                         │  openid-configuration   │
         │                         │─────────────────────────>
         │                         │                         │
         │  3. Metadata Response   │  Metadata Response      │
         │  (issuer, endpoints,    │<─────────────────────────
         │   DCR endpoint, etc.)   │                         │
         │<─────────────────────────                         │
         │                         │                         │
         │  4. Client Registration │                         │
         │  POST /register         │                         │
         │  (client metadata)      │                         │
         │─────────────────────────>                         │
         │                         │  5. Forward DCR Request │
         │                         │  POST /clients-         │
         │                         │  registrations/openid-  │
         │                         │  connect                │
         │                         │─────────────────────────>
         │                         │                         │
         │                         │  6. Client Credentials  │
         │                         │  (client_id, secret)    │
         │  7. Registration        │<─────────────────────────
         │  Response               │                         │
         │<─────────────────────────                         │
         │                         │                         │
         │  8. Authorization Code Flow (Standard OAuth)      │
         │<══════════════════════════════════════════════════>
         │                         │                         │
         │  9. Access Token        │                         │
         │  (bound to MCP server)  │                         │
         │<─────────────────────────                         │
         │                         │                         │
         │  10. MCP API Calls      │                         │
         │  (with Bearer token)    │                         │
         │─────────────────────────>                         │
```

### Keycloak DCR Configuration

Enable DCR in Keycloak for MCP Context Forge clients:

1. **Create Initial Access Token** (for anonymous DCR):
   - Navigate to Keycloak Admin → Realm Settings → Client Registration
   - Click "Create" under "Initial Access Tokens"
   - Set expiration and max client count
   - Store token securely

2. **Configure Client Registration Policies**:
   - Allow anonymous registration OR require Initial Access Token
   - Set scope restrictions (mcp:tools, mcp:prompts, mcp:resources)

3. **Set Trusted Host Policies**:
   - Add MCP Context Forge domain to trusted hosts

### Environment Variables for DCR

```yaml
# Enable DCR
DCR_ENABLED: "true"

# Auto-register when gateway lacks credentials for an issuer
DCR_AUTO_REGISTER_ON_MISSING_CREDENTIALS: "true"

# Enable RFC 8414 metadata discovery
OAUTH_DISCOVERY_ENABLED: "true"

# Restrict to trusted issuers (Keycloak only)
DCR_ALLOWED_ISSUERS: '["https://sso.matherly.net/realms/matherlynet"]'

# Default scopes for DCR
DCR_DEFAULT_SCOPES: "mcp:read"

# Token endpoint auth method
DCR_TOKEN_ENDPOINT_AUTH_METHOD: "client_secret_basic"
```

---

## HyprMCP Gateway (Optional)

If you need **anonymous DCR** without Keycloak Initial Access Tokens, or if MCP clients don't support Keycloak's DCR endpoint directly, deploy HyprMCP Gateway as a DCR proxy.

### When to Use HyprMCP

| Scenario | Use HyprMCP? |
| ---------- | ------------ |
| MCP clients support standard OIDC DCR | No |
| Need anonymous DCR (no IAT) | Yes |
| MCP 2025-11-25 spec with CIMD | No |
| Enterprise environment with strict DCR policies | Consider |
| Simple single-tenant deployment | No |

### HyprMCP Deployment (if needed)

```yaml
#% if mcp_context_forge_hyprmcp_enabled | default(false) %#
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hyprmcp-gateway
  namespace: ai-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: hyprmcp-gateway
  template:
    metadata:
      labels:
        app.kubernetes.io/name: hyprmcp-gateway
    spec:
      containers:
        - name: hyprmcp
          image: ghcr.io/hyprmcp/mcp-gateway:latest
          ports:
            - containerPort: 8080
          env:
            - name: UPSTREAM_MCP_SERVER
              value: "http://mcp-context-forge.ai-system.svc.cluster.local:4444"
            - name: OIDC_ISSUER
              value: "https://#{ keycloak_hostname }#/realms/#{ keycloak_realm }#"
            - name: DCR_ENABLED
              value: "true"
            - name: DCR_PUBLIC_CLIENT
              value: "true"
#% endif %#
```

---

## Monitoring & Observability

### ServiceMonitor (servicemonitor.yaml.j2)

```yaml
#% if mcp_context_forge_enabled | default(false) and mcp_context_forge_monitoring_enabled | default(monitoring_enabled | default(false)) %#
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mcp-context-forge
  namespace: ai-system
  labels:
    app.kubernetes.io/name: mcp-context-forge
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: mcp-context-forge
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
  namespaceSelector:
    matchNames:
      - ai-system
#% endif %#
```

### Grafana Dashboard

Create a ConfigMap for the MCP Context Forge dashboard:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mcp-context-forge-dashboard
  namespace: ai-system
  labels:
    grafana_dashboard: "1"
data:
  mcp-context-forge.json: |
    {
      "title": "MCP Context Forge",
      "panels": [
        {
          "title": "Request Rate",
          "targets": [
            {
              "expr": "rate(http_requests_total{service=\"mcp-context-forge\"}[5m])"
            }
          ]
        },
        {
          "title": "Tool Invocations",
          "targets": [
            {
              "expr": "rate(mcp_tool_calls_total{service=\"mcp-context-forge\"}[5m])"
            }
          ]
        },
        {
          "title": "Active Sessions",
          "targets": [
            {
              "expr": "mcp_active_sessions{service=\"mcp-context-forge\"}"
            }
          ]
        }
      ]
    }
```

---

## Security Considerations

### Authentication Layering

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security Layers                              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: TLS Termination (Envoy Gateway)                       │
│           - Certificate from cert-manager                       │
│           - Let's Encrypt via Cloudflare DNS-01                 │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: OIDC Authentication (Keycloak)                        │
│           - SSO_KEYCLOAK_ENABLED=true                           │
│           - Token validation at gateway                         │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: JWT Authorization (MCP Context Forge)                 │
│           - JWT_AUDIENCE verification                           │
│           - JWT_ISSUER verification                             │
│           - Token expiration enforcement                        │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: Team-based RBAC (MCP Context Forge)                   │
│           - Multi-tenant isolation                              │
│           - Role-based permissions                              │
│           - Personal team auto-creation                         │
├─────────────────────────────────────────────────────────────────┤
│  Layer 5: Network Policies (CiliumNetworkPolicy)                │
│           - Pod-to-pod isolation                                │
│           - Explicit egress allow-list                          │
└─────────────────────────────────────────────────────────────────┘
```

### Secret Management

All secrets are managed via SOPS with Age encryption:

```yaml
# Generate secrets before deployment
openssl rand -base64 24  # Database password
openssl rand -base64 48  # JWT secret (min 32 chars)
openssl rand -hex 32     # Auth encryption secret
openssl rand -hex 32     # Keycloak client secret
openssl rand -base64 24  # Dragonfly ACL password
```

### Security Headers

MCP Context Forge enables security headers by default:

```yaml
SECURITY_HEADERS_ENABLED: "true"
X_FRAME_OPTIONS: "DENY"
HSTS_ENABLED: "true"
HSTS_MAX_AGE: "31536000"
```

---

## Integration Points

### With Existing Cluster Services

| Service | Integration Method | Configuration |
| --------- | ------------------- | --------------- |
| **Keycloak** | OIDC SSO | `SSO_KEYCLOAK_*` env vars |
| **Dragonfly** | Redis cache | `REDIS_URL` with ACL password |
| **CloudNativePG** | PostgreSQL | `DATABASE_URL` connection string |
| **Tempo** | OTEL traces | `OTEL_EXPORTER_OTLP_ENDPOINT` |
| **Prometheus** | Metrics | ServiceMonitor + `/metrics` endpoint |
| **Envoy Gateway** | Ingress | HTTPRoute |
| **LiteLLM** | A2A integration | Agent registration (optional) |
| **Obot** | MCP client | Connect via DCR/OIDC |
| **Langfuse** | Observability | A2A agent (optional) |

### With Obot MCP Client

Obot can connect to MCP Context Forge as an MCP client:

1. Register MCP Context Forge URL in Obot's MCP catalog
2. Obot uses Keycloak SSO for authentication
3. MCP tools from Context Forge available to Obot agents

### With LiteLLM

LiteLLM can be registered as an A2A agent:

```json
{
  "name": "litellm",
  "type": "openai",
  "base_url": "http://litellm.ai-system.svc.cluster.local:4000/v1",
  "api_key": "sk-...",
  "model": "gpt-4o"
}
```

---

## Dragonfly ACL Configuration

Add MCP Context Forge user to Dragonfly ACL:

```yaml
# In cluster.yaml
dragonfly_mcpgateway_password: "..."  # Generate: openssl rand -base64 24

# Dragonfly ACL rule (added to dragonfly config)
# User: mcpgateway
# Permissions: Full access to mcpgw:* keys
```

Update `templates/config/kubernetes/apps/cache/dragonfly/app/configmap.yaml.j2`:

```yaml
#% if mcp_context_forge_enabled | default(false) %#
  #| MCP Context Forge cache user #|
  - name: mcpgateway
    password: "#{ dragonfly_mcpgateway_password | default(dragonfly_password) }#"
    permissions:
      - "+@all"
      - "~mcpgw:*"
#% endif %#
```

---

## Troubleshooting

### Common Issues

| Issue | Diagnosis | Solution |
| ------- | ----------- | ---------- |
| SSO login fails | Check Keycloak logs, verify client secret | Regenerate client secret, verify redirect URIs |
| DCR registration fails | Check `DCR_ALLOWED_ISSUERS` | Add Keycloak issuer to allowlist |
| Database connection fails | Check CNPG cluster status | Verify `DATABASE_URL`, check network policy |
| Redis connection fails | Check Dragonfly logs | Verify ACL user/password, check network policy |
| Token validation fails | Check JWT settings | Verify `JWT_ISSUER` and `JWT_AUDIENCE` match Keycloak |
| Traces not appearing | Check Tempo connection | Verify `OTEL_EXPORTER_OTLP_ENDPOINT` |

### Diagnostic Commands

```bash
# Check pod status
kubectl get pods -n ai-system -l app.kubernetes.io/name=mcp-context-forge

# View logs
kubectl logs -n ai-system -l app.kubernetes.io/name=mcp-context-forge -f

# Check database connection
kubectl exec -n ai-system deploy/mcp-context-forge -- \
  python -c "from mcpgateway.db import engine; print(engine.url)"

# Test Keycloak connectivity
kubectl exec -n ai-system deploy/mcp-context-forge -- \
  curl -s https://sso.matherly.net/realms/matherlynet/.well-known/openid-configuration | jq .issuer

# Check DCR endpoint
curl -s https://mcp.matherly.net/.well-known/oauth-authorization-server | jq .

# Test health endpoint
curl -s https://mcp.matherly.net/health | jq .
```

---

## References

### Official Documentation

- [IBM MCP Context Forge GitHub](https://github.com/IBM/mcp-context-forge)
- [MCP Context Forge Documentation](https://ibm.github.io/mcp-context-forge/)
- [Keycloak MCP Integration Guide](https://www.keycloak.org/securing-apps/mcp-authz-server)
- [HyprMCP Gateway](https://github.com/hyprmcp/mcp-gateway)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

### Keycloak DCR References

- [Keycloak Client Registration](https://www.keycloak.org/securing-apps/client-registration)
- [Keycloak DCR Configuration](https://medium.com/keycloak/dynamic-client-registration-in-keycloak-4dd1c5cd5e69)
- [MCP DCR with SPIFFE](https://blog.christianposta.com/implementing-mcp-dynamic-client-registration-with-spiffe/)

### Cluster Documentation

- [Architecture Overview](../ARCHITECTURE.md)
- [Configuration Guide](../CONFIGURATION.md)
- [Operations Guide](../OPERATIONS.md)
- [Keycloak SSO Patterns](./keycloak-social-identity-providers-integration-jan-2026.md)
- [LiteLLM Integration](./litellm-proxy-gateway-integration-jan-2026.md)
- [Obot MCP Gateway](./obot-mcp-gateway-integration-jan-2026.md)

---

## Appendix: Full cluster.yaml Variables

```yaml
#| =========================================================================== #|
#| MCP CONTEXT FORGE - Complete Variable Reference                             #|
#| =========================================================================== #|

# Core Settings
mcp_context_forge_enabled: true
mcp_context_forge_subdomain: "mcp"
mcp_context_forge_version: "latest"
mcp_context_forge_replicas: 1

# Resources
mcp_context_forge_cpu_request: "200m"
mcp_context_forge_cpu_limit: "1000m"
mcp_context_forge_memory_request: "512Mi"
mcp_context_forge_memory_limit: "1Gi"

# Database
mcp_context_forge_db_user: "mcpgateway"
mcp_context_forge_db_password: ""  # REQUIRED - SOPS encrypted
mcp_context_forge_db_name: "mcpgateway"
mcp_context_forge_db_instances: 1
mcp_context_forge_storage_size: "10Gi"

# Authentication
mcp_context_forge_admin_email: ""  # REQUIRED
mcp_context_forge_admin_password: ""  # REQUIRED - SOPS encrypted
mcp_context_forge_jwt_secret: ""  # REQUIRED - SOPS encrypted
mcp_context_forge_auth_encryption_secret: ""  # REQUIRED - SOPS encrypted

# Keycloak SSO
mcp_context_forge_keycloak_enabled: true
mcp_context_forge_keycloak_client_id: "mcp-context-forge"
mcp_context_forge_keycloak_client_secret: ""  # REQUIRED - SOPS encrypted

# DCR
mcp_context_forge_dcr_enabled: true
mcp_context_forge_dcr_allowed_issuers: []  # Auto-populated with Keycloak
mcp_context_forge_dcr_default_scopes: "mcp:read"

# Dragonfly ACL
dragonfly_mcpgateway_password: ""  # REQUIRED - SOPS encrypted

# Backup
mcp_context_forge_backup_enabled: true
mcp_context_forge_s3_access_key: "mcpgateway-backup"
mcp_context_forge_s3_secret_key: ""  # REQUIRED - SOPS encrypted

# Observability
mcp_context_forge_monitoring_enabled: true
mcp_context_forge_tracing_enabled: true
mcp_context_forge_tracing_sample_rate: "0.1"

# Optional: HyprMCP Gateway
mcp_context_forge_hyprmcp_enabled: false
```

---

**Document Version:** 1.0
**Last Updated:** January 2026
**Author:** Research Agent
**Status:** Ready for Implementation Review
