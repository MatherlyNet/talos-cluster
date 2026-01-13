# Headlamp AI Assistant - LiteLLM Integration

**Date:** January 2026
**Status:** Implemented
**Author:** Claude Code

## Overview

This document describes the implementation of ConfigMap-based configuration to redirect the Headlamp AI Assistant plugin from OpenAI to the local LiteLLM proxy.

## Problem Statement

The Headlamp AI Assistant plugin (v0.1.0-alpha) does not provide UI configuration options for:
1. Custom OpenAI baseURL
2. Local models provider API key input

Without this capability, the plugin defaults to calling `api.openai.com`, which requires users to:
- Use external OpenAI API (costs, latency, privacy concerns)
- Cannot leverage the existing LiteLLM proxy already deployed in the cluster

## Solution: Distributed Configuration via ConfigMap

Headlamp supports "distributed configuration" for plugins via ConfigMaps, allowing cluster administrators to pre-configure plugins for all users.

**REF:** [Headlamp Distributed Settings Issue #3979](https://github.com/kubernetes-sigs/headlamp/issues/3979)

## Implementation

### Architecture

```
Headlamp AI Assistant Plugin (browser)
         ↓
Headlamp Backend (Go server)
         ↓
ConfigMap: headlamp-ai-assistant-settings
  - provider: "openai" (OpenAI-compatible)
  - baseURL: "http://litellm.ai-system.svc.cluster.local:4000/v1"
  - apiKeySecretName: "headlamp-secret"
  - apiKeySecretKey: "ai-assistant-api-key"
         ↓
LiteLLM Proxy (ai-system namespace)
         ↓
Azure OpenAI / Anthropic / Other LLM providers
```

### Configuration Variables

#### cluster.yaml
```yaml
# Headlamp AI Assistant API key for LiteLLM proxy (SOPS-encrypted)
# Generate with: openssl rand -hex 32
# (OPTIONAL) / Used when headlamp_enabled and litellm_enabled are both true
headlamp_ai_assistant_api_key: "placeholder-will-be-encrypted-with-sops"
```

#### Computed Variables (plugin.py)
```python
# Headlamp AI Assistant enabled when:
# - headlamp_enabled: true
# - litellm_enabled: true
# - headlamp_ai_assistant_api_key is provided
headlamp_ai_assistant_enabled = (
    headlamp_enabled and litellm_enabled and headlamp_ai_assistant_api_key
)

# Defaults:
headlamp_ai_assistant_base_url: "http://litellm.ai-system.svc.cluster.local:4000/v1"
headlamp_ai_assistant_provider: "openai"
```

### Kubernetes Resources

#### ConfigMap Template
**Location:** `templates/config/kubernetes/apps/kube-system/headlamp/app/ai-assistant-configmap.yaml.j2`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: headlamp-ai-assistant-settings
  namespace: kube-system
  annotations:
    _headlamp.dev.settings-plugin/headlamp-ai-assistant: "configmap:headlamp-ai-assistant-settings"
data:
  provider: "openai"
  baseURL: "http://litellm.ai-system.svc.cluster.local:4000/v1"
  apiKeySecretName: "headlamp-secret"
  apiKeySecretKey: "ai-assistant-api-key"
```

The annotation `_headlamp.dev.settings-plugin/headlamp-ai-assistant` tells Headlamp to load this ConfigMap as settings for the AI Assistant plugin.

#### Secret Template
**Location:** `templates/config/kubernetes/apps/kube-system/headlamp/app/secret.sops.yaml.j2`

Added to existing `headlamp-secret`:
```yaml
stringData:
  oidc-client-secret: "..." # Existing
  ai-assistant-api-key: "${headlamp_ai_assistant_api_key}" # NEW
```

### Network Policy

Network policy already configured (templates/config/kubernetes/apps/kube-system/headlamp/app/networkpolicy.yaml.j2:91-104):

```yaml
# Cilium L7 Policy
- toEndpoints:
    - matchLabels:
        app.kubernetes.io/name: litellm
        io.kubernetes.pod.namespace: ai-system
  toPorts:
    - ports:
        - port: "4000"
          protocol: TCP

# Standard NetworkPolicy
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ai-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: litellm
  ports:
    - protocol: TCP
      port: 4000
```

## Why DNS Rewriting Won't Work

We considered DNS rewriting (`api.openai.com` → `litellm.ai-system.svc.cluster.local`) but rejected it due to:

1. **TLS Certificate Mismatch**: LiteLLM doesn't have OpenAI's TLS certificate
2. **SNI (Server Name Indication)**: Client sends `api.openai.com` in TLS handshake
3. **HTTP Host Header**: Mismatch between expected and actual host
4. **Complex Workarounds**: Would require TLS terminating proxy with forged certificates (security risk)

## Deployment

### Prerequisites
- `headlamp_enabled: true`
- `litellm_enabled: true`
- `headlamp_ai_assistant_api_key` set in cluster.yaml

### Steps

1. Generate API key:
   ```bash
   openssl rand -hex 32
   ```

2. Add to `cluster.yaml`:
   ```yaml
   headlamp_ai_assistant_api_key: "your-generated-key-here"
   ```

3. Regenerate and apply:
   ```bash
   task configure
   task reconcile
   ```

4. Verify ConfigMap created:
   ```bash
   kubectl get configmap -n kube-system headlamp-ai-assistant-settings -o yaml
   ```

5. Verify Secret updated:
   ```bash
   kubectl get secret -n kube-system headlamp-secret -o yaml
   ```

6. Test in Headlamp UI:
   - Open Headlamp
   - Enable AI Assistant plugin (if not auto-enabled)
   - Verify it connects to LiteLLM (check LiteLLM logs for requests)

## Verification

### Check LiteLLM Logs
```bash
kubectl logs -n ai-system -l app.kubernetes.io/name=litellm --tail=50 -f
```

### Check Headlamp Logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=headlamp -c headlamp --tail=50 -f
```

### Test AI Assistant
In Headlamp UI:
1. Click AI Assistant icon
2. Ask: "List all pods in kube-system namespace"
3. Verify response (should query via LiteLLM)

## Troubleshooting

### Plugin Not Loading Configuration
- Check ConfigMap annotation is correct
- Verify Headlamp pods restarted after ConfigMap creation
- Check Headlamp logs for plugin configuration errors

### API Authentication Failures
- Verify Secret contains correct API key
- Check LiteLLM logs for authentication errors
- Ensure LiteLLM is configured to accept the API key

### Network Connectivity Issues
- Verify Network Policy allows Headlamp → LiteLLM
- Test connectivity: `kubectl exec -n kube-system <headlamp-pod> -- curl http://litellm.ai-system.svc.cluster.local:4000/health`
- Check Cilium policy status: `cilium policy get`

## Future Improvements

1. **Plugin UI Configuration**: Upstream feature request to Headlamp for native baseURL/API key configuration
2. **Multiple Providers**: Support switching between multiple LLM backends
3. **User-Specific Keys**: Allow users to provide their own API keys (currently shared cluster-wide)
4. **Usage Tracking**: Integrate with LiteLLM usage tracking and budgets

## References

- [Headlamp AI Assistant Plugin](https://github.com/headlamp-k8s/plugins/tree/main/ai-assistant)
- [Headlamp Distributed Settings #3979](https://github.com/kubernetes-sigs/headlamp/issues/3979)
- [LiteLLM OpenAI Compatibility](https://docs.litellm.ai/docs/)
- [Headlamp Backend Architecture](https://headlamp.dev/docs/latest/development/backend/)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## Schema Updates

### cluster.schema.cue
```cue
// Headlamp AI Assistant API key for LiteLLM proxy (SOPS-encrypted)
// Used when both headlamp_enabled and litellm_enabled are true
headlamp_ai_assistant_api_key?: string & !=""  // Generate with: openssl rand -hex 32
```

### Test Files
- `.github/tests/public.yaml`: Added commented example
- `.github/tests/private.yaml`: Added commented example
