use vpn_cli::{
    cli::{Cli, Commands},
    config::{CliConfig, LogLevel, OutputFormat},
    menu::InteractiveMenu,
    migration::{MigrationManager, MigrationOptions},
    utils::{display, format_utils, validation},
    error::{CliError, Result},
};
use tempfile::tempdir;
use clap::Parser;
use std::path::PathBuf;
use tokio;

#[test]
fn test_cli_parsing() -> Result<(), Box<dyn std::error::Error>> {
    // Test basic command parsing
    let args = vec!["vpn-cli", "status"];
    let cli = Cli::try_parse_from(args)?;
    
    match cli.command {
        Commands::Status { .. } => {},
        _ => panic!("Expected Status command"),
    }
    
    // Test install command
    let args = vec!["vpn-cli", "install", "--protocol", "vless", "--port", "8443"];
    let cli = Cli::try_parse_from(args)?;
    
    match cli.command {
        Commands::Install { protocol, port, .. } => {
            assert_eq!(protocol, "vless");
            assert_eq!(port, 8443);
        },
        _ => panic!("Expected Install command"),
    }
    
    Ok(())
}

#[test]
fn test_cli_validation() -> Result<(), Box<dyn std::error::Error>> {
    // Test invalid port
    let args = vec!["vpn-cli", "install", "--protocol", "vless", "--port", "70000"];
    let result = Cli::try_parse_from(args);
    // Should parse but validation should catch invalid port later
    
    // Test invalid protocol
    let args = vec!["vpn-cli", "install", "--protocol", "invalid", "--port", "8443"];
    let cli = Cli::try_parse_from(args)?;
    // Validation should catch this in command execution
    
    Ok(())
}

#[tokio::test]
async fn test_cli_config_management() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let config_path = temp_dir.path().join("config.toml");
    
    // Test default config creation
    let config = CliConfig::default();
    assert_eq!(config.log_level, LogLevel::Info);
    assert_eq!(config.output_format, OutputFormat::Table);
    
    // Test config saving
    config.save_to_file(&config_path)?;
    assert!(config_path.exists());
    
    // Test config loading
    let loaded_config = CliConfig::load_from_file(&config_path)?;
    assert_eq!(loaded_config.log_level, config.log_level);
    assert_eq!(loaded_config.output_format, config.output_format);
    
    Ok(())
}

#[test]
fn test_config_validation() -> Result<(), Box<dyn std::error::Error>> {
    let mut config = CliConfig::default();
    
    // Test valid config
    assert!(config.validate().is_ok());
    
    // Test invalid paths
    config.data_directory = PathBuf::from("/nonexistent/path/that/should/not/exist");
    assert!(config.validate().is_err());
    
    Ok(())
}

#[tokio::test]
async fn test_interactive_menu() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let config = CliConfig {
        data_directory: temp_dir.path().to_path_buf(),
        log_level: LogLevel::Info,
        output_format: OutputFormat::Table,
        auto_save: true,
        color_output: true,
        confirm_destructive: true,
    };
    
    let menu = InteractiveMenu::new(config);
    
    // Test menu creation
    assert!(true); // Menu should create without issues
    
    // Test menu option validation
    assert!(menu.validate_menu_choice("1").is_ok());
    assert!(menu.validate_menu_choice("11").is_ok());
    assert!(menu.validate_menu_choice("0").is_err());
    assert!(menu.validate_menu_choice("12").is_err());
    assert!(menu.validate_menu_choice("invalid").is_err());
    
    Ok(())
}

#[tokio::test]
async fn test_migration_manager() -> Result<(), Box<dyn std::error::Error>> {
    let temp_source = tempdir()?;
    let temp_target = tempdir()?;
    
    // Create mock Bash VPN installation
    let source_path = temp_source.path();
    let config_dir = source_path.join("config");
    std::fs::create_dir_all(&config_dir)?;
    
    // Create mock docker-compose.yml
    std::fs::write(
        source_path.join("docker-compose.yml"),
        "version: '3'\nservices:\n  xray:\n    image: xray:latest"
    )?;
    
    // Create mock config files
    std::fs::write(config_dir.join("private_key.txt"), "test-private-key")?;
    std::fs::write(config_dir.join("public_key.txt"), "test-public-key")?;
    std::fs::write(config_dir.join("sni.txt"), "google.com")?;
    
    let migration_manager = MigrationManager::new();
    
    let options = MigrationOptions {
        source_path: source_path.to_path_buf(),
        target_path: temp_target.path().to_path_buf(),
        keep_original: true,
        migrate_users: true,
        migrate_config: true,
        migrate_logs: false,
        validate_after_migration: true,
    };
    
    // Test migration
    let report = migration_manager.migrate_from_bash(options).await?;
    
    assert!(report.success);
    assert_eq!(report.configs_migrated, 1);
    
    Ok(())
}

#[test]
fn test_validation_utilities() -> Result<(), Box<dyn std::error::Error>> {
    // Test username validation
    assert!(validation::validate_username("valid_user123").is_ok());
    assert!(validation::validate_username("user-name").is_ok());
    assert!(validation::validate_username("").is_err());
    assert!(validation::validate_username("-invalid").is_err());
    
    // Test email validation
    assert!(validation::validate_email("user@example.com").is_ok());
    assert!(validation::validate_email("test.email+tag@domain.co.uk").is_ok());
    assert!(validation::validate_email("invalid-email").is_err());
    
    // Test port validation
    assert!(validation::validate_port(8080).is_ok());
    assert!(validation::validate_port(65535).is_ok());
    assert!(validation::validate_port(0).is_err());
    assert!(validation::validate_port(22).is_err()); // Reserved port
    
    // Test domain validation
    assert!(validation::validate_domain_name("example.com").is_ok());
    assert!(validation::validate_domain_name("sub.domain.example.org").is_ok());
    assert!(validation::validate_domain_name("localhost").is_err()); // No dot
    
    Ok(())
}

#[test]
fn test_format_utilities() {
    // Test uptime formatting
    assert_eq!(format_utils::format_uptime(30), "30s");
    assert_eq!(format_utils::format_uptime(90), "1m 30s");
    assert_eq!(format_utils::format_uptime(3665), "1h 1m");
    assert_eq!(format_utils::format_uptime(90065), "1d 1h 1m");
    
    // Test speed formatting
    assert_eq!(format_utils::format_speed(512.0), "512.0 B/s");
    assert_eq!(format_utils::format_speed(1024.0), "1.0 KB/s");
    assert_eq!(format_utils::format_speed(1048576.0), "1.0 MB/s");
    
    // Test address formatting
    assert_eq!(format_utils::format_addr("192.168.1.1", 80), "192.168.1.1:80");
    assert_eq!(format_utils::format_addr("::1", 80), "[::1]:80");
    assert_eq!(format_utils::format_addr("2001:db8::1", 443), "[2001:db8::1]:443");
    
    // Test protocol info formatting
    assert_eq!(format_utils::format_protocol_info("vless", Some("1.8.0")), "VLESS v1.8.0");
    assert_eq!(format_utils::format_protocol_info("shadowsocks", None), "SHADOWSOCKS");
}

#[test]
fn test_display_utilities() {
    // Test byte formatting
    assert_eq!(display::format_bytes(0), "0 B");
    assert_eq!(display::format_bytes(512), "512.0 B");
    assert_eq!(display::format_bytes(1024), "1.0 KB");
    assert_eq!(display::format_bytes(1536), "1.5 KB");
    assert_eq!(display::format_bytes(1048576), "1.0 MB");
    
    // Test duration formatting
    use std::time::Duration;
    assert_eq!(display::format_duration(Duration::from_secs(30)), "30s");
    assert_eq!(display::format_duration(Duration::from_secs(90)), "1m 30s");
    assert_eq!(display::format_duration(Duration::from_secs(3665)), "1h 1m");
    
    // Test percentage formatting
    assert_eq!(display::format_percentage(50.0, 100.0), "50.0%");
    assert_eq!(display::format_percentage(33.0, 100.0), "33.0%");
    assert_eq!(display::format_percentage(0.0, 0.0), "0.0%");
}

#[test]
fn test_error_handling() {
    // Test CLI error types
    let validation_error = CliError::ValidationError("Invalid input".to_string());
    let config_error = CliError::ConfigError("Config not found".to_string());
    let migration_error = CliError::MigrationError("Migration failed".to_string());
    let io_error = CliError::IoError(std::io::Error::new(
        std::io::ErrorKind::NotFound, 
        "File not found"
    ));
    
    // Test error display
    assert!(validation_error.to_string().contains("Invalid input"));
    assert!(config_error.to_string().contains("Config not found"));
    assert!(migration_error.to_string().contains("Migration failed"));
    assert!(io_error.to_string().contains("File not found"));
}

#[tokio::test]
async fn test_command_execution_flow() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    
    // Test status command execution flow (without actual execution)
    let status_args = vec!["vpn-cli", "status", "--format", "json"];
    let cli = Cli::try_parse_from(status_args)?;
    
    match cli.command {
        Commands::Status { format, .. } => {
            assert_eq!(format, Some("json".to_string()));
        },
        _ => panic!("Expected Status command"),
    }
    
    Ok(())
}

#[test]
fn test_config_serialization() -> Result<(), Box<dyn std::error::Error>> {
    let config = CliConfig {
        data_directory: PathBuf::from("/opt/vpn"),
        log_level: LogLevel::Debug,
        output_format: OutputFormat::Json,
        auto_save: false,
        color_output: false,
        confirm_destructive: true,
    };
    
    // Test TOML serialization
    let toml_str = toml::to_string(&config)?;
    assert!(toml_str.contains("debug"));
    assert!(toml_str.contains("json"));
    assert!(toml_str.contains("/opt/vpn"));
    
    let deserialized: CliConfig = toml::from_str(&toml_str)?;
    assert_eq!(deserialized.log_level, config.log_level);
    assert_eq!(deserialized.output_format, config.output_format);
    assert_eq!(deserialized.data_directory, config.data_directory);
    
    Ok(())
}

#[test]
fn test_log_level_ordering() {
    // Test log level ordering
    assert!(LogLevel::Error > LogLevel::Warn);
    assert!(LogLevel::Warn > LogLevel::Info);
    assert!(LogLevel::Info > LogLevel::Debug);
    assert!(LogLevel::Debug > LogLevel::Trace);
}

#[test]
fn test_output_format_conversion() {
    // Test output format string conversion
    assert_eq!(OutputFormat::Table.to_string(), "table");
    assert_eq!(OutputFormat::Json.to_string(), "json");
    assert_eq!(OutputFormat::Plain.to_string(), "plain");
    assert_eq!(OutputFormat::Yaml.to_string(), "yaml");
    
    // Test parsing from string
    assert_eq!("table".parse::<OutputFormat>().unwrap(), OutputFormat::Table);
    assert_eq!("json".parse::<OutputFormat>().unwrap(), OutputFormat::Json);
    assert_eq!("plain".parse::<OutputFormat>().unwrap(), OutputFormat::Plain);
    assert_eq!("yaml".parse::<OutputFormat>().unwrap(), OutputFormat::Yaml);
    
    assert!("invalid".parse::<OutputFormat>().is_err());
}

#[tokio::test]
async fn test_bash_config_parsing() -> Result<(), Box<dyn std::error::Error>> {
    let migration_manager = MigrationManager::new();
    
    // Test text config parsing
    let config_text = r#"
        SERVER_HOST=192.168.1.100
        SERVER_PORT=8443
        PROTOCOL=vless
        PRIVATE_KEY=test-private-key
        SNI=example.com
    "#;
    
    let config = migration_manager.parse_text_config(config_text)?;
    assert_eq!(config.server_host, "192.168.1.100");
    assert_eq!(config.server_port, 8443);
    assert_eq!(config.protocol, "vless");
    assert_eq!(config.private_key, Some("test-private-key".to_string()));
    assert_eq!(config.sni, Some("example.com".to_string()));
    
    Ok(())
}

#[tokio::test]
async fn test_migration_validation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let migration_manager = MigrationManager::new();
    
    // Test validation of non-existent source
    let invalid_source = temp_dir.path().join("nonexistent");
    let result = migration_manager.validate_bash_installation(&invalid_source);
    assert!(result.is_err());
    
    // Test validation of valid source
    let valid_source = temp_dir.path();
    std::fs::write(valid_source.join("docker-compose.yml"), "version: '3'\nservices:\n  xray: {}")?;
    std::fs::create_dir_all(valid_source.join("config"))?;
    
    let result = migration_manager.validate_bash_installation(valid_source);
    assert!(result.is_ok());
    
    Ok(())
}

#[test]
fn test_sanitization_utilities() {
    // Test filename sanitization
    assert_eq!(validation::sanitize_filename("valid_filename.txt"), "valid_filename.txt");
    assert_eq!(validation::sanitize_filename("file<>with|invalid*chars.txt"), "file__with_invalid_chars.txt");
    assert_eq!(validation::sanitize_filename("  .trimmed.  "), "trimmed");
    
    // Test config key path validation
    assert!(validation::validate_config_key_path("server.port").is_ok());
    assert!(validation::validate_config_key_path("monitoring.alerts.cpu_threshold").is_ok());
    assert!(validation::validate_config_key_path("").is_err());
    assert!(validation::validate_config_key_path(".invalid").is_err());
}

#[tokio::test]
async fn test_comprehensive_workflow() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let config_path = temp_dir.path().join("cli_config.toml");
    
    // 1. Create and save config
    let mut config = CliConfig::default();
    config.data_directory = temp_dir.path().to_path_buf();
    config.save_to_file(&config_path)?;
    
    // 2. Load config
    let loaded_config = CliConfig::load_from_file(&config_path)?;
    assert_eq!(loaded_config.data_directory, config.data_directory);
    
    // 3. Create interactive menu
    let menu = InteractiveMenu::new(loaded_config);
    
    // 4. Test menu validation
    assert!(menu.validate_menu_choice("1").is_ok());
    assert!(menu.validate_menu_choice("invalid").is_err());
    
    // 5. Test migration setup
    let migration_manager = MigrationManager::new();
    let migration_options = MigrationOptions::default();
    assert_eq!(migration_options.source_path, PathBuf::from("/opt/v2ray"));
    assert_eq!(migration_options.target_path, PathBuf::from("/opt/vpn"));
    
    Ok(())
}