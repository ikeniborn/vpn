//! Cluster communication demonstration
//!
//! This example shows how to create a cluster with multiple nodes and
//! demonstrate cross-node communication.

use std::net::SocketAddr;
use std::time::Duration;
use tokio::time::sleep;
use vpn_cluster::{
    config::StorageBackendConfig, ClusterConfig, ClusterGrpcClient, ClusterManager, Node, NodeId,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    println!("🚀 Starting VPN Cluster Communication Demo");

    // Create first node (bootstrap node)
    let node1_config = create_node_config("node-1", "127.0.0.1:8001", true, vec![]);
    let mut node1 = ClusterManager::new(node1_config).await?;

    // Start node 1
    tokio::spawn(async move {
        if let Err(e) = node1.start().await {
            eprintln!("Node 1 error: {}", e);
        }
    });

    // Wait for node 1 to start
    sleep(Duration::from_secs(2)).await;

    // Create second node
    let node2_config = create_node_config(
        "node-2",
        "127.0.0.1:8002",
        false,
        vec!["127.0.0.1:8001".parse().unwrap()],
    );
    let mut node2 = ClusterManager::new(node2_config).await?;

    // Start node 2 and join cluster
    tokio::spawn(async move {
        if let Err(e) = node2.start().await {
            eprintln!("Node 2 error: {}", e);
        }
    });

    // Wait for cluster formation
    sleep(Duration::from_secs(3)).await;

    // Create third node
    let node3_config = create_node_config(
        "node-3",
        "127.0.0.1:8003",
        false,
        vec!["127.0.0.1:8001".parse().unwrap()],
    );
    let mut node3 = ClusterManager::new(node3_config).await?;

    // Start node 3
    tokio::spawn(async move {
        if let Err(e) = node3.start().await {
            eprintln!("Node 3 error: {}", e);
        }
    });

    // Wait for all nodes to join
    sleep(Duration::from_secs(2)).await;

    // Demonstrate client communication
    let client = ClusterGrpcClient::new(NodeId::new());

    println!("\n📊 Testing cluster status requests...");

    // Query each node for cluster status
    for port in [8001, 8002, 8003] {
        let address: SocketAddr = format!("127.0.0.1:{}", port).parse()?;

        match client.get_cluster_status(address).await {
            Ok(status) => {
                if let Some(cluster_state) = status.cluster_state {
                    println!(
                        "✅ Node {} - Cluster '{}' has {} nodes",
                        port,
                        cluster_state.cluster_name,
                        cluster_state.nodes.len()
                    );

                    if !cluster_state.leader_id.is_empty() {
                        println!("   Leader: {}", cluster_state.leader_id);
                    }
                }
            }
            Err(e) => {
                println!("❌ Failed to get status from node {}: {}", port, e);
            }
        }
    }

    println!("\n💓 Testing heartbeat communication...");

    // Send heartbeats to nodes
    for port in [8001, 8002, 8003] {
        let address: SocketAddr = format!("127.0.0.1:{}", port).parse()?;
        let resources = vpn_cluster::node::NodeResources {
            cpu_cores: 4,
            memory_mb: 8192,
            disk_mb: 51200,
            cpu_usage: 25.5,
            memory_usage: 60.0,
            disk_usage: 45.2,
            network_bandwidth: 1000,
        };

        match client.send_heartbeat(address, resources).await {
            Ok(response) => {
                println!(
                    "✅ Heartbeat to node {} successful (term: {})",
                    port, response.term
                );
                if !response.leader_id.is_empty() {
                    println!("   Current leader: {}", response.leader_id);
                }
            }
            Err(e) => {
                println!("❌ Heartbeat to node {} failed: {}", port, e);
            }
        }
    }

    println!("\n🔄 Testing node join/leave operations...");

    // Create a temporary node to test join/leave
    let temp_node = Node::new("temp-node".to_string(), "127.0.0.1:8004".parse()?);

    // Try to join cluster through node 1
    match client
        .join_cluster(
            "127.0.0.1:8001".parse()?,
            temp_node,
            "demo-cluster".to_string(),
        )
        .await
    {
        Ok(response) => {
            if response.success {
                println!("✅ Temporary node joined cluster successfully");
                if let Some(cluster_state) = response.cluster_state {
                    println!("   Cluster now has {} nodes", cluster_state.nodes.len());
                }
            } else {
                println!("❌ Failed to join cluster: {}", response.message);
            }
        }
        Err(e) => {
            println!("❌ Join cluster request failed: {}", e);
        }
    }

    println!("\n🏁 Demo completed successfully!");
    println!("   - Demonstrated cluster formation with 3 nodes");
    println!("   - Tested cross-node status queries");
    println!("   - Verified heartbeat communication");
    println!("   - Tested dynamic node join operations");

    Ok(())
}

fn create_node_config(
    name: &str,
    address: &str,
    is_initial: bool,
    bootstrap_nodes: Vec<SocketAddr>,
) -> ClusterConfig {
    ClusterConfig {
        node_name: name.to_string(),
        cluster_name: "demo-cluster".to_string(),
        bind_address: address.parse().unwrap(),
        storage_backend: StorageBackendConfig::Memory,
        consensus_algorithm: vpn_cluster::config::ConsensusAlgorithm::Simple,
        is_initial_node: is_initial,
        bootstrap_nodes,
        gossip_interval: Duration::from_secs(5),
        heartbeat_interval: Duration::from_secs(1),
        election_timeout: Duration::from_secs(10),
    }
}
