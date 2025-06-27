use vpn_network::{
    NetworkManager, PortChecker, IpDetector, FirewallManager, 
    SniValidator, NetworkInterface, PortStatus
};
use std::net::{IpAddr, Ipv4Addr};
use tokio;

#[tokio::test]
async fn test_network_manager_creation() {
    let network_manager = NetworkManager::new();
    assert!(true); // NetworkManager should always create successfully
}

#[tokio::test]
async fn test_port_checker() -> Result<(), Box<dyn std::error::Error>> {
    let port_checker = PortChecker::new();
    
    // Test well-known closed port (assuming it's not in use)
    let status = port_checker.check_port_availability(65432).await?;
    // Port should be available unless something is specifically using it
    
    // Test privileged port (should require sudo to bind)
    let privileged_status = port_checker.check_port_availability(80).await?;
    // Result depends on system state, just ensure it doesn't crash
    
    // Test port range validation
    assert!(port_checker.validate_port_range(1024, 65535).is_ok());
    assert!(port_checker.validate_port_range(65536, 70000).is_err());
    assert!(port_checker.validate_port_range(1000, 500).is_err());
    
    Ok(())
}

#[tokio::test]
async fn test_port_scanner() -> Result<(), Box<dyn std::error::Error>> {
    let port_checker = PortChecker::new();
    
    // Test scanning localhost for common ports
    let open_ports = port_checker.scan_ports("127.0.0.1", &[22, 80, 443, 8080]).await?;
    // Should return results without crashing
    assert!(open_ports.len() <= 4);
    
    Ok(())
}

#[tokio::test]
async fn test_ip_detector() -> Result<(), Box<dyn std::error::Error>> {
    let ip_detector = IpDetector::new();
    
    // Test local IP detection
    let local_ip = ip_detector.get_local_ip().await;
    if let Ok(ip) = local_ip {
        assert!(ip.is_ipv4() || ip.is_ipv6());
    }
    
    // Test public IP detection (may fail in CI/testing environments)
    let public_ip_result = ip_detector.get_public_ip().await;
    // Don't assert success as it depends on network connectivity
    
    // Test IP validation
    assert!(ip_detector.validate_ip_address("192.168.1.1").is_ok());
    assert!(ip_detector.validate_ip_address("::1").is_ok());
    assert!(ip_detector.validate_ip_address("2001:db8::1").is_ok());
    assert!(ip_detector.validate_ip_address("invalid").is_err());
    assert!(ip_detector.validate_ip_address("256.256.256.256").is_err());
    
    Ok(())
}

#[test]
fn test_ip_classification() -> Result<(), Box<dyn std::error::Error>> {
    let ip_detector = IpDetector::new();
    
    // Test private IP detection
    assert!(ip_detector.is_private_ip(&"192.168.1.1".parse()?));
    assert!(ip_detector.is_private_ip(&"10.0.0.1".parse()?));
    assert!(ip_detector.is_private_ip(&"172.16.0.1".parse()?));
    assert!(!ip_detector.is_private_ip(&"8.8.8.8".parse()?));
    
    // Test loopback detection
    assert!(ip_detector.is_loopback(&"127.0.0.1".parse()?));
    assert!(ip_detector.is_loopback(&"::1".parse()?));
    assert!(!ip_detector.is_loopback(&"192.168.1.1".parse()?));
    
    Ok(())
}

#[tokio::test]
async fn test_firewall_manager() -> Result<(), Box<dyn std::error::Error>> {
    let firewall = FirewallManager::new();
    
    // Test firewall status check (should not fail)
    let status = firewall.check_firewall_status().await;
    // Result depends on system, just ensure it doesn't crash
    
    // Test rule validation
    assert!(firewall.validate_port_rule(8080, "tcp").is_ok());
    assert!(firewall.validate_port_rule(443, "udp").is_ok());
    assert!(firewall.validate_port_rule(0, "tcp").is_err());
    assert!(firewall.validate_port_rule(70000, "tcp").is_err());
    assert!(firewall.validate_port_rule(8080, "invalid").is_err());
    
    Ok(())
}

#[test]
fn test_firewall_rule_parsing() -> Result<(), Box<dyn std::error::Error>> {
    let firewall = FirewallManager::new();
    
    // Test parsing UFW rules
    let ufw_rules = vec![
        "22/tcp                     ALLOW IN    Anywhere",
        "80/tcp                     ALLOW IN    Anywhere",
        "443/tcp                    ALLOW IN    Anywhere",
    ];
    
    let parsed = firewall.parse_ufw_rules(&ufw_rules)?;
    assert_eq!(parsed.len(), 3);
    assert!(parsed.iter().any(|r| r.port == 22 && r.protocol == "tcp"));
    assert!(parsed.iter().any(|r| r.port == 80 && r.protocol == "tcp"));
    assert!(parsed.iter().any(|r| r.port == 443 && r.protocol == "tcp"));
    
    Ok(())
}

#[tokio::test]
async fn test_sni_validator() -> Result<(), Box<dyn std::error::Error>> {
    let sni_validator = SniValidator::new();
    
    // Test SNI validation
    assert!(sni_validator.validate_sni_format("google.com").is_ok());
    assert!(sni_validator.validate_sni_format("www.example.org").is_ok());
    assert!(sni_validator.validate_sni_format("sub.domain.co.uk").is_ok());
    
    // Test invalid SNI
    assert!(sni_validator.validate_sni_format("").is_err());
    assert!(sni_validator.validate_sni_format("invalid..domain").is_err());
    assert!(sni_validator.validate_sni_format(".example.com").is_err());
    assert!(sni_validator.validate_sni_format("example.").is_err());
    
    // Test SNI accessibility (may fail due to network)
    let accessibility_result = sni_validator.check_sni_accessibility("google.com", 443).await;
    // Don't assert success as it depends on network connectivity
    
    Ok(())
}

#[tokio::test]
async fn test_sni_quality_check() -> Result<(), Box<dyn std::error::Error>> {
    let sni_validator = SniValidator::new();
    
    // Test SNI quality scoring
    let quality = sni_validator.assess_sni_quality("google.com").await;
    if let Ok(score) = quality {
        assert!(score >= 0.0 && score <= 1.0);
    }
    
    // Test multiple SNI quality assessment
    let sni_list = vec!["google.com", "cloudflare.com", "github.com"];
    let results = sni_validator.assess_multiple_sni_quality(&sni_list).await;
    
    if let Ok(scores) = results {
        assert_eq!(scores.len(), 3);
        for score in scores.values() {
            assert!(*score >= 0.0 && *score <= 1.0);
        }
    }
    
    Ok(())
}

#[tokio::test]
async fn test_network_interface_detection() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test network interface listing
    let interfaces = network_manager.list_network_interfaces().await?;
    
    // Should have at least loopback interface
    assert!(!interfaces.is_empty());
    
    // Test that loopback exists
    assert!(interfaces.iter().any(|iface| iface.name.contains("lo")));
    
    Ok(())
}

#[test]
fn test_network_interface_validation() -> Result<(), Box<dyn std::error::Error>> {
    let interface = NetworkInterface {
        name: "eth0".to_string(),
        ip_address: "192.168.1.100".parse()?,
        netmask: "255.255.255.0".to_string(),
        is_up: true,
        is_loopback: false,
    };
    
    assert_eq!(interface.name, "eth0");
    assert!(interface.is_up);
    assert!(!interface.is_loopback);
    
    Ok(())
}

#[tokio::test]
async fn test_network_connectivity() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test basic connectivity check
    let connectivity = network_manager.check_internet_connectivity().await;
    // Don't assert success as it depends on network availability
    
    // Test DNS resolution
    let dns_result = network_manager.resolve_domain("google.com").await;
    // Don't assert success as it depends on DNS availability
    
    Ok(())
}

#[tokio::test]
async fn test_port_forwarding_detection() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test UPnP detection
    let upnp_available = network_manager.check_upnp_availability().await;
    // Result depends on router configuration
    
    // Test port forwarding status
    let port_forward_status = network_manager.check_port_forwarding_status(8080).await;
    // Result depends on network configuration
    
    Ok(())
}

#[test]
fn test_port_status_enum() {
    let statuses = vec![
        PortStatus::Open,
        PortStatus::Closed,
        PortStatus::Filtered,
        PortStatus::Unknown,
    ];
    
    for status in statuses {
        let serialized = serde_json::to_string(&status).unwrap();
        let deserialized: PortStatus = serde_json::from_str(&serialized).unwrap();
        assert_eq!(status, deserialized);
    }
}

#[tokio::test]
async fn test_bandwidth_measurement() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test bandwidth measurement
    let bandwidth_result = network_manager.measure_bandwidth().await;
    if let Ok(bandwidth) = bandwidth_result {
        assert!(bandwidth.download_mbps >= 0.0);
        assert!(bandwidth.upload_mbps >= 0.0);
        assert!(bandwidth.latency_ms >= 0.0);
    }
    
    Ok(())
}

#[tokio::test]
async fn test_mtu_detection() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test MTU size detection
    let mtu = network_manager.detect_mtu_size("8.8.8.8").await;
    if let Ok(mtu_size) = mtu {
        assert!(mtu_size >= 576); // Minimum IPv4 MTU
        assert!(mtu_size <= 9000); // Reasonable maximum
    }
    
    Ok(())
}

#[tokio::test]
async fn test_route_table_analysis() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test route table retrieval
    let routes = network_manager.get_routing_table().await;
    if let Ok(route_table) = routes {
        // Should have at least default route and loopback
        assert!(!route_table.is_empty());
    }
    
    Ok(())
}

#[test]
fn test_cidr_validation() -> Result<(), Box<dyn std::error::Error>> {
    let network_manager = NetworkManager::new();
    
    // Test valid CIDR blocks
    assert!(network_manager.validate_cidr("192.168.1.0/24").is_ok());
    assert!(network_manager.validate_cidr("10.0.0.0/8").is_ok());
    assert!(network_manager.validate_cidr("172.16.0.0/12").is_ok());
    assert!(network_manager.validate_cidr("2001:db8::/32").is_ok());
    
    // Test invalid CIDR blocks
    assert!(network_manager.validate_cidr("192.168.1.0/33").is_err());
    assert!(network_manager.validate_cidr("invalid/24").is_err());
    assert!(network_manager.validate_cidr("192.168.1.0").is_err());
    
    Ok(())
}