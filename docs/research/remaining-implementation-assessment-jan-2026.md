# Remaining Implementation Assessment

> **Document Version:** 1.7.0
> **Assessment Date:** January 2026
> **Status:** Living Document
> **Sources:**
> - [k8s-at-home-remaining-implementation.md](../guides/k8s-at-home-remaining-implementation.md)
> - [gitops-components-implementation.md](../guides/gitops-components-implementation.md)
> - [envoy-gateway-observability-security.md](../guides/envoy-gateway-observability-security.md)
> - [envoy-gateway-examples-analysis.md](./envoy-gateway-examples-analysis.md)
> - [envoy-gateway-oidc-integration.md](./envoy-gateway-oidc-integration.md)
>
> **Implementation Guides:**
> - [VolSync with RustFS](../guides/volsync-rustfs-implementation.md)
> - [Talos Backup with RustFS](../guides/talos-backup-rustfs-implementation.md)
> - [JWT SecurityPolicy](../guides/jwt-securitypolicy-implementation.md)
> - [tuppr Verification](../guides/tuppr-verification-guide.md)
> - [Native OIDC SecurityPolicy](../guides/native-oidc-securitypolicy-implementation.md)
> - [OAuth2-Proxy ext_authz](../guides/oauth2-proxy-ext-authz-implementation.md)
> - [gRPC Routing](../guides/grpc-routing-implementation.md)
> - [Keycloak OIDC Provider](../guides/keycloak-implementation.md)
> - [CloudNativePG Operator](../guides/cnpg-implementation.md)

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
> **Implementation Guide:** [volsync-rustfs-implementation.md](../guides/volsync-rustfs-implementation.md)

**Status:** Templates do not exist. Variables defined in `cluster.yaml` but commented out.

**Required Work:**
1. Create `templates/config/kubernetes/apps/storage/volsync/` directory structure
2. Create template files per implementation guide:
   - `ks.yaml.j2` - Flux Kustomization
   - `app/kustomization.yaml.j2`
   - `app/helmrelease.yaml.j2`
   - `app/ocirepository.yaml.j2`
   - `app/secret.sops.yaml.j2` - Restic credentials for RustFS
3. Update `templates/config/kubernetes/apps/storage/kustomization.yaml.j2` to include VolSync conditional
4. Configure `volsync_*` variables in `cluster.yaml`
5. Create RustFS access key via Console UI for `volsync-backups` bucket

**Effort:** ~2 hours

---

### 2. Talos Backup - CONFIG INCOMPLETE

> Source: [gitops-components-implementation.md](../guides/gitops-components-implementation.md#12-talos-backup)
> **Implementation Guide:** [talos-backup-rustfs-implementation.md](../guides/talos-backup-rustfs-implementation.md)

**Status:** Templates complete. S3 configuration not set.

**cluster.yaml variables COMMENTED OUT:**
```yaml
# backup_s3_endpoint: ""
# backup_s3_bucket: ""
# backup_s3_access_key: ""
# backup_s3_secret_key: ""
# backup_age_public_key: ""
```

**Required Work (RustFS Backend - Recommended):**
1. Create RustFS access key via Console UI (port 9001)
2. Configure `backup_s3_endpoint: "http://rustfs.storage.svc.cluster.local:9000"`
3. Configure `backup_s3_bucket: "etcd-backups"`
4. Add `etcd-backups` to RustFS bucket setup job
5. Run `task configure` to encrypt secrets
6. Deploy via `task reconcile`
7. Test: `kubectl -n kube-system create job --from=cronjob/talos-backup test-backup`

**Alternative (Cloudflare R2 - External DR):**
- See implementation guide for R2 configuration if external backup storage preferred

**Effort:** ~1 hour

---

### 3. JWT SecurityPolicy (API Auth) - CONFIG INCOMPLETE

> Source: [envoy-gateway-observability-security.md](../guides/envoy-gateway-observability-security.md#phase-2-jwt-securitypolicy)
> **Implementation Guide:** [jwt-securitypolicy-implementation.md](../guides/jwt-securitypolicy-implementation.md)

**Status:** Templates complete (`securitypolicy-jwt.yaml.j2`). OIDC provider not configured.

**Use Case:** API/service-to-service authentication via Bearer tokens (stateless JWT validation).

**cluster.yaml variables COMMENTED OUT:**
```yaml
# oidc_provider_name: "keycloak"
# oidc_issuer_url: ""
# oidc_jwks_uri: ""
# oidc_additional_claims: []
```

**Required Work:**
1. Deploy Keycloak OIDC provider - see [Keycloak Implementation Guide](../guides/keycloak-implementation.md)
2. Create realm and configure token claims
3. Note JWKS URI endpoint
4. Configure `oidc_*` variables in `cluster.yaml`
5. Run `task configure`
6. Label HTTPRoutes with `security: jwt-protected`
7. Test with `curl -H "Authorization: Bearer $TOKEN"`

**Effort:** ~3-4 hours (with Keycloak guide)

---

### 4. tuppr - DEPLOYMENT VERIFICATION PENDING

> Source: [gitops-components-implementation.md](../guides/gitops-components-implementation.md#11-talos-upgrade-controller-tuppr)
> **Verification Guide:** [tuppr-verification-guide.md](../guides/tuppr-verification-guide.md)

**Status:** Templates complete. Configuration complete. Deployment needs verification.

**Verification Steps:**
1. Verify Talos API patch applied: `talosctl get machineconfig -n <node> -o yaml | grep kubernetesTalosAPIAccess`
2. Check `allowedRoles` includes `os:admin`
3. Check tuppr pods: `kubectl -n system-upgrade get pods`
4. Validate CRDs: `kubectl get crd | grep tuppr`
5. Validate CRs: `kubectl get talosupgrade,kubernetesupgrade`
6. Check health check CEL expressions evaluate correctly

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

| Item | Source Guide | Implementation Guide | Notes |
| ---- | ------------ | -------------------- | ----- |
| **Native OIDC SecurityPolicy** | envoy-gateway-oidc-integration | [native-oidc-securitypolicy-implementation.md](../guides/native-oidc-securitypolicy-implementation.md) | Web SSO (session-based) - templates documented |
| **OAuth2-Proxy ext_authz** | envoy-gateway-oidc-integration | [oauth2-proxy-ext-authz-implementation.md](../guides/oauth2-proxy-ext-authz-implementation.md) | Claims forwarding to backends |
| **gRPC Routing** | envoy-gateway-examples-analysis | [grpc-routing-implementation.md](../guides/grpc-routing-implementation.md) | Adopt when gRPC services deployed |
| Shared bjw-s Repository | k8s-at-home-remaining | - | Only for multiple bjw-s apps |
| ClusterSecretStore Templates | k8s-at-home-remaining | - | 1Password/Bitwarden/Vault |
| OTel Metrics Sink | envoy-gateway-examples-analysis | - | Unified observability (optional) |
| TCP/TLS Passthrough | envoy-gateway-examples-analysis | - | Adopt when needed |
| Merged Gateways | envoy-gateway-examples-analysis | - | Evaluate for resource optimization |

### OIDC Authentication Options (When Provider Available)

The project supports three OIDC authentication approaches:

1. **JWT SecurityPolicy** (Item #3 above) - For API/service-to-service auth
   - Template exists: `securitypolicy-jwt.yaml.j2`
   - Validates Bearer tokens, extracts claims to headers
   - **Guide:** [jwt-securitypolicy-implementation.md](../guides/jwt-securitypolicy-implementation.md)

2. **Native OIDC SecurityPolicy** - For web browser SSO
   - Template patterns documented in implementation guide
   - Session-based auth with cookies, login redirect flow
   - **Guide:** [native-oidc-securitypolicy-implementation.md](../guides/native-oidc-securitypolicy-implementation.md)

3. **OAuth2-Proxy ext_authz** - For advanced claims forwarding
   - Deploys OAuth2-Proxy with ext_authz filter
   - Forwards user info as X-Auth-Request-* headers
   - **Guide:** [oauth2-proxy-ext-authz-implementation.md](../guides/oauth2-proxy-ext-authz-implementation.md)

---

## Document Update Log

| Date | Version | Changes |
| ---- | ------- | ------- |
| 2026-01-06 | 1.0.0 | Initial assessment (k8s-at-home patterns) |
| 2026-01-06 | 1.1.0 | Added GitOps components assessment |
| 2026-01-06 | 1.2.0 | Added Envoy Gateway assessment; refactored to remaining-work-only format |
| 2026-01-06 | 1.3.0 | Added Envoy Gateway examples analysis; updated source doc with current status |
| 2026-01-06 | 1.4.0 | Added OIDC integration analysis; clarified JWT vs OIDC SSO distinction |
| 2026-01-06 | 1.5.0 | Added 7 new implementation guides: VolSync/RustFS, Talos Backup/RustFS, JWT SecurityPolicy, tuppr verification, Native OIDC, OAuth2-Proxy ext_authz, gRPC Routing |
| 2026-01-06 | 1.6.0 | Added Keycloak OIDC Provider implementation guide; updated JWT SecurityPolicy effort estimate |
| 2026-01-06 | 1.7.0 | Added CloudNativePG Operator implementation guide for shared PostgreSQL clusters |
| 2026-01-06 | 1.8.0 | Enhanced CNPG guide with pgvector extension support via Kubernetes ImageVolume |
