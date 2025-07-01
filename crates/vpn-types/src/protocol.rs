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
}

impl VpnProtocol {
    /// Get the default port for this protocol
    pub fn default_port(&self) -> u16 {
        match self {
            VpnProtocol::Vless => 8443,
            VpnProtocol::Outline => 8388,
            VpnProtocol::Wireguard => 51820,
            VpnProtocol::OpenVPN => 1194,
        }
    }

    /// Get the display name for this protocol
    pub fn display_name(&self) -> &'static str {
        match self {
            VpnProtocol::Vless => "VLESS",
            VpnProtocol::Outline => "Outline",
            VpnProtocol::Wireguard => "WireGuard",
            VpnProtocol::OpenVPN => "OpenVPN",
        }
    }

    /// Check if this protocol supports UDP
    pub fn supports_udp(&self) -> bool {
        matches!(self, VpnProtocol::Wireguard | VpnProtocol::OpenVPN)
    }

    /// Check if this protocol supports TCP
    pub fn supports_tcp(&self) -> bool {
        match self {
            VpnProtocol::Vless | VpnProtocol::Outline | VpnProtocol::OpenVPN => true,
            VpnProtocol::Wireguard => false,
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
            _ => Err(format!("Unknown protocol: {}", s)),
        }
    }
}