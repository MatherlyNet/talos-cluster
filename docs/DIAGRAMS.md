# Architecture Diagrams

> Mermaid diagrams for visual documentation of the cluster architecture

## System Overview

```mermaid
flowchart TB
    subgraph Internet["Internet"]
        User([External User])
        CF[Cloudflare]
    end

    subgraph Cluster["Kubernetes Cluster"]
        subgraph Ingress["Ingress Layer"]
            Tunnel[cloudflared<br/>Tunnel]
            ExtGW[envoy-external<br/>Gateway]
            IntGW[envoy-internal<br/>Gateway]
        end

        subgraph Apps["Application Layer"]
            App1[App 1]
            App2[App 2]
            Echo[Echo Test]
        end

        subgraph Infra["Infrastructure Layer"]
            Cilium[Cilium CNI]
            CoreDNS[CoreDNS]
            CertMgr[cert-manager]
            ExtDNS[external-dns]
            K8sGW[k8s-gateway]
        end

        subgraph GitOps["GitOps Layer"]
            FluxOp[Flux Operator]
            FluxInst[Flux Instance]
        end
    end

    subgraph Nodes["Talos Linux Nodes"]
        CP1[Control Plane 1]
        CP2[Control Plane 2]
        CP3[Control Plane 3]
    end

    subgraph External["External Services"]
        GitHub[(GitHub Repo)]
        CFAPI[Cloudflare API]
        LE[Let's Encrypt]
    end

    User --> CF
    CF --> Tunnel
    Tunnel --> ExtGW
    ExtGW --> Apps
    IntGW --> Apps

    FluxInst --> GitHub
    ExtDNS --> CFAPI
    CertMgr --> LE

    Cilium --> Nodes
    CoreDNS --> Cluster
```

## GitOps Flow

```mermaid
flowchart LR
    subgraph Developer["Developer"]
        Code[Code Changes]
        PR[Pull Request]
    end

    subgraph GitHub["GitHub"]
        Repo[(Repository)]
        Actions[GitHub Actions]
    end

    subgraph FluxCD["Flux CD"]
        GitRepo[GitRepository]
        Kustomize[Kustomization]
        HelmRel[HelmRelease]
    end

    subgraph Cluster["Kubernetes"]
        Resources[K8s Resources]
        Secrets[Secrets]
    end

    Code --> PR
    PR --> Actions
    Actions -->|Validate| PR
    PR -->|Merge| Repo

    Repo -->|Poll/Webhook| GitRepo
    GitRepo --> Kustomize
    Kustomize --> HelmRel
    HelmRel --> Resources
    Kustomize -->|SOPS Decrypt| Secrets
```

## Network Topology

```mermaid
flowchart TB
    subgraph Network["Network: 192.168.1.0/24"]
        Router[Router<br/>192.168.1.1]

        subgraph VIPs["Virtual IPs"]
            API[K8s API VIP<br/>192.168.1.100]
            IntLB[Internal LB<br/>192.168.1.101]
            DNSLB[DNS LB<br/>192.168.1.102]
            ExtLB[External LB<br/>192.168.1.103]
        end

        subgraph Nodes["Cluster Nodes"]
            N1[node-1<br/>192.168.1.10]
            N2[node-2<br/>192.168.1.11]
            N3[node-3<br/>192.168.1.12]
        end
    end

    subgraph PodNet["Pod Network: 10.42.0.0/16"]
        Pod1[Pod A]
        Pod2[Pod B]
    end

    subgraph SvcNet["Service Network: 10.43.0.0/16"]
        Svc1[Service X]
        Svc2[Service Y]
    end

    Router --> Nodes
    N1 & N2 & N3 --> API
    API --> N1 & N2 & N3

    N1 & N2 & N3 --> PodNet
    PodNet --> SvcNet
```

## Bootstrap Sequence

```mermaid
sequenceDiagram
    participant User
    participant Task as Taskfile
    participant Talos as Talos Nodes
    participant K8s as Kubernetes
    participant Helmfile
    participant Flux

    User->>Task: task bootstrap:talos
    Task->>Talos: Apply machine config
    Talos->>Talos: Bootstrap etcd
    Talos->>K8s: Start Kubernetes
    K8s-->>User: kubeconfig generated

    User->>Task: task bootstrap:apps
    Task->>Helmfile: Install CRDs
    Helmfile->>K8s: Apply CRDs
    Task->>Helmfile: Install Cilium
    Helmfile->>K8s: Deploy Cilium
    Note over K8s: CNI Ready

    Task->>Helmfile: Install CoreDNS
    Helmfile->>K8s: Deploy CoreDNS
    Task->>Helmfile: Install Spegel
    Helmfile->>K8s: Deploy Spegel

    Task->>Helmfile: Install Flux
    Helmfile->>K8s: Deploy Flux Operator
    Helmfile->>K8s: Create Flux Instance

    Flux->>Flux: Clone Git repo
    Flux->>K8s: Reconcile resources
    Note over K8s: GitOps Active
```

## Secret Management Flow

```mermaid
flowchart LR
    subgraph Local["Local Machine"]
        Plain[Plaintext Secret]
        AgeKey[age.key<br/>Private Key]
        SOPS[SOPS CLI]
    end

    subgraph Git["Git Repository"]
        Encrypted[*.sops.yaml<br/>Encrypted]
    end

    subgraph Cluster["Kubernetes"]
        FluxKS[Kustomization<br/>Controller]
        SOPSKey[SOPS Age Secret]
        K8sSecret[Kubernetes Secret]
    end

    Plain --> SOPS
    AgeKey --> SOPS
    SOPS --> Encrypted

    Encrypted --> Git
    Git --> FluxKS

    SOPSKey --> FluxKS
    FluxKS -->|Decrypt| K8sSecret
```

## Application Dependency Graph

```mermaid
flowchart TD
    subgraph Bootstrap["Bootstrap Phase"]
        CRDs[CRDs]
        Cilium[Cilium]
        CoreDNS[CoreDNS]
        Spegel[Spegel]
    end

    subgraph FluxLayer["Flux Layer"]
        FluxOp[Flux Operator]
        FluxInst[Flux Instance]
    end

    subgraph Infra["Infrastructure Apps"]
        CertMgr[cert-manager]
        Reloader[Reloader]
    end

    subgraph Network["Network Apps"]
        EnvoyGW[Envoy Gateway]
        ExtDNS[external-dns]
        K8sGW[k8s-gateway]
        CFTunnel[Cloudflare Tunnel]
    end

    subgraph Apps["User Applications"]
        Echo[Echo]
        Custom[Custom Apps...]
    end

    CRDs --> Cilium
    Cilium --> CoreDNS
    CoreDNS --> Spegel
    Spegel --> FluxOp
    FluxOp --> FluxInst

    FluxInst --> CertMgr
    FluxInst --> Reloader

    CertMgr --> EnvoyGW
    EnvoyGW --> ExtDNS
    EnvoyGW --> K8sGW
    EnvoyGW --> CFTunnel

    K8sGW --> Echo
    CFTunnel --> Apps
    EnvoyGW --> Apps
```

## DNS Resolution Paths

### Option A: k8s-gateway (Default)

```mermaid
flowchart TB
    subgraph External["External Request"]
        ExtUser([External User])
        CloudflareDNS[Cloudflare DNS]
    end

    subgraph Internal["Internal Request"]
        IntUser([Internal User])
        HomeDNS[Home DNS<br/>Pi-hole/AdGuard]
    end

    subgraph Cluster["Kubernetes Cluster"]
        K8sGW[k8s-gateway<br/>Split DNS]
        EnvoyInt[envoy-internal]
        EnvoyExt[envoy-external]
        CFTunnel[cloudflared]
        App[Application]
    end

    ExtUser -->|1. DNS Query| CloudflareDNS
    CloudflareDNS -->|2. Tunnel Route| CFTunnel
    CFTunnel -->|3. HTTPS| EnvoyExt
    EnvoyExt -->|4. Route| App

    IntUser -->|1. DNS Query| HomeDNS
    HomeDNS -->|2. Forward| K8sGW
    K8sGW -->|3. Resolve| EnvoyInt
    IntUser -->|4. Direct HTTPS| EnvoyInt
    EnvoyInt -->|5. Route| App
```

### Option B: UniFi DNS (When unifi_host + unifi_api_key configured)

```mermaid
flowchart TB
    subgraph External["External Request"]
        ExtUser([External User])
        CloudflareDNS[Cloudflare DNS]
    end

    subgraph Internal["Internal Request"]
        IntUser([Internal User])
        UniFiDNS[UniFi Controller<br/>Native DNS]
    end

    subgraph Cluster["Kubernetes Cluster"]
        UniFiExt[unifi-dns<br/>external-dns webhook]
        EnvoyInt[envoy-internal]
        EnvoyExt[envoy-external]
        CFTunnel[cloudflared]
        App[Application]
    end

    ExtUser -->|1. DNS Query| CloudflareDNS
    CloudflareDNS -->|2. Tunnel Route| CFTunnel
    CFTunnel -->|3. HTTPS| EnvoyExt
    EnvoyExt -->|4. Route| App

    UniFiExt -.->|Writes A Records| UniFiDNS
    IntUser -->|1. DNS Query| UniFiDNS
    UniFiDNS -->|2. Resolve to IP| IntUser
    IntUser -->|3. Direct HTTPS| EnvoyInt
    EnvoyInt -->|4. Route| App
```

**Note:** UniFi DNS writes records directly to the UniFi controller, eliminating the need for split-horizon DNS configuration on your router.

## Cilium Load Balancer Modes

### DSR Mode (Default)

```mermaid
flowchart LR
    Client([Client]) -->|1. Request| LBNode[LB Node]
    LBNode -->|2. Forward| PodNode[Pod Node]
    PodNode -->|3. Direct Response| Client

    style LBNode fill:#f9f,stroke:#333
    style PodNode fill:#9ff,stroke:#333
```

### SNAT Mode

```mermaid
flowchart LR
    Client([Client]) -->|1. Request| LBNode[LB Node]
    LBNode -->|2. Forward + SNAT| PodNode[Pod Node]
    PodNode -->|3. Response| LBNode
    LBNode -->|4. Return| Client

    style LBNode fill:#f9f,stroke:#333
    style PodNode fill:#9ff,stroke:#333
```

## Certificate Lifecycle

```mermaid
sequenceDiagram
    participant Ingress as HTTPRoute
    participant CM as cert-manager
    participant LE as Let's Encrypt
    participant CF as Cloudflare DNS
    participant K8s as Kubernetes

    Ingress->>CM: Request Certificate
    CM->>LE: ACME Challenge Request
    LE->>CM: DNS-01 Challenge
    CM->>CF: Create TXT Record
    CF-->>LE: Verify Record
    LE->>CM: Issue Certificate
    CM->>K8s: Store as Secret
    K8s-->>Ingress: Mount Certificate
```

## Upgrade Workflow

```mermaid
flowchart TD
    Start([Start Upgrade]) --> CheckVersion{Check Current<br/>Version}
    CheckVersion --> UpdateConfig[Update talenv.yaml]
    UpdateConfig --> GenConfig[task talos:generate-config]

    GenConfig --> Node1[Upgrade Node 1]
    Node1 --> Wait1{Node Ready?}
    Wait1 -->|No| Wait1
    Wait1 -->|Yes| Node2[Upgrade Node 2]

    Node2 --> Wait2{Node Ready?}
    Wait2 -->|No| Wait2
    Wait2 -->|Yes| Node3[Upgrade Node 3]

    Node3 --> Wait3{Node Ready?}
    Wait3 -->|No| Wait3
    Wait3 -->|Yes| Verify[Verify Cluster Health]

    Verify --> Done([Upgrade Complete])
```

---

## Usage

These diagrams are rendered automatically in:

- GitHub markdown preview
- Most documentation platforms (GitBook, Docusaurus, etc.)
- VS Code with Mermaid extensions

To view locally:

```bash
# Install Mermaid CLI
npm install -g @mermaid-js/mermaid-cli

# Generate PNG
mmdc -i DIAGRAMS.md -o diagrams/
```
