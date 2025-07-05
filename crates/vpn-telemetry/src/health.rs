//! Health monitoring and collection

use crate::{config::TelemetryConfig, error::Result, TelemetryError, TelemetryProvider};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Overall system health status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemHealth {
    pub overall_status: HealthStatus,
    pub components: HashMap<String, ComponentHealth>,
    pub last_check: chrono::DateTime<chrono::Utc>,
    pub uptime: Duration,
    pub system_metrics: SystemMetrics,
}

/// Health status levels
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthStatus {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

/// Component health information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentHealth {
    pub name: String,
    pub status: HealthStatus,
    pub message: String,
    pub last_check: chrono::DateTime<chrono::Utc>,
    pub response_time: Option<Duration>,
    pub metrics: HashMap<String, f64>,
    pub dependencies: Vec<String>,
}

/// System metrics for health monitoring
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub cpu_usage_percent: f64,
    pub memory_usage_percent: f64,
    pub disk_usage_percent: f64,
    pub load_average: f64,
    pub network_connections: u64,
    pub open_files: u64,
    pub process_count: u64,
}

/// Health check configuration for a component
#[derive(Debug, Clone)]
pub struct HealthCheckConfig {
    pub name: String,
    pub check_interval: Duration,
    pub timeout: Duration,
    pub retry_count: u32,
    pub critical_threshold: f64,
    pub warning_threshold: f64,
    pub enabled: bool,
}

/// Health collector that monitors system and component health
pub struct HealthCollector {
    config: TelemetryConfig,
    components: Arc<RwLock<HashMap<String, Box<dyn TelemetryProvider + Send + Sync>>>>,
    health_checks: Arc<RwLock<HashMap<String, HealthCheckConfig>>>,
    current_health: Arc<RwLock<SystemHealth>>,
    running: Arc<RwLock<bool>>,
    check_handles: Arc<RwLock<Vec<tokio::task::JoinHandle<()>>>>,
}

impl HealthCollector {
    /// Create a new health collector
    pub async fn new(config: &TelemetryConfig) -> Result<Self> {
        let current_health = SystemHealth {
            overall_status: HealthStatus::Unknown,
            components: HashMap::new(),
            last_check: chrono::Utc::now(),
            uptime: Duration::from_secs(0),
            system_metrics: SystemMetrics::default(),
        };

        Ok(Self {
            config: config.clone(),
            components: Arc::new(RwLock::new(HashMap::new())),
            health_checks: Arc::new(RwLock::new(HashMap::new())),
            current_health: Arc::new(RwLock::new(current_health)),
            running: Arc::new(RwLock::new(false)),
            check_handles: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// Register a component for health monitoring
    pub async fn register_component(
        &self,
        provider: Box<dyn TelemetryProvider + Send + Sync>,
        check_config: HealthCheckConfig,
    ) -> Result<()> {
        let component_name = provider.component_name().to_string();

        // Register the provider
        {
            let mut components = self.components.write().await;
            components.insert(component_name.clone(), provider);
        }

        // Register the health check configuration
        {
            let mut health_checks = self.health_checks.write().await;
            health_checks.insert(component_name.clone(), check_config);
        }

        info!(
            "Registered component for health monitoring: {}",
            component_name
        );
        Ok(())
    }

    /// Start health monitoring
    pub async fn start(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        *running = true;
        info!("Starting health monitoring");

        // Start health check tasks for each component
        let health_checks = self.health_checks.read().await.clone();
        let mut handles = Vec::new();

        for (component_name, check_config) in health_checks {
            if !check_config.enabled {
                continue;
            }

            let components = self.components.clone();
            let current_health = self.current_health.clone();
            let running_flag = self.running.clone();
            let config = self.config.clone();

            let handle = tokio::spawn(async move {
                Self::health_check_loop(
                    component_name,
                    check_config,
                    components,
                    current_health,
                    running_flag,
                    config,
                )
                .await;
            });

            handles.push(handle);
        }

        // Start system metrics collection
        let system_health = self.current_health.clone();
        let running_flag = self.running.clone();
        let system_interval = self.config.health.check_interval;

        let system_handle = tokio::spawn(async move {
            Self::system_metrics_loop(system_health, running_flag, system_interval).await;
        });

        handles.push(system_handle);

        *self.check_handles.write().await = handles;
        Ok(())
    }

    /// Stop health monitoring
    pub async fn stop(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        *running = false;

        // Cancel all health check tasks
        let mut handles = self.check_handles.write().await;
        for handle in handles.drain(..) {
            handle.abort();
        }

        info!("Health monitoring stopped");
        Ok(())
    }

    /// Get current system health
    pub async fn get_current_health(&self) -> Result<SystemHealth> {
        Ok(self.current_health.read().await.clone())
    }

    /// Health check loop for a specific component
    async fn health_check_loop(
        component_name: String,
        check_config: HealthCheckConfig,
        components: Arc<RwLock<HashMap<String, Box<dyn TelemetryProvider + Send + Sync>>>>,
        current_health: Arc<RwLock<SystemHealth>>,
        running: Arc<RwLock<bool>>,
        _config: TelemetryConfig,
    ) {
        let mut interval = tokio::time::interval(check_config.check_interval);

        while *running.read().await {
            interval.tick().await;

            let check_result =
                Self::perform_component_health_check(&component_name, &check_config, &components)
                    .await;

            // Update the overall health status
            let mut health = current_health.write().await;
            match check_result {
                Ok(component_health) => {
                    health
                        .components
                        .insert(component_name.clone(), component_health);
                }
                Err(e) => {
                    warn!("Health check failed for {}: {}", component_name, e);
                    let failed_health = ComponentHealth {
                        name: component_name.clone(),
                        status: HealthStatus::Critical,
                        message: format!("Health check failed: {}", e),
                        last_check: chrono::Utc::now(),
                        response_time: None,
                        metrics: HashMap::new(),
                        dependencies: vec![],
                    };
                    health
                        .components
                        .insert(component_name.clone(), failed_health);
                }
            }

            // Update overall status based on component statuses
            health.overall_status = Self::calculate_overall_status(&health.components);
            health.last_check = chrono::Utc::now();
        }
    }

    /// Perform health check for a specific component
    async fn perform_component_health_check(
        component_name: &str,
        check_config: &HealthCheckConfig,
        components: &Arc<RwLock<HashMap<String, Box<dyn TelemetryProvider + Send + Sync>>>>,
    ) -> Result<ComponentHealth> {
        let start_time = Instant::now();

        let components_guard = components.read().await;
        let provider = components_guard.get(component_name).ok_or_else(|| {
            TelemetryError::HealthCheckError {
                component: component_name.to_string(),
                message: "Component not found".to_string(),
            }
        })?;

        // Perform health check with timeout
        let health_result =
            tokio::time::timeout(check_config.timeout, provider.get_health_status()).await;

        let response_time = start_time.elapsed();

        match health_result {
            Ok(Ok(is_healthy)) => {
                let status = if is_healthy {
                    HealthStatus::Healthy
                } else {
                    HealthStatus::Critical
                };

                // Get component metrics
                let metrics = match provider.get_telemetry_metrics().await {
                    Ok(metrics_value) => {
                        // Convert JSON value to metrics map
                        Self::extract_metrics_from_json(metrics_value)
                    }
                    Err(_) => HashMap::new(),
                };

                Ok(ComponentHealth {
                    name: component_name.to_string(),
                    status,
                    message: if is_healthy {
                        "OK".to_string()
                    } else {
                        "Unhealthy".to_string()
                    },
                    last_check: chrono::Utc::now(),
                    response_time: Some(response_time),
                    metrics,
                    dependencies: vec![], // Would be configured per component
                })
            }
            Ok(Err(e)) => Ok(ComponentHealth {
                name: component_name.to_string(),
                status: HealthStatus::Critical,
                message: format!("Health check error: {}", e),
                last_check: chrono::Utc::now(),
                response_time: Some(response_time),
                metrics: HashMap::new(),
                dependencies: vec![],
            }),
            Err(_) => Ok(ComponentHealth {
                name: component_name.to_string(),
                status: HealthStatus::Critical,
                message: format!("Health check timed out after {:?}", check_config.timeout),
                last_check: chrono::Utc::now(),
                response_time: Some(response_time),
                metrics: HashMap::new(),
                dependencies: vec![],
            }),
        }
    }

    /// Extract numeric metrics from JSON value
    fn extract_metrics_from_json(value: serde_json::Value) -> HashMap<String, f64> {
        let mut metrics = HashMap::new();

        fn extract_recursive(
            value: &serde_json::Value,
            prefix: &str,
            metrics: &mut HashMap<String, f64>,
        ) {
            match value {
                serde_json::Value::Number(n) => {
                    if let Some(f) = n.as_f64() {
                        metrics.insert(prefix.to_string(), f);
                    }
                }
                serde_json::Value::Object(obj) => {
                    for (key, val) in obj {
                        let new_prefix = if prefix.is_empty() {
                            key.clone()
                        } else {
                            format!("{}.{}", prefix, key)
                        };
                        extract_recursive(val, &new_prefix, metrics);
                    }
                }
                _ => {}
            }
        }

        extract_recursive(&value, "", &mut metrics);
        metrics
    }

    /// Calculate overall system status based on component statuses
    fn calculate_overall_status(components: &HashMap<String, ComponentHealth>) -> HealthStatus {
        if components.is_empty() {
            return HealthStatus::Unknown;
        }

        let mut has_critical = false;
        let mut has_warning = false;

        for component in components.values() {
            match component.status {
                HealthStatus::Critical => has_critical = true,
                HealthStatus::Warning => has_warning = true,
                HealthStatus::Unknown => has_warning = true,
                HealthStatus::Healthy => {}
            }
        }

        if has_critical {
            HealthStatus::Critical
        } else if has_warning {
            HealthStatus::Warning
        } else {
            HealthStatus::Healthy
        }
    }

    /// System metrics collection loop
    async fn system_metrics_loop(
        current_health: Arc<RwLock<SystemHealth>>,
        running: Arc<RwLock<bool>>,
        interval: Duration,
    ) {
        let mut timer = tokio::time::interval(interval);

        while *running.read().await {
            timer.tick().await;

            if let Ok(system_metrics) = Self::collect_system_metrics().await {
                let mut health = current_health.write().await;
                health.system_metrics = system_metrics;
            }
        }
    }

    /// Collect system metrics
    async fn collect_system_metrics() -> Result<SystemMetrics> {
        // This is a simplified implementation
        // In a real implementation, you would use system APIs to collect actual metrics

        debug!("Collecting system metrics");

        Ok(SystemMetrics {
            cpu_usage_percent: 0.0,
            memory_usage_percent: 0.0,
            disk_usage_percent: 0.0,
            load_average: 0.0,
            network_connections: 0,
            open_files: 0,
            process_count: 0,
        })
    }
}

impl Default for SystemMetrics {
    fn default() -> Self {
        Self {
            cpu_usage_percent: 0.0,
            memory_usage_percent: 0.0,
            disk_usage_percent: 0.0,
            load_average: 0.0,
            network_connections: 0,
            open_files: 0,
            process_count: 0,
        }
    }
}

impl Default for HealthCheckConfig {
    fn default() -> Self {
        Self {
            name: "default".to_string(),
            check_interval: Duration::from_secs(30),
            timeout: Duration::from_secs(10),
            retry_count: 3,
            critical_threshold: 90.0,
            warning_threshold: 80.0,
            enabled: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::TelemetryConfig;

    struct MockTelemetryProvider {
        name: String,
        healthy: bool,
    }

    #[async_trait]
    impl TelemetryProvider for MockTelemetryProvider {
        async fn get_telemetry_metrics(&self) -> Result<serde_json::Value> {
            Ok(serde_json::json!({
                "cpu_usage": 45.5,
                "memory_usage": 1024,
                "connections": 10
            }))
        }

        async fn get_health_status(&self) -> Result<bool> {
            Ok(self.healthy)
        }

        fn component_name(&self) -> &str {
            &self.name
        }
    }

    #[tokio::test]
    async fn test_health_collector_creation() {
        let config = TelemetryConfig::default();
        let collector = HealthCollector::new(&config).await;
        assert!(collector.is_ok());
    }

    #[tokio::test]
    async fn test_component_registration() {
        let config = TelemetryConfig::default();
        let collector = HealthCollector::new(&config).await.unwrap();

        let provider = Box::new(MockTelemetryProvider {
            name: "test_component".to_string(),
            healthy: true,
        });

        let check_config = HealthCheckConfig {
            name: "test_component".to_string(),
            ..Default::default()
        };

        let result = collector.register_component(provider, check_config).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_metrics_extraction() {
        let json_value = serde_json::json!({
            "cpu": 45.5,
            "memory": {
                "usage": 1024,
                "total": 2048
            },
            "network": {
                "connections": 10,
                "bandwidth": {
                    "upload": 100.0,
                    "download": 200.0
                }
            }
        });

        let metrics = HealthCollector::extract_metrics_from_json(json_value);

        assert_eq!(metrics.get("cpu"), Some(&45.5));
        assert_eq!(metrics.get("memory.usage"), Some(&1024.0));
        assert_eq!(metrics.get("memory.total"), Some(&2048.0));
        assert_eq!(metrics.get("network.connections"), Some(&10.0));
        assert_eq!(metrics.get("network.bandwidth.upload"), Some(&100.0));
        assert_eq!(metrics.get("network.bandwidth.download"), Some(&200.0));
    }

    #[tokio::test]
    async fn test_overall_status_calculation() {
        let mut components = HashMap::new();

        // All healthy
        components.insert(
            "comp1".to_string(),
            ComponentHealth {
                name: "comp1".to_string(),
                status: HealthStatus::Healthy,
                message: "OK".to_string(),
                last_check: chrono::Utc::now(),
                response_time: None,
                metrics: HashMap::new(),
                dependencies: vec![],
            },
        );

        assert_eq!(
            HealthCollector::calculate_overall_status(&components),
            HealthStatus::Healthy
        );

        // Add warning
        components.insert(
            "comp2".to_string(),
            ComponentHealth {
                name: "comp2".to_string(),
                status: HealthStatus::Warning,
                message: "Warning".to_string(),
                last_check: chrono::Utc::now(),
                response_time: None,
                metrics: HashMap::new(),
                dependencies: vec![],
            },
        );

        assert_eq!(
            HealthCollector::calculate_overall_status(&components),
            HealthStatus::Warning
        );

        // Add critical
        components.insert(
            "comp3".to_string(),
            ComponentHealth {
                name: "comp3".to_string(),
                status: HealthStatus::Critical,
                message: "Critical".to_string(),
                last_check: chrono::Utc::now(),
                response_time: None,
                metrics: HashMap::new(),
                dependencies: vec![],
            },
        );

        assert_eq!(
            HealthCollector::calculate_overall_status(&components),
            HealthStatus::Critical
        );
    }
}
