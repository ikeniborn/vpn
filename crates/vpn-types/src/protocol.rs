//! VPN protocol types shared across crates

use serde::{Deserialize, Deserializer, Serialize};
use std::str::FromStr;

/// VPN protocol types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum VpnProtocol {
    /// VLESS protocol (Xray)
    Vless,
    /// Outline/Shadowsocks protocol
    Outline,
    /// WireGuard protocol
    Wireguard,
    /// OpenVPN protocol
    OpenVPN,
    /// HTTP/HTTPS proxy server
    HttpProxy,
    /// SOCKS5 proxy server
    Socks5Proxy,
    /// Combined HTTP and SOCKS5 proxy
    ProxyServer,
}

impl VpnProtocol {
    /// Get the default port for this protocol
    pub fn default_port(&self) -> u16 {
        match self {
            VpnProtocol::Vless => 8443,
            VpnProtocol::Outline => 8388,
            VpnProtocol::Wireguard => 51820,
            VpnProtocol::OpenVPN => 1194,
            VpnProtocol::HttpProxy => 8080,
            VpnProtocol::Socks5Proxy => 1080,
            VpnProtocol::ProxyServer => 8080, // Primary HTTP port
        }
    }

    /// Get the display name for this protocol
    pub fn display_name(&self) -> &'static str {
        match self {
            VpnProtocol::Vless => "VLESS",
            VpnProtocol::Outline => "Outline",
            VpnProtocol::Wireguard => "WireGuard",
            VpnProtocol::OpenVPN => "OpenVPN",
            VpnProtocol::HttpProxy => "HTTP/HTTPS Proxy",
            VpnProtocol::Socks5Proxy => "SOCKS5 Proxy",
            VpnProtocol::ProxyServer => "Proxy Server (HTTP+SOCKS5)",
        }
    }

    /// Check if this protocol supports UDP
    pub fn supports_udp(&self) -> bool {
        matches!(
            self,
            VpnProtocol::Wireguard
                | VpnProtocol::OpenVPN
                | VpnProtocol::Socks5Proxy
                | VpnProtocol::ProxyServer
        )
    }

    /// Check if this protocol supports TCP
    pub fn supports_tcp(&self) -> bool {
        match self {
            VpnProtocol::Vless | VpnProtocol::Outline | VpnProtocol::OpenVPN => true,
            VpnProtocol::HttpProxy | VpnProtocol::Socks5Proxy | VpnProtocol::ProxyServer => true,
            VpnProtocol::Wireguard => false,
        }
    }

    /// Check if this is a proxy protocol
    pub fn is_proxy(&self) -> bool {
        matches!(
            self,
            VpnProtocol::HttpProxy | VpnProtocol::Socks5Proxy | VpnProtocol::ProxyServer
        )
    }

    /// Get protocol as string
    pub fn as_str(&self) -> &'static str {
        match self {
            VpnProtocol::Vless => "vless",
            VpnProtocol::Outline => "outline",
            VpnProtocol::Wireguard => "wireguard",
            VpnProtocol::OpenVPN => "openvpn",
            VpnProtocol::HttpProxy => "http-proxy",
            VpnProtocol::Socks5Proxy => "socks5-proxy",
            VpnProtocol::ProxyServer => "proxy-server",
        }
    }
}

impl std::fmt::Display for VpnProtocol {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

impl std::str::FromStr for VpnProtocol {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "vless" => Ok(VpnProtocol::Vless),
            "outline" | "shadowsocks" => Ok(VpnProtocol::Outline),
            "wireguard" | "wg" => Ok(VpnProtocol::Wireguard),
            "openvpn" => Ok(VpnProtocol::OpenVPN),
            "http" | "httpproxy" | "http-proxy" => Ok(VpnProtocol::HttpProxy),
            "socks" | "socks5" | "socks5proxy" | "socks5-proxy" => Ok(VpnProtocol::Socks5Proxy),
            "proxy" | "proxyserver" | "proxy-server" => Ok(VpnProtocol::ProxyServer),
            _ => Err(format!("Unknown protocol: {}", s)),
        }
    }
}

// Custom deserializer that accepts both uppercase and lowercase variants
impl<'de> Deserialize<'de> for VpnProtocol {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Self::from_str(&s).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_protocol_deserialization_lowercase() {
        let json = r#""vless""#;
        let protocol: VpnProtocol = serde_json::from_str(json).unwrap();
        assert_eq!(protocol, VpnProtocol::Vless);
    }

    #[test]
    fn test_protocol_deserialization_uppercase() {
        let json = r#""Vless""#;
        let protocol: VpnProtocol = serde_json::from_str(json).unwrap();
        assert_eq!(protocol, VpnProtocol::Vless);
    }

    #[test]
    fn test_protocol_deserialization_mixed_case() {
        let json = r#""VLESS""#;
        let protocol: VpnProtocol = serde_json::from_str(json).unwrap();
        assert_eq!(protocol, VpnProtocol::Vless);
    }

    #[test]
    fn test_protocol_serialization_is_lowercase() {
        let protocol = VpnProtocol::Vless;
        let json = serde_json::to_string(&protocol).unwrap();
        assert_eq!(json, r#""vless""#);
    }

    #[test]
    fn test_all_protocols_deserialize_case_insensitive() {
        let test_cases = vec![
            ("vless", VpnProtocol::Vless),
            ("Vless", VpnProtocol::Vless),
            ("VLESS", VpnProtocol::Vless),
            ("outline", VpnProtocol::Outline),
            ("Outline", VpnProtocol::Outline),
            ("OUTLINE", VpnProtocol::Outline),
            ("wireguard", VpnProtocol::Wireguard),
            ("WireGuard", VpnProtocol::Wireguard),
            ("WIREGUARD", VpnProtocol::Wireguard),
        ];

        for (input, expected) in test_cases {
            let json = format!(r#""{}""#, input);
            let protocol: VpnProtocol = serde_json::from_str(&json).unwrap();
            assert_eq!(protocol, expected, "Failed to deserialize {}", input);
        }
    }
}
