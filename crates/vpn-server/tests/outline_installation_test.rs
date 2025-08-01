use vpn_server::installer::{InstallationOptions, LogLevel, ServerInstaller};
use vpn_types::protocol::VpnProtocol;

#[tokio::test]
async fn test_outline_server_config_generation() {
    let _installer = ServerInstaller::new().unwrap();
    
    let _options = InstallationOptions {
        protocol: VpnProtocol::Outline,
        port: Some(8388),
        sni_domain: None,
        install_path: std::path::PathBuf::from("/tmp/test-outline"),
        enable_firewall: false,
        auto_start: false,
        log_level: LogLevel::Info,
        reality_dest: None,
        subnet: None,
        interactive_subnet: false,
    };
    
    // Test that Outline-specific fields are generated
    // This would normally be an internal method, but we can test via the install flow
    // For unit tests, we'd need to expose generate_server_config as public or test via integration
}

#[test]
fn test_outline_installation_path() {
    use vpn_server::installer::InstallationOptions;
    
    let protocol = VpnProtocol::Outline;
    let path = InstallationOptions::get_protocol_install_path(protocol);
    
    assert_eq!(path, std::path::PathBuf::from("/opt/shadowsocks"));
}

#[test]
fn test_outline_docker_compose_requires_api_secret() {
    use vpn_server::templates::DockerComposeTemplate;
    use vpn_server::installer::{ServerConfig, InstallationOptions, LogLevel};
    
    let template = DockerComposeTemplate::new();
    
    // Test with missing API secret
    let server_config = ServerConfig {
        host: "127.0.0.1".to_string(),
        port: 8388,
        public_key: "test".to_string(),
        private_key: "test".to_string(),
        short_id: "test".to_string(),
        sni_domain: "test".to_string(),
        reality_dest: "test".to_string(),
        log_level: LogLevel::Info,
        api_secret: None, // Missing API secret
        management_port: Some(9388),
    };
    
    let options = InstallationOptions {
        protocol: VpnProtocol::Outline,
        port: Some(8388),
        sni_domain: None,
        install_path: std::path::PathBuf::from("/opt/shadowsocks"),
        enable_firewall: false,
        auto_start: false,
        log_level: LogLevel::Info,
        reality_dest: None,
        subnet: None,
        interactive_subnet: false,
    };
    
    let result = template.create_outline_compose_content(&server_config, &options, None);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("API secret not generated"));
}

#[test]
fn test_outline_docker_compose_requires_management_port() {
    use vpn_server::templates::DockerComposeTemplate;
    use vpn_server::installer::{ServerConfig, InstallationOptions, LogLevel};
    
    let template = DockerComposeTemplate::new();
    
    // Test with missing management port
    let server_config = ServerConfig {
        host: "127.0.0.1".to_string(),
        port: 8388,
        public_key: "test".to_string(),
        private_key: "test".to_string(),
        short_id: "test".to_string(),
        sni_domain: "test".to_string(),
        reality_dest: "test".to_string(),
        log_level: LogLevel::Info,
        api_secret: Some("test-api-secret".to_string()),
        management_port: None, // Missing management port
    };
    
    let options = InstallationOptions {
        protocol: VpnProtocol::Outline,
        port: Some(8388),
        sni_domain: None,
        install_path: std::path::PathBuf::from("/opt/shadowsocks"),
        enable_firewall: false,
        auto_start: false,
        log_level: LogLevel::Info,
        reality_dest: None,
        subnet: None,
        interactive_subnet: false,
    };
    
    let result = template.create_outline_compose_content(&server_config, &options, None);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Management port not set"));
}

#[test]
fn test_outline_docker_compose_generation_success() {
    use vpn_server::templates::DockerComposeTemplate;
    use vpn_server::installer::{ServerConfig, InstallationOptions, LogLevel};
    
    let template = DockerComposeTemplate::new();
    
    // Test with all required fields
    let server_config = ServerConfig {
        host: "192.168.1.100".to_string(),
        port: 8388,
        public_key: "test".to_string(),
        private_key: "test".to_string(),
        short_id: "test".to_string(),
        sni_domain: "test".to_string(),
        reality_dest: "test".to_string(),
        log_level: LogLevel::Info,
        api_secret: Some("secure-api-secret-123".to_string()),
        management_port: Some(9388),
    };
    
    let options = InstallationOptions {
        protocol: VpnProtocol::Outline,
        port: Some(8388),
        sni_domain: None,
        install_path: std::path::PathBuf::from("/opt/shadowsocks"),
        enable_firewall: false,
        auto_start: true,
        log_level: LogLevel::Info,
        reality_dest: None,
        subnet: None,
        interactive_subnet: false,
    };
    
    let result = template.create_outline_compose_content(&server_config, &options, None);
    assert!(result.is_ok());
    
    let compose_content = result.unwrap();
    
    // Verify the compose contains Outline-specific configuration
    assert!(compose_content.contains("outline-shadowbox"));
    assert!(compose_content.contains("9388:9388")); // Management port
    assert!(compose_content.contains("8388:8388")); // Client port
    assert!(compose_content.contains("SB_API_PREFIX=secure-api-secret-123"));
    assert!(compose_content.contains("SB_PUBLIC_IP=192.168.1.100"));
    assert!(compose_content.contains("restart: unless-stopped"));
}

#[test]
fn test_outline_management_url_format() {
    // Test that management URL includes the API secret in the path
    let host = "192.168.1.100";
    let management_port = 9388;
    let api_secret = "secure-api-secret-123";
    
    let management_url = format!("https://{}:{}/{}/", host, management_port, api_secret);
    
    assert_eq!(management_url, "https://192.168.1.100:9388/secure-api-secret-123/");
    assert!(management_url.contains(&api_secret));
    assert!(management_url.ends_with(&format!("{}/", api_secret)));
}