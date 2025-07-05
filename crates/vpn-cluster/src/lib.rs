//! VPN Cluster Management
//!
//! This crate provides distributed state management, cluster coordination,
//! and horizontal scaling capabilities for the VPN system.

pub mod communication;
pub mod config;
pub mod consensus;
pub mod coordination;
pub mod distributed_storage;
pub mod error;
pub mod gossip;
pub mod leader_election;
pub mod membership;
pub mod node;
pub mod state;

pub use communication::{ClusterGrpcClient, ClusterGrpcServer};
pub use config::ClusterConfig;
pub use consensus::{ConsensusEngine, RaftConsensus};
pub use coordination::{ClusterCoordinator, CoordinationEvent};
pub use distributed_storage::DistributedConfigStorage;
pub use error::{ClusterError, Result};
pub use node::{Node, NodeId, NodeRole, NodeStatus};
pub use state::{ClusterState, DistributedState};

use std::sync::Arc;
use tokio::sync::RwLock;
// use uuid::Uuid;  // Not needed directly

/// Main cluster manager that orchestrates all distributed components
pub struct ClusterManager {
    pub node_id: NodeId,
    pub config: ClusterConfig,
    pub state: Arc<RwLock<ClusterState>>,
    pub coordinator: ClusterCoordinator,
    pub storage: Arc<distributed_storage::MemoryStorage>,
    pub consensus: Arc<consensus::SimpleConsensus>,
}

impl ClusterManager {
    /// Create a new cluster manager
    pub async fn new(config: ClusterConfig) -> Result<Self> {
        let node_id = NodeId::new();
        let state = Arc::new(RwLock::new(ClusterState::with_cluster_name(
            node_id.clone(),
            config.cluster_name.clone(),
        )));

        // Initialize storage backend (simplified to memory storage for now)
        let storage = Arc::new(distributed_storage::MemoryStorage::new());

        // Initialize consensus engine (simplified to simple consensus for now)
        let consensus = Arc::new(consensus::SimpleConsensus::new(node_id.clone()));

        // Initialize coordinator
        let coordinator = ClusterCoordinator::new(
            node_id.clone(),
            config.clone(),
            state.clone(),
            consensus.clone(),
        )
        .await?;

        // Add this node to its own cluster state
        {
            let self_node = Node::new(config.node_name.clone(), config.bind_address);
            let mut cluster_state = state.write().await;
            cluster_state.add_node(self_node)?;
        }

        Ok(Self {
            node_id,
            config,
            state,
            coordinator,
            storage,
            consensus,
        })
    }

    /// Start the cluster manager
    pub async fn start(&mut self) -> Result<()> {
        tracing::info!("Starting cluster manager for node {}", self.node_id);

        // Start gRPC server first
        let grpc_server = ClusterGrpcServer::new(
            self.node_id.clone(),
            self.state.clone(),
            self.config.bind_address,
        );

        tokio::spawn(async move {
            if let Err(e) = grpc_server.start().await {
                tracing::error!("gRPC server failed: {}", e);
            }
        });

        // Give the server a moment to start
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;

        // Start consensus engine
        self.consensus.start().await?;

        // Start coordinator
        self.coordinator.start().await?;

        // Join cluster if not the initial node
        if !self.config.is_initial_node {
            self.join_cluster().await?;
        }

        tracing::info!("Cluster manager started successfully");
        Ok(())
    }

    /// Join an existing cluster
    pub async fn join_cluster(&mut self) -> Result<()> {
        self.coordinator
            .join_cluster(&self.config.bootstrap_nodes)
            .await
    }

    /// Leave the cluster gracefully
    pub async fn leave_cluster(&mut self) -> Result<()> {
        self.coordinator.leave_cluster().await
    }

    /// Get current cluster state
    pub async fn get_cluster_state(&self) -> ClusterState {
        self.state.read().await.clone()
    }

    /// Update cluster configuration
    pub async fn update_config(&mut self, key: &str, value: serde_json::Value) -> Result<()> {
        self.storage.store_config(key, value).await
    }

    /// Get configuration value
    pub async fn get_config(&self, key: &str) -> Result<Option<serde_json::Value>> {
        self.storage.get_config(key).await
    }

    /// Get all nodes in the cluster
    pub async fn get_cluster_nodes(&self) -> Result<Vec<Node>> {
        let state = self.state.read().await;
        Ok(state.nodes.values().cloned().collect())
    }

    /// Check if this node is the leader
    pub async fn is_leader(&self) -> bool {
        self.consensus.is_leader().await
    }

    /// Get current leader node
    pub async fn get_leader(&self) -> Option<NodeId> {
        self.consensus.get_leader().await
    }

    /// Perform leader election
    pub async fn elect_leader(&mut self) -> Result<NodeId> {
        self.consensus.elect_leader().await
    }

    /// Handle node failure
    pub async fn handle_node_failure(&mut self, failed_node: NodeId) -> Result<()> {
        tracing::warn!("Handling failure of node {}", failed_node);
        self.coordinator.handle_node_failure(failed_node).await
    }

    /// Scale cluster by adding nodes
    pub async fn scale_up(&mut self, target_nodes: usize) -> Result<()> {
        self.coordinator.scale_cluster(target_nodes).await
    }

    /// Shutdown cluster manager
    pub async fn shutdown(&mut self) -> Result<()> {
        tracing::info!("Shutting down cluster manager");

        self.leave_cluster().await?;
        self.coordinator.shutdown().await?;
        self.consensus.shutdown().await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_cluster_manager_creation() {
        let temp_dir = tempdir().unwrap();
        let config = ClusterConfig {
            node_name: "test-node".to_string(),
            cluster_name: "test-cluster".to_string(),
            bind_address: "127.0.0.1:8080".parse().unwrap(),
            storage_backend: config::StorageBackendConfig::Sled {
                path: temp_dir.path().to_path_buf(),
            },
            consensus_algorithm: config::ConsensusAlgorithm::Raft,
            is_initial_node: true,
            bootstrap_nodes: vec![],
            gossip_interval: std::time::Duration::from_secs(5),
            heartbeat_interval: std::time::Duration::from_secs(1),
            election_timeout: std::time::Duration::from_secs(10),
        };

        let manager = ClusterManager::new(config).await;
        assert!(manager.is_ok());
    }
}
