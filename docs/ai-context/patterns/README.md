# AI Context Patterns

**Purpose:** Reusable implementation patterns for common infrastructure procedures
**Last Updated:** January 14, 2026
**Versioning:** Patterns follow [Semantic Versioning](https://semver.org/) - see [CHANGELOG.md](./CHANGELOG.md)

---

## Available Patterns

### 1. [CNPG Password Rotation](./cnpg-password-rotation.md) `v1.1.0`

**Pattern:** Managed Role Password Rotation with Automatic Sync
**Use Case:** Rotate PostgreSQL passwords for applications using CloudNativePG
**Components:** CloudNativePG Cluster, Application Pods, Reloader

**When to Use:**

- Quarterly password rotation for database credentials
- Troubleshooting authentication errors after credential changes
- Setting up new CloudNativePG-backed applications

**Key Features:**

- ✅ Zero-downtime rotation via managed roles
- ✅ Automatic sync from secrets to PostgreSQL
- ✅ Graceful pod restart via Reloader

---

### 2. [RustFS IAM Setup](./rustfs-iam-setup.md) `v1.1.0`

**Pattern:** S3-Compatible Storage Access with Least Privilege IAM
**Use Case:** Configure service accounts for applications using RustFS object storage
**Components:** RustFS (S3-compatible), Application Pods

**When to Use:**

- Configuring S3 storage for new applications (LiteLLM, Langfuse, Obot, Loki)
- Troubleshooting "Access Denied" or S3 authentication errors
- Implementing least-privilege storage policies

**Key Features:**

- ✅ Console UI-based IAM management (no CLI)
- ✅ Scoped policies per application/bucket
- ✅ Component-specific policy examples

---

### 3. [Dragonfly ACL Configuration](./dragonfly-acl-configuration.md) `v1.1.0`

**Pattern:** Multi-Tenant Redis-Compatible Cache with ACL Isolation
**Use Case:** Configure isolated access for multiple applications sharing Dragonfly cache
**Components:** Dragonfly Operator, Dragonfly Instance

**When to Use:**

- Setting up shared cache for multiple applications
- Troubleshooting Redis authentication or permission errors
- Implementing key namespace isolation

**Key Features:**

- ✅ Key prefix-based namespace separation
- ✅ Redis ACL compatible
- ✅ Operator-managed declarative configuration

---

## Pattern Selection Guide

### I need to

**...rotate database passwords:**
→ [CNPG Password Rotation](./cnpg-password-rotation.md)

**...configure S3/object storage access:**
→ [RustFS IAM Setup](./rustfs-iam-setup.md)

**...set up Redis/cache access:**
→ [Dragonfly ACL Configuration](./dragonfly-acl-configuration.md)

**...troubleshoot authentication errors:**

- Database auth → [CNPG Password Rotation](./cnpg-password-rotation.md) (Troubleshooting section)
- S3 auth → [RustFS IAM Setup](./rustfs-iam-setup.md) (Troubleshooting section)
- Redis auth → [Dragonfly ACL Configuration](./dragonfly-acl-configuration.md) (Troubleshooting section)

---

## Using Patterns

### Pattern Structure

Each pattern document includes:

1. **Overview**: What the pattern is and key features
2. **Architecture**: Visual diagram of components and flow
3. **Prerequisites**: Required configuration before using pattern
4. **Procedure**: Step-by-step implementation guide
5. **Troubleshooting**: Common issues and resolutions
6. **Examples**: Real-world usage for cluster components
7. **Best Practices**: Security and operational recommendations

### Integration with Component Docs

Component documentation (litellm.md, langfuse.md, etc.) **references** these patterns instead of duplicating procedures. This provides:

- ✅ **Single Source of Truth**: Updates apply everywhere
- ✅ **Consistent Procedures**: Same steps across all components
- ✅ **Easier Maintenance**: Edit patterns once, not in every doc
- ✅ **Faster Context Loading**: Smaller component docs

---

## Components Using Patterns

### CNPG Password Rotation

- [LiteLLM](../litellm.md#postgresql-database) - ai-system namespace
- [Langfuse](../langfuse.md#postgresql-database-cnpg) - ai-system namespace
- [Obot](../obot.md#database-cloudnativepg-with-pgvector) - ai-system namespace

### RustFS IAM Setup

- [LiteLLM](../litellm.md#s3-storage) - Cache + logs
- [Langfuse](../langfuse.md#s3-storage-rustfs) - Events + media + exports
- [Obot](../obot.md#workspace-provider-configuration) - Workspaces
- [Dragonfly](../dragonfly.md#rustfs-backup) - PostgreSQL backups (optional)
- [Configuration Variables](../configuration-variables.md#rustfs) - Core config

### Dragonfly ACL Configuration

- [LiteLLM](../litellm.md#dragonfly-cache-shared) - Caching backend
- [Langfuse](../langfuse.md#redis-cache) - Session cache (optional)
- [Dragonfly](../dragonfly.md#acl-configuration) - Core ACL setup

---

## Contributing Patterns

### When to Create a New Pattern

Create a new pattern when:

1. **Procedure is repeated 3+ times** across component docs
2. **Common troubleshooting scenario** that applies to multiple components
3. **Complex multi-step procedure** that benefits from detailed explanation
4. **Best practice** that should be standardized across implementations

### Pattern Template

```markdown
# Pattern Name

**Pattern:** One-line description
**Use Case:** When to use this pattern
**Components:** What components are involved
**Last Updated:** January 2026

---

## Overview
What this pattern is and key features

## Architecture
Visual diagram of flow

## Prerequisites
Required configuration

## Procedure
Step-by-step guide

## Troubleshooting
Common issues and fixes

## Components Using This Pattern
Table of components

## Related Documentation
Links to related docs

---

**Last Updated:** Date
**Pattern Version:** 1.0
**Tested With:** Component versions
```

---

## Related Documentation

### AI Context Guides

- [LiteLLM Configuration](../litellm.md)
- [Langfuse Configuration](../langfuse.md)
- [Obot Configuration](../obot.md)
- [Dragonfly Configuration](../dragonfly.md)
- [Configuration Variables Reference](../configuration-variables.md)

### Research Documentation

- CNPG: `docs/research/cnpg-managed-roles-password-rotation-jan-2026.md`
- RustFS: `docs/research/archive/completed/rustfs-shared-storage-loki-simplescalable-jan-2026.md`

### Implementation Guides

- `docs/guides/completed/cnpg-implementation.md`
- `docs/guides/completed/native-oidc-securitypolicy-implementation.md`

---

**Total Patterns:** 3
**Components Covered:** LiteLLM, Langfuse, Obot, Dragonfly
**Pattern Coverage:** Database passwords, S3 storage, Redis cache
