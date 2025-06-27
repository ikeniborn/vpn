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

    /// Interactive menu mode
    Menu,

    /// Run diagnostics
    Diagnostics {
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
        #[arg(short, long, default_value = "24")]
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
        #[arg(short, long, default_value = "1")]
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

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum Protocol {
    Vless,
    Shadowsocks,
    Trojan,
    Vmess,
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

impl From<Protocol> for vpn_users::user::VpnProtocol {
    fn from(protocol: Protocol) -> Self {
        match protocol {
            Protocol::Vless => vpn_users::user::VpnProtocol::Vless,
            Protocol::Shadowsocks => vpn_users::user::VpnProtocol::Shadowsocks,
            Protocol::Trojan => vpn_users::user::VpnProtocol::Trojan,
            Protocol::Vmess => vpn_users::user::VpnProtocol::Vmess,
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