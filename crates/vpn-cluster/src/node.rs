//! Cluster node management

use crate::error::{ClusterError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::net::SocketAddr;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Unique identifier for a cluster node
#[derive(Debug, Clone, Hash, PartialEq, Eq, Serialize, Deserialize)]
pub struct NodeId(Uuid);

impl NodeId {
    /// Create a new random node ID
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }

    /// Create a node ID from a UUID
    pub fn from_uuid(uuid: Uuid) -> Self {
        Self(uuid)
    }

    /// Create a node ID from a string
    pub fn from_string(s: &str) -> Result<Self> {
        let uuid = Uuid::parse_str(s)
            .map_err(|e| ClusterError::configuration(format!("Invalid node ID: {}", e)))?;
        Ok(Self(uuid))
    }

    /// Get the underlying UUID
    pub fn as_uuid(&self) -> &Uuid {
        &self.0
    }

    /// Convert to string representation
    pub fn to_string(&self) -> String {
        self.0.to_string()
    }
}

impl fmt::Display for NodeId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl Default for NodeId {
    fn default() -> Self {
        Self::new()
    }
}

/// Role of a node in the cluster
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum NodeRole {
    /// Leader node - coordinates cluster operations
    Leader,
    
    /// Follower node - executes commands from leader
    Follower,
    
    /// Candidate node - seeking to become leader
    Candidate,
    
    /// Observer node - read-only, doesn't participate in consensus
    Observer,
    
    /// Bootstrap node - helps new nodes join the cluster
    Bootstrap,
}

impl Default for NodeRole {
    fn default() -> Self {
        Self::Follower
    }
}

impl fmt::Display for NodeRole {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Leader => write!(f, "leader"),
            Self::Follower => write!(f, "follower"),
            Self::Candidate => write!(f, "candidate"),
            Self::Observer => write!(f, "observer"),
            Self::Bootstrap => write!(f, "bootstrap"),
        }
    }
}

/// Status of a node in the cluster
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum NodeStatus {
    /// Node is healthy and operational
    Healthy,
    
    /// Node is suspected to be failing
    Suspected,
    
    /// Node has failed and is not responding
    Failed,
    
    /// Node is starting up
    Starting,
    
    /// Node is shutting down gracefully
    Stopping,
    
    /// Node is temporarily unavailable
    Unavailable,
    
    /// Node status is unknown
    Unknown,
}

impl Default for NodeStatus {
    fn default() -> Self {
        Self::Starting
    }
}

impl fmt::Display for NodeStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Healthy => write!(f, "healthy"),
            Self::Suspected => write!(f, "suspected"),
            Self::Failed => write!(f, "failed"),
            Self::Starting => write!(f, "starting"),
            Self::Stopping => write!(f, "stopping"),
            Self::Unavailable => write!(f, "unavailable"),
            Self::Unknown => write!(f, "unknown"),
        }
    }
}

/// Represents a node in the cluster
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Node {
    /// Unique identifier for this node
    pub id: NodeId,
    
    /// Human-readable name for this node
    pub name: String,
    
    /// Network address where this node can be reached
    pub address: SocketAddr,
    
    /// Current role of this node
    pub role: NodeRole,
    
    /// Current status of this node
    pub status: NodeStatus,
    
    /// When this node joined the cluster
    pub joined_at: u64,
    
    /// Last time we heard from this node
    pub last_seen: u64,
    
    /// Node capabilities and metadata
    pub metadata: HashMap<String, String>,
    
    /// Node version information
    pub version: String,
    
    /// Region/datacenter where this node is located
    pub region: Option<String>,
    
    /// Available resources on this node
    pub resources: NodeResources,
    
    /// Health information
    pub health: NodeHealth,
}

impl Node {
    /// Create a new node
    pub fn new(name: String, address: SocketAddr) -> Self {
        let now = current_timestamp();
        
        Self {
            id: NodeId::new(),
            name,
            address,
            role: NodeRole::default(),
            status: NodeStatus::Starting,
            joined_at: now,
            last_seen: now,
            metadata: HashMap::new(),
            version: env!("CARGO_PKG_VERSION").to_string(),
            region: None,
            resources: NodeResources::default(),
            health: NodeHealth::default(),
        }
    }

    /// Create a node with specific ID
    pub fn with_id(id: NodeId, name: String, address: SocketAddr) -> Self {
        let mut node = Self::new(name, address);
        node.id = id;
        node
    }

    /// Update last seen timestamp
    pub fn update_last_seen(&mut self) {
        self.last_seen = current_timestamp();
    }

    /// Check if node is considered alive based on last seen time
    pub fn is_alive(&self, timeout: Duration) -> bool {
        let current_time = current_timestamp();
        let timeout_secs = timeout.as_secs();
        
        current_time.saturating_sub(self.last_seen) <= timeout_secs
    }

    /// Check if node can participate in consensus
    pub fn can_vote(&self) -> bool {
        matches!(self.role, NodeRole::Leader | NodeRole::Follower | NodeRole::Candidate)
            && matches!(self.status, NodeStatus::Healthy | NodeStatus::Starting)
    }

    /// Get node uptime in seconds
    pub fn uptime(&self) -> u64 {
        current_timestamp().saturating_sub(self.joined_at)
    }

    /// Add metadata
    pub fn add_metadata(&mut self, key: String, value: String) {
        self.metadata.insert(key, value);
    }

    /// Get metadata value
    pub fn get_metadata(&self, key: &str) -> Option<&String> {
        self.metadata.get(key)
    }

    /// Set node region
    pub fn set_region(&mut self, region: String) {
        self.region = Some(region);
    }

    /// Update node role
    pub fn set_role(&mut self, role: NodeRole) {
        tracing::info!("Node {} changing role from {} to {}", self.id, self.role, role);
        self.role = role;
    }

    /// Update node status
    pub fn set_status(&mut self, status: NodeStatus) {
        if self.status != status {
            tracing::info!("Node {} changing status from {} to {}", self.id, self.status, status);
            self.status = status;
        }
    }

    /// Check if node is a leader
    pub fn is_leader(&self) -> bool {
        self.role == NodeRole::Leader
    }

    /// Check if node is healthy
    pub fn is_healthy(&self) -> bool {
        self.status == NodeStatus::Healthy
    }

    /// Get a summary of this node for logging
    pub fn summary(&self) -> String {
        format!(
            "Node[id={}, name={}, role={}, status={}, address={}]",
            self.id, self.name, self.role, self.status, self.address
        )
    }
}

impl PartialEq for Node {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}

impl Eq for Node {}

/// Node resource information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeResources {
    /// CPU cores available
    pub cpu_cores: u32,
    
    /// Memory in MB
    pub memory_mb: u64,
    
    /// Disk space in MB
    pub disk_mb: u64,
    
    /// Current CPU usage percentage
    pub cpu_usage: f64,
    
    /// Current memory usage percentage
    pub memory_usage: f64,
    
    /// Current disk usage percentage
    pub disk_usage: f64,
    
    /// Network bandwidth in Mbps
    pub network_bandwidth: u64,
}

impl Default for NodeResources {
    fn default() -> Self {
        Self {
            cpu_cores: num_cpus::get() as u32,
            memory_mb: 1024, // Default 1GB
            disk_mb: 10240,  // Default 10GB
            cpu_usage: 0.0,
            memory_usage: 0.0,
            disk_usage: 0.0,
            network_bandwidth: 1000, // Default 1Gbps
        }
    }
}

/// Node health information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeHealth {
    /// Overall health score (0-100)
    pub score: u8,
    
    /// Number of consecutive health check failures
    pub consecutive_failures: u32,
    
    /// Last health check timestamp
    pub last_check: u64,
    
    /// Health check details
    pub checks: HashMap<String, HealthCheck>,
}

impl Default for NodeHealth {
    fn default() -> Self {
        Self {
            score: 100,
            consecutive_failures: 0,
            last_check: current_timestamp(),
            checks: HashMap::new(),
        }
    }
}

/// Individual health check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheck {
    /// Name of the health check
    pub name: String,
    
    /// Whether the check passed
    pub passed: bool,
    
    /// Check execution time in milliseconds
    pub duration_ms: u64,
    
    /// Error message if check failed
    pub error: Option<String>,
    
    /// When this check was performed
    pub timestamp: u64,
}

impl HealthCheck {
    pub fn new(name: String, passed: bool, duration_ms: u64) -> Self {
        Self {
            name,
            passed,
            duration_ms,
            error: None,
            timestamp: current_timestamp(),
        }
    }

    pub fn with_error(mut self, error: String) -> Self {
        self.error = Some(error);
        self
    }
}

/// Get current timestamp in seconds since UNIX epoch
fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn test_node_id_creation() {
        let id1 = NodeId::new();
        let id2 = NodeId::new();
        
        assert_ne!(id1, id2);
        assert!(!id1.to_string().is_empty());
    }

    #[test]
    fn test_node_id_from_string() {
        let uuid_str = "550e8400-e29b-41d4-a716-446655440000";
        let node_id = NodeId::from_string(uuid_str).unwrap();
        assert_eq!(node_id.to_string(), uuid_str);
    }

    #[test]
    fn test_node_creation() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let node = Node::new("test-node".to_string(), address);
        
        assert_eq!(node.name, "test-node");
        assert_eq!(node.address, address);
        assert_eq!(node.role, NodeRole::Follower);
        assert_eq!(node.status, NodeStatus::Starting);
        assert!(node.uptime() == 0 || node.uptime() == 1); // Allow for timing differences
    }

    #[test]
    fn test_node_alive_check() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let mut node = Node::new("test-node".to_string(), address);
        
        // Node should be alive initially
        assert!(node.is_alive(Duration::from_secs(10)));
        
        // Simulate old last_seen time
        node.last_seen = current_timestamp() - 20;
        assert!(!node.is_alive(Duration::from_secs(10)));
    }

    #[test]
    fn test_node_voting_capability() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let mut node = Node::new("test-node".to_string(), address);
        
        // Starting follower can vote
        assert!(node.can_vote());
        
        // Observer cannot vote
        node.role = NodeRole::Observer;
        assert!(!node.can_vote());
        
        // Failed node cannot vote
        node.role = NodeRole::Follower;
        node.status = NodeStatus::Failed;
        assert!(!node.can_vote());
        
        // Healthy leader can vote
        node.role = NodeRole::Leader;
        node.status = NodeStatus::Healthy;
        assert!(node.can_vote());
    }

    #[test]
    fn test_node_metadata() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let mut node = Node::new("test-node".to_string(), address);
        
        node.add_metadata("datacenter".to_string(), "us-west".to_string());
        node.add_metadata("instance_type".to_string(), "m5.large".to_string());
        
        assert_eq!(node.get_metadata("datacenter"), Some(&"us-west".to_string()));
        assert_eq!(node.get_metadata("instance_type"), Some(&"m5.large".to_string()));
        assert_eq!(node.get_metadata("nonexistent"), None);
    }

    #[test]
    fn test_node_role_changes() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let mut node = Node::new("test-node".to_string(), address);
        
        assert_eq!(node.role, NodeRole::Follower);
        assert!(!node.is_leader());
        
        node.set_role(NodeRole::Leader);
        assert_eq!(node.role, NodeRole::Leader);
        assert!(node.is_leader());
    }

    #[test]
    fn test_node_status_changes() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let mut node = Node::new("test-node".to_string(), address);
        
        assert_eq!(node.status, NodeStatus::Starting);
        assert!(!node.is_healthy());
        
        node.set_status(NodeStatus::Healthy);
        assert_eq!(node.status, NodeStatus::Healthy);
        assert!(node.is_healthy());
    }

    #[test]
    fn test_health_check() {
        let check = HealthCheck::new("ping".to_string(), true, 50);
        assert_eq!(check.name, "ping");
        assert!(check.passed);
        assert_eq!(check.duration_ms, 50);
        assert!(check.error.is_none());
        
        let failed_check = HealthCheck::new("connect".to_string(), false, 1000)
            .with_error("Connection refused".to_string());
        assert!(!failed_check.passed);
        assert!(failed_check.error.is_some());
    }

    #[test]
    fn test_node_serialization() {
        let address = "127.0.0.1:8080".parse().unwrap();
        let node = Node::new("test-node".to_string(), address);
        
        let serialized = serde_json::to_string(&node).unwrap();
        let deserialized: Node = serde_json::from_str(&serialized).unwrap();
        
        assert_eq!(node.id, deserialized.id);
        assert_eq!(node.name, deserialized.name);
        assert_eq!(node.address, deserialized.address);
    }
}