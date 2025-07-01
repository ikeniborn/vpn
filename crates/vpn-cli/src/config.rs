use std::path::{Path, PathBuf};
use std::time::Duration;
use serde::{Deserialize, Serialize};
use crate::error::{CliError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CliConfig {
    pub general: GeneralConfig,
    pub server: ServerConfig,
    pub ui: UiConfig,
    pub monitoring: MonitoringConfig,
    pub security: SecurityConfig,
    pub runtime: RuntimeSelectionConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeneralConfig {
    pub install_path: PathBuf,
    pub log_level: String,
    pub auto_backup: bool,
    pub backup_retention_days: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub default_protocol: String,
    pub default_port_range: (u16, u16),
    pub enable_firewall: bool,
    pub auto_start: bool,
    pub update_check_interval: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UiConfig {
    pub default_output_format: String,
    pub color_output: bool,
    pub progress_bars: bool,
    pub confirmation_prompts: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringConfig {
    pub enable_metrics: bool,
    pub metrics_retention_days: u32,
    pub alert_thresholds: AlertThresholds,
    pub notification_channels: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlertThresholds {
    pub cpu_usage: f64,
    pub memory_usage: f64,
    pub disk_usage: f64,
    pub error_rate: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    pub auto_key_rotation: bool,
    pub key_rotation_interval_days: u32,
    pub backup_keys: bool,
    pub strict_validation: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeSelectionConfig {
    pub preferred_runtime: String,
    pub auto_detect: bool,
    pub fallback_enabled: bool,
    pub docker: DockerRuntimeConfig,
    pub containerd: ContainerdRuntimeConfig,
    pub migration: MigrationConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerRuntimeConfig {
    pub socket_path: String,
    pub api_version: Option<String>,
    pub timeout_seconds: u64,
    pub max_connections: usize,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerdRuntimeConfig {
    pub socket_path: String,
    pub namespace: String,
    pub timeout_seconds: u64,
    pub max_connections: usize,
    pub snapshotter: String,
    pub runtime: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrationConfig {
    pub backup_before_migration: bool,
    pub preserve_containers: bool,
    pub validate_after_migration: bool,
    pub migration_timeout_minutes: u32,
}

pub struct ConfigManager {
    config: CliConfig,
    config_path: PathBuf,
}

impl ConfigManager {
    pub fn new(config_path: Option<PathBuf>) -> Result<Self> {
        let config_path = config_path.unwrap_or_else(|| {
            Self::default_config_path()
        });

        let config = if config_path.exists() {
            Self::load_config(&config_path)?
        } else {
            let default_config = CliConfig::default();
            Self::save_config(&default_config, &config_path)?;
            default_config
        };

        Ok(Self {
            config,
            config_path,
        })
    }

    pub fn get_config(&self) -> &CliConfig {
        &self.config
    }

    pub fn update_config<F>(&mut self, updater: F) -> Result<()>
    where
        F: FnOnce(&mut CliConfig),
    {
        updater(&mut self.config);
        Self::save_config(&self.config, &self.config_path)
    }

    pub fn reload_config(&mut self) -> Result<()> {
        self.config = Self::load_config(&self.config_path)?;
        Ok(())
    }

    pub fn reset_to_defaults(&mut self) -> Result<()> {
        self.config = CliConfig::default();
        Self::save_config(&self.config, &self.config_path)
    }

    pub fn export_config(&self, path: &Path) -> Result<()> {
        Self::save_config(&self.config, path)
    }

    pub fn import_config(&mut self, path: &Path) -> Result<()> {
        self.config = Self::load_config(path)?;
        Self::save_config(&self.config, &self.config_path)
    }

    // Runtime configuration utility methods
    pub fn get_runtime_config(&self) -> &RuntimeSelectionConfig {
        &self.config.runtime
    }

    pub fn set_preferred_runtime(&mut self, runtime: &str) -> Result<()> {
        if !["auto", "docker", "containerd"].contains(&runtime) {
            return Err(CliError::ConfigError(
                "Runtime must be 'auto', 'docker', or 'containerd'".to_string()
            ));
        }
        self.config.runtime.preferred_runtime = runtime.to_string();
        Self::save_config(&self.config, &self.config_path)
    }

    pub fn enable_runtime(&mut self, runtime: &str, enabled: bool) -> Result<()> {
        // Check if disabling this runtime would leave no runtimes enabled
        if !enabled {
            let would_have_docker = match runtime {
                "docker" => false,
                _ => self.config.runtime.docker.enabled,
            };
            let would_have_containerd = match runtime {
                "containerd" => false,
                _ => self.config.runtime.containerd.enabled,
            };
            
            if !would_have_docker && !would_have_containerd {
                return Err(CliError::ConfigError(
                    "At least one runtime must be enabled".to_string()
                ));
            }
        }
        
        // Apply the change
        match runtime {
            "docker" => self.config.runtime.docker.enabled = enabled,
            "containerd" => self.config.runtime.containerd.enabled = enabled,
            _ => return Err(CliError::ConfigError(
                "Runtime must be 'docker' or 'containerd'".to_string()
            )),
        }
        
        Self::save_config(&self.config, &self.config_path)
    }

    pub fn update_runtime_socket(&mut self, runtime: &str, socket_path: &str) -> Result<()> {
        match runtime {
            "docker" => self.config.runtime.docker.socket_path = socket_path.to_string(),
            "containerd" => self.config.runtime.containerd.socket_path = socket_path.to_string(),
            _ => return Err(CliError::ConfigError(
                "Runtime must be 'docker' or 'containerd'".to_string()
            )),
        }
        Self::save_config(&self.config, &self.config_path)
    }

    pub fn enable_auto_detection(&mut self, enabled: bool) -> Result<()> {
        self.config.runtime.auto_detect = enabled;
        Self::save_config(&self.config, &self.config_path)
    }

    pub fn enable_runtime_fallback(&mut self, enabled: bool) -> Result<()> {
        self.config.runtime.fallback_enabled = enabled;
        Self::save_config(&self.config, &self.config_path)
    }

    /// Convert CLI runtime config to vpn-runtime config
    pub fn to_runtime_config(&self) -> vpn_runtime::RuntimeConfig {
        let runtime = &self.config.runtime;
        
        let runtime_type = match runtime.preferred_runtime.as_str() {
            "docker" => vpn_runtime::RuntimeType::Docker,
            "containerd" => vpn_runtime::RuntimeType::Containerd,
            _ => vpn_runtime::RuntimeType::Auto,
        };

        let docker_config = if runtime.docker.enabled {
            Some(vpn_runtime::DockerConfig {
                socket_path: runtime.docker.socket_path.clone(),
                api_version: runtime.docker.api_version.clone(),
                timeout_seconds: runtime.docker.timeout_seconds,
                max_connections: runtime.docker.max_connections,
            })
        } else {
            None
        };

        let containerd_config = if runtime.containerd.enabled {
            Some(vpn_runtime::ContainerdConfig {
                socket_path: runtime.containerd.socket_path.clone(),
                namespace: runtime.containerd.namespace.clone(),
                timeout_seconds: runtime.containerd.timeout_seconds,
                max_connections: runtime.containerd.max_connections,
                snapshotter: runtime.containerd.snapshotter.clone(),
                runtime: runtime.containerd.runtime.clone(),
            })
        } else {
            None
        };

        vpn_runtime::RuntimeConfig {
            runtime_type,
            socket_path: None, // Use runtime-specific socket paths
            namespace: None,   // Use runtime-specific namespaces
            timeout: Duration::from_secs(30), // Default timeout
            max_connections: 10, // Default max connections
            docker: docker_config,
            containerd: containerd_config,
            fallback_enabled: runtime.fallback_enabled,
        }
    }

    pub fn validate_config(&self) -> Result<Vec<String>> {
        let mut warnings = Vec::new();

        // Validate install path
        if !self.config.general.install_path.is_absolute() {
            warnings.push("Install path should be absolute".to_string());
        }

        // Validate port range
        if self.config.server.default_port_range.0 >= self.config.server.default_port_range.1 {
            warnings.push("Invalid port range: start port must be less than end port".to_string());
        }

        if self.config.server.default_port_range.0 < 1024 {
            warnings.push("Port range starts below 1024 (privileged ports)".to_string());
        }

        // Validate thresholds
        let thresholds = &self.config.monitoring.alert_thresholds;
        if thresholds.cpu_usage < 0.0 || thresholds.cpu_usage > 100.0 {
            warnings.push("CPU usage threshold must be between 0 and 100".to_string());
        }

        if thresholds.memory_usage < 0.0 || thresholds.memory_usage > 100.0 {
            warnings.push("Memory usage threshold must be between 0 and 100".to_string());
        }

        if thresholds.disk_usage < 0.0 || thresholds.disk_usage > 100.0 {
            warnings.push("Disk usage threshold must be between 0 and 100".to_string());
        }

        // Validate retention periods
        if self.config.general.backup_retention_days == 0 {
            warnings.push("Backup retention should be at least 1 day".to_string());
        }

        if self.config.monitoring.metrics_retention_days == 0 {
            warnings.push("Metrics retention should be at least 1 day".to_string());
        }

        // Validate runtime configuration
        let runtime = &self.config.runtime;
        if !["auto", "docker", "containerd"].contains(&runtime.preferred_runtime.as_str()) {
            warnings.push("Preferred runtime must be 'auto', 'docker', or 'containerd'".to_string());
        }

        if !runtime.docker.enabled && !runtime.containerd.enabled {
            warnings.push("At least one runtime must be enabled".to_string());
        }

        if runtime.docker.timeout_seconds == 0 {
            warnings.push("Docker timeout must be greater than 0".to_string());
        }

        if runtime.containerd.timeout_seconds == 0 {
            warnings.push("Containerd timeout must be greater than 0".to_string());
        }

        if runtime.docker.max_connections == 0 {
            warnings.push("Docker max connections must be greater than 0".to_string());
        }

        if runtime.containerd.max_connections == 0 {
            warnings.push("Containerd max connections must be greater than 0".to_string());
        }

        if runtime.migration.migration_timeout_minutes == 0 {
            warnings.push("Migration timeout must be greater than 0".to_string());
        }

        Ok(warnings)
    }

    fn default_config_path() -> PathBuf {
        if let Some(config_dir) = dirs::config_dir() {
            config_dir.join("vpn-cli").join("config.toml")
        } else {
            PathBuf::from("/etc/vpn-cli/config.toml")
        }
    }

    fn load_config(path: &Path) -> Result<CliConfig> {
        let content = std::fs::read_to_string(path)
            .map_err(|e| CliError::ConfigError(format!("Failed to read config file: {}", e)))?;

        toml::from_str(&content)
            .map_err(|e| CliError::ConfigError(format!("Failed to parse config file: {}", e)))
    }

    fn save_config(config: &CliConfig, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| CliError::ConfigError(format!("Failed to create config directory: {}", e)))?;
        }

        let content = toml::to_string_pretty(config)
            .map_err(|e| CliError::ConfigError(format!("Failed to serialize config: {}", e)))?;

        std::fs::write(path, content)
            .map_err(|e| CliError::ConfigError(format!("Failed to write config file: {}", e)))?;

        Ok(())
    }
}

impl Default for CliConfig {
    fn default() -> Self {
        Self {
            general: GeneralConfig::default(),
            server: ServerConfig::default(),
            ui: UiConfig::default(),
            monitoring: MonitoringConfig::default(),
            security: SecurityConfig::default(),
            runtime: RuntimeSelectionConfig::default(),
        }
    }
}

impl Default for GeneralConfig {
    fn default() -> Self {
        Self {
            install_path: PathBuf::from("/opt/vpn"),
            log_level: "info".to_string(),
            auto_backup: true,
            backup_retention_days: 7,
        }
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            default_protocol: "vless".to_string(),
            default_port_range: (10000, 65000),
            enable_firewall: true,
            auto_start: true,
            update_check_interval: 86400, // 24 hours
        }
    }
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            default_output_format: "table".to_string(),
            color_output: true,
            progress_bars: true,
            confirmation_prompts: true,
        }
    }
}

impl Default for MonitoringConfig {
    fn default() -> Self {
        Self {
            enable_metrics: true,
            metrics_retention_days: 30,
            alert_thresholds: AlertThresholds::default(),
            notification_channels: Vec::new(),
        }
    }
}

impl Default for AlertThresholds {
    fn default() -> Self {
        Self {
            cpu_usage: 90.0,
            memory_usage: 90.0,
            disk_usage: 85.0,
            error_rate: 5.0,
        }
    }
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            auto_key_rotation: false,
            key_rotation_interval_days: 90,
            backup_keys: true,
            strict_validation: true,
        }
    }
}

impl Default for RuntimeSelectionConfig {
    fn default() -> Self {
        Self {
            preferred_runtime: "auto".to_string(),
            auto_detect: true,
            fallback_enabled: true,
            docker: DockerRuntimeConfig::default(),
            containerd: ContainerdRuntimeConfig::default(),
            migration: MigrationConfig::default(),
        }
    }
}

impl Default for DockerRuntimeConfig {
    fn default() -> Self {
        Self {
            socket_path: "/var/run/docker.sock".to_string(),
            api_version: None,
            timeout_seconds: 30,
            max_connections: 10,
            enabled: true,
        }
    }
}

impl Default for ContainerdRuntimeConfig {
    fn default() -> Self {
        Self {
            socket_path: "/run/containerd/containerd.sock".to_string(),
            namespace: "default".to_string(),
            timeout_seconds: 30,
            max_connections: 10,
            snapshotter: "overlayfs".to_string(),
            runtime: "io.containerd.runc.v2".to_string(),
            enabled: true,
        }
    }
}

impl Default for MigrationConfig {
    fn default() -> Self {
        Self {
            backup_before_migration: true,
            preserve_containers: true,
            validate_after_migration: true,
            migration_timeout_minutes: 30,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_config_creation_and_validation() {
        let config = CliConfig::default();
        
        // Test serialization
        let toml_str = toml::to_string(&config).unwrap();
        assert!(!toml_str.is_empty());
        
        // Test deserialization
        let _parsed_config: CliConfig = toml::from_str(&toml_str).unwrap();
        
        // Test validation
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        let manager = ConfigManager::new(Some(config_path)).unwrap();
        
        let warnings = manager.validate_config().unwrap();
        assert!(warnings.is_empty(), "Default config should be valid");
    }

    #[test]
    fn test_config_validation_errors() {
        let mut config = CliConfig::default();
        config.server.default_port_range = (5000, 4000); // Invalid range
        config.monitoring.alert_thresholds.cpu_usage = 150.0; // Invalid threshold
        
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        ConfigManager::save_config(&config, &config_path).unwrap();
        
        let manager = ConfigManager::new(Some(config_path)).unwrap();
        let warnings = manager.validate_config().unwrap();
        
        assert!(!warnings.is_empty(), "Invalid config should produce warnings");
    }

    #[test]
    fn test_runtime_configuration() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        let mut manager = ConfigManager::new(Some(config_path)).unwrap();
        
        // Test default runtime config
        let runtime_config = manager.get_runtime_config();
        assert_eq!(runtime_config.preferred_runtime, "auto");
        assert!(runtime_config.auto_detect);
        assert!(runtime_config.fallback_enabled);
        assert!(runtime_config.docker.enabled);
        assert!(runtime_config.containerd.enabled);
        
        // Test setting preferred runtime
        manager.set_preferred_runtime("containerd").unwrap();
        assert_eq!(manager.get_runtime_config().preferred_runtime, "containerd");
        
        // Test invalid runtime
        assert!(manager.set_preferred_runtime("invalid").is_err());
        
        // Test enabling/disabling runtimes
        manager.enable_runtime("docker", false).unwrap();
        assert!(!manager.get_runtime_config().docker.enabled);
        assert!(manager.get_runtime_config().containerd.enabled);
        
        // Test disabling all runtimes should fail
        assert!(manager.enable_runtime("containerd", false).is_err());
        
        // Test socket path update
        manager.update_runtime_socket("containerd", "/custom/path.sock").unwrap();
        assert_eq!(manager.get_runtime_config().containerd.socket_path, "/custom/path.sock");
        
        // Test conversion to vpn-runtime config
        let vpn_runtime_config = manager.to_runtime_config();
        assert_eq!(vpn_runtime_config.runtime_type, vpn_runtime::RuntimeType::Containerd);
        assert!(vpn_runtime_config.containerd.is_some());
        assert!(vpn_runtime_config.docker.is_none()); // Docker is disabled
        assert!(vpn_runtime_config.fallback_enabled);
    }

    #[test]
    fn test_runtime_config_validation() {
        let mut config = CliConfig::default();
        
        // Test invalid preferred runtime
        config.runtime.preferred_runtime = "invalid".to_string();
        config.runtime.docker.enabled = false;
        config.runtime.containerd.enabled = false;
        config.runtime.docker.timeout_seconds = 0;
        config.runtime.migration.migration_timeout_minutes = 0;
        
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        ConfigManager::save_config(&config, &config_path).unwrap();
        
        let manager = ConfigManager::new(Some(config_path)).unwrap();
        let warnings = manager.validate_config().unwrap();
        
        // Should have multiple runtime-related warnings
        assert!(warnings.iter().any(|w| w.contains("Preferred runtime")));
        assert!(warnings.iter().any(|w| w.contains("At least one runtime")));
        assert!(warnings.iter().any(|w| w.contains("Docker timeout")));
        assert!(warnings.iter().any(|w| w.contains("Migration timeout")));
    }
}