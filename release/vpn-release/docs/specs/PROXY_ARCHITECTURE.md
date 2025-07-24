# Proxy Server Architecture Design

## Architecture Decision

After analyzing the requirements, we'll implement a **hybrid approach**:

1. **HTTP/HTTPS Proxy**: Use Traefik TCP proxy with custom middleware
2. **SOCKS5 Proxy**: Implement custom Rust service for full SOCKS5 support
3. **Management Layer**: Unified Rust management layer for both

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        VPN CLI                              │
│                   (vpn install --protocol proxy)            │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                    Proxy Manager (Rust)                     │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │   Config    │  │     Auth     │  │    Metrics      │  │
│  │  Generator  │  │   Manager    │  │   Collector     │  │
│  └─────────────┘  └──────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│    Traefik TCP Proxy     │    │   SOCKS5 Proxy (Rust)    │
│   (HTTP/HTTPS/TCP)       │    │    (SOCKS5/UDP)          │
│                          │    │                          │
│  - HTTP CONNECT          │    │  - SOCKS5 Auth          │
│  - HTTPS Tunneling       │    │  - UDP Associate        │
│  - Load Balancing        │    │  - BIND Support         │
│  - TLS Termination       │    │  - Fast Path            │
└──────────────────────────┘    └──────────────────────────┘
                │                               │
                └───────────────┬───────────────┘
                                ▼
                    ┌─────────────────────┐
                    │    PostgreSQL       │
                    │  - User Auth        │
                    │  - Access Logs      │
                    │  - Usage Stats      │
                    └─────────────────────┘
```

## Module Structure

```
crates/
├── vpn-proxy/              # Main proxy crate
│   ├── src/
│   │   ├── lib.rs         # Public API
│   │   ├── manager.rs     # Proxy manager
│   │   ├── config.rs      # Configuration
│   │   ├── http/          # HTTP/HTTPS proxy
│   │   │   ├── mod.rs
│   │   │   ├── connect.rs # CONNECT method
│   │   │   └── handler.rs # Request handler
│   │   ├── socks5/        # SOCKS5 implementation
│   │   │   ├── mod.rs
│   │   │   ├── auth.rs    # Authentication
│   │   │   ├── protocol.rs # Protocol handling
│   │   │   └── server.rs  # SOCKS5 server
│   │   ├── auth/          # Authentication
│   │   │   ├── mod.rs
│   │   │   ├── basic.rs   # Basic auth
│   │   │   └── token.rs   # Token auth
│   │   ├── metrics.rs     # Prometheus metrics
│   │   └── error.rs       # Error types
│   └── Cargo.toml
```

## Implementation Details

### 1. HTTP/HTTPS Proxy (Traefik)

```yaml
# Traefik configuration for HTTP proxy
tcp:
  routers:
    http-proxy:
      entryPoints:
        - http-proxy
      rule: "HostSNI(`*`)"
      service: http-proxy-service
      middlewares:
        - proxy-auth

  services:
    http-proxy-service:
      loadBalancer:
        servers:
          - address: "backend:80"

  middlewares:
    proxy-auth:
      plugin:
        vpn-proxy-auth:
          endpoint: "http://proxy-manager:8000/auth"
```

### 2. SOCKS5 Proxy (Rust)

```rust
// Core SOCKS5 server structure
pub struct Socks5Server {
    config: Socks5Config,
    auth_manager: Arc<AuthManager>,
    metrics: Arc<ProxyMetrics>,
    connection_pool: Arc<ConnectionPool>,
}

impl Socks5Server {
    pub async fn start(&self) -> Result<()> {
        let listener = TcpListener::bind(&self.config.bind_address).await?;
        
        loop {
            let (socket, addr) = listener.accept().await?;
            let server = self.clone();
            
            tokio::spawn(async move {
                if let Err(e) = server.handle_connection(socket, addr).await {
                    error!("Connection error: {}", e);
                }
            });
        }
    }
    
    async fn handle_connection(&self, socket: TcpStream, addr: SocketAddr) -> Result<()> {
        // SOCKS5 handshake
        let mut conn = Socks5Connection::new(socket);
        
        // Authentication
        if !self.authenticate(&mut conn).await? {
            return Ok(());
        }
        
        // Handle request
        match conn.read_request().await? {
            Socks5Command::Connect(target) => {
                self.handle_connect(conn, target).await?
            }
            Socks5Command::Bind(target) => {
                self.handle_bind(conn, target).await?
            }
            Socks5Command::UdpAssociate => {
                self.handle_udp_associate(conn).await?
            }
        }
        
        Ok(())
    }
}
```

### 3. Unified Management Interface

```rust
// Proxy manager for both HTTP and SOCKS5
pub struct ProxyManager {
    http_config: HttpProxyConfig,
    socks_config: Socks5Config,
    auth_backend: Arc<dyn AuthBackend>,
    metrics: Arc<ProxyMetrics>,
}

impl ProxyManager {
    pub async fn install(&self, protocol: ProxyProtocol) -> Result<()> {
        match protocol {
            ProxyProtocol::Http => self.install_http_proxy().await,
            ProxyProtocol::Socks5 => self.install_socks5_proxy().await,
            ProxyProtocol::Both => {
                self.install_http_proxy().await?;
                self.install_socks5_proxy().await
            }
        }
    }
    
    pub async fn create_user(&self, username: &str) -> Result<ProxyUser> {
        let user = ProxyUser {
            username: username.to_string(),
            password: generate_secure_password(),
            token: generate_token(),
            bandwidth_limit: self.default_bandwidth_limit(),
            connection_limit: self.default_connection_limit(),
            created_at: Utc::now(),
        };
        
        self.auth_backend.create_user(&user).await?;
        Ok(user)
    }
}
```

## Performance Optimizations

### 1. Connection Pooling
```rust
pub struct ConnectionPool {
    pools: DashMap<SocketAddr, Pool<TcpStream>>,
    config: PoolConfig,
}

impl ConnectionPool {
    pub async fn get_or_create(&self, addr: SocketAddr) -> Result<PooledConnection> {
        if let Some(pool) = self.pools.get(&addr) {
            if let Some(conn) = pool.try_get() {
                return Ok(conn);
            }
        }
        
        // Create new connection
        let stream = TcpStream::connect(addr).await?;
        stream.set_nodelay(true)?;
        
        Ok(PooledConnection::new(stream, addr))
    }
}
```

### 2. Zero-Copy Transfer
```rust
pub async fn proxy_data(
    client: &mut TcpStream,
    server: &mut TcpStream,
) -> Result<(u64, u64)> {
    let (client_read, client_write) = client.split();
    let (server_read, server_write) = server.split();
    
    let client_to_server = tokio::io::copy(client_read, server_write);
    let server_to_client = tokio::io::copy(server_read, client_write);
    
    let (uploaded, downloaded) = tokio::try_join!(
        client_to_server,
        server_to_client
    )?;
    
    Ok((uploaded, downloaded))
}
```

### 3. Authentication Cache
```rust
pub struct AuthCache {
    cache: Arc<DashMap<String, CachedAuth>>,
    ttl: Duration,
}

impl AuthCache {
    pub async fn authenticate(&self, credentials: &Credentials) -> Result<bool> {
        let key = credentials.cache_key();
        
        // Check cache
        if let Some(cached) = self.cache.get(&key) {
            if cached.is_valid() {
                return Ok(cached.authenticated);
            }
        }
        
        // Authenticate and cache
        let authenticated = self.backend.authenticate(credentials).await?;
        self.cache.insert(key, CachedAuth {
            authenticated,
            expires_at: Instant::now() + self.ttl,
        });
        
        Ok(authenticated)
    }
}
```

## Security Implementation

### 1. Rate Limiting
```rust
pub struct RateLimiter {
    limits: DashMap<String, UserLimits>,
}

impl RateLimiter {
    pub async fn check_rate_limit(&self, user: &str) -> Result<()> {
        let mut limits = self.limits.entry(user.to_string())
            .or_insert_with(UserLimits::default);
        
        if !limits.check_and_update() {
            return Err(ProxyError::RateLimitExceeded);
        }
        
        Ok(())
    }
}
```

### 2. Access Control
```rust
pub struct AccessController {
    rules: RwLock<AccessRules>,
}

impl AccessController {
    pub async fn check_access(&self, user: &str, target: &SocketAddr) -> Result<()> {
        let rules = self.rules.read().await;
        
        // Check IP whitelist/blacklist
        if rules.is_blacklisted(&target.ip()) {
            return Err(ProxyError::AccessDenied("IP blacklisted"));
        }
        
        // Check user permissions
        if !rules.user_can_access(user, target) {
            return Err(ProxyError::AccessDenied("User not authorized"));
        }
        
        Ok(())
    }
}
```

## Monitoring Integration

```rust
pub struct ProxyMetrics {
    connections_total: IntCounter,
    bytes_transferred: IntCounter,
    active_connections: IntGauge,
    auth_failures: IntCounter,
    request_duration: Histogram,
}

impl ProxyMetrics {
    pub fn record_connection(&self, protocol: &str) {
        self.connections_total
            .with_label_values(&[protocol])
            .inc();
    }
    
    pub fn record_transfer(&self, bytes: u64, direction: &str) {
        self.bytes_transferred
            .with_label_values(&[direction])
            .inc_by(bytes);
    }
}
```

## CLI Integration

```rust
// Add to existing CLI commands
#[derive(Subcommand)]
pub enum ProxyCommands {
    /// Install proxy server
    Install {
        /// Proxy protocol
        #[arg(long, value_enum)]
        protocol: ProxyProtocol,
        
        /// Listen port
        #[arg(long, default_value = "8080")]
        port: u16,
    },
    
    /// Manage proxy users
    Users {
        #[command(subcommand)]
        command: ProxyUserCommands,
    },
    
    /// Show proxy statistics
    Stats {
        /// Output format
        #[arg(long, value_enum, default_value = "table")]
        format: OutputFormat,
    },
}
```

## Docker Deployment

```dockerfile
# Dockerfile for proxy server
FROM rust:1.75-alpine AS builder
WORKDIR /app
COPY . .
RUN cargo build --release --bin vpn-proxy

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/target/release/vpn-proxy /usr/local/bin/
EXPOSE 8080 1080
ENTRYPOINT ["vpn-proxy"]
```

## Testing Strategy

### 1. Unit Tests
- Protocol compliance tests
- Authentication tests
- Rate limiting tests
- Connection pooling tests

### 2. Integration Tests
- End-to-end proxy tests
- Performance benchmarks
- Stress testing
- Security testing

### 3. Load Testing
```bash
# HTTP proxy load test
hey -n 10000 -c 100 -x http://proxy:8080 https://example.com

# SOCKS5 proxy test
curl --socks5 proxy:1080 https://example.com
```