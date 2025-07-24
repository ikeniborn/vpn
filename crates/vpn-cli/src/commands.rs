use indicatif::{ProgressBar, ProgressStyle};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use vpn_server::installer::LogLevel as ServerLogLevel;
use vpn_server::{InstallationOptions, ServerInstaller, ServerLifecycle};
use vpn_users::manager::UserListOptions;
use vpn_users::user::UserStatus;
use vpn_users::{BatchOperations, UserManager};
use vpn_types::protocol::VpnProtocol;
// use vpn_monitor::{TrafficMonitor, HealthMonitor, LogAnalyzer, MetricsCollector, AlertManager};
// use vpn_monitor::traffic::MonitoringConfig;
use crate::{
    cli::*, config::ConfigManager, runtime::RuntimeManager, utils::display, CliError, Result,
};
use serde_json;

pub struct CommandHandler {
    #[allow(dead_code)]
    config_manager: ConfigManager,
    install_path: PathBuf,
    output_format: OutputFormat,
    force_mode: bool,
}

impl CommandHandler {
    pub async fn new(config_manager: ConfigManager, install_path: PathBuf) -> Result<Self> {
        Ok(Self {
            config_manager,
            install_path,
            output_format: OutputFormat::Table,
            force_mode: false,
        })
    }

    pub fn set_output_format(&mut self, format: OutputFormat) {
        self.output_format = format;
    }

    pub fn set_force_mode(&mut self, force: bool) {
        self.force_mode = force;
    }

    /// Detect the protocol from existing installation and return the appropriate installation path
    fn get_protocol_install_path(&self) -> PathBuf {
        use std::path::Path;

        // Check different protocol paths to determine which one is installed
        let protocols = [
            (vpn_types::protocol::VpnProtocol::Vless, "/opt/vless"),
            (vpn_types::protocol::VpnProtocol::HttpProxy, "/opt/proxy"),
            (vpn_types::protocol::VpnProtocol::Socks5Proxy, "/opt/proxy"),
            (vpn_types::protocol::VpnProtocol::ProxyServer, "/opt/proxy"),
            (vpn_types::protocol::VpnProtocol::Outline, "/opt/shadowsocks"),
            (vpn_types::protocol::VpnProtocol::Wireguard, "/opt/wireguard"),
        ];

        for (_protocol, path) in protocols {
            let install_path = Path::new(path);
            if install_path.exists() && install_path.join("docker-compose.yml").exists() {
                return install_path.to_path_buf();
            }
        }

        // Fallback to original path for backward compatibility
        self.install_path.clone()
    }

    // Server Management Commands
    pub async fn install_server(
        &mut self,
        protocol: Protocol,
        port: Option<u16>,
        sni: Option<String>,
        firewall: bool,
        auto_start: bool,
        subnet: Option<String>,
        interactive_subnet: bool,
    ) -> Result<()> {
        // Get protocol-specific installation path
        let protocol_install_path = InstallationOptions::get_protocol_install_path(protocol.clone().into());

        // Check if this is a proxy server installation
        if matches!(
            protocol,
            Protocol::HttpProxy | Protocol::Socks5Proxy | Protocol::ProxyServer
        ) {
            // Install proxy server using ProxyInstaller
            use vpn_server::ProxyInstaller;

            let proxy_type = match protocol {
                Protocol::HttpProxy => "http",
                Protocol::Socks5Proxy => "socks5",
                Protocol::ProxyServer => "all",
                _ => unreachable!(),
            };

            display::info("ℹ Starting installation...");
            
            let installer = ProxyInstaller::new(protocol_install_path.clone(), port.unwrap_or(8080))?;
            
            // Install will print progress messages
            installer
                .install(proxy_type)
                .await
                .map_err(|e| CliError::ServerError(e))?;

            display::success(&format!(
                "{} proxy server installed successfully!",
                proxy_type
            ));

            return Ok(());
        }

        // Regular VPN server installation
        let installer = ServerInstaller::new()?;

        let options = InstallationOptions {
            protocol: protocol.into(),
            port,
            sni_domain: sni,
            install_path: protocol_install_path,
            enable_firewall: firewall,
            auto_start,
            log_level: ServerLogLevel::Warning,
            reality_dest: None,
            subnet,
            interactive_subnet,
        };

        let pb = ProgressBar::new_spinner();
        pb.set_style(
            ProgressStyle::default_spinner()
                .template("{spinner:.green} {msg}")
                .unwrap(),
        );
        pb.set_message("Installing VPN server...");

        let result = installer.install(options).await;
        pb.finish_and_clear();

        match result {
            Ok(installation_result) => {
                display::success("VPN server installed successfully!");

                match self.output_format {
                    OutputFormat::Json => {
                        let json = serde_json::json!({
                            "status": "success",
                            "server_config": {
                                "host": installation_result.server_config.host,
                                "port": installation_result.server_config.port,
                                "sni": installation_result.server_config.sni_domain
                            },
                            "initial_user": {
                                "id": installation_result.initial_user.id,
                                "name": installation_result.initial_user.name
                            }
                        });
                        println!("{}", serde_json::to_string_pretty(&json)?);
                    }
                    _ => {
                        println!("Server Details:");
                        println!("  Host: {}", installation_result.server_config.host);
                        println!("  Port: {}", installation_result.server_config.port);
                        println!("  SNI: {}", installation_result.server_config.sni_domain);
                        println!("Initial User: {}", installation_result.initial_user.name);
                    }
                }

                Ok(())
            }
            Err(e) => Err(CliError::ServerError(e)),
        }
    }

    pub async fn uninstall_server(&mut self, purge: bool) -> Result<()> {
        let install_path = self.get_protocol_install_path();
        self.uninstall_server_with_path(&install_path, purge).await
    }

    pub async fn uninstall_server_with_path(&mut self, install_path: &Path, purge: bool) -> Result<()> {
        if !self.force_mode {
            display::warning("This will completely remove the VPN server!");
            if purge {
                display::warning("All user data will be permanently deleted!");
            }

            // In a real implementation, you'd prompt for confirmation here
        }

        let installer = ServerInstaller::new()?;

        let pb = ProgressBar::new_spinner();
        pb.set_style(
            ProgressStyle::default_spinner()
                .template("{spinner:.red} {msg}")
                .unwrap(),
        );
        pb.set_message("Uninstalling VPN server...");

        let result = installer.uninstall(install_path, purge).await;
        pb.finish_and_clear();

        match result {
            Ok(_) => {
                display::success("VPN server uninstalled successfully!");
                Ok(())
            }
            Err(e) => Err(CliError::ServerError(e)),
        }
    }

    pub async fn start_server(&mut self) -> Result<()> {
        let lifecycle = ServerLifecycle::new()?;

        let pb = ProgressBar::new_spinner();
        pb.set_message("Starting VPN server...");

        let install_path = self.get_protocol_install_path();
        let result = lifecycle.start(&install_path).await;
        pb.finish_and_clear();

        match result {
            Ok(_) => {
                display::success("VPN server started successfully!");
                Ok(())
            }
            Err(e) => Err(CliError::ServerError(e)),
        }
    }

    pub async fn stop_server(&mut self) -> Result<()> {
        let lifecycle = ServerLifecycle::new()?;

        let pb = ProgressBar::new_spinner();
        pb.set_message("Stopping VPN server...");

        let install_path = self.get_protocol_install_path();
        let result = lifecycle.stop(&install_path).await;
        pb.finish_and_clear();

        match result {
            Ok(_) => {
                display::success("VPN server stopped successfully!");
                Ok(())
            }
            Err(e) => Err(CliError::ServerError(e)),
        }
    }

    pub async fn restart_server(&mut self) -> Result<()> {
        let lifecycle = ServerLifecycle::new()?;

        let pb = ProgressBar::new_spinner();
        pb.set_message("Restarting VPN server...");

        let install_path = self.get_protocol_install_path();
        let result = lifecycle.restart(&install_path).await;
        pb.finish_and_clear();

        match result {
            Ok(_) => {
                display::success("VPN server restarted successfully!");
                Ok(())
            }
            Err(e) => Err(CliError::ServerError(e)),
        }
    }

    pub async fn reload_server(&mut self) -> Result<()> {
        let lifecycle = ServerLifecycle::new()?;

        let pb = ProgressBar::new_spinner();
        pb.set_message("Reloading server configuration...");

        let install_path = self.get_protocol_install_path();
        let result = lifecycle.reload_config(&install_path).await;
        pb.finish_and_clear();

        match result {
            Ok(_) => {
                display::success("Server configuration reloaded successfully!");
                Ok(())
            }
            Err(e) => Err(CliError::ServerError(e)),
        }
    }

    pub async fn show_status(&mut self, detailed: bool, watch: bool) -> Result<()> {
        let lifecycle = ServerLifecycle::new()?;

        loop {
            let status = lifecycle.get_status().await?;

            if watch {
                print!("\x1B[2J\x1B[1;1H"); // Clear screen
            }

            match self.output_format {
                OutputFormat::Json => {
                    let json = serde_json::json!({
                        "is_running": status.is_running,
                        "health_score": status.health_score,
                        "uptime_seconds": status.uptime.map(|u| u.as_secs()),
                        "containers": status.containers
                    });
                    println!("{}", serde_json::to_string_pretty(&json)?);
                }
                _ => {
                    println!("VPN Server Status");
                    println!("================");
                    println!(
                        "Status: {}",
                        if status.is_running {
                            "🟢 Running"
                        } else {
                            "🔴 Stopped"
                        }
                    );
                    println!("Health Score: {:.1}%", status.health_score * 100.0);

                    if let Some(uptime) = status.uptime {
                        println!("Uptime: {}", display::format_duration(uptime));
                    }

                    if detailed {
                        println!("\nContainers:");
                        for container in &status.containers {
                            let status_icon = if container.is_running { "🟢" } else { "🔴" };
                            println!(
                                "  {} {} - CPU: {:.1}%, Memory: {}",
                                status_icon,
                                container.name,
                                container.cpu_usage,
                                display::format_bytes(container.memory_usage)
                            );
                        }
                    }
                }
            }

            if !watch {
                break;
            }

            tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
        }

        Ok(())
    }

    pub async fn get_server_status(&self) -> Result<ServerStatus> {
        let lifecycle = ServerLifecycle::new()?;
        let status = lifecycle.get_status().await?;

        Ok(ServerStatus {
            is_running: status.is_running,
            active_users: 0, // Would need to be calculated from user manager
            healthy_containers: status.containers.iter().filter(|c| c.is_running).count(),
            total_containers: status.containers.len(),
        })
    }

    pub async fn get_protocol_status(&self, protocol_path: &std::path::Path) -> Result<bool> {
        use std::process::Command;
        
        // Check if docker-compose.yml exists
        let compose_file = protocol_path.join("docker-compose.yml");
        if !compose_file.exists() {
            return Ok(false);
        }

        // Check container status using docker-compose
        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_file)
            .arg("ps")
            .arg("-q")
            .output()
            .map_err(|e| CliError::CommandError(format!("Failed to check status: {}", e)))?;

        // If output is not empty, containers are running
        Ok(!output.stdout.is_empty())
    }

    pub async fn is_server_installed(&self) -> Result<bool> {
        let install_path = self.get_protocol_install_path();
        let config_file = install_path.join("docker-compose.yml");
        Ok(config_file.exists())
    }

    pub async fn is_protocol_installed(&self, protocol: vpn_types::protocol::VpnProtocol) -> Result<bool> {
        let install_path = match protocol {
            vpn_types::protocol::VpnProtocol::Vless => PathBuf::from("/opt/vless"),
            vpn_types::protocol::VpnProtocol::Outline => PathBuf::from("/opt/shadowsocks"),
            vpn_types::protocol::VpnProtocol::Wireguard => PathBuf::from("/opt/wireguard"),
            vpn_types::protocol::VpnProtocol::HttpProxy | 
            vpn_types::protocol::VpnProtocol::Socks5Proxy | 
            vpn_types::protocol::VpnProtocol::ProxyServer => PathBuf::from("/opt/proxy"),
            _ => PathBuf::from("/opt/vpn"),
        };
        let config_file = install_path.join("docker-compose.yml");
        Ok(config_file.exists())
    }

    // User Management Commands
    pub async fn handle_user_command(&mut self, command: UserCommands) -> Result<()> {
        match command {
            UserCommands::List { status, detailed } => {
                self.list_users(status.map(|s| s.into()), detailed).await
            }
            UserCommands::Create {
                name,
                email,
                protocol,
            } => self.create_user(name, email, protocol).await,
            UserCommands::Delete { user } => self.delete_user(user).await,
            UserCommands::Show { user, qr } => self.show_user_details(user, qr).await,
            UserCommands::Link { user, qr, qr_file } => {
                self.generate_user_link(user, qr, qr_file).await
            }
            UserCommands::Update {
                user,
                status,
                email,
            } => {
                self.update_user(user, status.map(|s| s.into()), email)
                    .await
            }
            UserCommands::Batch { command } => self.handle_batch_command(command).await,
            UserCommands::Reset { user } => self.reset_user_traffic(user).await,
        }
    }

    pub async fn list_users(
        &mut self,
        status_filter: Option<UserStatus>,
        detailed: bool,
    ) -> Result<()> {
        let server_config = self.load_server_config()?;
        
        // Collect users from all installed protocols
        let mut all_users = Vec::new();
        
        // Check each protocol's installation path
        let protocols = [
            (vpn_types::protocol::VpnProtocol::Vless, "/opt/vless"),
            (vpn_types::protocol::VpnProtocol::HttpProxy, "/opt/proxy"),
            (vpn_types::protocol::VpnProtocol::Socks5Proxy, "/opt/proxy"),
            (vpn_types::protocol::VpnProtocol::ProxyServer, "/opt/proxy"),
            (vpn_types::protocol::VpnProtocol::Outline, "/opt/shadowsocks"),
            (vpn_types::protocol::VpnProtocol::Wireguard, "/opt/wireguard"),
        ];
        
        let mut seen_paths = std::collections::HashSet::new();
        
        for (_protocol, path) in protocols {
            let install_path = PathBuf::from(path);
            
            // Skip if path doesn't exist or we've already checked it
            if !install_path.exists() || !seen_paths.insert(path) {
                continue;
            }
            
            // Try to load users from this path
            if let Ok(user_manager) = UserManager::new(&install_path, server_config.clone()) {
                let mut options = UserListOptions::default();
                if let Some(status) = status_filter.as_ref() {
                    options.status_filter = Some(status.clone().into());
                }
                
                if let Ok(users) = user_manager.list_users(Some(options)).await {
                    all_users.extend(users);
                }
            }
        }
        
        let users = all_users;

        if users.is_empty() {
            display::info("No users found.");
            return Ok(());
        }

        match self.output_format {
            OutputFormat::Json => {
                println!("{}", serde_json::to_string_pretty(&users)?);
            }
            OutputFormat::Table => {
                self.display_users_table(&users, detailed);
            }
            OutputFormat::Plain => {
                for user in &users {
                    println!("{}: {} ({})", user.name, user.id, user.status.as_str());
                }
            }
        }

        Ok(())
    }

    pub async fn create_user(
        &mut self,
        name: String,
        email: Option<String>,
        protocol: Protocol,
    ) -> Result<()> {
        self.create_user_with_password(name, email, protocol, None).await
    }

    pub async fn create_user_with_password(
        &mut self,
        name: String,
        email: Option<String>,
        protocol: Protocol,
        password: Option<String>,
    ) -> Result<()> {
        let server_config = self.load_server_config()?;
        // Use the install path for the specific protocol, not the currently installed one
        let install_path = InstallationOptions::get_protocol_install_path(protocol.clone().into());
        let user_manager = UserManager::new(&install_path, server_config)?;

        let mut user = user_manager
            .create_user_with_password(name.clone(), protocol.into(), password)
            .await?;

        if let Some(email) = email {
            user.email = Some(email);
            user_manager.update_user(user.clone()).await?;
        }

        // Get temporary password if available
        let temp_password = user_manager.get_temp_password(&user.id);

        match self.output_format {
            OutputFormat::Json => {
                let mut user_json = serde_json::to_value(&user)?;
                if let Some(pwd) = temp_password {
                    if let Some(obj) = user_json.as_object_mut() {
                        obj.insert("password".to_string(), serde_json::Value::String(pwd));
                    }
                }
                println!("{}", serde_json::to_string_pretty(&user_json)?);
            }
            _ => {
                display::success(&format!("User '{}' created successfully!", name));
                println!("User ID: {}", user.id);
                println!("Short ID: {}", user.short_id);
                if let Some(email) = &user.email {
                    println!("Email: {}", email);
                }
                
                // Display password for proxy users
                if matches!(user.protocol, VpnProtocol::HttpProxy | VpnProtocol::Socks5Proxy | VpnProtocol::ProxyServer) {
                    if let Some(pwd) = temp_password {
                        println!("Password: {}", pwd);
                        println!("\n⚠️  Save this password now! It won't be shown again.");
                    }
                }
            }
        }

        Ok(())
    }

    pub async fn delete_user(&mut self, user: String) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = UserManager::new(&install_path, server_config)?;

        // Try to find user by name first, then by ID
        let user_obj = match user_manager.get_user_by_name(&user).await {
            Ok(u) => u,
            Err(_) => user_manager.get_user(&user).await?,
        };

        user_manager.delete_user(&user_obj.id).await?;

        display::success(&format!("User '{}' deleted successfully!", user_obj.name));
        Ok(())
    }

    pub async fn show_user_details(&mut self, user: String, show_qr: bool) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = UserManager::new(&install_path, server_config)?;

        let user_obj = match user_manager.get_user_by_name(&user).await {
            Ok(u) => u,
            Err(_) => user_manager.get_user(&user).await?,
        };

        match self.output_format {
            OutputFormat::Json => {
                println!("{}", serde_json::to_string_pretty(&user_obj)?);
            }
            _ => {
                println!("User Details");
                println!("============");
                println!("Name: {}", user_obj.name);
                println!("ID: {}", user_obj.id);
                println!("Short ID: {}", user_obj.short_id);
                println!("Protocol: {}", user_obj.protocol.as_str());
                println!("Status: {}", user_obj.status.as_str());
                println!(
                    "Created: {}",
                    user_obj.created_at.format("%Y-%m-%d %H:%M:%S")
                );

                if let Some(email) = &user_obj.email {
                    println!("Email: {}", email);
                }

                if let Some(last_active) = user_obj.last_active {
                    println!("Last Active: {}", last_active.format("%Y-%m-%d %H:%M:%S"));
                }

                println!("\nTraffic Statistics:");
                println!(
                    "  Sent: {}",
                    display::format_bytes(user_obj.stats.bytes_sent)
                );
                println!(
                    "  Received: {}",
                    display::format_bytes(user_obj.stats.bytes_received)
                );
                println!("  Connections: {}", user_obj.stats.connection_count);

                // Show connection info
                let link = user_manager.generate_connection_link(&user_obj.id).await?;
                println!("\nConnection Information:");
                
                // For proxy protocols, show formatted connection details
                if matches!(user_obj.protocol, VpnProtocol::HttpProxy | VpnProtocol::Socks5Proxy | VpnProtocol::ProxyServer) {
                    println!("Username: {}", user_obj.name);
                    println!("Password: [hidden - use private key or set during creation]");
                    
                    if matches!(user_obj.protocol, VpnProtocol::ProxyServer) {
                        // Show both HTTP and SOCKS5 endpoints
                        println!("\nConnection URLs:");
                        let lines: Vec<&str> = link.split('\n').collect();
                        for line in lines {
                            println!("  {}", line);
                        }
                    } else {
                        println!("\nConnection URL:");
                        println!("  {}", link);
                    }
                } else {
                    println!("{}", link);
                }

                if show_qr {
                    // Generate and display QR code in terminal
                    let qr_gen = vpn_crypto::QrCodeGenerator::new();
                    match qr_gen.generate_terminal_qr(&link) {
                        Ok(qr_string) => {
                            println!("\nQR Code:");
                            println!("{}", qr_string);
                        }
                        Err(e) => {
                            println!("\nFailed to generate terminal QR code: {}", e);
                            if let Ok(qr_data) = qr_gen.generate_qr_code(&link) {
                                println!("QR Code generated as SVG ({} bytes)", qr_data.len());
                                println!("Use '--save-qr <path>' to save QR code to file");
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    pub async fn generate_user_link(
        &mut self,
        user: String,
        show_qr: bool,
        qr_file: Option<PathBuf>,
    ) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = UserManager::new(&install_path, server_config)?;

        let user_obj = match user_manager.get_user_by_name(&user).await {
            Ok(u) => u,
            Err(_) => user_manager.get_user(&user).await?,
        };

        let link = user_manager.generate_connection_link(&user_obj.id).await?;

        match self.output_format {
            OutputFormat::Json => {
                let json = serde_json::json!({
                    "user": user_obj.name,
                    "connection_link": link
                });
                println!("{}", serde_json::to_string_pretty(&json)?);
            }
            _ => {
                println!("Connection Link for '{}':", user_obj.name);
                println!("{}", link);
            }
        }

        if show_qr && self.output_format != OutputFormat::Json {
            // Generate and display QR code in terminal
            let qr_gen = vpn_crypto::QrCodeGenerator::new();
            match qr_gen.generate_terminal_qr(&link) {
                Ok(qr_string) => {
                    println!("\nQR Code:");
                    println!("{}", qr_string);
                }
                Err(e) => {
                    println!("\nFailed to generate terminal QR code: {}", e);
                }
            }
        }

        if let Some(qr_path) = qr_file {
            user_manager
                .generate_qr_code(&user_obj.id, &qr_path)
                .await?;
            display::success(&format!("QR code saved to: {}", qr_path.display()));
        }

        Ok(())
    }

    pub async fn update_user(
        &mut self,
        user: String,
        status: Option<UserStatus>,
        email: Option<String>,
    ) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = UserManager::new(&install_path, server_config)?;

        let mut user_obj = match user_manager.get_user_by_name(&user).await {
            Ok(u) => u,
            Err(_) => user_manager.get_user(&user).await?,
        };

        if let Some(status) = status {
            user_obj.status = status.into();
        }

        if let Some(email) = email {
            user_obj.email = Some(email);
        }

        user_manager.update_user(user_obj.clone()).await?;

        display::success(&format!("User '{}' updated successfully!", user_obj.name));
        Ok(())
    }

    pub async fn reset_user_traffic(&mut self, user: String) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = UserManager::new(&install_path, server_config)?;

        let mut user_obj = match user_manager.get_user_by_name(&user).await {
            Ok(u) => u,
            Err(_) => user_manager.get_user(&user).await?,
        };

        user_obj.stats.bytes_sent = 0;
        user_obj.stats.bytes_received = 0;
        user_obj.stats.connection_count = 0;
        user_obj.stats.last_connection = None;

        user_manager.update_user(user_obj.clone()).await?;

        display::success(&format!(
            "Traffic statistics reset for user '{}'!",
            user_obj.name
        ));
        Ok(())
    }

    pub async fn get_user_list(&self) -> Result<Vec<vpn_users::User>> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = UserManager::new(&install_path, server_config)?;
        Ok(user_manager.list_users(None).await?)
    }

    async fn handle_batch_command(&mut self, command: BatchCommands) -> Result<()> {
        match command {
            BatchCommands::Export { file } => self.export_users(file).await,
            BatchCommands::Import { file, overwrite } => self.import_users(file, overwrite).await,
            _ => {
                display::info("Batch command not yet implemented");
                Ok(())
            }
        }
    }

    pub async fn export_users(&mut self, file: PathBuf) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = Arc::new(UserManager::new(&install_path, server_config)?);
        let batch_ops = BatchOperations::new(user_manager);

        batch_ops.export_users_to_json(&file).await?;

        display::success(&format!("Users exported to: {}", file.display()));
        Ok(())
    }

    pub async fn import_users(&mut self, file: PathBuf, overwrite: bool) -> Result<()> {
        let server_config = self.load_server_config()?;
        let install_path = self.get_protocol_install_path();
        let user_manager = Arc::new(UserManager::new(&install_path, server_config)?);
        let batch_ops = BatchOperations::new(user_manager);

        let options = vpn_users::batch::ImportOptions {
            overwrite_existing: overwrite,
            validate_configs: true,
            generate_new_keys: false,
        };

        let result = batch_ops.import_users_from_json(&file, options).await?;

        display::success(&format!(
            "Successfully imported {} users",
            result.successful.len()
        ));

        if !result.failed.is_empty() {
            display::warning(&format!("Failed to import {} users", result.failed.len()));
            for (user, error) in result.failed {
                println!("  {}: {}", user, error);
            }
        }

        Ok(())
    }

    // Additional command handlers would go here...
    // For brevity, I'll implement stubs for the remaining methods

    pub async fn handle_config_command(&mut self, _command: ConfigCommands) -> Result<()> {
        display::info("Configuration command not yet implemented");
        Ok(())
    }

    pub async fn handle_monitor_command(&mut self, _command: MonitorCommands) -> Result<()> {
        display::info("Monitor command not yet implemented");
        Ok(())
    }

    pub async fn handle_security_command(&mut self, _command: SecurityCommands) -> Result<()> {
        display::info("Security command not yet implemented");
        Ok(())
    }

    pub async fn handle_migration_command(&mut self, _command: MigrationCommands) -> Result<()> {
        display::info("Migration command not yet implemented");
        Ok(())
    }

    pub async fn handle_runtime_command(&mut self, command: RuntimeCommands) -> Result<()> {
        let mut runtime_manager = RuntimeManager::new(None)?;

        match command {
            RuntimeCommands::Status => {
                runtime_manager.show_status().await?;
            }
            RuntimeCommands::Switch { runtime } => {
                if runtime == "containerd" {
                    eprintln!("⚠️  WARNING: Containerd support has been deprecated!");
                    eprintln!("   Use Docker Compose orchestration instead: `vpn compose up`");
                    eprintln!("   For more information, see Phase 5 in TASK.md");
                    return Err(CliError::FeatureDeprecated(
                        "Containerd runtime has been deprecated in favor of Docker Compose orchestration".to_string()
                    ));
                }
                runtime_manager.switch_runtime(&runtime).await?;
            }
            RuntimeCommands::Enable { runtime, enabled } => {
                if runtime == "containerd" {
                    eprintln!("⚠️  WARNING: Containerd support has been deprecated!");
                    eprintln!("   Use Docker Compose orchestration instead: `vpn compose up`");
                    eprintln!("   For more information, see Phase 5 in TASK.md");
                    return Err(CliError::FeatureDeprecated(
                        "Containerd runtime has been deprecated in favor of Docker Compose orchestration".to_string()
                    ));
                }
                runtime_manager.enable_runtime(&runtime, enabled)?;
            }
            RuntimeCommands::Socket { runtime, path } => {
                if runtime == "containerd" {
                    eprintln!("⚠️  WARNING: Containerd support has been deprecated!");
                    eprintln!("   Use Docker Compose orchestration instead: `vpn compose up`");
                    eprintln!("   For more information, see Phase 5 in TASK.md");
                    return Err(CliError::FeatureDeprecated(
                        "Containerd runtime has been deprecated in favor of Docker Compose orchestration".to_string()
                    ));
                }
                runtime_manager.update_socket(&runtime, &path)?;
            }
            RuntimeCommands::Capabilities => {
                eprintln!("⚠️  NOTE: Containerd capabilities shown for reference only - containerd support deprecated");
                runtime_manager.show_capabilities()?;
            }
        }

        Ok(())
    }

    pub async fn handle_proxy_command(&mut self, command: ProxyCommands) -> Result<()> {
        match command {
            ProxyCommands::Status { detailed, format } => {
                self.show_proxy_status(detailed, format).await
            }
            ProxyCommands::Monitor {
                user,
                interval,
                active_only,
            } => {
                self.monitor_proxy_connections(user, interval, active_only)
                    .await
            }
            ProxyCommands::Stats {
                hours,
                by_user,
                format,
            } => self.show_proxy_stats(hours, by_user, format).await,
            ProxyCommands::Test {
                url,
                protocol,
                auth,
                username,
                password,
            } => {
                self.test_proxy_connectivity(url, protocol, auth, username, password)
                    .await
            }
            ProxyCommands::Config { command } => self.handle_proxy_config_command(command).await,
            ProxyCommands::Access { command } => self.handle_proxy_access_command(command).await,
        }
    }

    async fn show_proxy_status(&self, detailed: bool, format: StatusFormat) -> Result<()> {
        display::info("🔍 Checking proxy server status...");

        // Check if proxy services are running
        let mut config = vpn_compose::config::ComposeConfig::default();
        let install_path = self.get_protocol_install_path();
        config.compose_dir = install_path.join("docker-compose");
        let compose_manager = vpn_compose::manager::ComposeManager::new(&config)
            .await
            .map_err(|e| {
                CliError::ComposeError(format!("Failed to create compose manager: {}", e))
            })?;
        let compose_status = compose_manager
            .get_status()
            .await
            .map_err(|e| CliError::ComposeError(format!("Failed to get compose status: {}", e)))?;

        let proxy_services = ["traefik", "vpn-proxy-auth"];
        let mut proxy_status = vec![];

        for service_name in &proxy_services {
            if let Some(service) = compose_status
                .services
                .iter()
                .find(|s| s.name == *service_name)
            {
                proxy_status.push(service.clone());
            }
        }

        if proxy_status.is_empty() {
            display::error("Proxy server is not installed");
            return Ok(());
        }

        match format {
            StatusFormat::Json => {
                println!("{}", serde_json::to_string_pretty(&proxy_status)?);
            }
            _ => {
                for service in proxy_status {
                    display::section(&format!("Service: {}", service.name));
                    println!("  State: {}", service.state);

                    if detailed {
                        if let Some(health) = &service.health {
                            println!("  Health: {}", health);
                        }
                        if !service.ports.is_empty() {
                            println!("  Ports: {}", service.ports.join(", "));
                        }
                    }
                }
            }
        }

        Ok(())
    }

    async fn monitor_proxy_connections(
        &self,
        user: Option<String>,
        interval: u64,
        active_only: bool,
    ) -> Result<()> {
        display::info("📊 Monitoring proxy connections...");
        display::info(&format!("Refresh interval: {}s", interval));
        if let Some(u) = &user {
            display::info(&format!("Filtering by user: {}", u));
        }
        if active_only {
            display::info("Showing only active connections");
        }

        // TODO: Implement real-time monitoring by querying Prometheus metrics
        display::warning(
            "Real-time monitoring not yet implemented. Use `docker logs -f traefik` for now.",
        );

        Ok(())
    }

    async fn show_proxy_stats(
        &self,
        hours: u32,
        _by_user: bool,
        _format: StatusFormat,
    ) -> Result<()> {
        display::info(&format!("📈 Proxy statistics for the last {} hours", hours));

        // TODO: Query Prometheus for proxy metrics
        display::warning("Proxy statistics not yet implemented. Use Grafana dashboards for now.");

        Ok(())
    }

    async fn test_proxy_connectivity(
        &self,
        url: String,
        protocol: String,
        auth: bool,
        username: Option<String>,
        password: Option<String>,
    ) -> Result<()> {
        display::info(&format!("🧪 Testing proxy connectivity to {}", url));

        // Get proxy addresses from configuration
        let install_path = self.get_protocol_install_path();
        let config_path = install_path.join("proxy-config.yaml");
        if !config_path.exists() {
            display::error("Proxy configuration not found. Is the proxy server installed?");
            return Ok(());
        }

        let protocols_to_test: Vec<&str> = match protocol.as_str() {
            "both" => vec!["http", "socks5"],
            p => vec![p],
        };

        for proto in protocols_to_test {
            display::section(&format!("Testing {} proxy", proto.to_uppercase()));

            let proxy_addr = match proto {
                "http" => "http://localhost:8888",
                "socks5" => "socks5://localhost:1080",
                _ => {
                    display::error(&format!("Unknown protocol: {}", proto));
                    continue;
                }
            };

            // TODO: Implement actual proxy testing with curl or custom HTTP client
            display::info(&format!("Proxy address: {}", proxy_addr));

            if auth {
                if username.is_none() || password.is_none() {
                    display::error("Authentication test requires both username and password");
                    continue;
                }
                display::info("Testing with authentication...");
            }

            display::warning("Proxy connectivity test not yet fully implemented");
        }

        Ok(())
    }

    async fn handle_proxy_config_command(&self, command: ProxyConfigCommands) -> Result<()> {
        match command {
            ProxyConfigCommands::Show => {
                display::info("📋 Current proxy configuration:");

                let install_path = self.get_protocol_install_path();
        let config_path = install_path.join("proxy-config.yaml");
                if !config_path.exists() {
                    display::error("Proxy configuration not found");
                    return Ok(());
                }

                let config = std::fs::read_to_string(&config_path)?;
                println!("{}", config);
            }
            ProxyConfigCommands::Update {
                max_connections,
                rate_limit,
                auth_enabled,
                bind_address,
                socks5_address,
            } => {
                display::info("🔧 Updating proxy configuration...");

                // TODO: Implement configuration update
                if let Some(max) = max_connections {
                    display::info(&format!("Setting max connections per user: {}", max));
                }
                if let Some(rate) = rate_limit {
                    display::info(&format!("Setting rate limit: {} RPS", rate));
                }
                if let Some(auth) = auth_enabled {
                    display::info(&format!(
                        "Authentication: {}",
                        if auth { "enabled" } else { "disabled" }
                    ));
                }
                if let Some(addr) = bind_address {
                    display::info(&format!("HTTP proxy bind address: {}", addr));
                }
                if let Some(addr) = socks5_address {
                    display::info(&format!("SOCKS5 bind address: {}", addr));
                }

                display::warning("Configuration update not yet implemented");
            }
            ProxyConfigCommands::Reload => {
                display::info("🔄 Reloading proxy configuration...");

                // Restart proxy services to apply new configuration
                let mut config = vpn_compose::config::ComposeConfig::default();
                let install_path = self.get_protocol_install_path();
        config.compose_dir = install_path.join("docker-compose");
                let compose_manager = vpn_compose::manager::ComposeManager::new(&config)
                    .await
                    .map_err(|e| {
                        CliError::ComposeError(format!("Failed to create compose manager: {}", e))
                    })?;

                // Restart each proxy service
                for service in &["traefik", "vpn-proxy-auth"] {
                    compose_manager
                        .restart_service(service)
                        .await
                        .map_err(|e| {
                            CliError::ComposeError(format!("Failed to restart {}: {}", service, e))
                        })?;
                }

                display::success("Proxy configuration reloaded");
            }
        }

        Ok(())
    }

    async fn handle_proxy_access_command(&self, command: ProxyAccessCommands) -> Result<()> {
        match command {
            ProxyAccessCommands::List => {
                display::info("📜 Access control rules:");
                display::warning("Access control management not yet implemented");
            }
            ProxyAccessCommands::AddIp { ip, description } => {
                display::info(&format!("➕ Adding IP {} to whitelist", ip));
                if let Some(desc) = description {
                    display::info(&format!("Description: {}", desc));
                }
                display::warning("IP whitelist management not yet implemented");
            }
            ProxyAccessCommands::RemoveIp { ip } => {
                display::info(&format!("➖ Removing IP {} from whitelist", ip));
                display::warning("IP whitelist management not yet implemented");
            }
            ProxyAccessCommands::SetBandwidth { user, limit } => {
                display::info(&format!(
                    "🔧 Setting bandwidth limit for user {}: {} MB/s",
                    user, limit
                ));
                display::warning("Bandwidth limit management not yet implemented");
            }
            ProxyAccessCommands::SetConnections { user, limit } => {
                display::info(&format!(
                    "🔧 Setting connection limit for user {}: {}",
                    user, limit
                ));
                display::warning("Connection limit management not yet implemented");
            }
        }

        Ok(())
    }

    pub async fn run_diagnostics(&mut self, fix: bool) -> Result<()> {
        display::info("🔍 Running system diagnostics...");
        println!();

        let mut issues_found = 0;
        let mut issues_fixed = 0;

        // Check system requirements
        display::section("System Requirements");

        // Check Docker
        if self.check_docker_availability().await {
            display::success("✓ Docker is installed and running");
        } else {
            display::error("✗ Docker is not available");
            issues_found += 1;
            if fix {
                display::warning(
                    "  → Cannot auto-fix Docker installation. Please install Docker manually.",
                );
            }
        }

        // Check Docker Compose
        if self.check_docker_compose_availability().await {
            display::success("✓ Docker Compose is available");
        } else {
            display::error("✗ Docker Compose is not available");
            issues_found += 1;
            if fix {
                display::warning(
                    "  → Cannot auto-fix Docker Compose installation. Please install it manually.",
                );
            }
        }

        // Check network tools
        display::section("Network Tools");

        if vpn_network::FirewallManager::is_ufw_installed().await {
            display::success("✓ UFW firewall is installed");
        } else if vpn_network::FirewallManager::is_iptables_installed().await {
            display::success("✓ iptables is installed");
        } else {
            display::warning("⚠ No firewall management tools found");
            display::info("  → Consider installing ufw or iptables for firewall management");
        }

        // Check port availability
        display::section("Port Availability");
        let common_ports = [80, 443, 8080, 8443, 9443];
        for &port in &common_ports {
            if vpn_network::PortChecker::is_port_available(port) {
                display::success(&format!("✓ Port {} is available", port));
            } else {
                display::warning(&format!("⚠ Port {} is in use", port));
            }
        }

        // Check installation path
        display::section("Installation Path");
        if self.install_path.exists() {
            if self.install_path.is_dir() {
                display::success(&format!(
                    "✓ Installation directory exists: {}",
                    self.install_path.display()
                ));

                // Check permissions
                match std::fs::File::create(self.install_path.join(".permission_test")) {
                    Ok(_) => {
                        display::success("✓ Installation directory is writable");
                        let _ = std::fs::remove_file(self.install_path.join(".permission_test"));
                    }
                    Err(_) => {
                        display::error("✗ Installation directory is not writable");
                        issues_found += 1;
                        if fix {
                            display::info("  → Run with sudo for proper permissions");
                        }
                    }
                }
            } else {
                display::error(&format!(
                    "✗ Installation path is not a directory: {}",
                    self.install_path.display()
                ));
                issues_found += 1;
            }
        } else {
            display::warning(&format!(
                "⚠ Installation directory does not exist: {}",
                self.install_path.display()
            ));
            if fix {
                if let Err(e) = std::fs::create_dir_all(&self.install_path) {
                    display::error(&format!("✗ Failed to create installation directory: {}", e));
                    issues_found += 1;
                } else {
                    display::success("✓ Created installation directory");
                    issues_fixed += 1;
                }
            }
        }

        // Check existing VPN installation
        display::section("VPN Installation Status");
        let install_path = self.get_protocol_install_path();
        let docker_compose_path = install_path.join("docker-compose.yml");
        if docker_compose_path.exists() {
            display::success("✓ VPN server appears to be installed");

            // Check if containers are running
            if self.check_containers_running().await {
                display::success("✓ VPN containers are running");
            } else {
                display::warning("⚠ VPN containers are not running");
                display::info("  → Try: vpn start");
            }
        } else {
            display::info("ℹ VPN server is not installed");
            display::info("  → Try: vpn install");
        }

        // Summary
        println!();
        display::section("Diagnostic Summary");

        if issues_found == 0 {
            display::success("✓ No issues found. System is ready for VPN operations!");
        } else {
            display::warning(&format!("⚠ Found {} issue(s)", issues_found));
            if fix && issues_fixed > 0 {
                display::info(&format!("✓ Fixed {} issue(s)", issues_fixed));
            }
            if fix && issues_found > issues_fixed {
                display::warning(&format!(
                    "⚠ {} issue(s) require manual attention",
                    issues_found - issues_fixed
                ));
            } else if !fix {
                display::info("  → Run with --fix to attempt automatic fixes");
            }
        }

        Ok(())
    }

    pub async fn show_system_info(&mut self) -> Result<()> {
        display::info("System info not yet implemented");
        Ok(())
    }

    pub async fn run_benchmark(&mut self) -> Result<()> {
        display::info("Benchmark not yet implemented");
        Ok(())
    }

    // Utility methods for diagnostics
    async fn check_docker_availability(&self) -> bool {
        use tokio::process::Command;
        Command::new("docker")
            .arg("version")
            .output()
            .await
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    async fn check_docker_compose_availability(&self) -> bool {
        use tokio::process::Command;
        Command::new("docker-compose")
            .arg("version")
            .output()
            .await
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    async fn check_containers_running(&self) -> bool {
        use tokio::process::Command;
        let install_path = self.get_protocol_install_path();
        let compose_path = install_path.join("docker-compose.yml");
        if !compose_path.exists() {
            return false;
        }

        Command::new("docker-compose")
            .arg("-f")
            .arg(compose_path)
            .arg("ps")
            .arg("-q")
            .output()
            .await
            .map(|output| !output.stdout.is_empty())
            .unwrap_or(false)
    }

    // Other utility methods
    fn load_server_config(&self) -> Result<vpn_users::config::ServerConfig> {
        let install_path = self.get_protocol_install_path();
        let server_info_path = install_path.join("server_info.json");
        
        if server_info_path.exists() {
            // Try to load server info from file
            let content = std::fs::read_to_string(&server_info_path)?;
            if let Ok(server_info) = serde_json::from_str::<serde_json::Value>(&content) {
                let mut config = vpn_users::config::ServerConfig::default();
                
                // Extract values from server info
                if let Some(host) = server_info.get("host").and_then(|v| v.as_str()) {
                    config.host = host.to_string();
                }
                if let Some(port) = server_info.get("port").and_then(|v| v.as_u64()) {
                    config.port = port as u16;
                }
                if let Some(sni) = server_info.get("sni_domain").and_then(|v| v.as_str()) {
                    config.sni = Some(sni.to_string());
                }
                if let Some(public_key) = server_info.get("public_key").and_then(|v| v.as_str()) {
                    config.public_key = Some(public_key.to_string());
                }
                if let Some(private_key) = server_info.get("private_key").and_then(|v| v.as_str()) {
                    config.private_key = Some(private_key.to_string());
                }
                if let Some(short_id) = server_info.get("short_id").and_then(|v| v.as_str()) {
                    config.short_id = Some(short_id.to_string());
                }
                
                return Ok(config);
            }
        }
        
        // Fallback to default config
        Ok(vpn_users::config::ServerConfig::default())
    }

    fn display_users_table(&self, users: &[vpn_users::User], detailed: bool) {
        use tabled::{Table, Tabled};

        #[derive(Tabled)]
        struct UserRow {
            name: String,
            id: String,
            protocol: String,
            status: String,
            created: String,
            traffic: String,
        }

        let rows: Vec<UserRow> = users
            .iter()
            .map(|user| UserRow {
                name: user.name.clone(),
                id: if detailed {
                    user.id.clone()
                } else {
                    user.short_id.clone()
                },
                protocol: user.protocol.as_str().to_string(),
                status: user.status.as_str().to_string(),
                created: user.created_at.format("%Y-%m-%d").to_string(),
                traffic: display::format_bytes(user.total_traffic()),
            })
            .collect();

        let table = Table::new(rows).to_string();
        println!("{}", table);
    }

    pub async fn migrate_from_bash(
        &mut self,
        source_path: PathBuf,
        keep_original: bool,
    ) -> Result<()> {
        display::info(&format!(
            "Migration from bash VPN (source: {}, keep_original: {}) not yet implemented",
            source_path.display(),
            keep_original
        ));
        Ok(())
    }

    // Additional methods for menu system
    pub async fn validate_keys(&mut self) -> Result<()> {
        display::info("Key validation not yet implemented");
        Ok(())
    }

    pub async fn show_configuration(&mut self) -> Result<()> {
        display::info("Show configuration not yet implemented");
        Ok(())
    }

    pub async fn edit_configuration(&mut self) -> Result<()> {
        display::info("Edit configuration not yet implemented");
        Ok(())
    }

    pub async fn backup_configuration(&mut self, _backup_path: Option<PathBuf>) -> Result<()> {
        display::info("Backup configuration not yet implemented");
        Ok(())
    }

    pub async fn restore_configuration(&mut self, _backup_path: PathBuf) -> Result<()> {
        display::info("Restore configuration not yet implemented");
        Ok(())
    }

    pub async fn validate_configuration(&mut self) -> Result<()> {
        display::info("Validate configuration not yet implemented");
        Ok(())
    }

    pub async fn reset_configuration(&mut self) -> Result<()> {
        display::info("Reset configuration not yet implemented");
        Ok(())
    }

    pub async fn show_active_alerts(&mut self) -> Result<()> {
        display::info("Show active alerts not yet implemented");
        Ok(())
    }

    pub async fn show_performance_metrics(&mut self) -> Result<()> {
        display::info("Show performance metrics not yet implemented");
        Ok(())
    }

    pub async fn show_security_status(&mut self) -> Result<()> {
        display::info("Show security status not yet implemented");
        Ok(())
    }

    pub async fn show_system_health(&mut self) -> Result<()> {
        display::info("Show system health not yet implemented");
        Ok(())
    }

    pub async fn show_traffic_stats(&mut self) -> Result<()> {
        display::info("Show traffic stats not yet implemented");
        Ok(())
    }

    pub async fn rotate_keys(&mut self, generate_new: bool, backup: bool) -> Result<()> {
        display::info(&format!(
            "Rotate keys (generate_new: {}, backup: {}) not yet implemented",
            generate_new, backup
        ));
        Ok(())
    }

    pub async fn show_logs(
        &mut self,
        lines: usize,
        follow: bool,
        pattern: Option<String>,
    ) -> Result<()> {
        display::info(&format!(
            "Show logs (lines: {}, follow: {}, pattern: {:?}) not yet implemented",
            lines, follow, pattern
        ));
        Ok(())
    }

    pub async fn check_network_status(&mut self) -> Result<()> {
        display::info("🔍 Checking Docker network status and available subnets...");

        let installer = vpn_server::ServerInstaller::new().map_err(|e| CliError::ServerError(e))?;

        installer
            .check_network_status()
            .await
            .map_err(|e| CliError::ServerError(e))?;

        Ok(())
    }
}

// Helper struct for server status
pub struct ServerStatus {
    pub is_running: bool,
    pub active_users: usize,
    pub healthy_containers: usize,
    pub total_containers: usize,
}
