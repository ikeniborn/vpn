use thiserror::Error;

#[derive(Error, Debug)]
pub enum CliError {
    #[error("Command execution failed: {0}")]
    CommandError(String),
    
    #[error("Menu operation failed: {0}")]
    MenuError(String),
    
    #[error("Configuration error: {0}")]
    ConfigError(String),
    
    #[error("Migration error: {0}")]
    MigrationError(String),
    
    #[error("Validation error: {0}")]
    ValidationError(String),
    
    #[error("User input error: {0}")]
    InputError(String),
    
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    
    #[error("Runtime error: {0}")]
    RuntimeError(String),
    
    #[error("Feature deprecated: {0}")]
    FeatureDeprecated(String),
    
    #[error("Permission denied: {0}")]
    PermissionError(String),
    
    #[error("File operation failed: {0}")]
    FileOperation(String),
    
    #[error("Server error: {0}")]
    ServerError(#[from] vpn_server::ServerError),
    
    #[error("User management error: {0}")]
    UserError(#[from] vpn_users::UserError),
    
    #[error("Monitor error: {0}")]
    MonitorError(#[from] vpn_monitor::MonitorError),
    
    #[error("Docker error: {0}")]
    DockerError(#[from] vpn_docker::DockerError),
    
    #[error("Network error: {0}")]
    NetworkError(#[from] vpn_network::NetworkError),
    
    #[error("Crypto error: {0}")]
    CryptoError(#[from] vpn_crypto::CryptoError),
    
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
    
    #[error("Dialog error: {0}")]
    DialogError(#[from] dialoguer::Error),
    
    #[error("Anyhow error: {0}")]
    AnyhowError(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, CliError>;