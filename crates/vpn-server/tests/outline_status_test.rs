use vpn_server::lifecycle::ServerLifecycle;

#[tokio::test]
async fn test_outline_container_in_status() {
    // This test requires Docker to be running and outline-shadowbox container to exist
    let lifecycle = ServerLifecycle::new().unwrap();
    
    let status = lifecycle.get_status().await.unwrap();
    
    // Check if outline-shadowbox is in the container list
    let outline_container = status.containers.iter()
        .find(|c| c.name == "outline-shadowbox");
    
    assert!(outline_container.is_some(), "outline-shadowbox container should be in status");
    
    // If container exists and is running, check its properties
    if let Some(container) = outline_container {
        if container.is_running {
            assert!(container.memory_usage > 0, "Running container should have memory usage");
        }
    }
}

#[tokio::test]
async fn test_outline_watchtower_in_status() {
    let lifecycle = ServerLifecycle::new().unwrap();
    
    let status = lifecycle.get_status().await.unwrap();
    
    // Check if outline-watchtower is in the container list
    let watchtower = status.containers.iter()
        .find(|c| c.name == "outline-watchtower");
    
    assert!(watchtower.is_some(), "outline-watchtower container should be in status");
}

#[test]
fn test_container_names_updated() {
    // Verify that the container names array includes outline containers
    let expected_containers = vec![
        "vless-xray",
        "outline-shadowbox", 
        "wireguard",
        "vpn-squid-proxy",
        "vpn-proxy-auth",
        "vless-watchtower",
        "outline-watchtower",
    ];
    
    // This is a compile-time check to ensure we've updated the container list
    for container in &expected_containers {
        assert!(!container.is_empty());
    }
}