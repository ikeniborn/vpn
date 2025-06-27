use std::path::{Path, PathBuf};
use std::process::Command;
use std::collections::HashMap;
use bollard::container::Config;
use bollard::models::HostConfig;
use vpn_docker::ContainerManager;
use vpn_network::{PortChecker, IpDetector, FirewallManager, FirewallRule};
use vpn_network::firewall::{Protocol, Direction};
use vpn_crypto::{X25519KeyManager, UuidGenerator};
use vpn_users::{UserManager, User};
use vpn_users::user::VpnProtocol;
use crate::templates::DockerComposeTemplate;
use crate::validator::ConfigValidator;
use crate::error::{ServerError, Result};

#[derive(Debug, Clone)]
pub struct InstallationOptions {
    pub protocol: VpnProtocol,
    pub port: Option<u16>,
    pub sni_domain: Option<String>,
    pub install_path: PathBuf,
    pub enable_firewall: bool,
    pub auto_start: bool,
    pub log_level: LogLevel,
    pub reality_dest: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub enum LogLevel {
    None,
    Error,
    Warning,
    Info,
    Debug,
}

pub struct ServerInstaller {
    container_manager: ContainerManager,
    firewall_manager: FirewallManager,
}

impl ServerInstaller {
    pub fn new() -> Result<Self> {
        let container_manager = ContainerManager::new()?;
        let firewall_manager = FirewallManager;
        
        Ok(Self {
            container_manager,
            firewall_manager,
        })
    }
    
    pub async fn install(&self, options: InstallationOptions) -> Result<InstallationResult> {
        println!("Starting VPN server installation...");
        
        // Pre-installation checks
        self.check_dependencies().await?;
        self.check_system_requirements().await?;
        
        // Create installation directory
        std::fs::create_dir_all(&options.install_path)?;
        
        // Generate server configuration
        let server_config = self.generate_server_config(&options).await?;
        
        // Set up firewall rules
        if options.enable_firewall {
            self.setup_firewall_rules(server_config.port).await?;
        }
        
        // Create Docker configuration
        self.create_docker_configuration(&options, &server_config).await?;
        
        // Download and start containers
        self.deploy_containers(&options).await?;
        
        // Create initial user
        let initial_user = self.create_initial_user(&options, &server_config).await?;
        
        // Verify installation
        self.verify_installation(&options).await?;
        
        println!("VPN server installation completed successfully!");
        
        Ok(InstallationResult {
            server_config,
            initial_user,
            install_path: options.install_path,
        })
    }
    
    async fn check_dependencies(&self) -> Result<()> {
        // Check Docker
        if !self.is_docker_installed() {
            return Err(ServerError::DependencyMissing("Docker".to_string()));
        }
        
        // Check Docker Compose
        if !self.is_docker_compose_installed() {
            return Err(ServerError::DependencyMissing("Docker Compose".to_string()));
        }
        
        // Check UFW (optional)
        if !FirewallManager::is_ufw_installed() && !FirewallManager::is_iptables_installed() {
            println!("Warning: No firewall management tools found (UFW/iptables)");
        }
        
        Ok(())
    }
    
    async fn check_system_requirements(&self) -> Result<()> {
        // Check available disk space (minimum 1GB)
        // This is a simplified check - in production you'd want more robust checking
        
        // Check if ports are available
        let common_ports = [80, 443, 8080, 8443];
        for &port in &common_ports {
            if !PortChecker::is_port_available(port) {
                println!("Warning: Port {} is already in use", port);
            }
        }
        
        Ok(())
    }
    
    async fn generate_server_config(&self, options: &InstallationOptions) -> Result<ServerConfig> {
        let port = match options.port {
            Some(p) => {
                PortChecker::validate_port(p)?;
                if !PortChecker::is_port_available(p) {
                    return Err(ServerError::InstallationError(
                        format!("Port {} is not available", p)
                    ));
                }
                p
            }
            None => PortChecker::find_random_available_port(10000, 65000)?,
        };
        
        let public_ip = IpDetector::get_public_ip().await?;
        let keypair = X25519KeyManager::generate_keypair()?;
        let short_id = UuidGenerator::generate_short_id();
        
        let sni_domain = match &options.sni_domain {
            Some(domain) => domain.clone(),
            None => self.select_optimal_sni().await?,
        };
        
        Ok(ServerConfig {
            host: public_ip.to_string(),
            port,
            public_key: keypair.public_key_base64(),
            private_key: keypair.private_key_base64(),
            short_id,
            sni_domain,
            reality_dest: options.reality_dest.clone()
                .unwrap_or_else(|| "www.google.com:443".to_string()),
            log_level: options.log_level,
        })
    }
    
    async fn select_optimal_sni(&self) -> Result<String> {
        let candidates = [
            "www.google.com",
            "www.cloudflare.com",
            "www.amazon.com",
            "www.microsoft.com",
        ];
        
        for &candidate in &candidates {
            if vpn_network::SniValidator::validate_sni(candidate).await? {
                return Ok(candidate.to_string());
            }
        }
        
        Ok("www.google.com".to_string()) // fallback
    }
    
    async fn setup_firewall_rules(&self, port: u16) -> Result<()> {
        if FirewallManager::is_ufw_installed() {
            let rule = FirewallRule {
                port,
                protocol: Protocol::Both,
                direction: Direction::In,
                source: None,
                comment: Some("VPN Server".to_string()),
            };
            
            FirewallManager::add_ufw_rule(&rule)?;
            
            if !FirewallManager::check_ufw_status()? {
                FirewallManager::enable_ufw()?;
            }
        }
        
        Ok(())
    }
    
    async fn create_docker_configuration(
        &self,
        options: &InstallationOptions,
        server_config: &ServerConfig,
    ) -> Result<()> {
        let template = DockerComposeTemplate::new();
        
        match options.protocol {
            VpnProtocol::Vless => {
                template.generate_xray_compose(
                    &options.install_path,
                    server_config,
                    options,
                ).await?;
            }
            VpnProtocol::Shadowsocks => {
                template.generate_outline_compose(
                    &options.install_path,
                    server_config,
                    options,
                ).await?;
            }
            _ => {
                return Err(ServerError::InstallationError(
                    format!("Protocol {:?} not yet supported", options.protocol)
                ));
            }
        }
        
        Ok(())
    }
    
    async fn deploy_containers(&self, options: &InstallationOptions) -> Result<()> {
        let compose_path = options.install_path.join("docker-compose.yml");
        
        // Use docker-compose command
        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("up")
            .arg("-d")
            .output()?;
        
        if !output.status.success() {
            return Err(ServerError::InstallationError(
                format!("Docker Compose failed: {}", 
                    String::from_utf8_lossy(&output.stderr))
            ));
        }
        
        // Wait for containers to be healthy
        tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        
        Ok(())
    }
    
    async fn create_initial_user(
        &self,
        options: &InstallationOptions,
        server_config: &ServerConfig,
    ) -> Result<User> {
        let server_config_obj = vpn_users::config::ServerConfig {
            host: server_config.host.clone(),
            port: server_config.port,
            sni: Some(server_config.sni_domain.clone()),
            public_key: Some(server_config.public_key.clone()),
            private_key: Some(server_config.private_key.clone()),
            short_id: Some(server_config.short_id.clone()),
            reality_dest: Some(server_config.reality_dest.clone()),
            reality_server_names: vec![server_config.sni_domain.clone()],
        };
        
        let user_manager = UserManager::new(&options.install_path, server_config_obj)?;
        let user = user_manager.create_user("admin".to_string(), options.protocol).await?;
        
        Ok(user)
    }
    
    async fn verify_installation(&self, options: &InstallationOptions) -> Result<()> {
        let validator = ConfigValidator::new()?;
        validator.validate_installation(&options.install_path).await?;
        Ok(())
    }
    
    fn is_docker_installed(&self) -> bool {
        Command::new("docker")
            .arg("--version")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    
    fn is_docker_compose_installed(&self) -> bool {
        Command::new("docker-compose")
            .arg("--version")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    
    pub async fn uninstall(&self, install_path: &Path) -> Result<()> {
        let compose_path = install_path.join("docker-compose.yml");
        
        if compose_path.exists() {
            // Stop and remove containers
            let _output = Command::new("docker-compose")
                .arg("-f")
                .arg(&compose_path)
                .arg("down")
                .arg("-v")
                .output()?;
        }
        
        // Remove installation directory
        if install_path.exists() {
            std::fs::remove_dir_all(install_path)?;
        }
        
        Ok(())
    }
}

#[derive(Debug)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub public_key: String,
    pub private_key: String,
    pub short_id: String,
    pub sni_domain: String,
    pub reality_dest: String,
    pub log_level: LogLevel,
}

#[derive(Debug)]
pub struct InstallationResult {
    pub server_config: ServerConfig,
    pub initial_user: User,
    pub install_path: PathBuf,
}

impl Default for InstallationOptions {
    fn default() -> Self {
        Self {
            protocol: VpnProtocol::Vless,
            port: None,
            sni_domain: None,
            install_path: PathBuf::from("/opt/vpn"),
            enable_firewall: true,
            auto_start: true,
            log_level: LogLevel::Warning,
            reality_dest: None,
        }
    }
}

impl LogLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            LogLevel::None => "none",
            LogLevel::Error => "error",
            LogLevel::Warning => "warning",
            LogLevel::Info => "info",
            LogLevel::Debug => "debug",
        }
    }
}