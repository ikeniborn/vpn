//! Error types for VPN Compose orchestration

use thiserror::Error;

pub type Result<T> = std::result::Result<T, ComposeError>;

/// Errors that can occur in the Docker Compose orchestration system
#[derive(Error, Debug)]
pub enum ComposeError {
    #[error("Template error: {message}")]
    TemplateError {
        message: String,
    },

    #[error("Configuration error: {message}")]
    ConfigError {
        message: String,
    },

    #[error("Docker Compose command failed: {command} - {stderr}")]
    ComposeCommandFailed {
        command: String,
        stderr: String,
    },

    #[error("Service not found: {service}")]
    ServiceNotFound {
        service: String,
    },

    #[error("Environment error: {message}")]
    EnvironmentError {
        message: String,
    },

    #[error("File operation failed: {operation} - {path}")]
    FileOperationFailed {
        operation: String,
        path: String,
    },

    #[error("Validation failed: {message}")]
    ValidationFailed {
        message: String,
    },

    #[error("Service dependency error: {service} depends on {dependency}")]
    DependencyError {
        service: String,
        dependency: String,
    },

    #[error("Network configuration error: {message}")]
    NetworkError {
        message: String,
    },

    #[error("Volume configuration error: {message}")]
    VolumeError {
        message: String,
    },

    #[error("Generation failed: {message}")]
    GenerationFailed {
        message: String,
    },

    #[error("Manager initialization failed: {message}")]
    ManagerInitFailed {
        message: String,
    },

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("YAML error: {0}")]
    Yaml(#[from] serde_yaml::Error),

    #[error("Template engine error: {0}")]
    Tera(#[from] tera::Error),

    #[error("Handlebars error: {0}")]
    Handlebars(#[from] handlebars::RenderError),

    #[error("VPN users error: {0}")]
    VpnUsers(#[from] vpn_users::error::UserError),

    #[error("VPN docker error: {0}")]
    VpnDocker(#[from] vpn_docker::error::DockerError),

    #[error("VPN server error: {0}")]
    VpnServer(#[from] vpn_server::error::ServerError),

    #[error("VPN network error: {0}")]
    VpnNetwork(#[from] vpn_network::error::NetworkError),
}

impl ComposeError {
    /// Create a template error
    pub fn template_error(message: impl Into<String>) -> Self {
        Self::TemplateError {
            message: message.into(),
        }
    }

    /// Create a configuration error
    pub fn config_error(message: impl Into<String>) -> Self {
        Self::ConfigError {
            message: message.into(),
        }
    }

    /// Create a compose command error
    pub fn compose_command_failed(command: impl Into<String>, stderr: impl Into<String>) -> Self {
        Self::ComposeCommandFailed {
            command: command.into(),
            stderr: stderr.into(),
        }
    }

    /// Create a service not found error
    pub fn service_not_found(service: impl Into<String>) -> Self {
        Self::ServiceNotFound {
            service: service.into(),
        }
    }

    /// Create an environment error
    pub fn environment_error(message: impl Into<String>) -> Self {
        Self::EnvironmentError {
            message: message.into(),
        }
    }

    /// Create a file operation error
    pub fn file_operation_failed(operation: impl Into<String>, path: impl Into<String>) -> Self {
        Self::FileOperationFailed {
            operation: operation.into(),
            path: path.into(),
        }
    }

    /// Create a validation error
    pub fn validation_failed(message: impl Into<String>) -> Self {
        Self::ValidationFailed {
            message: message.into(),
        }
    }

    /// Create a dependency error
    pub fn dependency_error(service: impl Into<String>, dependency: impl Into<String>) -> Self {
        Self::DependencyError {
            service: service.into(),
            dependency: dependency.into(),
        }
    }

    /// Create a network error
    pub fn network_error(message: impl Into<String>) -> Self {
        Self::NetworkError {
            message: message.into(),
        }
    }

    /// Create a volume error
    pub fn volume_error(message: impl Into<String>) -> Self {
        Self::VolumeError {
            message: message.into(),
        }
    }

    /// Create a generation error
    pub fn generation_failed(message: impl Into<String>) -> Self {
        Self::GenerationFailed {
            message: message.into(),
        }
    }

    /// Create a manager initialization error
    pub fn manager_init_failed(message: impl Into<String>) -> Self {
        Self::ManagerInitFailed {
            message: message.into(),
        }
    }
}