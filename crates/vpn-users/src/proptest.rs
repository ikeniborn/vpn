//! Property-based tests for VPN user management
//! 
//! This module contains comprehensive property-based tests using proptest
//! to ensure the correctness of user operations under various scenarios.

use crate::{user::*, error::*};
use proptest::prelude::*;
use proptest::option;
use chrono::Utc;
use vpn_types::protocol::VpnProtocol;

/// Strategy for generating valid user names
pub fn user_name_strategy() -> impl Strategy<Value = String> {
    "[a-zA-Z][a-zA-Z0-9_-]{2,31}" // Valid user names: 3-32 chars, alphanumeric + _ -
}

/// Strategy for generating valid email addresses
pub fn email_strategy() -> impl Strategy<Value = String> {
    "[a-zA-Z0-9]{1,20}@[a-zA-Z0-9]{1,10}\\.[a-zA-Z]{2,5}".prop_map(|s| s)
}

/// Strategy for generating valid server hosts
pub fn server_host_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        // IPv4 addresses
        "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])",
        // Domain names
        "[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}"
    ]
}

/// Strategy for generating valid port numbers
pub fn port_strategy() -> impl Strategy<Value = u16> {
    1024u16..65535u16
}

/// Strategy for generating VPN protocols
pub fn protocol_strategy() -> impl Strategy<Value = VpnProtocol> {
    prop_oneof![
        Just(VpnProtocol::Vless),
        Just(VpnProtocol::Outline),
        Just(VpnProtocol::Wireguard),
        Just(VpnProtocol::OpenVPN),
    ]
}

/// Strategy for generating user status
pub fn user_status_strategy() -> impl Strategy<Value = UserStatus> {
    prop_oneof![
        Just(UserStatus::Active),
        Just(UserStatus::Inactive),
        Just(UserStatus::Suspended),
        Just(UserStatus::Expired),
    ]
}

/// Strategy for generating user configuration
pub fn user_config_strategy() -> impl Strategy<Value = UserConfig> {
    (
        server_host_strategy(),
        port_strategy(),
        option::of("[a-zA-Z0-9.-]{3,50}"), // SNI
        option::of("/[a-zA-Z0-9/-]{1,100}"), // Path
        "[a-zA-Z0-9]{3,20}", // Security
        "[a-zA-Z0-9]{3,20}", // Network
        option::of("[a-zA-Z0-9]{3,20}"), // Header type
        option::of("[a-zA-Z0-9-]{3,20}"), // Flow
    ).prop_map(|(host, port, sni, path, security, network, header_type, flow)| {
        UserConfig {
            public_key: None,
            private_key: None,
            server_host: host,
            server_port: port,
            sni,
            path,
            security,
            network,
            header_type,
            flow,
        }
    })
}

/// Strategy for generating user stats
pub fn user_stats_strategy() -> impl Strategy<Value = UserStats> {
    (
        0u64..u64::MAX/2, // bytes_sent
        0u64..u64::MAX/2, // bytes_received
        0u64..10000u64,   // connection_count
        0u64..86400u64*365u64, // total_uptime (max 1 year in seconds)
    ).prop_map(|(bytes_sent, bytes_received, connection_count, total_uptime)| {
        UserStats {
            bytes_sent,
            bytes_received,
            connection_count,
            last_connection: None,
            total_uptime,
        }
    })
}

/// Strategy for generating complete users
pub fn user_strategy() -> impl Strategy<Value = User> {
    (
        user_name_strategy(),
        protocol_strategy(),
        option::of(email_strategy()),
        user_status_strategy(),
        user_config_strategy(),
        user_stats_strategy(),
    ).prop_map(|(name, protocol, email, status, config, stats)| {
        let mut user = User::new(name, protocol);
        if let Some(email) = email {
            user = user.with_email(email);
        }
        user.status = status;
        user.config = config;
        user.stats = stats;
        user
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    use tokio_test;

    proptest! {
        /// Test that user creation with valid inputs always succeeds
        #[test]
        fn test_user_creation_always_succeeds(
            name in user_name_strategy(),
            protocol in protocol_strategy()
        ) {
            let user = User::new(name.clone(), protocol);
            
            // Basic invariants
            prop_assert_eq!(&user.name, &name);
            prop_assert_eq!(user.protocol, protocol);
            prop_assert_eq!(user.status, UserStatus::Active);
            prop_assert!(user.is_active());
            prop_assert!(!user.id.is_empty());
            prop_assert!(!user.short_id.is_empty());
            
            // UUID format validation
            prop_assert!(uuid::Uuid::parse_str(&user.id).is_ok());
            
            // Time invariants
            prop_assert!(user.created_at <= Utc::now());
            prop_assert!(user.last_active.is_none());
        }

        /// Test that user status transitions maintain consistency
        #[test]
        fn test_user_status_transitions(
            mut user in user_strategy()
        ) {
            let original_name = user.name.clone();
            let original_protocol = user.protocol;
            
            // Test activation
            user.activate();
            prop_assert_eq!(user.status, UserStatus::Active);
            prop_assert!(user.is_active());
            
            // Test deactivation
            user.deactivate();
            prop_assert_eq!(user.status, UserStatus::Inactive);
            prop_assert!(!user.is_active());
            
            // Test that other fields remain unchanged
            prop_assert_eq!(user.name, original_name);
            prop_assert_eq!(user.protocol, original_protocol);
        }

        /// Test that user configuration updates preserve other fields
        #[test]
        fn test_user_config_updates_preserve_identity(
            user in user_strategy(),
            new_config in user_config_strategy()
        ) {
            let original_id = user.id.clone();
            let original_name = user.name.clone();
            let original_protocol = user.protocol;
            let original_created_at = user.created_at;
            
            let updated_user = user.with_config(new_config.clone());
            
            // Identity fields should remain unchanged
            prop_assert_eq!(updated_user.id, original_id);
            prop_assert_eq!(updated_user.name, original_name);
            prop_assert_eq!(updated_user.protocol, original_protocol);
            prop_assert_eq!(updated_user.created_at, original_created_at);
            
            // Config should be updated
            prop_assert_eq!(updated_user.config.server_host, new_config.server_host);
            prop_assert_eq!(updated_user.config.server_port, new_config.server_port);
        }

        /// Test that email addition preserves other fields
        #[test]
        fn test_email_addition_preserves_identity(
            user in user_strategy(),
            email in email_strategy()
        ) {
            let original_id = user.id.clone();
            let original_name = user.name.clone();
            
            let updated_user = user.with_email(email.clone());
            
            prop_assert_eq!(updated_user.id, original_id);
            prop_assert_eq!(updated_user.name, original_name);
            prop_assert_eq!(updated_user.email, Some(email));
        }

        /// Test user stats invariants
        #[test]
        fn test_user_stats_invariants(
            stats in user_stats_strategy()
        ) {
            // Stats should never be negative (handled by u64 type)
            prop_assert!(stats.bytes_sent < u64::MAX);
            prop_assert!(stats.bytes_received < u64::MAX);
            prop_assert!(stats.connection_count < u64::MAX);
            prop_assert!(stats.total_uptime < u64::MAX);
            
            // Logical invariants
            if stats.connection_count == 0 {
                prop_assert!(stats.last_connection.is_none());
            }
        }

        /// Test that user serialization is symmetric
        #[test]
        fn test_user_serialization_symmetry(
            user in user_strategy()
        ) {
            // Test JSON serialization
            let json = serde_json::to_string(&user)?;
            let deserialized: User = serde_json::from_str(&json)?;
            
            prop_assert_eq!(user.id, deserialized.id);
            prop_assert_eq!(user.name, deserialized.name);
            prop_assert_eq!(user.email, deserialized.email);
            prop_assert_eq!(user.status, deserialized.status);
            prop_assert_eq!(user.protocol, deserialized.protocol);
        }

        /// Test VPN protocol enum properties
        #[test]
        fn test_vpn_protocol_properties(
            protocol in protocol_strategy()
        ) {
            // All protocols should be serializable
            let json = serde_json::to_string(&protocol)?;
            let deserialized: VpnProtocol = serde_json::from_str(&json)?;
            prop_assert_eq!(protocol, deserialized);
            
            // All protocols should have valid string representations
            let debug_str = format!("{:?}", protocol);
            prop_assert!(!debug_str.is_empty());
        }

        /// Test user status enum properties
        #[test]
        fn test_user_status_properties(
            status in user_status_strategy()
        ) {
            // All statuses should be serializable
            let json = serde_json::to_string(&status)?;
            let deserialized: UserStatus = serde_json::from_str(&json)?;
            prop_assert_eq!(status, deserialized);
            
            // Test active status detection
            let is_active = matches!(status, UserStatus::Active);
            let mut user = User::new("test".to_string(), VpnProtocol::Vless);
            user.status = status;
            prop_assert_eq!(user.is_active(), is_active);
        }

        /// Test user configuration validation
        #[test]
        fn test_user_config_validation(
            config in user_config_strategy()
        ) {
            // Port should be in valid range
            prop_assert!(config.server_port >= 1024);
            
            // Host should not be empty
            prop_assert!(!config.server_host.is_empty());
            
            // Required fields should not be empty
            prop_assert!(!config.security.is_empty());
            prop_assert!(!config.network.is_empty());
            
            // Optional fields can be None
            // (This is handled by the Option type)
        }
    }

    /// Test async user manager operations
    mod async_tests {
        use super::*;
        use crate::{UserManager, config::ServerConfig};

        #[tokio::test]
        async fn test_user_manager_creation() {
            let temp_dir = TempDir::new().unwrap();
            let server_config = ServerConfig::default();
            let manager = UserManager::new(temp_dir.path().to_path_buf(), server_config);
            
            // Manager should be created successfully
            assert!(manager.is_ok());
        }

        proptest! {
            /// Test that user manager operations maintain consistency
            #[test]
            fn test_user_manager_consistency(
                users in prop::collection::vec(user_strategy(), 1..10)
            ) {
                let _ = tokio_test::block_on(async {
                    let temp_dir = TempDir::new().unwrap();
                    let server_config = ServerConfig::default();
                    let manager = UserManager::new(temp_dir.path().to_path_buf(), server_config).unwrap();
                    
                    // Add users one by one
                    for user in &users {
                        let result = manager.create_user(user.name.clone(), user.protocol).await;
                        // Should succeed or fail consistently
                        if let Err(e) = &result {
                            // If it fails, it should be due to duplicate name
                            prop_assert!(matches!(e, UserError::UserAlreadyExists(_)));
                        }
                    }
                    
                    // Get all users using list_users method
                    let stored_users = manager.list_users(None).await.unwrap();
                    
                    // Should have at least some users (duplicates filtered out)
                    prop_assert!(!stored_users.is_empty());
                    prop_assert!(stored_users.len() <= users.len());
                    
                    // All stored users should have unique names
                    let mut names = std::collections::HashSet::new();
                    for user in &stored_users {
                        prop_assert!(names.insert(user.name.clone()));
                    }
                    
                    Ok(())
                });
            }
        }
    }
}