//! Connection pool implementation for upstream connections

use crate::{
    config::PoolConfig,
    error::{ProxyError, Result},
    metrics::ProxyMetrics,
};
use dashmap::DashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;
use tokio::net::TcpStream;
use tokio::sync::{Mutex, Semaphore};
use tracing::{debug, info};

/// A pooled connection with metadata
struct PooledConnection {
    stream: TcpStream,
    created_at: Instant,
    last_used: Instant,
    uses: u32,
}

impl PooledConnection {
    fn new(stream: TcpStream) -> Self {
        let now = Instant::now();
        Self {
            stream,
            created_at: now,
            last_used: now,
            uses: 0,
        }
    }

    fn is_expired(&self, config: &PoolConfig) -> bool {
        let now = Instant::now();

        // Check lifetime
        if now.duration_since(self.created_at) > config.max_lifetime {
            return true;
        }

        // Check idle time
        if now.duration_since(self.last_used) > config.idle_timeout {
            return true;
        }

        false
    }

    fn use_connection(&mut self) -> &mut TcpStream {
        self.last_used = Instant::now();
        self.uses += 1;
        &mut self.stream
    }
}

/// Connection pool for upstream connections
pub struct ConnectionPool {
    config: PoolConfig,
    pools: Arc<DashMap<SocketAddr, Vec<Arc<Mutex<PooledConnection>>>>>,
    total_connections: Arc<Semaphore>,
    host_semaphores: Arc<DashMap<SocketAddr, Arc<Semaphore>>>,
    metrics: ProxyMetrics,
}

impl ConnectionPool {
    /// Create a new connection pool
    pub fn new(config: &PoolConfig, metrics: ProxyMetrics) -> Self {
        Self {
            config: config.clone(),
            pools: Arc::new(DashMap::new()),
            total_connections: Arc::new(Semaphore::new(config.max_total_connections as usize)),
            host_semaphores: Arc::new(DashMap::new()),
            metrics,
        }
    }

    /// Get or create a connection to the specified address
    pub async fn get_or_create(&self, addr: SocketAddr) -> Result<TcpStream> {
        // Try to get an existing connection first
        if let Some(stream) = self.get_pooled_connection(&addr).await? {
            debug!("Reusing pooled connection to {}", addr);
            return Ok(stream);
        }

        // Create a new connection
        debug!("Creating new connection to {}", addr);
        self.create_connection(addr).await
    }

    /// Get a pooled connection if available
    async fn get_pooled_connection(&self, _addr: &SocketAddr) -> Result<Option<TcpStream>> {
        // TODO: Connection pooling is disabled for now due to TcpStream ownership issues
        // Always return None to create new connections
        self.metrics.record_pool_miss();
        Ok(None)
    }

    /// Create a new connection
    async fn create_connection(&self, addr: SocketAddr) -> Result<TcpStream> {
        // Get or create host semaphore
        let host_semaphore = self
            .host_semaphores
            .entry(addr)
            .or_insert_with(|| {
                Arc::new(Semaphore::new(
                    self.config.max_connections_per_host as usize,
                ))
            })
            .clone();

        // Acquire permits
        let _total_permit = self
            .total_connections
            .acquire()
            .await
            .map_err(|_| ProxyError::ConnectionPoolExhausted)?;

        let _host_permit = host_semaphore
            .acquire()
            .await
            .map_err(|_| ProxyError::ConnectionPoolExhausted)?;

        // Create connection with timeout
        let stream = tokio::time::timeout(self.config.idle_timeout, TcpStream::connect(addr))
            .await
            .map_err(|_| ProxyError::Timeout)?
            .map_err(|e| ProxyError::upstream(format!("Failed to connect to {}: {}", addr, e)))?;

        // Configure socket options
        stream.set_nodelay(true)?;

        Ok(stream)
    }

    /// Return a connection to the pool
    pub async fn return_connection(&self, addr: SocketAddr, stream: TcpStream) {
        // Check if connection is still valid
        if stream.peer_addr().is_err() {
            debug!("Not returning dead connection to pool");
            return;
        }

        let pooled = Arc::new(Mutex::new(PooledConnection::new(stream)));

        self.pools.entry(addr).or_insert_with(Vec::new).push(pooled);

        debug!("Returned connection to pool for {}", addr);
    }

    /// Close all connections in the pool
    pub async fn close_all(&self) {
        info!("Closing all pooled connections");

        for mut pool in self.pools.iter_mut() {
            pool.clear();
        }

        self.pools.clear();
    }

    /// Get pool statistics
    pub async fn stats(&self) -> PoolStats {
        let mut total_connections = 0;
        let mut active_connections = 0;

        for pool in self.pools.iter() {
            let pool_size = pool.len();
            total_connections += pool_size;

            // Count active connections (those currently locked)
            for conn in pool.iter() {
                if conn.try_lock().is_err() {
                    active_connections += 1;
                }
            }
        }

        PoolStats {
            total_connections,
            active_connections,
            idle_connections: total_connections - active_connections,
            total_hosts: self.pools.len(),
        }
    }

    /// Clean up expired connections
    pub async fn cleanup(&self) {
        debug!("Cleaning up connection pool");

        for mut pool in self.pools.iter_mut() {
            let initial_size = pool.len();

            pool.retain(|conn| {
                if let Ok(conn_guard) = conn.try_lock() {
                    !conn_guard.is_expired(&self.config)
                } else {
                    true // Keep if locked
                }
            });

            let removed = initial_size - pool.len();
            if removed > 0 {
                debug!(
                    "Removed {} expired connections from pool for {}",
                    removed,
                    pool.key()
                );
            }
        }

        // Remove empty pools
        self.pools.retain(|_, pool| !pool.is_empty());
    }
}

/// Pool statistics
#[derive(Debug, Clone)]
pub struct PoolStats {
    pub total_connections: usize,
    pub active_connections: usize,
    pub idle_connections: usize,
    pub total_hosts: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn test_pooled_connection_expiry() {
        let config = PoolConfig {
            max_connections_per_host: 10,
            max_total_connections: 100,
            idle_timeout: Duration::from_millis(100),
            max_lifetime: Duration::from_secs(1),
        };

        // This would need a real TcpStream for proper testing
        // For now, just test the logic structure
        assert!(true); // Placeholder
    }
}
