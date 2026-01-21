# gRPC Routing Implementation Guide

> **Created:** January 2026
> **Status:** Implementation Ready
> **Dependencies:** Envoy Gateway v1.6.1+, Gateway API GRPCRoute (GA since v1.1.0)
> **Effort:** ~1-2 hours per gRPC service

---

## Overview

This guide implements **gRPC Routing** using Envoy Gateway's GRPCRoute resource. GRPCRoute is part of the Gateway API standard (GA since v1.1.0) and provides native gRPC traffic management including:

- **Service/method matching:** Route based on gRPC service and method names
- **Header-based routing:** Match on HTTP/2 headers
- **Traffic splitting:** Weighted routing for canary deployments
- **Request mirroring:** Shadow traffic for testing

### When to Use GRPCRoute vs HTTPRoute

| Scenario | Recommendation |
| -------- | -------------- |
| Pure gRPC services | **GRPCRoute** - native gRPC matching |
| gRPC-Web (browser clients) | HTTPRoute with appropriate headers |
| Mixed HTTP + gRPC on same host | HTTPRoute for both (routing by path) |
| gRPC reflection, health checks | GRPCRoute with service/method matching |

> **Note:** Envoy Gateway enforces hostname uniqueness between GRPCRoute and HTTPRoute. Use separate hostnames for gRPC services or use HTTPRoute for both if sharing a hostname.

---

## Template Implementation

### Step 1: GRPCRoute Template Pattern

Create a template for gRPC services following the project's app template structure.

**File:** `templates/config/kubernetes/apps/<namespace>/<app>/app/grpcroute.yaml.j2`

```yaml
#% if grpc_enabled is defined and grpc_enabled %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: #{ app_name }#
  namespace: #{ namespace }#
  labels:
    app.kubernetes.io/name: #{ app_name }#
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
      sectionName: grpc  # Target the gRPC listener
  hostnames:
    - "#{ grpc_hostname }#"
  rules:
    #| Match all methods on the service #|
    - matches:
        - method:
            service: "#{ grpc_service_name }#"
      backendRefs:
        - name: #{ app_name }#
          port: #{ grpc_port | default(50051) }#
          weight: 1
    #| Include gRPC reflection for development/debugging #|
    #% if grpc_reflection_enabled | default(true) %#
    - matches:
        - method:
            service: grpc.reflection.v1alpha.ServerReflection
      backendRefs:
        - name: #{ app_name }#
          port: #{ grpc_port | default(50051) }#
    #% endif %#
    #| Include gRPC health checking #|
    - matches:
        - method:
            service: grpc.health.v1.Health
      backendRefs:
        - name: #{ app_name }#
          port: #{ grpc_port | default(50051) }#
#% endif %#
```

### Step 2: Gateway Listener Configuration

Ensure the Gateway has an appropriate listener for gRPC traffic.

**Edit:** `templates/config/kubernetes/apps/network/envoy-gateway/app/gateway-internal.yaml.j2`

Add a gRPC listener (or use existing HTTPS listener):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-internal
  namespace: network
spec:
  gatewayClassName: envoy-gateway
  listeners:
    # Existing HTTPS listener for HTTP/REST traffic
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.${SECRET_DOMAIN}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: ${SECRET_DOMAIN/./-}-production-tls
      allowedRoutes:
        namespaces:
          from: All
        kinds:
          - kind: HTTPRoute

    # gRPC listener (HTTP/2 over TLS)
    - name: grpc
      protocol: HTTPS
      port: 443
      hostname: "grpc.${SECRET_DOMAIN}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: ${SECRET_DOMAIN/./-}-production-tls
      allowedRoutes:
        namespaces:
          from: All
        kinds:
          - kind: GRPCRoute
```

> **Note:** gRPC uses HTTP/2, which Envoy automatically handles for HTTPS listeners. The `protocol: HTTPS` with `kind: GRPCRoute` properly routes gRPC traffic.

---

## Example: Echo gRPC Service

### Complete GRPCRoute Example

**File:** `templates/config/kubernetes/apps/default/grpc-echo/app/grpcroute.yaml.j2`

```yaml
#% if grpc_echo_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-echo
  namespace: default
  labels:
    app.kubernetes.io/name: grpc-echo
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "grpc.${SECRET_DOMAIN}"
  rules:
    # Match specific service and method
    - matches:
        - method:
            service: echo.EchoService
            method: Echo
      backendRefs:
        - name: grpc-echo
          port: 9000
          weight: 1

    # Match all methods on the service (catch-all)
    - matches:
        - method:
            service: echo.EchoService
      backendRefs:
        - name: grpc-echo
          port: 9000

    # gRPC reflection for grpcurl/grpc_cli
    - matches:
        - method:
            service: grpc.reflection.v1alpha.ServerReflection
      backendRefs:
        - name: grpc-echo
          port: 9000

    # gRPC health service
    - matches:
        - method:
            service: grpc.health.v1.Health
      backendRefs:
        - name: grpc-echo
          port: 9000
#% endif %#
```

### Service Definition

**File:** `templates/config/kubernetes/apps/default/grpc-echo/app/service.yaml.j2`

```yaml
#% if grpc_echo_enabled | default(false) %#
---
apiVersion: v1
kind: Service
metadata:
  name: grpc-echo
  namespace: default
spec:
  selector:
    app.kubernetes.io/name: grpc-echo
  ports:
    - name: grpc
      port: 9000
      targetPort: 9000
      protocol: TCP
  type: ClusterIP
#% endif %#
```

---

## Advanced Routing Patterns

### Method-Level Routing

Route specific methods to different backends:

```yaml
rules:
  # Read operations to replica
  - matches:
      - method:
          service: myapp.UserService
          method: GetUser
      - method:
          service: myapp.UserService
          method: ListUsers
    backendRefs:
      - name: user-service-replica
        port: 50051

  # Write operations to primary
  - matches:
      - method:
          service: myapp.UserService
          method: CreateUser
      - method:
          service: myapp.UserService
          method: UpdateUser
    backendRefs:
      - name: user-service-primary
        port: 50051
```

### Regular Expression Matching

Match patterns using regex:

```yaml
rules:
  - matches:
      - method:
          service: "myapp\\..*Service"  # All services in myapp package
          type: RegularExpression
    backendRefs:
      - name: myapp-service
        port: 50051

  - matches:
      - method:
          method: "Get.*"  # All Get* methods
          type: RegularExpression
    backendRefs:
      - name: read-service
        port: 50051
```

### Header-Based Routing

Route based on gRPC metadata (HTTP/2 headers):

```yaml
rules:
  - matches:
      - headers:
          - name: x-api-version
            value: v2
    backendRefs:
      - name: service-v2
        port: 50051

  - matches:
      - headers:
          - name: x-api-version
            value: v1
    backendRefs:
      - name: service-v1
        port: 50051
```

### Traffic Splitting (Canary)

Weighted routing for gradual rollouts:

```yaml
rules:
  - matches:
      - method:
          service: myapp.OrderService
    backendRefs:
      - name: order-service-stable
        port: 50051
        weight: 90
      - name: order-service-canary
        port: 50051
        weight: 10
```

### Request Mirroring

Mirror traffic for testing:

```yaml
rules:
  - matches:
      - method:
          service: myapp.OrderService
    backendRefs:
      - name: order-service
        port: 50051
    filters:
      - type: RequestMirror
        requestMirror:
          backendRef:
            name: order-service-shadow
            port: 50051
```

---

## Header Modification

### Request Header Modification

Add or modify headers before sending to backend:

```yaml
rules:
  - matches:
      - method:
          service: myapp.OrderService
    filters:
      - type: RequestHeaderModifier
        requestHeaderModifier:
          add:
            - name: x-request-source
              value: envoy-gateway
          set:
            - name: x-forwarded-proto
              value: https
    backendRefs:
      - name: order-service
        port: 50051
```

### Response Header Modification

Modify headers in responses:

```yaml
rules:
  - matches:
      - method:
          service: myapp.OrderService
    filters:
      - type: ResponseHeaderModifier
        responseHeaderModifier:
          add:
            - name: x-served-by
              value: envoy-gateway
          remove:
            - x-internal-header
    backendRefs:
      - name: order-service
        port: 50051
```

---

## Security Integration

### JWT Authentication for gRPC

Apply JWT SecurityPolicy to GRPCRoutes:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: grpc-jwt-auth
  namespace: network
spec:
  targetSelectors:
    - group: gateway.networking.k8s.io
      kind: GRPCRoute
      matchLabels:
        security: jwt-protected
  jwt:
    providers:
      - name: keycloak
        issuer: "https://auth.matherly.net/realms/matherlynet"
        remoteJWKS:
          uri: "https://auth.matherly.net/realms/matherlynet/protocol/openid-connect/certs"
```

Then label your GRPCRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: secure-grpc
  labels:
    security: jwt-protected  # Triggers JWT validation
```

> **Note:** OIDC (session-based) authentication is NOT available for GRPCRoute. Use JWT for gRPC service authentication.

---

## Configuration Variables

### cluster.yaml Variables

```yaml
# =============================================================================
# GRPC ROUTING - gRPC Service Configuration
# =============================================================================

# -- Enable gRPC listener on internal gateway
#    (OPTIONAL) / (DEFAULT: false)
# grpc_gateway_enabled: false

# -- gRPC gateway hostname
#    (OPTIONAL) / (DEFAULT: "grpc.${cloudflare_domain}")
# grpc_hostname: "grpc.matherly.net"

# -- Default gRPC port for services
#    (OPTIONAL) / (DEFAULT: 50051)
# grpc_default_port: 50051
```

---

## Deployment

```bash
# Regenerate templates
task configure

# Commit and push
git add -A
git commit -m "feat: add gRPC routing support with GRPCRoute"
git push

# Reconcile
task reconcile

# Verify GRPCRoute
kubectl get grpcroutes -A
kubectl describe grpcroute grpc-echo -n default
```

---

## Verification

### Test with grpcurl

```bash
# Install grpcurl
brew install grpcurl

# List services (requires reflection)
grpcurl -insecure grpc.matherly.net:443 list

# Call a method
grpcurl -insecure \
  -d '{"message": "hello"}' \
  grpc.matherly.net:443 \
  echo.EchoService/Echo

# With authentication (JWT)
grpcurl -insecure \
  -H "Authorization: Bearer $JWT_TOKEN" \
  grpc.matherly.net:443 \
  myapp.SecureService/GetData
```

### Check Gateway Status

```bash
# Verify Gateway accepts GRPCRoute
kubectl describe gateway envoy-internal -n network | grep -A5 "Listeners:"

# Check GRPCRoute status
kubectl get grpcroute -A -o wide
kubectl describe grpcroute <name> -n <namespace>
```

---

## Troubleshooting

| Issue | Cause | Solution |
| ----- | ----- | -------- |
| Route not attached | Hostname conflict with HTTPRoute | Use separate hostnames for gRPC |
| 404 for gRPC calls | Service/method mismatch | Verify proto service names match route |
| TLS errors | Missing HTTP/2 | Ensure HTTPS listener, not HTTP |
| Reflection not working | Method not matched | Add explicit reflection service rule |
| Headers not forwarded | Missing filter | Add RequestHeaderModifier |

### Debug Commands

```bash
# Check Envoy config for gRPC routes
kubectl -n network port-forward svc/envoy-internal 19000:19000
curl http://localhost:19000/config_dump | jq '.configs[].dynamic_route_configs'

# View Envoy access logs for gRPC
kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-internal -c envoy | grep -i grpc

# Test connectivity to backend
kubectl -n default exec -it deploy/grpc-echo -- grpcurl -plaintext localhost:9000 list
```

---

## Limitations

| Limitation | Description | Workaround |
| ---------- | ----------- | ---------- |
| **Backend types** | Only Service supported | Use Service for all backends |
| **Hostname sharing** | Cannot share with HTTPRoute | Use dedicated gRPC hostname |
| **Filter support** | Limited to header modifiers + mirror | Use EnvoyPatchPolicy for advanced needs |
| **Streaming timeouts** | Default timeouts may be too short | Configure via ClientTrafficPolicy |

---

## References

### External Documentation

- [Envoy Gateway gRPC Routing](https://gateway.envoyproxy.io/docs/tasks/traffic/grpc-routing/)
- [Gateway API GRPCRoute](https://gateway-api.sigs.k8s.io/guides/grpc-routing/)
- [GRPCRoute API Reference](https://gateway.envoyproxy.io/docs/api/gateway_api/grpcroute/)

### Project Documentation

- [Envoy Gateway Observability & Security](./envoy-gateway-observability-security.md) - Security integration
- [JWT SecurityPolicy](./envoy-gateway-observability-security.md#phase-2-jwt-securitypolicy) - API authentication

---

## Changelog

| Date | Change |
| ---- | ------ |
| 2026-01 | Initial implementation guide created |
