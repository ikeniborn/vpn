use std::net::{TcpListener, SocketAddr, IpAddr, Ipv4Addr};
use tokio::net::TcpStream;
use tokio::time::{timeout, Duration};
use crate::error::{NetworkError, Result};

pub struct PortChecker;

impl PortChecker {
    pub fn is_port_available(port: u16) -> bool {
        let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port);
        TcpListener::bind(addr).is_ok()
    }
    
    pub async fn is_port_open(host: &str, port: u16, timeout_secs: u64) -> bool {
        let addr = format!("{}:{}", host, port);
        let duration = Duration::from_secs(timeout_secs);
        
        match timeout(duration, TcpStream::connect(&addr)).await {
            Ok(Ok(_)) => true,
            _ => false,
        }
    }
    
    pub fn find_available_port(start: u16, end: u16) -> Result<u16> {
        for port in start..=end {
            if Self::is_port_available(port) {
                return Ok(port);
            }
        }
        Err(NetworkError::PortInUse(start))
    }
    
    pub fn find_random_available_port(min: u16, max: u16) -> Result<u16> {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let mut attempts = 0;
        const MAX_ATTEMPTS: u32 = 100;
        
        while attempts < MAX_ATTEMPTS {
            let port = rng.gen_range(min..=max);
            if Self::is_port_available(port) {
                return Ok(port);
            }
            attempts += 1;
        }
        
        Self::find_available_port(min, max)
    }
    
    pub fn validate_port(port: u16) -> Result<()> {
        if port == 0 {
            return Err(NetworkError::InvalidPort(port));
        }
        
        const RESERVED_PORTS: &[u16] = &[22, 80, 443];
        if RESERVED_PORTS.contains(&port) {
            return Err(NetworkError::InvalidPort(port));
        }
        
        Ok(())
    }
    
    pub async fn wait_for_port(host: &str, port: u16, timeout_secs: u64) -> Result<()> {
        let start = std::time::Instant::now();
        let duration = Duration::from_secs(timeout_secs);
        
        while start.elapsed() < duration {
            if Self::is_port_open(host, port, 1).await {
                return Ok(());
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        
        Err(NetworkError::PortInUse(port))
    }
    
    pub fn check_port_range(start: u16, end: u16) -> Vec<u16> {
        (start..=end)
            .filter(|&port| Self::is_port_available(port))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_port_availability() {
        let available = PortChecker::find_random_available_port(30000, 40000)
            .expect("Failed to find available port");
        assert!(PortChecker::is_port_available(available));
    }
    
    #[tokio::test]
    async fn test_port_open_check() {
        assert!(!PortChecker::is_port_open("127.0.0.1", 65535, 1).await);
    }
}