use vpn_containerd::ContainerdFactory;
use vpn_runtime::{RuntimeConfig, ContainerdConfig, RuntimeType};
use std::time::Duration;

#[tokio::test]
async fn test_containerd_availability_check() {
    let available = ContainerdFactory::is_available().await;
    
    // This test will pass/fail based on system configuration
    // Just verify the method doesn't panic
    println!("Containerd available: {}", available);
}

#[tokio::test]
async fn test_factory_creation_with_invalid_config() {
    let config = RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        socket_path: Some("/nonexistent/socket".to_string()),
        namespace: Some("test".to_string()),
        timeout: Duration::from_secs(5),
        max_connections: 10,
        containerd: Some(ContainerdConfig {
            socket_path: "/nonexistent/socket".to_string(),
            namespace: "test".to_string(),
            timeout_seconds: 5,
            max_connections: 10,
            snapshotter: "overlayfs".to_string(),
            runtime: "io.containerd.runc.v2".to_string(),
        }),
        docker: None,
        fallback_enabled: false,
    };

    let result = ContainerdFactory::create_runtime(config).await;
    assert!(result.is_err(), "Should fail with invalid socket path");
}

#[tokio::test] 
async fn test_verify_connection_with_invalid_config() {
    let config = RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        socket_path: Some("/nonexistent/socket".to_string()),
        namespace: Some("test".to_string()),
        timeout: Duration::from_secs(5),
        max_connections: 10,
        containerd: Some(ContainerdConfig {
            socket_path: "/nonexistent/socket".to_string(),
            namespace: "test".to_string(),
            timeout_seconds: 5,
            max_connections: 10,
            snapshotter: "overlayfs".to_string(),
            runtime: "io.containerd.runc.v2".to_string(),
        }),
        docker: None,
        fallback_enabled: false,
    };

    let result = ContainerdFactory::verify_connection(config).await;
    assert!(result.is_err(), "Should fail with invalid socket path");
}

#[tokio::test]
#[ignore] // Only run when containerd is actually available
async fn test_factory_creation_with_valid_config() {
    if !ContainerdFactory::is_available().await {
        println!("Skipping test: containerd not available");
        return;
    }

    let config = RuntimeConfig::containerd();

    let result = ContainerdFactory::create_runtime(config).await;
    assert!(result.is_ok(), "Should succeed with valid containerd config");
}

#[tokio::test]
#[ignore] // Only run when containerd is actually available  
async fn test_verify_connection_with_valid_config() {
    if !ContainerdFactory::is_available().await {
        println!("Skipping test: containerd not available");
        return;
    }

    let config = RuntimeConfig::containerd();

    let result = ContainerdFactory::verify_connection(config).await;
    assert!(result.is_ok(), "Should succeed with valid containerd config");
    
    if let Ok(version) = result {
        println!("Containerd version: {}", version);
        assert!(!version.is_empty(), "Version should not be empty");
    }
}