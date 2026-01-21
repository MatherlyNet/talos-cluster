# Pattern Documentation Changelog

All notable changes to pattern documentation will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and patterns follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning Scheme

Patterns use semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes in procedure (incompatible steps, major architecture changes)
- **MINOR**: New features, additional procedures, or enhanced guidance (backward compatible)
- **PATCH**: Bug fixes, typo corrections, clarifications (no procedure changes)

---

## [Unreleased]

### Added

- Mermaid diagrams for visual learners across all patterns
- Semantic versioning scheme for pattern evolution tracking
- This CHANGELOG for documenting pattern changes
- Automated markdown link checking via GitHub Actions CI/CD workflow

---

## Pattern: CNPG Password Rotation

### [1.1.0] - 2026-01-14

#### Added

- Mermaid sequence diagram showing password rotation flow
- Mermaid flowchart showing component interactions
- Visual representation of automation layers

#### Changed

- Enhanced architecture section with interactive diagrams

### [1.0.0] - 2026-01-14

#### Added

- Initial pattern extraction from component documentation
- Complete password rotation procedure with 6 verification steps
- Troubleshooting section with 3 common issues
- Component usage table for LiteLLM, Langfuse, Obot, Keycloak
- Best practices for security, operations, and automation
- Example workflow with timeline expectations

---

## Pattern: RustFS IAM Setup

### [1.1.0] - 2026-01-14

#### Added

- Mermaid sequence diagram for S3 access flow
- Mermaid flowchart for IAM setup workflow (9 steps)
- Mermaid graph showing policy scope model with bucket permissions
- Visual representation of Console UI workflow

#### Changed

- Enhanced architecture section with interactive diagrams
- Improved clarity of IAM policy evaluation flow

### [1.0.0] - 2026-01-14

#### Added

- Initial pattern extraction from 30+ duplicated procedures
- Complete Console UI procedure (6 steps)
- Component-specific policy examples for 5 components
- Troubleshooting section with 3 common IAM issues
- Security best practices (least privilege, rotation, audit)
- Policy templates for read-only and read-write access

---

## Pattern: Dragonfly ACL Configuration

### [1.1.0] - 2026-01-14

#### Added

- Mermaid sequence diagram showing multi-tenant isolation
- Mermaid graph showing ACL namespace model with user permissions
- Mermaid flowchart for ACL configuration flow (9 steps)
- Visual representation of key prefix isolation

#### Changed

- Enhanced architecture section with interactive diagrams
- Improved clarity of ACL enforcement mechanism

### [1.0.0] - 2026-01-14

#### Added

- Initial pattern extraction from 5-6 duplicated configurations
- Complete ACL secret format and syntax reference
- Key pattern and command category tables
- Testing procedures with 4 test scenarios
- Troubleshooting section with 3 common ACL issues
- Security best practices for multi-tenant isolation

---

## Pattern Index (README)

### [1.1.0] - 2026-01-14

#### Added

- Pattern versioning information
- Link to CHANGELOG.md

#### Changed

- Updated "Available Patterns" section with version references

### [1.0.0] - 2026-01-14

#### Added

- Initial pattern index creation
- Pattern selection guide with use case mapping
- Component usage matrix
- Contributing guidelines for new patterns
- Pattern template for consistency

---

## Guidelines for Pattern Updates

### When to Bump Version

**MAJOR (x.0.0):**

- Breaking changes to procedure steps (order changes, removed steps)
- Major architectural changes requiring different approach
- Incompatible configuration format changes
- Removal of supported components or features

**MINOR (x.y.0):**

- New procedures or alternative approaches (backward compatible)
- Additional troubleshooting scenarios
- Enhanced diagrams or documentation improvements
- New component examples
- Additional security best practices

**PATCH (x.y.z):**

- Typo corrections and grammar fixes
- Clarification of existing steps (no procedural changes)
- Updated version numbers for tested components
- Fixed broken links or formatting issues
- Minor wording improvements

### Changelog Entry Format

```markdown
### [Version] - YYYY-MM-DD

#### Added
- New features or sections

#### Changed
- Modifications to existing content

#### Deprecated
- Features marked for removal

#### Removed
- Deleted content

#### Fixed
- Bug fixes and corrections

#### Security
- Security-related changes
```

---

**Changelog Started:** January 14, 2026
**Maintainer:** matherlynet-talos-cluster project
**Update Frequency:** As patterns evolve with infrastructure changes
