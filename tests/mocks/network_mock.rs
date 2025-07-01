//! Mock implementation for network operations

use super::{MockService, MockError, MockStats, MockConfig, BaseMockService, MockState, MockNetworkInterface};
use async_trait::async_trait;
use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};

/// Mock network service for testing network operations
pub struct MockNetworkService {
    base: BaseMockService,
    interfaces: HashMap<String, MockNetworkInterface>,
    port_bindings: HashMap<u16, String>, // port -> service_name
    firewall_rules: Vec<MockFirewallRule>,
    dns_records: HashMap<String, String>, // hostname -> ip
}

impl MockNetworkService {
    pub fn new(config: MockConfig, state: Arc<Mutex<MockState>>) -> Self {
        let mut service = Self {
            base: BaseMockService::new(config, state),
            interfaces: HashMap::new(),
            port_bindings: HashMap::new(),
            firewall_rules: Vec::new(),
            dns_records: HashMap::new(),
        };

        // Pre-populate with default network interfaces
        service.add_mock_interface("lo", "127.0.0.1");
        service.add_mock_interface("eth0", "192.168.1.100");
        service.add_mock_interface("docker0", "172.17.0.1");
        service.add_mock_interface("vpn0", "10.8.0.1");

        // Pre-populate DNS records
        service.dns_records.insert("localhost".to_string(), "127.0.0.1".to_string());
        service.dns_records.insert("vpn-server".to_string(), "192.168.1.100".to_string());
        service.dns_records.insert("vpn-proxy".to_string(), "192.168.1.101".to_string());

        // Pre-populate some port bindings
        service.port_bindings.insert(22, "ssh".to_string());
        service.port_bindings.insert(80, "http".to_string());
        service.port_bindings.insert(443, "https".to_string());
        service.port_bindings.insert(8080, "vpn-proxy".to_string());

        service
    }

    fn add_mock_interface(&mut self, name: &str, ip: &str) {
        let interface = MockNetworkInterface::new(name, ip);
        self.interfaces.insert(name.to_string(), interface.clone());

        // Also store in shared state
        if let Ok(mut state) = self.base.state.lock() {
            state.network_interfaces.insert(name.to_string(), interface);
        }
    }

    /// Check if a port is available
    pub async fn is_port_available(&mut self, port: u16) -> Result<bool, MockError> {
        self.base.simulate_operation("is_port_available").await?;

        // Reserved ports are not available
        if port < 1024 && port != 0 {
            return Ok(false);
        }

        // Check if port is already bound
        Ok(!self.port_bindings.contains_key(&port))
    }

    /// Check if a port is open on a host
    pub async fn is_port_open(&mut self, host: &str, port: u16, timeout_ms: u64) -> Result<bool, MockError> {
        self.base.simulate_operation("is_port_open").await?;

        // Simulate network latency
        tokio::time::sleep(std::time::Duration::from_millis(timeout_ms.min(100))).await;

        // Localhost is always reachable
        if host == "127.0.0.1" || host == "localhost" {
            return Ok(self.port_bindings.contains_key(&port));
        }

        // Check if host exists in our DNS records
        if !self.dns_records.contains_key(host) && host.parse::<IpAddr>().is_err() {
            return Err(MockError::NetworkError(format!("Host not found: {}", host)));
        }

        // Simulate some ports being open based on common services
        let is_open = match port {
            22 => true,   // SSH
            80 => true,   // HTTP
            443 => true,  // HTTPS
            8080 => true, // VPN proxy
            _ => rand::random::<f64>() > 0.7, // 30% chance for other ports
        };

        Ok(is_open)
    }

    /// Find an available port in a range
    pub async fn find_available_port(&mut self, start: u16, end: u16) -> Result<u16, MockError> {
        self.base.simulate_operation("find_available_port").await?;

        for port in start..=end {
            if self.is_port_available(port).await? {
                return Ok(port);
            }
        }

        Err(MockError::ResourceNotFound(format!("No available ports in range {}-{}", start, end)))
    }

    /// Bind a port to a service
    pub async fn bind_port(&mut self, port: u16, service: &str) -> Result<(), MockError> {
        self.base.simulate_operation("bind_port").await?;

        if !self.is_port_available(port).await? {
            return Err(MockError::OperationFailed(format!("Port {} is already in use", port)));
        }

        self.port_bindings.insert(port, service.to_string());
        Ok(())
    }

    /// Release a port binding
    pub async fn release_port(&mut self, port: u16) -> Result<(), MockError> {
        self.base.simulate_operation("release_port").await?;

        if self.port_bindings.remove(&port).is_some() {
            Ok(())
        } else {
            Err(MockError::ResourceNotFound(format!("Port {} is not bound", port)))
        }
    }

    /// Get network interface information
    pub async fn get_interface(&mut self, name: &str) -> Result<MockNetworkInterface, MockError> {
        self.base.simulate_operation("get_interface").await?;

        self.interfaces.get(name)
            .cloned()
            .ok_or_else(|| MockError::ResourceNotFound(format!("Interface not found: {}", name)))
    }

    /// List all network interfaces
    pub async fn list_interfaces(&mut self) -> Result<Vec<MockNetworkInterface>, MockError> {
        self.base.simulate_operation("list_interfaces").await?;
        Ok(self.interfaces.values().cloned().collect())
    }

    /// Get local IP address
    pub async fn get_local_ip(&mut self) -> Result<String, MockError> {
        self.base.simulate_operation("get_local_ip").await?;

        // Return the first non-loopback interface IP
        for interface in self.interfaces.values() {
            if interface.name != "lo" && !interface.ip_address.starts_with("127.") {
                return Ok(interface.ip_address.clone());
            }
        }

        Ok("192.168.1.100".to_string()) // Fallback
    }

    /// Resolve hostname to IP address
    pub async fn resolve_hostname(&mut self, hostname: &str) -> Result<String, MockError> {
        self.base.simulate_operation("resolve_hostname").await?;

        // Check local DNS records first
        if let Some(ip) = self.dns_records.get(hostname) {
            return Ok(ip.clone());
        }

        // If it's already an IP address, return as-is
        if hostname.parse::<IpAddr>().is_ok() {
            return Ok(hostname.to_string());
        }

        // Simulate DNS lookup for common domains
        let resolved_ip = match hostname {
            "google.com" | "www.google.com" => "172.217.14.110",
            "github.com" | "www.github.com" => "140.82.112.3",
            "cloudflare.com" | "www.cloudflare.com" => "104.16.132.229",
            _ => {
                // Generate a mock IP for unknown hosts
                let ip = Ipv4Addr::new(
                    192,
                    168,
                    (hostname.len() % 255) as u8,
                    (hostname.chars().map(|c| c as u32).sum::<u32>() % 255) as u8,
                );
                return Ok(ip.to_string());
            }
        };

        Ok(resolved_ip.to_string())
    }

    /// Add a firewall rule
    pub async fn add_firewall_rule(&mut self, rule: MockFirewallRule) -> Result<String, MockError> {
        self.base.simulate_operation("add_firewall_rule").await?;

        let rule_id = format!("rule_{}", self.firewall_rules.len() + 1);
        let mut rule_with_id = rule;
        rule_with_id.id = Some(rule_id.clone());
        
        self.firewall_rules.push(rule_with_id);
        Ok(rule_id)
    }

    /// Remove a firewall rule
    pub async fn remove_firewall_rule(&mut self, rule_id: &str) -> Result<(), MockError> {
        self.base.simulate_operation("remove_firewall_rule").await?;

        let initial_len = self.firewall_rules.len();
        self.firewall_rules.retain(|rule| rule.id.as_ref() != Some(rule_id));

        if self.firewall_rules.len() < initial_len {
            Ok(())
        } else {
            Err(MockError::ResourceNotFound(format!("Firewall rule not found: {}", rule_id)))
        }
    }

    /// List firewall rules
    pub async fn list_firewall_rules(&mut self) -> Result<Vec<MockFirewallRule>, MockError> {
        self.base.simulate_operation("list_firewall_rules").await?;
        Ok(self.firewall_rules.clone())
    }

    /// Test network connectivity
    pub async fn ping(&mut self, host: &str, count: u32) -> Result<PingResult, MockError> {
        self.base.simulate_operation("ping").await?;

        // Simulate ping delay
        tokio::time::sleep(std::time::Duration::from_millis(10 * count as u64)).await;

        // Localhost always responds
        if host == "127.0.0.1" || host == "localhost" {
            return Ok(PingResult {
                host: host.to_string(),
                packets_sent: count,
                packets_received: count,
                packet_loss_percent: 0.0,
                avg_round_trip_ms: 0.5,
                min_round_trip_ms: 0.3,
                max_round_trip_ms: 0.8,
            });
        }

        // Check if host is resolvable
        let _resolved_ip = self.resolve_hostname(host).await?;

        // Simulate some packet loss for distant hosts
        let loss_rate = if self.dns_records.contains_key(host) { 0.0 } else { 0.1 }; // 10% loss for external hosts
        let packets_received = count - (count as f64 * loss_rate) as u32;

        Ok(PingResult {
            host: host.to_string(),
            packets_sent: count,
            packets_received,
            packet_loss_percent: loss_rate * 100.0,
            avg_round_trip_ms: 25.0 + rand::random::<f64>() * 50.0,
            min_round_trip_ms: 15.0 + rand::random::<f64>() * 10.0,
            max_round_trip_ms: 50.0 + rand::random::<f64>() * 100.0,
        })
    }

    /// Test bandwidth between endpoints
    pub async fn test_bandwidth(&mut self, target: &str, duration_secs: u32) -> Result<BandwidthResult, MockError> {
        self.base.simulate_operation("test_bandwidth").await?;

        // Simulate bandwidth test duration
        tokio::time::sleep(std::time::Duration::from_millis(duration_secs as u64 * 100)).await; // Scaled down

        let _resolved_ip = self.resolve_hostname(target).await?;

        // Simulate bandwidth based on target type
        let (upload_mbps, download_mbps) = if self.dns_records.contains_key(target) {
            // Local network - high bandwidth
            (900.0 + rand::random::<f64>() * 100.0, 950.0 + rand::random::<f64>() * 50.0)
        } else {
            // External network - lower bandwidth
            (50.0 + rand::random::<f64>() * 50.0, 100.0 + rand::random::<f64>() * 100.0)
        };

        Ok(BandwidthResult {
            target: target.to_string(),
            upload_mbps,
            download_mbps,
            latency_ms: 10.0 + rand::random::<f64>() * 40.0,
            jitter_ms: 1.0 + rand::random::<f64>() * 5.0,
            duration_secs,
        })
    }

    /// Check network route to target
    pub async fn traceroute(&mut self, target: &str, max_hops: u32) -> Result<Vec<TraceHop>, MockError> {
        self.base.simulate_operation("traceroute").await?;

        let _resolved_ip = self.resolve_hostname(target).await?;

        let mut hops = Vec::new();
        let hop_count = (max_hops.min(10) + rand::random::<u32>() % 5).max(1);

        for i in 1..=hop_count {
            // Simulate increasing latency with distance
            let latency = i as f64 * 5.0 + rand::random::<f64>() * 10.0;
            
            let hop_ip = if i == 1 {
                "192.168.1.1".to_string() // Gateway
            } else if i == hop_count {
                self.resolve_hostname(target).await.unwrap_or_else(|_| target.to_string())
            } else {
                format!("10.{}.{}.1", i % 255, (i * 2) % 255)
            };

            hops.push(TraceHop {
                hop_number: i,
                ip_address: hop_ip,
                hostname: None,
                round_trip_ms: vec![latency, latency + 1.0, latency - 0.5],
            });
        }

        Ok(hops)
    }
}

#[async_trait]
impl MockService for MockNetworkService {
    async fn initialize(&mut self) -> Result<(), MockError> {
        self.base.initialized = true;
        println!("Mock Network service initialized");
        Ok(())
    }

    async fn reset(&mut self) -> Result<(), MockError> {
        self.interfaces.clear();
        self.port_bindings.clear();
        self.firewall_rules.clear();
        self.dns_records.clear();
        self.base.stats = MockStats::default();

        // Reset shared state
        if let Ok(mut state) = self.base.state.lock() {
            state.network_interfaces.clear();
        }

        // Re-add default interfaces and records
        self.add_mock_interface("lo", "127.0.0.1");
        self.add_mock_interface("eth0", "192.168.1.100");
        self.add_mock_interface("docker0", "172.17.0.1");
        self.add_mock_interface("vpn0", "10.8.0.1");

        self.dns_records.insert("localhost".to_string(), "127.0.0.1".to_string());
        self.dns_records.insert("vpn-server".to_string(), "192.168.1.100".to_string());

        self.port_bindings.insert(22, "ssh".to_string());
        self.port_bindings.insert(80, "http".to_string());
        self.port_bindings.insert(443, "https".to_string());

        Ok(())
    }

    async fn health_check(&self) -> Result<bool, MockError> {
        Ok(self.base.initialized)
    }

    fn get_stats(&self) -> MockStats {
        self.base.stats.clone()
    }
}

/// Mock firewall rule
#[derive(Debug, Clone)]
pub struct MockFirewallRule {
    pub id: Option<String>,
    pub port: u16,
    pub protocol: String, // "tcp", "udp", "both"
    pub action: String,   // "allow", "deny"
    pub source: Option<String>,
    pub destination: Option<String>,
    pub comment: Option<String>,
}

/// Ping test result
#[derive(Debug, Clone)]
pub struct PingResult {
    pub host: String,
    pub packets_sent: u32,
    pub packets_received: u32,
    pub packet_loss_percent: f64,
    pub avg_round_trip_ms: f64,
    pub min_round_trip_ms: f64,
    pub max_round_trip_ms: f64,
}

/// Bandwidth test result
#[derive(Debug, Clone)]
pub struct BandwidthResult {
    pub target: String,
    pub upload_mbps: f64,
    pub download_mbps: f64,
    pub latency_ms: f64,
    pub jitter_ms: f64,
    pub duration_secs: u32,
}

/// Traceroute hop information
#[derive(Debug, Clone)]
pub struct TraceHop {
    pub hop_number: u32,
    pub ip_address: String,
    pub hostname: Option<String>,
    pub round_trip_ms: Vec<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_network_service_creation() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);

        assert!(!service.base.initialized);
        assert!(!service.interfaces.is_empty());

        let init_result = service.initialize().await;
        assert!(init_result.is_ok());
        assert!(service.base.initialized);
    }

    #[tokio::test]
    async fn test_port_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);
        service.initialize().await.unwrap();

        // Check port availability
        let available = service.is_port_available(9999).await.unwrap();
        assert!(available);

        let unavailable = service.is_port_available(80).await.unwrap(); // Pre-bound
        assert!(!unavailable);

        // Find available port
        let port = service.find_available_port(9000, 9999).await.unwrap();
        assert!(port >= 9000 && port <= 9999);

        // Bind port
        let bind_result = service.bind_port(port, "test-service").await;
        assert!(bind_result.is_ok());

        // Check it's no longer available
        let now_unavailable = service.is_port_available(port).await.unwrap();
        assert!(!now_unavailable);

        // Release port
        let release_result = service.release_port(port).await;
        assert!(release_result.is_ok());

        // Check it's available again
        let available_again = service.is_port_available(port).await.unwrap();
        assert!(available_again);
    }

    #[tokio::test]
    async fn test_network_interface_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);
        service.initialize().await.unwrap();

        // List interfaces
        let interfaces = service.list_interfaces().await.unwrap();
        assert!(!interfaces.is_empty());

        // Get specific interface
        let lo_interface = service.get_interface("lo").await.unwrap();
        assert_eq!(lo_interface.name, "lo");
        assert_eq!(lo_interface.ip_address, "127.0.0.1");

        // Get local IP
        let local_ip = service.get_local_ip().await.unwrap();
        assert!(!local_ip.is_empty());
        assert_ne!(local_ip, "127.0.0.1"); // Should not be loopback
    }

    #[tokio::test]
    async fn test_dns_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);
        service.initialize().await.unwrap();

        // Resolve known hostname
        let localhost_ip = service.resolve_hostname("localhost").await.unwrap();
        assert_eq!(localhost_ip, "127.0.0.1");

        // Resolve IP address (should return as-is)
        let ip_result = service.resolve_hostname("192.168.1.1").await.unwrap();
        assert_eq!(ip_result, "192.168.1.1");

        // Resolve external hostname
        let google_ip = service.resolve_hostname("google.com").await.unwrap();
        assert!(!google_ip.is_empty());
    }

    #[tokio::test]
    async fn test_connectivity_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);
        service.initialize().await.unwrap();

        // Test ping
        let ping_result = service.ping("localhost", 4).await.unwrap();
        assert_eq!(ping_result.packets_sent, 4);
        assert_eq!(ping_result.packets_received, 4);
        assert_eq!(ping_result.packet_loss_percent, 0.0);

        // Test port connectivity
        let port_open = service.is_port_open("localhost", 80, 1000).await.unwrap();
        assert!(port_open); // Port 80 is pre-bound

        let port_closed = service.is_port_open("localhost", 65432, 1000).await.unwrap();
        assert!(!port_closed);
    }

    #[tokio::test]
    async fn test_firewall_operations() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);
        service.initialize().await.unwrap();

        // Add firewall rule
        let rule = MockFirewallRule {
            id: None,
            port: 8080,
            protocol: "tcp".to_string(),
            action: "allow".to_string(),
            source: Some("192.168.1.0/24".to_string()),
            destination: None,
            comment: Some("Test rule".to_string()),
        };

        let rule_id = service.add_firewall_rule(rule).await.unwrap();
        assert!(!rule_id.is_empty());

        // List rules
        let rules = service.list_firewall_rules().await.unwrap();
        assert_eq!(rules.len(), 1);
        assert_eq!(rules[0].port, 8080);

        // Remove rule
        let remove_result = service.remove_firewall_rule(&rule_id).await;
        assert!(remove_result.is_ok());

        // Verify removal
        let rules_after = service.list_firewall_rules().await.unwrap();
        assert!(rules_after.is_empty());
    }

    #[tokio::test]
    async fn test_bandwidth_and_traceroute() {
        let state = MockState::new();
        let config = MockConfig::default();
        let mut service = MockNetworkService::new(config, state);
        service.initialize().await.unwrap();

        // Test bandwidth
        let bandwidth = service.test_bandwidth("vpn-server", 1).await.unwrap();
        assert!(bandwidth.upload_mbps > 0.0);
        assert!(bandwidth.download_mbps > 0.0);
        assert!(bandwidth.latency_ms > 0.0);

        // Test traceroute
        let trace = service.traceroute("google.com", 10).await.unwrap();
        assert!(!trace.is_empty());
        assert_eq!(trace[0].hop_number, 1);
        assert_eq!(trace[0].ip_address, "192.168.1.1"); // Gateway
    }
}