//! Deployment resource generation

use crate::{
    crd::{VpnServer, VpnProtocol},
    error::Result,
    resources::{common_labels, common_annotations, owner_reference},
    OperatorConfig,
};
use k8s_openapi::{
    api::{
        apps::v1::{Deployment, DeploymentSpec, DeploymentStrategy},
        core::v1::{
            Container, ContainerPort, EnvVar, EnvVarSource, PodSpec, PodTemplateSpec,
            ResourceRequirements, SecretKeySelector, Volume, VolumeMount,
            ConfigMapVolumeSource, SecretVolumeSource, Probe, HTTPGetAction,
        },
    },
    apimachinery::pkg::{
        api::resource::Quantity,
        apis::meta::v1::{LabelSelector, ObjectMeta},
    },
};
use kube::ResourceExt;
use std::collections::BTreeMap;

/// Create Deployment for VPN server
pub fn create_vpn_deployment(vpn: &VpnServer, config: &OperatorConfig) -> Result<Deployment> {
    let name = format!("{}-deployment", vpn.name_any());
    let namespace = vpn.namespace().unwrap_or_default();
    
    let labels = common_labels(vpn);
    let annotations = common_annotations(vpn);
    
    // Create container
    let container = create_vpn_container(vpn, config)?;
    
    // Create pod spec
    let pod_spec = PodSpec {
        containers: vec![container],
        volumes: Some(create_volumes(vpn)),
        security_context: Some(k8s_openapi::api::core::v1::PodSecurityContext {
            run_as_non_root: Some(true),
            run_as_user: Some(1000),
            fs_group: Some(1000),
            ..Default::default()
        }),
        ..Default::default()
    };
    
    // Create deployment spec
    let deployment_spec = DeploymentSpec {
        replicas: Some(vpn.spec.replicas),
        selector: LabelSelector {
            match_labels: Some(labels.clone()),
            ..Default::default()
        },
        template: PodTemplateSpec {
            metadata: Some(ObjectMeta {
                labels: Some(labels.clone()),
                annotations: Some(annotations.clone()),
                ..Default::default()
            }),
            spec: Some(pod_spec),
        },
        strategy: Some(DeploymentStrategy {
            type_: Some(if vpn.spec.high_availability {
                "RollingUpdate".to_string()
            } else {
                "Recreate".to_string()
            }),
            ..Default::default()
        }),
        ..Default::default()
    };
    
    Ok(Deployment {
        metadata: ObjectMeta {
            name: Some(name),
            namespace: Some(namespace),
            labels: Some(labels),
            annotations: Some(annotations),
            owner_references: Some(owner_reference(vpn)),
            ..Default::default()
        },
        spec: Some(deployment_spec),
        ..Default::default()
    })
}

/// Create VPN container
fn create_vpn_container(vpn: &VpnServer, config: &OperatorConfig) -> Result<Container> {
    let image = match &vpn.spec.protocol {
        VpnProtocol::Vless => format!("{}-vless", config.vpn_image),
        VpnProtocol::Outline => format!("{}-outline", config.vpn_image),
        VpnProtocol::Wireguard => format!("{}-wireguard", config.vpn_image),
        VpnProtocol::OpenVPN => format!("{}-openvpn", config.vpn_image),
    };
    
    let mut container = Container {
        name: "vpn-server".to_string(),
        image: Some(image),
        ports: Some(vec![
            ContainerPort {
                container_port: vpn.spec.port as i32,
                protocol: Some("TCP".to_string()),
                name: Some("vpn".to_string()),
                ..Default::default()
            },
        ]),
        env: Some(create_env_vars(vpn)),
        volume_mounts: Some(create_volume_mounts(vpn)),
        resources: Some(create_resource_requirements(&vpn.spec.resources)),
        ..Default::default()
    };
    
    // Add metrics port if enabled
    if vpn.spec.monitoring.enable_metrics {
        if let Some(ref mut ports) = container.ports {
            ports.push(ContainerPort {
                container_port: vpn.spec.monitoring.metrics_port as i32,
                protocol: Some("TCP".to_string()),
                name: Some("metrics".to_string()),
                ..Default::default()
            });
        }
    }
    
    // Add health checks
    container.liveness_probe = Some(create_liveness_probe(vpn));
    container.readiness_probe = Some(create_readiness_probe(vpn));
    
    Ok(container)
}

/// Create environment variables
fn create_env_vars(vpn: &VpnServer) -> Vec<EnvVar> {
    let mut env_vars = vec![
        EnvVar {
            name: "VPN_PROTOCOL".to_string(),
            value: Some(format!("{:?}", vpn.spec.protocol).to_lowercase()),
            ..Default::default()
        },
        EnvVar {
            name: "VPN_PORT".to_string(),
            value: Some(vpn.spec.port.to_string()),
            ..Default::default()
        },
    ];
    
    // Add secret-based environment variables
    match &vpn.spec.protocol {
        VpnProtocol::Vless => {
            env_vars.push(EnvVar {
                name: "VLESS_UUID".to_string(),
                value_from: Some(EnvVarSource {
                    secret_key_ref: Some(SecretKeySelector {
                        name: Some(format!("{}-secret", vpn.name_any())),
                        key: "uuid".to_string(),
                        ..Default::default()
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            });
        }
        VpnProtocol::Outline => {
            env_vars.push(EnvVar {
                name: "SHADOWSOCKS_PASSWORD".to_string(),
                value_from: Some(EnvVarSource {
                    secret_key_ref: Some(SecretKeySelector {
                        name: Some(format!("{}-secret", vpn.name_any())),
                        key: "password".to_string(),
                        ..Default::default()
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            });
        }
        _ => {}
    }
    
    env_vars
}

/// Create volume mounts
fn create_volume_mounts(vpn: &VpnServer) -> Vec<VolumeMount> {
    vec![
        VolumeMount {
            name: "config".to_string(),
            mount_path: "/etc/vpn".to_string(),
            ..Default::default()
        },
        VolumeMount {
            name: "secret".to_string(),
            mount_path: "/etc/vpn/secret".to_string(),
            read_only: Some(true),
            ..Default::default()
        },
        VolumeMount {
            name: "data".to_string(),
            mount_path: "/var/lib/vpn".to_string(),
            ..Default::default()
        },
    ]
}

/// Create volumes
fn create_volumes(vpn: &VpnServer) -> Vec<Volume> {
    vec![
        Volume {
            name: "config".to_string(),
            config_map: Some(ConfigMapVolumeSource {
                name: Some(format!("{}-config", vpn.name_any())),
                ..Default::default()
            }),
            ..Default::default()
        },
        Volume {
            name: "secret".to_string(),
            secret: Some(SecretVolumeSource {
                secret_name: Some(format!("{}-secret", vpn.name_any())),
                ..Default::default()
            }),
            ..Default::default()
        },
        Volume {
            name: "data".to_string(),
            empty_dir: Some(k8s_openapi::api::core::v1::EmptyDirVolumeSource::default()),
            ..Default::default()
        },
    ]
}

/// Create resource requirements
fn create_resource_requirements(resources: &crate::crd::ResourceRequirements) -> ResourceRequirements {
    let mut requests = BTreeMap::new();
    let mut limits = BTreeMap::new();
    
    requests.insert("cpu".to_string(), Quantity(resources.cpu_request.clone()));
    requests.insert("memory".to_string(), Quantity(resources.memory_request.clone()));
    
    limits.insert("cpu".to_string(), Quantity(resources.cpu_limit.clone()));
    limits.insert("memory".to_string(), Quantity(resources.memory_limit.clone()));
    
    ResourceRequirements {
        requests: Some(requests),
        limits: Some(limits),
        ..Default::default()
    }
}

/// Create liveness probe
fn create_liveness_probe(vpn: &VpnServer) -> Probe {
    Probe {
        http_get: Some(HTTPGetAction {
            path: Some("/health".to_string()),
            port: k8s_openapi::apimachinery::pkg::util::intstr::IntOrString::Int(
                vpn.spec.monitoring.metrics_port as i32
            ),
            ..Default::default()
        }),
        initial_delay_seconds: Some(30),
        period_seconds: Some(10),
        timeout_seconds: Some(5),
        failure_threshold: Some(3),
        ..Default::default()
    }
}

/// Create readiness probe
fn create_readiness_probe(vpn: &VpnServer) -> Probe {
    Probe {
        http_get: Some(HTTPGetAction {
            path: Some("/ready".to_string()),
            port: k8s_openapi::apimachinery::pkg::util::intstr::IntOrString::Int(
                vpn.spec.monitoring.metrics_port as i32
            ),
            ..Default::default()
        }),
        initial_delay_seconds: Some(10),
        period_seconds: Some(5),
        timeout_seconds: Some(3),
        success_threshold: Some(1),
        failure_threshold: Some(3),
        ..Default::default()
    }
}