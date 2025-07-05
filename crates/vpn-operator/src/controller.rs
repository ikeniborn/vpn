//! Main controller for managing VPN resources

use crate::{
    crd::{VpnPhase, VpnServer},
    error::{OperatorError, Result},
    reconciler::VpnReconciler,
    OperatorConfig,
};
use futures::StreamExt;
use kube::{
    api::{Api, Patch, PatchParams},
    client::Client,
    runtime::{
        controller::{Action, Controller},
        events::{Recorder, Reporter},
        finalizer::{finalizer, Event as FinalizerEvent},
    },
    ResourceExt,
};
use std::{sync::Arc, time::Duration};

/// Controller for managing VPN resources
pub struct VpnOperatorController {
    /// Kubernetes client
    client: Client,
    /// Operator configuration
    config: OperatorConfig,
    /// Reconciler for VPN resources
    reconciler: Arc<VpnReconciler>,
    /// Event recorder
    recorder: Recorder,
}

/// Controller context passed to reconciliation
pub struct Context {
    pub client: Client,
    pub config: OperatorConfig,
}

/// Finalizer name for VPN resources
const FINALIZER_NAME: &str = "vpnservers.vpn.io/finalizer";

impl VpnOperatorController {
    /// Create a new controller
    pub async fn new(client: Client, config: OperatorConfig) -> Result<Self> {
        let reconciler = Arc::new(VpnReconciler::new(client.clone(), config.clone()));

        // Create event recorder
        let reporter = Reporter {
            controller: "vpn-operator".into(),
            instance: std::env::var("HOSTNAME").ok(),
        };
        let recorder = Recorder::new(
            client.clone(),
            reporter,
            k8s_openapi::api::core::v1::ObjectReference::default(),
        );

        Ok(Self {
            client,
            config,
            reconciler,
            recorder,
        })
    }

    /// Run the controller
    pub async fn run(&self) -> Result<()> {
        tracing::info!("Starting VPN operator controller");

        let api = match &self.config.namespace {
            Some(ns) => Api::<VpnServer>::namespaced(self.client.clone(), ns),
            None => Api::<VpnServer>::all(self.client.clone()),
        };

        let context = Arc::new(Context {
            client: self.client.clone(),
            config: self.config.clone(),
        });

        Controller::new(api.clone(), kube::runtime::watcher::Config::default())
            .run(Self::reconcile, Self::error_policy, context)
            .for_each(|res| async {
                match res {
                    Ok(o) => tracing::debug!("Reconciled {:?}", o),
                    Err(e) => tracing::error!("Reconciliation error: {:?}", e),
                }
            })
            .await;

        Ok(())
    }

    /// Main reconciliation function
    async fn reconcile(vpn: Arc<VpnServer>, ctx: Arc<Context>) -> Result<Action> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        tracing::info!("Reconciling VpnServer {}/{}", namespace, name);

        let api = Api::<VpnServer>::namespaced(ctx.client.clone(), &namespace);

        // Handle finalizer
        let result = finalizer(&api, FINALIZER_NAME, vpn.clone(), |event| async {
            match event {
                FinalizerEvent::Apply(vpn_server) => {
                    Self::apply_vpn_server(vpn_server, ctx.clone()).await
                }
                FinalizerEvent::Cleanup(vpn_server) => {
                    Self::cleanup_vpn_server(vpn_server, ctx.clone()).await
                }
            }
        })
        .await;

        match result {
            Ok(_) => Ok(Action::requeue(Duration::from_secs(300))), // Requeue after 5 minutes
            Err(e) => {
                tracing::error!("Reconciliation failed: {:?}", e);
                Ok(Action::requeue(Duration::from_secs(30))) // Retry after 30 seconds
            }
        }
    }

    /// Apply VPN server resources
    async fn apply_vpn_server(vpn: Arc<VpnServer>, ctx: Arc<Context>) -> Result<Action> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        tracing::info!("Applying VPN server {}/{}", namespace, name);

        // Create reconciler and perform reconciliation
        let reconciler = VpnReconciler::new(ctx.client.clone(), ctx.config.clone());

        match reconciler.reconcile(vpn.clone()).await {
            Ok(_) => {
                // Update status to Running
                Self::update_status(vpn.clone(), ctx.clone(), VpnPhase::Running, None).await?;
                Ok(Action::requeue(Duration::from_secs(300)))
            }
            Err(e) => {
                tracing::error!("Failed to reconcile VPN server: {:?}", e);
                // Update status to Failed
                Self::update_status(
                    vpn.clone(),
                    ctx.clone(),
                    VpnPhase::Failed,
                    Some(format!("Reconciliation failed: {}", e)),
                )
                .await?;
                Ok(Action::requeue(Duration::from_secs(60)))
            }
        }
    }

    /// Cleanup VPN server resources
    async fn cleanup_vpn_server(vpn: Arc<VpnServer>, ctx: Arc<Context>) -> Result<Action> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        tracing::info!("Cleaning up VPN server {}/{}", namespace, name);

        // Update status to Terminating
        Self::update_status(vpn.clone(), ctx.clone(), VpnPhase::Terminating, None).await?;

        // Create reconciler and perform cleanup
        let reconciler = VpnReconciler::new(ctx.client.clone(), ctx.config.clone());

        match reconciler.cleanup(vpn.clone()).await {
            Ok(_) => {
                tracing::info!("Successfully cleaned up VPN server {}/{}", namespace, name);
                Ok(Action::await_change())
            }
            Err(e) => {
                tracing::error!("Failed to cleanup VPN server: {:?}", e);
                Ok(Action::requeue(Duration::from_secs(30)))
            }
        }
    }

    /// Update VPN server status
    async fn update_status(
        vpn: Arc<VpnServer>,
        ctx: Arc<Context>,
        phase: VpnPhase,
        message: Option<String>,
    ) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        let api = Api::<VpnServer>::namespaced(ctx.client.clone(), &namespace);

        let mut status = vpn.status.clone().unwrap_or_default();
        status.phase = phase;
        status.message = message;
        status.last_updated = chrono::Utc::now().to_rfc3339();

        let status_patch = serde_json::json!({
            "status": status
        });

        api.patch_status(&name, &PatchParams::default(), &Patch::Merge(status_patch))
            .await?;

        Ok(())
    }

    /// Error policy - determines how to handle errors
    fn error_policy(_vpn: Arc<VpnServer>, error: &OperatorError, _ctx: Arc<Context>) -> Action {
        tracing::error!("Reconciliation error: {:?}", error);
        Action::requeue(Duration::from_secs(60))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_controller_creation() {
        // This test would require a mock Kubernetes client
        // For now, just test that the types compile correctly
        let _ = Context {
            client: Client::try_default()
                .await
                .unwrap_or_else(|_| panic!("Test requires kube config")),
            config: OperatorConfig::default(),
        };
    }
}
