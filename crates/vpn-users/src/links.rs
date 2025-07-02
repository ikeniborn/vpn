use url::Url;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use crate::user::User;
use vpn_types::protocol::VpnProtocol;
use crate::config::ServerConfig;
use crate::error::{UserError, Result};

pub struct ConnectionLinkGenerator;

impl ConnectionLinkGenerator {
    pub fn generate(user: &User, server_config: &ServerConfig) -> Result<String> {
        match user.protocol {
            VpnProtocol::Vless => Self::generate_vless_link(user, server_config),
            VpnProtocol::Outline => Self::generate_shadowsocks_link(user, server_config),
            VpnProtocol::Wireguard => Self::generate_wireguard_link(user, server_config),
            VpnProtocol::OpenVPN => Self::generate_openvpn_link(user, server_config),
            VpnProtocol::HttpProxy => Self::generate_http_proxy_link(user, server_config),
            VpnProtocol::Socks5Proxy => Self::generate_socks5_link(user, server_config),
            VpnProtocol::ProxyServer => Self::generate_proxy_server_link(user, server_config),
        }
    }
    
    fn generate_vless_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        let mut url = Url::parse(&format!(
            "vless://{}@{}:{}",
            user.id,
            server_config.host,
            server_config.port
        )).map_err(|e| UserError::LinkGenerationError(e.to_string()))?;
        
        let mut query_pairs = url.query_pairs_mut();
        
        query_pairs.append_pair("type", "tcp");
        query_pairs.append_pair("security", "reality");
        query_pairs.append_pair("encryption", "none");
        
        if let Some(sni) = &server_config.sni {
            query_pairs.append_pair("sni", sni);
        }
        
        if let Some(flow) = &user.config.flow {
            query_pairs.append_pair("flow", flow);
        }
        
        if let Some(public_key) = &server_config.public_key {
            query_pairs.append_pair("pbk", public_key);
        }
        
        if let Some(short_id) = &server_config.short_id {
            query_pairs.append_pair("sid", short_id);
        }
        
        query_pairs.append_pair("fp", "chrome");
        
        drop(query_pairs);
        
        // Add fragment (user name)
        url.set_fragment(Some(&user.name));
        
        Ok(url.to_string())
    }
    
    fn generate_shadowsocks_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        let password = user.config.private_key.as_ref()
            .unwrap_or(&user.id);
        
        let method = "chacha20-ietf-poly1305";
        let user_info = format!("{}:{}", method, password);
        let encoded_user_info = URL_SAFE_NO_PAD.encode(user_info.as_bytes());
        
        let url = format!(
            "ss://{}@{}:{}#{}",
            encoded_user_info,
            server_config.host,
            server_config.port,
            urlencoding::encode(&user.name)
        );
        
        Ok(url)
    }
    
    fn _generate_trojan_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        let password = user.config.private_key.as_ref()
            .unwrap_or(&user.id);
        
        let mut url = Url::parse(&format!(
            "trojan://{}@{}:{}",
            password,
            server_config.host,
            server_config.port
        )).map_err(|e| UserError::LinkGenerationError(e.to_string()))?;
        
        let mut query_pairs = url.query_pairs_mut();
        
        query_pairs.append_pair("security", "tls");
        query_pairs.append_pair("type", "tcp");
        
        if let Some(sni) = &server_config.sni {
            query_pairs.append_pair("sni", sni);
        }
        
        drop(query_pairs);
        url.set_fragment(Some(&user.name));
        
        Ok(url.to_string())
    }
    
    fn _generate_vmess_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        let vmess_config = serde_json::json!({
            "v": "2",
            "ps": user.name,
            "add": server_config.host,
            "port": server_config.port.to_string(),
            "id": user.id,
            "aid": "0",
            "net": user.config.network,
            "type": user.config.header_type.as_deref().unwrap_or("none"),
            "host": server_config.sni.as_deref().unwrap_or(""),
            "path": user.config.path.as_deref().unwrap_or("/"),
            "tls": if user.config.security == "tls" { "tls" } else { "" },
            "sni": server_config.sni.as_deref().unwrap_or(""),
            "alpn": ""
        });
        
        let json_str = serde_json::to_string(&vmess_config)
            .map_err(|e| UserError::LinkGenerationError(e.to_string()))?;
        
        let encoded = URL_SAFE_NO_PAD.encode(json_str.as_bytes());
        Ok(format!("vmess://{}", encoded))
    }
    
    fn generate_wireguard_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        // WireGuard doesn't have a standard URI format, return config instructions
        Ok(format!(
            "wireguard://{}:{}?publickey={}&privatekey={}",
            server_config.host,
            server_config.port,
            server_config.public_key.as_deref().unwrap_or("MISSING_PUBLIC_KEY"),
            user.config.private_key.as_deref().unwrap_or("MISSING_PRIVATE_KEY")
        ))
    }
    
    fn generate_openvpn_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        // OpenVPN doesn't have a standard URI format, return config file path
        Ok(format!(
            "openvpn://{}@{}:{}",
            user.name,
            server_config.host,
            server_config.port
        ))
    }
    
    fn generate_http_proxy_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        Ok(format!(
            "http://{}:{}@{}:{}",
            user.name,
            user.config.private_key.as_deref().unwrap_or(&user.id),
            server_config.host,
            server_config.port
        ))
    }
    
    fn generate_socks5_link(user: &User, server_config: &ServerConfig) -> Result<String> {
        Ok(format!(
            "socks5://{}:{}@{}:{}",
            user.name,
            user.config.private_key.as_deref().unwrap_or(&user.id),
            server_config.host,
            server_config.port
        ))
    }
    
    fn generate_proxy_server_link(_user: &User, server_config: &ServerConfig) -> Result<String> {
        // Return both HTTP and SOCKS5 endpoints
        Ok(format!(
            "http://{}:{} | socks5://{}:{}",
            server_config.host,
            server_config.port,
            server_config.host,
            server_config.port.saturating_add(1000) // SOCKS5 on port+1000
        ))
    }
    
    pub fn parse_vless_link(link: &str) -> Result<(String, String, u16, Vec<(String, String)>)> {
        let url = Url::parse(link)
            .map_err(|e| UserError::LinkGenerationError(e.to_string()))?;
        
        if url.scheme() != "vless" {
            return Err(UserError::LinkGenerationError(
                "Not a VLESS link".to_string()
            ));
        }
        
        let user_id = url.username().to_string();
        let host = url.host_str()
            .ok_or_else(|| UserError::LinkGenerationError("No host in URL".to_string()))?
            .to_string();
        let port = url.port().unwrap_or(443);
        
        let params: Vec<(String, String)> = url.query_pairs()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        
        Ok((user_id, host, port, params))
    }
    
    pub fn generate_subscription_link(users: &[User], server_config: &ServerConfig) -> Result<String> {
        let mut links = Vec::new();
        
        for user in users {
            if user.is_active() {
                let link = Self::generate(user, server_config)?;
                links.push(link);
            }
        }
        
        let subscription_content = links.join("\n");
        let encoded = URL_SAFE_NO_PAD.encode(subscription_content.as_bytes());
        
        Ok(encoded)
    }
    
    pub fn generate_clash_config(users: &[User], server_config: &ServerConfig) -> Result<String> {
        let mut proxies = Vec::new();
        let mut proxy_names = Vec::new();
        
        for user in users {
            if user.is_active() {
                let proxy_name = format!("{}-{}", user.name, user.protocol.as_str());
                proxy_names.push(proxy_name.clone());
                
                let proxy = match user.protocol {
                    VpnProtocol::Vless => {
                        serde_json::json!({
                            "name": proxy_name,
                            "type": "vless",
                            "server": server_config.host,
                            "port": server_config.port,
                            "uuid": user.id,
                            "flow": user.config.flow.as_deref().unwrap_or("xtls-rprx-vision"),
                            "tls": true,
                            "reality-opts": {
                                "public-key": server_config.public_key.as_deref().unwrap_or(""),
                                "short-id": server_config.short_id.as_deref().unwrap_or("")
                            },
                            "servername": server_config.sni.as_deref().unwrap_or("www.google.com")
                        })
                    }
                    VpnProtocol::Outline => {
                        serde_json::json!({
                            "name": proxy_name,
                            "type": "ss",
                            "server": server_config.host,
                            "port": server_config.port,
                            "cipher": "chacha20-ietf-poly1305",
                            "password": user.config.private_key.as_deref().unwrap_or(&user.id)
                        })
                    }
                    _ => continue, // Skip unsupported protocols for now
                };
                
                proxies.push(proxy);
            }
        }
        
        let clash_config = serde_json::json!({
            "proxies": proxies,
            "proxy-groups": [{
                "name": "VPN",
                "type": "select",
                "proxies": proxy_names
            }]
        });
        
        serde_yaml::to_string(&clash_config)
            .map_err(|e| UserError::LinkGenerationError(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::user::User;
use vpn_types::protocol::VpnProtocol;
    
    #[test]
    fn test_vless_link_generation() {
        let user = User::new("test-user".to_string(), VpnProtocol::Vless);
        let server_config = ServerConfig::default();
        
        let link = ConnectionLinkGenerator::generate_vless_link(&user, &server_config).unwrap();
        
        assert!(link.starts_with("vless://"));
        assert!(link.contains(&user.id));
        assert!(link.contains(&server_config.host));
    }
    
    #[test]
    fn test_link_parsing() {
        let test_link = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?type=tcp&security=reality&encryption=none#test";
        
        let (user_id, host, port, _params) = 
            ConnectionLinkGenerator::parse_vless_link(test_link).unwrap();
        
        assert_eq!(user_id, "550e8400-e29b-41d4-a716-446655440000");
        assert_eq!(host, "example.com");
        assert_eq!(port, 443);
    }
}