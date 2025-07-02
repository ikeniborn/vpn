use crate::{ContainerdError, Result};
use chrono::{DateTime, Utc};
use futures_util::Stream;
use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;
use tokio::time::interval;
use tonic::transport::Channel;
use tracing::{debug, info, warn};
use vpn_runtime::ContainerStats;

/// Extended statistics for containerd containers
#[derive(Debug, Clone, serde::Serialize)]
pub struct ContainerdStats {
    pub container_id: String,
    pub timestamp: DateTime<Utc>,
    
    // CPU statistics
    pub cpu_usage_total: u64,
    pub cpu_usage_user: u64,
    pub cpu_usage_system: u64,
    pub cpu_throttling_periods: u64,
    pub cpu_throttling_throttled: u64,
    pub cpu_percent: f64,
    
    // Memory statistics
    pub memory_usage: u64,
    pub memory_limit: u64,
    pub memory_cache: u64,
    pub memory_rss: u64,
    pub memory_swap: u64,
    pub memory_percent: f64,
    
    // Network statistics
    pub network_rx_bytes: u64,
    pub network_tx_bytes: u64,
    pub network_rx_packets: u64,
    pub network_tx_packets: u64,
    pub network_rx_errors: u64,
    pub network_tx_errors: u64,
    
    // Block I/O statistics
    pub block_read_bytes: u64,
    pub block_write_bytes: u64,
    pub block_read_iops: u64,
    pub block_write_iops: u64,
    
    // Process statistics
    pub pids_current: u64,
    pub pids_limit: u64,
}

impl Default for ContainerdStats {
    fn default() -> Self {
        Self {
            container_id: String::new(),
            timestamp: Utc::now(),
            cpu_usage_total: 0,
            cpu_usage_user: 0,
            cpu_usage_system: 0,
            cpu_throttling_periods: 0,
            cpu_throttling_throttled: 0,
            cpu_percent: 0.0,
            memory_usage: 0,
            memory_limit: 0,
            memory_cache: 0,
            memory_rss: 0,
            memory_swap: 0,
            memory_percent: 0.0,
            network_rx_bytes: 0,
            network_tx_bytes: 0,
            network_rx_packets: 0,
            network_tx_packets: 0,
            network_rx_errors: 0,
            network_tx_errors: 0,
            block_read_bytes: 0,
            block_write_bytes: 0,
            block_read_iops: 0,
            block_write_iops: 0,
            pids_current: 0,
            pids_limit: 0,
        }
    }
}

impl From<ContainerdStats> for ContainerStats {
    fn from(stats: ContainerdStats) -> Self {
        Self {
            cpu_percent: stats.cpu_percent,
            memory_usage: stats.memory_usage,
            memory_limit: stats.memory_limit,
            memory_percent: stats.memory_percent,
            network_rx: stats.network_rx_bytes,
            network_tx: stats.network_tx_bytes,
            block_read: stats.block_read_bytes,
            block_write: stats.block_write_bytes,
            pids: stats.pids_current,
        }
    }
}

/// Statistics collection configuration
#[derive(Debug, Clone)]
pub struct StatsConfig {
    pub enabled: bool,
    pub collection_interval: Duration,
    pub retention_period: Duration,
    pub max_history_entries: usize,
    pub collect_extended_stats: bool,
}

impl Default for StatsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            collection_interval: Duration::from_secs(30),
            retention_period: Duration::from_secs(24 * 60 * 60), // 24 hours
            max_history_entries: 2880, // 24 hours at 30-second intervals
            collect_extended_stats: true,
        }
    }
}

/// Historical statistics data
#[derive(Debug, Clone)]
pub struct StatsHistory {
    pub container_id: String,
    pub entries: Vec<ContainerdStats>,
    pub last_collection: DateTime<Utc>,
}

impl StatsHistory {
    fn new(container_id: String) -> Self {
        Self {
            container_id,
            entries: Vec::new(),
            last_collection: Utc::now(),
        }
    }

    fn add_entry(&mut self, stats: ContainerdStats, max_entries: usize) {
        self.entries.push(stats);
        self.last_collection = Utc::now();
        
        // Remove old entries if we exceed the limit
        if self.entries.len() > max_entries {
            let remove_count = self.entries.len() - max_entries;
            self.entries.drain(0..remove_count);
        }
    }

    fn cleanup_old_entries(&mut self, retention_period: Duration) {
        let cutoff = Utc::now() - chrono::Duration::from_std(retention_period).unwrap_or_default();
        self.entries.retain(|entry| entry.timestamp > cutoff);
    }

    pub fn get_latest(&self) -> Option<&ContainerdStats> {
        self.entries.last()
    }

    pub fn get_average_over_period(&self, period: Duration) -> Option<ContainerdStats> {
        let cutoff = Utc::now() - chrono::Duration::from_std(period).unwrap_or_default();
        let recent_entries: Vec<&ContainerdStats> = self.entries
            .iter()
            .filter(|entry| entry.timestamp > cutoff)
            .collect();

        if recent_entries.is_empty() {
            return None;
        }

        let count = recent_entries.len() as u64;
        let mut avg_stats = ContainerdStats::default();
        avg_stats.container_id = self.container_id.clone();
        avg_stats.timestamp = Utc::now();

        for entry in &recent_entries {
            avg_stats.cpu_usage_total += entry.cpu_usage_total;
            avg_stats.cpu_percent += entry.cpu_percent;
            avg_stats.memory_usage += entry.memory_usage;
            avg_stats.memory_percent += entry.memory_percent;
            avg_stats.network_rx_bytes += entry.network_rx_bytes;
            avg_stats.network_tx_bytes += entry.network_tx_bytes;
            avg_stats.block_read_bytes += entry.block_read_bytes;
            avg_stats.block_write_bytes += entry.block_write_bytes;
            avg_stats.pids_current += entry.pids_current;
        }

        // Calculate averages
        avg_stats.cpu_usage_total /= count;
        avg_stats.cpu_percent /= count as f64;
        avg_stats.memory_usage /= count;
        avg_stats.memory_percent /= count as f64;
        avg_stats.network_rx_bytes /= count;
        avg_stats.network_tx_bytes /= count;
        avg_stats.block_read_bytes /= count;
        avg_stats.block_write_bytes /= count;
        avg_stats.pids_current /= count;

        // Use latest values for limits and non-averaged stats
        if let Some(latest) = recent_entries.last() {
            avg_stats.memory_limit = latest.memory_limit;
            avg_stats.pids_limit = latest.pids_limit;
        }

        Some(avg_stats)
    }
}

/// Statistics collector for containerd containers
pub struct StatsCollector {
    channel: Channel,
    namespace: String,
    config: StatsConfig,
    history: HashMap<String, StatsHistory>,
    collection_active: bool,
    last_cpu_stats: HashMap<String, (u64, DateTime<Utc>)>, // For CPU percentage calculation
}

impl StatsCollector {
    pub fn new(channel: Channel, namespace: String) -> Self {
        Self {
            channel,
            namespace,
            config: StatsConfig::default(),
            history: HashMap::new(),
            collection_active: false,
            last_cpu_stats: HashMap::new(),
        }
    }

    pub fn with_config(mut self, config: StatsConfig) -> Self {
        self.config = config;
        self
    }

    /// Add a container to statistics collection
    pub fn add_container(&mut self, container_id: String) {
        debug!("Adding container to statistics collection: {}", container_id);
        self.history.insert(container_id.clone(), StatsHistory::new(container_id));
    }

    /// Remove a container from statistics collection
    pub fn remove_container(&mut self, container_id: &str) {
        debug!("Removing container from statistics collection: {}", container_id);
        self.history.remove(container_id);
        self.last_cpu_stats.remove(container_id);
    }

    /// Collect current statistics for a container
    pub async fn collect_container_stats(&mut self, container_id: &str) -> Result<ContainerdStats> {
        if !self.config.enabled {
            return Ok(ContainerdStats {
                container_id: container_id.to_string(),
                ..Default::default()
            });
        }

        debug!("Collecting statistics for container: {}", container_id);

        // For now, return mock statistics
        // In a real implementation, you would:
        // 1. Read cgroup statistics from /sys/fs/cgroup/
        // 2. Query containerd task metrics
        // 3. Collect network interface statistics
        let stats = self.collect_mock_stats(container_id).await?;

        // Add to history
        if let Some(history) = self.history.get_mut(container_id) {
            history.add_entry(stats.clone(), self.config.max_history_entries);
        }

        Ok(stats)
    }

    /// Mock statistics collection (placeholder for real implementation)
    async fn collect_mock_stats(&mut self, container_id: &str) -> Result<ContainerdStats> {
        use rand::Rng;
        let mut rng = rand::thread_rng();

        // Calculate CPU percentage based on previous measurement
        let cpu_percent = if let Some((_last_cpu, last_time)) = self.last_cpu_stats.get(container_id) {
            let time_diff = Utc::now().signed_duration_since(*last_time).num_milliseconds();
            if time_diff > 0 {
                // Simulate CPU usage calculation
                rng.gen_range(0.0..50.0)
            } else {
                0.0
            }
        } else {
            rng.gen_range(0.0..50.0)
        };

        let current_cpu = rng.gen_range(1000000..10000000);
        self.last_cpu_stats.insert(container_id.to_string(), (current_cpu, Utc::now()));

        Ok(ContainerdStats {
            container_id: container_id.to_string(),
            timestamp: Utc::now(),
            
            cpu_usage_total: current_cpu,
            cpu_usage_user: current_cpu * 70 / 100,
            cpu_usage_system: current_cpu * 30 / 100,
            cpu_throttling_periods: rng.gen_range(0..100),
            cpu_throttling_throttled: rng.gen_range(0..10),
            cpu_percent,
            
            memory_usage: rng.gen_range(50_000_000..500_000_000), // 50MB to 500MB
            memory_limit: 1_000_000_000, // 1GB
            memory_cache: rng.gen_range(10_000_000..50_000_000),
            memory_rss: rng.gen_range(40_000_000..450_000_000),
            memory_swap: rng.gen_range(0..10_000_000),
            memory_percent: cpu_percent * 0.8, // Roughly correlated with CPU
            
            network_rx_bytes: rng.gen_range(1_000_000..100_000_000),
            network_tx_bytes: rng.gen_range(500_000..50_000_000),
            network_rx_packets: rng.gen_range(1000..100000),
            network_tx_packets: rng.gen_range(500..50000),
            network_rx_errors: rng.gen_range(0..10),
            network_tx_errors: rng.gen_range(0..5),
            
            block_read_bytes: rng.gen_range(1_000_000..100_000_000),
            block_write_bytes: rng.gen_range(500_000..50_000_000),
            block_read_iops: rng.gen_range(100..10000),
            block_write_iops: rng.gen_range(50..5000),
            
            pids_current: rng.gen_range(1..50),
            pids_limit: 1024,
        })
    }

    /// Start continuous statistics collection
    pub async fn start_collection(&mut self) -> Result<Pin<Box<dyn Stream<Item = Result<HashMap<String, ContainerdStats>>> + Send>>> {
        self.collection_active = true;
        info!("Starting statistics collection for {} containers", self.history.len());

        let container_ids: Vec<String> = self.history.keys().cloned().collect();
        let config = self.config.clone();
        let channel = self.channel.clone();
        let namespace = self.namespace.clone();

        let stream = async_stream::stream! {
            let mut interval = interval(config.collection_interval);
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

            loop {
                interval.tick().await;
                
                let mut stats_map = HashMap::new();
                
                // Collect stats for all containers
                for container_id in &container_ids {
                    let mut collector = StatsCollector::new(channel.clone(), namespace.clone());
                    collector.config = config.clone();
                    
                    match collector.collect_container_stats(container_id).await {
                        Ok(stats) => {
                            stats_map.insert(container_id.clone(), stats);
                        }
                        Err(e) => {
                            warn!("Failed to collect stats for container {}: {}", container_id, e);
                        }
                    }
                }
                
                if !stats_map.is_empty() {
                    yield Ok(stats_map);
                }
            }
        };

        Ok(Box::pin(stream))
    }

    /// Stop statistics collection
    pub fn stop_collection(&mut self) {
        self.collection_active = false;
        info!("Stopped statistics collection");
    }

    /// Get current statistics for a container
    pub fn get_current_stats(&self, container_id: &str) -> Option<&ContainerdStats> {
        self.history.get(container_id)?.get_latest()
    }

    /// Get historical statistics for a container
    pub fn get_history(&self, container_id: &str) -> Option<&StatsHistory> {
        self.history.get(container_id)
    }

    /// Get statistics averaged over a period
    pub fn get_average_stats(&self, container_id: &str, period: Duration) -> Option<ContainerdStats> {
        self.history.get(container_id)?.get_average_over_period(period)
    }

    /// Get statistics for all containers
    pub fn get_all_current_stats(&self) -> HashMap<String, ContainerdStats> {
        self.history.iter()
            .filter_map(|(id, history)| {
                history.get_latest().map(|stats| (id.clone(), stats.clone()))
            })
            .collect()
    }

    /// Cleanup old statistics based on retention policy
    pub fn cleanup_old_stats(&mut self) {
        debug!("Cleaning up old statistics based on retention policy");
        
        for history in self.history.values_mut() {
            history.cleanup_old_entries(self.config.retention_period);
        }
    }

    /// Export statistics as JSON
    pub fn export_stats_json(&self, container_id: &str) -> Result<String> {
        let history = self.history.get(container_id)
            .ok_or_else(|| ContainerdError::OperationFailed {
                operation: "export_stats".to_string(),
                message: format!("No statistics found for container: {}", container_id),
            })?;

        serde_json::to_string_pretty(&history.entries)
            .map_err(|e| ContainerdError::JsonError(e))
    }

    /// Export aggregated statistics summary
    pub fn export_summary_json(&self) -> Result<String> {
        let summary: HashMap<String, serde_json::Value> = self.history.iter()
            .map(|(id, history)| {
                let latest = history.get_latest();
                let avg_1h = history.get_average_over_period(Duration::from_secs(3600));
                let avg_24h = history.get_average_over_period(Duration::from_secs(86400));
                
                let container_summary = serde_json::json!({
                    "container_id": id,
                    "entry_count": history.entries.len(),
                    "last_collection": history.last_collection,
                    "latest": latest,
                    "average_1h": avg_1h,
                    "average_24h": avg_24h
                });
                
                (id.clone(), container_summary)
            })
            .collect();

        serde_json::to_string_pretty(&summary)
            .map_err(|e| ContainerdError::JsonError(e))
    }

    /// Get resource usage trends
    pub fn get_usage_trends(&self, container_id: &str, period: Duration) -> Option<UsageTrends> {
        let history = self.history.get(container_id)?;
        let cutoff = Utc::now() - chrono::Duration::from_std(period).unwrap_or_default();
        
        let recent_entries: Vec<&ContainerdStats> = history.entries
            .iter()
            .filter(|entry| entry.timestamp > cutoff)
            .collect();

        if recent_entries.len() < 2 {
            return None;
        }

        let first = recent_entries.first()?;
        let last = recent_entries.last()?;

        Some(UsageTrends {
            container_id: container_id.to_string(),
            period_start: first.timestamp,
            period_end: last.timestamp,
            cpu_trend: calculate_trend(&recent_entries, |s| s.cpu_percent),
            memory_trend: calculate_trend(&recent_entries, |s| s.memory_percent),
            network_rx_trend: calculate_linear_trend(&recent_entries, |s| s.network_rx_bytes as f64),
            network_tx_trend: calculate_linear_trend(&recent_entries, |s| s.network_tx_bytes as f64),
            block_read_trend: calculate_linear_trend(&recent_entries, |s| s.block_read_bytes as f64),
            block_write_trend: calculate_linear_trend(&recent_entries, |s| s.block_write_bytes as f64),
        })
    }

    /// Check if collection is active
    pub fn is_collection_active(&self) -> bool {
        self.collection_active
    }

    /// Get collection configuration
    pub fn get_config(&self) -> &StatsConfig {
        &self.config
    }

    /// Update collection configuration
    pub fn update_config(&mut self, config: StatsConfig) {
        self.config = config;
        info!("Updated statistics collection configuration");
    }
}

/// Usage trends analysis
#[derive(Debug, Clone, serde::Serialize)]
pub struct UsageTrends {
    pub container_id: String,
    pub period_start: DateTime<Utc>,
    pub period_end: DateTime<Utc>,
    pub cpu_trend: TrendDirection,
    pub memory_trend: TrendDirection,
    pub network_rx_trend: f64, // bytes per second trend
    pub network_tx_trend: f64,
    pub block_read_trend: f64,
    pub block_write_trend: f64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub enum TrendDirection {
    Increasing,
    Decreasing,
    Stable,
    Volatile,
}

fn calculate_trend<F>(entries: &[&ContainerdStats], extractor: F) -> TrendDirection
where
    F: Fn(&ContainerdStats) -> f64,
{
    if entries.len() < 3 {
        return TrendDirection::Stable;
    }

    let values: Vec<f64> = entries.iter().map(|entry| extractor(entry)).collect();
    let first_half_avg = values.iter().take(values.len() / 2).sum::<f64>() / (values.len() / 2) as f64;
    let second_half_avg = values.iter().skip(values.len() / 2).sum::<f64>() / (values.len() - values.len() / 2) as f64;
    
    let change_percent = (second_half_avg - first_half_avg) / first_half_avg * 100.0;
    
    // Calculate volatility (standard deviation)
    let mean = values.iter().sum::<f64>() / values.len() as f64;
    let variance = values.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / values.len() as f64;
    let std_dev = variance.sqrt();
    let coefficient_of_variation = std_dev / mean;

    if coefficient_of_variation > 0.3 {
        TrendDirection::Volatile
    } else if change_percent > 10.0 {
        TrendDirection::Increasing
    } else if change_percent < -10.0 {
        TrendDirection::Decreasing
    } else {
        TrendDirection::Stable
    }
}

fn calculate_linear_trend<F>(entries: &[&ContainerdStats], extractor: F) -> f64
where
    F: Fn(&ContainerdStats) -> f64,
{
    if entries.len() < 2 {
        return 0.0;
    }

    let first = entries.first().unwrap();
    let last = entries.last().unwrap();
    
    let value_diff = extractor(last) - extractor(first);
    let time_diff = last.timestamp.signed_duration_since(first.timestamp).num_seconds() as f64;
    
    if time_diff > 0.0 {
        value_diff / time_diff // Rate per second
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stats_default() {
        let stats = ContainerdStats::default();
        assert_eq!(stats.container_id, "");
        assert_eq!(stats.cpu_percent, 0.0);
        assert_eq!(stats.memory_usage, 0);
    }

    #[test]
    fn test_stats_config_default() {
        let config = StatsConfig::default();
        assert!(config.enabled);
        assert_eq!(config.collection_interval, Duration::from_secs(30));
        assert_eq!(config.max_history_entries, 2880);
    }

    #[test]
    fn test_stats_history() {
        let mut history = StatsHistory::new("test-container".to_string());
        assert_eq!(history.container_id, "test-container");
        assert!(history.entries.is_empty());

        let stats = ContainerdStats {
            container_id: "test-container".to_string(),
            cpu_percent: 50.0,
            ..Default::default()
        };

        history.add_entry(stats, 10);
        assert_eq!(history.entries.len(), 1);
        assert_eq!(history.get_latest().unwrap().cpu_percent, 50.0);
    }

    #[test]
    fn test_container_stats_conversion() {
        let containerd_stats = ContainerdStats {
            container_id: "test".to_string(),
            cpu_percent: 25.5,
            memory_usage: 1000000,
            memory_limit: 2000000,
            memory_percent: 50.0,
            network_rx_bytes: 5000,
            network_tx_bytes: 3000,
            block_read_bytes: 10000,
            block_write_bytes: 8000,
            pids_current: 10,
            ..Default::default()
        };

        let runtime_stats: ContainerStats = containerd_stats.into();
        assert_eq!(runtime_stats.cpu_percent, 25.5);
        assert_eq!(runtime_stats.memory_usage, 1000000);
        assert_eq!(runtime_stats.memory_limit, 2000000);
        assert_eq!(runtime_stats.memory_percent, 50.0);
        assert_eq!(runtime_stats.network_rx, 5000);
        assert_eq!(runtime_stats.network_tx, 3000);
        assert_eq!(runtime_stats.block_read, 10000);
        assert_eq!(runtime_stats.block_write, 8000);
        assert_eq!(runtime_stats.pids, 10);
    }

    #[test]
    fn test_trend_calculation() {
        let entries = vec![
            ContainerdStats { cpu_percent: 10.0, ..Default::default() },
            ContainerdStats { cpu_percent: 20.0, ..Default::default() },
            ContainerdStats { cpu_percent: 30.0, ..Default::default() },
            ContainerdStats { cpu_percent: 40.0, ..Default::default() },
        ];
        let entry_refs: Vec<&ContainerdStats> = entries.iter().collect();
        
        let trend = calculate_trend(&entry_refs, |s| s.cpu_percent);
        matches!(trend, TrendDirection::Increasing);
    }
}