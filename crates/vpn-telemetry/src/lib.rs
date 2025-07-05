//! VPN Telemetry Crate
//!
//! Provides comprehensive observability for the VPN system using OpenTelemetry.
//! Includes distributed tracing, custom metrics, and real-time dashboards.

pub mod config;
pub mod dashboard;
pub mod error;
pub mod exporters;
pub mod health;
pub mod metrics;
pub mod performance;
pub mod tracing;

// Re-export commonly used types
pub use config::TelemetryConfig;
pub use dashboard::{DashboardConfig, DashboardManager};
pub use error::{Result, TelemetryError};
pub use health::{HealthCollector, SystemHealth};
pub use metrics::{MetricsCollector, VpnMetrics};
pub use performance::{PerformanceMetrics, PerformanceMonitor};
pub use tracing::{TraceContext, TracingManager};

use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Main telemetry system that coordinates all observability components
pub struct TelemetrySystem {
    config: TelemetryConfig,
    metrics_collector: Arc<RwLock<MetricsCollector>>,
    tracing_manager: Arc<RwLock<TracingManager>>,
    dashboard_manager: Arc<RwLock<DashboardManager>>,
    health_collector: Arc<RwLock<HealthCollector>>,
    performance_monitor: Arc<RwLock<PerformanceMonitor>>,
    running: Arc<RwLock<bool>>,
}

impl TelemetrySystem {
    /// Create a new telemetry system with the given configuration
    pub async fn new(config: TelemetryConfig) -> Result<Self> {
        let metrics_collector = Arc::new(RwLock::new(MetricsCollector::new(&config).await?));

        let tracing_manager = Arc::new(RwLock::new(TracingManager::new(&config).await?));

        let dashboard_manager = Arc::new(RwLock::new(DashboardManager::new(&config).await?));

        let health_collector = Arc::new(RwLock::new(HealthCollector::new(&config).await?));

        let performance_monitor = Arc::new(RwLock::new(PerformanceMonitor::new(&config).await?));

        Ok(Self {
            config,
            metrics_collector,
            tracing_manager,
            dashboard_manager,
            health_collector,
            performance_monitor,
            running: Arc::new(RwLock::new(false)),
        })
    }

    /// Initialize and start the telemetry system
    pub async fn start(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(()); // Already running
        }

        // Initialize tracing
        {
            let mut tracing_manager = self.tracing_manager.write().await;
            tracing_manager.initialize().await?;
        }

        // Start metrics collection
        {
            let mut metrics_collector = self.metrics_collector.write().await;
            metrics_collector.start().await?;
        }

        // Start health monitoring
        {
            let mut health_collector = self.health_collector.write().await;
            health_collector.start().await?;
        }

        // Start performance monitoring
        {
            let mut performance_monitor = self.performance_monitor.write().await;
            performance_monitor.start().await?;
        }

        // Start dashboard if enabled
        if self.config.dashboard_enabled {
            let mut dashboard_manager = self.dashboard_manager.write().await;
            dashboard_manager.start().await?;
        }

        *running = true;
        println!("Telemetry system started successfully");
        Ok(())
    }

    /// Stop the telemetry system
    pub async fn stop(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(()); // Already stopped
        }

        // Stop dashboard
        {
            let mut dashboard_manager = self.dashboard_manager.write().await;
            dashboard_manager.stop().await?;
        }

        // Stop performance monitoring
        {
            let mut performance_monitor = self.performance_monitor.write().await;
            performance_monitor.stop().await?;
        }

        // Stop health monitoring
        {
            let mut health_collector = self.health_collector.write().await;
            health_collector.stop().await?;
        }

        // Stop metrics collection
        {
            let mut metrics_collector = self.metrics_collector.write().await;
            metrics_collector.stop().await?;
        }

        // Shutdown tracing
        {
            let mut tracing_manager = self.tracing_manager.write().await;
            tracing_manager.shutdown().await?;
        }

        *running = false;
        println!("Telemetry system stopped");
        Ok(())
    }

    /// Check if the telemetry system is running
    pub async fn is_running(&self) -> bool {
        *self.running.read().await
    }

    /// Get current system metrics
    pub async fn get_metrics(&self) -> Result<VpnMetrics> {
        let metrics_collector = self.metrics_collector.read().await;
        metrics_collector.get_current_metrics().await
    }

    /// Get system health status
    pub async fn get_health(&self) -> Result<SystemHealth> {
        let health_collector = self.health_collector.read().await;
        health_collector.get_current_health().await
    }

    /// Get performance metrics
    pub async fn get_performance(&self) -> Result<PerformanceMetrics> {
        let performance_monitor = self.performance_monitor.read().await;
        performance_monitor.get_current_metrics().await
    }

    /// Create a new trace span for an operation
    pub async fn start_span(&self, operation: &str) -> Result<TraceContext> {
        let tracing_manager = self.tracing_manager.read().await;
        tracing_manager.start_span(operation).await
    }

    /// Record a custom metric
    pub async fn record_metric(
        &self,
        name: &str,
        value: f64,
        labels: Vec<(&str, &str)>,
    ) -> Result<()> {
        let mut metrics_collector = self.metrics_collector.write().await;
        metrics_collector.record_metric(name, value, labels).await
    }

    /// Record a custom event
    pub async fn record_event(&self, event: &str, details: serde_json::Value) -> Result<()> {
        let tracing_manager = self.tracing_manager.read().await;
        tracing_manager.record_event(event, details).await
    }

    /// Export metrics to external systems
    pub async fn export_metrics(&self) -> Result<String> {
        let metrics_collector = self.metrics_collector.read().await;
        metrics_collector.export_metrics().await
    }

    /// Get dashboard URL if enabled
    pub async fn get_dashboard_url(&self) -> Option<String> {
        if !self.config.dashboard_enabled {
            return None;
        }

        let dashboard_manager = self.dashboard_manager.read().await;
        dashboard_manager.get_url()
    }
}

/// Trait for components that can provide telemetry data
#[async_trait]
pub trait TelemetryProvider {
    /// Get component-specific metrics
    async fn get_telemetry_metrics(&self) -> Result<serde_json::Value>;

    /// Get component health status
    async fn get_health_status(&self) -> Result<bool>;

    /// Get component name for labeling
    fn component_name(&self) -> &str;
}

/// Global telemetry instance for easy access throughout the application
static TELEMETRY: tokio::sync::OnceCell<Arc<TelemetrySystem>> = tokio::sync::OnceCell::const_new();

/// Initialize the global telemetry system
pub async fn init_telemetry(config: TelemetryConfig) -> Result<()> {
    let telemetry = Arc::new(TelemetrySystem::new(config).await?);
    TELEMETRY
        .set(telemetry.clone())
        .map_err(|_| TelemetryError::InitializationFailed {
            reason: "Telemetry system already initialized".to_string(),
        })?;

    telemetry.start().await?;
    Ok(())
}

/// Get the global telemetry system
pub fn telemetry() -> Option<Arc<TelemetrySystem>> {
    TELEMETRY.get().cloned()
}

/// Shutdown the global telemetry system
pub async fn shutdown_telemetry() -> Result<()> {
    if let Some(telemetry) = TELEMETRY.get() {
        telemetry.stop().await?;
    }
    Ok(())
}

/// Convenience macro for creating instrumented spans
#[macro_export]
macro_rules! traced {
    ($operation:expr, $block:block) => {
        {
            use tracing::{info_span, Instrument};
            async move $block.instrument(info_span!($operation)).await
        }
    };

    ($operation:expr, $($field:tt)*) => {
        {
            use tracing::{info_span, Instrument};
            info_span!($operation, $($field)*)
        }
    };
}

/// Convenience macro for recording metrics
#[macro_export]
macro_rules! record_metric {
    ($name:expr, $value:expr) => {
        if let Some(telemetry) = $crate::telemetry() {
            let _ = telemetry.record_metric($name, $value, vec![]).await;
        }
    };

    ($name:expr, $value:expr, $($label_key:expr => $label_value:expr),*) => {
        if let Some(telemetry) = $crate::telemetry() {
            let labels = vec![$(($label_key, $label_value)),*];
            let _ = telemetry.record_metric($name, $value, labels).await;
        }
    };
}

/// Convenience macro for recording events
#[macro_export]
macro_rules! record_event {
    ($event:expr, $details:expr) => {
        if let Some(telemetry) = $crate::telemetry() {
            let _ = telemetry.record_event($event, $details).await;
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_telemetry_system_creation() {
        let config = TelemetryConfig::default();
        let telemetry = TelemetrySystem::new(config).await;
        assert!(telemetry.is_ok());
    }

    #[tokio::test]
    async fn test_telemetry_system_lifecycle() {
        let config = TelemetryConfig::default();
        let telemetry = TelemetrySystem::new(config).await.unwrap();

        assert!(!telemetry.is_running().await);

        let result = telemetry.start().await;
        assert!(result.is_ok());
        assert!(telemetry.is_running().await);

        let result = telemetry.stop().await;
        assert!(result.is_ok());
        assert!(!telemetry.is_running().await);
    }
}
