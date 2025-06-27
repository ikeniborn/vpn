use std::collections::HashMap;
use std::path::Path;
use std::process::Command;
use chrono::{DateTime, Utc, Duration};
use serde::{Deserialize, Serialize};
use vpn_docker::{ContainerManager, HealthChecker};
use vpn_users::UserManager;
use crate::error::{MonitorError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrafficStats {
    pub user_id: String,
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub packets_sent: u64,
    pub packets_received: u64,
    pub connections: u64,
    pub last_activity: DateTime<Utc>,
    pub session_duration: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrafficSummary {
    pub total_bytes_sent: u64,
    pub total_bytes_received: u64,
    pub total_connections: u64,
    pub active_users: u64,
    pub peak_bandwidth: u64,
    pub average_bandwidth: u64,
    pub period_start: DateTime<Utc>,
    pub period_end: DateTime<Utc>,
    pub user_stats: Vec<TrafficStats>,
}

#[derive(Debug, Clone)]
pub struct MonitoringConfig {
    pub collection_interval: Duration,
    pub retention_days: u32,
    pub bandwidth_alert_threshold: u64,
    pub connection_alert_threshold: u64,
}

pub struct TrafficMonitor {
    container_manager: ContainerManager,
    health_checker: HealthChecker,
    config: MonitoringConfig,
}

impl TrafficMonitor {
    pub fn new(config: MonitoringConfig) -> Result<Self> {
        let container_manager = ContainerManager::new()?;
        let health_checker = HealthChecker::new()?;
        
        Ok(Self {
            container_manager,
            health_checker,
            config,
        })
    }
    
    pub async fn collect_traffic_stats(&self, install_path: &Path) -> Result<TrafficSummary> {
        let mut summary = TrafficSummary {
            total_bytes_sent: 0,
            total_bytes_received: 0,
            total_connections: 0,
            active_users: 0,
            peak_bandwidth: 0,
            average_bandwidth: 0,
            period_start: Utc::now() - self.config.collection_interval,
            period_end: Utc::now(),
            user_stats: Vec::new(),
        };
        
        // Collect Docker container stats
        let container_stats = self.collect_container_stats().await?;
        
        // Collect vnStat data if available
        let vnstat_data = self.collect_vnstat_data().await.unwrap_or_default();
        
        // Parse Xray logs for user-specific data
        let user_stats = self.parse_xray_logs(install_path).await?;
        
        // Combine all data sources
        summary.user_stats = user_stats;
        summary.total_bytes_sent = summary.user_stats.iter().map(|u| u.bytes_sent).sum();
        summary.total_bytes_received = summary.user_stats.iter().map(|u| u.bytes_received).sum();
        summary.total_connections = summary.user_stats.iter().map(|u| u.connections).sum();
        summary.active_users = summary.user_stats.iter()
            .filter(|u| u.last_activity > Utc::now() - Duration::hours(1))
            .count() as u64;
        
        // Calculate bandwidth metrics
        let total_bytes = summary.total_bytes_sent + summary.total_bytes_received;
        let period_seconds = self.config.collection_interval.num_seconds() as u64;
        if period_seconds > 0 {
            summary.average_bandwidth = total_bytes / period_seconds;
        }
        
        Ok(summary)
    }
    
    async fn collect_container_stats(&self) -> Result<HashMap<String, (u64, u64)>> {
        let containers = ["xray", "shadowbox"];
        let mut stats = HashMap::new();
        
        for container in &containers {
            if self.container_manager.container_exists(container).await {
                match self.health_checker.check_container_health(container).await {
                    Ok(health) => {
                        stats.insert(
                            container.to_string(),
                            (health.network_rx_bytes, health.network_tx_bytes),
                        );
                    }
                    Err(e) => {
                        eprintln!("Warning: Failed to get stats for {}: {}", container, e);
                    }
                }
            }
        }
        
        Ok(stats)
    }
    
    async fn collect_vnstat_data(&self) -> Result<HashMap<String, (u64, u64)>> {
        let output = Command::new("vnstat")
            .arg("-i")
            .arg("eth0") // Default interface
            .arg("--json")
            .output();
        
        match output {
            Ok(output) if output.status.success() => {
                let json_str = String::from_utf8_lossy(&output.stdout);
                let data: serde_json::Value = serde_json::from_str(&json_str)
                    .map_err(|e| MonitorError::DataParsingError(e.to_string()))?;
                
                let mut stats = HashMap::new();
                
                if let Some(interfaces) = data["interfaces"].as_array() {
                    for interface in interfaces {
                        if let (Some(name), Some(traffic)) = (
                            interface["name"].as_str(),
                            interface["traffic"].as_object(),
                        ) {
                            let default_map = serde_json::Map::new();
                            let total = traffic["total"].as_object().unwrap_or(&default_map);
                            let rx = total["rx"].as_u64().unwrap_or(0);
                            let tx = total["tx"].as_u64().unwrap_or(0);
                            
                            stats.insert(name.to_string(), (rx, tx));
                        }
                    }
                }
                
                Ok(stats)
            }
            _ => Ok(HashMap::new()), // vnstat not available or failed
        }
    }
    
    async fn parse_xray_logs(&self, install_path: &Path) -> Result<Vec<TrafficStats>> {
        let access_log = install_path.join("logs/access.log");
        if !access_log.exists() {
            return Ok(Vec::new());
        }
        
        let log_content = std::fs::read_to_string(&access_log)?;
        let mut user_stats: HashMap<String, TrafficStats> = HashMap::new();
        
        // Parse Xray access log format
        // Example: 2024/01/01 12:00:00 [Info] [user_id] accepted connection from [IP]
        let log_regex = regex::Regex::new(
            r"(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*\[(\w+)\].*accepted.*from.*"
        )?;
        
        for line in log_content.lines() {
            if let Some(captures) = log_regex.captures(line) {
                let timestamp_str = &captures[1];
                let user_id = &captures[2];
                
                // Parse timestamp
                let timestamp = chrono::NaiveDateTime::parse_from_str(
                    timestamp_str,
                    "%Y/%m/%d %H:%M:%S"
                ).ok().map(|dt| DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc));
                
                if let Some(timestamp) = timestamp {
                    let stats = user_stats.entry(user_id.to_string()).or_insert(TrafficStats {
                        user_id: user_id.to_string(),
                        bytes_sent: 0,
                        bytes_received: 0,
                        packets_sent: 0,
                        packets_received: 0,
                        connections: 0,
                        last_activity: timestamp,
                        session_duration: Duration::zero(),
                    });
                    
                    stats.connections += 1;
                    stats.last_activity = timestamp;
                }
            }
        }
        
        Ok(user_stats.into_values().collect())
    }
    
    pub async fn get_user_traffic_history(
        &self,
        user_id: &str,
        days: u32,
    ) -> Result<Vec<TrafficStats>> {
        // This would typically read from a database or log files
        // For now, we'll return mock data based on current stats
        let mut history = Vec::new();
        
        let end_date = Utc::now();
        let start_date = end_date - Duration::days(days as i64);
        
        // Generate daily stats (mock implementation)
        let mut current_date = start_date;
        while current_date <= end_date {
            let stats = TrafficStats {
                user_id: user_id.to_string(),
                bytes_sent: (current_date.timestamp() % 1000000) as u64 * 1024,
                bytes_received: (current_date.timestamp() % 800000) as u64 * 1024,
                packets_sent: (current_date.timestamp() % 10000) as u64,
                packets_received: (current_date.timestamp() % 8000) as u64,
                connections: (current_date.timestamp() % 100) as u64,
                last_activity: current_date,
                session_duration: Duration::hours(2),
            };
            
            history.push(stats);
            current_date = current_date + Duration::days(1);
        }
        
        Ok(history)
    }
    
    pub async fn get_top_users(&self, limit: usize) -> Result<Vec<TrafficStats>> {
        // This would typically query a database
        // For now, we'll return mock data
        let mut users = Vec::new();
        
        for i in 0..limit.min(10) {
            let stats = TrafficStats {
                user_id: format!("user_{}", i),
                bytes_sent: (1000000 - i * 100000) as u64,
                bytes_received: (800000 - i * 80000) as u64,
                packets_sent: (10000 - i * 1000) as u64,
                packets_received: (8000 - i * 800) as u64,
                connections: (100 - i * 10) as u64,
                last_activity: Utc::now() - Duration::hours(i as i64),
                session_duration: Duration::hours(3),
            };
            
            users.push(stats);
        }
        
        Ok(users)
    }
    
    pub async fn reset_user_stats(&self, user_id: &str, install_path: &Path) -> Result<()> {
        // This would typically update a database
        // For Xray, we might need to restart the service or clear logs
        
        let user_log_pattern = format!("*{}*", user_id);
        let logs_dir = install_path.join("logs");
        
        // Archive current logs
        let archive_name = format!("archive_{}_{}.log", user_id, Utc::now().timestamp());
        let archive_path = logs_dir.join(&archive_name);
        
        // Create new empty log files
        let access_log = logs_dir.join("access.log");
        if access_log.exists() {
            std::fs::copy(&access_log, &archive_path)?;
            
            // Filter out the user's entries
            let content = std::fs::read_to_string(&access_log)?;
            let filtered_content: String = content
                .lines()
                .filter(|line| !line.contains(user_id))
                .map(|line| format!("{}\n", line))
                .collect();
            
            std::fs::write(&access_log, filtered_content)?;
        }
        
        Ok(())
    }
    
    pub fn calculate_bandwidth_usage(&self, stats: &[TrafficStats], period: Duration) -> u64 {
        let total_bytes: u64 = stats.iter()
            .map(|s| s.bytes_sent + s.bytes_received)
            .sum();
        
        let period_seconds = period.num_seconds() as u64;
        if period_seconds > 0 {
            total_bytes / period_seconds // bytes per second
        } else {
            0
        }
    }
    
    pub fn format_bytes(bytes: u64) -> String {
        const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
        const THRESHOLD: f64 = 1024.0;
        
        if bytes == 0 {
            return "0 B".to_string();
        }
        
        let mut size = bytes as f64;
        let mut unit_index = 0;
        
        while size >= THRESHOLD && unit_index < UNITS.len() - 1 {
            size /= THRESHOLD;
            unit_index += 1;
        }
        
        format!("{:.2} {}", size, UNITS[unit_index])
    }
}

impl Default for MonitoringConfig {
    fn default() -> Self {
        Self {
            collection_interval: Duration::minutes(5),
            retention_days: 30,
            bandwidth_alert_threshold: 100 * 1024 * 1024, // 100 MB/s
            connection_alert_threshold: 1000,
        }
    }
}

impl TrafficStats {
    pub fn total_bytes(&self) -> u64 {
        self.bytes_sent + self.bytes_received
    }
    
    pub fn total_packets(&self) -> u64 {
        self.packets_sent + self.packets_received
    }
    
    pub fn is_active(&self, threshold: Duration) -> bool {
        Utc::now().signed_duration_since(self.last_activity) < threshold
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_format_bytes() {
        assert_eq!(TrafficMonitor::format_bytes(0), "0 B");
        assert_eq!(TrafficMonitor::format_bytes(1024), "1.00 KB");
        assert_eq!(TrafficMonitor::format_bytes(1048576), "1.00 MB");
        assert_eq!(TrafficMonitor::format_bytes(1073741824), "1.00 GB");
    }
    
    #[test]
    fn test_traffic_stats() {
        let stats = TrafficStats {
            user_id: "test".to_string(),
            bytes_sent: 1000,
            bytes_received: 2000,
            packets_sent: 10,
            packets_received: 20,
            connections: 5,
            last_activity: Utc::now(),
            session_duration: Duration::hours(1),
        };
        
        assert_eq!(stats.total_bytes(), 3000);
        assert_eq!(stats.total_packets(), 30);
        assert!(stats.is_active(Duration::hours(2)));
    }
}