//! Common error types shared across crates

use thiserror::Error;

/// Common result type
pub type Result<T> = std::result::Result<T, CommonError>;

/// Common errors that can occur across VPN crates
#[derive(Error, Debug)]
pub enum CommonError {
    /// I/O error
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// Serialization/deserialization error
    #[error("Serialization error: {0}")]
    Serialization(String),

    /// Configuration error
    #[error("Configuration error: {0}")]
    Configuration(String),

    /// Validation error
    #[error("Validation error: {0}")]
    Validation(String),

    /// Not found error
    #[error("Not found: {0}")]
    NotFound(String),

    /// Permission denied error
    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    /// Timeout error
    #[error("Operation timed out: {0}")]
    Timeout(String),

    /// Network error
    #[error("Network error: {0}")]
    Network(String),

    /// Container runtime error
    #[error("Container runtime error: {0}")]
    ContainerRuntime(String),

    /// Internal error
    #[error("Internal error: {0}")]
    Internal(String),
}

/// Trait for converting errors to common error type
pub trait IntoCommonError {
    fn into_common_error(self) -> CommonError;
}

/// Error context trait for adding context to errors
pub trait ErrorContext<T> {
    fn context(self, msg: &str) -> Result<T>;
    fn with_context<F>(self, f: F) -> Result<T>
    where
        F: FnOnce() -> String;
}

impl<T, E> ErrorContext<T> for std::result::Result<T, E>
where
    E: std::error::Error + 'static,
{
    fn context(self, msg: &str) -> Result<T> {
        self.map_err(|e| CommonError::Internal(format!("{}: {}", msg, e)))
    }

    fn with_context<F>(self, f: F) -> Result<T>
    where
        F: FnOnce() -> String,
    {
        self.map_err(|e| CommonError::Internal(format!("{}: {}", f(), e)))
    }
}