# Operations Guide

> Day-2 operations, maintenance, and troubleshooting

## Task Reference

All operations use [go-task](https://taskfile.dev/). Run `task --list` for available commands.

### Core Operations

| Command | Description |
| ---------------- | ------------- |
| `task init` | Initialize configuration from samples |
| `task configure` | Render templates, validate, encrypt |
| `task reconcile` | Force Flux to sync from Git |
| `task template:debug` | Dump cluster resource states |
| `task template:tidy` | Archive template files post-setup |
| `task template:reset` | Remove all generated files |

### Talos Operations

| Command | Description |
| ---------------- | ------------- |
| `task talos:generate-config` | Regenerate Talos configs |
| `task talos:apply-node IP=x` | Apply config to node |
| `task talos:upgrade-node IP=x` | Upgrade Talos version |
| `task talos:upgrade-k8s` | Upgrade Kubernetes |
| `task talos:reset` | Reset cluster to maintenance |

### Bootstrap Operations

| Command | Description |
| ---------------- | ------------- |
| `task bootstrap:talos` | Initial Talos installation |
| `task bootstrap:apps` | Deploy core applications |

---

## Common Workflows

### Adding a New Node

1. **Prepare Hardware**
   ```bash
   # Flash Talos ISO to USB, boot node
   # Get node info while in maintenance mode:
   talosctl get disks -n <new-ip> --insecure
   talosctl get links -n <new-ip> --insecure
   ```

2. **Update Configuration**
   ```yaml
   # Edit nodes.yaml, add new entry:
   nodes:
     # ... existing nodes ...
     - name: "k8s-node-4"
       address: "192.168.1.14"
       controller: false  # or true for control plane
       disk: "/dev/nvme0n1"
       mac_addr: "aa:bb:cc:dd:ee:04"
       schematic_id: "..."
   ```

3. **Apply Configuration**
   ```bash
   task configure
   task talos:generate-config
   task talos:apply-node IP=192.168.1.14
   ```

4. **Verify**
   ```bash
   kubectl get nodes
   ```

### Upgrading Talos Version

1. **Update Version**
   ```yaml
   # Edit talos/talenv.yaml:
   talosVersion: "v1.8.0"  # New version
   ```

2. **Regenerate and Apply** (one node at a time)
   ```bash
   task talos:generate-config
   task talos:upgrade-node IP=192.168.1.10
   # Wait for node to rejoin
   kubectl get nodes
   # Repeat for each node
   task talos:upgrade-node IP=192.168.1.11
   task talos:upgrade-node IP=192.168.1.12
   ```

### Upgrading Kubernetes Version

1. **Update Version**
   ```yaml
   # Edit talos/talenv.yaml:
   kubernetesVersion: "v1.30.0"  # New version
   ```

2. **Apply Upgrade**
   ```bash
   task talos:upgrade-k8s
   ```

### Modifying Node Configuration

1. **Edit Talos Patches**
   - Global changes: `templates/config/talos/patches/global/*.yaml.j2`
   - Controller-only: `templates/config/talos/patches/controller/*.yaml.j2`
   - Specific node: `templates/config/talos/patches/<node-name>/*.yaml.j2`

2. **Apply Changes**
   ```bash
   task configure
   task talos:generate-config
   task talos:apply-node IP=<node-ip> MODE=auto
   ```

### Adding a New Application

1. **Create Directory Structure**
   ```
   templates/config/kubernetes/apps/<namespace>/<app-name>/
   ├── ks.yaml.j2
   └── app/
       ├── kustomization.yaml.j2
       ├── helmrelease.yaml.j2
       └── ocirepository.yaml.j2
   ```

2. **Add to Namespace Kustomization**
   ```yaml
   # templates/config/kubernetes/apps/<namespace>/kustomization.yaml.j2
   resources:
     - ./namespace.yaml
     - ./<app-name>/ks.yaml
   ```

3. **Render and Deploy**
   ```bash
   task configure
   git add -A && git commit -m "Add <app-name>" && git push
   # Flux will automatically deploy
   ```

### Rotating Secrets

1. **Generate New Secret**
   ```bash
   # Example: new Age key
   age-keygen -o age.key.new
   ```

2. **Re-encrypt All Secrets**
   ```bash
   # Update .sops.yaml with new public key
   # Re-encrypt each secret:
   sops updatekeys kubernetes/apps/*/secret.sops.yaml
   ```

3. **Deploy**
   ```bash
   git add -A && git commit -m "Rotate secrets" && git push
   ```

---

## Troubleshooting

### Flux Issues

**Check Flux Status**
```bash
flux check
flux get sources git -A
flux get ks -A
flux get hr -A
```

**Force Reconciliation**
```bash
task reconcile
# Or for specific resource:
flux reconcile ks flux-system --with-source
flux reconcile hr -n network envoy-gateway
```

**View Flux Logs**
```bash
kubectl -n flux-system logs deploy/source-controller
kubectl -n flux-system logs deploy/kustomize-controller
kubectl -n flux-system logs deploy/helm-controller
```

**Common Flux Errors**

| Error | Cause | Solution |
| ---------------- | ---------------- | ---------------- |
| `authentication required` | Deploy key issue | Check `github-deploy-key.sops.yaml` |
| `failed to render` | Template error | Check YAML syntax, run `task configure` |
| `dependencies not ready` | Dependency chain | Check `dependsOn` in ks.yaml |
| `HelmRelease not ready` | Helm values error | Check HelmRelease events, values |

### Talos Issues

**Check Node Status**
```bash
talosctl health -n <node-ip>
talosctl services -n <node-ip>
talosctl dmesg -n <node-ip>
```

**Etcd Issues**
```bash
talosctl etcd status -n <control-plane-ip>
talosctl etcd members -n <control-plane-ip>
```

**Reset Stuck Node**
```bash
talosctl reset --nodes <node-ip> --graceful=false
```

### Cilium Issues

**Check Cilium Status**
```bash
cilium status
cilium connectivity test
```

**Debug Networking**
```bash
kubectl -n kube-system exec -it ds/cilium -- cilium status
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list
```

**L2 Announcements Not Working**
```bash
# Check CiliumL2AnnouncementPolicy
kubectl get ciliuml2announcementpolicy -A
kubectl get ciliumbgpnodeconfigoverride -A
```

### Certificate Issues

**Check cert-manager**
```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A
```

**Debug Certificate**
```bash
kubectl -n network describe certificate wildcard
kubectl -n cert-manager logs deploy/cert-manager
```

### DNS Issues

**Internal DNS (CoreDNS)**
```bash
kubectl -n kube-system logs deploy/coredns
# Test from pod:
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes
```

**External DNS (k8s-gateway)**
```bash
kubectl -n network logs deploy/k8s-gateway
# Test from outside cluster:
dig @<cluster_dns_gateway_addr> echo.<cloudflare_domain>
```

---

## Monitoring Commands

### Cluster Health

```bash
# Node status
kubectl get nodes -o wide
talosctl health -n <any-node-ip>

# Pod status
kubectl get pods -A
kubectl get pods -A | grep -v Running

# Events
kubectl get events -A --sort-by='.metadata.creationTimestamp' | tail -20
```

### Resource Usage

```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -A

# Detailed node info
kubectl describe node <node-name>
```

### Flux Dashboard

```bash
# If using Weave GitOps UI:
kubectl -n flux-system port-forward svc/weave-gitops 9001:9001
# Open http://localhost:9001
```

---

## Backup and Recovery

### Backup etcd

```bash
# Snapshot etcd
talosctl etcd snapshot db.snapshot -n <control-plane-ip>
```

### Backup Secrets

```bash
# Export all secrets (already encrypted by SOPS in Git)
kubectl get secrets -A -o yaml > secrets-backup.yaml
```

### Recovery from Git

1. **Full Cluster Reset**
   ```bash
   task talos:reset  # Destructive!
   ```

2. **Re-bootstrap**
   ```bash
   task bootstrap:talos
   task bootstrap:apps
   ```

3. **Flux Restores State**
   - All applications defined in Git are restored
   - Secrets decrypted from SOPS

---

## Maintenance Windows

### Draining Nodes

```bash
# Cordon (prevent new pods)
kubectl cordon <node-name>

# Drain (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Perform maintenance...

# Uncordon
kubectl uncordon <node-name>
```

### Rolling Restarts

```bash
# Restart deployment
kubectl -n <namespace> rollout restart deployment/<name>

# Restart daemonset
kubectl -n <namespace> rollout restart daemonset/<name>
```

---

## Security Operations

### Audit Secret Access

```bash
# List secret access
kubectl auth can-i get secrets --as=system:serviceaccount:default:default

# Check RBAC
kubectl get rolebindings,clusterrolebindings -A
```

### Update Cloudflare Token

1. Generate new token in Cloudflare dashboard
2. Update `cluster.yaml`
3. Run `task configure`
4. Commit and push

### Rotate Deploy Key

```bash
# Generate new key
ssh-keygen -t ed25519 -C "deploy-key" -f github-deploy.key -q -P ""

# Update GitHub repository deploy keys
# Run task configure to re-encrypt
task configure
git add -A && git commit -m "Rotate deploy key" && git push
```
