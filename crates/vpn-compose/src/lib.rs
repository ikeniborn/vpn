//! VPN Docker Compose Orchestration
//! 
//! This crate provides comprehensive Docker Compose orchestration for the VPN system,
//! replacing the complex containerd abstraction with a proven, reliable solution.

pub mod config;
pub mod template;
pub mod generator;
pub mod manager;
pub mod environment;
pub mod services;
pub mod error;

// Re-export commonly used types
pub use config::{ComposeConfig, ServiceConfig, NetworkConfig, VolumeConfig};
pub use template::{TemplateManager, TemplateContext, TemplateError};
pub use generator::{ComposeGenerator, GeneratorOptions};
pub use manager::{ComposeManager, ComposeStatus, ServiceStatus as ComposeServiceStatus};
pub use environment::Environment;
pub use config::EnvironmentConfig;
pub use services::{ServiceManager, ServiceDefinition, ServiceStatus as ServiceDefinitionStatus};
pub use error::{ComposeError, Result};

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Docker Compose orchestration system
pub struct ComposeOrchestrator {
    config: ComposeConfig,
    template_manager: TemplateManager,
    generator: ComposeGenerator,
    manager: ComposeManager,
    environment: Environment,
}

impl ComposeOrchestrator {
    /// Create a new compose orchestrator
    pub async fn new(config: ComposeConfig) -> Result<Self> {
        let template_manager = TemplateManager::new(&config).await?;
        let generator = ComposeGenerator::new(&config).await?;
        let manager = ComposeManager::new(&config).await?;
        let environment = Environment::new(&config.environment).await?;

        Ok(Self {
            config,
            template_manager,
            generator,
            manager,
            environment,
        })
    }

    /// Initialize the orchestration system
    pub async fn initialize(&mut self) -> Result<()> {
        // Ensure templates are available
        self.template_manager.load_templates().await?;
        
        // Generate compose files for the current environment
        self.generator.generate_compose_files().await?;
        
        // Initialize the compose manager
        self.manager.initialize().await?;
        
        Ok(())
    }

    /// Deploy the VPN system
    pub async fn deploy(&self) -> Result<()> {
        self.manager.up().await
    }

    /// Stop the VPN system
    pub async fn stop(&self) -> Result<()> {
        self.manager.down().await
    }

    /// Restart specific services
    pub async fn restart_service(&self, service: &str) -> Result<()> {
        self.manager.restart_service(service).await
    }

    /// Scale a service
    pub async fn scale_service(&self, service: &str, replicas: u32) -> Result<()> {
        self.manager.scale_service(service, replicas).await
    }

    /// Get system status
    pub async fn get_status(&self) -> Result<ComposeStatus> {
        self.manager.get_status().await
    }

    /// Get service logs
    pub async fn get_logs(&self, service: Option<&str>) -> Result<String> {
        self.manager.get_logs(service).await
    }

    /// Update configuration and regenerate compose files
    pub async fn update_config(&mut self, new_config: ComposeConfig) -> Result<()> {
        self.config = new_config;
        self.generator.update_config(&self.config).await?;
        self.generator.generate_compose_files().await?;
        Ok(())
    }

    /// Get current configuration
    pub fn get_config(&self) -> &ComposeConfig {
        &self.config
    }

    /// Switch environment (dev/staging/production)
    pub async fn switch_environment(&mut self, env: Environment) -> Result<()> {
        self.environment = env;
        self.generator.set_environment(&self.environment).await?;
        self.generator.generate_compose_files().await?;
        Ok(())
    }
}

/// Trait for components that can provide Docker Compose services
#[async_trait]
pub trait ComposeProvider {
    /// Get the service definition for this component
    async fn get_service_definition(&self) -> Result<ServiceDefinition>;
    
    /// Get environment variables needed by this service
    async fn get_environment_vars(&self) -> Result<HashMap<String, String>>;
    
    /// Get volumes needed by this service
    async fn get_volumes(&self) -> Result<Vec<VolumeConfig>>;
    
    /// Get networks needed by this service
    async fn get_networks(&self) -> Result<Vec<NetworkConfig>>;
    
    /// Validate service configuration
    async fn validate_config(&self) -> Result<()>;
}

/// Docker Compose file structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComposeFile {
    pub version: String,
    pub services: HashMap<String, ServiceDefinition>,
    pub networks: HashMap<String, NetworkConfig>,
    pub volumes: HashMap<String, VolumeConfig>,
}

impl Default for ComposeFile {
    fn default() -> Self {
        Self {
            version: "3.8".to_string(),
            services: HashMap::new(),
            networks: HashMap::new(),
            volumes: HashMap::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_compose_orchestrator_creation() {
        let config = ComposeConfig::default();
        let orchestrator = ComposeOrchestrator::new(config).await;
        assert!(orchestrator.is_ok());
    }

    #[tokio::test]
    async fn test_compose_file_serialization() {
        let compose_file = ComposeFile::default();
        let yaml = serde_yaml::to_string(&compose_file);
        assert!(yaml.is_ok());
    }
}