use thiserror::Error;

#[derive(Debug, Error)]
pub enum RuntimeError {
    #[error("Container not found: {id}")]
    ContainerNotFound { id: String },

    #[error("Task not found: {id}")]
    TaskNotFound { id: String },

    #[error("Image not found: {name}")]
    ImageNotFound { name: String },

    #[error("Volume not found: {name}")]
    VolumeNotFound { name: String },

    #[error("Connection error: {message}")]
    ConnectionError { message: String },

    #[error("Runtime operation failed: {operation} - {message}")]
    OperationFailed { operation: String, message: String },

    #[error("Configuration error: {message}")]
    ConfigError { message: String },

    #[error("No runtime available")]
    NoRuntimeAvailable,

    #[error("Timeout occurred: {operation}")]
    Timeout { operation: String },

    #[error("Invalid specification: {message}")]
    InvalidSpec { message: String },

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("Other error: {0}")]
    Other(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, RuntimeError>;
