//! Network-related types shared across crates

use serde::{Deserialize, Serialize};
use std::net::{IpAddr, SocketAddr};

/// Network protocol
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NetworkProtocol {
    Tcp,
    Udp,
}

/// Port range for network services
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortRange {
    pub start: u16,
    pub end: u16,
}

impl PortRange {
    /// Create a new port range
    pub fn new(start: u16, end: u16) -> Self {
        Self { start, end }
    }

    /// Create a single port range
    pub fn single(port: u16) -> Self {
        Self { start: port, end: port }
    }

    /// Check if a port is within this range
    pub fn contains(&self, port: u16) -> bool {
        port >= self.start && port <= self.end
    }

    /// Get the number of ports in this range
    pub fn count(&self) -> u16 {
        self.end - self.start + 1
    }
}

/// Network interface information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInterface {
    pub name: String,
    pub addresses: Vec<IpAddr>,
    pub is_up: bool,
    pub is_loopback: bool,
}

/// Firewall rule direction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Inbound,
    Outbound,
}

/// Basic firewall rule
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FirewallRule {
    pub name: String,
    pub direction: Direction,
    pub protocol: NetworkProtocol,
    pub port: PortRange,
    pub source: Option<IpAddr>,
    pub destination: Option<IpAddr>,
    pub action: FirewallAction,
}

/// Firewall action
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FirewallAction {
    Allow,
    Deny,
    Reject,
}

/// Network bandwidth limits
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct BandwidthLimit {
    /// Upload speed in bytes per second (0 = unlimited)
    pub upload: u64,
    /// Download speed in bytes per second (0 = unlimited)
    pub download: u64,
}

impl Default for BandwidthLimit {
    fn default() -> Self {
        Self {
            upload: 0,
            download: 0,
        }
    }
}

impl BandwidthLimit {
    /// Check if bandwidth is unlimited
    pub fn is_unlimited(&self) -> bool {
        self.upload == 0 && self.download == 0
    }
}

/// Connection information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionInfo {
    pub protocol: NetworkProtocol,
    pub local_addr: SocketAddr,
    pub remote_addr: SocketAddr,
    pub state: ConnectionState,
}

/// Connection state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionState {
    Connecting,
    Connected,
    Disconnecting,
    Disconnected,
    Error,
}