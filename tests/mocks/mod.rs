//! Mock implementations for external dependencies
//! 
//! This module provides mock implementations for external services and dependencies
//! to enable isolated testing of the VPN system components.

pub mod docker_mock;
pub mod network_mock;
pub mod auth_mock;
pub mod database_mock;

use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use async_trait::async_trait;

/// Mock state manager for tracking mock service state across tests
#[derive(Debug, Default)]
pub struct MockState {
    pub docker_containers: HashMap<String, MockContainer>,
    pub network_interfaces: HashMap<String, MockNetworkInterface>,
    pub auth_sessions: HashMap<String, MockAuthSession>,
    pub database_records: HashMap<String, serde_json::Value>,
    pub call_counts: HashMap<String, usize>,
}

impl MockState {
    pub fn new() -> Arc<Mutex<Self>> {
        Arc::new(Mutex::new(Self::default()))
    }

    pub fn increment_call_count(&mut self, method: &str) {
        *self.call_counts.entry(method.to_string()).or_insert(0) += 1;
    }

    pub fn get_call_count(&self, method: &str) -> usize {
        self.call_counts.get(method).copied().unwrap_or(0)
    }

    pub fn reset(&mut self) {
        self.docker_containers.clear();
        self.network_interfaces.clear();
        self.auth_sessions.clear();
        self.database_records.clear();
        self.call_counts.clear();
    }
}

/// Mock container representation
#[derive(Debug, Clone)]
pub struct MockContainer {
    pub id: String,
    pub name: String,
    pub image: String,
    pub status: String,
    pub ports: Vec<u16>,
    pub environment: HashMap<String, String>,
    pub volumes: HashMap<String, String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub health_status: String,
}

impl MockContainer {
    pub fn new(name: &str, image: &str) -> Self {
        Self {
            id: format!("mock_container_{}", rand::random::<u32>()),
            name: name.to_string(),
            image: image.to_string(),
            status: "running".to_string(),
            ports: vec![],
            environment: HashMap::new(),
            volumes: HashMap::new(),
            created_at: chrono::Utc::now(),
            health_status: "healthy".to_string(),
        }
    }

    pub fn with_status(mut self, status: &str) -> Self {
        self.status = status.to_string();
        self
    }

    pub fn with_port(mut self, port: u16) -> Self {
        self.ports.push(port);
        self
    }

    pub fn with_env(mut self, key: &str, value: &str) -> Self {
        self.environment.insert(key.to_string(), value.to_string());
        self
    }
}

/// Mock network interface representation
#[derive(Debug, Clone)]
pub struct MockNetworkInterface {
    pub name: String,
    pub ip_address: String,
    pub subnet: String,
    pub gateway: String,
    pub status: String,
    pub mtu: u16,
}

impl MockNetworkInterface {
    pub fn new(name: &str, ip: &str) -> Self {
        Self {
            name: name.to_string(),
            ip_address: ip.to_string(),
            subnet: "192.168.1.0/24".to_string(),
            gateway: "192.168.1.1".to_string(),
            status: "up".to_string(),
            mtu: 1500,
        }
    }
}

/// Mock authentication session
#[derive(Debug, Clone)]
pub struct MockAuthSession {
    pub session_id: String,
    pub user_id: String,
    pub username: String,
    pub roles: Vec<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
    pub active: bool,
}

impl MockAuthSession {
    pub fn new(user_id: &str, username: &str) -> Self {
        let now = chrono::Utc::now();
        Self {
            session_id: format!("session_{}", rand::random::<u32>()),
            user_id: user_id.to_string(),
            username: username.to_string(),
            roles: vec!["user".to_string()],
            created_at: now,
            expires_at: now + chrono::Duration::hours(24),
            active: true,
        }
    }

    pub fn with_roles(mut self, roles: Vec<String>) -> Self {
        self.roles = roles;
        self
    }

    pub fn is_expired(&self) -> bool {
        chrono::Utc::now() > self.expires_at
    }
}

/// Trait for mockable services
#[async_trait]
pub trait MockService: Send + Sync {
    /// Initialize the mock service
    async fn initialize(&mut self) -> Result<(), MockError>;
    
    /// Reset the mock service to initial state
    async fn reset(&mut self) -> Result<(), MockError>;
    
    /// Get service health status
    async fn health_check(&self) -> Result<bool, MockError>;
    
    /// Get mock statistics
    fn get_stats(&self) -> MockStats;
}

/// Mock service error type
#[derive(Debug, thiserror::Error)]
pub enum MockError {
    #[error("Mock service not initialized")]
    NotInitialized,
    
    #[error("Mock operation failed: {0}")]
    OperationFailed(String),
    
    #[error("Mock resource not found: {0}")]
    ResourceNotFound(String),
    
    #[error("Mock network error: {0}")]
    NetworkError(String),
    
    #[error("Mock authentication error: {0}")]
    AuthError(String),
    
    #[error("Mock database error: {0}")]
    DatabaseError(String),
}

/// Mock service statistics
#[derive(Debug, Clone)]
pub struct MockStats {
    pub total_calls: usize,
    pub successful_calls: usize,
    pub failed_calls: usize,
    pub average_response_time_ms: f64,
    pub last_call_timestamp: Option<chrono::DateTime<chrono::Utc>>,
}

impl Default for MockStats {
    fn default() -> Self {
        Self {
            total_calls: 0,
            successful_calls: 0,
            failed_calls: 0,
            average_response_time_ms: 0.0,
            last_call_timestamp: None,
        }
    }
}

impl MockStats {
    pub fn success_rate(&self) -> f64 {
        if self.total_calls == 0 {
            0.0
        } else {
            self.successful_calls as f64 / self.total_calls as f64
        }
    }
}

/// Mock configuration for controlling mock behavior
#[derive(Debug, Clone)]
pub struct MockConfig {
    pub failure_rate: f64,           // 0.0-1.0, probability of operations failing
    pub latency_ms: u64,             // Artificial latency to simulate network delays
    pub max_concurrent_operations: usize, // Limit concurrent operations
    pub enable_chaos: bool,          // Enable random failures and delays
    pub log_calls: bool,             // Log all mock calls for debugging
}

impl Default for MockConfig {
    fn default() -> Self {
        Self {
            failure_rate: 0.0,
            latency_ms: 0,
            max_concurrent_operations: 100,
            enable_chaos: false,
            log_calls: false,
        }
    }
}

impl MockConfig {
    pub fn with_failure_rate(mut self, rate: f64) -> Self {
        self.failure_rate = rate.clamp(0.0, 1.0);
        self
    }

    pub fn with_latency(mut self, latency_ms: u64) -> Self {
        self.latency_ms = latency_ms;
        self
    }

    pub fn with_chaos(mut self) -> Self {
        self.enable_chaos = true;
        self.failure_rate = 0.1; // 10% failure rate in chaos mode
        self.latency_ms = 100;   // 100ms latency in chaos mode
        self
    }

    pub fn with_logging(mut self) -> Self {
        self.log_calls = true;
        self
    }
}

/// Base mock service implementation with common functionality
pub struct BaseMockService {
    pub config: MockConfig,
    pub stats: MockStats,
    pub initialized: bool,
    pub state: Arc<Mutex<MockState>>,
}

impl BaseMockService {
    pub fn new(config: MockConfig, state: Arc<Mutex<MockState>>) -> Self {
        Self {
            config,
            stats: MockStats::default(),
            initialized: false,
            state,
        }
    }

    /// Simulate operation with configured latency and failure rate
    pub async fn simulate_operation(&mut self, operation_name: &str) -> Result<(), MockError> {
        self.stats.total_calls += 1;
        self.stats.last_call_timestamp = Some(chrono::Utc::now());

        if self.config.log_calls {
            println!("Mock: Executing {}", operation_name);
        }

        // Simulate latency
        if self.config.latency_ms > 0 {
            tokio::time::sleep(std::time::Duration::from_millis(self.config.latency_ms)).await;
        }

        // Simulate chaos engineering failures
        if self.config.enable_chaos && rand::random::<f64>() < 0.05 {
            // 5% chance of chaos failure in chaos mode
            self.stats.failed_calls += 1;
            return Err(MockError::OperationFailed(format!("Chaos failure in {}", operation_name)));
        }

        // Simulate configured failure rate
        if rand::random::<f64>() < self.config.failure_rate {
            self.stats.failed_calls += 1;
            return Err(MockError::OperationFailed(format!("Simulated failure in {}", operation_name)));
        }

        // Track call count in shared state
        if let Ok(mut state) = self.state.lock() {
            state.increment_call_count(operation_name);
        }

        self.stats.successful_calls += 1;
        Ok(())
    }

    pub fn update_average_response_time(&mut self, response_time_ms: f64) {
        if self.stats.total_calls == 1 {
            self.stats.average_response_time_ms = response_time_ms;
        } else {
            // Calculate running average
            let total_time = self.stats.average_response_time_ms * (self.stats.total_calls - 1) as f64;
            self.stats.average_response_time_ms = (total_time + response_time_ms) / self.stats.total_calls as f64;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mock_state_creation() {
        let state = MockState::new();
        let state_guard = state.lock().unwrap();
        assert_eq!(state_guard.get_call_count("test"), 0);
    }

    #[test]
    fn test_mock_container_creation() {
        let container = MockContainer::new("test-container", "nginx:latest")
            .with_status("running")
            .with_port(80)
            .with_env("ENV_VAR", "value");

        assert_eq!(container.name, "test-container");
        assert_eq!(container.image, "nginx:latest");
        assert_eq!(container.status, "running");
        assert_eq!(container.ports, vec![80]);
        assert_eq!(container.environment.get("ENV_VAR"), Some(&"value".to_string()));
    }

    #[test]
    fn test_mock_auth_session() {
        let session = MockAuthSession::new("user123", "testuser")
            .with_roles(vec!["admin".to_string(), "user".to_string()]);

        assert_eq!(session.user_id, "user123");
        assert_eq!(session.username, "testuser");
        assert!(session.roles.contains(&"admin".to_string()));
        assert!(!session.is_expired());
    }

    #[test]
    fn test_mock_config_builder() {
        let config = MockConfig::default()
            .with_failure_rate(0.1)
            .with_latency(50)
            .with_chaos()
            .with_logging();

        assert_eq!(config.failure_rate, 0.1);
        assert_eq!(config.latency_ms, 100); // Chaos mode overrides
        assert!(config.enable_chaos);
        assert!(config.log_calls);
    }

    #[test]
    fn test_mock_stats() {
        let mut stats = MockStats::default();
        stats.total_calls = 10;
        stats.successful_calls = 8;
        stats.failed_calls = 2;

        assert_eq!(stats.success_rate(), 0.8);
    }

    #[tokio::test]
    async fn test_base_mock_service() {
        let state = MockState::new();
        let config = MockConfig::default().with_failure_rate(0.0); // No failures
        let mut service = BaseMockService::new(config, state.clone());

        let result = service.simulate_operation("test_op").await;
        assert!(result.is_ok());
        assert_eq!(service.stats.total_calls, 1);
        assert_eq!(service.stats.successful_calls, 1);

        let state_guard = state.lock().unwrap();
        assert_eq!(state_guard.get_call_count("test_op"), 1);
    }

    #[tokio::test]
    async fn test_base_mock_service_with_failures() {
        let state = MockState::new();
        let config = MockConfig::default().with_failure_rate(1.0); // Always fail
        let mut service = BaseMockService::new(config, state);

        let result = service.simulate_operation("test_op").await;
        assert!(result.is_err());
        assert_eq!(service.stats.total_calls, 1);
        assert_eq!(service.stats.failed_calls, 1);
    }
}