use std::collections::HashMap;
use tempfile::tempdir;
use uuid::Uuid;
use vpn_users::config::ServerConfig;
use vpn_users::{
    ConnectionLinkGenerator, User, UserConfig, UserManager, UserStats, UserStatus, VpnProtocol,
};

#[tokio::test]
async fn test_user_manager_creation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    assert_eq!(user_manager.get_users_directory(), temp_dir.path());

    Ok(())
}

#[tokio::test]
async fn test_user_creation_and_retrieval() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create a new user
    let user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;

    assert_eq!(user.name, "testuser");
    assert_eq!(user.protocol, VpnProtocol::Vless);
    assert_eq!(user.status, UserStatus::Active);
    assert!(Uuid::parse_str(&user.id).is_ok());

    // Retrieve the user
    let retrieved_user = user_manager.get_user(&user.id).await?;
    assert_eq!(retrieved_user.name, user.name);
    assert_eq!(retrieved_user.id, user.id);

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
        .create_user("user2".to_string(), VpnProtocol::Vless)
        .await?;
    let _user3 = user_manager
        .create_user("user3".to_string(), VpnProtocol::Vless)
        .await?;

    // List all users
    let users = user_manager.list_users(None).await?;
    assert_eq!(users.len(), 3);

    let user_names: Vec<&str> = users.iter().map(|u| u.name.as_str()).collect();
    assert!(user_names.contains(&"user1"));
    assert!(user_names.contains(&"user2"));
    assert!(user_names.contains(&"user3"));

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

    // Create and delete user
    let user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;
    let user_id = user.id.clone();

    user_manager.delete_user(&user_id).await?;

    // Verify deletion
    assert!(user_manager.get_user(&user_id).await.is_err());

    let users = user_manager.list_users(None).await?;
    assert!(users.is_empty());

    Ok(())
}

#[test]
fn test_user_configuration() -> Result<(), Box<dyn std::error::Error>> {
    let config = UserConfig {
        server_host: "example.com".to_string(),
        server_port: 443,
        private_key: Some("private_key_data".to_string()),
        public_key: Some("public_key_data".to_string()),
        short_id: Some("short123".to_string()),
        sni: Some("google.com".to_string()),
        reality_dest: Some("www.google.com:443".to_string()),
        additional_settings: HashMap::new(),
    };

    assert_eq!(config.server_host, "example.com");
    assert_eq!(config.server_port, 443);
    assert_eq!(config.private_key, Some("private_key_data".to_string()));

    Ok(())
}

#[tokio::test]
async fn test_connection_link_generation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;
    let link_generator = ConnectionLinkGenerator::new();

    let user = user_manager
        .create_user("testuser".to_string(), VpnProtocol::Vless)
        .await?;

    // Generate VLESS link
    let vless_link = link_generator.generate_vless_link(&user).await?;
    assert!(vless_link.starts_with("vless://"));
    assert!(vless_link.contains(&user.id));

    // Generate VMess link
    let mut vmess_user = user.clone();
    vmess_user.protocol = VpnProtocol::Vmess;
    let vmess_link = link_generator.generate_vmess_link(&vmess_user).await?;
    assert!(vmess_link.starts_with("vmess://"));

    Ok(())
}

#[tokio::test]
async fn test_batch_user_operations() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;
    let batch_ops = BatchUserOperations::new(user_manager);

    // Create multiple users at once
    let user_specs = vec![
        ("user1", VpnProtocol::Vless),
        ("user2", VpnProtocol::Vmess),
        ("user3", VpnProtocol::Trojan),
    ];

    let created_users = batch_ops.create_multiple_users(&user_specs).await?;
    assert_eq!(created_users.len(), 3);

    // Update multiple users
    let user_ids: Vec<String> = created_users.iter().map(|u| u.id.clone()).collect();
    let update_result = batch_ops
        .update_user_status(&user_ids, UserStatus::Suspended)
        .await?;
    assert_eq!(update_result.successful, 3);
    assert_eq!(update_result.failed, 0);

    Ok(())
}

#[tokio::test]
async fn test_user_search_and_filtering() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create users with different attributes
    let mut user1 = user_manager
        .create_user("alice".to_string(), VpnProtocol::Vless)
        .await?;
    user1.email = Some("alice@company.com".to_string());
    user_manager.update_user(&user1).await?;

    let mut user2 = user_manager
        .create_user("bob".to_string(), VpnProtocol::Vless)
        .await?;
    user2.email = Some("bob@personal.com".to_string());
    user2.status = UserStatus::Suspended;
    user_manager.update_user(&user2).await?;

    let user3 = user_manager
        .create_user("charlie".to_string(), VpnProtocol::Vless)
        .await?;

    // Test search by name
    let search_results = user_manager.search_users_by_name("alice").await?;
    assert_eq!(search_results.len(), 1);
    assert_eq!(search_results[0].name, "alice");

    // Test filter by protocol
    let vless_users = user_manager
        .filter_users_by_protocol(VpnProtocol::Vless)
        .await?;
    assert_eq!(vless_users.len(), 1);
    assert_eq!(vless_users[0].protocol, VpnProtocol::Vless);

    // Test filter by status
    let suspended_users = user_manager
        .filter_users_by_status(UserStatus::Suspended)
        .await?;
    assert_eq!(suspended_users.len(), 1);
    assert_eq!(suspended_users[0].status, UserStatus::Suspended);

    Ok(())
}

#[tokio::test]
async fn test_user_statistics() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create users with different protocols and statuses
    let _user1 = user_manager
        .create_user("user1".to_string(), VpnProtocol::Vless)
        .await?;
    let mut user2 = user_manager
        .create_user("user2".to_string(), VpnProtocol::Vless)
        .await?;
    user2.status = UserStatus::Suspended;
    user_manager.update_user(user2).await?;
    let _user3 = user_manager
        .create_user("user3".to_string(), VpnProtocol::Outline)
        .await?;

    // Get user statistics
    let stats = user_manager.get_user_statistics().await?;
    assert_eq!(stats.total_users, 3);
    assert_eq!(stats.active_users, 2);
    assert_eq!(stats.suspended_users, 1);
    assert_eq!(stats.users_by_protocol.get(&VpnProtocol::Vless), Some(&2));
    assert_eq!(stats.users_by_protocol.get(&VpnProtocol::Outline), Some(&1));

    Ok(())
}

#[tokio::test]
async fn test_user_backup_and_restore() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Create users
    let user1 = user_manager
        .create_user("user1".to_string(), VpnProtocol::Vless)
        .await?;
    let user2 = user_manager
        .create_user("user2".to_string(), VpnProtocol::Vless)
        .await?;

    // Create backup
    let backup_path = temp_dir.path().join("backup.json");
    user_manager.backup_users(&backup_path).await?;
    assert!(backup_path.exists());

    // Clear users
    user_manager.delete_user(&user1.id).await?;
    user_manager.delete_user(&user2.id).await?;

    let users_before_restore = user_manager.list_users(None).await?;
    assert!(users_before_restore.is_empty());

    // Restore users
    user_manager.restore_users(&backup_path).await?;

    let users_after_restore = user_manager.list_users(None).await?;
    assert_eq!(users_after_restore.len(), 2);

    Ok(())
}

#[test]
fn test_user_serialization() -> Result<(), Box<dyn std::error::Error>> {
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

#[test]
fn test_user_status_transitions() {
    let statuses = vec![
        UserStatus::Active,
        UserStatus::Suspended,
        UserStatus::Expired,
        UserStatus::Inactive,
    ];

    for status in &statuses {
        let json = serde_json::to_string(status).unwrap();
        let deserialized: UserStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(*status, deserialized);
    }
}

#[tokio::test]
async fn test_concurrent_user_operations() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    use std::sync::Arc;
    use tokio::task;

    let manager = Arc::new(user_manager);
    let mut handles = vec![];

    // Create users concurrently
    for i in 0..10 {
        let manager_clone = Arc::clone(&manager);
        let handle = task::spawn(async move {
            manager_clone
                .create_user(format!("user{}", i), VpnProtocol::Vless)
                .await
        });
        handles.push(handle);
    }

    let mut created_users = vec![];
    for handle in handles {
        let user = handle.await??;
        created_users.push(user);
    }

    assert_eq!(created_users.len(), 10);

    // Verify all users were created with unique IDs
    let mut user_ids = std::collections::HashSet::new();
    for user in &created_users {
        assert!(user_ids.insert(user.id.clone()));
    }

    Ok(())
}

#[tokio::test]
async fn test_user_validation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let server_config = ServerConfig::default();
    let user_manager = UserManager::new(temp_dir.path().to_path_buf(), server_config)?;

    // Test valid user creation
    let valid_user = user_manager
        .create_user("validuser123".to_string(), VpnProtocol::Vless)
        .await;
    assert!(valid_user.is_ok());

    // Test invalid username (empty)
    let invalid_empty = user_manager
        .create_user("".to_string(), VpnProtocol::Vless)
        .await;
    assert!(invalid_empty.is_err());

    // Test invalid username (too long)
    let long_name = "a".repeat(100);
    let invalid_long = user_manager
        .create_user(long_name, VpnProtocol::Vless)
        .await;
    assert!(invalid_long.is_err());

    // Test duplicate username
    let _first_user = user_manager
        .create_user("duplicate".to_string(), VpnProtocol::Vless)
        .await?;
    let duplicate_result = user_manager
        .create_user("duplicate".to_string(), VpnProtocol::Vless)
        .await;
    assert!(duplicate_result.is_err());

    Ok(())
}
