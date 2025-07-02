use vpn_docker::{DockerManager, ContainerConfig, ContainerStatus, ContainerStats};
use tokio;

#[tokio::test]
async fn test_docker_manager_creation() {
    let docker = DockerManager::new();
    assert!(docker.is_ok());
}

#[tokio::test]
async fn test_container_config_validation() {
    let mut config = ContainerConfig::new("test-container", "nginx:latest");
    config.add_port_mapping(8080, 80);
    config.add_environment_variable("TEST_VAR", "test_value");
    config.add_volume_mount("/host/path", "/container/path");
    
    assert_eq!(config.name, "test-container");
    assert_eq!(config.image, "nginx:latest");
    assert_eq!(config.port_mappings.len(), 1);
    assert_eq!(config.environment_variables.len(), 1);
    assert_eq!(config.volume_mounts.len(), 1);
}

#[tokio::test]
async fn test_container_lifecycle_simulation() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new()?;
    
    // Test listing containers (should not fail even if empty)
    let containers = docker.list_containers(false).await;
    assert!(containers.is_ok());
    
    Ok(())
}

#[test]
fn test_container_status_conversion() {
    assert!(matches!(ContainerStatus::from("running"), ContainerStatus::Running));
    assert!(matches!(ContainerStatus::from("stopped"), ContainerStatus::Stopped));
    assert!(matches!(ContainerStatus::from("paused"), ContainerStatus::Paused));
    assert!(matches!(ContainerStatus::from("exited (0)"), ContainerStatus::Exited(0)));
    assert!(matches!(ContainerStatus::from("exited (1)"), ContainerStatus::Exited(1)));
    assert!(matches!(ContainerStatus::from("unknown_status"), ContainerStatus::Unknown(_)));
}

#[tokio::test]
async fn test_container_stats_structure() {
    let stats = ContainerStats {
        cpu_usage_percent: 25.5,
        memory_usage_bytes: 1024 * 1024 * 256, // 256MB
        memory_limit_bytes: 1024 * 1024 * 512, // 512MB
        network_rx_bytes: 1024 * 100,
        network_tx_bytes: 1024 * 50,
        block_read_bytes: 1024 * 1024,
        block_write_bytes: 1024 * 512,
        pids: 42,
    };
    
    assert_eq!(stats.cpu_usage_percent, 25.5);
    assert_eq!(stats.memory_usage_bytes, 268435456);
    assert_eq!(stats.get_memory_usage_percent(), 50.0);
}

#[test]
fn test_container_config_builder_pattern() {
    let config = ContainerConfig::new("test", "image:latest")
        .with_port_mapping(8080, 80)
        .with_environment_variable("KEY", "value")
        .with_volume_mount("/host", "/container")
        .with_restart_policy("always");
    
    assert_eq!(config.name, "test");
    assert_eq!(config.image, "image:latest");
    assert_eq!(config.port_mappings.get(&8080), Some(&80));
    assert_eq!(config.environment_variables.get("KEY"), Some(&"value".to_string()));
    assert_eq!(config.volume_mounts.get("/host"), Some(&"/container".to_string()));
    assert_eq!(config.restart_policy, "always");
}

#[test]
fn test_container_status_display() {
    assert_eq!(format!("{}", ContainerStatus::Running), "running");
    assert_eq!(format!("{}", ContainerStatus::Stopped), "stopped");
    assert_eq!(format!("{}", ContainerStatus::NotFound), "not_found");
    assert_eq!(format!("{}", ContainerStatus::Error("test".to_string())), "error: test");
    assert_eq!(format!("{}", ContainerStatus::Exited(0)), "exited(0)");
    assert_eq!(format!("{}", ContainerStatus::Exited(1)), "exited(1)");
}

#[test]
fn test_container_stats_default() {
    let stats = ContainerStats::default();
    assert_eq!(stats.cpu_usage_percent, 0.0);
    assert_eq!(stats.memory_usage_bytes, 0);
    assert_eq!(stats.memory_limit_bytes, 0);
    assert_eq!(stats.get_memory_usage_percent(), 0.0);
}

#[test]
fn test_container_config_networks() {
    let mut config = ContainerConfig::new("test", "nginx");
    assert_eq!(config.networks, vec!["default"]);
    
    config.add_network("custom-network");
    assert!(config.networks.contains(&"custom-network".to_string()));
    
    // Test that adding the same network twice doesn't duplicate it
    config.add_network("custom-network");
    let custom_count = config.networks.iter().filter(|&n| n == "custom-network").count();
    assert_eq!(custom_count, 1);
}

#[test]
fn test_container_stats_memory_calculation() {
    let stats = ContainerStats {
        memory_usage_bytes: 500 * 1024 * 1024, // 500MB
        memory_limit_bytes: 1024 * 1024 * 1024, // 1GB
        ..Default::default()
    };
    
    // Should be approximately 48.83%
    let percentage = stats.get_memory_usage_percent();
    assert!((percentage - 48.83).abs() < 0.01);
    
    // Test division by zero case
    let stats_no_limit = ContainerStats {
        memory_usage_bytes: 100,
        memory_limit_bytes: 0,
        ..Default::default()
    };
    assert_eq!(stats_no_limit.get_memory_usage_percent(), 0.0);
}