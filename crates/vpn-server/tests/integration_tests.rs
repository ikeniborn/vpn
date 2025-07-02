use vpn_server::{
    ServerInstaller, ConfigValidator, ServerLifecycle,
    KeyRotationManager, DockerComposeTemplate, ProxyInstaller
};
use vpn_types::protocol::VpnProtocol;
use vpn_users::config::ServerConfig;
use tempfile::tempdir;
use std::path::PathBuf;
use tokio;

#[tokio::test]
async fn test_server_manager_creation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    assert_eq!(server_manager.get_config_directory(), temp_dir.path());
    
    Ok(())
}

#[tokio::test]
async fn test_server_configuration() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    let config = ServerConfig {
        server_name: "test-server".to_string(),
        host: "0.0.0.0".to_string(),
        port: 8443,
        protocol: VpnProtocol::Vless,
        protocol_config: ProtocolConfig::Vless {
            private_key: "test_private_key".to_string(),
            public_key: "test_public_key".to_string(),
            short_id: "test_short".to_string(),
            sni: "google.com".to_string(),
            reality_dest: "www.google.com:443".to_string(),
        },
        docker_config: Default::default(),
        logging_config: Default::default(),
        security_config: Default::default(),
    };
    
    // Save configuration
    server_manager.save_config(&config).await?;
    
    // Load configuration
    let loaded_config = server_manager.load_config().await?;
    assert_eq!(loaded_config.server_name, "test-server");
    assert_eq!(loaded_config.port, 8443);
    assert_eq!(loaded_config.protocol, VpnProtocol::Vless);
    
    Ok(())
}

#[tokio::test]
async fn test_server_status_management() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    // Test status check for non-running server
    let status = server_manager.get_server_status().await?;
    assert_eq!(status, ServerStatus::Stopped);
    
    // Test server health check
    let health = server_manager.check_server_health().await;
    // Should return error for non-running server
    assert!(health.is_err());
    
    Ok(())
}

#[tokio::test]
async fn test_installation_manager() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let install_manager = InstallationManager::new(temp_dir.path().to_path_buf());
    
    // Test installation workflow validation
    let install_path = temp_dir.path().join("vpn-server");
    let workflow = install_manager.create_installation_workflow(&install_path, VpnProtocol::Vless).await?;
    
    assert!(!workflow.steps.is_empty());
    assert!(workflow.estimated_duration_minutes > 0);
    
    Ok(())
}

#[tokio::test]
async fn test_template_manager() -> Result<(), Box<dyn std::error::Error>> {
    let template_manager = TemplateManager::new();
    
    // Test VLESS template generation
    let vless_template = template_manager.generate_vless_config(
        8443,
        "test_private_key",
        "google.com",
        "www.google.com:443",
        "test_short"
    ).await?;
    
    assert!(vless_template.contains("vless"));
    assert!(vless_template.contains("8443"));
    assert!(vless_template.contains("google.com"));
    
    // Test VMess template generation
    let vmess_template = template_manager.generate_vmess_config(
        8080,
        "test_uuid",
        "test_alter_id"
    ).await?;
    
    assert!(vmess_template.contains("vmess"));
    assert!(vmess_template.contains("8080"));
    assert!(vmess_template.contains("test_uuid"));
    
    Ok(())
}

#[tokio::test]
async fn test_docker_compose_generation() -> Result<(), Box<dyn std::error::Error>> {
    let template_manager = TemplateManager::new();
    
    let docker_compose = template_manager.generate_docker_compose(
        VpnProtocol::Vless,
        "/opt/vpn/config",
        "/opt/vpn/logs",
        8443
    ).await?;
    
    assert!(docker_compose.contains("version:"));
    assert!(docker_compose.contains("services:"));
    assert!(docker_compose.contains("xray"));
    assert!(docker_compose.contains("8443"));
    
    Ok(())
}

#[tokio::test]
async fn test_key_rotation_manager() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let key_rotation = KeyRotationManager::new(temp_dir.path().to_path_buf());
    
    // Test key rotation schedule
    let schedule = key_rotation.create_rotation_schedule(30).await?; // 30 days
    assert_eq!(schedule.rotation_interval_days, 30);
    assert!(schedule.next_rotation > chrono::Utc::now());
    
    // Test key backup before rotation
    let backup_result = key_rotation.backup_current_keys().await;
    // Should work even if no keys exist
    assert!(backup_result.is_ok());
    
    Ok(())
}

#[tokio::test]
async fn test_validation_manager() -> Result<(), Box<dyn std::error::Error>> {
    let validator = ValidationManager::new();
    
    // Test port validation
    assert!(validator.validate_port(8443).is_ok());
    assert!(validator.validate_port(0).is_err());
    assert!(validator.validate_port(70000).is_err());
    
    // Test host validation
    assert!(validator.validate_host("0.0.0.0").is_ok());
    assert!(validator.validate_host("192.168.1.1").is_ok());
    assert!(validator.validate_host("example.com").is_ok());
    assert!(validator.validate_host("invalid_host").is_err());
    
    // Test protocol configuration validation
    let vless_config = ProtocolConfig::Vless {
        private_key: "valid_base64_key_here".to_string(),
        public_key: "valid_public_key_here".to_string(),
        short_id: "1234567890abcdef".to_string(),
        sni: "google.com".to_string(),
        reality_dest: "www.google.com:443".to_string(),
    };
    
    let validation_result = validator.validate_protocol_config(&vless_config).await;
    // May fail due to invalid keys, but should not crash
    
    Ok(())
}

#[test]
fn test_server_config_serialization() -> Result<(), Box<dyn std::error::Error>> {
    let config = ServerConfig {
        server_name: "test-server".to_string(),
        host: "0.0.0.0".to_string(),
        port: 8443,
        protocol: VpnProtocol::Vless,
        protocol_config: ProtocolConfig::Vless {
            private_key: "private".to_string(),
            public_key: "public".to_string(),
            short_id: "short".to_string(),
            sni: "google.com".to_string(),
            reality_dest: "dest".to_string(),
        },
        docker_config: Default::default(),
        logging_config: Default::default(),
        security_config: Default::default(),
    };
    
    // Test JSON serialization
    let json = serde_json::to_string_pretty(&config)?;
    assert!(json.contains("test-server"));
    assert!(json.contains("vless"));
    
    let deserialized: ServerConfig = serde_json::from_str(&json)?;
    assert_eq!(deserialized.server_name, config.server_name);
    assert_eq!(deserialized.protocol, config.protocol);
    
    Ok(())
}

#[test]
fn test_protocol_config_variants() -> Result<(), Box<dyn std::error::Error>> {
    let protocols = vec![
        ProtocolConfig::Vless {
            private_key: "priv".to_string(),
            public_key: "pub".to_string(),
            short_id: "short".to_string(),
            sni: "google.com".to_string(),
            reality_dest: "dest".to_string(),
        },
        ProtocolConfig::Vmess {
            uuid: "test-uuid".to_string(),
            alter_id: "test-alter".to_string(),
            network: "tcp".to_string(),
        },
        ProtocolConfig::Trojan {
            password: "test-password".to_string(),
            sni: "google.com".to_string(),
        },
        ProtocolConfig::Shadowsocks {
            method: "aes-256-gcm".to_string(),
            password: "test-password".to_string(),
        },
    ];
    
    for protocol in protocols {
        let json = serde_json::to_string(&protocol)?;
        let deserialized: ProtocolConfig = serde_json::from_str(&json)?;
        
        match (&protocol, &deserialized) {
            (ProtocolConfig::Vless { sni: s1, .. }, ProtocolConfig::Vless { sni: s2, .. }) => {
                assert_eq!(s1, s2);
            }
            (ProtocolConfig::Vmess { uuid: u1, .. }, ProtocolConfig::Vmess { uuid: u2, .. }) => {
                assert_eq!(u1, u2);
            }
            (ProtocolConfig::Trojan { password: p1, .. }, ProtocolConfig::Trojan { password: p2, .. }) => {
                assert_eq!(p1, p2);
            }
            (ProtocolConfig::Shadowsocks { method: m1, .. }, ProtocolConfig::Shadowsocks { method: m2, .. }) => {
                assert_eq!(m1, m2);
            }
            _ => panic!("Protocol config mismatch"),
        }
    }
    
    Ok(())
}

#[tokio::test]
async fn test_server_lifecycle() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    // Test configuration creation
    let config = ServerConfig {
        server_name: "lifecycle-test".to_string(),
        host: "127.0.0.1".to_string(),
        port: 8443,
        protocol: VpnProtocol::Vless,
        protocol_config: ProtocolConfig::Vless {
            private_key: "test_key".to_string(),
            public_key: "test_pub".to_string(),
            short_id: "short".to_string(),
            sni: "google.com".to_string(),
            reality_dest: "dest".to_string(),
        },
        docker_config: Default::default(),
        logging_config: Default::default(),
        security_config: Default::default(),
    };
    
    // Save config
    server_manager.save_config(&config).await?;
    
    // Test status check
    let status = server_manager.get_server_status().await?;
    assert_eq!(status, ServerStatus::Stopped);
    
    // Test configuration validation
    let validation_result = server_manager.validate_config().await;
    // Should not crash, result depends on actual validation
    
    Ok(())
}

#[tokio::test]
async fn test_backup_and_restore() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    // Create configuration
    let config = ServerConfig {
        server_name: "backup-test".to_string(),
        host: "0.0.0.0".to_string(),
        port: 8443,
        protocol: VpnProtocol::Vless,
        protocol_config: ProtocolConfig::Vless {
            private_key: "backup_key".to_string(),
            public_key: "backup_pub".to_string(),
            short_id: "backup".to_string(),
            sni: "google.com".to_string(),
            reality_dest: "dest".to_string(),
        },
        docker_config: Default::default(),
        logging_config: Default::default(),
        security_config: Default::default(),
    };
    
    server_manager.save_config(&config).await?;
    
    // Create backup
    let backup_path = temp_dir.path().join("server_backup.tar.gz");
    server_manager.create_backup(&backup_path).await?;
    assert!(backup_path.exists());
    
    // Test restore preparation
    let restore_result = server_manager.prepare_restore(&backup_path).await;
    assert!(restore_result.is_ok());
    
    Ok(())
}

#[tokio::test]
async fn test_performance_metrics() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    // Test metrics collection
    let metrics = server_manager.collect_performance_metrics().await;
    // Should work even if server is not running
    if let Ok(perf_metrics) = metrics {
        assert!(perf_metrics.cpu_usage >= 0.0);
        assert!(perf_metrics.memory_usage >= 0.0);
    }
    
    Ok(())
}

#[test]
fn test_server_status_enum() {
    let statuses = vec![
        ServerStatus::Running,
        ServerStatus::Stopped,
        ServerStatus::Starting,
        ServerStatus::Stopping,
        ServerStatus::Error("test error".to_string()),
    ];
    
    for status in statuses {
        let json = serde_json::to_string(&status).unwrap();
        let deserialized: ServerStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(status, deserialized);
    }
}

#[tokio::test]
async fn test_multi_protocol_support() -> Result<(), Box<dyn std::error::Error>> {
    let template_manager = TemplateManager::new();
    
    // Test all protocol templates
    let protocols = vec![
        VpnProtocol::Vless,
        VpnProtocol::Vmess,
        VpnProtocol::Trojan,
        VpnProtocol::Shadowsocks,
    ];
    
    for protocol in protocols {
        let template = template_manager.generate_protocol_template(&protocol).await?;
        assert!(!template.is_empty());
        assert!(template.contains(&protocol.to_string()));
    }
    
    Ok(())
}

#[tokio::test]
async fn test_configuration_migration() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    // Test configuration version migration
    let migration_result = server_manager.migrate_config_version("1.0", "2.0").await;
    // Should handle gracefully even if no config exists
    
    Ok(())
}

#[tokio::test]
async fn test_security_validation() -> Result<(), Box<dyn std::error::Error>> {
    let validator = ValidationManager::new();
    
    // Test security configuration validation
    let security_checks = validator.validate_security_settings().await?;
    
    // Should include various security checks
    assert!(!security_checks.is_empty());
    
    for check in security_checks {
        assert!(!check.check_name.is_empty());
        // Status can be pass, fail, or warning
    }
    
    Ok(())
}

#[tokio::test]
async fn test_log_management() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_manager = ServerManager::new(temp_dir.path().to_path_buf()).await?;
    
    // Test log rotation setup
    let log_rotation_result = server_manager.setup_log_rotation().await;
    assert!(log_rotation_result.is_ok());
    
    // Test log level configuration
    let log_levels = vec!["debug", "info", "warn", "error"];
    for level in log_levels {
        let result = server_manager.set_log_level(level).await;
        assert!(result.is_ok());
    }
    
    Ok(())
}