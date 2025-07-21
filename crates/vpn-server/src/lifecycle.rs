use crate::error::{Result, ServerError};
use crate::validator::ConfigValidator;
use std::path::Path;
use std::time::Duration;
use tokio::process::Command;
use vpn_docker::{ContainerManager, HealthChecker};

pub struct ServerLifecycle {
    container_manager: ContainerManager,
    health_checker: HealthChecker,
    validator: ConfigValidator,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ServerStatus {
    pub is_running: bool,
    pub containers: Vec<ContainerStatus>,
    pub uptime: Option<Duration>,
    pub health_score: f64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ContainerStatus {
    pub name: String,
    pub is_running: bool,
    pub cpu_usage: f64,
    pub memory_usage: u64,
    pub memory_limit: u64,
    pub network_rx: u64,
    pub network_tx: u64,
}

impl ServerLifecycle {
    pub fn new() -> Result<Self> {
        let container_manager = ContainerManager::new()?;
        let health_checker = HealthChecker::new()?;
        let validator = ConfigValidator::new()?;

        Ok(Self {
            container_manager,
            health_checker,
            validator,
        })
    }

    pub async fn start(&self, install_path: &Path) -> Result<()> {
        let compose_file = install_path.join("docker-compose.yml");

        if !compose_file.exists() {
            return Err(ServerError::ServerNotFound);
        }

        println!("Starting VPN server...");

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_file)
            .arg("up")
            .arg("-d")
            .output()
            .await?;

        if !output.status.success() {
            return Err(ServerError::LifecycleError(format!(
                "Failed to start server: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        // Wait for containers to become healthy
        self.wait_for_healthy_state(Duration::from_secs(60)).await?;

        println!("VPN server started successfully");
        Ok(())
    }

    pub async fn stop(&self, install_path: &Path) -> Result<()> {
        let compose_file = install_path.join("docker-compose.yml");

        if !compose_file.exists() {
            return Err(ServerError::ServerNotFound);
        }

        println!("Stopping VPN server...");

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_file)
            .arg("stop")
            .output()
            .await?;

        if !output.status.success() {
            return Err(ServerError::LifecycleError(format!(
                "Failed to stop server: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        println!("VPN server stopped successfully");
        Ok(())
    }

    pub async fn restart(&self, install_path: &Path) -> Result<()> {
        println!("Restarting VPN server...");

        self.stop(install_path).await?;
        tokio::time::sleep(Duration::from_secs(5)).await;
        self.start(install_path).await?;

        println!("VPN server restarted successfully");
        Ok(())
    }

    pub async fn reload_config(&self, install_path: &Path) -> Result<()> {
        // Validate new configuration first
        let validation_result = self.validator.validate_installation(install_path).await?;

        if !validation_result.is_valid {
            return Err(ServerError::ValidationError(format!(
                "Configuration validation failed: {:?}",
                validation_result.errors
            )));
        }

        // Send reload signal to containers
        let containers = [
            ("vless-xray", "xray"),
            ("shadowsocks", "shadowsocks-server"),
            ("wireguard", "wg"),
        ];

        for (container_name, process_name) in &containers {
            if self.container_manager.container_exists(container_name).await {
                // Send SIGHUP to reload configuration
                match self
                    .container_manager
                    .exec_command(container_name, vec!["killall", "-HUP", process_name])
                    .await
                {
                    Ok(_) => println!("Reloaded configuration for {}", container_name),
                    Err(e) => println!("Warning: Failed to reload {}: {}", container_name, e),
                }
            }
        }

        Ok(())
    }

    pub async fn get_status(&self) -> Result<ServerStatus> {
        let containers = ["vless-xray", "shadowsocks", "wireguard", "proxy-server", "vless-watchtower", "shadowsocks-watchtower"];
        let mut container_statuses = Vec::new();
        let mut running_count = 0;
        let mut total_health = 0.0;

        for container in &containers {
            if self.container_manager.container_exists(container).await {
                match self.health_checker.check_container_health(container).await {
                    Ok(health) => {
                        let status = ContainerStatus {
                            name: container.to_string(),
                            is_running: health.is_running,
                            cpu_usage: health.cpu_usage,
                            memory_usage: health.memory_usage,
                            memory_limit: health.memory_limit,
                            network_rx: health.network_rx_bytes,
                            network_tx: health.network_tx_bytes,
                        };

                        if health.is_running {
                            running_count += 1;
                            total_health += 1.0;
                        }

                        container_statuses.push(status);
                    }
                    Err(_) => {
                        container_statuses.push(ContainerStatus {
                            name: container.to_string(),
                            is_running: false,
                            cpu_usage: 0.0,
                            memory_usage: 0,
                            memory_limit: 0,
                            network_rx: 0,
                            network_tx: 0,
                        });
                    }
                }
            }
        }

        let is_running = running_count > 0;
        let health_score = if container_statuses.is_empty() {
            0.0
        } else {
            total_health / container_statuses.len() as f64
        };

        // Get uptime from the main container
        let uptime = if is_running {
            self.get_container_uptime("xray").await.ok()
        } else {
            None
        };

        Ok(ServerStatus {
            is_running,
            containers: container_statuses,
            uptime,
            health_score,
        })
    }

    async fn wait_for_healthy_state(&self, timeout: Duration) -> Result<()> {
        let start = std::time::Instant::now();

        while start.elapsed() < timeout {
            let status = self.get_status().await?;

            if status.is_running && status.health_score > 0.5 {
                return Ok(());
            }

            tokio::time::sleep(Duration::from_secs(2)).await;
        }

        Err(ServerError::LifecycleError(
            "Server did not become healthy within timeout".to_string(),
        ))
    }

    async fn get_container_uptime(&self, container: &str) -> Result<Duration> {
        let inspect = self.container_manager.inspect_container(container).await?;

        if let Some(state) = inspect.state {
            if let Some(started_at) = state.started_at {
                let started = chrono::DateTime::parse_from_rfc3339(&started_at)
                    .map_err(|e| ServerError::LifecycleError(e.to_string()))?;

                let now = chrono::Utc::now();
                let duration = now.signed_duration_since(started);

                return Ok(Duration::from_secs(duration.num_seconds() as u64));
            }
        }

        Err(ServerError::LifecycleError(
            "Could not determine uptime".to_string(),
        ))
    }

    pub async fn backup_configuration(
        &self,
        install_path: &Path,
        backup_path: &Path,
    ) -> Result<()> {
        // Create backup directory
        tokio::fs::create_dir_all(backup_path).await?;

        // Copy configuration files
        let config_files = [
            "docker-compose.yml",
            "config/config.json",
            "config/private_key.txt",
            "config/public_key.txt",
        ];

        for file in &config_files {
            let src = install_path.join(file);
            let dst = backup_path.join(file);

            if tokio::fs::try_exists(&src).await.unwrap_or(false) {
                if let Some(parent) = dst.parent() {
                    tokio::fs::create_dir_all(parent).await?;
                }
                tokio::fs::copy(&src, &dst).await?;
            }
        }

        // Backup user data
        let users_dir = install_path.join("users");
        if tokio::fs::try_exists(&users_dir).await.unwrap_or(false) {
            let backup_users_dir = backup_path.join("users");
            self.copy_dir_all(&users_dir, &backup_users_dir).await?;
        }

        println!("Configuration backup completed");
        Ok(())
    }

    pub async fn restore_configuration(
        &self,
        install_path: &Path,
        backup_path: &Path,
    ) -> Result<()> {
        if !tokio::fs::try_exists(backup_path).await.unwrap_or(false) {
            return Err(ServerError::LifecycleError(
                "Backup path does not exist".to_string(),
            ));
        }

        // Stop server before restore
        if let Err(e) = self.stop(install_path).await {
            println!("Warning: Failed to stop server before restore: {}", e);
        }

        // Restore files
        self.copy_dir_all(backup_path, install_path).await?;

        // Validate restored configuration
        let validation_result = self.validator.validate_installation(install_path).await?;

        if !validation_result.is_valid {
            return Err(ServerError::ValidationError(format!(
                "Restored configuration is invalid: {:?}",
                validation_result.errors
            )));
        }

        println!("Configuration restored successfully");
        Ok(())
    }

    async fn copy_dir_all(&self, src: &Path, dst: &Path) -> Result<()> {
        tokio::fs::create_dir_all(dst).await?;

        let mut entries = tokio::fs::read_dir(src).await?;
        while let Some(entry) = entries.next_entry().await? {
            let file_type = entry.file_type().await?;

            if file_type.is_dir() {
                Box::pin(self.copy_dir_all(&entry.path(), &dst.join(entry.file_name()))).await?;
            } else {
                tokio::fs::copy(entry.path(), dst.join(entry.file_name())).await?;
            }
        }

        Ok(())
    }
}

impl ServerStatus {
    pub fn is_healthy(&self) -> bool {
        self.is_running && self.health_score > 0.8
    }

    pub fn get_total_memory_usage(&self) -> u64 {
        self.containers.iter().map(|c| c.memory_usage).sum()
    }

    pub fn get_average_cpu_usage(&self) -> f64 {
        if self.containers.is_empty() {
            return 0.0;
        }

        let total: f64 = self.containers.iter().map(|c| c.cpu_usage).sum();
        total / self.containers.len() as f64
    }
}
