//! Cross-node communication protocols

use crate::error::{ClusterError, Result};
use crate::node::{Node, NodeId};
use crate::state::ClusterState;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use tonic::{transport::Server, Request, Response, Status};

// Include generated protobuf code
pub mod cluster {
    tonic::include_proto!("cluster");
}

use cluster::{
    cluster_service_server::{ClusterService, ClusterServiceServer},
    consensus_service_server::{ConsensusService, ConsensusServiceServer},
    *,
};

/// gRPC server for cluster communication
pub struct ClusterGrpcServer {
    node_id: NodeId,
    state: Arc<RwLock<ClusterState>>,
    bind_address: SocketAddr,
}

impl ClusterGrpcServer {
    pub fn new(
        node_id: NodeId,
        state: Arc<RwLock<ClusterState>>,
        bind_address: SocketAddr,
    ) -> Self {
        Self {
            node_id,
            state,
            bind_address,
        }
    }

    /// Start the gRPC server
    pub async fn start(&self) -> Result<()> {
        let cluster_service = ClusterServiceImpl {
            node_id: self.node_id.clone(),
            state: self.state.clone(),
        };

        let consensus_service = ConsensusServiceImpl {
            node_id: self.node_id.clone(),
            state: self.state.clone(),
        };

        tracing::info!("Starting gRPC server on {}", self.bind_address);

        Server::builder()
            .add_service(ClusterServiceServer::new(cluster_service))
            .add_service(ConsensusServiceServer::new(consensus_service))
            .serve(self.bind_address)
            .await
            .map_err(|e| ClusterError::network(format!("gRPC server error: {}", e)))?;

        Ok(())
    }
}

/// Implementation of ClusterService
#[derive(Clone)]
struct ClusterServiceImpl {
    node_id: NodeId,
    state: Arc<RwLock<ClusterState>>,
}

#[tonic::async_trait]
impl ClusterService for ClusterServiceImpl {
    async fn join_cluster(
        &self,
        request: Request<JoinClusterRequest>,
    ) -> std::result::Result<Response<JoinClusterResponse>, Status> {
        let req = request.into_inner();
        
        tracing::info!("Received join cluster request from node: {:?}", req.node_info);

        // Convert protobuf NodeInfo to our Node struct
        let node_info = req.node_info.ok_or_else(|| {
            Status::invalid_argument("Missing node info")
        })?;

        let node = convert_proto_to_node(node_info)?;
        
        // Add node to cluster state
        let mut state = self.state.write().await;
        match state.add_node(node) {
            Ok(_) => {
                let cluster_state = convert_state_to_proto(&*state);
                
                let response = JoinClusterResponse {
                    success: true,
                    message: "Successfully joined cluster".to_string(),
                    cluster_state: Some(cluster_state),
                };
                
                Ok(Response::new(response))
            }
            Err(e) => {
                let response = JoinClusterResponse {
                    success: false,
                    message: format!("Failed to join cluster: {}", e),
                    cluster_state: None,
                };
                
                Ok(Response::new(response))
            }
        }
    }

    async fn leave_cluster(
        &self,
        request: Request<LeaveClusterRequest>,
    ) -> std::result::Result<Response<LeaveClusterResponse>, Status> {
        let req = request.into_inner();
        
        let node_id = NodeId::from_string(&req.node_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid node ID: {}", e)))?;

        let mut state = self.state.write().await;
        match state.remove_node(&node_id) {
            Ok(_) => {
                let response = LeaveClusterResponse {
                    success: true,
                    message: "Successfully left cluster".to_string(),
                };
                Ok(Response::new(response))
            }
            Err(e) => {
                let response = LeaveClusterResponse {
                    success: false,
                    message: format!("Failed to leave cluster: {}", e),
                };
                Ok(Response::new(response))
            }
        }
    }

    async fn heartbeat(
        &self,
        request: Request<HeartbeatRequest>,
    ) -> std::result::Result<Response<HeartbeatResponse>, Status> {
        let req = request.into_inner();
        
        let node_id = NodeId::from_string(&req.node_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid node ID: {}", e)))?;

        // Update node's last seen time
        {
            let mut state = self.state.write().await;
            state.update_node_last_seen(&node_id);
        }

        let state = self.state.read().await;
        let response = HeartbeatResponse {
            success: true,
            server_time: current_timestamp(),
            leader_id: state.leader_id.as_ref().map(|id| id.to_string()).unwrap_or_default(),
            term: state.term,
        };

        Ok(Response::new(response))
    }

    async fn sync_state(
        &self,
        request: Request<SyncStateRequest>,
    ) -> std::result::Result<Response<SyncStateResponse>, Status> {
        let _req = request.into_inner();
        
        let state = self.state.read().await;
        let cluster_state = convert_state_to_proto(&*state);
        
        let response = SyncStateResponse {
            success: true,
            cluster_state: Some(cluster_state),
        };

        Ok(Response::new(response))
    }

    async fn forward_to_leader(
        &self,
        request: Request<ForwardMessage>,
    ) -> std::result::Result<Response<ForwardResponse>, Status> {
        let req = request.into_inner();
        
        tracing::debug!("Forwarding message type '{}' to leader", req.message_type);
        
        // In a real implementation, this would forward the message to the leader
        // For now, just return a simple response
        let response = ForwardResponse {
            success: true,
            message: "Message forwarded to leader".to_string(),
            response_payload: vec![],
        };

        Ok(Response::new(response))
    }

    async fn get_cluster_status(
        &self,
        request: Request<StatusRequest>,
    ) -> std::result::Result<Response<StatusResponse>, Status> {
        let _req = request.into_inner();
        
        let state = self.state.read().await;
        let cluster_state = convert_state_to_proto(&*state);
        let nodes: Vec<NodeInfo> = state.get_all_nodes()
            .into_iter()
            .map(convert_node_to_proto)
            .collect();
        
        let response = StatusResponse {
            cluster_state: Some(cluster_state),
            nodes,
            timestamp: current_timestamp(),
        };

        Ok(Response::new(response))
    }
}

/// Implementation of ConsensusService
#[derive(Clone)]
struct ConsensusServiceImpl {
    node_id: NodeId,
    state: Arc<RwLock<ClusterState>>,
}

#[tonic::async_trait]
impl ConsensusService for ConsensusServiceImpl {
    async fn request_vote(
        &self,
        request: Request<VoteRequest>,
    ) -> std::result::Result<Response<VoteResponse>, Status> {
        let req = request.into_inner();
        
        tracing::debug!("Received vote request from {} for term {}", req.candidate_id, req.term);
        
        // Simple vote granting logic (in real Raft, this would be more complex)
        let state = self.state.read().await;
        let vote_granted = req.term > state.term;
        
        let response = VoteResponse {
            term: state.term,
            vote_granted,
        };

        Ok(Response::new(response))
    }

    async fn append_entries(
        &self,
        request: Request<AppendEntriesRequest>,
    ) -> std::result::Result<Response<AppendEntriesResponse>, Status> {
        let req = request.into_inner();
        
        tracing::debug!("Received append entries from {} for term {}", req.leader_id, req.term);
        
        // Simple append entries response (in real Raft, this would be more complex)
        let state = self.state.read().await;
        let success = req.term >= state.term;
        
        let response = AppendEntriesResponse {
            term: state.term,
            success,
        };

        Ok(Response::new(response))
    }

    async fn install_snapshot(
        &self,
        request: Request<SnapshotRequest>,
    ) -> std::result::Result<Response<SnapshotResponse>, Status> {
        let req = request.into_inner();
        
        tracing::debug!("Received snapshot from {} for term {}", req.leader_id, req.term);
        
        // Simple snapshot installation response
        let state = self.state.read().await;
        let success = req.term >= state.term;
        
        let response = SnapshotResponse {
            term: state.term,
            success,
        };

        Ok(Response::new(response))
    }
}

/// gRPC client for communicating with other nodes
pub struct ClusterGrpcClient {
    node_id: NodeId,
}

impl ClusterGrpcClient {
    pub fn new(node_id: NodeId) -> Self {
        Self { node_id }
    }

    /// Send join cluster request to a node
    pub async fn join_cluster(
        &self,
        target_address: SocketAddr,
        node_info: Node,
        cluster_name: String,
    ) -> Result<JoinClusterResponse> {
        let mut client = cluster::cluster_service_client::ClusterServiceClient::connect(
            format!("http://{}", target_address)
        )
        .await
        .map_err(|e| ClusterError::network(format!("Failed to connect: {}", e)))?;

        let request = JoinClusterRequest {
            node_info: Some(convert_node_to_proto(&node_info)),
            cluster_name,
            timestamp: current_timestamp(),
        };

        let response = client
            .join_cluster(request)
            .await
            .map_err(|e| ClusterError::network(format!("Join cluster failed: {}", e)))?
            .into_inner();

        Ok(response)
    }

    /// Send heartbeat to a node
    pub async fn send_heartbeat(
        &self,
        target_address: SocketAddr,
        resources: crate::node::NodeResources,
    ) -> Result<HeartbeatResponse> {
        let mut client = cluster::cluster_service_client::ClusterServiceClient::connect(
            format!("http://{}", target_address)
        )
        .await
        .map_err(|e| ClusterError::network(format!("Failed to connect: {}", e)))?;

        let request = HeartbeatRequest {
            node_id: self.node_id.to_string(),
            timestamp: current_timestamp(),
            resources: Some(convert_resources_to_proto(&resources)),
        };

        let response = client
            .heartbeat(request)
            .await
            .map_err(|e| ClusterError::network(format!("Heartbeat failed: {}", e)))?
            .into_inner();

        Ok(response)
    }

    /// Get cluster status from a node
    pub async fn get_cluster_status(&self, target_address: SocketAddr) -> Result<StatusResponse> {
        let mut client = cluster::cluster_service_client::ClusterServiceClient::connect(
            format!("http://{}", target_address)
        )
        .await
        .map_err(|e| ClusterError::network(format!("Failed to connect: {}", e)))?;

        let request = StatusRequest {
            node_id: self.node_id.to_string(),
        };

        let response = client
            .get_cluster_status(request)
            .await
            .map_err(|e| ClusterError::network(format!("Get status failed: {}", e)))?
            .into_inner();

        Ok(response)
    }
}

// Helper functions for converting between protobuf and internal types

fn convert_node_to_proto(node: &Node) -> NodeInfo {
    NodeInfo {
        node_id: node.id.to_string(),
        name: node.name.clone(),
        address: node.address.to_string(),
        role: format!("{}", node.role),
        status: format!("{}", node.status),
        joined_at: node.joined_at,
        last_seen: node.last_seen,
        metadata: node.metadata.clone(),
        version: node.version.clone(),
        region: node.region.clone().unwrap_or_default(),
        resources: Some(convert_resources_to_proto(&node.resources)),
    }
}

fn convert_proto_to_node(proto: NodeInfo) -> std::result::Result<Node, Status> {
    let node_id = NodeId::from_string(&proto.node_id)
        .map_err(|e| Status::invalid_argument(format!("Invalid node ID: {}", e)))?;
    
    let address: SocketAddr = proto.address.parse()
        .map_err(|e| Status::invalid_argument(format!("Invalid address: {}", e)))?;

    let mut node = Node::with_id(node_id, proto.name, address);
    node.joined_at = proto.joined_at;
    node.last_seen = proto.last_seen;
    node.metadata = proto.metadata;
    node.version = proto.version;
    if !proto.region.is_empty() {
        node.region = Some(proto.region);
    }
    
    if let Some(resources) = proto.resources {
        node.resources = convert_proto_to_resources(resources);
    }

    Ok(node)
}

fn convert_resources_to_proto(resources: &crate::node::NodeResources) -> NodeResources {
    NodeResources {
        cpu_cores: resources.cpu_cores,
        memory_mb: resources.memory_mb,
        disk_mb: resources.disk_mb,
        cpu_usage: resources.cpu_usage,
        memory_usage: resources.memory_usage,
        disk_usage: resources.disk_usage,
        network_bandwidth: resources.network_bandwidth,
    }
}

fn convert_proto_to_resources(proto: NodeResources) -> crate::node::NodeResources {
    crate::node::NodeResources {
        cpu_cores: proto.cpu_cores,
        memory_mb: proto.memory_mb,
        disk_mb: proto.disk_mb,
        cpu_usage: proto.cpu_usage,
        memory_usage: proto.memory_usage,
        disk_usage: proto.disk_usage,
        network_bandwidth: proto.network_bandwidth,
    }
}

fn convert_state_to_proto(state: &ClusterState) -> cluster::ClusterState {
    let nodes: Vec<NodeInfo> = state.get_all_nodes()
        .into_iter()
        .map(convert_node_to_proto)
        .collect();

    // Convert config_data to string map
    let config_data: HashMap<String, String> = state.config_data
        .iter()
        .map(|(k, v)| (k.clone(), v.to_string()))
        .collect();

    cluster::ClusterState {
        cluster_name: state.cluster_name.clone(),
        nodes,
        leader_id: state.leader_id.as_ref().map(|id| id.to_string()).unwrap_or_default(),
        term: state.term,
        config_version: state.config_version,
        config_data,
        last_updated: state.last_updated,
        created_at: state.created_at,
        metadata: state.metadata.clone(),
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
    use std::net::SocketAddr;

    #[test]
    fn test_node_conversion() {
        let address: SocketAddr = "127.0.0.1:8080".parse().unwrap();
        let original_node = Node::new("test-node".to_string(), address);
        
        let proto = convert_node_to_proto(&original_node);
        let converted_node = convert_proto_to_node(proto).unwrap();
        
        assert_eq!(original_node.id, converted_node.id);
        assert_eq!(original_node.name, converted_node.name);
        assert_eq!(original_node.address, converted_node.address);
    }

    #[test]
    fn test_resources_conversion() {
        let original_resources = crate::node::NodeResources {
            cpu_cores: 4,
            memory_mb: 8192,
            disk_mb: 51200,
            cpu_usage: 25.5,
            memory_usage: 60.0,
            disk_usage: 45.2,
            network_bandwidth: 1000,
        };
        
        let proto = convert_resources_to_proto(&original_resources);
        let converted_resources = convert_proto_to_resources(proto);
        
        assert_eq!(original_resources.cpu_cores, converted_resources.cpu_cores);
        assert_eq!(original_resources.memory_mb, converted_resources.memory_mb);
        assert_eq!(original_resources.disk_mb, converted_resources.disk_mb);
    }

    #[tokio::test]
    async fn test_grpc_client_creation() {
        let node_id = NodeId::new();
        let client = ClusterGrpcClient::new(node_id);
        assert!(!client.node_id.to_string().is_empty());
    }
}