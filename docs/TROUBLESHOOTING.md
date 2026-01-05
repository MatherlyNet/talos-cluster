# Troubleshooting Guide

> Systematic troubleshooting for common cluster issues

## Diagnostic Flowchart

```
                    ┌─────────────────────────────────┐
                    │       ISSUE DETECTED            │
                    └─────────────────┬───────────────┘
                                      │
                    ┌─────────────────▼───────────────┐
                    │    What layer is affected?      │
                    └─────────────────┬───────────────┘
                                      │
        ┌─────────────┬───────────────┼───────────────┬─────────────┐
        │             │               │               │             │
        ▼             ▼               ▼               ▼             ▼
   ┌─────────┐  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
   │  Nodes  │  │   Pods  │    │ Network │    │  Flux   │    │  Certs  │
   │ Not     │  │   Not   │    │  Issues │    │   Not   │    │   Not   │
   │ Ready   │  │ Running │    │         │    │ Syncing │    │  Valid  │
   └────┬────┘  └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘
        │            │              │              │              │
        ▼            ▼              ▼              ▼              ▼
   See: §1       See: §2        See: §3       See: §4        See: §5
```

---

## Section 1: Node Issues

### Symptom: Node Not Ready

**Quick Check:**
```bash
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -A5 Conditions
```

**Decision Tree:**

```
Node Not Ready
     │
     ├── Status: NotReady + NetworkNotReady
     │   └── CNI Issue → Go to "Cilium Not Running"
     │
     ├── Status: NotReady + DiskPressure
     │   └── Disk full → Clean up or expand storage
     │
     ├── Status: NotReady + MemoryPressure
     │   └── OOM → Check resource limits, evicted pods
     │
     └── Status: Unknown
         └── Node unreachable → Check network/hardware
```

**Detailed Diagnostics:**

```bash
# 1. Check Talos health
talosctl health -n <node-ip>

# 2. Check Talos services
talosctl services -n <node-ip>

# 3. Check system logs
talosctl dmesg -n <node-ip> | tail -50

# 4. Check kubelet logs
talosctl logs kubelet -n <node-ip>
```

**Common Fixes:**

| Issue | Solution |
| ------- | ---------- |
| Kubelet not starting | Check etcd health, restart kubelet |
| Network plugin failing | Check Cilium pods, network connectivity |
| Disk pressure | Clean up unused images, PVCs |
| API server unreachable | Check VIP, control plane pods |

---

## Section 2: Pod Issues

### Symptom: Pods Not Running

**Quick Check:**
```bash
kubectl get pods -A | grep -v Running
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```

**Decision Tree:**

```
Pod Not Running
     │
     ├── Status: Pending
     │   ├── "no nodes available" → Check node capacity/taints
     │   ├── "Insufficient cpu/memory" → Adjust requests/limits
     │   └── "persistentvolumeclaim not found" → Check PVC/StorageClass
     │
     ├── Status: ImagePullBackOff
     │   ├── Private registry → Check imagePullSecrets
     │   ├── Image not found → Verify image:tag exists
     │   └── Rate limited → Wait or configure Spegel
     │
     ├── Status: CrashLoopBackOff
     │   ├── Check logs → kubectl logs <pod> --previous
     │   ├── Config error → Check ConfigMaps/Secrets
     │   └── Dependency missing → Check init containers
     │
     └── Status: ContainerCreating (stuck)
         ├── CNI issue → Check Cilium
         ├── Volume mount → Check PVC status
         └── Secret missing → Check SOPS decryption
```

**Image Pull Issues (Spegel):**

```bash
# Check Spegel status
kubectl get pods -n kube-system -l app.kubernetes.io/name=spegel

# Check if image is cached
kubectl logs -n kube-system -l app.kubernetes.io/name=spegel | grep <image>
```

---

## Section 3: Network Issues

### Symptom: Service Not Reachable

**Quick Check:**
```bash
kubectl get svc -A | grep <service>
kubectl get endpoints -n <namespace> <service>
cilium status
```

**Decision Tree:**

```
Service Not Reachable
     │
     ├── No External IP (LoadBalancer pending)
     │   ├── Check CiliumLoadBalancerIPPool
     │   ├── Check CiliumL2AnnouncementPolicy
     │   └── Check available IPs in pool
     │
     ├── External IP assigned but not responding
     │   ├── ARP issue → Check L2 announcements
     │   ├── No endpoints → Check pod labels/selectors
     │   └── Firewall → Check node firewall rules
     │
     └── Internal service not reachable
         ├── DNS issue → Test with nslookup from pod
         ├── NetworkPolicy blocking → Check policies
         └── Cilium identity issue → Check BPF maps
```

**Cilium Diagnostics:**

```bash
# Overall status
cilium status

# Check BPF load balancer entries
kubectl -n kube-system exec -it ds/cilium -- cilium bpf lb list

# Check service resolution
kubectl -n kube-system exec -it ds/cilium -- cilium service list

# Run connectivity test
cilium connectivity test
```

**L2 Announcement Issues:**

```bash
# Check L2 policy
kubectl get ciliuml2announcementpolicy -o yaml

# Check IP pool
kubectl get ciliumloadbalancerippool -o yaml

# Verify ARP responses (from external machine)
arping -I <interface> <loadbalancer-ip>
```

### Symptom: Traffic Blocked by Network Policies

> **Note:** CiliumNetworkPolicies are optional. Skip this section if `network_policies_enabled: false`.

**Quick Check:**
```bash
hubble observe --verdict DROPPED
hubble observe --verdict AUDIT
kubectl get cnp -A
kubectl get ccnp -A
```

**Decision Tree:**

```
Traffic Blocked
     │
     ├── Hubble shows DROPPED verdict
     │   ├── Check policy name in verdict → Review policy rules
     │   ├── Missing egress rule → Add DNS/API server access
     │   └── Missing ingress rule → Allow source namespace
     │
     ├── Hubble shows AUDIT verdict (audit mode)
     │   └── Traffic allowed but logged → Review before switching to enforce
     │
     └── No verdict shown
         ├── Hubble not enabled → Enable hubble_enabled: true
         └── Policy not matching → Check endpointSelector labels
```

**Debugging Network Policies:**

```bash
# Monitor policy verdicts via Hubble
hubble observe --verdict DROPPED
hubble observe --verdict AUDIT
hubble observe --namespace <ns> --verdict DROPPED

# List deployed policies
kubectl get cnp -A       # Namespace-scoped
kubectl get ccnp -A      # Cluster-wide

# Inspect policy details
kubectl describe cnp -n <ns> <name>
kubectl get cnp -n <ns> <name> -o yaml

# Debug specific pod connectivity
hubble observe --from-pod <ns>/<pod> --verdict DROPPED
hubble observe --to-pod <ns>/<pod> --verdict DROPPED

# Check Cilium endpoint policy status
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list
kubectl -n kube-system exec -it ds/cilium -- cilium policy get -n <ns>
```

**Common Network Policy Issues:**

| Issue | Cause | Solution |
| ------- | ------- | ---------- |
| Pod can't resolve DNS | Missing DNS egress rule | Add egress to `kube-system/kube-dns` port 53 |
| Pod can't reach API server | Missing API egress rule | Add egress to `kube-apiserver` entity |
| Metrics not scraped | Missing prometheus ingress | Allow ingress from `monitoring/prometheus` |
| External access blocked | Missing world egress | Add egress to `world` entity with port |
| Cross-namespace blocked | Missing namespace selector | Use `io.kubernetes.pod.namespace` label |

**Switching from Audit to Enforce:**

1. Monitor for 24-48 hours with `network_policies_mode: "audit"`
2. Review AUDIT verdicts for legitimate traffic
3. Adjust policies as needed
4. Change to `network_policies_mode: "enforce"` in `cluster.yaml`
5. Run `task configure` and commit changes

### Symptom: BGP Peering Not Established

> **Note:** BGP is optional. Skip this section if you're using L2 announcements (default).

**Quick Check:**
```bash
cilium bgp peers
kubectl get ciliumbgpclusterconfig -A
kubectl get ciliumbgppeerconfig -A
```

**Decision Tree:**

```
BGP Session Not Establishing
     │
     ├── Session state: Active
     │   └── Firewall blocking TCP 179 → Add firewall rule
     │
     ├── Session state: OpenSent
     │   └── ASN mismatch → Verify ASNs match both sides
     │
     ├── Session flapping
     │   └── MTU issues → Check path MTU, reduce if needed
     │
     └── No routes exchanged
         └── Missing "no bgp ebgp-requires-policy" → Add to router config
```

**BGP Diagnostics:**

```bash
# Check BGP peer status (detailed)
cilium bgp peers

# View advertised routes
cilium bgp routes advertised ipv4 unicast

# View available/learned routes
cilium bgp routes available ipv4 unicast

# Check BGP CRDs
kubectl get ciliumbgpclusterconfig -o yaml
kubectl get ciliumbgppeerconfig -o yaml
kubectl get ciliumbgpadvertisement -o yaml

# Check Cilium agent BGP logs
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp

# Check if LoadBalancer IPs are assigned
kubectl get svc -A | grep LoadBalancer

# Verify IP pool has available addresses
kubectl get ciliumloadbalancerippool -o yaml
```

**UniFi Router Verification (SSH):**

```bash
# Check FRR service status
service frr status

# View running BGP config
vtysh -c "show running-config"

# Check BGP session status
vtysh -c "show ip bgp summary"

# View learned routes
vtysh -c "show ip bgp"
ip route show proto bgp

# Check specific neighbor
vtysh -c "show ip bgp neighbors <PEER_IP>"
```

**Common BGP Issues:**

| Issue | Cause | Solution |
| ------- | ------- | ---------- |
| Session stuck in `Active` | Firewall blocking port 179 | Add firewall rule for TCP 179 |
| Session stuck in `OpenSent` | ASN mismatch | Verify ASNs match on both sides |
| Session flapping | MTU issues | Check path MTU, reduce if needed |
| No routes exchanged | Missing policy config | Add `no bgp ebgp-requires-policy` |
| LoadBalancer IP not advertised | IP pool exhausted | Check CiliumLoadBalancerIPPool |
| Ping to LB IP fails | Expected behavior | Use `curl` - ICMP not supported |

> **Note:** BGP-advertised LoadBalancer IPs will NOT respond to ICMP ping. This is a known Cilium limitation ([GitHub #14118](https://github.com/cilium/cilium/issues/14118)). Use `curl` or actual service connections to test reachability.

---

## Section 4: Flux Issues

### Symptom: Flux Not Syncing

**Quick Check:**
```bash
flux check
flux get sources git -A
flux get ks -A
flux get hr -A
```

**Decision Tree:**

```
Flux Not Syncing
     │
     ├── GitRepository not ready
     │   ├── "authentication required" → Check deploy key
     │   ├── "repository not found" → Verify repo URL
     │   └── "unable to clone" → Check network/SSH
     │
     ├── Kustomization not ready
     │   ├── "Source not found" → Check sourceRef
     │   ├── "dependency not ready" → Check dependsOn chain
     │   └── "failed to render" → Check YAML syntax
     │
     └── HelmRelease not ready
         ├── "chart not found" → Check OCIRepository
         ├── "values validation failed" → Check values
         └── "upgrade failed" → Check helm diff
```

**Force Reconciliation:**

```bash
# Reconcile entire cluster
task reconcile

# Reconcile specific resource
flux reconcile ks <name> --with-source
flux reconcile hr -n <namespace> <name>

# Suspend and resume (for stuck resources)
flux suspend ks <name>
flux resume ks <name>
```

**Check Flux Logs:**

```bash
# Source controller (Git/OCI)
kubectl -n flux-system logs deploy/source-controller

# Kustomize controller
kubectl -n flux-system logs deploy/kustomize-controller

# Helm controller
kubectl -n flux-system logs deploy/helm-controller
```

**SOPS Decryption Issues:**

```bash
# Check SOPS secret exists
kubectl -n flux-system get secret sops-age

# Verify key matches
kubectl -n flux-system get secret sops-age -o jsonpath='{.data.age\.agekey}' | base64 -d

# Test decryption locally
sops -d <file>.sops.yaml
```

---

## Section 5: Certificate Issues

### Symptom: Certificates Not Ready

**Quick Check:**
```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A
```

**Decision Tree:**

```
Certificate Not Ready
     │
     ├── CertificateRequest pending
     │   └── Check ClusterIssuer ready
     │
     ├── Order pending
     │   └── Waiting for challenge verification
     │
     └── Challenge failing
         ├── DNS-01: Check Cloudflare token/permissions
         ├── HTTP-01: Check ingress routing
         └── Timeout: Check DNS propagation
```

**cert-manager Diagnostics:**

```bash
# Check issuer status
kubectl get clusterissuer -o yaml
kubectl get issuer -A -o yaml

# Check cert-manager logs
kubectl -n cert-manager logs deploy/cert-manager

# Describe failing certificate
kubectl describe certificate <name> -n <namespace>

# Check challenge status
kubectl describe challenge <name> -n <namespace>
```

**Cloudflare DNS-01 Issues:**

```bash
# Verify token permissions (Zone:DNS:Edit, Zone:Zone:Read)
# Check TXT record creation
dig +short TXT _acme-challenge.<domain>

# Check external-dns logs
kubectl -n network logs deploy/external-dns
```

---

## Section 6: Talos-Specific Issues

### Symptom: VM Boots from ISO After Talos Install (Proxmox)

**Console shows:**
```
[talos] task haltIfInstalled (1/1): Talos is already installed to disk but booted from another media and talos.halt_if_installed kernel parameter is set. Please reboot from the disk.
```

**Quick Check:**
```bash
# Check VM boot order in Proxmox
qm config <VMID> | grep boot
```

**Decision Tree:**

```
Talos halt_if_installed Error
     │
     ├── Boot order incorrect
     │   └── VM booting from ISO (ide2) before disk (scsi0)
     │       └── FIXED: boot_order = ["scsi0", "ide2"] in OpenTofu templates
     │
     └── ISO still attached after install
         └── Expected - ISO can remain, boot order ensures disk priority
```

**Root Cause:**
The Proxmox VM was booting from the ISO (ide2) instead of the installed disk (scsi0). Talos detects it's already installed and halts to prevent accidental reinstallation.

**Fix Applied:**
The `boot_order` configuration in `templates/config/infrastructure/tofu/main.tf.j2` ensures:
1. Initial boot: Empty disk fails → falls back to ISO → Talos installs
2. After install: Boots from disk automatically (Talos on scsi0)

```hcl
boot_order = ["scsi0", "ide2"]
```

**For Existing VMs (manual fix):**
```bash
# Option 1: Change boot order
qm set <VMID> -boot order=scsi0,ide2

# Option 2: Remove ISO entirely
qm set <VMID> -ide2 none

# Then restart the VM
qm start <VMID>
```

**For New VMs:**
Run `task configure` to regenerate infrastructure files with the boot_order fix, then `task infra:apply`.

---

### Symptom: Bootstrap Node Stuck in MAINTENANCE

**Console/logs show:**
```
Node still in MAINTENANCE stage after config apply
```

**Quick Check:**
```bash
# Check node stage
talosctl get machineconfig -n <node-ip> --insecure

# Check if config was applied
talosctl dmesg -n <node-ip> --insecure | tail -50
```

**Decision Tree:**

```
Node Stuck in MAINTENANCE
     │
     ├── Config never applied
     │   └── Bootstrap apply failed silently
     │       └── FIX: Use enhanced bootstrap with retry logic
     │
     ├── Config applied but node not transitioning
     │   ├── Disk detection issue → Check installDiskSelector
     │   └── Network configuration error → Check node IP/gateway
     │
     └── Multiple nodes stuck
         └── Network connectivity issue during apply
             └── Check firewall rules, port 50000
```

**Root Cause:**
The original `task bootstrap:talos` used semicolon-separated commands that continue even if individual nodes fail, causing silent failures.

**Enhanced Bootstrap (Now Default):**
```bash
# Full bootstrap with pre-flight checks, per-node retry, and verification
task bootstrap:talos

# Or run individual phases:
task bootstrap:preflight        # Verify all nodes reachable
task bootstrap:apply-sequential # Apply configs with retry
task bootstrap:verify           # Confirm nodes transitioned
```

**Recovery for Stuck Nodes:**
```bash
# 1. Check which nodes failed
talosctl get machineconfig -n <node-ip> --insecure

# 2. Apply config to specific node manually
task talos:apply-node IP=<node-ip>

# 3. Monitor node boot progress
talosctl dmesg -n <node-ip> --insecure -f

# 4. If still stuck, reset and retry
talosctl reset -n <node-ip> --insecure --graceful=false
task bootstrap:preflight
task bootstrap:apply-sequential
task bootstrap:verify
```

---

### etcd Problems

```bash
# Check etcd status
talosctl etcd status -n <control-plane-ip>

# List etcd members
talosctl etcd members -n <control-plane-ip>

# Check etcd health
talosctl etcd alarm list -n <control-plane-ip>
```

**etcd Quorum Lost:**

```bash
# If only one control plane survives
talosctl etcd forfeit-leadership -n <surviving-node>
talosctl etcd remove-member <failed-member-id> -n <surviving-node>

# Re-bootstrap failed node
task talos:apply-node IP=<failed-node-ip>
```

### API Server Unreachable

```bash
# Check VIP assignment
talosctl get virtualip -n <any-control-plane>

# Check API server pods
talosctl containers -n <control-plane-ip> | grep kube-apiserver

# Check API server logs
talosctl logs kube-apiserver -n <control-plane-ip>
```

---

## Quick Reference: Diagnostic Commands

### Cluster Health

```bash
# Overall health check
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

### Network Stack

```bash
# Cilium
cilium status
cilium connectivity test

# DNS
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes

# Split DNS (k8s-gateway or unifi-dns)
dig @<cluster_dns_gateway_addr> <domain>

# If using unifi-dns
kubectl -n network logs deploy/unifi-dns-external-dns

# If using k8s-gateway (default)
kubectl -n network logs deploy/k8s-gateway
```

### GitOps Stack

```bash
# Flux overall
flux check
flux stats

# Reconciliation status
flux get all -A
```

### Talos Nodes

```bash
# Health
talosctl health -n <ip>

# Services
talosctl services -n <ip>

# Logs
talosctl dmesg -n <ip>
talosctl logs kubelet -n <ip>
```

---

## Common Error Messages

| Error | Likely Cause | Solution |
| ------- | -------------- | ---------- |
| `halt_if_installed kernel parameter is set` | VM booting from ISO instead of disk | Change boot order to disk first (see §6) |
| `no nodes available to schedule pods` | All nodes tainted or full | Check node taints, resource limits |
| `container runtime network not ready` | Cilium not running | Check Cilium pods, restart |
| `failed to pull image` | Registry auth, rate limit | Check imagePullSecrets, Spegel |
| `SOPS: Decryption failed` | Wrong Age key | Verify sops-age secret matches age.key |
| `authentication required for git repo` | Deploy key issue | Check github-deploy-key secret |
| `unable to recognize "..."` | CRD not installed | Check CRD installation order |
| `context deadline exceeded` | Timeout on operation | Check network, increase timeout |
| `etcd cluster is unavailable` | etcd quorum lost | Check control plane health |
| `policy verdict: DROPPED` | Network policy blocking | Check CNP rules, add required access |
| `policy verdict: AUDIT` | Policy audit mode | Traffic allowed but logged for review |

---

## Emergency Procedures

### Full Cluster Recovery

```bash
# 1. If nodes are responsive
talosctl health -n <any-node>

# 2. If API is down but nodes up
talosctl kubeconfig -n <control-plane-ip>

# 3. If etcd corrupt (last resort)
task talos:reset
task bootstrap:talos
task bootstrap:apps
# Flux will restore all applications from Git
```

### Single Node Recovery

```bash
# Reset stuck node
talosctl reset --nodes <node-ip> --graceful=false

# Re-apply configuration
task talos:apply-node IP=<node-ip>

# Wait for rejoin
kubectl get nodes -w
```

### Force Flux Resync

```bash
# Nuclear option: delete and let Flux recreate
flux suspend ks --all
flux resume ks --all

# Or delete stuck HelmRelease
kubectl delete hr <name> -n <namespace>
# Flux will recreate it
```
