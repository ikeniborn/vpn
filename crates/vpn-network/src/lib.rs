pub mod error;
pub mod firewall;
pub mod ip;
pub mod manager;
pub mod port;
pub mod sni;
pub mod subnet;

#[cfg(test)]
pub mod proptest;

pub use error::{NetworkError, Result};
pub use firewall::{FirewallManager, FirewallRule};
pub use ip::IpDetector;
pub use manager::{NetworkInterface, NetworkInterfaceType, NetworkManager};
pub use port::{PortChecker, PortStatus};
pub use sni::SniValidator;
pub use subnet::{SubnetManager, VpnSubnet};
