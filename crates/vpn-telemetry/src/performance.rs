//! Performance monitoring and benchmarking

use crate::{config::TelemetryConfig, error::Result, TelemetryError};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Performance metrics for the VPN system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub system_performance: SystemPerformance,
    pub network_performance: NetworkPerformance,
    pub container_performance: ContainerPerformance,
    pub user_performance: UserPerformance,
    pub benchmarks: HashMap<String, BenchmarkResult>,
}

/// System-level performance metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemPerformance {
    pub cpu_usage_percent: f64,
    pub memory_usage_bytes: u64,
    pub memory_total_bytes: u64,
    pub disk_read_bytes_per_sec: u64,
    pub disk_write_bytes_per_sec: u64,
    pub load_average_1m: f64,
    pub load_average_5m: f64,
    pub load_average_15m: f64,
    pub process_count: u64,
    pub thread_count: u64,
    pub open_files: u64,
}

/// Network performance metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkPerformance {
    pub bytes_received_per_sec: u64,
    pub bytes_sent_per_sec: u64,
    pub packets_received_per_sec: u64,
    pub packets_sent_per_sec: u64,
    pub connection_count: u64,
    pub connection_errors: u64,
    pub average_latency_ms: f64,
    pub packet_loss_rate: f64,
    pub bandwidth_utilization_percent: f64,
}

/// Container performance metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerPerformance {
    pub total_containers: u64,
    pub running_containers: u64,
    pub average_start_time_ms: f64,
    pub average_memory_usage_mb: f64,
    pub average_cpu_usage_percent: f64,
    pub restart_count: u64,
    pub failed_starts: u64,
    pub operations_per_second: f64,
}

/// User-related performance metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPerformance {
    pub active_sessions: u64,
    pub connection_success_rate: f64,
    pub average_connection_time_ms: f64,
    pub data_transfer_rate_mbps: f64,
    pub authentication_time_ms: f64,
    pub session_duration_avg_minutes: f64,
}

/// Benchmark result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkResult {
    pub name: String,
    pub duration: Duration,
    pub operations_per_second: f64,
    pub memory_usage_mb: f64,
    pub success_rate: f64,
    pub comparison_baseline: Option<f64>,
    pub improvement_factor: Option<f64>,
}

/// Performance sample for trend analysis
#[derive(Debug, Clone)]
struct PerformanceSample {
    timestamp: Instant,
    metrics: PerformanceMetrics,
}

/// Performance monitor that tracks system performance over time
pub struct PerformanceMonitor {
    config: TelemetryConfig,
    samples: Arc<RwLock<VecDeque<PerformanceSample>>>,
    running: Arc<RwLock<bool>>,
    collection_handle: Arc<RwLock<Option<tokio::task::JoinHandle<()>>>>,
    benchmarks: Arc<RwLock<HashMap<String, BenchmarkResult>>>,
    baseline_metrics: Arc<RwLock<Option<PerformanceMetrics>>>,
}

impl PerformanceMonitor {
    /// Create a new performance monitor
    pub async fn new(config: &TelemetryConfig) -> Result<Self> {
        Ok(Self {
            config: config.clone(),
            samples: Arc::new(RwLock::new(VecDeque::new())),
            running: Arc::new(RwLock::new(false)),
            collection_handle: Arc::new(RwLock::new(None)),
            benchmarks: Arc::new(RwLock::new(HashMap::new())),
            baseline_metrics: Arc::new(RwLock::new(None)),
        })
    }

    /// Start performance monitoring
    pub async fn start(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        *running = true;
        info!("Starting performance monitoring");

        // Start background collection task
        let samples = self.samples.clone();
        let config = self.config.clone();
        let running_flag = self.running.clone();

        let collection_task = tokio::spawn(async move {
            Self::collection_loop(samples, config, running_flag).await;
        });

        *self.collection_handle.write().await = Some(collection_task);

        // Set baseline metrics if enabled
        if self.config.performance.benchmark_enabled {
            self.establish_baseline().await?;
        }

        Ok(())
    }

    /// Stop performance monitoring
    pub async fn stop(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        *running = false;

        // Cancel collection task
        if let Some(handle) = self.collection_handle.write().await.take() {
            handle.abort();
        }

        info!("Performance monitoring stopped");
        Ok(())
    }

    /// Get current performance metrics
    pub async fn get_current_metrics(&self) -> Result<PerformanceMetrics> {
        let samples = self.samples.read().await;
        
        if let Some(latest) = samples.back() {
            Ok(latest.metrics.clone())
        } else {
            // Return default metrics if no samples available
            Ok(PerformanceMetrics::default())
        }
    }

    /// Get performance trends over time
    pub async fn get_performance_trends(&self, duration: Duration) -> Result<Vec<PerformanceMetrics>> {
        let samples = self.samples.read().await;
        let cutoff_time = Instant::now() - duration;

        let trends: Vec<PerformanceMetrics> = samples
            .iter()
            .filter(|sample| sample.timestamp >= cutoff_time)
            .map(|sample| sample.metrics.clone())
            .collect();

        Ok(trends)
    }

    /// Run a performance benchmark
    pub async fn run_benchmark(&self, name: &str, benchmark_fn: impl Fn() -> Result<()>) -> Result<BenchmarkResult> {
        info!("Running benchmark: {}", name);
        
        let start_time = Instant::now();
        let start_memory = Self::get_memory_usage().await?;
        
        let operations = 1000; // Fixed number of operations for benchmarking
        let mut success_count = 0;
        
        for _ in 0..operations {
            if benchmark_fn().is_ok() {
                success_count += 1;
            }
        }
        
        let duration = start_time.elapsed();
        let end_memory = Self::get_memory_usage().await?;
        let memory_usage_mb = (end_memory - start_memory) as f64 / 1024.0 / 1024.0;
        
        let ops_per_second = operations as f64 / duration.as_secs_f64();
        let success_rate = success_count as f64 / operations as f64;
        
        // Calculate improvement factor if baseline exists
        let (comparison_baseline, improvement_factor) = {
            let benchmarks = self.benchmarks.read().await;
            if let Some(baseline) = benchmarks.get(&format!("{}_baseline", name)) {
                let improvement = ops_per_second / baseline.operations_per_second;
                (Some(baseline.operations_per_second), Some(improvement))
            } else {
                (None, None)
            }
        };
        
        let result = BenchmarkResult {
            name: name.to_string(),
            duration,
            operations_per_second: ops_per_second,
            memory_usage_mb,
            success_rate,
            comparison_baseline,
            improvement_factor,
        };
        
        // Store the benchmark result
        {
            let mut benchmarks = self.benchmarks.write().await;
            benchmarks.insert(name.to_string(), result.clone());
        }
        
        info!("Benchmark {} completed: {:.2} ops/sec, {:.2}% success rate", 
               name, ops_per_second, success_rate * 100.0);
        
        Ok(result)
    }

    /// Establish baseline performance metrics
    async fn establish_baseline(&self) -> Result<()> {
        info!("Establishing performance baseline");
        
        let baseline = Self::collect_current_metrics().await?;
        *self.baseline_metrics.write().await = Some(baseline);
        
        // Run baseline benchmarks
        self.run_baseline_benchmarks().await?;
        
        Ok(())
    }

    /// Run baseline benchmarks
    async fn run_baseline_benchmarks(&self) -> Result<()> {
        // CPU benchmark
        let cpu_result = self.run_benchmark("cpu_baseline", || {
            // Simple CPU-intensive operation
            let mut sum = 0u64;
            for i in 0..10000 {
                sum = sum.wrapping_add(i * i);
            }
            Ok(())
        }).await?;

        // Store as baseline
        {
            let mut benchmarks = self.benchmarks.write().await;
            benchmarks.insert("cpu_baseline_baseline".to_string(), cpu_result);
        }

        // Memory allocation benchmark
        let memory_result = self.run_benchmark("memory_baseline", || {
            let _data: Vec<u8> = vec![0; 1024 * 1024]; // Allocate 1MB
            Ok(())
        }).await?;

        {
            let mut benchmarks = self.benchmarks.write().await;
            benchmarks.insert("memory_baseline_baseline".to_string(), memory_result);
        }

        info!("Baseline benchmarks established");
        Ok(())
    }

    /// Performance collection loop
    async fn collection_loop(
        samples: Arc<RwLock<VecDeque<PerformanceSample>>>,
        config: TelemetryConfig,
        running: Arc<RwLock<bool>>,
    ) {
        let mut interval = tokio::time::interval(config.performance.collection_interval);

        while *running.read().await {
            interval.tick().await;

            match Self::collect_current_metrics().await {
                Ok(metrics) => {
                    let sample = PerformanceSample {
                        timestamp: Instant::now(),
                        metrics,
                    };

                    let mut samples_guard = samples.write().await;
                    samples_guard.push_back(sample);

                    // Keep only the configured number of samples
                    if samples_guard.len() > config.performance.sample_size {
                        samples_guard.pop_front();
                    }
                }
                Err(e) => {
                    warn!("Failed to collect performance metrics: {}", e);
                }
            }
        }
    }

    /// Collect current performance metrics
    async fn collect_current_metrics() -> Result<PerformanceMetrics> {
        debug!("Collecting performance metrics");

        // This is a simplified implementation
        // In a real implementation, you would use system APIs to collect actual metrics
        
        let system_performance = SystemPerformance {
            cpu_usage_percent: Self::get_cpu_usage().await?,
            memory_usage_bytes: Self::get_memory_usage().await?,
            memory_total_bytes: Self::get_total_memory().await?,
            disk_read_bytes_per_sec: 0,
            disk_write_bytes_per_sec: 0,
            load_average_1m: 0.0,
            load_average_5m: 0.0,
            load_average_15m: 0.0,
            process_count: 0,
            thread_count: 0,
            open_files: 0,
        };

        let network_performance = NetworkPerformance {
            bytes_received_per_sec: 0,
            bytes_sent_per_sec: 0,
            packets_received_per_sec: 0,
            packets_sent_per_sec: 0,
            connection_count: 0,
            connection_errors: 0,
            average_latency_ms: 0.0,
            packet_loss_rate: 0.0,
            bandwidth_utilization_percent: 0.0,
        };

        let container_performance = ContainerPerformance {
            total_containers: 0,
            running_containers: 0,
            average_start_time_ms: 0.0,
            average_memory_usage_mb: 0.0,
            average_cpu_usage_percent: 0.0,
            restart_count: 0,
            failed_starts: 0,
            operations_per_second: 0.0,
        };

        let user_performance = UserPerformance {
            active_sessions: 0,
            connection_success_rate: 0.0,
            average_connection_time_ms: 0.0,
            data_transfer_rate_mbps: 0.0,
            authentication_time_ms: 0.0,
            session_duration_avg_minutes: 0.0,
        };

        Ok(PerformanceMetrics {
            timestamp: chrono::Utc::now(),
            system_performance,
            network_performance,
            container_performance,
            user_performance,
            benchmarks: HashMap::new(),
        })
    }

    /// Get current CPU usage
    async fn get_cpu_usage() -> Result<f64> {
        // Simplified implementation - would use system APIs in practice
        Ok(0.0)
    }

    /// Get current memory usage
    async fn get_memory_usage() -> Result<u64> {
        // Simplified implementation - would use system APIs in practice
        Ok(0)
    }

    /// Get total memory
    async fn get_total_memory() -> Result<u64> {
        // Simplified implementation - would use system APIs in practice
        Ok(0)
    }

    /// Compare current performance with baseline
    pub async fn compare_with_baseline(&self) -> Result<HashMap<String, f64>> {
        let baseline = self.baseline_metrics.read().await;
        let baseline_metrics = baseline.as_ref()
            .ok_or_else(|| TelemetryError::PerformanceError {
                message: "No baseline metrics available".to_string(),
            })?;

        let current_metrics = self.get_current_metrics().await?;
        let mut comparison = HashMap::new();

        // Compare CPU usage
        if baseline_metrics.system_performance.cpu_usage_percent > 0.0 {
            let cpu_ratio = current_metrics.system_performance.cpu_usage_percent / 
                          baseline_metrics.system_performance.cpu_usage_percent;
            comparison.insert("cpu_usage_ratio".to_string(), cpu_ratio);
        }

        // Compare memory usage
        if baseline_metrics.system_performance.memory_usage_bytes > 0 {
            let memory_ratio = current_metrics.system_performance.memory_usage_bytes as f64 / 
                             baseline_metrics.system_performance.memory_usage_bytes as f64;
            comparison.insert("memory_usage_ratio".to_string(), memory_ratio);
        }

        // Compare network performance
        if baseline_metrics.network_performance.bytes_received_per_sec > 0 {
            let network_ratio = current_metrics.network_performance.bytes_received_per_sec as f64 / 
                              baseline_metrics.network_performance.bytes_received_per_sec as f64;
            comparison.insert("network_throughput_ratio".to_string(), network_ratio);
        }

        Ok(comparison)
    }

    /// Get performance summary
    pub async fn get_performance_summary(&self, duration: Duration) -> Result<PerformanceSummary> {
        let trends = self.get_performance_trends(duration).await?;
        
        if trends.is_empty() {
            return Err(TelemetryError::PerformanceError {
                message: "No performance data available".to_string(),
            });
        }

        let cpu_usage: Vec<f64> = trends.iter()
            .map(|m| m.system_performance.cpu_usage_percent)
            .collect();
        
        let memory_usage: Vec<u64> = trends.iter()
            .map(|m| m.system_performance.memory_usage_bytes)
            .collect();

        Ok(PerformanceSummary {
            period: duration,
            sample_count: trends.len(),
            cpu_usage_avg: cpu_usage.iter().sum::<f64>() / cpu_usage.len() as f64,
            cpu_usage_max: cpu_usage.iter().fold(0.0, |a, &b| a.max(b)),
            memory_usage_avg: memory_usage.iter().sum::<u64>() / memory_usage.len() as u64,
            memory_usage_max: *memory_usage.iter().max().unwrap_or(&0),
        })
    }
}

/// Performance summary over a time period
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceSummary {
    pub period: Duration,
    pub sample_count: usize,
    pub cpu_usage_avg: f64,
    pub cpu_usage_max: f64,
    pub memory_usage_avg: u64,
    pub memory_usage_max: u64,
}

impl Default for PerformanceMetrics {
    fn default() -> Self {
        Self {
            timestamp: chrono::Utc::now(),
            system_performance: SystemPerformance::default(),
            network_performance: NetworkPerformance::default(),
            container_performance: ContainerPerformance::default(),
            user_performance: UserPerformance::default(),
            benchmarks: HashMap::new(),
        }
    }
}

impl Default for SystemPerformance {
    fn default() -> Self {
        Self {
            cpu_usage_percent: 0.0,
            memory_usage_bytes: 0,
            memory_total_bytes: 0,
            disk_read_bytes_per_sec: 0,
            disk_write_bytes_per_sec: 0,
            load_average_1m: 0.0,
            load_average_5m: 0.0,
            load_average_15m: 0.0,
            process_count: 0,
            thread_count: 0,
            open_files: 0,
        }
    }
}

impl Default for NetworkPerformance {
    fn default() -> Self {
        Self {
            bytes_received_per_sec: 0,
            bytes_sent_per_sec: 0,
            packets_received_per_sec: 0,
            packets_sent_per_sec: 0,
            connection_count: 0,
            connection_errors: 0,
            average_latency_ms: 0.0,
            packet_loss_rate: 0.0,
            bandwidth_utilization_percent: 0.0,
        }
    }
}

impl Default for ContainerPerformance {
    fn default() -> Self {
        Self {
            total_containers: 0,
            running_containers: 0,
            average_start_time_ms: 0.0,
            average_memory_usage_mb: 0.0,
            average_cpu_usage_percent: 0.0,
            restart_count: 0,
            failed_starts: 0,
            operations_per_second: 0.0,
        }
    }
}

impl Default for UserPerformance {
    fn default() -> Self {
        Self {
            active_sessions: 0,
            connection_success_rate: 0.0,
            average_connection_time_ms: 0.0,
            data_transfer_rate_mbps: 0.0,
            authentication_time_ms: 0.0,
            session_duration_avg_minutes: 0.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::TelemetryConfig;

    #[tokio::test]
    async fn test_performance_monitor_creation() {
        let config = TelemetryConfig::default();
        let monitor = PerformanceMonitor::new(&config).await;
        assert!(monitor.is_ok());
    }

    #[tokio::test]
    async fn test_benchmark_execution() {
        let config = TelemetryConfig::default();
        let monitor = PerformanceMonitor::new(&config).await.unwrap();

        let result = monitor.run_benchmark("test_benchmark", || {
            // Simple test operation
            let _sum: u64 = (0..1000).sum();
            Ok(())
        }).await;

        assert!(result.is_ok());
        let benchmark = result.unwrap();
        assert_eq!(benchmark.name, "test_benchmark");
        assert!(benchmark.operations_per_second > 0.0);
        assert_eq!(benchmark.success_rate, 1.0);
    }

    #[tokio::test]
    async fn test_performance_metrics_default() {
        let metrics = PerformanceMetrics::default();
        assert_eq!(metrics.system_performance.cpu_usage_percent, 0.0);
        assert_eq!(metrics.network_performance.connection_count, 0);
        assert_eq!(metrics.container_performance.total_containers, 0);
        assert_eq!(metrics.user_performance.active_sessions, 0);
    }

    #[tokio::test]
    async fn test_performance_collection() {
        let metrics = PerformanceMonitor::collect_current_metrics().await;
        assert!(metrics.is_ok());
    }
}