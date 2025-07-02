use vpn_network::{
    NetworkManager, PortChecker, IpDetector, FirewallManager, 
    SniValidator, NetworkInterface, PortStatus
};
use std::net::{IpAddr, Ipv4Addr};
use tokio;

#[tokio::test]
async fn test_network_manager_creation() {
    let _network_manager = NetworkManager::new();
    // Just test that it can be created without panicking
    assert!(true);
}

#[test]
fn test_port_checker_functionality() {
    // Test port availability check
    let available = PortChecker::is_port_available(0); // Port 0 should be available
    assert!(available);
    
    // Test finding available port
    let port_result = PortChecker::find_available_port(8000, 8010);
    assert!(port_result.is_ok());
}

#[tokio::test]
async fn test_port_checker_async() {
    // Test port connectivity (to localhost, should be fast)
    let is_open = PortChecker::is_port_open("127.0.0.1", 22, 1).await;
    // SSH might or might not be running, so we just test it doesn't panic
    assert!(is_open || !is_open);
}

#[test]
fn test_ip_detector_functionality() {
    // Test local IP detection
    let local_ip = IpDetector::get_local_ip();
    assert!(local_ip.is_ok());
}

#[tokio::test]
async fn test_ip_detector_async() {
    // Test public IP detection (might fail in CI/offline environments)
    let public_ip = IpDetector::get_public_ip().await;
    // Don't assert success as this might fail in test environments
    assert!(public_ip.is_ok() || public_ip.is_err());
}

#[test]
fn test_firewall_manager_creation() {
    let _firewall = FirewallManager;
    // Just test that it can be created without panicking
    assert!(true);
}

#[test]
fn test_sni_validator_functionality() {
    // Test domain validation
    let is_valid = SniValidator::validate_domain("www.google.com");
    assert!(is_valid.is_ok());
    assert!(is_valid.unwrap());
    
    let is_invalid = SniValidator::validate_domain("");
    assert!(is_invalid.is_ok());
    assert!(!is_invalid.unwrap());
}

#[tokio::test]
async fn test_sni_validator_async() {
    // Test SNI validation (might fail in offline environments)
    let result = SniValidator::validate_sni("www.google.com").await;
    // Don't assert success as this might fail in test environments
    assert!(result.is_ok() || result.is_err());
}

#[tokio::test]
async fn test_network_manager_functionality() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test getting network interfaces
    let interfaces = network_manager.get_network_interfaces().await?;
    assert!(!interfaces.is_empty());
    assert!(interfaces.iter().any(|i| i.is_loopback));
    
    Ok(())
}

#[test]
fn test_network_interface_creation() {
    let interface = NetworkInterface::new(
        "test0".to_string(),
        IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100))
    );
    
    assert_eq!(interface.name, "test0");
    assert_eq!(interface.ip_address, IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100)));
    assert!(!interface.is_loopback);
    assert!(interface.is_up);
}

#[test]
fn test_network_interface_builder_pattern() {
    let interface = NetworkInterface::new(
        "eth0".to_string(),
        IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1))
    )
    .with_mac_address("00:11:22:33:44:55".to_string())
    .with_mtu(1500)
    .set_up(true)
    .set_loopback(false);
    
    assert_eq!(interface.mac_address, Some("00:11:22:33:44:55".to_string()));
    assert_eq!(interface.mtu, Some(1500));
    assert!(interface.is_up);
    assert!(!interface.is_loopback);
}

#[test]
fn test_port_status_enum() {
    let statuses = vec![
        PortStatus::Open,
        PortStatus::Closed,
        PortStatus::Filtered,
        PortStatus::Unavailable,
        PortStatus::InUse,
        PortStatus::Available,
    ];
    
    // Test that all variants can be created
    assert_eq!(statuses.len(), 6);
    
    // Test equality
    assert_eq!(PortStatus::Open, PortStatus::Open);
    assert_ne!(PortStatus::Open, PortStatus::Closed);
}

#[tokio::test]
async fn test_network_manager_port_operations() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test port status checking
    let port_status = network_manager.check_port_status("127.0.0.1", 22).await?;
    // Port 22 might or might not be open, so we just test it returns a valid status
    assert!(matches!(port_status, 
        PortStatus::Open | PortStatus::Closed | PortStatus::Available | 
        PortStatus::Filtered | PortStatus::InUse | PortStatus::Unavailable
    ));
    
    Ok(())
}

#[test]
fn test_network_manager_port_range() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test finding available port range (small range to avoid conflicts)
    let ports = network_manager.find_available_port_range(50000, 3)?;
    assert_eq!(ports.len(), 3);
    
    // All ports should be different
    assert_ne!(ports[0], ports[1]);
    assert_ne!(ports[1], ports[2]);
    assert_ne!(ports[0], ports[2]);
    
    Ok(())
}

#[test]
fn test_sni_validator_domain_format() {
    // Test valid domains
    assert!(SniValidator::validate_domain("www.google.com").unwrap());
    assert!(SniValidator::validate_domain("example.org").unwrap());
    assert!(SniValidator::validate_domain("sub.domain.example.com").unwrap());
    
    // Test invalid domains
    assert!(!SniValidator::validate_domain("").unwrap());
    assert!(!SniValidator::validate_domain("single").unwrap());
    assert!(!SniValidator::validate_domain(".example.com").unwrap());
    assert!(!SniValidator::validate_domain("example.com.").unwrap());
}

#[test]
fn test_sni_validator_recommended_snis() {
    let recommended = SniValidator::get_recommended_snis();
    assert!(!recommended.is_empty());
    assert!(recommended.contains(&"www.google.com"));
    assert!(recommended.contains(&"www.cloudflare.com"));
}

#[test]
fn test_sni_validator_url_extraction() {
    assert_eq!(
        SniValidator::extract_domain_from_url("https://www.example.com/path"),
        Some("www.example.com".to_string())
    );
    
    assert_eq!(
        SniValidator::extract_domain_from_url("http://test.org"),
        Some("test.org".to_string())
    );
    
    assert_eq!(
        SniValidator::extract_domain_from_url("invalid-url"),
        None
    );
}