use std::collections::HashMap;
use std::time::{Duration, Instant};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use crate::health::{HealthMonitor, HealthStatus};
use crate::traffic::{TrafficMonitor, TrafficSummary};
use crate::error::Result;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub timestamp: DateTime<Utc>,
    pub system_metrics: SystemPerformance,
    pub application_metrics: ApplicationPerformance,
    pub network_metrics: NetworkPerformance,
    pub custom_metrics: HashMap<String, f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemPerformance {
    pub cpu_usage: f64,
    pub memory_usage: f64,
    pub disk_usage: f64,
    pub disk_io_read: u64,
    pub disk_io_write: u64,
    pub network_io_rx: u64,
    pub network_io_tx: u64,
    pub load_average: (f64, f64, f64),
    pub uptime: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApplicationPerformance {
    pub response_time: Duration,
    pub throughput: f64, // requests per second
    pub error_rate: f64,
    pub active_connections: u64,
    pub memory_footprint: u64,
    pub cpu_time: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkPerformance {
    pub bandwidth_utilization: f64,
    pub packet_loss: f64,
    pub latency: Duration,
    pub jitter: Duration,
    pub concurrent_connections: u64,
    pub connection_rate: f64, // connections per second
}

#[derive(Debug, Clone)]
pub struct MetricsConfig {
    pub collection_interval: Duration,
    pub retention_period: Duration,
    pub enable_detailed_metrics: bool,
    pub custom_metrics: Vec<CustomMetric>,
}

#[derive(Debug, Clone)]
pub struct CustomMetric {
    pub name: String,
    pub description: String,
    pub metric_type: MetricType,
    pub collection_fn: fn() -> Result<f64>,
}

#[derive(Debug, Clone, Copy)]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
    Timer,
}

pub struct MetricsCollector {
    health_monitor: HealthMonitor,
    traffic_monitor: TrafficMonitor,
    config: MetricsConfig,
    last_metrics: Option<PerformanceMetrics>,
    collection_history: Vec<PerformanceMetrics>,
}

impl MetricsCollector {
    pub fn new(
        health_monitor: HealthMonitor,
        traffic_monitor: TrafficMonitor,
        config: MetricsConfig,
    ) -> Self {
        Self {
            health_monitor,
            traffic_monitor,
            config,
            last_metrics: None,
            collection_history: Vec::new(),
        }
    }
    
    pub async fn collect_metrics(&mut self) -> Result<PerformanceMetrics> {
        let start_time = Instant::now();
        
        // Collect health metrics
        let health_status = self.health_monitor.check_overall_health().await?;
        
        // Collect traffic metrics
        let traffic_summary = self.traffic_monitor.collect_traffic_stats(
            &std::path::PathBuf::from("/opt/vpn")
        ).await?;
        
        // Build performance metrics
        let system_metrics = self.build_system_metrics(&health_status).await?;
        let application_metrics = self.build_application_metrics(&health_status, &traffic_summary).await?;
        let network_metrics = self.build_network_metrics(&health_status, &traffic_summary).await?;
        let custom_metrics = self.collect_custom_metrics().await?;
        
        let metrics = PerformanceMetrics {
            timestamp: Utc::now(),
            system_metrics,
            application_metrics,
            network_metrics,
            custom_metrics,
        };
        
        // Store in history
        self.collection_history.push(metrics.clone());
        
        // Cleanup old metrics
        self.cleanup_old_metrics();
        
        // Update last metrics
        self.last_metrics = Some(metrics.clone());
        
        let collection_time = start_time.elapsed();
        if collection_time > Duration::from_secs(5) {
            eprintln!("Warning: Metrics collection took {:?}", collection_time);
        }
        
        Ok(metrics)
    }
    
    async fn build_system_metrics(&self, health_status: &HealthStatus) -> Result<SystemPerformance> {
        let system = &health_status.system_metrics;
        
        Ok(SystemPerformance {
            cpu_usage: system.cpu_usage,
            memory_usage: system.memory_percentage,
            disk_usage: system.disk_percentage,
            disk_io_read: 0, // Would need to be collected separately
            disk_io_write: 0,
            network_io_rx: system.network_interfaces.iter().map(|i| i.rx_bytes).sum(),
            network_io_tx: system.network_interfaces.iter().map(|i| i.tx_bytes).sum(),
            load_average: system.load_average,
            uptime: health_status.uptime,
        })
    }
    
    async fn build_application_metrics(
        &self,
        health_status: &HealthStatus,
        traffic_summary: &TrafficSummary,
    ) -> Result<ApplicationPerformance> {
        // Calculate response time based on container health
        let response_time = if health_status.is_healthy() {
            Duration::from_millis(50) // Typical good response time
        } else {
            Duration::from_millis(500) // Degraded performance
        };
        
        // Calculate throughput
        let period_seconds = 300.0; // 5 minutes
        let throughput = traffic_summary.total_connections as f64 / period_seconds;
        
        // Calculate error rate from logs (simplified)
        let error_rate = if health_status.is_critical() { 5.0 } else { 0.1 };
        
        // Sum memory usage from all containers
        let memory_footprint = health_status.containers.iter()
            .map(|c| c.memory_usage)
            .sum();
        
        Ok(ApplicationPerformance {
            response_time,
            throughput,
            error_rate,
            active_connections: traffic_summary.active_users,
            memory_footprint,
            cpu_time: Duration::from_secs(0), // Would need process-specific data
        })
    }
    
    async fn build_network_metrics(
        &self,
        health_status: &HealthStatus,
        traffic_summary: &TrafficSummary,
    ) -> Result<NetworkPerformance> {
        // Calculate bandwidth utilization
        let total_bytes = traffic_summary.total_bytes_sent + traffic_summary.total_bytes_received;
        let bandwidth_utilization = (total_bytes as f64 / (100.0 * 1024.0 * 1024.0)) * 100.0; // % of 100Mbps
        
        // Network health indicators
        let (packet_loss, latency) = if health_status.network_status.connectivity {
            let avg_response_time = health_status.network_status.response_times
                .values()
                .map(|&rt| rt as f64)
                .sum::<f64>() / health_status.network_status.response_times.len().max(1) as f64;
            
            (0.01, Duration::from_millis(avg_response_time as u64)) // 0.01% packet loss
        } else {
            (5.0, Duration::from_millis(1000)) // High packet loss and latency
        };
        
        Ok(NetworkPerformance {
            bandwidth_utilization: bandwidth_utilization.min(100.0),
            packet_loss,
            latency,
            jitter: Duration::from_millis(10), // Simplified
            concurrent_connections: traffic_summary.total_connections,
            connection_rate: traffic_summary.total_connections as f64 / 300.0, // connections per second
        })
    }
    
    async fn collect_custom_metrics(&self) -> Result<HashMap<String, f64>> {
        let mut custom_metrics = HashMap::new();
        
        for metric in &self.config.custom_metrics {
            match (metric.collection_fn)() {
                Ok(value) => {
                    custom_metrics.insert(metric.name.clone(), value);
                }
                Err(e) => {
                    eprintln!("Failed to collect custom metric '{}': {}", metric.name, e);
                }
            }
        }
        
        // Add some built-in custom metrics
        custom_metrics.insert("metrics_collection_count".to_string(), self.collection_history.len() as f64);
        custom_metrics.insert("rust_process_memory".to_string(), self.get_process_memory_usage() as f64);
        
        Ok(custom_metrics)
    }
    
    fn get_process_memory_usage(&self) -> u64 {
        // Get current process memory usage
        if let Ok(content) = std::fs::read_to_string("/proc/self/status") {
            for line in content.lines() {
                if line.starts_with("VmRSS:") {
                    if let Some(parts) = line.split_whitespace().nth(1) {
                        if let Ok(kb) = parts.parse::<u64>() {
                            return kb * 1024; // Convert KB to bytes
                        }
                    }
                }
            }
        }
        0
    }
    
    fn cleanup_old_metrics(&mut self) {
        let cutoff_time = Utc::now() - chrono::Duration::from_std(self.config.retention_period).unwrap();
        
        self.collection_history.retain(|metrics| {
            metrics.timestamp > cutoff_time
        });
    }
    
    pub fn get_metrics_history(&self, duration: Duration) -> Vec<&PerformanceMetrics> {
        let cutoff_time = Utc::now() - chrono::Duration::from_std(duration).unwrap();
        
        self.collection_history.iter()
            .filter(|metrics| metrics.timestamp > cutoff_time)
            .collect()
    }
    
    pub fn calculate_averages(&self, duration: Duration) -> Option<PerformanceMetrics> {
        let history = self.get_metrics_history(duration);
        
        if history.is_empty() {
            return None;
        }
        
        let count = history.len() as f64;
        
        // Calculate averages
        let avg_cpu = history.iter().map(|m| m.system_metrics.cpu_usage).sum::<f64>() / count;
        let avg_memory = history.iter().map(|m| m.system_metrics.memory_usage).sum::<f64>() / count;
        let avg_disk = history.iter().map(|m| m.system_metrics.disk_usage).sum::<f64>() / count;
        
        let avg_response_time_ms = history.iter()
            .map(|m| m.application_metrics.response_time.as_millis() as f64)
            .sum::<f64>() / count;
        
        let avg_throughput = history.iter().map(|m| m.application_metrics.throughput).sum::<f64>() / count;
        let avg_error_rate = history.iter().map(|m| m.application_metrics.error_rate).sum::<f64>() / count;
        
        let avg_bandwidth = history.iter().map(|m| m.network_metrics.bandwidth_utilization).sum::<f64>() / count;
        let avg_packet_loss = history.iter().map(|m| m.network_metrics.packet_loss).sum::<f64>() / count;
        
        Some(PerformanceMetrics {
            timestamp: Utc::now(),
            system_metrics: SystemPerformance {
                cpu_usage: avg_cpu,
                memory_usage: avg_memory,
                disk_usage: avg_disk,
                disk_io_read: 0,
                disk_io_write: 0,
                network_io_rx: 0,
                network_io_tx: 0,
                load_average: (0.0, 0.0, 0.0),
                uptime: Duration::from_secs(0),
            },
            application_metrics: ApplicationPerformance {
                response_time: Duration::from_millis(avg_response_time_ms as u64),
                throughput: avg_throughput,
                error_rate: avg_error_rate,
                active_connections: 0,
                memory_footprint: 0,
                cpu_time: Duration::from_secs(0),
            },
            network_metrics: NetworkPerformance {
                bandwidth_utilization: avg_bandwidth,
                packet_loss: avg_packet_loss,
                latency: Duration::from_millis(0),
                jitter: Duration::from_millis(0),
                concurrent_connections: 0,
                connection_rate: 0.0,
            },
            custom_metrics: HashMap::new(),
        })
    }
    
    pub fn detect_anomalies(&self, current: &PerformanceMetrics) -> Vec<String> {
        let mut anomalies = Vec::new();
        
        // CPU usage anomaly
        if current.system_metrics.cpu_usage > 90.0 {
            anomalies.push(format!("High CPU usage: {:.1}%", current.system_metrics.cpu_usage));
        }
        
        // Memory usage anomaly
        if current.system_metrics.memory_usage > 90.0 {
            anomalies.push(format!("High memory usage: {:.1}%", current.system_metrics.memory_usage));
        }
        
        // Disk usage anomaly
        if current.system_metrics.disk_usage > 90.0 {
            anomalies.push(format!("High disk usage: {:.1}%", current.system_metrics.disk_usage));
        }
        
        // Response time anomaly
        if current.application_metrics.response_time > Duration::from_millis(1000) {
            anomalies.push(format!("High response time: {:?}", current.application_metrics.response_time));
        }
        
        // Error rate anomaly
        if current.application_metrics.error_rate > 5.0 {
            anomalies.push(format!("High error rate: {:.1}%", current.application_metrics.error_rate));
        }
        
        // Network anomalies
        if current.network_metrics.packet_loss > 1.0 {
            anomalies.push(format!("High packet loss: {:.1}%", current.network_metrics.packet_loss));
        }
        
        if current.network_metrics.latency > Duration::from_millis(500) {
            anomalies.push(format!("High network latency: {:?}", current.network_metrics.latency));
        }
        
        anomalies
    }
    
    pub fn export_prometheus_metrics(&self, metrics: &PerformanceMetrics) -> String {
        let mut output = String::new();
        
        // System metrics
        output.push_str(&format!("vpn_cpu_usage_percent {}\n", metrics.system_metrics.cpu_usage));
        output.push_str(&format!("vpn_memory_usage_percent {}\n", metrics.system_metrics.memory_usage));
        output.push_str(&format!("vpn_disk_usage_percent {}\n", metrics.system_metrics.disk_usage));
        output.push_str(&format!("vpn_uptime_seconds {}\n", metrics.system_metrics.uptime.as_secs()));
        
        // Application metrics
        output.push_str(&format!("vpn_response_time_ms {}\n", metrics.application_metrics.response_time.as_millis()));
        output.push_str(&format!("vpn_throughput_rps {}\n", metrics.application_metrics.throughput));
        output.push_str(&format!("vpn_error_rate_percent {}\n", metrics.application_metrics.error_rate));
        output.push_str(&format!("vpn_active_connections {}\n", metrics.application_metrics.active_connections));
        
        // Network metrics
        output.push_str(&format!("vpn_bandwidth_utilization_percent {}\n", metrics.network_metrics.bandwidth_utilization));
        output.push_str(&format!("vpn_packet_loss_percent {}\n", metrics.network_metrics.packet_loss));
        output.push_str(&format!("vpn_latency_ms {}\n", metrics.network_metrics.latency.as_millis()));
        
        // Custom metrics
        for (name, value) in &metrics.custom_metrics {
            output.push_str(&format!("vpn_custom_{} {}\n", name, value));
        }
        
        output
    }
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            collection_interval: Duration::from_secs(60),
            retention_period: Duration::from_secs(86400 * 7), // 7 days
            enable_detailed_metrics: true,
            custom_metrics: Vec::new(),
        }
    }
}

impl MetricType {
    pub fn as_str(&self) -> &'static str {
        match self {
            MetricType::Counter => "counter",
            MetricType::Gauge => "gauge",
            MetricType::Histogram => "histogram",
            MetricType::Timer => "timer",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::health::HealthMonitor;
    use crate::traffic::{TrafficMonitor, MonitoringConfig};
    
    #[tokio::test]
    async fn test_metrics_collection() {
        let health_monitor = HealthMonitor::new().unwrap();
        let traffic_monitor = TrafficMonitor::new(MonitoringConfig::default()).unwrap();
        let mut collector = MetricsCollector::new(
            health_monitor,
            traffic_monitor,
            MetricsConfig::default(),
        );
        
        let _metrics = collector.collect_metrics().await.unwrap();
        assert!(collector.collection_history.len() > 0);
    }
    
    #[test]
    fn test_anomaly_detection() {
        let health_monitor = HealthMonitor::new().unwrap();
        let traffic_monitor = TrafficMonitor::new(MonitoringConfig::default()).unwrap();
        let collector = MetricsCollector::new(
            health_monitor,
            traffic_monitor,
            MetricsConfig::default(),
        );
        
        let high_cpu_metrics = PerformanceMetrics {
            timestamp: Utc::now(),
            system_metrics: SystemPerformance {
                cpu_usage: 95.0,
                memory_usage: 50.0,
                disk_usage: 30.0,
                disk_io_read: 0,
                disk_io_write: 0,
                network_io_rx: 0,
                network_io_tx: 0,
                load_average: (1.0, 1.0, 1.0),
                uptime: Duration::from_secs(3600),
            },
            application_metrics: ApplicationPerformance {
                response_time: Duration::from_millis(100),
                throughput: 10.0,
                error_rate: 1.0,
                active_connections: 50,
                memory_footprint: 1024 * 1024,
                cpu_time: Duration::from_secs(100),
            },
            network_metrics: NetworkPerformance {
                bandwidth_utilization: 50.0,
                packet_loss: 0.1,
                latency: Duration::from_millis(50),
                jitter: Duration::from_millis(5),
                concurrent_connections: 100,
                connection_rate: 5.0,
            },
            custom_metrics: HashMap::new(),
        };
        
        let anomalies = collector.detect_anomalies(&high_cpu_metrics);
        assert!(anomalies.iter().any(|a| a.contains("High CPU usage")));
    }
}