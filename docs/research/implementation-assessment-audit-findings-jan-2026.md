# Implementation Assessment Audit Findings

> **Audit Date:** January 7, 2026
> **Document Audited:** `docs/research/remaining-implementation-assessment-jan-2026.md` (v2.6.0)
> **Auditor:** Claude AI Research Agent

---

## Executive Summary

The `remaining-implementation-assessment-jan-2026.md` document is **significantly outdated**. Multiple components listed as "Templates Complete" or "Ready for Deployment" have since been **deployed and are operational**. This audit identifies all discrepancies and provides recommendations for document updates and archival.

### Summary of Findings

| Component | Document Status | Actual Status | Action Required |
| --------- | --------------- | ------------- | --------------- |
| **VolSync** | Templates Needed | Templates do NOT exist | Accurate |
| **Talos Backup** | Deployed and Operational | Deployed and Operational | Accurate |
| **JWT SecurityPolicy** | Config Incomplete | **DEPLOYED** (`jwt-auth` SecurityPolicy active) | Update document |
| **tuppr** | Verified and Operational | Verified and Operational | Accurate |
| **CloudNativePG** | Deployed and Operational | Deployed + **Keycloak PostgreSQL cluster running** | Update document |
| **Keycloak** | Templates Complete (Ready for Deployment) | **DEPLOYED** (keycloak-0 running, realm imported) | Update document |
| **OIDC SSO** | Not documented | **DEPLOYED** (`oidc-sso` SecurityPolicy active) | Add to document |
| **gRPC Routing** | Adopt When Needed | Not implemented | Accurate |

---

## Detailed Findings

### 1. JWT SecurityPolicy - STATUS DISCREPANCY

**Document states:** "CONFIG INCOMPLETE - OIDC provider not configured"

**Actual status:** **DEPLOYED AND OPERATIONAL**

Evidence:
```bash
$ kubectl get securitypolicy -n network jwt-auth
NAME       AGE
jwt-auth   13h
```

The SecurityPolicy is configured with:
- Issuer: `https://sso.matherly.net/realms/matherlynet`
- JWKS URI: `https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs`
- Claims forwarded: sub, email, groups, preferred_username, realm_access.roles, resource_access.envoy-gateway.roles

**Recommendation:** Update section #3 to "DEPLOYED AND OPERATIONAL" with verification results.

---

### 2. Keycloak OIDC Provider - STATUS DISCREPANCY

**Document states:** "Templates Complete (Ready for Deployment)"

**Actual status:** **DEPLOYED AND OPERATIONAL**

Evidence:
```bash
$ kubectl get pods -n identity
NAME                                 READY   STATUS      RESTARTS      AGE
keycloak-0                           1/1     Running     2 (95m ago)   96m
keycloak-operator-7f984b684c-6fz6k   1/1     Running     0             96m
keycloak-postgres-1                  1/1     Running     0             96m
matherlynet-realm-n8n9j              0/1     Completed   0             95m

$ kubectl get keycloak -n identity
NAME       AGE
keycloak   96m
```

Configuration in `cluster.yaml`:
```yaml
keycloak_enabled: true
keycloak_subdomain: "sso"  # Creates sso.matherly.net
keycloak_db_mode: "cnpg"   # Using CloudNativePG backend
keycloak_monitoring_enabled: true
google_idp_enabled: true   # Social login enabled
```

**Additional finding:** CNPG PostgreSQL cluster (`keycloak-postgres`) is running for Keycloak.

**Recommendation:** Update section #6 to "DEPLOYED AND OPERATIONAL" with full verification results.

---

### 3. OIDC SSO SecurityPolicy - NEW CAPABILITY NOT DOCUMENTED

**Document status:** Not mentioned in assessment

**Actual status:** **DEPLOYED AND OPERATIONAL**

Evidence:
```bash
$ kubectl get securitypolicy -n network oidc-sso
NAME       AGE
oidc-sso   11h

$ kubectl get httproutes -A -l security=oidc-protected
NAMESPACE   NAME            AGE
network     grafana         ...
network     hubble-ui       ...
network     rustfs-console  ...
```

Configuration in `cluster.yaml`:
```yaml
oidc_sso_enabled: true
oidc_client_id: "envoy-gateway"
oidc_client_secret: "***" # Configured
```

**Recommendation:** Add new section documenting OIDC SSO SecurityPolicy as deployed capability.

---

### 4. CloudNativePG - UPDATE NEEDED

**Document states:** "PostgreSQL Clusters: None deployed yet (ready for Keycloak)"

**Actual status:** **Keycloak PostgreSQL cluster is running**

Evidence:
```bash
$ kubectl get clusters.postgresql.cnpg.io -A
NAMESPACE   NAME                AGE   INSTANCES   READY   STATUS                     PRIMARY
identity    keycloak-postgres   96m   1           1       Cluster in healthy state   keycloak-postgres-1
```

**Recommendation:** Update section #5 verification table to show Keycloak PostgreSQL cluster as deployed.

---

## Implementation Guides - Archival Recommendations

Based on the audit, the following guides should be moved to `docs/guides/completed/`:

### Already Completed - Ready for Archive

1. **`keycloak-implementation.md`** - Keycloak is deployed and operational
2. **`jwt-securitypolicy-implementation.md`** - JWT SecurityPolicy is deployed
3. **`cnpg-implementation.md`** - CNPG operator deployed, Keycloak cluster running

### Already in Completed Directory (Correct)

1. **`native-oidc-securitypolicy-implementation.md`** - Already archived

### Research Documents - Ready for Archive

The following research documents in `docs/research/archive/completed/` are correctly archived:
- `envoy-gateway-keycloak-oidc-integration-jan-2026.md`
- `envoy-gateway-oidc-integration.md`
- `keycloak-social-identity-providers-integration-jan-2026.md`
- `oidc-keycloak-implementation-review-jan-2026.md`
- `rustfs-otlp-metrics-alloy-integration-jan-2026.md`
- `rustfs-shared-storage-loki-simplescalable-jan-2026.md`

### Research Documents - Active

- `grafana-sso-authentication-integration-jan-2026.md` - New research, NOT yet implemented

---

## Updated Priority Order

Based on the audit, here is the corrected priority order:

### Completed (Verified Operational)

1. **Talos Backup** - CronJob running, backups scheduled every 6 hours
2. **tuppr** - Upgrade controller operational, v1.12.0/v1.35.0 deployed
3. **CloudNativePG Operator** - Deployed, Keycloak PostgreSQL cluster healthy
4. **Keycloak OIDC Provider** - Deployed, realm imported, Google IdP enabled
5. **JWT SecurityPolicy** - Deployed, claims forwarding configured
6. **OIDC SSO SecurityPolicy** - Deployed, protecting Grafana/Hubble/RustFS

### Templates Needed

1. **VolSync** (~2 hours) - PVC backup templates do not exist

### Adopt When Needed

1. **gRPC Routing** - Pattern documented, no services require it yet

### In Progress (Research Phase)

1. **Grafana Native SSO** - Research complete, implementation not started

---

## Document Recommendations

### 1. Update `remaining-implementation-assessment-jan-2026.md`

The document should be updated to version 2.7.0 with:

1. **Section #3 (JWT SecurityPolicy):** Change status to "DEPLOYED AND OPERATIONAL"
2. **Section #5 (CloudNativePG):** Update PostgreSQL Clusters row to show `keycloak-postgres` running
3. **Section #6 (Keycloak):** Change status to "DEPLOYED AND OPERATIONAL"
4. **Add Section #8:** Document OIDC SSO SecurityPolicy as deployed capability
5. **Update Quick Status table:** Reflect current deployed state
6. **Update Priority Order:** Move items to "Completed" section

### 2. Archive Implementation Guides

Move these guides to `docs/guides/completed/`:
- `keycloak-implementation.md`
- `jwt-securitypolicy-implementation.md`
- `cnpg-implementation.md`

Each guide should have a completion header added:
```markdown
> **STATUS:** Implementation Complete
> **Deployed:** January 7, 2026
> **Verification:** All components operational
```

### 3. Add OIDC SSO Documentation

Create or update documentation to cover the OIDC SSO SecurityPolicy:
- Configuration variables (`oidc_sso_enabled`, `oidc_client_*`)
- HTTPRoute label (`security: oidc-protected`)
- Protected applications (Grafana, Hubble UI, RustFS Console)

---

## New Opportunities Identified

### 1. Grafana Native SSO Enhancement

The `grafana-sso-authentication-integration-jan-2026.md` research document proposes three approaches for enhanced Grafana SSO. The recommended approach (Option 3: Grafana Native OAuth) would provide:
- Full RBAC support with role mapping from Keycloak
- Groups/teams mapping capability
- Independent session management

**Current state:** Grafana is OIDC-protected at the gateway level (Option 4), but lacks Grafana-native RBAC.

**Recommendation:** Consider implementing Option 3 for enhanced Grafana RBAC if role-based dashboard access is needed.

### 2. CNPG Backup Enablement

CNPG backup infrastructure is templated but not enabled:
```yaml
cnpg_backup_enabled: false  # Currently disabled
```

RustFS S3 credentials for CNPG backups need to be created and configured.

**Recommendation:** Enable CNPG backups via RustFS for production database resilience.

### 3. Additional OIDC-Protected Applications

The following applications could benefit from OIDC protection:
- AlertManager (if exposed externally)
- Tempo Query UI (if deployed)
- Any future internal dashboards

**Pattern:** Add `security: oidc-protected` label to HTTPRoute.

---

## Conclusion

The `remaining-implementation-assessment-jan-2026.md` document requires significant updates to reflect the current deployed state. The cluster has progressed substantially since the document's last update (v2.6.0), with Keycloak, JWT SecurityPolicy, and OIDC SSO SecurityPolicy all deployed and operational.

**Immediate Actions:**
1. Update assessment document to v2.7.0
2. Archive completed implementation guides
3. Add completion headers to guide documents

**Future Considerations:**
1. Implement Grafana Native OAuth (Option 3) for enhanced RBAC
2. Enable CNPG backups to RustFS
3. Document OIDC SSO pattern for future applications
