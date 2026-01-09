# LiteLLM Proxy Configuration

## Overview

LiteLLM is an LLM proxy that provides a unified OpenAI-compatible API for multiple LLM backends. It enables:
- Multi-provider routing (Azure OpenAI, Anthropic via Azure, Cohere)
- Credential management with named credentials
- Rate limiting and quota management
- Caching via Dragonfly (Redis-compatible, 25x faster than Redis)
- Observability via Prometheus metrics, OpenTelemetry tracing, and Langfuse
- OIDC authentication via Keycloak (optional)
- Database backups via CloudNativePG to RustFS (optional)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ai-system namespace                  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐                       ┌─────────────────┐  │
│  │   LiteLLM   │───────────────────────│  CloudNativePG  │  │
│  │ (Deployment)│                       │   PostgreSQL    │  │
│  │  Port 4000  │                       │   Port 5432     │  │
│  └──────┬──────┘                       └─────────────────┘  │
│         │                                                   │
│         ├─────► Azure OpenAI US East                        │
│         ├─────► Azure OpenAI US East2                       │
│         ├─────► Azure Anthropic (Claude models)             │
│         └─────► Azure Cohere (Embed + Rerank)               │
└─────────│───────────────────────────────────────────────────┘
          │
          │  Cross-namespace connection (ACL: litellm user, litellm:* keys)
          │
┌─────────▼───────────────────────────────────────────────────┐
│                        cache namespace                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Dragonfly (Operator-managed)           │    │
│  │         Redis-compatible, 25x faster than Redis     │    │
│  │                     Port 6379                       │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Variables

### Enable/Disable
```yaml
litellm_enabled: true        # Enable LiteLLM deployment
litellm_subdomain: "litellm" # Creates litellm.${cloudflare_domain}
litellm_replicas: 1          # Number of LiteLLM replicas
```

### Security Keys (SOPS-encrypted)
```yaml
litellm_master_key: "sk-..."  # Master API key (min 32 chars, starts with sk-)
litellm_salt_key: "..."       # Encryption salt (min 32 chars)
```

### Resource Configuration
```yaml
litellm_cpu_request: "200m"
litellm_cpu_limit: "1000m"
litellm_memory_request: "512Mi"
litellm_memory_limit: "1Gi"
litellm_image_tag: "main-v1.80.8-stable.1"  # LiteLLM container tag
```

### PostgreSQL Database
```yaml
litellm_db_user: "litellm"
litellm_db_password: "..."      # SOPS-encrypted
litellm_db_name: "litellm"
litellm_db_instances: 1         # 1 for dev, 3+ for HA
litellm_db_storage_size: "20Gi"
```

### Dragonfly Cache (Shared)
LiteLLM uses the shared Dragonfly deployment in the `cache` namespace for caching.
Requires the following configuration in the Dragonfly section:
```yaml
dragonfly_enabled: true           # Enable shared Dragonfly
dragonfly_acl_enabled: true       # Enable ACL for multi-tenant access
dragonfly_litellm_password: "..." # SOPS-encrypted, ACL user password
```
LiteLLM connects to `dragonfly.cache.svc.cluster.local:6379` with:
- **User:** `litellm` (ACL-authenticated)
- **Key prefix:** `litellm:*` (namespace isolation via ACL)
- **Namespace:** `litellm` (additional key prefixing by LiteLLM)

### Azure OpenAI Backends
```yaml
# US East Region
azure_openai_us_east_api_key: ""           # API key (SOPS-encrypted)
azure_openai_us_east_resource_name: ""     # e.g., "my-openai-east"
azure_openai_us_east_api_version: "2025-01-01-preview"

# US East2 Region
azure_openai_us_east2_api_key: ""          # API key (SOPS-encrypted)
azure_openai_us_east2_resource_name: ""    # e.g., "my-openai-east2"
azure_openai_us_east2_api_version: "2025-04-01-preview"

# Azure Anthropic
azure_anthropic_api_key: ""
azure_anthropic_api_base: ""

# Azure Cohere Rerank
azure_cohere_rerank_api_key: ""
azure_cohere_rerank_api_base: ""

# Azure Cohere Embed
azure_cohere_embed_api_key: ""
azure_cohere_embed_api_base: ""
```

### OIDC Authentication (requires keycloak_enabled)
```yaml
litellm_oidc_enabled: true
litellm_oidc_client_secret: "..."  # SOPS-encrypted
```

### Observability
```yaml
# Prometheus metrics (auto-enabled with litellm_enabled)
litellm_monitoring_enabled: true   # ServiceMonitor + Dashboard

# OpenTelemetry Tracing (requires tracing_enabled)
litellm_tracing_enabled: true      # Export traces to Tempo

# Langfuse (external LLM analytics)
litellm_langfuse_enabled: true
litellm_langfuse_host: "https://cloud.langfuse.com"
litellm_langfuse_public_key: ""    # SOPS-encrypted
litellm_langfuse_secret_key: ""    # SOPS-encrypted
```

### Backups (requires rustfs_enabled)
```yaml
litellm_backup_enabled: true
litellm_s3_access_key: ""          # SOPS-encrypted (create via RustFS Console)
litellm_s3_secret_key: ""          # SOPS-encrypted
# Required bucket: litellm-backups (created by RustFS setup job)
```

#### RustFS IAM Setup (Principle of Least Privilege)

> All user/policy operations must be performed via the **RustFS Console UI** (port 9001).
> The RustFS bucket setup job automatically creates the `litellm-backups` bucket.

**1. Create Custom Policy**

Navigate to **Identity** → **Policies** → **Create Policy**

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

| Permission | Purpose |
| ---------- | ------- |
| `s3:ListBucket` | List backup files for WAL management |
| `s3:GetObject` | Download backups for restore (PITR) |
| `s3:PutObject` | Upload WAL segments and base backups |
| `s3:DeleteObject` | Retention cleanup of old WAL files |
| `s3:GetBucketLocation` | AWS SDK compatibility |

**2. Create Group (or use existing `ai-system` group)**

Navigate to **Identity** → **Groups** → **Create Group**

- **Name:** `ai-system` (shared with Obot, Langfuse)
- **Assign Policy:** `litellm-storage` (add to existing policies if group exists)
- Click **Save**

**3. Create LiteLLM Backup User**

Navigate to **Identity** → **Users** → **Create User**

- **Access Key:** (auto-generated, copy this)
- **Secret Key:** (auto-generated, copy this)
- **Assign Group:** `ai-system`
- Click **Save**

**4. Update cluster.yaml**

```yaml
litellm_s3_access_key: "<paste-access-key>"
litellm_s3_secret_key: "<paste-secret-key>"
```

Then run: `task configure && task reconcile`

## File Structure

```
templates/config/kubernetes/apps/ai-system/litellm/
├── ks.yaml.j2                  # Flux Kustomization
└── app/
    ├── kustomization.yaml.j2
    ├── ocirepository.yaml.j2   # Helm chart source (bjw-s/app-template)
    ├── helmrelease.yaml.j2     # LiteLLM Helm chart deployment
    ├── configmap.yaml.j2       # LiteLLM proxy config (model_list)
    ├── postgresql.yaml.j2      # CloudNativePG Cluster + Database
    ├── secret.sops.yaml.j2     # API keys and credentials
    ├── referencegrant.yaml.j2  # Gateway API cross-namespace access
    ├── networkpolicy.yaml.j2   # Cilium NetworkPolicy
    └── servicemonitor.yaml.j2  # Prometheus scraping

# Note: Dragonfly is provided by the shared cache namespace deployment

# HTTPRoute is centralized in:
# templates/config/kubernetes/apps/network/envoy-gateway/app/httproutes.yaml.j2
# - Uses both envoy-internal and envoy-external gateways (split-horizon DNS)
# - No OIDC protection (LiteLLM uses native SSO via GENERIC_* env vars)
```

## Key Implementation Details

### Container Image
LiteLLM uses `ghcr.io/berriai/litellm:main-v1.80.8-stable.1`:
- Standard base image with pre-built UI
- Runs as root (UID 0) for UI serving
- Prisma migrations via `LITELLM_MIGRATION_DIR: /tmp/prisma`

Security context:
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # Required for Prisma
  runAsNonRoot: false            # Runs as root (UID 0)
  privileged: false
  capabilities: { drop: ["ALL"] }
  seccompProfile: { type: RuntimeDefault }
```

### Health Check Endpoints
LiteLLM provides several health check endpoints:

| Endpoint | Purpose | Use Case |
| -------- | ------- | -------- |
| `/health/liveliness` | Returns "I'm alive!" | Startup/Liveness probes |
| `/health/readiness` | Checks DB, cache, callbacks | **Readiness probe** |
| `/health` | Full model health (makes API calls) | Manual testing only |
| `/health/services` | Admin-only integration check | Debugging |

**Kubernetes Probe Configuration:**
```yaml
probes:
  startup:
    path: /health/liveliness
    initialDelaySeconds: 30
    failureThreshold: 30
  liveness:
    path: /health/liveliness
    initialDelaySeconds: 60
  readiness:
    path: /health/readiness
    initialDelaySeconds: 30
```

**Background Health Checks:**
Disabled to prevent Prisma connection pool exhaustion:
```yaml
general_settings:
  background_health_checks: false
```

### ConfigMap Mount
The proxy configuration is mounted via persistence volume:
```yaml
persistence:
  config-file:
    type: configMap
    name: litellm-config
    globalMounts:
      - path: /app/config.yaml
        subPath: config.yaml
        readOnly: true
```

### Prometheus Metrics
Metrics are exposed at `/metrics` endpoint. Required configuration:
```yaml
# In envVars section of HelmRelease
LITELLM_CALLBACKS: prometheus

# In ConfigMap litellm_settings
callbacks:
  - prometheus
service_callbacks:
  - prometheus_system
success_callback:
  - prometheus
failure_callback:
  - prometheus
```

### Grafana Dashboard
When `litellm_monitoring_enabled: true`:
- ServiceMonitor deployed for Prometheus scraping
- Dashboard can be added to Grafana's AI folder

### UI Authentication
The LiteLLM UI uses:
- Username: `admin` (hardcoded)
- Password: `LITELLM_MASTER_KEY` (from SOPS secret)

Environment variables:
```yaml
- name: UI_USERNAME
  value: "admin"
- name: UI_PASSWORD
  valueFrom:
    secretKeyRef:
      name: litellm-secret
      key: LITELLM_MASTER_KEY
```

## Model Configuration

Models are defined in the ConfigMap (`configmap.yaml.j2`) under `model_list`. Each model specifies:
- `model_name`: Public name exposed via API
- `litellm_params`: Backend configuration
  - `model`: Provider prefix + model name (e.g., `azure/gpt-4.1`)
  - `litellm_credential_name`: Reference to credential_list entry
  - Rate limits: `rpm`, `tpm`
  - Timeouts: `timeout`, `stream_timeout`
- `model_info`: Metadata (access_groups, base_model, supports_reasoning)

### Credential Management
Credentials are defined in `credential_list`:
```yaml
credential_list:
  - credential_name: azure_credential_us_east
    credential_values:
      api_key: os.environ/AZURE_API_KEY
      api_base: os.environ/AZURE_API_BASE
      api_version: os.environ/AZURE_API_VERSION
```

### Model Prefixes
Different model providers require specific prefixes:

| Prefix | Provider | Example |
| ------ | -------- | ------- |
| `azure/` | Azure OpenAI | `azure/gpt-4.1` |
| `azure_ai/` | Azure AI Models (Cohere, etc.) | `azure_ai/cohere-embed-v-4-0` |
| `anthropic/` | Anthropic (via Azure inference) | `anthropic/claude-sonnet-4-5` |
| `cohere/` | Cohere (rerank models) | `cohere/cohere-rerank-v3.5` |

**Important**: For Azure-hosted Cohere embedding models, use `azure_ai/` prefix (NOT `cohere/`).

### Model Health Check Modes
Per-model health check configuration in `model_info`:

| Mode | Use Case | Health Check Support |
| ---- | -------- | -------------------- |
| `chat` (default) | Chat completion models | ✅ Supported |
| `embedding` | Embedding models | ✅ Supported |
| `rerank` | Reranking models | ✅ Supported |
| `realtime` | Realtime streaming models | ❌ Use `disable_background_health_check: true` |
| `image_generation` | Image generation models | ✅ Supported |
| `audio_speech` | Text-to-speech (TTS) | ✅ Supported (requires `health_check_voice`) |
| `audio_transcription` | Speech-to-text | ✅ Supported |

**Special Cases:**

1. **gpt-audio models** (gpt-audio, gpt-audio-mini):
   - These are **hybrid chat completion models** requiring `modalities: ["text", "audio"]`
   - They are NOT text-to-speech models - do NOT use `mode: audio_speech`
   - LiteLLM has no health check mode for audio chat models
   - **Must use**: `disable_background_health_check: true`

2. **Realtime models** (gpt-realtime, gpt-realtime-mini):
   - Use `mode: realtime` for proper identification
   - **Must use**: `disable_background_health_check: true`

3. **Azure AI embeddings** (cohere-embed-v-4-0):
   - Use `mode: embedding`
   - Use `azure_ai/` prefix (NOT `cohere/`)
   - Azure AI endpoints may return 404 on health checks
   - **Must use**: `disable_background_health_check: true`

Example configuration:
```yaml
# Audio chat model (NOT TTS)
- model_name: gpt-audio
  litellm_params:
    model: azure/gpt-audio
  model_info:
    supports_audio_output: true
    supports_audio_input: true
    disable_background_health_check: true

# Embedding model on Azure AI
- model_name: cohere-embed-v-4-0
  litellm_params:
    model: azure_ai/cohere-embed-v-4-0
    input_type: text
  model_info:
    mode: embedding
    disable_background_health_check: true
```

### Available Models (when Azure regions configured)

**US East:**
- gpt-4.1, gpt-4.1-nano, gpt-4o-mini
- o3, o4-mini (reasoning models)
- text-embedding-3-small, text-embedding-ada-002

**US East2:**
- gpt-5, gpt-5-chat, gpt-5-mini, gpt-5-nano
- gpt-5.1, gpt-5.2
- gpt-audio, gpt-audio-mini (audio chat models)
- gpt-image-1 (image generation)
- gpt-realtime, gpt-realtime-mini
- claude-opus-4-5, claude-sonnet-4-5, claude-opus-4-1, claude-haiku-4-5 (via Azure Anthropic)
- text-embedding-3-large

**Azure AI Services:**
- cohere-embed-v-4-0 (embeddings)
- cohere-rerank-v3.5 (reranking)

## Testing

```bash
# Check pods
kubectl get pods -n ai-system -l app.kubernetes.io/name=litellm

# Check health
kubectl port-forward -n ai-system svc/litellm 4000:4000
curl http://localhost:4000/health/readiness

# List models (requires API key)
MASTER_KEY=$(kubectl get secret -n ai-system litellm-secret -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
curl -H "Authorization: Bearer $MASTER_KEY" http://localhost:4000/models

# Check metrics
curl http://localhost:4000/metrics

# Access via HTTPRoute
https://litellm.<domain>/
```

## Troubleshooting

### Prisma ConnectTimeout Errors
If you see `httpcore.ConnectTimeout` errors:
- Verify `background_health_checks: false` in general_settings
- Check Prisma migration directory: `LITELLM_MIGRATION_DIR: /tmp/prisma`
- Restart pods to clear connection pool

### Models Not Loading
If only default models appear (gpt-3.5-turbo, fake-openai-endpoint):
- Verify ConfigMap is correctly mounted: `kubectl exec -n ai-system <pod> -- cat /app/config.yaml`
- Check for syntax errors in config.yaml

### Model Health Check Failures
Common health check issues:

| Error | Model Type | Solution |
| ----- | ---------- | -------- |
| "audioSpeech operation does not work" | gpt-audio | Remove `mode: audio_speech`, use `disable_background_health_check: true` |
| "404 Resource not found" | Azure AI models | Use `azure_ai/` prefix, not `cohere/` |
| "requires audio modalities" | gpt-audio | These are chat models, NOT TTS - disable health check |

### /metrics Returns 404
Ensure both are configured:
- `LITELLM_CALLBACKS: prometheus` in envVars
- `callbacks: ["prometheus"]` in ConfigMap litellm_settings

### UI Login Fails
Verify environment variables:
- `UI_USERNAME` must be set (default: "admin")
- `UI_PASSWORD` must reference the secret

### Readiness Probe Failures
If readiness probe fails but liveness passes:
- Check database connectivity
- Verify PostgreSQL pod is running: `kubectl get pods -n ai-system -l app.kubernetes.io/name=litellm-postgresql`
- Check Dragonfly (Redis) connectivity: `kubectl get pods -n cache -l app=dragonfly`

### OIDC Login Issues
If SSO redirect fails:
- Verify Keycloak is healthy: `kubectl get keycloak -n identity`
- Check client secret matches: `litellm_oidc_client_secret`
- Verify redirect URLs in Keycloak client configuration
- Check pod can reach internal Keycloak: `kubectl exec -n ai-system <pod> -- wget -qO- http://keycloak-service.identity.svc.cluster.local:8080/realms/matherlynet/.well-known/openid-configuration`

**Split-horizon DNS Issue**: If external Keycloak URL times out from pods (UniFi DNS resolves to LAN IP), the solution is already implemented - LiteLLM uses external URL for `GENERIC_AUTHORIZATION_ENDPOINT` (browser redirects) but internal URL for `GENERIC_TOKEN_ENDPOINT` and `GENERIC_USERINFO_ENDPOINT` (server-to-server calls). Keycloak's `backchannelDynamic: true` ensures issuer consistency in tokens.

## NetworkPolicy Considerations

LiteLLM requires egress to external Azure OpenAI endpoints. The NetworkPolicy in `networkpolicy.yaml.j2` includes:
- DNS egress to kube-system
- External HTTPS (443) egress to Azure OpenAI endpoints
- CiliumNetworkPolicy for Kubernetes API access (if needed)

When `network_policies_enabled: true`:
- Labels are added: `network.cilium.io/api-access: "true"`
- Pods can access Kubernetes API for service discovery

## Dependencies

- **CloudNativePG** (`cnpg_enabled: true`): PostgreSQL database for LiteLLM state
- **Dragonfly** (`dragonfly_enabled: true`, `dragonfly_acl_enabled: true`): Shared Redis-compatible cache in `cache` namespace. LiteLLM authenticates as `litellm` user with ACL-limited access to `litellm:*` keys
- **Envoy Gateway**: HTTPRoute support for external access via Gateway API
- **Prometheus/Grafana** (`monitoring_enabled`): Metrics and dashboards
- **Tempo** (`tracing_enabled`): Distributed tracing via OpenTelemetry
- **Keycloak** (`keycloak_enabled`): OIDC authentication (optional)
- **RustFS** (`rustfs_enabled`): PostgreSQL backups via CNPG Barman Cloud Plugin (optional)
- **SOPS/Age**: Secret encryption for API keys and credentials
