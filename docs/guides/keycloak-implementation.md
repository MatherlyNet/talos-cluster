# Keycloak Implementation Guide

> **Created:** January 2026
> **Status:** Templates Complete ✅ (January 6, 2026)
> **Dependencies:** PostgreSQL (CNPG or embedded), Gateway API HTTPRoute, TLS certificates
> **Effort:** ~1-2 hours remaining (deployment and realm setup)

---

## Overview

This guide implements **Keycloak** as the OIDC provider for the cluster, enabling:

- **JWT SecurityPolicy:** API/service-to-service authentication via Bearer tokens
- **OIDC SecurityPolicy:** Web browser SSO with session cookies
- **OAuth2-Proxy ext_authz:** Claims forwarding to backends

### Why Keycloak?

| Feature | Benefit |
| ------- | ------- |
| **Open Source** | Apache 2.0 license, no vendor lock-in |
| **Standards Compliant** | OAuth 2.0, OIDC, SAML 2.0 |
| **Production Ready** | Battle-tested, used by Red Hat, CNCF incubation |
| **Kubernetes Native** | Official Operator with CRD-based deployment |
| **Self-Hosted** | Data sovereignty, no external dependencies |

### Version Information (January 2026)

| Component | Version | Notes |
| --------- | ------- | ----- |
| **Keycloak** | 26.5.0 | Released January 6, 2026 - JWT Authorization Grant, MCP Auth Server, OpenTelemetry |
| **Keycloak Operator** | 26.5.0 | CRD-based deployment (recommended) |
| **PostgreSQL** | 17.x | Via CloudNativePG or embedded |

---

## Architecture Decision

### Deployment Options Comparison

| Option | Pros | Cons | Recommendation |
| ------ | ---- | ---- | -------------- |
| **Keycloak Operator** | Official, CRD-based, version-matched, declarative | Requires PostgreSQL pre-provisioned | **Production** |
| **Codecentric Helm** | Community charts, familiar patterns | Chart version lags behind Keycloak releases | Development only |
| **Raw Manifests** | Full control | Manual updates, no lifecycle management | Not recommended |

**Recommendation:** Use the **Keycloak Operator** for this project because:
1. **Version alignment**: Operator releases match Keycloak versions exactly (26.5.0)
2. **Official support**: Maintained by the Keycloak team, not third-party
3. **Kubernetes-native**: Uses CRDs (`Keycloak`, `KeycloakRealmImport`) for declarative configuration
4. **Day-2 operations**: Better lifecycle management, upgrades, and reconciliation
5. **No OLM required**: kubectl-based installation works on vanilla Kubernetes

### Database Options

| Option | Pros | Cons | Recommendation |
| ------ | ---- | ---- | -------------- |
| **CloudNativePG (CNPG)** | Production-grade, HA, backups | Additional CRD to manage | Production |
| **Embedded PostgreSQL** | Simple, no external deps | Not for production, ephemeral | Development |
| **External PostgreSQL** | Managed service | Egress, cost | Cloud deployments |

**Recommendation:** Start with **embedded PostgreSQL** for initial setup, migrate to **CloudNativePG** for production.

---

## Configuration Variables

### Required Variables (cluster.yaml)

```yaml
# =============================================================================
# KEYCLOAK OIDC PROVIDER - Identity and Access Management
# =============================================================================
# Keycloak provides OIDC/OAuth2 authentication for JWT SecurityPolicy and
# OIDC SecurityPolicy. Deploys in the 'identity' namespace using the
# official Keycloak Operator.
# REF: https://www.keycloak.org/operator/installation
# REF: docs/guides/keycloak-implementation.md

# -- Enable Keycloak deployment
#    (OPTIONAL) / (DEFAULT: false)
keycloak_enabled: false

# -- Keycloak subdomain (creates auth.${cloudflare_domain})
#    (OPTIONAL) / (DEFAULT: "auth")
keycloak_subdomain: "auth"

# -- Keycloak realm name (for application tokens)
#    (OPTIONAL) / (DEFAULT: cluster name or "matherlynet")
keycloak_realm: "matherlynet"

# -- Keycloak admin password (SOPS-encrypted)
#    (REQUIRED when keycloak_enabled: true)
#    Generate with: openssl rand -base64 24
#    Note: Admin username is always "admin" (operator default)
keycloak_admin_password: "ENC[AES256_GCM,...]"

# -- Keycloak database mode: "embedded" or "cnpg"
#    embedded: Uses in-cluster PostgreSQL StatefulSet (dev/testing)
#    cnpg: Uses CloudNativePG Cluster (production)
#    (OPTIONAL) / (DEFAULT: "embedded")
keycloak_db_mode: "embedded"

# -- PostgreSQL credentials (SOPS-encrypted)
#    (REQUIRED when keycloak_enabled: true)
keycloak_db_user: "keycloak"
keycloak_db_password: "ENC[AES256_GCM,...]"
keycloak_db_name: "keycloak"

# -- Keycloak storage size (for PostgreSQL PVC)
#    (OPTIONAL) / (DEFAULT: "5Gi")
keycloak_storage_size: "5Gi"

# -- Keycloak replicas (1 for dev, 2+ for HA)
#    (OPTIONAL) / (DEFAULT: 1)
keycloak_replicas: 1

# -- Keycloak Operator version
#    (OPTIONAL) / (DEFAULT: "26.5.0")
keycloak_operator_version: "26.5.0"
```

### Derived Variables (plugin.py)

Add to `templates/scripts/plugin.py`:

```python
# Keycloak - enabled when keycloak_enabled is true
keycloak_enabled = data.get("keycloak_enabled", False)
variables["keycloak_enabled"] = keycloak_enabled

# Derive full hostname
if keycloak_enabled:
    keycloak_subdomain = data.get("keycloak_subdomain", "auth")
    cloudflare_domain = data.get("cloudflare_domain", "")
    keycloak_hostname = f"{keycloak_subdomain}.{cloudflare_domain}"
    variables["keycloak_hostname"] = keycloak_hostname

    # OIDC endpoints for SecurityPolicy integration
    keycloak_realm = data.get("keycloak_realm", "matherlynet")
    variables["keycloak_issuer_url"] = f"https://{keycloak_hostname}/realms/{keycloak_realm}"
    variables["keycloak_jwks_uri"] = f"https://{keycloak_hostname}/realms/{keycloak_realm}/protocol/openid-connect/certs"

    # Operator version
    variables["keycloak_operator_version"] = data.get("keycloak_operator_version", "26.5.0")
```

---

## Template Implementation

### Directory Structure

```
templates/config/kubernetes/apps/identity/
├── kustomization.yaml.j2
├── namespace.yaml.j2
└── keycloak/
    ├── ks.yaml.j2                        # Two Kustomizations: operator + instance
    ├── operator/
    │   ├── kustomization.yaml.j2
    │   └── keycloak-operator.yaml.j2     # CRDs + Operator Deployment
    └── app/
        ├── kustomization.yaml.j2
        ├── keycloak-cr.yaml.j2           # Keycloak Custom Resource
        ├── secret.sops.yaml.j2           # Admin & DB credentials
        ├── httproute.yaml.j2             # Gateway API routing
        └── postgres-statefulset.yaml.j2  # Only for embedded mode
```

> **Note:** The CRD split pattern is used here (like tuppr/rustfs) to ensure CRDs are installed before CRs are created. This prevents "no matches for kind 'Keycloak'" errors.

### Step 1: Create Namespace Kustomization

**File:** `templates/config/kubernetes/apps/identity/kustomization.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: identity

components:
  - ../../components/sops

resources:
  - ./namespace.yaml
  - ./keycloak/ks.yaml
#% endif %#
```

### Step 2: Create Namespace

**File:** `templates/config/kubernetes/apps/identity/namespace.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: identity
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
#% endif %#
```

### Step 3: Create Flux Kustomizations (CRD Split Pattern)

**File:** `templates/config/kubernetes/apps/identity/keycloak/ks.yaml.j2`

> **Critical Pattern:** This uses two Kustomizations following the CRD split pattern from tuppr/rustfs. The operator Kustomization installs CRDs and waits for health, then the instance Kustomization creates the Keycloak CR.

```yaml
#% if keycloak_enabled | default(false) %#
---
#| First Kustomization: Operator + CRDs (must be healthy before CRs can be created) #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: keycloak-operator
spec:
  dependsOn:
    - name: coredns
      namespace: kube-system
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: keycloak-operator
      namespace: identity
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/identity/keycloak/operator
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: identity
  timeout: 10m
  wait: true
---
#| Second Kustomization: Keycloak CR + HTTPRoute (depends on operator being ready) #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: keycloak
spec:
  dependsOn:
    - name: keycloak-operator
    - name: cert-manager
      namespace: cert-manager
  healthChecks:
    - apiVersion: k8s.keycloak.org/v2alpha1
      kind: Keycloak
      name: keycloak
      namespace: identity
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/identity/keycloak/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: identity
  timeout: 15m
  wait: true
#% endif %#
```

### Step 4: Create Operator Kustomization

**File:** `templates/config/kubernetes/apps/identity/keycloak/operator/kustomization.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./keycloak-operator.yaml
#% endif %#
```

### Step 5: Create Keycloak Operator with CRDs

**File:** `templates/config/kubernetes/apps/identity/keycloak/operator/keycloak-operator.yaml.j2`

> **Note:** CRDs are applied directly as raw manifests (like flux-operator pattern). The operator image version matches the CRD version for compatibility.

```yaml
#% if keycloak_enabled | default(false) %#
---
#| ============================================================================= #|
#| KEYCLOAK OPERATOR - CRDs + Deployment                                          #|
#| Source: https://github.com/keycloak/keycloak-k8s-resources/tree/#{ keycloak_operator_version | default('26.5.0') }#/kubernetes #|
#| ============================================================================= #|
#| CRDs are installed first (Keycloak, KeycloakRealmImport), then the operator    #|
#| The operator watches the namespace where it's deployed                         #|
#| ============================================================================= #|
#| NOTE: For production, consider pre-installing CRDs via:                        #|
#|   kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.0/kubernetes/keycloaks.k8s.keycloak.org-v1.yml     #|
#|   kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.0/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml #|
#| ============================================================================= #|
#| Keycloak Operator - Watches the identity namespace #|
#| Source: https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/#{ keycloak_operator_version | default('26.5.0') }#/kubernetes/kubernetes.yml #|
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keycloak-operator
  namespace: identity
  labels:
    app.kubernetes.io/name: keycloak-operator
    app.kubernetes.io/version: "#{ keycloak_operator_version | default('26.5.0') }#"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: keycloak-operator-clusterrole
rules:
  - apiGroups:
      - ""
    resources:
      - namespaces
    verbs:
      - get
      - list
  - apiGroups:
      - k8s.keycloak.org
    resources:
      - keycloaks
      - keycloaks/status
      - keycloaks/finalizers
      - keycloakrealmimports
      - keycloakrealmimports/status
      - keycloakrealmimports/finalizers
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - patch
      - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloak-operator-clusterrole-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: keycloak-operator-clusterrole
subjects:
  - kind: ServiceAccount
    name: keycloak-operator
    namespace: identity
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: keycloak-operator-role
  namespace: identity
rules:
  - apiGroups:
      - ""
    resources:
      - secrets
      - services
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - patch
      - update
  - apiGroups:
      - apps
    resources:
      - statefulsets
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - patch
      - update
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - patch
      - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: keycloak-operator-role-binding
  namespace: identity
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: keycloak-operator-role
subjects:
  - kind: ServiceAccount
    name: keycloak-operator
    namespace: identity
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak-operator
  namespace: identity
  labels:
    app.kubernetes.io/name: keycloak-operator
    app.kubernetes.io/version: "#{ keycloak_operator_version | default('26.5.0') }#"
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: keycloak-operator
  template:
    metadata:
      labels:
        app.kubernetes.io/name: keycloak-operator
    spec:
      serviceAccountName: keycloak-operator
      containers:
        - name: keycloak-operator
          image: "quay.io/keycloak/keycloak-operator:#{ keycloak_operator_version | default('26.5.0') }#"
          imagePullPolicy: IfNotPresent
          env:
            - name: KUBERNETES_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: RELATED_IMAGE_KEYCLOAK
              value: "quay.io/keycloak/keycloak:#{ keycloak_operator_version | default('26.5.0') }#"
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /q/health/live
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /q/health/ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
#% endif %#
```

### Step 6: Create Keycloak Custom Resource

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/keycloak-cr.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: keycloak
  namespace: identity
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/version: "#{ keycloak_operator_version | default('26.5.0') }#"
spec:
  #| Number of Keycloak instances #|
  instances: #{ keycloak_replicas | default(1) }#

  #| Database configuration #|
  db:
    vendor: postgres
    host: keycloak-postgres
    port: 5432
    database: #{ keycloak_db_name | default('keycloak') }#
    usernameSecret:
      name: keycloak-db-secret
      key: username
    passwordSecret:
      name: keycloak-db-secret
      key: password

  #| HTTP configuration - TLS termination at gateway #|
  http:
    httpEnabled: true
    httpPort: 8080
    httpsPort: 8443

  #| Hostname configuration #|
  hostname:
    hostname: "#{ keycloak_hostname }#"
    strict: false
    backchannelDynamic: true

  #| Proxy configuration for Gateway API #|
  proxy:
    headers: xforwarded

  #| Disable operator-managed ingress (using HTTPRoute instead) #|
  ingress:
    enabled: false

  #| Feature flags #|
  features:
    enabled:
      - token-exchange
      - admin-fine-grained-authz

  #| Additional server options #|
  additionalOptions:
    - name: health-enabled
      value: "true"
    - name: metrics-enabled
      value: "true"
    - name: cache
      value: "ispn"
    - name: cache-stack
      value: "kubernetes"

  #| Resource limits #|
  resources:
    requests:
      cpu: 500m
      memory: 1700Mi
    limits:
      cpu: 2000m
      memory: 2Gi

  #| Startup configuration #|
  startOptimized: false

  #| Unsupported - advanced customization (use sparingly) #|
  unsupported:
    podTemplate:
      spec:
        containers:
          - name: keycloak
            env:
              - name: JAVA_OPTS_APPEND
                value: "-Djgroups.dns.query=keycloak-discovery.identity.svc.cluster.local"
#% endif %#
```

### Step 7: Create Secrets

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/secret.sops.yaml.j2`

> **IMPORTANT:** The `keycloak-initial-admin` secret is **pre-created by Flux** with credentials from `cluster.yaml`.
> The Keycloak operator checks for this secret BEFORE creating the instance - if it exists, the operator
> uses the pre-created credentials instead of generating random ones.
> REF: https://www.keycloak.org/operator/basic-deployment
> REF: https://github.com/keycloak/keycloak/issues/9843

```yaml
#% if keycloak_enabled | default(false) %#
---
#| Initial admin credentials - pre-created for Keycloak Operator #|
#| Secret name MUST be: {keycloak-cr-name}-initial-admin #|
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-initial-admin
  namespace: identity
type: kubernetes.io/basic-auth
stringData:
  username: "admin"
  password: "#{ keycloak_admin_password }#"
---
#| Database credentials for PostgreSQL connection #|
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-secret
  namespace: identity
type: Opaque
stringData:
  username: "#{ keycloak_db_user | default('keycloak') }#"
  password: "#{ keycloak_db_password }#"
#% endif %#
```

### Step 8: Create HTTPRoute

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/httproute.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: keycloak
  namespace: identity
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "#{ keycloak_hostname }#"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        #| Service created by operator: keycloak-service #|
        - name: keycloak-service
          port: 8080
#% endif %#
```

### Step 9: Create Embedded PostgreSQL (Development)

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/postgres-statefulset.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and (keycloak_db_mode | default('embedded')) == 'embedded' %#
---
#| WARNING: Embedded PostgreSQL is for development/testing only #|
#| For production, use CloudNativePG (keycloak_db_mode: "cnpg") #|
apiVersion: v1
kind: Service
metadata:
  name: keycloak-postgres
  namespace: identity
  labels:
    app: keycloak-postgres
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: keycloak-postgres
---
#| Headless service for StatefulSet DNS #|
apiVersion: v1
kind: Service
metadata:
  name: keycloak-discovery
  namespace: identity
  labels:
    app: keycloak-postgres
spec:
  type: ClusterIP
  clusterIP: None
  ports:
    - port: 7800
      name: jgroups
  selector:
    app.kubernetes.io/name: keycloak
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak-postgres
  namespace: identity
spec:
  serviceName: keycloak-postgres
  replicas: 1
  selector:
    matchLabels:
      app: keycloak-postgres
  template:
    metadata:
      labels:
        app: keycloak-postgres
    spec:
      containers:
        - name: postgres
          image: postgres:17-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: "#{ keycloak_db_name | default('keycloak') }#"
            - name: POSTGRES_USER
              value: "#{ keycloak_db_user | default('keycloak') }#"
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-db-secret
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - #{ keycloak_db_user | default('keycloak') }#
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - #{ keycloak_db_user | default('keycloak') }#
            initialDelaySeconds: 5
            periodSeconds: 5
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: "#{ storage_class | default('local-path') }#"
        resources:
          requests:
            storage: "#{ keycloak_storage_size | default('5Gi') }#"
#% endif %#
```

### Step 10: Create App Kustomization

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/kustomization.yaml.j2`

> **Note:** The `app/` directory contains only the Keycloak CR and supporting resources, not the operator (which is in `operator/`).

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./secret.sops.yaml
#% if (keycloak_db_mode | default('embedded')) == 'embedded' %#
  - ./postgres-statefulset.yaml
#% endif %#
  - ./keycloak-cr.yaml
  - ./httproute.yaml
#% endif %#
```

### Step 11: Update Root Kustomization

**Edit:** `templates/config/kubernetes/apps/kustomization.yaml.j2`

Add the identity namespace:

```yaml
resources:
  # ... existing resources ...
#% if keycloak_enabled | default(false) %#
  - ./identity
#% endif %#
```

---

## Realm and Client Configuration

After Keycloak is deployed, configure it for JWT SecurityPolicy integration.

### Step 1: Access Keycloak Admin Console

```bash
# Port-forward to access locally (if HTTPRoute not yet working)
kubectl -n identity port-forward svc/keycloak-service 8080:8080

# Open browser: http://localhost:8080
# Login with admin credentials (username: admin, password: from keycloak_admin_password)
```

### Step 2: Create Realm

1. Click **Create Realm**
2. **Realm name:** `matherlynet` (or your `keycloak_realm` value)
3. Click **Create**

### Step 3: Create Client for API Authentication

1. Navigate to **Clients** -> **Create client**
2. **Client type:** OpenID Connect
3. **Client ID:** `api-clients`
4. Click **Next**
5. **Client authentication:** OFF (public client for JWT)
6. **Authorization:** OFF
7. **Authentication flow:** Check only **Direct access grants** (for testing)
8. Click **Next**
9. **Valid redirect URIs:** `*` (or specific app URIs)
10. Click **Save**

### Step 4: Configure Token Mappers

Add groups and custom claims to tokens:

1. Go to **Clients** -> `api-clients` -> **Client scopes**
2. Click `api-clients-dedicated`
3. Click **Add mapper** -> **By configuration**
4. Select **Group Membership**:
   - **Name:** `groups`
   - **Token Claim Name:** `groups`
   - **Full group path:** OFF
   - Click **Save**

### Step 5: Create Test User

1. Navigate to **Users** -> **Add user**
2. **Username:** `testuser`
3. **Email:** `test@example.com`
4. Click **Create**
5. Go to **Credentials** tab -> **Set password**
6. Set password and disable **Temporary**

### Step 6: Test Token Generation

```bash
# Get a test token
TOKEN=$(curl -s -X POST \
  "https://auth.matherly.net/realms/matherlynet/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=api-clients" \
  -d "username=testuser" \
  -d "password=yourpassword" | jq -r '.access_token')

# Decode and verify token claims
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq
```

---

## Automated Realm Import (Optional)

For GitOps-managed realm configuration, use the `KeycloakRealmImport` CRD.

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/realm-import.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and keycloak_realm_import | default(false) %#
---
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: #{ keycloak_realm | default('matherlynet') }#-realm
  namespace: identity
spec:
  keycloakCRName: keycloak
  realm:
    realm: "#{ keycloak_realm | default('matherlynet') }#"
    enabled: true
    displayName: "#{ keycloak_realm | default('matherlynet') | title }#"

    #| Default token settings #|
    accessTokenLifespan: 300
    ssoSessionIdleTimeout: 1800
    ssoSessionMaxLifespan: 36000

    #| Clients #|
    clients:
      - clientId: "api-clients"
        enabled: true
        publicClient: true
        directAccessGrantsEnabled: true
        standardFlowEnabled: false
        implicitFlowEnabled: false
        protocol: "openid-connect"
        redirectUris:
          - "*"
        webOrigins:
          - "*"
        defaultClientScopes:
          - "openid"
          - "profile"
          - "email"
#% endif %#
```

**Note:** KeycloakRealmImport only creates new realms; it cannot update existing ones. For updates, use the Admin Console or Admin API.

---

## Integration with Envoy Gateway SecurityPolicy

### JWT Authentication (Service-to-Service)

For API authentication using Bearer tokens, configure a JWT SecurityPolicy:

**File:** `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-jwt.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-keycloak
  namespace: network
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: protected-api
  jwt:
    providers:
      - name: keycloak
        issuer: "#{ keycloak_issuer_url }#"
        remoteJWKS:
          uri: "#{ keycloak_jwks_uri }#"
        claimToHeaders:
          - claim: "preferred_username"
            header: "X-Username"
          - claim: "groups"
            header: "X-User-Groups"
#% endif %#
```

### OIDC Authentication (Browser SSO)

For web application SSO with session cookies:

**File:** `templates/config/kubernetes/apps/network/envoy-gateway/app/securitypolicy-oidc.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-oidc-client-secret
  namespace: network
type: Opaque
stringData:
  client-secret: "#{ keycloak_oidc_client_secret }#"
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: oidc-keycloak
  namespace: network
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: protected-web-app
  oidc:
    provider:
      issuer: "#{ keycloak_issuer_url }#"
      authorizationEndpoint: "#{ keycloak_issuer_url }#/protocol/openid-connect/auth"
      tokenEndpoint: "#{ keycloak_issuer_url }#/protocol/openid-connect/token"
    clientID: "web-app"
    clientSecret:
      name: keycloak-oidc-client-secret
    redirectURL: "https://app.#{ cloudflare_domain }#/oauth2/callback"
    logoutPath: "/logout"
#% endif %#
```

### Verify SecurityPolicy

```bash
# Check SecurityPolicy is created
kubectl get securitypolicy -n network

# Describe for details
kubectl describe securitypolicy jwt-keycloak -n network
```

---

## Deployment

### Step 1: Configure Variables

Edit `cluster.yaml`:

```yaml
# Enable Keycloak
keycloak_enabled: true
keycloak_subdomain: "auth"
keycloak_realm: "matherlynet"
keycloak_admin_password: "your-secure-password"  # Will be SOPS-encrypted
keycloak_db_mode: "embedded"  # Use "cnpg" for production
keycloak_db_user: "keycloak"
keycloak_db_password: "your-db-password"  # Will be SOPS-encrypted
keycloak_replicas: 1
keycloak_operator_version: "26.5.0"
```

### Step 2: Generate and Encrypt

```bash
# Regenerate templates
task configure

# Verify secrets are encrypted
cat kubernetes/apps/identity/keycloak/app/secret.sops.yaml
```

### Step 3: Deploy

```bash
# Commit and push
git add -A
git commit -m "feat: add Keycloak OIDC provider using official Operator"
git push

# Reconcile
task reconcile

# Watch deployment
kubectl -n identity get pods -w
```

### Step 4: Verify

```bash
# Check operator is running
kubectl -n identity get pods -l app.kubernetes.io/name=keycloak-operator

# Check Keycloak CR status
kubectl -n identity get keycloak keycloak -o yaml | yq '.status'

# Check Keycloak pods (created by operator)
kubectl -n identity get pods -l app.kubernetes.io/name=keycloak

# Check Keycloak logs
kubectl -n identity logs -l app.kubernetes.io/name=keycloak -f

# Test OIDC discovery endpoint
curl https://auth.matherly.net/realms/matherlynet/.well-known/openid-configuration | jq

# Test JWKS endpoint (used by SecurityPolicy)
curl https://auth.matherly.net/realms/matherlynet/protocol/openid-connect/certs | jq
```

---

## Production Considerations

### High Availability

For production, configure:

```yaml
# cluster.yaml
keycloak_replicas: 2  # Minimum for HA
keycloak_db_mode: "cnpg"  # CloudNativePG for database HA
```

The Keycloak Operator automatically configures:
- Pod anti-affinity across nodes and zones
- Infinispan distributed cache for session clustering
- JGroups DNS-based discovery via headless service

### CloudNativePG Integration

When `keycloak_db_mode: "cnpg"`, use the shared CloudNativePG operator. See the **[CloudNativePG Implementation Guide](./cnpg-implementation.md)** for full operator deployment.

**Prerequisites:**
- Deploy CNPG operator first: `cnpg_enabled: true` in cluster.yaml
- The CNPG guide includes a complete Keycloak Cluster CR example

**File:** `templates/config/kubernetes/apps/identity/keycloak/app/cnpg-cluster.yaml.j2`

```yaml
#% if keycloak_enabled | default(false) and (keycloak_db_mode | default('embedded')) == 'cnpg' %#
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: keycloak-postgres
  namespace: identity
spec:
  instances: #{ keycloak_db_instances | default(3) }#
  imageName: #{ cnpg_postgres_image | default('ghcr.io/cloudnative-pg/postgresql:17.2') }#

  bootstrap:
    initdb:
      database: #{ keycloak_db_name | default('keycloak') }#
      owner: #{ keycloak_db_user | default('keycloak') }#
      secret:
        name: keycloak-db-secret

  storage:
    size: #{ keycloak_storage_size | default('10Gi') }#
    storageClass: #{ cnpg_storage_class | default(storage_class) | default('local-path') }#

  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 1000m

  monitoring:
    enablePodMonitor: #{ 'true' if monitoring_enabled | default(false) else 'false' }#

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"

  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname

#% if cnpg_backup_enabled | default(false) %#
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/keycloak"
      endpointURL: "http://rustfs.storage.svc.cluster.local:9000"
      s3Credentials:
        accessKeyId:
          name: cnpg-backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: cnpg-backup-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
    retentionPolicy: "7d"
#% endif %#
#% endif %#
```

### TLS Configuration

For internal TLS between Gateway and Keycloak, use BackendTLSPolicy:

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: BackendTLSPolicy
metadata:
  name: keycloak-tls
  namespace: identity
spec:
  targetRefs:
    - group: ""
      kind: Service
      name: keycloak-service
  validation:
    caCertificateRefs:
      - name: keycloak-ca-cert
        kind: ConfigMap
    hostname: keycloak.identity.svc.cluster.local
```

### Backup Strategy

With CloudNativePG, configure scheduled backups:

```yaml
backup:
  barmanObjectStore:
    destinationPath: "s3://keycloak-backups/pgdata"
    endpointURL: "http://rustfs.storage.svc.cluster.local:9000"
    s3Credentials:
      accessKeyId:
        name: cnpg-backup-credentials
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: cnpg-backup-credentials
        key: SECRET_ACCESS_KEY
  retentionPolicy: "7d"
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| Operator pod CrashLoopBackOff | Missing CRDs | Apply CRDs first, restart operator |
| Operator pod Error: read-only filesystem | Missing /tmp emptyDir volume | Add emptyDir volume for Vert.x cache |
| Operator RBAC 403 errors | Missing RBAC permissions | See RBAC requirements below |
| Keycloak CR not progressing | Database not ready | Check PostgreSQL pod/service |
| 502 Bad Gateway | HTTPRoute service name wrong | Use `keycloak-service` (operator default) |
| JWKS fetch timeout | Network policy blocking | Add egress rule for Keycloak |
| Token validation fails | Issuer mismatch | Verify realm URL matches config |
| Admin login fails | Wrong credentials | Verify `keycloak-initial-admin` secret matches `keycloak_admin_password` in cluster.yaml |
| Clustering issues | JGroups DNS not resolving | Check headless service `keycloak-discovery` |
| Unrecognized config key warning | Normal - bundle config for OLM | Can be safely ignored |
| `hostname-backchannel-dynamic must be false` | hostname not full URL | Use `https://hostname` when `backchannelDynamic: true` |
| `secrets "keycloak-initial-admin" already exists` | Race condition on first deploy | Pre-created secret is correct - restart operator to adopt it |
| Operator exhausted retries | Previous error blocked reconciliation | Restart operator: `kubectl rollout restart deployment/keycloak-operator -n identity` |

### RBAC Requirements (v26.5.0)

The Keycloak operator requires specific RBAC permissions. If you see 403 errors in logs, ensure these are configured:

**ClusterRole requirements:**
- `apiextensions.k8s.io/customresourcedefinitions` - get, list, watch (for ServiceMonitor CRD detection)
- `k8s.keycloak.org/*` - full CRUD for Keycloak CRs
- `""/namespaces` - get, list

**Namespace Role requirements:**
- `""/configmaps, secrets, services` - full CRUD
- `""/pods` - list
- `""/pods/log` - get
- `apps/statefulsets` - full CRUD
- `networking.k8s.io/ingresses, networkpolicies` - full CRUD
- `batch/jobs` - full CRUD
- `monitoring.coreos.com/servicemonitors` - full CRUD (if Prometheus installed)

**REF:** https://github.com/keycloak/keycloak-k8s-resources/blob/26.5.0/kubernetes/kubernetes.yml

### Debug Commands

```bash
# Check operator logs
kubectl -n identity logs -l app.kubernetes.io/name=keycloak-operator --tail=100

# Check Keycloak CR status
kubectl -n identity get keycloak keycloak -o yaml

# Check Keycloak pod status
kubectl -n identity describe pod -l app.kubernetes.io/name=keycloak

# View Keycloak logs
kubectl -n identity logs -l app.kubernetes.io/name=keycloak --tail=100

# Check PostgreSQL
kubectl -n identity logs keycloak-postgres-0

# Test database connectivity
kubectl -n identity exec -it keycloak-postgres-0 -- psql -U keycloak -c "SELECT 1"

# Test OIDC endpoints from within cluster
kubectl run curl-test --rm -it --image=curlimages/curl -- \
  curl -v http://keycloak-service.identity.svc:8080/realms/matherlynet/.well-known/openid-configuration

# Check operator-created resources
kubectl -n identity get statefulset,service,secret -l app.kubernetes.io/managed-by=keycloak-operator
```

---

## Security Considerations

### Admin Credentials

- **Pre-created secret approach:** The `keycloak-initial-admin` secret is created by Flux with credentials from `cluster.yaml`
- The operator detects the pre-existing secret and uses those credentials instead of generating random ones
- Admin credentials are managed via GitOps (SOPS-encrypted in `cluster.yaml`)
- Username: `admin` (hardcoded for consistency)
- Password: Set via `keycloak_admin_password` in `cluster.yaml`
- Enable MFA for admin accounts after first login

### Network Security

When network policies are enabled, Keycloak needs:
- Ingress from Envoy Gateway pods
- Egress to PostgreSQL
- Egress to external IdPs (if federated)

### Token Security

- Configure appropriate token lifetimes in realm settings
- Use short-lived access tokens (5-15 minutes)
- Use refresh tokens for long sessions

---

## Keycloak 26.5.0 New Features

Key features available in this version:

| Feature | Description |
| ------- | ----------- |
| **JWT Authorization Grant** | RFC 7523 support for OAuth 2.0 token requests using signed JWT assertions |
| **MCP Authorization Server** | Keycloak can serve as an auth server for Model Context Protocol servers |
| **Kubernetes Token Auth** | Clients can authenticate using Kubernetes service account tokens |
| **OpenTelemetry** | Unified observability for metrics and logging |
| **Workflows (preview)** | Automate administrative tasks within a realm |

---

## References

### External Documentation
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak Operator Installation](https://www.keycloak.org/operator/installation)
- [Keycloak Operator Basic Deployment](https://www.keycloak.org/operator/basic-deployment)
- [Keycloak Operator Advanced Configuration](https://www.keycloak.org/operator/advanced-configuration)
- [Keycloak K8s Resources (GitHub)](https://github.com/keycloak/keycloak-k8s-resources)
- [Envoy Gateway OIDC Authentication](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)
- [Envoy Gateway JWT Authentication](https://gateway.envoyproxy.io/latest/tasks/security/jwt-authentication/)
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)

### Project Documentation
- [CloudNativePG Implementation](./cnpg-implementation.md) - PostgreSQL operator for production
- [JWT SecurityPolicy Implementation](./jwt-securitypolicy-implementation.md)
- [Native OIDC SecurityPolicy Implementation](./native-oidc-securitypolicy-implementation.md)
- [OAuth2-Proxy ext_authz Implementation](./oauth2-proxy-ext-authz-implementation.md)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01-06 | Refactored guide to use Keycloak Operator instead of Codecentric Helm chart |
| 2026-01 | Initial implementation guide created |
