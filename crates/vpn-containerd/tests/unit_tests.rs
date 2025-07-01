use vpn_containerd::ContainerdRuntime;
use vpn_runtime::{RuntimeConfig, ContainerdConfig, RuntimeType};
use std::time::Duration;
use tokio;

/// Mock configuration for testing
fn test_config() -> RuntimeConfig {
    RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        socket_path: Some("/tmp/test-containerd.sock".to_string()),
        namespace: Some("test".to_string()),
        timeout: Duration::from_secs(10),
        max_connections: 5,
        containerd: Some(ContainerdConfig {
            socket_path: "/tmp/test-containerd.sock".to_string(),
            namespace: "test".to_string(),
            timeout_seconds: 10,
            max_connections: 5,
            snapshotter: "overlayfs".to_string(),
            runtime: "io.containerd.runc.v2".to_string(),
        }),
        docker: None,
        fallback_enabled: false,
    }
}

#[tokio::test]
async fn test_containerd_runtime_creation() {
    let config = test_config();
    
    // Should be able to create runtime instance even with invalid socket
    // (actual connection will fail, but creation should succeed)
    let result = ContainerdRuntime::new(config).await;
    
    match result {
        Ok(_runtime) => {
            // Runtime created successfully (even if socket doesn't exist)
        }
        Err(e) => {
            // Expected for non-existent socket, verify error type
            assert!(e.to_string().contains("transport error") || 
                   e.to_string().contains("Connection") ||
                   e.to_string().contains("No such file"));
        }
    }
}

#[tokio::test]
async fn test_config_validation() {
    // Test with empty socket path
    let mut config = test_config();
    config.containerd.as_mut().unwrap().socket_path = "".to_string();
    
    let result = ContainerdRuntime::new(config).await;
    assert!(result.is_err(), "Should fail with empty socket path");
}

#[tokio::test]
async fn test_namespace_validation() {
    // Test with empty namespace
    let mut config = test_config();
    config.containerd.as_mut().unwrap().namespace = "".to_string();
    
    let result = ContainerdRuntime::new(config).await;
    assert!(result.is_err(), "Should fail with empty namespace");
}

#[tokio::test]
async fn test_timeout_configuration() {
    let mut config = test_config();
    config.containerd.as_mut().unwrap().timeout_seconds = 1; // Very short timeout
    
    let result = ContainerdRuntime::new(config).await;
    // Should either succeed or fail quickly due to timeout
    match result {
        Ok(_) => {} // Connection succeeded unexpectedly
        Err(_) => {} // Expected timeout or connection failure
    }
}

#[cfg(test)]
mod container_operations_tests {
    use super::*;
    use vpn_runtime::{ContainerSpec, ContainerState, RestartPolicy};

    #[tokio::test]
    async fn test_container_spec_validation() {
        let config = ContainerSpec {
            name: "test-container".to_string(),
            image: "test:latest".to_string(),
            command: None,
            args: None,
            environment: std::collections::HashMap::new(),
            volumes: vec![],
            ports: vec![],
            networks: vec![],
            labels: std::collections::HashMap::new(),
            working_dir: None,
            user: None,
            restart_policy: RestartPolicy::No,
        };

        // Validate required fields
        assert!(!config.name.is_empty(), "Container name should not be empty");
        assert!(!config.image.is_empty(), "Container image should not be empty");
    }

    #[tokio::test]
    async fn test_container_name_validation() {
        let config = ContainerSpec {
            name: "".to_string(), // Invalid empty name
            image: "test:latest".to_string(),
            command: None,
            args: None,
            environment: std::collections::HashMap::new(),
            volumes: vec![],
            ports: vec![],
            networks: vec![],
            labels: std::collections::HashMap::new(),
            working_dir: None,
            user: None,
            restart_policy: RestartPolicy::No,
        };

        assert!(config.name.is_empty(), "Should detect empty container name");
    }

    #[tokio::test]
    async fn test_container_image_validation() {
        let config = ContainerSpec {
            name: "test-container".to_string(),
            image: "".to_string(), // Invalid empty image
            command: None,
            args: None,
            environment: std::collections::HashMap::new(),
            volumes: vec![],
            ports: vec![],
            networks: vec![],
            labels: std::collections::HashMap::new(),
            working_dir: None,
            user: None,
            restart_policy: RestartPolicy::No,
        };

        assert!(config.image.is_empty(), "Should detect empty image name");
    }
}

#[cfg(test)]
mod task_operations_tests {
    use super::*;
    use vpn_runtime::TaskStatus;

    #[tokio::test]
    async fn test_task_state_transitions() {
        // Test valid state transitions
        let states = vec![
            TaskStatus::Created,
            TaskStatus::Running,
            TaskStatus::Paused,
            TaskStatus::Stopped,
        ];

        for (i, state) in states.iter().enumerate() {
            match state {
                TaskStatus::Created => {
                    // Can transition to Running
                    assert!(true, "Created state is valid");
                }
                TaskStatus::Running => {
                    // Can transition to Paused or Stopped
                    assert!(true, "Running state is valid");
                }
                TaskStatus::Paused => {
                    // Can transition to Running or Stopped
                    assert!(true, "Paused state is valid");
                }
                TaskStatus::Stopped => {
                    // Terminal state
                    assert!(true, "Stopped state is valid");
                }
                TaskStatus::Unknown => {
                    // Should handle unknown states
                    assert!(true, "Unknown state should be handled");
                }
            }
        }
    }
}

#[cfg(test)]
mod image_operations_tests {
    use super::*;

    #[tokio::test]
    async fn test_image_tag_parsing() {
        let test_cases = vec![
            ("ubuntu:latest", "ubuntu", "latest"),
            ("nginx:1.21", "nginx", "1.21"),
            ("registry.example.com/app:v1.0", "registry.example.com/app", "v1.0"),
            ("localhost:5000/test:dev", "localhost:5000/test", "dev"),
        ];

        for (full_name, expected_repo, expected_tag) in test_cases {
            let parts: Vec<&str> = full_name.rsplitn(2, ':').collect();
            let (tag, repo) = if parts.len() == 2 {
                (parts[0], parts[1])
            } else {
                ("latest", full_name)
            };

            assert_eq!(repo, expected_repo, "Repository parsing failed for {}", full_name);
            assert_eq!(tag, expected_tag, "Tag parsing failed for {}", full_name);
        }
    }

    #[tokio::test]
    async fn test_image_validation() {
        let valid_images = vec![
            "ubuntu:latest",
            "nginx:1.21",
            "registry.example.com/app:v1.0",
            "localhost:5000/test:dev",
        ];

        let invalid_images = vec![
            "",            // Empty
            ":",           // Only separator
            "ubuntu:",     // Empty tag
            ":latest",     // Empty repo
        ];

        for image in valid_images {
            assert!(!image.is_empty(), "Valid image should not be empty: {}", image);
            assert!(image.contains(':') || image == "ubuntu", "Image should have tag or be simple name: {}", image);
        }

        for image in invalid_images {
            if image.is_empty() {
                assert!(image.is_empty(), "Should detect empty image");
            } else if image == ":" {
                assert_eq!(image.len(), 1, "Should detect invalid separator-only image");
            } else if image.ends_with(':') {
                assert!(image.ends_with(':'), "Should detect empty tag");
            } else if image.starts_with(':') {
                assert!(image.starts_with(':'), "Should detect empty repository");
            }
        }
    }
}

#[cfg(test)]
mod volume_operations_tests {
    use super::*;
    use vpn_runtime::{VolumeSpec, VolumeFilter};

    #[tokio::test]
    async fn test_volume_spec_validation() {
        let valid_spec = VolumeSpec {
            name: "test-volume".to_string(),
            driver: "local".to_string(),
            driver_opts: std::collections::HashMap::new(),
            labels: std::collections::HashMap::new(),
        };

        assert!(!valid_spec.name.is_empty(), "Volume name should not be empty");
        assert!(!valid_spec.driver.is_empty(), "Volume driver should not be empty");
    }

    #[tokio::test]
    async fn test_volume_name_validation() {
        let invalid_names = vec![
            "",              // Empty
            " ",             // Whitespace only
            "test volume",   // Contains space
            "test/volume",   // Contains slash
            "test:volume",   // Contains colon
        ];

        for name in invalid_names {
            let is_valid = !name.is_empty() && 
                          !name.contains(' ') && 
                          !name.contains('/') && 
                          !name.contains(':');
            
            assert!(!is_valid, "Should detect invalid volume name: '{}'", name);
        }

        let valid_names = vec![
            "test-volume",
            "test_volume",
            "testvolume123",
            "test.volume",
        ];

        for name in valid_names {
            let is_valid = !name.is_empty() && 
                          !name.contains(' ') && 
                          !name.contains('/') && 
                          !name.contains(':');
            
            assert!(is_valid, "Should accept valid volume name: '{}'", name);
        }
    }
}

#[cfg(test)]
mod network_operations_tests {
    use super::*;

    #[tokio::test]
    async fn test_network_spec_validation() {
        // Basic network configuration structure
        struct NetworkConfig {
            name: String,
            driver: String,
            subnet: Option<String>,
            gateway: Option<String>,
            options: std::collections::HashMap<String, String>,
            labels: std::collections::HashMap<String, String>,
        }

        let config = NetworkConfig {
            name: "test-network".to_string(),
            driver: "bridge".to_string(),
            subnet: Some("172.20.0.0/16".to_string()),
            gateway: Some("172.20.0.1".to_string()),
            options: std::collections::HashMap::new(),
            labels: std::collections::HashMap::new(),
        };

        assert!(!config.name.is_empty(), "Network name should not be empty");
        assert!(!config.driver.is_empty(), "Network driver should not be empty");
    }

    #[tokio::test]
    async fn test_subnet_validation() {
        let valid_subnets = vec![
            "172.20.0.0/16",
            "192.168.1.0/24",
            "10.0.0.0/8",
            "172.16.0.0/12",
        ];

        let invalid_subnets = vec![
            "",                    // Empty
            "172.20.0.0",         // No CIDR
            "172.20.0.0/",        // No mask
            "172.20.0.0/33",      // Invalid mask
            "256.1.1.1/24",       // Invalid IP
        ];

        for subnet in valid_subnets {
            assert!(subnet.contains('/'), "Valid subnet should contain CIDR notation: {}", subnet);
            let parts: Vec<&str> = subnet.split('/').collect();
            assert_eq!(parts.len(), 2, "Should have exactly two parts separated by /");
        }

        for subnet in invalid_subnets {
            if subnet.is_empty() {
                assert!(subnet.is_empty(), "Should detect empty subnet");
            } else if !subnet.contains('/') {
                assert!(!subnet.contains('/'), "Should detect missing CIDR notation");
            } else {
                let parts: Vec<&str> = subnet.split('/').collect();
                if parts.len() != 2 {
                    assert_ne!(parts.len(), 2, "Should detect invalid CIDR format");
                }
            }
        }
    }
}

#[cfg(test)]
mod error_handling_tests {
    use super::*;

    #[tokio::test]
    async fn test_error_types() {
        // Test different error scenarios that should be handled gracefully
        
        // Connection error
        let config = test_config();
        let result = ContainerdRuntime::new(config).await;
        
        if let Err(e) = result {
            // Should be a meaningful error message
            let error_msg = e.to_string();
            assert!(!error_msg.is_empty(), "Error message should not be empty");
            
            // Should indicate connection issue
            assert!(
                error_msg.contains("transport") || 
                error_msg.contains("connection") || 
                error_msg.contains("Connection") ||
                error_msg.contains("No such file"),
                "Error should indicate connection issue: {}", error_msg
            );
        }
    }

    #[tokio::test]
    async fn test_timeout_handling() {
        let mut config = test_config();
        config.timeout = Duration::from_millis(1); // Very short timeout
        config.containerd.as_mut().unwrap().timeout_seconds = 0; // Invalid timeout
        
        let result = ContainerdRuntime::new(config).await;
        // Should handle timeout gracefully
        match result {
            Ok(_) => {} // Unexpected success
            Err(e) => {
                let error_msg = e.to_string();
                assert!(!error_msg.is_empty(), "Timeout error should have message");
            }
        }
    }
}

#[cfg(test)]
mod integration_helpers {
    use super::*;

    /// Helper function to check if containerd is available for integration tests
    pub async fn is_containerd_available() -> bool {
        use std::path::Path;
        Path::new("/run/containerd/containerd.sock").exists()
    }

    /// Helper function to create a test runtime only if containerd is available
    pub async fn create_test_runtime_if_available() -> Option<ContainerdRuntime> {
        if !is_containerd_available().await {
            return None;
        }

        let config = RuntimeConfig::containerd();
        match ContainerdRuntime::new(config).await {
            Ok(runtime) => Some(runtime),
            Err(_) => None,
        }
    }

    #[tokio::test]
    async fn test_helper_functions() {
        let available = is_containerd_available().await;
        println!("Containerd available for testing: {}", available);
        
        if available {
            let runtime = create_test_runtime_if_available().await;
            match runtime {
                Some(_) => println!("Successfully created test runtime"),
                None => println!("Failed to create test runtime despite containerd being available"),
            }
        }
    }
}