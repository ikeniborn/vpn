//! Prometheus metrics for proxy server

use crate::error::Result;
use prometheus::{
    register_counter, register_counter_vec, register_gauge_vec, register_histogram_vec,
    Counter, CounterVec, GaugeVec, HistogramVec,
    Registry, TextEncoder, Encoder,
};
use std::sync::Arc;
use tracing::info;

/// Proxy server metrics
#[derive(Clone)]
pub struct ProxyMetrics {
    /// Total number of connections
    pub connections_total: CounterVec,
    
    /// Active connections
    pub connections_active: GaugeVec,
    
    /// Authentication attempts
    pub auth_attempts_total: CounterVec,
    
    /// Bytes transferred
    pub bytes_transferred_total: CounterVec,
    
    /// Request duration histogram
    pub request_duration_seconds: HistogramVec,
    
    /// Rate limit hits
    pub rate_limit_hits_total: Counter,
    
    /// Connection pool stats
    pub connection_pool_size: GaugeVec,
    pub connection_pool_hits: Counter,
    pub connection_pool_misses: Counter,
    
    /// Registry
    registry: Registry,
}

impl ProxyMetrics {
    /// Create new metrics instance
    pub fn new() -> Result<Self> {
        let registry = Registry::new();
        
        let connections_total = register_counter_vec!(
            "proxy_connections_total",
            "Total number of proxy connections",
            &["protocol", "status"]
        )?;
        
        let connections_active = register_gauge_vec!(
            "proxy_connections_active",
            "Number of active proxy connections",
            &["protocol"]
        )?;
        
        let auth_attempts_total = register_counter_vec!(
            "proxy_auth_attempts_total",
            "Total number of authentication attempts",
            &["result"]
        )?;
        
        let bytes_transferred_total = register_counter_vec!(
            "proxy_bytes_transferred_total",
            "Total bytes transferred through proxy",
            &["direction", "protocol"]
        )?;
        
        let request_duration_seconds = register_histogram_vec!(
            "proxy_request_duration_seconds",
            "Request duration in seconds",
            &["protocol", "method"],
            vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0]
        )?;
        
        let rate_limit_hits_total = register_counter!(
            "proxy_rate_limit_hits_total",
            "Total number of rate limit hits"
        )?;
        
        let connection_pool_size = register_gauge_vec!(
            "proxy_connection_pool_size",
            "Size of connection pool",
            &["state"]
        )?;
        
        let connection_pool_hits = register_counter!(
            "proxy_connection_pool_hits_total",
            "Total connection pool hits"
        )?;
        
        let connection_pool_misses = register_counter!(
            "proxy_connection_pool_misses_total",
            "Total connection pool misses"
        )?;
        
        // Register all metrics
        registry.register(Box::new(connections_total.clone()))?;
        registry.register(Box::new(connections_active.clone()))?;
        registry.register(Box::new(auth_attempts_total.clone()))?;
        registry.register(Box::new(bytes_transferred_total.clone()))?;
        registry.register(Box::new(request_duration_seconds.clone()))?;
        registry.register(Box::new(rate_limit_hits_total.clone()))?;
        registry.register(Box::new(connection_pool_size.clone()))?;
        registry.register(Box::new(connection_pool_hits.clone()))?;
        registry.register(Box::new(connection_pool_misses.clone()))?;
        
        info!("Proxy metrics initialized");
        
        Ok(Self {
            connections_total,
            connections_active,
            auth_attempts_total,
            bytes_transferred_total,
            request_duration_seconds,
            rate_limit_hits_total,
            connection_pool_size,
            connection_pool_hits,
            connection_pool_misses,
            registry,
        })
    }
    
    /// Record a new connection
    pub fn record_connection(&self, protocol: &str, success: bool) {
        let status = if success { "success" } else { "failed" };
        self.connections_total
            .with_label_values(&[protocol, status])
            .inc();
            
        if success {
            self.connections_active
                .with_label_values(&[protocol])
                .inc();
        }
    }
    
    /// Record connection closed
    pub fn record_connection_closed(&self, protocol: &str) {
        self.connections_active
            .with_label_values(&[protocol])
            .dec();
    }
    
    /// Record authentication success
    pub fn record_auth_success(&self) {
        self.auth_attempts_total
            .with_label_values(&["success"])
            .inc();
    }
    
    /// Record authentication failure
    pub fn record_auth_failure(&self) {
        self.auth_attempts_total
            .with_label_values(&["failure"])
            .inc();
    }
    
    /// Record bytes transferred
    pub fn record_bytes_transferred(&self, bytes: u64, direction: &str) {
        self.bytes_transferred_total
            .with_label_values(&[direction, "proxy"])
            .inc_by(bytes as f64);
    }
    
    /// Record request duration
    pub fn record_request_duration(&self, protocol: &str, method: &str, duration: f64) {
        self.request_duration_seconds
            .with_label_values(&[protocol, method])
            .observe(duration);
    }
    
    /// Record rate limit exceeded
    pub fn record_rate_limit_exceeded(&self) {
        self.rate_limit_hits_total.inc();
    }
    
    /// Update connection pool stats
    pub fn update_connection_pool_stats(&self, total: usize, active: usize) {
        self.connection_pool_size
            .with_label_values(&["total"])
            .set(total as f64);
            
        self.connection_pool_size
            .with_label_values(&["active"])
            .set(active as f64);
            
        self.connection_pool_size
            .with_label_values(&["idle"])
            .set((total - active) as f64);
    }
    
    /// Record connection pool hit
    pub fn record_pool_hit(&self) {
        self.connection_pool_hits.inc();
    }
    
    /// Record connection pool miss
    pub fn record_pool_miss(&self) {
        self.connection_pool_misses.inc();
    }
    
    /// Export metrics in Prometheus format
    pub fn export(&self) -> Result<String> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();
        let mut buffer = Vec::new();
        encoder.encode(&metric_families, &mut buffer)?;
        String::from_utf8(buffer)
            .map_err(|e| crate::ProxyError::internal(format!("Failed to encode metrics: {}", e)))
    }
    
    /// Flush any pending metrics
    pub fn flush(&self) {
        // Prometheus metrics are exported on demand, so nothing to flush
        info!("Metrics flushed");
    }
}

/// Start metrics HTTP server
pub async fn start_metrics_server(
    metrics: ProxyMetrics,
    bind_address: &str,
    path: &str,
) -> Result<()> {
    use axum::{Router, routing::get};
    
    let metrics = Arc::new(metrics);
    let path = format!("/{}", path.trim_start_matches('/'));
    
    let app = Router::new()
        .route(&path, get({
            let metrics = metrics.clone();
            move || serve_metrics(metrics.clone())
        }));
    
    let addr: std::net::SocketAddr = bind_address.parse()
        .map_err(|e| crate::ProxyError::config(format!("Invalid metrics address: {}", e)))?;
    
    info!("Starting metrics server on {}", bind_address);
    
    let listener = tokio::net::TcpListener::bind(addr).await
        .map_err(|e| crate::ProxyError::config(format!("Failed to bind metrics server: {}", e)))?;
    
    axum::serve(listener, app).await
        .map_err(|e| crate::ProxyError::internal(format!("Metrics server error: {}", e)))?;
    
    Ok(())
}

async fn serve_metrics(
    metrics: Arc<ProxyMetrics>,
) -> impl axum::response::IntoResponse {
    use http::{Response, StatusCode, header};
    use axum::body::Body;
    
    match metrics.export() {
        Ok(output) => Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_TYPE, "text/plain; version=0.0.4")
            .body(Body::from(output))
            .unwrap(),
        Err(_) => Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .body(Body::empty())
            .unwrap(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_metrics_creation() {
        let metrics = ProxyMetrics::new().unwrap();
        
        // Test recording various metrics
        metrics.record_connection("http", true);
        metrics.record_auth_success();
        metrics.record_bytes_transferred(1024, "upload");
        metrics.record_request_duration("http", "GET", 0.123);
        
        // Export and check format
        let output = metrics.export().unwrap();
        assert!(output.contains("proxy_connections_total"));
        assert!(output.contains("proxy_auth_attempts_total"));
    }
}