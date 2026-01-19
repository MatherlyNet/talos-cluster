# Documentation Index

> Knowledge base for matherlynet-talos-cluster

## Quick Navigation

| Document | Description | When to Read |
| -------- | ----------- | ------------ |
| [AGENTS.md](../AGENTS.md) | **AI assistant instructions (Windsurf/GitHub Copilot)** | **Every session start** |
| [PROJECT_INDEX.md](../PROJECT_INDEX.md) | Token-efficient project summary | Every session start |
| [QUICKSTART.md](./QUICKSTART.md) | Step-by-step setup guide | First-time setup |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design and component layers | Understanding the system |
| [CONFIGURATION.md](./CONFIGURATION.md) | cluster.yaml and nodes.yaml reference | Initial setup, modifications |
| [OPERATIONS.md](./OPERATIONS.md) | Day-2 operations and maintenance | Maintenance, upgrades |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Diagnostic flowcharts and fixes | When things break |
| [CLI_REFERENCE.md](./CLI_REFERENCE.md) | Command reference for all tools | Daily operations |
| [DIAGRAMS.md](./DIAGRAMS.md) | Mermaid architecture diagrams | Visual understanding |
| [APPLICATIONS.md](./APPLICATIONS.md) | Included application details | Adding/modifying apps |

---

## Topic Cross-Reference

### Getting Started

1. Read [AGENTS.md](../AGENTS.md) for AI assistant context (if using Windsurf/GitHub Copilot)
2. Read [PROJECT_INDEX.md](../PROJECT_INDEX.md) for overview
3. Review [CONFIGURATION.md](./CONFIGURATION.md) for setup
4. Follow [README.md](../README.md) step-by-step guide

### AI Context Documentation

For AI assistants working on specific subsystems, see `ai-context/` directory:

| Document | Domain | Use When |
| -------- | ------ | -------- |
| [flux-gitops.md](./ai-context/flux-gitops.md) | Flux CD | Adding apps, troubleshooting sync issues |
| [talos-operations.md](./ai-context/talos-operations.md) | Talos Linux | Node operations, upgrades, configuration |
| [cilium-networking.md](./ai-context/cilium-networking.md) | Cilium CNI | Network debugging, LoadBalancer, BGP, OIDC |
| [template-system.md](./ai-context/template-system.md) | makejinja | Template syntax, variables, new templates |
| [infrastructure-opentofu.md](./ai-context/infrastructure-opentofu.md) | OpenTofu | IaC operations, R2 backend, Proxmox |
| [context-loading-strategy.md](./ai-context/context-loading-strategy.md) | Context Optimization | Token usage optimization, progressive loading |

### Documentation Standards

For creating high-quality documentation:

| Document | Purpose | Use When |
| -------- | ------- | -------- |
| [DOCUMENTATION_STANDARDS.md](./DOCUMENTATION_STANDARDS.md) | Standards for comprehensive docs | Creating analysis, validation reports, implementation guides |

### Understanding the System

| Topic | Primary Doc | Related Sections |
| ------- | ------------- | ------------------ |
| Overall architecture | [ARCHITECTURE.md](./ARCHITECTURE.md) | System Overview |
| Network topology | [ARCHITECTURE.md](./ARCHITECTURE.md#network-topology) | Network Topology |
| GitOps flow | [ARCHITECTURE.md](./ARCHITECTURE.md#layer-4-gitops-flux-cd) | Layer 4: GitOps |
| Directory structure | [ARCHITECTURE.md](./ARCHITECTURE.md#directory-structure-post-configure) | Directory Structure |

### Configuration Reference

| Topic | Primary Doc | Related Sections |
| ------- | ------------- | ------------------ |
| cluster.yaml schema | [CONFIGURATION.md](./CONFIGURATION.md#clusteryaml-schema) | Required/Optional Fields |
| nodes.yaml schema | [CONFIGURATION.md](./CONFIGURATION.md#nodesyaml-schema) | Node Fields |
| Template functions | [CONFIGURATION.md](./CONFIGURATION.md#template-plugin-functions) | Filters, Functions |
| Environment variables | [CONFIGURATION.md](./CONFIGURATION.md#environment-variables) | Required vars |

### Operations & Maintenance

| Task | Primary Doc | Related Sections |
| ------ | ------------- | ------------------ |
| Adding nodes | [OPERATIONS.md](./OPERATIONS.md#adding-a-new-node) | Common Workflows |
| Upgrading Talos | [OPERATIONS.md](./OPERATIONS.md#upgrading-talos-version) | Common Workflows |
| Upgrading K8s | [OPERATIONS.md](./OPERATIONS.md#upgrading-kubernetes-version) | Common Workflows |
| Adding apps | [OPERATIONS.md](./OPERATIONS.md#adding-a-new-application) | Common Workflows |
| Troubleshooting | [OPERATIONS.md](./OPERATIONS.md#troubleshooting) | Flux, Talos, Cilium |

### Application Details

| Application | Primary Doc | Related Sections |
| ------------- | ------------- | ------------------ |
| Cilium (CNI) | [APPLICATIONS.md](./APPLICATIONS.md#cilium) | kube-system |
| Flux | [APPLICATIONS.md](./APPLICATIONS.md#flux-instance) | flux-system |
| cert-manager | [APPLICATIONS.md](./APPLICATIONS.md#cert-manager) | cert-manager |
| Envoy Gateway | [APPLICATIONS.md](./APPLICATIONS.md#envoy-gateway) | network |
| cloudflare-dns | [APPLICATIONS.md](./APPLICATIONS.md#cloudflare-dns) | network |
| unifi-dns | [APPLICATIONS.md](./APPLICATIONS.md#unifi-dns) | network (optional) |
| k8s-gateway | [APPLICATIONS.md](./APPLICATIONS.md#k8s-gateway) | network |
| Cloudflare Tunnel | [APPLICATIONS.md](./APPLICATIONS.md#cloudflare-tunnel) | network |
| kube-prometheus-stack | [APPLICATIONS.md](./APPLICATIONS.md#kube-prometheus-stack) | monitoring (optional) |
| Loki | [APPLICATIONS.md](./APPLICATIONS.md#loki) | monitoring (optional) |
| Alloy | [APPLICATIONS.md](./APPLICATIONS.md#alloy) | monitoring (optional) |
| Tempo | [APPLICATIONS.md](./APPLICATIONS.md#tempo) | monitoring (optional) |
| Hubble | [APPLICATIONS.md](./APPLICATIONS.md#hubble) | kube-system (optional) |
| tuppr | [APPLICATIONS.md](./APPLICATIONS.md#tuppr) | system-upgrade |
| Talos CCM | [APPLICATIONS.md](./APPLICATIONS.md#talos-ccm) | kube-system |
| Talos Backup | [APPLICATIONS.md](./APPLICATIONS.md#talos-backup) | kube-system (optional) |

---

## Task Quick Reference

| Task | Command | Docs |
| ------ | --------- | ------ |
| Initialize | `task init` | [OPERATIONS.md](./OPERATIONS.md#core-operations) |
| Configure | `task configure` | [OPERATIONS.md](./OPERATIONS.md#core-operations) |
| Bootstrap Talos | `task bootstrap:talos` | [OPERATIONS.md](./OPERATIONS.md#bootstrap-operations) |
| Bootstrap Apps | `task bootstrap:apps` | [OPERATIONS.md](./OPERATIONS.md#bootstrap-operations) |
| Force Sync | `task reconcile` | [OPERATIONS.md](./OPERATIONS.md#core-operations) |
| Apply Node Config | `task talos:apply-node IP=x` | [OPERATIONS.md](./OPERATIONS.md#talos-operations) |
| Upgrade Node | `task talos:upgrade-node IP=x` | [OPERATIONS.md](./OPERATIONS.md#upgrading-talos-version) |
| Upgrade K8s | `task talos:upgrade-k8s` | [OPERATIONS.md](./OPERATIONS.md#upgrading-kubernetes-version) |
| Reset Cluster | `task talos:reset` | [OPERATIONS.md](./OPERATIONS.md#talos-operations) |

---

## Troubleshooting Quick Reference

| Issue | Command | Docs |
| ------- | --------- | ------ |
| Flux not syncing | `flux get ks -A` | [OPERATIONS.md](./OPERATIONS.md#flux-issues) |
| Node not ready | `talosctl health -n <ip>` | [OPERATIONS.md](./OPERATIONS.md#talos-issues) |
| CNI issues | `cilium status` | [OPERATIONS.md](./OPERATIONS.md#cilium-issues) |
| Certificate issues | `kubectl get certificates -A` | [OPERATIONS.md](./OPERATIONS.md#certificate-issues) |
| DNS issues | `dig @<dns-ip> <domain>` | [OPERATIONS.md](./OPERATIONS.md#dns-issues) |

---

## Configuration Variables Index

### Network Variables

| Variable | Used In | Docs |
| ---------- | --------- | ------ |
| `node_cidr` | Talos, Cilium | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cluster_api_addr` | Talos VIP | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cluster_gateway_addr` | Envoy internal | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cluster_dns_gateway_addr` | k8s-gateway | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cloudflare_gateway_addr` | Envoy external | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cluster_pod_cidr` | Cilium | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cluster_svc_cidr` | Kubernetes | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |

### Cloudflare Variables

| Variable | Used In | Docs |
| ---------- | --------- | ------ |
| `cloudflare_domain` | cert-manager, cloudflare-dns, tunnel | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cloudflare_token` | cert-manager, cloudflare-dns | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |

### UniFi Variables (Optional)

| Variable | Used In | Docs |
| ---------- | --------- | ------ |
| `unifi_host` | unifi-dns | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `unifi_api_key` | unifi-dns | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `unifi_site` | unifi-dns | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `unifi_external_controller` | unifi-dns | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |

### Repository Variables

| Variable | Used In | Docs |
| ---------- | --------- | ------ |
| `repository_name` | Flux GitRepository | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `repository_branch` | Flux GitRepository | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `repository_visibility` | Flux deploy key | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |

### Cilium Variables

| Variable | Used In | Docs |
| ---------- | --------- | ------ |
| `cilium_loadbalancer_mode` | Cilium LB | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cilium_bgp_router_addr` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cilium_bgp_router_asn` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cilium_bgp_node_asn` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |

### Observability Variables (Optional)

| Variable | Used In | Docs |
| ---------- | --------- | ------ |
| `monitoring_enabled` | kube-prometheus-stack | [CONFIGURATION.md](./CONFIGURATION.md#observability-monitoring-stack) |
| `monitoring_stack` | Monitoring backend (prometheus) | [CONFIGURATION.md](./CONFIGURATION.md#observability-monitoring-stack) |
| `monitoring_alerts_enabled` | PrometheusRule alerts | [CONFIGURATION.md](./CONFIGURATION.md#infrastructure-alerts-prometheusrule) |
| `node_memory_threshold` | Alert thresholds | [CONFIGURATION.md](./CONFIGURATION.md#infrastructure-alerts-prometheusrule) |
| `node_cpu_threshold` | Alert thresholds | [CONFIGURATION.md](./CONFIGURATION.md#infrastructure-alerts-prometheusrule) |
| `loki_enabled` | Log aggregation | [CONFIGURATION.md](./CONFIGURATION.md#observability-log-aggregation) |
| `tracing_enabled` | Distributed tracing | [CONFIGURATION.md](./CONFIGURATION.md#observability-distributed-tracing) |
| `hubble_enabled` | Network observability | [CONFIGURATION.md](./CONFIGURATION.md#observability-monitoring-stack) |

---

## File Reference

### Configuration Files

| File | Purpose | Docs |
| ------ | --------- | ------ |
| `cluster.yaml` | Cluster configuration | [CONFIGURATION.md](./CONFIGURATION.md#clusteryaml-schema) |
| `nodes.yaml` | Node definitions | [CONFIGURATION.md](./CONFIGURATION.md#nodesyaml-schema) |
| `makejinja.toml` | Template engine config | [CONFIGURATION.md](./CONFIGURATION.md#template-delimiters) |
| `.mise.toml` | Dev environment tools | [PROJECT_INDEX.md](../PROJECT_INDEX.md#tool-dependencies) |

### Generated Files

| File | Purpose | Generated By |
| ------ | --------- | -------------- |
| `.sops.yaml` | SOPS encryption rules | `task configure` |
| `kubeconfig` | Cluster credentials | `task bootstrap:talos` |
| `kubernetes/` | K8s manifests | `task configure` |
| `talos/` | Talos configs | `task configure` |
| `bootstrap/` | Bootstrap resources | `task configure` |
| `infrastructure/` | OpenTofu configs | `task configure` |

### Secret Files (Local Only)

| File | Purpose | Created By |
| ------ | --------- | ------------ |
| `age.key` | SOPS encryption key | `task init` |
| `github-deploy.key` | Flux Git access | `task init` |
| `github-push-token.txt` | Webhook token | `task init` |
| `cloudflare-tunnel.json` | Tunnel credentials | `cloudflared tunnel create` |

---

## External Resources

### Official Documentation

| Resource | URL |
| ---------- | ----- |
| Talos Linux | https://www.talos.dev/latest/ |
| Flux CD | https://fluxcd.io/docs/ |
| Cilium | https://docs.cilium.io/ |
| Gateway API | https://gateway-api.sigs.k8s.io/ |
| cert-manager | https://cert-manager.io/docs/ |
| SOPS | https://github.com/getsops/sops |

### Community

| Resource | URL |
| ---------- | ----- |
| Upstream Template | https://github.com/onedr0p/cluster-template |
| Home Operations Discord | https://discord.gg/home-operations |
| Kubesearch | https://kubesearch.dev |

---

## Implementation Guides

| Guide | Description | When to Read |
| ----- | ----------- | ------------ |
| [OpenTofu R2 State Backend](./guides/opentofu-r2-state-backend.md) | R2 + Worker-based state locking | Implementing IaC with OpenTofu |
| [BGP UniFi Cilium Implementation](./guides/bgp-unifi-cilium-implementation.md) | BGP peering between UniFi gateway and Cilium | Enabling BGP routing |
| [GitOps Components Implementation](./guides/gitops-components-implementation.md) | tuppr, Talos CCM, Talos Backup, Proxmox CSI/CCM | Adding cloud-native components |
| [Observability Stack Implementation](./guides/archived/observability-stack-implementation-victoriametrics.md) | VictoriaMetrics (archived), kube-prometheus-stack, Loki, Tempo | Enabling monitoring/alerting |
| [Envoy Gateway Observability & Security](./guides/envoy-gateway-observability-security.md) | Tracing, metrics, JWT authentication | Gateway observability/security |
| [k8s-at-home Patterns Implementation](./guides/archived/k8s-at-home-patterns-implementation.md) | Community patterns (Phase 1 + 3A) | Adopting k8s-at-home patterns |
| [k8s-at-home Remaining Implementation](./guides/k8s-at-home-remaining-implementation.md) | VolSync, External Secrets, Descheduler | Future enhancements |

## Research Documents

### Active Research

| Document | Description | Status |
| -------- | ----------- | ------ |
| [Envoy Gateway Examples Analysis](./research/archive/completed/envoy-gateway-examples-analysis.md) | Examples analysis, v0.0.0-latest adoption for K8s 1.35 | Validated Jan 2026 |
| [Envoy Gateway OIDC Integration](./research/archive/completed/envoy-gateway-oidc-integration.md) | OIDC/OAuth2 authentication patterns | Validated Jan 2026 |
| [k8s-at-home Patterns](./research/archive/k8s-at-home-patterns-research.md) | Community patterns and practices | Complete |

### Archived (Implemented)

Research documents that have been fully implemented and archived:

| Document | Description | Status |
| -------- | ----------- | ------ |
| [External-DNS UniFi Integration](./research/archive/implemented/external-dns-unifi-integration.md) | UniFi webhook for internal DNS | Implemented |
| [Cloudflare R2 Terraform State](./research/archive/implemented/cloudflare-r2-terraform-state.md) | R2 as OpenTofu backend | Implemented |
| [Proxmox VM Automation](./research/archive/implemented/proxmox-vm-automation.md) | Proxmox automation via OpenTofu | Implemented |
| [BGP UniFi Cilium Integration](./research/archive/implemented/bgp-unifi-cilium-integration.md) | BGP peering between UniFi + Cilium | Implemented |
| [GitOps Examples Integration](./research/archive/implemented/gitops-examples-integration.md) | Cloud-native components for Proxmox + Talos | Implemented |

### Archived (Reference Only)

| Document | Description | Status |
| -------- | ----------- | ------ |
| [GitHub Actions Audit](./research/archive/github-actions-audit.md) | Security audit of workflows | Complete |
| [Crossplane Proxmox Automation](./research/archive/crossplane-proxmox-automation.md) | Crossplane approach (not adopted) | Reference |
| [Ansible Proxmox Automation](./research/archive/ansible-proxmox-automation.md) | Ansible approach (not adopted) | Reference |
