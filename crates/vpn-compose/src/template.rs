//! Template management for Docker Compose files

use crate::config::ComposeConfig;
use crate::error::{ComposeError, Result};
use handlebars::Handlebars;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use tera::Tera;
use tracing::{debug, info};

/// Template manager for generating Docker Compose files
pub struct TemplateManager {
    config: ComposeConfig,
    handlebars: Handlebars<'static>,
    tera: Tera,
    templates: HashMap<String, String>,
}

impl TemplateManager {
    /// Create a new template manager
    pub async fn new(config: &ComposeConfig) -> Result<Self> {
        let mut handlebars = Handlebars::new();
        handlebars.set_strict_mode(true);

        // Initialize Tera with templates directory
        let templates_glob = format!("{}/**/*", config.templates_dir.to_string_lossy());
        let tera = Tera::new(&templates_glob)
            .map_err(|e| ComposeError::template_error(format!("Failed to initialize Tera: {}", e)))?;

        Ok(Self {
            config: config.clone(),
            handlebars,
            tera,
            templates: HashMap::new(),
        })
    }

    /// Load all templates from the templates directory
    pub async fn load_templates(&mut self) -> Result<()> {
        info!("Loading Docker Compose templates");

        // Load base template
        self.load_template("base", "base.yml").await?;
        
        // Load environment-specific templates
        self.load_template("development", "development.yml").await?;
        self.load_template("staging", "staging.yml").await?;
        self.load_template("production", "production.yml").await?;
        
        // Load configuration templates
        self.load_config_templates().await?;

        info!("Templates loaded successfully");
        Ok(())
    }

    /// Load a specific template
    async fn load_template(&mut self, name: &str, filename: &str) -> Result<()> {
        let template_path = self.config.templates_dir.join(filename);
        
        if !template_path.exists() {
            debug!("Template not found: {:?}", template_path);
            return Ok(());
        }

        let content = tokio::fs::read_to_string(&template_path).await
            .map_err(|e| ComposeError::file_operation_failed("read", template_path.to_string_lossy()))?;

        // Register with both engines
        self.handlebars.register_template_string(name, &content)
            .map_err(|e| ComposeError::template_error(format!("Handlebars error: {}", e)))?;

        self.templates.insert(name.to_string(), content);
        
        debug!("Loaded template: {}", name);
        Ok(())
    }

    /// Load configuration templates (nginx, xray, etc.)
    async fn load_config_templates(&mut self) -> Result<()> {
        let configs_dir = self.config.templates_dir.join("configs");
        
        if !configs_dir.exists() {
            return Ok(());
        }

        // Load nginx config templates
        self.load_config_template("nginx-default", &configs_dir.join("nginx/default.conf")).await?;
        
        // Load xray config templates
        self.load_config_template("xray-config", &configs_dir.join("xray/config.json")).await?;
        
        // Load prometheus config templates
        self.load_config_template("prometheus-config", &configs_dir.join("prometheus/prometheus.yml")).await?;

        Ok(())
    }

    /// Load a configuration file template
    async fn load_config_template(&mut self, name: &str, path: &PathBuf) -> Result<()> {
        if !path.exists() {
            debug!("Config template not found: {:?}", path);
            return Ok(());
        }

        let content = tokio::fs::read_to_string(path).await
            .map_err(|e| ComposeError::file_operation_failed("read", path.to_string_lossy()))?;

        self.handlebars.register_template_string(name, &content)
            .map_err(|e| ComposeError::template_error(format!("Handlebars error: {}", e)))?;

        self.templates.insert(name.to_string(), content);
        
        debug!("Loaded config template: {}", name);
        Ok(())
    }

    /// Render a template with the given context
    pub fn render_template(&self, template_name: &str, context: &TemplateContext) -> Result<String> {
        debug!("Rendering template: {}", template_name);

        // Convert context to serde_json::Value for handlebars
        let json_context = serde_json::to_value(context)
            .map_err(|e| ComposeError::template_error(format!("Failed to serialize context: {}", e)))?;

        // Try handlebars first
        if self.handlebars.get_template(template_name).is_some() {
            return self.handlebars.render(template_name, &json_context)
                .map_err(|e| ComposeError::template_error(format!("Handlebars render error: {}", e)));
        }

        // Fallback to Tera
        let tera_context = tera::Context::from_serialize(context)
            .map_err(|e| ComposeError::template_error(format!("Failed to create Tera context: {}", e)))?;

        self.tera.render(template_name, &tera_context)
            .map_err(|e| ComposeError::template_error(format!("Tera render error: {}", e)))
    }

    /// Generate docker-compose.yml content
    pub fn generate_compose_file(&self, context: &TemplateContext) -> Result<String> {
        // Start with base template
        let mut compose_content = self.render_template("base", context)?;

        // Apply environment-specific overrides
        if let Some(env_template) = context.environment.as_ref() {
            if self.templates.contains_key(env_template) {
                let env_content = self.render_template(env_template, context)?;
                compose_content = self.merge_compose_files(&compose_content, &env_content)?;
            }
        }

        Ok(compose_content)
    }

    /// Generate configuration files
    pub fn generate_config_files(&self, context: &TemplateContext, output_dir: &PathBuf) -> Result<()> {
        // Generate nginx configuration
        if let Ok(nginx_config) = self.render_template("nginx-default", context) {
            let nginx_dir = output_dir.join("configs/nginx");
            std::fs::create_dir_all(&nginx_dir)?;
            std::fs::write(nginx_dir.join("default.conf"), nginx_config)?;
        }

        // Generate xray configuration
        if let Ok(xray_config) = self.render_template("xray-config", context) {
            let xray_dir = output_dir.join("configs/xray");
            std::fs::create_dir_all(&xray_dir)?;
            std::fs::write(xray_dir.join("config.json"), xray_config)?;
        }

        // Generate prometheus configuration
        if let Ok(prometheus_config) = self.render_template("prometheus-config", context) {
            let prometheus_dir = output_dir.join("configs/prometheus");
            std::fs::create_dir_all(&prometheus_dir)?;
            std::fs::write(prometheus_dir.join("prometheus.yml"), prometheus_config)?;
        }

        Ok(())
    }

    /// Merge two Docker Compose YAML files
    fn merge_compose_files(&self, base: &str, override_content: &str) -> Result<String> {
        // Parse both YAML files
        let mut base_value: serde_yaml::Value = serde_yaml::from_str(base)
            .map_err(|e| ComposeError::template_error(format!("Failed to parse base YAML: {}", e)))?;

        let override_value: serde_yaml::Value = serde_yaml::from_str(override_content)
            .map_err(|e| ComposeError::template_error(format!("Failed to parse override YAML: {}", e)))?;

        // Merge the values
        self.merge_yaml_values(&mut base_value, override_value);

        // Convert back to YAML
        serde_yaml::to_string(&base_value)
            .map_err(|e| ComposeError::template_error(format!("Failed to serialize merged YAML: {}", e)))
    }

    /// Recursively merge YAML values
    fn merge_yaml_values(&self, base: &mut serde_yaml::Value, override_val: serde_yaml::Value) {
        match (base, override_val) {
            (serde_yaml::Value::Mapping(base_map), serde_yaml::Value::Mapping(override_map)) => {
                for (key, value) in override_map {
                    if let Some(base_value) = base_map.get_mut(&key) {
                        self.merge_yaml_values(base_value, value);
                    } else {
                        base_map.insert(key, value);
                    }
                }
            }
            (base_val, override_val) => {
                *base_val = override_val;
            }
        }
    }

    /// Validate template syntax
    pub fn validate_template(&self, template_name: &str) -> Result<()> {
        if !self.templates.contains_key(template_name) {
            return Err(ComposeError::template_error(
                format!("Template not found: {}", template_name)
            ));
        }

        // Create a minimal context for validation
        let context = TemplateContext::default();
        
        // Try to render the template
        self.render_template(template_name, &context)?;
        
        Ok(())
    }

    /// Get available templates
    pub fn get_available_templates(&self) -> Vec<String> {
        self.templates.keys().cloned().collect()
    }
}

/// Context for template rendering
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateContext {
    pub project_name: String,
    pub environment: Option<String>,
    pub domain_name: String,
    pub ports: PortContext,
    pub database: DatabaseContext,
    pub security: SecurityContext,
    pub monitoring: MonitoringContext,
    pub services: Vec<ServiceContext>,
    pub env_vars: HashMap<String, String>,
}

impl Default for TemplateContext {
    fn default() -> Self {
        Self {
            project_name: "vpn-system".to_string(),
            environment: Some("development".to_string()),
            domain_name: "vpn.localhost".to_string(),
            ports: PortContext::default(),
            database: DatabaseContext::default(),
            security: SecurityContext::default(),
            monitoring: MonitoringContext::default(),
            services: vec![],
            env_vars: HashMap::new(),
        }
    }
}

/// Port configuration context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortContext {
    pub vpn_port: u16,
    pub api_port: u16,
    pub nginx_http_port: u16,
    pub nginx_https_port: u16,
    pub prometheus_port: u16,
    pub grafana_port: u16,
}

impl Default for PortContext {
    fn default() -> Self {
        Self {
            vpn_port: 8443,
            api_port: 3000,
            nginx_http_port: 80,
            nginx_https_port: 443,
            prometheus_port: 9090,
            grafana_port: 3001,
        }
    }
}

/// Database configuration context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseContext {
    pub postgres_db: String,
    pub postgres_user: String,
    pub postgres_password: String,
    pub redis_password: String,
}

impl Default for DatabaseContext {
    fn default() -> Self {
        Self {
            postgres_db: "vpndb".to_string(),
            postgres_user: "vpnuser".to_string(),
            postgres_password: "changepassword".to_string(),
            redis_password: "changepassword".to_string(),
        }
    }
}

/// Security configuration context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityContext {
    pub jwt_secret: String,
    pub ssl_cert_path: Option<String>,
    pub ssl_key_path: Option<String>,
}

impl Default for SecurityContext {
    fn default() -> Self {
        Self {
            jwt_secret: "changethissecret".to_string(),
            ssl_cert_path: None,
            ssl_key_path: None,
        }
    }
}

/// Monitoring configuration context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringContext {
    pub enabled: bool,
    pub grafana_password: String,
    pub retention_days: u32,
}

impl Default for MonitoringContext {
    fn default() -> Self {
        Self {
            enabled: true,
            grafana_password: "admin".to_string(),
            retention_days: 30,
        }
    }
}

/// Service-specific context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceContext {
    pub name: String,
    pub image: String,
    pub env_vars: HashMap<String, String>,
    pub ports: Vec<String>,
    pub volumes: Vec<String>,
}

/// Template error type
#[derive(Debug, thiserror::Error)]
pub enum TemplateError {
    #[error("Template not found: {name}")]
    NotFound { name: String },
    
    #[error("Template syntax error: {message}")]
    SyntaxError { message: String },
    
    #[error("Template rendering error: {message}")]
    RenderError { message: String },
    
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    async fn create_test_template_manager() -> (TemplateManager, TempDir) {
        let temp_dir = TempDir::new().unwrap();
        let templates_dir = temp_dir.path().to_path_buf();

        // Create a simple test template
        let template_content = r#"
version: '3.8'
services:
  test-service:
    image: nginx
    environment:
      - TEST_VAR={{env_vars.TEST_VAR}}
"#;
        
        tokio::fs::write(templates_dir.join("base.yml"), template_content).await.unwrap();

        let config = ComposeConfig {
            templates_dir,
            ..ComposeConfig::default()
        };

        let manager = TemplateManager::new(&config).await.unwrap();
        (manager, temp_dir)
    }

    #[tokio::test]
    async fn test_template_manager_creation() {
        let temp_dir = TempDir::new().unwrap();
        let config = ComposeConfig {
            templates_dir: temp_dir.path().to_path_buf(),
            ..ComposeConfig::default()
        };

        let result = TemplateManager::new(&config).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_template_loading() {
        let (mut manager, _temp_dir) = create_test_template_manager().await;
        
        let result = manager.load_templates().await;
        assert!(result.is_ok());
        
        assert!(manager.templates.contains_key("base"));
    }

    #[tokio::test]
    async fn test_template_rendering() {
        let (mut manager, _temp_dir) = create_test_template_manager().await;
        manager.load_templates().await.unwrap();

        let mut context = TemplateContext::default();
        context.env_vars.insert("TEST_VAR".to_string(), "test_value".to_string());

        let result = manager.render_template("base", &context);
        assert!(result.is_ok());
        
        let rendered = result.unwrap();
        assert!(rendered.contains("test_value"));
    }
}