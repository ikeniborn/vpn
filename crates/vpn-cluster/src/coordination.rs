//! Cluster coordination and event management

use crate::config::ClusterConfig;
use crate::consensus::{ConsensusEngine, SimpleConsensus};
use crate::error::{ClusterError, Result};
use crate::node::{Node, NodeId, NodeRole, NodeStatus};
use crate::state::ClusterState;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{broadcast, RwLock};

/// Coordinates cluster operations and manages events
pub struct ClusterCoordinator {
    node_id: NodeId,
    config: ClusterConfig,
    state: Arc<RwLock<ClusterState>>,
    consensus: Arc<SimpleConsensus>,
    event_tx: broadcast::Sender<CoordinationEvent>,
    active_operations: Arc<RwLock<HashMap<String, OperationStatus>>>,
}

impl ClusterCoordinator {
    /// Create a new cluster coordinator
    pub async fn new(
        node_id: NodeId,
        config: ClusterConfig,
        state: Arc<RwLock<ClusterState>>,
        consensus: Arc<SimpleConsensus>,
    ) -> Result<Self> {
        let (event_tx, _) = broadcast::channel(1000);
        
        Ok(Self {
            node_id,
            config,
            state,
            consensus,
            event_tx,
            active_operations: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    /// Start the coordinator
    pub async fn start(&mut self) -> Result<()> {
        tracing::info!("Starting cluster coordinator for node {}", self.node_id);
        
        // Start background tasks
        self.start_heartbeat_task().await?;
        self.start_failure_detection_task().await?;
        self.start_maintenance_task().await?;
        
        // Broadcast startup event
        let event = CoordinationEvent::NodeStarted {
            node_id: self.node_id.clone(),
            timestamp: current_timestamp(),
        };
        let _ = self.event_tx.send(event);
        
        Ok(())
    }

    /// Join an existing cluster
    pub async fn join_cluster(&mut self, bootstrap_nodes: &[SocketAddr]) -> Result<()> {
        tracing::info!("Attempting to join cluster via bootstrap nodes: {:?}", bootstrap_nodes);
        
        if bootstrap_nodes.is_empty() {
            return Err(ClusterError::configuration("No bootstrap nodes provided"));
        }

        // Try to contact bootstrap nodes
        for &bootstrap_addr in bootstrap_nodes {
            match self.contact_bootstrap_node(bootstrap_addr).await {
                Ok(cluster_info) => {
                    tracing::info!("Successfully contacted bootstrap node at {}", bootstrap_addr);
                    return self.integrate_with_cluster(cluster_info).await;
                }
                Err(e) => {
                    tracing::warn!("Failed to contact bootstrap node {}: {}", bootstrap_addr, e);
                    continue;
                }
            }
        }

        Err(ClusterError::membership("Failed to contact any bootstrap nodes"))
    }

    /// Leave the cluster gracefully
    pub async fn leave_cluster(&mut self) -> Result<()> {
        tracing::info!("Node {} leaving cluster", self.node_id);

        // Update node status to stopping
        {
            let mut state = self.state.write().await;
            if let Some(node) = state.get_node_mut(&self.node_id) {
                node.set_status(NodeStatus::Stopping);
            }
        }

        // If we're the leader, transfer leadership
        if self.consensus.is_leader().await {
            if let Err(e) = self.transfer_leadership_before_leaving().await {
                tracing::warn!("Failed to transfer leadership before leaving: {}", e);
            }
        }

        // Remove ourselves from the cluster
        self.consensus.remove_node(self.node_id.clone()).await?;

        // Broadcast leave event
        let event = CoordinationEvent::NodeLeft {
            node_id: self.node_id.clone(),
            timestamp: current_timestamp(),
        };
        let _ = self.event_tx.send(event);

        Ok(())
    }

    /// Handle node failure
    pub async fn handle_node_failure(&mut self, failed_node: NodeId) -> Result<()> {
        tracing::warn!("Handling failure of node {}", failed_node);

        // Update node status in cluster state
        {
            let mut state = self.state.write().await;
            if let Some(node) = state.get_node_mut(&failed_node) {
                node.set_status(NodeStatus::Failed);
            }
        }

        // Remove failed node from consensus
        self.consensus.remove_node(failed_node.clone()).await?;

        // If failed node was leader, trigger leader election
        let current_leader = self.consensus.get_leader().await;
        if current_leader.as_ref() == Some(&failed_node) {
            tracing::info!("Failed node was leader, triggering election");
            self.trigger_leader_election().await?;
        }

        // Broadcast failure event
        let event = CoordinationEvent::NodeFailed {
            node_id: failed_node,
            timestamp: current_timestamp(),
        };
        let _ = self.event_tx.send(event);

        Ok(())
    }

    /// Scale cluster to target number of nodes
    pub async fn scale_cluster(&mut self, target_nodes: usize) -> Result<()> {
        let current_size = {
            let state = self.state.read().await;
            state.size()
        };

        if target_nodes == current_size {
            tracing::info!("Cluster already at target size of {} nodes", target_nodes);
            return Ok(());
        }

        if target_nodes > current_size {
            let scale_up_count = target_nodes - current_size;
            tracing::info!("Scaling up cluster by {} nodes", scale_up_count);
            self.scale_up(scale_up_count).await
        } else {
            let scale_down_count = current_size - target_nodes;
            tracing::info!("Scaling down cluster by {} nodes", scale_down_count);
            self.scale_down(scale_down_count).await
        }
    }

    /// Subscribe to coordination events
    pub fn subscribe_to_events(&self) -> broadcast::Receiver<CoordinationEvent> {
        self.event_tx.subscribe()
    }

    /// Get current operation status
    pub async fn get_operation_status(&self, operation_id: &str) -> Option<OperationStatus> {
        let operations = self.active_operations.read().await;
        operations.get(operation_id).cloned()
    }

    /// List all active operations
    pub async fn list_active_operations(&self) -> HashMap<String, OperationStatus> {
        let operations = self.active_operations.read().await;
        operations.clone()
    }

    /// Shutdown the coordinator
    pub async fn shutdown(&mut self) -> Result<()> {
        tracing::info!("Shutting down cluster coordinator");
        
        // Cancel all active operations
        {
            let mut operations = self.active_operations.write().await;
            for (_, status) in operations.iter_mut() {
                if matches!(status.state, OperationState::Running) {
                    status.state = OperationState::Cancelled;
                    status.completed_at = Some(current_timestamp());
                }
            }
        }

        // Broadcast shutdown event
        let event = CoordinationEvent::NodeStopping {
            node_id: self.node_id.clone(),
            timestamp: current_timestamp(),
        };
        let _ = self.event_tx.send(event);

        Ok(())
    }

    // Private helper methods

    async fn start_heartbeat_task(&self) -> Result<()> {
        let node_id = self.node_id.clone();
        let state = self.state.clone();
        let interval = self.config.heartbeat_interval;
        
        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(interval);
            
            loop {
                interval_timer.tick().await;
                
                // Update our last seen timestamp
                {
                    let mut cluster_state = state.write().await;
                    cluster_state.update_node_last_seen(&node_id);
                }
                
                // In a real implementation, this would send heartbeats to other nodes
                tracing::trace!("Heartbeat sent from node {}", node_id);
            }
        });
        
        Ok(())
    }

    async fn start_failure_detection_task(&self) -> Result<()> {
        let state = self.state.clone();
        let interval = self.config.heartbeat_interval * 3; // Check every 3 heartbeat intervals
        let timeout = self.config.heartbeat_interval * 5; // Consider failed after 5 intervals
        
        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(interval);
            
            loop {
                interval_timer.tick().await;
                
                {
                    let mut cluster_state = state.write().await;
                    cluster_state.detect_failed_nodes(timeout);
                }
            }
        });
        
        Ok(())
    }

    async fn start_maintenance_task(&self) -> Result<()> {
        let operations = self.active_operations.clone();
        
        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(Duration::from_secs(60)); // Run every minute
            
            loop {
                interval_timer.tick().await;
                
                // Clean up completed operations older than 1 hour
                let cutoff_time = current_timestamp().saturating_sub(3600);
                
                {
                    let mut ops = operations.write().await;
                    ops.retain(|_, status| {
                        if let Some(completed_at) = status.completed_at {
                            completed_at > cutoff_time
                        } else {
                            true // Keep running operations
                        }
                    });
                }
            }
        });
        
        Ok(())
    }

    async fn contact_bootstrap_node(&self, address: SocketAddr) -> Result<ClusterInfo> {
        // In a real implementation, this would make HTTP/gRPC calls to the bootstrap node
        // For now, simulate the response
        tokio::time::sleep(Duration::from_millis(100)).await;
        
        Ok(ClusterInfo {
            cluster_name: self.config.cluster_name.clone(),
            leader_id: None,
            node_count: 1,
            bootstrap_address: address,
        })
    }

    async fn integrate_with_cluster(&mut self, _cluster_info: ClusterInfo) -> Result<()> {
        // In a real implementation, this would:
        // 1. Sync cluster state from existing nodes
        // 2. Add ourselves to the cluster
        // 3. Start participating in consensus
        
        let our_node = Node::new(
            self.config.node_name.clone(),
            self.config.bind_address,
        );
        
        {
            let mut state = self.state.write().await;
            state.add_node(our_node)?;
        }

        self.consensus.add_node(self.node_id.clone(), self.config.bind_address.to_string()).await?;

        tracing::info!("Successfully integrated with cluster");
        Ok(())
    }

    async fn transfer_leadership_before_leaving(&self) -> Result<()> {
        let potential_leaders = {
            let state = self.state.read().await;
            state.get_voting_nodes()
                .into_iter()
                .filter(|node| node.id != self.node_id && node.is_healthy())
                .map(|node| node.id.clone())
                .collect::<Vec<_>>()
        };

        if let Some(target) = potential_leaders.first() {
            tracing::info!("Transferring leadership to {} before leaving", target);
            self.consensus.transfer_leadership(target.clone()).await?;
            
            // Wait a bit for the transfer to complete
            tokio::time::sleep(Duration::from_secs(2)).await;
        }

        Ok(())
    }

    async fn trigger_leader_election(&self) -> Result<()> {
        tracing::info!("Triggering leader election");
        
        let operation_id = format!("election_{}", uuid::Uuid::new_v4());
        self.start_operation(operation_id.clone(), "leader_election".to_string()).await?;
        
        match self.consensus.elect_leader().await {
            Ok(new_leader) => {
                tracing::info!("New leader elected: {}", new_leader);
                
                {
                    let mut state = self.state.write().await;
                    state.set_leader(Some(new_leader.clone()))?;
                }

                let event = CoordinationEvent::LeaderElected {
                    node_id: new_leader,
                    term: self.consensus.get_term().await,
                    timestamp: current_timestamp(),
                };
                let _ = self.event_tx.send(event);
                
                self.complete_operation(operation_id, OperationState::Completed).await?;
            }
            Err(e) => {
                tracing::error!("Leader election failed: {}", e);
                self.complete_operation(operation_id, OperationState::Failed).await?;
                return Err(e);
            }
        }

        Ok(())
    }

    async fn scale_up(&mut self, count: usize) -> Result<()> {
        let operation_id = format!("scale_up_{}", uuid::Uuid::new_v4());
        self.start_operation(operation_id.clone(), format!("scale_up_{}", count)).await?;
        
        // In a real implementation, this would:
        // 1. Request new nodes from orchestrator (Kubernetes, Docker Swarm, etc.)
        // 2. Wait for nodes to come online
        // 3. Add them to the cluster
        
        tracing::info!("Scale up operation {} not fully implemented", operation_id);
        self.complete_operation(operation_id, OperationState::Completed).await?;
        
        Ok(())
    }

    async fn scale_down(&mut self, count: usize) -> Result<()> {
        let operation_id = format!("scale_down_{}", uuid::Uuid::new_v4());
        self.start_operation(operation_id.clone(), format!("scale_down_{}", count)).await?;
        
        // In a real implementation, this would:
        // 1. Select nodes to remove (prefer non-voting or unhealthy nodes)
        // 2. Gracefully remove them from consensus
        // 3. Signal orchestrator to terminate the nodes
        
        tracing::info!("Scale down operation {} not fully implemented", operation_id);
        self.complete_operation(operation_id, OperationState::Completed).await?;
        
        Ok(())
    }

    async fn start_operation(&self, operation_id: String, description: String) -> Result<()> {
        let status = OperationStatus {
            id: operation_id.clone(),
            description,
            state: OperationState::Running,
            started_at: current_timestamp(),
            completed_at: None,
            error: None,
        };

        {
            let mut operations = self.active_operations.write().await;
            operations.insert(operation_id, status);
        }

        Ok(())
    }

    async fn complete_operation(&self, operation_id: String, state: OperationState) -> Result<()> {
        {
            let mut operations = self.active_operations.write().await;
            if let Some(status) = operations.get_mut(&operation_id) {
                status.state = state;
                status.completed_at = Some(current_timestamp());
            }
        }

        Ok(())
    }
}

/// Coordination events that can occur in the cluster
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum CoordinationEvent {
    NodeStarted {
        node_id: NodeId,
        timestamp: u64,
    },
    NodeStopping {
        node_id: NodeId,
        timestamp: u64,
    },
    NodeLeft {
        node_id: NodeId,
        timestamp: u64,
    },
    NodeFailed {
        node_id: NodeId,
        timestamp: u64,
    },
    NodeRecovered {
        node_id: NodeId,
        timestamp: u64,
    },
    LeaderElected {
        node_id: NodeId,
        term: u64,
        timestamp: u64,
    },
    LeadershipTransferred {
        from_node: NodeId,
        to_node: NodeId,
        timestamp: u64,
    },
    ClusterScaling {
        target_size: usize,
        current_size: usize,
        timestamp: u64,
    },
    ConfigurationChanged {
        key: String,
        timestamp: u64,
    },
}

/// Information about a cluster obtained from bootstrap nodes
#[derive(Debug, Clone)]
struct ClusterInfo {
    cluster_name: String,
    leader_id: Option<NodeId>,
    node_count: usize,
    bootstrap_address: SocketAddr,
}

/// Status of a coordination operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperationStatus {
    pub id: String,
    pub description: String,
    pub state: OperationState,
    pub started_at: u64,
    pub completed_at: Option<u64>,
    pub error: Option<String>,
}

/// State of a coordination operation
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OperationState {
    Running,
    Completed,
    Failed,
    Cancelled,
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
    use crate::config::ClusterConfig;
    use crate::consensus::SimpleConsensus;

    async fn create_test_coordinator() -> ClusterCoordinator {
        let node_id = NodeId::new();
        let config = ClusterConfig::default();
        let state = Arc::new(RwLock::new(ClusterState::new(node_id.clone())));
        let consensus = Arc::new(SimpleConsensus::new(node_id.clone()));
        
        ClusterCoordinator::new(node_id, config, state, consensus)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn test_coordinator_creation() {
        let coordinator = create_test_coordinator().await;
        assert!(!coordinator.node_id.to_string().is_empty());
    }

    #[tokio::test]
    async fn test_coordinator_start_shutdown() {
        let mut coordinator = create_test_coordinator().await;
        
        // Start coordinator
        assert!(coordinator.start().await.is_ok());
        
        // Shutdown coordinator
        assert!(coordinator.shutdown().await.is_ok());
    }

    #[tokio::test]
    async fn test_event_subscription() {
        let coordinator = create_test_coordinator().await;
        let mut event_rx = coordinator.subscribe_to_events();
        
        // Send an event
        let test_event = CoordinationEvent::NodeStarted {
            node_id: coordinator.node_id.clone(),
            timestamp: current_timestamp(),
        };
        
        coordinator.event_tx.send(test_event.clone()).unwrap();
        
        // Receive the event
        let received_event = event_rx.recv().await.unwrap();
        match (&test_event, &received_event) {
            (
                CoordinationEvent::NodeStarted { node_id: id1, .. },
                CoordinationEvent::NodeStarted { node_id: id2, .. },
            ) => {
                assert_eq!(id1, id2);
            }
            _ => panic!("Event types don't match"),
        }
    }

    #[tokio::test]
    async fn test_operation_tracking() {
        let coordinator = create_test_coordinator().await;
        
        // Start an operation
        let op_id = "test_operation".to_string();
        coordinator.start_operation(op_id.clone(), "Test operation".to_string()).await.unwrap();
        
        // Check operation status
        let status = coordinator.get_operation_status(&op_id).await.unwrap();
        assert_eq!(status.state, OperationState::Running);
        assert_eq!(status.description, "Test operation");
        
        // Complete the operation
        coordinator.complete_operation(op_id.clone(), OperationState::Completed).await.unwrap();
        
        // Check updated status
        let status = coordinator.get_operation_status(&op_id).await.unwrap();
        assert_eq!(status.state, OperationState::Completed);
        assert!(status.completed_at.is_some());
    }

    #[tokio::test]
    async fn test_cluster_scaling() {
        let mut coordinator = create_test_coordinator().await;
        
        // Test scale up
        assert!(coordinator.scale_cluster(5).await.is_ok());
        
        // Test scale down
        assert!(coordinator.scale_cluster(2).await.is_ok());
        
        // Test no scaling needed
        assert!(coordinator.scale_cluster(2).await.is_ok());
    }
}