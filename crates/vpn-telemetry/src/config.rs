//! Telemetry configuration module

use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Configuration for the telemetry system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TelemetryConfig {
    /// Whether telemetry is enabled
    pub enabled: bool,

    /// Service name for tracing
    pub service_name: String,

    /// Service version
    pub service_version: String,

    /// Environment (e.g., "production", "staging", "development")
    pub environment: String,

    /// Tracing configuration
    pub tracing: TracingConfig,

    /// Metrics configuration
    pub metrics: MetricsConfig,

    /// Dashboard configuration
    pub dashboard: DashboardConfig,

    /// Whether to enable the built-in dashboard
    pub dashboard_enabled: bool,

    /// Health monitoring configuration
    pub health: HealthConfig,

    /// Performance monitoring configuration
    pub performance: PerformanceConfig,
}

/// Tracing configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TracingConfig {
    /// Whether tracing is enabled
    pub enabled: bool,

    /// Jaeger configuration
    pub jaeger: Option<JaegerConfig>,

    /// OTLP configuration
    pub otlp: Option<OtlpConfig>,

    /// Sampling ratio (0.0 to 1.0)
    pub sampling_ratio: f32,

    /// Maximum span batch size
    pub max_batch_size: usize,

    /// Maximum export timeout
    pub export_timeout: Duration,
}

/// Jaeger configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JaegerConfig {
    /// Jaeger endpoint URL
    pub endpoint: String,

    /// Agent endpoint (for UDP)
    pub agent_endpoint: Option<String>,

    /// Username for authentication
    pub username: Option<String>,

    /// Password for authentication
    pub password: Option<String>,
}

/// OTLP configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OtlpConfig {
    /// OTLP endpoint URL
    pub endpoint: String,

    /// Headers to include in requests
    pub headers: std::collections::HashMap<String, String>,

    /// Timeout for OTLP requests
    pub timeout: Duration,
}

/// Metrics configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    /// Whether metrics collection is enabled
    pub enabled: bool,

    /// Prometheus configuration
    pub prometheus: PrometheusConfig,

    /// Collection interval
    pub collection_interval: Duration,

    /// Custom metrics to collect
    pub custom_metrics: Vec<CustomMetricConfig>,
}

/// Prometheus configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrometheusConfig {
    /// Whether Prometheus metrics are enabled
    pub enabled: bool,

    /// Address to bind the metrics server to
    pub bind_address: String,

    /// Port for the metrics server
    pub port: u16,

    /// Path for metrics endpoint
    pub path: String,
}

/// Custom metric configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomMetricConfig {
    /// Metric name
    pub name: String,

    /// Metric description
    pub description: String,

    /// Metric type (counter, gauge, histogram)
    pub metric_type: MetricType,

    /// Labels to apply to the metric
    pub labels: Vec<String>,
}

/// Metric types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
}

/// Dashboard configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DashboardConfig {
    /// Dashboard bind address
    pub bind_address: String,

    /// Dashboard port
    pub port: u16,

    /// Dashboard title
    pub title: String,

    /// Refresh interval for real-time updates
    pub refresh_interval: Duration,

    /// Whether to enable authentication
    pub auth_enabled: bool,

    /// Username for basic auth
    pub username: Option<String>,

    /// Password for basic auth
    pub password: Option<String>,
}

/// Health monitoring configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthConfig {
    /// Whether health monitoring is enabled
    pub enabled: bool,

    /// Health check interval
    pub check_interval: Duration,

    /// Components to monitor
    pub components: Vec<String>,

    /// Thresholds for health alerts
    pub thresholds: HealthThresholds,
}

/// Health thresholds
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthThresholds {
    /// CPU usage threshold (percentage)
    pub cpu_threshold: f64,

    /// Memory usage threshold (percentage)
    pub memory_threshold: f64,

    /// Disk usage threshold (percentage)
    pub disk_threshold: f64,

    /// Network error rate threshold (percentage)
    pub network_error_threshold: f64,
}

/// Performance monitoring configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceConfig {
    /// Whether performance monitoring is enabled
    pub enabled: bool,

    /// Performance data collection interval
    pub collection_interval: Duration,

    /// Number of samples to keep in memory
    pub sample_size: usize,

    /// Whether to enable benchmark comparison
    pub benchmark_enabled: bool,
}

impl Default for TelemetryConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            service_name: "vpn-system".to_string(),
            service_version: "0.1.0".to_string(),
            environment: "development".to_string(),
            tracing: TracingConfig::default(),
            metrics: MetricsConfig::default(),
            dashboard: DashboardConfig::default(),
            dashboard_enabled: true,
            health: HealthConfig::default(),
            performance: PerformanceConfig::default(),
        }
    }
}

impl Default for TracingConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            jaeger: Some(JaegerConfig::default()),
            otlp: None,
            sampling_ratio: 1.0, // Sample all traces in development
            max_batch_size: 512,
            export_timeout: Duration::from_secs(30),
        }
    }
}

impl Default for JaegerConfig {
    fn default() -> Self {
        Self {
            endpoint: "http://localhost:14268/api/traces".to_string(),
            agent_endpoint: Some("localhost:6831".to_string()),
            username: None,
            password: None,
        }
    }
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            prometheus: PrometheusConfig::default(),
            collection_interval: Duration::from_secs(10),
            custom_metrics: vec![],
        }
    }
}

impl Default for PrometheusConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            bind_address: "0.0.0.0".to_string(),
            port: 9090,
            path: "/metrics".to_string(),
        }
    }
}

impl Default for DashboardConfig {
    fn default() -> Self {
        Self {
            bind_address: "0.0.0.0".to_string(),
            port: 8080,
            title: "VPN System Telemetry".to_string(),
            refresh_interval: Duration::from_secs(5),
            auth_enabled: false,
            username: None,
            password: None,
        }
    }
}

impl Default for HealthConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            check_interval: Duration::from_secs(30),
            components: vec![
                "docker".to_string(),
                "containerd".to_string(),
                "users".to_string(),
                "server".to_string(),
            ],
            thresholds: HealthThresholds::default(),
        }
    }
}

impl Default for HealthThresholds {
    fn default() -> Self {
        Self {
            cpu_threshold: 80.0,
            memory_threshold: 85.0,
            disk_threshold: 90.0,
            network_error_threshold: 5.0,
        }
    }
}

impl Default for PerformanceConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            collection_interval: Duration::from_secs(60),
            sample_size: 1000,
            benchmark_enabled: true,
        }
    }
}

impl TelemetryConfig {
    /// Load configuration from a file
    pub fn from_file(path: &str) -> crate::Result<Self> {
        let content =
            std::fs::read_to_string(path).map_err(|e| crate::TelemetryError::ConfigError {
                message: format!("Failed to read config file: {}", e),
            })?;

        toml::from_str(&content).map_err(|e| crate::TelemetryError::ConfigError {
            message: format!("Failed to parse config: {}", e),
        })
    }

    /// Save configuration to a file
    pub fn to_file(&self, path: &str) -> crate::Result<()> {
        let content =
            toml::to_string_pretty(self).map_err(|e| crate::TelemetryError::ConfigError {
                message: format!("Failed to serialize config: {}", e),
            })?;

        std::fs::write(path, content).map_err(|e| crate::TelemetryError::ConfigError {
            message: format!("Failed to write config file: {}", e),
        })?;

        Ok(())
    }

    /// Validate the configuration
    pub fn validate(&self) -> crate::Result<()> {
        if self.service_name.is_empty() {
            return Err(crate::TelemetryError::ConfigError {
                message: "Service name cannot be empty".to_string(),
            });
        }

        if self.tracing.enabled && self.tracing.jaeger.is_none() && self.tracing.otlp.is_none() {
            return Err(crate::TelemetryError::ConfigError {
                message: "At least one tracing exporter must be configured when tracing is enabled"
                    .to_string(),
            });
        }

        if self.tracing.sampling_ratio < 0.0 || self.tracing.sampling_ratio > 1.0 {
            return Err(crate::TelemetryError::ConfigError {
                message: "Sampling ratio must be between 0.0 and 1.0".to_string(),
            });
        }

        if self.dashboard_enabled && self.dashboard.port == 0 {
            return Err(crate::TelemetryError::ConfigError {
                message: "Dashboard port must be specified when dashboard is enabled".to_string(),
            });
        }

        Ok(())
    }
}

/// Environment variable names for configuration
pub mod env {
    pub const TELEMETRY_ENABLED: &str = "VPN_TELEMETRY_ENABLED";
    pub const SERVICE_NAME: &str = "VPN_SERVICE_NAME";
    pub const SERVICE_VERSION: &str = "VPN_SERVICE_VERSION";
    pub const ENVIRONMENT: &str = "VPN_ENVIRONMENT";
    pub const JAEGER_ENDPOINT: &str = "VPN_JAEGER_ENDPOINT";
    pub const PROMETHEUS_PORT: &str = "VPN_PROMETHEUS_PORT";
    pub const DASHBOARD_PORT: &str = "VPN_DASHBOARD_PORT";
}

/// Load configuration from environment variables
pub fn from_env() -> TelemetryConfig {
    let mut config = TelemetryConfig::default();

    if let Ok(enabled) = std::env::var(env::TELEMETRY_ENABLED) {
        config.enabled = enabled.parse().unwrap_or(true);
    }

    if let Ok(service_name) = std::env::var(env::SERVICE_NAME) {
        config.service_name = service_name;
    }

    if let Ok(service_version) = std::env::var(env::SERVICE_VERSION) {
        config.service_version = service_version;
    }

    if let Ok(environment) = std::env::var(env::ENVIRONMENT) {
        config.environment = environment;
    }

    if let Ok(jaeger_endpoint) = std::env::var(env::JAEGER_ENDPOINT) {
        if let Some(ref mut jaeger) = config.tracing.jaeger {
            jaeger.endpoint = jaeger_endpoint;
        }
    }

    if let Ok(prometheus_port) = std::env::var(env::PROMETHEUS_PORT) {
        if let Ok(port) = prometheus_port.parse() {
            config.metrics.prometheus.port = port;
        }
    }

    if let Ok(dashboard_port) = std::env::var(env::DASHBOARD_PORT) {
        if let Ok(port) = dashboard_port.parse() {
            config.dashboard.port = port;
        }
    }

    config
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = TelemetryConfig::default();
        assert!(config.enabled);
        assert_eq!(config.service_name, "vpn-system");
        assert!(config.tracing.enabled);
        assert!(config.metrics.enabled);
    }

    #[test]
    fn test_config_validation() {
        let mut config = TelemetryConfig::default();
        assert!(config.validate().is_ok());

        config.service_name = String::new();
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_config_serialization() {
        let config = TelemetryConfig::default();
        let serialized = toml::to_string(&config).unwrap();
        let deserialized: TelemetryConfig = toml::from_str(&serialized).unwrap();
        assert_eq!(config.service_name, deserialized.service_name);
    }
}
