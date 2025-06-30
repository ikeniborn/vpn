use vpn_runtime::{
    ContainerFilter, ContainerRuntime, ContainerSpec, RuntimeConfig, RuntimeType,
    ContainerdConfig, MountType, VolumeMount,
};
use vpn_containerd::ContainerdRuntime;
use std::collections::HashMap;

/// Test configuration for integration tests
fn create_test_config() -> RuntimeConfig {
    RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        containerd: Some(ContainerdConfig {
            socket_path: "/run/containerd/containerd.sock".to_string(),
            namespace: "vpn-test".to_string(),
            timeout_seconds: 30,
            max_connections: 5,
            snapshotter: "overlayfs".to_string(),
            runtime: "io.containerd.runc.v2".to_string(),
        }),
        ..Default::default()
    }
}

/// Create a test container specification
fn create_test_container_spec(name: &str) -> ContainerSpec {
    let mut labels = HashMap::new();
    labels.insert("test".to_string(), "true".to_string());
    labels.insert("created_by".to_string(), "integration_test".to_string());

    ContainerSpec {
        name: name.to_string(),
        image: "alpine:latest".to_string(),
        command: Some(vec!["sleep".to_string(), "30".to_string()]),
        args: None,
        environment: {
            let mut env = HashMap::new();
            env.insert("TEST_ENV".to_string(), "test_value".to_string());
            env
        },
        volumes: vec![],
        ports: vec![],
        networks: vec!["default".to_string()],
        labels,
        working_dir: Some("/tmp".to_string()),
        user: Some("root".to_string()),
        restart_policy: vpn_runtime::RestartPolicy::No,
    }
}

/// Test basic runtime connection
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_runtime_connection() {
    let config = create_test_config();
    
    let runtime = ContainerdRuntime::connect(config).await;
    match runtime {
        Ok(mut rt) => {
            // Test ping
            assert!(rt.ping().await.is_ok());
            
            // Test version
            if let Ok(version) = rt.version().await {
                println!("containerd version: {}", version);
                assert!(!version.is_empty());
            }
            
            // Clean disconnect
            assert!(rt.disconnect().await.is_ok());
        }
        Err(e) => {
            println!("Failed to connect to containerd: {}", e);
            println!("Make sure containerd is running and accessible");
        }
    }
}

/// Test container lifecycle operations
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_container_lifecycle() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping test - containerd not available");
            return;
        }
    };

    let container_name = "test-lifecycle-container";
    let spec = create_test_container_spec(container_name);

    // Test container creation
    let container = runtime.create_container(spec).await.unwrap();
    assert_eq!(container.name(), container_name);
    assert_eq!(container.image(), "alpine:latest");

    // Test container exists
    assert!(runtime.container_exists(container_name).await.unwrap());

    // Test get container
    let retrieved = runtime.get_container(container_name).await.unwrap();
    assert_eq!(retrieved.id(), container.id());

    // Test list containers with filter
    let filter = ContainerFilter {
        names: vec![container_name.to_string()],
        ..Default::default()
    };
    let containers = runtime.list_containers(filter).await.unwrap();
    assert_eq!(containers.len(), 1);
    assert_eq!(containers[0].name(), container_name);

    // Clean up - remove container
    runtime.remove_container(container_name, false).await.unwrap();
    
    // Verify removal
    assert!(!runtime.container_exists(container_name).await.unwrap());
}

/// Test task lifecycle operations
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_task_lifecycle() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping test - containerd not available");
            return;
        }
    };

    let container_name = "test-task-container";
    let spec = create_test_container_spec(container_name);

    // Create container
    let _container = runtime.create_container(spec).await.unwrap();

    // Start container (creates and starts task)
    let task = runtime.start_container(container_name).await.unwrap();
    assert_eq!(task.container_id(), container_name);

    // Test get task
    let retrieved_task = runtime.get_task(container_name).await.unwrap();
    assert_eq!(retrieved_task.container_id(), container_name);

    // Test container health check
    let is_healthy = runtime.check_container_health(container_name).await.unwrap();
    assert!(is_healthy);

    // Stop container
    runtime.stop_container(container_name, None).await.unwrap();

    // Clean up
    runtime.remove_container(container_name, false).await.unwrap();
}

/// Test batch operations
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_batch_operations() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping test - containerd not available");
            return;
        }
    };

    let container_names = vec!["batch-test-1", "batch-test-2", "batch-test-3"];
    
    // Create multiple containers
    for name in &container_names {
        let spec = create_test_container_spec(name);
        runtime.create_container(spec).await.unwrap();
    }

    // Test batch start
    let batch_options = vpn_runtime::BatchOptions {
        max_concurrent: 2,
        timeout: std::time::Duration::from_secs(30),
        fail_fast: false,
    };

    let start_result = runtime.batch_start_containers(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        batch_options.clone()
    ).await.unwrap();

    assert_eq!(start_result.success_count(), container_names.len());
    assert_eq!(start_result.failure_count(), 0);

    // Test batch health check
    let health_results = runtime.batch_health_check(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        batch_options.clone()
    ).await.unwrap();

    assert_eq!(health_results.len(), container_names.len());
    for (_, health) in health_results {
        assert!(health.unwrap());
    }

    // Test batch stop
    let stop_result = runtime.batch_stop_containers(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        None,
        batch_options.clone()
    ).await.unwrap();

    assert_eq!(stop_result.success_count(), container_names.len());

    // Clean up - batch remove
    let remove_result = runtime.batch_remove_containers(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        false,
        batch_options
    ).await.unwrap();

    assert_eq!(remove_result.success_count(), container_names.len());
}

/// Test image operations
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_image_operations() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping test - containerd not available");
            return;
        }
    };

    let image_ref = "alpine:latest";

    // Test image exists (might not exist initially)
    let exists_initially = runtime.image_exists(image_ref).await.unwrap();
    println!("Image {} exists initially: {}", image_ref, exists_initially);

    // Try to get image (may fail if not present)
    if exists_initially {
        let image = runtime.get_image(image_ref).await.unwrap();
        assert!(!image.id().is_empty());
        println!("Image ID: {}", image.id());
        println!("Image size: {} bytes", image.size());
    }

    // Test list images
    let filter = vpn_runtime::ImageFilter::default();
    let images = runtime.list_images(filter).await.unwrap();
    println!("Found {} images", images.len());

    // Note: We don't test pull_image or remove_image as they require
    // network access and might affect other tests
}

/// Test volume operations
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_volume_operations() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping test - containerd not available");
            return;
        }
    };

    let volume_name = "test-volume";
    let mut labels = HashMap::new();
    labels.insert("test".to_string(), "true".to_string());

    let volume_spec = vpn_runtime::VolumeSpec {
        name: volume_name.to_string(),
        driver: "overlayfs".to_string(),
        driver_opts: HashMap::new(),
        labels,
    };

    // Test volume creation
    let volume = runtime.create_volume(volume_spec).await.unwrap();
    assert_eq!(volume.name(), volume_name);

    // Test volume exists
    assert!(runtime.volume_exists(volume_name).await.unwrap());

    // Test get volume
    let retrieved = runtime.get_volume(volume_name).await.unwrap();
    assert_eq!(retrieved.name(), volume_name);

    // Test list volumes
    let filter = vpn_runtime::VolumeFilter {
        names: vec![volume_name.to_string()],
        ..Default::default()
    };
    let volumes = runtime.list_volumes(filter).await.unwrap();
    assert_eq!(volumes.len(), 1);

    // Test backup volume
    let backup_name = "test-volume-backup";
    runtime.backup_volume(volume_name, backup_name).await.unwrap();
    assert!(runtime.volume_exists(backup_name).await.unwrap());

    // Clean up
    runtime.remove_volume(volume_name, false).await.unwrap();
    runtime.remove_volume(backup_name, false).await.unwrap();
    
    assert!(!runtime.volume_exists(volume_name).await.unwrap());
    assert!(!runtime.volume_exists(backup_name).await.unwrap());
}

/// Test error handling
#[tokio::test]
#[ignore] // Requires actual containerd running
async fn test_error_handling() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping test - containerd not available");
            return;
        }
    };

    // Test non-existent container
    let result = runtime.get_container("non-existent-container").await;
    assert!(result.is_err());
    
    match result.unwrap_err() {
        vpn_runtime::RuntimeError::ContainerNotFound { id } => {
            assert_eq!(id, "non-existent-container");
        }
        _ => panic!("Expected ContainerNotFound error"),
    }

    // Test non-existent image
    let result = runtime.get_image("non-existent:image").await;
    assert!(result.is_err());

    // Test non-existent volume
    let result = runtime.get_volume("non-existent-volume").await;
    assert!(result.is_err());
}

/// Benchmark test for performance comparison
#[tokio::test]
#[ignore] // Requires actual containerd running and is slow
async fn benchmark_container_operations() {
    let config = create_test_config();
    let runtime = match ContainerdRuntime::connect(config).await {
        Ok(rt) => rt,
        Err(_) => {
            println!("Skipping benchmark - containerd not available");
            return;
        }
    };

    let num_containers = 10;
    let container_names: Vec<String> = (0..num_containers)
        .map(|i| format!("benchmark-container-{}", i))
        .collect();

    // Benchmark container creation
    let start = std::time::Instant::now();
    for name in &container_names {
        let spec = create_test_container_spec(name);
        runtime.create_container(spec).await.unwrap();
    }
    let creation_time = start.elapsed();
    println!("Created {} containers in {:?}", num_containers, creation_time);
    println!("Average creation time: {:?}", creation_time / num_containers);

    // Benchmark batch start
    let start = std::time::Instant::now();
    let batch_options = vpn_runtime::BatchOptions {
        max_concurrent: 5,
        timeout: std::time::Duration::from_secs(30),
        fail_fast: false,
    };
    
    let _result = runtime.batch_start_containers(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        batch_options.clone()
    ).await.unwrap();
    let start_time = start.elapsed();
    println!("Started {} containers in {:?}", num_containers, start_time);

    // Benchmark batch stop
    let start = std::time::Instant::now();
    let _result = runtime.batch_stop_containers(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        None,
        batch_options.clone()
    ).await.unwrap();
    let stop_time = start.elapsed();
    println!("Stopped {} containers in {:?}", num_containers, stop_time);

    // Clean up
    let _result = runtime.batch_remove_containers(
        &container_names.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        false,
        batch_options
    ).await.unwrap();

    println!("Benchmark completed successfully");
}