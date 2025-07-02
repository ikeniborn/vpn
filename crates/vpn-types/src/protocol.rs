//! VPN protocol types shared across crates

use serde::{Deserialize, Serialize};

/// VPN protocol types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
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
            VpnProtocol::Wireguard | VpnProtocol::OpenVPN | VpnProtocol::Socks5Proxy | VpnProtocol::ProxyServer
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