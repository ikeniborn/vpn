//! Basic integration tests for vpn-users crate
//! Tests only the core functionality that is actually implemented

use tempfile::tempdir;
use uuid::Uuid;
use vpn_users::config::ServerConfig;
use vpn_users::{User, UserConfig, UserManager, UserStats, UserStatus, VpnProtocol};

#[tokio::test]
async fn test_user_manager_creation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Test basic functionality
    assert!(!user_manager.is_read_only());
    assert_eq!(user_manager.get_user_count().await, 0);

    Ok(())
}

#[tokio::test]
async fn test_user_creation_and_retrieval() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create a user
    let user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;
    assert_eq!(user.name, "testuser");
    assert_eq!(user.protocol, VpnProtocol::Vless);
    assert_eq!(user.status, UserStatus::Active);

    // Retrieve user by ID
    let retrieved_user = user_manager.get_user(&user.id).await?;
    assert_eq!(retrieved_user.id, user.id);
    assert_eq!(retrieved_user.name, user.name);

    // Retrieve user by name
    let user_by_name = user_manager.get_user_by_name("testuser").await?;
    assert_eq!(user_by_name.id, user.id);

    Ok(())
}

#[tokio::test]
async fn test_user_listing() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create multiple users
    let _user1 = user_manager
        .create_user("user1".to_string(), VpnProtocol::Vless)
        .await?;
    let _user2 = user_manager
        .create_user("user2".to_string(), VpnProtocol::Outline)
        .await?;
    let _user3 = user_manager
        .create_user("user3".to_string(), VpnProtocol::Wireguard)
        .await?;

    // List all users
    let users = user_manager.list_users(None).await?;
    assert_eq!(users.len(), 3);
    assert_eq!(user_manager.get_user_count().await, 3);
    assert_eq!(user_manager.get_active_user_count().await, 3);

    Ok(())
}

#[tokio::test]
async fn test_user_update() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create and update user
    let mut user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;
    let user_id = user.id.clone();
    user.email = Some("test@example.com".to_string());
    user.status = UserStatus::Suspended;

    user_manager.update_user(user).await?;

    // Verify update
    let updated_user = user_manager.get_user(&user_id).await?;
    assert_eq!(updated_user.email, Some("test@example.com".to_string()));
    assert_eq!(updated_user.status, UserStatus::Suspended);

    Ok(())
}

#[tokio::test]
async fn test_user_deletion() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create user
    let user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;
    assert_eq!(user_manager.get_user_count().await, 1);

    // Delete user
    user_manager.delete_user(&user.id).await?;
    assert_eq!(user_manager.get_user_count().await, 0);

    // Verify user is gone
    let result = user_manager.get_user(&user.id).await;
    assert!(result.is_err());

    Ok(())
}

#[tokio::test]
async fn test_connection_link_generation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create user
    let user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;

    // Generate connection link
    let link = user_manager.generate_connection_link(&user.id).await?;
    assert!(!link.is_empty());
    assert!(link.starts_with("vless://") || link.starts_with("http://"));

    Ok(())
}

#[test]
fn test_user_struct_serialization() -> Result<(), Box<dyn std::error::Error>> {
    let user = User {
        id: Uuid::new_v4().to_string(),
        short_id: "short".to_string(),
        name: "testuser".to_string(),
        email: Some("test@example.com".to_string()),
        created_at: chrono::Utc::now(),
        last_active: None,
        status: UserStatus::Active,
        protocol: VpnProtocol::Vless,
        config: UserConfig {
            public_key: Some("pubkey".to_string()),
            private_key: Some("key".to_string()),
            server_host: "example.com".to_string(),
            server_port: 443,
            sni: Some("google.com".to_string()),
            path: Some("/path".to_string()),
            security: "reality".to_string(),
            network: "tcp".to_string(),
            header_type: Some("none".to_string()),
            flow: Some("xtls-rprx-vision".to_string()),
        },
        stats: UserStats {
            bytes_sent: 0,
            bytes_received: 0,
            connection_count: 0,
            last_connection: None,
            total_uptime: 0,
        },
    };

    // Test JSON serialization
    let json = serde_json::to_string_pretty(&user)?;
    assert!(json.contains("testuser"));
    assert!(json.contains("vless"));

    let deserialized: User = serde_json::from_str(&json)?;
    assert_eq!(deserialized.name, user.name);
    assert_eq!(deserialized.protocol, user.protocol);

    Ok(())
}

#[test]
fn test_vpn_protocol_conversion() {
    // Test protocol string conversion
    assert_eq!(VpnProtocol::Vless.to_string(), "VLESS");
    assert_eq!(VpnProtocol::Wireguard.to_string(), "WireGuard");
    assert_eq!(VpnProtocol::OpenVPN.to_string(), "OpenVPN");
    assert_eq!(VpnProtocol::Outline.to_string(), "Outline");

    // Test protocol from string
    assert_eq!("vless".parse::<VpnProtocol>().unwrap(), VpnProtocol::Vless);
    assert_eq!(
        "wireguard".parse::<VpnProtocol>().unwrap(),
        VpnProtocol::Wireguard
    );
    assert_eq!(
        "openvpn".parse::<VpnProtocol>().unwrap(),
        VpnProtocol::OpenVPN
    );
    assert_eq!(
        "shadowsocks".parse::<VpnProtocol>().unwrap(),
        VpnProtocol::Outline
    );

    assert!("invalid".parse::<VpnProtocol>().is_err());
}
