use thiserror::Error;

#[derive(Error, Debug)]
pub enum ServerError {
    #[error("Installation failed: {0}")]
    InstallationError(String),

    #[error("Configuration validation failed: {0}")]
    ValidationError(String),

    #[error("Server lifecycle operation failed: {0}")]
    LifecycleError(String),

    #[error("Key rotation failed: {0}")]
    KeyRotationError(String),

    #[error("Template generation failed: {0}")]
    TemplateError(String),

    #[error("Server not found or not installed")]
    ServerNotFound,

    #[error("Service dependency missing: {0}")]
    DependencyMissing(String),

    #[error("Docker error: {0}")]
    DockerError(#[from] vpn_docker::DockerError),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("VPN network error: {0}")]
    VpnNetworkError(#[from] vpn_network::NetworkError),

    #[error("Crypto error: {0}")]
    CryptoError(#[from] vpn_crypto::CryptoError),

    #[error("User management error: {0}")]
    UserError(#[from] vpn_users::UserError),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("HTTP request failed: {0}")]
    HttpError(#[from] reqwest::Error),
}

pub type Result<T> = std::result::Result<T, ServerError>;
