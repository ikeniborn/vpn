//! Error types for the proxy server

use thiserror::Error;

pub type Result<T> = std::result::Result<T, ProxyError>;

#[derive(Error, Debug)]
pub enum ProxyError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    #[error("Authorization denied: {0}")]
    AuthorizationDenied(String),

    #[error("Rate limit exceeded")]
    RateLimitExceeded,

    #[error("Connection pool exhausted")]
    ConnectionPoolExhausted,

    #[error("Invalid protocol: {0}")]
    InvalidProtocol(String),

    #[error("HTTP error: {0}")]
    Http(String),

    #[error("SOCKS5 error: {0}")]
    Socks5(String),

    #[error("TLS error: {0}")]
    Tls(String),

    #[error("Upstream connection failed: {0}")]
    UpstreamConnectionFailed(String),

    #[error("Invalid request: {0}")]
    InvalidRequest(String),

    #[error("Timeout")]
    Timeout,

    #[error("Service unavailable")]
    ServiceUnavailable,

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("User error: {0}")]
    User(#[from] vpn_users::error::UserError),

    #[error("Network error: {0}")]
    Network(#[from] vpn_network::error::NetworkError),

    #[error("Metrics error: {0}")]
    Metrics(String),

    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl ProxyError {
    pub fn config(msg: impl Into<String>) -> Self {
        Self::Config(msg.into())
    }

    pub fn auth_failed(msg: impl Into<String>) -> Self {
        Self::AuthenticationFailed(msg.into())
    }

    pub fn auth_denied(msg: impl Into<String>) -> Self {
        Self::AuthorizationDenied(msg.into())
    }

    pub fn http(msg: impl Into<String>) -> Self {
        Self::Http(msg.into())
    }

    pub fn socks5(msg: impl Into<String>) -> Self {
        Self::Socks5(msg.into())
    }

    pub fn upstream(msg: impl Into<String>) -> Self {
        Self::UpstreamConnectionFailed(msg.into())
    }

    pub fn invalid_request(msg: impl Into<String>) -> Self {
        Self::InvalidRequest(msg.into())
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        Self::Internal(msg.into())
    }
}

impl From<prometheus::Error> for ProxyError {
    fn from(err: prometheus::Error) -> Self {
        Self::Metrics(err.to_string())
    }
}
