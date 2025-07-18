use console::{style, Term};
use crossterm::{
    execute,
    terminal::{Clear, ClearType},
};
use dialoguer::{theme::ColorfulTheme, Confirm, FuzzySelect, Input, Select};
use std::io;

use crate::utils::display;
use crate::{CommandHandler, Result};

pub struct InteractiveMenu {
    handler: CommandHandler,
    term: Term,
}

#[derive(Debug, Clone)]
pub struct MenuOption {
    pub title: String,
    pub description: String,
    pub action: MenuAction,
}

#[derive(Debug, Clone)]
pub enum MenuAction {
    InstallServer,
    ServerManagement,
    UserManagement,
    Monitoring,
    Security,
    Configuration,
    Migration,
    Diagnostics,
    SystemInfo,
    Exit,
}

impl InteractiveMenu {
    pub fn new(handler: CommandHandler) -> Self {
        Self {
            handler,
            term: Term::stdout(),
        }
    }

    pub async fn run(&mut self) -> Result<()> {
        loop {
            self.clear_screen()?;
            self.show_header().await?;

            let choice = self.show_main_menu().await?;

            match choice {
                MenuAction::Exit => {
                    println!("{}", style("Goodbye!").green());
                    break;
                }
                action => {
                    if let Err(e) = self.handle_menu_action(action).await {
                        display::error(&format!("Operation failed: {}", e));
                        self.wait_for_keypress()?;
                    }
                }
            }
        }

        Ok(())
    }

    fn clear_screen(&self) -> Result<()> {
        execute!(io::stdout(), Clear(ClearType::All))?;
        Ok(())
    }

    async fn show_header(&mut self) -> Result<()> {
        println!("{}", style("VPN SERVER MANAGEMENT").cyan().bold());
        println!("{}", style("===================").cyan());

        // Show server status
        match self.handler.get_server_status().await {
            Ok(status) => {
                let status_text = if status.is_running {
                    style("RUNNING").green()
                } else {
                    style("STOPPED").red()
                };
                println!("Server Status: {}", status_text);

                if status.is_running {
                    println!("Active Users: {}", status.active_users);
                    println!(
                        "Containers: {}/{} healthy",
                        status.healthy_containers, status.total_containers
                    );
                }
            }
            Err(_) => {
                println!("Server Status: {}", style("UNKNOWN").yellow());
            }
        }

        println!();
        Ok(())
    }

    async fn show_main_menu(&self) -> Result<MenuAction> {
        let options = vec![
            MenuOption {
                title: "📦 Install VPN Server".to_string(),
                description: "Install and configure a new VPN server".to_string(),
                action: MenuAction::InstallServer,
            },
            MenuOption {
                title: "🚀 Server Management".to_string(),
                description: "Start, stop, restart, or reload the server".to_string(),
                action: MenuAction::ServerManagement,
            },
            MenuOption {
                title: "👥 User Management".to_string(),
                description: "Create, delete, and manage VPN users".to_string(),
                action: MenuAction::UserManagement,
            },
            MenuOption {
                title: "📊 Monitoring & Statistics".to_string(),
                description: "View traffic, logs, and performance metrics".to_string(),
                action: MenuAction::Monitoring,
            },
            MenuOption {
                title: "🔐 Security & Keys".to_string(),
                description: "Manage keys, certificates, and security settings".to_string(),
                action: MenuAction::Security,
            },
            MenuOption {
                title: "⚙️ Configuration".to_string(),
                description: "View and modify server configuration".to_string(),
                action: MenuAction::Configuration,
            },
            MenuOption {
                title: "🔄 Migration & Backup".to_string(),
                description: "Import/export configurations and migrate data".to_string(),
                action: MenuAction::Migration,
            },
            MenuOption {
                title: "🔧 System Diagnostics".to_string(),
                description: "Run diagnostics and fix common issues".to_string(),
                action: MenuAction::Diagnostics,
            },
            MenuOption {
                title: "ℹ️ System Information".to_string(),
                description: "View system and server information".to_string(),
                action: MenuAction::SystemInfo,
            },
            MenuOption {
                title: "❌ Exit".to_string(),
                description: "Exit the VPN management interface".to_string(),
                action: MenuAction::Exit,
            },
        ];

        let items: Vec<String> = options
            .iter()
            .map(|opt| format!("{} - {}", opt.title, opt.description))
            .collect();

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select an option")
            .items(&items)
            .default(0)
            .interact()?;

        Ok(options[selection].action.clone())
    }

    async fn handle_menu_action(&mut self, action: MenuAction) -> Result<()> {
        match action {
            MenuAction::InstallServer => self.install_server_menu().await,
            MenuAction::ServerManagement => self.server_management_menu().await,
            MenuAction::UserManagement => self.user_management_menu().await,
            MenuAction::Monitoring => self.monitoring_menu().await,
            MenuAction::Security => self.security_menu().await,
            MenuAction::Configuration => self.configuration_menu().await,
            MenuAction::Migration => self.migration_menu().await,
            MenuAction::Diagnostics => self.diagnostics_menu().await,
            MenuAction::SystemInfo => self.system_info_menu().await,
            MenuAction::Exit => Ok(()),
        }
    }

    async fn install_server_menu(&mut self) -> Result<()> {
        println!("{}", style("VPN Server Installation").cyan().bold());
        println!();

        // Check if server is already installed
        if self.handler.is_server_installed().await? {
            display::warning("Server is already installed!");

            let reinstall = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt("Do you want to reinstall?")
                .default(false)
                .interact()?;

            if !reinstall {
                return Ok(());
            }
        }

        // Select protocol
        let protocols = vec!["VLESS+Reality", "Shadowsocks", "WireGuard", "HTTP/SOCKS5 Proxy"];
        let protocol_selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select VPN protocol")
            .items(&protocols)
            .default(0)
            .interact()?;

        let protocol = match protocol_selection {
            0 => crate::cli::Protocol::Vless,
            1 => crate::cli::Protocol::Shadowsocks,
            2 => crate::cli::Protocol::Wireguard,
            3 => crate::cli::Protocol::ProxyServer,
            _ => crate::cli::Protocol::Vless,
        };

        // Get port (optional)
        let use_custom_port = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Use custom port?")
            .default(false)
            .interact()?;

        let port = if use_custom_port {
            let port_input: String = Input::with_theme(&ColorfulTheme::default())
                .with_prompt("Enter port number (1024-65535)")
                .validate_with(|input: &String| -> std::result::Result<(), &str> {
                    match input.parse::<u16>() {
                        Ok(port) if port >= 1024 => Ok(()),
                        _ => Err("Port must be between 1024 and 65535"),
                    }
                })
                .interact_text()?;
            Some(port_input.parse().unwrap())
        } else {
            None
        };

        // Get SNI domain for Reality protocol
        let sni = if matches!(protocol, crate::cli::Protocol::Vless) {
            let use_custom_sni = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt("Use custom SNI domain?")
                .default(false)
                .interact()?;

            if use_custom_sni {
                let sni_input: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter SNI domain (e.g., www.google.com)")
                    .validate_with(|input: &String| -> std::result::Result<(), &str> {
                        if input.contains('.') && !input.is_empty() {
                            Ok(())
                        } else {
                            Err("Please enter a valid domain name")
                        }
                    })
                    .interact_text()?;
                Some(sni_input)
            } else {
                None
            }
        } else {
            None
        };

        // Firewall configuration
        let firewall = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Configure firewall rules?")
            .default(true)
            .interact()?;

        // Auto-start configuration
        let auto_start = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Enable auto-start on boot?")
            .default(true)
            .interact()?;

        // Confirm installation
        println!();
        println!("Installation Summary:");
        println!("  Protocol: {:?}", protocol);
        if let Some(port) = port {
            println!("  Port: {}", port);
        }
        if let Some(ref sni) = sni {
            println!("  SNI Domain: {}", sni);
        }
        println!(
            "  Firewall: {}",
            if firewall { "Enabled" } else { "Disabled" }
        );
        println!(
            "  Auto-start: {}",
            if auto_start { "Enabled" } else { "Disabled" }
        );
        println!();

        let confirm = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Proceed with installation?")
            .default(true)
            .interact()?;

        if confirm {
            self.check_admin_privileges("VPN server installation")?;
            display::info("Starting installation...");
            self.handler
                .install_server(protocol, port, sni, firewall, auto_start, None, false)
                .await?;
            display::success("Server installed successfully!");

            // Show next steps
            println!();
            display::info("Next steps:");
            println!("  1. Create users with 'User Management'");
            println!("  2. Check server status");
            println!("  3. View logs and monitoring");
        }

        self.wait_for_keypress()?;
        Ok(())
    }

    async fn server_management_menu(&mut self) -> Result<()> {
        println!("{}", style("Server Management").cyan().bold());
        println!();

        let actions = vec![
            "Start Server",
            "Stop Server",
            "Restart Server",
            "Reload Configuration",
            "Show Status",
            "Uninstall Server",
            "Back to Main Menu",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select action")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                self.check_admin_privileges("Server start")?;
                display::info("Starting server...");
                self.handler.start_server().await?;
                display::success("Server started successfully!");
            }
            1 => {
                self.check_admin_privileges("Server stop")?;
                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Are you sure you want to stop the server?")
                    .default(false)
                    .interact()?;

                if confirm {
                    display::info("Stopping server...");
                    self.handler.stop_server().await?;
                    display::success("Server stopped successfully!");
                }
            }
            2 => {
                self.check_admin_privileges("Server restart")?;
                display::info("Restarting server...");
                self.handler.restart_server().await?;
                display::success("Server restarted successfully!");
            }
            3 => {
                self.check_admin_privileges("Configuration reload")?;
                display::info("Reloading configuration...");
                self.handler.reload_server().await?;
                display::success("Configuration reloaded successfully!");
            }
            4 => {
                self.handler.show_status(true, false).await?;
            }
            5 => {
                self.uninstall_server_interactive().await?;
            }
            6 => return Ok(()),
            _ => {}
        }

        if selection < 6 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn user_management_menu(&mut self) -> Result<()> {
        println!("{}", style("User Management").cyan().bold());
        println!();

        let actions = vec![
            "List All Users",
            "Create New User",
            "Show User Details",
            "Delete User",
            "Generate Connection Link",
            "Reset User Traffic",
            "Batch Operations",
            "Back to Main Menu",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select action")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                self.handler.list_users(None, true).await?;
            }
            1 => {
                self.create_user_interactive().await?;
            }
            2 => {
                self.show_user_interactive().await?;
            }
            3 => {
                self.delete_user_interactive().await?;
            }
            4 => {
                self.generate_link_interactive().await?;
            }
            5 => {
                self.reset_user_traffic_interactive().await?;
            }
            6 => {
                self.batch_operations_menu().await?;
            }
            7 => return Ok(()),
            _ => {}
        }

        if selection < 7 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn create_user_interactive(&mut self) -> Result<()> {
        let name: String = Input::with_theme(&ColorfulTheme::default())
            .with_prompt("Enter username")
            .validate_with(|input: &String| -> std::result::Result<(), &str> {
                if input.trim().is_empty() {
                    Err("Username cannot be empty")
                } else if input.len() > 50 {
                    Err("Username too long (max 50 characters)")
                } else {
                    Ok(())
                }
            })
            .interact_text()?;

        let email: Option<String> = {
            let add_email = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt("Add email address?")
                .default(false)
                .interact()?;

            if add_email {
                let email_input: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter email address")
                    .validate_with(|input: &String| -> std::result::Result<(), &str> {
                        if input.contains('@') && input.contains('.') {
                            Ok(())
                        } else {
                            Err("Please enter a valid email address")
                        }
                    })
                    .interact_text()?;
                Some(email_input)
            } else {
                None
            }
        };

        let protocols = vec!["VLESS+Reality", "Shadowsocks", "WireGuard"];
        let protocol_selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select protocol")
            .items(&protocols)
            .default(0)
            .interact()?;

        let protocol = match protocol_selection {
            0 => crate::cli::Protocol::Vless,
            1 => crate::cli::Protocol::Shadowsocks,
            2 => crate::cli::Protocol::Wireguard,
            _ => crate::cli::Protocol::Vless,
        };

        self.check_admin_privileges("User creation")?;
        display::info("Creating user...");
        self.handler.create_user(name, email, protocol).await?;
        display::success("User created successfully!");

        Ok(())
    }

    async fn show_user_interactive(&mut self) -> Result<()> {
        let users = self.handler.get_user_list().await?;

        if users.is_empty() {
            display::warning("No users found!");
            return Ok(());
        }

        let user_names: Vec<String> = users.iter().map(|u| u.name.clone()).collect();

        let selection = FuzzySelect::with_theme(&ColorfulTheme::default())
            .with_prompt("Select user")
            .items(&user_names)
            .default(0)
            .interact()?;

        let user_name = &user_names[selection];

        let show_qr = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Show QR code?")
            .default(false)
            .interact()?;

        self.handler
            .show_user_details(user_name.clone(), show_qr)
            .await?;
        Ok(())
    }

    async fn delete_user_interactive(&mut self) -> Result<()> {
        let users = self.handler.get_user_list().await?;

        if users.is_empty() {
            display::warning("No users found!");
            return Ok(());
        }

        let user_names: Vec<String> = users.iter().map(|u| u.name.clone()).collect();

        let selection = FuzzySelect::with_theme(&ColorfulTheme::default())
            .with_prompt("Select user to delete")
            .items(&user_names)
            .default(0)
            .interact()?;

        let user_name = &user_names[selection];

        let confirm = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(&format!(
                "Are you sure you want to delete user '{}'?",
                user_name
            ))
            .default(false)
            .interact()?;

        if confirm {
            self.handler.delete_user(user_name.clone()).await?;
            display::success("User deleted successfully!");
        }

        Ok(())
    }

    async fn generate_link_interactive(&mut self) -> Result<()> {
        let users = self.handler.get_user_list().await?;

        if users.is_empty() {
            display::warning("No users found!");
            return Ok(());
        }

        let user_names: Vec<String> = users.iter().map(|u| u.name.clone()).collect();

        let selection = FuzzySelect::with_theme(&ColorfulTheme::default())
            .with_prompt("Select user")
            .items(&user_names)
            .default(0)
            .interact()?;

        let user_name = &user_names[selection];

        let show_qr = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Display QR code in terminal?")
            .default(true)
            .interact()?;

        let generate_qr_file = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Save QR code to file?")
            .default(false)
            .interact()?;

        let qr_file = if generate_qr_file {
            let qr_path: String = Input::with_theme(&ColorfulTheme::default())
                .with_prompt("Enter QR code file path")
                .default(format!("{}_qr.png", user_name))
                .interact_text()?;
            Some(std::path::PathBuf::from(qr_path))
        } else {
            None
        };

        self.handler
            .generate_user_link(user_name.clone(), show_qr, qr_file)
            .await?;
        Ok(())
    }

    async fn reset_user_traffic_interactive(&mut self) -> Result<()> {
        let users = self.handler.get_user_list().await?;

        if users.is_empty() {
            display::warning("No users found!");
            return Ok(());
        }

        let user_names: Vec<String> = users.iter().map(|u| u.name.clone()).collect();

        let selection = FuzzySelect::with_theme(&ColorfulTheme::default())
            .with_prompt("Select user")
            .items(&user_names)
            .default(0)
            .interact()?;

        let user_name = &user_names[selection];

        let confirm = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(&format!(
                "Reset traffic statistics for user '{}'?",
                user_name
            ))
            .default(false)
            .interact()?;

        if confirm {
            self.handler.reset_user_traffic(user_name.clone()).await?;
            display::success("Traffic statistics reset successfully!");
        }

        Ok(())
    }

    async fn batch_operations_menu(&mut self) -> Result<()> {
        println!("{}", style("Batch Operations").cyan().bold());
        println!();

        let actions = vec![
            "Export All Users",
            "Import Users from File",
            "Delete Multiple Users",
            "Update Multiple Users",
            "Back to User Management",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select batch operation")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                let file_path: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter export file path")
                    .default("users_export.json".to_string())
                    .interact_text()?;

                self.handler
                    .export_users(std::path::PathBuf::from(file_path))
                    .await?;
                display::success("Users exported successfully!");
            }
            1 => {
                let file_path: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter import file path")
                    .interact_text()?;

                let overwrite = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Overwrite existing users?")
                    .default(false)
                    .interact()?;

                self.handler
                    .import_users(std::path::PathBuf::from(file_path), overwrite)
                    .await?;
                display::success("Users imported successfully!");
            }
            _ => {
                // Implementation for other batch operations would go here
                display::info("Feature coming soon!");
            }
        }

        if selection < 4 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn monitoring_menu(&mut self) -> Result<()> {
        println!("{}", style("Monitoring & Statistics").cyan().bold());
        println!();

        let actions = vec![
            "Traffic Statistics",
            "System Health",
            "View Logs",
            "Performance Metrics",
            "Active Alerts",
            "Back to Main Menu",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select monitoring option")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                let _hours: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Time period in hours")
                    .default("24".to_string())
                    .validate_with(|input: &String| -> std::result::Result<(), &str> {
                        match input.parse::<u32>() {
                            Ok(_) => Ok(()),
                            Err(_) => Err("Please enter a valid number"),
                        }
                    })
                    .interact_text()?;

                self.handler.show_traffic_stats().await?;
            }
            1 => {
                let _watch = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Continuous monitoring?")
                    .default(false)
                    .interact()?;

                self.handler.show_system_health().await?;
            }
            2 => {
                self.logs_menu().await?;
            }
            3 => {
                self.handler.show_performance_metrics().await?;
            }
            4 => {
                self.handler.show_active_alerts().await?;
            }
            5 => return Ok(()),
            _ => {}
        }

        if selection < 5 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn logs_menu(&mut self) -> Result<()> {
        let actions = vec![
            "Show Recent Logs",
            "Follow Logs (Live)",
            "Search Logs",
            "Error Logs Only",
            "Back",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select log option")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                let lines: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Number of lines to show")
                    .default("100".to_string())
                    .interact_text()?;

                self.handler
                    .show_logs(lines.parse().unwrap_or(100), false, None)
                    .await?;
            }
            1 => {
                display::info("Following logs (Press Ctrl+C to stop)...");
                self.handler.show_logs(50, true, None).await?;
            }
            2 => {
                let pattern: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter search pattern")
                    .interact_text()?;

                self.handler.show_logs(100, false, Some(pattern)).await?;
            }
            3 => {
                self.handler
                    .show_logs(100, false, Some("error".to_string()))
                    .await?;
            }
            4 => return Ok(()),
            _ => {}
        }

        Ok(())
    }

    async fn security_menu(&mut self) -> Result<()> {
        println!("{}", style("Security & Key Management").cyan().bold());
        println!();

        let actions = vec![
            "Security Status",
            "Rotate Server Keys",
            "Rotate All Keys",
            "Validate Keys",
            "Generate New Keys",
            "Back to Main Menu",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select security option")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                self.handler.show_security_status().await?;
            }
            1 => {
                let backup = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Create backup before rotation?")
                    .default(true)
                    .interact()?;

                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt(
                        "Rotate server keys? This will require reconnection of all clients.",
                    )
                    .default(false)
                    .interact()?;

                if confirm {
                    self.handler.rotate_keys(false, backup).await?;
                    display::success("Server keys rotated successfully!");
                }
            }
            2 => {
                let backup = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Create backup before rotation?")
                    .default(true)
                    .interact()?;

                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Rotate ALL keys? This will require ALL clients to reconnect.")
                    .default(false)
                    .interact()?;

                if confirm {
                    self.handler.rotate_keys(true, backup).await?;
                    display::success("All keys rotated successfully!");
                }
            }
            3 => {
                self.handler.validate_keys().await?;
            }
            4 => {
                display::info("Feature coming soon!");
            }
            5 => return Ok(()),
            _ => {}
        }

        if selection < 5 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn configuration_menu(&mut self) -> Result<()> {
        println!("{}", style("Configuration Management").cyan().bold());
        println!();

        let actions = vec![
            "Show Current Configuration",
            "Edit Configuration",
            "Backup Configuration",
            "Restore Configuration",
            "Validate Configuration",
            "Reset to Defaults",
            "Back to Main Menu",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select configuration option")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                self.handler.show_configuration().await?;
            }
            1 => {
                display::info("Opening configuration editor...");
                self.handler.edit_configuration().await?;
            }
            2 => {
                let backup_path: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter backup file path")
                    .default(format!(
                        "config_backup_{}.tar.gz",
                        chrono::Utc::now().format("%Y%m%d_%H%M%S")
                    ))
                    .interact_text()?;

                self.handler
                    .backup_configuration(Some(std::path::PathBuf::from(backup_path)))
                    .await?;
                display::success("Configuration backed up successfully!");
            }
            3 => {
                let backup_path: String = Input::with_theme(&ColorfulTheme::default())
                    .with_prompt("Enter backup file path")
                    .interact_text()?;

                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt(
                        "Restore configuration from backup? This will overwrite current settings.",
                    )
                    .default(false)
                    .interact()?;

                if confirm {
                    self.handler
                        .restore_configuration(std::path::PathBuf::from(backup_path))
                        .await?;
                    display::success("Configuration restored successfully!");
                }
            }
            4 => {
                self.handler.validate_configuration().await?;
            }
            5 => {
                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt("Reset configuration to defaults? This cannot be undone.")
                    .default(false)
                    .interact()?;

                if confirm {
                    self.handler.reset_configuration().await?;
                    display::success("Configuration reset to defaults!");
                }
            }
            6 => return Ok(()),
            _ => {}
        }

        if selection < 6 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn migration_menu(&mut self) -> Result<()> {
        println!("{}", style("Migration & Backup").cyan().bold());
        println!();

        let actions = vec![
            "Migrate from Bash Version",
            "Export Configuration",
            "Import Configuration",
            "System Backup",
            "Back to Main Menu",
        ];

        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select migration option")
            .items(&actions)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                self.migrate_from_bash_interactive().await?;
            }
            1 => {
                display::info("Feature coming soon!");
            }
            2 => {
                display::info("Feature coming soon!");
            }
            3 => {
                display::info("Feature coming soon!");
            }
            4 => return Ok(()),
            _ => {}
        }

        if selection < 4 {
            self.wait_for_keypress()?;
        }
        Ok(())
    }

    async fn migrate_from_bash_interactive(&mut self) -> Result<()> {
        let source_path: String = Input::with_theme(&ColorfulTheme::default())
            .with_prompt("Enter Bash installation path")
            .default("/opt/v2ray".to_string())
            .interact_text()?;

        let keep_original = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Keep original installation?")
            .default(true)
            .interact()?;

        let confirm = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Start migration? This may take several minutes.")
            .default(true)
            .interact()?;

        if confirm {
            display::info("Starting migration from Bash implementation...");
            self.handler
                .migrate_from_bash(std::path::PathBuf::from(source_path), keep_original)
                .await?;
            display::success("Migration completed successfully!");
        }

        Ok(())
    }

    async fn diagnostics_menu(&mut self) -> Result<()> {
        println!("{}", style("System Diagnostics").cyan().bold());
        println!();

        let fix_issues = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Automatically fix detected issues?")
            .default(false)
            .interact()?;

        display::info("Running system diagnostics...");
        self.handler.run_diagnostics(fix_issues).await?;

        self.wait_for_keypress()?;
        Ok(())
    }

    async fn system_info_menu(&mut self) -> Result<()> {
        println!("{}", style("System Information").cyan().bold());
        println!();

        self.handler.show_system_info().await?;
        self.wait_for_keypress()?;
        Ok(())
    }

    fn check_admin_privileges(&self, operation: &str) -> Result<()> {
        if !crate::PrivilegeManager::is_root() {
            display::warning(&format!("{} requires administrator privileges.", operation));
            return Err(crate::CliError::PermissionError(format!(
                "Please run with administrator privileges: sudo vpn menu"
            )));
        }
        Ok(())
    }

    async fn uninstall_server_interactive(&mut self) -> Result<()> {
        println!("{}", style("Server Uninstallation").red().bold());
        println!();

        // Check if server is installed
        if !self.handler.is_server_installed().await? {
            display::warning("No VPN server installation found!");
            return Ok(());
        }

        display::warning("⚠️  This will completely remove the VPN server!");
        display::warning("   • All containers will be stopped and removed");
        display::warning("   • Firewall rules will be cleaned up");
        display::warning("   • Configuration files will be deleted");
        println!();

        // Ask for purge option
        let purge = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Also remove Docker images and log files? (Complete cleanup)")
            .default(false)
            .interact()?;

        if purge {
            display::warning("   • Docker images will be removed");
            display::warning("   • All log files will be deleted");
            display::warning("   • This cannot be undone!");
            println!();
        }

        // Final confirmation
        let confirm = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Are you sure you want to proceed with uninstallation?")
            .default(false)
            .interact()?;

        if confirm {
            self.check_admin_privileges("Server uninstallation")?;
            display::info("Starting server uninstallation...");

            match self.handler.uninstall_server(purge).await {
                Ok(_) => {
                    display::success("Server uninstalled successfully!");
                    println!();
                    display::info("The VPN server has been completely removed from this system.");
                    if !purge {
                        display::info("Note: Some Docker images and logs may still remain.");
                        display::info("Use 'Complete cleanup' option to remove everything.");
                    }
                }
                Err(e) => {
                    display::error(&format!("Uninstallation failed: {}", e));
                }
            }
        } else {
            display::info("Uninstallation cancelled.");
        }

        Ok(())
    }

    fn wait_for_keypress(&self) -> Result<()> {
        println!();
        println!("{}", style("Press any key to continue...").dim());
        let _ = self.term.read_key();
        Ok(())
    }
}
