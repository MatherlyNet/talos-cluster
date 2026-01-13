# Network Inventory and Configuration

**Last Updated:** 2026-01-10

This document catalogs all exposed endpoints, network policies, and security configurations in the cluster. Use this as a living reference to identify gaps and ensure consistent network security.

---

## Table of Contents

1. [Gateways](#gateways)
2. [Exposed Endpoints](#exposed-endpoints)
3. [Security Policies](#security-policies)
4. [Network Policies](#network-policies)
5. [ReferenceGrants](#referencegrants)
6. [Coverage Analysis](#coverage-analysis)
7. [Gaps and Recommendations](#gaps-and-recommendations)

---

## Gateways

The cluster uses Envoy Gateway with two gateway instances for traffic separation:

| Gateway | Namespace | Address | Purpose | Listeners |
| --------- | ----------- | --------- | --------- | ----------- |
| `envoy-external` | network | 192.168.22.90 | Public-facing services (via Cloudflare Tunnel) | 80, 443 |
| `envoy-internal` | network | 192.168.22.80 | Internal services (VPN/LAN access only) | 80, 443 |

### Traffic Flow

```
Internet → Cloudflare Tunnel → envoy-external (192.168.22.90)
                                    ↓
                              HTTPRoutes → Backend Services

VPN/LAN → envoy-internal (192.168.22.80)
              ↓
        HTTPRoutes → Backend Services
```

---

## Exposed Endpoints

### External Endpoints (via Cloudflare Tunnel)

These endpoints are accessible from the public internet through Cloudflare Tunnel:

| Hostname | Service | Namespace | Port | Authentication | Purpose |
| ---------- | --------- | ----------- | ------ | ---------------- | --------- |
| `echo.matherly.net` | echo | default | 80 | None | Test/health check |
| `flux-webhook.matherly.net` | webhook-receiver | flux-system | 80 | HMAC signature | GitOps webhook |
| `sso.matherly.net` | keycloak-service | identity | 8080 | Native | Identity provider |
| `langfuse.matherly.net` | langfuse-web | ai-system | 3000 | Keycloak SSO | LLM observability |
| `llms.matherly.net` | litellm | ai-system | 4000 | JWT/API Key | LLM proxy gateway |
| `obot.matherly.net` | obot | ai-system | 80 | Keycloak SSO | MCP agent platform |

### Internal Endpoints (VPN/LAN Only)

These endpoints are only accessible from internal network or VPN:

| Hostname | Service | Namespace | Port | Authentication | Purpose |
| ---------- | --------- | ----------- | ------ | ---------------- | --------- |
| `grafana.matherly.net` | kube-prometheus-stack-grafana | monitoring | 80 | OIDC SSO | Metrics/dashboards |
| `headlamp.matherly.net` | headlamp | kube-system | 80 | Keycloak SSO | Kubernetes Web UI |
| `hubble.matherly.net` | hubble-ui | kube-system | 80 | OIDC SSO | Network observability |
| `rustfs.matherly.net` | rustfs-svc | storage | 9001 | None (Console UI) | S3 management |

### LoadBalancer Services

| Service | Namespace | External IP | Ports | Purpose |
| --------- | ----------- | ------------- | ------- | --------- |
| `envoy-external` | network | 192.168.22.90 | 80, 443 | External ingress |
| `envoy-internal` | network | 192.168.22.80 | 80, 443 | Internal ingress |

### NodePort Services

| Service | Namespace | NodePort | Purpose |
| --------- | ----------- | ---------- | --------- |
| `spegel-registry` | kube-system | 30021 | Container image registry mirror |

---

## Security Policies

The cluster uses Envoy Gateway SecurityPolicies for authentication:

### JWT Authentication (`jwt-auth`)

| Field | Value |
| ------- | ------- |
| **Namespace** | network |
| **Target** | HTTPRoutes with label `security: jwt-protected` |
| **Issuer** | `https://sso.matherly.net/realms/matherlynet` |
| **JWKS URI** | `https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/certs` |

**Claims Forwarded to Backends:**

| Claim | Header |
| ------- | -------- |
| `sub` | X-User-ID |
| `email` | X-User-Email, X-Email |
| `groups` | X-User-Groups, X-Groups |
| `preferred_username` | X-Username |
| `realm_access.roles` | X-User-Roles |
| `resource_access.envoy-gateway.roles` | X-Client-Roles |

### OIDC SSO (`oidc-sso`)

| Field | Value |
| ------- | ------- |
| **Namespace** | network |
| **Target** | HTTPRoutes with label `security: oidc-protected` |
| **Client ID** | envoy-gateway |
| **Provider** | Keycloak |
| **Cookie Domain** | matherly.net |

**Authentication Flow (Split-Path Architecture):**

```
Browser → authorizationEndpoint (external): https://sso.matherly.net/realms/matherlynet/protocol/openid-connect/auth
Envoy → tokenEndpoint (internal): http://keycloak-service.identity.svc.cluster.local:8080/realms/matherlynet/protocol/openid-connect/token
```

This split-path architecture avoids hairpin NAT issues and TLS handshake problems.

---

## Network Policies

### CiliumNetworkPolicies

| Namespace | Name | Selector | Description |
| ----------- | ------ | ---------- | ------------- |
| ai-system | `langfuse` | `app.kubernetes.io/name: langfuse` | Langfuse web UI and worker access controls |
| ai-system | `langfuse-postgres` | `cnpg.io/cluster: langfuse-postgresql` | Langfuse PostgreSQL access, replication, backups |
| ai-system | `litellm-azure-egress` | `app.kubernetes.io/name: litellm` | FQDN-based egress to Azure OpenAI, AI Services |
| ai-system | `litellm-db-kube-api-egress` | `cnpg.io/cluster: litellm-postgresql` | LiteLLM PostgreSQL DNS and kube-apiserver access |
| ai-system | `litellm-icmp-egress` | `app.kubernetes.io/name: litellm` | ICMP health probes |
| ai-system | `obot` | `app.kubernetes.io/name: obot` | Obot main application pod access controls |
| ai-system | `obot-postgres` | `cnpg.io/cluster: obot-postgresql` | Obot PostgreSQL access, replication, backups |
| cache | `dragonfly` | `app: dragonfly` | Dragonfly Redis-compatible cache |
| cnpg-system | `barman-cloud-plugin` | `app.kubernetes.io/name: plugin-barman-cloud` | Barman backup plugin access |
| cnpg-system | `cnpg-operator` | `app.kubernetes.io/name: cloudnative-pg` | CNPG operator access to cluster pods, Kubernetes API |
| identity | `keycloak-config-cli` | `app.kubernetes.io/name: keycloak-config-cli` | Keycloak realm configuration job |
| identity | `keycloak-postgres` | `cnpg.io/cluster: keycloak-postgres` | Keycloak PostgreSQL access, replication, backups |
| obot-mcp | `mcp-servers-default` | (namespace-wide) | MCP Servers default isolation policy |
| storage | `rustfs` | `app.kubernetes.io/name: rustfs` | RustFS S3-compatible storage access |

### Kubernetes NetworkPolicies

| Namespace | Name | Selector | Policy Types |
| ----------- | ------ | ---------- | -------------- |
| ai-system | `langfuse` | `app.kubernetes.io/name: langfuse` | Ingress, Egress |
| ai-system | `langfuse-clickhouse` | ClickHouse components | Ingress, Egress |
| ai-system | `langfuse-db` | `cnpg.io/cluster: langfuse-postgresql` | Ingress, Egress |
| ai-system | `langfuse-zookeeper` | Zookeeper components | Ingress, Egress |
| ai-system | `litellm` | `app.kubernetes.io/name: litellm` | Ingress, Egress |
| ai-system | `litellm-db` | `cnpg.io/cluster: litellm-postgresql` | Ingress, Egress |
| ai-system | `obot` | `app.kubernetes.io/name: obot` | Ingress, Egress |
| ai-system | `obot-db` | `cnpg.io/cluster: obot-postgresql` | Ingress, Egress |
| identity | `keycloak-network-policy` | `app: keycloak` | Ingress only |
| obot-mcp | `mcp-servers-default` | (namespace-wide) | Ingress, Egress |
| storage | `rustfs` | `app.kubernetes.io/name: rustfs` | Ingress, Egress |

### Network Policy Templates

Policy templates are located at:

```
templates/config/kubernetes/apps/
├── ai-system/
│   ├── langfuse/app/networkpolicy.yaml.j2
│   ├── litellm/app/networkpolicy.yaml.j2
│   └── obot/
│       ├── app/networkpolicy.yaml.j2
│       └── mcp-policies/app/networkpolicy.yaml.j2
├── cache/dragonfly/app/networkpolicy.yaml.j2
├── cnpg-system/
│   ├── barman-cloud-plugin/app/networkpolicy.yaml.j2
│   └── cloudnative-pg/app/networkpolicy-operator.yaml.j2
├── identity/keycloak/
│   ├── app/networkpolicy-postgres.yaml.j2
│   └── config/networkpolicy.yaml.j2
└── storage/rustfs/app/networkpolicy.yaml.j2
```

---

## ReferenceGrants

ReferenceGrants enable cross-namespace service references:

| Namespace | Name | Purpose |
| ----------- | ------ | --------- |
| ai-system | `langfuse-network-access` | Allow network namespace to reference Langfuse services |
| ai-system | `network-litellm-access` | Allow network namespace to reference LiteLLM services |
| ai-system | `network-obot-access` | Allow network namespace to reference Obot services |
| identity | `allow-oidc-from-network` | Allow OIDC SecurityPolicy to reference Keycloak backend |
| kube-system | `allow-network-httproutes` | Allow network namespace HTTPRoutes (Hubble UI) |
| kube-system | `headlamp-network-access` | Allow network namespace to reference Headlamp service |
| monitoring | `allow-network-httproutes` | Allow network namespace HTTPRoutes |
| storage | `allow-network-httproutes` | Allow network namespace HTTPRoutes |

---

## Coverage Analysis

### Pods per Namespace

| Namespace | Running Pods | CNP Count | NP Count | Status |
| ----------- | ------------ | ----------- | ---------- | -------- |
| ai-system | 11 | 7 | 8 | Covered |
| cache | 1 | 1 | 0 | Partially Covered |
| cert-manager | 3 | 0 | 0 | **No Policies** |
| cnpg-system | 2 | 2 | 0 | Covered (CNP) |
| csi-proxmox | 4 | 0 | 0 | **No Policies** |
| default | 1 | 0 | 0 | **No Policies** |
| dragonfly-operator-system | 1 | 0 | 0 | **No Policies** |
| flux-system | 5 | 0 | 0 | **No Policies** |
| identity | 3 | 2 | 1 | Covered |
| kube-system | 31 | 0 | 0 | **No Policies** (system) |
| monitoring | 25 | 0 | 0 | **No Policies** |
| network | 8 | 0 | 0 | **No Policies** |
| obot-mcp | 0 | 1 | 1 | Covered (default deny) |
| storage | 1 | 1 | 1 | Covered |
| system-upgrade | 1 | 0 | 0 | **No Policies** |

### Internal Service Communication

Key internal service dependencies:

```
┌─────────────────────────────────────────────────────────────────┐
│                        ai-system namespace                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  obot ──────────────► litellm (port 4000)                       │
│    │                      │                                     │
│    │                      ├──► litellm-postgresql (5432)        │
│    │                      ├──► dragonfly (cache, 6379)          │
│    │                      └──► Azure OpenAI (external HTTPS)    │
│    │                                                            │
│    ├──────────────► obot-postgresql (5432)                      │
│    ├──────────────► tempo (4317)                                │
│    ├──────────────► obot-mcp namespace (8080, 8099)             │
│    └──────────────► keycloak (8080, via FQDN)                   │
│                                                                 │
│  langfuse-web ────► langfuse-postgresql (5432)                  │
│       │           ├──► dragonfly (cache, 6379)                  │
│       │           ├──► langfuse-clickhouse (8123, 9000)         │
│       │           └──► tempo (4317)                             │
│       │                                                         │
│  langfuse-worker ──► (same as web)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      identity namespace                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  keycloak ──────────► keycloak-postgres (5432)                  │
│     │                                                           │
│     ├──────────────► dragonfly (sessions, 6379)                 │
│     └──────────────► tempo (4317)                               │
│                                                                 │
│  keycloak-config-cli ──► keycloak (8080)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       storage namespace                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  rustfs ◄──────────── loki-write (monitoring, 9000)             │
│         ◄──────────── cnpg-backups (ai-system, identity, 9000)  │
│         ◄──────────── langfuse (media/exports, 9000)            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Gaps and Recommendations

### Critical Gaps

1. **monitoring namespace** - 25 pods with no network policies
   - Prometheus, Grafana, Loki, Tempo, Alloy
   - Recommendation: Add baseline ingress/egress policies

2. **flux-system namespace** - 5 pods with no network policies
   - Source controller, Kustomize controller, Helm controller
   - Recommendation: Add policies restricting access to Git sources

3. **cert-manager namespace** - 3 pods with no network policies
   - Issuer access to ACME endpoints
   - Recommendation: Add egress policies for Let's Encrypt

### Medium Priority

1. **network namespace** - 8 pods (Envoy, external-dns, etc.)
   - Gateway pods, Cloudflare tunnel
   - Recommendation: Add baseline policies

2. **dragonfly-operator-system** - 1 pod with no policies
   - Operator needs kube-apiserver access
   - Recommendation: Add operator CNP

3. **csi-proxmox namespace** - 4 pods with no policies
   - CSI driver pods
   - Recommendation: Add policies for Proxmox API access

### Low Priority (System Namespaces)

1. **kube-system** - Core system components (Cilium, CoreDNS, etc.)
   - Usually left open for system functionality
   - Optional: Add restrictive policies for specific components

2. **default namespace** - Echo test app
   - Test endpoint only
   - Optional: Add basic ingress-only policy

### Recommended Actions

1. **Create monitoring namespace policies** - Priority: High
   - Allow Prometheus scraping from kube-system, ai-system, identity, storage
   - Allow Grafana access from network namespace (OIDC proxy)
   - Allow Loki write access from Alloy
   - Allow Tempo trace ingestion from applications

2. **Create flux-system policies** - Priority: Medium
   - Allow source-controller egress to GitHub
   - Allow webhook-receiver ingress from network namespace
   - Restrict kustomize/helm controllers to kube-apiserver

3. **Audit existing policies** - Priority: Medium
   - Verify all CNP/NP pairs are consistent
   - Check for missing ingress rules (like obot→litellm fix)
   - Validate FQDN egress rules are complete

---

## Appendix: Quick Reference Commands

```bash
# Check all network policies
kubectl get cnp -A
kubectl get networkpolicy -A

# Check for dropped traffic
hubble observe -n <namespace> --verdict DROPPED

# Check specific pod connectivity
kubectl -n <namespace> exec -it <pod> -- curl -s http://<service>:<port>/health

# View policy for a pod
kubectl -n <namespace> describe cnp <policy-name>

# Check ReferenceGrants
kubectl get referencegrant -A

# View SecurityPolicies
kubectl get securitypolicy -n network -o yaml
```

---

## Document History

| Date       | Change                                                     |
| ---------- | ---------------------------------------------------------- |
| 2026-01-12 | Add Headlamp Kubernetes Web UI endpoint and ReferenceGrant |
| 2026-01-10 | Initial inventory creation                                 |
