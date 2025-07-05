//! Proxy server configuration

use serde::{Deserialize, Serialize};
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::time::Duration;

/// Proxy protocol type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProxyProtocol {
    /// HTTP/HTTPS proxy
    Http,
    /// SOCKS5 proxy
    Socks5,
    /// Both HTTP and SOCKS5
    Both,
}

/// Proxy server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyConfig {
    /// Protocol to use
    pub protocol: ProxyProtocol,

    /// HTTP proxy listen address
    pub http_bind: Option<String>,

    /// SOCKS5 proxy listen address
    pub socks5_bind: Option<String>,

    /// Default bind address if specific ones not set
    pub bind_host: IpAddr,

    /// HTTP proxy port
    pub http_port: u16,

    /// SOCKS5 proxy port
    pub socks5_port: u16,

    /// Authentication configuration
    pub auth: AuthConfig,

    /// Rate limiting configuration
    pub rate_limit: RateLimitConfig,

    /// Connection pool configuration
    pub pool: PoolConfig,

    /// TLS configuration
    pub tls: Option<TlsConfig>,

    /// Upstream proxy (for chaining)
    pub upstream: Option<UpstreamConfig>,

    /// Logging configuration
    pub log_level: String,

    /// Metrics configuration
    pub metrics: MetricsConfig,

    /// Timeout settings
    pub timeouts: TimeoutConfig,
}

/// Authentication configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthConfig {
    /// Enable authentication
    pub enabled: bool,

    /// Authentication backend
    pub backend: AuthBackend,

    /// Cache authenticated sessions
    pub cache_ttl: Duration,

    /// Allow anonymous access
    pub allow_anonymous: bool,

    /// IP whitelist (no auth required)
    pub ip_whitelist: Vec<IpAddr>,
}

/// Authentication backend type
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AuthBackend {
    /// Use VPN user database
    VpnUsers,
    /// Static file with users
    File { path: PathBuf },
    /// LDAP authentication
    Ldap { url: String },
    /// External HTTP API
    Http { url: String },
}

/// Rate limiting configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitConfig {
    /// Enable rate limiting
    pub enabled: bool,

    /// Requests per second per user
    pub requests_per_second: u32,

    /// Burst size
    pub burst_size: u32,

    /// Bandwidth limit per user (bytes/sec)
    pub bandwidth_limit: Option<u64>,

    /// Global rate limit
    pub global_limit: Option<u32>,
}

/// Connection pool configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolConfig {
    /// Maximum connections per upstream host
    pub max_connections_per_host: u32,

    /// Total maximum connections
    pub max_total_connections: u32,

    /// Connection idle timeout
    pub idle_timeout: Duration,

    /// Connection lifetime
    pub max_lifetime: Duration,
}

/// TLS configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TlsConfig {
    /// Certificate file path
    pub cert_path: PathBuf,

    /// Private key file path
    pub key_path: PathBuf,

    /// CA certificate for client verification
    pub ca_path: Option<PathBuf>,

    /// Require client certificates
    pub verify_client: bool,
}

/// Upstream proxy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpstreamConfig {
    /// Upstream proxy URL
    pub url: String,

    /// Upstream authentication
    pub auth: Option<UpstreamAuth>,
}

/// Upstream authentication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpstreamAuth {
    pub username: String,
    pub password: String,
}

/// Metrics configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    /// Enable metrics collection
    pub enabled: bool,

    /// Metrics listen address
    pub bind_address: String,

    /// Metrics path
    pub path: String,
}

/// Timeout configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeoutConfig {
    /// Connect timeout
    pub connect: Duration,

    /// Read timeout
    pub read: Duration,

    /// Write timeout
    pub write: Duration,

    /// Idle timeout
    pub idle: Duration,
}

impl Default for ProxyConfig {
    fn default() -> Self {
        Self {
            protocol: ProxyProtocol::Both,
            http_bind: None,
            socks5_bind: None,
            bind_host: "0.0.0.0".parse().unwrap(),
            http_port: 8080,
            socks5_port: 1080,
            auth: AuthConfig::default(),
            rate_limit: RateLimitConfig::default(),
            pool: PoolConfig::default(),
            tls: None,
            upstream: None,
            log_level: "info".to_string(),
            metrics: MetricsConfig::default(),
            timeouts: TimeoutConfig::default(),
        }
    }
}

impl ProxyConfig {
    /// Get HTTP bind address
    pub fn bind_address(&self) -> crate::Result<SocketAddr> {
        if let Some(addr) = &self.http_bind {
            addr.parse()
                .map_err(|e| crate::ProxyError::config(format!("Invalid HTTP bind address: {}", e)))
        } else {
            Ok(SocketAddr::new(self.bind_host, self.http_port))
        }
    }

    /// Get SOCKS5 bind address
    pub fn socks5_bind_address(&self) -> crate::Result<SocketAddr> {
        if let Some(addr) = &self.socks5_bind {
            addr.parse().map_err(|e| {
                crate::ProxyError::config(format!("Invalid SOCKS5 bind address: {}", e))
            })
        } else {
            Ok(SocketAddr::new(self.bind_host, self.socks5_port))
        }
    }

    /// Load configuration from file
    pub async fn load_from_file(path: &std::path::Path) -> crate::Result<Self> {
        let content = tokio::fs::read_to_string(path).await?;
        toml::from_str(&content)
            .map_err(|e| crate::ProxyError::config(format!("Failed to parse config: {}", e)))
    }

    /// Save configuration to file
    pub async fn save_to_file(&self, path: &std::path::Path) -> crate::Result<()> {
        let content = toml::to_string_pretty(self)
            .map_err(|e| crate::ProxyError::config(format!("Failed to serialize config: {}", e)))?;
        tokio::fs::write(path, content).await?;
        Ok(())
    }
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            backend: AuthBackend::VpnUsers,
            cache_ttl: Duration::from_secs(300),
            allow_anonymous: false,
            ip_whitelist: Vec::new(),
        }
    }
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            requests_per_second: 100,
            burst_size: 200,
            bandwidth_limit: Some(10 * 1024 * 1024), // 10 MB/s
            global_limit: Some(10000),
        }
    }
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections_per_host: 100,
            max_total_connections: 1000,
            idle_timeout: Duration::from_secs(300),
            max_lifetime: Duration::from_secs(3600),
        }
    }
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            bind_address: "127.0.0.1:9090".to_string(),
            path: "/metrics".to_string(),
        }
    }
}

impl Default for TimeoutConfig {
    fn default() -> Self {
        Self {
            connect: Duration::from_secs(10),
            read: Duration::from_secs(30),
            write: Duration::from_secs(30),
            idle: Duration::from_secs(300),
        }
    }
}
