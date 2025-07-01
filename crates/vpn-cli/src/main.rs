use clap::Parser;
use colored::*;
use std::process;
use tokio;

use vpn_cli::{Cli, Commands, InteractiveMenu, CommandHandler, ConfigManager, CliError, PrivilegeManager};

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    
    // Check and request privileges if needed for specific commands
    if let Some(ref _command) = cli.command {
        let args: Vec<String> = std::env::args().collect();
        if PrivilegeManager::command_needs_root(&args) {
            if let Err(e) = PrivilegeManager::ensure_root_privileges() {
                eprintln!("{} {}", "Error:".red(), e);
                process::exit(1);
            }
        }
    }
    // For interactive menu, privilege checks are done per-operation
    
    // Initialize configuration
    let config_manager = match ConfigManager::new(cli.config.clone()) {
        Ok(manager) => manager,
        Err(e) => {
            eprintln!("{} {}", "Error:".red(), e);
            process::exit(1);
        }
    };

    // Set up logging based on verbosity
    setup_logging(cli.verbose, cli.quiet);

    // Check installation directory permissions
    if let Err(e) = check_installation_permissions(&cli).await {
        eprintln!("{} {}", "Error:".red(), e);
        process::exit(1);
    }

    // Show privilege status if verbose
    if cli.verbose {
        PrivilegeManager::show_privilege_status();
        println!();
    }

    // Initialize command handler
    let command_handler = match CommandHandler::new(config_manager, cli.install_path.clone()).await {
        Ok(handler) => handler,
        Err(e) => {
            eprintln!("{} {}", "Error:".red(), e);
            process::exit(1);
        }
    };

    // Execute command or start interactive menu
    let result = match cli.command {
        Some(ref command) => execute_command(command_handler, command.clone(), &cli).await,
        None => start_interactive_menu(command_handler).await,
    };

    if let Err(e) = result {
        eprintln!("{} {}", "Error:".red(), e);
        process::exit(1);
    }
}

async fn execute_command(
    mut handler: CommandHandler,
    command: Commands,
    cli: &Cli,
) -> Result<(), CliError> {
    handler.set_output_format(cli.format.clone());
    handler.set_force_mode(cli.force);

    match command {
        Commands::Install { protocol, port, sni, firewall, auto_start, subnet, interactive_subnet } => {
            handler.install_server(protocol, port, sni, firewall, auto_start, subnet, interactive_subnet).await
        }
        Commands::Uninstall { purge } => {
            handler.uninstall_server(purge).await
        }
        Commands::Start => {
            handler.start_server().await
        }
        Commands::Stop => {
            handler.stop_server().await
        }
        Commands::Restart => {
            handler.restart_server().await
        }
        Commands::Reload => {
            handler.reload_server().await
        }
        Commands::Status { detailed, watch } => {
            handler.show_status(detailed, watch).await
        }
        Commands::Users(user_cmd) => {
            handler.handle_user_command(user_cmd).await
        }
        Commands::Config(config_cmd) => {
            handler.handle_config_command(config_cmd).await
        }
        Commands::Monitor(monitor_cmd) => {
            handler.handle_monitor_command(monitor_cmd).await
        }
        Commands::Security(security_cmd) => {
            handler.handle_security_command(security_cmd).await
        }
        Commands::Migration(migration_cmd) => {
            handler.handle_migration_command(migration_cmd).await
        }
        Commands::Runtime(runtime_cmd) => {
            handler.handle_runtime_command(runtime_cmd).await
        }
        Commands::Compose(compose_cmd) => {
            vpn_cli::compose::handle_compose_command(
                compose_cmd, 
                cli.config.clone(),
                cli.install_path.clone(),
                cli.verbose
            ).await.map_err(CliError::from)
        }
        Commands::Menu => {
            start_interactive_menu(handler).await
        }
        Commands::Diagnostics { fix } => {
            handler.run_diagnostics(fix).await
        }
        Commands::Doctor { fix } => {
            handler.run_diagnostics(fix).await
        }
        Commands::Info => {
            handler.show_system_info().await
        }
        Commands::Benchmark => {
            handler.run_benchmark().await
        }
        Commands::Privileges => {
            PrivilegeManager::show_privilege_status();
            Ok(())
        }
        Commands::NetworkCheck => {
            handler.check_network_status().await
        }
    }
}

async fn start_interactive_menu(handler: CommandHandler) -> Result<(), CliError> {
    println!("{}", "Welcome to VPN Server Management".cyan().bold());
    println!("{}", "=================================".cyan());
    
    let mut menu = InteractiveMenu::new(handler);
    menu.run().await
}

async fn check_installation_permissions(cli: &Cli) -> Result<(), CliError> {
    // Check if installation path is writable when needed
    if let Err(e) = PrivilegeManager::check_install_path_permissions(&cli.install_path) {
        if PrivilegeManager::is_root() {
            // If we're root but still can't write, it's a real problem
            return Err(e);
        } else {
            // If we're not root, show warning but continue in read-only mode
            eprintln!("{}", format!("Warning: {}", e).yellow());
            eprintln!("{}", "Running in read-only mode. Some operations may be limited.".yellow());
        }
    }
    Ok(())
}

fn setup_logging(verbose: bool, quiet: bool) {
    use tracing_subscriber::{EnvFilter, fmt};
    
    if quiet {
        return; // No logging in quiet mode
    }
    
    let level = if verbose {
        "debug"
    } else {
        "info"
    };
    
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(level));
    
    fmt()
        .with_env_filter(filter)
        .with_target(false)
        .with_thread_ids(false)
        .with_file(false)
        .with_line_number(false)
        .init();
}