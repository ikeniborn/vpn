use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VpnProtocol {
    Vless,
    Shadowsocks,
    Trojan,
    Vmess,
}

impl std::fmt::Display for VpnProtocol {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VpnProtocol::Vless => write!(f, "vless"),
            VpnProtocol::Shadowsocks => write!(f, "shadowsocks"),
            VpnProtocol::Trojan => write!(f, "trojan"),
            VpnProtocol::Vmess => write!(f, "vmess"),
        }
    }
}

impl std::str::FromStr for VpnProtocol {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "vless" => Ok(VpnProtocol::Vless),
            "shadowsocks" | "ss" => Ok(VpnProtocol::Shadowsocks),
            "trojan" => Ok(VpnProtocol::Trojan),
            "vmess" => Ok(VpnProtocol::Vmess),
            _ => Err(format!("Unknown VPN protocol: {}", s)),
        }
    }
}
