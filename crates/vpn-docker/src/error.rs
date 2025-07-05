use thiserror::Error;

#[derive(Error, Debug)]
pub enum DockerError {
    #[error("Docker connection failed: {0}")]
    ConnectionError(String),

    #[error("Container not found: {0}")]
    ContainerNotFound(String),

    #[error("Volume operation failed: {0}")]
    VolumeError(String),

    #[error("Health check failed: {0}")]
    HealthCheckFailed(String),

    #[error("Docker API error: {0}")]
    ApiError(#[from] bollard::errors::Error),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, DockerError>;
