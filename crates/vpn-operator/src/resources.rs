//! Resource generation for VPN deployments

pub mod configmap;
pub mod deployment;
pub mod secret;
pub mod service;

use crate::crd::VpnServer;
use kube::ResourceExt;
use std::collections::BTreeMap;

/// Common labels for all resources
pub fn common_labels(vpn: &VpnServer) -> BTreeMap<String, String> {
    let mut labels = BTreeMap::new();

    labels.insert("app".to_string(), "vpn-server".to_string());
    labels.insert("vpn.io/name".to_string(), vpn.name_any());
    labels.insert(
        "vpn.io/protocol".to_string(),
        format!("{:?}", vpn.spec.protocol).to_lowercase(),
    );
    labels.insert("vpn.io/managed-by".to_string(), "vpn-operator".to_string());

    // Add custom labels from spec
    for (key, value) in &vpn.spec.labels {
        labels.insert(key.clone(), value.clone());
    }

    labels
}

/// Common annotations for all resources
pub fn common_annotations(vpn: &VpnServer) -> BTreeMap<String, String> {
    let mut annotations = BTreeMap::new();

    annotations.insert(
        "vpn.io/version".to_string(),
        env!("CARGO_PKG_VERSION").to_string(),
    );

    // Add custom annotations from spec
    for (key, value) in &vpn.spec.annotations {
        annotations.insert(key.clone(), value.clone());
    }

    annotations
}

/// Owner reference for resources
pub fn owner_reference(
    vpn: &VpnServer,
) -> Vec<k8s_openapi::apimachinery::pkg::apis::meta::v1::OwnerReference> {
    vec![
        k8s_openapi::apimachinery::pkg::apis::meta::v1::OwnerReference {
            api_version: "vpn.io/v1alpha1".to_string(),
            kind: "VpnServer".to_string(),
            name: vpn.name_any(),
            uid: vpn.uid().unwrap_or_default(),
            controller: Some(true),
            block_owner_deletion: Some(true),
        },
    ]
}
