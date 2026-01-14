# Obot MCP Gateway Integration Research

**Date:** January 2026
**Status:** Research Complete
**Priority:** High
**Related Components:** Keycloak (identity), CloudNativePG (cnpg-system), Dragonfly (cache), Envoy Gateway (network), Tempo/Loki (monitoring)

## Executive Summary

This document provides comprehensive research and implementation guidance for integrating Obot MCP Gateway into the matherlynet-talos-cluster project. The deployment will use the custom [jrmatherly/obot-entraid](https://github.com/jrmatherly/obot-entraid) fork which extends the upstream [obot-platform/obot](https://github.com/obot-platform/obot) with Keycloak and Entra ID authentication providers.

### Key Findings

1. **Obot v0.15.x** (latest) introduces major architectural changes - gateway is now a lightweight reverse-proxy
2. **Custom Fork** (v0.2.29) provides Keycloak auth provider with PKCE S256 support and Entra ID integration
3. **Database Requirement:** PostgreSQL 17+ with pgvector extension
4. **Kubernetes Runtime:** Native MCP server deployment as pods in dedicated namespace
5. **Integration Points:** Keycloak SSO, CNPG database, Dragonfly cache (optional), Tempo tracing, Loki logging

## Upstream Obot Features (January 2026)

### Version History

| Version | Date | Key Changes |
| --------- | ------ | ------------- |
| v0.15.1 | Dec 22, 2025 | OAuth fixes, audit log improvements |
| v0.15.0 | Dec 16, 2025 | Gateway restructuring (reverse-proxy), auth overhaul |
| v0.14.0 | Dec 4, 2025 | MCP Registry API support |
| v0.13.0 | Nov 2025 | Composite MCP servers, fine-grained tool access control |

### Core Components

1. **MCP Hosting** - Docker/Kubernetes deployment of MCP servers (Node.js, Python, containers)
2. **MCP Registry** - Centralized server catalog with visibility controls and credential sharing
3. **MCP Gateway** - Single access point with logging, usage tracking, request filtering
4. **Obot Chat** - Native chat interface with RAG, project memory, scheduled automations

### Production Requirements

- **Database:** PostgreSQL 17+ with pgvector extension
- **Storage:** S3-compatible storage for production (workspace provider)
- **Encryption:** AWS KMS, GCP KMS, Azure Key Vault, or custom provider
- **Memory:** 4GB minimum, 8GB recommended for HA

## Custom Fork Analysis (jrmatherly/obot-entraid)

### Repository Details

- **Latest Version:** v0.2.29 (January 7, 2026)
- **Source:** https://github.com/jrmatherly/obot-entraid
- **Helm Chart:** ghcr.io/jrmatherly/charts/obot (OCI registry)
- **Container Image:** ghcr.io/jrmatherly/obot-entraid

### Custom Authentication Providers

The fork adds two custom authentication providers not available in upstream:

#### 1. Keycloak Authentication Provider

Located in `tools/keycloak-auth-provider/`:

```
OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL     # Keycloak base URL
OBOT_KEYCLOAK_AUTH_PROVIDER_REALM        # Realm name (e.g., matherlynet)
OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID    # OIDC client ID
OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET # OIDC client secret
OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET # base64-encoded 32-byte key
OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS # Optional group restrictions
OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES  # Optional role restrictions
```

Features:
- PKCE S256 support (v0.2.21+)
- Profile picture and name sync (v0.2.22+)
- Group-based access control
- Role-based access control

#### 2. Entra ID Authentication Provider

Located in `tools/entra-auth-provider/`:

```
OBOT_ENTRA_AUTH_PROVIDER_TENANT_ID       # Azure tenant ID
OBOT_ENTRA_AUTH_PROVIDER_CLIENT_ID       # App registration client ID
OBOT_ENTRA_AUTH_PROVIDER_CLIENT_SECRET   # App registration secret
```

Required Azure permissions:
- Delegated: `User.Read`, `ProfilePhoto.Read.All`
- Application: `GroupMember.Read.All`, `User.Read.All` (for group restrictions)

### Helm Chart Configuration

The custom chart extends upstream with:
- Custom image repository support
- MCP Kubernetes runtime configuration
- MCP server defaults (resources, security context, affinity)
- Image pull secrets for private registries
- OpenTelemetry observability integration

## Current Project Analysis

### Pattern Comparison: LiteLLM vs Obot

Both are AI-focused applications in the ai-system namespace with similar infrastructure requirements:

| Feature | LiteLLM (Current) | Obot (Proposed) |
| --------- | ------------------- | ----------------- |
| Namespace | ai-system | ai-system (new: obot for isolation) |
| Database | CNPG PostgreSQL | CNPG PostgreSQL + pgvector |
| Cache | Dragonfly (cache ns) | Optional (can use same) |
| Auth | Keycloak OIDC | Keycloak (custom provider) |
| Tracing | Tempo OTLP | Tempo OTLP |
| Gateway | Envoy HTTPRoute | Envoy HTTPRoute |
| Storage Class | local-path/proxmox-csi | local-path/proxmox-csi |
| Helm Approach | bjw-s app-template | Custom OCI chart |

### Key Differences from Old Project Deployment

The old project (`talos-k8s-cluster`) differs from current project (`matherlynet-talos-cluster`) in:

1. **Namespace Placement:** Old uses `obot` namespace, current project pattern suggests `ai-system` to co-locate AI apps
2. **Gateway:** Old uses `external` gateway in `network` namespace (matching current project pattern)
3. **Observability:** Old references VictoriaMetrics/VictoriaLogs; current uses Prometheus/Loki/Tempo
4. **Network Policies:** Old uses CiliumNetworkPolicy + NetworkPolicy; current uses conditional `network_policies_enabled`
5. **Storage:** Old references `proxmox-csi`; current project supports multiple storage classes
6. **Database Mode:** Old hardcodes CNPG; current should follow pattern of conditional database modes

### Integration Points Identified

1. **Keycloak Integration**
   - Add `obot` OIDC client to `realm-config.yaml.j2`
   - Configure redirect URIs for `obot.${cloudflare_domain}`
   - Add protocol mappers for roles and groups claims

2. **CloudNativePG Integration**
   - Create `obot-postgresql` cluster in `ai-system` namespace
   - Enable pgvector extension via ImageVolume pattern
   - Configure backup to RustFS (if `obot_backup_enabled`)

3. **Envoy Gateway Integration**
   - Create HTTPRoute in `ai-system` namespace
   - Add ReferenceGrant for cross-namespace service access
   - Route to internal service port 80 (maps to 8080)

4. **Network Policies**
   - MCP namespace isolation (dedicated `obot-mcp` namespace)
   - Egress to external services (GitHub for tools, LLM providers)
   - Ingress from Envoy Gateway
   - Database communication to CNPG cluster

5. **Observability Integration**
   - ServiceMonitor for Prometheus scraping
   - OTEL Collector for traces to Tempo (optional)
   - Grafana dashboard (optional)

## Recommended Implementation Design

### Directory Structure

```
templates/config/kubernetes/apps/ai-system/obot/
├── ks.yaml.j2                    # Flux Kustomization (dependsOn chain)
├── app/
│   ├── kustomization.yaml.j2     # Resources list
│   ├── ocirepository.yaml.j2     # OCI chart source
│   ├── helmrelease.yaml.j2       # Main deployment values
│   ├── postgresql.yaml.j2        # CNPG cluster + pgvector
│   ├── db-secret.sops.yaml.j2    # Database credentials
│   ├── httproute.yaml.j2         # Gateway API route
│   ├── referencegrant.yaml.j2    # Cross-namespace access
│   ├── networkpolicy.yaml.j2     # Cilium + K8s network policies
│   ├── servicemonitor.yaml.j2    # Prometheus scraping (conditional)
│   └── grafana-dashboard.yaml.j2 # Grafana dashboard (conditional)
├── mcp-namespace/                # Separate Kustomization for MCP namespace
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       └── namespace.yaml.j2
└── mcp-policies/                 # MCP namespace policies
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── networkpolicy.yaml.j2
        ├── resourcequota.yaml.j2
        └── limitrange.yaml.j2
```

### Configuration Variables (cluster.yaml)

```yaml
# Obot MCP Gateway Configuration
obot_enabled: true                                    # Enable Obot deployment
obot_version: "0.2.33"                               # Obot image/chart version
obot_subdomain: "obot"                               # Creates obot.${cloudflare_domain}
obot_replicas: 1                                     # Pod replicas

# Authentication (Keycloak) - Uses custom auth provider from jrmatherly/obot-entraid fork
obot_keycloak_enabled: true                          # Use Keycloak auth provider
obot_keycloak_client_id: "obot"                      # OIDC client ID
obot_keycloak_client_secret: "..."                   # SOPS-encrypted client secret
obot_keycloak_cookie_secret: "..."                   # SOPS-encrypted (openssl rand -base64 32)
obot_keycloak_allowed_groups: ""                     # Optional: comma-separated group restrictions
obot_keycloak_allowed_roles: ""                      # Optional: comma-separated role restrictions
obot_admin_emails: "admin@example.com"               # Admin email(s) - full platform access
obot_owner_emails: ""                                # Owner email(s) - highest privilege level

# Alternative: Entra ID Authentication
# obot_entra_tenant_id: "..."                        # Azure tenant ID
# obot_entra_client_id: "..."                        # SOPS-encrypted
# obot_entra_client_secret: "..."                    # SOPS-encrypted

# Database
obot_postgres_user: "obot"                           # PostgreSQL username
obot_db_password: "..."                              # SOPS-encrypted password
obot_postgres_db: "obot"                             # Database name
obot_postgresql_replicas: 1                          # CNPG instances (3 for HA)
obot_postgresql_storage_size: "10Gi"                 # PVC size

# MCP Runtime
obot_mcp_namespace: "obot-mcp"                       # MCP servers namespace

# Resources
obot_cpu_request: "500m"
obot_memory_request: "1Gi"
obot_cpu_limit: "2000m"
obot_memory_limit: "4Gi"

# Storage (workspace provider)
obot_storage_class: "proxmox-csi"                    # Or local-path
obot_storage_size: "20Gi"                            # Workspace PVC size

# Optional: S3 Workspace Provider (for multi-replica)
# obot_workspace_provider: "s3"
# obot_s3_bucket: "obot-workspace"
# obot_s3_endpoint: "http://rustfs.storage.svc.cluster.local:9000"
# obot_s3_access_key: "..."                          # SOPS-encrypted
# obot_s3_secret_key: "..."                          # SOPS-encrypted

# Encryption
obot_encryption_provider: "custom"                   # custom/aws/gcp/azure
obot_encryption_key: "..."                           # SOPS-encrypted (openssl rand -base64 32)

# Observability
obot_otel_enabled: false                             # Enable OTEL tracing to Tempo
obot_monitoring_enabled: false                       # Enable ServiceMonitor + dashboard

# LLM Gateway Integration
obot_use_ai_gateway: true                            # Route LLM requests through gateway
# Option 1: Use LiteLLM directly
obot_litellm_base_url: "http://litellm.ai-system.svc.cluster.local:4000/v1"
# Option 2: Use external gateway URL
# obot_llm_base_url: "https://litellm.${cloudflare_domain}/v1"

# Bootstrap
obot_bootstrap_token: "..."                          # SOPS-encrypted initial token
```

### Derived Variables (plugin.py)

```python
# Obot derived variables
if data.get('obot_enabled'):
    data['obot_hostname'] = f"{data.get('obot_subdomain', 'obot')}.{data['cloudflare_domain']}"

    # Keycloak integration - derive URLs for custom auth provider
    if data.get('obot_keycloak_enabled') and data.get('keycloak_enabled'):
        keycloak_realm = data.get('keycloak_realm', 'matherlynet')
        # Base URL (without /realms/...) for OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL
        data['obot_keycloak_base_url'] = f"https://{data['keycloak_hostname']}"
        # Issuer URL (with /realms/...) for reference
        data['obot_keycloak_issuer_url'] = f"https://{data['keycloak_hostname']}/realms/{keycloak_realm}"
        # Realm name for OBOT_KEYCLOAK_AUTH_PROVIDER_REALM
        data['obot_keycloak_realm'] = keycloak_realm

    # Backup enabled when RustFS + credentials configured
    if (data.get('rustfs_enabled') and
        data.get('obot_s3_access_key') and
        data.get('obot_s3_secret_key')):
        data['obot_backup_enabled'] = True

    # Monitoring enabled when both flags set
    if data.get('monitoring_enabled') and data.get('obot_monitoring_enabled'):
        data['obot_monitoring_enabled'] = True

    # Tracing enabled when both flags set
    if data.get('tracing_enabled') and data.get('obot_otel_enabled'):
        data['obot_tracing_enabled'] = True
```

### Keycloak Client Configuration

Add to `realm-config.yaml.j2`:

```yaml
#% if obot_keycloak_enabled | default(false) %#
      #| =========================================================================== #|
      #| OBOT OIDC CLIENT - MCP Gateway Authentication                               #|
      #| Auto-created when obot_keycloak_enabled + obot_keycloak_client_secret set   #|
      #| REF: docs/research/obot-mcp-gateway-integration-jan-2026.md                 #|
      #| =========================================================================== #|
      - clientId: "$(env:OBOT_CLIENT_ID)"
        name: "Obot MCP Gateway"
        description: "OIDC client for Obot MCP Gateway - enables SSO for AI agent platform"
        enabled: true
        publicClient: false
        clientAuthenticatorType: "client-secret"
        secret: "$(env:OBOT_CLIENT_SECRET)"
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        serviceAccountsEnabled: false
        implicitFlowEnabled: false
        protocol: "openid-connect"
        redirectUris:
          - "https://#{ obot_subdomain | default('obot') }#.#{ cloudflare_domain }#/oauth2/callback"
          - "https://#{ obot_subdomain | default('obot') }#.#{ cloudflare_domain }#/*"
        webOrigins:
          - "https://#{ obot_subdomain | default('obot') }#.#{ cloudflare_domain }#"
        attributes:
          pkce.code.challenge.method: "S256"
          post.logout.redirect.uris: "https://#{ obot_subdomain | default('obot') }#.#{ cloudflare_domain }#/*"
        defaultClientScopes:
          - "profile"
          - "email"
          - "offline_access"
        optionalClientScopes:
          - "address"
          - "phone"
        #| Protocol mappers for role and group claims #|
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
#% endif %#
```

### Flux Kustomization (ks.yaml.j2)

```yaml
#% if obot_enabled | default(false) %#
---
#| First: MCP Namespace (must exist before other resources) #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: obot-mcp-namespace
  namespace: flux-system
spec:
  interval: 1h
  path: ./kubernetes/apps/ai-system/obot/mcp-namespace/app
  prune: false
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
---
#| Second: Main Obot deployment #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app obot
  namespace: flux-system
spec:
  targetNamespace: ai-system
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: coredns
      namespace: kube-system
    - name: cloudnative-pg
      namespace: cnpg-system
    - name: cert-manager
      namespace: cert-manager
    - name: obot-mcp-namespace
#% if obot_keycloak_enabled | default(false) %#
    - name: keycloak
      namespace: identity
#% endif %#
#% if obot_backup_enabled | default(false) %#
    - name: rustfs
      namespace: storage
#% endif %#
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: obot
      namespace: ai-system
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/ai-system/obot/app
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
---
#| Third: MCP Namespace Policies (after Obot deployed) #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: obot-mcp-policies
  namespace: flux-system
spec:
  dependsOn:
    - name: obot
    - name: obot-mcp-namespace
  interval: 1h
  path: ./kubernetes/apps/ai-system/obot/mcp-policies/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: #{ obot_mcp_namespace | default('obot-mcp') }#
  wait: false
#% endif %#
```

### HelmRelease Values (helmrelease.yaml.j2)

```yaml
#% if obot_enabled | default(false) %#
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: obot
spec:
  chartRef:
    kind: OCIRepository
    name: obot
  interval: 1h
  timeout: 15m
  values:
    image:
      repository: ghcr.io/jrmatherly/obot-entraid
      tag: v#{ obot_version }#

    replicaCount: #{ obot_replicas | default(1) }#

#% if obot_workspace_provider | default('directory') == 's3' %#
    updateStrategy: RollingUpdate
#% else %#
    updateStrategy: Recreate
#% endif %#

    service:
      type: ClusterIP
      port: 80

    ingress:
      enabled: false

    config:
      OBOT_SERVER_HOSTNAME: "https://#{ obot_hostname }#"
      OBOT_SERVER_DSN: "postgresql://#{ obot_postgres_user | default('obot') }#:${OBOT_DB_PASSWORD}@obot-postgresql-rw.ai-system.svc.cluster.local:5432/#{ obot_postgres_db | default('obot') }#?sslmode=require"
      OBOT_SERVER_MCPRUNTIME_BACKEND: "kubernetes"
      OBOT_SERVER_ENABLE_AUTHENTICATION: true
#% if obot_admin_emails | default('') %#
      OBOT_SERVER_AUTH_ADMIN_EMAILS: "#{ obot_admin_emails }#"
#% endif %#
#% if obot_owner_emails | default('') %#
      OBOT_SERVER_AUTH_OWNER_EMAILS: "#{ obot_owner_emails }#"
#% endif %#
#% if obot_bootstrap_token | default('') %#
      OBOT_BOOTSTRAP_TOKEN: "${OBOT_BOOTSTRAP_TOKEN}"
#% endif %#

#% if obot_keycloak_enabled | default(false) %#
      #| Keycloak Auth Provider - jrmatherly/obot-entraid fork variables #|
      OBOT_SERVER_AUTH_PROVIDER: "keycloak"
      OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL: "#{ obot_keycloak_base_url }#"
      OBOT_KEYCLOAK_AUTH_PROVIDER_REALM: "#{ obot_keycloak_realm }#"
      OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID: "#{ obot_keycloak_client_id | default('obot') }#"
      OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET: "${OBOT_KEYCLOAK_CLIENT_SECRET}"
      OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET: "${OBOT_KEYCLOAK_COOKIE_SECRET}"
#% if obot_keycloak_allowed_groups | default('') %#
      OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS: "#{ obot_keycloak_allowed_groups }#"
#% endif %#
#% if obot_keycloak_allowed_roles | default('') %#
      OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES: "#{ obot_keycloak_allowed_roles }#"
#% endif %#
#% elif obot_entra_tenant_id | default('') %#
      OBOT_SERVER_AUTH_PROVIDER: "entra-id"
      OBOT_SERVER_AUTH_ENTRA_TENANT_ID: "#{ obot_entra_tenant_id }#"
      OBOT_SERVER_AUTH_ENTRA_CLIENT_ID: "${OBOT_ENTRA_CLIENT_ID}"
      OBOT_SERVER_AUTH_ENTRA_CLIENT_SECRET: "${OBOT_ENTRA_CLIENT_SECRET}"
      OBOT_SERVER_AUTH_REDIRECT_URL: "https://#{ obot_hostname }#/oauth2/callback"
#% endif %#

#% if obot_encryption_provider | default('custom') == 'custom' %#
      OBOT_SERVER_ENCRYPTION_PROVIDER: "custom"
      OBOT_SERVER_ENCRYPTION_KEY: "${OBOT_SERVER_ENCRYPTION_KEY}"
      OBOT_SERVER_ENCRYPTION_CONFIG_FILE: "/config/encryption.yaml"
#% endif %#

#% if litellm_enabled | default(false) %#
      OBOT_SERVER_LLM_BASE_URL: "http://litellm.ai-system.svc.cluster.local:4000/v1"
#% endif %#

      OBOT_SERVER_TOOL_REGISTRIES: "/obot-tools/tools"
      OBOT_SERVER_DISABLE_UPDATE_CHECK: "true"

#% if obot_tracing_enabled | default(false) %#
      OBOT_SERVER_OTEL_BASE_EXPORT_ENDPOINT: "http://tempo.monitoring.svc.cluster.local:4317"
      OBOT_SERVER_OTEL_SAMPLE_PROB: "#{ obot_otel_sample_prob | default(0.1) }#"
#% endif %#

#% if obot_workspace_provider | default('directory') == 's3' %#
      OBOT_WORKSPACE_PROVIDER_TYPE: "s3"
      WORKSPACE_PROVIDER_S3_BUCKET: "#{ obot_s3_bucket }#"
      WORKSPACE_PROVIDER_S3_BASE_ENDPOINT: "#{ obot_s3_endpoint }#"
      AWS_ACCESS_KEY_ID: "${OBOT_S3_ACCESS_KEY}"
      AWS_SECRET_ACCESS_KEY: "${OBOT_S3_SECRET_KEY}"
      AWS_REGION: "#{ obot_s3_region | default('us-east-1') }#"
      WORKSPACE_PROVIDER_S3_USE_PATH_STYLE: "true"
#% endif %#

#% if obot_workspace_provider | default('directory') == 's3' %#
    persistence:
      enabled: false
#% else %#
    persistence:
      enabled: true
      storageClass: #{ obot_storage_class | default('local-path') }#
      size: #{ obot_storage_size | default('20Gi') }#
      accessMode: ReadWriteOnce
#% endif %#

    mcpNamespace:
      name: #{ obot_mcp_namespace | default('obot-mcp') }#
      create: false

    mcpServerDefaults:
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
      podSecurityContext:
        runAsNonRoot: true
        runAsUser: 65534
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL

    resources:
      requests:
        cpu: "#{ obot_cpu_request | default('500m') }#"
        memory: "#{ obot_memory_request | default('1Gi') }#"
      limits:
        cpu: "#{ obot_cpu_limit | default('2000m') }#"
        memory: "#{ obot_memory_limit | default('4Gi') }#"

    podSecurityContext:
      fsGroup: 1000

    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      capabilities:
        drop:
          - ALL

    livenessProbe:
      httpGet:
        path: /api/healthz
        port: 8080
      initialDelaySeconds: 60
      periodSeconds: 15
      failureThreshold: 5
      timeoutSeconds: 10

    readinessProbe:
      httpGet:
        path: /api/healthz
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      failureThreshold: 3
      timeoutSeconds: 5

    serviceAccount:
      create: true
      name: obot

    rbac:
      create: true

#% if network_policies_enabled | default(false) %#
    podLabels:
      network.cilium.io/api-access: "true"
#% endif %#
#% endif %#
```

### CNPG PostgreSQL Cluster (postgresql.yaml.j2)

```yaml
#% if obot_enabled | default(false) %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: obot-postgresql
  namespace: ai-system
  labels:
    app.kubernetes.io/name: obot-postgresql
    app.kubernetes.io/part-of: obot
#% if network_policies_enabled | default(false) %#
    network.cilium.io/api-access: "true"
#% endif %#
spec:
  instances: #{ obot_postgresql_replicas | default(1) }#
  imageName: #{ cnpg_postgres_image | default('ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie') }#

  bootstrap:
    initdb:
      database: #{ obot_postgres_db | default('obot') }#
      owner: #{ obot_postgres_user | default('obot') }#
      secret:
        name: obot-db-secret

  storage:
    size: #{ obot_postgresql_storage_size | default('10Gi') }#
    storageClass: #{ cnpg_storage_class | default(storage_class) | default('local-path') }#

  resources:
    requests:
      memory: 512Mi
      cpu: 200m
    limits:
      memory: 2Gi
      cpu: 1000m

  monitoring:
    enablePodMonitor: #{ 'true' if monitoring_enabled | default(false) else 'false' }#

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"
      maintenance_work_mem: "64MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
      work_mem: "5242kB"
#% if cnpg_pgvector_enabled | default(false) %#
    extensions:
      - name: pgvector
        image:
          reference: #{ cnpg_pgvector_image | default('ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie') }#
#% endif %#

#% if (obot_postgresql_replicas | default(1)) > 1 %#
  affinity:
    enablePodAntiAffinity: true
    podAntiAffinityType: preferred
#% endif %#

#% if obot_backup_enabled | default(false) %#
  backup:
    barmanObjectStore:
      destinationPath: "s3://obot-backups"
      endpointURL: "http://rustfs.storage.svc.cluster.local:9000"
      s3Credentials:
        accessKeyId:
          name: obot-backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: obot-backup-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
    retentionPolicy: "7d"
#% endif %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: obot-db-obot
  namespace: ai-system
spec:
  name: obot
  owner: obot
  cluster:
    name: obot-postgresql
#% if cnpg_pgvector_enabled | default(false) %#
  extensions:
    - name: vector
#% endif %#
#% endif %#
```

## Network Policies Design

### Obot Main Pod CiliumNetworkPolicy (networkpolicy.yaml.j2)

```yaml
#% if obot_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - Obot Main Application Pod                              #|
#| Zero-trust networking for Obot AI agent platform                             #|
#| REF: docs/research/obot-mcp-gateway-integration-jan-2026.md                  #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: obot
  namespace: ai-system
  labels:
    app.kubernetes.io/name: obot
    app.kubernetes.io/component: network-policy
spec:
  description: "Obot: Main application pod access controls"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: obot
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| ======================================================================= #|
    #| Gateway API ingress (Envoy Gateway)                                    #|
    #| ======================================================================= #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: network
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    #| ======================================================================= #|
    #| MCP Server callbacks (obot-mcp namespace)                              #|
    #| ======================================================================= #|
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
            - port: "8099"
              protocol: TCP
#% if obot_monitoring_enabled | default(false) %#
    #| ======================================================================= #|
    #| Prometheus scraping                                                    #|
    #| ======================================================================= #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
#% endif %#
  egress:
    #| ======================================================================= #|
    #| DNS resolution                                                         #|
    #| ======================================================================= #|
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
    #| ======================================================================= #|
    #| Kubernetes API (required for MCP runtime backend)                      #|
    #| ======================================================================= #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| ======================================================================= #|
    #| PostgreSQL (CNPG) - Obot database                                      #|
    #| ======================================================================= #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: obot-postgresql
            io.kubernetes.pod.namespace: ai-system
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| ======================================================================= #|
    #| MCP Namespace - spawn and communicate with MCP servers                 #|
    #| ======================================================================= #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
            - port: "8080"
              protocol: TCP
            - port: "8099"
              protocol: TCP
#% if obot_keycloak_enabled | default(false) %#
    #| ======================================================================= #|
    #| Keycloak (OIDC SSO)                                                    #|
    #| ======================================================================= #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
            io.kubernetes.pod.namespace: identity
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
#% endif %#
#% if litellm_enabled | default(false) %#
    #| ======================================================================= #|
    #| LiteLLM proxy (AI model gateway)                                       #|
    #| ======================================================================= #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: litellm
            io.kubernetes.pod.namespace: ai-system
      toPorts:
        - ports:
            - port: "4000"
              protocol: TCP
#% endif %#
#% if obot_tracing_enabled | default(false) %#
    #| ======================================================================= #|
    #| OpenTelemetry (Tempo) - Trace export                                   #|
    #| ======================================================================= #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: tempo
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
#% endif %#
    #| ======================================================================= #|
    #| External LLM providers (Azure OpenAI, etc)                             #|
    #| ======================================================================= #|
    - toFQDNs:
        - matchPattern: "*.openai.azure.com"
        - matchPattern: "*.models.ai.azure.com"
        - matchPattern: "*.cognitiveservices.azure.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#
```

### Obot PostgreSQL CiliumNetworkPolicy

```yaml
#% if obot_enabled | default(false) and network_policies_enabled | default(false) %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - Obot PostgreSQL Database                               #|
#| Controls ingress/egress for CNPG database pods                               #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: obot-postgres
  namespace: ai-system
  labels:
    app.kubernetes.io/name: obot-postgres
    app.kubernetes.io/component: database
spec:
  description: "Obot PostgreSQL: Database access, replication, backups"
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: obot-postgresql
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| CNPG operator health checks on port 8000 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: cloudnative-pg
            io.kubernetes.pod.namespace: cnpg-system
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    #| Obot application access on port 5432 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: obot
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| Inter-pod replication between cluster instances #|
    - fromEndpoints:
        - matchLabels:
            cnpg.io/cluster: obot-postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% if monitoring_enabled | default(false) %#
    #| Prometheus metrics scraping on port 9187 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9187"
              protocol: TCP
#% endif %#
  egress:
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    #| Kubernetes API access (required for CNPG operator) #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| Inter-pod replication #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: obot-postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% if obot_backup_enabled | default(false) %#
    #| Backup to RustFS S3 endpoint #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: rustfs
            io.kubernetes.pod.namespace: storage
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% endif %#
```

### MCP Namespace Policies (mcp-policies/app/networkpolicy.yaml.j2)

```yaml
#% if obot_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| ============================================================================= #|
#| CiliumNetworkPolicy - MCP Server Namespace Default Policy                    #|
#| Controls all MCP server pods spawned by Obot                                 #|
#| ============================================================================= #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: mcp-servers-default
  namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
spec:
  description: "MCP Servers: Default isolation policy for dynamically spawned pods"
  endpointSelector: {}
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| ======================================================================= #|
    #| Obot main pod communication                                            #|
    #| ======================================================================= #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: obot
            io.kubernetes.pod.namespace: ai-system
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
            - port: "8080"
              protocol: TCP
            - port: "8099"
              protocol: TCP
  egress:
    #| ======================================================================= #|
    #| DNS resolution                                                         #|
    #| ======================================================================= #|
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
    #| ======================================================================= #|
    #| Callback to Obot main pod                                              #|
    #| ======================================================================= #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: obot
            io.kubernetes.pod.namespace: ai-system
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
            - port: "8099"
              protocol: TCP
    #| ======================================================================= #|
    #| External services (MCP tool APIs) - restricted to HTTPS                #|
    #| ======================================================================= #|
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
#% endif %#
```

### MCP Namespace Resource Quotas (mcp-policies/app/resourcequota.yaml.j2)

```yaml
#% if obot_enabled | default(false) %#
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: mcp-servers-quota
  namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    pods: "20"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: mcp-servers-limits
  namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "256Mi"
      max:
        cpu: "1000m"
        memory: "1Gi"
#% endif %#
```

### RBAC for MCP Namespace (rbac.yaml.j2)

The Obot service account in ai-system needs permissions to manage pods in the MCP namespace:

```yaml
#% if obot_enabled | default(false) %#
---
#| ============================================================================= #|
#| Role - Obot MCP Manager                                                       #|
#| Permissions for Obot to spawn and manage MCP server pods                      #|
#| ============================================================================= #|
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: obot-mcp-manager
  namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
  labels:
    app.kubernetes.io/name: obot
    app.kubernetes.io/component: rbac
rules:
  #| Pod management for MCP servers #|
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["create", "get", "list", "watch", "delete"]
  #| Services for MCP server communication #|
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["create", "get", "list", "watch", "delete"]
  #| ConfigMaps and Secrets for MCP server configuration #|
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["create", "get", "list", "watch", "delete"]
  #| Events for monitoring MCP server status #|
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
---
#| ============================================================================= #|
#| RoleBinding - Obot MCP Manager                                                #|
#| Binds Obot service account to MCP manager role                                #|
#| ============================================================================= #|
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: obot-mcp-manager
  namespace: #{ obot_mcp_namespace | default('obot-mcp') }#
  labels:
    app.kubernetes.io/name: obot
    app.kubernetes.io/component: rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: obot-mcp-manager
subjects:
  - kind: ServiceAccount
    name: obot
    namespace: ai-system
#% endif %#
```

### Encryption Configuration (encryption-config.yaml.j2)

```yaml
#% if obot_enabled | default(false) and obot_encryption_provider | default('custom') == 'custom' %#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: obot-encryption-config
  namespace: ai-system
  labels:
    app.kubernetes.io/name: obot
    app.kubernetes.io/component: config
data:
  encryption.yaml: |
    #| Custom encryption configuration for credential storage #|
    provider: custom
    #| Key is injected via environment variable reference #|
#% endif %#
```

## Implementation Checklist

### Phase 1: Core Infrastructure

- [ ] Add `obot_enabled` and related variables to cluster.yaml schema
- [ ] Add `obot_keycloak_cookie_secret` (SOPS-encrypted) to cluster.yaml
- [ ] Add derived variables to plugin.py (`obot_keycloak_base_url`, `obot_keycloak_realm`)
- [ ] Create directory structure under `templates/config/kubernetes/apps/ai-system/obot/`
- [ ] Implement `ocirepository.yaml.j2` for chart source
- [ ] Implement `helmrelease.yaml.j2` with correct `OBOT_KEYCLOAK_AUTH_PROVIDER_*` variables
- [ ] Implement `postgresql.yaml.j2` with CNPG cluster (use `18.1-standard-trixie` image)
- [ ] Implement `db-secret.sops.yaml.j2` for database credentials
- [ ] Implement `encryption-config.yaml.j2` ConfigMap for custom encryption provider

### Phase 2: Routing & Access

- [ ] Implement `httproute.yaml.j2` for Gateway API
- [ ] Implement `referencegrant.yaml.j2` for cross-namespace access
- [ ] Update `ai-system/kustomization.yaml.j2` to include obot resources

### Phase 3: Keycloak Integration

- [ ] Add Obot client to `realm-config.yaml.j2` (PKCE S256, confidential)
- [ ] Add secrets to `keycloak-realm-secrets.yaml.j2` (client_secret, cookie_secret)
- [ ] Verify OIDC scopes: openid, profile, email

### Phase 4: MCP Namespace Setup

- [ ] Create `mcp-namespace/` Kustomization structure
- [ ] Implement namespace YAML with proper labels and PodSecurityStandard (restricted)
- [ ] Create `mcp-policies/` Kustomization structure
- [ ] Implement CiliumNetworkPolicy with `enableDefaultDeny`
- [ ] Implement ResourceQuota and LimitRange
- [ ] Implement RBAC Role and RoleBinding for cross-namespace pod management

### Phase 5: Network Policies

- [ ] Implement `networkpolicy.yaml.j2` for main Obot pod with `enableDefaultDeny`
- [ ] Implement CiliumNetworkPolicy for kube-apiserver access (MCP runtime)
- [ ] Implement MCP namespace isolation policies with external registry egress (GitHub, npm)
- [ ] Implement PostgreSQL CiliumNetworkPolicy with backup egress to RustFS

### Phase 6: Observability (Optional)

- [ ] Implement `servicemonitor.yaml.j2` for Prometheus
- [ ] Implement `grafana-dashboard.yaml.j2` ConfigMap
- [ ] Configure OTEL export to Tempo (port 4317 gRPC)

### Phase 7: Documentation & Testing

- [ ] Update CLAUDE.md with Obot configuration reference
- [ ] Update docs/CONFIGURATION.md with variable schema
- [ ] Add Obot to PROJECT_INDEX.json applications list
- [ ] Test deployment with `task configure && task reconcile`
- [ ] Verify Keycloak authentication flow with PKCE S256

## Security Considerations

1. **OIDC Token Validation:** Always validate audience claim matches client ID
2. **Encryption at Rest:** Use custom encryption provider with strong key (32 bytes)
3. **Network Isolation:** MCP namespace should be isolated with strict egress controls
4. **Secret Management:** All credentials in SOPS-encrypted secrets
5. **RBAC:** Obot service account has minimal permissions in MCP namespace only
6. **Pod Security:** Non-root user (UID 1000), read-only root filesystem where possible

## Risk Assessment

| Risk | Impact | Mitigation |
| ------ | -------- | ------------ |
| MCP server resource exhaustion | High | ResourceQuota + LimitRange in MCP namespace |
| Unauthorized access to LLM providers | High | Network policies restricting egress |
| Database compromise | High | CNPG encryption, backups to RustFS |
| Token replay attacks | Medium | PKCE S256, short token lifetimes |
| MCP server escape | Medium | Pod security context, namespace isolation |

## References

- [Obot Documentation](https://docs.obot.ai/)
- [Obot GitHub Releases](https://github.com/obot-platform/obot/releases)
- [Obot EntraID Fork](https://github.com/jrmatherly/obot-entraid)
- [Keycloak Setup Guide](https://github.com/jrmatherly/obot-entraid/blob/main/tools/keycloak-auth-provider/KEYCLOAK_SETUP.md)
- [CloudNativePG Documentation](https://cloudnative-pg.io/docs/1.28/)
- [Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/references/spec/#gateway.networking.k8s.io/v1.HTTPRoute)

## Appendix A: Environment Variables Reference

### Core Server Configuration

| Variable | Description | Required |
| ---------- | ------------- | ---------- |
| `OBOT_SERVER_HOSTNAME` | Full URL including protocol | Yes |
| `OBOT_SERVER_DSN` | PostgreSQL connection string | Yes |
| `OBOT_SERVER_MCPRUNTIME_BACKEND` | `kubernetes` or `docker` | Yes |
| `OBOT_SERVER_ENABLE_AUTHENTICATION` | Enable auth | Yes |

### Authentication (Keycloak - jrmatherly/obot-entraid fork)

| Variable | Description | Required |
| ---------- | ------------- | ---------- |
| `OBOT_SERVER_AUTH_PROVIDER` | `keycloak` | Yes |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_BASE_URL` | Keycloak base URL (without /realms/...) | Yes |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_REALM` | Keycloak realm name | Yes |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_ID` | OIDC client ID | Yes |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_CLIENT_SECRET` | OIDC client secret | Yes |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_COOKIE_SECRET` | Cookie encryption secret (32 bytes base64) | Yes |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_GROUPS` | Comma-separated group restrictions | No |
| `OBOT_KEYCLOAK_AUTH_PROVIDER_ALLOWED_ROLES` | Comma-separated role restrictions | No |

### Encryption

| Variable | Description | Required |
| ---------- | ------------- | ---------- |
| `OBOT_SERVER_ENCRYPTION_PROVIDER` | `custom`, `aws`, `gcp`, `azure` | Yes |
| `OBOT_SERVER_ENCRYPTION_KEY` | 32-byte base64 key | If custom |
| `OBOT_SERVER_ENCRYPTION_CONFIG_FILE` | Path to encryption config | If custom |

### Observability

| Variable | Description | Required |
| ---------- | ------------- | ---------- |
| `OBOT_SERVER_OTEL_BASE_EXPORT_ENDPOINT` | OTLP endpoint | No |
| `OBOT_SERVER_OTEL_SAMPLE_PROB` | Sampling rate (0.0-1.0) | No |

### S3 Workspace Provider

| Variable | Description | Required |
| ---------- | ------------- | ---------- |
| `OBOT_WORKSPACE_PROVIDER_TYPE` | `s3` | If using S3 |
| `WORKSPACE_PROVIDER_S3_BUCKET` | Bucket name | If using S3 |
| `WORKSPACE_PROVIDER_S3_BASE_ENDPOINT` | S3 endpoint | If using S3 |
| `AWS_ACCESS_KEY_ID` | S3 access key | If using S3 |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | If using S3 |
| `WORKSPACE_PROVIDER_S3_USE_PATH_STYLE` | Use path-style URLs | If MinIO/RustFS |

## Appendix B: Research Validation Summary

**Research validated:** January 9, 2026

| Item | Status | Notes |
| ------ | -------- | ------- |
| Upstream Obot v0.15.x | ✅ Verified | v0.15.1 (Dec 22, 2025) with gateway restructuring |
| jrmatherly/obot-entraid | ✅ Verified | v0.2.29 (Jan 7, 2026), 2,857 commits, MIT license |
| Keycloak PKCE S256 | ✅ Verified | Added in v0.2.21 (Dec 23, 2025) |
| Helm chart (chart/) | ✅ Verified | Version 0.2.23 (may lag app version) |
| Project pattern alignment | ✅ Verified | Follows LiteLLM/Langfuse patterns |

**All corrections have been applied inline in this document:**
- Environment variables updated to `OBOT_KEYCLOAK_AUTH_PROVIDER_*` format
- Cookie secret (`obot_keycloak_cookie_secret`) added to configuration
- Network policies include `enableDefaultDeny` pattern
- PostgreSQL image updated to `18.1-standard-trixie`
- RBAC templates added for MCP namespace management
- Encryption configuration template included

### Project Pattern References

| Component | Reference File |
| ----------- | --------------- |
| Flux Kustomization | `templates/config/kubernetes/apps/ai-system/litellm/ks.yaml.j2` |
| HelmRelease | `templates/config/kubernetes/apps/ai-system/litellm/app/helmrelease.yaml.j2` |
| CNPG PostgreSQL | `templates/config/kubernetes/apps/ai-system/litellm/app/postgresql.yaml.j2` |
| Network Policies | `templates/config/kubernetes/apps/ai-system/langfuse/app/networkpolicy.yaml.j2` |
| Keycloak Client | `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.yaml.j2` |
| Derived Variables | `templates/scripts/plugin.py` |

### Research Sources

- [GitHub: obot-platform/obot releases](https://github.com/obot-platform/obot/releases)
- [GitHub: jrmatherly/obot-entraid](https://github.com/jrmatherly/obot-entraid)
- [Keycloak Setup Guide](https://github.com/jrmatherly/obot-entraid/blob/main/tools/keycloak-auth-provider/KEYCLOAK_SETUP.md)
