use vpn_containerd::ContainerdRuntime;
use vpn_runtime::{ContainerdConfig, RuntimeConfig, RuntimeType, ContainerRuntime};

/// Test basic containerd connectivity
/// Note: This test requires a running containerd daemon
#[tokio::test]
#[ignore] // Ignored by default since it requires containerd to be running
async fn test_basic_containerd_connectivity() {
    let config = RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        containerd: Some(ContainerdConfig {
            socket_path: "/run/containerd/containerd.sock".to_string(),
            namespace: "default".to_string(),
            snapshotter: "overlayfs".to_string(),
            timeout_seconds: 30,
            max_connections: 5,
            runtime: "io.containerd.runc.v2".to_string(),
        }),
        ..Default::default()
    };

    // Test connection
    match ContainerdRuntime::connect(config).await {
        Ok(runtime) => {
            println!("✓ Successfully connected to containerd");
            
            // Test ping
            match runtime.ping().await {
                Ok(_) => println!("✓ Ping successful"),
                Err(e) => {
                    println!("✗ Ping failed: {}", e);
                    panic!("Ping failed");
                }
            }
        }
        Err(e) => {
            println!("✗ Failed to connect to containerd: {}", e);
            // Don't panic here since containerd might not be running
            // This is expected in CI/test environments
            println!("Note: This test requires a running containerd daemon");
        }
    }
}

#[tokio::test]
async fn test_config_validation() {
    let config = RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        containerd: Some(ContainerdConfig::default()),
        ..Default::default()
    };

    // Test that we can create the runtime config without errors
    assert_eq!(config.runtime_type, RuntimeType::Containerd);
    assert_eq!(config.effective_namespace(), "default");
    assert!(config.effective_socket_path().contains("containerd.sock"));
}

#[test]
fn test_containerd_types() {
    use vpn_containerd::{ContainerdContainer, ContainerdTask, ContainerdImage, ContainerdVolume};
    use chrono::Utc;
    use std::collections::HashMap;
    use vpn_runtime::{Container, Task, Image, Volume, ContainerState, ContainerStatus, TaskStatus};

    // Test ContainerdContainer
    let container = ContainerdContainer {
        id: "test-container".to_string(),
        name: "test".to_string(),
        image: "alpine:latest".to_string(),
        state: ContainerState::Running,
        status: ContainerStatus {
            state: ContainerState::Running,
            started_at: Some(Utc::now()),
            finished_at: None,
            exit_code: None,
            error: None,
        },
        labels: HashMap::new(),
        created_at: Utc::now(),
    };

    assert_eq!(container.id(), "test-container");
    assert_eq!(container.name(), "test");
    assert_eq!(container.image(), "alpine:latest");

    // Test ContainerdTask
    let task = ContainerdTask {
        id: "task-1".to_string(),
        container_id: "test-container".to_string(),
        pid: Some(1234),
        status: TaskStatus::Running,
        exit_code: None,
    };

    assert_eq!(task.id(), "task-1");
    assert_eq!(task.container_id(), "test-container");
    assert_eq!(task.pid(), Some(1234));

    // Test ContainerdImage
    let image = ContainerdImage {
        id: "alpine:latest".to_string(),
        tags: vec!["alpine:latest".to_string()],
        size: 5000000,
        created_at: Utc::now(),
        labels: HashMap::new(),
    };

    assert_eq!(image.id(), "alpine:latest");
    assert_eq!(image.size(), 5000000);

    // Test ContainerdVolume
    let volume = ContainerdVolume {
        name: "test-volume".to_string(),
        driver: "overlayfs".to_string(),
        mount_point: Some("/var/lib/containerd/snapshots".to_string()),
        labels: HashMap::new(),
        created_at: Utc::now(),
    };

    assert_eq!(volume.name(), "test-volume");
    assert_eq!(volume.driver(), "overlayfs");
}