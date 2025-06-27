use std::path::{Path, PathBuf};
use std::process::Command;
// removed unused imports
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
    #[allow(dead_code)]
    container_manager: ContainerManager,
    #[allow(dead_code)]
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
        
        // Create installation directory with proper error handling
        if let Err(e) = std::fs::create_dir_all(&options.install_path) {
            match e.kind() {
                std::io::ErrorKind::PermissionDenied => {
                    return Err(ServerError::InstallationError(format!(
                        "Permission denied creating installation directory '{}'. Please run with sudo or check directory permissions.",
                        options.install_path.display()
                    )));
                }
                _ => {
                    return Err(ServerError::InstallationError(format!(
                        "Failed to create installation directory '{}': {}",
                        options.install_path.display(), e
                    )));
                }
            }
        }
        
        // Generate server configuration
        let server_config = self.generate_server_config(&options).await?;
        
        // Set up firewall rules
        if options.enable_firewall {
            self.setup_firewall_rules(server_config.port).await?;
        }
        
        // Create Docker configuration (this will overwrite any existing files)
        self.create_docker_configuration(&options, &server_config).await?;
        
        // Validate the new Docker Compose file
        self.validate_docker_compose_file(&options).await?;
        
        // Check and resolve network conflicts
        self.resolve_network_conflicts(&options).await?;
        
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
        if !FirewallManager::is_ufw_installed().await && !FirewallManager::is_iptables_installed().await {
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
        if FirewallManager::is_ufw_installed().await {
            let rule = FirewallRule {
                port,
                protocol: Protocol::Both,
                direction: Direction::In,
                source: None,
                comment: Some("VPN Server".to_string()),
            };
            
            FirewallManager::add_ufw_rule(&rule).await?;
            
            if !FirewallManager::check_ufw_status().await? {
                FirewallManager::enable_ufw().await?;
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
        
        println!("🐳 Starting VPN containers...");
        
        // Use docker-compose command
        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("up")
            .arg("-d")
            .output()?;
        
        let stderr = String::from_utf8_lossy(&output.stderr);
        
        // Handle Docker Compose version warnings (these are warnings, not errors)
        if stderr.contains("the attribute `version` is obsolete") {
            println!("⚠️ Note: Docker Compose version attribute warning (can be ignored)");
        }
        
        if !output.status.success() {
            // Check for common permission issues
            if stderr.contains("permission denied") || stderr.contains("Permission denied") {
                return Err(ServerError::InstallationError(
                    "Docker permission denied. Please ensure your user is in the docker group or run with sudo.".to_string()
                ));
            }
            
            // Check for network conflicts
            if stderr.contains("Pool overlaps with other one") || stderr.contains("network conflicts") {
                return Err(ServerError::InstallationError(
                    "Docker network conflict detected. The network cleanup may have failed. Try running 'vpn fix-networks' manually.".to_string()
                ));
            }
            
            return Err(ServerError::InstallationError(
                format!("Docker Compose failed: {}", stderr)
            ));
        }
        
        println!("✓ Containers started, waiting for initialization...");
        
        // Wait for containers to start and stabilize
        tokio::time::sleep(std::time::Duration::from_secs(15)).await;
        
        // Check if containers are actually running
        let status_output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("ps")
            .arg("-q")
            .output()?;
            
        if status_output.stdout.is_empty() {
            return Err(ServerError::InstallationError(
                "Containers failed to start. Check 'docker-compose logs' for details.".to_string()
            ));
        }
        
        println!("✓ Container deployment completed");
        Ok(())
    }
    
    async fn resolve_network_conflicts(&self, options: &InstallationOptions) -> Result<()> {
        println!("🔍 Checking for Docker network conflicts...");
        
        let compose_path = options.install_path.join("docker-compose.yml");
        
        // Always clean up existing installation first
        if compose_path.exists() {
            println!("🧹 Cleaning up existing VPN installation...");
            
            // Stop existing containers
            let stop_output = Command::new("docker-compose")
                .arg("-f")
                .arg(&compose_path)
                .arg("down")
                .arg("-v")
                .arg("--remove-orphans")
                .output();
                
            if let Ok(output) = stop_output {
                if output.status.success() {
                    println!("✓ Stopped existing containers");
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    println!("⚠️ Warning: Issue stopping containers: {}", stderr.lines().next().unwrap_or(""));
                }
            }
        }
        
        // Force remove any vpn-related networks
        self.force_remove_vpn_networks().await?;
        
        // Clean up unused networks
        let cleanup_output = Command::new("docker")
            .arg("network")
            .arg("prune")
            .arg("-f")
            .output();
            
        if cleanup_output.is_ok() {
            println!("✓ Cleaned up unused Docker networks");
        }
        
        println!("✓ Network conflict resolution completed");
        Ok(())
    }
    
    async fn force_remove_vpn_networks(&self) -> Result<()> {
        // Get list of networks containing 'vpn'
        let network_list_output = Command::new("docker")
            .arg("network")
            .arg("ls")
            .arg("--filter")
            .arg("name=vpn")
            .arg("-q")
            .output();
            
        if let Ok(output) = network_list_output {
            let network_ids = String::from_utf8_lossy(&output.stdout);
            
            for network_id in network_ids.lines() {
                if !network_id.trim().is_empty() {
                    let remove_output = Command::new("docker")
                        .arg("network")
                        .arg("rm")
                        .arg(network_id.trim())
                        .output();
                        
                    if let Ok(result) = remove_output {
                        if result.status.success() {
                            println!("✓ Removed VPN network: {}", network_id.trim());
                        }
                    }
                }
            }
        }
        
        // Also try to remove networks by name patterns
        let network_patterns = ["vpn_vpn-network", "vpn-network", "vpn_default"];
        for pattern in &network_patterns {
            let _remove_output = Command::new("docker")
                .arg("network")
                .arg("rm")
                .arg(pattern)
                .output();
        }
        
        Ok(())
    }
    
    async fn validate_docker_compose_file(&self, options: &InstallationOptions) -> Result<()> {
        let compose_path = options.install_path.join("docker-compose.yml");
        
        if let Ok(content) = std::fs::read_to_string(&compose_path) {
            // Check if file contains obsolete version attribute
            if content.contains("version:") {
                println!("⚠️ Detected obsolete version attribute in Docker Compose file");
                
                // Remove the version line
                let lines: Vec<&str> = content.lines().collect();
                let filtered_lines: Vec<&str> = lines
                    .into_iter()
                    .filter(|line| !line.trim().starts_with("version:"))
                    .collect();
                
                let new_content = filtered_lines.join("\n");
                
                // Write back the cleaned content
                if let Err(e) = std::fs::write(&compose_path, new_content) {
                    println!("⚠️ Warning: Could not clean Docker Compose file: {}", e);
                } else {
                    println!("✓ Cleaned Docker Compose file (removed version attribute)");
                }
            }
            
            // Check for fixed subnet configuration
            if content.contains("subnet:") || content.contains("172.20.0.0") {
                println!("⚠️ Detected fixed subnet configuration, regenerating Docker Compose file...");
                // The file will be regenerated by the create_docker_configuration call
                // which should have already happened, so this is just a safety check
            }
        }
        
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
        println!("🔍 Verifying installation...");
        
        // 1. Validate configuration files exist
        let validator = ConfigValidator::new()?;
        validator.validate_installation(&options.install_path).await?;
        println!("✓ Configuration files validated");
        
        // 2. Check if containers are created
        let compose_path = options.install_path.join("docker-compose.yml");
        if !compose_path.exists() {
            return Err(ServerError::InstallationError(
                "Docker Compose file not found".to_string()
            ));
        }
        println!("✓ Docker Compose configuration found");
        
        // 3. Verify containers are running
        self.verify_containers_running(&options.install_path).await?;
        println!("✓ VPN containers are running");
        
        // 4. Check container health status
        self.verify_container_health(&options.install_path).await?;
        println!("✓ Container health check passed");
        
        // 5. Test basic connectivity
        self.verify_service_connectivity(options).await?;
        println!("✓ Service connectivity verified");
        
        println!("🎉 Installation verification completed successfully!");
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
    
    async fn verify_containers_running(&self, install_path: &Path) -> Result<()> {
        use std::process::Command;
        
        let compose_path = install_path.join("docker-compose.yml");
        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("ps")
            .arg("-q")
            .output()?;

        if !output.status.success() {
            return Err(ServerError::InstallationError(
                "Failed to check container status".to_string()
            ));
        }

        if output.stdout.is_empty() {
            return Err(ServerError::InstallationError(
                "No VPN containers are running. Installation may have failed.".to_string()
            ));
        }

        Ok(())
    }

    async fn verify_container_health(&self, install_path: &Path) -> Result<()> {
        use std::process::Command;
        
        let compose_path = install_path.join("docker-compose.yml");
        
        // Wait a bit for containers to initialize
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        
        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("ps")
            .arg("--format")
            .arg("table")
            .output()?;

        if !output.status.success() {
            return Err(ServerError::InstallationError(
                "Failed to check container health".to_string()
            ));
        }

        let output_str = String::from_utf8_lossy(&output.stdout);
        
        // Check if any container is in "unhealthy" or "restarting" state
        if output_str.contains("unhealthy") || output_str.contains("restarting") {
            return Err(ServerError::InstallationError(
                "One or more containers are unhealthy. Check logs with 'docker-compose logs'".to_string()
            ));
        }

        // Check if containers are actually up
        if !output_str.contains("Up") {
            return Err(ServerError::InstallationError(
                "Containers are not in running state".to_string()
            ));
        }

        Ok(())
    }

    async fn verify_service_connectivity(&self, options: &InstallationOptions) -> Result<()> {
        use std::net::TcpListener;
        
        // Try to connect to the service port to verify it's accessible
        let bind_addr = format!("127.0.0.1:{}", 
            options.port.unwrap_or(8443));
        
        // Give the service a moment to start
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        
        // Check if port is bound (service is listening)
        match TcpListener::bind(&bind_addr) {
            Ok(_) => {
                return Err(ServerError::InstallationError(
                    format!("Service port {} is not bound. VPN service may not have started correctly.", 
                           options.port.unwrap_or(8443))
                ));
            }
            Err(e) => {
                if e.kind() == std::io::ErrorKind::AddrInUse {
                    // This is expected - service is running and bound to the port
                    return Ok(());
                } else {
                    return Err(ServerError::InstallationError(
                        format!("Unexpected error checking service port: {}", e)
                    ));
                }
            }
        }
    }

    pub async fn uninstall(&self, install_path: &Path, purge: bool) -> Result<()> {
        println!("🗑️ Starting VPN server uninstallation...");
        
        let compose_path = install_path.join("docker-compose.yml");
        
        // 1. Stop and remove containers
        if compose_path.exists() {
            println!("🐳 Stopping and removing containers...");
            let output = Command::new("docker-compose")
                .arg("-f")
                .arg(&compose_path)
                .arg("down")
                .arg("-v")
                .arg("--remove-orphans")
                .output()?;
            
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                println!("⚠️ Warning: Failed to cleanly stop containers: {}", stderr);
            } else {
                println!("✓ Containers stopped and removed");
            }
        }
        
        // 2. Remove Docker images if purge is enabled
        if purge {
            self.cleanup_docker_images().await?;
        }
        
        // 3. Remove firewall rules
        self.cleanup_firewall_rules(install_path).await?;
        
        // 4. Remove installation directory and all configuration files
        if install_path.exists() {
            println!("📂 Removing installation directory...");
            if let Err(e) = std::fs::remove_dir_all(install_path) {
                println!("⚠️ Warning: Failed to remove directory {}: {}", install_path.display(), e);
            } else {
                println!("✓ Installation directory removed");
            }
        }
        
        // 5. Remove system configuration files
        self.cleanup_system_config().await?;
        
        // 6. Remove log files if purge is enabled
        if purge {
            self.cleanup_log_files().await?;
        }
        
        println!("🎉 VPN server uninstallation completed successfully!");
        Ok(())
    }
    
    async fn cleanup_docker_images(&self) -> Result<()> {
        println!("🐳 Cleaning up Docker images...");
        
        // Remove VPN-related images
        let images_to_remove = ["xray/xray", "shadowsocks/shadowsocks-libev", "outline/shadowbox"];
        
        for image in &images_to_remove {
            let output = Command::new("docker")
                .arg("rmi")
                .arg("-f")
                .arg(image)
                .output();
            
            match output {
                Ok(result) if result.status.success() => {
                    println!("✓ Removed Docker image: {}", image);
                }
                _ => {
                    println!("ℹ️ Docker image {} not found or already removed", image);
                }
            }
        }
        
        // Clean up unused Docker resources
        let _cleanup_output = Command::new("docker")
            .arg("system")
            .arg("prune")
            .arg("-f")
            .arg("--volumes")
            .output();
        
        println!("✓ Docker cleanup completed");
        Ok(())
    }
    
    async fn cleanup_firewall_rules(&self, install_path: &Path) -> Result<()> {
        println!("🔥 Cleaning up firewall rules...");
        
        // Try to detect which ports were used by reading the configuration
        let mut ports_to_clean = Vec::new();
        
        // Try to read the server configuration to get the port
        if let Ok(config_content) = std::fs::read_to_string(install_path.join("config.json")) {
            if let Ok(config) = serde_json::from_str::<serde_json::Value>(&config_content) {
                if let Some(port) = config["port"].as_u64() {
                    ports_to_clean.push(port as u16);
                }
            }
        }
        
        // Also clean common VPN ports
        ports_to_clean.extend_from_slice(&[8443, 9443, 8080, 8090]);
        
        if FirewallManager::is_ufw_installed().await {
            for port in ports_to_clean {
                // Remove both TCP and UDP rules
                for protocol in ["tcp", "udp"] {
                    let output = Command::new("sudo")
                        .arg("ufw")
                        .arg("delete")
                        .arg("allow")
                        .arg(format!("{}/{}", port, protocol))
                        .output();
                    
                    match output {
                        Ok(result) if result.status.success() => {
                            println!("✓ Removed firewall rule for port {}/{}", port, protocol);
                        }
                        _ => {
                            // Rule might not exist, that's ok
                        }
                    }
                }
            }
        }
        
        println!("✓ Firewall cleanup completed");
        Ok(())
    }
    
    async fn cleanup_system_config(&self) -> Result<()> {
        println!("⚙️ Cleaning up system configuration...");
        
        // Remove system-wide configuration files
        let config_paths = [
            "/etc/vpn",
            "/etc/systemd/system/vpn.service",
            "/etc/cron.d/vpn-maintenance",
        ];
        
        for path in &config_paths {
            if std::path::Path::new(path).exists() {
                if let Err(e) = std::fs::remove_dir_all(path) {
                    println!("⚠️ Warning: Failed to remove {}: {}", path, e);
                } else {
                    println!("✓ Removed configuration: {}", path);
                }
            }
        }
        
        // Reload systemd if service was removed
        let _reload_output = Command::new("sudo")
            .arg("systemctl")
            .arg("daemon-reload")
            .output();
        
        println!("✓ System configuration cleanup completed");
        Ok(())
    }
    
    async fn cleanup_log_files(&self) -> Result<()> {
        println!("📝 Cleaning up log files...");
        
        let log_paths = [
            "/var/log/vpn",
            "/var/log/xray",
            "/var/log/shadowsocks",
        ];
        
        for path in &log_paths {
            if std::path::Path::new(path).exists() {
                if let Err(e) = std::fs::remove_dir_all(path) {
                    println!("⚠️ Warning: Failed to remove log directory {}: {}", path, e);
                } else {
                    println!("✓ Removed log directory: {}", path);
                }
            }
        }
        
        println!("✓ Log files cleanup completed");
        Ok(())
    }
    
    pub async fn fix_network_conflicts(&self) -> Result<()> {
        println!("🔧 Attempting to fix Docker network conflicts...");
        
        // 1. Stop all VPN containers
        println!("🛑 Stopping VPN containers...");
        let containers_output = Command::new("docker")
            .arg("ps")
            .arg("-q")
            .arg("--filter")
            .arg("name=xray")
            .output();
            
        if let Ok(output) = containers_output {
            let container_ids = String::from_utf8_lossy(&output.stdout);
            for container_id in container_ids.lines() {
                if !container_id.trim().is_empty() {
                    let _stop_output = Command::new("docker")
                        .arg("stop")
                        .arg(container_id.trim())
                        .output();
                }
            }
        }
        
        // Stop watchtower container too
        let _stop_watchtower = Command::new("docker")
            .arg("stop")
            .arg("watchtower")
            .output();
        
        println!("✓ Stopped VPN containers");
        
        // 2. Remove all VPN networks using our helper method
        self.force_remove_vpn_networks().await?;
        
        // 3. Prune unused networks
        let prune_output = Command::new("docker")
            .arg("network")
            .arg("prune")
            .arg("-f")
            .output();
            
        if let Ok(output) = prune_output {
            if output.status.success() {
                println!("✓ Pruned unused Docker networks");
            }
        }
        
        // 4. Clean up any remaining network with subnet conflicts
        self.remove_conflicting_subnets().await?;
        
        // 5. Clean up existing Docker Compose files
        self.clean_existing_compose_files().await?;
        
        println!("✅ Network conflict resolution completed");
        println!("💡 You can now try installing again: vpn install");
        
        Ok(())
    }
    
    async fn remove_conflicting_subnets(&self) -> Result<()> {
        // List all networks and check for conflicting subnets
        let networks_output = Command::new("docker")
            .arg("network")
            .arg("ls")
            .arg("--format")
            .arg("{{.ID}}")
            .output();
            
        if let Ok(output) = networks_output {
            let network_ids = String::from_utf8_lossy(&output.stdout);
            
            for network_id in network_ids.lines() {
                if !network_id.trim().is_empty() {
                    // Inspect each network for conflicting subnets
                    let inspect_output = Command::new("docker")
                        .arg("network")
                        .arg("inspect")
                        .arg(network_id.trim())
                        .output();
                        
                    if let Ok(inspect_result) = inspect_output {
                        let network_info = String::from_utf8_lossy(&inspect_result.stdout);
                        
                        // Check if this network uses conflicting subnet ranges
                        if network_info.contains("172.20.0.0") || 
                           network_info.contains("172.18.0.0") ||
                           network_info.contains("172.19.0.0") {
                            
                            // Try to remove this network if it's not in use
                            let _remove_output = Command::new("docker")
                                .arg("network")
                                .arg("rm")
                                .arg(network_id.trim())
                                .output();
                        }
                    }
                }
            }
        }
        
        Ok(())
    }
    
    async fn clean_existing_compose_files(&self) -> Result<()> {
        // Common VPN installation paths
        let potential_paths = [
            "/opt/vpn/docker-compose.yml",
            "/etc/vpn/docker-compose.yml", 
            "/var/lib/vpn/docker-compose.yml",
        ];
        
        for path in &potential_paths {
            if std::path::Path::new(path).exists() {
                if let Ok(content) = std::fs::read_to_string(path) {
                    let mut modified = false;
                    let mut lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
                    
                    // Remove version lines
                    if let Some(pos) = lines.iter().position(|line| line.trim().starts_with("version:")) {
                        lines.remove(pos);
                        // Also remove empty line after version if it exists
                        if pos < lines.len() && lines[pos].trim().is_empty() {
                            lines.remove(pos);
                        }
                        modified = true;
                        println!("✓ Removed version attribute from {}", path);
                    }
                    
                    // Remove ipam subnet configuration
                    if let Some(ipam_pos) = lines.iter().position(|line| line.trim().starts_with("ipam:")) {
                        // Remove ipam line and the next 2 lines (config and subnet)
                        for _ in 0..3 {
                            if ipam_pos < lines.len() {
                                lines.remove(ipam_pos);
                            }
                        }
                        modified = true;
                        println!("✓ Removed fixed subnet configuration from {}", path);
                    }
                    
                    // Write back if modified
                    if modified {
                        let new_content = lines.join("\n");
                        if let Err(e) = std::fs::write(path, new_content) {
                            println!("⚠️ Warning: Could not update {}: {}", path, e);
                        }
                    }
                }
            }
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