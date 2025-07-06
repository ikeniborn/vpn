//! Reconciler for VPN resources

use crate::{
    crd::VpnServer,
    error::Result,
    resources::{configmap, deployment, secret, service},
    OperatorConfig,
};
use k8s_openapi::api::{
    apps::v1::Deployment,
    core::v1::{ConfigMap, Secret, Service},
};
use kube::{
    api::{Api, DeleteParams, Patch, PatchParams, PostParams},
    client::Client,
    ResourceExt,
};
use std::sync::Arc;

/// Reconciler for VPN resources
pub struct VpnReconciler {
    /// Kubernetes client
    client: Client,
    /// Operator configuration
    config: OperatorConfig,
}

impl VpnReconciler {
    /// Create a new reconciler
    pub fn new(client: Client, config: OperatorConfig) -> Self {
        Self { client, config }
    }

    /// Reconcile a VPN server resource
    pub async fn reconcile(&self, vpn: Arc<VpnServer>) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        tracing::info!("Reconciling VPN server {}/{}", namespace, name);

        // Create or update ConfigMap
        self.reconcile_configmap(&vpn).await?;

        // Create or update Secret
        self.reconcile_secret(&vpn).await?;

        // Create or update Deployment
        self.reconcile_deployment(&vpn).await?;

        // Create or update Service
        self.reconcile_service(&vpn).await?;

        // Create additional resources based on configuration
        if vpn.spec.high_availability {
            self.reconcile_ha_resources(&vpn).await?;
        }

        if vpn.spec.monitoring.enable_metrics {
            self.reconcile_monitoring_resources(&vpn).await?;
        }

        Ok(())
    }

    /// Cleanup VPN server resources
    pub async fn cleanup(&self, vpn: Arc<VpnServer>) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        tracing::info!("Cleaning up VPN server {}/{}", namespace, name);

        // Delete in reverse order
        self.delete_service(&name, &namespace).await?;
        self.delete_deployment(&name, &namespace).await?;
        self.delete_secret(&name, &namespace).await?;
        self.delete_configmap(&name, &namespace).await?;

        Ok(())
    }

    /// Reconcile ConfigMap
    async fn reconcile_configmap(&self, vpn: &VpnServer) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        let api: Api<ConfigMap> = Api::namespaced(self.client.clone(), &namespace);
        let cm_name = format!("{}-config", name);

        let cm = configmap::create_vpn_configmap(vpn, &self.config)?;

        match api.get(&cm_name).await {
            Ok(_existing) => {
                // Update existing ConfigMap
                let patch = Patch::Apply(&cm);
                api.patch(&cm_name, &PatchParams::apply("vpn-operator"), &patch)
                    .await?;
                tracing::debug!("Updated ConfigMap {}/{}", namespace, cm_name);
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Create new ConfigMap
                api.create(&PostParams::default(), &cm).await?;
                tracing::info!("Created ConfigMap {}/{}", namespace, cm_name);
            }
            Err(e) => return Err(e.into()),
        }

        Ok(())
    }

    /// Reconcile Secret
    async fn reconcile_secret(&self, vpn: &VpnServer) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        let api: Api<Secret> = Api::namespaced(self.client.clone(), &namespace);
        let secret_name = format!("{}-secret", name);

        // Check if secret already exists
        match api.get(&secret_name).await {
            Ok(_) => {
                // Secret exists, don't regenerate keys
                tracing::debug!("Secret {}/{} already exists", namespace, secret_name);
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Create new Secret with generated keys
                let secret = secret::create_vpn_secret(vpn)?;
                api.create(&PostParams::default(), &secret).await?;
                tracing::info!("Created Secret {}/{}", namespace, secret_name);
            }
            Err(e) => return Err(e.into()),
        }

        Ok(())
    }

    /// Reconcile Deployment
    async fn reconcile_deployment(&self, vpn: &VpnServer) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        let api: Api<Deployment> = Api::namespaced(self.client.clone(), &namespace);
        let deployment_name = format!("{}-deployment", name);

        let deployment = deployment::create_vpn_deployment(vpn, &self.config)?;

        match api.get(&deployment_name).await {
            Ok(_existing) => {
                // Update existing Deployment
                let patch = Patch::Apply(&deployment);
                api.patch(
                    &deployment_name,
                    &PatchParams::apply("vpn-operator"),
                    &patch,
                )
                .await?;
                tracing::debug!("Updated Deployment {}/{}", namespace, deployment_name);
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Create new Deployment
                api.create(&PostParams::default(), &deployment).await?;
                tracing::info!("Created Deployment {}/{}", namespace, deployment_name);
            }
            Err(e) => return Err(e.into()),
        }

        Ok(())
    }

    /// Reconcile Service
    async fn reconcile_service(&self, vpn: &VpnServer) -> Result<()> {
        let name = vpn.name_any();
        let namespace = vpn.namespace().unwrap_or_default();

        let api: Api<Service> = Api::namespaced(self.client.clone(), &namespace);
        let service_name = name.clone();

        let service = service::create_vpn_service(vpn)?;

        match api.get(&service_name).await {
            Ok(existing) => {
                // Update existing Service (but preserve ClusterIP and NodePort)
                let patch = service::create_service_patch(vpn, &existing)?;
                let patch = Patch::Apply(patch);
                api.patch(&service_name, &PatchParams::apply("vpn-operator"), &patch)
                    .await?;
                tracing::debug!("Updated Service {}/{}", namespace, service_name);
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Create new Service
                api.create(&PostParams::default(), &service).await?;
                tracing::info!("Created Service {}/{}", namespace, service_name);
            }
            Err(e) => return Err(e.into()),
        }

        Ok(())
    }

    /// Reconcile HA resources
    async fn reconcile_ha_resources(&self, vpn: &VpnServer) -> Result<()> {
        tracing::info!("Reconciling HA resources for {}", vpn.name_any());

        // TODO: Create PodDisruptionBudget
        // TODO: Configure anti-affinity rules
        // TODO: Setup health checks

        Ok(())
    }

    /// Reconcile monitoring resources
    async fn reconcile_monitoring_resources(&self, vpn: &VpnServer) -> Result<()> {
        tracing::info!("Reconciling monitoring resources for {}", vpn.name_any());

        // TODO: Create ServiceMonitor for Prometheus
        // TODO: Configure metrics endpoints

        Ok(())
    }

    /// Delete ConfigMap
    async fn delete_configmap(&self, name: &str, namespace: &str) -> Result<()> {
        let api: Api<ConfigMap> = Api::namespaced(self.client.clone(), namespace);
        let cm_name = format!("{}-config", name);

        match api.delete(&cm_name, &DeleteParams::default()).await {
            Ok(_) => {
                tracing::info!("Deleted ConfigMap {}/{}", namespace, cm_name);
                Ok(())
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Already deleted
                Ok(())
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Delete Secret
    async fn delete_secret(&self, name: &str, namespace: &str) -> Result<()> {
        let api: Api<Secret> = Api::namespaced(self.client.clone(), namespace);
        let secret_name = format!("{}-secret", name);

        match api.delete(&secret_name, &DeleteParams::default()).await {
            Ok(_) => {
                tracing::info!("Deleted Secret {}/{}", namespace, secret_name);
                Ok(())
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Already deleted
                Ok(())
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Delete Deployment
    async fn delete_deployment(&self, name: &str, namespace: &str) -> Result<()> {
        let api: Api<Deployment> = Api::namespaced(self.client.clone(), namespace);
        let deployment_name = format!("{}-deployment", name);

        match api.delete(&deployment_name, &DeleteParams::default()).await {
            Ok(_) => {
                tracing::info!("Deleted Deployment {}/{}", namespace, deployment_name);
                Ok(())
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Already deleted
                Ok(())
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Delete Service
    async fn delete_service(&self, name: &str, namespace: &str) -> Result<()> {
        let api: Api<Service> = Api::namespaced(self.client.clone(), namespace);

        match api.delete(name, &DeleteParams::default()).await {
            Ok(_) => {
                tracing::info!("Deleted Service {}/{}", namespace, name);
                Ok(())
            }
            Err(kube::Error::Api(e)) if e.code == 404 => {
                // Already deleted
                Ok(())
            }
            Err(e) => Err(e.into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reconciler_creation() {
        // This test would require a mock client
        // For now, just ensure the types compile
        let _ = std::mem::size_of::<VpnReconciler>();
    }
}
