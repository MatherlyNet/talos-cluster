# Review Follow-Up Items - January 2026

**Created:** January 3, 2026
**Source:** Comprehensive Code Review Report
**Status:** Active tracking document

---

## Executive Summary

This document tracks remaining action items from the January 2026 comprehensive review. **Twelve high-priority items have been remediated; eight items remain pending for future implementation.**

**Completed Today (January 3, 2026):**
- Health probes for critical monitoring apps (#9)
- PodDisruptionBudgets for CoreDNS, cert-manager, Envoy Gateway (#13)
- Parallelized bootstrap operations (#14)
- SBOM generation for releases (#15)

---

## Remaining Action Items by Priority

### Critical - Immediate (CI/CD Security)

| # | Action | Effort | Impact | Status |
| --- | -------- | -------- | -------- | -------- |
| 3 | Add Trivy scanning to CI | 2h | HIGH | ✅ **IMPLEMENTED** |

**Implementation Details (Completed January 3, 2026):**

Added `security-scan` job to `.github/workflows/flux-local.yaml` with:
- **Filesystem scan**: Detects vulnerabilities in container images referenced in manifests
- **Config scan**: Identifies Kubernetes misconfigurations and security best practices
- **SARIF upload**: Results appear in GitHub Security tab
- **Severity filtering**: CRITICAL, HIGH (filesystem), CRITICAL, HIGH, MEDIUM (config)
- **Digest pinning**: Uses `aquasecurity/trivy-action@6e7b7d1fd3e4fef0c5fa8cce1229c54b2c9bd0d8` (v0.29.0)

---

### High Priority - Performance

| # | Action | Effort | Impact | Status |
| --- | -------- | -------- | -------- | -------- |
| 9 | Add health probes to critical apps | 4h | MEDIUM | ✅ **IMPLEMENTED** |
| 10 | Cache file reads in plugin.py | 1h | MEDIUM | ✅ **IMPLEMENTED** |

**Implementation Details for #9 (Completed January 3, 2026):**

Added readinessProbe and livenessProbe configurations to all critical monitoring apps:
- **VictoriaMetrics (vmsingle)**: `/health` on port 8429
- **VictoriaMetrics (vmagent)**: `/health` on port 8429
- **Grafana**: `/api/health` on port 3000
- **AlertManager**: `/-/ready` and `/-/healthy` on port 9093
- **Loki**: `/ready` on port 3100
- **Tempo**: `/ready` on port 3200
- **Alloy**: `/-/ready` and `/-/healthy` on port 12345

All probes configured with appropriate `initialDelaySeconds`, `periodSeconds`, and `timeoutSeconds`.

**Implementation Details for #10 (Completed January 3, 2026):**

Added `@lru_cache` decorators to `templates/scripts/plugin.py` with:
- **`_read_file_cached()`**: Caches text file reads (maxsize=8) for age.key, github-deploy.key, github-push-token.txt
- **`_read_json_cached()`**: Caches JSON file reads (maxsize=4) for cloudflare-tunnel.json
- **Functions refactored**: `age_key()`, `cloudflare_tunnel_id()`, `cloudflare_tunnel_secret()`, `github_deploy_key()`, `github_push_token()`
- **Expected improvement**: 20-30% faster template rendering during `task configure`

```python
from functools import lru_cache

@lru_cache(maxsize=8)
def _read_file_cached(file_path: str) -> str:
    """Read and cache file contents. Cached for performance during template rendering."""
    with open(file_path, "r") as file:
        return file.read().strip()

@lru_cache(maxsize=4)
def _read_json_cached(file_path: str) -> str:
    """Read and cache JSON file contents as string. Parsed by caller."""
    with open(file_path, "r") as file:
        return file.read()
```

---

### Medium Priority - Security & Resilience

| # | Action | Effort | Impact | Status |
| --- | -------- | -------- | -------- | ------- |
| 11 | Add CiliumNetworkPolicies | 4h | MEDIUM | Pending |
| 12 | Create disaster recovery runbook | 4h | MEDIUM | Pending |
| 13 | Add PodDisruptionBudgets | 3h | MEDIUM | ✅ **IMPLEMENTED** |
| 14 | Parallelize bootstrap operations | 4h | MEDIUM | ✅ **IMPLEMENTED** |
| 15 | Add SBOM generation to releases | 2h | MEDIUM | ✅ **IMPLEMENTED** |

**NetworkPolicy Priority:**
1. monitoring namespace (isolate observability stack)
2. flux-system namespace (protect GitOps controllers)
3. cert-manager namespace (protect PKI)

**Implementation Details for #13 (Completed January 3, 2026):**

Created PodDisruptionBudget templates for critical workloads:
- **CoreDNS**: `templates/config/kubernetes/apps/kube-system/coredns/app/pdb.yaml.j2` (minAvailable: 1)
- **cert-manager**: `templates/config/kubernetes/apps/cert-manager/cert-manager/app/pdb.yaml.j2` (minAvailable: 1)
- **Envoy Gateway**: `templates/config/kubernetes/apps/network/envoy-gateway/app/pdb.yaml.j2` (minAvailable: 1)

All PDBs ensure at least one pod remains available during voluntary disruptions (node drains, upgrades).

**Implementation Details for #14 (Completed January 3, 2026):**

Refactored `scripts/bootstrap-apps.sh` to use parallel execution:
- Added `run_parallel()` and `wait_parallel()` helper functions for background job management
- Restructured `main()` into 4 distinct phases:
  - Phase 1: Wait for nodes (sequential, required first)
  - Phase 2: Apply namespaces and secrets in parallel
  - Phase 3: Apply CRDs (depends on namespaces)
  - Phase 4: Sync Helm releases (depends on CRDs)
- Added timing measurement for performance visibility
- Expected improvement: 2-3x faster bootstrap for independent operations

**Implementation Details for #15 (Completed January 3, 2026):**

Updated `.github/workflows/release.yaml` to generate SBOMs:
- **SPDX format**: `sbom.spdx.json` for broad tooling compatibility
- **CycloneDX format**: `sbom.cyclonedx.json` for supply chain analysis
- **Tool**: `anchore/sbom-action@v0.17.8` with digest pinning
- **Artifacts**: Both SBOMs attached to GitHub releases
- **Permissions**: Added `id-token: write` for attestation support

---

### Low Priority - Advanced Security & Compliance

| # | Action | Effort | Notes |
| --- | -------- | -------- | ------- |
| 16 | Add Sigstore image signing | 4h | Requires cosign setup, policy controller |
| 17 | Add SLSA compliance | 4h | Build provenance attestation |
| 18 | Add SLO/SLI tracking | 6h | Integrate with VictoriaMetrics/Grafana |
| 19 | Add chaos engineering | 8h | Chaos Mesh or Litmus integration |
| 20 | Create video tutorials | 16h | Onboarding content |

---

## Implementation Roadmap

### Week 2-3 (Immediate)
- [x] Add Trivy scanning to CI (#3) - ✅ Completed January 3, 2026
- [x] Cache plugin.py file reads (#10) - ✅ Completed January 3, 2026
- [x] Add health probes to critical apps (#9) - ✅ Completed January 3, 2026
- [x] Add PodDisruptionBudgets (#13) - ✅ Completed January 3, 2026
- [x] Parallelize bootstrap operations (#14) - ✅ Completed January 3, 2026
- [x] Add SBOM generation (#15) - ✅ Completed January 3, 2026

### Month 1
- [ ] Create disaster recovery runbook (#12)

### Month 2
- [ ] Add CiliumNetworkPolicies (#11)

### Month 3+
- [ ] Sigstore image signing (#16)
- [ ] SLSA compliance (#17)
- [ ] SLO/SLI tracking (#18)
- [ ] Chaos engineering (#19)
- [ ] Video tutorials (#20)

---

## Dependencies & Prerequisites

### For Trivy Scanning (#3)
- GitHub Actions workflow access
- SARIF upload permissions

### For NetworkPolicies (#11)
- Cilium CNI already deployed
- CiliumNetworkPolicy CRD available

### For Sigstore (#16)
- cosign CLI
- Container registry with OCI support
- Policy controller (Kyverno or Gatekeeper)

### For Chaos Engineering (#19)
- Dedicated namespace for chaos tools
- RBAC permissions for fault injection

---

## Tracking

| Date | Action | Status |
| --- | -------- | -------- |
| 2026-01-03 | Initial document created | Active |
| 2026-01-03 | 7 items remediated from original 20 | Complete |
| 2026-01-03 | Added Trivy scanning to CI (#3) | Complete |
| 2026-01-03 | Added @lru_cache to plugin.py (#10) | Complete |
| 2026-01-03 | Added health probes to monitoring apps (#9) | Complete |
| 2026-01-03 | Added PodDisruptionBudgets (#13) | Complete |
| 2026-01-03 | Parallelized bootstrap operations (#14) | Complete |
| 2026-01-03 | Added SBOM generation to releases (#15) | Complete |

---

## Related Documents

- `docs/COMPREHENSIVE-REVIEW-JAN-2026.md` - Full review report with remediation status
- `docs/BEST_PRACTICES_AUDIT_2026.md` - Detailed best practices analysis
- `docs/CLI_REFERENCE.md` - Updated with infrastructure tasks
- `docs/TROUBLESHOOTING.md` - Diagnostic procedures

---

*This document should be reviewed weekly until all items are addressed.*
