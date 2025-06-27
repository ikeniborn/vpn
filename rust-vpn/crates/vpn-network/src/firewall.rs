use std::process::Command;
use std::net::IpAddr;
use crate::error::{NetworkError, Result};

#[derive(Debug, Clone)]
pub struct FirewallRule {
    pub port: u16,
    pub protocol: Protocol,
    pub direction: Direction,
    pub source: Option<IpAddr>,
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Protocol {
    Tcp,
    Udp,
    Both,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Direction {
    In,
    Out,
    Both,
}

pub struct FirewallManager;

impl FirewallManager {
    pub fn is_ufw_installed() -> bool {
        Command::new("which")
            .arg("ufw")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    
    pub fn is_iptables_installed() -> bool {
        Command::new("which")
            .arg("iptables")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    
    pub fn add_ufw_rule(rule: &FirewallRule) -> Result<()> {
        let mut cmd = Command::new("ufw");
        cmd.arg("allow");
        
        if let Some(source) = &rule.source {
            cmd.arg("from").arg(source.to_string());
        }
        
        cmd.arg("to").arg("any");
        cmd.arg("port").arg(rule.port.to_string());
        
        match rule.protocol {
            Protocol::Tcp => cmd.arg("proto").arg("tcp"),
            Protocol::Udp => cmd.arg("proto").arg("udp"),
            Protocol::Both => &mut cmd,
        };
        
        if let Some(comment) = &rule.comment {
            cmd.arg("comment").arg(comment);
        }
        
        let output = cmd.output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        Ok(())
    }
    
    pub fn remove_ufw_rule(rule: &FirewallRule) -> Result<()> {
        let mut cmd = Command::new("ufw");
        cmd.arg("delete").arg("allow");
        
        cmd.arg("to").arg("any");
        cmd.arg("port").arg(rule.port.to_string());
        
        match rule.protocol {
            Protocol::Tcp => cmd.arg("proto").arg("tcp"),
            Protocol::Udp => cmd.arg("proto").arg("udp"),
            Protocol::Both => &mut cmd,
        };
        
        let output = cmd.output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        Ok(())
    }
    
    pub fn add_iptables_rule(rule: &FirewallRule) -> Result<()> {
        let chain = match rule.direction {
            Direction::In => "INPUT",
            Direction::Out => "OUTPUT",
            Direction::Both => return Err(NetworkError::FirewallError(
                "Cannot use Both direction with iptables directly".to_string()
            )),
        };
        
        let mut cmd = Command::new("iptables");
        cmd.arg("-A").arg(chain);
        
        if let Some(source) = &rule.source {
            cmd.arg("-s").arg(source.to_string());
        }
        
        match rule.protocol {
            Protocol::Tcp => cmd.arg("-p").arg("tcp"),
            Protocol::Udp => cmd.arg("-p").arg("udp"),
            Protocol::Both => {
                Self::add_iptables_rule(&FirewallRule {
                    protocol: Protocol::Tcp,
                    ..rule.clone()
                })?;
                
                let mut udp_rule = rule.clone();
                udp_rule.protocol = Protocol::Udp;
                return Self::add_iptables_rule(&udp_rule);
            }
        };
        
        cmd.arg("--dport").arg(rule.port.to_string());
        cmd.arg("-j").arg("ACCEPT");
        
        if let Some(comment) = &rule.comment {
            cmd.arg("-m").arg("comment");
            cmd.arg("--comment").arg(comment);
        }
        
        let output = cmd.output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        Ok(())
    }
    
    pub fn enable_ufw() -> Result<()> {
        let output = Command::new("ufw")
            .arg("--force")
            .arg("enable")
            .output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        Ok(())
    }
    
    pub fn check_ufw_status() -> Result<bool> {
        let output = Command::new("ufw")
            .arg("status")
            .output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        let status = String::from_utf8_lossy(&output.stdout);
        Ok(status.contains("Status: active"))
    }
    
    pub fn list_ufw_rules() -> Result<Vec<String>> {
        let output = Command::new("ufw")
            .arg("status")
            .arg("numbered")
            .output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        let output_str = String::from_utf8_lossy(&output.stdout);
        let rules: Vec<String> = output_str
            .lines()
            .filter(|line| line.contains("[") && line.contains("]"))
            .map(|line| line.to_string())
            .collect();
        
        Ok(rules)
    }
    
    pub fn save_iptables_rules(path: &str) -> Result<()> {
        let output = Command::new("iptables-save")
            .output()?;
        
        if !output.status.success() {
            return Err(NetworkError::FirewallError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ));
        }
        
        std::fs::write(path, output.stdout)?;
        Ok(())
    }
}

impl Protocol {
    pub fn as_str(&self) -> &str {
        match self {
            Protocol::Tcp => "tcp",
            Protocol::Udp => "udp",
            Protocol::Both => "tcp/udp",
        }
    }
}

impl Direction {
    pub fn as_str(&self) -> &str {
        match self {
            Direction::In => "in",
            Direction::Out => "out",
            Direction::Both => "in/out",
        }
    }
}