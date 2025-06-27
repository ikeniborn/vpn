use bollard::Docker;
use bollard::container::StatsOptions;
use bollard::models::ContainerStateStatusEnum;
use futures_util::stream::StreamExt;
use std::time::Duration;
use crate::error::{DockerError, Result};
use crate::container::ContainerManager;

#[derive(Debug, Clone)]
pub struct HealthStatus {
    pub container_name: String,
    pub is_running: bool,
    pub status: String,
    pub cpu_usage: f64,
    pub memory_usage: u64,
    pub memory_limit: u64,
    pub network_rx_bytes: u64,
    pub network_tx_bytes: u64,
}

pub struct HealthChecker {
    docker: Docker,
    container_manager: ContainerManager,
}

impl HealthChecker {
    pub fn new() -> Result<Self> {
        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| DockerError::ConnectionError(e.to_string()))?;
        let container_manager = ContainerManager::new()?;
        Ok(Self { docker, container_manager })
    }
    
    pub async fn check_container_health(&self, name: &str) -> Result<HealthStatus> {
        let inspect = self.container_manager.inspect_container(name).await?;
        
        let state = inspect.state.as_ref()
            .ok_or_else(|| DockerError::HealthCheckFailed("No state information".to_string()))?;
        
        let is_running = matches!(
            state.status,
            Some(ContainerStateStatusEnum::RUNNING)
        );
        
        let status = state.status.as_ref()
            .map(|s| format!("{:?}", s))
            .unwrap_or_else(|| "unknown".to_string());
        
        let stats = self.get_container_stats(name).await?;
        
        Ok(HealthStatus {
            container_name: name.to_string(),
            is_running,
            status,
            cpu_usage: stats.0,
            memory_usage: stats.1,
            memory_limit: stats.2,
            network_rx_bytes: stats.3,
            network_tx_bytes: stats.4,
        })
    }
    
    async fn get_container_stats(&self, name: &str) -> Result<(f64, u64, u64, u64, u64)> {
        let options = StatsOptions {
            stream: false,
            one_shot: true,
        };
        
        let mut stream = self.docker.stats(name, Some(options));
        
        if let Some(Ok(stats)) = stream.next().await {
            let cpu_usage = calculate_cpu_percentage(&stats);
            
            let memory_stats = &stats.memory_stats;
            
            let memory_usage = memory_stats.usage.unwrap_or(0);
            let memory_limit = memory_stats.limit.unwrap_or(0);
            
            let (rx_bytes, tx_bytes) = if let Some(networks) = &stats.networks {
                let rx: u64 = networks.values()
                    .map(|n| n.rx_bytes)
                    .sum();
                let tx: u64 = networks.values()
                    .map(|n| n.tx_bytes)
                    .sum();
                (rx, tx)
            } else {
                (0, 0)
            };
            
            Ok((cpu_usage, memory_usage, memory_limit, rx_bytes, tx_bytes))
        } else {
            Err(DockerError::HealthCheckFailed("Failed to get stats".to_string()))
        }
    }
    
    pub async fn wait_for_healthy(&self, name: &str, timeout: Duration) -> Result<()> {
        let start = std::time::Instant::now();
        
        while start.elapsed() < timeout {
            match self.check_container_health(name).await {
                Ok(status) if status.is_running => return Ok(()),
                _ => tokio::time::sleep(Duration::from_secs(1)).await,
            }
        }
        
        Err(DockerError::HealthCheckFailed(
            format!("Container {} did not become healthy within {:?}", name, timeout)
        ))
    }
    
    pub async fn check_multiple_containers(&self, names: &[&str]) -> Vec<Result<HealthStatus>> {
        let mut results = Vec::new();
        
        for name in names {
            results.push(self.check_container_health(name).await);
        }
        
        results
    }
}

fn calculate_cpu_percentage(stats: &bollard::container::Stats) -> f64 {
    let cpu_stats = &stats.cpu_stats;
    
    let precpu_stats = &stats.precpu_stats;
    
    let cpu_usage = cpu_stats.cpu_usage.total_usage as f64;
    
    let precpu_usage = precpu_stats.cpu_usage.total_usage as f64;
    
    let system_cpu = cpu_stats.system_cpu_usage.unwrap_or(0) as f64;
    let presystem_cpu = precpu_stats.system_cpu_usage.unwrap_or(0) as f64;
    
    let cpu_delta = cpu_usage - precpu_usage;
    let system_delta = system_cpu - presystem_cpu;
    
    if system_delta > 0.0 && cpu_delta > 0.0 {
        let cpu_count = cpu_stats.online_cpus.unwrap_or(1) as f64;
        (cpu_delta / system_delta) * cpu_count * 100.0
    } else {
        0.0
    }
}