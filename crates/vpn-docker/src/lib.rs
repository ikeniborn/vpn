//! # VPN Docker Management
//!
//! This crate provides comprehensive Docker container management capabilities
//! for VPN server infrastructure, including container lifecycle management,
//! health monitoring, logging, and performance optimizations.
//!
//! ## Features
//!
//! - **Container Management**: Full lifecycle management of Docker containers
//! - **Health Monitoring**: Real-time health checks and status monitoring
//! - **Log Streaming**: Efficient log collection and streaming
//! - **Volume Management**: Persistent storage and backup operations
//! - **Connection Pooling**: Optimized Docker API connections for performance
//! - **Intelligent Caching**: Multi-tier caching system for reduced API calls
//!
//! ## Quick Start
//!
//! ```rust,no_run
//! use vpn_docker::{ContainerManager, ContainerConfig};
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     // Create a container manager
//!     let manager = ContainerManager::new()?;
//!     
//!     // Create container configuration
//!     let mut config = ContainerConfig::new("vpn-server", "xray:latest");
//!     config.add_port_mapping(8443, 8443);
//!     config.add_environment_variable("LOG_LEVEL", "info");
//!     
//!     // Check container status (uses caching for performance)
//!     let status = manager.get_container_status("vpn-server").await?;
//!     println!("Container status: {:?}", status);
//!     
//!     Ok(())
//! }
//! ```
//!
//! ## Performance Features
//!
//! This crate includes several performance optimizations:
//!
//! - **Connection pooling** reduces Docker API overhead
//! - **Intelligent caching** minimizes redundant API calls
//! - **Async operations** for non-blocking I/O
//! - **Batch operations** for efficient bulk container management
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────┐    ┌──────────────┐    ┌─────────────┐
//! │  Application    │───▶│ Connection   │───▶│   Docker    │
//! │     Code        │    │    Pool      │    │     API     │
//! └─────────────────┘    └──────────────┘    └─────────────┘
//!          │                       │
//!          ▼                       ▼
//! ┌─────────────────┐    ┌──────────────┐
//! │     Cache       │    │   Health     │
//! │    System       │    │  Monitoring  │
//! └─────────────────┘    └──────────────┘
//! ```

pub mod cache;
pub mod container;
pub mod error;
pub mod health;
pub mod logs;
pub mod pool;
pub mod volumes;

#[cfg(test)]
pub mod proptest;

// Re-export main types for convenience
pub use cache::{
    get_container_cache, start_cache_cleanup_task, CacheConfig, CacheStats, ContainerCache,
};
pub use container::{
    ContainerConfig, ContainerManager, ContainerStats, ContainerStatus, DockerManager,
};
pub use error::{DockerError, Result};
pub use health::HealthChecker;
pub use logs::LogStreamer;
pub use pool::{get_docker_connection, get_pool_stats, DockerPool, PoolConfig, PoolStats};
pub use volumes::VolumeManager;
