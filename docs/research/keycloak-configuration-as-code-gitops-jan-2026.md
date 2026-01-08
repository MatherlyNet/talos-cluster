# Keycloak Configuration as Code - GitOps Integration Research

**Date:** January 2026
**Status:** Implemented - See `templates/config/kubernetes/apps/identity/keycloak/config/`
**Author:** Claude Code Research Agent
**Last Updated:** January 2026 (Implementation complete, validated against upstream docs)

## Executive Summary

This document investigates solutions for managing Keycloak realm configuration as code, addressing the limitation that the current `KeycloakRealmImport` CRD only supports one-time initial imports and cannot update existing realms.

**Recommendation:** Implement **keycloak-config-cli** as a Kubernetes Job triggered after Keycloak deployment. This provides:
- Declarative YAML/JSON configuration compatible with Keycloak export format
- Incremental updates to existing realms (not create-only like KeycloakRealmImport)
- GitOps-friendly workflow via Flux post-deployment Jobs
- Active maintenance with Keycloak 26.x support

> **DEPLOYMENT CONTEXT:** This is a greenfield deployment with no existing realm data to preserve. This simplifies implementation significantly - we can use a straightforward Job-based approach without complex migration or state management concerns.

## Problem Statement

### Current Implementation

The cluster currently uses the Keycloak Operator's `KeycloakRealmImport` CRD for realm configuration:

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: matherlynet-realm
spec:
  keycloakCRName: keycloak
  realm:
    realm: matherlynet
    # ... realm configuration
```

**Location:** `templates/config/kubernetes/apps/identity/keycloak/app/realm-import.sops.yaml.j2`

### Limitations

1. **One-Time Import Only:** The KeycloakRealmImport CR only supports initial realm creation. From the [official documentation](https://www.keycloak.org/operator/realm-import): "The Realm Import CR only supports creation of new realms and does not update or delete those."

2. **No Update Support:** If the realm already exists, the import is skipped. Any changes to the configuration require deleting and recreating the realm, which destroys all user data.

3. **No Sync Back:** Changes made directly in the Keycloak UI are not reflected in the CR, leading to configuration drift.

4. **Enterprise Limitation:** As noted in [community discussions](https://github.com/keycloak/keycloak/discussions/30643): "This makes the usage of KeycloakRealmImport operator not suitable in an enterprise context."

## Solution Options Evaluated

### Option 1: keycloak-config-cli (Recommended)

**Repository:** [adorsys/keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli)

#### Overview

keycloak-config-cli is a utility that ensures the desired configuration state for a realm based on JSON/YAML files. Unlike KeycloakRealmImport, it can update existing realms incrementally.

#### Key Features

| Feature | Description |
| --------- | ------------- |
| **Incremental Updates** | Updates existing realms without destroying data |
| **Variable Substitution** | Supports environment variables and Spring Boot properties |
| **Keycloak Export Format** | Uses the same JSON/YAML format as Keycloak's native export |
| **GitOps Compatible** | Configuration files stored in Git, applied via Jobs |
| **Parallel Processing** | Can import resources concurrently for performance |

#### Version Compatibility

- **Latest Version:** 6.4.0 (February 21, 2025)
- **Keycloak 26.x:** Fully supported as of version 6.3.0+
- **Support Policy:** Latest 4 Keycloak releases

#### Deployment Pattern

Run as a Kubernetes Job after Keycloak is ready:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: keycloak-config-apply
  namespace: identity
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: keycloak-config-cli
          image: adorsys/keycloak-config-cli:6.4.0-26.1.4
          env:
            # NOTE: Keycloak Operator creates service named "keycloak-service"
            # Verified in httproute.yaml.j2 - backendRefs target keycloak-service:8080
            - name: KEYCLOAK_URL
              value: "http://keycloak-service.identity.svc.cluster.local:8080"
            - name: KEYCLOAK_USER
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin-credentials
                  key: username
            - name: KEYCLOAK_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin-credentials
                  key: password
            - name: KEYCLOAK_AVAILABILITYCHECK_ENABLED
              value: "true"
            - name: KEYCLOAK_AVAILABILITYCHECK_TIMEOUT
              value: "120s"
            # NOTE: Env var name uses no underscore between VAR and SUBSTITUTION
            # REF: https://github.com/adorsys/keycloak-config-cli#variable-substitution
            - name: IMPORT_VARSUBSTITUTION_ENABLED
              value: "true"
            # JSON logging for Kubernetes log aggregation
            - name: SPRING_PROFILES_ACTIVE
              value: "json-log"
          volumeMounts:
            - name: realm-config
              mountPath: /config
      volumes:
        - name: realm-config
          configMap:
            name: keycloak-realm-config
```

> **IMPORTANT:** The Keycloak Operator creates a service named `keycloak-service` (not `keycloak`). This is verified in the existing `httproute.yaml.j2` which targets `keycloak-service:8080`.

#### Pros

- Mature, actively maintained (1000+ GitHub stars)
- Native update support for existing realms
- Remote state management prevents overwriting manual changes
- Uses familiar Keycloak JSON/YAML format
- Works with any Keycloak deployment (Operator, Helm, etc.)
- Can be triggered by Flux Kustomizations

#### Cons

- Requires running as a separate Job (not CRD-native)
- Additional container to maintain
- Requires admin credentials access
- Java-based (larger image size)

### Option 2: Keycloak Terraform Provider

**Repository:** [keycloak/terraform-provider-keycloak](https://github.com/keycloak/terraform-provider-keycloak)

#### Overview

The official Keycloak Terraform provider, now maintained by the Keycloak team. According to [community surveys](https://github.com/keycloak/keycloak/discussions/30643), it's the most popular tool with 51% adoption.

#### Key Features

- Declarative HCL configuration
- Full CRUD operations on all Keycloak resources
- State management via Terraform
- Plan/Apply workflow with drift detection

#### Example

```hcl
resource "keycloak_realm" "matherlynet" {
  realm   = "matherlynet"
  enabled = true

  login_theme = "keycloak"

  security_defenses {
    brute_force_detection {
      permanent_lockout = false
      max_failure_wait_seconds = 900
      failure_factor = 5
    }
  }
}

resource "keycloak_openid_client" "envoy_gateway" {
  realm_id  = keycloak_realm.matherlynet.id
  client_id = "envoy-gateway"
  enabled   = true

  access_type = "CONFIDENTIAL"
  standard_flow_enabled = true
}
```

#### Pros

- Official Keycloak project support
- Industry-standard IaC tool
- Full state management and drift detection
- Excellent documentation
- Works well with existing Terraform/OpenTofu workflows

#### Cons

- Requires Terraform state management
- Different configuration format than Keycloak exports
- Learning curve if not already using Terraform
- Doesn't integrate natively with Flux CD GitOps workflow
- Separation of concerns: mixing infrastructure and application config

### Option 3: Keycloak Realm Operator (Legacy)

**Repository:** [keycloak/keycloak-realm-operator](https://github.com/keycloak/keycloak-realm-operator)

#### Overview

A Kubernetes Operator forked from the legacy Keycloak Operator, designed to manage realms via CRDs. Positioned as a "temporary workaround" until the new operator supports User/Client CRDs.

#### CRDs Provided

- `ExternalKeycloak` - Connection to Keycloak instance
- `KeycloakRealm` - Realm configuration
- `KeycloakClient` - Client configuration
- `KeycloakUser` - User management

#### Limitations

- **Realm updates not supported:** "Realm updates to CRs are ignored—the operator treats realms as write-once resources"
- Last release: v1.0.0 (November 2022) - minimal maintenance
- Uses legacy `legacy.k8s.keycloak.org` API group
- Explicitly positioned as temporary

#### Verdict

**Not recommended** due to stale maintenance and lack of realm update support.

### Option 4: JAVA_OPTS OVERWRITE_EXISTING Workaround

#### Overview

A workaround that uses Keycloak's native import functionality with the `OVERWRITE_EXISTING` strategy via environment variables.

```yaml
env:
  - name: JAVA_OPTS_APPEND
    value: >-
      -Dkeycloak.migration.action=import
      -Dkeycloak.migration.provider=dir
      -Dkeycloak.migration.dir=/opt/keycloak/data/import
      -Dkeycloak.migration.strategy=OVERWRITE_EXISTING
```

#### Limitations

From the [documentation](https://rahulroyz.medium.com/update-keycloak-realm-configurations-using-import-feature-on-kubernetes-platform-b1b0ed85f7f7):

> "If you are making any manual realm configurations (like users, roles etc) outside the realm configuration JSONs, then this approach will clean up everything."

#### Verdict

**Not recommended** - destroys all manual configurations including users.

## Comparison Matrix

| Criteria | keycloak-config-cli | Terraform Provider | Realm Operator | OVERWRITE_EXISTING |
| --------- | ------------- | ------------- | ------------- | ------------- |
| Update existing realms | Yes | Yes | No | Yes (destructive) |
| Keycloak 26 support | Yes (6.3.0+) | Yes (5.0+) | Unknown | Yes |
| GitOps/Flux integration | Excellent (Job) | Moderate | Excellent (CRD) | Poor |
| Learning curve | Low | Moderate | Low | Low |
| Maintenance status | Active | Active (official) | Stale | N/A |
| Configuration format | Keycloak JSON/YAML | HCL | CRD YAML | Keycloak JSON |

## Recommended Implementation: keycloak-config-cli

### Architecture

```
                                    ┌─────────────────────────────────────┐
                                    │           Git Repository            │
                                    │  templates/config/kubernetes/apps/  │
                                    │        identity/keycloak/           │
                                    └──────────────┬──────────────────────┘
                                                   │
                                                   │ makejinja render
                                                   ▼
                                    ┌─────────────────────────────────────┐
                                    │    kubernetes/apps/identity/        │
                                    │         keycloak/app/               │
                                    │  ├── keycloak-cr.yaml               │
                                    │  ├── realm-config.yaml (ConfigMap)  │
                                    │  └── config-apply-job.yaml          │
                                    └──────────────┬──────────────────────┘
                                                   │
                                                   │ Flux sync
                                                   ▼
┌──────────────────┐    ┌─────────────────────────────────────────────────────────────┐
│  Flux Operator   │───▶│                    Kubernetes Cluster                        │
└──────────────────┘    │                                                              │
                        │  ┌─────────────────┐     ┌───────────────────────────────┐  │
                        │  │ Keycloak CR     │────▶│ Keycloak Pod                  │  │
                        │  │ (Operator)      │     │ (identity namespace)          │  │
                        │  └─────────────────┘     └───────────────────────────────┘  │
                        │                                        ▲                     │
                        │  ┌─────────────────┐                   │                     │
                        │  │ ConfigMap       │     ┌─────────────┴─────────────────┐  │
                        │  │ realm-config    │────▶│ keycloak-config-cli Job       │  │
                        │  │ (YAML config)   │     │ - Waits for Keycloak ready    │  │
                        │  └─────────────────┘     │ - Applies realm config        │  │
                        │                          │ - Tracks remote state         │  │
                        │                          └───────────────────────────────┘  │
                        └─────────────────────────────────────────────────────────────┘
```

### Implementation Approach (Streamlined)

> **GREENFIELD DEPLOYMENT:** No existing realm data to preserve. This enables a simple, direct implementation.

#### 1. SOPS Encryption for Client Secrets

The realm configuration contains sensitive data (`oidc_client_secret`, `google_client_secret`, etc.). Use SOPS-encrypted ConfigMap (`realm-config.sops.yaml.j2`) - Flux decrypts during reconciliation, maintaining encryption at rest in Git.

#### 2. Flux Kustomization Pattern

Add a third Kustomization for the config Job that depends on Keycloak being healthy:

```yaml
# In ks.yaml.j2
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: keycloak-config
spec:
  dependsOn:
    - name: keycloak
  path: ./kubernetes/apps/identity/keycloak/config
  wait: false  # Don't block on Job completion
```

#### 3. Job Re-triggering on Config Changes

Use the Flux force annotation to ensure the Job is recreated when configuration changes:

```yaml
metadata:
  annotations:
    kustomize.toolkit.fluxcd.io/force: "enabled"
```

### Implementation Plan

#### Phase 1: Configuration Structure

Convert the existing `realm-import.sops.yaml.j2` to a ConfigMap-based configuration:

**New Files:**
- `templates/config/kubernetes/apps/identity/keycloak/config/realm-config.sops.yaml.j2` - SOPS-encrypted ConfigMap with realm YAML
- `templates/config/kubernetes/apps/identity/keycloak/config/config-job.yaml.j2` - Kubernetes Job
- `templates/config/kubernetes/apps/identity/keycloak/config/kustomization.yaml.j2` - Kustomization for config resources

**Directory Structure (following CRD split pattern):**
```
keycloak/
├── ks.yaml.j2                    # Three Kustomizations: operator → keycloak → keycloak-config
├── operator/                      # Operator deployment
├── app/                           # Keycloak CR + HTTPRoute
│   ├── keycloak-cr.yaml.j2
│   ├── httproute.yaml.j2
│   └── secret.sops.yaml.j2
└── config/                        # NEW: keycloak-config-cli Job
    ├── kustomization.yaml.j2
    ├── realm-config.sops.yaml.j2  # Realm configuration (SOPS encrypted)
    └── config-job.yaml.j2         # keycloak-config-cli Job
```

#### Phase 2: Kubernetes Job Template (`config/config-job.yaml.j2`)

```yaml
#% if keycloak_enabled | default(false) %#
#| ============================================================================= #|
#| KEYCLOAK CONFIG CLI JOB - Configuration as Code for Keycloak Realms          #|
#| REF: https://github.com/adorsys/keycloak-config-cli                          #|
#| ============================================================================= #|
---
apiVersion: batch/v1
kind: Job
metadata:
  name: keycloak-config-apply
  namespace: identity
  labels:
    app.kubernetes.io/name: keycloak-config-cli
  annotations:
    kustomize.toolkit.fluxcd.io/force: "enabled"
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: keycloak-config-cli
          image: adorsys/keycloak-config-cli:#{ keycloak_config_cli_version | default('6.4.0-26.1.0') }#
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          env:
            - name: KEYCLOAK_URL
              value: "http://keycloak-service.identity.svc.cluster.local:8080"
            - name: KEYCLOAK_USER
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin-credentials
                  key: username
            - name: KEYCLOAK_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin-credentials
                  key: password
            - name: KEYCLOAK_AVAILABILITYCHECK_ENABLED
              value: "true"
            - name: KEYCLOAK_AVAILABILITYCHECK_TIMEOUT
              value: "120s"
            - name: IMPORT_FILES_LOCATIONS
              value: "/config/*"
            # NOTE: Env var name uses no underscore between VAR and SUBSTITUTION
            # REF: https://github.com/adorsys/keycloak-config-cli#variable-substitution
            - name: IMPORT_VARSUBSTITUTION_ENABLED
              value: "true"
            # JSON logging for Kubernetes log aggregation
            - name: SPRING_PROFILES_ACTIVE
              value: "json-log"
          volumeMounts:
            - name: realm-config
              mountPath: /config
              readOnly: true
            - name: tmp
              mountPath: /tmp
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: realm-config
          configMap:
            name: keycloak-realm-config
        - name: tmp
          emptyDir: {}
#% endif %#
```

#### Phase 3: Realm Configuration ConfigMap

Convert existing realm configuration to a ConfigMap format compatible with keycloak-config-cli.

> **NOTE:** This configuration mirrors `realm-import.sops.yaml.j2` but uses ConfigMap format for keycloak-config-cli. The full template includes all current features: Envoy Gateway SSO client, Grafana OIDC client, all three IdPs (Google, GitHub, Microsoft), and all IdP role mappers.

**File: `config/realm-config.sops.yaml.j2`** (SOPS-encrypted ConfigMap)

```yaml
#% if keycloak_enabled | default(false) %#
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-realm-config
  namespace: identity
data:
  realm.yaml: |
    realm: #{ keycloak_realm | default('matherlynet') }#
    enabled: true
    displayName: "#{ keycloak_realm | default('matherlynet') | title }# Realm"

    #| =========================================================================== #|
    #| SESSION SETTINGS                                                            #|
    #| =========================================================================== #|
    ssoSessionIdleTimeout: 1800
    ssoSessionMaxLifespan: 36000
    accessTokenLifespan: 300
    accessTokenLifespanForImplicitFlow: 900

    #| =========================================================================== #|
    #| LOGIN SETTINGS                                                              #|
    #| =========================================================================== #|
    registrationAllowed: false
    resetPasswordAllowed: true
    rememberMe: true
    loginWithEmailAllowed: true
    duplicateEmailsAllowed: false

    #| =========================================================================== #|
    #| BRUTE FORCE PROTECTION                                                      #|
    #| =========================================================================== #|
    bruteForceProtected: true
    permanentLockout: false
    maxFailureWaitSeconds: 900
    minimumQuickLoginWaitSeconds: 60
    waitIncrementSeconds: 60
    quickLoginCheckMilliSeconds: 1000
    maxDeltaTimeSeconds: 43200
    failureFactor: 5

    #| =========================================================================== #|
    #| REALM ROLES - Including auto-added IdP mapper roles                         #|
    #| =========================================================================== #|
#% set configured_role_names = [] %#
#% if keycloak_realm_roles is defined and keycloak_realm_roles %#
#%   for role in keycloak_realm_roles %#
#%     set _ = configured_role_names.append(role.name) %#
#%   endfor %#
#% endif %#
#% set idp_mapper_roles = [] %#
#% if google_default_role is defined and google_default_role %#
#%   if google_default_role not in configured_role_names and google_default_role not in idp_mapper_roles %#
#%     set _ = idp_mapper_roles.append(google_default_role) %#
#%   endif %#
#% endif %#
#% if google_domain_role_mapping is defined and google_domain_role_mapping.role is defined %#
#%   if google_domain_role_mapping.role not in configured_role_names and google_domain_role_mapping.role not in idp_mapper_roles %#
#%     set _ = idp_mapper_roles.append(google_domain_role_mapping.role) %#
#%   endif %#
#% endif %#
#% if github_default_role is defined and github_default_role %#
#%   if github_default_role not in configured_role_names and github_default_role not in idp_mapper_roles %#
#%     set _ = idp_mapper_roles.append(github_default_role) %#
#%   endif %#
#% endif %#
#% if github_org_role_mapping is defined and github_org_role_mapping.role is defined %#
#%   if github_org_role_mapping.role not in configured_role_names and github_org_role_mapping.role not in idp_mapper_roles %#
#%     set _ = idp_mapper_roles.append(github_org_role_mapping.role) %#
#%   endif %#
#% endif %#
#% if microsoft_default_role is defined and microsoft_default_role %#
#%   if microsoft_default_role not in configured_role_names and microsoft_default_role not in idp_mapper_roles %#
#%     set _ = idp_mapper_roles.append(microsoft_default_role) %#
#%   endif %#
#% endif %#
#% if microsoft_group_role_mappings is defined and microsoft_group_role_mappings %#
#%   for mapping in microsoft_group_role_mappings %#
#%     if mapping.role not in configured_role_names and mapping.role not in idp_mapper_roles %#
#%       set _ = idp_mapper_roles.append(mapping.role) %#
#%     endif %#
#%   endfor %#
#% endif %#
#% set has_roles = (keycloak_realm_roles is defined and keycloak_realm_roles | length > 0) or (idp_mapper_roles | length > 0) %#
#% if has_roles %#
    roles:
      realm:
#%   if keycloak_realm_roles is defined and keycloak_realm_roles %#
#%     for role in keycloak_realm_roles %#
        - name: "#{ role.name }#"
          description: "#{ role.description | default('Custom realm role') }#"
#%     endfor %#
#%   endif %#
#%   for role in idp_mapper_roles %#
        - name: "#{ role }#"
          description: "IdP mapper role (auto-added from *_default_role/*_role_mapping)"
#%   endfor %#
#% endif %#

    #| =========================================================================== #|
    #| OIDC CLIENTS                                                                #|
    #| =========================================================================== #|
#% if keycloak_bootstrap_oidc_client | default(false) or grafana_oidc_enabled | default(false) %#
    clients:
#% if keycloak_bootstrap_oidc_client | default(false) %#
      #| Envoy Gateway SSO Client #|
      - clientId: "#{ oidc_client_id | default('envoy-gateway') }#"
        name: "Envoy Gateway SSO"
        description: "OIDC client for Envoy Gateway SecurityPolicy - enables browser SSO"
        enabled: true
        publicClient: false
        clientAuthenticatorType: "client-secret"
        secret: "#{ oidc_client_secret }#"
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        serviceAccountsEnabled: false
        implicitFlowEnabled: false
        protocol: "openid-connect"
        redirectUris:
#% if hubble_enabled | default(false) and oidc_sso_enabled | default(false) %#
          - "https://#{ hubble_subdomain | default('hubble') }#.#{ cloudflare_domain }#/oauth2/callback"
#% endif %#
#% if monitoring_enabled | default(false) and oidc_sso_enabled | default(false) %#
          - "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#/oauth2/callback"
#% endif %#
#% if rustfs_enabled | default(false) and oidc_sso_enabled | default(false) %#
          - "https://#{ rustfs_subdomain | default('rustfs') }#.#{ cloudflare_domain }#/oauth2/callback"
#% endif %#
#% if oidc_additional_redirect_uris is defined and oidc_additional_redirect_uris %#
#%   for uri in oidc_additional_redirect_uris %#
          - "#{ uri }#"
#%   endfor %#
#% endif %#
        webOrigins:
#% if hubble_enabled | default(false) and oidc_sso_enabled | default(false) %#
          - "https://#{ hubble_subdomain | default('hubble') }#.#{ cloudflare_domain }#"
#% endif %#
#% if monitoring_enabled | default(false) and oidc_sso_enabled | default(false) %#
          - "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#"
#% endif %#
#% if rustfs_enabled | default(false) and oidc_sso_enabled | default(false) %#
          - "https://#{ rustfs_subdomain | default('rustfs') }#.#{ cloudflare_domain }#"
#% endif %#
        attributes:
          pkce.code.challenge.method: "S256"
          post.logout.redirect.uris: >-
#% set logout_uris = [] %#
#% if hubble_enabled | default(false) and oidc_sso_enabled | default(false) %#
#%   set _ = logout_uris.append('https://' ~ (hubble_subdomain | default('hubble')) ~ '.' ~ cloudflare_domain ~ '/*') %#
#% endif %#
#% if monitoring_enabled | default(false) and oidc_sso_enabled | default(false) %#
#%   set _ = logout_uris.append('https://' ~ (grafana_subdomain | default('grafana')) ~ '.' ~ cloudflare_domain ~ '/*') %#
#% endif %#
#% if rustfs_enabled | default(false) and oidc_sso_enabled | default(false) %#
#%   set _ = logout_uris.append('https://' ~ (rustfs_subdomain | default('rustfs')) ~ '.' ~ cloudflare_domain ~ '/*') %#
#% endif %#
            #{ logout_uris | join('##') }#
        defaultClientScopes:
          - "openid"
          - "profile"
          - "email"
        optionalClientScopes:
          - "address"
          - "phone"
          - "offline_access"
#% endif %#
#% if grafana_oidc_enabled | default(false) %#
      #| Grafana OIDC Client - Native OAuth for RBAC #|
      - clientId: "grafana"
        name: "Grafana"
        description: "OIDC client for Grafana native OAuth - provides RBAC"
        enabled: true
        publicClient: false
        clientAuthenticatorType: "client-secret"
        secret: "#{ grafana_oidc_client_secret }#"
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        serviceAccountsEnabled: false
        implicitFlowEnabled: false
        protocol: "openid-connect"
        redirectUris:
          - "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#/login/generic_oauth"
        webOrigins:
          - "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#"
        attributes:
          pkce.code.challenge.method: "S256"
          post.logout.redirect.uris: "https://#{ grafana_subdomain | default('grafana') }#.#{ cloudflare_domain }#/*"
        defaultClientScopes:
          - "openid"
          - "profile"
          - "email"
        optionalClientScopes:
          - "address"
          - "phone"
          - "offline_access"
        protocolMappers:
          - name: "realm-roles"
            protocol: "openid-connect"
            protocolMapper: "oidc-usermodel-realm-role-mapper"
            consentRequired: false
            config:
              claim.name: "roles"
              jsonType.label: "String"
              multivalued: "true"
              id.token.claim: "true"
              access.token.claim: "true"
              userinfo.token.claim: "true"
          - name: "groups"
            protocol: "openid-connect"
            protocolMapper: "oidc-group-membership-mapper"
            consentRequired: false
            config:
              claim.name: "groups"
              full.path: "false"
              id.token.claim: "true"
              access.token.claim: "true"
              userinfo.token.claim: "true"
#% endif %#
#% endif %#

    #| =========================================================================== #|
    #| SOCIAL IDENTITY PROVIDERS                                                   #|
    #| =========================================================================== #|
#% if google_idp_enabled | default(false) or github_idp_enabled | default(false) or microsoft_idp_enabled | default(false) %#
    identityProviders:
#% if google_idp_enabled | default(false) %#
      - alias: "google"
        displayName: "Google"
        providerId: "google"
        enabled: true
        trustEmail: true
        storeToken: true
        linkOnly: false
        firstBrokerLoginFlowAlias: "first broker login"
        config:
          clientId: "#{ google_client_id }#"
          clientSecret: "#{ google_client_secret }#"
          defaultScope: "openid profile email"
          syncMode: "IMPORT"
#% endif %#
#% if github_idp_enabled | default(false) %#
      - alias: "github"
        displayName: "GitHub"
        providerId: "github"
        enabled: true
        trustEmail: true
        storeToken: true
        linkOnly: false
        firstBrokerLoginFlowAlias: "first broker login"
        config:
          clientId: "#{ github_client_id }#"
          clientSecret: "#{ github_client_secret }#"
          defaultScope: "user:email"
          syncMode: "IMPORT"
#% endif %#
#% if microsoft_idp_enabled | default(false) %#
      - alias: "microsoft"
        displayName: "Microsoft"
        providerId: "oidc"
        enabled: true
        trustEmail: true
        storeToken: true
        linkOnly: false
        firstBrokerLoginFlowAlias: "first broker login"
        config:
          clientId: "#{ microsoft_client_id }#"
          clientSecret: "#{ microsoft_client_secret }#"
          authorizationUrl: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/oauth2/v2.0/authorize"
          tokenUrl: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/oauth2/v2.0/token"
          userInfoUrl: "https://graph.microsoft.com/oidc/userinfo"
          jwksUrl: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/discovery/v2.0/keys"
          issuer: "https://login.microsoftonline.com/#{ microsoft_tenant_id | default('common') }#/v2.0"
          defaultScope: "openid profile email"
          syncMode: "FORCE"
          validateSignature: "true"
          useJwksUrl: "true"
#% endif %#
#% endif %#

    #| =========================================================================== #|
    #| IDENTITY PROVIDER MAPPERS - Automatic Role Assignment                       #|
    #| =========================================================================== #|
#% set has_mappers = (google_default_role is defined and google_default_role) or
                     (google_domain_role_mapping is defined and google_domain_role_mapping) or
                     (github_default_role is defined and github_default_role) or
                     (github_org_role_mapping is defined and github_org_role_mapping) or
                     (microsoft_default_role is defined and microsoft_default_role) or
                     (microsoft_group_role_mappings is defined and microsoft_group_role_mappings) %#
#% if has_mappers %#
    identityProviderMappers:
#% if google_idp_enabled | default(false) %#
#% if google_default_role is defined and google_default_role %#
      - name: "google-default-role"
        identityProviderAlias: "google"
        identityProviderMapper: "oidc-hardcoded-role-idp-mapper"
        config:
          syncMode: "INHERIT"
          role: "#{ google_default_role }#"
#% endif %#
#% if google_domain_role_mapping is defined and google_domain_role_mapping %#
      - name: "google-domain-#{ google_domain_role_mapping.domain | replace('.', '-') }#"
        identityProviderAlias: "google"
        identityProviderMapper: "oidc-role-idp-mapper"
        config:
          syncMode: "INHERIT"
          claim: "hd"
          claim.value: "#{ google_domain_role_mapping.domain }#"
          role: "#{ google_domain_role_mapping.role }#"
#% endif %#
#% endif %#
#% if github_idp_enabled | default(false) %#
#% if github_default_role is defined and github_default_role %#
      - name: "github-default-role"
        identityProviderAlias: "github"
        identityProviderMapper: "oidc-hardcoded-role-idp-mapper"
        config:
          syncMode: "INHERIT"
          role: "#{ github_default_role }#"
#% endif %#
#% if github_org_role_mapping is defined and github_org_role_mapping %#
      - name: "github-org-#{ github_org_role_mapping.org }#"
        identityProviderAlias: "github"
        identityProviderMapper: "oidc-advanced-role-idp-mapper"
        config:
          syncMode: "FORCE"
          claims: "[{\"key\":\"organizations_url\",\"value\":\".*#{ github_org_role_mapping.org }#.*\"}]"
          are.claim.values.regex: "true"
          role: "#{ github_org_role_mapping.role }#"
#% endif %#
#% endif %#
#% if microsoft_idp_enabled | default(false) %#
#% if microsoft_default_role is defined and microsoft_default_role %#
      - name: "microsoft-default-role"
        identityProviderAlias: "microsoft"
        identityProviderMapper: "oidc-hardcoded-role-idp-mapper"
        config:
          syncMode: "INHERIT"
          role: "#{ microsoft_default_role }#"
#% endif %#
#% if microsoft_group_role_mappings is defined and microsoft_group_role_mappings %#
#% for mapping in microsoft_group_role_mappings %#
      - name: "microsoft-group-#{ mapping.role | replace('.', '-') }#"
        identityProviderAlias: "microsoft"
        identityProviderMapper: "oidc-advanced-role-idp-mapper"
        config:
          syncMode: "FORCE"
          claims: "[{\"key\":\"groups\",\"value\":\".*#{ mapping.group_id }#.*\"}]"
          are.claim.values.regex: "true"
          role: "#{ mapping.role }#"
#% endfor %#
#% endif %#
#% endif %#
#% endif %#
#% endif %#
```

> **IMPORTANT:** This configuration is SOPS-encrypted because it contains sensitive data (`oidc_client_secret`, `grafana_oidc_client_secret`, `google_client_secret`, `github_client_secret`, `microsoft_client_secret`). Flux decrypts during reconciliation.

#### Phase 4: Flux Kustomization Integration (`ks.yaml.j2`)

Add a third Kustomization for the config Job that depends on the Keycloak CR being healthy:

```yaml
#% if keycloak_enabled | default(false) %#
---
#| First Kustomization: Operator + CRDs (existing) #|
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
  path: ./kubernetes/apps/identity/keycloak/operator
  # ... existing spec ...
---
#| Second Kustomization: Keycloak CR + HTTPRoute (existing) #|
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
  path: ./kubernetes/apps/identity/keycloak/app
  # ... existing spec ...
---
#| ============================================================================= #|
#| Third Kustomization: Realm Configuration via keycloak-config-cli             #|
#| Runs AFTER Keycloak is healthy; applies realm configuration via Admin API    #|
#| ============================================================================= #|
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: keycloak-config
spec:
  dependsOn:
    - name: keycloak
  #| No healthChecks - Job is fire-and-forget #|
  interval: 1h
  retryInterval: 30s
  path: ./kubernetes/apps/identity/keycloak/config
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
  #| wait: false - don't block on Job completion #|
  wait: false
#% endif %#
```

> **NOTE:** The `keycloak-config` Kustomization uses `wait: false` because:
> 1. The Job runs once and exits
> 2. Blocking on Job completion would delay the entire Flux reconciliation
> 3. Job failures are handled via `backoffLimit` and alerting (if configured)

#### Phase 5: Migration Path

1. **Backup existing realm:** Export current realm configuration from Keycloak UI
2. **Deploy keycloak-config-cli Job:** Add new templates
3. **Remove KeycloakRealmImport:** Delete the old CRD-based import
4. **Verify configuration:** Check realm matches expected state
5. **Test updates:** Modify configuration and verify changes apply

### Configuration Variables

Add to `cluster.yaml`:

```yaml
# keycloak-config-cli version (image tag)
keycloak_config_cli_version: "6.4.0-26.1.0"

# Enable/disable config-cli (default: true when keycloak_enabled)
keycloak_config_cli_enabled: true
```

### Benefits Over Current Implementation

1. **Incremental Updates:** Change realm settings without recreating
2. **User Preservation:** Users and manual configurations preserved
3. **Remote State:** Only manages resources it created
4. **Variable Substitution:** Environment-aware configuration
5. **GitOps Native:** Triggered automatically on Git changes via Flux
6. **Audit Trail:** All changes version-controlled in Git

### Monitoring and Troubleshooting

#### Job Status

```bash
# Check job status
kubectl -n identity get jobs keycloak-config-apply

# View job logs
kubectl -n identity logs -l app.kubernetes.io/name=keycloak-config-cli

# Check for errors
kubectl -n identity describe job keycloak-config-apply
```

#### Common Issues

| Issue | Cause | Solution |
| --------- | ------------- | ------------- |
| Job fails with 401 | Invalid credentials | Verify keycloak-admin-credentials secret |
| Job fails with 403 | Insufficient permissions | Ensure admin user has realm-admin role |
| Availability check timeout | Keycloak not ready | Increase AVAILABILITYCHECK_TIMEOUT |
| Config not applied | Checksum unchanged | Force job re-run or update config |

## Alternative Consideration: Hybrid Approach

For teams already using Terraform/OpenTofu, consider a hybrid approach:

1. **keycloak-config-cli** for realm structure (clients, roles, IdPs) - runs as Kubernetes Job
2. **Terraform Provider** for infrastructure-level settings - runs in CI/CD

This separates concerns while maintaining GitOps principles.

## Known Limitations and Considerations

### 1. Keycloak Operator Service Naming (Issue #38757)

As of Keycloak v26.1.4, there's an open issue where the StatefulSet is not properly bound to a headless service for clustering. This is tracked in [keycloak/keycloak#38757](https://github.com/keycloak/keycloak/issues/38757) and tagged for `release/26.3.0`.

**Impact:** For HA deployments with `keycloak_replicas > 1`, the cluster already creates a manual `keycloak-discovery` headless service in `httproute.yaml.j2`. This pattern should be maintained.

### 2. ConfigMap vs Secret for Realm Configuration

The realm configuration contains sensitive data (client secrets, IdP credentials). While the document recommends SOPS-encrypted ConfigMaps, an alternative is:

```yaml
# Use Secret instead of ConfigMap for realm config
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-realm-config
stringData:
  realm.yaml: |
    # ... realm configuration
```

**Trade-off:** Secrets are base64-encoded (not encrypted at rest by default in etcd). SOPS + ConfigMap provides encryption at rest in Git. With Flux SOPS integration, both approaches result in encrypted storage.

### 3. Removal of KeycloakRealmImport CR

The current `realm-import.sops.yaml.j2` must be removed after migration to avoid conflicts. The KeycloakRealmImport CR will:
- Continue to exist but do nothing (realm already exists)
- Potentially cause confusion during troubleshooting

**Migration Step:** Remove `realm-import.sops.yaml.j2` from `kustomization.yaml.j2` after successful keycloak-config-cli deployment.

### 4. First-Time Bootstrap vs Updates

keycloak-config-cli handles both scenarios:
- **Bootstrap (new cluster):** Creates realm and all resources
- **Update (existing cluster):** Incrementally updates only changed resources

The same Job template works for both cases with no special handling required.

### 5. Image Version Pinning

The keycloak-config-cli image tag format is `<cli-version>-<keycloak-version>`, e.g., `6.4.0-26.1.4`. When upgrading Keycloak:
1. Check keycloak-config-cli releases for matching Keycloak version
2. Update `keycloak_config_cli_version` in `cluster.yaml`
3. Test configuration import in development first

## Security Considerations

1. **Admin Credentials Access:** The Job mounts `keycloak-admin-credentials` secret. Ensure proper RBAC on the secret.

2. **Network Access:** The Job needs network access to `keycloak-service:8080`. If NetworkPolicies are enabled, ensure the Job can reach Keycloak.

3. **SOPS Key Rotation:** If Age keys are rotated, re-encrypt `realm-config.sops.yaml` before deployment.

## Implementation Notes (Validated January 2026)

### Environment Variable Naming Convention

**CRITICAL:** The keycloak-config-cli environment variable naming follows Spring Boot conventions:
- CLI parameter: `--import.var-substitution.enabled`
- Environment variable: `IMPORT_VARSUBSTITUTION_ENABLED` (no underscore between VAR and SUBSTITUTION)

From the [documentation](https://github.com/adorsys/keycloak-config-cli#configuration):
> "For docker -e you have to remove hyphens and replace dots with underscores."

### Recommended Environment Variables

| Variable | Value | Purpose |
| ---------- | ------- | --------- |
| `KEYCLOAK_URL` | `http://keycloak-service.identity.svc.cluster.local:8080` | Internal service endpoint |
| `KEYCLOAK_USER` | From Secret | Admin username |
| `KEYCLOAK_PASSWORD` | From Secret | Admin password |
| `KEYCLOAK_AVAILABILITYCHECK_ENABLED` | `true` | Wait for Keycloak readiness |
| `KEYCLOAK_AVAILABILITYCHECK_TIMEOUT` | `120s` | Readiness check timeout |
| `IMPORT_FILES_LOCATIONS` | `/config/*` | Glob pattern for config files |
| `IMPORT_VARSUBSTITUTION_ENABLED` | `true` | Enable `$(VAR)` substitution |
| `SPRING_PROFILES_ACTIVE` | `json-log` | Structured JSON logging for K8s |

### Variable Substitution Syntax

When `IMPORT_VARSUBSTITUTION_ENABLED=true`:
- Default prefix: `$(`
- Default suffix: `)`
- Example: `$(env:MY_VAR)` or `$(file:/path/to/file)`

**Note:** Our implementation uses a hybrid approach:
- **Jinja2 templates** (`#{ }#`) at `task configure` time for non-sensitive values (URLs, subdomains, feature flags)
- **Runtime `$(env:VAR)` substitution** for secrets injected via `envFrom` from `keycloak-realm-secrets`

This ensures sensitive values are never rendered into plain files, only into SOPS-encrypted Secrets.

### Implementation Files

The implementation is located in:
```
templates/config/kubernetes/apps/identity/keycloak/config/
├── kustomization.yaml.j2      # Kustomize resource list
├── config-job.yaml.j2         # keycloak-config-cli Job
├── realm-config.yaml.j2       # Plain ConfigMap with $(env:VAR) placeholders
├── secrets.sops.yaml.j2       # SOPS-encrypted Secret with actual credentials
└── networkpolicy.yaml.j2      # CiliumNetworkPolicy for Job egress
```

### Architecture Pattern: Environment Variable Substitution

The implementation uses keycloak-config-cli's native variable substitution feature for clean separation of concerns:

**realm-config.yaml** (Plain ConfigMap - NOT SOPS encrypted):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-realm-config
data:
  realm.yaml: |
    clients:
      - clientId: "$(env:OIDC_CLIENT_ID)"
        secret: "$(env:OIDC_CLIENT_SECRET)"
    identityProviders:
      - alias: "google"
        config:
          clientId: "$(env:GOOGLE_CLIENT_ID)"
          clientSecret: "$(env:GOOGLE_CLIENT_SECRET)"
```

**secrets.sops.yaml** (SOPS-encrypted Secret):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-realm-secrets
stringData:
  OIDC_CLIENT_ID: "envoy-gateway"
  OIDC_CLIENT_SECRET: "actual-secret-value"
  GOOGLE_CLIENT_ID: "google-oauth-id"
  GOOGLE_CLIENT_SECRET: "google-oauth-secret"
```

**config-job.yaml** (Job with envFrom):
```yaml
containers:
  - name: keycloak-config-cli
    env:
      - name: IMPORT_VARSUBSTITUTION_ENABLED
        value: "true"
    envFrom:
      - secretRef:
          name: keycloak-realm-secrets
    volumeMounts:
      - name: realm-config
        mountPath: /config
volumes:
  - name: realm-config
    configMap:
      name: keycloak-realm-config
```

**Benefits:**
1. **kubeconform validation passes** - ConfigMap has no SOPS metadata
2. **Clean separation** - Secrets in standard Secret, config in ConfigMap
3. **GitOps-friendly** - Config changes visible in plain YAML diffs
4. **Kubernetes-native** - Standard Secret/ConfigMap patterns
5. **Easier code review** - Readable YAML without encrypted blobs

## References

- [keycloak-config-cli GitHub](https://github.com/adorsys/keycloak-config-cli)
- [keycloak-config-cli Documentation](https://adorsys.github.io/keycloak-config-cli/)
- [keycloak-config-cli Supported Features](https://adorsys.github.io/keycloak-config-cli/supported-features/)
- [Remote State Management](https://adorsys.github.io/keycloak-config-cli/config/remote-state-management/)
- [Keycloak Realm Configuration Management Discussion](https://github.com/keycloak/keycloak/discussions/30643)
- [Keycloak Operator Realm Import](https://www.keycloak.org/operator/realm-import)
- [Keycloak Terraform Provider](https://github.com/keycloak/terraform-provider-keycloak)
- [Keycloak Realm Operator](https://github.com/keycloak/keycloak-realm-operator)
- [Keycloak 26 Compatibility Issue](https://github.com/adorsys/keycloak-config-cli/issues/1160)
- [Keycloak StatefulSet Service Issue](https://github.com/keycloak/keycloak/issues/38757)

## Next Steps

1. **Review and approve** this implementation plan with stakeholders
2. **Create feature branch** for keycloak-config-cli integration: `feat/keycloak-config-cli`
3. **Create directory structure:**
   - `templates/config/kubernetes/apps/identity/keycloak/config/`
   - Move realm configuration from `realm-import.sops.yaml.j2`
4. **Implement templates** per Phase 2-4:
   - `config-job.yaml.j2` - Kubernetes Job
   - `realm-config.sops.yaml.j2` - SOPS-encrypted ConfigMap
   - `kustomization.yaml.j2` - Kustomize resources
5. **Update ks.yaml.j2** with third Kustomization for `keycloak-config`
6. **Remove old KeycloakRealmImport** from `app/kustomization.yaml.j2`
7. **Test in development** environment:
   - Fresh cluster bootstrap
   - Configuration update scenarios
   - Verify remote state management
8. **Document migration** procedure for existing deployments
9. **Update CLAUDE.md** with new configuration options:
   - `keycloak_config_cli_version`
   - `keycloak_config_cli_enabled`
10. **Update project memories** with keycloak-config-cli patterns
