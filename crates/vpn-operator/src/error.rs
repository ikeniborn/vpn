//! Error types for the VPN operator

use thiserror::Error;

/// Result type for operator operations
pub type Result<T> = std::result::Result<T, OperatorError>;

/// Operator error types
#[derive(Error, Debug)]
pub enum OperatorError {
    /// Kubernetes API error
    #[error("Kubernetes API error: {0}")]
    KubeError(#[from] kube::Error),

    /// Serialization error
    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    /// YAML error
    #[error("YAML error: {0}")]
    YamlError(#[from] serde_yaml::Error),

    /// Template rendering error
    #[error("Template error: {0}")]
    TemplateError(String),

    /// Resource not found
    #[error("Resource not found: {0}")]
    ResourceNotFound(String),

    /// Invalid resource specification
    #[error("Invalid resource spec: {0}")]
    InvalidSpec(String),

    /// Reconciliation error
    #[error("Reconciliation failed: {0}")]
    ReconciliationError(String),

    /// Webhook validation error
    #[error("Webhook validation failed: {0}")]
    WebhookValidationError(String),

    /// Configuration error
    #[error("Configuration error: {0}")]
    ConfigError(String),

    /// Network error
    #[error("Network error: {0}")]
    NetworkError(String),

    /// Internal error
    #[error("Internal error: {0}")]
    InternalError(String),
}

impl OperatorError {
    /// Create a template error
    pub fn template(msg: impl Into<String>) -> Self {
        Self::TemplateError(msg.into())
    }

    /// Create a reconciliation error
    pub fn reconciliation(msg: impl Into<String>) -> Self {
        Self::ReconciliationError(msg.into())
    }

    /// Create a validation error
    pub fn validation(msg: impl Into<String>) -> Self {
        Self::WebhookValidationError(msg.into())
    }

    /// Create a configuration error
    pub fn config(msg: impl Into<String>) -> Self {
        Self::ConfigError(msg.into())
    }

    /// Create an internal error
    pub fn internal(msg: impl Into<String>) -> Self {
        Self::InternalError(msg.into())
    }
}
