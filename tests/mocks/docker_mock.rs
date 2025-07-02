//! Mock implementation for Docker operations

use super::{MockService, MockError, MockStats, MockConfig, BaseMockService, MockState, MockContainer};
use async_trait::async_trait;
use std::sync::{Arc, Mutex};
use std::collections::HashMap;

/// Mock Docker service for testing Docker operations without actual Docker daemon
pub struct MockDockerService {
    base: BaseMockService,
    containers: HashMap<String, MockContainer>,
    images: Vec<String>,
    networks: Vec<String>,
    volumes: Vec<String>,
}

impl MockDockerService {
    pub fn new(config: MockConfig, state: Arc<Mutex<MockState>>) -> Self {
        let mut service = Self {
            base: BaseMockService::new(config, state),
            containers: HashMap::new(),
            images: vec![
                "nginx:latest".to_string(),
                "xray:latest".to_string(),
                "postgres:15".to_string(),
                "redis:7-alpine".to_string(),
            ],
            networks: vec!["default".to_string(), "vpn-network".to_string()],
            volumes: vec!["vpn-data".to_string(), "postgres-data".to_string()],
        };

        // Pre-populate with some mock containers
        service.add_mock_container("vpn-server", "xray:latest", "running");
        service.add_mock_container("vpn-proxy", "nginx:latest", "running");
        service.add_mock_container("vpn-db", "postgres:15", "running");

        service
    }

    fn add_mock_container(&mut self, name: &str, image: &str, status: &str) {
        let container = MockContainer::new(name, image).with_status(status);
        self.containers.insert(container.id.clone(), container.clone());
        
        // Also store in shared state
        if let Ok(mut state) = self.base.state.lock() {
            state.docker_containers.insert(container.id.clone(), container);
        }
    }

    /// Create a new container
    pub async fn create_container(&mut self, name: &str, image: &str, config: ContainerCreateConfig) -> Result<String, MockError> {
        self.base.simulate_operation("create_container").await?;

        if !self.images.contains(&image.to_string()) {
            return Err(MockError::ResourceNotFound(format!("Image not found: {}", image)));
        }

        let mut container = MockContainer::new(name, image)
            .with_status("created");

        // Apply configuration
        for port in config.ports {
            container = container.with_port(port);
        }

        for (key, value) in config.environment {
            container = container.with_env(&key, &value);
        }

        let container_id = container.id.clone();
        self.containers.insert(container_id.clone(), container.clone());

        if let Ok(mut state) = self.base.state.lock() {
            state.docker_containers.insert(container_id.clone(), container);
        }

        Ok(container_id)
    }

    /// Start a container
    pub async fn start_container(&mut self, container_id: &str) -> Result<(), MockError> {
        self.base.simulate_operation("start_container").await?;

        if let Some(container) = self.containers.get_mut(container_id) {
            container.status = "running".to_string();
            
            // Update shared state
            if let Ok(mut state) = self.base.state.lock() {
                if let Some(shared_container) = state.docker_containers.get_mut(container_id) {
                    shared_container.status = "running".to_string();
                }
            }
            
            Ok(())
        } else {
            Err(MockError::ResourceNotFound(format!("Container not found: {}", container_id)))
        }
    }

    /// Stop a container
    pub async fn stop_container(&mut self, container_id: &str, timeout: Option<u64>) -> Result<(), MockError> {
        self.base.simulate_operation("stop_container").await?;

        // Simulate timeout delay
        if let Some(timeout_secs) = timeout {
            tokio::time::sleep(std::time::Duration::from_millis(timeout_secs * 10)).await; // Scaled down for testing
        }

        if let Some(container) = self.containers.get_mut(container_id) {
            container.status = "stopped".to_string();
            
            // Update shared state
            if let Ok(mut state) = self.base.state.lock() {
                if let Some(shared_container) = state.docker_containers.get_mut(container_id) {
                    shared_container.status = "stopped".to_string();
                }
            }
            
            Ok(())
        } else {
            Err(MockError::ResourceNotFound(format!("Container not found: {}", container_id)))
        }
    }

    /// Remove a container
    pub async fn remove_container(&mut self, container_id: &str, force: bool) -> Result<(), MockError> {
        self.base.simulate_operation("remove_container").await?;

        if let Some(container) = self.containers.get(container_id) {
            if container.status == "running" && !force {
                return Err(MockError::OperationFailed("Cannot remove running container without force".to_string()));
            }

            self.containers.remove(container_id);
            
            // Update shared state
            if let Ok(mut state) = self.base.state.lock() {
                state.docker_containers.remove(container_id);
            }
            
            Ok(())
        } else {
            Err(MockError::ResourceNotFound(format!("Container not found: {}", container_id)))
        }
    }

    /// List containers
    pub async fn list_containers(&mut self, all: bool) -> Result<Vec<MockContainer>, MockError> {
        self.base.simulate_operation("list_containers").await?;

        let containers: Vec<MockContainer> = if all {
            self.containers.values().cloned().collect()
        } else {
            self.containers.values()
                .filter(|c| c.status == "running")
                .cloned()
                .collect()
        };

        Ok(containers)
    }

    /// Get container details
    pub async fn inspect_container(&mut self, container_id: &str) -> Result<MockContainer, MockError> {
        self.base.simulate_operation("inspect_container").await?;

        self.containers.get(container_id)
            .cloned()
            .ok_or_else(|| MockError::ResourceNotFound(format!("Container not found: {}", container_id)))
    }

    /// Execute command in container
    pub async fn exec_in_container(&mut self, container_id: &str, command: &[&str]) -> Result<String, MockError> {
        self.base.simulate_operation("exec_in_container").await?;

        if !self.containers.contains_key(container_id) {
            return Err(MockError::ResourceNotFound(format!("Container not found: {}", container_id)));
        }

        // Simulate command execution
        let output = match command.get(0) {
            Some(&"echo") => command.get(1).unwrap_or(&"").to_string(),
            Some(&"ps") => "PID COMMAND\n1   /usr/bin/xray\n".to_string(),
            Some(&"ls") => "bin  etc  usr  var\n".to_string(),
            Some(&"cat") => {
                if command.get(1) == Some(&"/proc/version") {
                    "Linux version 5.4.0 (mock)".to_string()
                } else {
                    "mock file content".to_string()
                }
            },
            _ => format!("mock output for: {}", command.join(" ")),
        };

        Ok(output)
    }

    /// Get container logs
    pub async fn get_container_logs(&mut self, container_id: &str, tail: Option<usize>) -> Result<String, MockError> {
        self.base.simulate_operation("get_container_logs").await?;

        if !self.containers.contains_key(container_id) {
            return Err(MockError::ResourceNotFound(format!("Container not found: {}", container_id)));
        }

        let mut logs = vec![
            "2025-07-01T10:00:00Z [INFO] Container started",
            "2025-07-01T10:00:01Z [INFO] Service initialized",
            "2025-07-01T10:00:02Z [INFO] Ready to accept connections",
            "2025-07-01T10:01:00Z [DEBUG] Health check passed",
            "2025-07-01T10:02:00Z [INFO] Processing request",
        ];

        if let Some(tail_count) = tail {
            logs = logs.into_iter().rev().take(tail_count).rev().collect();
        }

        Ok(logs.join("\n"))
    }

    /// Get container statistics
    pub async fn get_container_stats(&mut self, container_id: &str) -> Result<ContainerStats, MockError> {
        self.base.simulate_operation("get_container_stats").await?;

        if !self.containers.contains_key(container_id) {
            return Err(MockError::ResourceNotFound(format!("Container not found: {}", container_id)));
        }

        Ok(ContainerStats {
            cpu_usage_percent: 5.0 + rand::random::<f64>() * 10.0, // 5-15%
            memory_usage_bytes: 50 * 1024 * 1024 + (rand::random::<u64>() % (100 * 1024 * 1024)), // 50-150MB
            memory_limit_bytes: 512 * 1024 * 1024, // 512MB
            network_rx_bytes: rand::random::<u64>() % (1024 * 1024), // 0-1MB
            network_tx_bytes: rand::random::<u64>() % (1024 * 1024), // 0-1MB
            block_read_bytes: rand::random::<u64>() % (10 * 1024 * 1024), // 0-10MB
            block_write_bytes: rand::random::<u64>() % (5 * 1024 * 1024), // 0-5MB
            pids: 1 + rand::random::<u64>() % 10, // 1-10 processes
        })
    }

    /// Pull an image
    pub async fn pull_image(&mut self, image: &str) -> Result<(), MockError> {
        self.base.simulate_operation("pull_image").await?;

        // Simulate pull time
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;

        if !self.images.contains(&image.to_string()) {
            self.images.push(image.to_string());
        }

        Ok(())
    }

    /// List images
    pub async fn list_images(&mut self) -> Result<Vec<String>, MockError> {
        self.base.simulate_operation("list_images").await?;
        Ok(self.images.clone())
    }

    /// Create a network
    pub async fn create_network(&mut self, name: &str) -> Result<String, MockError> {
        self.base.simulate_operation("create_network").await?;

        let network_id = format!("net_{}", rand::random::<u32>());
        self.networks.push(name.to_string());
        
        Ok(network_id)
    }

    /// List networks
    pub async fn list_networks(&mut self) -> Result<Vec<String>, MockError> {
        self.base.simulate_operation("list_networks").await?;
        Ok(self.networks.clone())
    }
}

#[async_trait]
impl MockService for MockDockerService {
    async fn initialize(&mut self) -> Result<(), MockError> {
        self.base.initialized = true;
        println!("Mock Docker service initialized");
        Ok(())
    }

    async fn reset(&mut self) -> Result<(), MockError> {
        self.containers.clear();
        self.base.stats = MockStats::default();
        
        // Reset shared state
        if let Ok(mut state) = self.base.state.lock() {
            state.docker_containers.clear();
        }
        
        // Re-add default containers
        self.add_mock_container("vpn-server", "xray:latest", "running");
        self.add_mock_container("vpn-proxy", "nginx:latest", "running");
        self.add_mock_container("vpn-db", "postgres:15", "running");
        
        Ok(())
    }

    async fn health_check(&self) -> Result<bool, MockError> {
        Ok(self.base.initialized)
    }

    fn get_stats(&self) -> MockStats {
        self.base.stats.clone()
    }
}

/// Container creation configuration
#[derive(Debug, Clone)]
pub struct ContainerCreateConfig {
    pub ports: Vec<u16>,
    pub environment: HashMap<String, String>,
    pub volumes: HashMap<String, String>,
    pub network: Option<String>,
    pub restart_policy: Option<String>,
}

impl Default for ContainerCreateConfig {
    fn default() -> Self {
        Self {
            ports: vec![],
            environment: HashMap::new(),
            volumes: HashMap::new(),
            network: None,
            restart_policy: None,
        }
    }
}

/// Container statistics
#[derive(Debug, Clone)]
pub struct ContainerStats {
    pub cpu_usage_percent: f64,
    pub memory_usage_bytes: u64,
    pub memory_limit_bytes: u64,
    pub network_rx_bytes: u64,
    pub network_tx_bytes: u64,
    pub block_read_bytes: u64,
    pub block_write_bytes: u64,
    pub pids: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_docker_service_creation() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockDockerService::new(config, state);

        assert!(!service.base.initialized);
        assert!(!service.containers.is_empty()); // Pre-populated containers

        let init_result = service.initialize().await;
        assert!(init_result.is_ok());
        assert!(service.base.initialized);
    }

    #[tokio::test]
    async fn test_container_lifecycle() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockDockerService::new(config, state);
        service.initialize().await.unwrap();

        // Create container
        let container_config = ContainerCreateConfig {
            ports: vec![8080],
            environment: [("ENV_VAR".to_string(), "value".to_string())].into(),
            ..Default::default()
        };

        let container_id = service.create_container("test-container", "nginx:latest", container_config).await.unwrap();
        assert!(!container_id.is_empty());

        // Start container
        let start_result = service.start_container(&container_id).await;
        assert!(start_result.is_ok());

        // Check container status
        let container = service.inspect_container(&container_id).await.unwrap();
        assert_eq!(container.status, "running");

        // Stop container
        let stop_result = service.stop_container(&container_id, Some(5)).await;
        assert!(stop_result.is_ok());

        // Check stopped status
        let container = service.inspect_container(&container_id).await.unwrap();
        assert_eq!(container.status, "stopped");

        // Remove container
        let remove_result = service.remove_container(&container_id, false).await;
        assert!(remove_result.is_ok());

        // Verify removal
        let inspect_result = service.inspect_container(&container_id).await;
        assert!(inspect_result.is_err());
    }

    #[tokio::test]
    async fn test_container_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockDockerService::new(config, state);
        service.initialize().await.unwrap();

        // List containers
        let containers = service.list_containers(true).await.unwrap();
        assert!(!containers.is_empty());

        // Get stats for first container
        let first_container = &containers[0];
        let stats = service.get_container_stats(&first_container.id).await.unwrap();
        assert!(stats.cpu_usage_percent >= 0.0);
        assert!(stats.memory_usage_bytes > 0);

        // Get logs
        let logs = service.get_container_logs(&first_container.id, Some(3)).await.unwrap();
        assert!(!logs.is_empty());

        // Execute command
        let output = service.exec_in_container(&first_container.id, &["echo", "hello"]).await.unwrap();
        assert_eq!(output, "hello");
    }

    #[tokio::test]
    async fn test_image_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockDockerService::new(config, state);
        service.initialize().await.unwrap();

        // List images
        let images = service.list_images().await.unwrap();
        assert!(!images.is_empty());

        // Pull new image
        let pull_result = service.pull_image("alpine:latest").await;
        assert!(pull_result.is_ok());

        // Verify image was added
        let updated_images = service.list_images().await.unwrap();
        assert!(updated_images.contains(&"alpine:latest".to_string()));
    }

    #[tokio::test]
    async fn test_network_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockDockerService::new(config, state);
        service.initialize().await.unwrap();

        // List networks
        let networks = service.list_networks().await.unwrap();
        assert!(!networks.is_empty());

        // Create network
        let network_id = service.create_network("test-network").await.unwrap();
        assert!(!network_id.is_empty());

        // Verify network was added
        let updated_networks = service.list_networks().await.unwrap();
        assert!(updated_networks.contains(&"test-network".to_string()));
    }

    #[tokio::test]
    async fn test_error_conditions() {
        let state = MockState::new();
        let config = MockConfig::default().with_failure_rate(1.0); // Always fail
        let mut service = MockDockerService::new(config, state);
        service.initialize().await.unwrap();

        // All operations should fail due to configured failure rate
        let result = service.list_containers(false).await;
        assert!(result.is_err());

        let result = service.create_container("test", "nginx", ContainerCreateConfig::default()).await;
        assert!(result.is_err());
    }
}