use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use vpn_runtime::{Container, ContainerState, ContainerStatus, Image, Task, TaskStatus, Volume};

/// containerd container implementation
#[derive(Debug, Clone)]
pub struct ContainerdContainer {
    pub id: String,
    pub name: String,
    pub image: String,
    pub state: ContainerState,
    pub status: ContainerStatus,
    pub labels: HashMap<String, String>,
    pub created_at: DateTime<Utc>,
}

impl Container for ContainerdContainer {
    fn id(&self) -> &str {
        &self.id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn image(&self) -> &str {
        &self.image
    }

    fn state(&self) -> ContainerState {
        self.state.clone()
    }

    fn status(&self) -> &ContainerStatus {
        &self.status
    }

    fn labels(&self) -> &HashMap<String, String> {
        &self.labels
    }

    fn created_at(&self) -> DateTime<Utc> {
        self.created_at
    }
}

/// containerd task implementation
#[derive(Debug, Clone)]
pub struct ContainerdTask {
    pub id: String,
    pub container_id: String,
    pub pid: Option<u32>,
    pub status: TaskStatus,
    pub exit_code: Option<i32>,
}

impl Task for ContainerdTask {
    fn id(&self) -> &str {
        &self.id
    }

    fn container_id(&self) -> &str {
        &self.container_id
    }

    fn pid(&self) -> Option<u32> {
        self.pid
    }

    fn status(&self) -> TaskStatus {
        self.status.clone()
    }

    fn exit_code(&self) -> Option<i32> {
        self.exit_code
    }
}

/// containerd volume (snapshot) implementation
#[derive(Debug, Clone)]
pub struct ContainerdVolume {
    pub name: String,
    pub driver: String,
    pub mount_point: Option<String>,
    pub labels: HashMap<String, String>,
    pub created_at: DateTime<Utc>,
}

impl Volume for ContainerdVolume {
    fn name(&self) -> &str {
        &self.name
    }

    fn driver(&self) -> &str {
        &self.driver
    }

    fn mount_point(&self) -> Option<&str> {
        self.mount_point.as_deref()
    }

    fn labels(&self) -> &HashMap<String, String> {
        &self.labels
    }

    fn created_at(&self) -> DateTime<Utc> {
        self.created_at
    }
}

/// containerd image implementation
#[derive(Debug, Clone)]
pub struct ContainerdImage {
    pub id: String,
    pub tags: Vec<String>,
    pub size: u64,
    pub created_at: DateTime<Utc>,
    pub labels: HashMap<String, String>,
}

impl Image for ContainerdImage {
    fn id(&self) -> &str {
        &self.id
    }

    fn tags(&self) -> &[String] {
        &self.tags
    }

    fn size(&self) -> u64 {
        self.size
    }

    fn created_at(&self) -> DateTime<Utc> {
        self.created_at
    }

    fn labels(&self) -> &HashMap<String, String> {
        &self.labels
    }
}

/// containerd-specific container specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerdContainerSpec {
    pub id: String,
    pub image: String,
    pub command: Option<Vec<String>>,
    pub args: Option<Vec<String>>,
    pub env: Vec<String>,
    pub working_dir: Option<String>,
    pub user: Option<String>,
    pub labels: HashMap<String, String>,
    pub annotations: HashMap<String, String>,
    pub runtime: Option<String>,
    pub snapshotter: Option<String>,
}

/// containerd-specific task specification
#[derive(Debug, Clone)]
pub struct ContainerdTaskSpec {
    pub container_id: String,
    pub stdin: Option<String>,
    pub stdout: Option<String>,
    pub stderr: Option<String>,
    pub terminal: bool,
}

/// Process specification for exec operations
#[derive(Debug, Clone)]
pub struct ProcessSpec {
    pub args: Vec<String>,
    pub env: Vec<String>,
    pub cwd: Option<String>,
    pub user: Option<String>,
    pub terminal: bool,
}

/// Mount specification for snapshots
#[derive(Debug, Clone)]
pub struct MountSpec {
    pub mount_type: String,
    pub source: String,
    pub target: String,
    pub options: Vec<String>,
}

/// Snapshot information
#[derive(Debug, Clone)]
pub struct SnapshotInfo {
    pub key: String,
    pub parent: Option<String>,
    pub kind: SnapshotKind,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Snapshot kind
#[derive(Debug, Clone, PartialEq)]
pub enum SnapshotKind {
    View,
    Active,
    Committed,
}

/// Event information from containerd
#[derive(Debug, Clone)]
pub struct ContainerdEvent {
    pub timestamp: DateTime<Utc>,
    pub namespace: String,
    pub topic: String,
    pub event_type: String,
    pub event_data: serde_json::Value,
}

/// Statistics from cgroup
#[derive(Debug, Clone)]
pub struct CgroupStats {
    pub cpu_usage_nanos: u64,
    pub cpu_throttled_periods: u64,
    pub cpu_throttled_time: u64,
    pub memory_usage: u64,
    pub memory_max_usage: u64,
    pub memory_limit: u64,
    pub memory_cache: u64,
    pub memory_rss: u64,
    pub memory_swap: u64,
    pub pids_current: u64,
    pub pids_limit: u64,
}

/// Network statistics
#[derive(Debug, Clone)]
pub struct NetworkStats {
    pub interface: String,
    pub rx_bytes: u64,
    pub rx_packets: u64,
    pub rx_errors: u64,
    pub rx_dropped: u64,
    pub tx_bytes: u64,
    pub tx_packets: u64,
    pub tx_errors: u64,
    pub tx_dropped: u64,
}

/// Block device statistics
#[derive(Debug, Clone)]
pub struct BlockStats {
    pub device: String,
    pub read_bytes: u64,
    pub read_ops: u64,
    pub write_bytes: u64,
    pub write_ops: u64,
}

/// Complete container metrics
#[derive(Debug, Clone)]
pub struct ContainerMetrics {
    pub container_id: String,
    pub cgroup_stats: CgroupStats,
    pub network_stats: Vec<NetworkStats>,
    pub block_stats: Vec<BlockStats>,
    pub timestamp: DateTime<Utc>,
}