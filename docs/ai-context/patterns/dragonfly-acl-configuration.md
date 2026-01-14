# Dragonfly ACL Configuration Pattern

**Pattern:** Multi-Tenant Redis-Compatible Cache with ACL Isolation
**Use Case:** Configure isolated access for multiple applications sharing Dragonfly cache
**Components:** Dragonfly Operator, Dragonfly Instance
**Last Updated:** January 2026

---

## Overview

Dragonfly is a Redis-compatible in-memory data store (25x faster than Redis) with ACL support for multi-tenant deployments. This pattern demonstrates how to configure **isolated cache access** for multiple applications sharing a single Dragonfly instance.

### Key Features

- ✅ **Multi-Tenant Isolation**: Key prefix-based namespace separation
- ✅ **Redis ACL Compatible**: Standard Redis ACL commands
- ✅ **Operator-Managed**: Declarative configuration via CRDs
- ✅ **High Performance**: 25x faster than Redis, optimized for modern hardware

---

## Architecture

### Multi-Tenant Isolation

```mermaid
sequenceDiagram
    participant LiteLLM
    participant Langfuse
    participant Dragonfly as Dragonfly<br/>(ACL Engine)
    participant Keys as Key Storage

    LiteLLM->>Dragonfly: SET litellm:cache:123<br/>(user: litellm)
    Dragonfly->>Dragonfly: Check ACL: ~litellm:*
    Dragonfly->>Keys: ✅ Write permitted
    Keys-->>Dragonfly: OK
    Dragonfly-->>LiteLLM: OK

    Langfuse->>Dragonfly: GET litellm:cache:123<br/>(user: langfuse)
    Dragonfly->>Dragonfly: Check ACL: ~langfuse:*
    Dragonfly-->>Langfuse: ❌ NOPERM<br/>(key prefix mismatch)

    Langfuse->>Dragonfly: SET langfuse:session:456<br/>(user: langfuse)
    Dragonfly->>Dragonfly: Check ACL: ~langfuse:*
    Dragonfly->>Keys: ✅ Write permitted
    Keys-->>Dragonfly: OK
    Dragonfly-->>Langfuse: OK
```

### ACL Namespace Model

```mermaid
graph TB
    subgraph Dragonfly["🗄️ Dragonfly Cache (cache namespace)"]
        ACL[ACL Engine]
        Storage[Key-Value Storage]
    end

    subgraph Users["👥 ACL Users"]
        U1[litellm<br/>~litellm:*]
        U2[langfuse<br/>~langfuse:*]
        U3[default<br/>~*]
    end

    subgraph Keys["🔑 Key Namespaces"]
        K1[litellm:cache:*]
        K2[litellm:rate_limit:*]
        K3[langfuse:session:*]
        K4[langfuse:cache:*]
    end

    U1 -->|✅ Allow| K1
    U1 -->|✅ Allow| K2
    U1 -->|❌ Deny| K3
    U1 -->|❌ Deny| K4

    U2 -->|❌ Deny| K1
    U2 -->|❌ Deny| K2
    U2 -->|✅ Allow| K3
    U2 -->|✅ Allow| K4

    U3 -->|✅ Allow| K1
    U3 -->|✅ Allow| K2
    U3 -->|✅ Allow| K3
    U3 -->|✅ Allow| K4

    ACL -.enforces.-> Users
    Storage -.contains.-> Keys

    style Dragonfly fill:#e1f5ff
    style Users fill:#fff4e1
    style Keys fill:#e1ffe1
```

### ACL Configuration Flow

```mermaid
flowchart TB
    subgraph Config["⚙️ Configuration"]
        A[1. Define ACL users<br/>in cluster.yaml] --> B[2. Generate passwords<br/>SOPS encrypt]
        B --> C[3. task configure]
    end

    subgraph Deploy["🚀 Deployment"]
        C --> D[4. Secret rendered<br/>users.acl]
        D --> E[5. Dragonfly CR<br/>aclFromSecret]
        E --> F[6. Operator mounts<br/>ACL secret]
        F --> G[7. Dragonfly loads<br/>ACL rules]
    end

    subgraph Runtime["▶️ Runtime"]
        G --> H[8. Apps connect<br/>with credentials]
        H --> I[9. ACL enforces<br/>key prefix isolation]
    end

    style Config fill:#e1f5ff
    style Deploy fill:#fff4e1
    style Runtime fill:#e1ffe1
```

---

## ACL Configuration

### Dragonfly CR with ACL

**File:** `templates/config/kubernetes/apps/cache/dragonfly/app/dragonfly.yaml.j2`

```yaml
apiVersion: dragonflydb.io/v1alpha1
kind: Dragonfly
metadata:
  name: dragonfly
  namespace: cache
spec:
  replicas: 1

  #% if dragonfly_acl_enabled | default(false) %#
  # ACL Configuration
  authentication:
    passwordFromSecret:
      name: dragonfly-auth
      key: password

    # Enable ACL mode
    aclFromSecret:
      name: dragonfly-acl
  #% endif %#

  resources:
    requests:
      cpu: "#{ dragonfly_cpu_request | default('500m') }#"
      memory: "#{ dragonfly_memory_request | default('1Gi') }#"
    limits:
      cpu: "#{ dragonfly_cpu_limit | default('2000m') }#"
      memory: "#{ dragonfly_memory_limit | default('4Gi') }#"
```

---

### ACL Secret Format

**File:** `templates/config/kubernetes/apps/cache/dragonfly/app/acl-secret.sops.yaml.j2`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dragonfly-acl
  namespace: cache
type: Opaque
stringData:
  users.acl: |
    # Default admin user
    user default on >#{ dragonfly_admin_password }# ~* +@all

    #% if dragonfly_litellm_enabled | default(false) %#
    # LiteLLM cache user
    user litellm on >#{ dragonfly_litellm_password }# ~litellm:* +@all
    #% endif %#

    #% if dragonfly_langfuse_enabled | default(false) %#
    # Langfuse cache user
    user langfuse on >#{ dragonfly_langfuse_password }# ~langfuse:* +@all
    #% endif %#
```

---

## ACL Syntax Reference

### User Definition

```
user <username> on ><password> ~<key-pattern> +<commands>
```

**Components:**
- `user <username>` - Username for authentication
- `on` - Enable the user
- `><password>` - Plaintext password (prefixed with `>`)
- `~<key-pattern>` - Key access pattern (glob-style)
- `+<commands>` - Allowed command categories

### Key Patterns

| Pattern | Description | Example Keys Matched |
| --------- | ------------- | ---------------------- |
| `~*` | All keys | Any key |
| `~litellm:*` | Prefix match | `litellm:cache:123`, `litellm:model:gpt4` |
| `~litellm:cache:*` | Nested prefix | `litellm:cache:token1`, `litellm:cache:token2` |
| `~{litellm,langfuse}:*` | Multiple prefixes | Keys starting with `litellm:` or `langfuse:` |

### Command Categories

| Category | Description | Common Commands |
| --------- | ------------- | ----------------- |
| `+@all` | All commands | Full Redis API access |
| `+@read` | Read-only | GET, MGET, HGETALL, LRANGE, etc. |
| `+@write` | Write | SET, MSET, HSET, LPUSH, etc. |
| `+@admin` | Admin | CONFIG, FLUSHDB, SHUTDOWN, etc. |
| `+@dangerous` | Destructive | FLUSHALL, KEYS, etc. |

---

## Configuration in cluster.yaml

### Enable Dragonfly with ACL

```yaml
# Dragonfly Cache Configuration
dragonfly_enabled: true
dragonfly_acl_enabled: true

# Admin password (for default user)
dragonfly_admin_password: "admin-password-encrypted"  # SOPS

# Application-specific ACL users
dragonfly_litellm_enabled: true
dragonfly_litellm_password: "litellm-password-encrypted"  # SOPS

dragonfly_langfuse_enabled: true
dragonfly_langfuse_password: "langfuse-password-encrypted"  # SOPS
```

**Generate Passwords:**
```bash
openssl rand -base64 24  # For each user
```

**Encrypt with SOPS:**
```bash
sops cluster.yaml  # Edit and encrypt
```

---

## Application Connection Configuration

### LiteLLM Connection

**Environment Variables:**
```yaml
env:
  - name: REDIS_HOST
    value: "dragonfly.cache.svc.cluster.local"
  - name: REDIS_PORT
    value: "6379"
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: litellm-dragonfly-secret
        key: password
```

**Connection String:**
```
redis://litellm:<password>@dragonfly.cache.svc.cluster.local:6379/0
```

**Key Prefixing:**
LiteLLM automatically prefixes keys with `litellm:` namespace:
- `litellm:cache:model_gpt-4_user_123`
- `litellm:rate_limit:user_456`

---

### Langfuse Connection

**Environment Variables:**
```yaml
env:
  - name: REDIS_URL
    value: "redis://langfuse:<password>@dragonfly.cache.svc.cluster.local:6379"
```

**Key Prefixing:**
Langfuse uses session and cache keys with `langfuse:` prefix:
- `langfuse:session:abc123`
- `langfuse:cache:trace_xyz`

---

## Testing ACL Configuration

### 1. Test Admin Access

```bash
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<admin-password>" PING
# Expected: PONG
```

### 2. Test User Access (Positive)

```bash
# Test litellm user with allowed key
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<litellm-password>" --user litellm \
  SET litellm:test:key "value"
# Expected: OK

kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<litellm-password>" --user litellm \
  GET litellm:test:key
# Expected: "value"
```

### 3. Test User Isolation (Negative)

```bash
# Test litellm user trying to access langfuse key (should fail)
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<litellm-password>" --user litellm \
  GET langfuse:test:key
# Expected: (error) NOPERM User litellm has no permissions to access key 'langfuse:test:key'
```

### 4. Verify ACL Rules

```bash
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<admin-password>" ACL LIST
# Expected:
# user default on #<hash> ~* +@all
# user litellm on #<hash> ~litellm:* +@all
# user langfuse on #<hash> ~langfuse:* +@all
```

---

## Troubleshooting

### Issue: "NOAUTH Authentication required"

**Symptoms:**
- Application can't connect to Dragonfly
- Logs show authentication errors

**Causes:**
1. ACL secret not created
2. Password incorrect in application secret
3. Username not specified in connection string

**Resolution:**
```bash
# 1. Verify ACL secret exists
kubectl get secret -n cache dragonfly-acl -o yaml

# 2. Verify application secret has correct password
kubectl get secret -n <namespace> <app>-dragonfly-secret -o jsonpath='{.data.password}' | base64 -d

# 3. Check connection string includes username
# Correct: redis://litellm:password@host:6379
# Wrong:   redis://:password@host:6379  (missing username)
```

---

### Issue: "NOPERM" Key Access Denied

**Symptoms:**
- Application can connect but operations fail
- Logs show permission errors on specific keys

**Causes:**
1. Key prefix doesn't match ACL pattern
2. Application not prefixing keys correctly
3. ACL rule typo

**Resolution:**
```bash
# 1. Check actual keys being accessed
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<admin-password>" --scan --pattern "*" | head -20

# 2. Verify ACL rule for user
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<admin-password>" ACL GETUSER litellm

# 3. Test with admin user to confirm key access works
kubectl exec -n cache deploy/dragonfly -- \
  redis-cli -a "<admin-password>" GET <problematic-key>
```

---

### Issue: ACL Changes Not Applied

**Symptoms:**
- Updated ACL secret but users still have old permissions
- New users not recognized

**Causes:**
1. Dragonfly not reloaded ACL
2. Secret update not propagated
3. Operator not reconciling

**Resolution:**
```bash
# 1. Force Dragonfly pod restart to reload ACL
kubectl rollout restart statefulset/dragonfly -n cache

# 2. Verify secret update timestamp
kubectl get secret -n cache dragonfly-acl -o yaml | grep "creationTimestamp\|resourceVersion"

# 3. Check Dragonfly Operator logs
kubectl logs -n dragonfly-operator-system deploy/dragonfly-operator-controller-manager -f
```

---

## Security Best Practices

### 1. Principle of Least Privilege

- ✅ **Use narrow key patterns**: `~litellm:*` not `~*`
- ✅ **Restrict command categories**: Use `+@read +@write` not `+@all` if admin commands not needed
- ❌ **Avoid wildcard access**: Don't use `~*` for application users

### 2. Password Management

- ✅ **Strong passwords**: Minimum 24 characters, random
- ✅ **SOPS encryption**: Always encrypt passwords in cluster.yaml
- ✅ **Rotate regularly**: Quarterly password rotation
- ❌ **Never share passwords**: Distinct password per application

### 3. Key Namespace Hygiene

- ✅ **Always prefix keys**: Applications must prefix keys with their namespace
- ✅ **Document prefixes**: Clearly document key patterns in application docs
- ✅ **Monitor access**: Log and audit key access patterns

---

## Components Using This Pattern

| Component | Namespace | ACL User | Key Prefix | Commands |
| --------- | --------- | -------- | ---------- | -------- |
| **LiteLLM** | ai-system | litellm | `litellm:*` | +@all |
| **Langfuse** | ai-system | langfuse | `langfuse:*` | +@all |
| **Admin** | cache | default | `*` | +@all |

---

## Related Documentation

- **Dragonfly Configuration**: `docs/ai-context/dragonfly.md`
- **LiteLLM Caching**: `docs/ai-context/litellm.md#dragonfly-cache`
- **Langfuse Caching**: `docs/ai-context/langfuse.md#redis-cache`
- **Redis ACL Documentation**: https://redis.io/docs/management/security/acl/

---

**Last Updated:** January 14, 2026
**Pattern Version:** 1.1.0 ([CHANGELOG](./CHANGELOG.md#pattern-dragonfly-acl-configuration))
**Tested With:** Dragonfly v1.24.0, Dragonfly Operator v1.1.9

### Version History
- **v1.1.0** (2026-01-14): Added Mermaid diagrams for multi-tenant visualization
- **v1.0.0** (2026-01-14): Initial pattern extraction
