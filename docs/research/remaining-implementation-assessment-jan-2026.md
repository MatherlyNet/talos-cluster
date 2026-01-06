# Remaining Implementation Assessment

> **Document Version:** 1.4.0
> **Assessment Date:** January 2026
> **Status:** Living Document
> **Sources:**
> - [k8s-at-home-remaining-implementation.md](../guides/k8s-at-home-remaining-implementation.md)
> - [gitops-components-implementation.md](../guides/gitops-components-implementation.md)
> - [envoy-gateway-observability-security.md](../guides/envoy-gateway-observability-security.md)
> - [envoy-gateway-examples-analysis.md](./envoy-gateway-examples-analysis.md)
> - [envoy-gateway-oidc-integration.md](./envoy-gateway-oidc-integration.md)

---

## Executive Summary

This document tracks **remaining work only**. Completed components are documented in their respective source guides with updated status.

### Quick Status

| Category | Remaining Items |
| -------- | --------------- |
| Templates Needed | VolSync (~2 hours) |
| Config Needed | Talos Backup S3, JWT/OIDC |
| Deployment Pending | tuppr verification |

---

## Remaining Work

### 1. VolSync (PVC Backup) - TEMPLATES NEEDED

> Source: [k8s-at-home-remaining-implementation.md](../guides/k8s-at-home-remaining-implementation.md#phase-2-volsync-pvc-backup)

**Status:** Templates do not exist. Variables defined in `cluster.yaml` but commented out.

**Required Work:**
1. Create `templates/config/kubernetes/apps/storage/volsync/` directory structure
2. Create template files per guide:
   - `ks.yaml.j2` - Flux Kustomization
   - `app/kustomization.yaml.j2`
   - `app/helmrelease.yaml.j2`
   - `app/ocirepository.yaml.j2`
   - `app/secret.sops.yaml.j2` - Restic credentials
3. Update `templates/config/kubernetes/apps/storage/kustomization.yaml.j2` to include VolSync conditional
4. Uncomment and configure `volsync_*` variables in `cluster.yaml`

**Effort:** ~2 hours

---

### 2. Talos Backup - CONFIG INCOMPLETE

> Source: [gitops-components-implementation.md](../guides/gitops-components-implementation.md#12-talos-backup)

**Status:** Templates complete. S3 configuration not set.

**cluster.yaml variables COMMENTED OUT:**
```yaml
# backup_s3_endpoint: ""
# backup_s3_bucket: ""
# backup_s3_access_key: ""
# backup_s3_secret_key: ""
# backup_age_public_key: ""
```

**Required Work:**
1. Set up Cloudflare R2 bucket for backups
2. Generate R2 API token with write permissions
3. Uncomment and configure `backup_s3_*` variables
4. Run `task configure` to encrypt secrets
5. Deploy via `task reconcile`
6. Test: `kubectl -n kube-system create job --from=cronjob/talos-backup test-backup`

**Effort:** ~1 hour

---

### 3. JWT SecurityPolicy (API Auth) - CONFIG INCOMPLETE

> Source: [envoy-gateway-observability-security.md](../guides/envoy-gateway-observability-security.md#phase-2-jwt-securitypolicy)

**Status:** Templates complete (`securitypolicy-jwt.yaml.j2`). OIDC provider not configured.

**Use Case:** API/service-to-service authentication via Bearer tokens.

**cluster.yaml variables COMMENTED OUT:**
```yaml
# oidc_provider_name: "keycloak"
# oidc_issuer_url: ""
# oidc_jwks_uri: ""
# oidc_additional_claims: []
```

**Required Work:**
1. Deploy OIDC provider (e.g., Keycloak)
2. Configure realm and client
3. Uncomment and configure `oidc_*` variables
4. Run `task configure`
5. Label HTTPRoutes with `security: jwt-protected`
6. Test JWT authentication

**Effort:** Variable (depends on OIDC provider setup)

---

### 4. tuppr - DEPLOYMENT VERIFICATION PENDING

> Source: [gitops-components-implementation.md](../guides/gitops-components-implementation.md#11-talos-upgrade-controller-tuppr)

**Status:** Templates complete. Configuration complete. Deployment needs verification.

**Verification Steps:**
1. Verify Talos API patch applied: `talosctl get machineconfig -n <node> -o yaml | grep kubernetesTalosAPIAccess`
2. Check tuppr pods: `kubectl -n system-upgrade get pods`
3. Validate CRs: `kubectl get talosupgrade,kubernetesupgrade`

**Effort:** ~30 minutes

---

## Priority Order

### High Priority (Operations & Disaster Recovery)

1. **Talos Backup Configuration** (~1 hour) - Essential for DR
2. **tuppr Deployment Verification** (~30 min) - Validates upgrade automation

### Medium Priority

1. **VolSync Implementation** (~2 hours) - Only if PVC backups needed

### Low Priority (When OIDC Provider Available)

1. **JWT SecurityPolicy Configuration** - Requires OIDC provider first

---

## Future Considerations

These are optional enhancements documented in source guides:

| Item | Source Guide | Notes |
| ---- | ------------ | ----- |
| **Native OIDC SecurityPolicy** | envoy-gateway-oidc-integration | Web SSO (session-based) - needs templates |
| **OAuth2-Proxy ext_authz** | envoy-gateway-oidc-integration | Claims forwarding to backends |
| Shared bjw-s Repository | k8s-at-home-remaining | Only for multiple bjw-s apps |
| ClusterSecretStore Templates | k8s-at-home-remaining | 1Password/Bitwarden/Vault |
| OTel Metrics Sink | envoy-gateway-examples-analysis | Unified observability (optional) |
| gRPC Routing | envoy-gateway-examples-analysis | Adopt when gRPC services deployed |
| TCP/TLS Passthrough | envoy-gateway-examples-analysis | Adopt when needed |
| Merged Gateways | envoy-gateway-examples-analysis | Evaluate for resource optimization |

### OIDC Authentication Options (When Provider Available)

The project supports two OIDC authentication approaches:

1. **JWT SecurityPolicy** (Item #3 above) - For API/service-to-service auth
   - Template exists: `securitypolicy-jwt.yaml.j2`
   - Validates Bearer tokens, extracts claims to headers

2. **Native OIDC SecurityPolicy** - For web browser SSO
   - **Templates NOT created** - needs `securitypolicy-oidc.yaml.j2` + `secret-oidc.sops.yaml.j2`
   - Session-based auth with cookies, login redirect flow
   - See [envoy-gateway-oidc-integration.md](./envoy-gateway-oidc-integration.md) Phase 1

---

## Document Update Log

| Date | Version | Changes |
| ---- | ------- | ------- |
| 2026-01-06 | 1.0.0 | Initial assessment (k8s-at-home patterns) |
| 2026-01-06 | 1.1.0 | Added GitOps components assessment |
| 2026-01-06 | 1.2.0 | Added Envoy Gateway assessment; refactored to remaining-work-only format |
| 2026-01-06 | 1.3.0 | Added Envoy Gateway examples analysis; updated source doc with current status |
| 2026-01-06 | 1.4.0 | Added OIDC integration analysis; clarified JWT vs OIDC SSO distinction |
