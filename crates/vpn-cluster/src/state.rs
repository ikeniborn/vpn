//! Cluster state management

use crate::error::{ClusterError, Result};
use crate::node::{Node, NodeId, NodeRole, NodeStatus};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

/// Represents the complete state of the cluster
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterState {
    /// ID of this node
    pub node_id: NodeId,
    
    /// Name of the cluster
    pub cluster_name: String,
    
    /// All nodes in the cluster
    pub nodes: HashMap<NodeId, Node>,
    
    /// Current leader node ID
    pub leader_id: Option<NodeId>,
    
    /// Current term/epoch for consensus
    pub term: u64,
    
    /// Configuration version for cluster membership changes
    pub config_version: u64,
    
    /// Cluster configuration data
    pub config_data: HashMap<String, serde_json::Value>,
    
    /// When this state was last updated
    pub last_updated: u64,
    
    /// Cluster formation timestamp
    pub created_at: u64,
    
    /// Cluster metadata
    pub metadata: HashMap<String, String>,
}

impl ClusterState {
    /// Create a new cluster state
    pub fn new(node_id: NodeId) -> Self {
        let now = current_timestamp();
        
        Self {
            node_id,
            cluster_name: "vpn-cluster".to_string(), // Default, should be updated with actual cluster name
            nodes: HashMap::new(),
            leader_id: None,
            term: 0,
            config_version: 0,
            config_data: HashMap::new(),
            last_updated: now,
            created_at: now,
            metadata: HashMap::new(),
        }
    }
    
    /// Create a new cluster state with specific cluster name
    pub fn with_cluster_name(node_id: NodeId, cluster_name: String) -> Self {
        let now = current_timestamp();
        
        Self {
            node_id,
            cluster_name,
            nodes: HashMap::new(),
            leader_id: None,
            term: 0,
            config_version: 0,
            config_data: HashMap::new(),
            last_updated: now,
            created_at: now,
            metadata: HashMap::new(),
        }
    }

    /// Add a node to the cluster
    pub fn add_node(&mut self, node: Node) -> Result<()> {
        if self.nodes.contains_key(&node.id) {
            return Err(ClusterError::node_already_exists(node.id.to_string()));
        }

        tracing::info!("Adding node {} to cluster", node.summary());
        self.nodes.insert(node.id.clone(), node);
        self.update_timestamp();
        self.increment_config_version();
        
        Ok(())
    }

    /// Remove a node from the cluster
    pub fn remove_node(&mut self, node_id: &NodeId) -> Result<Node> {
        let node = self.nodes.remove(node_id)
            .ok_or_else(|| ClusterError::node_not_found(node_id.to_string()))?;

        // If removed node was leader, clear leader
        if self.leader_id.as_ref() == Some(node_id) {
            self.leader_id = None;
        }

        tracing::info!("Removed node {} from cluster", node.summary());
        self.update_timestamp();
        self.increment_config_version();
        
        Ok(node)
    }

    /// Update an existing node
    pub fn update_node(&mut self, node: Node) -> Result<()> {
        if !self.nodes.contains_key(&node.id) {
            return Err(ClusterError::node_not_found(node.id.to_string()));
        }

        self.nodes.insert(node.id.clone(), node);
        self.update_timestamp();
        
        Ok(())
    }

    /// Get a node by ID
    pub fn get_node(&self, node_id: &NodeId) -> Option<&Node> {
        self.nodes.get(node_id)
    }

    /// Get a mutable reference to a node by ID
    pub fn get_node_mut(&mut self, node_id: &NodeId) -> Option<&mut Node> {
        if self.nodes.contains_key(node_id) {
            self.update_timestamp();
        }
        self.nodes.get_mut(node_id)
    }

    /// Get all nodes
    pub fn get_all_nodes(&self) -> Vec<&Node> {
        self.nodes.values().collect()
    }

    /// Get nodes by status
    pub fn get_nodes_by_status(&self, status: NodeStatus) -> Vec<&Node> {
        self.nodes.values()
            .filter(|node| node.status == status)
            .collect()
    }

    /// Get nodes by role
    pub fn get_nodes_by_role(&self, role: NodeRole) -> Vec<&Node> {
        self.nodes.values()
            .filter(|node| node.role == role)
            .collect()
    }

    /// Get healthy nodes
    pub fn get_healthy_nodes(&self) -> Vec<&Node> {
        self.get_nodes_by_status(NodeStatus::Healthy)
    }

    /// Get voting nodes (can participate in consensus)
    pub fn get_voting_nodes(&self) -> Vec<&Node> {
        self.nodes.values()
            .filter(|node| node.can_vote())
            .collect()
    }

    /// Set the cluster leader
    pub fn set_leader(&mut self, leader_id: Option<NodeId>) -> Result<()> {
        if let Some(ref id) = leader_id {
            // Verify the leader node exists and can be a leader
            let node = self.get_node(id)
                .ok_or_else(|| ClusterError::node_not_found(id.to_string()))?;
            
            if !node.can_vote() {
                return Err(ClusterError::invalid_state(
                    format!("Node {} cannot be a leader in its current state", id)
                ));
            }
        }

        // Update previous leader to follower
        if let Some(old_leader_id) = self.leader_id.clone() {
            if let Some(old_leader) = self.get_node_mut(&old_leader_id) {
                if old_leader.role == NodeRole::Leader {
                    old_leader.set_role(NodeRole::Follower);
                }
            }
        }

        // Update new leader role
        if let Some(ref new_leader_id) = leader_id {
            if let Some(new_leader) = self.get_node_mut(new_leader_id) {
                new_leader.set_role(NodeRole::Leader);
            }
        }

        self.leader_id = leader_id;
        self.update_timestamp();
        
        if let Some(ref id) = self.leader_id {
            tracing::info!("Set cluster leader to {}", id);
        } else {
            tracing::warn!("Cluster has no leader");
        }
        
        Ok(())
    }

    /// Get the current leader
    pub fn get_leader(&self) -> Option<&Node> {
        self.leader_id.as_ref().and_then(|id| self.get_node(id))
    }

    /// Check if this node is the leader
    pub fn is_leader(&self, node_id: &NodeId) -> bool {
        self.leader_id.as_ref() == Some(node_id)
    }

    /// Increment the term (for leader election)
    pub fn increment_term(&mut self) {
        self.term += 1;
        self.update_timestamp();
        tracing::debug!("Incremented cluster term to {}", self.term);
    }

    /// Update the term
    pub fn set_term(&mut self, term: u64) {
        if term > self.term {
            self.term = term;
            self.update_timestamp();
            tracing::debug!("Updated cluster term to {}", self.term);
        }
    }

    /// Get cluster size
    pub fn size(&self) -> usize {
        self.nodes.len()
    }

    /// Get number of healthy nodes
    pub fn healthy_count(&self) -> usize {
        self.get_healthy_nodes().len()
    }

    /// Get number of voting nodes
    pub fn voting_count(&self) -> usize {
        self.get_voting_nodes().len()
    }

    /// Check if cluster has quorum
    pub fn has_quorum(&self) -> bool {
        let voting_nodes = self.voting_count();
        let healthy_voting = self.nodes.values()
            .filter(|node| node.can_vote() && node.is_healthy())
            .count();
        
        healthy_voting > voting_nodes / 2
    }

    /// Calculate quorum size
    pub fn quorum_size(&self) -> usize {
        (self.voting_count() / 2) + 1
    }

    /// Set configuration value
    pub fn set_config(&mut self, key: String, value: serde_json::Value) {
        self.config_data.insert(key, value);
        self.increment_config_version();
        self.update_timestamp();
    }

    /// Get configuration value
    pub fn get_config(&self, key: &str) -> Option<&serde_json::Value> {
        self.config_data.get(key)
    }

    /// Remove configuration value
    pub fn remove_config(&mut self, key: &str) -> Option<serde_json::Value> {
        let result = self.config_data.remove(key);
        if result.is_some() {
            self.increment_config_version();
            self.update_timestamp();
        }
        result
    }

    /// Mark nodes as failed if they haven't been seen recently
    pub fn detect_failed_nodes(&mut self, timeout: Duration) {
        let current_time = current_timestamp();
        let timeout_secs = timeout.as_secs();
        
        let mut failed_nodes = Vec::new();
        
        for (node_id, node) in &mut self.nodes {
            if node.status == NodeStatus::Healthy || node.status == NodeStatus::Suspected {
                if current_time.saturating_sub(node.last_seen) > timeout_secs {
                    if node.status == NodeStatus::Healthy {
                        node.set_status(NodeStatus::Suspected);
                        tracing::warn!("Node {} is suspected to have failed", node_id);
                    } else if current_time.saturating_sub(node.last_seen) > timeout_secs * 2 {
                        node.set_status(NodeStatus::Failed);
                        failed_nodes.push(node_id.clone());
                        tracing::error!("Node {} has failed", node_id);
                    }
                }
            }
        }

        // If leader failed, clear leadership
        if let Some(ref leader_id) = self.leader_id.clone() {
            if failed_nodes.contains(leader_id) {
                tracing::warn!("Leader {} has failed, clearing leadership", leader_id);
                self.leader_id = None;
            }
        }

        if !failed_nodes.is_empty() {
            self.update_timestamp();
        }
    }

    /// Update a node's last seen timestamp
    pub fn update_node_last_seen(&mut self, node_id: &NodeId) {
        if let Some(node) = self.get_node_mut(node_id) {
            node.update_last_seen();
            
            // If node was suspected/failed but is now responding, mark as healthy
            if matches!(node.status, NodeStatus::Suspected | NodeStatus::Failed) {
                node.set_status(NodeStatus::Healthy);
                tracing::info!("Node {} has recovered and is now healthy", node_id);
            }
        }
    }

    /// Get cluster health summary
    pub fn health_summary(&self) -> ClusterHealthSummary {
        let total_nodes = self.size();
        let healthy_nodes = self.healthy_count();
        let voting_nodes = self.voting_count();
        let has_leader = self.leader_id.is_some();
        let has_quorum = self.has_quorum();
        
        let status = if has_leader && has_quorum && healthy_nodes == total_nodes {
            ClusterHealthStatus::Healthy
        } else if has_quorum {
            ClusterHealthStatus::Degraded
        } else {
            ClusterHealthStatus::Unhealthy
        };

        ClusterHealthSummary {
            status,
            total_nodes,
            healthy_nodes,
            voting_nodes,
            has_leader,
            has_quorum,
            leader_id: self.leader_id.clone(),
            term: self.term,
        }
    }

    /// Add cluster metadata
    pub fn add_metadata(&mut self, key: String, value: String) {
        self.metadata.insert(key, value);
        self.update_timestamp();
    }

    /// Get cluster uptime in seconds
    pub fn uptime(&self) -> u64 {
        current_timestamp().saturating_sub(self.created_at)
    }

    /// Update the last updated timestamp
    fn update_timestamp(&mut self) {
        self.last_updated = current_timestamp();
    }

    /// Increment configuration version
    fn increment_config_version(&mut self) {
        self.config_version += 1;
    }
}

/// Cluster health summary
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterHealthSummary {
    pub status: ClusterHealthStatus,
    pub total_nodes: usize,
    pub healthy_nodes: usize,
    pub voting_nodes: usize,
    pub has_leader: bool,
    pub has_quorum: bool,
    pub leader_id: Option<NodeId>,
    pub term: u64,
}

/// Overall cluster health status
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClusterHealthStatus {
    /// All nodes healthy, has leader and quorum
    Healthy,
    
    /// Has quorum but some issues (failed nodes, no leader, etc.)
    Degraded,
    
    /// No quorum, cannot make progress
    Unhealthy,
}

/// Trait for distributed state storage and synchronization
#[async_trait::async_trait]
pub trait DistributedState: Send + Sync {
    /// Get the current cluster state
    async fn get_state(&self) -> Result<ClusterState>;
    
    /// Update the cluster state
    async fn update_state(&self, state: ClusterState) -> Result<()>;
    
    /// Subscribe to state changes
    async fn subscribe_to_changes(&self) -> Result<tokio::sync::mpsc::Receiver<ClusterState>>;
    
    /// Apply a state change atomically
    async fn apply_change<F>(&self, change_fn: F) -> Result<ClusterState>
    where
        F: FnOnce(&mut ClusterState) -> Result<()> + Send;
}

/// In-memory implementation of DistributedState for testing
pub struct InMemoryDistributedState {
    state: Arc<RwLock<ClusterState>>,
    change_tx: tokio::sync::broadcast::Sender<ClusterState>,
}

impl InMemoryDistributedState {
    pub fn new(initial_state: ClusterState) -> Self {
        let (change_tx, _) = tokio::sync::broadcast::channel(100);
        
        Self {
            state: Arc::new(RwLock::new(initial_state)),
            change_tx,
        }
    }
}

#[async_trait::async_trait]
impl DistributedState for InMemoryDistributedState {
    async fn get_state(&self) -> Result<ClusterState> {
        Ok(self.state.read().await.clone())
    }
    
    async fn update_state(&self, state: ClusterState) -> Result<()> {
        *self.state.write().await = state.clone();
        let _ = self.change_tx.send(state);
        Ok(())
    }
    
    async fn subscribe_to_changes(&self) -> Result<tokio::sync::mpsc::Receiver<ClusterState>> {
        let mut broadcast_rx = self.change_tx.subscribe();
        let (tx, rx) = tokio::sync::mpsc::channel(100);
        
        tokio::spawn(async move {
            while let Ok(state) = broadcast_rx.recv().await {
                if tx.send(state).await.is_err() {
                    break;
                }
            }
        });
        
        Ok(rx)
    }
    
    async fn apply_change<F>(&self, change_fn: F) -> Result<ClusterState>
    where
        F: FnOnce(&mut ClusterState) -> Result<()> + Send,
    {
        let mut state = self.state.write().await;
        change_fn(&mut *state)?;
        let updated_state = state.clone();
        drop(state);
        
        let _ = self.change_tx.send(updated_state.clone());
        Ok(updated_state)
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
    use crate::node::Node;
    use std::net::SocketAddr;

    fn create_test_node(name: &str, address: &str) -> Node {
        let addr: SocketAddr = address.parse().unwrap();
        Node::new(name.to_string(), addr)
    }

    #[test]
    fn test_cluster_state_creation() {
        let node_id = NodeId::new();
        let state = ClusterState::new(node_id.clone());
        
        assert_eq!(state.node_id, node_id);
        assert_eq!(state.cluster_name, "vpn-cluster");
        assert_eq!(state.nodes.len(), 0);
        assert!(state.leader_id.is_none());
        assert_eq!(state.term, 0);
    }

    #[test]
    fn test_add_remove_nodes() {
        let node_id = NodeId::new();
        let mut state = ClusterState::new(node_id);
        
        let node1 = create_test_node("node1", "127.0.0.1:8001");
        let node1_id = node1.id.clone();
        
        // Add node
        assert!(state.add_node(node1).is_ok());
        assert_eq!(state.size(), 1);
        assert!(state.get_node(&node1_id).is_some());
        
        // Try to add same node again (should fail)
        let duplicate_node = Node::with_id(node1_id.clone(), "duplicate".to_string(), "127.0.0.1:8002".parse().unwrap());
        assert!(state.add_node(duplicate_node).is_err());
        
        // Remove node
        let removed = state.remove_node(&node1_id);
        assert!(removed.is_ok());
        assert_eq!(state.size(), 0);
        assert!(state.get_node(&node1_id).is_none());
        
        // Try to remove non-existent node
        assert!(state.remove_node(&node1_id).is_err());
    }

    #[test]
    fn test_leader_management() {
        let node_id = NodeId::new();
        let mut state = ClusterState::new(node_id);
        
        let mut node1 = create_test_node("node1", "127.0.0.1:8001");
        node1.set_status(NodeStatus::Healthy);
        let node1_id = node1.id.clone();
        
        state.add_node(node1).unwrap();
        
        // Set leader
        assert!(state.set_leader(Some(node1_id.clone())).is_ok());
        assert_eq!(state.leader_id, Some(node1_id.clone()));
        assert!(state.is_leader(&node1_id));
        
        // Check leader role was updated
        let leader_node = state.get_node(&node1_id).unwrap();
        assert_eq!(leader_node.role, NodeRole::Leader);
        
        // Clear leader
        assert!(state.set_leader(None).is_ok());
        assert!(state.leader_id.is_none());
        assert!(!state.is_leader(&node1_id));
    }

    #[test]
    fn test_quorum_calculation() {
        let node_id = NodeId::new();
        let mut state = ClusterState::new(node_id);
        
        // No nodes - no quorum
        assert!(!state.has_quorum());
        assert_eq!(state.quorum_size(), 1);
        
        // Add nodes
        for i in 1..=5 {
            let mut node = create_test_node(&format!("node{}", i), &format!("127.0.0.1:800{}", i));
            node.set_status(NodeStatus::Healthy);
            state.add_node(node).unwrap();
        }
        
        assert_eq!(state.voting_count(), 5);
        assert_eq!(state.quorum_size(), 3);
        assert!(state.has_quorum()); // All 5 nodes are healthy
    }

    #[test]
    fn test_node_failure_detection() {
        let node_id = NodeId::new();
        let mut state = ClusterState::new(node_id);
        
        let mut node1 = create_test_node("node1", "127.0.0.1:8001");
        node1.set_status(NodeStatus::Healthy);
        node1.last_seen = current_timestamp() - 100; // 100 seconds ago
        let node1_id = node1.id.clone();
        
        state.add_node(node1).unwrap();
        state.set_leader(Some(node1_id.clone())).unwrap();
        
        // Detect failures with 30 second timeout
        state.detect_failed_nodes(Duration::from_secs(30));
        
        // Node should be suspected
        let node = state.get_node(&node1_id).unwrap();
        assert_eq!(node.status, NodeStatus::Suspected);
        
        // Leader should still be set (only suspected)
        assert!(state.leader_id.is_some());
        
        // Detect failures again with same timeout (node has been suspected for >60s total)
        state.detect_failed_nodes(Duration::from_secs(30));
        
        // Node should now be failed
        let node = state.get_node(&node1_id).unwrap();
        assert_eq!(node.status, NodeStatus::Failed);
        
        // Leader should be cleared
        assert!(state.leader_id.is_none());
    }

    #[test]
    fn test_config_management() {
        let node_id = NodeId::new();
        let mut state = ClusterState::new(node_id);
        
        let initial_version = state.config_version;
        
        // Set config
        state.set_config("test_key".to_string(), serde_json::json!("test_value"));
        assert_eq!(state.get_config("test_key"), Some(&serde_json::json!("test_value")));
        assert!(state.config_version > initial_version);
        
        // Update config
        let version_after_set = state.config_version;
        state.set_config("test_key".to_string(), serde_json::json!("updated_value"));
        assert_eq!(state.get_config("test_key"), Some(&serde_json::json!("updated_value")));
        assert!(state.config_version > version_after_set);
        
        // Remove config
        let version_after_update = state.config_version;
        let removed = state.remove_config("test_key");
        assert_eq!(removed, Some(serde_json::json!("updated_value")));
        assert!(state.get_config("test_key").is_none());
        assert!(state.config_version > version_after_update);
    }

    #[test]
    fn test_health_summary() {
        let node_id = NodeId::new();
        let mut state = ClusterState::new(node_id);
        
        // Empty cluster - unhealthy
        let summary = state.health_summary();
        assert_eq!(summary.status, ClusterHealthStatus::Unhealthy);
        assert!(!summary.has_leader);
        assert!(!summary.has_quorum);
        
        // Add healthy nodes
        for i in 1..=3 {
            let mut node = create_test_node(&format!("node{}", i), &format!("127.0.0.1:800{}", i));
            node.set_status(NodeStatus::Healthy);
            state.add_node(node).unwrap();
        }
        
        // Has quorum but no leader - degraded
        let summary = state.health_summary();
        assert_eq!(summary.status, ClusterHealthStatus::Degraded);
        assert!(!summary.has_leader);
        assert!(summary.has_quorum);
        
        // Set leader - now healthy
        let first_node_id = state.nodes.keys().next().unwrap().clone();
        state.set_leader(Some(first_node_id)).unwrap();
        
        let summary = state.health_summary();
        assert_eq!(summary.status, ClusterHealthStatus::Healthy);
        assert!(summary.has_leader);
        assert!(summary.has_quorum);
        assert_eq!(summary.total_nodes, 3);
        assert_eq!(summary.healthy_nodes, 3);
    }

    #[tokio::test]
    async fn test_in_memory_distributed_state() {
        let node_id = NodeId::new();
        let initial_state = ClusterState::new(node_id);
        let distributed_state = InMemoryDistributedState::new(initial_state);
        
        // Get initial state
        let state = distributed_state.get_state().await.unwrap();
        assert_eq!(state.size(), 0);
        
        // Apply change to add a node
        let node = create_test_node("test", "127.0.0.1:8001");
        let node_id = node.id.clone();
        
        let updated_state = distributed_state.apply_change(|state| {
            state.add_node(node)?;
            Ok(())
        }).await.unwrap();
        
        assert_eq!(updated_state.size(), 1);
        assert!(updated_state.get_node(&node_id).is_some());
        
        // Verify state was persisted
        let current_state = distributed_state.get_state().await.unwrap();
        assert_eq!(current_state.size(), 1);
    }
}