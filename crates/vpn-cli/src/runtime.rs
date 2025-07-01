use crate::config::ConfigManager;
use crate::error::{CliError, Result};
use vpn_runtime::{RuntimeFactory, RuntimeType};
use vpn_containerd::ContainerdFactory;
use colored::*;
use std::path::PathBuf;

/// Runtime management commands
pub struct RuntimeManager {
    config_manager: ConfigManager,
}

impl RuntimeManager {
    pub fn new(config_path: Option<PathBuf>) -> Result<Self> {
        let config_manager = ConfigManager::new(config_path)?;
        Ok(Self { config_manager })
    }

    /// Show runtime status and information
    pub async fn show_status(&self) -> Result<()> {
        println!("{}", "Runtime Status".bold().cyan());
        println!("{}", "=".repeat(50).cyan());

        let runtime_config = self.config_manager.get_runtime_config();
        
        // Show current configuration
        println!("\n{}", "Configuration:".bold());
        println!("  Preferred Runtime: {}", runtime_config.preferred_runtime.yellow());
        println!("  Auto Detection: {}", format_bool(runtime_config.auto_detect));
        println!("  Fallback Enabled: {}", format_bool(runtime_config.fallback_enabled));

        // Check runtime availability
        println!("\n{}", "Runtime Availability:".bold());
        
        let docker_available = RuntimeFactory::is_runtime_available(RuntimeType::Docker).await;
        let containerd_available = RuntimeFactory::is_runtime_available(RuntimeType::Containerd).await;
        
        println!("  Docker: {} ({})", 
            format_bool(runtime_config.docker.enabled),
            if docker_available { "Available".green() } else { "Not Available".red() }
        );
        
        println!("  Containerd: {} ({})", 
            format_bool(runtime_config.containerd.enabled),
            if containerd_available { "Available".green() } else { "Not Available".red() }
        );

        // Show detailed configuration
        if runtime_config.docker.enabled {
            println!("\n{}", "Docker Configuration:".bold());
            println!("  Socket Path: {}", runtime_config.docker.socket_path);
            println!("  Timeout: {}s", runtime_config.docker.timeout_seconds);
            println!("  Max Connections: {}", runtime_config.docker.max_connections);
        }

        if runtime_config.containerd.enabled {
            println!("\n{}", "Containerd Configuration:".bold());
            println!("  Socket Path: {}", runtime_config.containerd.socket_path);
            println!("  Namespace: {}", runtime_config.containerd.namespace);
            println!("  Timeout: {}s", runtime_config.containerd.timeout_seconds);
            println!("  Max Connections: {}", runtime_config.containerd.max_connections);
            println!("  Snapshotter: {}", runtime_config.containerd.snapshotter);
            println!("  Runtime: {}", runtime_config.containerd.runtime);
        }

        // Test connectivity
        println!("\n{}", "Connectivity Tests:".bold());
        self.test_connectivity().await?;

        Ok(())
    }

    /// Switch to a different runtime
    pub async fn switch_runtime(&mut self, runtime: &str) -> Result<()> {
        // Validate runtime choice
        if !["auto", "docker", "containerd"].contains(&runtime) {
            return Err(CliError::InvalidInput(
                "Runtime must be 'auto', 'docker', or 'containerd'".to_string()
            ));
        }

        // Check if the runtime is available and enabled
        if runtime != "auto" {
            let runtime_config = self.config_manager.get_runtime_config();
            let (enabled, available) = match runtime {
                "docker" => (
                    runtime_config.docker.enabled,
                    RuntimeFactory::is_runtime_available(RuntimeType::Docker).await
                ),
                "containerd" => (
                    runtime_config.containerd.enabled,
                    RuntimeFactory::is_runtime_available(RuntimeType::Containerd).await
                ),
                _ => unreachable!(),
            };

            if !enabled {
                return Err(CliError::ConfigError(
                    format!("Runtime '{}' is not enabled in configuration", runtime)
                ));
            }

            if !available {
                return Err(CliError::RuntimeError(
                    format!("Runtime '{}' is not available on this system", runtime)
                ));
            }
        }

        // Perform the switch
        println!("Switching to runtime: {}", runtime.yellow());
        self.config_manager.set_preferred_runtime(runtime)?;
        
        // Test the new runtime
        println!("Testing new runtime configuration...");
        self.test_connectivity().await?;
        
        println!("{}", "Runtime switched successfully!".green());
        Ok(())
    }

    /// Enable or disable a runtime
    pub fn enable_runtime(&mut self, runtime: &str, enabled: bool) -> Result<()> {
        if !["docker", "containerd"].contains(&runtime) {
            return Err(CliError::InvalidInput(
                "Runtime must be 'docker' or 'containerd'".to_string()
            ));
        }

        let action = if enabled { "Enabling" } else { "Disabling" };
        println!("{} runtime: {}", action, runtime.yellow());
        
        self.config_manager.enable_runtime(runtime, enabled)?;
        
        let action_past = if enabled { "enabled" } else { "disabled" };
        println!("{}", format!("Runtime '{}' {}", runtime, action_past).green());
        
        Ok(())
    }

    /// Update runtime socket path
    pub fn update_socket(&mut self, runtime: &str, socket_path: &str) -> Result<()> {
        if !["docker", "containerd"].contains(&runtime) {
            return Err(CliError::InvalidInput(
                "Runtime must be 'docker' or 'containerd'".to_string()
            ));
        }

        println!("Updating {} socket path to: {}", runtime.yellow(), socket_path);
        self.config_manager.update_runtime_socket(runtime, socket_path)?;
        println!("{}", "Socket path updated successfully!".green());
        
        Ok(())
    }

    /// Migrate from Docker to containerd
    pub async fn migrate_to_containerd(&mut self) -> Result<()> {
        println!("{}", "Docker to Containerd Migration".bold().cyan());
        println!("{}", "=".repeat(40).cyan());

        // Check prerequisites
        println!("Checking prerequisites...");
        
        let runtime_config = self.config_manager.get_runtime_config();
        if !runtime_config.containerd.enabled {
            return Err(CliError::ConfigError(
                "Containerd runtime is not enabled in configuration".to_string()
            ));
        }

        let containerd_available = ContainerdFactory::is_available().await;
        if !containerd_available {
            return Err(CliError::RuntimeError(
                "Containerd is not available on this system".to_string()
            ));
        }

        // Test containerd connectivity
        println!("Testing containerd connectivity...");
        let vpn_runtime_config = self.config_manager.to_runtime_config();
        match ContainerdFactory::verify_connection(vpn_runtime_config.clone()).await {
            Ok(version) => println!("✓ Containerd connection verified (version: {})", version.green()),
            Err(e) => return Err(CliError::RuntimeError(
                format!("Failed to connect to containerd: {}", e)
            )),
        }

        // Backup current configuration if enabled
        if runtime_config.migration.backup_before_migration {
            println!("Creating configuration backup...");
            let backup_path = std::env::temp_dir().join(format!("vpn-config-backup-{}.toml", 
                chrono::Utc::now().timestamp()));
            self.config_manager.export_config(&backup_path)?;
            println!("✓ Configuration backed up to: {}", backup_path.display().to_string().green());
        }

        // Switch to containerd
        println!("Switching runtime to containerd...");
        let preserve_containers = runtime_config.migration.preserve_containers;
        let validate_after_migration = runtime_config.migration.validate_after_migration;
        self.config_manager.set_preferred_runtime("containerd")?;

        // Optionally disable Docker runtime
        if !preserve_containers {
            println!("Disabling Docker runtime...");
            // Don't actually disable to maintain fallback capability
            println!("Note: Docker runtime kept enabled for fallback capability");
        }

        // Validate migration
        if validate_after_migration {
            println!("Validating migration...");
            self.test_connectivity().await?;
        }

        println!("{}", "Migration completed successfully!".bold().green());
        println!("Your VPN system is now using containerd as the container runtime.");
        
        Ok(())
    }

    /// Test connectivity to configured runtimes
    async fn test_connectivity(&self) -> Result<()> {
        let runtime_config = self.config_manager.get_runtime_config();
        let vpn_runtime_config = self.config_manager.to_runtime_config();

        if runtime_config.docker.enabled {
            let available = RuntimeFactory::is_runtime_available(RuntimeType::Docker).await;
            if available {
                // For now just check availability, as we don't have Docker factory integration yet
                println!("  Docker: {}", "Connected".green());
            } else {
                println!("  Docker: {}", "Connection Failed".red());
            }
        }

        if runtime_config.containerd.enabled {
            match ContainerdFactory::verify_connection(vpn_runtime_config.clone()).await {
                Ok(version) => println!("  Containerd: {} (version: {})", "Connected".green(), version),
                Err(e) => println!("  Containerd: {} ({})", "Connection Failed".red(), e),
            }
        }

        Ok(())
    }

    /// Get runtime capabilities comparison
    pub fn show_capabilities(&self) -> Result<()> {
        println!("{}", "Runtime Capabilities Comparison".bold().cyan());
        println!("{}", "=".repeat(45).cyan());

        let docker_caps = RuntimeFactory::get_runtime_capabilities(RuntimeType::Docker);
        let containerd_caps = RuntimeFactory::get_runtime_capabilities(RuntimeType::Containerd);

        println!("\n{:<25} {:<10} {:<10}", "Feature", "Docker", "Containerd");
        println!("{}", "-".repeat(45));
        
        println!("{:<25} {:<10} {:<10}", 
            "Native Logging", 
            format_bool(docker_caps.native_logging),
            format_bool(containerd_caps.native_logging)
        );
        
        println!("{:<25} {:<10} {:<10}", 
            "Native Statistics", 
            format_bool(docker_caps.native_stats),
            format_bool(containerd_caps.native_stats)
        );
        
        println!("{:<25} {:<10} {:<10}", 
            "Health Checks", 
            format_bool(docker_caps.native_health_checks),
            format_bool(containerd_caps.native_health_checks)
        );
        
        println!("{:<25} {:<10} {:<10}", 
            "Volume Management", 
            format_bool(docker_caps.native_volumes),
            format_bool(containerd_caps.native_volumes)
        );
        
        println!("{:<25} {:<10} {:<10}", 
            "Event Streaming", 
            format_bool(docker_caps.event_streaming),
            format_bool(containerd_caps.event_streaming)
        );
        
        println!("{:<25} {:<10} {:<10}", 
            "Exec Support", 
            format_bool(docker_caps.exec_support),
            format_bool(containerd_caps.exec_support)
        );
        
        println!("{:<25} {:<10} {:<10}", 
            "Network Management", 
            format_bool(docker_caps.network_management),
            format_bool(containerd_caps.network_management)
        );

        println!("\n{}", "Recommendations:".bold());
        println!("• Docker: Full-featured, mature ecosystem, easier setup");
        println!("• Containerd: Lightweight, cloud-native, better for Kubernetes");
        println!("• Auto: Automatic selection based on availability and performance");

        Ok(())
    }
}

fn format_bool(value: bool) -> colored::ColoredString {
    if value {
        "✓".green()
    } else {
        "✗".red()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_runtime_manager_creation() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        
        let manager = RuntimeManager::new(Some(config_path));
        assert!(manager.is_ok());
    }

    #[tokio::test]
    async fn test_invalid_runtime_switch() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        let mut manager = RuntimeManager::new(Some(config_path)).unwrap();
        
        let result = manager.switch_runtime("invalid").await;
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_runtime_enable() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        let mut manager = RuntimeManager::new(Some(config_path)).unwrap();
        
        let result = manager.enable_runtime("invalid", true);
        assert!(result.is_err());
    }

    #[test]
    fn test_runtime_enable_disable() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        let mut manager = RuntimeManager::new(Some(config_path)).unwrap();
        
        // Should be able to disable docker (containerd still enabled)
        let result = manager.enable_runtime("docker", false);
        assert!(result.is_ok());
        
        // Should not be able to disable containerd now (would leave no runtimes)
        let result = manager.enable_runtime("containerd", false);
        assert!(result.is_err());
    }

    #[test]
    fn test_socket_path_update() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config.toml");
        let mut manager = RuntimeManager::new(Some(config_path)).unwrap();
        
        let result = manager.update_socket("containerd", "/custom/path.sock");
        assert!(result.is_ok());
        
        let runtime_config = manager.config_manager.get_runtime_config();
        assert_eq!(runtime_config.containerd.socket_path, "/custom/path.sock");
    }
}