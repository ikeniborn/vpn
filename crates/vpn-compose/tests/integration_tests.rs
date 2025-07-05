use std::path::PathBuf;
use tempfile::TempDir;
use vpn_compose::{
    ComposeConfig, ComposeError, ComposeFile, ComposeGenerator, ComposeOrchestrator, Environment,
    GeneratorOptions, ServiceManager, TemplateContext, TemplateManager,
};

async fn setup_test_environment() -> (TempDir, ComposeConfig) {
    let temp_dir = TempDir::new().unwrap();
    let templates_dir = temp_dir.path().join("templates");
    let compose_dir = temp_dir.path().join("compose");

    // Create directories
    tokio::fs::create_dir_all(&templates_dir).await.unwrap();
    tokio::fs::create_dir_all(&compose_dir).await.unwrap();

    // Create a basic template
    let base_template = r#"
version: '3.8'
services:
  vpn-server:
    image: ghcr.io/xtls/xray-core:latest
    container_name: vpn-server
    ports:
      - "${VPN_PORT:-8443}:8443"
    environment:
      - LOG_LEVEL=${LOG_LEVEL:-info}
networks:
  vpn-network:
    driver: bridge
volumes:
  vpn-data:
    driver: local
"#;

    tokio::fs::write(templates_dir.join("base.yml"), base_template)
        .await
        .unwrap();

    let config = ComposeConfig {
        templates_dir,
        compose_dir: compose_dir.clone(),
        ..ComposeConfig::default()
    };

    (temp_dir, config)
}

#[tokio::test]
async fn test_compose_orchestrator_initialization() {
    let (_temp_dir, config) = setup_test_environment().await;

    let orchestrator = ComposeOrchestrator::new(config).await;
    assert!(orchestrator.is_ok());

    let mut orchestrator = orchestrator.unwrap();
    let result = orchestrator.initialize().await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_template_loading() {
    let (_temp_dir, config) = setup_test_environment().await;

    let mut template_manager = TemplateManager::new(&config).await.unwrap();
    let result = template_manager.load_templates().await;
    assert!(result.is_ok());

    let templates = template_manager.get_available_templates();
    assert!(templates.contains(&"base".to_string()));
}

#[tokio::test]
async fn test_compose_file_generation() {
    let (_temp_dir, config) = setup_test_environment().await;

    let mut generator = ComposeGenerator::new(&config).await.unwrap();
    generator.set_options(GeneratorOptions {
        output_dir: config.compose_dir.clone(),
        environment: "development".to_string(),
        include_monitoring: true,
        include_dev_tools: false,
    });

    let result = generator.generate_compose_files().await;
    assert!(result.is_ok());

    // Check if docker-compose.yml was created
    let compose_file = config.compose_dir.join("docker-compose.yml");
    assert!(compose_file.exists());

    // Check if .env file was created
    let env_file = config.compose_dir.join(".env");
    assert!(env_file.exists());
}

#[tokio::test]
async fn test_service_definitions() {
    let mut service_manager = ServiceManager::new();
    service_manager.load_predefined_services();

    // Check all predefined services exist
    assert!(service_manager.get_service("vpn-server").is_some());
    assert!(service_manager.get_service("nginx-proxy").is_some());
    assert!(service_manager.get_service("postgres").is_some());
    assert!(service_manager.get_service("redis").is_some());
    assert!(service_manager.get_service("prometheus").is_some());
    assert!(service_manager.get_service("grafana").is_some());
    assert!(service_manager.get_service("jaeger").is_some());

    // Validate dependencies
    let result = service_manager.validate_dependencies();
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_service_dependency_ordering() {
    let mut service_manager = ServiceManager::new();
    service_manager.load_predefined_services();

    let result = service_manager.get_services_in_order();
    assert!(result.is_ok());

    let ordered_services = result.unwrap();

    // Find positions of services
    let postgres_pos = ordered_services
        .iter()
        .position(|s| s == "postgres")
        .unwrap();
    let redis_pos = ordered_services.iter().position(|s| s == "redis").unwrap();
    let vpn_server_pos = ordered_services
        .iter()
        .position(|s| s == "vpn-server")
        .unwrap();
    let nginx_pos = ordered_services
        .iter()
        .position(|s| s == "nginx-proxy")
        .unwrap();

    // Verify dependency order
    assert!(postgres_pos < vpn_server_pos); // postgres before vpn-server
    assert!(redis_pos < vpn_server_pos); // redis before vpn-server
    assert!(vpn_server_pos < nginx_pos); // vpn-server before nginx
}

#[tokio::test]
async fn test_environment_configurations() {
    // Test development environment
    let dev_env = Environment::development();
    assert!(dev_env.is_development());
    assert_eq!(dev_env.get_name(), "development");

    let dev_vars = dev_env.get_variables();
    assert_eq!(dev_vars.get("LOG_LEVEL"), Some(&"debug".to_string()));
    assert_eq!(dev_vars.get("DEV_MODE"), Some(&"true".to_string()));

    // Test staging environment
    let staging_env = Environment::staging();
    assert!(staging_env.is_staging());
    assert_eq!(staging_env.get_name(), "staging");

    let staging_vars = staging_env.get_variables();
    assert_eq!(staging_vars.get("LOG_LEVEL"), Some(&"info".to_string()));
    assert_eq!(staging_vars.get("DEV_MODE"), Some(&"false".to_string()));

    // Test production environment
    let prod_env = Environment::production();
    assert!(prod_env.is_production());
    assert_eq!(prod_env.get_name(), "production");

    let prod_vars = prod_env.get_variables();
    assert_eq!(prod_vars.get("LOG_LEVEL"), Some(&"warn".to_string()));
    assert_eq!(prod_vars.get("DEV_MODE"), Some(&"false".to_string()));
}

#[tokio::test]
async fn test_environment_compose_files() {
    let dev_env = Environment::development();
    let files = dev_env.get_compose_files();
    assert_eq!(files.len(), 2);
    assert!(files.contains(&"docker-compose.yml".to_string()));
    assert!(files.contains(&"docker-compose.development.yml".to_string()));

    let staging_env = Environment::staging();
    let files = staging_env.get_compose_files();
    assert!(files.contains(&"docker-compose.staging.yml".to_string()));

    let prod_env = Environment::production();
    let files = prod_env.get_compose_files();
    assert!(files.contains(&"docker-compose.production.yml".to_string()));
}

#[tokio::test]
async fn test_template_context_generation() {
    let context = TemplateContext::default();

    assert_eq!(context.project_name, "vpn-system");
    assert_eq!(context.domain_name, "vpn.localhost");
    assert_eq!(context.ports.vpn_port, 8443);
    assert_eq!(context.ports.api_port, 3000);
    assert_eq!(context.database.postgres_db, "vpndb");
}

#[tokio::test]
async fn test_compose_file_structure() {
    let compose_file = ComposeFile::default();

    assert_eq!(compose_file.version, "3.8");
    assert!(compose_file.services.is_empty());
    assert!(compose_file.networks.is_empty());
    assert!(compose_file.volumes.is_empty());

    // Test serialization
    let yaml = serde_yaml::to_string(&compose_file);
    assert!(yaml.is_ok());

    let yaml_str = yaml.unwrap();
    assert!(yaml_str.contains("version: '3.8'"));
}

#[tokio::test]
async fn test_circular_dependency_detection() {
    use vpn_compose::services::ServiceDefinition;

    let mut service_manager = ServiceManager::new();

    // Create circular dependency: A -> B -> C -> A
    let mut service_a = ServiceDefinition {
        image: "test:latest".to_string(),
        depends_on: vec!["service-b".to_string()],
        ..Default::default()
    };

    let mut service_b = ServiceDefinition {
        image: "test:latest".to_string(),
        depends_on: vec!["service-c".to_string()],
        ..Default::default()
    };

    let mut service_c = ServiceDefinition {
        image: "test:latest".to_string(),
        depends_on: vec!["service-a".to_string()],
        ..Default::default()
    };

    service_manager.add_service("service-a".to_string(), service_a);
    service_manager.add_service("service-b".to_string(), service_b);
    service_manager.add_service("service-c".to_string(), service_c);

    let result = service_manager.get_services_in_order();
    assert!(result.is_err());
}

#[tokio::test]
async fn test_environment_validation() {
    let mut env = Environment::development();

    // Should pass with default values
    let result = env.validate();
    assert!(result.is_ok());

    // Test invalid port
    env.set_variable("VPN_PORT".to_string(), "invalid".to_string());
    let result = env.validate();
    assert!(result.is_err());

    // Test production port validation
    let mut prod_env = Environment::production();
    prod_env.set_variable("VPN_PORT".to_string(), "80".to_string());
    let result = prod_env.validate();
    assert!(result.is_err()); // Should fail for port < 1024 in production
}

#[tokio::test]
async fn test_generator_with_multiple_environments() {
    let (_temp_dir, config) = setup_test_environment().await;

    // Create environment templates
    let dev_template = r#"
version: '3.8'
services:
  vpn-server:
    environment:
      - DEBUG=true
"#;

    let staging_template = r#"
version: '3.8'
services:
  vpn-server:
    deploy:
      replicas: 2
"#;

    let prod_template = r#"
version: '3.8'
services:
  vpn-server:
    deploy:
      replicas: 3
    logging:
      driver: json-file
"#;

    tokio::fs::write(config.templates_dir.join("development.yml"), dev_template)
        .await
        .unwrap();
    tokio::fs::write(config.templates_dir.join("staging.yml"), staging_template)
        .await
        .unwrap();
    tokio::fs::write(config.templates_dir.join("production.yml"), prod_template)
        .await
        .unwrap();

    // Generate for different environments
    for env in ["development", "staging", "production"] {
        let mut generator = ComposeGenerator::new(&config).await.unwrap();
        generator.set_options(GeneratorOptions {
            output_dir: config.compose_dir.join(env),
            environment: env.to_string(),
            include_monitoring: true,
            include_dev_tools: env == "development",
        });

        tokio::fs::create_dir_all(&config.compose_dir.join(env))
            .await
            .unwrap();

        let result = generator.generate_compose_files().await;
        assert!(result.is_ok());

        // Check environment-specific files
        let compose_file = config.compose_dir.join(env).join("docker-compose.yml");
        assert!(compose_file.exists());

        let env_override = config
            .compose_dir
            .join(env)
            .join(format!("docker-compose.{}.yml", env));
        assert!(env_override.exists());
    }
}
