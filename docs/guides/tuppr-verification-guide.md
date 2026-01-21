# tuppr Deployment Verification Guide

> **Created:** January 2026
> **Status:** Verification Ready
> **Dependencies:** tuppr deployed, Talos API access patch applied
> **Effort:** ~30 minutes

---

## Overview

This guide provides comprehensive verification steps for **tuppr** (Talos Upgrade Controller) deployment. tuppr automates Talos OS and Kubernetes version upgrades through GitOps-driven Custom Resources.

### What tuppr Does

- **TalosUpgrade CR:** Manages Talos OS version upgrades across nodes
- **KubernetesUpgrade CR:** Manages Kubernetes version upgrades
- **Health checks:** CEL-based expressions validate cluster health before/after upgrades
- **Safe execution:** Never self-upgrades; always runs from healthy nodes

---

## Pre-Verification Checklist

Before verifying tuppr, ensure:

- [ ] `machine-talos-api.yaml.j2` patch applied to all nodes
- [ ] `system-upgrade` namespace exists
- [ ] Talos API access includes `os:admin` role
- [ ] tuppr HelmRelease deployed

---

## Verification Steps

### Step 1: Verify Talos API Access Patch

The Talos machine patch must be applied to enable API access from the cluster.

```bash
# Check patch on first control plane node
talosctl get machineconfig -n $(yq '.nodes[0].ip' nodes.yaml) -o yaml | grep -A10 kubernetesTalosAPIAccess
```

**Expected output:**

```yaml
kubernetesTalosAPIAccess:
  allowedKubernetesNamespaces:
    - system-upgrade
    - kube-system
  allowedRoles:
    - os:admin
    - os:etcd:backup
  enabled: true
```

**If missing or incomplete:**

```bash
# Apply patch to all nodes
for ip in $(yq '.nodes[].ip' nodes.yaml); do
  task talos:apply-node IP=$ip
done
```

### Step 2: Verify Namespace and Pods

```bash
# Check namespace exists
kubectl get namespace system-upgrade

# Check tuppr pods are running
kubectl -n system-upgrade get pods

# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# tuppr-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
```

**Check pod logs for errors:**

```bash
kubectl -n system-upgrade logs -l app.kubernetes.io/name=tuppr --tail=50
```

### Step 3: Verify Custom Resources

```bash
# Check CRDs are installed
kubectl get crd | grep tuppr

# Expected:
# kubernetesupgrades.tuppr.home-operations.com
# talosupgrades.tuppr.home-operations.com

# Check upgrade CRs exist
kubectl get talosupgrade,kubernetesupgrade
```

**Expected output:**

```
NAME                                      VERSION   STATUS
talosupgrade.tuppr.home-operations.com/talos   v1.12.0   Completed

NAME                                               VERSION   STATUS
kubernetesupgrade.tuppr.home-operations.com/kubernetes   v1.35.0   Completed
```

### Step 4: Verify Talos ServiceAccount

tuppr uses a Talos ServiceAccount for API access:

```bash
# Check Talos ServiceAccount exists
kubectl -n system-upgrade get serviceaccount tuppr -o yaml

# Check the bound Talos identity
kubectl -n system-upgrade get secret -l app.kubernetes.io/name=tuppr
```

### Step 5: Verify Current Versions

```bash
# Check Talos version on nodes
talosctl version --nodes $(yq '.nodes[0].ip' nodes.yaml)

# Check Kubernetes version
kubectl version

# Compare with cluster.yaml settings
yq '.talos_version, .kubernetes_version' cluster.yaml
```

---

## Health Check Verification

### Understanding Health Checks

tuppr uses CEL (Common Expression Language) expressions to validate cluster health:

```yaml
healthChecks:
  - apiVersion: v1
    kind: Node
    expr: status.conditions.exists(c, c.type == "Ready" && c.status == "True")
    timeout: 10m
```

This checks that all nodes have `Ready=True` condition.

### Test Health Check Logic

```bash
# List all nodes with their Ready status
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[?(@.type=="Ready")]}{.status}{"\n"}{end}{end}'

# All nodes should show "True"
```

### Custom Health Check Examples

**Check all pods in kube-system are ready:**

```yaml
healthChecks:
  - apiVersion: v1
    kind: Pod
    namespace: kube-system
    expr: status.phase == "Running" && status.containerStatuses.all(c, c.ready == true)
    timeout: 5m
```

**Check specific deployment:**

```yaml
healthChecks:
  - apiVersion: apps/v1
    kind: Deployment
    namespace: network
    name: envoy-internal-envoy-gateway
    expr: status.readyReplicas == status.replicas
    timeout: 5m
```

---

## Upgrade Simulation (Dry Run)

### Step 1: Check Current State

```bash
# Verify current versions
talosctl version --nodes $(yq '.nodes[0].ip' nodes.yaml)
kubectl get nodes -o wide

# Check upgrade CR status
kubectl describe talosupgrade talos
kubectl describe kubernetesupgrade kubernetes
```

### Step 2: Monitor Upgrade Progress

During an upgrade, monitor:

```bash
# Watch tuppr logs
kubectl -n system-upgrade logs -l app.kubernetes.io/name=tuppr -f

# Watch node status
watch kubectl get nodes -o wide

# Watch upgrade CR status
watch kubectl get talosupgrade,kubernetesupgrade
```

### Step 3: Trigger Version Bump (When Ready)

To trigger an upgrade, update `cluster.yaml`:

```yaml
talos_version: "1.12.1"  # Bump from 1.12.0
kubernetes_version: "1.35.1"  # Bump from 1.35.0
```

Then:

```bash
task configure
git add -A
git commit -m "chore: upgrade Talos to 1.12.1, K8s to 1.35.1"
git push
task reconcile
```

---

## Status Interpretation

### TalosUpgrade Status

| Status | Meaning |
| ------ | ------- |
| `Pending` | Upgrade queued, waiting for health checks |
| `InProgress` | Upgrade running on nodes |
| `Completed` | All nodes upgraded successfully |
| `Failed` | Upgrade failed, check logs |

### KubernetesUpgrade Status

| Status | Meaning |
| ------ | ------- |
| `Pending` | Waiting for Talos upgrade to complete |
| `InProgress` | K8s components being upgraded |
| `Completed` | All components upgraded |
| `Failed` | Upgrade failed, check logs |

---

## Troubleshooting

### Issue: Pod Not Starting

```bash
# Check pod events
kubectl -n system-upgrade describe pod -l app.kubernetes.io/name=tuppr

# Check for RBAC issues
kubectl auth can-i --as=system:serviceaccount:system-upgrade:tuppr list nodes
```

### Issue: Talos API Connection Failed

```bash
# Verify Talos API access from inside the cluster
kubectl -n system-upgrade exec -it deploy/tuppr -- talosctl version --nodes <control-plane-ip>

# If fails, check:
# 1. Machine patch applied
# 2. Node IP reachable from pod network
# 3. allowedRoles includes os:admin
```

### Issue: Health Checks Failing

```bash
# Check which condition is failing
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.conditions[*]}{.type}={.status}, {end}{"\n"}{end}'

# Look for non-Ready nodes
kubectl describe node <node-name>
```

### Issue: Upgrade Stuck

```bash
# Check tuppr logs for the stuck node
kubectl -n system-upgrade logs -l app.kubernetes.io/name=tuppr | grep -i error

# Force reconcile the CR
kubectl annotate talosupgrade talos reconcile.fluxcd.io/requestedAt=$(date +%s) --overwrite
```

---

## Metrics and Monitoring

### ServiceMonitor Verification

```bash
# Check ServiceMonitor exists
kubectl -n system-upgrade get servicemonitor tuppr

# Port-forward to check metrics
kubectl -n system-upgrade port-forward svc/tuppr 8080:8080
curl http://localhost:8080/metrics | grep tuppr
```

### Key Metrics

| Metric | Description |
| ------ | ----------- |
| `tuppr_upgrade_status` | Current upgrade status per CR |
| `tuppr_node_upgrade_duration_seconds` | Time taken for node upgrades |
| `tuppr_health_check_failures_total` | Health check failure count |

---

## Verification Checklist Summary

### Basic Functionality

- [ ] tuppr pod running in system-upgrade namespace
- [ ] TalosUpgrade CR exists and shows status
- [ ] KubernetesUpgrade CR exists and shows status
- [ ] CRDs registered (`kubectl api-resources | grep tuppr`)
- [ ] Versions in CRs match cluster.yaml

### Talos API Access

- [ ] Machine patch includes `kubernetesTalosAPIAccess`
- [ ] `allowedKubernetesNamespaces` includes `system-upgrade`
- [ ] `allowedRoles` includes `os:admin`
- [ ] Talos API reachable from tuppr pod

### Health Checks

- [ ] All nodes showing Ready condition
- [ ] CEL expressions evaluate correctly
- [ ] Health check timeout appropriate

### Upgrade Readiness

- [ ] Previous upgrades show `Completed` status
- [ ] No stuck or failed upgrades
- [ ] Logs show no persistent errors

---

## References

### External Documentation

- [tuppr GitHub Repository](https://github.com/home-operations/tuppr)
- [Talos kubernetesTalosAPIAccess](https://www.talos.dev/v1.12/kubernetes-guides/configuration/talos-api-access/)
- [CEL Expressions](https://kubernetes.io/docs/reference/using-api/cel/)

### Project Documentation

- [GitOps Components Implementation](./gitops-components-implementation.md#11-talos-upgrade-controller-tuppr)
- [Talos Operations](../ai-context/talos-operations.md)

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial verification guide created |
