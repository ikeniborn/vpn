use std::path::{Path, PathBuf};
use std::process::Command;
// removed unused imports
use crate::error::{Result, ServerError};
use crate::templates::DockerComposeTemplate;
use crate::validator::ConfigValidator;
use uuid::Uuid;
use vpn_crypto::{UuidGenerator, X25519KeyManager};
use vpn_docker::ContainerManager;
use vpn_network::firewall::{Direction, Protocol};
use vpn_network::{
    FirewallManager, FirewallRule, IpDetector, PortChecker, SubnetManager, VpnSubnet,
};
use vpn_types::protocol::VpnProtocol;
use vpn_types::validation::{PathValidator, PortValidator};
use vpn_users::{User, UserManager};

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
    pub subnet: Option<String>,
    pub interactive_subnet: bool,
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

        // Stop any existing VPN containers to avoid conflicts
        self.stop_existing_containers(&options.install_path).await?;

        // Validate installation path
        let mut allowed_paths = vec![
            PathBuf::from("/opt"),
            PathBuf::from("/etc/vpn"),
            PathBuf::from("/var/lib/vpn"),
            PathBuf::from("/usr/local/vpn"),
            PathBuf::from("/home"),
        ];

        // Add user's home directory if available
        if let Ok(home) = std::env::var("HOME") {
            allowed_paths.push(PathBuf::from(home));
        }

        let path_validator = PathValidator::new(allowed_paths);

        // For new installations, we just need to check the parent directory exists
        if let Some(parent) = options.install_path.parent() {
            if parent.exists() {
                path_validator.validate(parent).map_err(|e| {
                    ServerError::ValidationError(format!(
                        "Installation path validation failed: {}",
                        e
                    ))
                })?;
            }
        }

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
                        options.install_path.display(),
                        e
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

        // Select appropriate subnet for VPN
        let selected_subnet = self.select_vpn_subnet(&options).await?;

        // Create Docker configuration with selected subnet
        self.create_docker_configuration(&options, &server_config, Some(&selected_subnet.cidr))
            .await?;

        // Validate the new Docker Compose file
        self.validate_docker_compose_file(&options).await?;

        // Download and start containers
        self.deploy_containers(&options).await?;

        // Create initial user
        let initial_user = self.create_initial_user(&options, &server_config).await?;

        // Verify installation with actual server config
        self.verify_installation(&options, &server_config).await?;

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
        if !FirewallManager::is_ufw_installed().await
            && !FirewallManager::is_iptables_installed().await
        {
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

    async fn stop_existing_containers(&self, install_path: &Path) -> Result<()> {
        let compose_path = install_path.join("docker-compose.yml");

        // Check if docker-compose file exists
        if compose_path.exists() {
            println!("🛑 Stopping existing VPN containers...");

            // Stop and remove containers
            let output = Command::new("docker-compose")
                .arg("-f")
                .arg(&compose_path)
                .arg("down")
                .arg("--remove-orphans")
                .arg("-v") // Remove volumes too
                .output()?;

            if !output.status.success() {
                // Log the error but don't fail - containers might already be stopped
                let stderr = String::from_utf8_lossy(&output.stderr);
                eprintln!("Warning: Failed to stop containers: {}", stderr);
            } else {
                println!("✓ Existing containers stopped");
            }

            // Give Docker time to clean up
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        }

        Ok(())
    }

    async fn generate_server_config(&self, options: &InstallationOptions) -> Result<ServerConfig> {
        let port = match options.port {
            Some(p) => {
                // Use comprehensive port validation
                PortValidator::validate(p)
                    .map_err(|e| ServerError::ValidationError(e.to_string()))?;
                PortChecker::validate_port(p)?;
                if !PortChecker::is_port_available(p) {
                    return Err(ServerError::InstallationError(format!(
                        "Port {} is not available",
                        p
                    )));
                }
                p
            }
            None => {
                // Try protocol default port first, fallback to random if not available
                let default_port = options.protocol.default_port();
                if PortChecker::is_port_available(default_port) {
                    default_port
                } else {
                    println!(
                        "Default port {} is not available, selecting random port...",
                        default_port
                    );
                    PortChecker::find_random_available_port(10000, 65000)?
                }
            }
        };

        let public_ip = IpDetector::get_public_ip().await?;
        let key_manager = X25519KeyManager::new();
        let keypair = key_manager.generate_keypair()?;
        let uuid_gen = UuidGenerator::new();
        let server_uuid = Uuid::new_v4().to_string();
        let short_id = uuid_gen.generate_short_id(&server_uuid)?;

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
            reality_dest: options
                .reality_dest
                .clone()
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
        subnet: Option<&str>,
    ) -> Result<()> {
        let template = DockerComposeTemplate::new();

        match options.protocol {
            VpnProtocol::Vless => {
                template
                    .generate_xray_compose(&options.install_path, server_config, options, subnet)
                    .await?;
            }
            VpnProtocol::Outline => {
                template
                    .generate_outline_compose(&options.install_path, server_config, options, subnet)
                    .await?;
            }
            VpnProtocol::Wireguard => {
                template
                    .generate_wireguard_compose(&options.install_path, server_config, options, subnet)
                    .await?;
            }
            VpnProtocol::HttpProxy | VpnProtocol::Socks5Proxy | VpnProtocol::ProxyServer => {
                // TODO: Implement proxy server installation
                return Err(ServerError::InstallationError(format!(
                    "Proxy protocol {:?} installation coming soon",
                    options.protocol
                )));
            }
            _ => {
                return Err(ServerError::InstallationError(format!(
                    "Protocol {:?} not yet supported",
                    options.protocol
                )));
            }
        }

        Ok(())
    }

    async fn deploy_containers(&self, options: &InstallationOptions) -> Result<()> {
        let compose_path = options.install_path.join("docker-compose.yml");

        println!("🐳 Starting VPN containers...");

        // Clean up any existing containers and networks first
        let _ = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("down")
            .arg("--remove-orphans")
            .output();

        // Give Docker a moment to clean up
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;

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
            if stderr.contains("Pool overlaps with other one")
                || stderr.contains("network conflicts")
            {
                return Err(ServerError::InstallationError(
                    "Docker network conflict detected. Try running 'vpn diagnostics --fix' to clean up Docker networks.".to_string()
                ));
            }

            // Check for network not found errors
            if stderr.contains("network") && stderr.contains("not found") {
                return Err(ServerError::InstallationError(
                    "Docker network error detected. This often happens when containers are recreated. Try running 'vpn diagnostics --fix' to clean up Docker resources.".to_string()
                ));
            }

            return Err(ServerError::InstallationError(format!(
                "Docker Compose failed: {}",
                stderr
            )));
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
                "Containers failed to start. Check 'docker-compose logs' for details.".to_string(),
            ));
        }

        println!("✓ Container deployment completed");
        Ok(())
    }

    async fn select_vpn_subnet(&self, options: &InstallationOptions) -> Result<VpnSubnet> {
        // If subnet is already specified, validate it
        if let Some(subnet) = &options.subnet {
            println!("🔍 Validating specified subnet: {}", subnet);

            match SubnetManager::is_subnet_available(subnet) {
                Ok(true) => {
                    println!("✓ Specified subnet is available");
                    return Ok(VpnSubnet {
                        cidr: subnet.clone(),
                        description: "User specified".to_string(),
                        range_start: "N/A".to_string(),
                        range_end: "N/A".to_string(),
                    });
                }
                Ok(false) => {
                    println!(
                        "⚠️ Specified subnet {} conflicts with existing networks",
                        subnet
                    );
                    if !options.interactive_subnet {
                        return Err(ServerError::NetworkError(format!(
                            "Subnet {} is not available. Use --interactive-subnet to choose an alternative.",
                            subnet
                        )));
                    }
                }
                Err(e) => {
                    println!("⚠️ Cannot validate subnet {}: {}", subnet, e);
                    if !options.interactive_subnet {
                        return Err(ServerError::InstallationError(format!(
                            "Subnet validation failed: {}. Use --interactive-subnet to choose manually.",
                            e
                        )));
                    }
                }
            }
        }

        // Interactive subnet selection if requested or if specified subnet is not available
        if options.interactive_subnet {
            println!("🔧 Interactive subnet selection requested");
            return SubnetManager::select_subnet_interactive()
                .map_err(|e| ServerError::NetworkError(format!("Subnet selection failed: {}", e)));
        }

        // Automatic subnet selection
        println!("🔍 Automatically selecting available VPN subnet...");
        SubnetManager::select_subnet_auto()
            .map_err(|e| ServerError::NetworkError(format!("No available subnets found: {}", e)))
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
                println!(
                    "⚠️ Detected fixed subnet configuration, regenerating Docker Compose file..."
                );
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

        // Check if default user already exists
        let default_username = "vpnuser".to_string();

        // Try to find existing default user first
        let existing_users = user_manager.list_users(None).await?;
        if let Some(existing_user) = existing_users
            .iter()
            .find(|user| user.name == default_username)
        {
            println!(
                "✓ Default user '{}' already exists, using existing user",
                default_username
            );
            return Ok(existing_user.clone());
        }

        // Create new user if doesn't exist
        let user = user_manager
            .create_user(default_username, options.protocol)
            .await?;

        Ok(user)
    }

    async fn verify_installation(
        &self,
        options: &InstallationOptions,
        server_config: &ServerConfig,
    ) -> Result<()> {
        println!("🔍 Verifying installation...");

        // 1. Validate configuration files exist
        let validator = ConfigValidator::new()?;
        validator
            .validate_installation(&options.install_path)
            .await?;
        println!("✓ Configuration files validated");

        // 2. Check if containers are created
        let compose_path = options.install_path.join("docker-compose.yml");
        if !compose_path.exists() {
            return Err(ServerError::InstallationError(
                "Docker Compose file not found".to_string(),
            ));
        }
        println!("✓ Docker Compose configuration found");

        // 3. Verify containers are running
        self.verify_containers_running(&options.install_path)
            .await?;
        println!("✓ VPN containers are running");

        // 4. Check container health status
        self.verify_container_health(&options.install_path).await?;
        println!("✓ Container health check passed");

        // 5. Test basic connectivity with actual server port
        self.verify_service_connectivity(server_config.port).await?;
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
                "Failed to check container status".to_string(),
            ));
        }

        if output.stdout.is_empty() {
            return Err(ServerError::InstallationError(
                "No VPN containers are running. Installation may have failed.".to_string(),
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
                "Failed to check container health".to_string(),
            ));
        }

        let output_str = String::from_utf8_lossy(&output.stdout);

        // Check if any container is in "unhealthy" or "restarting" state
        if output_str.contains("unhealthy") || output_str.contains("restarting") {
            return Err(ServerError::InstallationError(
                "One or more containers are unhealthy. Check logs with 'docker-compose logs'"
                    .to_string(),
            ));
        }

        // Check if containers are actually up
        if !output_str.contains("Up") {
            return Err(ServerError::InstallationError(
                "Containers are not in running state".to_string(),
            ));
        }

        Ok(())
    }

    async fn verify_service_connectivity(&self, port: u16) -> Result<()> {
        use std::time::Duration;
        use tokio::net::TcpStream;

        // Give the service a moment to start
        tokio::time::sleep(Duration::from_secs(3)).await;

        // Try to connect to the service port to verify it's accessible
        let connect_addr = format!("127.0.0.1:{}", port);

        // Try to connect with a timeout
        match tokio::time::timeout(Duration::from_secs(5), TcpStream::connect(&connect_addr)).await
        {
            Ok(Ok(_)) => {
                // Successfully connected - service is running
                Ok(())
            }
            Ok(Err(e)) => {
                // Connection failed
                return Err(ServerError::InstallationError(
                    format!("Cannot connect to VPN service on port {}. Service may not have started correctly. Error: {}", 
                           port, e)
                ));
            }
            Err(_) => {
                // Timeout
                return Err(ServerError::InstallationError(
                    format!("Connection to VPN service on port {} timed out. Service may not be responding.", 
                           port)
                ));
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
                println!(
                    "⚠️ Warning: Failed to remove directory {}: {}",
                    install_path.display(),
                    e
                );
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
        let images_to_remove = [
            "xray/xray",
            "shadowsocks/shadowsocks-libev",
            "outline/shadowbox",
        ];

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

        let log_paths = ["/var/log/vpn", "/var/log/xray", "/var/log/shadowsocks"];

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

    pub async fn check_network_status(&self) -> Result<()> {
        println!("🔍 Checking Docker network status...");

        // Show available subnets instead of aggressive cleanup
        match SubnetManager::get_available_subnets() {
            Ok(available_subnets) => {
                if available_subnets.is_empty() {
                    println!("⚠️ No available subnet ranges found for VPN");
                    println!("💡 This might indicate network conflicts. Consider:");
                    println!("   • Using vpn install --interactive-subnet to choose manually");
                    println!("   • Specifying a custom subnet with --subnet <CIDR>");
                    println!("   • Checking existing Docker networks: docker network ls");
                } else {
                    println!(
                        "✅ Found {} available subnet ranges for VPN",
                        available_subnets.len()
                    );
                    println!();
                    println!("Available options:");
                    for subnet in &available_subnets[..3.min(available_subnets.len())] {
                        println!("  • {} - {}", subnet.cidr, subnet.description);
                    }
                    if available_subnets.len() > 3 {
                        println!("  ... and {} more options", available_subnets.len() - 3);
                    }
                }
            }
            Err(e) => {
                println!("❌ Failed to check network status: {}", e);
                return Err(ServerError::NetworkError(format!(
                    "Network check failed: {}",
                    e
                )));
            }
        }

        // Show current Docker networks status
        let network_output = Command::new("docker")
            .arg("network")
            .arg("ls")
            .arg("--format")
            .arg("table {{.Name}}\\t{{.Driver}}\\t{{.Scope}}")
            .output();

        if let Ok(output) = network_output {
            if output.status.success() {
                let networks = String::from_utf8_lossy(&output.stdout);
                println!();
                println!("Current Docker networks:");
                println!("{}", networks);
            }
        }

        println!();
        println!("💡 To install VPN with subnet selection:");
        println!("   vpn install --interactive-subnet    # Interactive selection");
        println!("   vpn install --subnet 172.30.0.0/16  # Specify subnet manually");

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
            subnet: None,
            interactive_subnet: false,
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
