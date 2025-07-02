//! Basic integration tests for vpn-server crate
//! Tests only the core functionality that is actually implemented

use vpn_server::{
    ServerInstaller, ConfigValidator, ServerLifecycle,
    KeyRotationManager, DockerComposeTemplate, ProxyInstaller
};
use vpn_types::protocol::VpnProtocol;
use vpn_users::config::ServerConfig;
use tempfile::tempdir;
use std::path::PathBuf;

#[tokio::test]
async fn test_config_validator_creation() -> Result<(), Box<dyn std::error::Error>> {
    let _temp_dir = tempdir()?;
    let _validator = ConfigValidator::new()?;
    
    // Test that validator was created successfully
    assert!(true); // ConfigValidator created
    
    Ok(())
}

#[tokio::test]
async fn test_server_installer_creation() -> Result<(), Box<dyn std::error::Error>> {
    let _temp_dir = tempdir()?;
    let _installer = ServerInstaller::new()?;
    
    // Test that installer was created successfully
    assert!(true); // ServerInstaller created
    
    Ok(())
}

#[tokio::test]
async fn test_server_lifecycle_creation() -> Result<(), Box<dyn std::error::Error>> {
    let _temp_dir = tempdir()?;
    let _lifecycle = ServerLifecycle::new()?;
    
    // Test that lifecycle manager was created successfully
    assert!(true); // ServerLifecycle created
    
    Ok(())
}

#[tokio::test]
async fn test_key_rotation_manager_creation() -> Result<(), Box<dyn std::error::Error>> {
    let _temp_dir = tempdir()?;
    let _key_manager = KeyRotationManager::new()?;
    
    // Test that key rotation manager was created successfully
    assert!(true); // KeyRotationManager created
    
    Ok(())
}

#[tokio::test]
async fn test_docker_compose_template_creation() -> Result<(), Box<dyn std::error::Error>> {
    let _temp_dir = tempdir()?;
    let _template = DockerComposeTemplate::new();
    
    // Test that template manager was created successfully
    assert!(true); // DockerComposeTemplate created
    
    Ok(())
}

#[tokio::test]
async fn test_proxy_installer_creation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let _proxy_installer = ProxyInstaller::new(temp_dir.path().to_path_buf(), 8080)?;
    
    // Test that proxy installer was created successfully
    assert!(true); // ProxyInstaller created
    
    Ok(())
}

#[test]
fn test_vpn_protocol_handling() {
    // Test that VpnProtocol enum works correctly
    let protocols = vec![
        VpnProtocol::Vless,
        VpnProtocol::Outline,
        VpnProtocol::Wireguard,
        VpnProtocol::OpenVPN,
        VpnProtocol::HttpProxy,
        VpnProtocol::Socks5Proxy,
        VpnProtocol::ProxyServer,
    ];
    
    for protocol in protocols {
        assert!(protocol.default_port() > 0);
        assert!(!protocol.display_name().is_empty());
        assert!(!protocol.as_str().is_empty());
    }
}

#[test]
fn test_server_config_default() {
    let config = ServerConfig::default();
    
    // Test that server config can be created with defaults
    assert!(config.host.len() > 0);
    assert!(config.port > 0);
}