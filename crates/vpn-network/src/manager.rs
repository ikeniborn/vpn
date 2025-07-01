use std::net::{IpAddr, Ipv4Addr};
use crate::port::{PortChecker, PortStatus};
use crate::ip::IpDetector;
use crate::firewall::FirewallManager;
use crate::sni::SniValidator;
use crate::subnet::SubnetManager;
use crate::error::{NetworkError, Result};
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInterface {
    pub name: String,
    pub ip_address: IpAddr,
    pub mac_address: Option<String>,
    pub is_up: bool,
    pub is_loopback: bool,
    pub mtu: Option<u32>,
    pub interface_type: NetworkInterfaceType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NetworkInterfaceType {
    Ethernet,
    Wireless,
    Loopback,
    Tunnel,
    Bridge,
    Virtual,
    Unknown,
}

pub struct NetworkManager {
    pub port_checker: PortChecker,
    pub ip_detector: IpDetector,
    pub firewall_manager: FirewallManager,
    pub sni_validator: SniValidator,
    pub subnet_manager: SubnetManager,
}

impl NetworkManager {
    pub fn new() -> Self {
        Self {
            port_checker: PortChecker,
            ip_detector: IpDetector,
            firewall_manager: FirewallManager,
            sni_validator: SniValidator,
            subnet_manager: SubnetManager,
        }
    }
    
    pub async fn get_network_interfaces(&self) -> Result<Vec<NetworkInterface>> {
        // Mock implementation for testing purposes
        Ok(vec![
            NetworkInterface {
                name: "lo".to_string(),
                ip_address: IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)),
                mac_address: None,
                is_up: true,
                is_loopback: true,
                mtu: Some(65536),
                interface_type: NetworkInterfaceType::Loopback,
            },
            NetworkInterface {
                name: "eth0".to_string(),
                ip_address: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100)),
                mac_address: Some("00:11:22:33:44:55".to_string()),
                is_up: true,
                is_loopback: false,
                mtu: Some(1500),
                interface_type: NetworkInterfaceType::Ethernet,
            },
        ])
    }
    
    pub async fn check_port_status(&self, host: &str, port: u16) -> Result<PortStatus> {
        if PortChecker::is_port_available(port) {
            Ok(PortStatus::Available)
        } else if PortChecker::is_port_open(host, port, 3).await {
            Ok(PortStatus::Open)
        } else {
            Ok(PortStatus::Closed)
        }
    }
    
    pub async fn get_public_ip(&self) -> Result<IpAddr> {
        IpDetector::get_public_ip().await
    }
    
    pub fn get_local_ip(&self) -> Result<IpAddr> {
        IpDetector::get_local_ip()
    }
    
    pub fn validate_sni(&self, domain: &str) -> Result<bool> {
        SniValidator::validate_domain(domain)
    }
    
    pub async fn test_network_connectivity(&self, host: &str, port: u16) -> Result<bool> {
        Ok(PortChecker::is_port_open(host, port, 5).await)
    }
    
    pub fn find_available_port_range(&self, start: u16, count: u16) -> Result<Vec<u16>> {
        let mut available_ports = Vec::new();
        let mut current_port = start;
        
        while available_ports.len() < count as usize && current_port < 65535 {
            if PortChecker::is_port_available(current_port) {
                available_ports.push(current_port);
            }
            current_port += 1;
        }
        
        if available_ports.len() == count as usize {
            Ok(available_ports)
        } else {
            Err(NetworkError::PortInUse(start))
        }
    }
}

impl Default for NetworkManager {
    fn default() -> Self {
        Self::new()
    }
}

impl NetworkInterface {
    pub fn new(name: String, ip_address: IpAddr) -> Self {
        Self {
            name,
            ip_address,
            mac_address: None,
            is_up: true,
            is_loopback: false,
            mtu: Some(1500),
            interface_type: NetworkInterfaceType::Unknown,
        }
    }
    
    pub fn with_mac_address(mut self, mac: String) -> Self {
        self.mac_address = Some(mac);
        self
    }
    
    pub fn with_interface_type(mut self, interface_type: NetworkInterfaceType) -> Self {
        self.interface_type = interface_type;
        self
    }
    
    pub fn with_mtu(mut self, mtu: u32) -> Self {
        self.mtu = Some(mtu);
        self
    }
    
    pub fn set_up(mut self, is_up: bool) -> Self {
        self.is_up = is_up;
        self
    }
    
    pub fn set_loopback(mut self, is_loopback: bool) -> Self {
        self.is_loopback = is_loopback;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_network_interface_creation() {
        let interface = NetworkInterface::new(
            "test0".to_string(),
            IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1))
        );
        
        assert_eq!(interface.name, "test0");
        assert_eq!(interface.ip_address, IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1)));
        assert!(!interface.is_loopback);
        assert!(interface.is_up);
    }
    
    #[test]
    fn test_network_interface_builder() {
        let interface = NetworkInterface::new(
            "eth0".to_string(),
            IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100))
        )
        .with_mac_address("00:11:22:33:44:55".to_string())
        .with_interface_type(NetworkInterfaceType::Ethernet)
        .with_mtu(1500);
        
        assert_eq!(interface.mac_address, Some("00:11:22:33:44:55".to_string()));
        assert!(matches!(interface.interface_type, NetworkInterfaceType::Ethernet));
        assert_eq!(interface.mtu, Some(1500));
    }
    
    #[tokio::test]
    async fn test_network_manager_creation() {
        let manager = NetworkManager::new();
        // Just test that it can be created without panicking
        assert!(true);
    }
}