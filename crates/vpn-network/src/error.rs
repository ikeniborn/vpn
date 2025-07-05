use thiserror::Error;

#[derive(Error, Debug)]
pub enum NetworkError {
    #[error("Port {0} is already in use")]
    PortInUse(u16),

    #[error("Invalid port number: {0}")]
    InvalidPort(u16),

    #[error("IP detection failed: {0}")]
    IpDetectionError(String),

    #[error("Firewall operation failed: {0}")]
    FirewallError(String),

    #[error("SNI validation failed: {0}")]
    SniValidationError(String),

    #[error("DNS resolution failed: {0}")]
    DnsError(String),

    #[error("Network interface error: {0}")]
    InterfaceError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("HTTP request failed: {0}")]
    HttpError(#[from] reqwest::Error),

    #[error("No available subnets found for VPN")]
    NoAvailableSubnets,

    #[error("Invalid subnet format: {0}")]
    InvalidSubnet(String),

    #[error("Command execution failed: {0}")]
    CommandError(String),
}

pub type Result<T> = std::result::Result<T, NetworkError>;
