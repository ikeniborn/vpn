//! Environment management for Docker Compose deployments

use crate::config::EnvironmentConfig;
use crate::error::{ComposeError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Environment types for VPN deployment
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum EnvironmentType {
    Development,
    Staging,
    Production,
}

impl std::fmt::Display for EnvironmentType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EnvironmentType::Development => write!(f, "development"),
            EnvironmentType::Staging => write!(f, "staging"),
            EnvironmentType::Production => write!(f, "production"),
        }
    }
}

impl std::str::FromStr for EnvironmentType {
    type Err = ComposeError;

    fn from_str(s: &str) -> Result<Self> {
        match s.to_lowercase().as_str() {
            "development" | "dev" => Ok(EnvironmentType::Development),
            "staging" | "stage" => Ok(EnvironmentType::Staging),
            "production" | "prod" => Ok(EnvironmentType::Production),
            _ => Err(ComposeError::environment_error(format!(
                "Unknown environment type: {}",
                s
            ))),
        }
    }
}

/// Environment management for Docker Compose deployments
#[derive(Debug, Clone)]
pub struct Environment {
    env_type: EnvironmentType,
    config: EnvironmentConfig,
    variables: HashMap<String, String>,
}

impl Environment {
    /// Create a new environment
    pub async fn new(config: &EnvironmentConfig) -> Result<Self> {
        let env_type = config.name.parse::<EnvironmentType>()?;
        let variables = Self::get_default_variables(&env_type);

        Ok(Self {
            env_type,
            config: config.clone(),
            variables,
        })
    }

    /// Create a development environment
    pub fn development() -> Self {
        Self {
            env_type: EnvironmentType::Development,
            config: EnvironmentConfig {
                name: "development".to_string(),
                ..Default::default()
            },
            variables: Self::get_default_variables(&EnvironmentType::Development),
        }
    }

    /// Create a staging environment
    pub fn staging() -> Self {
        Self {
            env_type: EnvironmentType::Staging,
            config: EnvironmentConfig {
                name: "staging".to_string(),
                ..Default::default()
            },
            variables: Self::get_default_variables(&EnvironmentType::Staging),
        }
    }

    /// Create a production environment
    pub fn production() -> Self {
        Self {
            env_type: EnvironmentType::Production,
            config: EnvironmentConfig {
                name: "production".to_string(),
                ..Default::default()
            },
            variables: Self::get_default_variables(&EnvironmentType::Production),
        }
    }

    /// Get environment type
    pub fn get_type(&self) -> &EnvironmentType {
        &self.env_type
    }

    /// Get environment name
    pub fn get_name(&self) -> &str {
        &self.config.name
    }

    /// Get environment configuration
    pub fn get_config(&self) -> &EnvironmentConfig {
        &self.config
    }

    /// Get environment variables
    pub fn get_variables(&self) -> &HashMap<String, String> {
        &self.variables
    }

    /// Set an environment variable
    pub fn set_variable(&mut self, key: String, value: String) {
        self.variables.insert(key, value);
    }

    /// Get an environment variable
    pub fn get_variable(&self, key: &str) -> Option<&String> {
        self.variables.get(key)
    }

    /// Check if this is a development environment
    pub fn is_development(&self) -> bool {
        self.env_type == EnvironmentType::Development
    }

    /// Check if this is a staging environment
    pub fn is_staging(&self) -> bool {
        self.env_type == EnvironmentType::Staging
    }

    /// Check if this is a production environment
    pub fn is_production(&self) -> bool {
        self.env_type == EnvironmentType::Production
    }

    /// Get Docker Compose file names for this environment
    pub fn get_compose_files(&self) -> Vec<String> {
        let mut files = vec!["docker-compose.yml".to_string()];

        match self.env_type {
            EnvironmentType::Development => {
                files.push("docker-compose.development.yml".to_string());
            }
            EnvironmentType::Staging => {
                files.push("docker-compose.staging.yml".to_string());
            }
            EnvironmentType::Production => {
                files.push("docker-compose.production.yml".to_string());
            }
        }

        files
    }

    /// Get resource limits for this environment
    pub fn get_resource_limits(&self) -> ResourceLimits {
        match self.env_type {
            EnvironmentType::Development => ResourceLimits {
                memory_limit: "256M".to_string(),
                cpu_limit: "0.5".to_string(),
                memory_reservation: "128M".to_string(),
                cpu_reservation: "0.1".to_string(),
            },
            EnvironmentType::Staging => ResourceLimits {
                memory_limit: "512M".to_string(),
                cpu_limit: "1.0".to_string(),
                memory_reservation: "256M".to_string(),
                cpu_reservation: "0.25".to_string(),
            },
            EnvironmentType::Production => ResourceLimits {
                memory_limit: "1G".to_string(),
                cpu_limit: "2.0".to_string(),
                memory_reservation: "512M".to_string(),
                cpu_reservation: "0.5".to_string(),
            },
        }
    }

    /// Get security settings for this environment
    pub fn get_security_settings(&self) -> SecuritySettings {
        SecuritySettings {
            read_only_root_filesystem: !self.is_development(),
            no_new_privileges: true,
            drop_all_capabilities: true,
            run_as_non_root: self.is_production(),
        }
    }

    /// Get logging configuration for this environment
    pub fn get_logging_config(&self) -> LoggingConfig {
        match self.env_type {
            EnvironmentType::Development => LoggingConfig {
                level: "debug".to_string(),
                max_size: "5m".to_string(),
                max_files: 2,
                driver: "json-file".to_string(),
            },
            EnvironmentType::Staging => LoggingConfig {
                level: "info".to_string(),
                max_size: "10m".to_string(),
                max_files: 3,
                driver: "json-file".to_string(),
            },
            EnvironmentType::Production => LoggingConfig {
                level: "warn".to_string(),
                max_size: "10m".to_string(),
                max_files: 5,
                driver: "json-file".to_string(),
            },
        }
    }

    /// Get monitoring configuration for this environment
    pub fn get_monitoring_config(&self) -> MonitoringConfig {
        MonitoringConfig {
            enabled: !self.is_development()
                || self
                    .get_variable("ENABLE_MONITORING")
                    .map(|v| v == "true")
                    .unwrap_or(false),
            prometheus_retention: match self.env_type {
                EnvironmentType::Development => "7d".to_string(),
                EnvironmentType::Staging => "30d".to_string(),
                EnvironmentType::Production => "90d".to_string(),
            },
            metrics_interval: match self.env_type {
                EnvironmentType::Development => "30s".to_string(),
                EnvironmentType::Staging => "15s".to_string(),
                EnvironmentType::Production => "15s".to_string(),
            },
        }
    }

    /// Get default environment variables for the environment type
    fn get_default_variables(env_type: &EnvironmentType) -> HashMap<String, String> {
        let mut vars = HashMap::new();

        // Common variables
        vars.insert(
            "LOG_LEVEL".to_string(),
            match env_type {
                EnvironmentType::Development => "debug".to_string(),
                EnvironmentType::Staging => "info".to_string(),
                EnvironmentType::Production => "warn".to_string(),
            },
        );

        vars.insert("VPN_PORT".to_string(), "8443".to_string());
        vars.insert("API_PORT".to_string(), "3000".to_string());

        // Environment-specific variables
        match env_type {
            EnvironmentType::Development => {
                vars.insert("DEV_MODE".to_string(), "true".to_string());
                vars.insert("DEBUG".to_string(), "true".to_string());
                vars.insert("POSTGRES_DB".to_string(), "vpndb_dev".to_string());
                vars.insert("DOMAIN_NAME".to_string(), "vpn.localhost".to_string());
            }
            EnvironmentType::Staging => {
                vars.insert("DEV_MODE".to_string(), "false".to_string());
                vars.insert("DEBUG".to_string(), "false".to_string());
                vars.insert("POSTGRES_DB".to_string(), "vpndb_staging".to_string());
                vars.insert(
                    "DOMAIN_NAME".to_string(),
                    "vpn-staging.example.com".to_string(),
                );
            }
            EnvironmentType::Production => {
                vars.insert("DEV_MODE".to_string(), "false".to_string());
                vars.insert("DEBUG".to_string(), "false".to_string());
                vars.insert("POSTGRES_DB".to_string(), "vpndb".to_string());
                vars.insert("DOMAIN_NAME".to_string(), "vpn.example.com".to_string());
            }
        }

        vars
    }

    /// Validate environment configuration
    pub fn validate(&self) -> Result<()> {
        // Check required variables
        let required_vars = vec!["VPN_PORT", "API_PORT", "POSTGRES_DB", "DOMAIN_NAME"];

        for var in required_vars {
            if !self.variables.contains_key(var) {
                return Err(ComposeError::validation_failed(format!(
                    "Required environment variable missing: {}",
                    var
                )));
            }
        }

        // Validate port ranges
        if let Some(vpn_port) = self.variables.get("VPN_PORT") {
            if let Ok(port) = vpn_port.parse::<u16>() {
                if port < 1024 && self.is_production() {
                    return Err(ComposeError::validation_failed(
                        "VPN port should be >= 1024 in production",
                    ));
                }
            } else {
                return Err(ComposeError::validation_failed("Invalid VPN_PORT value"));
            }
        }

        Ok(())
    }
}

/// Resource limits for an environment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    pub memory_limit: String,
    pub cpu_limit: String,
    pub memory_reservation: String,
    pub cpu_reservation: String,
}

/// Security settings for an environment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecuritySettings {
    pub read_only_root_filesystem: bool,
    pub no_new_privileges: bool,
    pub drop_all_capabilities: bool,
    pub run_as_non_root: bool,
}

/// Logging configuration for an environment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    pub level: String,
    pub max_size: String,
    pub max_files: u32,
    pub driver: String,
}

/// Monitoring configuration for an environment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringConfig {
    pub enabled: bool,
    pub prometheus_retention: String,
    pub metrics_interval: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_environment_type_parsing() {
        assert_eq!(
            "development".parse::<EnvironmentType>().unwrap(),
            EnvironmentType::Development
        );
        assert_eq!(
            "staging".parse::<EnvironmentType>().unwrap(),
            EnvironmentType::Staging
        );
        assert_eq!(
            "production".parse::<EnvironmentType>().unwrap(),
            EnvironmentType::Production
        );
    }

    #[test]
    fn test_environment_creation() {
        let dev_env = Environment::development();
        assert_eq!(dev_env.get_type(), &EnvironmentType::Development);
        assert!(dev_env.is_development());
        assert!(!dev_env.is_production());

        let prod_env = Environment::production();
        assert_eq!(prod_env.get_type(), &EnvironmentType::Production);
        assert!(prod_env.is_production());
        assert!(!prod_env.is_development());
    }

    #[test]
    fn test_compose_files() {
        let dev_env = Environment::development();
        let files = dev_env.get_compose_files();
        assert!(files.contains(&"docker-compose.yml".to_string()));
        assert!(files.contains(&"docker-compose.development.yml".to_string()));

        let prod_env = Environment::production();
        let files = prod_env.get_compose_files();
        assert!(files.contains(&"docker-compose.yml".to_string()));
        assert!(files.contains(&"docker-compose.production.yml".to_string()));
    }

    #[test]
    fn test_resource_limits() {
        let dev_env = Environment::development();
        let limits = dev_env.get_resource_limits();
        assert_eq!(limits.memory_limit, "256M");

        let prod_env = Environment::production();
        let limits = prod_env.get_resource_limits();
        assert_eq!(limits.memory_limit, "1G");
    }

    #[test]
    fn test_environment_validation() {
        let env = Environment::development();
        let result = env.validate();
        assert!(result.is_ok());
    }

    #[test]
    fn test_security_settings() {
        let dev_env = Environment::development();
        let security = dev_env.get_security_settings();
        assert_eq!(security.read_only_root_filesystem, false);

        let prod_env = Environment::production();
        let security = prod_env.get_security_settings();
        assert_eq!(security.read_only_root_filesystem, true);
        assert_eq!(security.run_as_non_root, true);
    }
}
