//! Docker Compose management operations

use crate::config::ComposeConfig;
use crate::error::{ComposeError, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command;
use tracing::{debug, info};

/// Docker Compose manager for executing compose operations
pub struct ComposeManager {
    config: ComposeConfig,
    compose_file_path: PathBuf,
    project_name: String,
}

impl ComposeManager {
    /// Create a new compose manager
    pub async fn new(config: &ComposeConfig) -> Result<Self> {
        let compose_file_path = config.compose_dir.join("docker-compose.yml");
        let project_name = config.project_name.clone();

        Ok(Self {
            config: config.clone(),
            compose_file_path,
            project_name,
        })
    }

    /// Initialize the compose manager
    pub async fn initialize(&self) -> Result<()> {
        // Ensure Docker Compose is available
        self.check_docker_compose().await?;

        // Ensure compose directory exists
        if !self.config.compose_dir.exists() {
            tokio::fs::create_dir_all(&self.config.compose_dir).await?;
        }

        info!("Compose manager initialized successfully");
        Ok(())
    }

    /// Start all services (docker-compose up)
    pub async fn up(&self) -> Result<()> {
        info!("Starting VPN system with Docker Compose");

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("up")
            .arg("-d")
            .arg("--remove-orphans")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed("up", stderr));
        }

        info!("VPN system started successfully");
        Ok(())
    }

    /// Stop all services (docker-compose down)
    pub async fn down(&self) -> Result<()> {
        info!("Stopping VPN system");

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("down")
            .arg("--remove-orphans")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed("down", stderr));
        }

        info!("VPN system stopped successfully");
        Ok(())
    }

    /// Restart a specific service
    pub async fn restart_service(&self, service: &str) -> Result<()> {
        info!("Restarting service: {}", service);

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("restart")
            .arg(service)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed(
                format!("restart {}", service),
                stderr,
            ));
        }

        info!("Service {} restarted successfully", service);
        Ok(())
    }

    /// Scale a service
    pub async fn scale_service(&self, service: &str, replicas: u32) -> Result<()> {
        info!("Scaling service {} to {} replicas", service, replicas);

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("up")
            .arg("-d")
            .arg("--scale")
            .arg(format!("{}={}", service, replicas))
            .arg("--no-recreate")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed(
                format!("scale {} to {}", service, replicas),
                stderr,
            ));
        }

        info!("Service {} scaled to {} replicas", service, replicas);
        Ok(())
    }

    /// Get system status
    pub async fn get_status(&self) -> Result<ComposeStatus> {
        debug!("Getting system status");

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("ps")
            .arg("--format")
            .arg("json")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed("ps", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let services = self.parse_service_status(&stdout)?;

        let total_services = services.len();
        let running_services = services.iter().filter(|s| s.state == "running").count();
        let stopped_services = services.iter().filter(|s| s.state != "running").count();

        Ok(ComposeStatus {
            project_name: self.project_name.clone(),
            services,
            total_services,
            running_services,
            stopped_services,
        })
    }

    /// Get logs from services
    pub async fn get_logs(&self, service: Option<&str>) -> Result<String> {
        debug!("Getting logs for service: {:?}", service);

        let mut cmd = Command::new("docker-compose");
        cmd.arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("logs")
            .arg("--tail")
            .arg("100");

        if let Some(service_name) = service {
            cmd.arg(service_name);
        }

        let output = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed("logs", stderr));
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Pull latest images
    pub async fn pull(&self) -> Result<()> {
        info!("Pulling latest images");

        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("pull")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed("pull", stderr));
        }

        info!("Images pulled successfully");
        Ok(())
    }

    /// Build services
    pub async fn build(&self, service: Option<&str>) -> Result<()> {
        info!("Building services");

        let mut cmd = Command::new("docker-compose");
        cmd.arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("build");

        if let Some(service_name) = service {
            cmd.arg(service_name);
        }

        let output = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed("build", stderr));
        }

        info!("Services built successfully");
        Ok(())
    }

    /// Execute command in a service container
    pub async fn exec(&self, service: &str, command: &[&str]) -> Result<String> {
        debug!("Executing command in service {}: {:?}", service, command);

        let mut cmd = Command::new("docker-compose");
        cmd.arg("-f")
            .arg(&self.compose_file_path)
            .arg("-p")
            .arg(&self.project_name)
            .arg("exec")
            .arg("-T")
            .arg(service);

        for arg in command {
            cmd.arg(arg);
        }

        let output = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ComposeError::compose_command_failed(
                format!("exec {} {:?}", service, command),
                stderr,
            ));
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Update configuration and recreate services
    pub async fn update_config(&mut self, config: &ComposeConfig) -> Result<()> {
        self.config = config.clone();
        self.compose_file_path = config.compose_dir.join("docker-compose.yml");

        // Recreate services with new configuration
        self.up().await?;

        Ok(())
    }

    /// Check if Docker Compose is available
    async fn check_docker_compose(&self) -> Result<()> {
        let output = Command::new("docker-compose")
            .arg("--version")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            return Err(ComposeError::manager_init_failed(
                "Docker Compose not found. Please install Docker Compose.",
            ));
        }

        let version = String::from_utf8_lossy(&output.stdout);
        info!("Docker Compose detected: {}", version.trim());
        Ok(())
    }

    /// Parse service status from docker-compose ps output
    fn parse_service_status(&self, output: &str) -> Result<Vec<ServiceStatus>> {
        let mut services = Vec::new();

        for line in output.lines() {
            if line.trim().is_empty() {
                continue;
            }

            // Try to parse as JSON first (newer docker-compose versions)
            if let Ok(service) = serde_json::from_str::<ServiceStatus>(line) {
                services.push(service);
            } else {
                // Fallback to parsing text format
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    services.push(ServiceStatus {
                        name: parts[0].to_string(),
                        state: parts[1].to_string(),
                        health: if parts.len() > 2 && parts[2] != "-" {
                            Some(parts[2].to_string())
                        } else {
                            None
                        },
                        ports: if parts.len() > 3 {
                            vec![parts[3..].join(" ")]
                        } else {
                            vec![]
                        },
                    });
                }
            }
        }

        Ok(services)
    }
}

/// Status of the entire Docker Compose system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComposeStatus {
    pub project_name: String,
    pub services: Vec<ServiceStatus>,
    pub total_services: usize,
    pub running_services: usize,
    pub stopped_services: usize,
}

/// Status of a single service
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub name: String,
    pub state: String,
    pub health: Option<String>,
    pub ports: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ComposeConfig;

    #[tokio::test]
    async fn test_compose_manager_creation() {
        let config = ComposeConfig::default();
        let manager = ComposeManager::new(&config).await;
        assert!(manager.is_ok());
    }

    #[test]
    fn test_service_status_parsing() {
        let config = ComposeConfig::default();
        let manager = ComposeManager {
            config: config.clone(),
            compose_file_path: config.compose_dir.join("docker-compose.yml"),
            project_name: config.project_name,
        };

        let output = r#"
vpn-server    running    healthy    8443/tcp, 443/tcp
vpn-api       running    -          3000/tcp
postgres      running    healthy    5432/tcp
"#;

        let result = manager.parse_service_status(output);
        assert!(result.is_ok());

        let services = result.unwrap();
        assert_eq!(services.len(), 3);
        assert_eq!(services[0].name, "vpn-server");
        assert_eq!(services[0].state, "running");
    }
}
