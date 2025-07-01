use thiserror::Error;
use vpn_runtime::RuntimeError;

#[derive(Debug, Error)]
pub enum ContainerdError {
    #[error("gRPC transport error: {0}")]
    TransportError(#[from] tonic::transport::Error),

    #[error("gRPC status error: {0}")]
    GrpcError(#[from] tonic::Status),

    #[error("Connection error: {message}")]
    ConnectionError { message: String },

    #[error("Container not found: {id}")]
    ContainerNotFound { id: String },

    #[error("Task not found: {id}")]
    TaskNotFound { id: String },

    #[error("Image not found: {reference}")]
    ImageNotFound { reference: String },

    #[error("Snapshot not found: {key}")]
    SnapshotNotFound { key: String },

    #[error("Invalid container spec: {message}")]
    InvalidSpec { message: String },

    #[error("Task operation failed: {operation} - {message}")]
    TaskOperationFailed { operation: String, message: String },

    #[error("Snapshot operation failed: {operation} - {message}")]
    SnapshotOperationFailed { operation: String, message: String },

    #[error("Log collection error: {message}")]
    LogError { message: String },

    #[error("Statistics collection error: {message}")]
    StatsError { message: String },

    #[error("Event streaming error: {message}")]
    EventError { message: String },

    #[error("Event operation failed: {operation} - {message}")]
    EventOperationFailed { operation: String, message: String },

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("JSON serialization error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Timeout: {operation}")]
    Timeout { operation: String },

    #[error("Operation cancelled: {operation}")]
    Cancelled { operation: String },

    #[error("Configuration error: {message}")]
    ConfigError { message: String },

    #[error("Operation not supported: {operation} - {reason}")]
    OperationNotSupported { operation: String, reason: String },

    #[error("Operation failed: {operation} - {message}")]
    OperationFailed { operation: String, message: String },

    #[error("Runtime error: {0}")]
    RuntimeError(#[from] RuntimeError),

    #[error("Other error: {0}")]
    Other(#[from] anyhow::Error),
}

impl From<ContainerdError> for RuntimeError {
    fn from(err: ContainerdError) -> Self {
        match err {
            ContainerdError::ContainerNotFound { id } => RuntimeError::ContainerNotFound { id },
            ContainerdError::TaskNotFound { id } => RuntimeError::TaskNotFound { id },
            ContainerdError::ImageNotFound { reference } => RuntimeError::ImageNotFound { name: reference },
            ContainerdError::ConnectionError { message } => RuntimeError::ConnectionError { message },
            ContainerdError::TransportError(e) => RuntimeError::ConnectionError { 
                message: format!("Transport error: {}", e) 
            },
            ContainerdError::GrpcError(status) => RuntimeError::OperationFailed { 
                operation: "gRPC call".to_string(), 
                message: status.to_string() 
            },
            ContainerdError::InvalidSpec { message } => RuntimeError::InvalidSpec { message },
            ContainerdError::Timeout { operation } => RuntimeError::Timeout { operation },
            ContainerdError::ConfigError { message } => RuntimeError::ConfigError { message },
            ContainerdError::OperationNotSupported { operation, reason } => RuntimeError::OperationFailed { 
                operation, 
                message: format!("Operation not supported: {}", reason) 
            },
            ContainerdError::IoError(e) => RuntimeError::IoError(e),
            ContainerdError::JsonError(e) => RuntimeError::SerializationError(e),
            ContainerdError::RuntimeError(e) => e,
            ContainerdError::Other(e) => RuntimeError::Other(e),
            _ => RuntimeError::OperationFailed {
                operation: "containerd operation".to_string(),
                message: err.to_string(),
            },
        }
    }
}

pub type Result<T> = std::result::Result<T, ContainerdError>;