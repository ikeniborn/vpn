use std::path::PathBuf;
use std::sync::Arc;
use indicatif::{ProgressBar, ProgressStyle};
use vpn_server::{ServerInstaller, ServerLifecycle, InstallationOptions};
use vpn_server::installer::LogLevel as ServerLogLevel;
use vpn_users::{UserManager, BatchOperations};
use vpn_users::user::UserStatus;
use vpn_users::manager::UserListOptions;
// use vpn_monitor::{TrafficMonitor, HealthMonitor, LogAnalyzer, MetricsCollector, AlertManager};
// use vpn_monitor::traffic::MonitoringConfig;
use crate::{cli::*, config::ConfigManager, runtime::RuntimeManager, utils::display, CliError, Result};

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
        let installer = ServerInstaller::new()?;
        
        let options = InstallationOptions {
            protocol: protocol.into(),
            port,
            sni_domain: sni,
            install_path: self.install_path.clone(),
            enable_firewall: firewall,
            auto_start,
            log_level: ServerLogLevel::Warning,
            reality_dest: None,
            subnet,
            interactive_subnet,
        };

        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner()
            .template("{spinner:.green} {msg}")
            .unwrap());
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
        if !self.force_mode {
            display::warning("This will completely remove the VPN server!");
            if purge {
                display::warning("All user data will be permanently deleted!");
            }
            
            // In a real implementation, you'd prompt for confirmation here
        }

        let installer = ServerInstaller::new()?;
        
        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner()
            .template("{spinner:.red} {msg}")
            .unwrap());
        pb.set_message("Uninstalling VPN server...");

        let result = installer.uninstall(&self.install_path, purge).await;
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
        
        let result = lifecycle.start(&self.install_path).await;
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
        
        let result = lifecycle.stop(&self.install_path).await;
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
        
        let result = lifecycle.restart(&self.install_path).await;
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
        
        let result = lifecycle.reload_config(&self.install_path).await;
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
                    println!("Status: {}", if status.is_running { "🟢 Running" } else { "🔴 Stopped" });
                    println!("Health Score: {:.1}%", status.health_score * 100.0);
                    
                    if let Some(uptime) = status.uptime {
                        println!("Uptime: {}", display::format_duration(uptime));
                    }
                    
                    if detailed {
                        println!("\nContainers:");
                        for container in &status.containers {
                            let status_icon = if container.is_running { "🟢" } else { "🔴" };
                            println!("  {} {} - CPU: {:.1}%, Memory: {}", 
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

    pub async fn is_server_installed(&self) -> Result<bool> {
        let config_file = self.install_path.join("docker-compose.yml");
        Ok(config_file.exists())
    }

    // User Management Commands
    pub async fn handle_user_command(&mut self, command: UserCommands) -> Result<()> {
        match command {
            UserCommands::List { status, detailed } => {
                self.list_users(status.map(|s| s.into()), detailed).await
            }
            UserCommands::Create { name, email, protocol } => {
                self.create_user(name, email, protocol).await
            }
            UserCommands::Delete { user } => {
                self.delete_user(user).await
            }
            UserCommands::Show { user, qr } => {
                self.show_user_details(user, qr).await
            }
            UserCommands::Link { user, qr_file } => {
                self.generate_user_link(user, qr_file).await
            }
            UserCommands::Update { user, status, email } => {
                self.update_user(user, status.map(|s| s.into()), email).await
            }
            UserCommands::Batch { command } => {
                self.handle_batch_command(command).await
            }
            UserCommands::Reset { user } => {
                self.reset_user_traffic(user).await
            }
        }
    }

    pub async fn list_users(&mut self, status_filter: Option<UserStatus>, detailed: bool) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
        let mut options = UserListOptions::default();
        if let Some(status) = status_filter {
            options.status_filter = Some(status.into());
        }
        
        let users = user_manager.list_users(Some(options)).await?;
        
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

    pub async fn create_user(&mut self, name: String, email: Option<String>, protocol: Protocol) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
        let mut user = user_manager.create_user(name.clone(), protocol.into()).await?;
        
        if let Some(email) = email {
            user.email = Some(email);
            user_manager.update_user(user.clone()).await?;
        }
        
        match self.output_format {
            OutputFormat::Json => {
                println!("{}", serde_json::to_string_pretty(&user)?);
            }
            _ => {
                display::success(&format!("User '{}' created successfully!", name));
                println!("User ID: {}", user.id);
                println!("Short ID: {}", user.short_id);
                if let Some(email) = &user.email {
                    println!("Email: {}", email);
                }
            }
        }
        
        Ok(())
    }

    pub async fn delete_user(&mut self, user: String) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
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
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
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
                println!("Created: {}", user_obj.created_at.format("%Y-%m-%d %H:%M:%S"));
                
                if let Some(email) = &user_obj.email {
                    println!("Email: {}", email);
                }
                
                if let Some(last_active) = user_obj.last_active {
                    println!("Last Active: {}", last_active.format("%Y-%m-%d %H:%M:%S"));
                }
                
                println!("\nTraffic Statistics:");
                println!("  Sent: {}", display::format_bytes(user_obj.stats.bytes_sent));
                println!("  Received: {}", display::format_bytes(user_obj.stats.bytes_received));
                println!("  Connections: {}", user_obj.stats.connection_count);
                
                if show_qr {
                    let link = user_manager.generate_connection_link(&user_obj.id).await?;
                    println!("\nConnection Link:");
                    println!("{}", link);
                    
                    // Generate QR code
                    let qr_gen = vpn_crypto::QrCodeGenerator::new();
                    if let Ok(qr_data) = qr_gen.generate_qr_code(&link) {
                        println!("\nQR Code generated successfully ({} bytes)", qr_data.len());
                        println!("Use '--save-qr <path>' to save QR code to file");
                    }
                }
            }
        }
        
        Ok(())
    }

    pub async fn generate_user_link(&mut self, user: String, qr_file: Option<PathBuf>) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
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
        
        if let Some(qr_path) = qr_file {
            user_manager.generate_qr_code(&user_obj.id, &qr_path).await?;
            display::success(&format!("QR code saved to: {}", qr_path.display()));
        }
        
        Ok(())
    }

    pub async fn update_user(&mut self, user: String, status: Option<UserStatus>, email: Option<String>) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
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
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        
        let mut user_obj = match user_manager.get_user_by_name(&user).await {
            Ok(u) => u,
            Err(_) => user_manager.get_user(&user).await?,
        };
        
        user_obj.stats.bytes_sent = 0;
        user_obj.stats.bytes_received = 0;
        user_obj.stats.connection_count = 0;
        user_obj.stats.last_connection = None;
        
        user_manager.update_user(user_obj.clone()).await?;
        
        display::success(&format!("Traffic statistics reset for user '{}'!", user_obj.name));
        Ok(())
    }

    pub async fn get_user_list(&self) -> Result<Vec<vpn_users::User>> {
        let server_config = self.load_server_config()?;
        let user_manager = UserManager::new(&self.install_path, server_config)?;
        Ok(user_manager.list_users(None).await?)
    }

    async fn handle_batch_command(&mut self, command: BatchCommands) -> Result<()> {
        match command {
            BatchCommands::Export { file } => {
                self.export_users(file).await
            }
            BatchCommands::Import { file, overwrite } => {
                self.import_users(file, overwrite).await
            }
            _ => {
                display::info("Batch command not yet implemented");
                Ok(())
            }
        }
    }

    pub async fn export_users(&mut self, file: PathBuf) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = Arc::new(UserManager::new(&self.install_path, server_config)?);
        let batch_ops = BatchOperations::new(user_manager);
        
        batch_ops.export_users_to_json(&file).await?;
        
        display::success(&format!("Users exported to: {}", file.display()));
        Ok(())
    }

    pub async fn import_users(&mut self, file: PathBuf, overwrite: bool) -> Result<()> {
        let server_config = self.load_server_config()?;
        let user_manager = Arc::new(UserManager::new(&self.install_path, server_config)?);
        let batch_ops = BatchOperations::new(user_manager);
        
        let options = vpn_users::batch::ImportOptions {
            overwrite_existing: overwrite,
            validate_configs: true,
            generate_new_keys: false,
        };
        
        let result = batch_ops.import_users_from_json(&file, options).await?;
        
        display::success(&format!("Successfully imported {} users", result.successful.len()));
        
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
            RuntimeCommands::Migrate => {
                eprintln!("⚠️  WARNING: Docker to Containerd migration has been deprecated!");
                eprintln!("   Use Docker Compose orchestration instead: `vpn compose up`");
                eprintln!("   For migration guidance, see Phase 5 in TASK.md");
                return Err(CliError::FeatureDeprecated(
                    "Containerd migration has been deprecated in favor of Docker Compose orchestration".to_string()
                ));
            }
            RuntimeCommands::Capabilities => {
                eprintln!("⚠️  NOTE: Containerd capabilities shown for reference only - containerd support deprecated");
                runtime_manager.show_capabilities()?;
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
                display::warning("  → Cannot auto-fix Docker installation. Please install Docker manually.");
            }
        }

        // Check Docker Compose
        if self.check_docker_compose_availability().await {
            display::success("✓ Docker Compose is available");
        } else {
            display::error("✗ Docker Compose is not available");
            issues_found += 1;
            if fix {
                display::warning("  → Cannot auto-fix Docker Compose installation. Please install it manually.");
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
                display::success(&format!("✓ Installation directory exists: {}", self.install_path.display()));
                
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
                display::error(&format!("✗ Installation path is not a directory: {}", self.install_path.display()));
                issues_found += 1;
            }
        } else {
            display::warning(&format!("⚠ Installation directory does not exist: {}", self.install_path.display()));
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
        let docker_compose_path = self.install_path.join("docker-compose.yml");
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
                display::warning(&format!("⚠ {} issue(s) require manual attention", issues_found - issues_fixed));
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
        let compose_path = self.install_path.join("docker-compose.yml");
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
        // This would load the actual server configuration
        // For now, return a default config
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
        
        let rows: Vec<UserRow> = users.iter().map(|user| {
            UserRow {
                name: user.name.clone(),
                id: if detailed { user.id.clone() } else { user.short_id.clone() },
                protocol: user.protocol.as_str().to_string(),
                status: user.status.as_str().to_string(),
                created: user.created_at.format("%Y-%m-%d").to_string(),
                traffic: display::format_bytes(user.total_traffic()),
            }
        }).collect();
        
        let table = Table::new(rows).to_string();
        println!("{}", table);
    }

    pub async fn migrate_from_bash(&mut self, source_path: PathBuf, keep_original: bool) -> Result<()> {
        display::info(&format!("Migration from bash VPN (source: {}, keep_original: {}) not yet implemented", 
                              source_path.display(), keep_original));
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
        display::info(&format!("Rotate keys (generate_new: {}, backup: {}) not yet implemented", generate_new, backup));
        Ok(())
    }

    pub async fn show_logs(&mut self, lines: usize, follow: bool, pattern: Option<String>) -> Result<()> {
        display::info(&format!("Show logs (lines: {}, follow: {}, pattern: {:?}) not yet implemented", lines, follow, pattern));
        Ok(())
    }
    
    pub async fn check_network_status(&mut self) -> Result<()> {
        display::info("🔍 Checking Docker network status and available subnets...");
        
        let installer = vpn_server::ServerInstaller::new()
            .map_err(|e| CliError::ServerError(e))?;
        
        installer.check_network_status().await
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