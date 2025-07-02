use std::process::Command;
use std::collections::HashSet;
use std::io::{self, Write};
use crate::error::{NetworkError, Result};

pub struct SubnetManager;

impl SubnetManager {
    /// Get list of available VPN subnet ranges that don't conflict with existing networks
    pub fn get_available_subnets() -> Result<Vec<VpnSubnet>> {
        let used_subnets = Self::get_used_docker_subnets()?;
        let candidate_subnets = Self::get_candidate_subnets();
        
        let available = candidate_subnets
            .into_iter()
            .filter(|subnet| !Self::conflicts_with_used(&subnet.cidr, &used_subnets))
            .collect();
            
        Ok(available)
    }
    
    /// Get list of candidate VPN subnet ranges
    fn get_candidate_subnets() -> Vec<VpnSubnet> {
        vec![
            VpnSubnet {
                cidr: "172.30.0.0/16".to_string(),
                description: "Recommended - Private range 172.30.x.x".to_string(),
                range_start: "172.30.0.1".to_string(),
                range_end: "172.30.255.254".to_string(),
            },
            VpnSubnet {
                cidr: "172.31.0.0/16".to_string(),
                description: "Alternative - Private range 172.31.x.x".to_string(),
                range_start: "172.31.0.1".to_string(),
                range_end: "172.31.255.254".to_string(),
            },
            VpnSubnet {
                cidr: "192.168.100.0/24".to_string(),
                description: "Compact - Private range 192.168.100.x".to_string(),
                range_start: "192.168.100.1".to_string(),
                range_end: "192.168.100.254".to_string(),
            },
            VpnSubnet {
                cidr: "192.168.101.0/24".to_string(),
                description: "Compact - Private range 192.168.101.x".to_string(),
                range_start: "192.168.101.1".to_string(),
                range_end: "192.168.101.254".to_string(),
            },
            VpnSubnet {
                cidr: "10.100.0.0/16".to_string(),
                description: "Large - Private range 10.100.x.x".to_string(),
                range_start: "10.100.0.1".to_string(),
                range_end: "10.100.255.254".to_string(),
            },
            VpnSubnet {
                cidr: "10.101.0.0/16".to_string(),
                description: "Large - Private range 10.101.x.x".to_string(),
                range_start: "10.101.0.1".to_string(),
                range_end: "10.101.255.254".to_string(),
            },
        ]
    }
    
    /// Get currently used Docker subnets
    fn get_used_docker_subnets() -> Result<HashSet<String>> {
        let output = Command::new("docker")
            .arg("network")
            .arg("ls")
            .arg("--format")
            .arg("{{.ID}}")
            .output()
            .map_err(|e| NetworkError::CommandError(format!("Failed to list Docker networks: {}", e)))?;
            
        if !output.status.success() {
            return Err(NetworkError::CommandError("Docker network ls failed".to_string()));
        }
        
        let network_ids = String::from_utf8_lossy(&output.stdout);
        let mut used_subnets = HashSet::new();
        
        for network_id in network_ids.lines() {
            if network_id.trim().is_empty() {
                continue;
            }
            
            // Get network details
            let inspect_output = Command::new("docker")
                .arg("network")
                .arg("inspect")
                .arg(network_id.trim())
                .output();
                
            if let Ok(inspect_result) = inspect_output {
                let network_info = String::from_utf8_lossy(&inspect_result.stdout);
                
                // Extract subnet information from JSON
                if let Ok(network_data) = serde_json::from_str::<serde_json::Value>(&network_info) {
                    if let Some(networks) = network_data.as_array() {
                        for network in networks {
                            if let Some(ipam) = network.get("IPAM") {
                                if let Some(config) = ipam.get("Config") {
                                    if let Some(config_array) = config.as_array() {
                                        for config_item in config_array {
                                            if let Some(subnet) = config_item.get("Subnet") {
                                                if let Some(subnet_str) = subnet.as_str() {
                                                    used_subnets.insert(subnet_str.to_string());
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Ok(used_subnets)
    }
    
    /// Check if candidate subnet conflicts with used subnets
    fn conflicts_with_used(candidate: &str, used_subnets: &HashSet<String>) -> bool {
        // Simple subnet conflict detection
        // For production use, would need more sophisticated CIDR overlap detection
        for used in used_subnets {
            if Self::subnets_overlap(candidate, used) {
                return true;
            }
        }
        false
    }
    
    /// Basic subnet overlap detection
    fn subnets_overlap(subnet1: &str, subnet2: &str) -> bool {
        // Extract the network part (before the slash)
        let net1 = subnet1.split('/').next().unwrap_or("");
        let net2 = subnet2.split('/').next().unwrap_or("");
        
        // Simple check for same network base (first 3 octets for /24, first 2 for /16)
        if subnet1.contains("/16") && subnet2.contains("/16") {
            let net1_parts: Vec<&str> = net1.split('.').collect();
            let net2_parts: Vec<&str> = net2.split('.').collect();
            
            if net1_parts.len() >= 2 && net2_parts.len() >= 2 {
                return net1_parts[0] == net2_parts[0] && net1_parts[1] == net2_parts[1];
            }
        }
        
        if subnet1.contains("/24") && subnet2.contains("/24") {
            let net1_parts: Vec<&str> = net1.split('.').collect();
            let net2_parts: Vec<&str> = net2.split('.').collect();
            
            if net1_parts.len() >= 3 && net2_parts.len() >= 3 {
                return net1_parts[0] == net2_parts[0] && 
                       net1_parts[1] == net2_parts[1] && 
                       net1_parts[2] == net2_parts[2];
            }
        }
        
        // Exact match
        subnet1 == subnet2
    }
    
    /// Interactive subnet selection for user
    pub fn select_subnet_interactive() -> Result<VpnSubnet> {
        println!("🔍 Detecting available VPN subnets...");
        
        let available_subnets = Self::get_available_subnets()?;
        
        if available_subnets.is_empty() {
            return Err(NetworkError::NoAvailableSubnets);
        }
        
        println!("\n📋 Available VPN subnet options:");
        println!();
        
        for (i, subnet) in available_subnets.iter().enumerate() {
            println!("{}. {} - {}", 
                     i + 1, 
                     subnet.cidr, 
                     subnet.description);
            println!("   Range: {} - {}", subnet.range_start, subnet.range_end);
            println!();
        }
        
        loop {
            print!("Select subnet number (1-{}) [1]: ", available_subnets.len());
            io::stdout().flush().unwrap();
            
            let mut input = String::new();
            io::stdin().read_line(&mut input)
                .map_err(|e| NetworkError::IoError(e))?;
                
            let input = input.trim();
            
            // Default to first option if empty
            if input.is_empty() {
                return Ok(available_subnets[0].clone());
            }
            
            if let Ok(choice) = input.parse::<usize>() {
                if choice >= 1 && choice <= available_subnets.len() {
                    return Ok(available_subnets[choice - 1].clone());
                }
            }
            
            println!("❌ Invalid choice. Please enter a number between 1 and {}", available_subnets.len());
        }
    }
    
    /// Automatically select best available subnet (non-interactive)
    pub fn select_subnet_auto() -> Result<VpnSubnet> {
        let available_subnets = Self::get_available_subnets()?;
        
        if available_subnets.is_empty() {
            return Err(NetworkError::NoAvailableSubnets);
        }
        
        // Return the first (recommended) available subnet
        Ok(available_subnets[0].clone())
    }
    
    /// Check if a specific subnet is available
    pub fn is_subnet_available(subnet: &str) -> Result<bool> {
        let used_subnets = Self::get_used_docker_subnets()?;
        Ok(!Self::conflicts_with_used(subnet, &used_subnets))
    }
}

#[derive(Debug, Clone)]
pub struct VpnSubnet {
    pub cidr: String,
    pub description: String,
    pub range_start: String,
    pub range_end: String,
}

impl VpnSubnet {
    /// Get the gateway IP for this subnet (typically .1)
    pub fn get_gateway_ip(&self) -> Result<String> {
        let network_part = self.cidr.split('/').next()
            .ok_or_else(|| NetworkError::InvalidSubnet(self.cidr.clone()))?;
            
        let mut parts: Vec<&str> = network_part.split('.').collect();
        if parts.len() != 4 {
            return Err(NetworkError::InvalidSubnet(self.cidr.clone()));
        }
        
        // Set last octet to 1 for gateway
        parts[3] = "1";
        Ok(parts.join("."))
    }
    
    /// Get subnet mask from CIDR
    pub fn get_subnet_mask(&self) -> Result<String> {
        let cidr_suffix = self.cidr.split('/').nth(1)
            .ok_or_else(|| NetworkError::InvalidSubnet(self.cidr.clone()))?;
            
        match cidr_suffix {
            "16" => Ok("255.255.0.0".to_string()),
            "24" => Ok("255.255.255.0".to_string()),
            "8" => Ok("255.0.0.0".to_string()),
            _ => Err(NetworkError::InvalidSubnet(format!("Unsupported CIDR: /{}", cidr_suffix))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_subnet_overlap_detection() {
        assert!(SubnetManager::subnets_overlap("172.20.0.0/16", "172.20.1.0/24"));
        assert!(SubnetManager::subnets_overlap("192.168.1.0/24", "192.168.1.0/24"));
        assert!(!SubnetManager::subnets_overlap("172.20.0.0/16", "172.21.0.0/16"));
        assert!(!SubnetManager::subnets_overlap("192.168.1.0/24", "192.168.2.0/24"));
    }

    #[test]
    fn test_vpn_subnet_gateway() {
        let subnet = VpnSubnet {
            cidr: "172.30.0.0/16".to_string(),
            description: "Test".to_string(),
            range_start: "172.30.0.1".to_string(),
            range_end: "172.30.255.254".to_string(),
        };
        
        assert_eq!(subnet.get_gateway_ip().unwrap(), "172.30.0.1");
    }
}