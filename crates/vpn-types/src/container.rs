//! Container-related types shared across crates

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Container runtime backend
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContainerRuntime {
    Docker,
    Podman,
    Containerd,
}

/// Container state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContainerState {
    Created,
    Running,
    Paused,
    Stopped,
    Exited,
    Dead,
}

impl ContainerState {
    /// Check if container is in a running state
    pub fn is_running(&self) -> bool {
        matches!(self, ContainerState::Running)
    }

    /// Check if container is in a stopped state
    pub fn is_stopped(&self) -> bool {
        matches!(self, ContainerState::Stopped | ContainerState::Exited)
    }
}

/// Container health status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthStatus {
    Starting,
    Healthy,
    Unhealthy,
    None,
}

/// Container restart policy
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RestartPolicy {
    No,
    Always,
    OnFailure { max_retries: u32 },
    UnlessStopped,
}

impl Default for RestartPolicy {
    fn default() -> Self {
        RestartPolicy::UnlessStopped
    }
}

/// Container resource limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    /// Memory limit in bytes (0 = unlimited)
    pub memory: u64,
    /// CPU limit in cores (0.0 = unlimited)
    pub cpu: f64,
    /// Disk I/O limit in bytes per second (0 = unlimited)
    pub disk_io: u64,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self {
            memory: 0,
            cpu: 0.0,
            disk_io: 0,
        }
    }
}

/// Container port mapping
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PortMapping {
    pub host_port: u16,
    pub container_port: u16,
    pub protocol: crate::NetworkProtocol,
}

/// Container volume mount
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VolumeMount {
    pub source: String,
    pub target: String,
    pub read_only: bool,
}

/// Basic container information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerInfo {
    pub id: String,
    pub name: String,
    pub image: String,
    pub state: ContainerState,
    pub health: HealthStatus,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub labels: HashMap<String, String>,
}