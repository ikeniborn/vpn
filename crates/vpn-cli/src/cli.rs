use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "vpn",
    about = "Advanced VPN Server Management Tool",
    version = env!("CARGO_PKG_VERSION"),
    author = "VPN Project Team",
    long_about = "A comprehensive VPN server management tool supporting multiple protocols including VLESS+Reality, Shadowsocks, and more."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,

    /// Configuration file path
    #[arg(short, long, value_name = "FILE")]
    pub config: Option<PathBuf>,

    /// Installation directory
    #[arg(short, long, default_value = "/opt/vpn")]
    pub install_path: PathBuf,

    /// Enable verbose output
    #[arg(short, long)]
    pub verbose: bool,

    /// Suppress output
    #[arg(short, long)]
    pub quiet: bool,

    /// Force operations without confirmation
    #[arg(short, long)]
    pub force: bool,

    /// Output format (json, table, plain)
    #[arg(long, default_value = "table")]
    pub format: OutputFormat,
}

#[derive(Subcommand, Clone)]
pub enum Commands {
    /// Install VPN server
    Install {
        /// VPN protocol to install
        #[arg(short, long, default_value = "vless")]
        protocol: Protocol,
        
        /// Server port
        #[arg(short = 'P', long)]
        port: Option<u16>,
        
        /// SNI domain for Reality protocol
        #[arg(short, long)]
        sni: Option<String>,
        
        /// Enable firewall rules
        #[arg(long, default_value = "true")]
        firewall: bool,
        
        /// Auto-start service
        #[arg(long, default_value = "true")]
        auto_start: bool,
        
        /// Docker subnet for VPN network (CIDR format, e.g., 172.30.0.0/16)
        #[arg(long)]
        subnet: Option<String>,
        
        /// Interactive subnet selection
        #[arg(long)]
        interactive_subnet: bool,
    },

    /// Uninstall VPN server
    Uninstall {
        /// Remove all data including users
        #[arg(long)]
        purge: bool,
    },

    /// Start VPN server
    Start,

    /// Stop VPN server
    Stop,

    /// Restart VPN server
    Restart,

    /// Reload server configuration
    Reload,

    /// Show server status
    Status {
        /// Show detailed status
        #[arg(short, long)]
        detailed: bool,
        
        /// Continuous monitoring
        #[arg(short, long)]
        watch: bool,
    },

    /// User management commands
    #[command(subcommand)]
    Users(UserCommands),

    /// Server configuration commands
    #[command(subcommand)]
    Config(ConfigCommands),

    /// Monitoring and statistics commands
    #[command(subcommand)]
    Monitor(MonitorCommands),

    /// Key rotation and security commands
    #[command(subcommand)]
    Security(SecurityCommands),

    /// Migration and backup commands
    #[command(subcommand)]
    Migration(MigrationCommands),

    /// Runtime management commands
    #[command(subcommand)]
    Runtime(RuntimeCommands),

    /// Docker Compose orchestration commands
    #[command(subcommand)]
    Compose(ComposeCommands),

    /// Interactive menu mode
    Menu,

    /// Run diagnostics
    Diagnostics {
        /// Fix issues automatically
        #[arg(short, long)]
        fix: bool,
    },

    /// Run system compatibility check (alias for diagnostics)
    Doctor {
        /// Fix issues automatically
        #[arg(short, long)]
        fix: bool,
    },

    /// Show system information
    Info,

    /// Run performance benchmark
    Benchmark,

    /// Show privilege status
    Privileges,
    
    /// Check Docker network status and available subnets
    NetworkCheck,

    /// Generate shell completion scripts
    Completions {
        /// Shell to generate completions for
        #[arg(value_enum)]
        shell: Shell,
        
        /// Output file (defaults to stdout)
        #[arg(short, long)]
        output: Option<PathBuf>,
    },
    
    /// Proxy server management commands
    #[command(subcommand)]
    Proxy(ProxyCommands),
}

#[derive(Subcommand, Clone)]
pub enum ProxyCommands {
    /// Show proxy server status
    Status {
        /// Show detailed metrics
        #[arg(short, long)]
        detailed: bool,
        
        /// Output format (json, table)
        #[arg(short, long, default_value = "table")]
        format: StatusFormat,
    },
    
    /// Monitor proxy connections in real-time
    Monitor {
        /// Filter by user
        #[arg(short, long)]
        user: Option<String>,
        
        /// Refresh interval in seconds
        #[arg(short, long, default_value = "1")]
        interval: u64,
        
        /// Show only active connections
        #[arg(long)]
        active_only: bool,
    },
    
    /// Show proxy statistics
    Stats {
        /// Time period in hours
        #[arg(short = 't', long, default_value = "24")]
        hours: u32,
        
        /// Group by user
        #[arg(long)]
        by_user: bool,
        
        /// Output format (json, table)
        #[arg(short, long, default_value = "table")]
        format: StatusFormat,
    },
    
    /// Test proxy connectivity
    Test {
        /// Target URL to test
        #[arg(default_value = "https://example.com")]
        url: String,
        
        /// Proxy protocol to test (http, socks5, both)
        #[arg(short, long, default_value = "both")]
        protocol: String,
        
        /// Test authentication
        #[arg(long)]
        auth: bool,
        
        /// Username for authentication test
        #[arg(short, long)]
        username: Option<String>,
        
        /// Password for authentication test
        #[arg(short = 'P', long)]
        password: Option<String>,
    },
    
    /// Manage proxy configuration
    Config {
        /// Configuration subcommands
        #[command(subcommand)]
        command: ProxyConfigCommands,
    },
    
    /// Manage proxy access control
    Access {
        /// Access control subcommands
        #[command(subcommand)]
        command: ProxyAccessCommands,
    },
}

#[derive(Subcommand, Clone)]
pub enum ProxyConfigCommands {
    /// Show current proxy configuration
    Show,
    
    /// Update proxy configuration
    Update {
        /// Maximum connections per user
        #[arg(long)]
        max_connections: Option<u32>,
        
        /// Rate limit (requests per second)
        #[arg(long)]
        rate_limit: Option<u32>,
        
        /// Enable/disable authentication
        #[arg(long)]
        auth_enabled: Option<bool>,
        
        /// Proxy bind address
        #[arg(long)]
        bind_address: Option<String>,
        
        /// SOCKS5 bind address
        #[arg(long)]
        socks5_address: Option<String>,
    },
    
    /// Reload proxy configuration
    Reload,
}

#[derive(Subcommand, Clone)]
pub enum ProxyAccessCommands {
    /// List access rules
    List,
    
    /// Add IP to whitelist
    AddIp {
        /// IP address or CIDR
        ip: String,
        
        /// Description
        #[arg(short, long)]
        description: Option<String>,
    },
    
    /// Remove IP from whitelist
    RemoveIp {
        /// IP address or CIDR
        ip: String,
    },
    
    /// Set user bandwidth limit
    SetBandwidth {
        /// User name or ID
        user: String,
        
        /// Bandwidth limit in MB/s (0 for unlimited)
        limit: u32,
    },
    
    /// Set user connection limit
    SetConnections {
        /// User name or ID
        user: String,
        
        /// Maximum concurrent connections (0 for unlimited)
        limit: u32,
    },
}

#[derive(Subcommand, Clone)]
pub enum UserCommands {
    /// List all users
    List {
        /// Filter by status
        #[arg(short, long)]
        status: Option<UserStatus>,
        
        /// Show detailed information
        #[arg(short, long)]
        detailed: bool,
    },

    /// Create a new user
    Create {
        /// User name
        name: String,
        
        /// User email (optional)
        #[arg(short, long)]
        email: Option<String>,
        
        /// VPN protocol
        #[arg(short, long, default_value = "vless")]
        protocol: Protocol,
    },

    /// Delete a user
    Delete {
        /// User name or ID
        user: String,
    },

    /// Show user details
    Show {
        /// User name or ID
        user: String,
        
        /// Show QR code
        #[arg(short, long)]
        qr: bool,
    },

    /// Generate connection link
    Link {
        /// User name or ID
        user: String,
        
        /// Generate QR code file
        #[arg(short, long)]
        qr_file: Option<PathBuf>,
    },

    /// Update user status
    Update {
        /// User name or ID
        user: String,
        
        /// New status
        #[arg(short, long)]
        status: Option<UserStatus>,
        
        /// New email
        #[arg(short, long)]
        email: Option<String>,
    },

    /// Batch operations
    Batch {
        /// Batch command
        #[command(subcommand)]
        command: BatchCommands,
    },

    /// Reset user traffic statistics
    Reset {
        /// User name or ID
        user: String,
    },
}

#[derive(Subcommand, Clone)]
pub enum BatchCommands {
    /// Create multiple users from file
    Create {
        /// Input file (JSON)
        file: PathBuf,
    },

    /// Delete multiple users
    Delete {
        /// User names/IDs (comma-separated)
        users: String,
    },

    /// Update multiple users
    Update {
        /// User names/IDs (comma-separated)
        users: String,
        
        /// New status
        #[arg(short, long)]
        status: UserStatus,
    },

    /// Export users to file
    Export {
        /// Output file
        file: PathBuf,
    },

    /// Import users from file
    Import {
        /// Input file
        file: PathBuf,
        
        /// Overwrite existing users
        #[arg(long)]
        overwrite: bool,
    },
}

#[derive(Subcommand, Clone)]
pub enum ConfigCommands {
    /// Show current configuration
    Show,

    /// Edit configuration
    Edit,

    /// Validate configuration
    Validate,

    /// Backup configuration
    Backup {
        /// Backup file path
        #[arg(short, long)]
        output: Option<PathBuf>,
    },

    /// Restore configuration
    Restore {
        /// Backup file path
        file: PathBuf,
    },

    /// Reset to default configuration
    Reset,
}

#[derive(Subcommand, Clone)]
pub enum MonitorCommands {
    /// Show traffic statistics
    Traffic {
        /// Time period in hours
        #[arg(short = 't', long, default_value = "24")]
        hours: u32,
        
        /// User filter
        #[arg(short, long)]
        user: Option<String>,
    },

    /// Show system health
    Health {
        /// Continuous monitoring
        #[arg(short, long)]
        watch: bool,
    },

    /// Analyze logs
    Logs {
        /// Number of lines to show
        #[arg(short, long, default_value = "100")]
        lines: usize,
        
        /// Follow logs
        #[arg(short, long)]
        follow: bool,
        
        /// Filter pattern
        #[arg(short, long)]
        pattern: Option<String>,
    },

    /// Show performance metrics
    Metrics {
        /// Time period in hours
        #[arg(short = 't', long, default_value = "1")]
        hours: u32,
    },

    /// Manage alerts
    Alerts {
        /// Alert command
        #[command(subcommand)]
        command: AlertCommands,
    },
}

#[derive(Subcommand, Clone)]
pub enum AlertCommands {
    /// List active alerts
    List,

    /// Acknowledge an alert
    Ack {
        /// Alert ID
        id: String,
    },

    /// Resolve an alert
    Resolve {
        /// Alert ID
        id: String,
    },

    /// Configure alert rules
    Rules,
}

#[derive(Subcommand, Clone)]
pub enum SecurityCommands {
    /// Rotate server keys
    Rotate {
        /// Rotate user keys too
        #[arg(long)]
        users: bool,
        
        /// Create backup before rotation
        #[arg(long, default_value = "true")]
        backup: bool,
    },

    /// Validate all keys
    Validate,

    /// Show security status
    Status,

    /// Generate new server keys
    Generate,
}

#[derive(Subcommand, Clone)]
pub enum MigrationCommands {
    /// Migrate from Bash implementation
    FromBash {
        /// Bash installation path
        #[arg(short, long, default_value = "/opt/v2ray")]
        source: PathBuf,
        
        /// Keep original installation
        #[arg(long)]
        keep_original: bool,
    },

    /// Export to other formats
    Export {
        /// Export format
        #[arg(short, long)]
        format: ExportFormat,
        
        /// Output file
        #[arg(short, long)]
        output: PathBuf,
    },

    /// Import from other formats
    Import {
        /// Import format
        #[arg(short, long)]
        format: ImportFormat,
        
        /// Input file
        #[arg(short, long)]
        input: PathBuf,
    },
}

#[derive(Subcommand, Clone)]
pub enum RuntimeCommands {
    /// Show runtime status and information
    Status,

    /// Switch container runtime (DEPRECATED: containerd support removed)
    Switch {
        /// Runtime to switch to (auto, docker) - containerd deprecated
        runtime: String,
    },

    /// Enable or disable a runtime (DEPRECATED: containerd support removed)
    Enable {
        /// Runtime to configure (docker only) - containerd deprecated
        runtime: String,
        /// Enable (true) or disable (false) the runtime
        #[arg(long)]
        enabled: bool,
    },

    /// Update runtime socket path (DEPRECATED: containerd support removed)
    Socket {
        /// Runtime to configure (docker only) - containerd deprecated
        runtime: String,
        /// New socket path
        path: String,
    },

    /// Migrate from Docker to containerd (DEPRECATED: Feature removed)
    #[deprecated = "Containerd support has been deprecated in favor of Docker Compose orchestration"]
    Migrate,

    /// Show runtime capabilities comparison
    Capabilities,
}

#[derive(Subcommand, Clone)]
pub enum ComposeCommands {
    /// Start all VPN services using Docker Compose
    Up {
        /// Start in detached mode
        #[arg(short, long, default_value = "true")]
        detach: bool,
        
        /// Remove orphaned containers
        #[arg(long, default_value = "true")]
        remove_orphans: bool,
        
        /// Specific services to start
        #[arg(long)]
        services: Vec<String>,
    },

    /// Stop all VPN services
    Down {
        /// Remove volumes
        #[arg(short, long)]
        volumes: bool,
        
        /// Remove orphaned containers
        #[arg(long, default_value = "true")]
        remove_orphans: bool,
        
        /// Timeout for stopping containers (seconds)
        #[arg(short, long, default_value = "10")]
        timeout: u32,
    },

    /// Restart VPN services
    Restart {
        /// Specific services to restart
        services: Vec<String>,
        
        /// Timeout for stopping containers (seconds)
        #[arg(short, long, default_value = "10")]
        timeout: u32,
    },

    /// Scale services
    Scale {
        /// Service scaling specs (service=replicas)
        #[arg(value_parser = parse_service_scale)]
        services: Vec<ServiceScale>,
    },

    /// Show service status
    Status {
        /// Show only running services
        #[arg(long)]
        running_only: bool,
        
        /// Output format (table, json)
        #[arg(short, long, default_value = "table")]
        format: StatusFormat,
    },

    /// View service logs
    Logs {
        /// Specific service to show logs for
        service: Option<String>,
        
        /// Follow log output
        #[arg(short, long)]
        follow: bool,
        
        /// Number of lines to show
        #[arg(short = 'n', long, default_value = "100")]
        tail: usize,
        
        /// Show timestamps
        #[arg(short = 'T', long)]
        timestamps: bool,
    },

    /// Execute command in a service container
    Exec {
        /// Service name
        service: String,
        
        /// Command to execute
        command: Vec<String>,
        
        /// Run in interactive mode
        #[arg(short, long)]
        interactive: bool,
        
        /// Allocate a TTY
        #[arg(short, long)]
        tty: bool,
    },

    /// Pull latest images for all services
    Pull {
        /// Specific services to pull
        services: Vec<String>,
        
        /// Pull images in parallel
        #[arg(long, default_value = "true")]
        parallel: bool,
    },

    /// Build or rebuild services
    Build {
        /// Specific services to build
        services: Vec<String>,
        
        /// Don't use cache when building
        #[arg(long)]
        no_cache: bool,
        
        /// Always remove intermediate containers
        #[arg(long)]
        force_rm: bool,
    },

    /// Generate Docker Compose files
    Generate {
        /// Environment (development, staging, production)
        #[arg(short, long, default_value = "development")]
        environment: String,
        
        /// Output directory
        #[arg(short, long, default_value = "./docker-compose")]
        output: PathBuf,
        
        /// Include monitoring stack
        #[arg(long, default_value = "true")]
        monitoring: bool,
        
        /// Include development tools
        #[arg(long)]
        dev_tools: bool,
    },

    /// Configure environment settings
    Config {
        /// Configuration subcommands
        #[command(subcommand)]
        command: ComposeConfigCommands,
    },

    /// Environment management
    Environment {
        /// Environment subcommands
        #[command(subcommand)]
        command: EnvironmentCommands,
    },

    /// Health check for all services
    Health {
        /// Service to check (default: all)
        service: Option<String>,
        
        /// Timeout for health checks (seconds)
        #[arg(short, long, default_value = "30")]
        timeout: u32,
    },

    /// Update service configurations
    Update {
        /// Recreate containers with updated config
        #[arg(long, default_value = "true")]
        recreate: bool,
        
        /// Specific services to update
        services: Vec<String>,
    },
}

#[derive(Subcommand, Clone)]
pub enum ComposeConfigCommands {
    /// Show current compose configuration
    Show,
    
    /// Edit compose configuration
    Edit,
    
    /// Validate compose configuration
    Validate,
    
    /// Set environment variable
    Set {
        /// Variable name
        key: String,
        /// Variable value
        value: String,
    },
    
    /// Get environment variable
    Get {
        /// Variable name
        key: String,
    },
    
    /// List all environment variables
    List,
}

#[derive(Subcommand, Clone)]
pub enum EnvironmentCommands {
    /// List available environments
    List,
    
    /// Switch to an environment
    Switch {
        /// Environment name (development, staging, production)
        environment: String,
    },
    
    /// Create a new environment
    Create {
        /// Environment name
        name: String,
        /// Base environment to copy from
        #[arg(short, long)]
        from: Option<String>,
    },
    
    /// Delete an environment
    Delete {
        /// Environment name
        name: String,
    },
    
    /// Show environment details
    Show {
        /// Environment name (defaults to current)
        environment: Option<String>,
    },
}

/// Service scaling specification
#[derive(Clone, Debug)]
pub struct ServiceScale {
    pub service: String,
    pub replicas: u32,
}

/// Parse service scaling specification (service=replicas)
fn parse_service_scale(s: &str) -> Result<ServiceScale, String> {
    let parts: Vec<&str> = s.split('=').collect();
    if parts.len() != 2 {
        return Err("Invalid format. Use: service=replicas".to_string());
    }
    
    let service = parts[0].to_string();
    let replicas = parts[1].parse::<u32>()
        .map_err(|_| "Invalid replica count")?;
    
    Ok(ServiceScale { service, replicas })
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum Shell {
    Bash,
    Zsh,
    Fish,
    PowerShell,
    Elvish,
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum StatusFormat {
    Table,
    Json,
    Yaml,
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum Protocol {
    Vless,
    Shadowsocks,
    Trojan,
    Vmess,
    HttpProxy,
    Socks5Proxy,
    ProxyServer,
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum UserStatus {
    Active,
    Inactive,
    Suspended,
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum OutputFormat {
    Json,
    Table,
    Plain,
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum ExportFormat {
    Json,
    Yaml,
    Csv,
    Clash,
    V2ray,
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum ImportFormat {
    Json,
    Yaml,
    V2ray,
}

impl From<Protocol> for vpn_types::protocol::VpnProtocol {
    fn from(protocol: Protocol) -> Self {
        match protocol {
            Protocol::Vless => vpn_types::protocol::VpnProtocol::Vless,
            Protocol::Shadowsocks => vpn_types::protocol::VpnProtocol::Outline,
            Protocol::Trojan => vpn_types::protocol::VpnProtocol::Vless, // Map to VLESS for now
            Protocol::Vmess => vpn_types::protocol::VpnProtocol::Vless, // Map to VLESS for now
            Protocol::HttpProxy => vpn_types::protocol::VpnProtocol::HttpProxy,
            Protocol::Socks5Proxy => vpn_types::protocol::VpnProtocol::Socks5Proxy,
            Protocol::ProxyServer => vpn_types::protocol::VpnProtocol::ProxyServer,
        }
    }
}

impl From<UserStatus> for vpn_users::user::UserStatus {
    fn from(status: UserStatus) -> Self {
        match status {
            UserStatus::Active => vpn_users::user::UserStatus::Active,
            UserStatus::Inactive => vpn_users::user::UserStatus::Inactive,
            UserStatus::Suspended => vpn_users::user::UserStatus::Suspended,
        }
    }
}

impl OutputFormat {
    pub fn as_str(&self) -> &'static str {
        match self {
            OutputFormat::Json => "json",
            OutputFormat::Table => "table",
            OutputFormat::Plain => "plain",
        }
    }
}

impl From<Shell> for clap_complete::Shell {
    fn from(shell: Shell) -> Self {
        match shell {
            Shell::Bash => clap_complete::Shell::Bash,
            Shell::Zsh => clap_complete::Shell::Zsh,
            Shell::Fish => clap_complete::Shell::Fish,
            Shell::PowerShell => clap_complete::Shell::PowerShell,
            Shell::Elvish => clap_complete::Shell::Elvish,
        }
    }
}