use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use crate::user::User;
use crate::error::{UserError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub sni: Option<String>,
    pub public_key: Option<String>,
    pub private_key: Option<String>,
    pub short_id: Option<String>,
    pub reality_dest: Option<String>,
    pub reality_server_names: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XrayConfig {
    pub log: LogConfig,
    pub inbounds: Vec<Inbound>,
    pub outbounds: Vec<Outbound>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogConfig {
    pub level: String,
    pub access: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Inbound {
    pub tag: String,
    pub port: u16,
    pub protocol: String,
    pub settings: InboundSettings,
    pub stream_settings: Option<StreamSettings>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InboundSettings {
    pub clients: Vec<Client>,
    pub decryption: Option<String>,
    pub fallbacks: Option<Vec<Fallback>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Client {
    pub id: String,
    pub flow: Option<String>,
    pub email: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Fallback {
    pub dest: String,
    pub xver: Option<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Outbound {
    pub tag: String,
    pub protocol: String,
    pub settings: Option<OutboundSettings>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboundSettings {
    pub freedom: Option<HashMap<String, serde_json::Value>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamSettings {
    pub network: String,
    pub security: String,
    pub reality_settings: Option<RealitySettings>,
    pub tcp_settings: Option<TcpSettings>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RealitySettings {
    pub show: bool,
    pub dest: String,
    pub xver: u8,
    pub server_names: Vec<String>,
    pub private_key: String,
    pub short_id: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TcpSettings {
    pub header: Option<TcpHeader>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TcpHeader {
    #[serde(rename = "type")]
    pub header_type: String,
}

pub struct ConfigGenerator;

impl ConfigGenerator {
    pub fn generate_xray_config(
        users: &[User],
        server_config: &ServerConfig,
    ) -> Result<XrayConfig> {
        let clients: Vec<Client> = users
            .iter()
            .filter(|u| u.is_active())
            .map(|u| Client {
                id: u.id.clone(),
                flow: u.config.flow.clone(),
                email: u.email.clone(),
            })
            .collect();

        let inbound_settings = InboundSettings {
            clients,
            decryption: Some("none".to_string()),
            fallbacks: None,
        };

        let reality_settings = if server_config.private_key.is_some() {
            Some(RealitySettings {
                show: false,
                dest: server_config.reality_dest.clone()
                    .unwrap_or_else(|| "www.google.com:443".to_string()),
                xver: 0,
                server_names: server_config.reality_server_names.clone(),
                private_key: server_config.private_key.clone().unwrap(),
                short_id: server_config.short_id.clone()
                    .map(|s| vec![s])
                    .unwrap_or_default(),
            })
        } else {
            None
        };

        let stream_settings = StreamSettings {
            network: "tcp".to_string(),
            security: "reality".to_string(),
            reality_settings,
            tcp_settings: Some(TcpSettings {
                header: Some(TcpHeader {
                    header_type: "none".to_string(),
                }),
            }),
        };

        let inbound = Inbound {
            tag: "vless-in".to_string(),
            port: server_config.port,
            protocol: "vless".to_string(),
            settings: inbound_settings,
            stream_settings: Some(stream_settings),
        };

        let outbound = Outbound {
            tag: "direct".to_string(),
            protocol: "freedom".to_string(),
            settings: Some(OutboundSettings {
                freedom: Some(HashMap::new()),
            }),
        };

        Ok(XrayConfig {
            log: LogConfig {
                level: "warning".to_string(),
                access: Some("/opt/v2ray/logs/access.log".to_string()),
                error: Some("/opt/v2ray/logs/error.log".to_string()),
            },
            inbounds: vec![inbound],
            outbounds: vec![outbound],
        })
    }
    
    pub fn generate_shadowsocks_config(
        users: &[User],
        server_config: &ServerConfig,
    ) -> Result<serde_json::Value> {
        let mut config = serde_json::json!({
            "server": server_config.host,
            "server_port": server_config.port,
            "method": "chacha20-ietf-poly1305",
            "mode": "tcp_and_udp",
            "fast_open": true,
            "users": []
        });
        
        let users_array: Vec<serde_json::Value> = users
            .iter()
            .filter(|u| u.is_active())
            .map(|u| serde_json::json!({
                "id": u.id,
                "password": u.config.private_key.clone().unwrap_or_else(|| u.id.clone()),
                "name": u.name
            }))
            .collect();
        
        config["users"] = serde_json::Value::Array(users_array);
        Ok(config)
    }
    
    pub fn save_config_to_file<P: AsRef<Path>>(
        config: &XrayConfig,
        path: P,
    ) -> Result<()> {
        let json = serde_json::to_string_pretty(config)?;
        std::fs::write(path, json)?;
        Ok(())
    }
    
    pub fn load_config_from_file<P: AsRef<Path>>(path: P) -> Result<XrayConfig> {
        let content = std::fs::read_to_string(path)?;
        let config: XrayConfig = serde_json::from_str(&content)?;
        Ok(config)
    }
    
    pub fn validate_config(config: &XrayConfig) -> Result<()> {
        if config.inbounds.is_empty() {
            return Err(UserError::InvalidConfiguration(
                "No inbounds configured".to_string()
            ));
        }
        
        if config.outbounds.is_empty() {
            return Err(UserError::InvalidConfiguration(
                "No outbounds configured".to_string()
            ));
        }
        
        for inbound in &config.inbounds {
            if inbound.port == 0 {
                return Err(UserError::InvalidConfiguration(
                    "Invalid inbound port".to_string()
                ));
            }
            
            if inbound.settings.clients.is_empty() {
                return Err(UserError::InvalidConfiguration(
                    "No clients configured for inbound".to_string()
                ));
            }
        }
        
        Ok(())
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "0.0.0.0".to_string(),
            port: 443,
            sni: None,
            public_key: None,
            private_key: None,
            short_id: None,
            reality_dest: Some("www.google.com:443".to_string()),
            reality_server_names: vec!["www.google.com".to_string()],
        }
    }
}