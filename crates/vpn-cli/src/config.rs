use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};
use crate::error::{CliError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CliConfig {
    pub general: GeneralConfig,
    pub server: ServerConfig,
    pub ui: UiConfig,
    pub monitoring: MonitoringConfig,
    pub security: SecurityConfig,
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
}