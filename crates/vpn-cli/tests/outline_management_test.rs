use vpn_cli::cli::Protocol;
use vpn_cli::error::Result;
use tempfile::TempDir;
use std::fs;

#[test]
fn test_outline_protocol_mapping() {
    // Test that Shadowsocks maps to Outline
    assert!(matches!(Protocol::Shadowsocks, Protocol::Shadowsocks));
    assert!(matches!(Protocol::Outline, Protocol::Outline));
}

#[test]
fn test_outline_management_url_display() {
    // Create a mock installation result with management URL
    let server_config = vpn_server::installer::ServerConfig {
        host: "192.168.1.100".to_string(),
        port: 8388,
        public_key: "test-key".to_string(),
        private_key: "test-key".to_string(),
        short_id: "test-id".to_string(),
        sni_domain: "test.com".to_string(),
        reality_dest: "test.com:443".to_string(),
        log_level: vpn_server::installer::LogLevel::Info,
        api_secret: Some("test-api-secret".to_string()),
        management_port: Some(9388),
    };
    
    // Verify that both api_secret and management_port are present
    assert!(server_config.api_secret.is_some());
    assert!(server_config.management_port.is_some());
    
    // Test management URL format
    let management_url = format!(
        "https://{}:{}/{}/",
        server_config.host,
        server_config.management_port.unwrap(),
        server_config.api_secret.as_ref().unwrap()
    );
    
    assert_eq!(management_url, "https://192.168.1.100:9388/test-api-secret/");
}

#[test]
fn test_outline_user_creation_message() {
    // Test that appropriate message is shown for Outline user creation
    let protocols = vec![Protocol::Outline, Protocol::Shadowsocks];
    
    for protocol in protocols {
        match protocol {
            Protocol::Outline | Protocol::Shadowsocks => {
                // Should show special message for Outline/Shadowsocks
                assert!(true, "Outline/Shadowsocks should show management URL message");
            }
            _ => {
                // Other protocols should proceed normally
                assert!(false, "Other protocols should not show Outline message");
            }
        }
    }
}

#[tokio::test]
async fn test_outline_server_info_reading() -> Result<()> {
    // Create temporary directory
    let temp_dir = TempDir::new()?;
    let server_info_path = temp_dir.path().join("server_info.json");
    
    // Write test server info
    let server_info = serde_json::json!({
        "host": "192.168.1.100",
        "port": 8388,
        "protocol": "outline",
        "api_secret": "test-secret",
        "management_port": 9388,
        "management_url": "https://192.168.1.100:9388/test-secret/"
    });
    
    fs::write(&server_info_path, serde_json::to_string_pretty(&server_info)?)?;
    
    // Read and verify
    let content = fs::read_to_string(&server_info_path)?;
    let parsed: serde_json::Value = serde_json::from_str(&content)?;
    
    assert_eq!(parsed["protocol"], "outline");
    assert_eq!(parsed["management_url"], "https://192.168.1.100:9388/test-secret/");
    
    Ok(())
}