use std::collections::HashMap;
use std::process::Command;
use std::time::Duration;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use vpn_docker::{ContainerManager, HealthChecker};
use crate::error::{MonitorError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub overall_status: ServiceStatus,
    pub containers: Vec<ContainerHealth>,
    pub system_metrics: SystemMetrics,
    pub network_status: NetworkStatus,
    pub last_check: DateTime<Utc>,
    pub uptime: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerHealth {
    pub name: String,
    pub status: ServiceStatus,
    pub cpu_usage: f64,
    pub memory_usage: u64,
    pub memory_limit: u64,
    pub memory_percentage: f64,
    pub network_io: NetworkIO,
    pub restart_count: u32,
    pub uptime: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub cpu_usage: f64,
    pub memory_usage: u64,
    pub memory_total: u64,
    pub memory_percentage: f64,
    pub disk_usage: u64,
    pub disk_total: u64,
    pub disk_percentage: f64,
    pub load_average: (f64, f64, f64),
    pub network_interfaces: Vec<NetworkInterface>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkStatus {
    pub connectivity: bool,
    pub dns_resolution: bool,
    pub external_access: bool,
    pub port_accessibility: HashMap<u16, bool>,
    pub response_times: HashMap<String, u64>, // milliseconds
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkIO {
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub rx_packets: u64,
    pub tx_packets: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInterface {
    pub name: String,
    pub ip_address: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub is_up: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServiceStatus {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

pub struct HealthMonitor {
    container_manager: ContainerManager,
    health_checker: HealthChecker,
}

impl HealthMonitor {
    pub fn new() -> Result<Self> {
        let container_manager = ContainerManager::new()?;
        let health_checker = HealthChecker::new()?;
        
        Ok(Self {
            container_manager,
            health_checker,
        })
    }
    
    pub async fn check_overall_health(&self) -> Result<HealthStatus> {
        let _start_time = std::time::Instant::now();
        
        // Check container health
        let containers = self.check_container_health().await?;
        
        // Collect system metrics
        let system_metrics = self.collect_system_metrics().await?;
        
        // Check network status
        let network_status = self.check_network_status().await?;
        
        // Determine overall status
        let overall_status = self.calculate_overall_status(&containers, &system_metrics, &network_status);
        
        // Calculate uptime (simplified - would typically come from system)
        let uptime = self.get_system_uptime().unwrap_or(Duration::from_secs(0));
        
        Ok(HealthStatus {
            overall_status,
            containers,
            system_metrics,
            network_status,
            last_check: Utc::now(),
            uptime,
        })
    }
    
    async fn check_container_health(&self) -> Result<Vec<ContainerHealth>> {
        let container_names = ["xray", "shadowbox", "watchtower"];
        let mut containers = Vec::new();
        
        for &name in &container_names {
            if self.container_manager.container_exists(name).await {
                match self.health_checker.check_container_health(name).await {
                    Ok(health) => {
                        let memory_percentage = if health.memory_limit > 0 {
                            (health.memory_usage as f64 / health.memory_limit as f64) * 100.0
                        } else {
                            0.0
                        };
                        
                        let status = if health.is_running {
                            if health.cpu_usage > 90.0 || memory_percentage > 90.0 {
                                ServiceStatus::Critical
                            } else if health.cpu_usage > 70.0 || memory_percentage > 70.0 {
                                ServiceStatus::Warning
                            } else {
                                ServiceStatus::Healthy
                            }
                        } else {
                            ServiceStatus::Critical
                        };
                        
                        containers.push(ContainerHealth {
                            name: name.to_string(),
                            status,
                            cpu_usage: health.cpu_usage,
                            memory_usage: health.memory_usage,
                            memory_limit: health.memory_limit,
                            memory_percentage,
                            network_io: NetworkIO {
                                rx_bytes: health.network_rx_bytes,
                                tx_bytes: health.network_tx_bytes,
                                rx_packets: 0, // Not available from Docker stats
                                tx_packets: 0,
                            },
                            restart_count: 0, // Would need to be tracked separately
                            uptime: Duration::from_secs(3600), // Mock data
                        });
                    }
                    Err(_) => {
                        containers.push(ContainerHealth {
                            name: name.to_string(),
                            status: ServiceStatus::Unknown,
                            cpu_usage: 0.0,
                            memory_usage: 0,
                            memory_limit: 0,
                            memory_percentage: 0.0,
                            network_io: NetworkIO {
                                rx_bytes: 0,
                                tx_bytes: 0,
                                rx_packets: 0,
                                tx_packets: 0,
                            },
                            restart_count: 0,
                            uptime: Duration::from_secs(0),
                        });
                    }
                }
            }
        }
        
        Ok(containers)
    }
    
    async fn collect_system_metrics(&self) -> Result<SystemMetrics> {
        // Get CPU usage
        let cpu_usage = self.get_cpu_usage().await.unwrap_or(0.0);
        
        // Get memory info
        let (memory_usage, memory_total) = self.get_memory_info().await.unwrap_or((0, 0));
        let memory_percentage = if memory_total > 0 {
            (memory_usage as f64 / memory_total as f64) * 100.0
        } else {
            0.0
        };
        
        // Get disk info
        let (disk_usage, disk_total) = self.get_disk_info().await.unwrap_or((0, 0));
        let disk_percentage = if disk_total > 0 {
            (disk_usage as f64 / disk_total as f64) * 100.0
        } else {
            0.0
        };
        
        // Get load average
        let load_average = self.get_load_average().await.unwrap_or((0.0, 0.0, 0.0));
        
        // Get network interfaces
        let network_interfaces = self.get_network_interfaces().await.unwrap_or_default();
        
        Ok(SystemMetrics {
            cpu_usage,
            memory_usage,
            memory_total,
            memory_percentage,
            disk_usage,
            disk_total,
            disk_percentage,
            load_average,
            network_interfaces,
        })
    }
    
    async fn check_network_status(&self) -> Result<NetworkStatus> {
        let mut status = NetworkStatus {
            connectivity: false,
            dns_resolution: false,
            external_access: false,
            port_accessibility: HashMap::new(),
            response_times: HashMap::new(),
        };
        
        // Test DNS resolution
        let dns_start = std::time::Instant::now();
        if let Ok(_) = tokio::net::lookup_host("google.com:80").await {
            status.dns_resolution = true;
            status.response_times.insert(
                "dns".to_string(),
                dns_start.elapsed().as_millis() as u64,
            );
        }
        
        // Test external connectivity
        let http_start = std::time::Instant::now();
        if let Ok(response) = reqwest::get("https://httpbin.org/ip").await {
            if response.status().is_success() {
                status.external_access = true;
                status.connectivity = true;
                status.response_times.insert(
                    "external_http".to_string(),
                    http_start.elapsed().as_millis() as u64,
                );
            }
        }
        
        // Test common ports
        let test_ports = [80, 443, 22, 53];
        for &port in &test_ports {
            let port_start = std::time::Instant::now();
            let accessible = self.test_port_connectivity("127.0.0.1", port).await;
            status.port_accessibility.insert(port, accessible);
            
            if accessible {
                status.response_times.insert(
                    format!("port_{}", port),
                    port_start.elapsed().as_millis() as u64,
                );
            }
        }
        
        Ok(status)
    }
    
    async fn test_port_connectivity(&self, host: &str, port: u16) -> bool {
        match tokio::time::timeout(
            Duration::from_secs(3),
            tokio::net::TcpStream::connect(&format!("{}:{}", host, port)),
        ).await {
            Ok(Ok(_)) => true,
            _ => false,
        }
    }
    
    fn calculate_overall_status(
        &self,
        containers: &[ContainerHealth],
        system_metrics: &SystemMetrics,
        network_status: &NetworkStatus,
    ) -> ServiceStatus {
        // Check for critical issues
        let has_critical_containers = containers.iter()
            .any(|c| c.status == ServiceStatus::Critical);
        
        let has_critical_system_issues = 
            system_metrics.cpu_usage > 95.0 ||
            system_metrics.memory_percentage > 95.0 ||
            system_metrics.disk_percentage > 95.0;
        
        let has_network_issues = !network_status.connectivity || !network_status.dns_resolution;
        
        if has_critical_containers || has_critical_system_issues || has_network_issues {
            return ServiceStatus::Critical;
        }
        
        // Check for warnings
        let has_warning_containers = containers.iter()
            .any(|c| c.status == ServiceStatus::Warning);
        
        let has_warning_system_issues = 
            system_metrics.cpu_usage > 80.0 ||
            system_metrics.memory_percentage > 80.0 ||
            system_metrics.disk_percentage > 80.0;
        
        if has_warning_containers || has_warning_system_issues {
            return ServiceStatus::Warning;
        }
        
        // Check if we have enough healthy containers
        let healthy_containers = containers.iter()
            .filter(|c| c.status == ServiceStatus::Healthy)
            .count();
        
        if healthy_containers > 0 {
            ServiceStatus::Healthy
        } else {
            ServiceStatus::Unknown
        }
    }
    
    async fn get_cpu_usage(&self) -> Result<f64> {
        // Read from /proc/stat to calculate CPU usage
        let content = tokio::fs::read_to_string("/proc/stat").await?;
        
        if let Some(line) = content.lines().next() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 5 && parts[0] == "cpu" {
                let user: u64 = parts[1].parse().unwrap_or(0);
                let nice: u64 = parts[2].parse().unwrap_or(0);
                let system: u64 = parts[3].parse().unwrap_or(0);
                let idle: u64 = parts[4].parse().unwrap_or(0);
                
                let total = user + nice + system + idle;
                let used = total - idle;
                
                if total > 0 {
                    return Ok((used as f64 / total as f64) * 100.0);
                }
            }
        }
        
        Ok(0.0)
    }
    
    async fn get_memory_info(&self) -> Result<(u64, u64)> {
        let content = tokio::fs::read_to_string("/proc/meminfo").await?;
        
        let mut mem_total = 0u64;
        let mut mem_available = 0u64;
        
        for line in content.lines() {
            if line.starts_with("MemTotal:") {
                if let Some(value) = line.split_whitespace().nth(1) {
                    mem_total = value.parse::<u64>().unwrap_or(0) * 1024; // Convert KB to bytes
                }
            } else if line.starts_with("MemAvailable:") {
                if let Some(value) = line.split_whitespace().nth(1) {
                    mem_available = value.parse::<u64>().unwrap_or(0) * 1024; // Convert KB to bytes
                }
            }
        }
        
        let mem_used = mem_total.saturating_sub(mem_available);
        Ok((mem_used, mem_total))
    }
    
    async fn get_disk_info(&self) -> Result<(u64, u64)> {
        let output = Command::new("df")
            .arg("-B1") // Output in bytes
            .arg("/")
            .output()?;
        
        if output.status.success() {
            let output_str = String::from_utf8_lossy(&output.stdout);
            if let Some(line) = output_str.lines().nth(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    let total = parts[1].parse::<u64>().unwrap_or(0);
                    let used = parts[2].parse::<u64>().unwrap_or(0);
                    return Ok((used, total));
                }
            }
        }
        
        Ok((0, 0))
    }
    
    async fn get_load_average(&self) -> Result<(f64, f64, f64)> {
        let content = tokio::fs::read_to_string("/proc/loadavg").await?;
        
        let parts: Vec<&str> = content.trim().split_whitespace().collect();
        if parts.len() >= 3 {
            let load1 = parts[0].parse::<f64>().unwrap_or(0.0);
            let load5 = parts[1].parse::<f64>().unwrap_or(0.0);
            let load15 = parts[2].parse::<f64>().unwrap_or(0.0);
            return Ok((load1, load5, load15));
        }
        
        Ok((0.0, 0.0, 0.0))
    }
    
    async fn get_network_interfaces(&self) -> Result<Vec<NetworkInterface>> {
        let mut interfaces = Vec::new();
        
        // Read network interface statistics from /proc/net/dev
        let content = tokio::fs::read_to_string("/proc/net/dev").await?;
        
        for line in content.lines().skip(2) { // Skip header lines
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 10 {
                let name = parts[0].trim_end_matches(':').to_string();
                let rx_bytes = parts[1].parse::<u64>().unwrap_or(0);
                let tx_bytes = parts[9].parse::<u64>().unwrap_or(0);
                
                // Get IP address (simplified)
                let ip_address = if name == "lo" {
                    "127.0.0.1".to_string()
                } else {
                    "0.0.0.0".to_string() // Would need more complex logic
                };
                
                interfaces.push(NetworkInterface {
                    name,
                    ip_address,
                    rx_bytes,
                    tx_bytes,
                    is_up: true, // Would need to check interface flags
                });
            }
        }
        
        Ok(interfaces)
    }
    
    fn get_system_uptime(&self) -> Option<Duration> {
        if let Ok(content) = std::fs::read_to_string("/proc/uptime") {
            if let Some(uptime_str) = content.split_whitespace().next() {
                if let Ok(uptime_secs) = uptime_str.parse::<f64>() {
                    return Some(Duration::from_secs(uptime_secs as u64));
                }
            }
        }
        None
    }
    
    pub async fn run_health_check_command(&self, command: &str) -> Result<String> {
        let output = Command::new("sh")
            .arg("-c")
            .arg(command)
            .output()?;
        
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(MonitorError::HealthCheckError(
                format!("Command failed: {}", String::from_utf8_lossy(&output.stderr))
            ))
        }
    }
}

impl ServiceStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            ServiceStatus::Healthy => "healthy",
            ServiceStatus::Warning => "warning",
            ServiceStatus::Critical => "critical",
            ServiceStatus::Unknown => "unknown",
        }
    }
    
    pub fn as_emoji(&self) -> &'static str {
        match self {
            ServiceStatus::Healthy => "🟢",
            ServiceStatus::Warning => "🟡",
            ServiceStatus::Critical => "🔴",
            ServiceStatus::Unknown => "⚪",
        }
    }
}

impl HealthStatus {
    pub fn is_healthy(&self) -> bool {
        matches!(self.overall_status, ServiceStatus::Healthy)
    }
    
    pub fn has_warnings(&self) -> bool {
        matches!(self.overall_status, ServiceStatus::Warning) ||
        self.containers.iter().any(|c| c.status == ServiceStatus::Warning)
    }
    
    pub fn is_critical(&self) -> bool {
        matches!(self.overall_status, ServiceStatus::Critical) ||
        self.containers.iter().any(|c| c.status == ServiceStatus::Critical)
    }
}