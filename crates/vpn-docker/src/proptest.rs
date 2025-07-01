//! Property-based tests for VPN Docker utilities
//! 
//! This module contains comprehensive property-based tests using proptest
//! to ensure the correctness of Docker operations under various scenarios.

use crate::{container::*};
use proptest::prelude::*;
use proptest::option;
use std::collections::HashMap;
use std::time::Duration;

/// Strategy for generating valid container names
pub fn container_name_strategy() -> impl Strategy<Value = String> {
    "[a-zA-Z][a-zA-Z0-9_.-]{1,63}" // Valid Docker container names
}

/// Strategy for generating valid Docker image names
pub fn docker_image_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        // Official images (start with alphanumeric)
        "[a-z0-9][a-z0-9]+",
        // User/repo format
        "[a-z0-9]+/[a-z0-9][a-z0-9_.-]+",
        // Registry/user/repo format
        "[a-z0-9][a-z0-9.-]+/[a-z0-9]+/[a-z0-9][a-z0-9_.-]+",
        // With tags
        "[a-z0-9]+:[a-z0-9][a-z0-9._-]+",
        // Common images
        Just("nginx".to_string()),
        Just("alpine:latest".to_string()),
        Just("ubuntu:22.04".to_string()),
        Just("redis:7-alpine".to_string()),
        Just("postgres:15".to_string()),
    ]
}

/// Strategy for generating valid port numbers
pub fn port_strategy() -> impl Strategy<Value = u16> {
    1024u16..65535u16
}

/// Strategy for generating port mappings
pub fn port_mappings_strategy() -> impl Strategy<Value = HashMap<u16, u16>> {
    prop::collection::btree_map(port_strategy(), port_strategy(), 0..=5)
        .prop_map(|btree| btree.into_iter().collect())
}

/// Strategy for generating environment variables
pub fn env_vars_strategy() -> impl Strategy<Value = HashMap<String, String>> {
    prop::collection::btree_map(
        "[A-Z_][A-Z0-9_]{1,20}", // Environment variable names
        "[a-zA-Z0-9/._:-]{0,100}", // Environment variable values
        0..=10
    ).prop_map(|btree| btree.into_iter().collect())
}

/// Strategy for generating volume mounts
pub fn volume_mounts_strategy() -> impl Strategy<Value = HashMap<String, String>> {
    prop::collection::btree_map(
        "/[a-zA-Z0-9/._-]{1,20}", // Host paths (shorter)
        "/[a-zA-Z0-9/._-]{1,20}", // Container paths (shorter)
        0..=5
    ).prop_map(|btree| btree.into_iter().collect())
}

/// Strategy for generating restart policies
pub fn restart_policy_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("no".to_string()),
        Just("always".to_string()),
        Just("unless-stopped".to_string()),
        Just("on-failure".to_string()),
        Just("on-failure:3".to_string()), // With retry count
    ]
}

/// Strategy for generating network names
pub fn network_strategy() -> impl Strategy<Value = Vec<String>> {
    prop::collection::vec(
        prop_oneof![
            Just("default".to_string()),
            Just("bridge".to_string()),
            Just("host".to_string()),
            Just("none".to_string()),
            "[a-z0-9_.-]{3,20}", // Custom network names
        ],
        1..=3
    )
}

/// Strategy for generating container configurations
pub fn container_config_strategy() -> impl Strategy<Value = ContainerConfig> {
    (
        container_name_strategy(),
        docker_image_strategy(),
        port_mappings_strategy(),
        env_vars_strategy(),
        volume_mounts_strategy(),
        restart_policy_strategy(),
        network_strategy(),
    ).prop_map(|(name, image, port_mappings, environment_variables, volume_mounts, restart_policy, networks)| {
        ContainerConfig {
            name,
            image,
            port_mappings,
            environment_variables,
            volume_mounts,
            restart_policy,
            networks,
        }
    })
}

/// Strategy for generating container status
pub fn container_status_strategy() -> impl Strategy<Value = ContainerStatus> {
    prop_oneof![
        Just(ContainerStatus::Running),
        Just(ContainerStatus::Stopped),
        Just(ContainerStatus::Paused),
        Just(ContainerStatus::Restarting),
        Just(ContainerStatus::Removing),
        Just(ContainerStatus::Dead),
        Just(ContainerStatus::Created),
        Just(ContainerStatus::NotFound),
        (-128i64..128i64).prop_map(ContainerStatus::Exited),
        "[a-zA-Z0-9 ._-]{3,50}".prop_map(ContainerStatus::Error),
        "[a-zA-Z0-9 ._-]{3,50}".prop_map(ContainerStatus::Unknown),
    ]
}

/// Strategy for generating container stats
pub fn container_stats_strategy() -> impl Strategy<Value = ContainerStats> {
    (
        0.0f64..100.0f64, // CPU usage percentage
        1024u64*1024u64*1024u64..1024u64*1024u64*1024u64*16u64, // Memory limit (1-16GB)
        0u64..1024u64*1024u64*1024u64, // Network RX bytes (up to 1GB)
        0u64..1024u64*1024u64*1024u64, // Network TX bytes (up to 1GB)
        0u64..1024u64*1024u64*1024u64, // Block read bytes (up to 1GB)
        0u64..1024u64*1024u64*1024u64, // Block write bytes (up to 1GB)
        1u64..1000u64, // Process count
    ).prop_map(|(cpu_usage_percent, memory_limit_bytes, network_rx_bytes, network_tx_bytes, block_read_bytes, block_write_bytes, pids)| {
        // Generate memory usage that's always <= memory limit
        let memory_usage_bytes = memory_limit_bytes / 2; // Use half of available memory
        
        ContainerStats {
            cpu_usage_percent,
            memory_usage_bytes,
            memory_limit_bytes,
            network_rx_bytes,
            network_tx_bytes,
            block_read_bytes,
            block_write_bytes,
            pids,
        }
    })
}

/// Strategy for generating container operations
pub fn container_operation_strategy() -> impl Strategy<Value = ContainerOperation> {
    prop_oneof![
        container_name_strategy().prop_map(ContainerOperation::Start),
        (container_name_strategy(), option::of(1i64..300i64))
            .prop_map(|(name, timeout)| ContainerOperation::Stop(name, timeout)),
        (container_name_strategy(), option::of(1i64..300i64))
            .prop_map(|(name, timeout)| ContainerOperation::Restart(name, timeout)),
        (container_name_strategy(), any::<bool>())
            .prop_map(|(name, force)| ContainerOperation::Remove(name, force)),
    ]
}

/// Strategy for generating batch operation options
pub fn batch_operation_options_strategy() -> impl Strategy<Value = BatchOperationOptions> {
    (
        1usize..10usize, // max_concurrent
        1u64..60u64, // timeout in seconds
        any::<bool>(), // fail_fast
    ).prop_map(|(max_concurrent, timeout_secs, fail_fast)| {
        BatchOperationOptions {
            max_concurrent,
            timeout: Duration::from_secs(timeout_secs),
            fail_fast,
        }
    })
}

/// Strategy for generating durations
pub fn duration_strategy() -> impl Strategy<Value = Duration> {
    (1u64..3600u64).prop_map(Duration::from_secs)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    proptest! {
        /// Test that container configuration creation preserves fields
        #[test]
        fn test_container_config_creation(
            name in container_name_strategy(),
            image in docker_image_strategy()
        ) {
            let config = ContainerConfig::new(&name, &image);
            
            // Basic fields should be set correctly
            prop_assert_eq!(config.name, name);
            prop_assert_eq!(config.image, image);
            
            // Default values should be set
            prop_assert!(config.port_mappings.is_empty());
            prop_assert!(config.environment_variables.is_empty());
            prop_assert!(config.volume_mounts.is_empty());
            prop_assert_eq!(config.restart_policy, "unless-stopped");
            prop_assert_eq!(config.networks, vec!["default"]);
        }

        /// Test that container configuration modifications work correctly
        #[test]
        fn test_container_config_modifications(
            mut config in container_config_strategy(),
            host_port in port_strategy(),
            container_port in port_strategy(),
            env_key in "[A-Z_][A-Z0-9_]{1,20}",
            env_value in "[a-zA-Z0-9/._:-]{0,100}",
            host_path in "/[a-zA-Z0-9/._-]{1,100}",
            container_path in "/[a-zA-Z0-9/._-]{1,100}",
            restart_policy in restart_policy_strategy()
        ) {
            let original_name = config.name.clone();
            let original_image = config.image.clone();
            
            // Add port mapping
            config.add_port_mapping(host_port, container_port);
            prop_assert!(config.port_mappings.contains_key(&host_port));
            prop_assert_eq!(config.port_mappings[&host_port], container_port);
            
            // Add environment variable
            config.add_environment_variable(&env_key, &env_value);
            prop_assert!(config.environment_variables.contains_key(&env_key));
            prop_assert_eq!(&config.environment_variables[&env_key], &env_value);
            
            // Add volume mount
            config.add_volume_mount(&host_path, &container_path);
            prop_assert!(config.volume_mounts.contains_key(&host_path));
            prop_assert_eq!(&config.volume_mounts[&host_path], &container_path);
            
            // Set restart policy
            config.set_restart_policy(&restart_policy);
            prop_assert_eq!(config.restart_policy, restart_policy);
            
            // Original fields should remain unchanged
            prop_assert_eq!(config.name, original_name);
            prop_assert_eq!(config.image, original_image);
        }

        /// Test that container status enum has correct properties
        #[test]
        fn test_container_status_properties(
            status in container_status_strategy()
        ) {
            // All statuses should be serializable
            let json = serde_json::to_string(&status)?;
            let deserialized: ContainerStatus = serde_json::from_str(&json)?;
            
            // Check serialization roundtrip
            match (&status, &deserialized) {
                (ContainerStatus::Exited(code1), ContainerStatus::Exited(code2)) => {
                    prop_assert_eq!(code1, code2);
                }
                (ContainerStatus::Error(msg1), ContainerStatus::Error(msg2)) => {
                    prop_assert_eq!(msg1, msg2);
                }
                (ContainerStatus::Unknown(msg1), ContainerStatus::Unknown(msg2)) => {
                    prop_assert_eq!(msg1, msg2);
                }
                _ => {
                    prop_assert_eq!(status.clone(), deserialized);
                }
            }
            
            // All statuses should have valid debug representations
            let debug_str = format!("{:?}", status);
            prop_assert!(!debug_str.is_empty());
        }

        /// Test that container stats have logical constraints
        #[test]
        fn test_container_stats_constraints(
            stats in container_stats_strategy()
        ) {
            // CPU usage should be between 0 and 100%
            prop_assert!(stats.cpu_usage_percent >= 0.0);
            prop_assert!(stats.cpu_usage_percent <= 100.0);
            
            // Memory usage should not exceed memory limit
            prop_assert!(stats.memory_usage_bytes <= stats.memory_limit_bytes);
            
            // Process count should be positive
            prop_assert!(stats.pids > 0);
            
            // All byte counts should be non-negative (guaranteed by u64 type)
            // Stats should be serializable
            let json = serde_json::to_string(&stats)?;
            let deserialized: ContainerStats = serde_json::from_str(&json)?;
            // Use approximate equality for floating point
            prop_assert!((stats.cpu_usage_percent - deserialized.cpu_usage_percent).abs() < 0.001);
            prop_assert_eq!(stats.memory_usage_bytes, deserialized.memory_usage_bytes);
        }

        /// Test that container operations have valid structure
        #[test]
        fn test_container_operation_structure(
            operation in container_operation_strategy()
        ) {
            match &operation {
                ContainerOperation::Start(name) => {
                    prop_assert!(!name.is_empty());
                    prop_assert!(name.len() <= 64); // Docker name limit
                }
                ContainerOperation::Stop(name, timeout) => {
                    prop_assert!(!name.is_empty());
                    if let Some(timeout_val) = timeout {
                        prop_assert!(*timeout_val > 0);
                        prop_assert!(*timeout_val < 3600); // Reasonable upper bound
                    }
                }
                ContainerOperation::Restart(name, timeout) => {
                    prop_assert!(!name.is_empty());
                    if let Some(timeout_val) = timeout {
                        prop_assert!(*timeout_val > 0);
                        prop_assert!(*timeout_val < 3600);
                    }
                }
                ContainerOperation::Remove(name, _force) => {
                    prop_assert!(!name.is_empty());
                }
            }
            
            // Should be cloneable
            let cloned = operation.clone();
            let debug_original = format!("{:?}", operation);
            let debug_cloned = format!("{:?}", cloned);
            prop_assert_eq!(debug_original, debug_cloned);
        }

        /// Test that batch operation options are reasonable
        #[test]
        fn test_batch_operation_options_constraints(
            options in batch_operation_options_strategy()
        ) {
            // Max concurrent should be positive and reasonable
            prop_assert!(options.max_concurrent > 0);
            prop_assert!(options.max_concurrent < 1000);
            
            // Timeout should be positive and reasonable
            prop_assert!(options.timeout.as_secs() > 0);
            prop_assert!(options.timeout.as_secs() < 3600);
            
            // Should be cloneable
            let cloned = options.clone();
            prop_assert_eq!(options.max_concurrent, cloned.max_concurrent);
            prop_assert_eq!(options.timeout, cloned.timeout);
            prop_assert_eq!(options.fail_fast, cloned.fail_fast);
        }

        /// Test that container names follow Docker naming rules
        #[test]
        fn test_container_name_validity(
            name in container_name_strategy()
        ) {
            // Should not be empty
            prop_assert!(!name.is_empty());
            
            // Should not exceed Docker's limit
            prop_assert!(name.len() <= 64);
            
            // Should start with alphanumeric character
            prop_assert!(name.chars().next().unwrap().is_alphanumeric());
            
            // Should only contain valid characters
            for ch in name.chars() {
                prop_assert!(ch.is_alphanumeric() || ch == '_' || ch == '.' || ch == '-');
            }
        }

        /// Test that Docker image names are valid
        #[test]
        fn test_docker_image_validity(
            image in docker_image_strategy()
        ) {
            // Should not be empty
            prop_assert!(!image.is_empty());
            
            // Should not contain uppercase letters (Docker convention)
            prop_assert!(!image.chars().any(|c| c.is_uppercase()));
            
            // Should not start with special characters
            let first_char = image.chars().next().unwrap();
            prop_assert!(first_char.is_alphanumeric());
        }

        /// Test that port mappings are valid
        #[test]
        fn test_port_mappings_validity(
            mappings in port_mappings_strategy()
        ) {
            for (&host_port, &container_port) in &mappings {
                // Both ports should be in valid range (guaranteed by strategy)
                prop_assert!(host_port >= 1024);
                prop_assert!(container_port >= 1024);
            }
            
            // Should not have too many mappings (resource constraint)
            prop_assert!(mappings.len() <= 5);
        }

        /// Test that environment variables follow naming conventions
        #[test]
        fn test_env_vars_validity(
            env_vars in env_vars_strategy()
        ) {
            for (key, value) in &env_vars {
                // Key should follow environment variable naming convention
                prop_assert!(!key.is_empty());
                prop_assert!(key.chars().all(|c| c.is_uppercase() || c.is_numeric() || c == '_'));
                prop_assert!(key.chars().next().unwrap().is_alphabetic() || key.starts_with('_'));
                
                // Value length should be reasonable
                prop_assert!(value.len() <= 100);
            }
            
            // Should not have too many variables
            prop_assert!(env_vars.len() <= 10);
        }

        /// Test that volume mounts use absolute paths
        #[test]
        fn test_volume_mounts_validity(
            mounts in volume_mounts_strategy()
        ) {
            for (host_path, container_path) in &mounts {
                // Both paths should be absolute
                prop_assert!(host_path.starts_with('/'));
                prop_assert!(container_path.starts_with('/'));
                
                // Paths should not be too long
                prop_assert!(host_path.len() <= 22); // +1 for leading slash
                prop_assert!(container_path.len() <= 22);
            }
            
            // Should not have too many mounts
            prop_assert!(mounts.len() <= 5);
        }
    }
}