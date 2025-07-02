//! Configuration management for Docker Compose orchestration

use crate::error::{ComposeError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Main configuration for Docker Compose orchestration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComposeConfig {
    /// Project name
    pub project_name: String,
    
    /// Base directory for compose files
    pub compose_dir: PathBuf,
    
    /// Templates directory
    pub templates_dir: PathBuf,
    
    /// Environment configuration
    pub environment: EnvironmentConfig,
    
    /// Service configurations
    pub services: HashMap<String, ServiceConfig>,
    
    /// Network configurations
    pub networks: HashMap<String, NetworkConfig>,
    
    /// Volume configurations
    pub volumes: HashMap<String, VolumeConfig>,
    
    /// Global environment variables
    pub env_vars: HashMap<String, String>,
    
    /// Docker Compose version
    pub compose_version: String,
}

impl Default for ComposeConfig {
    fn default() -> Self {
        let mut env_vars = HashMap::new();
        env_vars.insert("LOG_LEVEL".to_string(), "info".to_string());
        env_vars.insert("VPN_PORT".to_string(), "8443".to_string());
        env_vars.insert("API_PORT".to_string(), "3000".to_string());

        let mut networks = HashMap::new();
        networks.insert("vpn-network".to_string(), NetworkConfig::bridge("172.20.0.0/16"));
        networks.insert("vpn-internal".to_string(), NetworkConfig::internal_bridge("172.21.0.0/16"));

        let mut volumes = HashMap::new();
        volumes.insert("vpn-data".to_string(), VolumeConfig::local());
        volumes.insert("vpn-config".to_string(), VolumeConfig::local());
        volumes.insert("vpn-logs".to_string(), VolumeConfig::local());

        Self {
            project_name: "vpn-system".to_string(),
            compose_dir: PathBuf::from("./docker-compose"),
            templates_dir: PathBuf::from("./templates/docker-compose"),
            environment: EnvironmentConfig::default(),
            services: HashMap::new(),
            networks,
            volumes,
            env_vars,
            compose_version: "3.8".to_string(),
        }
    }
}

/// Environment-specific configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentConfig {
    /// Environment name (dev, staging, production)
    pub name: String,
    
    /// Environment-specific overrides
    pub overrides: HashMap<String, serde_json::Value>,
    
    /// Resource limits
    pub resource_limits: ResourceLimits,
    
    /// Security settings
    pub security: SecurityConfig,
    
    /// Logging configuration
    pub logging: LoggingConfig,
}

impl Default for EnvironmentConfig {
    fn default() -> Self {
        Self {
            name: "development".to_string(),
            overrides: HashMap::new(),
            resource_limits: ResourceLimits::default(),
            security: SecurityConfig::default(),
            logging: LoggingConfig::default(),
        }
    }
}

/// Service configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceConfig {
    /// Docker image
    pub image: String,
    
    /// Container name
    pub container_name: Option<String>,
    
    /// Ports to expose
    pub ports: Vec<PortMapping>,
    
    /// Environment variables
    pub environment: HashMap<String, String>,
    
    /// Volumes
    pub volumes: Vec<VolumeMount>,
    
    /// Networks
    pub networks: Vec<String>,
    
    /// Dependencies
    pub depends_on: Vec<String>,
    
    /// Health check
    pub healthcheck: Option<HealthCheck>,
    
    /// Restart policy
    pub restart: RestartPolicy,
    
    /// Resource limits
    pub resources: Option<ResourceLimits>,
    
    /// Security options
    pub security_opt: Vec<String>,
    
    /// Capabilities
    pub cap_add: Vec<String>,
    pub cap_drop: Vec<String>,
}

/// Port mapping configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortMapping {
    pub host_port: u16,
    pub container_port: u16,
    pub protocol: String,
}

impl PortMapping {
    pub fn tcp(host_port: u16, container_port: u16) -> Self {
        Self {
            host_port,
            container_port,
            protocol: "tcp".to_string(),
        }
    }

    pub fn udp(host_port: u16, container_port: u16) -> Self {
        Self {
            host_port,
            container_port,
            protocol: "udp".to_string(),
        }
    }
}

/// Volume mount configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeMount {
    pub source: String,
    pub target: String,
    pub read_only: bool,
}

impl VolumeMount {
    pub fn new(source: impl Into<String>, target: impl Into<String>) -> Self {
        Self {
            source: source.into(),
            target: target.into(),
            read_only: false,
        }
    }

    pub fn read_only(source: impl Into<String>, target: impl Into<String>) -> Self {
        Self {
            source: source.into(),
            target: target.into(),
            read_only: true,
        }
    }
}

/// Network configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkConfig {
    pub driver: String,
    pub internal: bool,
    pub ipam: Option<IpamConfig>,
    pub options: HashMap<String, String>,
}

impl NetworkConfig {
    pub fn bridge(subnet: &str) -> Self {
        Self {
            driver: "bridge".to_string(),
            internal: false,
            ipam: Some(IpamConfig::with_subnet(subnet)),
            options: HashMap::new(),
        }
    }

    pub fn internal_bridge(subnet: &str) -> Self {
        Self {
            driver: "bridge".to_string(),
            internal: true,
            ipam: Some(IpamConfig::with_subnet(subnet)),
            options: HashMap::new(),
        }
    }
}

/// IPAM configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpamConfig {
    pub config: Vec<SubnetConfig>,
}

impl IpamConfig {
    pub fn with_subnet(subnet: &str) -> Self {
        Self {
            config: vec![SubnetConfig {
                subnet: subnet.to_string(),
            }],
        }
    }
}

/// Subnet configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubnetConfig {
    pub subnet: String,
}

/// Volume configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeConfig {
    pub driver: String,
    pub driver_opts: HashMap<String, String>,
}

impl VolumeConfig {
    pub fn local() -> Self {
        Self {
            driver: "local".to_string(),
            driver_opts: HashMap::new(),
        }
    }

    pub fn bind(device: impl Into<String>) -> Self {
        let mut driver_opts = HashMap::new();
        driver_opts.insert("type".to_string(), "none".to_string());
        driver_opts.insert("o".to_string(), "bind".to_string());
        driver_opts.insert("device".to_string(), device.into());

        Self {
            driver: "local".to_string(),
            driver_opts,
        }
    }
}

/// Health check configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheck {
    pub test: Vec<String>,
    pub interval: String,
    pub timeout: String,
    pub retries: u32,
    pub start_period: Option<String>,
}

impl HealthCheck {
    pub fn cmd_shell(command: impl Into<String>) -> Self {
        Self {
            test: vec!["CMD-SHELL".to_string(), command.into()],
            interval: "30s".to_string(),
            timeout: "10s".to_string(),
            retries: 3,
            start_period: Some("30s".to_string()),
        }
    }

    pub fn cmd(command: Vec<String>) -> Self {
        let mut test = vec!["CMD".to_string()];
        test.extend(command);

        Self {
            test,
            interval: "30s".to_string(),
            timeout: "10s".to_string(),
            retries: 3,
            start_period: Some("30s".to_string()),
        }
    }

    pub fn http(path: &str, port: u16, interval_secs: u64, timeout_secs: u64, retries: u32, start_period_secs: u64) -> Self {
        Self {
            test: vec!["CMD".to_string(), "curl".to_string(), "-f".to_string(), format!("http://localhost:{}{}", port, path)],
            interval: format!("{}s", interval_secs),
            timeout: format!("{}s", timeout_secs),
            retries,
            start_period: Some(format!("{}s", start_period_secs)),
        }
    }
}

/// Restart policy
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RestartPolicy {
    No,
    Always,
    OnFailure,
    UnlessStopped,
}

impl Default for RestartPolicy {
    fn default() -> Self {
        Self::UnlessStopped
    }
}

/// Resource limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    pub memory: Option<String>,
    pub cpus: Option<String>,
    pub memory_reservation: Option<String>,
    pub cpus_reservation: Option<String>,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self {
            memory: None,
            cpus: None,
            memory_reservation: None,
            cpus_reservation: None,
        }
    }
}

impl ResourceLimits {
    pub fn development() -> Self {
        Self {
            memory: Some("256M".to_string()),
            cpus: Some("0.5".to_string()),
            memory_reservation: Some("128M".to_string()),
            cpus_reservation: Some("0.1".to_string()),
        }
    }

    pub fn production() -> Self {
        Self {
            memory: Some("1G".to_string()),
            cpus: Some("2.0".to_string()),
            memory_reservation: Some("512M".to_string()),
            cpus_reservation: Some("0.5".to_string()),
        }
    }
}

/// Security configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    pub read_only_root_filesystem: bool,
    pub no_new_privileges: bool,
    pub user: Option<String>,
    pub capabilities: CapabilitiesConfig,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            read_only_root_filesystem: false,
            no_new_privileges: true,
            user: None,
            capabilities: CapabilitiesConfig::default(),
        }
    }
}

/// Capabilities configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilitiesConfig {
    pub drop: Vec<String>,
    pub add: Vec<String>,
}

impl Default for CapabilitiesConfig {
    fn default() -> Self {
        Self {
            drop: vec!["ALL".to_string()],
            add: vec![],
        }
    }
}

/// Logging configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    pub driver: String,
    pub options: HashMap<String, String>,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        let mut options = HashMap::new();
        options.insert("max-size".to_string(), "10m".to_string());
        options.insert("max-file".to_string(), "3".to_string());

        Self {
            driver: "json-file".to_string(),
            options,
        }
    }
}

impl ComposeConfig {
    /// Load configuration from file
    pub async fn load_from_file(path: &PathBuf) -> Result<Self> {
        let content = tokio::fs::read_to_string(path).await
            .map_err(|_e| ComposeError::file_operation_failed("read", path.to_string_lossy()))?;

        let config: ComposeConfig = toml::from_str(&content)
            .map_err(|e| ComposeError::config_error(format!("Failed to parse config: {}", e)))?;

        Ok(config)
    }

    /// Save configuration to file
    pub async fn save_to_file(&self, path: &PathBuf) -> Result<()> {
        let content = toml::to_string_pretty(self)
            .map_err(|e| ComposeError::config_error(format!("Failed to serialize config: {}", e)))?;

        tokio::fs::write(path, content).await
            .map_err(|_e| ComposeError::file_operation_failed("write", path.to_string_lossy()))?;

        Ok(())
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<()> {
        if self.project_name.is_empty() {
            return Err(ComposeError::validation_failed("Project name cannot be empty"));
        }

        if !self.compose_dir.exists() {
            return Err(ComposeError::validation_failed(
                format!("Compose directory does not exist: {:?}", self.compose_dir)
            ));
        }

        if !self.templates_dir.exists() {
            return Err(ComposeError::validation_failed(
                format!("Templates directory does not exist: {:?}", self.templates_dir)
            ));
        }

        // Validate service dependencies
        for (service_name, service_config) in &self.services {
            for dependency in &service_config.depends_on {
                if !self.services.contains_key(dependency) {
                    return Err(ComposeError::dependency_error(service_name, dependency));
                }
            }
        }

        Ok(())
    }

    /// Get environment-specific configuration
    pub fn for_environment(&self, environment: &str) -> Self {
        let mut config = self.clone();
        config.environment.name = environment.to_string();

        // Apply environment-specific resource limits
        match environment {
            "development" => {
                config.environment.resource_limits = ResourceLimits::development();
            },
            "production" => {
                config.environment.resource_limits = ResourceLimits::production();
            },
            _ => {
                // Keep default
            }
        }

        config
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compose_config_default() {
        let config = ComposeConfig::default();
        assert_eq!(config.project_name, "vpn-system");
        assert_eq!(config.compose_version, "3.8");
        assert!(!config.networks.is_empty());
        assert!(!config.volumes.is_empty());
    }

    #[test]
    fn test_port_mapping() {
        let port = PortMapping::tcp(8080, 80);
        assert_eq!(port.host_port, 8080);
        assert_eq!(port.container_port, 80);
        assert_eq!(port.protocol, "tcp");
    }

    #[test]
    fn test_health_check() {
        let health = HealthCheck::cmd_shell("curl -f http://localhost/health");
        assert_eq!(health.test[0], "CMD-SHELL");
        assert_eq!(health.retries, 3);
    }

    #[test]
    fn test_config_validation() {
        let mut config = ComposeConfig::default();
        config.project_name = "".to_string();
        
        let result = config.validate();
        assert!(result.is_err());
    }
}