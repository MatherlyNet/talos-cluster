# GitHub Actions Workflow Audit

> **Audit Date:** January 2026
> **Repository:** matherlynet-talos-cluster
> **Purpose:** Review all GitHub Actions workflows for outdated components, security issues, and best practices

## Executive Summary

All GitHub Actions workflows in this project are **up-to-date** as of January 2026. No critical updates are required. The project uses SHA-pinned references for **all** GitHub Actions (security best practice) and current versions of all components.

### Key Findings

| Status | Category | Finding |
| -------- | ---------- | --------- |
| :white_check_mark: | Versions | All actions at latest stable versions |
| :white_check_mark: | Security | SHA-pinned references used throughout |
| :white_check_mark: | Runtime | Node.js 20+ runtimes in use |
| :information_source: | Historical | tj-actions/changed-files had March 2025 incident (now patched) |

---

## Workflow Inventory

| Workflow | Purpose | Trigger |
| ---------- | ---------- | --------- |
| `e2e.yaml` | End-to-end testing with template configuration | `workflow_dispatch`, `pull_request` |
| `flux-local.yaml` | Flux manifest testing and diff | `pull_request` |
| `label-sync.yaml` | Sync labels from `.github/labels.yaml` | `workflow_dispatch`, `push` to main |
| `labeler.yaml` | Auto-label PRs based on paths | `pull_request_target` |
| `release.yaml` | Automated releases | `workflow_dispatch` |

---

## Component Version Analysis

### GitHub Actions

| Action | Project Version | Latest Version | Status | Notes |
| -------- | ---------------- | ---------------- | -------- | ------- |
| `actions/checkout` | v6.0.1 (SHA pinned) | v6.0.1 | :white_check_mark: Current | Node 20 runtime |
| `actions/labeler` | v6.0.1 (SHA pinned) | v6.0.1 | :white_check_mark: Current | Node 24 runtime |
| `actions/github-script` | v8.0.0 (SHA pinned) | v8.0.0 | :white_check_mark: Current | Node 20 runtime |
| `jdx/mise-action` | v3.5.1 (SHA pinned) | v3.5.1 | :white_check_mark: Current | - |
| `tj-actions/changed-files` | v47.0.1 (SHA pinned) | v47.0.1 | :white_check_mark: Current | Post-security-fix version |
| `mshick/add-pr-comment` | v2.8.2 (SHA pinned) | v2.8.2 | :white_check_mark: Current | Node 20 runtime (Feb 2025) |
| `EndBug/label-sync` | v2.3.3 (SHA pinned) | v2.3.3 | :white_check_mark: Current | - |
| `ncipollo/release-action` | v1.20.0 (SHA pinned) | v1.20.0 | :white_check_mark: Current | - |

### Container Images

| Image | Project Version | Latest Version | Status | Notes |
| ------- | ----------------- | ---------------- | -------- | ------- |
| `ghcr.io/allenporter/flux-local` | v8.1.0 (SHA pinned) | v8.1.0 | :white_check_mark: Current | Used in e2e and flux-local |

---

## Security Analysis

### SHA Pinning (Best Practice)

The project correctly uses SHA-pinned references for **all** GitHub Actions, which protects against:

- Tag hijacking attacks
- Supply chain compromises via tag modification

**All Actions Are SHA-Pinned:**

```yaml
# Core actions
actions/checkout@8e8c483db84b4bee98b60c0593521ed34d9990e8       # v6.0.1
actions/labeler@634933edcd8ababfe52f92936142cc22ac488b1b        # v6.0.1
actions/github-script@ed597411d8f924073f98dfc5c65a23a2325f34cd  # v8.0.0

# Third-party actions
jdx/mise-action@146a28175021df8ca24f8ee1828cc2a60f980bd5        # v3.5.1
tj-actions/changed-files@e0021407031f5be11a464abee9a0776171c79891  # v47.0.1
mshick/add-pr-comment@b8f338c590a895d50bcbfa6c5859251edc8952fc  # v2.8.2
EndBug/label-sync@52074158190acb45f3077f9099fea818aa43f97a      # v2.3.3
ncipollo/release-action@b7eabc95ff50cbeeedec83973935c8f306dfcd0b # v1.20.0
```

**Container Images:**

```yaml
# e2e.yaml - SHA-pinned (excellent)
docker://ghcr.io/allenporter/flux-local:v8.1.0@sha256:37c3c4309a351830b04f93c323adfcb0e28c368001818cd819cbce3e08828261

# flux-local.yaml - Tag only (acceptable, could improve)
docker://ghcr.io/allenporter/flux-local:v8.1.0
```

:information_source: **Note:** The flux-local container image is SHA-pinned in `e2e.yaml` but uses only the tag in `flux-local.yaml`. Consider adding SHA pinning for consistency.

### Historical Security Incident: tj-actions/changed-files

**Date:** March 2025
**Severity:** High (supply chain attack)
**Impact on this project:** None (already using post-fix version)

**Summary:** The tj-actions/changed-files action was compromised in March 2025 through a supply chain attack affecting versions prior to the security fix. The action has since been patched and is now maintained with enhanced security measures.

**Current Status:** The project uses v47.0.1 with SHA pinning, which is the patched and secure version.

**Recommendation:** Continue using SHA-pinned references to protect against future incidents.

---

## Workflow-Specific Analysis

### e2e.yaml

**Purpose:** Runs end-to-end tests by configuring the cluster template with test configs

**Components:**

- `actions/checkout@v6.0.1` (SHA pinned) :white_check_mark:
- `jdx/mise-action@v3.5.1` (SHA pinned) :white_check_mark:
- `flux-local:v8.1.0` (SHA pinned) :white_check_mark:

**Configuration:**

- Configured to run on `MatherlyNet/talos-cluster` repository
- Uses matrix strategy for `public` and `private` test configs
- Proper concurrency control with cancel-in-progress

### flux-local.yaml

**Purpose:** Tests Flux manifests and generates diffs for PRs

**Components:**

- `actions/checkout@v6.0.1` (SHA pinned) :white_check_mark:
- `tj-actions/changed-files@v47.0.1` (SHA pinned) :white_check_mark:
- `mshick/add-pr-comment@v2.8.2` (SHA pinned) :white_check_mark:
- `flux-local:v8.1.0` :white_check_mark:

**Notable Patterns:**

- Pre-job optimization to skip if no kubernetes/ changes
- Matrix strategy for helmrelease/kustomization diffs
- Proper permissions scoped to minimum required

### label-sync.yaml

**Purpose:** Synchronizes GitHub labels from configuration file

**Components:**

- `actions/checkout@v6.0.1` (SHA pinned) :white_check_mark:
- `EndBug/label-sync@v2.3.3` (SHA pinned) :white_check_mark:

### labeler.yaml

**Purpose:** Automatically labels PRs based on changed file paths

**Components:**

- `actions/labeler@v6.0.1` (SHA pinned) :white_check_mark:

**Note:** Uses `pull_request_target` trigger (runs in context of base branch for security)

### release.yaml

**Purpose:** Creates GitHub releases

**Components:**

- `actions/github-script@v8.0.0` (SHA pinned) :white_check_mark:
- `ncipollo/release-action@v1.20.0` (SHA pinned) :white_check_mark:

---

## Node.js Runtime Status

GitHub Actions is transitioning runtime versions. Current status:

| Runtime | Status | Actions Using |
| --------- | -------- | --------------- |
| Node 16 | :x: Deprecated | None in project |
| Node 20 | :white_check_mark: Current LTS | Most actions |
| Node 24 | :new: Newest | `actions/labeler` |

All actions in this project use Node 20 or newer runtimes.

---

## Recommendations

### No Immediate Actions Required

All components are current and following security best practices. The project demonstrates excellent security posture with 100% SHA-pinned GitHub Actions.

### Future Maintenance

1. **Monitor tj-actions/changed-files** - Given the March 2025 incident, continue monitoring this action for security advisories

2. **Periodic Audits** - Run this audit quarterly to catch any new vulnerabilities

3. **Dependabot/Renovate** - Consider enabling automated dependency updates for GitHub Actions

### Optional Improvement

**SHA-pin flux-local container in flux-local.yaml:**

The `flux-local` container image is SHA-pinned in `e2e.yaml` but uses only the tag in `flux-local.yaml`. For consistency:

```yaml
# Current (flux-local.yaml)
uses: docker://ghcr.io/allenporter/flux-local:v8.1.0

# Recommended (match e2e.yaml pattern)
uses: docker://ghcr.io/allenporter/flux-local:v8.1.0@sha256:37c3c4309a351830b04f93c323adfcb0e28c368001818cd819cbce3e08828261
```

---

## Audit Methodology

1. **Workflow Identification** - Cataloged all `.github/workflows/*.yaml` files
2. **Component Extraction** - Identified all `uses:` references and container images
3. **Version Research** - Checked GitHub releases and container registries for current versions
4. **Security Review** - Researched CVEs, security advisories, and supply chain incidents
5. **Runtime Analysis** - Verified Node.js runtime versions for deprecated runtimes

---

## References

- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [tj-actions/changed-files Repository](https://github.com/tj-actions/changed-files)
- [flux-local Documentation](https://github.com/allenporter/flux-local)
- [actions/checkout Releases](https://github.com/actions/checkout/releases)
- [Node.js Release Schedule](https://nodejs.org/en/about/releases/)

---

*Audit conducted: January 2026*
