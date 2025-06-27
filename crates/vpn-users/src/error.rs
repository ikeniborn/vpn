use thiserror::Error;

#[derive(Error, Debug)]
pub enum UserError {
    #[error("User not found: {0}")]
    UserNotFound(String),
    
    #[error("User already exists: {0}")]
    UserAlreadyExists(String),
    
    #[error("Invalid user configuration: {0}")]
    InvalidConfiguration(String),
    
    #[error("Connection link generation failed: {0}")]
    LinkGenerationError(String),
    
    #[error("Batch operation failed: {0}")]
    BatchOperationError(String),
    
    #[error("User limit exceeded: {0}")]
    UserLimitExceeded(usize),
    
    #[error("Storage error: {0}")]
    StorageError(String),
    
    #[error("Operation not allowed: running in read-only mode")]
    ReadOnlyMode,
    
    #[error("Crypto error: {0}")]
    CryptoError(#[from] vpn_crypto::CryptoError),
    
    #[error("Network error: {0}")]
    NetworkError(#[from] vpn_network::NetworkError),
    
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, UserError>;