//! Docker utilities for container management and conflict resolution

use crate::error::{Result, ServerError};
use std::process::Command;
use tracing::{debug, info, warn};

pub struct DockerUtils;

impl DockerUtils {
    /// Check if a container with the given name exists
    pub fn container_exists(name: &str) -> Result<bool> {
        let output = Command::new("docker")
            .arg("ps")
            .arg("-a")
            .arg("--filter")
            .arg(format!("name=^{}$", name))
            .arg("--format")
            .arg("{{.ID}}")
            .output()
            .map_err(|e| ServerError::InstallationError(format!("Failed to check container: {}", e)))?;

        if output.status.success() {
            let container_ids = String::from_utf8_lossy(&output.stdout);
            Ok(!container_ids.trim().is_empty())
        } else {
            Ok(false)
        }
    }

    /// Remove a container by name, forcefully if needed
    pub fn remove_container(name: &str) -> Result<bool> {
        debug!("Attempting to remove container: {}", name);
        
        // First try to stop the container
        let _ = Command::new("docker")
            .arg("stop")
            .arg(name)
            .output();

        // Then force remove it
        let output = Command::new("docker")
            .arg("rm")
            .arg("-f")
            .arg(name)
            .output()
            .map_err(|e| ServerError::InstallationError(format!("Failed to remove container: {}", e)))?;

        if output.status.success() {
            info!("Successfully removed container: {}", name);
            Ok(true)
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if stderr.contains("No such container") {
                debug!("Container {} does not exist", name);
                Ok(false)
            } else {
                warn!("Failed to remove container {}: {}", name, stderr);
                Ok(false)
            }
        }
    }

    /// Remove multiple containers that might conflict
    pub fn cleanup_conflicting_containers(container_names: &[&str]) -> Result<()> {
        info!("Checking for conflicting containers...");
        
        let mut removed_count = 0;
        for container_name in container_names {
            if Self::container_exists(container_name)? {
                if Self::remove_container(container_name)? {
                    removed_count += 1;
                }
            }
        }
        
        if removed_count > 0 {
            info!("Cleaned up {} conflicting container(s)", removed_count);
        } else {
            debug!("No conflicting containers found");
        }
        
        Ok(())
    }

    /// Extract container name from Docker error message
    pub fn extract_container_name_from_error(error_msg: &str) -> Option<String> {
        // Error format: 'The container name "/watchtower" is already in use by container...'
        if let Some(start) = error_msg.find("/") {
            if let Some(end) = error_msg[start+1..].find("\"") {
                return Some(error_msg[start+1..start+1+end].to_string());
            }
        }
        None
    }

    /// Handle container name conflict during deployment
    pub async fn handle_container_conflict(
        error_msg: &str,
        compose_path: &std::path::Path,
    ) -> Result<bool> {
        if error_msg.contains("Conflict") && error_msg.contains("container name") && error_msg.contains("already in use") {
            if let Some(container_name) = Self::extract_container_name_from_error(error_msg) {
                warn!("Container name conflict detected: {}", container_name);
                info!("Attempting to resolve conflict...");
                
                if Self::remove_container(&container_name)? {
                    info!("Retrying deployment...");
                    
                    // Retry the deployment
                    let output = Command::new("docker-compose")
                        .arg("-f")
                        .arg(compose_path)
                        .arg("up")
                        .arg("-d")
                        .arg("--remove-orphans")
                        .current_dir(compose_path.parent().unwrap_or(std::path::Path::new(".")))
                        .output()
                        .map_err(|e| ServerError::InstallationError(format!("Failed to retry deployment: {}", e)))?;
                    
                    if output.status.success() {
                        info!("Container deployment succeeded on retry");
                        return Ok(true);
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        return Err(ServerError::InstallationError(format!(
                            "Docker Compose failed on retry: {}",
                            stderr
                        )));
                    }
                }
            }
        }
        Ok(false)
    }

    /// Clean up unused Docker networks
    pub fn prune_networks() -> Result<()> {
        debug!("Pruning unused Docker networks...");
        
        let output = Command::new("docker")
            .arg("network")
            .arg("prune")
            .arg("-f")
            .output()
            .map_err(|e| ServerError::InstallationError(format!("Failed to prune networks: {}", e)))?;

        if output.status.success() {
            debug!("Docker network prune completed");
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            warn!("Network prune warning: {}", stderr);
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_container_name_from_error() {
        let error_msg = r#"Error response from daemon: Conflict. The container name "/watchtower" is already in use by container "ef0f0db94020"."#;
        let name = DockerUtils::extract_container_name_from_error(error_msg);
        assert_eq!(name, Some("watchtower".to_string()));
    }

    #[test]
    fn test_extract_container_name_with_prefix() {
        let error_msg = r#"Error response from daemon: Conflict. The container name "/vless-watchtower" is already in use."#;
        let name = DockerUtils::extract_container_name_from_error(error_msg);
        assert_eq!(name, Some("vless-watchtower".to_string()));
    }
}