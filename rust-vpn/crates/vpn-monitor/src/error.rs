use thiserror::Error;

#[derive(Error, Debug)]
pub enum MonitorError {
    #[error("Traffic monitoring failed: {0}")]
    TrafficMonitoringError(String),
    
    #[error("Health check failed: {0}")]
    HealthCheckError(String),
    
    #[error("Log analysis failed: {0}")]
    LogAnalysisError(String),
    
    #[error("Metrics collection failed: {0}")]
    MetricsError(String),
    
    #[error("Alert processing failed: {0}")]
    AlertError(String),
    
    #[error("Data parsing error: {0}")]
    DataParsingError(String),
    
    #[error("Storage error: {0}")]
    StorageError(String),
    
    #[error("Docker error: {0}")]
    DockerError(#[from] vpn_docker::DockerError),
    
    #[error("User management error: {0}")]
    UserError(#[from] vpn_users::UserError),
    
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
    
    #[error("HTTP request failed: {0}")]
    HttpError(#[from] reqwest::Error),
    
    #[error("Regex error: {0}")]
    RegexError(#[from] regex::Error),
}

pub type Result<T> = std::result::Result<T, MonitorError>;