//! Proxy manager for handling authentication, rate limiting, and connection management

use crate::{
    auth::AuthManager,
    config::ProxyConfig,
    error::{ProxyError, Result},
    metrics::ProxyMetrics,
    pool::ConnectionPool,
    rate_limit::RateLimiter,
};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info};

/// Central manager for proxy operations
#[derive(Clone)]
pub struct ProxyManager {
    config: Arc<ProxyConfig>,
    auth_manager: Arc<AuthManager>,
    rate_limiter: Arc<RateLimiter>,
    connection_pool: Arc<ConnectionPool>,
    metrics: ProxyMetrics,
    shutdown_signal: Arc<RwLock<bool>>,
}

impl ProxyManager {
    /// Create a new proxy manager
    pub fn new(config: ProxyConfig, metrics: ProxyMetrics) -> Result<Self> {
        let auth_manager = Arc::new(AuthManager::new(&config.auth)?);
        let rate_limiter = Arc::new(RateLimiter::new(&config.rate_limit));
        let connection_pool = Arc::new(ConnectionPool::new(&config.pool, metrics.clone()));

        Ok(Self {
            config: Arc::new(config),
            auth_manager,
            rate_limiter,
            connection_pool,
            metrics,
            shutdown_signal: Arc::new(RwLock::new(false)),
        })
    }

    /// Authenticate a connection
    pub async fn authenticate(
        &self,
        credentials: Option<(String, String)>,
        peer_addr: SocketAddr,
    ) -> Result<String> {
        // Check IP whitelist first
        if self.config.auth.ip_whitelist.contains(&peer_addr.ip()) {
            debug!("IP {} is whitelisted", peer_addr.ip());
            return Ok(format!("ip-{}", peer_addr.ip()));
        }

        // Check if authentication is required
        if !self.config.auth.enabled {
            return Ok("anonymous".to_string());
        }

        // Authenticate with credentials
        if let Some((username, password)) = credentials {
            let user_id = self.auth_manager.authenticate(&username, &password).await?;
            self.metrics.record_auth_success();
            Ok(user_id)
        } else if self.config.auth.allow_anonymous {
            Ok("anonymous".to_string())
        } else {
            self.metrics.record_auth_failure();
            Err(ProxyError::auth_failed("No credentials provided"))
        }
    }

    /// Check rate limit for a user
    pub async fn check_rate_limit(&self, user_id: &str) -> Result<()> {
        if !self.config.rate_limit.enabled {
            return Ok(());
        }

        if self.rate_limiter.check_rate_limit(user_id).await? {
            Ok(())
        } else {
            self.metrics.record_rate_limit_exceeded();
            Err(ProxyError::RateLimitExceeded)
        }
    }

    /// Record bandwidth usage
    pub async fn record_bandwidth(&self, user_id: &str, bytes: u64) -> Result<()> {
        if let Some(limit) = self.config.rate_limit.bandwidth_limit {
            self.rate_limiter.record_bandwidth(user_id, bytes).await?;

            let current_rate = self.rate_limiter.get_bandwidth_rate(user_id).await?;
            if current_rate > limit {
                return Err(ProxyError::RateLimitExceeded);
            }
        }

        self.metrics.record_bytes_transferred(bytes, "upload");
        Ok(())
    }

    /// Get or create a connection to upstream
    pub async fn get_connection(&self, addr: SocketAddr) -> Result<tokio::net::TcpStream> {
        self.connection_pool.get_or_create(addr).await
    }

    /// Return a connection to the pool
    pub async fn return_connection(&self, addr: SocketAddr, conn: tokio::net::TcpStream) {
        self.connection_pool.return_connection(addr, conn).await;
    }

    /// Check if shutdown is requested
    pub async fn is_shutting_down(&self) -> bool {
        *self.shutdown_signal.read().await
    }

    /// Shutdown the manager
    pub async fn shutdown(&self) -> Result<()> {
        info!("Shutting down proxy manager");
        *self.shutdown_signal.write().await = true;

        // Close connection pool
        self.connection_pool.close_all().await;

        // Flush metrics
        self.metrics.flush();

        Ok(())
    }

    /// Get configuration
    pub fn config(&self) -> &ProxyConfig {
        &self.config
    }

    /// Get metrics
    pub fn metrics(&self) -> &ProxyMetrics {
        &self.metrics
    }
}
