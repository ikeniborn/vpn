//! VPN Kubernetes Operator
//!
//! This binary runs the VPN operator that manages VPN deployments in Kubernetes.

use anyhow::Result;
use clap::Parser;
use tracing::{error, info};
use vpn_operator::{OperatorConfig, VpnOperator};

#[derive(Parser, Debug)]
#[clap(
    name = "vpn-operator",
    version,
    about = "Kubernetes operator for managing VPN deployments"
)]
struct Args {
    /// Config file path
    #[clap(short, long, default_value = "/etc/vpn-operator/config.yaml")]
    config: String,

    /// Namespace to watch (empty for all namespaces)
    #[clap(short, long)]
    namespace: Option<String>,

    /// Metrics port
    #[clap(long, default_value = "8080")]
    metrics_port: u16,

    /// Webhook port (0 to disable)
    #[clap(long, default_value = "9443")]
    webhook_port: u16,

    /// VPN container image
    #[clap(long, default_value = "vpn-server:latest")]
    vpn_image: String,

    /// Enable debug logging
    #[clap(short, long)]
    debug: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logging
    let log_level = if args.debug { "debug" } else { "info" };
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                format!("vpn_operator={},kube={}", log_level, log_level)
                    .parse()
                    .unwrap()
            }),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("Starting VPN Kubernetes Operator");
    info!("Version: {}", env!("CARGO_PKG_VERSION"));

    // Load or create configuration
    let config = if std::path::Path::new(&args.config).exists() {
        info!("Loading configuration from {}", args.config);
        let config_str = std::fs::read_to_string(&args.config)?;
        serde_yaml::from_str(&config_str)?
    } else {
        info!("Using default configuration");
        OperatorConfig {
            namespace: args.namespace,
            vpn_image: args.vpn_image,
            metrics_port: args.metrics_port,
            webhook_port: args.webhook_port,
            ..Default::default()
        }
    };

    // Create and run operator
    let operator = VpnOperator::new(config).await?;

    // Handle shutdown gracefully
    let shutdown = tokio::signal::ctrl_c();

    tokio::select! {
        result = operator.run() => {
            if let Err(e) = result {
                error!("Operator error: {}", e);
                std::process::exit(1);
            }
        }
        _ = shutdown => {
            info!("Received shutdown signal");
        }
    }

    info!("VPN operator stopped");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_args_parsing() {
        let args = Args::parse_from(&[
            "vpn-operator",
            "--namespace",
            "vpn-system",
            "--metrics-port",
            "9090",
            "--vpn-image",
            "custom-vpn:v1.0",
        ]);

        assert_eq!(args.namespace, Some("vpn-system".to_string()));
        assert_eq!(args.metrics_port, 9090);
        assert_eq!(args.vpn_image, "custom-vpn:v1.0");
    }
}
