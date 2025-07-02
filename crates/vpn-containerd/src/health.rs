use crate::{ContainerdError, Result};
use chrono::{DateTime, Utc};
use futures_util::Stream;
use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;
use tokio::time::interval;
use tonic::transport::Channel;
use tracing::{debug, info};

/// Health status of a container
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub enum HealthStatus {
    Healthy,
    Unhealthy,
    Starting,
    Unknown,
}

impl std::fmt::Display for HealthStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HealthStatus::Healthy => write!(f, "healthy"),
            HealthStatus::Unhealthy => write!(f, "unhealthy"),
            HealthStatus::Starting => write!(f, "starting"),
            HealthStatus::Unknown => write!(f, "unknown"),
        }
    }
}

/// Health check configuration
#[derive(Debug, Clone)]
pub struct HealthCheckConfig {
    pub enabled: bool,
    pub interval: Duration,
    pub timeout: Duration,
    pub retries: u32,
    pub start_period: Duration,
    pub command: Option<Vec<String>>,
    pub http_endpoint: Option<String>,
    pub tcp_port: Option<u16>,
}

impl Default for HealthCheckConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            interval: Duration::from_secs(30),
            timeout: Duration::from_secs(10),
            retries: 3,
            start_period: Duration::from_secs(60),
            command: None,
            http_endpoint: None,
            tcp_port: None,
        }
    }
}

/// Health check result
#[derive(Debug, Clone)]
pub struct HealthCheckResult {
    pub container_id: String,
    pub status: HealthStatus,
    pub timestamp: DateTime<Utc>,
    pub output: String,
    pub exit_code: Option<i32>,
    pub duration: Duration,
    pub error: Option<String>,
}

/// Health metrics for a container
#[derive(Debug, Clone, serde::Serialize)]
pub struct HealthMetrics {
    pub container_id: String,
    pub current_status: HealthStatus,
    pub consecutive_failures: u32,
    pub total_checks: u64,
    pub total_failures: u64,
    pub last_success: Option<DateTime<Utc>>,
    pub last_failure: Option<DateTime<Utc>>,
    pub average_response_time: Duration,
    pub uptime: Duration,
}

impl Default for HealthMetrics {
    fn default() -> Self {
        Self {
            container_id: String::new(),
            current_status: HealthStatus::Unknown,
            consecutive_failures: 0,
            total_checks: 0,
            total_failures: 0,
            last_success: None,
            last_failure: None,
            average_response_time: Duration::from_secs(0),
            uptime: Duration::from_secs(0),
        }
    }
}

/// Health monitor for containerd containers
pub struct HealthMonitor {
    channel: Channel,
    namespace: String,
    configs: HashMap<String, HealthCheckConfig>,
    metrics: HashMap<String, HealthMetrics>,
    monitoring_active: bool,
}

impl HealthMonitor {
    pub fn new(channel: Channel, namespace: String) -> Self {
        Self {
            channel,
            namespace,
            configs: HashMap::new(),
            metrics: HashMap::new(),
            monitoring_active: false,
        }
    }

    /// Add health check configuration for a container
    pub fn add_health_check(&mut self, container_id: String, config: HealthCheckConfig) {
        debug!("Adding health check for container: {}", container_id);
        self.configs.insert(container_id.clone(), config);
        
        // Initialize metrics
        let mut metrics = HealthMetrics::default();
        metrics.container_id = container_id.clone();
        self.metrics.insert(container_id, metrics);
    }

    /// Remove health check for a container
    pub fn remove_health_check(&mut self, container_id: &str) {
        debug!("Removing health check for container: {}", container_id);
        self.configs.remove(container_id);
        self.metrics.remove(container_id);
    }

    /// Get health status for a container
    pub fn get_health_status(&self, container_id: &str) -> Option<HealthStatus> {
        self.metrics.get(container_id).map(|m| m.current_status.clone())
    }

    /// Get health metrics for a container
    pub fn get_health_metrics(&self, container_id: &str) -> Option<&HealthMetrics> {
        self.metrics.get(container_id)
    }

    /// Get health metrics for all monitored containers
    pub fn get_all_health_metrics(&self) -> &HashMap<String, HealthMetrics> {
        &self.metrics
    }

    /// Perform a single health check for a container
    pub async fn check_container_health(&mut self, container_id: &str) -> Result<HealthCheckResult> {
        let config = self.configs.get(container_id)
            .ok_or_else(|| ContainerdError::OperationFailed {
                operation: "health_check".to_string(),
                message: format!("No health check configured for container: {}", container_id),
            })?;

        if !config.enabled {
            return Ok(HealthCheckResult {
                container_id: container_id.to_string(),
                status: HealthStatus::Unknown,
                timestamp: Utc::now(),
                output: "Health check disabled".to_string(),
                exit_code: None,
                duration: Duration::from_secs(0),
                error: None,
            });
        }

        let start_time = std::time::Instant::now();
        let timestamp = Utc::now();

        // First, check if container is running
        let basic_status = self.check_basic_container_status(container_id).await?;
        if basic_status != HealthStatus::Healthy {
            return Ok(HealthCheckResult {
                container_id: container_id.to_string(),
                status: basic_status,
                timestamp,
                output: "Container not running".to_string(),
                exit_code: None,
                duration: start_time.elapsed(),
                error: None,
            });
        }

        // Perform specific health check based on configuration
        let check_result = if let Some(command) = &config.command {
            self.check_command_health(container_id, command, config.timeout).await
        } else if let Some(endpoint) = &config.http_endpoint {
            self.check_http_health(container_id, endpoint, config.timeout).await
        } else if let Some(port) = config.tcp_port {
            self.check_tcp_health(container_id, port, config.timeout).await
        } else {
            // Default: check if container is just running
            Ok(HealthCheckResult {
                container_id: container_id.to_string(),
                status: HealthStatus::Healthy,
                timestamp,
                output: "Container is running".to_string(),
                exit_code: Some(0),
                duration: start_time.elapsed(),
                error: None,
            })
        };

        // Update metrics
        if let Ok(ref result) = check_result {
            self.update_metrics(container_id, result);
        }

        check_result
    }

    /// Check basic container status (is it running?)
    async fn check_basic_container_status(&self, container_id: &str) -> Result<HealthStatus> {
        use containerd_client::services::v1::{
            containers_client::ContainersClient,
            tasks_client::TasksClient,
            GetContainerRequest,
            GetRequest,
        };

        // Check if container exists
        let mut containers_client = ContainersClient::new(self.channel.clone());
        let container_request = GetContainerRequest {
            id: container_id.to_string(),
        };

        match containers_client.get(container_request).await {
            Ok(_) => {
                // Container exists, now check if task is running
                let mut tasks_client = TasksClient::new(self.channel.clone());
                let task_request = GetRequest {
                    container_id: container_id.to_string(),
                    exec_id: String::new(),
                };

                match tasks_client.get(task_request).await {
                    Ok(response) => {
                        let _task = response.get_ref();
                        // For now, if we can get the task, assume it's healthy
                        // In a real implementation, you'd check the actual status field
                        Ok(HealthStatus::Healthy)
                    }
                    Err(_) => Ok(HealthStatus::Unhealthy), // No task means not running
                }
            }
            Err(_) => Ok(HealthStatus::Unhealthy), // Container doesn't exist
        }
    }

    /// Perform command-based health check
    async fn check_command_health(
        &self,
        container_id: &str,
        command: &[String],
        _timeout: Duration,
    ) -> Result<HealthCheckResult> {
        use containerd_client::services::v1::{
            tasks_client::TasksClient,
            ExecProcessRequest,
        };

        debug!("Running command health check for container: {} with command: {:?}", container_id, command);

        let start_time = std::time::Instant::now();
        let timestamp = Utc::now();

        // This is a simplified implementation
        // In a real implementation, you would execute the command in the container
        let _tasks_client = TasksClient::new(self.channel.clone());
        
        let _exec_request = ExecProcessRequest {
            container_id: container_id.to_string(),
            stdin: String::new(),
            stdout: String::new(),
            stderr: String::new(),
            terminal: false,
            spec: None, // Would contain the ProcessSpec with the command
            exec_id: format!("health-check-{}", Utc::now().timestamp()),
        };

        // For now, return a placeholder result
        // In a real implementation, you would execute the command and capture output
        Ok(HealthCheckResult {
            container_id: container_id.to_string(),
            status: HealthStatus::Healthy,
            timestamp,
            output: "Command health check not fully implemented yet".to_string(),
            exit_code: Some(0),
            duration: start_time.elapsed(),
            error: None,
        })
    }

    /// Perform HTTP-based health check
    async fn check_http_health(
        &self,
        container_id: &str,
        endpoint: &str,
        timeout: Duration,
    ) -> Result<HealthCheckResult> {
        debug!("Running HTTP health check for container: {} at endpoint: {}", container_id, endpoint);

        let start_time = std::time::Instant::now();
        let timestamp = Utc::now();

        // Create HTTP client with timeout
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(|e| ContainerdError::OperationFailed {
                operation: "http_health_check".to_string(),
                message: format!("Failed to create HTTP client: {}", e),
            })?;

        // Perform HTTP request
        match client.get(endpoint).send().await {
            Ok(response) => {
                let status_code = response.status().as_u16();
                let is_healthy = status_code >= 200 && status_code < 300;
                
                Ok(HealthCheckResult {
                    container_id: container_id.to_string(),
                    status: if is_healthy { HealthStatus::Healthy } else { HealthStatus::Unhealthy },
                    timestamp,
                    output: format!("HTTP {} {}", status_code, response.status().canonical_reason().unwrap_or("Unknown")),
                    exit_code: Some(if is_healthy { 0 } else { 1 }),
                    duration: start_time.elapsed(),
                    error: None,
                })
            }
            Err(e) => {
                Ok(HealthCheckResult {
                    container_id: container_id.to_string(),
                    status: HealthStatus::Unhealthy,
                    timestamp,
                    output: "HTTP request failed".to_string(),
                    exit_code: Some(1),
                    duration: start_time.elapsed(),
                    error: Some(e.to_string()),
                })
            }
        }
    }

    /// Perform TCP-based health check
    async fn check_tcp_health(
        &self,
        container_id: &str,
        port: u16,
        _timeout: Duration,
    ) -> Result<HealthCheckResult> {
        debug!("Running TCP health check for container: {} on port: {}", container_id, port);

        let start_time = std::time::Instant::now();
        let timestamp = Utc::now();

        // For now, just return a placeholder
        // In a real implementation, you would try to connect to the port
        // This requires knowing the container's IP address
        
        Ok(HealthCheckResult {
            container_id: container_id.to_string(),
            status: HealthStatus::Healthy,
            timestamp,
            output: format!("TCP check on port {} (simplified implementation)", port),
            exit_code: Some(0),
            duration: start_time.elapsed(),
            error: None,
        })
    }

    /// Update health metrics based on check result
    fn update_metrics(&mut self, container_id: &str, result: &HealthCheckResult) {
        if let Some(metrics) = self.metrics.get_mut(container_id) {
            metrics.total_checks += 1;
            
            // Update response time average
            let total_duration = metrics.average_response_time * (metrics.total_checks - 1) as u32 + result.duration;
            metrics.average_response_time = total_duration / metrics.total_checks as u32;
            
            match result.status {
                HealthStatus::Healthy => {
                    metrics.consecutive_failures = 0;
                    metrics.last_success = Some(result.timestamp);
                    metrics.current_status = HealthStatus::Healthy;
                }
                HealthStatus::Unhealthy => {
                    metrics.consecutive_failures += 1;
                    metrics.total_failures += 1;
                    metrics.last_failure = Some(result.timestamp);
                    metrics.current_status = HealthStatus::Unhealthy;
                }
                _ => {
                    metrics.current_status = result.status.clone();
                }
            }
            
            debug!("Updated health metrics for {}: status={}, consecutive_failures={}, total_checks={}", 
                   container_id, metrics.current_status, metrics.consecutive_failures, metrics.total_checks);
        }
    }

    /// Start continuous monitoring for all configured containers
    pub async fn start_monitoring(&mut self) -> Result<Pin<Box<dyn Stream<Item = Result<HealthCheckResult>> + Send>>> {
        self.monitoring_active = true;
        info!("Starting health monitoring for {} containers", self.configs.len());

        let _container_ids: Vec<String> = self.configs.keys().cloned().collect();
        let configs = self.configs.clone();
        let channel = self.channel.clone();
        let namespace = self.namespace.clone();

        let stream = async_stream::stream! {
            let mut intervals: HashMap<String, tokio::time::Interval> = HashMap::new();
            
            // Create intervals for each container
            for (container_id, config) in &configs {
                if config.enabled {
                    let mut interval = interval(config.interval);
                    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                    intervals.insert(container_id.clone(), interval);
                }
            }

            // Simple implementation: check all containers in sequence
            loop {
                for (container_id, interval) in &mut intervals {
                    // Wait for interval tick
                    interval.tick().await;
                    
                    // Create a temporary monitor for this check
                    let mut monitor = HealthMonitor::new(channel.clone(), namespace.clone());
                    monitor.configs = configs.clone();
                    
                    match monitor.check_container_health(container_id).await {
                        Ok(result) => yield Ok(result),
                        Err(e) => yield Err(e),
                    }
                }
            }
        };

        Ok(Box::pin(stream))
    }

    /// Stop monitoring
    pub fn stop_monitoring(&mut self) {
        self.monitoring_active = false;
        info!("Stopped health monitoring");
    }

    /// Check if monitoring is active
    pub fn is_monitoring_active(&self) -> bool {
        self.monitoring_active
    }

    /// Get summary of all container health statuses
    pub fn get_health_summary(&self) -> HashMap<String, HealthStatus> {
        self.metrics.iter()
            .map(|(id, metrics)| (id.clone(), metrics.current_status.clone()))
            .collect()
    }

    /// Get containers that are currently unhealthy
    pub fn get_unhealthy_containers(&self) -> Vec<String> {
        self.metrics.iter()
            .filter(|(_, metrics)| metrics.current_status == HealthStatus::Unhealthy)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Get containers with consecutive failures above threshold
    pub fn get_failing_containers(&self, threshold: u32) -> Vec<String> {
        self.metrics.iter()
            .filter(|(_, metrics)| metrics.consecutive_failures >= threshold)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Reset metrics for a container
    pub fn reset_metrics(&mut self, container_id: &str) {
        if let Some(metrics) = self.metrics.get_mut(container_id) {
            *metrics = HealthMetrics {
                container_id: container_id.to_string(),
                ..Default::default()
            };
            info!("Reset health metrics for container: {}", container_id);
        }
    }

    /// Export metrics as JSON
    pub fn export_metrics_json(&self) -> Result<String> {
        serde_json::to_string_pretty(&self.metrics)
            .map_err(|e| ContainerdError::JsonError(e))
    }
}

/// Health check builder for easy configuration
pub struct HealthCheckBuilder {
    config: HealthCheckConfig,
}

impl HealthCheckBuilder {
    pub fn new() -> Self {
        Self {
            config: HealthCheckConfig::default(),
        }
    }

    pub fn interval(mut self, interval: Duration) -> Self {
        self.config.interval = interval;
        self
    }

    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.config.timeout = timeout;
        self
    }

    pub fn retries(mut self, retries: u32) -> Self {
        self.config.retries = retries;
        self
    }

    pub fn command<S: Into<String>>(mut self, command: Vec<S>) -> Self {
        self.config.command = Some(command.into_iter().map(|s| s.into()).collect());
        self
    }

    pub fn http_endpoint<S: Into<String>>(mut self, endpoint: S) -> Self {
        self.config.http_endpoint = Some(endpoint.into());
        self
    }

    pub fn tcp_port(mut self, port: u16) -> Self {
        self.config.tcp_port = Some(port);
        self
    }

    pub fn disabled(mut self) -> Self {
        self.config.enabled = false;
        self
    }

    pub fn build(self) -> HealthCheckConfig {
        self.config
    }
}

impl Default for HealthCheckBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_status_display() {
        assert_eq!(format!("{}", HealthStatus::Healthy), "healthy");
        assert_eq!(format!("{}", HealthStatus::Unhealthy), "unhealthy");
        assert_eq!(format!("{}", HealthStatus::Starting), "starting");
        assert_eq!(format!("{}", HealthStatus::Unknown), "unknown");
    }

    #[test]
    fn test_health_check_config_default() {
        let config = HealthCheckConfig::default();
        assert!(config.enabled);
        assert_eq!(config.interval, Duration::from_secs(30));
        assert_eq!(config.timeout, Duration::from_secs(10));
        assert_eq!(config.retries, 3);
    }

    #[test]
    fn test_health_check_builder() {
        let config = HealthCheckBuilder::new()
            .interval(Duration::from_secs(60))
            .timeout(Duration::from_secs(5))
            .retries(2)
            .http_endpoint("http://localhost:8080/health")
            .build();

        assert_eq!(config.interval, Duration::from_secs(60));
        assert_eq!(config.timeout, Duration::from_secs(5));
        assert_eq!(config.retries, 2);
        assert_eq!(config.http_endpoint, Some("http://localhost:8080/health".to_string()));
    }

    #[test]
    fn test_health_metrics_default() {
        let metrics = HealthMetrics::default();
        assert_eq!(metrics.current_status, HealthStatus::Unknown);
        assert_eq!(metrics.consecutive_failures, 0);
        assert_eq!(metrics.total_checks, 0);
        assert_eq!(metrics.total_failures, 0);
    }
}