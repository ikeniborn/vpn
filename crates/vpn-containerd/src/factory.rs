use crate::ContainerdRuntime;
use vpn_runtime::{RuntimeConfig, RuntimeError, CompleteRuntime};
use std::sync::Arc;

/// Factory for creating containerd runtime instances
pub struct ContainerdFactory;

impl ContainerdFactory {
    /// Create a new containerd runtime instance
    pub async fn create_runtime(
        config: RuntimeConfig,
    ) -> Result<Arc<ContainerdRuntime>, RuntimeError> {
        let runtime = ContainerdRuntime::new(config)
            .await
            .map_err(|e| RuntimeError::ConfigError {
                message: format!("Failed to create containerd runtime: {}", e),
            })?;
        
        Ok(Arc::new(runtime))
    }

    /// Check if containerd is available on the system
    pub async fn is_available() -> bool {
        // Check if containerd socket exists
        std::path::Path::new("/run/containerd/containerd.sock").exists()
    }

    /// Verify containerd connection
    pub async fn verify_connection(config: RuntimeConfig) -> Result<String, RuntimeError> {
        let runtime = ContainerdRuntime::new(config).await
            .map_err(|e| RuntimeError::ConfigError {
                message: format!("Failed to connect to containerd: {}", e),
            })?;
        
        runtime.version().await
    }
}