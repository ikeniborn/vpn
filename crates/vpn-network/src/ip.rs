use local_ip_address::local_ip;
use reqwest;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::time::Duration;
use crate::error::{NetworkError, Result};

pub struct IpDetector;

impl IpDetector {
    pub fn get_local_ip() -> Result<IpAddr> {
        local_ip().map_err(|e| NetworkError::IpDetectionError(e.to_string()))
    }
    
    pub async fn get_public_ip() -> Result<IpAddr> {
        let services = [
            "https://api.ipify.org",
            "https://ipinfo.io/ip",
            "https://checkip.amazonaws.com",
            "https://icanhazip.com",
        ];
        
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()?;
        
        for service in &services {
            match Self::fetch_ip_from_service(&client, service).await {
                Ok(ip) => return Ok(ip),
                Err(_) => continue,
            }
        }
        
        Err(NetworkError::IpDetectionError(
            "Failed to detect public IP from all services".to_string()
        ))
    }
    
    async fn fetch_ip_from_service(client: &reqwest::Client, url: &str) -> Result<IpAddr> {
        let response = client.get(url).send().await?;
        let text = response.text().await?;
        let ip_str = text.trim();
        
        ip_str.parse::<IpAddr>()
            .map_err(|e| NetworkError::IpDetectionError(e.to_string()))
    }
    
    pub fn is_private_ip(ip: &IpAddr) -> bool {
        match ip {
            IpAddr::V4(ipv4) => {
                ipv4.is_private() || 
                ipv4.is_loopback() ||
                ipv4.is_link_local()
            }
            IpAddr::V6(ipv6) => {
                ipv6.is_loopback() ||
                ipv6.is_unique_local()
            }
        }
    }
    
    pub fn get_all_local_ips() -> Result<Vec<IpAddr>> {
        use pnet::datalink;
        
        let mut ips = Vec::new();
        
        for interface in datalink::interfaces() {
            if interface.is_up() && !interface.is_loopback() {
                for ip_network in interface.ips {
                    ips.push(ip_network.ip());
                }
            }
        }
        
        if ips.is_empty() {
            return Err(NetworkError::IpDetectionError(
                "No network interfaces found".to_string()
            ));
        }
        
        Ok(ips)
    }
    
    pub fn get_interface_by_name(name: &str) -> Result<Vec<IpAddr>> {
        use pnet::datalink;
        
        let interfaces = datalink::interfaces();
        let interface = interfaces.into_iter()
            .find(|iface| iface.name == name)
            .ok_or_else(|| NetworkError::InterfaceError(
                format!("Interface {} not found", name)
            ))?;
        
        let ips: Vec<IpAddr> = interface.ips
            .into_iter()
            .map(|ip_network| ip_network.ip())
            .collect();
        
        if ips.is_empty() {
            return Err(NetworkError::InterfaceError(
                format!("No IPs assigned to interface {}", name)
            ));
        }
        
        Ok(ips)
    }
    
    pub fn is_valid_ipv4(ip: &str) -> bool {
        ip.parse::<Ipv4Addr>().is_ok()
    }
    
    pub fn is_valid_ipv6(ip: &str) -> bool {
        ip.parse::<Ipv6Addr>().is_ok()
    }
    
    pub fn is_valid_ip(ip: &str) -> bool {
        ip.parse::<IpAddr>().is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_local_ip_detection() {
        let ip = IpDetector::get_local_ip();
        assert!(ip.is_ok());
    }
    
    #[test]
    fn test_ip_validation() {
        assert!(IpDetector::is_valid_ipv4("192.168.1.1"));
        assert!(!IpDetector::is_valid_ipv4("256.256.256.256"));
        assert!(IpDetector::is_valid_ipv6("::1"));
        assert!(!IpDetector::is_valid_ipv6("invalid"));
    }
    
    #[test]
    fn test_private_ip_detection() {
        let private_ip = "192.168.1.1".parse::<IpAddr>().expect("Valid private IP");
        let public_ip = "8.8.8.8".parse::<IpAddr>().expect("Valid public IP");
        
        assert!(IpDetector::is_private_ip(&private_ip));
        assert!(!IpDetector::is_private_ip(&public_ip));
    }
}