# kubectl OIDC Login Setup

**Date**: January 12, 2026
**Prerequisites**: Kubernetes API Server OIDC Authentication configured (see `docs/research/kubernetes-api-server-oidc-authentication-jan-2026.md`)

## Overview

This guide explains how to configure `kubectl` to authenticate with your Kubernetes cluster using OIDC tokens from Keycloak. After setup, you'll log in through your browser using Google SSO (or other IdPs) instead of using certificate-based authentication.

## Architecture

```
┌──────────┐    1. kubectl command     ┌────────────────────┐
│  kubectl │ ─────────────────────────▶│  kubectl oidc-login│
└──────────┘                           └─────────┬──────────┘
                                                 │ 2. Opens browser
                                                 ▼
                                        ┌──────────────────────┐
                                        │   Keycloak OIDC      │
                                        │  (Google IdP auth)   │
                                        └─────────┬────────────┘
                                                  │ 3. Returns ID token
                                                  ▼
┌──────────┐    4. API request         ┌────────────────────┐
│  kubectl │ ◀──── with Bearer token ──│ kubectl oidc-login │
└─────┬────┘                           └────────────────────┘
      │ 5. API Server validates token
      ▼
┌────────────────────────┐
│  Kubernetes API Server │
│  (validates via JWKS)  │
└────────────────────────┘
```

## Installation

### Option 1: kubectl krew (Recommended for this project)

This project uses [mise](https://mise.jdx.dev) for tool management. Krew is already configured in `.mise.toml`, so after running `mise install`, krew is available.

```bash
# Krew is already installed via mise - just install the plugin
kubectl krew install oidc-login

# Verify installation
kubectl oidc-login --version
```

> **Note**: If you're working outside this project's mise setup, install krew first: https://krew.sigs.k8s.io/docs/user-guide/setup/install/

### Option 2: Direct Binary Download

```bash
# Download latest release for your platform
# REF: https://github.com/int128/kubelogin/releases

# macOS (Apple Silicon)
curl -LO https://github.com/int128/kubelogin/releases/latest/download/kubelogin_darwin_arm64.zip
unzip kubelogin_darwin_arm64.zip
chmod +x kubelogin
sudo mv kubelogin /usr/local/bin/kubectl-oidc_login

# macOS (Intel)
curl -LO https://github.com/int128/kubelogin/releases/latest/download/kubelogin_darwin_amd64.zip
unzip kubelogin_darwin_amd64.zip
chmod +x kubelogin
sudo mv kubelogin /usr/local/bin/kubectl-oidc_login

# Linux
curl -LO https://github.com/int128/kubelogin/releases/latest/download/kubelogin_linux_amd64.zip
unzip kubelogin_linux_amd64.zip
chmod +x kubelogin
sudo mv kubelogin /usr/local/bin/kubectl-oidc_login
```

## Configuration

### Step 1: Get Kubernetes Client Secret

The client secret is stored in `cluster.yaml` (SOPS-encrypted). Use `sops` to view it:

```bash
# View the kubernetes_oidc_client_secret value
grep kubernetes_oidc_client_secret cluster.yaml

# If you need the actual value from generated secrets
sops -d kubernetes/identity/keycloak/config/secrets.sops.yaml | grep KUBERNETES_CLIENT_SECRET
```

### Step 2: Configure kubeconfig

Add a new user to your kubeconfig using the OIDC authentication plugin:

```bash
# Set variables
ISSUER_URL="https://sso.matherly.net/realms/matherlynet"
CLIENT_ID="kubernetes"
CLIENT_SECRET="<your-client-secret-from-cluster.yaml>"

# Add OIDC user to kubeconfig
kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url="${ISSUER_URL}" \
  --exec-arg=--oidc-client-id="${CLIENT_ID}" \
  --exec-arg=--oidc-client-secret="${CLIENT_SECRET}"

# Set current context to use OIDC user
kubectl config set-context --current --user=oidc-user
```

### Step 3: Test Authentication

```bash
# First command will open browser for login
kubectl get nodes

# Expected: Browser opens to Keycloak → Google login → Success
# Token cached for future requests
```

### Alternative: Separate Context for OIDC

If you want to keep both certificate-based and OIDC authentication:

```bash
# Create new context for OIDC auth
kubectl config set-context oidc-context \
  --cluster=<your-cluster-name> \
  --user=oidc-user

# Switch between contexts
kubectl config use-context oidc-context  # OIDC auth
kubectl config use-context admin@kubernetes  # Certificate auth
```

## Advanced Configuration

### Persistent Token Storage

By default, tokens are cached in `~/.kube/cache/oidc-login/`. You can customize:

```bash
kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url="${ISSUER_URL}" \
  --exec-arg=--oidc-client-id="${CLIENT_ID}" \
  --exec-arg=--oidc-client-secret="${CLIENT_SECRET}" \
  --exec-arg=--token-cache-dir="${HOME}/.kube/oidc-cache"
```

### Custom Listen Port (if 8000 conflicts)

```bash
kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url="${ISSUER_URL}" \
  --exec-arg=--oidc-client-id="${CLIENT_ID}" \
  --exec-arg=--oidc-client-secret="${CLIENT_SECRET}" \
  --exec-arg=--listen-address=127.0.0.1:18000
```

**Note**: If you change the listen port, update the Keycloak client redirect URIs in `realm-config.yaml.j2`.

### Skip Browser Auto-Open

For remote/headless environments:

```bash
kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url="${ISSUER_URL}" \
  --exec-arg=--oidc-client-id="${CLIENT_ID}" \
  --exec-arg=--oidc-client-secret="${CLIENT_SECRET}" \
  --exec-arg=--skip-open-browser

# Plugin will print URL to copy/paste in another browser
```

## RBAC Setup

### Grant Admin Access to OIDC Users

Create ClusterRoleBinding for OIDC admin group:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-cluster-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: Group
    name: oidc:admin  # Keycloak "admin" group → "oidc:admin" in K8s
    apiGroup: rbac.authorization.k8s.io
```

Apply:

```bash
kubectl apply -f rbac-oidc-admins.yaml
```

### Grant View-Only Access

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-cluster-viewers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: Group
    name: oidc:viewer  # Keycloak "viewer" group
    apiGroup: rbac.authorization.k8s.io
```

### Namespace-Scoped Access

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-access
  namespace: development
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
  - kind: Group
    name: oidc:developer
    apiGroup: rbac.authorization.k8s.io
```

## Verification

### Check Current User

```bash
kubectl auth whoami
```

Expected output:

```yaml
ATTRIBUTE   VALUE
Username    oidc:your-email@matherly.net
Groups      [oidc:admin system:authenticated]
```

### Check Effective Permissions

```bash
kubectl auth can-i --list
```

### Decode ID Token (for debugging)

```bash
# Get cached token
TOKEN=$(kubectl oidc-login get-token \
  --oidc-issuer-url="${ISSUER_URL}" \
  --oidc-client-id="${CLIENT_ID}" \
  --oidc-client-secret="${CLIENT_SECRET}" | jq -r '.status.token')

# Decode JWT claims
echo "$TOKEN" | cut -d. -f2 | base64 -d | jq
```

## Troubleshooting

### Issue: "Unable to authenticate the request"

**Cause**: Token validation failed at API Server

**Solution**:

1. Verify API Server OIDC configuration:

   ```bash
   talosctl -n 192.168.22.101 logs controller-runtime | grep oidc
   ```

2. Check issuer URL matches:

   ```bash
   echo "$TOKEN" | cut -d. -f2 | base64 -d | jq -r '.iss'
   # Should be: https://sso.matherly.net/realms/matherlynet
   ```

3. Check audience matches:

   ```bash
   echo "$TOKEN" | cut -d. -f2 | base64 -d | jq -r '.aud'
   # Should be: kubernetes
   ```

### Issue: "Forbidden" after successful login

**Cause**: User authenticated but has no RBAC permissions

**Solution**: Create ClusterRoleBinding (see RBAC Setup section above)

### Issue: Browser doesn't open

**Cause**: System browser not configured or plugin can't detect it

**Solution**: Use `--skip-open-browser` flag and manually visit printed URL

### Issue: "Address already in use" (port 8000)

**Cause**: Another process using port 8000

**Solution**: Use custom listen port (see Advanced Configuration)

### Issue: Token expired

**Cause**: ID tokens expire after 5 minutes by default (Keycloak setting)

**Solution**: Token is automatically refreshed using refresh token. If refresh fails, re-authenticate:

```bash
rm -rf ~/.kube/cache/oidc-login/
kubectl get nodes  # Will trigger new login
```

## Security Considerations

### Client Secret Protection

- Client secret in kubeconfig is **not encrypted** - protect your kubeconfig file!
- Consider using `chmod 600 ~/.kube/config` to restrict access
- On shared systems, use separate kubeconfig files per user

### Token Expiration

- ID tokens expire after 5 minutes (configurable in Keycloak)
- Refresh tokens valid for 30 days (configurable in Keycloak)
- After refresh token expires, full re-authentication required

### Network Security

- OIDC authentication flow happens over HTTPS
- API Server fetches JWKS from Keycloak over HTTPS
- Browser callback uses localhost (http://localhost:8000) - safe for local use

## References

- [kubectl oidc-login GitHub](https://github.com/int128/kubelogin)
- [Kubernetes OIDC Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens)
- [Keycloak OpenID Connect](https://www.keycloak.org/docs/latest/server_admin/#_oidc)
- [Project Implementation Guide](../research/kubernetes-api-server-oidc-authentication-jan-2026.md)

---

**Last Updated**: January 12, 2026
**Author**: AI Implementation Agent (Claude Sonnet 4.5)
**Status**: Ready for Use
