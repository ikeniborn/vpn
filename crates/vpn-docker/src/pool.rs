//! Docker connection pooling for improved performance
//!
//! This module provides connection pooling for Docker API calls to reduce
//! connection overhead and improve performance for frequent operations.

use bollard::Docker;
use std::sync::Arc;
use tokio::sync::{Mutex, Semaphore};
use std::time::{Duration, Instant};
use crate::error::{DockerError, Result};

/// Configuration for the Docker connection pool
#[derive(Debug, Clone)]
pub struct PoolConfig {
    /// Maximum number of concurrent connections
    pub max_connections: usize,
    /// Connection timeout
    pub connection_timeout: Duration,
    /// Maximum idle time before closing connection
    pub max_idle_time: Duration,
    /// Health check interval
    pub health_check_interval: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: 10,
            connection_timeout: Duration::from_secs(30),
            max_idle_time: Duration::from_secs(300), // 5 minutes
            health_check_interval: Duration::from_secs(60), // 1 minute
        }
    }
}

/// A pooled Docker connection wrapper
#[derive(Debug)]
struct PooledConnection {
    docker: Docker,
    created_at: Instant,
    last_used: Mutex<Instant>,
}

impl PooledConnection {
    fn new(docker: Docker) -> Self {
        let now = Instant::now();
        Self {
            docker,
            created_at: now,
            last_used: Mutex::new(now),
        }
    }

    async fn mark_used(&self) {
        *self.last_used.lock().await = Instant::now();
    }

    async fn is_idle(&self, max_idle: Duration) -> bool {
        let last_used = *self.last_used.lock().await;
        Instant::now().duration_since(last_used) > max_idle
    }

    fn docker(&self) -> &Docker {
        &self.docker
    }
}

/// Docker connection pool for efficient resource management
pub struct DockerPool {
    connections: Arc<Mutex<Vec<Arc<PooledConnection>>>>,
    semaphore: Arc<Semaphore>,
    config: PoolConfig,
}

impl DockerPool {
    /// Create a new Docker connection pool
    pub fn new(config: PoolConfig) -> Self {
        Self {
            connections: Arc::new(Mutex::new(Vec::new())),
            semaphore: Arc::new(Semaphore::new(config.max_connections)),
            config,
        }
    }

    /// Get a connection from the pool
    pub async fn get_connection(&self) -> Result<PooledDocker> {
        // Acquire semaphore permit
        let permit = self.semaphore.clone().acquire_owned().await
            .map_err(|_| DockerError::ConnectionError("Failed to acquire connection permit".into()))?;

        // Try to get an existing connection
        let connection = {
            let mut connections = self.connections.lock().await;
            
            // Remove idle connections
            let now = Instant::now();
            connections.retain(|conn| {
                if let Ok(last_used_guard) = conn.last_used.try_lock() {
                    let last_used = *last_used_guard;
                    now.duration_since(last_used) <= self.config.max_idle_time
                } else {
                    // If we can't lock, assume it's being used
                    true
                }
            });

            // Get an available connection
            connections.pop()
        };

        let pooled_conn = match connection {
            Some(conn) => {
                conn.mark_used().await;
                conn
            }
            None => {
                // Create new connection
                let docker = Docker::connect_with_local_defaults()
                    .map_err(|e| DockerError::ConnectionError(format!("Failed to connect to Docker: {}", e)))?;
                
                Arc::new(PooledConnection::new(docker))
            }
        };

        Ok(PooledDocker {
            connection: pooled_conn,
            pool: self.connections.clone(),
            _permit: permit,
        })
    }

    /// Get pool statistics
    pub async fn stats(&self) -> PoolStats {
        let connections = self.connections.lock().await;
        PoolStats {
            total_connections: connections.len(),
            available_permits: self.semaphore.available_permits(),
            max_connections: self.config.max_connections,
        }
    }

    /// Perform health check on all connections
    pub async fn health_check(&self) -> Result<()> {
        let connections = self.connections.lock().await;
        
        for conn in connections.iter() {
            // Simple ping to check if connection is alive
            if let Err(_) = conn.docker().ping().await {
                // Connection is dead, it will be removed next time
                continue;
            }
        }
        
        Ok(())
    }
}

/// A Docker connection borrowed from the pool
pub struct PooledDocker {
    connection: Arc<PooledConnection>,
    pool: Arc<Mutex<Vec<Arc<PooledConnection>>>>,
    _permit: tokio::sync::OwnedSemaphorePermit,
}

impl PooledDocker {
    /// Get the underlying Docker client
    pub fn docker(&self) -> &Docker {
        self.connection.docker()
    }
}

impl Drop for PooledDocker {
    fn drop(&mut self) {
        // Return connection to pool
        let pool = self.pool.clone();
        let connection = self.connection.clone();
        
        tokio::spawn(async move {
            let mut connections = pool.lock().await;
            connections.push(connection);
        });
    }
}

/// Pool statistics
#[derive(Debug, Clone)]
pub struct PoolStats {
    pub total_connections: usize,
    pub available_permits: usize,
    pub max_connections: usize,
}

/// Global Docker pool instance
static DOCKER_POOL: once_cell::sync::Lazy<DockerPool> = once_cell::sync::Lazy::new(|| {
    DockerPool::new(PoolConfig::default())
});

/// Get a connection from the global Docker pool
pub async fn get_docker_connection() -> Result<PooledDocker> {
    DOCKER_POOL.get_connection().await
}

/// Get statistics for the global Docker pool
pub async fn get_pool_stats() -> PoolStats {
    DOCKER_POOL.stats().await
}

/// Perform health check on the global Docker pool
pub async fn health_check_pool() -> Result<()> {
    DOCKER_POOL.health_check().await
}