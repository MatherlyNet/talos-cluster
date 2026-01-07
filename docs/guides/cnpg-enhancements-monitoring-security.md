# CNPG Enhancements: Monitoring, Cilium, and External Secrets

> **Created:** January 2026
> **Status:** Research Complete - Implementation Ready
> **Based On:** CloudNativePG v1.28 Documentation
> **Dependencies:** cnpg_enabled, monitoring_enabled, network_policies_enabled

---

## Executive Summary

This document analyzes three CNPG enhancement areas from the official documentation and provides recommendations for this project:

| Enhancement Area | Current Status | Recommendation | Priority |
| ---------------- | -------------- | -------------- | -------- |
| **Monitoring Enhancements** | Partial | Add TLS metrics, custom queries | Medium |
| **Cilium Network Policies** | Not Implemented | Add CNPG-specific policies | High |
| **External Secrets Integration** | Templates exist, disabled | Consider for credential rotation | Low |

---

## 1. Monitoring Enhancements

### Current Implementation Analysis

Your project already has solid CNPG monitoring:
- ✅ ServiceMonitor for operator metrics (port 8080)
- ✅ PrometheusRule with 6 alert rules
- ✅ Grafana dashboard with key metrics
- ⚠️ Uses deprecated `enablePodMonitor: true` in Cluster CRs

### Recommended Enhancements

#### 1.1 Manual PodMonitor for PostgreSQL Instances

**Why:** The `spec.monitoring.enablePodMonitor` field is deprecated in CNPG 1.28. Manual PodMonitors provide more control and follow best practices.

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/podmonitor-instances.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) and monitoring_enabled | default(false) %#
---
#| PodMonitor for all CNPG PostgreSQL cluster instances #|
#| Scrapes metrics from port 9187 on all pods with cnpg.io/cluster label #|
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cnpg-cluster-instances
  labels:
    app.kubernetes.io/name: cloudnative-pg
    app.kubernetes.io/component: postgresql
spec:
  #| Match ALL pods that have cnpg.io/cluster label (any value) #|
  selector:
    matchExpressions:
      - key: cnpg.io/cluster
        operator: Exists
  #| Watch all namespaces for CNPG clusters #|
  namespaceSelector:
    any: true
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
      scrapeTimeout: 10s
      path: /metrics
#% endif %#
```

**Update kustomization.yaml.j2:**

```yaml
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
#% if monitoring_enabled | default(false) %#
  - ./servicemonitor.yaml
  - ./podmonitor-instances.yaml
  - ./prometheusrule.yaml
  - ./dashboard-configmap.yaml
#% endif %#
```

#### 1.2 TLS on Metrics Port (Optional)

**Why:** Enables encrypted metrics scraping. Useful if you have strict security requirements.

**Cluster CR enhancement:**

```yaml
spec:
  monitoring:
    tls:
      enabled: true  #| Triggers rolling restart, uses server cert #|
```

**PodMonitor with TLS:**

```yaml
podMetricsEndpoints:
  - port: metrics
    scheme: https
    tlsConfig:
      ca:
        secret:
          name: <cluster-name>-ca
          key: ca.crt
      serverName: <cluster-name>-rw
```

**Recommendation:** Skip for now unless you have compliance requirements for encrypted internal metrics.

#### 1.3 Custom Metrics Queries (Optional)

**Why:** Add application-specific PostgreSQL metrics beyond defaults.

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/configmap-custom-metrics.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) and monitoring_enabled | default(false) %#
---
#| Custom metrics queries for CNPG clusters #|
#| Reload automatically with cnpg.io/reload label #|
apiVersion: v1
kind: ConfigMap
metadata:
  name: cnpg-custom-monitoring
  labels:
    cnpg.io/reload: ""
data:
  custom-queries: |
    #| Long-running queries metric #|
    cnpg_pg_stat_activity_long_running:
      query: |
        SELECT
          datname,
          usename,
          count(*) as count
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query NOT LIKE 'autovacuum%'
          AND now() - query_start > interval '5 minutes'
        GROUP BY datname, usename
      metrics:
        - datname:
            usage: "LABEL"
            description: "Database name"
        - usename:
            usage: "LABEL"
            description: "User name"
        - count:
            usage: "GAUGE"
            description: "Number of queries running longer than 5 minutes"

    #| Table bloat estimation #|
    cnpg_pg_table_bloat:
      query: |
        SELECT
          schemaname,
          tablename,
          pg_relation_size(schemaname || '.' || tablename) as size_bytes
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 1000
      metrics:
        - schemaname:
            usage: "LABEL"
            description: "Schema name"
        - tablename:
            usage: "LABEL"
            description: "Table name"
        - size_bytes:
            usage: "GAUGE"
            description: "Table size in bytes"
#% endif %#
```

**Reference in Cluster CR:**

```yaml
spec:
  monitoring:
    customQueriesConfigMap:
      - name: cnpg-custom-monitoring
        key: custom-queries
```

**Recommendation:** Low priority. Only add if you need specific database-level metrics beyond the defaults.

#### 1.4 Additional Alert Rules

**Why:** The current PrometheusRule covers basics but could add more operational alerts.

**Add to `prometheusrule.yaml.j2`:**

```yaml
        #| Alert when primary instance changes (failover occurred) #|
        - alert: CNPGFailoverOccurred
          expr: changes(cnpg_pg_replication_is_wal_receiver_up[5m]) > 0
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "CNPG failover occurred for {{ $labels.cluster }}"
            description: "Primary instance changed for cluster {{ $labels.cluster }} in namespace {{ $labels.namespace }}. Verify application connectivity."

        #| Alert when instance is fenced (isolated from cluster) #|
        - alert: CNPGInstanceFenced
          expr: cnpg_pg_replication_fenced == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "CNPG instance fenced in {{ $labels.cluster }}"
            description: "Instance {{ $labels.pod }} in cluster {{ $labels.cluster }} is fenced and isolated from the cluster."

        #| Alert when checkpoint completion is slow #|
        - alert: CNPGCheckpointSlow
          expr: rate(cnpg_pg_stat_bgwriter_checkpoint_write_time[5m]) > 30
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "CNPG checkpoint writes slow for {{ $labels.cluster }}"
            description: "Checkpoint write time is elevated for cluster {{ $labels.cluster }}. Consider tuning checkpoint_completion_target or storage performance."
```

**Recommendation:** Medium priority. Add failover and fencing alerts for better operational visibility.

---

## 2. Cilium Network Policies for CNPG

### Current Status

Your project has `network_policies_enabled: true` with `network_policies_mode: "audit"`, but **no CNPG-specific CiliumNetworkPolicies exist**.

The `cnpg-implementation.md` guide mentions network policies but doesn't include actual template files.

### Recommended Implementation

#### 2.1 CNPG Operator Egress Policy

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/networkpolicy-operator.yaml.j2`

> **Note:** This follows the project's `enableDefaultDeny` pattern from `monitoring/network-policies/`.

```yaml
#% if cnpg_enabled | default(false) and network_policies_enabled | default(false) %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| CiliumNetworkPolicy for CNPG operator #|
#| Allows operator to access all CNPG cluster pods for health checks #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cnpg-operator
  namespace: cnpg-system
  labels:
    app.kubernetes.io/name: cloudnative-pg
    app.kubernetes.io/component: operator
spec:
  description: "CNPG operator: Access cluster pods, Kubernetes API"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: cloudnative-pg
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| Prometheus metrics scraping on port 8080 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
  egress:
    #| Access Kubernetes API for CR management #|
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    #| Access all CNPG cluster pods on status port 8000 #|
    - toEntities:
        - cluster
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
#% endif %#
```

#### 2.2 Keycloak PostgreSQL Cluster Policy

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/networkpolicy-postgres.yaml.j2`

> **Note:** This follows the project's `enableDefaultDeny` pattern and combines ingress/egress in a single policy.

```yaml
#% if keycloak_enabled | default(false) and network_policies_enabled | default(false) and (keycloak_db_mode | default('embedded')) == 'cnpg' %#
#% set enforce = network_policies_mode | default('audit') == 'enforce' %#
---
#| CiliumNetworkPolicy for Keycloak PostgreSQL cluster #|
#| Controls ingress/egress for CNPG database pods #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: keycloak-postgres
  namespace: identity
  labels:
    app.kubernetes.io/name: keycloak-postgres
    app.kubernetes.io/component: database
spec:
  description: "Keycloak PostgreSQL: Database access, replication, backups"
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: keycloak-postgres
  enableDefaultDeny:
    egress: #{ enforce | lower }#
    ingress: #{ enforce | lower }#
  ingress:
    #| CNPG operator health checks on port 8000 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: cloudnative-pg
            io.kubernetes.pod.namespace: cnpg-system
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    #| Keycloak application access on port 5432 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    #| Inter-pod replication between cluster instances #|
    - fromEndpoints:
        - matchLabels:
            cnpg.io/cluster: keycloak-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% if monitoring_enabled | default(false) %#
    #| Prometheus metrics scraping on port 9187 #|
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
            io.kubernetes.pod.namespace: monitoring
      toPorts:
        - ports:
            - port: "9187"
              protocol: TCP
#% endif %#
  egress:
    #| DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    #| Inter-pod replication #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: keycloak-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% if keycloak_backup_enabled | default(false) %#
    #| Backup to RustFS S3 endpoint #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: rustfs
            io.kubernetes.pod.namespace: storage
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#
#% endif %#
```

#### 2.3 Default Deny Policy for cnpg-system Namespace

**File:** `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/networkpolicy-default-deny.yaml.j2`

```yaml
#% if cnpg_enabled | default(false) and network_policies_enabled | default(false) %#
#% if network_policies_mode | default('audit') == 'enforce' %#
---
#| Default deny policy for cnpg-system namespace #|
#| Only applied in enforce mode #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-cnpg-system
  labels:
    app.kubernetes.io/name: cloudnative-pg
    app.kubernetes.io/component: network-policy
spec:
  description: "Default deny all traffic in cnpg-system namespace"
  endpointSelector: {}
  ingress: []
  egress: []
#% endif %#
#% endif %#
```

#### 2.4 Egress Policy for PostgreSQL Backups

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/networkpolicy-postgres-egress.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and network_policies_enabled | default(false) and (keycloak_db_mode | default('embedded')) == 'cnpg' %#
---
#| CiliumNetworkPolicy for Keycloak PostgreSQL egress #|
#| Allows backup to RustFS S3 and DNS resolution #|
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: keycloak-postgres-egress
  labels:
    app.kubernetes.io/name: keycloak-postgres
    app.kubernetes.io/component: database
spec:
  description: "Allow Keycloak PostgreSQL egress for backups and DNS"
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: keycloak-postgres
  egress:
    #| Allow DNS resolution #|
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP

#% if rustfs_enabled | default(false) and cnpg_backup_enabled | default(false) %#
    #| Allow backup to RustFS S3 endpoint #|
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: rustfs
            io.kubernetes.pod.namespace: storage
      toPorts:
        - ports:
            - port: "9000"
              protocol: TCP
#% endif %#

    #| Allow inter-pod communication for replication #|
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: keycloak-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
#% endif %#
```

### Implementation Priority

1. **High:** `networkpolicy-operator.yaml.j2` - Operator needs access to all clusters
2. **High:** `networkpolicy-postgres.yaml.j2` - Per-cluster access control
3. **Medium:** `networkpolicy-postgres-egress.yaml.j2` - Backup connectivity
4. **Low:** `networkpolicy-default-deny.yaml.j2` - Only for enforce mode

---

## 3. External Secrets Integration

### Current Status

- Templates exist in `templates/config/kubernetes/apps/external-secrets/`
- Currently disabled: `external_secrets_enabled: false` (commented out in cluster.yaml)
- Project uses SOPS/Age for secrets encryption

### Analysis

**External Secrets Operator (ESO) provides:**
- Automated password generation and rotation
- Integration with external KMS (Vault, AWS SM, etc.)
- `cnpg.io/reload: "true"` label triggers CNPG to reload credentials automatically

**Current SOPS approach:**
- Secrets encrypted in Git with Age key
- Manual rotation via `task configure` after editing secrets
- No external dependency (Vault, cloud KMS)

### Recommendation: Low Priority

**Reasons to keep SOPS:**
1. **Simplicity:** No external dependency, works offline
2. **GitOps native:** Secrets versioned with code
3. **Current workflow:** Already established with SOPS/Age
4. **No vault infrastructure:** Would need to deploy and manage Vault

**When ESO makes sense:**
- Enterprise environments with existing Vault infrastructure
- Compliance requirements for automated credential rotation
- Multi-tenant clusters sharing secrets from central KMS
- Integration with cloud provider secrets (AWS SM, GCP SM, Azure KV)

### Optional Implementation (If Needed Later)

If you decide to enable External Secrets for CNPG credential management:

#### 3.1 Enable External Secrets

```yaml
# cluster.yaml
external_secrets_enabled: true
external_secrets_provider: "kubernetes"  # Start with built-in generator
```

#### 3.2 Password Generator for CNPG

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/externalsecret-db.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and external_secrets_enabled | default(false) %#
---
#| Password Generator for Keycloak database credentials #|
apiVersion: generators.external-secrets.io/v1alpha1
kind: Password
metadata:
  name: keycloak-db-password-generator
spec:
  length: 32
  digits: 5
  symbols: 5
  noUpper: false
  allowRepeat: true
---
#| ExternalSecret that generates and manages Keycloak DB password #|
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: keycloak-db-credentials
  labels:
    cnpg.io/reload: "true"  #| Trigger CNPG credential reload on change #|
spec:
  refreshInterval: "24h"
  target:
    name: keycloak-db-secret
    creationPolicy: Merge
  dataFrom:
    - sourceRef:
        generatorRef:
          kind: Password
          name: keycloak-db-password-generator
#% endif %#
```

**Note:** This requires removing the manual `keycloak_db_password` from cluster.yaml and letting ESO manage it.

---

## 4. Summary of Recommended Changes

### High Priority (Implement Now)

| Change | File(s) | Effort |
| ------ | ------- | ------ |
| Add CNPG operator egress policy | `networkpolicy-operator.yaml.j2` | Low |
| Add Keycloak PostgreSQL policies | `networkpolicy-postgres.yaml.j2`, `networkpolicy-postgres-egress.yaml.j2` | Low |
| Update kustomization to include policies | Multiple `kustomization.yaml.j2` | Low |

### Medium Priority (Consider)

| Change | File(s) | Effort |
| ------ | ------- | ------ |
| Add manual PodMonitor (replaces deprecated flag) | `podmonitor-instances.yaml.j2` | Low |
| Add failover/fencing alerts | `prometheusrule.yaml.j2` | Low |
| Custom metrics queries | `configmap-custom-metrics.yaml.j2` | Medium |

### Low Priority (Skip Unless Needed)

| Change | Reason to Skip |
| ------ | -------------- |
| TLS on metrics port | Adds complexity, internal traffic only |
| External Secrets integration | SOPS works well, no Vault infrastructure |
| Metrics caching tuning | Default 30s TTL is appropriate |

---

## 5. Implementation Steps

### Step 1: Add Cilium Network Policies

```bash
# Create operator network policy
cat > templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/networkpolicy-operator.yaml.j2 << 'EOF'
# [Content from section 2.1]
EOF

# Create Keycloak PostgreSQL policies
cat > templates/config/kubernetes/apps/identity/keycloak/app/networkpolicy-postgres.yaml.j2 << 'EOF'
# [Content from section 2.2]
EOF

cat > templates/config/kubernetes/apps/identity/keycloak/app/networkpolicy-postgres-egress.yaml.j2 << 'EOF'
# [Content from section 2.4]
EOF
```

### Step 2: Update Kustomizations

Add network policy resources to:
- `templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/kustomization.yaml.j2`
- `templates/config/kubernetes/apps/identity/keycloak/app/kustomization.yaml.j2`

### Step 3: Add PodMonitor for Instances

```bash
cat > templates/config/kubernetes/apps/cnpg-system/cloudnative-pg/app/podmonitor-instances.yaml.j2 << 'EOF'
# [Content from section 1.1]
EOF
```

### Step 4: Regenerate and Deploy

```bash
task configure
task reconcile

# Verify policies in audit mode
hubble observe --namespace identity --verdict DROPPED
hubble observe --namespace cnpg-system --verdict DROPPED
```

---

## 6. Verification Commands

```bash
# Check network policies applied
kubectl get ciliumnetworkpolicies -A | grep -E "cnpg|keycloak"

# Verify operator can reach cluster pods (should show FORWARDED)
hubble observe --from-pod cnpg-system/ --to-port 8000

# Verify Keycloak can reach PostgreSQL
hubble observe --from-pod identity/ --to-port 5432

# Check PodMonitor is scraping
kubectl get podmonitor -n cnpg-system

# Verify Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets and search for "cnpg"
```

---

## References

- [CloudNativePG Monitoring](https://cloudnative-pg.io/docs/1.28/monitoring)
- [CloudNativePG Cilium Integration](https://cloudnative-pg.io/docs/1.28/cncf-projects/cilium)
- [CloudNativePG External Secrets](https://cloudnative-pg.io/docs/1.28/cncf-projects/external-secrets)
- [Cilium Network Policy Editor](https://editor.networkpolicy.io/)
- [Project CNPG Implementation Guide](./cnpg-implementation.md)
- [Project Cilium Network Policies Research](../research/cilium-network-policies-jan-2026.md)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-07 | Initial research and recommendations document created |
