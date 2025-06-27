use vpn_docker::{DockerManager, ContainerConfig, ContainerStatus, ContainerStats};
use tokio;
use std::collections::HashMap;

#[tokio::test]
async fn test_docker_manager_creation() {
    let docker = DockerManager::new().await;
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
    let docker = DockerManager::new().await?;
    
    // Test listing containers (should not fail even if empty)
    let containers = docker.list_containers().await;
    assert!(containers.is_ok());
    
    // Test container status check for non-existent container
    let status = docker.get_container_status("non-existent-container").await;
    assert!(matches!(status, Ok(ContainerStatus::NotFound)));
    
    Ok(())
}

#[tokio::test] 
async fn test_container_logs_retrieval() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new().await?;
    
    // Test logs for non-existent container
    let logs = docker.get_container_logs("non-existent", Some(10)).await;
    assert!(logs.is_err());
    
    Ok(())
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
    };
    
    assert_eq!(stats.cpu_usage_percent, 25.5);
    assert_eq!(stats.memory_usage_bytes, 268435456);
    assert_eq!(stats.get_memory_usage_percent(), 50.0);
}

#[tokio::test]
async fn test_docker_image_operations() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new().await?;
    
    // Test image listing
    let images = docker.list_images().await;
    assert!(images.is_ok());
    
    // Test image existence check
    let exists = docker.image_exists("nginx:latest").await;
    assert!(exists.is_ok());
    
    Ok(())
}

#[tokio::test]
async fn test_network_operations() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new().await?;
    
    // Test network listing
    let networks = docker.list_networks().await;
    assert!(networks.is_ok());
    
    Ok(())
}

#[tokio::test]
async fn test_volume_operations() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new().await?;
    
    // Test volume listing
    let volumes = docker.list_volumes().await;
    assert!(volumes.is_ok());
    
    Ok(())
}

#[tokio::test]
async fn test_container_health_check() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new().await?;
    
    // Test health check for non-existent container
    let health = docker.check_container_health("non-existent").await;
    assert!(health.is_err());
    
    Ok(())
}

#[test]
fn test_container_config_builder_pattern() {
    let config = ContainerConfig::new("test", "image:latest")
        .with_port_mapping(8080, 80)
        .with_environment_variable("KEY", "value")
        .with_volume_mount("/host", "/container")
        .with_restart_policy("always");
    
    assert_eq!(config.name, "test");
    assert_eq!(config.port_mappings.len(), 1);
    assert_eq!(config.environment_variables.len(), 1);
    assert_eq!(config.volume_mounts.len(), 1);
    assert_eq!(config.restart_policy.as_deref(), Some("always"));
}

#[test]
fn test_container_status_display() {
    assert_eq!(format!("{}", ContainerStatus::Running), "running");
    assert_eq!(format!("{}", ContainerStatus::Stopped), "stopped");
    assert_eq!(format!("{}", ContainerStatus::NotFound), "not_found");
    assert_eq!(format!("{}", ContainerStatus::Error("test".to_string())), "error: test");
}

#[tokio::test]
async fn test_docker_cleanup_operations() -> Result<(), Box<dyn std::error::Error>> {
    let docker = DockerManager::new().await?;
    
    // Test cleanup operations (should not fail)
    let cleanup_result = docker.cleanup_unused_containers().await;
    assert!(cleanup_result.is_ok());
    
    let prune_result = docker.prune_unused_images().await;
    assert!(prune_result.is_ok());
    
    Ok(())
}