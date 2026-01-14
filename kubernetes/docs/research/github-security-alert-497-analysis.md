# GitHub Security Alert #497 - Analysis and Resolution Strategy

**Date:** 2026-01-14
**Alert URL:** https://github.com/MatherlyNet/talos-cluster/security/code-scanning/497
**Status:** Under Investigation
**Related Commits:** 897008d2 (CodeQL v4 migration), 48f95fe6 (workflow improvements)

## Executive Summary

GitHub security alert #497 was triggered following recent workflow changes, specifically the migration from CodeQL Action v3 to v4 for SARIF upload functionality. This document provides comprehensive analysis, root cause hypotheses, and resolution strategies.

## Context: Recent Workflow Changes

### Key Commits
- **897008d2** (Jan 11, 2026): "ci(workflows): add timeouts and update codeql-action to v4"
  - Updated `github/codeql-action/upload-sarif` from v3 to v4
  - Added timeout-minutes to all workflow jobs
  - Updated mise configuration for network resilience

- **48f95fe6** (Jan 11, 2026): "ci(github): add community health files and improve workflows"
  - Added community health files
  - General workflow improvements

### Current Workflow Configuration

**File:** `.github/workflows/flux-local.yaml`
**Security Scan Job** (lines 47-93):

```yaml
security-scan:
  name: Security Scan
  needs: pre-job
  runs-on: ubuntu-latest
  timeout-minutes: 10
  permissions:
    contents: read
    security-events: write  # ✅ Correct permission
  steps:
    - name: Run Trivy vulnerability scanner (filesystem)
      uses: aquasecurity/trivy-action@b6643a29fecd7f34b3597bc6acb0a98b03d33ff8 # 0.33.1
      with:
        scan-type: 'fs'
        scan-ref: 'kubernetes/'
        format: 'sarif'
        output: 'trivy-fs-results.sarif'
        severity: 'CRITICAL,HIGH'
        ignore-unfixed: true

    - name: Run Trivy vulnerability scanner (config)
      uses: aquasecurity/trivy-action@b6643a29fecd7f34b3597bc6acb0a98b03d33ff8 # 0.33.1
      with:
        scan-type: 'config'
        scan-ref: 'kubernetes/'
        format: 'sarif'
        output: 'trivy-config-results.sarif'
        severity: 'CRITICAL,HIGH,MEDIUM'
        ignore-unfixed: true

    - name: Upload Trivy scan results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@5d4e8d1aca955e8d8589aabd499c5cae939e33c7 # v4.31.9
      if: always()
      with:
        sarif_file: 'trivy-fs-results.sarif'
        category: 'trivy-filesystem'

    - name: Upload Trivy config scan results
      uses: github/codeql-action/upload-sarif@5d4e8d1aca955e8d8589aabd499c5cae939e33c7 # v4.31.9
      if: always()
      with:
        sarif_file: 'trivy-config-results.sarif'
        category: 'trivy-config'
```

## Root Cause Analysis

### Hypothesis 1: CodeQL Default Setup Conflict ⚠️ HIGH PROBABILITY

**Description:** GitHub's automatic CodeQL default setup may be enabled, which blocks manual SARIF uploads to prevent duplicate alerts.

**Evidence:**
- Repository SECURITY.md claims "CodeQL analysis runs on all PRs and pushes"
- No CodeQL workflow file exists in `.github/workflows/`
- This suggests GitHub's default setup is enabled
- Default setup blocks ALL SARIF uploads, even from non-CodeQL tools like Trivy

**Error Pattern:**
```
Upload with CodeQL results rejected due to 'default setup'
```

**Why This Matters:**
Despite using Trivy (not CodeQL), the `github/codeql-action/upload-sarif` action is a generic SARIF uploader. If GitHub's default CodeQL setup is enabled, it may block these uploads to prevent confusion from multiple scanning sources.

**Resolution:**
1. **Option A (Recommended):** Disable CodeQL default setup
   - Navigate to: Repository Settings → Security → Code scanning
   - Click "Disable CodeQL" from the dropdown menu
   - Rerun the workflow

2. **Option B:** Keep default setup, disable Trivy SARIF uploads
   - Remove or comment out the upload-sarif steps in flux-local.yaml
   - Rely solely on GitHub's default CodeQL scanning
   - **Trade-off:** Lose Trivy's container and config scanning capabilities

**Validation:**
```bash
# After applying fix, trigger workflow
git commit --allow-empty -m "test: trigger security scan"
git push

# Monitor workflow run
gh run list --workflow=flux-local.yaml
gh run view <run-id> --log
```

**References:**
- [Upload Rejected - Default Setup Enabled](https://docs.github.com/en/code-security/how-tos/scan-code-for-vulnerabilities/troubleshooting/troubleshooting-sarif-uploads/default-setup-enabled)
- [Troubleshooting SARIF Uploads](https://docs.github.com/en/code-security/code-scanning/troubleshooting-sarif-uploads)

---

### Hypothesis 2: CodeQL Action v4 Migration Issues ⚠️ MEDIUM PROBABILITY

**Description:** Breaking changes in CodeQL Action v4 may cause upload failures.

**Evidence:**
- v4 requires Node.js 24 runtime (GitHub-hosted runners have this)
- No input parameter changes for upload-sarif between v3 and v4
- Current pinned version: v4.31.9 (released recently)

**Known v4 Changes:**
- Runs on Node.js 24 runtime (was Node.js 20 in v3)
- Removed `add-snippets` input from analyze action (not used in upload-sarif)
- Minimum CodeQL bundle version: 2.17.6

**Resolution:**
The migration is straightforward and should not cause issues. However, verify:

```bash
# Check GitHub runner Node.js version (should be 24.x)
# This is automatic on GitHub-hosted runners

# Verify SARIF files are generated correctly
# Add debugging step to workflow:
- name: Validate SARIF files
  run: |
    echo "Filesystem scan results:"
    cat trivy-fs-results.sarif | jq '.version, .runs[0].tool.driver.name'
    echo "Config scan results:"
    cat trivy-config-results.sarif | jq '.version, .runs[0].tool.driver.name'
```

**Validation:**
SARIF files should show:
```json
{
  "version": "2.1.0",
  "runs": [{
    "tool": {
      "driver": {
        "name": "Trivy"
      }
    }
  }]
}
```

**References:**
- [CodeQL Action v4 Release Announcement](https://github.blog/changelog/2025-10-28-upcoming-deprecation-of-codeql-action-v3/)
- [CodeQL Action v4 Migration Issue](https://github.com/github/codeql-action/issues/3271)
- [CodeQL Action CHANGELOG](https://github.com/github/codeql-action/blob/main/CHANGELOG.md)

---

### Hypothesis 3: Permission or Authentication Issues ⚠️ LOW PROBABILITY

**Description:** Workflow lacks necessary permissions or GitHub token is invalid.

**Evidence:**
- Current permissions: `contents: read, security-events: write` ✅ CORRECT
- Uses automatic `GITHUB_TOKEN` (standard for GitHub Actions)

**Common Errors:**
```
Error: Resource not accessible by integration
Error: Insufficient permissions to upload SARIF
```

**Resolution:**
The current permissions are correct. If this is the issue:

1. Verify repository settings:
   - Settings → Actions → General → Workflow permissions
   - Should be: "Read and write permissions" OR "Read repository contents and packages permissions" with explicit `security-events: write`

2. Check if repository has security features enabled:
   - Settings → Security → Code scanning
   - Must be enabled for SARIF uploads

**Validation:**
```bash
# Check workflow run logs for permission errors
gh run view <run-id> --log | grep -i "permission\|access\|auth"
```

**References:**
- [GitHub Actions Permissions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication#permissions-for-the-github_token)
- [Troubleshooting: Resource Not Accessible](https://thomasthornton.cloud/2025/03/13/github-actions-fix-resource-not-accessible-by-integration/)

---

### Hypothesis 4: SARIF Format Validation Errors ⚠️ LOW PROBABILITY

**Description:** Generated SARIF files don't conform to SARIF 2.1.0 specification.

**Evidence:**
- Trivy generates SARIF 2.1.0 format by default
- Using stable Trivy version: 0.33.1

**Common Errors:**
```
Error: Invalid SARIF. JSON syntax error: ...
Error: SARIF validation failed: ...
```

**Resolution:**
Add SARIF validation step to workflow:

```yaml
- name: Validate SARIF format
  run: |
    # Install SARIF validator
    npm install -g @microsoft/sarif-multitool

    # Validate both SARIF files
    sarif-multitool validate trivy-fs-results.sarif
    sarif-multitool validate trivy-config-results.sarif
```

**Validation:**
```bash
# Locally validate SARIF files
cat trivy-fs-results.sarif | jq '.' > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
```

**References:**
- [SARIF 2.1.0 Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [Uploading SARIF Files](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)

---

### Hypothesis 5: Category Naming Conflicts ⚠️ LOW PROBABILITY

**Description:** Multiple uploads with same category name cause rejection.

**Evidence:**
- Two separate uploads with distinct categories:
  - `category: 'trivy-filesystem'`
  - `category: 'trivy-config'`
- Categories are unique ✅

**Common Error:**
```
Error: Aborting upload: only one run of the codeql/analyze or codeql/upload-sarif
actions is allowed per job per tool/category
```

**Resolution:**
If this occurs, ensure each SARIF upload has a unique category. Current configuration is correct.

**References:**
- [Multiple Upload Attempts Error](https://docs.github.com/en/code-security/code-scanning/troubleshooting-sarif-uploads#multiple-upload-attempts)

---

## Investigation Workflow

### Step 1: Access Alert Details

```bash
# Try accessing via GitHub CLI
gh api repos/MatherlyNet/talos-cluster/code-scanning/alerts/497

# Or via browser (requires authentication)
# Navigate to: https://github.com/MatherlyNet/talos-cluster/security/code-scanning/497
```

**Expected Information:**
- Alert severity (Critical, High, Medium, Low)
- Affected file path
- Vulnerability type/CWE
- Rule ID
- Description and remediation guidance

### Step 2: Check Workflow Run Status

```bash
# List recent workflow runs
gh run list --workflow=flux-local.yaml --limit 10

# View specific run details
gh run view <run-id>

# Download logs for analysis
gh run view <run-id> --log > workflow-logs.txt

# Search for errors in security-scan job
grep -A 10 "security-scan" workflow-logs.txt | grep -i "error\|fail\|reject"
```

### Step 3: Verify CodeQL Default Setup Status

```bash
# Check if default setup is enabled (requires admin access)
gh api repos/MatherlyNet/talos-cluster/code-scanning/default-setup

# Expected response if enabled:
# {
#   "state": "configured",
#   "languages": ["javascript", "python", ...],
#   ...
# }
```

### Step 4: Local Trivy Scan for Comparison

```bash
# Run same scans locally to see what would be reported
cd kubernetes/

# Filesystem scan
trivy fs --format sarif --output trivy-fs-results.sarif \
  --severity CRITICAL,HIGH --ignore-unfixed .

# Config scan
trivy config --format sarif --output trivy-config-results.sarif \
  --severity CRITICAL,HIGH,MEDIUM --ignore-unfixed .

# Review findings
cat trivy-fs-results.sarif | jq '.runs[0].results[] | {ruleId, level, message}'
cat trivy-config-results.sarif | jq '.runs[0].results[] | {ruleId, level, message}'
```

### Step 5: Test SARIF Upload Manually

```bash
# Upload SARIF file manually using gh CLI
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  repos/MatherlyNet/talos-cluster/code-scanning/sarifs \
  -f commit_sha="$(git rev-parse HEAD)" \
  -f ref="refs/heads/main" \
  -f sarif=@trivy-fs-results.sarif \
  -f tool_name="Trivy"
```

---

## Recommended Resolution Path

### Phase 1: Immediate Investigation (5-10 minutes)

1. **Access the alert:**
   ```bash
   gh api repos/MatherlyNet/talos-cluster/code-scanning/alerts/497
   ```

2. **Check workflow run status:**
   ```bash
   gh run list --workflow=flux-local.yaml --limit 5
   gh run view <latest-run-id> --log | grep -A 20 "security-scan"
   ```

3. **Determine alert type:**
   - Is it a **vulnerability finding** (Trivy detected an issue)?
   - Is it a **workflow failure** (upload-sarif failed)?
   - Is it a **configuration issue** (misconfigured SARIF)?

### Phase 2: Apply Most Likely Fix (10-15 minutes)

**If alert indicates "default setup" conflict:**

```bash
# Navigate to repository settings
# Settings → Security → Code scanning → Configure → Disable CodeQL

# Then rerun workflow
git commit --allow-empty -m "test: rerun security scan after CodeQL setup change"
git push
```

**If alert is a Trivy finding (vulnerability in Kubernetes manifests):**

1. Review the specific vulnerability details
2. Apply remediation (fix the misconfigured resource)
3. Regenerate manifests: `task configure -y`
4. Commit and push changes

**If alert is a workflow failure:**

Add debugging to `.github/workflows/flux-local.yaml`:

```yaml
- name: Debug SARIF upload
  if: always()
  run: |
    echo "=== SARIF File Validation ==="
    for file in trivy-*.sarif; do
      echo "Checking $file"
      jq -e '.version == "2.1.0"' "$file" && echo "✓ Valid version" || echo "✗ Invalid version"
      jq -e '.runs[0].tool.driver.name' "$file" || echo "✗ Missing tool name"
    done

    echo "=== File Sizes ==="
    ls -lh trivy-*.sarif

    echo "=== GitHub Context ==="
    echo "Repository: ${{ github.repository }}"
    echo "Ref: ${{ github.ref }}"
    echo "SHA: ${{ github.sha }}"
```

### Phase 3: Validation and Monitoring (5-10 minutes)

1. **Verify fix:**
   ```bash
   gh run list --workflow=flux-local.yaml --limit 1
   gh run view <run-id>
   ```

2. **Check security tab:**
   ```bash
   gh api repos/MatherlyNet/talos-cluster/code-scanning/alerts \
     --jq '.[] | select(.state == "open") | {number, rule_id, severity}'
   ```

3. **Monitor for new alerts:**
   - Ensure alert #497 is resolved or dismissed
   - Verify no new alerts are created

---

## Long-Term Improvements

### 1. Add SARIF Validation to Workflow

```yaml
- name: Install SARIF tools
  run: npm install -g @microsoft/sarif-multitool

- name: Validate SARIF files before upload
  run: |
    sarif-multitool validate trivy-fs-results.sarif
    sarif-multitool validate trivy-config-results.sarif
```

### 2. Add Workflow Notifications

```yaml
- name: Notify on SARIF upload failure
  if: failure()
  uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: '⚠️ Security scan SARIF upload failed. Check workflow logs for details.'
      })
```

### 3. Document CodeQL Setup Decision

Update `.github/SECURITY.md`:

```markdown
## Code Scanning Setup

This repository uses **manual SARIF uploads** for code scanning:

- **Trivy** for container and configuration scanning
- **CodeQL default setup** is DISABLED to allow manual SARIF uploads
- Scans run on every PR and push via `.github/workflows/flux-local.yaml`

To enable GitHub's default CodeQL setup, disable Trivy SARIF uploads first.
```

### 4. Add Local Scanning to Pre-commit Hooks

```bash
# .pre-commit-config.yaml (if using pre-commit framework)
- repo: local
  hooks:
    - id: trivy-config
      name: Trivy Config Scan
      entry: trivy config --exit-code 1 --severity CRITICAL,HIGH kubernetes/
      language: system
      pass_filenames: false
```

---

## Action Items

- [ ] **URGENT:** Access alert #497 to determine exact issue
- [ ] **HIGH:** Check if CodeQL default setup is enabled
- [ ] **HIGH:** Review recent workflow runs for upload-sarif errors
- [ ] **MEDIUM:** Add SARIF validation debugging to workflow
- [ ] **MEDIUM:** Document CodeQL setup decision in SECURITY.md
- [ ] **LOW:** Implement long-term improvements (SARIF validation, notifications)

---

## References

### Official Documentation
- [Troubleshooting SARIF Uploads](https://docs.github.com/en/code-security/code-scanning/troubleshooting-sarif-uploads)
- [Upload Rejected - Default Setup](https://docs.github.com/en/code-security/how-tos/scan-code-for-vulnerabilities/troubleshooting/troubleshooting-sarif-uploads/default-setup-enabled)
- [Uploading SARIF Files](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
- [CodeQL Action Repository](https://github.com/github/codeql-action)

### CodeQL Action v4
- [v4 Release Announcement](https://github.blog/changelog/2025-10-28-upcoming-deprecation-of-codeql-action-v3/)
- [v4 Migration Issue #3271](https://github.com/github/codeql-action/issues/3271)
- [CHANGELOG](https://github.com/github/codeql-action/blob/main/CHANGELOG.md)
- [Releases](https://github.com/github/codeql-action/releases)

### Common Issues
- [Resource Not Accessible by Integration](https://thomasthornton.cloud/2025/03/13/github-actions-fix-resource-not-accessible-by-integration/)
- [Multiple Upload Attempts Error](https://github.com/github/codeql-action/issues/2456)
- [Upload Timeouts Issue #2992](https://github.com/github/codeql-action/issues/2992)
- [Not Found Error Issue #2719](https://github.com/github/codeql-action/issues/2719)

### Tools
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [SARIF 2.1.0 Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [SARIF Multitool](https://github.com/microsoft/sarif-sdk)

---

## Appendix: Workflow Diff (v3 → v4)

```diff
--- a/.github/workflows/flux-local.yaml
+++ b/.github/workflows/flux-local.yaml
@@ -75,14 +75,14 @@ jobs:
          ignore-unfixed: true

       - name: Upload Trivy scan results to GitHub Security tab
-        uses: github/codeql-action/upload-sarif@v3
+        uses: github/codeql-action/upload-sarif@5d4e8d1aca955e8d8589aabd499c5cae939e33c7 # v4.31.9
         if: always()
         with:
           sarif_file: 'trivy-fs-results.sarif'
           category: 'trivy-filesystem'

       - name: Upload Trivy config scan results
-        uses: github/codeql-action/upload-sarif@v3
+        uses: github/codeql-action/upload-sarif@5d4e8d1aca955e8d8589aabd499c5cae939e33c7 # v4.31.9
         if: always()
         with:
           sarif_file: 'trivy-config-results.sarif'
```

**Key Changes:**
- Updated from floating `@v3` tag to pinned `@v4.31.9` SHA
- No input parameter changes required
- Action now runs on Node.js 24 runtime (automatic on GitHub runners)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-14
**Next Review:** After alert #497 resolution
