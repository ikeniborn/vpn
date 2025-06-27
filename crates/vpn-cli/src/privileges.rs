use std::process::{Command, Stdio};
use std::env;
use std::io::{self, Write};
use colored::*;
use crate::error::{CliError, Result};

pub struct PrivilegeManager;

impl PrivilegeManager {
    /// Check if running as root
    pub fn is_root() -> bool {
        #[cfg(unix)]
        {
            unsafe { libc::geteuid() == 0 }
        }
        #[cfg(not(unix))]
        {
            // On non-Unix systems, assume we have the necessary permissions
            true
        }
    }

    /// Check if command requires root privileges
    pub fn command_needs_root(args: &[String]) -> bool {
        // Commands that typically need root access
        let root_commands = [
            "install", "uninstall", "start", "stop", "restart", 
            "reload", "diagnostics", "security", "menu"
        ];
        
        // User management write operations also need root
        let user_write_ops = ["create", "delete", "update", "import"];
        
        // Check main commands
        if args.iter().any(|arg| root_commands.contains(&arg.as_str())) {
            return true;
        }
        
        // Check user subcommands
        if args.len() >= 2 && args[1] == "users" && args.len() >= 3 {
            if user_write_ops.contains(&args[2].as_str()) {
                return true;
            }
        }
        
        false
    }

    /// Get user-friendly operation name from command arguments
    fn get_operation_name(args: &[String]) -> String {
        if args.len() < 2 {
            return "VPN Management".to_string();
        }

        match args[1].as_str() {
            "install" => "VPN Server Installation".to_string(),
            "uninstall" => "VPN Server Uninstallation".to_string(),
            "start" => "Start VPN Server".to_string(),
            "stop" => "Stop VPN Server".to_string(),
            "restart" => "Restart VPN Server".to_string(),
            "reload" => "Reload VPN Configuration".to_string(),
            "diagnostics" => "System Diagnostics".to_string(),
            "security" => "Security Operations".to_string(),
            "menu" => "VPN Management Menu".to_string(),
            "users" => {
                if args.len() >= 3 {
                    match args[2].as_str() {
                        "create" => "Create VPN User".to_string(),
                        "delete" => "Delete VPN User".to_string(),
                        "update" => "Update VPN User".to_string(),
                        "import" => "Import VPN Users".to_string(),
                        _ => "User Management".to_string(),
                    }
                } else {
                    "User Management".to_string()
                }
            }
            _ => "VPN Operation".to_string(),
        }
    }

    /// Request elevated privileges and restart if needed
    pub fn ensure_root_privileges() -> Result<()> {
        if Self::is_root() {
            return Ok(());
        }

        let args: Vec<String> = env::args().collect();
        
        if !Self::command_needs_root(&args) {
            return Ok(());
        }

        // Check if we're already being run under sudo (avoid infinite recursion)
        if env::var("SUDO_USER").is_ok() {
            return Err(CliError::PermissionError(
                "Already running under sudo but still don't have root privileges".to_string()
            ));
        }

        // Determine the operation name for user-friendly message
        let operation = Self::get_operation_name(&args);
        
        println!("{}", format!("'{}' requires administrator privileges.", operation).yellow());
        
        // Interactive confirmation
        if !Self::prompt_for_privilege_elevation(&operation)? {
            return Err(CliError::PermissionError(
                "Operation cancelled by user".to_string()
            ));
        }
        
        // Try to get privilege elevation
        Self::request_sudo_privileges(&args)
    }

    /// Request sudo privileges and re-execute with elevated rights
    fn request_sudo_privileges(args: &[String]) -> Result<()> {
        let current_exe = env::current_exe()
            .map_err(|e| CliError::PermissionError(format!("Cannot get current executable path: {}", e)))?;
        
        println!("{}", "Requesting administrator privileges...".cyan());
        
        // Check if sudo is available
        if !Self::is_sudo_available() {
            return Err(CliError::PermissionError(
                "sudo is not available. Please run as administrator manually.".to_string()
            ));
        }

        // Prepare command for sudo execution
        let mut cmd_args = vec![current_exe.to_string_lossy().to_string()];
        cmd_args.extend_from_slice(&args[1..]);

        println!("{} sudo {}", "Executing:".dimmed(), cmd_args.join(" ").dimmed());
        
        // Execute with sudo
        let status = Command::new("sudo")
            .args(&cmd_args)
            .status()
            .map_err(|e| CliError::PermissionError(format!("Failed to execute sudo: {}", e)))?;

        // Exit with the same code as the sudo process
        std::process::exit(status.code().unwrap_or(1));
    }

    /// Check if sudo is available on the system
    fn is_sudo_available() -> bool {
        Command::new("which")
            .arg("sudo")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }

    /// Prompt user for confirmation before requesting privileges
    pub fn prompt_for_privilege_elevation(operation: &str) -> Result<bool> {
        print!("{} requires administrator privileges. Continue? [y/N]: ", operation.yellow());
        io::stdout().flush().unwrap();
        
        let mut input = String::new();
        io::stdin().read_line(&mut input)
            .map_err(|e| CliError::PermissionError(format!("Failed to read input: {}", e)))?;
        
        let input = input.trim().to_lowercase();
        Ok(input == "y" || input == "yes")
    }

    /// Check installation directory permissions
    pub fn check_install_path_permissions(path: &std::path::Path) -> Result<()> {
        // Try to create a test file in the directory
        let test_file = path.join(".vpn_permission_test");
        
        match std::fs::write(&test_file, "test") {
            Ok(_) => {
                // Clean up test file
                let _ = std::fs::remove_file(&test_file);
                Ok(())
            }
            Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
                Err(CliError::PermissionError(format!(
                    "No write permission to installation directory: {}. Run with administrator privileges.",
                    path.display()
                )))
            }
            Err(e) => {
                Err(CliError::PermissionError(format!(
                    "Cannot access installation directory {}: {}",
                    path.display(), e
                )))
            }
        }
    }

    /// Get effective user information
    pub fn get_user_info() -> UserInfo {
        let current_user = env::var("USER").unwrap_or_else(|_| "unknown".to_string());
        let sudo_user = env::var("SUDO_USER").ok();
        let is_root = Self::is_root();
        
        UserInfo {
            current_user,
            sudo_user,
            is_root,
        }
    }

    /// Show privilege status
    pub fn show_privilege_status() {
        let user_info = Self::get_user_info();
        
        println!("{}", "Privilege Status:".cyan().bold());
        println!("  Current user: {}", user_info.current_user.green());
        
        if let Some(sudo_user) = &user_info.sudo_user {
            println!("  Original user: {}", sudo_user.yellow());
        }
        
        if user_info.is_root {
            println!("  Status: {} (Administrator)", "Elevated".green().bold());
            println!("  Capabilities: {}", "Full VPN management access".green());
        } else {
            println!("  Status: {} (Limited access)", "Standard".yellow());
            println!("  Capabilities: {}", "Read-only operations only".yellow());
            println!();
            println!("{}", "To perform administrative operations:".cyan());
            println!("  • VPN CLI will automatically request privileges when needed");
            println!("  • You can manually run with: {}", "sudo vpn <command>".green());
            println!("  • Or check specific operations: {}", "vpn privileges".green());
        }
    }
}

#[derive(Debug)]
pub struct UserInfo {
    pub current_user: String,
    pub sudo_user: Option<String>,
    pub is_root: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_needs_root() {
        let install_args = vec!["vpn".to_string(), "install".to_string()];
        assert!(PrivilegeManager::command_needs_root(&install_args));
        
        let list_args = vec!["vpn".to_string(), "users".to_string(), "list".to_string()];
        assert!(!PrivilegeManager::command_needs_root(&list_args));
        
        let create_args = vec!["vpn".to_string(), "users".to_string(), "create".to_string(), "test".to_string()];
        assert!(PrivilegeManager::command_needs_root(&create_args));
    }

    #[test]
    fn test_is_sudo_available() {
        // This test may fail on systems without sudo, which is expected
        let available = PrivilegeManager::is_sudo_available();
        println!("Sudo available: {}", available);
    }
}