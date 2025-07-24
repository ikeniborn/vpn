# Network Topology & Traffic Flow

## Network Topology Overview

```mermaid
graph TB
    subgraph "Internet"
        I[Internet Users]
    end

    subgraph "Edge/CDN Layer"
        CF[Cloudflare/CDN<br/>Optional]
    end

    subgraph "VPN Server Host"
        subgraph "Host Network (Docker Bridge)"
            subgraph "Public Interfaces"
                PI1[eth0:80<br/>HTTP]
                PI2[eth0:443<br/>HTTPS/TLS]
                PI3[eth0:8443<br/>VPN/Reality]
                PI4[eth0:1080<br/>SOCKS5]
                PI5[eth0:8888<br/>HTTP Proxy]
            end

            subgraph "Traefik (Reverse Proxy)"
                TR[Traefik Container<br/>traefik:latest]
                TR_HTTP[HTTP :80]
                TR_HTTPS[HTTPS :443]
                TR_DASH[Dashboard :8080]
            end

            subgraph "VPN Core Services"
                subgraph "vpn-network (Internal Docker Network)"
                    XR[Xray VPN Server<br/>:8443 Internal]
                    PA[Proxy Auth Service<br/>:9001 Internal]
                    IS[Identity Service<br/>:9002 Internal]
                end
            end

            subgraph "Data Services"
                subgraph "data-network (Docker Network)"
                    PG[PostgreSQL<br/>:5432 Internal]
                    RD[Redis<br/>:6379 Internal]
                end
            end

            subgraph "Monitoring Services"
                subgraph "monitoring-network (Docker Network)"
                    PR[Prometheus<br/>:9090 Internal]
                    GR[Grafana<br/>:3000 Internal]
                    JG[Jaeger<br/>:14268 Internal]
                end
            end
        end
    end

    subgraph "Client Networks"
        subgraph "VPN Clients"
            VC1[Mobile Client]
            VC2[Desktop Client]
            VC3[Router Client]
        end

        subgraph "Proxy Clients"
            PC1[Browser]
            PC2[Application]
            PC3[Script/Bot]
        end
    end

    %% Internet routing
    I -.->|Optional| CF
    CF --> PI1
    CF --> PI2
    I --> PI1
    I --> PI2
    I --> PI3
    I --> PI4
    I --> PI5

    %% Public interface routing
    PI1 --> TR_HTTP
    PI2 --> TR_HTTPS
    PI3 --> XR
    PI4 --> TR
    PI5 --> TR

    %% Traefik routing
    TR_HTTP --> PA
    TR_HTTPS --> PA
    TR_DASH --> IS

    %% Internal service communication
    PA --> IS
    IS --> PG
    IS --> RD
    XR --> IS

    %% Monitoring connections
    XR -.->|Metrics| PR
    PA -.->|Metrics| PR
    IS -.->|Metrics| PR
    TR -.->|Metrics| PR
    PR --> GR

    %% Client connections
    VC1 -.->|VPN Tunnel| XR
    VC2 -.->|VPN Tunnel| XR
    VC3 -.->|VPN Tunnel| XR
    PC1 -.->|HTTP/HTTPS| PA
    PC2 -.->|SOCKS5| PA
    PC3 -.->|HTTP Proxy| PA

    style I fill:#e1f5fe
    style CF fill:#f3e5f5
    style TR fill:#fff3e0
    style XR fill:#e8f5e8
    style PA fill:#e8f5e8
    style IS fill:#e8f5e8
    style PG fill:#fce4ec
    style RD fill:#fce4ec
    style PR fill:#f3e5f5
    style GR fill:#f3e5f5
    style VC1 fill:#e1f5fe
    style VC2 fill:#e1f5fe
    style VC3 fill:#e1f5fe
    style PC1 fill:#e1f5fe
    style PC2 fill:#e1f5fe
    style PC3 fill:#e1f5fe
```

## Traffic Flow Patterns

### VPN Traffic Flow (VLESS+Reality)

```mermaid
sequenceDiagram
    participant VC as VPN Client
    participant FW as Firewall/NAT
    participant XR as Xray Server
    participant TS as Target Service
    participant IS as Identity Service

    Note over VC,IS: VPN Connection Establishment
    VC->>FW: TLS Handshake (Port 8443)
    FW->>XR: Forward to Xray
    XR->>IS: Validate User Certificate
    IS-->>XR: User Valid
    XR-->>FW: TLS Connection Established
    FW-->>VC: VPN Tunnel Ready

    Note over VC,IS: Encrypted Traffic Tunneling
    VC->>XR: Encrypted HTTP Request
    XR->>TS: Decrypted Request (via Reality)
    TS-->>XR: Response
    XR-->>VC: Encrypted Response

    Note over VC,IS: Traffic Monitoring
    XR->>IS: Log Traffic Stats
    IS->>IS: Update User Metrics
```

### Proxy Traffic Flow (HTTP/SOCKS5)

```mermaid
sequenceDiagram
    participant PC as Proxy Client
    participant TR as Traefik
    participant PA as Proxy Auth
    participant IS as Identity Service
    participant TS as Target Service

    Note over PC,TS: HTTP Proxy Request
    PC->>TR: HTTP CONNECT example.com:443
    TR->>PA: Forward Proxy Request
    PA->>IS: Authenticate User
    IS-->>PA: Auth Success/Failure
    
    alt Authentication Success
        PA->>TS: Establish Connection
        TS-->>PA: Connection Established
        PA-->>TR: 200 Connection Established
        TR-->>PC: Tunnel Ready
        PC<->>TS: Direct Encrypted Traffic
    else Authentication Failure
        PA-->>TR: 407 Proxy Authentication Required
        TR-->>PC: Auth Error
    end

    Note over PC,TS: SOCKS5 Proxy Request
    PC->>TR: SOCKS5 CONNECT example.com:443
    TR->>PA: Forward SOCKS5 Request
    PA->>IS: Authenticate User
    IS-->>PA: Auth Result
    PA->>TS: Establish Connection
    TS-->>PA: Connection Established
    PA-->>PC: SOCKS5 Success
    PC<->>TS: Proxied Traffic via PA
```

## Network Security Architecture

```mermaid
graph TB
    subgraph "External Threats"
        DDoS[DDoS Attacks]
        BF[Brute Force]
        SCAN[Port Scanning]
        MALWARE[Malware C&C]
    end

    subgraph "Network Security Layers"
        subgraph "Edge Protection"
            CF_WAF[Cloudflare WAF]
            CF_DDoS[DDoS Protection]
            CF_BOT[Bot Management]
        end

        subgraph "Host Firewall"
            UFW[UFW/iptables Rules]
            FAIL2BAN[Fail2Ban]
            RATE[Rate Limiting]
        end

        subgraph "Application Security"
            TLS[TLS 1.3 Encryption]
            AUTH[Strong Authentication]
            RBAC[Role-Based Access]
            INPUT_VAL[Input Validation]
        end

        subgraph "Container Security"
            NET_POL[Network Policies]
            SECRETS[Secret Management]
            NON_ROOT[Non-Root Containers]
            READ_ONLY[Read-Only Filesystems]
        end

        subgraph "Monitoring & Detection"
            IDS[Intrusion Detection]
            LOG_MON[Log Monitoring]
            ANOMALY[Anomaly Detection]
            ALERTS[Real-time Alerts]
        end
    end

    subgraph "Protected Services"
        VPN_SRV[VPN Services]
        PROXY_SRV[Proxy Services]
        MGMT[Management APIs]
        DATA[User Data]
    end

    %% Threat flow
    DDoS --> CF_DDoS
    BF --> FAIL2BAN
    SCAN --> UFW
    MALWARE --> CF_BOT

    %% Protection layers
    CF_WAF --> UFW
    CF_DDoS --> UFW
    CF_BOT --> UFW
    
    UFW --> TLS
    FAIL2BAN --> AUTH
    RATE --> RBAC
    
    TLS --> NET_POL
    AUTH --> SECRETS
    RBAC --> NON_ROOT
    INPUT_VAL --> READ_ONLY
    
    NET_POL --> IDS
    SECRETS --> LOG_MON
    NON_ROOT --> ANOMALY
    READ_ONLY --> ALERTS
    
    %% Final protection
    IDS --> VPN_SRV
    LOG_MON --> PROXY_SRV
    ANOMALY --> MGMT
    ALERTS --> DATA

    style DDoS fill:#ffebee
    style BF fill:#ffebee
    style SCAN fill:#ffebee
    style MALWARE fill:#ffebee
    style CF_WAF fill:#e8f5e8
    style CF_DDoS fill:#e8f5e8
    style CF_BOT fill:#e8f5e8
    style UFW fill:#fff3e0
    style FAIL2BAN fill:#fff3e0
    style RATE fill:#fff3e0
    style TLS fill:#f3e5f5
    style AUTH fill:#f3e5f5
    style RBAC fill:#f3e5f5
    style VPN_SRV fill:#e3f2fd
    style PROXY_SRV fill:#e3f2fd
    style MGMT fill:#e3f2fd
    style DATA fill:#e3f2fd
```

## Port Configuration & Firewall Rules

```mermaid
graph TB
    subgraph "External Ports (Public)"
        P80[Port 80<br/>HTTP Redirect]
        P443[Port 443<br/>HTTPS/TLS]
        P8443[Port 8443<br/>VPN/Reality]
        P1080[Port 1080<br/>SOCKS5 Proxy]
        P8888[Port 8888<br/>HTTP Proxy]
        P8080[Port 8080<br/>Traefik Dashboard]
    end

    subgraph "Internal Ports (Docker Networks)"
        PI9001[Port 9001<br/>Proxy Auth Service]
        PI9002[Port 9002<br/>Identity Service]
        PI5432[Port 5432<br/>PostgreSQL]
        PI6379[Port 6379<br/>Redis]
        PI9090[Port 9090<br/>Prometheus]
        PI3000[Port 3000<br/>Grafana]
        PI14268[Port 14268<br/>Jaeger]
    end

    subgraph "Firewall Rules"
        FR1[Allow 80,443 from anywhere]
        FR2[Allow 8443 from anywhere]
        FR3[Allow 1080,8888 from anywhere]
        FR4[Allow 8080 from admin IPs only]
        FR5[Deny all other external ports]
        FR6[Allow inter-container communication]
        FR7[Rate limit per IP: 100 req/min]
        FR8[Block known malicious IPs]
    end

    %% Port associations
    P80 --> FR1
    P443 --> FR1
    P8443 --> FR2
    P1080 --> FR3
    P8888 --> FR3
    P8080 --> FR4

    PI9001 --> FR6
    PI9002 --> FR6
    PI5432 --> FR6
    PI6379 --> FR6
    PI9090 --> FR6
    PI3000 --> FR6
    PI14268 --> FR6

    %% Security rules
    FR5 -.-> PI9001
    FR5 -.-> PI9002
    FR5 -.-> PI5432
    FR5 -.-> PI6379

    FR7 --> P80
    FR7 --> P443
    FR7 --> P8443
    FR8 --> FR1
    FR8 --> FR2
    FR8 --> FR3

    style P80 fill:#e8f5e8
    style P443 fill:#e8f5e8
    style P8443 fill:#e8f5e8
    style P1080 fill:#e8f5e8
    style P8888 fill:#e8f5e8
    style P8080 fill:#fff3e0
    style PI9001 fill:#fce4ec
    style PI9002 fill:#fce4ec
    style PI5432 fill:#fce4ec
    style PI6379 fill:#fce4ec
    style PI9090 fill:#fce4ec
    style PI3000 fill:#fce4ec
    style PI14268 fill:#fce4ec
    style FR5 fill:#ffebee
    style FR7 fill:#f3e5f5
    style FR8 fill:#f3e5f5
```