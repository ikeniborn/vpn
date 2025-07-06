//! ConfigMap resource generation

use crate::{
    crd::{VpnProtocol, VpnServer},
    error::Result,
    resources::{common_annotations, common_labels, owner_reference},
    OperatorConfig,
};
use k8s_openapi::{api::core::v1::ConfigMap, apimachinery::pkg::apis::meta::v1::ObjectMeta};
use kube::ResourceExt;
use std::collections::BTreeMap;

/// Create ConfigMap for VPN server configuration
pub fn create_vpn_configmap(vpn: &VpnServer, config: &OperatorConfig) -> Result<ConfigMap> {
    let name = format!("{}-config", vpn.name_any());
    let namespace = vpn.namespace().unwrap_or_default();

    let mut data = BTreeMap::new();

    // Generate VPN configuration based on protocol
    match &vpn.spec.protocol {
        VpnProtocol::Vless => {
            data.insert("config.json".to_string(), generate_vless_config(vpn)?);
        }
        VpnProtocol::Outline => {
            data.insert("config.yml".to_string(), generate_outline_config(vpn)?);
        }
        VpnProtocol::Wireguard => {
            data.insert("wg0.conf".to_string(), generate_wireguard_config(vpn)?);
        }
        VpnProtocol::OpenVPN => {
            data.insert("server.conf".to_string(), generate_openvpn_config(vpn)?);
        }
    }

    // Add common configuration
    data.insert("server.env".to_string(), generate_env_config(vpn, config)?);

    Ok(ConfigMap {
        metadata: ObjectMeta {
            name: Some(name),
            namespace: Some(namespace),
            labels: Some(common_labels(vpn)),
            annotations: Some(common_annotations(vpn)),
            owner_references: Some(owner_reference(vpn)),
            ..Default::default()
        },
        data: Some(data),
        ..Default::default()
    })
}

/// Generate VLESS configuration
fn generate_vless_config(vpn: &VpnServer) -> Result<String> {
    let config = serde_json::json!({
        "log": {
            "loglevel": "info"
        },
        "inbounds": [{
            "port": vpn.spec.port,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none",
                "fallbacks": []
            },
            "streamSettings": {
                "network": "tcp",
                "security": if vpn.spec.security.enable_tls { "tls" } else { "none" },
                "tcpSettings": {
                    "acceptProxyProtocol": false
                }
            }
        }],
        "outbounds": [{
            "protocol": "freedom",
            "settings": {}
        }],
        "policy": {
            "levels": {
                "0": {
                    "handshake": 4,
                    "connIdle": 300,
                    "uplinkOnly": 2,
                    "downlinkOnly": 5,
                    "statsUserUplink": false,
                    "statsUserDownlink": false
                }
            },
            "system": {
                "statsInboundUplink": true,
                "statsInboundDownlink": true
            }
        }
    });

    Ok(serde_json::to_string_pretty(&config)?)
}

/// Generate Outline configuration
fn generate_outline_config(vpn: &VpnServer) -> Result<String> {
    let config = serde_json::json!({
        "keys": [],
        "port": vpn.spec.port,
        "hostname": vpn.spec.network.load_balancer_source_ranges.first()
            .unwrap_or(&"0.0.0.0".to_string()),
        "metrics": {
            "enabled": vpn.spec.monitoring.enable_metrics,
            "port": vpn.spec.monitoring.metrics_port
        }
    });

    serde_yaml::to_string(&config).map_err(|e| e.into())
}

/// Generate WireGuard configuration
fn generate_wireguard_config(vpn: &VpnServer) -> Result<String> {
    Ok(format!(
        r#"[Interface]
PrivateKey = {{PRIVATE_KEY}}
Address = 10.0.0.1/24
ListenPort = {}
SaveConfig = false

# Peers will be added dynamically
"#,
        vpn.spec.port
    ))
}

/// Generate OpenVPN configuration
fn generate_openvpn_config(vpn: &VpnServer) -> Result<String> {
    Ok(format!(
        r#"port {}
proto tcp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-GCM
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
"#,
        vpn.spec.port
    ))
}

/// Generate environment configuration
fn generate_env_config(vpn: &VpnServer, _config: &OperatorConfig) -> Result<String> {
    let mut env = vec![
        format!("VPN_PROTOCOL={:?}", vpn.spec.protocol).to_lowercase(),
        format!("VPN_PORT={}", vpn.spec.port),
        format!("MAX_USERS={}", vpn.spec.users.max_users),
        format!("ENABLE_METRICS={}", vpn.spec.monitoring.enable_metrics),
        format!("METRICS_PORT={}", vpn.spec.monitoring.metrics_port),
    ];

    if vpn.spec.users.quota_gb > 0 {
        env.push(format!("USER_QUOTA_GB={}", vpn.spec.users.quota_gb));
    }

    if vpn.spec.network.enable_ipv6 {
        env.push("ENABLE_IPV6=true".to_string());
    }

    Ok(env.join("\n"))
}
