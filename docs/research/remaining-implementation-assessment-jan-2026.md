# Remaining Implementation Assessment

> **Document Version:** 2.1.0
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
>
> **Shared Infrastructure (Deploy First):**
> - CloudNativePG → Keycloak (database dependency)
> - Keycloak → JWT SecurityPolicy, OIDC SecurityPolicy (OIDC provider dependency)

---

## Executive Summary

This document tracks **remaining work only**. Completed components are documented in their respective source guides with updated status.

### Quick Status

| Category | Remaining Items |
| -------- | --------------- |
| **Shared Infrastructure** | CloudNativePG (~2-3 hours), Keycloak (~3-4 hours) |
| **Templates Needed** | VolSync (~2 hours) |
| **Config Ready** | Talos Backup (~30 min IAM setup) |
| **Verified ✅** | tuppr (operational, January 6, 2026) |
| **Adopt When Needed** | gRPC Routing (~1-2 hours per service) |

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

### 2. Talos Backup - ✅ TEMPLATES COMPLETE, CONFIG READY

> Source: [gitops-components-implementation.md](../guides/gitops-components-implementation.md#12-talos-backup)
> **Implementation Guide:** [talos-backup-rustfs-implementation.md](../guides/talos-backup-rustfs-implementation.md)

**Status:** Templates enhanced (January 6, 2026). S3 configuration not set.

**Template Updates (Completed):**
- ✅ All talos-backup templates wrapped with `talos_backup_enabled` conditional
- ✅ HelmRelease supports internal RustFS (`S3_FORCE_PATH_STYLE`, `S3_USE_SSL`)
- ✅ Kustomization depends on RustFS when `backup_s3_internal` is true
- ✅ `backup_s3_internal` derived variable added to `plugin.py`
- ✅ RustFS bucket setup job creates `etcd-backups` bucket
- ✅ `cluster.sample.yaml` documents both RustFS and R2 options

**cluster.yaml variables (uncomment to enable):**
```yaml
# OPTION A: Internal RustFS
backup_s3_endpoint: "http://rustfs-svc.storage.svc.cluster.local:9000"
backup_s3_bucket: "etcd-backups"

# OPTION B: External Cloudflare R2
# backup_s3_endpoint: "https://<account-id>.r2.cloudflarestorage.com"
# backup_s3_bucket: "cluster-backups"

# Both options require:
backup_s3_access_key: ""  # Create via RustFS Console or R2 API token
backup_s3_secret_key: ""
backup_age_public_key: "" # From: cat age.key | grep "public key"
```

**Required Work (RustFS Backend):**
1. Create `backup-storage` policy in RustFS Console (see guide)
2. Create `backups` group with policy attached
3. Create `talos-backup` user in group
4. Generate access key and update cluster.yaml
5. Run `task configure` to encrypt secrets
6. Deploy via `task reconcile`
7. Test: `kubectl -n kube-system create job --from=cronjob/talos-backup test-backup`

**Effort:** ~30 minutes (IAM setup only)

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

### 4. tuppr - ✅ VERIFIED AND OPERATIONAL

> Source: [gitops-components-implementation.md](../guides/gitops-components-implementation.md#11-talos-upgrade-controller-tuppr)
> **Verification Guide:** [tuppr-verification-guide.md](../guides/tuppr-verification-guide.md)

**Status:** Fully verified and operational (January 6, 2026).

**Verification Results:**

| Check | Status | Details |
| ------- | -------- | --------- |
| Talos API patch | ✅ | `kubernetesTalosAPIAccess` enabled with `os:admin`, `os:etcd:backup` roles |
| tuppr pod | ✅ | Running in `system-upgrade` namespace |
| CRDs | ✅ | `talosupgrades.tuppr.home-operations.com`, `kubernetesupgrades.tuppr.home-operations.com` |
| TalosUpgrade CR | ✅ | Phase: Completed, Version: v1.12.0 |
| KubernetesUpgrade CR | ✅ | Phase: Completed, Version: v1.35.0 |
| Health checks | ✅ | All 6 nodes showing Ready=True |
| Logs | ✅ | No errors, reconciling successfully |

**Notes:**
- ServiceMonitor not created despite `enabled: true` - chart issue (non-blocking)
- Upgrade automation ready for next version bump in `cluster.yaml`

**Effort:** Completed

---

### 5. CloudNativePG Operator - TEMPLATES NEEDED

> **Implementation Guide:** [cnpg-implementation.md](../guides/cnpg-implementation.md)

**Status:** Templates documented in guide but not created. Shared infrastructure dependency for Keycloak.

**Use Case:** Production-grade PostgreSQL operator providing automated HA, backups, and monitoring for database-dependent applications (Keycloak, future apps).

**Key Features:**
- CNCF Incubating project with PostgreSQL 18 support
- Automated quorum-based failover (stable in CNPG 1.28)
- Barman Cloud backups to RustFS S3
- pgvector extension support via ImageVolume (K8s 1.35+)
- Single operator serves multiple database clusters

**Required Work:**
1. Create `templates/config/kubernetes/apps/cnpg-system/` directory structure:
   - `kustomization.yaml.j2`
   - `namespace.yaml.j2`
   - `cloudnative-pg/ks.yaml.j2`
   - `cloudnative-pg/app/kustomization.yaml.j2`
   - `cloudnative-pg/app/helmrepository.yaml.j2`
   - `cloudnative-pg/app/helmrelease.yaml.j2`
2. Add derived variables to `templates/scripts/plugin.py`:
   - `cnpg_enabled`, `cnpg_backup_enabled`, `cnpg_postgres_image`
   - `cnpg_pgvector_enabled`, `cnpg_pgvector_image` (optional)
3. Update `templates/config/kubernetes/apps/kustomization.yaml.j2` to include cnpg-system
4. Configure `cnpg_enabled: true` in `cluster.yaml`
5. (Optional) Create RustFS access key for CNPG backups

**cluster.yaml variables:**
```yaml
cnpg_enabled: false                    # Enable operator deployment
cnpg_postgres_image: "ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie"
cnpg_storage_class: ""                 # Defaults to storage_class
cnpg_backup_enabled: false             # Enable S3 backups to RustFS
cnpg_priority_class: "system-cluster-critical"
cnpg_control_plane_only: true          # Schedule operator on control-plane
```

**Effort:** ~2-3 hours

**Dependency Chain:** CloudNativePG → Keycloak → JWT/OIDC SecurityPolicy

---

### 6. Keycloak OIDC Provider - TEMPLATES NEEDED

> **Implementation Guide:** [keycloak-implementation.md](../guides/keycloak-implementation.md)

**Status:** Templates documented in guide but not created. Requires PostgreSQL (CloudNativePG or embedded).

**Use Case:** Self-hosted OIDC/OAuth2 provider enabling JWT SecurityPolicy (API auth) and OIDC SecurityPolicy (web SSO).

**Key Features:**
- Keycloak 26.5.0 with official Keycloak Operator (NOT Codecentric Helm)
- Two database modes: `embedded` (dev) or `cnpg` (production)
- CRD split pattern: operator Kustomization → instance Kustomization
- HTTPRoute for Gateway API integration
- Automatic JWKS/issuer URL derivation for SecurityPolicy

**Required Work:**
1. Create `templates/config/kubernetes/apps/identity/` directory structure:
   - `kustomization.yaml.j2`
   - `namespace.yaml.j2`
   - `keycloak/ks.yaml.j2` (two Kustomizations: operator + instance)
   - `keycloak/operator/kustomization.yaml.j2`
   - `keycloak/operator/keycloak-operator.yaml.j2` (ServiceAccount, RBAC, Deployment)
   - `keycloak/app/kustomization.yaml.j2`
   - `keycloak/app/keycloak-cr.yaml.j2`
   - `keycloak/app/secret.sops.yaml.j2`
   - `keycloak/app/httproute.yaml.j2`
   - `keycloak/app/postgres-statefulset.yaml.j2` (embedded mode only)
2. Add derived variables to `templates/scripts/plugin.py`:
   - `keycloak_enabled`, `keycloak_hostname`
   - `keycloak_issuer_url`, `keycloak_jwks_uri` (auto-derived)
3. Update `templates/config/kubernetes/apps/kustomization.yaml.j2` to include identity
4. Configure variables in `cluster.yaml`
5. Post-deploy: Create realm, client, and test user via Admin Console

**cluster.yaml variables:**
```yaml
keycloak_enabled: false
keycloak_subdomain: "auth"             # Creates auth.${cloudflare_domain}
keycloak_realm: "matherlynet"
keycloak_admin_password: ""            # SOPS-encrypted
keycloak_db_mode: "embedded"           # "embedded" or "cnpg"
keycloak_db_user: "keycloak"
keycloak_db_password: ""               # SOPS-encrypted
keycloak_replicas: 1
keycloak_operator_version: "26.5.0"
```

**Effort:** ~3-4 hours (including PostgreSQL setup and realm configuration)

**Dependency Chain:** (CloudNativePG if cnpg mode) → Keycloak → JWT/OIDC SecurityPolicy

---

### 7. gRPC Routing - ADOPT WHEN NEEDED

> **Implementation Guide:** [grpc-routing-implementation.md](../guides/grpc-routing-implementation.md)

**Status:** Pattern documented. Adopt when first gRPC service is deployed.

**Use Case:** Native gRPC traffic management via Gateway API GRPCRoute (GA since v1.1.0).

**Key Features:**
- Service/method-level routing matching
- Traffic splitting for canary deployments
- Request mirroring for shadow testing
- Header-based routing (gRPC metadata)
- JWT authentication works; OIDC (session-based) does NOT work for gRPC

**Required Work (When First gRPC Service Deployed):**
1. Add gRPC listener to internal Gateway:
   ```yaml
   - name: grpc
     protocol: HTTPS
     port: 443
     hostname: "grpc.${SECRET_DOMAIN}"
     allowedRoutes:
       kinds:
         - kind: GRPCRoute
   ```
2. Create GRPCRoute per service following template pattern
3. (Optional) Configure cluster-level variables

**cluster.yaml variables (optional):**
```yaml
grpc_gateway_enabled: false            # Enable gRPC listener on Gateway
grpc_hostname: "grpc.matherly.net"     # gRPC services hostname
grpc_default_port: 50051               # Default gRPC port
```

**Per-Service Template Pattern:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: <service>
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "grpc.${SECRET_DOMAIN}"
  rules:
    - matches:
        - method:
            service: "<package>.<Service>"
      backendRefs:
        - name: <service>
          port: 50051
```

**Effort:** ~1-2 hours per gRPC service

**Note:** Hostname uniqueness enforced between GRPCRoute and HTTPRoute - use dedicated gRPC hostname.

---

## Priority Order

### High Priority (Operations & Disaster Recovery)

1. **Talos Backup Configuration** (~1 hour) - Essential for DR

### Medium Priority (Shared Infrastructure)

1. **CloudNativePG Operator** (~2-3 hours) - Production PostgreSQL for apps
2. **Keycloak OIDC Provider** (~3-4 hours) - Enables authentication features
3. **VolSync Implementation** (~2 hours) - Only if PVC backups needed

### Low Priority (Adopt When Needed)

1. **JWT SecurityPolicy Configuration** - After Keycloak deployed
2. **gRPC Routing** - When first gRPC service deployed

### Completed ✅

1. **tuppr Deployment Verification** - Verified January 6, 2026

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
| 2026-01-06 | 1.9.0 | Added detailed sub-sections for CloudNativePG (#5), Keycloak (#6), and gRPC Routing (#7); updated Quick Status and Priority Order to reflect shared infrastructure dependencies |
| 2026-01-06 | 2.0.0 | tuppr deployment verified operational; section #4 updated with verification results table; added to "Completed ✅" in Priority Order |
| 2026-01-06 | 2.1.0 | Talos Backup templates enhanced: conditional wrapping, RustFS internal support, `backup_s3_internal` derived variable, etcd-backups bucket in setup job; section #2 updated to "TEMPLATES COMPLETE, CONFIG READY" |
