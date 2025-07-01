//! Telemetry data exporters for various backends

use crate::{error::Result, TelemetryError};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;
use tracing::{debug, info, warn};

/// Trait for telemetry data exporters
#[async_trait]
pub trait TelemetryExporter {
    /// Export telemetry data to the backend
    async fn export(&self, data: ExportData) -> Result<()>;
    
    /// Get exporter name
    fn name(&self) -> &str;
    
    /// Check if the exporter is healthy
    async fn health_check(&self) -> Result<bool>;
    
    /// Get exporter configuration
    fn config(&self) -> &ExporterConfig;
}

/// Configuration for exporters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExporterConfig {
    pub name: String,
    pub enabled: bool,
    pub endpoint: String,
    pub timeout: Duration,
    pub retry_count: u32,
    pub batch_size: usize,
    pub flush_interval: Duration,
    pub headers: HashMap<String, String>,
    pub authentication: Option<AuthenticationConfig>,
}

/// Authentication configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthenticationConfig {
    pub auth_type: AuthenticationType,
    pub username: Option<String>,
    pub password: Option<String>,
    pub token: Option<String>,
    pub api_key: Option<String>,
}

/// Authentication types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AuthenticationType {
    None,
    Basic,
    Bearer,
    ApiKey,
}

/// Data to be exported
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportData {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub data_type: DataType,
    pub metrics: Option<serde_json::Value>,
    pub traces: Option<Vec<TraceData>>,
    pub logs: Option<Vec<LogData>>,
    pub events: Option<Vec<EventData>>,
}

/// Data types for export
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DataType {
    Metrics,
    Traces,
    Logs,
    Events,
    Mixed,
}

/// Trace data for export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceData {
    pub trace_id: String,
    pub span_id: String,
    pub parent_span_id: Option<String>,
    pub operation_name: String,
    pub start_time: chrono::DateTime<chrono::Utc>,
    pub end_time: chrono::DateTime<chrono::Utc>,
    pub duration_ms: u64,
    pub status: TraceStatus,
    pub tags: HashMap<String, String>,
    pub logs: Vec<String>,
}

/// Trace status
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TraceStatus {
    Ok,
    Error,
    Timeout,
}

/// Log data for export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogData {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub level: LogLevel,
    pub message: String,
    pub source: String,
    pub fields: HashMap<String, serde_json::Value>,
}

/// Log levels
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

/// Event data for export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventData {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub event_type: String,
    pub source: String,
    pub data: serde_json::Value,
    pub metadata: HashMap<String, String>,
}

/// Prometheus exporter
pub struct PrometheusExporter {
    config: ExporterConfig,
    client: reqwest::Client,
}

impl PrometheusExporter {
    /// Create a new Prometheus exporter
    pub fn new(config: ExporterConfig) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(config.timeout)
            .build()
            .map_err(|e| TelemetryError::ExportError {
                exporter: config.name.clone(),
                message: format!("Failed to create HTTP client: {}", e),
            })?;

        Ok(Self { config, client })
    }

    /// Format metrics for Prometheus
    fn format_prometheus_metrics(&self, metrics: &serde_json::Value) -> Result<String> {
        let mut output = String::new();

        fn format_value(
            key: &str,
            value: &serde_json::Value,
            prefix: &str,
            output: &mut String,
        ) {
            match value {
                serde_json::Value::Number(n) => {
                    if let Some(f) = n.as_f64() {
                        let metric_name = if prefix.is_empty() {
                            key.to_string()
                        } else {
                            format!("{}_{}", prefix, key)
                        };
                        output.push_str(&format!("{} {}\n", metric_name, f));
                    }
                }
                serde_json::Value::Object(obj) => {
                    let new_prefix = if prefix.is_empty() {
                        key.to_string()
                    } else {
                        format!("{}_{}", prefix, key)
                    };
                    for (k, v) in obj {
                        format_value(k, v, &new_prefix, output);
                    }
                }
                _ => {}
            }
        }

        if let serde_json::Value::Object(obj) = metrics {
            for (key, value) in obj {
                format_value(key, value, "", &mut output);
            }
        }

        Ok(output)
    }
}

#[async_trait]
impl TelemetryExporter for PrometheusExporter {
    async fn export(&self, data: ExportData) -> Result<()> {
        if let Some(metrics) = &data.metrics {
            let prometheus_format = self.format_prometheus_metrics(metrics)?;
            
            let mut request = self.client.post(&self.config.endpoint);
            
            // Add custom headers
            for (key, value) in &self.config.headers {
                request = request.header(key, value);
            }
            
            // Add authentication if configured
            if let Some(auth) = &self.config.authentication {
                match &auth.auth_type {
                    AuthenticationType::Basic => {
                        if let (Some(username), Some(password)) = (&auth.username, &auth.password) {
                            request = request.basic_auth(username, Some(password));
                        }
                    }
                    AuthenticationType::Bearer => {
                        if let Some(token) = &auth.token {
                            request = request.bearer_auth(token);
                        }
                    }
                    AuthenticationType::ApiKey => {
                        if let Some(api_key) = &auth.api_key {
                            request = request.header("X-API-Key", api_key);
                        }
                    }
                    AuthenticationType::None => {}
                }
            }

            let response = request
                .body(prometheus_format)
                .send()
                .await
                .map_err(|e| TelemetryError::ExportError {
                    exporter: self.config.name.clone(),
                    message: format!("HTTP request failed: {}", e),
                })?;

            if !response.status().is_success() {
                return Err(TelemetryError::ExportError {
                    exporter: self.config.name.clone(),
                    message: format!("HTTP error: {}", response.status()),
                });
            }

            debug!("Successfully exported metrics to Prometheus");
        }

        Ok(())
    }

    fn name(&self) -> &str {
        &self.config.name
    }

    async fn health_check(&self) -> Result<bool> {
        match self.client.get(&self.config.endpoint).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    fn config(&self) -> &ExporterConfig {
        &self.config
    }
}

/// Jaeger exporter
pub struct JaegerExporter {
    config: ExporterConfig,
    client: reqwest::Client,
}

impl JaegerExporter {
    /// Create a new Jaeger exporter
    pub fn new(config: ExporterConfig) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(config.timeout)
            .build()
            .map_err(|e| TelemetryError::ExportError {
                exporter: config.name.clone(),
                message: format!("Failed to create HTTP client: {}", e),
            })?;

        Ok(Self { config, client })
    }

    /// Format traces for Jaeger
    fn format_jaeger_traces(&self, traces: &[TraceData]) -> Result<serde_json::Value> {
        let jaeger_spans: Vec<serde_json::Value> = traces
            .iter()
            .map(|trace| {
                serde_json::json!({
                    "traceID": trace.trace_id,
                    "spanID": trace.span_id,
                    "parentSpanID": trace.parent_span_id,
                    "operationName": trace.operation_name,
                    "startTime": trace.start_time.timestamp_micros(),
                    "duration": trace.duration_ms * 1000, // Convert to microseconds
                    "tags": trace.tags.iter().map(|(k, v)| {
                        serde_json::json!({
                            "key": k,
                            "value": v,
                            "type": "string"
                        })
                    }).collect::<Vec<_>>(),
                    "process": {
                        "serviceName": "vpn-system",
                        "tags": []
                    }
                })
            })
            .collect();

        Ok(serde_json::json!({
            "data": [{
                "traceID": traces.first().map(|t| &t.trace_id).unwrap_or(&"".to_string()),
                "spans": jaeger_spans
            }]
        }))
    }
}

#[async_trait]
impl TelemetryExporter for JaegerExporter {
    async fn export(&self, data: ExportData) -> Result<()> {
        if let Some(traces) = &data.traces {
            let jaeger_format = self.format_jaeger_traces(traces)?;
            
            let mut request = self.client.post(&self.config.endpoint);
            
            // Add custom headers
            for (key, value) in &self.config.headers {
                request = request.header(key, value);
            }
            
            // Add authentication if configured
            if let Some(auth) = &self.config.authentication {
                match &auth.auth_type {
                    AuthenticationType::Basic => {
                        if let (Some(username), Some(password)) = (&auth.username, &auth.password) {
                            request = request.basic_auth(username, Some(password));
                        }
                    }
                    AuthenticationType::Bearer => {
                        if let Some(token) = &auth.token {
                            request = request.bearer_auth(token);
                        }
                    }
                    AuthenticationType::ApiKey => {
                        if let Some(api_key) = &auth.api_key {
                            request = request.header("X-API-Key", api_key);
                        }
                    }
                    AuthenticationType::None => {}
                }
            }

            let response = request
                .json(&jaeger_format)
                .send()
                .await
                .map_err(|e| TelemetryError::ExportError {
                    exporter: self.config.name.clone(),
                    message: format!("HTTP request failed: {}", e),
                })?;

            if !response.status().is_success() {
                return Err(TelemetryError::ExportError {
                    exporter: self.config.name.clone(),
                    message: format!("HTTP error: {}", response.status()),
                });
            }

            debug!("Successfully exported traces to Jaeger");
        }

        Ok(())
    }

    fn name(&self) -> &str {
        &self.config.name
    }

    async fn health_check(&self) -> Result<bool> {
        match self.client.get(&self.config.endpoint).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    fn config(&self) -> &ExporterConfig {
        &self.config
    }
}

/// Generic HTTP exporter for custom backends
pub struct HttpExporter {
    config: ExporterConfig,
    client: reqwest::Client,
}

impl HttpExporter {
    /// Create a new HTTP exporter
    pub fn new(config: ExporterConfig) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(config.timeout)
            .build()
            .map_err(|e| TelemetryError::ExportError {
                exporter: config.name.clone(),
                message: format!("Failed to create HTTP client: {}", e),
            })?;

        Ok(Self { config, client })
    }
}

#[async_trait]
impl TelemetryExporter for HttpExporter {
    async fn export(&self, data: ExportData) -> Result<()> {
        let mut request = self.client.post(&self.config.endpoint);
        
        // Add custom headers
        for (key, value) in &self.config.headers {
            request = request.header(key, value);
        }
        
        // Add authentication if configured
        if let Some(auth) = &self.config.authentication {
            match &auth.auth_type {
                AuthenticationType::Basic => {
                    if let (Some(username), Some(password)) = (&auth.username, &auth.password) {
                        request = request.basic_auth(username, Some(password));
                    }
                }
                AuthenticationType::Bearer => {
                    if let Some(token) = &auth.token {
                        request = request.bearer_auth(token);
                    }
                }
                AuthenticationType::ApiKey => {
                    if let Some(api_key) = &auth.api_key {
                        request = request.header("X-API-Key", api_key);
                    }
                }
                AuthenticationType::None => {}
            }
        }

        let response = request
            .json(&data)
            .send()
            .await
            .map_err(|e| TelemetryError::ExportError {
                exporter: self.config.name.clone(),
                message: format!("HTTP request failed: {}", e),
            })?;

        if !response.status().is_success() {
            return Err(TelemetryError::ExportError {
                exporter: self.config.name.clone(),
                message: format!("HTTP error: {}", response.status()),
            });
        }

        debug!("Successfully exported data via HTTP");
        Ok(())
    }

    fn name(&self) -> &str {
        &self.config.name
    }

    async fn health_check(&self) -> Result<bool> {
        match self.client.get(&self.config.endpoint).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    fn config(&self) -> &ExporterConfig {
        &self.config
    }
}

/// Exporter manager that coordinates multiple exporters
pub struct ExporterManager {
    exporters: Vec<Box<dyn TelemetryExporter + Send + Sync>>,
}

impl ExporterManager {
    /// Create a new exporter manager
    pub fn new() -> Self {
        Self {
            exporters: Vec::new(),
        }
    }

    /// Add an exporter
    pub fn add_exporter(&mut self, exporter: Box<dyn TelemetryExporter + Send + Sync>) {
        info!("Added telemetry exporter: {}", exporter.name());
        self.exporters.push(exporter);
    }

    /// Export data to all configured exporters
    pub async fn export_to_all(&self, data: ExportData) -> Result<()> {
        let mut errors = Vec::new();

        for exporter in &self.exporters {
            if exporter.config().enabled {
                match exporter.export(data.clone()).await {
                    Ok(()) => {
                        debug!("Successfully exported to {}", exporter.name());
                    }
                    Err(e) => {
                        warn!("Failed to export to {}: {}", exporter.name(), e);
                        errors.push(format!("{}: {}", exporter.name(), e));
                    }
                }
            }
        }

        if !errors.is_empty() && errors.len() == self.exporters.len() {
            return Err(TelemetryError::ExportError {
                exporter: "all".to_string(),
                message: format!("All exporters failed: {}", errors.join(", ")),
            });
        }

        Ok(())
    }

    /// Check health of all exporters
    pub async fn check_exporter_health(&self) -> HashMap<String, bool> {
        let mut health_status = HashMap::new();

        for exporter in &self.exporters {
            let is_healthy = exporter.health_check().await.unwrap_or(false);
            health_status.insert(exporter.name().to_string(), is_healthy);
        }

        health_status
    }

    /// Get list of configured exporters
    pub fn list_exporters(&self) -> Vec<&str> {
        self.exporters.iter().map(|e| e.name()).collect()
    }
}

impl Default for ExporterManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exporter_config_creation() {
        let config = ExporterConfig {
            name: "test_exporter".to_string(),
            enabled: true,
            endpoint: "http://localhost:9090".to_string(),
            timeout: Duration::from_secs(30),
            retry_count: 3,
            batch_size: 100,
            flush_interval: Duration::from_secs(60),
            headers: HashMap::new(),
            authentication: None,
        };

        assert_eq!(config.name, "test_exporter");
        assert!(config.enabled);
        assert_eq!(config.endpoint, "http://localhost:9090");
    }

    #[test]
    fn test_export_data_creation() {
        let data = ExportData {
            timestamp: chrono::Utc::now(),
            source: "test".to_string(),
            data_type: DataType::Metrics,
            metrics: Some(serde_json::json!({"cpu_usage": 50.0})),
            traces: None,
            logs: None,
            events: None,
        };

        assert_eq!(data.source, "test");
        assert!(matches!(data.data_type, DataType::Metrics));
        assert!(data.metrics.is_some());
    }

    #[tokio::test]
    async fn test_exporter_manager() {
        let mut manager = ExporterManager::new();
        assert_eq!(manager.list_exporters().len(), 0);

        // In a real test, you would add actual exporters
        // For this test, we just verify the manager can be created
        assert_eq!(manager.exporters.len(), 0);
    }
}