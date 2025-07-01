//! Error types for the telemetry system

use thiserror::Error;

/// Result type for telemetry operations
pub type Result<T> = std::result::Result<T, TelemetryError>;

/// Errors that can occur in the telemetry system
#[derive(Error, Debug)]
pub enum TelemetryError {
    /// Configuration errors
    #[error("Configuration error: {message}")]
    ConfigError { message: String },

    /// Initialization errors
    #[error("Initialization failed: {reason}")]
    InitializationFailed { reason: String },

    /// Tracing errors
    #[error("Tracing error: {message}")]
    TracingError { message: String },

    /// Metrics errors
    #[error("Metrics error: {message}")]
    MetricsError { message: String },

    /// Dashboard errors
    #[error("Dashboard error: {message}")]
    DashboardError { message: String },

    /// Export errors
    #[error("Export failed for {exporter}: {message}")]
    ExportError { exporter: String, message: String },

    /// Network errors
    #[error("Network error: {message}")]
    NetworkError { message: String },

    /// I/O errors
    #[error("I/O error: {message}")]
    IoError { message: String },

    /// Serialization errors
    #[error("Serialization error: {message}")]
    SerializationError { message: String },

    /// Health check errors
    #[error("Health check failed for {component}: {message}")]
    HealthCheckError { component: String, message: String },

    /// Performance monitoring errors
    #[error("Performance monitoring error: {message}")]
    PerformanceError { message: String },

    /// Resource not found
    #[error("Resource not found: {resource}")]
    NotFound { resource: String },

    /// Permission denied
    #[error("Permission denied: {operation}")]
    PermissionDenied { operation: String },

    /// Timeout errors
    #[error("Operation timed out: {operation}")]
    Timeout { operation: String },

    /// Generic operation failed
    #[error("Operation failed: {operation} - {message}")]
    OperationFailed { operation: String, message: String },
}

impl From<std::io::Error> for TelemetryError {
    fn from(error: std::io::Error) -> Self {
        TelemetryError::IoError {
            message: error.to_string(),
        }
    }
}

impl From<serde_json::Error> for TelemetryError {
    fn from(error: serde_json::Error) -> Self {
        TelemetryError::SerializationError {
            message: error.to_string(),
        }
    }
}

impl From<toml::de::Error> for TelemetryError {
    fn from(error: toml::de::Error) -> Self {
        TelemetryError::ConfigError {
            message: error.to_string(),
        }
    }
}

impl From<toml::ser::Error> for TelemetryError {
    fn from(error: toml::ser::Error) -> Self {
        TelemetryError::ConfigError {
            message: error.to_string(),
        }
    }
}

impl From<reqwest::Error> for TelemetryError {
    fn from(error: reqwest::Error) -> Self {
        TelemetryError::NetworkError {
            message: error.to_string(),
        }
    }
}

impl From<tokio::time::error::Elapsed> for TelemetryError {
    fn from(error: tokio::time::error::Elapsed) -> Self {
        TelemetryError::Timeout {
            operation: error.to_string(),
        }
    }
}

/// Helper macro for creating telemetry errors
#[macro_export]
macro_rules! telemetry_error {
    (config, $msg:expr) => {
        $crate::TelemetryError::ConfigError {
            message: $msg.to_string(),
        }
    };
    
    (init, $reason:expr) => {
        $crate::TelemetryError::InitializationFailed {
            reason: $reason.to_string(),
        }
    };
    
    (tracing, $msg:expr) => {
        $crate::TelemetryError::TracingError {
            message: $msg.to_string(),
        }
    };
    
    (metrics, $msg:expr) => {
        $crate::TelemetryError::MetricsError {
            message: $msg.to_string(),
        }
    };
    
    (dashboard, $msg:expr) => {
        $crate::TelemetryError::DashboardError {
            message: $msg.to_string(),
        }
    };
    
    (export, $exporter:expr, $msg:expr) => {
        $crate::TelemetryError::ExportError {
            exporter: $exporter.to_string(),
            message: $msg.to_string(),
        }
    };
    
    (health, $component:expr, $msg:expr) => {
        $crate::TelemetryError::HealthCheckError {
            component: $component.to_string(),
            message: $msg.to_string(),
        }
    };
    
    (performance, $msg:expr) => {
        $crate::TelemetryError::PerformanceError {
            message: $msg.to_string(),
        }
    };
    
    (not_found, $resource:expr) => {
        $crate::TelemetryError::NotFound {
            resource: $resource.to_string(),
        }
    };
    
    (permission_denied, $operation:expr) => {
        $crate::TelemetryError::PermissionDenied {
            operation: $operation.to_string(),
        }
    };
    
    (timeout, $operation:expr) => {
        $crate::TelemetryError::Timeout {
            operation: $operation.to_string(),
        }
    };
    
    (operation_failed, $operation:expr, $msg:expr) => {
        $crate::TelemetryError::OperationFailed {
            operation: $operation.to_string(),
            message: $msg.to_string(),
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let error = TelemetryError::ConfigError {
            message: "test error".to_string(),
        };
        assert!(error.to_string().contains("test error"));
    }

    #[test]
    fn test_error_macro() {
        let error = telemetry_error!(config, "test message");
        match error {
            TelemetryError::ConfigError { message } => {
                assert_eq!(message, "test message");
            }
            _ => panic!("Wrong error type"),
        }
    }

    #[test]
    fn test_error_conversions() {
        let io_error = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let telemetry_error: TelemetryError = io_error.into();
        
        match telemetry_error {
            TelemetryError::IoError { message } => {
                assert!(message.contains("file not found"));
            }
            _ => panic!("Wrong error type"),
        }
    }
}