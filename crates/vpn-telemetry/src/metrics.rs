//! Metrics collection and Prometheus integration

use crate::{config::TelemetryConfig, error::Result, TelemetryError};
use async_trait::async_trait;
use prometheus::{
    Counter, CounterVec, Encoder, Gauge, GaugeVec, Histogram, HistogramVec, Registry, TextEncoder,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// VPN-specific metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VpnMetrics {
    /// Number of active users
    pub active_users: u64,
    
    /// Number of active connections
    pub active_connections: u64,
    
    /// Total data transferred (bytes)
    pub total_data_transferred: u64,
    
    /// Current bandwidth usage (bytes/sec)
    pub current_bandwidth: f64,
    
    /// Container metrics
    pub containers: ContainerMetrics,
    
    /// Server metrics
    pub server: ServerMetrics,
    
    /// System metrics
    pub system: SystemMetrics,
    
    /// Custom metrics
    pub custom: HashMap<String, f64>,
}

/// Container-related metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerMetrics {
    /// Number of running containers
    pub running: u64,
    
    /// Number of stopped containers
    pub stopped: u64,
    
    /// Number of failed containers
    pub failed: u64,
    
    /// Total container starts
    pub total_starts: u64,
    
    /// Total container stops
    pub total_stops: u64,
    
    /// Average container start time (seconds)
    pub avg_start_time: f64,
    
    /// Container restart count
    pub restart_count: u64,
}

/// Server-related metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerMetrics {
    /// Server uptime (seconds)
    pub uptime: u64,
    
    /// Number of successful connections
    pub successful_connections: u64,
    
    /// Number of failed connections
    pub failed_connections: u64,
    
    /// Average connection duration (seconds)
    pub avg_connection_duration: f64,
    
    /// Current CPU usage (percentage)
    pub cpu_usage: f64,
    
    /// Current memory usage (bytes)
    pub memory_usage: u64,
    
    /// Network errors count
    pub network_errors: u64,
}

/// System-related metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    /// CPU usage (percentage)
    pub cpu_percent: f64,
    
    /// Memory usage (bytes)
    pub memory_usage: u64,
    
    /// Memory total (bytes)
    pub memory_total: u64,
    
    /// Disk usage (bytes)
    pub disk_usage: u64,
    
    /// Disk total (bytes)
    pub disk_total: u64,
    
    /// Network bytes received
    pub network_rx: u64,
    
    /// Network bytes transmitted
    pub network_tx: u64,
    
    /// Load average (1 minute)
    pub load_avg_1m: f64,
}

/// Metrics collector that manages Prometheus metrics
pub struct MetricsCollector {
    config: TelemetryConfig,
    registry: Arc<Registry>,
    
    // VPN-specific counters
    user_connections: CounterVec,
    data_transferred: CounterVec,
    connection_duration: HistogramVec,
    
    // Container metrics
    container_operations: CounterVec,
    container_start_duration: HistogramVec,
    container_status: GaugeVec,
    
    // Server metrics
    server_uptime: Gauge,
    server_cpu_usage: Gauge,
    server_memory_usage: Gauge,
    
    // System metrics
    system_cpu_usage: Gauge,
    system_memory_usage: Gauge,
    system_disk_usage: Gauge,
    system_network_bytes: CounterVec,
    
    // Custom metrics
    custom_counters: Arc<RwLock<HashMap<String, Counter>>>,
    custom_gauges: Arc<RwLock<HashMap<String, Gauge>>>,
    custom_histograms: Arc<RwLock<HashMap<String, Histogram>>>,
    
    // State
    running: Arc<RwLock<bool>>,
    last_update: Arc<RwLock<Instant>>,
}

impl MetricsCollector {
    /// Create a new metrics collector
    pub async fn new(config: &TelemetryConfig) -> Result<Self> {
        let registry = Arc::new(Registry::new());
        
        // Initialize VPN-specific metrics
        let user_connections = CounterVec::new(
            prometheus::Opts::new("vpn_user_connections_total", "Total VPN user connections")
                .namespace("vpn"),
            &["user_id", "protocol", "status"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create user_connections metric: {}", e),
        })?;
        
        let data_transferred = CounterVec::new(
            prometheus::Opts::new("vpn_data_transferred_bytes_total", "Total data transferred")
                .namespace("vpn"),
            &["direction", "user_id"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create data_transferred metric: {}", e),
        })?;
        
        let connection_duration = HistogramVec::new(
            prometheus::HistogramOpts::new("vpn_connection_duration_seconds", "VPN connection duration")
                .namespace("vpn")
                .buckets(vec![1.0, 5.0, 15.0, 30.0, 60.0, 300.0, 600.0, 1800.0, 3600.0]),
            &["user_id", "protocol"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create connection_duration metric: {}", e),
        })?;
        
        // Container metrics
        let container_operations = CounterVec::new(
            prometheus::Opts::new("container_operations_total", "Total container operations")
                .namespace("vpn"),
            &["operation", "container_type", "status"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create container_operations metric: {}", e),
        })?;
        
        let container_start_duration = HistogramVec::new(
            prometheus::HistogramOpts::new("container_start_duration_seconds", "Container start duration")
                .namespace("vpn")
                .buckets(vec![0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0]),
            &["container_type"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create container_start_duration metric: {}", e),
        })?;
        
        let container_status = GaugeVec::new(
            prometheus::Opts::new("container_status", "Current container status")
                .namespace("vpn"),
            &["container_id", "container_type", "status"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create container_status metric: {}", e),
        })?;
        
        // Server metrics
        let server_uptime = Gauge::new(
            "vpn_server_uptime_seconds", "Server uptime in seconds"
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create server_uptime metric: {}", e),
        })?;
        
        let server_cpu_usage = Gauge::new(
            "vpn_server_cpu_usage_percent", "Server CPU usage percentage"
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create server_cpu_usage metric: {}", e),
        })?;
        
        let server_memory_usage = Gauge::new(
            "vpn_server_memory_usage_bytes", "Server memory usage in bytes"
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create server_memory_usage metric: {}", e),
        })?;
        
        // System metrics
        let system_cpu_usage = Gauge::new(
            "system_cpu_usage_percent", "System CPU usage percentage"
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create system_cpu_usage metric: {}", e),
        })?;
        
        let system_memory_usage = Gauge::new(
            "system_memory_usage_bytes", "System memory usage in bytes"
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create system_memory_usage metric: {}", e),
        })?;
        
        let system_disk_usage = Gauge::new(
            "system_disk_usage_bytes", "System disk usage in bytes"
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create system_disk_usage metric: {}", e),
        })?;
        
        let system_network_bytes = CounterVec::new(
            prometheus::Opts::new("system_network_bytes_total", "System network bytes"),
            &["direction"],
        ).map_err(|e| TelemetryError::MetricsError {
            message: format!("Failed to create system_network_bytes metric: {}", e),
        })?;
        
        // Register all metrics
        registry.register(Box::new(user_connections.clone()))?;
        registry.register(Box::new(data_transferred.clone()))?;
        registry.register(Box::new(connection_duration.clone()))?;
        registry.register(Box::new(container_operations.clone()))?;
        registry.register(Box::new(container_start_duration.clone()))?;
        registry.register(Box::new(container_status.clone()))?;
        registry.register(Box::new(server_uptime.clone()))?;
        registry.register(Box::new(server_cpu_usage.clone()))?;
        registry.register(Box::new(server_memory_usage.clone()))?;
        registry.register(Box::new(system_cpu_usage.clone()))?;
        registry.register(Box::new(system_memory_usage.clone()))?;
        registry.register(Box::new(system_disk_usage.clone()))?;
        registry.register(Box::new(system_network_bytes.clone()))?;
        
        Ok(Self {
            config: config.clone(),
            registry,
            user_connections,
            data_transferred,
            connection_duration,
            container_operations,
            container_start_duration,
            container_status,
            server_uptime,
            server_cpu_usage,
            server_memory_usage,
            system_cpu_usage,
            system_memory_usage,
            system_disk_usage,
            system_network_bytes,
            custom_counters: Arc::new(RwLock::new(HashMap::new())),
            custom_gauges: Arc::new(RwLock::new(HashMap::new())),
            custom_histograms: Arc::new(RwLock::new(HashMap::new())),
            running: Arc::new(RwLock::new(false)),
            last_update: Arc::new(RwLock::new(Instant::now())),
        })
    }
    
    /// Start metrics collection
    pub async fn start(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }
        
        *running = true;
        info!("Started metrics collection");
        
        // Start background collection task
        let collector = Arc::new(RwLock::new(self.clone()));
        let interval = self.config.metrics.collection_interval;
        
        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(interval);
            
            loop {
                interval_timer.tick().await;
                
                let is_running = {
                    let collector_guard = collector.read().await;
                    let running_guard = collector_guard.running.read().await;
                    *running_guard
                };
                
                if !is_running {
                    break;
                }
                
                if let Err(e) = Self::collect_metrics(collector.clone()).await {
                    warn!("Failed to collect metrics: {}", e);
                }
            }
        });
        
        Ok(())
    }
    
    /// Stop metrics collection
    pub async fn stop(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        *running = false;
        info!("Stopped metrics collection");
        Ok(())
    }
    
    /// Collect current metrics
    async fn collect_metrics(collector: Arc<RwLock<Self>>) -> Result<()> {
        let collector_guard = collector.write().await;
        
        // Update system metrics
        if let Ok(system_info) = Self::get_system_info().await {
            collector_guard.system_cpu_usage.set(system_info.cpu_percent);
            collector_guard.system_memory_usage.set(system_info.memory_usage as f64);
            collector_guard.system_disk_usage.set(system_info.disk_usage as f64);
            collector_guard.system_network_bytes
                .with_label_values(&["rx"])
                .inc_by(system_info.network_rx as f64);
            collector_guard.system_network_bytes
                .with_label_values(&["tx"])
                .inc_by(system_info.network_tx as f64);
        }
        
        // Update server metrics
        collector_guard.server_uptime.set(Self::get_uptime().await as f64);
        
        *collector_guard.last_update.write().await = Instant::now();
        debug!("Collected metrics successfully");
        
        Ok(())
    }
    
    /// Get current system information
    async fn get_system_info() -> Result<SystemMetrics> {
        // This is a simplified implementation
        // In a real implementation, you would use system APIs to get actual metrics
        Ok(SystemMetrics {
            cpu_percent: 0.0,
            memory_usage: 0,
            memory_total: 0,
            disk_usage: 0,
            disk_total: 0,
            network_rx: 0,
            network_tx: 0,
            load_avg_1m: 0.0,
        })
    }
    
    /// Get server uptime
    async fn get_uptime() -> u64 {
        // This would be implemented to track actual server uptime
        0
    }
    
    /// Record a custom metric
    pub async fn record_metric(&mut self, name: &str, value: f64, labels: Vec<(&str, &str)>) -> Result<()> {
        debug!("Recording custom metric: {} = {}", name, value);
        
        // For simplicity, treat all custom metrics as gauges
        let mut custom_gauges = self.custom_gauges.write().await;
        
        if !custom_gauges.contains_key(name) {
            let gauge = Gauge::new(name, &format!("Custom metric: {}", name))
                .map_err(|e| TelemetryError::MetricsError {
                    message: format!("Failed to create custom gauge {}: {}", name, e),
                })?;
            
            self.registry.register(Box::new(gauge.clone()))?;
            custom_gauges.insert(name.to_string(), gauge);
        }
        
        if let Some(gauge) = custom_gauges.get(name) {
            gauge.set(value);
        }
        
        Ok(())
    }
    
    /// Get current metrics
    pub async fn get_current_metrics(&self) -> Result<VpnMetrics> {
        // This would collect metrics from various sources
        Ok(VpnMetrics {
            active_users: 0,
            active_connections: 0,
            total_data_transferred: 0,
            current_bandwidth: 0.0,
            containers: ContainerMetrics {
                running: 0,
                stopped: 0,
                failed: 0,
                total_starts: 0,
                total_stops: 0,
                avg_start_time: 0.0,
                restart_count: 0,
            },
            server: ServerMetrics {
                uptime: 0,
                successful_connections: 0,
                failed_connections: 0,
                avg_connection_duration: 0.0,
                cpu_usage: 0.0,
                memory_usage: 0,
                network_errors: 0,
            },
            system: SystemMetrics {
                cpu_percent: 0.0,
                memory_usage: 0,
                memory_total: 0,
                disk_usage: 0,
                disk_total: 0,
                network_rx: 0,
                network_tx: 0,
                load_avg_1m: 0.0,
            },
            custom: HashMap::new(),
        })
    }
    
    /// Export metrics in Prometheus format
    pub async fn export_metrics(&self) -> Result<String> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();
        
        encoder.encode_to_string(&metric_families)
            .map_err(|e| TelemetryError::MetricsError {
                message: format!("Failed to encode metrics: {}", e),
            })
    }
    
    /// Record user connection
    pub fn record_user_connection(&self, user_id: &str, protocol: &str, success: bool) {
        let status = if success { "success" } else { "failure" };
        self.user_connections
            .with_label_values(&[user_id, protocol, status])
            .inc();
    }
    
    /// Record data transfer
    pub fn record_data_transfer(&self, direction: &str, user_id: &str, bytes: u64) {
        self.data_transferred
            .with_label_values(&[direction, user_id])
            .inc_by(bytes as f64);
    }
    
    /// Record connection duration
    pub fn record_connection_duration(&self, user_id: &str, protocol: &str, duration: Duration) {
        self.connection_duration
            .with_label_values(&[user_id, protocol])
            .observe(duration.as_secs_f64());
    }
    
    /// Record container operation
    pub fn record_container_operation(&self, operation: &str, container_type: &str, success: bool) {
        let status = if success { "success" } else { "failure" };
        self.container_operations
            .with_label_values(&[operation, container_type, status])
            .inc();
    }
    
    /// Record container start duration
    pub fn record_container_start_duration(&self, container_type: &str, duration: Duration) {
        self.container_start_duration
            .with_label_values(&[container_type])
            .observe(duration.as_secs_f64());
    }
}

impl Clone for MetricsCollector {
    fn clone(&self) -> Self {
        Self {
            config: self.config.clone(),
            registry: self.registry.clone(),
            user_connections: self.user_connections.clone(),
            data_transferred: self.data_transferred.clone(),
            connection_duration: self.connection_duration.clone(),
            container_operations: self.container_operations.clone(),
            container_start_duration: self.container_start_duration.clone(),
            container_status: self.container_status.clone(),
            server_uptime: self.server_uptime.clone(),
            server_cpu_usage: self.server_cpu_usage.clone(),
            server_memory_usage: self.server_memory_usage.clone(),
            system_cpu_usage: self.system_cpu_usage.clone(),
            system_memory_usage: self.system_memory_usage.clone(),
            system_disk_usage: self.system_disk_usage.clone(),
            system_network_bytes: self.system_network_bytes.clone(),
            custom_counters: self.custom_counters.clone(),
            custom_gauges: self.custom_gauges.clone(),
            custom_histograms: self.custom_histograms.clone(),
            running: self.running.clone(),
            last_update: self.last_update.clone(),
        }
    }
}

impl From<prometheus::Error> for TelemetryError {
    fn from(error: prometheus::Error) -> Self {
        TelemetryError::MetricsError {
            message: error.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::TelemetryConfig;

    #[tokio::test]
    async fn test_metrics_collector_creation() {
        let config = TelemetryConfig::default();
        let collector = MetricsCollector::new(&config).await;
        assert!(collector.is_ok());
    }

    #[tokio::test]
    async fn test_metrics_collection_lifecycle() {
        let config = TelemetryConfig::default();
        let mut collector = MetricsCollector::new(&config).await.unwrap();
        
        assert!(!*collector.running.read().await);
        
        let result = collector.start().await;
        assert!(result.is_ok());
        assert!(*collector.running.read().await);
        
        let result = collector.stop().await;
        assert!(result.is_ok());
        assert!(!*collector.running.read().await);
    }

    #[tokio::test]
    async fn test_custom_metric_recording() {
        let config = TelemetryConfig::default();
        let mut collector = MetricsCollector::new(&config).await.unwrap();
        
        let result = collector.record_metric("test_metric", 42.0, vec![]).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_metrics_export() {
        let config = TelemetryConfig::default();
        let collector = MetricsCollector::new(&config).await.unwrap();
        
        let result = collector.export_metrics().await;
        assert!(result.is_ok());
        
        let metrics = result.unwrap();
        assert!(metrics.contains("vpn_"));
    }
}