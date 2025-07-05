//! Consensus mechanisms for cluster coordination

use crate::error::{ClusterError, Result};
use crate::node::NodeId;
use async_trait::async_trait;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;

/// Trait for consensus algorithms
#[async_trait]
pub trait ConsensusEngine: Send + Sync {
    /// Start the consensus engine
    async fn start(&self) -> Result<()>;

    /// Shutdown the consensus engine
    async fn shutdown(&self) -> Result<()>;

    /// Check if this node is the leader
    async fn is_leader(&self) -> bool;

    /// Get the current leader node ID
    async fn get_leader(&self) -> Option<NodeId>;

    /// Propose a state change
    async fn propose(&self, data: Vec<u8>) -> Result<()>;

    /// Perform leader election
    async fn elect_leader(&self) -> Result<NodeId>;

    /// Add a node to the cluster
    async fn add_node(&self, node_id: NodeId, address: String) -> Result<()>;

    /// Remove a node from the cluster
    async fn remove_node(&self, node_id: NodeId) -> Result<()>;

    /// Get current term/epoch
    async fn get_term(&self) -> u64;

    /// Transfer leadership to another node
    async fn transfer_leadership(&self, target: NodeId) -> Result<()>;

    /// Take a snapshot of the current state
    async fn snapshot(&self) -> Result<Vec<u8>>;

    /// Apply a snapshot
    async fn apply_snapshot(&self, snapshot: Vec<u8>) -> Result<()>;

    /// Get consensus metrics
    async fn get_metrics(&self) -> ConsensusMetrics;
}

/// Consensus algorithm metrics
#[derive(Debug, Clone)]
pub struct ConsensusMetrics {
    pub current_term: u64,
    pub last_log_index: u64,
    pub commit_index: u64,
    pub leader_id: Option<NodeId>,
    pub cluster_size: usize,
    pub is_leader: bool,
    pub election_elapsed: Duration,
    pub heartbeat_elapsed: Duration,
}

/// Create consensus engine based on algorithm type
pub async fn create_consensus_engine(
    algorithm: &crate::config::ConsensusAlgorithm,
    node_id: NodeId,
) -> Result<Arc<dyn ConsensusEngine>> {
    match algorithm {
        crate::config::ConsensusAlgorithm::Raft => Ok(Arc::new(RaftConsensus::new(node_id).await?)),
        crate::config::ConsensusAlgorithm::PBFT => Ok(Arc::new(PbftConsensus::new(node_id).await?)),
        crate::config::ConsensusAlgorithm::Simple => Ok(Arc::new(SimpleConsensus::new(node_id))),
    }
}

/// Raft consensus implementation
pub struct RaftConsensus {
    node_id: NodeId,
    state: Arc<RwLock<RaftState>>,
    // In a real implementation, this would contain Raft-specific structures
}

#[derive(Debug)]
struct RaftState {
    current_term: u64,
    voted_for: Option<NodeId>,
    log: Vec<LogEntry>,
    commit_index: u64,
    last_applied: u64,
    next_index: std::collections::HashMap<NodeId, u64>,
    match_index: std::collections::HashMap<NodeId, u64>,
    role: RaftRole,
    leader_id: Option<NodeId>,
    election_timeout: std::time::Instant,
    heartbeat_timeout: std::time::Instant,
    cluster_members: std::collections::HashSet<NodeId>,
}

#[derive(Debug, Clone, PartialEq)]
enum RaftRole {
    Follower,
    Candidate,
    Leader,
}

#[derive(Debug, Clone)]
struct LogEntry {
    term: u64,
    index: u64,
    data: Vec<u8>,
    timestamp: u64,
}

impl RaftConsensus {
    pub async fn new(node_id: NodeId) -> Result<Self> {
        let state = RaftState {
            current_term: 0,
            voted_for: None,
            log: vec![],
            commit_index: 0,
            last_applied: 0,
            next_index: std::collections::HashMap::new(),
            match_index: std::collections::HashMap::new(),
            role: RaftRole::Follower,
            leader_id: None,
            election_timeout: std::time::Instant::now()
                + Duration::from_millis(150 + rand::random::<u64>() % 150),
            heartbeat_timeout: std::time::Instant::now(),
            cluster_members: std::collections::HashSet::new(),
        };

        Ok(Self {
            node_id,
            state: Arc::new(RwLock::new(state)),
        })
    }

    async fn become_leader(&self) -> Result<()> {
        let mut state = self.state.write().await;
        state.role = RaftRole::Leader;
        state.leader_id = Some(self.node_id.clone());
        state.heartbeat_timeout = std::time::Instant::now();

        // Initialize next_index and match_index for all followers
        let last_log_index = state.log.len() as u64;
        let cluster_members: Vec<NodeId> = state.cluster_members.iter().cloned().collect();
        for member in cluster_members {
            if member != self.node_id {
                state.next_index.insert(member.clone(), last_log_index + 1);
                state.match_index.insert(member.clone(), 0);
            }
        }

        tracing::info!(
            "Node {} became leader for term {}",
            self.node_id,
            state.current_term
        );
        Ok(())
    }

    async fn become_follower(&self, term: u64, leader_id: Option<NodeId>) -> Result<()> {
        let mut state = self.state.write().await;
        state.role = RaftRole::Follower;
        state.current_term = term;
        state.voted_for = None;
        state.leader_id = leader_id;
        state.election_timeout =
            std::time::Instant::now() + Duration::from_millis(150 + rand::random::<u64>() % 150);

        tracing::info!("Node {} became follower for term {}", self.node_id, term);
        Ok(())
    }

    async fn become_candidate(&self) -> Result<()> {
        let mut state = self.state.write().await;
        state.role = RaftRole::Candidate;
        state.current_term += 1;
        state.voted_for = Some(self.node_id.clone());
        state.leader_id = None;
        state.election_timeout =
            std::time::Instant::now() + Duration::from_millis(150 + rand::random::<u64>() % 150);

        tracing::info!(
            "Node {} became candidate for term {}",
            self.node_id,
            state.current_term
        );
        Ok(())
    }

    async fn append_log_entry(&self, data: Vec<u8>) -> Result<u64> {
        let mut state = self.state.write().await;

        if state.role != RaftRole::Leader {
            return Err(ClusterError::consensus(
                "Only leader can append log entries",
            ));
        }

        let entry = LogEntry {
            term: state.current_term,
            index: state.log.len() as u64 + 1,
            data,
            timestamp: current_timestamp(),
        };

        let index = entry.index;
        state.log.push(entry);

        tracing::debug!(
            "Leader {} appended log entry at index {}",
            self.node_id,
            index
        );
        Ok(index)
    }
}

#[async_trait]
impl ConsensusEngine for RaftConsensus {
    async fn start(&self) -> Result<()> {
        tracing::info!("Starting Raft consensus engine for node {}", self.node_id);

        // Add self to cluster members
        {
            let mut state = self.state.write().await;
            state.cluster_members.insert(self.node_id.clone());
        }

        // In a real implementation, this would start background tasks for:
        // - Election timeout handling
        // - Heartbeat sending (if leader)
        // - Log replication (if leader)
        // - Message handling

        Ok(())
    }

    async fn shutdown(&self) -> Result<()> {
        tracing::info!(
            "Shutting down Raft consensus engine for node {}",
            self.node_id
        );

        // In a real implementation, this would:
        // - Stop all background tasks
        // - Clean up resources
        // - Notify other nodes

        Ok(())
    }

    async fn is_leader(&self) -> bool {
        let state = self.state.read().await;
        state.role == RaftRole::Leader
    }

    async fn get_leader(&self) -> Option<NodeId> {
        let state = self.state.read().await;
        state.leader_id.clone()
    }

    async fn propose(&self, data: Vec<u8>) -> Result<()> {
        let index = self.append_log_entry(data).await?;

        // In a real implementation, this would:
        // - Replicate the log entry to followers
        // - Wait for majority to acknowledge
        // - Commit the entry when majority confirms

        tracing::debug!("Proposed log entry at index {}", index);
        Ok(())
    }

    async fn elect_leader(&self) -> Result<NodeId> {
        self.become_candidate().await?;

        // In a real implementation, this would:
        // - Send RequestVote RPCs to all other nodes
        // - Wait for majority of votes
        // - Become leader if majority votes received
        // - Fall back to follower if another leader emerges

        // For simplicity, assume we win the election if we're the only node
        let state = self.state.read().await;
        if state.cluster_members.len() == 1 {
            drop(state);
            self.become_leader().await?;
            Ok(self.node_id.clone())
        } else {
            Err(ClusterError::leader_election_failed(
                "Multi-node election not implemented",
            ))
        }
    }

    async fn add_node(&self, node_id: NodeId, _address: String) -> Result<()> {
        let mut state = self.state.write().await;

        if state.cluster_members.contains(&node_id) {
            return Err(ClusterError::node_already_exists(node_id.to_string()));
        }

        state.cluster_members.insert(node_id.clone());

        if state.role == RaftRole::Leader {
            let last_log_index = state.log.len() as u64;
            state.next_index.insert(node_id.clone(), last_log_index + 1);
            state.match_index.insert(node_id.clone(), 0);
        }

        tracing::info!("Added node {} to Raft cluster", node_id);
        Ok(())
    }

    async fn remove_node(&self, node_id: NodeId) -> Result<()> {
        let mut state = self.state.write().await;

        if !state.cluster_members.contains(&node_id) {
            return Err(ClusterError::node_not_found(node_id.to_string()));
        }

        state.cluster_members.remove(&node_id);
        state.next_index.remove(&node_id);
        state.match_index.remove(&node_id);

        // If we removed the current leader, clear leadership
        if state.leader_id.as_ref() == Some(&node_id) {
            state.leader_id = None;
            if state.role == RaftRole::Leader {
                state.role = RaftRole::Follower;
            }
        }

        tracing::info!("Removed node {} from Raft cluster", node_id);
        Ok(())
    }

    async fn get_term(&self) -> u64 {
        let state = self.state.read().await;
        state.current_term
    }

    async fn transfer_leadership(&self, target: NodeId) -> Result<()> {
        let state = self.state.read().await;

        if state.role != RaftRole::Leader {
            return Err(ClusterError::consensus(
                "Only leader can transfer leadership",
            ));
        }

        if !state.cluster_members.contains(&target) {
            return Err(ClusterError::node_not_found(target.to_string()));
        }

        drop(state);

        // In a real implementation, this would:
        // - Send a TimeoutNow message to the target
        // - Step down as leader
        // - Wait for the target to become leader

        self.become_follower(self.get_term().await, Some(target.clone()))
            .await?;

        tracing::info!("Transferred leadership from {} to {}", self.node_id, target);
        Ok(())
    }

    async fn snapshot(&self) -> Result<Vec<u8>> {
        let state = self.state.read().await;

        // In a real implementation, this would create a proper snapshot
        let snapshot_data = serde_json::json!({
            "term": state.current_term,
            "commit_index": state.commit_index,
            "cluster_members": state.cluster_members.iter().map(|id| id.to_string()).collect::<Vec<_>>(),
            "timestamp": current_timestamp()
        });

        Ok(serde_json::to_vec(&snapshot_data)?)
    }

    async fn apply_snapshot(&self, snapshot: Vec<u8>) -> Result<()> {
        let snapshot_data: serde_json::Value = serde_json::from_slice(&snapshot)?;

        let mut state = self.state.write().await;

        if let Some(term) = snapshot_data["term"].as_u64() {
            state.current_term = term;
        }

        if let Some(commit_index) = snapshot_data["commit_index"].as_u64() {
            state.commit_index = commit_index;
        }

        if let Some(members) = snapshot_data["cluster_members"].as_array() {
            state.cluster_members.clear();
            for member in members {
                if let Some(member_str) = member.as_str() {
                    if let Ok(node_id) = NodeId::from_string(member_str) {
                        state.cluster_members.insert(node_id);
                    }
                }
            }
        }

        tracing::info!("Applied Raft snapshot for term {}", state.current_term);
        Ok(())
    }

    async fn get_metrics(&self) -> ConsensusMetrics {
        let state = self.state.read().await;

        ConsensusMetrics {
            current_term: state.current_term,
            last_log_index: state.log.len() as u64,
            commit_index: state.commit_index,
            leader_id: state.leader_id.clone(),
            cluster_size: state.cluster_members.len(),
            is_leader: state.role == RaftRole::Leader,
            election_elapsed: state.election_timeout.elapsed(),
            heartbeat_elapsed: state.heartbeat_timeout.elapsed(),
        }
    }
}

/// PBFT consensus implementation (placeholder)
pub struct PbftConsensus {
    node_id: NodeId,
}

impl PbftConsensus {
    pub async fn new(node_id: NodeId) -> Result<Self> {
        Ok(Self { node_id })
    }
}

#[async_trait]
impl ConsensusEngine for PbftConsensus {
    async fn start(&self) -> Result<()> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn is_leader(&self) -> bool {
        false
    }

    async fn get_leader(&self) -> Option<NodeId> {
        None
    }

    async fn propose(&self, _data: Vec<u8>) -> Result<()> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn elect_leader(&self) -> Result<NodeId> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn add_node(&self, _node_id: NodeId, _address: String) -> Result<()> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn remove_node(&self, _node_id: NodeId) -> Result<()> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn get_term(&self) -> u64 {
        0
    }

    async fn transfer_leadership(&self, _target: NodeId) -> Result<()> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn snapshot(&self) -> Result<Vec<u8>> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn apply_snapshot(&self, _snapshot: Vec<u8>) -> Result<()> {
        Err(ClusterError::consensus(
            "PBFT consensus not yet implemented",
        ))
    }

    async fn get_metrics(&self) -> ConsensusMetrics {
        ConsensusMetrics {
            current_term: 0,
            last_log_index: 0,
            commit_index: 0,
            leader_id: None,
            cluster_size: 0,
            is_leader: false,
            election_elapsed: Duration::from_secs(0),
            heartbeat_elapsed: Duration::from_secs(0),
        }
    }
}

/// Simple consensus implementation (for testing)
pub struct SimpleConsensus {
    node_id: NodeId,
    state: Arc<RwLock<SimpleState>>,
}

#[derive(Debug)]
struct SimpleState {
    is_leader: bool,
    term: u64,
    proposals: Vec<Vec<u8>>,
}

impl SimpleConsensus {
    pub fn new(node_id: NodeId) -> Self {
        let state = SimpleState {
            is_leader: false,
            term: 0,
            proposals: vec![],
        };

        Self {
            node_id,
            state: Arc::new(RwLock::new(state)),
        }
    }
}

#[async_trait]
impl ConsensusEngine for SimpleConsensus {
    async fn start(&self) -> Result<()> {
        tracing::info!("Starting simple consensus engine for node {}", self.node_id);
        Ok(())
    }

    async fn shutdown(&self) -> Result<()> {
        tracing::info!(
            "Shutting down simple consensus engine for node {}",
            self.node_id
        );
        Ok(())
    }

    async fn is_leader(&self) -> bool {
        let state = self.state.read().await;
        state.is_leader
    }

    async fn get_leader(&self) -> Option<NodeId> {
        let state = self.state.read().await;
        if state.is_leader {
            Some(self.node_id.clone())
        } else {
            None
        }
    }

    async fn propose(&self, data: Vec<u8>) -> Result<()> {
        let mut state = self.state.write().await;

        if !state.is_leader {
            return Err(ClusterError::consensus("Only leader can propose"));
        }

        state.proposals.push(data);
        Ok(())
    }

    async fn elect_leader(&self) -> Result<NodeId> {
        let mut state = self.state.write().await;
        state.is_leader = true;
        state.term += 1;

        tracing::info!(
            "Node {} elected as leader for term {}",
            self.node_id,
            state.term
        );
        Ok(self.node_id.clone())
    }

    async fn add_node(&self, _node_id: NodeId, _address: String) -> Result<()> {
        // Simple consensus doesn't manage cluster membership
        Ok(())
    }

    async fn remove_node(&self, _node_id: NodeId) -> Result<()> {
        // Simple consensus doesn't manage cluster membership
        Ok(())
    }

    async fn get_term(&self) -> u64 {
        let state = self.state.read().await;
        state.term
    }

    async fn transfer_leadership(&self, _target: NodeId) -> Result<()> {
        let mut state = self.state.write().await;
        state.is_leader = false;

        tracing::info!("Node {} transferred leadership", self.node_id);
        Ok(())
    }

    async fn snapshot(&self) -> Result<Vec<u8>> {
        let state = self.state.read().await;
        let snapshot = serde_json::json!({
            "term": state.term,
            "proposals_count": state.proposals.len(),
            "timestamp": current_timestamp()
        });

        Ok(serde_json::to_vec(&snapshot)?)
    }

    async fn apply_snapshot(&self, snapshot: Vec<u8>) -> Result<()> {
        let snapshot_data: serde_json::Value = serde_json::from_slice(&snapshot)?;

        let mut state = self.state.write().await;
        if let Some(term) = snapshot_data["term"].as_u64() {
            state.term = term;
        }

        tracing::info!("Applied simple consensus snapshot for term {}", state.term);
        Ok(())
    }

    async fn get_metrics(&self) -> ConsensusMetrics {
        let state = self.state.read().await;

        ConsensusMetrics {
            current_term: state.term,
            last_log_index: state.proposals.len() as u64,
            commit_index: state.proposals.len() as u64,
            leader_id: if state.is_leader {
                Some(self.node_id.clone())
            } else {
                None
            },
            cluster_size: 1,
            is_leader: state.is_leader,
            election_elapsed: Duration::from_secs(0),
            heartbeat_elapsed: Duration::from_secs(0),
        }
    }
}

/// Get current timestamp in seconds since UNIX epoch
fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_raft_consensus_creation() {
        let node_id = NodeId::new();
        let raft = RaftConsensus::new(node_id.clone()).await.unwrap();

        assert!(!raft.is_leader().await);
        assert_eq!(raft.get_term().await, 0);
        assert_eq!(raft.get_leader().await, None);
    }

    #[tokio::test]
    async fn test_raft_leader_election() {
        let node_id = NodeId::new();
        let raft = RaftConsensus::new(node_id.clone()).await.unwrap();

        raft.start().await.unwrap();

        // Single node should win election
        let leader = raft.elect_leader().await.unwrap();
        assert_eq!(leader, node_id);
        assert!(raft.is_leader().await);
        assert_eq!(raft.get_leader().await, Some(node_id));
    }

    #[tokio::test]
    async fn test_raft_propose() {
        let node_id = NodeId::new();
        let raft = RaftConsensus::new(node_id).await.unwrap();

        raft.start().await.unwrap();
        raft.elect_leader().await.unwrap();

        // Should be able to propose as leader
        let data = b"test proposal".to_vec();
        assert!(raft.propose(data).await.is_ok());
    }

    #[tokio::test]
    async fn test_raft_node_management() {
        let node_id = NodeId::new();
        let raft = RaftConsensus::new(node_id).await.unwrap();

        raft.start().await.unwrap();
        raft.elect_leader().await.unwrap();

        let new_node = NodeId::new();

        // Add node
        assert!(raft
            .add_node(new_node.clone(), "127.0.0.1:8081".to_string())
            .await
            .is_ok());

        // Try to add same node again (should fail)
        assert!(raft
            .add_node(new_node.clone(), "127.0.0.1:8082".to_string())
            .await
            .is_err());

        // Remove node
        assert!(raft.remove_node(new_node.clone()).await.is_ok());

        // Try to remove non-existent node (should fail)
        assert!(raft.remove_node(new_node).await.is_err());
    }

    #[tokio::test]
    async fn test_raft_snapshot() {
        let node_id = NodeId::new();
        let raft = RaftConsensus::new(node_id).await.unwrap();

        raft.start().await.unwrap();

        // Take snapshot
        let snapshot = raft.snapshot().await.unwrap();
        assert!(!snapshot.is_empty());

        // Apply snapshot
        assert!(raft.apply_snapshot(snapshot).await.is_ok());
    }

    #[tokio::test]
    async fn test_simple_consensus() {
        let node_id = NodeId::new();
        let simple = SimpleConsensus::new(node_id.clone());

        simple.start().await.unwrap();

        assert!(!simple.is_leader().await);
        assert_eq!(simple.get_leader().await, None);

        // Elect as leader
        let leader = simple.elect_leader().await.unwrap();
        assert_eq!(leader, node_id);
        assert!(simple.is_leader().await);
        assert_eq!(simple.get_leader().await, Some(node_id));

        // Propose as leader
        let data = b"simple proposal".to_vec();
        assert!(simple.propose(data).await.is_ok());

        // Transfer leadership
        let target = NodeId::new();
        assert!(simple.transfer_leadership(target).await.is_ok());
        assert!(!simple.is_leader().await);
    }

    #[tokio::test]
    async fn test_consensus_metrics() {
        let node_id = NodeId::new();
        let raft = RaftConsensus::new(node_id).await.unwrap();

        raft.start().await.unwrap();
        raft.elect_leader().await.unwrap();

        let metrics = raft.get_metrics().await;
        assert!(metrics.is_leader);
        assert!(metrics.current_term > 0);
        assert_eq!(metrics.cluster_size, 1);
    }

    #[tokio::test]
    async fn test_create_consensus_engine() {
        let node_id = NodeId::new();

        // Test Raft creation
        let raft =
            create_consensus_engine(&crate::config::ConsensusAlgorithm::Raft, node_id.clone())
                .await
                .unwrap();
        assert!(!raft.is_leader().await);

        // Test Simple creation
        let simple = create_consensus_engine(&crate::config::ConsensusAlgorithm::Simple, node_id)
            .await
            .unwrap();
        assert!(!simple.is_leader().await);
    }
}
