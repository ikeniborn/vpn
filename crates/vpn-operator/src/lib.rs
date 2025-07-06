//! Kubernetes Operator for VPN Management
//!
//! This crate provides a Kubernetes operator that manages VPN deployments,
//! including automated provisioning, scaling, and lifecycle management.

pub mod controller;
pub mod crd;
pub mod error;
pub mod reconciler;
pub mod resources;
pub mod webhook;

pub use controller::VpnOperatorController;
pub use crd::{VpnServer, VpnServerSpec, VpnServerStatus};
pub use error::{OperatorError, Result};
pub use reconciler::VpnReconciler;

use kube::Client;
use std::sync::Arc;

/// Main operator that orchestrates VPN deployments in Kubernetes
pub struct VpnOperator {
    /// Kubernetes client
    _client: Client,
    /// Operator configuration
    config: OperatorConfig,
    /// Controller for managing resources
    controller: Arc<VpnOperatorController>,
}

/// Operator configuration
#[derive(Debug, Clone, serde::Deserialize)]
pub struct OperatorConfig {
    /// Namespace to watch (empty for all namespaces)
    pub namespace: Option<String>,
    /// Image to use for VPN containers
    pub vpn_image: String,
    /// Default VPN protocol
    pub default_protocol: String,
    /// Enable high availability mode
    pub enable_ha: bool,
    /// Metrics port
    pub metrics_port: u16,
    /// Webhook port
    pub webhook_port: u16,
    /// Leader election enabled
    pub leader_election: bool,
    /// Resource limits
    pub resource_limits: ResourceLimits,
}

/// Resource limits configuration
#[derive(Debug, Clone, serde::Deserialize)]
pub struct ResourceLimits {
    /// Default CPU request
    pub cpu_request: String,
    /// Default CPU limit
    pub cpu_limit: String,
    /// Default memory request
    pub memory_request: String,
    /// Default memory limit
    pub memory_limit: String,
}

impl Default for OperatorConfig {
    fn default() -> Self {
        Self {
            namespace: None,
            vpn_image: "vpn-server:latest".to_string(),
            default_protocol: "vless".to_string(),
            enable_ha: false,
            metrics_port: 8080,
            webhook_port: 9443,
            leader_election: true,
            resource_limits: ResourceLimits {
                cpu_request: "100m".to_string(),
                cpu_limit: "500m".to_string(),
                memory_request: "128Mi".to_string(),
                memory_limit: "512Mi".to_string(),
            },
        }
    }
}

impl VpnOperator {
    /// Create a new VPN operator
    pub async fn new(config: OperatorConfig) -> Result<Self> {
        let client = Client::try_default().await?;
        let controller =
            Arc::new(VpnOperatorController::new(client.clone(), config.clone()).await?);

        Ok(Self {
            _client: client,
            config,
            controller,
        })
    }

    /// Start the operator
    pub async fn run(&self) -> Result<()> {
        tracing::info!("Starting VPN Kubernetes Operator");

        // Start metrics server
        let metrics_handle = self.start_metrics_server();

        // Start webhook server if configured
        let webhook_handle = if self.config.webhook_port > 0 {
            Some(self.start_webhook_server())
        } else {
            None
        };

        // Start the controller
        self.controller.run().await?;

        // Wait for shutdown
        if let Some(webhook) = webhook_handle {
            webhook
                .await
                .map_err(|e| OperatorError::internal(format!("Webhook task failed: {}", e)))?;
        }
        metrics_handle
            .await
            .map_err(|e| OperatorError::internal(format!("Metrics task failed: {}", e)))?;

        Ok(())
    }

    /// Start metrics server
    fn start_metrics_server(&self) -> tokio::task::JoinHandle<()> {
        let port = self.config.metrics_port;
        tokio::spawn(async move {
            tracing::info!("Starting metrics server on port {}", port);
            // TODO: Implement metrics server
        })
    }

    /// Start webhook server
    fn start_webhook_server(&self) -> tokio::task::JoinHandle<()> {
        let port = self.config.webhook_port;
        tokio::spawn(async move {
            tracing::info!("Starting webhook server on port {}", port);
            // TODO: Implement webhook server
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = OperatorConfig::default();
        assert_eq!(config.vpn_image, "vpn-server:latest");
        assert_eq!(config.default_protocol, "vless");
        assert!(!config.enable_ha);
        assert_eq!(config.metrics_port, 8080);
    }
}
