# Documentation Index

> Knowledge base for matherlynet-talos-cluster

## Quick Navigation

| Document | Description | When to Read |
| -------- | ----------- | ------------ |
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

1. Read [PROJECT_INDEX.md](../PROJECT_INDEX.md) for overview
2. Review [CONFIGURATION.md](./CONFIGURATION.md) for setup
3. Follow [README.md](../README.md) step-by-step guide

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
| external-dns | [APPLICATIONS.md](./APPLICATIONS.md#external-dns) | network |
| k8s-gateway | [APPLICATIONS.md](./APPLICATIONS.md#k8s-gateway) | network |
| Cloudflare Tunnel | [APPLICATIONS.md](./APPLICATIONS.md#cloudflare-tunnel) | network |

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
| `cloudflare_domain` | cert-manager, external-dns, tunnel | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |
| `cloudflare_token` | cert-manager, external-dns | [CONFIGURATION.md](./CONFIGURATION.md#required-fields) |

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
| `cilium_bgp_enabled` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cilium_bgp_router_addr` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cilium_bgp_router_asn` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |
| `cilium_bgp_node_asn` | Cilium BGP | [CONFIGURATION.md](./CONFIGURATION.md#optional-fields) |

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
