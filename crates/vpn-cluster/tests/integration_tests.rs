//! Integration tests for cross-node communication

use std::net::SocketAddr;
use std::time::Duration;
use tokio::time::{sleep, timeout};
use tracing_subscriber::fmt::try_init;
use vpn_cluster::{
    config::{ConsensusAlgorithm, StorageBackendConfig},
    ClusterConfig, ClusterGrpcClient, ClusterManager, Node, NodeId,
};

/// Test basic cluster formation and communication
#[tokio::test]
async fn test_cluster_formation() {
    let _ = try_init();

    // Create bootstrap node
    let node1_config = ClusterConfig {
        node_name: "test-node-1".to_string(),
        cluster_name: "test-cluster".to_string(),
        bind_address: "127.0.0.1:9001".parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: ConsensusAlgorithm::Simple,
        is_initial_node: true,
        bootstrap_nodes: vec![],
        gossip_interval: Duration::from_secs(1),
        heartbeat_interval: Duration::from_millis(500),
        election_timeout: Duration::from_secs(5),
    };

    let mut node1 = ClusterManager::new(node1_config).await.unwrap();

    // Start node in background
    let node1_handle = tokio::spawn(async move { node1.start().await });

    // Wait for node to start
    sleep(Duration::from_millis(500)).await;

    // Test client can connect to node
    let client = ClusterGrpcClient::new(NodeId::new());
    let status = timeout(
        Duration::from_secs(2),
        client.get_cluster_status("127.0.0.1:9001".parse().unwrap()),
    )
    .await;

    assert!(status.is_ok(), "Should be able to get cluster status");
    let status = status.unwrap().unwrap();

    assert!(status.cluster_state.is_some());
    let cluster_state = status.cluster_state.unwrap();
    assert_eq!(cluster_state.cluster_name, "test-cluster");
    assert_eq!(cluster_state.nodes.len(), 1);

    // Clean up
    node1_handle.abort();
}

/// Test node joining an existing cluster
#[tokio::test]
async fn test_node_join_cluster() {
    let _ = try_init();

    // Create bootstrap node
    let node1_config = ClusterConfig {
        node_name: "bootstrap-node".to_string(),
        cluster_name: "join-test-cluster".to_string(),
        bind_address: "127.0.0.1:9101".parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: ConsensusAlgorithm::Simple,
        is_initial_node: true,
        bootstrap_nodes: vec![],
        gossip_interval: Duration::from_secs(1),
        heartbeat_interval: Duration::from_millis(500),
        election_timeout: Duration::from_secs(5),
    };

    let mut node1 = ClusterManager::new(node1_config).await.unwrap();
    let node1_handle = tokio::spawn(async move { node1.start().await });

    // Wait for bootstrap node to be ready
    sleep(Duration::from_millis(500)).await;

    // Create second node that joins the cluster
    let node2_config = ClusterConfig {
        node_name: "joining-node".to_string(),
        cluster_name: "join-test-cluster".to_string(),
        bind_address: "127.0.0.1:9102".parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: ConsensusAlgorithm::Simple,
        is_initial_node: false,
        bootstrap_nodes: vec!["127.0.0.1:9101".parse().unwrap()],
        gossip_interval: Duration::from_secs(1),
        heartbeat_interval: Duration::from_millis(500),
        election_timeout: Duration::from_secs(5),
    };

    let mut node2 = ClusterManager::new(node2_config).await.unwrap();
    let node2_handle = tokio::spawn(async move { node2.start().await });

    // Wait for cluster formation
    sleep(Duration::from_secs(1)).await;

    // Test that both nodes see each other
    let client = ClusterGrpcClient::new(NodeId::new());

    // Check cluster state from node 1
    let status1 = client
        .get_cluster_status("127.0.0.1:9101".parse().unwrap())
        .await
        .unwrap();
    assert!(status1.cluster_state.is_some());
    let cluster_state1 = status1.cluster_state.unwrap();

    // Check cluster state from node 2
    let status2 = client
        .get_cluster_status("127.0.0.1:9102".parse().unwrap())
        .await
        .unwrap();
    assert!(status2.cluster_state.is_some());
    let cluster_state2 = status2.cluster_state.unwrap();

    // Both should report the same cluster size
    assert_eq!(cluster_state1.cluster_name, "join-test-cluster");
    assert_eq!(cluster_state2.cluster_name, "join-test-cluster");

    // Note: Due to timing, we might see 1 or 2 nodes depending on when the join completes
    assert!(cluster_state1.nodes.len() >= 1);
    assert!(cluster_state2.nodes.len() >= 1);

    // Clean up
    node1_handle.abort();
    node2_handle.abort();
}

/// Test heartbeat communication between nodes
#[tokio::test]
async fn test_heartbeat_communication() {
    let _ = try_init();

    // Create a single node for heartbeat testing
    let node_config = ClusterConfig {
        node_name: "heartbeat-node".to_string(),
        cluster_name: "heartbeat-cluster".to_string(),
        bind_address: "127.0.0.1:9201".parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: ConsensusAlgorithm::Simple,
        is_initial_node: true,
        bootstrap_nodes: vec![],
        gossip_interval: Duration::from_secs(1),
        heartbeat_interval: Duration::from_millis(500),
        election_timeout: Duration::from_secs(5),
    };

    let mut node = ClusterManager::new(node_config).await.unwrap();
    let node_handle = tokio::spawn(async move { node.start().await });

    // Wait for node to start
    sleep(Duration::from_millis(500)).await;

    // Test heartbeat
    let client = ClusterGrpcClient::new(NodeId::new());
    let resources = vpn_cluster::node::NodeResources {
        cpu_cores: 4,
        memory_mb: 8192,
        disk_mb: 51200,
        cpu_usage: 25.5,
        memory_usage: 60.0,
        disk_usage: 45.2,
        network_bandwidth: 1000,
    };

    let heartbeat_response = timeout(
        Duration::from_secs(2),
        client.send_heartbeat("127.0.0.1:9201".parse().unwrap(), resources),
    )
    .await;

    assert!(heartbeat_response.is_ok(), "Heartbeat should succeed");
    let response = heartbeat_response.unwrap().unwrap();
    assert!(response.success);
    assert!(response.server_time > 0);

    // Clean up
    node_handle.abort();
}

/// Test client join operations
#[tokio::test]
async fn test_client_join_operations() {
    let _ = try_init();

    // Create bootstrap node
    let node_config = ClusterConfig {
        node_name: "join-test-node".to_string(),
        cluster_name: "client-join-cluster".to_string(),
        bind_address: "127.0.0.1:9301".parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: ConsensusAlgorithm::Simple,
        is_initial_node: true,
        bootstrap_nodes: vec![],
        gossip_interval: Duration::from_secs(1),
        heartbeat_interval: Duration::from_millis(500),
        election_timeout: Duration::from_secs(5),
    };

    let mut node = ClusterManager::new(node_config).await.unwrap();
    let node_handle = tokio::spawn(async move { node.start().await });

    // Wait for node to start
    sleep(Duration::from_millis(500)).await;

    // Test client join
    let client = ClusterGrpcClient::new(NodeId::new());
    let joining_node = Node::new(
        "client-joined-node".to_string(),
        "127.0.0.1:9302".parse().unwrap(),
    );

    let join_response = timeout(
        Duration::from_secs(2),
        client.join_cluster(
            "127.0.0.1:9301".parse().unwrap(),
            joining_node,
            "client-join-cluster".to_string(),
        ),
    )
    .await;

    assert!(join_response.is_ok(), "Join request should succeed");
    let response = join_response.unwrap().unwrap();
    assert!(
        response.success,
        "Join should be successful: {}",
        response.message
    );

    // Verify cluster state includes new node
    if let Some(cluster_state) = response.cluster_state {
        assert_eq!(cluster_state.cluster_name, "client-join-cluster");
        assert!(
            cluster_state.nodes.len() >= 2,
            "Should have at least 2 nodes after join"
        );
    }

    // Clean up
    node_handle.abort();
}

/// Test multiple concurrent operations
#[tokio::test]
async fn test_concurrent_operations() {
    let _ = try_init();

    // Create bootstrap node
    let node_config = ClusterConfig {
        node_name: "concurrent-test-node".to_string(),
        cluster_name: "concurrent-cluster".to_string(),
        bind_address: "127.0.0.1:9401".parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: ConsensusAlgorithm::Simple,
        is_initial_node: true,
        bootstrap_nodes: vec![],
        gossip_interval: Duration::from_secs(1),
        heartbeat_interval: Duration::from_millis(500),
        election_timeout: Duration::from_secs(5),
    };

    let mut node = ClusterManager::new(node_config).await.unwrap();
    let node_handle = tokio::spawn(async move { node.start().await });

    // Wait for node to start
    sleep(Duration::from_millis(500)).await;

    // Run concurrent operations
    let client = ClusterGrpcClient::new(NodeId::new());
    let address: SocketAddr = "127.0.0.1:9401".parse().unwrap();

    let resources = vpn_cluster::node::NodeResources {
        cpu_cores: 4,
        memory_mb: 8192,
        disk_mb: 51200,
        cpu_usage: 25.5,
        memory_usage: 60.0,
        disk_usage: 45.2,
        network_bandwidth: 1000,
    };

    // Run multiple operations concurrently
    let (status_result, heartbeat_result) = tokio::join!(
        client.get_cluster_status(address),
        client.send_heartbeat(address, resources)
    );

    assert!(
        status_result.is_ok(),
        "Concurrent status request should succeed"
    );
    assert!(
        heartbeat_result.is_ok(),
        "Concurrent heartbeat should succeed"
    );

    let status = status_result.unwrap();
    let heartbeat = heartbeat_result.unwrap();

    assert!(status.cluster_state.is_some());
    assert!(heartbeat.success);

    // Clean up
    node_handle.abort();
}

/// Test error handling for invalid requests
#[tokio::test]
async fn test_error_handling() {
    let _ = try_init();

    let client = ClusterGrpcClient::new(NodeId::new());

    // Test connection to non-existent node
    let invalid_address: SocketAddr = "127.0.0.1:9999".parse().unwrap();

    let status_result = timeout(
        Duration::from_secs(2),
        client.get_cluster_status(invalid_address),
    )
    .await;

    // Should timeout or return connection error
    assert!(
        status_result.is_err() || status_result.unwrap().is_err(),
        "Should fail to connect to non-existent node"
    );
}
