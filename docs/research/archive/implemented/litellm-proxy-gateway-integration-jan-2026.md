# LiteLLM Proxy Gateway Integration Research

**Date:** January 2026
**Status:** ✅ IMPLEMENTATION COMPLETE
**Implemented:** January 2026
**Priority:** Medium
**Complexity:** High

> **Implementation Status:** This research has been fully implemented. All template files are in place and the feature is ready for activation. Set `litellm_enabled: true` in `cluster.yaml` with valid API credentials to activate. See `docs/research/archive/litellm-implementation-validation-jan-2026.md` for validation report.

## Executive Summary

This document analyzes the integration of LiteLLM Proxy Gateway into the matherlynet-talos-cluster infrastructure. LiteLLM provides a unified API gateway for 100+ LLM providers with cost tracking, caching, load balancing, and guardrails. The analysis leverages an existing implementation from an older cluster (`talos-k8s-cluster`) and validates integration points with the current matherlynet-talos-cluster architecture.

### Key Findings

| Aspect | Status | Notes |
| -------- | -------- | ------- |
| CloudNativePG Integration | ✅ Ready | CNPG already enabled with pgvector |
| Keycloak OIDC | ⚠️ Partial | SSO free for 5 users; full RBAC requires Enterprise |
| Prometheus Metrics | ✅ Ready | Native `/metrics` endpoint with rich metrics |
| OpenTelemetry Tracing | ✅ Ready | OTLP gRPC/HTTP export to Tempo supported |
| Redis Cache | ✅ Ready | Dragonfly (Redis-compatible) pattern validated |
| Network Policies | ✅ Ready | CiliumNetworkPolicy with FQDN egress pattern exists |
| Guardrails (PII/Content) | ⚠️ Optional | Presidio requires sidecar containers |
| MCP Hub | ✅ Ready | Native MCP server gateway support |
| A2A Gateway | ✅ Ready | Agent-to-agent protocol support |
| Alerting | ⚠️ Optional | Slack/Discord webhooks available |

### Recommendation

Proceed with implementation using the bjw-s app-template pattern from the older cluster, adapting it for matherlynet-talos-cluster's architecture. Use open-source SSO (5 user limit) initially; evaluate Enterprise license if RBAC requirements grow.

---

## 1. LiteLLM Overview (January 2026)

### Current Version

- **Stable Release:** v1.80.8 (as of January 2026)
- **Image:** `ghcr.io/berriai/litellm:main-v1.80.8-stable.1`
- **License:** MIT (open source) with Enterprise tier for advanced features

### Core Capabilities

1. **Unified API Gateway** - Single endpoint for 100+ LLM providers (OpenAI, Anthropic, Azure, Cohere, etc.)
2. **Cost Management** - Per-user, per-team, per-key budget tracking with alerts
3. **Load Balancing** - Router with retry policies, failover, and model fallbacks
4. **Caching** - Redis-compatible caching (supports Dragonfly)
5. **Guardrails** - Content moderation, secret detection, request validation
6. **Observability** - Prometheus metrics, OpenTelemetry tracing, Langfuse integration

### New Features in v1.80.x

| Feature | Description |
| --------- | --------- |
| Agent Hub | Unified interface for agent frameworks (LangGraph, CrewAI, AutoGen) |
| A2A Agent Gateway | Agent-to-agent communication protocol support |
| MCP Hub | Model Context Protocol server integration |
| Prompt Management | Centralized prompt versioning and management |
| Gemini 3.0 | Support for Google's latest Gemini models |

---

## 2. Existing Implementation Analysis

### Source Reference

Location: `/Users/jason/dev/IaC/talos-k8s-cluster/templates/config/kubernetes/apps/ai-system/litellm/`

### Component Architecture

```
litellm/
├── ks.yaml.j2                    # Flux Kustomization with dependencies
└── app/
    ├── kustomization.yaml.j2     # Kustomize aggregation
    ├── helmrelease.yaml.j2       # bjw-s app-template deployment
    ├── configmap.yaml.j2         # LiteLLM config.yaml (models, settings)
    ├── postgresql.yaml.j2        # CNPG PostgreSQL cluster with pgvector
    ├── dragonfly.yaml.j2         # Redis-compatible cache
    ├── networkpolicy.yaml.j2     # CiliumNetworkPolicy + NetworkPolicy
    └── secret.sops.yaml.j2       # Encrypted credentials
```

### Key Configuration Patterns

#### HelmRelease (bjw-s app-template)

```yaml
#| From older cluster implementation #|
controllers:
  main:
    containers:
      main:
        image:
          repository: ghcr.io/berriai/litellm
          tag: main-v1.80.8-stable.1
        env:
          DATABASE_URL:
            valueFrom:
              secretKeyRef:
                name: litellm-postgresql-app
                key: uri
          REDIS_HOST: litellm-dragonfly
          REDIS_PORT: "6379"
          LITELLM_MASTER_KEY:
            valueFrom:
              secretKeyRef:
                name: litellm-secrets
                key: master-key
        probes:
          liveness:
            custom: true
            spec:
              httpGet:
                path: /health/liveliness
                port: 4000
          readiness:
            custom: true
            spec:
              httpGet:
                path: /health/readiness
                port: 4000
```

#### ConfigMap (config.yaml)

The existing implementation configures:

1. **Model List** - Azure OpenAI (GPT-4.1, GPT-5, o3, o4-mini), Anthropic Claude, Cohere
2. **Credential List** - Centralized API key management with variable references
3. **LiteLLM Settings** - Redis caching, Prometheus callbacks, Langfuse
4. **Router Settings** - Retry policies (3 attempts), 60s timeout, cooldown_time

```yaml
#| Example model configuration pattern #|
model_list:
  - model_name: gpt-4.1
    litellm_params:
      model: azure/gpt-4.1
      api_base: os.environ/AZURE_API_BASE
      api_key: credential_name/azure-openai-key

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: os.environ/REDIS_HOST
    port: os.environ/REDIS_PORT
  callbacks:
    - prometheus
    - langfuse
```

#### PostgreSQL (CNPG)

```yaml
#| PostgreSQL with pgvector for embeddings #|
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: litellm-postgresql
spec:
  instances: 3
  imageCatalogRef:
    kind: ClusterImageCatalog
    major: 18
  storage:
    size: 20Gi
  postgresql:
    shared_preload_libraries:
      - pgvector
```

#### Network Policies

The implementation uses dual network policies:

1. **CiliumNetworkPolicy** - FQDN-based egress to LLM providers:
```yaml
egress:
  - toFQDNs:
      - matchPattern: "*.openai.azure.com"
      - matchPattern: "*.anthropic.com"
      - matchPattern: "api.cohere.ai"
```

1. **Standard NetworkPolicy** - Internal cluster access control

---

## 3. matherlynet-talos-cluster Integration Points

### Available Infrastructure

| Component | Status | Configuration Variable |
| ----------- | -------- | ---------------------- |
| CloudNativePG | ✅ Enabled | `cnpg_enabled: true` |
| pgvector Extension | ✅ Enabled | `cnpg_pgvector_enabled: true` |
| Keycloak OIDC | ✅ Enabled | `keycloak_enabled: true` |
| Prometheus Stack | ✅ Enabled | `monitoring_enabled: true` |
| Tempo Tracing | ✅ Enabled | `tracing_enabled: true` |
| Loki Logging | ✅ Enabled | `loki_enabled: true` |
| RustFS S3 | ✅ Enabled | `rustfs_enabled: true` |
| CiliumNetworkPolicy | ✅ Enabled | `network_policies_enabled: true` |
| Envoy Gateway | ✅ Enabled | Gateway API for ingress |

### Gap Analysis

| Requirement | Current State | Action Needed |
| ----------- | ------------- | ------------- |
| Redis/Dragonfly | Not deployed | Deploy Dragonfly in ai-system namespace |
| LiteLLM namespace | Not exists | Create `ai-system` namespace |
| CNPG Cluster | Shared operator | Create LiteLLM-specific cluster |
| HTTPRoute | Not exists | Add to internal-httproutes.yaml.j2 |
| Secret credentials | Not exists | Create SOPS-encrypted secret |

---

## 4. Authentication & Authorization

### Open Source SSO (Free for 5 Users)

LiteLLM v1.76.0+ provides free SSO for Admin UI with up to 5 users:

```yaml
#| Generic OAuth configuration for Keycloak #|
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  ui_access_mode: "all"  # or "admin_only"

environment_variables:
  GENERIC_CLIENT_ID: "litellm"
  GENERIC_CLIENT_SECRET: os.environ/LITELLM_OIDC_SECRET
  GENERIC_AUTHORIZATION_ENDPOINT: "https://auth.${cloudflare_domain}/realms/matherlynet/protocol/openid-connect/auth"
  GENERIC_TOKEN_ENDPOINT: "https://auth.${cloudflare_domain}/realms/matherlynet/protocol/openid-connect/token"
  GENERIC_USERINFO_ENDPOINT: "https://auth.${cloudflare_domain}/realms/matherlynet/protocol/openid-connect/userinfo"
```

### JWT Authentication (API Requests)

LiteLLM supports JWT-based authentication for API requests:

```yaml
#| JWT configuration with Keycloak #|
general_settings:
  enable_jwt_auth: true
  litellm_jwtauth:
    user_id_jwt_field: "sub"
    user_email_jwt_field: "email"
    team_id_jwt_field: "team_id"  # Custom claim from Keycloak
```

### Enterprise Features (License Required)

| Feature | Open Source | Enterprise |
| --------- | ------------ | ------------ |
| SSO (5 users) | ✅ | ✅ |
| SSO (unlimited) | ❌ | ✅ |
| JWT Auth | ✅ | ✅ |
| Full RBAC | ❌ | ✅ |
| Audit Logs | ❌ | ✅ |
| Secret Manager Integration | ❌ | ✅ |
| IP Access Control | ❌ | ✅ |

### Keycloak Client Configuration

Create a confidential client in Keycloak:

```yaml
#| Keycloak client for LiteLLM (realm-import.yaml.j2) #|
clients:
  - clientId: litellm
    name: LiteLLM Proxy Gateway
    enabled: true
    clientAuthenticatorType: client-secret
    standardFlowEnabled: true
    directAccessGrantsEnabled: false
    publicClient: false
    redirectUris:
      - "https://litellm.${cloudflare_domain}/*"
    webOrigins:
      - "https://litellm.${cloudflare_domain}"
    defaultClientScopes:
      - openid
      - profile
      - email
```

---

## 5. Observability Integration

### Prometheus Metrics

LiteLLM exposes comprehensive metrics at `/metrics`:

```yaml
#| Enable Prometheus callback #|
litellm_settings:
  callbacks:
    - prometheus

#| Optional: Require authentication for metrics #|
general_settings:
  require_auth_for_metrics_endpoint: false
```

**Available Metrics:**

| Category | Metrics |
| ---------- | --------- |
| Spending | Per user, API key, team, model |
| Tokens | Input, output, total consumption |
| Performance | Request latency, TTFT (streaming) |
| Health | Deployment status (0=healthy, 1=partial, 2=outage) |
| Errors | Failure counts, fallback attempts |

**ServiceMonitor Configuration:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: litellm
  namespace: ai-system
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: litellm
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

### OpenTelemetry Tracing (Tempo)

LiteLLM supports OTLP export for distributed tracing:

```yaml
#| Environment variables for OTLP export #|
env:
  OTEL_EXPORTER: "otlp_grpc"
  OTEL_ENDPOINT: "http://tempo.monitoring.svc:4317"
  OTEL_HEADERS: ""
  #| Optional: Debug mode #|
  # OTEL_DEBUG: "True"

#| Config.yaml settings #|
litellm_settings:
  callbacks:
    - otel
  #| Privacy: Disable message logging if needed #|
  # turn_off_message_logging: true
```

**Span Attributes (v1.81.0+):**
- Request/response attached to parent "Received Proxy Server Request" span
- Supports privacy controls (`mask_input`, `mask_output`)

### Langfuse Integration (Optional)

For enhanced LLM observability:

```yaml
env:
  LANGFUSE_PUBLIC_KEY: os.environ/LANGFUSE_PUBLIC_KEY
  LANGFUSE_SECRET_KEY: os.environ/LANGFUSE_SECRET_KEY
  LANGFUSE_HOST: "https://langfuse.${cloudflare_domain}"

litellm_settings:
  callbacks:
    - langfuse
```

### Grafana Dashboard

LiteLLM provides maintained Grafana dashboards:
- Repository: `github.com/BerriAI/litellm/tree/main/cookbook/litellm_proxy_server/grafana_dashboard`

Deployment via ConfigMap with `grafana_dashboard: "1"` label.

### Langfuse OTEL Integration (v3 Recommended)

For Langfuse v3, use OpenTelemetry integration instead of direct HTTP:

```yaml
#| Langfuse via OTEL - recommended for Langfuse v3 #|
env:
  LANGFUSE_PUBLIC_KEY: os.environ/LANGFUSE_PUBLIC_KEY
  LANGFUSE_SECRET_KEY: os.environ/LANGFUSE_SECRET_KEY
  #| OTEL endpoint auto-constructed based on region #|
  #| US: https://us.cloud.langfuse.com/api/public/otel #|
  #| EU: https://cloud.langfuse.com/api/public/otel #|
  #| Self-hosted: ${LANGFUSE_OTEL_HOST}/api/public/otel #|
  LANGFUSE_OTEL_HOST: "https://langfuse.${cloudflare_domain}"
```

**Benefits over direct integration:**
- Standardized OpenTelemetry protocol
- All metadata fields supported as span attributes (prefixed with `langfuse.`)
- Better tracing correlation with Tempo

### Slack/Discord Alerting

LiteLLM supports webhook-based alerting for operational monitoring:

```yaml
#| Environment variables #|
env:
  SLACK_WEBHOOK_URL: os.environ/SLACK_WEBHOOK_URL
  #| Optional: Discord, Teams #|
  # DISCORD_WEBHOOK_URL: os.environ/DISCORD_WEBHOOK_URL
  # MS_TEAMS_WEBHOOK_URL: os.environ/MS_TEAMS_WEBHOOK_URL

#| Config.yaml settings #|
general_settings:
  alerting: ["slack"]
  alerting_threshold: 300  # Slow request threshold (seconds)
  alert_types:
    - llm_exceptions
    - budget_alerts
    - spend_reports
    - hanging_llm_responses
    - failed_tracking
    - region_outage_alerts
```

**Alert Categories:**

| Category | Description |
| -------- | ----------- |
| LLM Performance | Hanging calls, slow calls, failed calls, model outages |
| Budget/Spend | Per-key/team limits, soft budget alerts, weekly/monthly reports |
| System Health | Database read/write failures, deployment status changes |

**Channel Mapping:** Route specific alert types to designated Slack channels for focused monitoring.

---

## 6. Database Integration (CNPG)

### PostgreSQL Cluster

LiteLLM requires PostgreSQL for:
- Virtual key management
- User/team data
- Spend tracking
- Request logs

```yaml
#| CNPG Cluster for LiteLLM - Aligned with Keycloak postgres-cnpg.yaml.j2 pattern #|
#% if litellm_enabled | default(false) %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: litellm-postgresql
  namespace: ai-system
  labels:
    app.kubernetes.io/name: litellm-postgresql
    app.kubernetes.io/part-of: litellm
spec:
  #| Number of PostgreSQL instances (1 for dev, 3+ for HA) #|
  instances: #{ litellm_db_instances | default(1) }#

  #| PostgreSQL image - always use full image, extensions mount via ImageVolume #|
  imageName: #{ cnpg_postgres_image | default('ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie') }#

  #| Bootstrap from initdb (fresh database) #|
  bootstrap:
    initdb:
      database: #{ litellm_db_name | default('litellm') }#
      owner: #{ litellm_db_user | default('litellm') }#
      secret:
        name: litellm-db-secret

  #| Storage configuration #|
  storage:
    size: #{ litellm_db_storage_size | default('20Gi') }#
    storageClass: #{ cnpg_storage_class | default(storage_class) | default('local-path') }#

  #| Resource limits (match Keycloak pattern) #|
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 1000m

  #| Monitoring (if prometheus-stack enabled) #|
  monitoring:
    enablePodMonitor: #{ 'true' if monitoring_enabled | default(false) else 'false' }#

  #| PostgreSQL configuration optimized for LiteLLM #|
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
      effective_cache_size: "512MB"
#% if cnpg_pgvector_enabled | default(false) %#
    #| pgvector extension via ImageVolume (K8s 1.35+, PostgreSQL 18+) #|
    extensions:
      - name: pgvector
        image:
          reference: #{ cnpg_pgvector_image | default('ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie') }#
#% endif %#

  #| Affinity rules for HA deployments (match Keycloak pattern) #|
#% if (litellm_db_instances | default(1)) > 1 %#
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
#% endif %#

  #| Priority class for critical database workload #|
  priorityClassName: #{ cnpg_priority_class | default('system-cluster-critical') }#

#% if litellm_backup_enabled | default(false) %#
  #| CNPG Backup via barmanObjectStore to LiteLLM-specific RustFS bucket #|
  backup:
    barmanObjectStore:
      destinationPath: "s3://litellm-backups"
      endpointURL: "http://rustfs.storage.svc.cluster.local:9000"
      s3Credentials:
        accessKeyId:
          name: litellm-backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: litellm-backup-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
    retentionPolicy: "7d"
#% endif %#
#% endif %#
```

### RustFS IAM Setup (for Backups)

> **IMPORTANT:** RustFS does NOT support `mc admin` commands. All user/policy operations must be performed via the **RustFS Console UI** at `https://rustfs.${cloudflare_domain}`.

#### Step 1: Create LiteLLM Storage Policy

Create in RustFS Console → **Identity** → **Policies** → **Create Policy**:

**Policy Name:** `litellm-storage`

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
        "arn:aws:s3:::litellm-backups"
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
        "arn:aws:s3:::litellm-backups/*"
      ]
    }
  ]
}
```

#### Step 2: Create AI System Group

1. Navigate to **Identity** → **Groups** → **Create Group**
2. **Name:** `ai-system`
3. **Assign Policy:** `litellm-storage`
4. Click **Save**

#### Step 3: Create LiteLLM Service Account

1. Navigate to **Identity** → **Users** → **Create User**
2. **Access Key:** `litellm-backup`
3. **Assign to Group:** `ai-system`
4. Click **Save**
5. Generate access key and **save both keys immediately**

#### Step 4: Update cluster.yaml

```yaml
litellm_s3_access_key: "litellm-backup"
litellm_s3_secret_key: "ENC[AES256_GCM,...]"  # SOPS-encrypted
```

#### IAM Architecture Summary

| Component | Value |
| --------- | ----- |
| **Bucket** | `litellm-backups` |
| **Policy** | `litellm-storage` (scoped to litellm-backups only) |
| **Group** | `ai-system` |
| **User** | `litellm-backup` |
| **Cluster.yaml vars** | `litellm_s3_access_key`, `litellm_s3_secret_key` |
| **K8s Secret** | `litellm-backup-credentials` (in ai-system namespace) |

### Connection Configuration

LiteLLM expects a PostgreSQL URI:

```yaml
env:
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: litellm-postgresql-app  # Auto-created by CNPG
        key: uri  # postgresql://user:pass@host:5432/db
```

---

## 7. Caching Strategy (Dragonfly)

### Why Dragonfly?

- 25x faster than Redis
- Drop-in Redis replacement
- Lower memory footprint
- Better for high-throughput LLM caching

### Dragonfly Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm-dragonfly
  namespace: ai-system
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: dragonfly
          image: docker.dragonflydb.io/dragonflydb/dragonfly:v1.29.0
          args:
            - "--requirepass=$(DRAGONFLY_PASSWORD)"
            - "--proactor_threads=2"
          env:
            - name: DRAGONFLY_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: litellm-dragonfly-secret
                  key: password
          ports:
            - containerPort: 6379
          securityContext:
            runAsNonRoot: true
            runAsUser: 999
            allowPrivilegeEscalation: false
```

### LiteLLM Cache Configuration

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: litellm-dragonfly
    port: 6379
    password: os.environ/REDIS_PASSWORD
    #| Optional: Namespace for multi-tenant #|
    # namespace: "litellm"
```

---

## 8. Guardrails and Security Features

### Built-in Content Filter (No Dependencies)

LiteLLM includes an on-device guardrail for detecting and filtering sensitive information:

```yaml
#| Config.yaml guardrails section #|
guardrails:
  - guardrail_name: "content-filter"
    litellm_params:
      guardrail: litellm_content_filter
      mode: "pre_call"  # or "post_call", "during_call" (streaming)
      action: "MASK"    # or "BLOCK" - rejects with HTTP 400

#| Prebuilt patterns available: #|
#| - EMAIL, US_SSN, PHONE_NUMBER, CREDIT_CARD #|
#| - AWS_ACCESS_KEY, GITHUB_TOKEN #|
#| Custom regex patterns also supported #|

#| Content categories with severity thresholds: #|
#| - Harmful content (self-harm, violence, weapons) #|
#| - Bias detection (gender, racial, religious) #|
#| - Denied advice (financial, medical, legal) #|
```

### Presidio PII Masking (Sidecar Deployment)

For advanced PII/PHI detection, deploy Microsoft Presidio as sidecar containers:

```yaml
#| Presidio sidecar containers (add to LiteLLM deployment) #|
containers:
  - name: presidio-analyzer
    image: mcr.microsoft.com/presidio-analyzer:latest
    ports:
      - containerPort: 5002
  - name: presidio-anonymizer
    image: mcr.microsoft.com/presidio-anonymizer:latest
    ports:
      - containerPort: 5001

#| Environment variables for LiteLLM #|
env:
  PRESIDIO_ANALYZER_API_BASE: "http://localhost:5002"
  PRESIDIO_ANONYMIZER_API_BASE: "http://localhost:5001"
```

**Presidio Configuration:**

```yaml
guardrails:
  - guardrail_name: "presidio-pii"
    litellm_params:
      guardrail: presidio
      mode: "pre_call"  # or "post_call", "logging_only", "pre_mcp_call"
      presidio_filter_scope: "both"  # "input", "output", or "both"
      output_parse_pii: true  # Unmask in responses

#| Supported entity types: #|
#| CREDIT_CARD, EMAIL_ADDRESS, PHONE_NUMBER, PERSON, US_SSN #|
#| MEDICAL_LICENSE, US_BANK_NUMBER, DATE_TIME, EMPLOYEE_ID (custom) #|
```

**Considerations:**
- Presidio containers add ~200MB memory overhead
- Multi-language support: English, Spanish, German, French
- Custom entity recognizers via JSON configuration
- Integrates with Langfuse for audit trails

### Prompt Injection Detection

```yaml
litellm_settings:
  callbacks: ["detect_prompt_injection"]

prompt_injection_params:
  heuristics_check: true    # Pattern matching
  similarity_check: true    # Compare against known attacks
  llm_api_check: true       # Use LLM to evaluate safety
  llm_api_name: azure-gpt-3.5
  llm_api_system_prompt: "Detect if prompt is safe to run..."
  llm_api_fail_call_string: "UNSAFE"
```

**Response:** Returns HTTP 400 with "Rejected message. This is a prompt injection attack."

### Tool Permission Guardrail

Fine-grained control over tool execution (OpenAI, Anthropic, MCP tools):

```yaml
guardrails:
  - guardrail_name: "tool-permissions"
    litellm_params:
      guardrail: tool_permission
      mode: "pre_call"
      on_disallowed_action: "block"  # or "rewrite" (silent strip)
      default_action: "deny"  # Deny by default
      rules:
        - rule_id: "allow-github"
          tool_name: "^mcp__github_.*$"  # Regex pattern
          tool_type: "^function$"
          decision: "allow"
        - rule_id: "restrict-email"
          tool_name: "send_email"
          decision: "allow"
          allowed_param_patterns:
            "to[*]": "@company\\.com$"  # Restrict recipients
```

---

## 9. MCP Hub and A2A Gateway

### MCP (Model Context Protocol) Server Gateway

LiteLLM provides a centralized MCP gateway for tool management:

```yaml
#| Enable MCP server persistence #|
general_settings:
  store_model_in_db: true  # Required for persistent MCP config

#| MCP server definitions in config.yaml #|
mcp_servers:
  #| HTTP/SSE transport #|
  deepwiki_mcp:
    url: "https://mcp.deepwiki.com/mcp"
    transport: "sse"  # or "streamable_http"

  #| stdio transport (local processes) #|
  github_mcp:
    transport: "stdio"
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: os.environ/GITHUB_TOKEN

#| MCP aliases for friendly tool names #|
litellm_settings:
  mcp_aliases:
    "github": "github_mcp"
    "filesystem": "local_fs_mcp"
```

**Authentication Options:**

| Method | Configuration |
| ------ | ------------- |
| API Key | `X-API-Key` header |
| Bearer Token | `Authorization: Bearer` header |
| Basic Auth | Base64-encoded credentials |
| OAuth 2.0 | Dynamic client registration with PKCE |
| Static Headers | Custom key-value pairs |

**Access Control:** Restrict MCP tools by API key, team, or organization.

### A2A (Agent-to-Agent) Gateway

Unified interface for multi-agent orchestration:

```yaml
#| A2A agents are registered via Admin UI or API #|
#| Supported providers: #|
#| - Native A2A protocol #|
#| - Vertex AI Agent Engine #|
#| - LangGraph #|
#| - Azure AI Foundry #|
#| - Bedrock AgentCore #|
#| - Pydantic AI #|
```

**Invocation:** Uses A2A JSON-RPC 2.0 specification with bearer token authentication.

**AI Hub Feature:** Make agents public and discoverable across organization.

---

## 10. Prompt Management

### GitOps-Based Prompt Storage

LiteLLM supports file-based prompt management without external services:

```yaml
#| .prompt file format (Jinja2 templating) #|
# prompts/customer_support.prompt
---
model: gpt-4
temperature: 0.7
max_tokens: 1000
---
System: You are a helpful {{role}} assistant.
User: {{user_message}}
```

**Configuration:**

```yaml
#| Config.yaml prompt configuration #|
model_list:
  - model_name: customer-support
    litellm_params:
      model: dotprompt/gpt-4
      prompt_id: customer_support
      prompt_directory: "./prompts"
```

**API Usage:**

```bash
curl -X POST http://litellm:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{
    "model": "customer-support",
    "prompt_variables": {
      "role": "technical support",
      "user_message": "How do I reset my password?"
    }
  }'
```

### External Prompt Providers

| Provider | Storage | Authentication |
| -------- | ------- | -------------- |
| Langfuse | Cloud/Self-hosted | API keys |
| BitBucket | Repository | OAuth/Token |
| GitLab | Repository | OAuth/Token |

**Note:** Config-loaded prompts (`prompt_type: "config"`) cannot be updated via API—modifications require config.yaml changes and proxy restart.

---

## 11. Network Policies

### CiliumNetworkPolicy for FQDN Egress

**Note:** If using Presidio sidecars, add localhost communication to network policy.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: litellm-egress
  namespace: ai-system
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: litellm
  egress:
    #| LLM Provider APIs #|
    - toFQDNs:
        - matchPattern: "*.openai.azure.com"
        - matchPattern: "*.openai.com"
        - matchPattern: "api.anthropic.com"
        - matchPattern: "api.cohere.ai"
        - matchPattern: "generativelanguage.googleapis.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP

    #| Internal services #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: litellm-postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP

    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: litellm-dragonfly
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP

    #| Observability #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: tempo
          matchExpressions:
            - key: io.kubernetes.pod.namespace
              operator: In
              values:
                - monitoring
      toPorts:
        - ports:
            - port: "4317"  # OTLP gRPC
              protocol: TCP
```

### Standard NetworkPolicy for Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: litellm-ingress
  namespace: ai-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: litellm
  policyTypes:
    - Ingress
  ingress:
    #| Envoy Gateway #|
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: network
          podSelector:
            matchLabels:
              gateway.envoyproxy.io/owning-gateway-name: envoy-internal
      ports:
        - port: 4000
          protocol: TCP

    #| Prometheus scraping #|
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - port: 4000
          protocol: TCP
```

---

## 12. Gateway API Integration

### HTTPRoute Configuration

Add to `internal-httproutes.yaml.j2`:

```yaml
#% if litellm_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: litellm
  namespace: network
  labels:
#% if oidc_sso_enabled | default(false) %#
    #| Note: LiteLLM has its own auth; may not need gateway-level OIDC #|
    # security: oidc-protected
#% endif %#
spec:
  hostnames:
    - "#{ litellm_subdomain | default('litellm') }#.${SECRET_DOMAIN}"
  parentRefs:
    - name: envoy-internal
      namespace: network
      sectionName: https
  rules:
    - backendRefs:
        - name: litellm
          namespace: ai-system
          port: 4000
      matches:
        - path:
            type: PathPrefix
            value: /
#% endif %#
```

### ReferenceGrant

```yaml
#% if litellm_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-network-to-litellm
  namespace: ai-system
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: network
  to:
    - group: ""
      kind: Service
      name: litellm
#% endif %#
```

---

## 13. Implementation Plan

### Directory Structure (Simplified - No CRD Split)

Unlike Keycloak which requires a CRD split pattern (operator → instance), LiteLLM uses the bjw-s app-template Helm chart which does not install CRDs. Therefore, a simpler single-Kustomization pattern is appropriate:

```
templates/config/kubernetes/apps/ai-system/
├── namespace.yaml.j2           # ai-system namespace with labels
└── litellm/
    ├── ks.yaml.j2              # Single Flux Kustomization (no CRD split needed)
    └── app/
        ├── kustomization.yaml.j2
        ├── helmrelease.yaml.j2   # bjw-s app-template deployment
        ├── configmap.yaml.j2     # LiteLLM config.yaml (models, settings)
        ├── postgresql.yaml.j2    # CNPG PostgreSQL cluster
        ├── dragonfly.yaml.j2     # Redis-compatible cache deployment
        ├── networkpolicy.yaml.j2 # CiliumNetworkPolicy + NetworkPolicy
        ├── servicemonitor.yaml.j2 # Prometheus ServiceMonitor
        ├── grafana-dashboard.yaml.j2 # Grafana dashboard ConfigMap
        └── secret.sops.yaml.j2   # SOPS-encrypted credentials
```

**Note:** If LiteLLM introduces operator-based deployment in the future, consider the CRD split pattern per `flux_dependency_patterns` memory.

### Flux Kustomization Dependencies

Per `flux_dependency_patterns` memory, LiteLLM requires explicit cross-namespace dependencies:

```yaml
#| ks.yaml.j2 - Flux Kustomization with cross-namespace dependencies #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app litellm
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
    #| Optional: Keycloak for SSO (if oidc_enabled) #|
#% if litellm_oidc_enabled | default(false) %#
    - name: keycloak
      namespace: identity
#% endif %#
    #| Optional: RustFS for backups (if backup_enabled) #|
#% if litellm_backup_enabled | default(false) %#
    - name: rustfs
      namespace: storage
#% endif %#
  path: ./kubernetes/apps/ai-system/litellm/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  interval: 30m
  timeout: 5m
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: litellm
      namespace: ai-system
```

### Secret Template Pattern (secret.sops.yaml.j2)

Following the Keycloak secret pattern from `style_and_conventions` memory:

```yaml
#% if litellm_enabled | default(false) %#
---
#| ============================================================================= #|
#| LITELLM MASTER KEY - Primary authentication for proxy administration         #|
#| ============================================================================= #|
apiVersion: v1
kind: Secret
metadata:
  name: litellm-secrets
  namespace: ai-system
  labels:
    app.kubernetes.io/name: litellm
    app.kubernetes.io/component: credentials
type: Opaque
stringData:
  master-key: "#{ litellm_master_key }#"
---
#| Database credentials for PostgreSQL connection #|
apiVersion: v1
kind: Secret
metadata:
  name: litellm-db-secret
  namespace: ai-system
type: Opaque
stringData:
  username: "#{ litellm_db_user | default('litellm') }#"
  password: "#{ litellm_db_password }#"
---
#| Dragonfly (Redis-compatible) credentials #|
apiVersion: v1
kind: Secret
metadata:
  name: litellm-dragonfly-secret
  namespace: ai-system
type: Opaque
stringData:
  password: "#{ litellm_dragonfly_password }#"
#% if litellm_oidc_enabled | default(false) %#
---
#| OIDC client secret for Keycloak SSO #|
apiVersion: v1
kind: Secret
metadata:
  name: litellm-oidc-secret
  namespace: ai-system
type: Opaque
stringData:
  client-secret: "#{ litellm_oidc_client_secret }#"
#% endif %#
#% if litellm_backup_enabled | default(false) %#
---
#| RustFS S3 backup credentials #|
apiVersion: v1
kind: Secret
metadata:
  name: litellm-backup-credentials
  namespace: ai-system
  labels:
    app.kubernetes.io/name: litellm
    app.kubernetes.io/component: backup-credentials
type: Opaque
stringData:
  ACCESS_KEY_ID: "#{ litellm_s3_access_key }#"
  SECRET_ACCESS_KEY: "#{ litellm_s3_secret_key }#"
#% endif %#
#% if litellm_alerting_enabled | default(false) %#
---
#| Slack/Discord webhook credentials #|
apiVersion: v1
kind: Secret
metadata:
  name: litellm-alerting-secret
  namespace: ai-system
type: Opaque
stringData:
  slack-webhook-url: "#{ litellm_slack_webhook_url }#"
#% endif %#
#% endif %#
```

### Phase 1: Core Infrastructure

1. **Create Namespace**
   - Add `ai-system` namespace template
   - Configure namespace labels for network policies

2. **Deploy Dragonfly**
   - Create dragonfly.yaml.j2 template
   - Configure SOPS-encrypted password

3. **Deploy CNPG Cluster**
   - Create postgresql.yaml.j2 template
   - Enable pgvector extension
   - Configure backup to RustFS (optional)

### Phase 2: LiteLLM Deployment

1. **Create HelmRelease**
   - Adapt bjw-s app-template from older cluster
   - Configure environment variables
   - Set up health probes

2. **Create ConfigMap**
   - Define model_list for target LLM providers
   - Configure litellm_settings
   - Set up router_settings

3. **Create Secrets**
   - SOPS-encrypted credentials for:
     - LITELLM_MASTER_KEY
     - Azure OpenAI API keys
     - Anthropic API key
     - Other provider credentials

### Phase 3: Networking

1. **Create HTTPRoute**
   - Add to internal-httproutes.yaml.j2
   - Configure ReferenceGrant

2. **Create Network Policies**
   - CiliumNetworkPolicy for FQDN egress
   - NetworkPolicy for internal ingress

### Phase 4: Observability

1. **Create ServiceMonitor**
   - Configure Prometheus scraping
   - Deploy Grafana dashboards

2. **Configure OpenTelemetry**
    - Enable OTLP export to Tempo
    - Configure span attributes

### Phase 5: Authentication

1. **Create Keycloak Client**
    - Add to realm-import.yaml.j2
    - Configure redirect URIs

2. **Configure SSO**
    - Set GENERIC_* environment variables
    - Test OAuth flow

---

## 14. Configuration Variables

### Required Variables (cluster.yaml)

```yaml
#| LiteLLM Proxy Gateway #|
litellm_enabled: true
litellm_subdomain: litellm  # Creates litellm.${cloudflare_domain}

#| Azure OpenAI US East (Primary Region) #|
azure_openai_us_east_api_key: "<encrypted>"
azure_openai_us_east_api_base: "https://<instance>.openai.azure.com"
azure_openai_us_east_api_version: "2024-10-21"

#| Azure OpenAI US East2 (Secondary Region - GPT-5 series) #|
azure_openai_us_east2_api_key: "<encrypted>"
azure_openai_us_east2_api_base: "https://<instance>.openai.azure.com"
azure_openai_us_east2_api_version: "2025-01-01-preview"

#| Azure Anthropic (Claude models via Azure) #|
azure_anthropic_api_key: "<encrypted>"
azure_anthropic_api_base: "https://<instance>.services.ai.azure.com"

#| Core Credentials (SOPS-encrypted) #|
litellm_master_key: "<encrypted>"
litellm_db_password: "<encrypted>"
litellm_dragonfly_password: "<encrypted>"
```

**Note:** The old cluster uses multi-region Azure OpenAI deployments for model diversity and failover. Each region has its own API key/base/version.

### Optional Variables

```yaml
#| LiteLLM Configuration #|
litellm_image_tag: "main-v1.80.8-stable.1"
litellm_master_key: "<encrypted>"  # Auto-generated if not set
litellm_db_storage_size: "20Gi"
litellm_backup_enabled: false  # Requires rustfs_enabled

#| Observability #|
litellm_tracing_enabled: true  # Requires tracing_enabled
litellm_monitoring_enabled: true  # Requires monitoring_enabled

#| SSO Configuration #|
litellm_oidc_enabled: true  # Requires keycloak_enabled
litellm_oidc_client_secret: "<encrypted>"  # Generated in Keycloak

#| Dragonfly Cache #|
litellm_dragonfly_password: "<encrypted>"

#| Alerting (Optional) #|
litellm_alerting_enabled: false
litellm_slack_webhook_url: "<encrypted>"  # SOPS-encrypted
litellm_alerting_threshold: 300  # Slow request threshold (seconds)

#| Guardrails (Optional) #|
litellm_guardrails_enabled: false  # Enable built-in content filter
litellm_presidio_enabled: false  # Enable Presidio PII masking (adds sidecars)
litellm_prompt_injection_check: false  # Enable prompt injection detection

#| MCP Hub (Optional) #|
litellm_mcp_enabled: false  # Enable MCP server gateway
litellm_mcp_store_in_db: false  # Persist MCP config in PostgreSQL

#| Langfuse Integration (Optional - alternative to self-hosted) #|
litellm_langfuse_enabled: false
litellm_langfuse_public_key: "<encrypted>"
litellm_langfuse_secret_key: "<encrypted>"
litellm_langfuse_host: ""  # Leave empty for cloud, or set self-hosted URL

#| Backup Credentials (SOPS-encrypted, requires rustfs_enabled + litellm_backup_enabled) #|
litellm_s3_access_key: "<encrypted>"  # Create via RustFS Console
litellm_s3_secret_key: "<encrypted>"

#| Azure Cohere (Optional - Rerank and Embedding) #|
azure_cohere_rerank_api_key: "<encrypted>"
azure_cohere_rerank_api_base: "https://<instance>.services.ai.azure.com"
azure_cohere_embed_api_key: "<encrypted>"
azure_cohere_embed_api_base: "https://<instance>.services.ai.azure.com"

#| Direct Provider Access (Optional - if not using Azure) #|
openai_api_key: "<encrypted>"         # For direct OpenAI access
anthropic_api_key: "<encrypted>"      # For direct Anthropic access
cohere_api_key: "<encrypted>"         # For direct Cohere access
google_api_key: "<encrypted>"         # For Gemini models
```

### Derived Variables (plugin.py)

```python
#| LiteLLM derived variables #|
if litellm_enabled:
    litellm_hostname = f"{litellm_subdomain}.{cloudflare_domain}"
    litellm_tracing_enabled = tracing_enabled and litellm_tracing_enabled
    litellm_monitoring_enabled = monitoring_enabled and litellm_monitoring_enabled
    litellm_oidc_enabled = keycloak_enabled and litellm_oidc_enabled
    litellm_backup_enabled = rustfs_enabled and litellm_backup_enabled
    litellm_alerting_enabled = litellm_alerting_enabled and litellm_slack_webhook_url
    litellm_presidio_enabled = litellm_guardrails_enabled and litellm_presidio_enabled
```

---

## 15. Migration from Older Cluster

### Files to Adapt

| Source File | Target Location | Changes Needed |
| ------------- | ----------------- | ---------------- |
| `ks.yaml.j2` | Same structure | Update dependencies |
| `helmrelease.yaml.j2` | Same structure | Update image, env vars |
| `configmap.yaml.j2` | Same structure | Review model_list |
| `postgresql.yaml.j2` | Same structure | Use ClusterImageCatalog |
| `dragonfly.yaml.j2` | Same structure | Minor updates |
| `networkpolicy.yaml.j2` | Same structure | Add Tempo egress |
| `secret.sops.yaml.j2` | Same structure | Re-encrypt with new key |

### Breaking Changes to Address

1. **CNPG ImageVolume** - Older cluster uses different pgvector mounting; use ImageVolume pattern
2. **Monitoring Integration** - Ensure ServiceMonitor uses correct labels
3. **Keycloak Client** - Add to realm-import.yaml.j2 instead of separate resource
4. **RustFS Service Name** - Use `rustfs.storage.svc.cluster.local` (not `rustfs-svc`)

### Project Convention Alignment

Based on validation against `flux_dependency_patterns` and `style_and_conventions` memories:

| Pattern | Source | Required Adaptation |
| ------- | ------ | ------------------- |
| Template delimiters | `style_and_conventions` | Use `#% %#`, `#{ }#`, `#\| #\|` |
| CRD split pattern | `flux_dependency_patterns` | May need operator → instance split if CRDs involved |
| Cross-namespace deps | `flux_dependency_patterns` | Specify namespace in `dependsOn` |
| StorageClass explicit | `flux_dependency_patterns` | Always specify `storageClassName` |
| HTTPRoute pattern | `flux_dependency_patterns` | Use centralized internal-httproutes.yaml.j2 |
| CNPG pattern | `postgres-cnpg.yaml.j2` | Follow Keycloak's CNPG pattern exactly |

### Model Configuration from Old Cluster (configmap.yaml.j2)

The old project's ConfigMap contains extensive model configurations that must be carried over. Below is the complete analysis:

#### Model Inventory Summary

| Provider | Region/Endpoint | Models | Modes |
| -------- | --------------- | ------ | ----- |
| Azure OpenAI | US East | 6 | Chat, Embedding |
| Azure OpenAI | US East2 | 14 | Chat, Reasoning, Image, Realtime, Audio, Embedding, Speech |
| Azure Anthropic | US East2 | 4 | Chat (Claude) |
| Azure Cohere | US East2 | 2 | Rerank, Embedding |
| **Total** | | **26 models** | |

#### Azure OpenAI US East Models (Conditional: `azure_openai_us_east_api_key`)

| Model Name | Azure Model | Max Tokens | RPM | TPM | Access Groups |
| ---------- | ----------- | ---------- | --- | --- | ------------- |
| gpt-4.1 | azure/gpt-4.1 | 13,107 | 250 | 250K | premium, restricted, aangpt, aanai |
| gpt-4.1-nano | azure/gpt-4.1-nano | 13,107 | 450 | 450K | default, aangpt, aanai |
| gpt-4o-mini | azure/gpt-4o-mini | 4,096 | 5,000 | 500K | default, aangpt, aanai |
| o3 | azure/o3 | 40,000 | 250 | 250K | premium, restricted (reasoning) |
| o4-mini | azure/o4-mini | 40,000 | 2,000 | 400K | premium, restricted (reasoning) |
| text-embedding-3-small | azure/text-embedding-3-small | - | 3,000 | 500K | default, developer |
| text-embedding-ada-002 | azure/text-embedding-ada-002 | - | 3,000 | 500K | default, developer |

**Credential Reference:** `azure_credential_us_east`

#### Azure OpenAI US East2 Models (Conditional: `azure_openai_us_east2_api_key`)

| Model Name | Azure Model | Max Tokens | RPM | TPM | Special Features |
| ---------- | ----------- | ---------- | --- | --- | ---------------- |
| gpt-5 | azure/gpt5_series/gpt-5 | 16,384 | 1,750 | 1.75M | Premium |
| gpt-5-chat | azure/gpt5_series/gpt-5-chat | 16,384 | 1,750 | 1.75M | Reasoning (thinking) |
| gpt-5-mini | azure/gpt5_series/gpt-5-mini | 16,384 | 2,500 | 2.5M | Default tier |
| gpt-5-nano | azure/gpt5_series/gpt-5-nano | 16,384 | 15,000 | 15M | High throughput |
| gpt-5.1 | azure/gpt5_series/gpt-5.1 | 16,384 | 20,000 | 2M | Reasoning support |
| gpt-5.1-chat | azure/gpt5_series/gpt-5.1-chat | 16,384 | 20,000 | 2M | Chat + Reasoning |
| gpt-5.1-codex | azure/gpt-5.1-codex | 16,384 | 2,000 | 2M | Code generation (preview) |
| gpt-5.1-codex-mini | azure/gpt-5.1-codex-mini | 16,384 | 2,500 | 2.5M | Code generation (preview) |
| gpt-5.2 | azure/gpt5_series/gpt-5.2 | 16,384 | 22,500 | 2.25M | Latest reasoning |
| gpt-audio | azure/gpt-audio | - | 250 | 250K | Audio I/O, health check disabled |
| gpt-audio-mini | azure/gpt-audio-mini | - | 200 | 100K | Audio I/O, health check disabled |
| gpt-image-1 | azure/gpt-image-1 | - | 60 | - | Image generation |
| gpt-realtime | azure/gpt-realtime | - | 200 | 100K | Realtime, health check disabled |
| gpt-realtime-mini | azure/gpt-realtime-mini | - | 200 | 100K | Realtime, health check disabled |
| text-embedding-3-large | azure/text-embedding-3-large | - | 18,000 | 3M | High-quality embedding |
| azure-speech | azure/speech/azure-tts | - | - | - | TTS, health check disabled |

**Credential Reference:** `azure_credential_us_east2`

**Note:** Audio and Realtime models have `disable_background_health_check: true` because LiteLLM's health check doesn't support these modalities.

#### Azure Anthropic Models (Conditional: `azure_anthropic_api_key`)

| Model Name | Anthropic Model | Max Tokens | RPM | TPM | Notes |
| ---------- | --------------- | ---------- | --- | --- | ----- |
| claude-opus-4-5 | anthropic/claude-opus-4-5 | 16,384 | 1,500 | 1.5M | Latest Opus, reasoning |
| claude-sonnet-4-5 | anthropic/claude-sonnet-4-5 | 16,384 | 2,750 | 2.75M | Latest Sonnet, reasoning |
| claude-opus-4-1 | anthropic/claude-opus-4-1 | 16,384 | 1,250 | 1.25M | Reasoning support |
| claude-haiku-4-5 | anthropic/claude-haiku-4-5 | 16,384 | 2,250 | 2.25M | Fast, reasoning |

**Credential Reference:** `azure_credential_anthropic_us_east2`

#### Azure Cohere Models

| Model Name | API Base | Mode | Notes |
| ---------- | -------- | ---- | ----- |
| cohere-rerank-v3.5 | AZURE_COHERE_RERANK_API_BASE | Rerank | Conditional: `azure_cohere_rerank_api_key` |
| cohere-embed-v-4-0 | AZURE_COHERE_EMBED_API_BASE | Embedding | Health check disabled (404 on check) |

#### Credential List Pattern

```yaml
#| Credential list pattern from old cluster #|
credential_list:
  - credential_name: azure_credential_us_east
    credential_values:
      api_key: "os.environ/AZURE_API_KEY"
      api_base: "os.environ/AZURE_API_BASE"
      api_version: "os.environ/AZURE_API_VERSION"
    credential_info:
      description: "Azure OpenAI US East credentials"

  - credential_name: azure_credential_us_east2
    credential_values:
      api_key: "os.environ/AZURE_API_KEY_EAST2"
      api_base: "os.environ/AZURE_API_BASE_EAST2"
      api_version: "os.environ/AZURE_API_VERSION_EAST2"

  - credential_name: azure_credential_anthropic_us_east2
    credential_values:
      api_key: "os.environ/AZURE_ANTHROPIC_API_KEY"
      api_base: "os.environ/AZURE_ANTHROPIC_API_BASE"
```

#### Access Groups Strategy

The old cluster uses access groups for fine-grained model access control:

| Access Group | Description | Example Models |
| ------------ | ----------- | -------------- |
| `default-models` | Available to all users | gpt-4.1-nano, gpt-5-mini, gpt-5-nano |
| `premium-models` | Higher-tier models | gpt-5, claude-opus-4-5, o3 |
| `restricted-models` | Limited access | gpt-5, o3, o4-mini |
| `developer-models` | Embedding/tools | text-embedding-3-small |
| `aangpt-models` | Organization-specific | All models |
| `aanai-models` | Organization-specific | All models |

#### Key LiteLLM Settings from Old Cluster

```yaml
litellm_settings:
  #| Privacy settings #|
  turn_off_message_logging: true
  redact_user_api_key_info: true
  redact_messages_in_exceptions: true

  #| Performance #|
  cache: true
  cache_params:
    type: redis
    ttl: 600
    mode: default_on
    supported_call_types: ["acompletion", "atext_completion", "aembedding", "atranscription"]

  #| Callbacks #|
  success_callback: ["prometheus", "langfuse"]  # if langfuse enabled
  failure_callback: ["prometheus", "langfuse"]
  callbacks: ["prometheus"]
  service_callbacks: ["prometheus_system"]

  #| Limits #|
  request_timeout: 30
  tpm_limit: 3500000
  rpm_limit: 35000
  max_file_size_mb: 25
  max_budget: 1000
  budget_duration: 30d

  #| Telemetry disabled #|
  telemetry: false
  json_logs: true
```

#### Router Settings from Old Cluster

```yaml
router_settings:
  routing_strategy: simple-shuffle  # Recommended for performance
  enable_pre_call_checks: true
  enable_tag_filtering: true
  timeout: 120
  stream_timeout: 300

  #| Failover policy #|
  allowed_fails: 3
  cooldown_time: 30
  disable_cooldowns: true  # Currently disabled

  #| Retry policy #|
  retry_policy:
    AuthenticationErrorRetries: 1
    TimeoutErrorRetries: 2
    RateLimitErrorRetries: 3
    ContentPolicyViolationErrorRetries: 2
    InternalServerErrorRetries: 3
```

#### General Settings from Old Cluster

```yaml
general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"
  database_connection_pool_limit: 20
  database_connection_timeout: 60

  #| DB behavior #|
  allow_requests_on_db_unavailable: true
  disable_spend_logs: false
  store_model_in_db: true
  store_prompts_in_spend_logs: true
  disable_error_logs: true

  #| Batching #|
  proxy_batch_write_at: 60
  proxy_budget_rescheduler_min_time: 300
  proxy_budget_rescheduler_max_time: 3600

  #| Health checks disabled due to Prisma timeout issues #|
  background_health_checks: false
  health_check_interval: 300

  #| User identification #|
  user_header_name: X-OpenWebUI-User-Email
```

#### Required Environment Variables for Migration

Based on the ConfigMap analysis, these environment variables must be configured in `secret.sops.yaml.j2`:

```yaml
#| Azure OpenAI US East #|
AZURE_API_KEY: "<encrypted>"
AZURE_API_BASE: "https://<instance>.openai.azure.com"
AZURE_API_VERSION: "2024-10-21"

#| Azure OpenAI US East2 #|
AZURE_API_KEY_EAST2: "<encrypted>"
AZURE_API_BASE_EAST2: "https://<instance>.openai.azure.com"
AZURE_API_VERSION_EAST2: "2025-01-01-preview"

#| Azure Anthropic #|
AZURE_ANTHROPIC_API_KEY: "<encrypted>"
AZURE_ANTHROPIC_API_BASE: "https://<instance>.services.ai.azure.com"

#| Azure Cohere (Optional) #|
AZURE_COHERE_RERANK_API_KEY: "<encrypted>"
AZURE_COHERE_RERANK_API_BASE: "https://<instance>.services.ai.azure.com"
AZURE_COHERE_EMBED_API_KEY: "<encrypted>"
AZURE_COHERE_EMBED_API_BASE: "https://<instance>.services.ai.azure.com"

#| Redis/Dragonfly #|
REDIS_HOST: "litellm-dragonfly"
REDIS_PORT: "6379"
REDIS_PASSWORD: "<encrypted>"
REDIS_NAMESPACE: "litellm"

#| Core #|
DATABASE_URL: "postgresql://litellm:xxx@litellm-postgresql:5432/litellm"
LITELLM_MASTER_KEY: "<encrypted>"
STORE_MODEL_IN_DB: "true"

#| Langfuse (Optional) #|
LANGFUSE_HOST: "https://langfuse.${cloudflare_domain}"
LANGFUSE_PUBLIC_KEY: "<encrypted>"
LANGFUSE_SECRET_KEY: "<encrypted>"
```

#### Migration Checklist for ConfigMap

- [ ] Copy model_list structure with conditional blocks (`#% if provider_api_key %#`)
- [ ] Update credential_list to use `litellm_credential_name` pattern
- [ ] Verify all access_groups match organizational requirements
- [ ] Update `disable_background_health_check: true` for audio/realtime models
- [ ] Configure cache_params with Dragonfly connection
- [ ] Set `turn_off_message_logging: true` for privacy
- [ ] Enable `store_model_in_db: true` for runtime management
- [ ] Configure retry_policy and allowed_fails_policy
- [ ] Set appropriate tpm_limit and rpm_limit based on quotas
- [ ] Add user_header_name if using Open WebUI integration

---

## 16. Security Considerations

### Credential Management

| Secret | Storage | Rotation Strategy |
| -------- | --------- | ------------------- |
| LITELLM_MASTER_KEY | SOPS | Manual (admin access) |
| Database credentials | CNPG auto-generated | Automatic via CNPG |
| Dragonfly password | SOPS | Manual |
| LLM API keys | SOPS | Provider-dependent |
| OIDC client secret | Keycloak + SOPS | Via Keycloak |

### Network Security

- All external egress via HTTPS (port 443)
- Internal traffic on non-standard ports (4000, 5432, 6379)
- FQDN-based egress control prevents data exfiltration
- Gateway-level TLS termination

### Data Privacy

- `turn_off_message_logging: true` for OTLP if needed
- `mask_input`/`mask_output` for sensitive requests
- GDPR compliance via Enterprise logging controls

---

## 17. Cost Considerations

### Resource Requirements

| Component | CPU Request | Memory Request | Storage |
| ----------- | ------------- | ---------------- | --------- |
| LiteLLM | 200m | 512Mi | - |
| PostgreSQL (x3) | 100m | 256Mi | 20Gi each |
| Dragonfly | 100m | 256Mi | 1Gi |
| **Total** | 700m | 1.5Gi | 61Gi |

### LLM Provider Costs

LiteLLM tracks costs automatically per user/team/key. Consider:
- Setting budget limits per API key
- Enabling cost alerts
- Using Enterprise for detailed reporting

---

## 18. References

### Documentation

- [LiteLLM Official Docs](https://docs.litellm.ai/)
- [LiteLLM GitHub Repository](https://github.com/BerriAI/litellm)
- [LiteLLM Prometheus Metrics](https://docs.litellm.ai/docs/proxy/prometheus)
- [LiteLLM OpenTelemetry](https://docs.litellm.ai/docs/observability/opentelemetry_integration)
- [LiteLLM Enterprise Features](https://docs.litellm.ai/docs/proxy/enterprise)
- [LiteLLM Langfuse Integration](https://docs.litellm.ai/docs/observability/langfuse_integration)
- [LiteLLM Langfuse OTEL Integration](https://docs.litellm.ai/docs/observability/langfuse_otel_integration)
- [LiteLLM Content Filter Guardrails](https://docs.litellm.ai/docs/proxy/guardrails/litellm_content_filter)
- [LiteLLM Presidio PII Masking](https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2)
- [LiteLLM Prompt Injection Detection](https://docs.litellm.ai/docs/proxy/guardrails/prompt_injection)
- [LiteLLM Tool Permissions](https://docs.litellm.ai/docs/proxy/guardrails/tool_permission)
- [LiteLLM Alerting](https://docs.litellm.ai/docs/proxy/alerting)
- [LiteLLM Prompt Management](https://docs.litellm.ai/docs/proxy/prompt_management)
- [LiteLLM MCP Integration](https://docs.litellm.ai/docs/mcp)
- [LiteLLM A2A Gateway](https://docs.litellm.ai/docs/a2a)

### Related Project Documentation

- `docs/guides/cnpg-implementation.md` - CloudNativePG setup
- `docs/guides/keycloak-implementation.md` - Keycloak OIDC configuration
- `docs/research/grafana-sso-authentication-integration-jan-2026.md` - SSO patterns

### Older Cluster Implementation

- `/Users/jason/dev/IaC/talos-k8s-cluster/templates/config/kubernetes/apps/ai-system/litellm/`

---

## 19. Validation and Reflection Notes

### Research Completeness Assessment

| Aspect | Status | Notes |
| ------ | ------ | ----- |
| LiteLLM v1.80.x features | ✅ Complete | Agent Hub, A2A, MCP Hub documented |
| CNPG integration | ✅ Complete | Follows Keycloak's postgres-cnpg.yaml.j2 pattern |
| Keycloak OIDC | ✅ Complete | SSO and JWT auth patterns documented |
| Prometheus metrics | ✅ Complete | ServiceMonitor and dashboard patterns |
| OpenTelemetry tracing | ✅ Complete | OTLP gRPC to Tempo documented |
| Network policies | ✅ Complete | CiliumNetworkPolicy FQDN egress pattern |
| Gateway API | ✅ Complete | HTTPRoute in internal-httproutes.yaml.j2 |
| Older cluster analysis | ✅ Complete | All 7 template files reviewed |
| Guardrails (Content Filter) | ✅ Complete | Built-in regex/keyword filtering documented |
| Guardrails (Presidio PII) | ✅ Complete | Sidecar deployment pattern documented |
| Prompt Injection Detection | ✅ Complete | Heuristics + LLM-based detection documented |
| Tool Permissions | ✅ Complete | Fine-grained MCP/function tool control |
| MCP Hub Integration | ✅ Complete | HTTP/SSE/stdio transport patterns |
| A2A Gateway | ✅ Complete | Multi-agent orchestration patterns |
| Prompt Management | ✅ Complete | GitOps-based .prompt files documented |
| Alerting (Slack/Discord) | ✅ Complete | Webhook-based alerting configuration |
| Langfuse OTEL Integration | ✅ Complete | v3 recommended OTEL approach |

### Identified Improvement Opportunities

1. **Valkey Alternative**: Consider Valkey (Redis fork by Linux Foundation) as an alternative to Dragonfly for cache layer. Valkey is 100% Redis compatible and actively maintained.

2. **Multi-Provider Failover**: Document specific failover configuration for Azure OpenAI → OpenAI → Anthropic chains with appropriate retry policies.

3. **Rate Limiting**: Consider adding Envoy Gateway rate limiting (`BackendTrafficPolicy`) for API abuse protection before LiteLLM's internal rate limiting.

4. **Secrets Rotation**: Document integration with External Secrets Operator for automated API key rotation from cloud secret managers.

5. **High Availability**: Document LiteLLM horizontal scaling patterns with Redis-based session state for >1 replica deployments.

6. **Presidio Resource Sizing**: Presidio sidecars add ~200MB memory overhead; consider optional deployment flag for resource-constrained environments.

7. **Prompt Injection Model**: The LLM-based prompt injection check consumes tokens; consider cost implications and threshold tuning.

8. **MCP Server Catalog**: Pre-configure common MCP servers (GitHub, filesystem, database) as optional templates.

9. **CRD Split Pattern**: Consider whether LiteLLM requires a CRD split pattern similar to Keycloak (operator → instance). The bjw-s app-template is a standard Helm chart without CRDs, so this is likely NOT required.

10. **Resource Limits Missing**: Add explicit resource limits to CNPG cluster configuration to match Keycloak pattern (requests + limits defined).

11. **Affinity Rules**: Add conditional affinity rules for HA PostgreSQL deployments (instances > 1) per Keycloak pattern.

12. **Multi-Region Azure Credentials**: The old cluster uses 2 Azure OpenAI regions (US East, US East2). Consider documenting fallback strategy between regions for resilience.

13. **Model ID Uniqueness**: Each model in the old cluster has a unique numeric `id` field (e.g., `id: "41"` for gpt-4.1). Ensure IDs don't conflict when adding new models.

14. **Health Check Exceptions**: 5 models require `disable_background_health_check: true` (audio, realtime, speech, Cohere embed). Document this pattern for future model additions.

15. **Access Group Consolidation**: The old cluster has 6 access groups. Consider whether `aangpt-models` and `aanai-models` are organization-specific and need renaming for the new cluster.

16. **Cache Control Injection**: Most chat models have `cache_control_injection_points` configured for system messages. This enables prompt caching optimization - ensure this pattern is preserved.

17. **Reasoning Model Configuration**: Models with reasoning/thinking capabilities (o3, o4-mini, gpt-5-chat, claude-*) have specific `thinking` and `merge_reasoning_content_in_choices` settings that must be preserved.

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| SSO 5-user limit | Low | Medium | Monitor user count; evaluate Enterprise |
| LLM provider outage | Medium | High | Configure multi-provider failover |
| Database corruption | Low | High | Enable CNPG backups to RustFS |
| Cache miss storms | Medium | Medium | Configure appropriate TTLs and warm-up |
| Secret exposure | Low | Critical | SOPS encryption, network policies |
| Prompt injection attack | Medium | High | Enable detection callbacks + guardrails |
| PII data leakage | Medium | Critical | Enable Presidio masking for sensitive data |
| Tool abuse via MCP | Low | Medium | Configure tool permission guardrails |
| Alerting fatigue | Medium | Low | Tune thresholds, channel mapping |
| Azure quota exhaustion | Medium | Medium | Monitor TPM/RPM limits, configure fallbacks |
| Prisma timeout issues | Medium | Medium | Keep `background_health_checks: false` per old cluster |
| Model ID collision | Low | Low | Maintain ID registry, use sequential numbering |

### Pre-Implementation Checklist

- [ ] Verify CNPG operator is healthy: `kubectl get pods -n cnpg-system`
- [ ] Verify Keycloak is operational: `kubectl get keycloak -n identity`
- [ ] Verify RustFS S3 accessible: `kubectl get pods -n storage -l app.kubernetes.io/name=rustfs`
- [ ] Verify Tempo OTLP endpoint: `kubectl get svc -n monitoring tempo`
- [ ] Create RustFS bucket for LiteLLM backups via Console UI
- [ ] Generate LiteLLM OIDC client secret in Keycloak
- [ ] Obtain LLM provider API keys (Azure OpenAI, Anthropic, etc.)
- [ ] Review older cluster ConfigMap for model_list adaptation

### Post-Implementation Validation

- [ ] Verify Flux Kustomization: `flux get ks litellm -n flux-system`
- [ ] Verify HelmRelease: `flux get hr litellm -n ai-system`
- [ ] Verify CNPG cluster: `kubectl cnpg status litellm-postgresql -n ai-system`
- [ ] Verify Dragonfly: `kubectl get pods -n ai-system -l app.kubernetes.io/name=litellm-dragonfly`
- [ ] Test LiteLLM health: `curl https://litellm.${domain}/health/liveliness`
- [ ] Test SSO login via Keycloak
- [ ] Verify Prometheus metrics: `curl https://litellm.${domain}/metrics`
- [ ] Check Grafana dashboard visibility
- [ ] Verify traces in Tempo via Grafana Explore
- [ ] Test guardrails (if enabled): Send test request with PII data
- [ ] Test prompt injection detection (if enabled): Send test injection payload
- [ ] Verify Slack alerts (if enabled): Trigger test alert
- [ ] Test MCP tools (if enabled): List available tools via API
- [ ] Test prompt templates (if configured): Call prompt_id endpoint

### Reflection Summary (January 2026)

#### First Reflection Cycle - Architecture & Conventions

**Validation Performed:**
1. ✅ Task adherence verified against original research objectives
2. ✅ Information completeness assessed - 17 feature areas documented
3. ✅ Cross-referenced with project conventions:
   - `style_and_conventions` memory - Template delimiters, secret patterns
   - `flux_dependency_patterns` memory - CRD split, cross-namespace deps, storageClass
   - `task_completion_checklist` memory - Validation commands documented
4. ✅ Compared against Keycloak implementation patterns (postgres-cnpg.yaml.j2, secret.sops.yaml.j2, ks.yaml.j2)

**Updates Applied:**
- Added resource limits to CNPG configuration (matching Keycloak pattern)
- Added conditional affinity rules for HA deployments
- Added complete secret.sops.yaml.j2 template following project conventions
- Added directory structure clarification (no CRD split needed for bjw-s)
- Added missing configuration variables (backup credentials, additional providers)
- Added 3 improvement opportunities (#9-11)

#### Second Reflection Cycle - Model Configuration Analysis

**Validation Performed:**
1. ✅ Analyzed old cluster ConfigMap (`configmap.yaml.j2` - 865 lines)
2. ✅ Documented all 26 models across 4 providers:
   - Azure OpenAI US East: 7 models (GPT-4.1 series)
   - Azure OpenAI US East2: 16 models (GPT-5 series, audio, realtime, image)
   - Azure Anthropic: 4 models (Claude Opus/Sonnet/Haiku)
   - Azure Cohere: 2 models (Rerank, Embed)
3. ✅ Cross-referenced Required Variables with actual old cluster credentials
4. ✅ Validated special model configurations (health check exceptions, reasoning modes)

**Updates Applied:**
- Updated Required Variables to match multi-region Azure pattern (US East + US East2)
- Added Azure Cohere credentials to Optional Variables
- Documented credential list pattern with 3 Azure credentials
- Documented 6 access groups strategy
- Added complete litellm_settings, router_settings, general_settings from old cluster
- Added migration checklist for ConfigMap (10 items)
- Added 6 new improvement opportunities (#12-17)
- Added 3 new risks to Risk Assessment

**Critical Patterns Preserved:**
- `disable_background_health_check: true` for 5 non-standard models
- `cache_control_injection_points` for prompt caching optimization
- `thinking` and `merge_reasoning_content_in_choices` for reasoning models
- `background_health_checks: false` global setting (Prisma timeout workaround)

#### Convention Compliance

| Convention | Status | Notes |
| ---------- | ------ | ----- |
| Template delimiters (`#% %#`, `#{ }#`, `#\| #\|`) | ✅ Compliant | All examples use correct delimiters |
| Cross-namespace dependencies with namespace field | ✅ Compliant | ks.yaml.j2 example includes namespaces |
| Explicit storageClass on persistence | ✅ Compliant | CNPG uses storageClass field |
| Secret pattern with labels and components | ✅ Compliant | Secret template follows Keycloak pattern |
| CNPG resource limits | ✅ Compliant | Added during first reflection |
| Conditional affinity for HA | ✅ Compliant | Added during first reflection |
| Multi-region credential pattern | ✅ Compliant | Updated during second reflection |
| Model access groups | ✅ Documented | May need renaming for new cluster |

#### Remaining Considerations
- No CRD split pattern needed (bjw-s app-template is standard Helm)
- Keycloak client must be added to realm-import.yaml.j2 during implementation
- RustFS bucket creation requires manual Console UI step (documented in checklist)
- Organization-specific access groups (`aangpt-models`, `aanai-models`) need review/renaming
- Model IDs should use sequential numbering to avoid collisions
