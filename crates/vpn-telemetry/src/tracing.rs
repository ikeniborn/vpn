//! Distributed tracing with structured logging

use crate::{config::TelemetryConfig, error::Result, TelemetryError};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{info, Span};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

/// Trace context for managing distributed traces
#[derive(Debug, Clone)]
pub struct TraceContext {
    pub trace_id: String,
    pub span_id: String,
    pub operation: String,
    pub start_time: std::time::Instant,
    span: Arc<Span>,
}

impl TraceContext {
    /// Create a new trace context
    pub fn new(operation: &str, span: Span) -> Self {
        let trace_id = uuid::Uuid::new_v4().to_string();
        let span_id = uuid::Uuid::new_v4().to_string();

        Self {
            trace_id,
            span_id,
            operation: operation.to_string(),
            start_time: std::time::Instant::now(),
            span: Arc::new(span),
        }
    }

    /// Add an attribute to the current span
    pub fn set_attribute(&self, _key: &str, _value: &str) {
        // Simplified implementation - would be implemented with proper tracing
    }

    /// Add multiple attributes to the current span
    pub fn set_attributes(&self, _attributes: HashMap<String, String>) {
        // Simplified implementation - would be implemented with proper tracing
    }

    /// Add an event to the current span
    pub fn add_event(&self, name: &str, attributes: HashMap<String, String>) {
        tracing::info!(
            event = name,
            trace_id = %self.trace_id,
            span_id = %self.span_id,
            ?attributes,
            "Trace event"
        );
    }

    /// Mark the span as having an error
    pub fn record_error(&self, error: &dyn std::error::Error) {
        tracing::error!(
            error = %error,
            trace_id = %self.trace_id,
            span_id = %self.span_id,
            "Trace error"
        );
    }

    /// Get the elapsed time since the span started
    pub fn elapsed(&self) -> std::time::Duration {
        self.start_time.elapsed()
    }

    /// Finish the span
    pub fn finish(self) {
        info!(
            "Trace completed: {} ({}ms)",
            self.operation,
            self.elapsed().as_millis()
        );
    }
}

/// Tracing manager that handles structured logging setup
pub struct TracingManager {
    config: TelemetryConfig,
    initialized: bool,
}

impl TracingManager {
    /// Create a new tracing manager
    pub async fn new(config: &TelemetryConfig) -> Result<Self> {
        Ok(Self {
            config: config.clone(),
            initialized: false,
        })
    }

    /// Initialize the tracing system
    pub async fn initialize(&mut self) -> Result<()> {
        if self.initialized {
            return Ok(());
        }

        if !self.config.tracing.enabled {
            info!("Tracing is disabled");
            return Ok(());
        }

        // Setup tracing subscriber with structured logging
        self.setup_tracing_subscriber().await?;

        self.initialized = true;
        info!("Tracing system initialized successfully");
        Ok(())
    }

    /// Setup tracing subscriber
    async fn setup_tracing_subscriber(&self) -> Result<()> {
        let env_filter =
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

        Registry::default()
            .with(env_filter)
            .with(tracing_subscriber::fmt::layer().json())
            .try_init()
            .map_err(|e| TelemetryError::TracingError {
                message: format!("Failed to initialize tracing subscriber: {}", e),
            })?;

        Ok(())
    }

    /// Start a new span for an operation
    pub async fn start_span(&self, operation: &str) -> Result<TraceContext> {
        if !self.initialized {
            return Err(TelemetryError::TracingError {
                message: "Tracing system not initialized".to_string(),
            });
        }

        let span = tracing::info_span!("vpn_operation", operation = operation);
        Ok(TraceContext::new(operation, span))
    }

    /// Record an event with structured data
    pub async fn record_event(&self, event: &str, details: Value) -> Result<()> {
        if !self.initialized {
            return Ok(()); // Silently ignore if not initialized
        }

        tracing::info!(
            event = event,
            details = %details,
            "Telemetry event recorded"
        );

        Ok(())
    }

    /// Shutdown the tracing system
    pub async fn shutdown(&mut self) -> Result<()> {
        if !self.initialized {
            return Ok(());
        }

        self.initialized = false;
        info!("Tracing system shutdown");
        Ok(())
    }

    /// Check if tracing is initialized
    pub fn is_initialized(&self) -> bool {
        self.initialized
    }
}

/// Convenience function to create a traced async block
pub async fn traced<F, T>(operation: &str, future: F) -> T
where
    F: std::future::Future<Output = T>,
{
    use tracing::Instrument;

    let span = tracing::info_span!("vpn_operation", operation = operation);
    future.instrument(span).await
}

/// Macro for creating instrumented functions
#[macro_export]
macro_rules! traced_fn {
    (
        $(#[$attr:meta])*
        $vis:vis async fn $name:ident($($param:ident: $param_ty:ty),*) -> $ret:ty $body:block
    ) => {
        $(#[$attr])*
        #[tracing::instrument]
        $vis async fn $name($($param: $param_ty),*) -> $ret $body
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::TelemetryConfig;

    #[tokio::test]
    async fn test_tracing_manager_creation() {
        let config = TelemetryConfig::default();
        let manager = TracingManager::new(&config).await;
        assert!(manager.is_ok());
    }

    #[tokio::test]
    async fn test_trace_context() {
        let span = tracing::info_span!("test_operation");
        let context = TraceContext::new("test_operation", span);

        assert_eq!(context.operation, "test_operation");
        assert!(!context.trace_id.is_empty());
        assert!(!context.span_id.is_empty());

        context.set_attribute("test_key", "test_value");
        context.add_event("test_event", HashMap::new());

        // Test elapsed time
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        assert!(context.elapsed().as_millis() >= 10);
    }

    #[tokio::test]
    async fn test_traced_function() {
        let result = traced("test_operation", async {
            tokio::time::sleep(std::time::Duration::from_millis(1)).await;
            42
        })
        .await;

        assert_eq!(result, 42);
    }
}
