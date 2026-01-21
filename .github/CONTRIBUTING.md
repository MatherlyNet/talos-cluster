# Contributing to Talos Cluster

Thank you for your interest in contributing to this GitOps-driven Kubernetes cluster template! This document provides guidelines for contributing to the repository, with a focus on maintaining security and quality standards.

## Table of Contents

- [Getting Started](#getting-started)
- [GitHub Actions Security Guidelines](#github-actions-security-guidelines)
- [Workflow Development Guidelines](#workflow-development-guidelines)
- [Template Development](#template-development)
- [Testing Changes](#testing-changes)

---

## Getting Started

This repository uses a GitOps approach with Flux CD to manage a Kubernetes cluster running on Talos Linux. Before contributing:

1. **Read the documentation:**
   - `README.md` - Repository overview
   - `PROJECT_INDEX.md` - Complete project structure and context
   - `docs/ARCHITECTURE.md` - System architecture
   - `docs/CONFIGURATION.md` - Configuration reference

2. **Understand the workflow:**
   - Changes are made to Jinja2 templates in `templates/config/`
   - Run `task configure` to generate manifests
   - Commit both templates and generated manifests
   - Flux CD syncs changes to the cluster

3. **Set up your environment:**
   - Install required tools via mise: `mise install`
   - Initialize configuration: `task init`
   - See `docs/CLI_REFERENCE.md` for available commands

---

## GitHub Actions Security Guidelines

All GitHub Actions workflows **MUST** include explicit `permissions` blocks to adhere to the **principle of least privilege**. This prevents workflows from inheriting overly permissive repository/organization defaults.

### Why Explicit Permissions Matter

Without explicit permissions, workflows inherit repository/organization defaults which may include unnecessary write access. Organizations created before February 2023 default to `read-write` permissions, granting workflows more access than required.

**Security Benefits:**

- Reduces attack surface if workflow is compromised
- Prevents accidental modifications to repository resources
- Makes security audits straightforward
- Future-proofs against permission policy changes

### Required: Explicit Permissions Block

Every workflow MUST include a `permissions` block at either the root level or job level.

❌ **INCORRECT** - Missing permissions:

```yaml
name: "My Workflow"

jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
```

✅ **CORRECT** - Explicit permissions:

```yaml
name: "My Workflow"

permissions:
  contents: read

jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
```

### Standard Permission Patterns

Use these permission patterns based on your workflow's operations:

#### Read-Only Workflows (Testing, Validation, Linting)

```yaml
permissions:
  contents: read
```

**When to use:**

- Running tests
- Linting code
- Validating configuration
- Checking markdown links
- Security scanning (without SARIF upload)

**Examples:** `e2e.yaml`, `markdown-link-check.yaml`

---

#### PR Automation Workflows

```yaml
permissions:
  contents: read
  pull-requests: write
```

**When to use:**

- Posting comments on pull requests
- Adding/removing PR labels
- Requesting reviewers

**Examples:** `flux-local.yaml` (diff job), `labeler.yaml`

---

#### Issue/Label Management Workflows

```yaml
permissions:
  contents: read
  issues: write
```

**When to use:**

- Syncing repository labels
- Creating/closing issues
- Adding issue labels

**Examples:** `label-sync.yaml`

---

#### Security Scanning Workflows (with SARIF Upload)

```yaml
permissions:
  contents: read
  security-events: write
```

**When to use:**

- Uploading security scan results (Trivy, CodeQL, Semgrep, etc.)
- Publishing vulnerability findings to Security tab

**Examples:** `flux-local.yaml` (security-scan job)

---

#### Release Workflows

```yaml
permissions:
  contents: write       # Create releases and tags
  id-token: write       # OIDC authentication for attestation
  attestations: write   # Sign SBOMs with Sigstore
```

**When to use:**

- Creating GitHub releases
- Tagging versions
- Generating and signing SBOMs
- Publishing release artifacts

**Examples:** `release.yaml`

---

#### Repository Automation Workflows

```yaml
permissions:
  contents: write
  pull-requests: write
```

**When to use:**

- Committing generated files (manifest regeneration)
- Creating pull requests
- Automated dependency updates

**Examples:** `renovate-manifest-regen.yaml`

---

### Permission Scope Strategies

Choose the appropriate strategy based on your workflow's complexity:

#### Strategy 1: Root-Level Permissions (Simple Workflows)

Use when all jobs need the same permissions.

```yaml
name: "Simple Workflow"

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run lint
```

**Advantages:**

- Simple and clear
- Avoids repetition
- Easy to audit

**Use for:** Single-job workflows or multi-job workflows with uniform permissions

---

#### Strategy 2: Job-Level Permissions (Varied Needs)

Use when different jobs need different permissions.

```yaml
name: "Complex Workflow"

jobs:
  test:
    permissions:
      contents: read
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test

  comment:
    permissions:
      contents: read
      pull-requests: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        # Post comment on PR
```

**Advantages:**

- Each job has minimal required permissions
- More granular security control
- Clear permission requirements per job

**Use for:** Workflows where jobs perform different operations (read-only + write operations)

---

#### Strategy 3: Hybrid Permissions (Recommended for Complex Workflows)

Use root-level defaults with job-level overrides for special cases.

```yaml
name: "Hybrid Workflow"

permissions:
  contents: read  # Default for all jobs

jobs:
  validate:
    runs-on: ubuntu-latest
    # Inherits: contents: read
    steps:
      - uses: actions/checkout@v4
      - run: npm run validate

  security-scan:
    permissions:
      contents: read
      security-events: write  # Override: needs additional permission
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: trivy scan
      - uses: github/codeql-action/upload-sarif@v4
```

**Advantages:**

- Most jobs use minimal permissions (root-level)
- Special jobs explicitly override when needed
- Best balance of security and clarity

**Use for:** Workflows with many jobs where most need read-only but some need additional permissions

**Example:** `flux-local.yaml` uses this pattern

---

### Common Permissions Reference

| Permission | Level | Purpose |
|------------|-------|---------|
| `contents: read` | Minimal | Read repository code, files, and commits |
| `contents: write` | Elevated | Create/modify files, branches, tags, and releases |
| `pull-requests: read` | Minimal | Read PR details, comments, and reviews |
| `pull-requests: write` | Elevated | Create/modify PRs, add comments and labels |
| `issues: read` | Minimal | Read issue details and comments |
| `issues: write` | Elevated | Create/modify issues, add labels |
| `security-events: write` | Elevated | Upload SARIF files to Security tab |
| `id-token: write` | Special | OIDC authentication for external services |
| `attestations: write` | Special | Sign artifacts with Sigstore |
| `actions: read` | Special | Read workflow run status and artifacts |

### Permission Validation Checklist

Before committing a new workflow:

- [ ] Does the workflow include an explicit `permissions` block?
- [ ] Are the permissions the **minimum required** for the workflow's operations?
- [ ] If using write permissions, is there a clear justification?
- [ ] For multi-job workflows, are permissions appropriately scoped (root vs job-level)?
- [ ] Have you tested the workflow with the specified permissions?

### CodeQL Security Scanning

This repository uses GitHub's CodeQL security scanning to identify security issues, including missing explicit permissions in workflows. If you see an alert like:

```
Actions job or workflow does not limit the permissions of the GITHUB_TOKEN.
Consider setting an explicit permissions block.
```

This means your workflow is missing the required `permissions` block. Add appropriate permissions following the guidelines above.

---

## Workflow Development Guidelines

### Workflow Best Practices

1. **Pinning Actions to SHA Commits**
   - Always pin third-party actions to full commit SHAs (not tags)
   - Include the semantic version as a comment for readability

   ```yaml
   - uses: actions/checkout@8e8c483db84b4bee98b60c0593521ed34d9990e8 # v6.0.1
   ```

2. **Timeout Minutes**
   - Always specify `timeout-minutes` to prevent runaway jobs
   - Typical values: 5-15 minutes depending on job complexity

   ```yaml
   jobs:
     test:
       timeout-minutes: 10
   ```

3. **Concurrency Control**
   - Use concurrency groups to cancel outdated workflow runs

   ```yaml
   concurrency:
     group: ${{ github.workflow }}-${{ github.event.number || github.ref }}
     cancel-in-progress: true
   ```

4. **Conditional Execution**
   - Skip workflows for bot accounts or draft PRs when appropriate

   ```yaml
   jobs:
     review:
       if: |
         github.event.pull_request.draft == false &&
         github.event.pull_request.user.login != 'renovate[bot]'
   ```

5. **Path Filtering**
   - Use `paths` and `paths-ignore` to trigger workflows only when relevant files change

   ```yaml
   on:
     pull_request:
       paths:
         - 'kubernetes/**'
       paths-ignore:
         - '*.md'
         - 'docs/**'
   ```

### Testing Workflows Locally

Before pushing workflow changes:

1. **Validate YAML syntax:**

   ```bash
   yamllint .github/workflows/my-workflow.yaml
   ```

2. **Use `act` for local testing (optional):**

   ```bash
   act pull_request -W .github/workflows/my-workflow.yaml
   ```

3. **Test with `workflow_dispatch` trigger:**
   - Add `workflow_dispatch:` to `on:` section
   - Manually trigger from GitHub Actions tab
   - Remove after testing if not needed

---

## Template Development

When modifying Jinja2 templates:

### Template Conventions

1. **Use correct delimiters (makejinja):**
   - Variables: `#{ variable_name }#`
   - Blocks: `#% if condition %# ... #% endif %#`
   - Comments: `#| comment text #|` (note: both ends use `#|`)

2. **Always regenerate manifests:**

   ```bash
   task configure -y
   ```

3. **Commit both templates and generated manifests:**

   ```bash
   git add templates/config/
   git add kubernetes/
   git commit -m "feat: add new feature"
   ```

### Configuration Variables

- Add new variables to `cluster.yaml` schema
- Document in `docs/CONFIGURATION.md`
- Use sensible defaults in `templates/scripts/plugin.py`
- Test with both enabled and disabled states

---

## Testing Changes

### Required Tests

Before submitting a pull request:

1. **Template validation:**

   ```bash
   task configure -y
   ```

2. **Flux validation:**

   ```bash
   task flux:validate
   ```

3. **Local Flux test:**

   ```bash
   flux-local test --enable-helm --all-namespaces \
     --path kubernetes/flux/cluster -v
   ```

4. **Security scanning:**

   ```bash
   trivy config --severity CRITICAL,HIGH kubernetes/
   ```

### CI/CD Validation

All pull requests automatically run:

- E2E configuration tests (public and private configs)
- Flux validation and diff generation
- Security scanning (Trivy)
- Markdown link checking
- Automated labeling

Monitor the PR checks and address any failures before requesting review.

---

## References

### GitHub Documentation

- [Automatic Token Authentication](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication)
- [Permissions for the GITHUB_TOKEN](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication#permissions-for-the-github_token)
- [Security Hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions)

### Repository Documentation

- `docs/ARCHITECTURE.md` - System architecture
- `docs/CONFIGURATION.md` - Configuration reference
- `docs/OPERATIONS.md` - Operational procedures
- `docs/CLI_REFERENCE.md` - Task commands reference

### Community

- **Issues:** Use GitHub Issues for bug reports and feature requests
- **Security:** Report security issues via email (see `SECURITY.md`)

---

Thank you for contributing to this project! Following these guidelines helps maintain security, quality, and consistency across the repository.
