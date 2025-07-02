//! Service resource generation

use crate::{
    crd::VpnServer,
    error::Result,
    resources::{common_labels, common_annotations, owner_reference},
};
use k8s_openapi::{
    api::core::v1::{Service, ServicePort, ServiceSpec},
    apimachinery::pkg::{
        apis::meta::v1::ObjectMeta,
        util::intstr::IntOrString,
    },
};
use kube::ResourceExt;

/// Create Service for VPN server
pub fn create_vpn_service(vpn: &VpnServer) -> Result<Service> {
    let name = vpn.name_any();
    let namespace = vpn.namespace().unwrap_or_default();
    
    let labels = common_labels(vpn);
    let annotations = common_annotations(vpn);
    
    let mut ports = vec![
        ServicePort {
            name: Some("vpn".to_string()),
            port: vpn.spec.port as i32,
            target_port: Some(IntOrString::Int(vpn.spec.port as i32)),
            protocol: Some("TCP".to_string()),
            node_port: vpn.spec.network.node_port.map(|p| p as i32),
            app_protocol: None,
        },
    ];
    
    // Add metrics port if enabled
    if vpn.spec.monitoring.enable_metrics {
        ports.push(ServicePort {
            name: Some("metrics".to_string()),
            port: vpn.spec.monitoring.metrics_port as i32,
            target_port: Some(IntOrString::Int(vpn.spec.monitoring.metrics_port as i32)),
            protocol: Some("TCP".to_string()),
            node_port: None,
            app_protocol: None,
        });
    }
    
    let mut spec = ServiceSpec {
        selector: Some(labels.clone()),
        ports: Some(ports),
        type_: Some(vpn.spec.network.service_type.clone()),
        ..Default::default()
    };
    
    // Add load balancer source ranges if specified
    if !vpn.spec.network.load_balancer_source_ranges.is_empty() {
        spec.load_balancer_source_ranges = Some(vpn.spec.network.load_balancer_source_ranges.clone());
    }
    
    Ok(Service {
        metadata: ObjectMeta {
            name: Some(name),
            namespace: Some(namespace),
            labels: Some(labels),
            annotations: Some(annotations),
            owner_references: Some(owner_reference(vpn)),
            ..Default::default()
        },
        spec: Some(spec),
        ..Default::default()
    })
}

/// Create a patch for updating an existing service
pub fn create_service_patch(vpn: &VpnServer, existing: &Service) -> Result<serde_json::Value> {
    let new_service = create_vpn_service(vpn)?;
    
    // Preserve ClusterIP and NodePort from existing service
    let mut patch = serde_json::json!({
        "metadata": {
            "labels": new_service.metadata.labels,
            "annotations": new_service.metadata.annotations,
        },
        "spec": new_service.spec,
    });
    
    // Preserve ClusterIP
    if let Some(existing_spec) = &existing.spec {
        if let Some(cluster_ip) = &existing_spec.cluster_ip {
            patch["spec"]["clusterIP"] = serde_json::Value::String(cluster_ip.clone());
        }
        
        // Preserve NodePorts
        if let (Some(existing_ports), Some(new_ports)) = (&existing_spec.ports, &new_service.spec.as_ref().unwrap().ports) {
            let mut preserved_ports = new_ports.clone();
            for (i, new_port) in preserved_ports.iter_mut().enumerate() {
                if let Some(existing_port) = existing_ports.iter().find(|p| p.name == new_port.name) {
                    if let Some(node_port) = existing_port.node_port {
                        new_port.node_port = Some(node_port);
                    }
                }
            }
            patch["spec"]["ports"] = serde_json::to_value(preserved_ports)?;
        }
    }
    
    Ok(patch)
}