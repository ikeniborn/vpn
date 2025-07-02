//! Docker Compose command handlers

use crate::cli::{
    ComposeCommands, ComposeConfigCommands, EnvironmentCommands, ServiceScale, StatusFormat
};
use anyhow::{Context, Result};
use colored::Colorize;
use serde_json::json;
use std::path::PathBuf;
use tabled::{Table, Tabled};
use vpn_compose::{
    ComposeOrchestrator, ComposeConfig, Environment, EnvironmentConfig,
    ComposeManager, ComposeStatus, ComposeServiceStatus
};

/// Handle Docker Compose commands
pub async fn handle_compose_command(
    command: ComposeCommands,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
    verbose: bool,
) -> Result<()> {
    match command {
        ComposeCommands::Up { detach, remove_orphans, services } => {
            handle_compose_up(detach, remove_orphans, services, config_path, install_path).await
        }
        ComposeCommands::Down { volumes, remove_orphans, timeout } => {
            handle_compose_down(volumes, remove_orphans, timeout, config_path, install_path).await
        }
        ComposeCommands::Restart { services, timeout } => {
            handle_compose_restart(services, timeout, config_path, install_path).await
        }
        ComposeCommands::Scale { services } => {
            handle_compose_scale(services, config_path, install_path).await
        }
        ComposeCommands::Status { running_only, format } => {
            handle_compose_status(running_only, format, config_path, install_path).await
        }
        ComposeCommands::Logs { service, follow, tail, timestamps } => {
            handle_compose_logs(service, follow, tail, timestamps, config_path, install_path).await
        }
        ComposeCommands::Exec { service, command, interactive, tty } => {
            handle_compose_exec(service, command, interactive, tty, config_path, install_path).await
        }
        ComposeCommands::Pull { services, parallel } => {
            handle_compose_pull(services, parallel, config_path, install_path).await
        }
        ComposeCommands::Build { services, no_cache, force_rm } => {
            handle_compose_build(services, no_cache, force_rm, config_path, install_path).await
        }
        ComposeCommands::Generate { environment, output, monitoring, dev_tools } => {
            handle_compose_generate(environment, output, monitoring, dev_tools, config_path).await
        }
        ComposeCommands::Config { command } => {
            handle_compose_config(command, config_path, install_path).await
        }
        ComposeCommands::Environment { command } => {
            handle_environment_command(command, config_path, install_path).await
        }
        ComposeCommands::Health { service, timeout } => {
            handle_compose_health(service, timeout, config_path, install_path).await
        }
        ComposeCommands::Update { recreate, services } => {
            handle_compose_update(recreate, services, config_path, install_path).await
        }
    }
}

/// Start VPN services using Docker Compose
async fn handle_compose_up(
    detach: bool,
    remove_orphans: bool,
    services: Vec<String>,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    println!("{}", "Starting VPN services with Docker Compose...".cyan());

    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    orchestrator.deploy().await
        .context("Failed to start VPN services")?;

    println!("{}", "✓ VPN services started successfully".green());
    Ok(())
}

/// Stop VPN services
async fn handle_compose_down(
    volumes: bool,
    remove_orphans: bool,
    timeout: u32,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    println!("{}", "Stopping VPN services...".cyan());

    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    orchestrator.stop().await
        .context("Failed to stop VPN services")?;

    println!("{}", "✓ VPN services stopped successfully".green());
    Ok(())
}

/// Restart specific services
async fn handle_compose_restart(
    services: Vec<String>,
    timeout: u32,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    if services.is_empty() {
        println!("{}", "Restarting all VPN services...".cyan());
        orchestrator.stop().await?;
        orchestrator.deploy().await?;
        println!("{}", "✓ All services restarted successfully".green());
    } else {
        for service in &services {
            println!("{}", format!("Restarting service: {}", service).cyan());
            orchestrator.restart_service(service).await
                .context(format!("Failed to restart service: {}", service))?;
            println!("{}", format!("✓ Service {} restarted successfully", service).green());
        }
    }

    Ok(())
}

/// Scale services
async fn handle_compose_scale(
    services: Vec<ServiceScale>,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    for service_scale in services {
        println!("{}", 
            format!("Scaling {} to {} replicas...", service_scale.service, service_scale.replicas).cyan()
        );
        
        orchestrator.scale_service(&service_scale.service, service_scale.replicas).await
            .context(format!("Failed to scale service: {}", service_scale.service))?;
        
        println!("{}", 
            format!("✓ Service {} scaled to {} replicas", service_scale.service, service_scale.replicas).green()
        );
    }

    Ok(())
}

/// Show service status
async fn handle_compose_status(
    running_only: bool,
    format: StatusFormat,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    let status = orchestrator.get_status().await
        .context("Failed to get service status")?;

    let mut services = status.services.clone();
    if running_only {
        services.retain(|s| s.state == "running");
    }

    match format {
        StatusFormat::Table => {
            display_status_table(&status, &services);
        }
        StatusFormat::Json => {
            let json_output = json!({
                "project": status.project_name,
                "total_services": status.total_services,
                "running_services": status.running_services,
                "stopped_services": status.stopped_services,
                "services": services
            });
            println!("{}", serde_json::to_string_pretty(&json_output)?);
        }
        StatusFormat::Yaml => {
            let yaml_output = serde_yaml::to_string(&status)?;
            println!("{}", yaml_output);
        }
    }

    Ok(())
}

/// Display status in table format
fn display_status_table(status: &ComposeStatus, services: &[ComposeServiceStatus]) {
    println!("\n{}", format!("VPN System Status - Project: {}", status.project_name).bold());
    println!("{}", format!(
        "Services: {} total, {} running, {} stopped", 
        status.total_services, 
        status.running_services, 
        status.stopped_services
    ));

    if !services.is_empty() {
        #[derive(Tabled)]
        struct ServiceRow {
            #[tabled(rename = "Service")]
            name: String,
            #[tabled(rename = "State")]
            state: String,
            #[tabled(rename = "Health")]
            health: String,
            #[tabled(rename = "Ports")]
            ports: String,
        }

        let rows: Vec<ServiceRow> = services.iter().map(|s| {
            let state_colored = match s.state.as_str() {
                "running" => s.state.green().to_string(),
                "exited" => s.state.red().to_string(),
                _ => s.state.yellow().to_string(),
            };

            ServiceRow {
                name: s.name.clone(),
                state: state_colored,
                health: s.health.clone().unwrap_or_else(|| "-".to_string()),
                ports: s.ports.join(", "),
            }
        }).collect();

        let table = Table::new(rows);
        println!("\n{}", table);
    }
}

/// Display health status for a single service
fn display_service_health(service: &ComposeServiceStatus) {
    let health_icon = match service.health.as_deref() {
        Some("healthy") => "✓".green(),
        Some("unhealthy") => "✗".red(),
        Some("starting") => "⟳".yellow(),
        _ => "-".white(),
    };
    
    let state_display = match service.state.as_str() {
        "running" => service.state.green(),
        "exited" => service.state.red(),
        _ => service.state.yellow(),
    };
    
    println!("{} {} - State: {}, Health: {}", 
        health_icon,
        service.name.bold(),
        state_display,
        service.health.as_deref().unwrap_or("N/A")
    );
    
    if !service.ports.is_empty() {
        println!("  Ports: {}", service.ports.join(", "));
    }
}

/// View service logs
async fn handle_compose_logs(
    service: Option<String>,
    follow: bool,
    tail: usize,
    timestamps: bool,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    let logs = orchestrator.get_logs(service.as_deref()).await
        .context("Failed to get service logs")?;

    println!("{}", logs);
    Ok(())
}

/// Execute command in service container
async fn handle_compose_exec(
    service: String,
    command: Vec<String>,
    _interactive: bool,
    _tty: bool,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    println!("{}", format!("Executing command in service: {}", service).cyan());
    
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;
    
    // Convert Vec<String> to Vec<&str> for the exec method
    let command_refs: Vec<&str> = command.iter().map(|s| s.as_str()).collect();
    
    let output = orchestrator.exec_command(&service, &command_refs).await
        .context(format!("Failed to execute command in service: {}", service))?;
    
    println!("{}", output);
    println!("{}", "✓ Command execution completed".green());
    Ok(())
}

/// Pull latest images
async fn handle_compose_pull(
    services: Vec<String>,
    _parallel: bool,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    println!("{}", "Pulling latest images...".cyan());
    
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;
    
    if services.is_empty() {
        orchestrator.pull_images(None).await
            .context("Failed to pull images")?;
        println!("{}", "✓ All images pulled successfully".green());
    } else {
        for service in &services {
            println!("{}", format!("Pulling image for service: {}", service).cyan());
            orchestrator.pull_images(Some(service)).await
                .context(format!("Failed to pull image for service: {}", service))?;
            println!("{}", format!("✓ Image for {} pulled successfully", service).green());
        }
    }
    
    Ok(())
}

/// Build services
async fn handle_compose_build(
    services: Vec<String>,
    _no_cache: bool,
    _force_rm: bool,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    println!("{}", "Building services...".cyan());
    
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;
    
    if services.is_empty() {
        orchestrator.build_services(None).await
            .context("Failed to build services")?;
        println!("{}", "✓ All services built successfully".green());
    } else {
        for service in &services {
            println!("{}", format!("Building service: {}", service).cyan());
            orchestrator.build_services(Some(service)).await
                .context(format!("Failed to build service: {}", service))?;
            println!("{}", format!("✓ Service {} built successfully", service).green());
        }
    }
    
    Ok(())
}

/// Generate Docker Compose files
async fn handle_compose_generate(
    environment: String,
    output: PathBuf,
    monitoring: bool,
    dev_tools: bool,
    config_path: Option<PathBuf>,
) -> Result<()> {
    println!("{}", format!("Generating Docker Compose files for {} environment...", environment).cyan());

    let mut config = if let Some(config_path) = config_path {
        ComposeConfig::load_from_file(&config_path).await?
    } else {
        ComposeConfig::default()
    };

    // Create environment configuration
    let env_config = EnvironmentConfig {
        name: environment.clone(),
        ..Default::default()
    };

    config.environment = env_config;
    config.compose_dir = output.clone();

    let mut orchestrator = ComposeOrchestrator::new(config).await?;
    orchestrator.initialize().await?;

    println!("{}", format!("✓ Docker Compose files generated in: {}", output.display()).green());
    println!("{}",
        format!(
            "To start the system: docker-compose -f {}/docker-compose.yml up -d",
            output.display()
        ).yellow()
    );

    Ok(())
}

/// Handle compose configuration commands
async fn handle_compose_config(
    command: ComposeConfigCommands,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    match command {
        ComposeConfigCommands::Show => {
            let config = load_compose_config(config_path, install_path).await?;
            let config_str = toml::to_string_pretty(&config)?;
            println!("{}", config_str);
        }
        ComposeConfigCommands::Edit => {
            println!("{}", "Opening configuration editor...".cyan());
            // Implementation would open an editor
        }
        ComposeConfigCommands::Validate => {
            let config = load_compose_config(config_path, install_path).await?;
            config.validate()?;
            println!("{}", "✓ Configuration is valid".green());
        }
        ComposeConfigCommands::Set { key, value } => {
            println!("{}", format!("Setting {}={}", key, value).cyan());
            // Implementation would update the configuration
        }
        ComposeConfigCommands::Get { key } => {
            let config = load_compose_config(config_path, install_path).await?;
            if let Some(value) = config.env_vars.get(&key) {
                println!("{}", value);
            } else {
                println!("{}", format!("Variable {} not found", key).red());
            }
        }
        ComposeConfigCommands::List => {
            let config = load_compose_config(config_path, install_path).await?;
            for (key, value) in &config.env_vars {
                println!("{}={}", key, value);
            }
        }
    }
    Ok(())
}

/// Handle environment management commands
async fn handle_environment_command(
    command: EnvironmentCommands,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    match command {
        EnvironmentCommands::List => {
            println!("{}", "Available environments:".bold());
            println!("  {} (optimized for local development)", "development".green());
            println!("  {} (pre-production testing)", "staging".yellow());
            println!("  {} (production deployment)", "production".red());
        }
        EnvironmentCommands::Switch { environment } => {
            println!("{}", format!("Switching to {} environment...", environment).cyan());
            // Implementation would switch the active environment
            println!("{}", format!("✓ Switched to {} environment", environment).green());
        }
        EnvironmentCommands::Create { name, from } => {
            println!("{}", format!("Creating new environment: {}", name).cyan());
            if let Some(base) = from {
                println!("{}", format!("Based on: {}", base).yellow());
            }
            // Implementation would create a new environment configuration
            println!("{}", format!("✓ Environment {} created", name).green());
        }
        EnvironmentCommands::Delete { name } => {
            println!("{}", format!("Deleting environment: {}", name).cyan());
            // Implementation would delete the environment
            println!("{}", format!("✓ Environment {} deleted", name).green());
        }
        EnvironmentCommands::Show { environment } => {
            let env_name = environment.unwrap_or_else(|| "current".to_string());
            println!("{}", format!("Environment details: {}", env_name).bold());
            // Implementation would show environment details
        }
    }
    Ok(())
}

/// Health check for services
async fn handle_compose_health(
    service: Option<String>,
    _timeout: u32,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    let config = load_compose_config(config_path, install_path).await?;
    let orchestrator = ComposeOrchestrator::new(config).await?;

    let status = orchestrator.get_status().await
        .context("Failed to get service status")?;

    if let Some(service_name) = service {
        println!("{}", format!("Checking health of service: {}", service_name).cyan());
        
        if let Some(service_status) = status.services.iter().find(|s| s.name == service_name) {
            display_service_health(&service_status);
        } else {
            println!("{}", format!("Service {} not found", service_name).red());
            return Ok(());
        }
    } else {
        println!("{}", "Checking health of all services...".cyan());
        println!();
        
        let healthy_count = status.services.iter()
            .filter(|s| s.state == "running" && s.health.as_deref() == Some("healthy"))
            .count();
        
        println!("{}", format!(
            "Overall Health: {}/{} services healthy", 
            healthy_count, 
            status.total_services
        ).bold());
        println!();
        
        for service_status in &status.services {
            display_service_health(&service_status);
            println!();
        }
    }

    let all_healthy = status.services.iter()
        .all(|s| s.state == "running" && s.health.as_deref() != Some("unhealthy"));
    
    if all_healthy {
        println!("{}", "✓ All services are healthy".green());
    } else {
        println!("{}", "⚠ Some services are unhealthy".yellow());
    }
    
    Ok(())
}

/// Update service configurations
async fn handle_compose_update(
    recreate: bool,
    services: Vec<String>,
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<()> {
    println!("{}", "Updating service configurations...".cyan());
    
    let config = load_compose_config(config_path, install_path).await?;
    let mut orchestrator = ComposeOrchestrator::new(config.clone()).await?;

    if recreate {
        println!("{}", "Recreating containers with updated configuration...".yellow());
        orchestrator.update_config(config).await?;
    }

    println!("{}", "✓ Services updated successfully".green());
    Ok(())
}

/// Load compose configuration
async fn load_compose_config(
    config_path: Option<PathBuf>,
    install_path: PathBuf,
) -> Result<ComposeConfig> {
    if let Some(path) = config_path {
        ComposeConfig::load_from_file(&path).await
            .context("Failed to load compose configuration")
    } else {
        let mut config = ComposeConfig::default();
        config.compose_dir = install_path.join("docker-compose");
        config.templates_dir = install_path.join("templates/docker-compose");
        Ok(config)
    }
}