//! # DEPRECATED: vpn-containerd crate
//! 
//! **This crate is deprecated and no longer actively developed.**
//! 
//! As part of Phase 5 (Docker Compose Orchestration) outlined in TASK.md, 
//! we are migrating from containerd runtime abstraction to a Docker Compose 
//! based orchestration system.
//!
//! ## Migration Path
//! - Use Docker + Docker Compose for container orchestration
//! - Simplified deployment with `docker-compose up`
//! - Better tooling ecosystem and proven technology
//! - Reduced complexity and improved maintainability
//!
//! ## Replacement
//! See the new `vpn-compose` module for Docker Compose orchestration.
//!
//! This crate is kept for reference purposes only.

#[deprecated(since = "2025-07-01", note = "Use Docker Compose orchestration instead. See TASK.md Phase 5.")]
pub mod runtime;
pub mod containers;
pub mod tasks;
pub mod images;
// pub mod snapshots;  // Temporarily disabled due to missing APIs in containerd-client 0.8.0
pub mod events;
pub mod stats;
pub mod logs;
pub mod health;
pub mod batch;
pub mod error;
pub mod types;
pub mod factory;

pub use runtime::ContainerdRuntime;
pub use error::{ContainerdError, Result};
pub use types::*;
pub use events::{EventManager, ContainerdEvent, ContainerdEventType, EventFilter};
pub use health::{HealthMonitor, HealthStatus, HealthCheckConfig, HealthCheckResult, HealthMetrics, HealthCheckBuilder};
pub use stats::{StatsCollector, ContainerdStats, StatsConfig, StatsHistory, UsageTrends, TrendDirection};
pub use factory::ContainerdFactory;