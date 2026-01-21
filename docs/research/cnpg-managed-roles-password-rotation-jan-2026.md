# CNPG Managed Roles - Password Rotation Implementation

> **Created:** January 2026
> **Status:** Research Complete - Ready for Implementation
> **Purpose:** Enable automatic password rotation for CNPG-managed PostgreSQL databases
> **Scope:** Obot, LiteLLM, Langfuse, Keycloak CNPG clusters

---

## Executive Summary

CloudNativePG (CNPG) provides **declarative role management** through the `spec.managed.roles` configuration. This feature enables automatic password synchronization when Kubernetes Secrets are updated, eliminating the need for manual `ALTER USER` commands during credential rotation.

### Key Findings

| Feature | Status | Notes |
| --------- | -------- | ------- |
| Managed Roles | GA (v1.20+) | Full lifecycle management for database roles |
| Password Secret | Supported | References `kubernetes.io/basic-auth` secrets |
| Auto-Rotation | Supported | Requires `cnpg.io/reload: "true"` label on secrets |
| DSN Construction | Not Managed | Application must handle DSN assembly from secret |

### Critical Requirement

The secret **MUST** have the label `cnpg.io/reload: "true"` for CNPG to detect password changes and trigger reconciliation. Without this label, password updates are ignored.

---

## Current Project State Analysis

### CNPG Clusters in Project

| Application | Cluster Name | Namespace | Secret Name | Secret Type | Has Reload Label |
| ------------- | -------------- | ----------- | ------------- | ------------- | ------------------ |
| **Obot** | `obot-postgresql` | `ai-system` | `obot-db-secret` | `Opaque` | **No** |
| **LiteLLM** | `litellm-postgresql` | `ai-system` | `litellm-db-secret` | `Opaque` | **No** |
| **Langfuse** | `langfuse-postgresql` | `ai-system` | `langfuse-postgresql-credentials` | `kubernetes.io/basic-auth` ✓ | **No** |
| **Keycloak** | `keycloak-postgres` | `identity` | `keycloak-db-secret` | `Opaque` | **No** |

### Current Bootstrap Configuration

All clusters use `bootstrap.initdb.secret` which:

- Sets password **only at initial cluster creation**
- Does **not** sync password changes afterward
- Requires manual `ALTER USER` for rotation

### DSN Handling Issues

Several applications embed database passwords directly in HelmRelease configs or application secrets:

| Application | Issue | Location |
| ------------- | ------- | ---------- |
| **Obot** | DSN in HelmRelease `config:` | `helmrelease.yaml.j2` lines 104, 137 |
| **LiteLLM** | DSN in Secret `DATABASE_URL` | `secret.sops.yaml.j2` line 24 |
| **Langfuse** | DSN in HelmRelease | Via environment variables |

---

## CNPG Managed Roles Feature

### Overview

The `spec.managed.roles` stanza provides declarative role management:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  managed:
    roles:
      - name: obot
        ensure: present
        login: true
        passwordSecret:
          name: obot-db-secret
```

### How It Works

1. **Reconciliation Loop**: CNPG operator watches the Cluster spec and referenced secrets
2. **Secret Change Detection**: When a secret with `cnpg.io/reload: "true"` changes, operator detects via resourceVersion
3. **Password Update**: Operator executes `ALTER USER <role> PASSWORD '<new_password>'`
4. **Application Restart**: Application pods using the secret get new credentials via envFrom reload

### Secret Requirements

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: obot-db-secret
  namespace: ai-system
  labels:
    cnpg.io/reload: "true"  # CRITICAL: Required for auto-rotation
type: kubernetes.io/basic-auth
stringData:
  username: obot
  password: "<password>"
```

| Field | Requirement |
| ------- | ------------- |
| `type` | Must be `kubernetes.io/basic-auth` |
| `labels.cnpg.io/reload` | Must be `"true"` for auto-rotation |
| `username` | Must match role name in `managed.roles[].name` |
| `password` | Plaintext or SCRAM-SHA-256/MD5 hash |

### Role Configuration Options

```yaml
managed:
  roles:
    - name: app_user
      ensure: present        # 'present' or 'absent'
      login: true           # Can connect to database
      superuser: false      # Superuser privileges
      createdb: false       # Can create databases
      createrole: false     # Can create roles
      inherit: true         # Inherits privileges from member roles
      replication: false    # Can initiate replication
      bypassrls: false      # Bypass row-level security
      connectionLimit: -1   # Max connections (-1 = unlimited)
      validUntil: ""        # Password expiry (ISO 8601)
      inRoles: []           # Member of these roles
      passwordSecret:
        name: secret-name
      disablePassword: false # Set to true for NULL password
```

---

## Implementation Plan

### Phase 1: Update Secret Templates

#### 1.1 Obot Secret (`secret.sops.yaml.j2`)

**Before:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: obot-db-secret
  namespace: ai-system
type: Opaque
stringData:
  username: "obot"
  password: "#{ obot_db_password }#"
```

**After:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: obot-db-secret
  namespace: ai-system
  labels:
    cnpg.io/reload: "true"
    app.kubernetes.io/name: obot-postgresql
    app.kubernetes.io/component: database-credentials
type: kubernetes.io/basic-auth
stringData:
  username: "#{ obot_postgres_user | default('obot') }#"
  password: "#{ obot_db_password }#"
```

#### 1.2 LiteLLM Secret (`secret.sops.yaml.j2`)

**Before:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-db-secret
  namespace: ai-system
type: Opaque
stringData:
  username: "litellm"
  password: "#{ litellm_db_password }#"
```

**After:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-db-secret
  namespace: ai-system
  labels:
    cnpg.io/reload: "true"
    app.kubernetes.io/name: litellm-postgresql
    app.kubernetes.io/component: database-credentials
type: kubernetes.io/basic-auth
stringData:
  username: "#{ litellm_db_user | default('litellm') }#"
  password: "#{ litellm_db_password }#"
```

#### 1.3 Langfuse Secret (Already `kubernetes.io/basic-auth`)

Add the reload label:

**Before:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-postgresql-credentials
  namespace: ai-system
type: kubernetes.io/basic-auth
```

**After:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-postgresql-credentials
  namespace: ai-system
  labels:
    cnpg.io/reload: "true"
    app.kubernetes.io/name: langfuse-postgresql
    app.kubernetes.io/component: database-credentials
type: kubernetes.io/basic-auth
```

#### 1.4 Keycloak Secret (`secret.sops.yaml.j2`)

**Before:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-secret
  namespace: identity
type: Opaque
stringData:
  username: "keycloak"
  password: "#{ keycloak_db_password }#"
```

**After:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-secret
  namespace: identity
  labels:
    cnpg.io/reload: "true"
    app.kubernetes.io/name: keycloak-postgres
    app.kubernetes.io/component: database-credentials
type: kubernetes.io/basic-auth
stringData:
  username: "#{ keycloak_db_user | default('keycloak') }#"
  password: "#{ keycloak_db_password }#"
```

### Phase 2: Add Managed Roles to Cluster Specs

#### 2.1 Obot PostgreSQL (`postgresql.yaml.j2`)

Add after `bootstrap:` section:

```yaml
spec:
  # ... existing config ...

  #| =========================================================================== #|
  #| MANAGED ROLES - Declarative role management with password auto-rotation    #|
  #| CNPG syncs password changes from secret when cnpg.io/reload: "true" label  #|
  #| REF: https://cloudnative-pg.io/docs/1.28/declarative_role_management/   #|
  #| =========================================================================== #|
  managed:
    roles:
      - name: #{ obot_postgres_user | default('obot') }#
        ensure: present
        login: true
        createdb: false
        createrole: false
        inherit: true
        connectionLimit: -1
        passwordSecret:
          name: obot-db-secret
```

#### 2.2 LiteLLM PostgreSQL (`postgresql.yaml.j2`)

```yaml
spec:
  managed:
    roles:
      - name: #{ litellm_db_user | default('litellm') }#
        ensure: present
        login: true
        createdb: false
        createrole: false
        inherit: true
        connectionLimit: -1
        passwordSecret:
          name: litellm-db-secret
```

#### 2.3 Langfuse PostgreSQL (`postgresql.yaml.j2`)

```yaml
spec:
  managed:
    roles:
      - name: langfuse
        ensure: present
        login: true
        createdb: false
        createrole: false
        inherit: true
        connectionLimit: -1
        passwordSecret:
          name: langfuse-postgresql-credentials
```

#### 2.4 Keycloak PostgreSQL (`postgres-cnpg.yaml.j2`)

```yaml
spec:
  managed:
    roles:
      - name: #{ keycloak_db_user | default('keycloak') }#
        ensure: present
        login: true
        createdb: false
        createrole: false
        inherit: true
        connectionLimit: -1
        passwordSecret:
          name: keycloak-db-secret
```

### Phase 3: Verify DSN Handling in SOPS Secrets

Applications need the full DSN in SOPS-encrypted secrets, not plaintext HelmRelease configs.

#### 3.1 Obot ✓ (Already Fixed)

DSN moved to `obot-secret` with `OBOT_SERVER_DSN` and `OBOT_AUTH_PROVIDER_POSTGRES_CONNECTION_DSN` keys.

- Location: `secret.sops.yaml.j2` lines 21-26
- HelmRelease updated to remove plaintext DSN

#### 3.2 LiteLLM ✓ (Already in SOPS)

DSN is already in `litellm-secret` as `DATABASE_URL` (line 24 of `secret.sops.yaml.j2`).

- Note: Uses `sslmode=disable` for internal cluster communication (Cilium provides encryption)

#### 3.3 Langfuse ✓ (Verified)

Langfuse uses environment variables that reference the secret, not embedded DSN in HelmRelease.

#### 3.4 Keycloak ✓ (Verified)

Keycloak operator handles database connection via `spec.db` configuration referencing the secret.

### Phase 4: Add Reloader Annotations

Applications must be configured to restart when secrets change.

#### 4.1 Obot HelmRelease

Add to `helmrelease.yaml.j2`:

```yaml
values:
  podAnnotations:
    secret.reloader.stakater.com/reload: "obot-db-secret,obot-secret"
```

#### 4.2 LiteLLM HelmRelease

Add to `helmrelease.yaml.j2`:

```yaml
values:
  podAnnotations:
    secret.reloader.stakater.com/reload: "litellm-db-secret,litellm-secret"
```

#### 4.3 Langfuse HelmRelease

Add to `helmrelease.yaml.j2`:

```yaml
values:
  server:
    podAnnotations:
      secret.reloader.stakater.com/reload: "langfuse-postgresql-credentials,langfuse-credentials"
  worker:
    podAnnotations:
      secret.reloader.stakater.com/reload: "langfuse-postgresql-credentials,langfuse-credentials"
```

#### 4.4 Keycloak

Keycloak operator manages its own pods. Verify if annotation propagates or requires manual restart.

---

## Password Rotation Procedure

### Standard Rotation (With Managed Roles)

Once managed roles are configured:

```bash
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

# 2. Update cluster.yaml
# Edit: obot_db_password: "<NEW_PASS>"

# 3. Regenerate and deploy
task configure
git add -A && git commit -m "chore: rotate obot database password"
git push

# 4. Force reconcile
task reconcile

# CNPG will automatically:
# - Detect secret change (cnpg.io/reload label)
# - Execute ALTER USER obot PASSWORD '...'
# - Application pods get new password via envFrom
```

### Verification

```bash
# Check CNPG operator logs
kubectl logs -n cnpg-system deployment/cnpg-controller-manager | grep -i password

# Verify role password was updated (check cluster status)
kubectl get cluster obot-postgresql -n ai-system -o yaml | grep -A 20 status

# Test connection with new password
kubectl exec -n ai-system obot-postgresql-1 -- psql -U obot -c "SELECT 1"
```

---

## Caveats and Limitations

### 1. Bootstrap vs Managed Roles

The `bootstrap.initdb.secret` is used **only at cluster creation**. After initial setup, password management transitions to `managed.roles`. Both should reference the same secret.

### 2. Reconciliation Timing

Password changes may not be immediate. CNPG reconciles on:

- Secret change detection (requires `cnpg.io/reload` label)
- Operator restart
- Cluster spec changes

If immediate rotation is required, trigger reconciliation:

```bash
kubectl annotate cluster obot-postgresql -n ai-system \
  "force-reconcile=$(date +%s)" --overwrite
```

### 3. Application Restart

Applications using `envFrom` with secrets will need pod restart to pick up new passwords. Options:

- Use [Reloader](https://github.com/stakater/Reloader) (already deployed in `kube-system` namespace)
- Add annotation to trigger rollout: `reloader.stakater.com/auto: "true"`

**IMPORTANT:** Currently, none of the CNPG-dependent applications (Obot, LiteLLM, Langfuse, Keycloak) have Reloader annotations. This must be added as part of Phase 4 implementation.

Example for HelmRelease templates:

```yaml
values:
  podAnnotations:
    reloader.stakater.com/auto: "true"
```

Or for specific secret watching:

```yaml
values:
  podAnnotations:
    secret.reloader.stakater.com/reload: "obot-db-secret,obot-secret"
```

### 4. SCRAM-SHA-256 vs Plaintext

For additional security, store pre-hashed passwords in secrets:

```yaml
stringData:
  password: "SCRAM-SHA-256$4096:<salt>$<StoredKey>:<ServerKey>"
```

Generate with:

```bash
kubectl exec -n ai-system obot-postgresql-1 -- \
  psql -U postgres -c "SELECT 'SCRAM-SHA-256' || regexp_replace(
    encode(pg_catalog.scram_sha_256('new_password'), 'hex'),
    '(.{8})(.{64})(.{64})', E'\\$4096:\\1\\$\\2:\\3'
  )"
```

### 5. Secret Type Immutability (Migration Caveat)

**CRITICAL for existing clusters:** Kubernetes Secret `type` field is **immutable**. You cannot change an existing secret from `type: Opaque` to `type: kubernetes.io/basic-auth` via normal GitOps apply.

**Symptom:**

```
Secret "litellm-db-secret" is invalid: type: Invalid value: "kubernetes.io/basic-auth": field is immutable
```

**Solution for existing deployments:**

```bash
# Delete the secrets with wrong type (Flux will recreate with correct type)
kubectl delete secret keycloak-db-secret -n identity
kubectl delete secret litellm-db-secret -n ai-system
kubectl delete secret obot-db-secret -n ai-system

# Force Flux reconciliation
flux reconcile ks keycloak -n identity --with-source
flux reconcile ks litellm -n ai-system --with-source
flux reconcile ks obot -n ai-system --with-source
```

**Why this is safe:**

- CNPG clusters remain healthy (they cache the connection)
- Passwords are stored in SOPS-encrypted templates
- Flux immediately recreates secrets with correct type
- Reloader restarts application pods with new secret references

**Prevention:** For new deployments, secrets are created with correct type from the start. This issue only affects clusters migrating from `Opaque` to `kubernetes.io/basic-auth`.

---

## Integration with External Secrets Operator

For fully automated rotation, integrate with External Secrets Operator (ESO):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: obot-db-secret
  namespace: ai-system
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: obot-db-secret
    template:
      type: kubernetes.io/basic-auth
      metadata:
        labels:
          cnpg.io/reload: "true"
      data:
        username: obot
        password: "{{ .password }}"
  data:
    - secretKey: password
      remoteRef:
        key: databases/obot
        property: password
```

This enables:

- Automatic password generation in Vault
- Scheduled rotation (e.g., every 24h)
- CNPG auto-detects and syncs to PostgreSQL
- Application gets new credentials via pod restart

---

## Files to Modify

### Phase 1: Secret Templates (Add reload label, fix types)

| File | Changes Required |
| ------ | ------------------ |
| `templates/config/kubernetes/apps/ai-system/obot/app/secret.sops.yaml.j2` | Add `cnpg.io/reload` label to `obot-db-secret`, change type to `kubernetes.io/basic-auth` |
| `templates/config/kubernetes/apps/ai-system/litellm/app/secret.sops.yaml.j2` | Add `cnpg.io/reload` label to `litellm-db-secret`, change type to `kubernetes.io/basic-auth` |
| `templates/config/kubernetes/apps/ai-system/langfuse/app/secret.sops.yaml.j2` | Add `cnpg.io/reload` label to `langfuse-postgresql-credentials` (type already correct) |
| `templates/config/kubernetes/apps/identity/keycloak/app/secret.sops.yaml.j2` | Add `cnpg.io/reload` label to `keycloak-db-secret`, change type to `kubernetes.io/basic-auth` |

### Phase 2: CNPG Cluster Specs (Add managed.roles)

| File | Changes Required |
| ------ | ------------------ |
| `templates/config/kubernetes/apps/ai-system/obot/app/postgresql.yaml.j2` | Add `managed.roles` section referencing `obot-db-secret` |
| `templates/config/kubernetes/apps/ai-system/litellm/app/postgresql.yaml.j2` | Add `managed.roles` section referencing `litellm-db-secret` |
| `templates/config/kubernetes/apps/ai-system/langfuse/app/postgresql.yaml.j2` | Add `managed.roles` section referencing `langfuse-postgresql-credentials` |
| `templates/config/kubernetes/apps/identity/keycloak/app/postgres-cnpg.yaml.j2` | Add `managed.roles` section referencing `keycloak-db-secret` |

### Phase 4: HelmRelease Templates (Add Reloader annotations)

| File | Changes Required |
| ------ | ------------------ |
| `templates/config/kubernetes/apps/ai-system/obot/app/helmrelease.yaml.j2` | Add `secret.reloader.stakater.com/reload` pod annotation |
| `templates/config/kubernetes/apps/ai-system/litellm/app/helmrelease.yaml.j2` | Add `secret.reloader.stakater.com/reload` pod annotation |
| `templates/config/kubernetes/apps/ai-system/langfuse/app/helmrelease.yaml.j2` | Add `secret.reloader.stakater.com/reload` pod annotation (server + worker) |
| `templates/config/kubernetes/apps/identity/keycloak/app/keycloak.yaml.j2` | Verify Keycloak CR supports pod annotations or document manual restart |

---

## Validation Findings

### Cross-Reference Analysis (2026-01-11)

The following validation was performed against actual project templates:

| Finding | Status | Details |
| --------- | -------- | --------- |
| Langfuse secret type | ✓ Correct | Already uses `kubernetes.io/basic-auth` |
| Obot DSN security | ✓ Fixed | DSN moved to SOPS secret (previous session) |
| Reloader deployment | ✓ Present | Deployed in `kube-system` namespace |
| Reloader annotations | ⚠ Missing | No CNPG apps have Reloader annotations |
| Database CRDs | ✓ Verified | All clusters use separate `Database` CRDs |
| Langfuse username | ⚠ Note | Hardcodes `owner: langfuse` instead of variable |

### Additional Considerations

1. **Database CRD Consistency**: Each postgresql.yaml.j2 includes a `Database` CRD that sets `owner`. This owner must match the managed role name for proper permission inheritance.

2. **CNPG Operator Version**: Managed roles feature requires CNPG v1.20+. Verify operator version before implementation.

3. **Existing Role Migration**: For existing clusters, the role already exists from bootstrap. CNPG will adopt management of the role when `managed.roles` is added.

4. **Network Policies**: All CNPG clusters have `network.cilium.io/api-access: "true"` label which allows API access. No network policy changes required.

---

## References

### Official Documentation

- [CloudNativePG Declarative Role Management](https://cloudnative-pg.io/docs/1.28/declarative_role_management/)
- [CloudNativePG Security](https://cloudnative-pg.io/docs/1.28/security/)
- [External Secrets with CNPG](https://cloudnative-pg.io/docs/1.28/cncf-projects/external-secrets/)

### GitHub Issues/Discussions

- [Password rotation via secret update discussion](https://github.com/cloudnative-pg/cloudnative-pg/discussions/8062)
- [Superuser password rotation issue #2658](https://github.com/cloudnative-pg/cloudnative-pg/issues/2658)
- [Auto-generate password secrets feature request #3788](https://github.com/cloudnative-pg/cloudnative-pg/issues/3788)

### Project Documentation

- [CNPG Implementation Guide](../guides/completed/cnpg-implementation.md)
- [Barman Cloud Plugin Remediation](./barman-cloud-plugin-wal-archive-remediation-jan-2026.md)

---

## Changelog

| Date | Change |
| ------ | -------- |
| 2026-01-11 | Initial research document created |
| 2026-01-11 | Analyzed all 4 CNPG clusters in project |
| 2026-01-11 | Documented implementation plan with specific file changes |
| 2026-01-11 | **Validation pass**: Cross-referenced against actual templates |
| 2026-01-11 | Added Phase 4: Reloader annotations (critical gap identified) |
| 2026-01-11 | Updated Phase 3 with verification status for all apps |
| 2026-01-11 | Added Validation Findings section with cross-reference analysis |
| 2026-01-11 | Expanded Files to Modify with phase-organized structure |
| 2026-01-11 | **Implementation complete**: All changes deployed to cluster |
| 2026-01-11 | Added Section 5: Secret Type Immutability migration caveat (learned from production) |
