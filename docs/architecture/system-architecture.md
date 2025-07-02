# System Architecture

## High-Level System Architecture

```mermaid
graph TB
    subgraph "Client Layer"
        C1[VPN Clients]
        C2[Web Browsers]
        C3[CLI Tools]
    end

    subgraph "Load Balancer & Proxy Layer"
        T[Traefik v3.x<br/>Load Balancer]
        T --> |SSL/TLS Termination| TP1[HTTP Proxy :8888]
        T --> |SOCKS5 Routing| TP2[SOCKS5 Proxy :1080]
        T --> |Management| TP3[Dashboard :8080]
    end

    subgraph "VPN Core Services"
        VS[Xray VPN Server<br/>VLESS+Reality :8443]
        PA[Proxy Auth Service<br/>:9001]
        IS[Identity Service<br/>:9002]
    end

    subgraph "Data Layer"
        PG[(PostgreSQL<br/>User Data & Config)]
        RD[(Redis<br/>Sessions & Cache)]
        FS[File System<br/>User Configs & Keys]
    end

    subgraph "Monitoring & Observability"
        PR[Prometheus<br/>:9090]
        GR[Grafana<br/>:3000]
        JG[Jaeger<br/>:14268]
        LG[Logs<br/>/var/log/vpn/]
    end

    subgraph "Management Layer"
        CLI[VPN CLI<br/>Management Tool]
        DC[Docker Compose<br/>Orchestration]
    end

    %% Client connections
    C1 -.->|VPN Traffic| VS
    C2 -.->|HTTP/HTTPS| TP1
    C3 -.->|SOCKS5| TP2
    CLI -.->|Management| IS

    %% Service connections
    T --> VS
    TP1 --> PA
    TP2 --> PA
    PA --> IS
    IS --> PG
    IS --> RD
    VS --> FS

    %% Monitoring connections
    VS --> PR
    PA --> PR
    IS --> PR
    T --> PR
    PR --> GR
    VS --> JG
    PA --> JG
    IS --> JG
    VS --> LG
    PA --> LG
    IS --> LG

    %% Management connections
    CLI --> DC
    DC --> T
    DC --> VS
    DC --> PA
    DC --> IS

    style C1 fill:#e1f5fe
    style C2 fill:#e1f5fe
    style C3 fill:#e1f5fe
    style T fill:#f3e5f5
    style VS fill:#e8f5e8
    style PA fill:#e8f5e8
    style IS fill:#e8f5e8
    style PG fill:#fff3e0
    style RD fill:#fff3e0
    style PR fill:#fce4ec
    style GR fill:#fce4ec
    style CLI fill:#e3f2fd
```

## Service Communication Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant T as Traefik
    participant P as Proxy Service
    participant A as Auth Service
    participant I as Identity Service
    participant D as Database
    participant V as VPN Server

    Note over C,V: User Authentication Flow
    C->>T: Connect to proxy
    T->>P: Forward request
    P->>A: Authenticate user
    A->>I: Validate credentials
    I->>D: Query user data
    D-->>I: Return user info
    I-->>A: Auth result
    A-->>P: Auth success/failure
    
    alt Authentication Success
        P-->>T: Allow connection
        T-->>C: Connection established
        C->>V: VPN traffic (if VPN client)
    else Authentication Failure
        P-->>T: Deny connection
        T-->>C: 401/403 Error
    end

    Note over C,V: Monitoring & Metrics
    P->>I: Log connection metrics
    V->>I: Log traffic stats
    I->>D: Store metrics
```

## Container Architecture

```mermaid
graph TB
    subgraph "Docker Host"
        subgraph "vpn-network (Docker Network)"
            subgraph "Traefik Container"
                TR[Traefik Process<br/>:80, :443, :8080]
            end
            
            subgraph "VPN Server Container"
                XR[Xray-core Process<br/>:8443]
                XC[Config Files<br/>/etc/xray/]
            end
            
            subgraph "Proxy Auth Container"
                PA[Auth Service<br/>:9001]
                PC[Proxy Config<br/>/etc/proxy/]
            end
            
            subgraph "Identity Service Container"
                IS[Identity API<br/>:9002]
                IC[User Data<br/>/opt/vpn/users/]
            end
            
            subgraph "Database Containers"
                PG[PostgreSQL<br/>:5432]
                RD[Redis<br/>:6379]
            end
            
            subgraph "Monitoring Containers"
                PR[Prometheus<br/>:9090]
                GR[Grafana<br/>:3000]
                JG[Jaeger<br/>:14268]
            end
        end
        
        subgraph "Host Volumes"
            V1[/opt/vpn/config]
            V2[/opt/vpn/users]
            V3[/opt/vpn/logs]
            V4[/opt/vpn/data]
            V5[/opt/vpn/certs]
        end
    end

    %% Volume mounts
    XC -.->|Mount| V1
    IC -.->|Mount| V2
    PG -.->|Mount| V4
    TR -.->|Mount| V5

    %% Service communication
    TR --> XR
    TR --> PA
    PA --> IS
    IS --> PG
    IS --> RD
    
    %% Monitoring
    XR --> PR
    PA --> PR
    IS --> PR
    PR --> GR
    
    style TR fill:#f3e5f5
    style XR fill:#e8f5e8
    style PA fill:#e8f5e8
    style IS fill:#e8f5e8
    style PG fill:#fff3e0
    style RD fill:#fff3e0
    style PR fill:#fce4ec
    style GR fill:#fce4ec
```