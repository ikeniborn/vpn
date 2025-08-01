//! Webhook handlers for admission control

use crate::{
    crd::{VpnServer, VpnServerSpec},
    error::{OperatorError, Result},
};
use kube::core::admission::{AdmissionRequest, AdmissionResponse};
use serde_json::json;

/// Validate VPN server specifications
pub fn validate_vpn_server(req: AdmissionRequest<VpnServer>) -> AdmissionResponse {
    match &req.object {
        Some(vpn) => match validate_spec(&vpn.spec) {
            Ok(_) => AdmissionResponse::from(&req),
            Err(e) => AdmissionResponse::invalid(e.to_string()),
        },
        None => AdmissionResponse::invalid("No object provided"),
    }
}

/// Mutate VPN server specifications with defaults
pub fn mutate_vpn_server(req: AdmissionRequest<VpnServer>) -> AdmissionResponse {
    match &req.object {
        Some(vpn) => {
            let patches = generate_patches(&vpn.spec);

            if patches.is_empty() {
                AdmissionResponse::from(&req)
            } else {
                let patch = json_patch::Patch(patches);
                AdmissionResponse::from(&req).with_patch(patch).unwrap()
            }
        }
        None => AdmissionResponse::invalid("No object provided"),
    }
}

/// Validate VPN server specification
fn validate_spec(spec: &VpnServerSpec) -> Result<()> {
    // Validate port range
    if spec.port < 1024 {
        return Err(OperatorError::validation("Port must be 1024 or higher"));
    }

    // Validate replicas
    if spec.replicas < 1 || spec.replicas > 10 {
        return Err(OperatorError::validation(
            "Replicas must be between 1 and 10",
        ));
    }

    // Validate user limits
    if spec.users.max_users == 0 {
        return Err(OperatorError::validation(
            "Maximum users must be greater than 0",
        ));
    }

    // Validate HA configuration
    if spec.high_availability && spec.replicas < 2 {
        return Err(OperatorError::validation(
            "High availability requires at least 2 replicas",
        ));
    }

    // Validate resource requests don't exceed limits
    // This would require parsing the quantity strings

    Ok(())
}

/// Generate JSON patches for default values
fn generate_patches(spec: &VpnServerSpec) -> Vec<json_patch::PatchOperation> {
    let mut patches = Vec::new();

    // Add default labels if missing
    if spec.labels.is_empty() {
        patches.push(json_patch::PatchOperation::Add(json_patch::AddOperation {
            path: "/spec/labels".to_string(),
            value: json!({
                "vpn.io/protocol": format!("{:?}", spec.protocol).to_lowercase()
            }),
        }));
    }

    // Add default annotations if missing
    if spec.annotations.is_empty() {
        patches.push(json_patch::PatchOperation::Add(json_patch::AddOperation {
            path: "/spec/annotations".to_string(),
            value: json!({
                "vpn.io/created-by": "vpn-operator"
            }),
        }));
    }

    patches
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crd::{
        MonitoringConfig, NetworkConfig, ResourceRequirements, SecurityConfig, UserManagement,
        VpnProtocol,
    };
    use std::collections::BTreeMap;

    fn create_test_spec() -> VpnServerSpec {
        VpnServerSpec {
            protocol: VpnProtocol::Vless,
            port: 8443,
            replicas: 1,
            high_availability: false,
            resources: ResourceRequirements::default(),
            users: UserManagement {
                max_users: 100,
                auto_create: false,
                quota_gb: 0,
                external_auth: None,
            },
            network: NetworkConfig::default(),
            security: SecurityConfig::default(),
            monitoring: MonitoringConfig::default(),
            labels: BTreeMap::new(),
            annotations: BTreeMap::new(),
        }
    }

    #[test]
    fn test_validate_valid_spec() {
        let spec = create_test_spec();
        assert!(validate_spec(&spec).is_ok());
    }

    #[test]
    fn test_validate_invalid_port() {
        let mut spec = create_test_spec();
        spec.port = 80;
        assert!(validate_spec(&spec).is_err());
    }

    #[test]
    fn test_validate_invalid_replicas() {
        let mut spec = create_test_spec();
        spec.replicas = 0;
        assert!(validate_spec(&spec).is_err());
    }

    #[test]
    fn test_validate_ha_requirements() {
        let mut spec = create_test_spec();
        spec.high_availability = true;
        spec.replicas = 1;
        assert!(validate_spec(&spec).is_err());

        spec.replicas = 2;
        assert!(validate_spec(&spec).is_ok());
    }
}
