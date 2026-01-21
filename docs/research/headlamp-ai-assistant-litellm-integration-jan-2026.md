# Headlamp AI Assistant - LiteLLM Integration

**Date:** January 2026
**Status:** ❌ NOT USABLE - Plugin Removed (Awaiting Upstream Changes)
**Author:** Claude Code

## Overview

This document describes the research and attempted implementation of configuring the Headlamp AI Assistant plugin to use the local LiteLLM proxy instead of OpenAI, and why this is currently impossible due to plugin limitations.

## Problem Statement

The Headlamp AI Assistant plugin (v0.1.0-alpha) has critical configuration limitations that prevent using it with LiteLLM:

### Plugin UI Limitations (Confirmed via Testing)

1. **OpenAI Provider**: Does NOT allow custom baseURL configuration
   - Only accepts API key input
   - Hardcoded to use `api.openai.com`
   - Cannot redirect to LiteLLM proxy

2. **Local Models Provider**: Does NOT allow API key input
   - Only accepts baseURL configuration
   - Cannot authenticate to LiteLLM (requires API key)

3. **Other Providers** (Azure, Anthropic, etc.): Require provider-specific endpoints and credentials

### Conclusion

**There is NO combination of provider settings that allows:**

- Custom baseURL (to point to LiteLLM) **AND**
- API key authentication (to authenticate to LiteLLM)

Without both capabilities, the plugin cannot be used with LiteLLM proxy and must connect directly to external API providers (OpenAI, Anthropic, etc.), which:

- Incurs external API costs
- Introduces latency
- Raises privacy/data residency concerns
- Cannot leverage the existing LiteLLM proxy infrastructure

## Attempted Solution: Distributed Configuration via ConfigMap

### Why This Approach Was Attempted

Headlamp Issue #3979 proposes "distributed configuration" for plugins via ConfigMaps, which would allow cluster administrators to pre-configure plugins for all users.

**REF:** [Headlamp Distributed Settings Issue #3979](https://github.com/kubernetes-sigs/headlamp/issues/3979)

### Critical Finding: Feature Not Implemented

**As of January 2026, the distributed settings feature has NOT been implemented.** After extensive research:

1. **Issue #3979 remains OPEN** with "Queued" status - no implementation timeline
2. **ConfigMap-based plugin configuration is NOT supported** in Headlamp v0.39.0
3. **The proposed annotation format was only a discussion**, not an actual feature
4. **Plugin settings are stored in browser localStorage** via `registerPluginSettings` API
5. **No backend configuration mechanism exists** for plugins currently

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

## Current Status: Plugin Removed

**As of January 2026, the Headlamp AI Assistant plugin has been REMOVED from the deployment** due to insurmountable configuration limitations.

### Why It Cannot Be Used

The plugin's UI has **fatal limitations** that make LiteLLM integration impossible:

1. **OpenAI Provider**:
   - ✅ Accepts API key
   - ❌ **Does NOT allow custom baseURL** (hardcoded to `api.openai.com`)
   - Cannot redirect to LiteLLM

2. **Local Models Provider**:
   - ✅ Accepts custom baseURL
   - ❌ **Does NOT allow API key input**
   - Cannot authenticate to LiteLLM

3. **Result**: No combination of settings allows both custom baseURL AND API key authentication

### What Was Removed

All AI Assistant integration attempts have been removed from the codebase:

- ❌ `templates/config/kubernetes/apps/kube-system/headlamp/app/ai-assistant-configmap.yaml.j2` (deleted)
- ❌ AI Assistant plugin from `helmrelease.yaml.j2` plugin list (removed)
- ❌ `ai-assistant-api-key` from `secret.sops.yaml.j2` (removed)
- ❌ `headlamp_ai_assistant_api_key` variable from `cluster.yaml` (removed)
- ❌ `headlamp_ai_assistant_api_key` schema from `cluster.schema.cue` (removed)
- ❌ `headlamp_ai_assistant_*` computed variables from `plugin.py` (removed)
- ❌ ConfigMap resource from `kustomization.yaml.j2` (removed)

### Network Policy Status

✅ **Network policy allowing Headlamp → LiteLLM remains configured** in case future plugin versions support proper configuration.

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

### "AI Assistant Setup Required" Message

**Symptom**: After installing plugin, UI shows "AI Assistant Setup Required - To use the AI Assistant, please configure your AI provider credentials in the settings page."

**Cause**: Plugin settings are not configured in browser localStorage.

**Solution**: Follow the manual configuration steps above. This is expected behavior - there is no automatic/centralized configuration.

### API Authentication Failures

**Symptom**: AI Assistant shows errors when sending queries.

**Possible Causes**:

1. Incorrect API key entered in Headlamp settings
2. LiteLLM not configured to accept the API key
3. Network connectivity issues

**Solutions**:

- Verify API key matches `headlamp_ai_assistant_api_key` in cluster.yaml
- Check LiteLLM logs: `kubectl logs -n ai-system -l app.kubernetes.io/name=litellm --tail=50 -f`
- Ensure LiteLLM is configured to accept the API key

### Network Connectivity Issues

**Symptom**: Timeouts or connection errors when using AI Assistant.

**Solutions**:

- Verify Network Policy allows Headlamp → LiteLLM
- Test connectivity from Headlamp pod:

  ```bash
  kubectl exec -n kube-system deployment/headlamp -- curl -v http://litellm.ai-system.svc.cluster.local:4000/health
  ```

- Check Cilium policy status: `cilium policy get`

### Settings Lost After Browser Clear

**Symptom**: AI Assistant requires reconfiguration after clearing browser data.

**Cause**: Settings are stored in browser localStorage, not on server.

**Solution**:

- Re-enter configuration following manual steps
- OR wait for distributed settings feature (Issue #3979)
- OR consider custom plugin build with hardcoded settings

## Potential Future Solutions

### Option 1: Wait for Plugin UI Improvements ⭐ **RECOMMENDED**

**Track upstream issues:**

- Request custom baseURL support for OpenAI provider
- Request API key support for Local Models provider
- OR use "Custom" provider that accepts both baseURL and API key

**When implemented**: Simply configure plugin settings to point to LiteLLM

**Timeline**: Unknown - plugin is in alpha (v0.1.0-alpha)

### Option 2: Wait for Distributed Settings Feature

**Track**: [Issue #3979](https://github.com/kubernetes-sigs/headlamp/issues/3979)

**Status**: Queued, no implementation timeline

**Impact**: Would enable ConfigMap-based pre-configuration, but still requires Option 1 to work

### Option 3: Custom Plugin Build (Advanced)

**Approach**: Fork AI Assistant plugin and modify source code to:

- Default baseURL to LiteLLM endpoint
- Read API key from environment variable or Kubernetes Secret
- Remove UI configuration requirement

**Pros**: Would work today with LiteLLM
**Cons**:

- Requires maintaining fork
- Must rebuild on every plugin update
- Not officially supported
- Complex build/distribution process

### Option 4: Headlamp Backend Proxy Modification (Advanced)

**Approach**: Fork Headlamp backend to intercept AI Assistant HTTP requests and:

- Rewrite `api.openai.com` URLs to LiteLLM endpoint
- Inject LiteLLM API key from Kubernetes Secret

**Pros**: Transparent to plugin, no plugin changes needed
**Cons**:

- Requires maintaining Headlamp fork
- Complex Go backend modifications
- High maintenance burden
- Would break on Headlamp updates

## Recommended Action

**File upstream feature requests** with Headlamp AI Assistant plugin:

1. **Custom baseURL for OpenAI provider** - Allow users to specify alternative OpenAI-compatible endpoints
2. **API key support for Local Models provider** - Allow authentication to local proxies like LiteLLM
3. **Generic "Custom" provider** - Accepts both baseURL AND API key for maximum flexibility
4. **ConfigMap/Secret integration** - Read configuration from Kubernetes resources instead of browser localStorage

**Project Repository**: [https://github.com/headlamp-k8s/plugins](https://github.com/headlamp-k8s/plugins)

## Monitoring for Updates

Track these issues for progress:

1. **Distributed Settings**: [Issue #3979](https://github.com/kubernetes-sigs/headlamp/issues/3979)
2. **Persistent Storage**: [Issue #4280](https://github.com/kubernetes-sigs/headlamp/issues/4280)
3. **AI Assistant Plugin**: [GitHub - headlamp-k8s/plugins](https://github.com/headlamp-k8s/plugins/tree/main/ai-assistant)

When any of these features are implemented, this integration can be revisited.

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

- `.github/tests/public.yaml`: Removed AI Assistant variable references
- `.github/tests/private.yaml`: Removed AI Assistant variable references

## Summary

**Headlamp AI Assistant plugin (v0.1.0-alpha) cannot be used with LiteLLM** due to fundamental UI limitations:

- OpenAI provider: No custom baseURL support ❌
- Local Models provider: No API key support ❌
- No distributed configuration support ❌
- Settings stored in browser localStorage only ❌

**Plugin has been removed from deployment** until upstream changes are made to support:

1. Custom baseURL for OpenAI provider (or generic provider)
2. API key authentication for local providers
3. ConfigMap/Secret-based configuration

**Network policy remains configured** for future use when plugin capabilities improve.

**Upstream issues to monitor**:

- [Headlamp Distributed Settings #3979](https://github.com/kubernetes-sigs/headlamp/issues/3979)
- [Headlamp Persistent Storage #4280](https://github.com/kubernetes-sigs/headlamp/issues/4280)
- [AI Assistant Plugin Repository](https://github.com/headlamp-k8s/plugins/tree/main/ai-assistant)
