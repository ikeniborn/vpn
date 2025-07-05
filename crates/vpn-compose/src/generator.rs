//! Docker Compose file generation

use crate::config::ComposeConfig;
use crate::environment::Environment;
use crate::error::{ComposeError, Result};
use crate::template::{TemplateContext, TemplateManager};
use std::path::PathBuf;
use tracing::{debug, info};

/// Options for compose file generation
#[derive(Debug, Clone)]
pub struct GeneratorOptions {
    pub output_dir: PathBuf,
    pub environment: String,
    pub include_monitoring: bool,
    pub include_dev_tools: bool,
}

impl Default for GeneratorOptions {
    fn default() -> Self {
        Self {
            output_dir: PathBuf::from("./docker-compose"),
            environment: "development".to_string(),
            include_monitoring: true,
            include_dev_tools: false,
        }
    }
}

/// Docker Compose file generator
pub struct ComposeGenerator {
    config: ComposeConfig,
    template_manager: TemplateManager,
    options: GeneratorOptions,
    environment: Environment,
}

impl ComposeGenerator {
    /// Create a new compose generator
    pub async fn new(config: &ComposeConfig) -> Result<Self> {
        let template_manager = TemplateManager::new(config).await?;
        let options = GeneratorOptions::default();
        let environment = Environment::new(&config.environment).await?;

        Ok(Self {
            config: config.clone(),
            template_manager,
            options,
            environment,
        })
    }

    /// Generate all Docker Compose files
    pub async fn generate_compose_files(&mut self) -> Result<()> {
        info!(
            "Generating Docker Compose files for environment: {}",
            self.options.environment
        );

        // Ensure output directory exists
        tokio::fs::create_dir_all(&self.options.output_dir).await?;

        // Load templates
        self.template_manager.load_templates().await?;

        // Create template context
        let context = self.create_template_context().await?;

        // Generate main compose file
        self.generate_main_compose_file(&context).await?;

        // Generate environment-specific override
        self.generate_environment_override(&context).await?;

        // Generate configuration files
        self.generate_configuration_files(&context).await?;

        // Generate environment file
        self.generate_env_file(&context).await?;

        info!("Docker Compose files generated successfully");
        Ok(())
    }

    /// Generate the main docker-compose.yml file
    async fn generate_main_compose_file(&self, context: &TemplateContext) -> Result<()> {
        debug!("Generating main docker-compose.yml");

        let compose_content = self.template_manager.generate_compose_file(context)?;
        let output_path = self.options.output_dir.join("docker-compose.yml");

        tokio::fs::write(&output_path, compose_content)
            .await
            .map_err(|_e| {
                ComposeError::file_operation_failed("write", output_path.to_string_lossy())
            })?;

        info!("Generated docker-compose.yml");
        Ok(())
    }

    /// Generate environment-specific override file
    async fn generate_environment_override(&self, context: &TemplateContext) -> Result<()> {
        debug!(
            "Generating environment override: {}",
            self.options.environment
        );

        if let Some(env_name) = &context.environment {
            if let Ok(override_content) = self.template_manager.render_template(env_name, context) {
                let filename = format!("docker-compose.{}.yml", env_name);
                let output_path = self.options.output_dir.join(filename);

                tokio::fs::write(&output_path, override_content)
                    .await
                    .map_err(|_e| {
                        ComposeError::file_operation_failed("write", output_path.to_string_lossy())
                    })?;

                info!("Generated environment override: {}", env_name);
            }
        }

        Ok(())
    }

    /// Generate configuration files for services
    async fn generate_configuration_files(&self, context: &TemplateContext) -> Result<()> {
        debug!("Generating service configuration files");

        let configs_dir = self.options.output_dir.join("configs");
        tokio::fs::create_dir_all(&configs_dir).await?;

        // Generate configuration files using template manager
        self.template_manager
            .generate_config_files(context, &self.options.output_dir)?;

        info!("Generated service configuration files");
        Ok(())
    }

    /// Generate .env file
    async fn generate_env_file(&self, context: &TemplateContext) -> Result<()> {
        debug!("Generating .env file");

        let mut env_content = String::new();
        env_content.push_str("# VPN System Environment Configuration\n");
        env_content.push_str("# Generated automatically - do not edit manually\n\n");

        // Add context-based environment variables
        env_content.push_str(&format!("DOMAIN_NAME={}\n", context.domain_name));
        env_content.push_str(&format!("VPN_PORT={}\n", context.ports.vpn_port));
        env_content.push_str(&format!("API_PORT={}\n", context.ports.api_port));
        env_content.push_str(&format!(
            "NGINX_HTTP_PORT={}\n",
            context.ports.nginx_http_port
        ));
        env_content.push_str(&format!(
            "NGINX_HTTPS_PORT={}\n",
            context.ports.nginx_https_port
        ));

        env_content.push_str(&format!("POSTGRES_DB={}\n", context.database.postgres_db));
        env_content.push_str(&format!(
            "POSTGRES_USER={}\n",
            context.database.postgres_user
        ));
        env_content.push_str(&format!(
            "POSTGRES_PASSWORD={}\n",
            context.database.postgres_password
        ));
        env_content.push_str(&format!(
            "REDIS_PASSWORD={}\n",
            context.database.redis_password
        ));

        env_content.push_str(&format!("JWT_SECRET={}\n", context.security.jwt_secret));

        if context.monitoring.enabled {
            env_content.push_str(&format!(
                "PROMETHEUS_PORT={}\n",
                context.ports.prometheus_port
            ));
            env_content.push_str(&format!("GRAFANA_PORT={}\n", context.ports.grafana_port));
            env_content.push_str(&format!(
                "GRAFANA_PASSWORD={}\n",
                context.monitoring.grafana_password
            ));
        }

        // Add custom environment variables
        for (key, value) in &context.env_vars {
            env_content.push_str(&format!("{}={}\n", key, value));
        }

        let output_path = self.options.output_dir.join(".env");
        tokio::fs::write(&output_path, env_content)
            .await
            .map_err(|_e| {
                ComposeError::file_operation_failed("write", output_path.to_string_lossy())
            })?;

        info!("Generated .env file");
        Ok(())
    }

    /// Create template context from configuration
    async fn create_template_context(&self) -> Result<TemplateContext> {
        debug!("Creating template context");

        let mut context = TemplateContext {
            project_name: self.config.project_name.clone(),
            environment: Some(self.options.environment.clone()),
            domain_name: self
                .config
                .env_vars
                .get("DOMAIN_NAME")
                .cloned()
                .unwrap_or_else(|| "vpn.localhost".to_string()),
            ..TemplateContext::default()
        };

        // Configure ports from environment variables or config
        if let Some(vpn_port) = self.config.env_vars.get("VPN_PORT") {
            if let Ok(port) = vpn_port.parse::<u16>() {
                context.ports.vpn_port = port;
            }
        }

        if let Some(api_port) = self.config.env_vars.get("API_PORT") {
            if let Ok(port) = api_port.parse::<u16>() {
                context.ports.api_port = port;
            }
        }

        // Configure database from environment variables
        if let Some(db_name) = self.config.env_vars.get("POSTGRES_DB") {
            context.database.postgres_db = db_name.clone();
        }

        if let Some(db_user) = self.config.env_vars.get("POSTGRES_USER") {
            context.database.postgres_user = db_user.clone();
        }

        // Add all environment variables to context
        context.env_vars = self.config.env_vars.clone();

        // Environment-specific adjustments
        match self.options.environment.as_str() {
            "development" => {
                context.monitoring.enabled = self.options.include_monitoring;
                // Add development-specific context
            }
            "production" => {
                context.monitoring.enabled = true;
                context.monitoring.retention_days = 90;
                // Add production-specific context
            }
            "staging" => {
                context.monitoring.enabled = true;
                context.monitoring.retention_days = 30;
                // Add staging-specific context
            }
            _ => {}
        }

        Ok(context)
    }

    /// Update generator configuration
    pub async fn update_config(&mut self, config: &ComposeConfig) -> Result<()> {
        self.config = config.clone();
        self.template_manager = TemplateManager::new(config).await?;
        Ok(())
    }

    /// Set generation options
    pub fn set_options(&mut self, options: GeneratorOptions) {
        self.options = options;
    }

    /// Set environment
    pub async fn set_environment(&mut self, environment: &Environment) -> Result<()> {
        self.environment = environment.clone();
        self.options.environment = environment.get_name().to_string();
        Ok(())
    }

    /// Generate a specific service configuration
    pub async fn generate_service_config(&self, service_name: &str) -> Result<String> {
        debug!("Generating configuration for service: {}", service_name);

        let context = self.create_template_context().await?;
        let template_name = format!("{}-config", service_name);

        self.template_manager
            .render_template(&template_name, &context)
            .map_err(|e| {
                ComposeError::generation_failed(format!(
                    "Failed to generate config for {}: {}",
                    service_name, e
                ))
            })
    }

    /// Validate generated files
    pub async fn validate_generated_files(&self) -> Result<()> {
        debug!("Validating generated Docker Compose files");

        let compose_file = self.options.output_dir.join("docker-compose.yml");
        if !compose_file.exists() {
            return Err(ComposeError::validation_failed(
                "Main docker-compose.yml file not found",
            ));
        }

        // Validate YAML syntax
        let content = tokio::fs::read_to_string(&compose_file).await?;
        serde_yaml::from_str::<serde_yaml::Value>(&content).map_err(|e| {
            ComposeError::validation_failed(format!(
                "Invalid YAML syntax in docker-compose.yml: {}",
                e
            ))
        })?;

        info!("Docker Compose files validation passed");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    async fn create_test_generator() -> (ComposeGenerator, TempDir) {
        let temp_dir = TempDir::new().unwrap();
        let templates_dir = temp_dir.path().join("templates");
        let compose_dir = temp_dir.path().join("compose");

        tokio::fs::create_dir_all(&templates_dir).await.unwrap();
        tokio::fs::create_dir_all(&compose_dir).await.unwrap();

        // Create a minimal template
        let template_content = r#"
version: '3.8'
services:
  test:
    image: nginx
"#;
        tokio::fs::write(templates_dir.join("base.yml"), template_content)
            .await
            .unwrap();

        let config = ComposeConfig {
            templates_dir,
            compose_dir: compose_dir.clone(),
            ..ComposeConfig::default()
        };

        let mut generator = ComposeGenerator::new(&config).await.unwrap();
        generator.set_options(GeneratorOptions {
            output_dir: compose_dir,
            ..GeneratorOptions::default()
        });

        (generator, temp_dir)
    }

    #[tokio::test]
    async fn test_generator_creation() {
        let config = ComposeConfig::default();
        let result = ComposeGenerator::new(&config).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_generate_compose_files() {
        let (mut generator, _temp_dir) = create_test_generator().await;

        let result = generator.generate_compose_files().await;
        assert!(result.is_ok());

        // Check if files were created
        let compose_file = generator.options.output_dir.join("docker-compose.yml");
        assert!(compose_file.exists());
    }

    #[tokio::test]
    async fn test_template_context_creation() {
        let (generator, _temp_dir) = create_test_generator().await;

        let result = generator.create_template_context().await;
        assert!(result.is_ok());

        let context = result.unwrap();
        assert_eq!(context.project_name, "vpn-system");
        assert!(context.environment.is_some());
    }
}
