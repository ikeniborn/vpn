use crate::{ContainerRuntime, RuntimeConfig, RuntimeError, RuntimeType};
use std::sync::Arc;

/// Factory for creating runtime instances
pub struct RuntimeFactory;

impl RuntimeFactory {
    /// Create a runtime instance based on configuration
    pub async fn create_runtime(
        config: RuntimeConfig,
    ) -> Result<Arc<dyn ContainerRuntime<Container = Box<dyn crate::Container>, Task = Box<dyn crate::Task>, Volume = Box<dyn crate::Volume>, Image = Box<dyn crate::Image>>>, RuntimeError> {
        match config.runtime_type {
            RuntimeType::Docker => {
                Self::create_docker_runtime(config).await
            }
            RuntimeType::Containerd => {
                Self::create_containerd_runtime(config).await
            }
            RuntimeType::Auto => {
                Self::auto_detect_runtime(config).await
            }
        }
    }

    /// Automatically detect and create the best available runtime
    async fn auto_detect_runtime(
        config: RuntimeConfig,
    ) -> Result<Arc<dyn ContainerRuntime<Container = Box<dyn crate::Container>, Task = Box<dyn crate::Task>, Volume = Box<dyn crate::Volume>, Image = Box<dyn crate::Image>>>, RuntimeError> {
        // Try containerd first if enabled
        if config.containerd.is_some() {
            if let Ok(runtime) = Self::create_containerd_runtime(config.clone()).await {
                return Ok(runtime);
            }
        }

        // Fallback to Docker if enabled
        if config.fallback_enabled && config.docker.is_some() {
            if let Ok(runtime) = Self::create_docker_runtime(config).await {
                return Ok(runtime);
            }
        }

        Err(RuntimeError::NoRuntimeAvailable)
    }

    /// Create Docker runtime instance
    async fn create_docker_runtime(
        _config: RuntimeConfig,
    ) -> Result<Arc<dyn ContainerRuntime<Container = Box<dyn crate::Container>, Task = Box<dyn crate::Task>, Volume = Box<dyn crate::Volume>, Image = Box<dyn crate::Image>>>, RuntimeError> {
        // This will be implemented when we integrate with existing vpn-docker
        Err(RuntimeError::ConfigError {
            message: "Docker runtime not yet integrated".to_string(),
        })
    }

    /// Create containerd runtime instance
    async fn create_containerd_runtime(
        _config: RuntimeConfig,
    ) -> Result<Arc<dyn ContainerRuntime<Container = Box<dyn crate::Container>, Task = Box<dyn crate::Task>, Volume = Box<dyn crate::Volume>, Image = Box<dyn crate::Image>>>, RuntimeError> {
        // This will be implemented in vpn-containerd crate
        Err(RuntimeError::ConfigError {
            message: "containerd runtime not yet implemented".to_string(),
        })
    }

    /// Check if a runtime is available
    pub async fn is_runtime_available(runtime_type: RuntimeType) -> bool {
        match runtime_type {
            RuntimeType::Docker => Self::is_docker_available().await,
            RuntimeType::Containerd => Self::is_containerd_available().await,
            RuntimeType::Auto => {
                Self::is_containerd_available().await || Self::is_docker_available().await
            }
        }
    }

    /// Check if Docker is available
    async fn is_docker_available() -> bool {
        // Check if Docker socket exists and is accessible
        std::path::Path::new("/var/run/docker.sock").exists()
    }

    /// Check if containerd is available
    async fn is_containerd_available() -> bool {
        // Check if containerd socket exists and is accessible
        std::path::Path::new("/run/containerd/containerd.sock").exists()
    }

    /// Get runtime capabilities
    pub fn get_runtime_capabilities(runtime_type: RuntimeType) -> RuntimeCapabilities {
        match runtime_type {
            RuntimeType::Docker => RuntimeCapabilities {
                native_logging: true,
                native_stats: true,
                native_health_checks: true,
                native_volumes: true,
                event_streaming: true,
                exec_support: true,
                network_management: true,
            },
            RuntimeType::Containerd => RuntimeCapabilities {
                native_logging: false, // Requires custom implementation
                native_stats: false,   // Requires cgroup access
                native_health_checks: false, // Custom implementation needed
                native_volumes: true,  // Via snapshots
                event_streaming: true,
                exec_support: true,
                network_management: false, // Limited support
            },
            RuntimeType::Auto => RuntimeCapabilities {
                native_logging: true,
                native_stats: true,
                native_health_checks: true,
                native_volumes: true,
                event_streaming: true,
                exec_support: true,
                network_management: true,
            },
        }
    }
}

/// Runtime capabilities information
#[derive(Debug, Clone)]
pub struct RuntimeCapabilities {
    pub native_logging: bool,
    pub native_stats: bool,
    pub native_health_checks: bool,
    pub native_volumes: bool,
    pub event_streaming: bool,
    pub exec_support: bool,
    pub network_management: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_runtime_capabilities() {
        let docker_caps = RuntimeFactory::get_runtime_capabilities(RuntimeType::Docker);
        assert!(docker_caps.native_logging);
        assert!(docker_caps.native_stats);

        let containerd_caps = RuntimeFactory::get_runtime_capabilities(RuntimeType::Containerd);
        assert!(!containerd_caps.native_logging);
        assert!(!containerd_caps.native_stats);
        assert!(containerd_caps.event_streaming);
    }

    #[tokio::test]
    async fn test_runtime_availability() {
        // These tests will pass/fail based on system configuration
        let docker_available = RuntimeFactory::is_docker_available().await;
        let containerd_available = RuntimeFactory::is_containerd_available().await;
        
        // At least log what's available for debugging
        println!("Docker available: {}", docker_available);
        println!("containerd available: {}", containerd_available);
    }
}