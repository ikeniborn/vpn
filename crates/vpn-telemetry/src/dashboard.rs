//! Real-time performance dashboard

use crate::{config::TelemetryConfig, error::Result, TelemetryError};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::sync::RwLock;
use tracing::{info, warn};

/// Dashboard configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DashboardConfig {
    pub enabled: bool,
    pub bind_address: String,
    pub port: u16,
    pub title: String,
    pub refresh_interval: std::time::Duration,
    pub auth_enabled: bool,
    pub username: Option<String>,
    pub password: Option<String>,
}

impl Default for DashboardConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            bind_address: "0.0.0.0".to_string(),
            port: 8080,
            title: "VPN System Telemetry".to_string(),
            refresh_interval: std::time::Duration::from_secs(5),
            auth_enabled: false,
            username: None,
            password: None,
        }
    }
}

/// Dashboard data structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DashboardData {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub system_health: SystemHealthWidget,
    pub performance_metrics: PerformanceWidget,
    pub container_status: ContainerWidget,
    pub user_activity: UserActivityWidget,
    pub network_stats: NetworkStatsWidget,
    pub alerts: Vec<Alert>,
}

/// System health widget data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemHealthWidget {
    pub overall_status: HealthStatus,
    pub cpu_usage: f64,
    pub memory_usage: f64,
    pub disk_usage: f64,
    pub uptime: u64,
    pub services: Vec<ServiceHealth>,
}

/// Service health status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceHealth {
    pub name: String,
    pub status: HealthStatus,
    pub response_time: Option<f64>,
    pub last_check: chrono::DateTime<chrono::Utc>,
}

/// Health status enum
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthStatus {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

/// Performance metrics widget
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceWidget {
    pub total_requests: u64,
    pub requests_per_second: f64,
    pub average_response_time: f64,
    pub error_rate: f64,
    pub throughput_mbps: f64,
    pub active_connections: u64,
}

/// Container status widget
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerWidget {
    pub total_containers: u64,
    pub running_containers: u64,
    pub stopped_containers: u64,
    pub failed_containers: u64,
    pub recent_events: Vec<ContainerEvent>,
}

/// Container event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerEvent {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub container_id: String,
    pub event_type: String,
    pub status: String,
}

/// User activity widget
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserActivityWidget {
    pub active_users: u64,
    pub total_sessions: u64,
    pub data_transferred_gb: f64,
    pub top_users: Vec<UserStats>,
    pub connection_history: Vec<ConnectionHistoryPoint>,
}

/// User statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserStats {
    pub user_id: String,
    pub sessions: u64,
    pub data_transferred: u64,
    pub last_seen: chrono::DateTime<chrono::Utc>,
}

/// Connection history point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionHistoryPoint {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub active_connections: u64,
}

/// Network statistics widget
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkStatsWidget {
    pub total_bandwidth_mbps: f64,
    pub upload_mbps: f64,
    pub download_mbps: f64,
    pub packet_loss_rate: f64,
    pub latency_ms: f64,
}

/// Alert structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Alert {
    pub id: String,
    pub level: AlertLevel,
    pub title: String,
    pub message: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub acknowledged: bool,
}

/// Alert levels
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AlertLevel {
    Info,
    Warning,
    Error,
    Critical,
}

/// Dashboard manager
pub struct DashboardManager {
    config: TelemetryConfig,
    dashboard_data: Arc<RwLock<DashboardData>>,
    running: Arc<RwLock<bool>>,
    server_handle: Arc<RwLock<Option<tokio::task::JoinHandle<()>>>>,
}

impl DashboardManager {
    /// Create a new dashboard manager
    pub async fn new(config: &TelemetryConfig) -> Result<Self> {
        let dashboard_data = Arc::new(RwLock::new(DashboardData::default()));

        Ok(Self {
            config: config.clone(),
            dashboard_data,
            running: Arc::new(RwLock::new(false)),
            server_handle: Arc::new(RwLock::new(None)),
        })
    }

    /// Start the dashboard server
    pub async fn start(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        if !self.config.dashboard_enabled {
            info!("Dashboard is disabled");
            return Ok(());
        }

        let bind_addr = format!(
            "{}:{}",
            self.config.dashboard.bind_address, self.config.dashboard.port
        );

        info!("Starting dashboard server on {}", bind_addr);

        let listener =
            TcpListener::bind(&bind_addr)
                .await
                .map_err(|e| TelemetryError::DashboardError {
                    message: format!("Failed to bind to {}: {}", bind_addr, e),
                })?;

        let dashboard_data = self.dashboard_data.clone();
        let config = self.config.clone();
        let running_flag = self.running.clone();

        let server_task = tokio::spawn(async move {
            if let Err(e) = Self::run_server(listener, dashboard_data, config, running_flag).await {
                warn!("Dashboard server error: {}", e);
            }
        });

        *self.server_handle.write().await = Some(server_task);
        *running = true;

        info!("Dashboard server started successfully");
        Ok(())
    }

    /// Stop the dashboard server
    pub async fn stop(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        *running = false;

        // Cancel the server task
        if let Some(handle) = self.server_handle.write().await.take() {
            handle.abort();
        }

        info!("Dashboard server stopped");
        Ok(())
    }

    /// Get the dashboard URL
    pub fn get_url(&self) -> Option<String> {
        if !self.config.dashboard_enabled {
            return None;
        }

        Some(format!(
            "http://{}:{}",
            self.config.dashboard.bind_address, self.config.dashboard.port
        ))
    }

    /// Update dashboard data
    pub async fn update_data(&self, data: DashboardData) -> Result<()> {
        let mut dashboard_data = self.dashboard_data.write().await;
        *dashboard_data = data;
        Ok(())
    }

    /// Get current dashboard data
    pub async fn get_data(&self) -> DashboardData {
        self.dashboard_data.read().await.clone()
    }

    /// Run the HTTP server
    async fn run_server(
        listener: TcpListener,
        dashboard_data: Arc<RwLock<DashboardData>>,
        config: TelemetryConfig,
        running: Arc<RwLock<bool>>,
    ) -> Result<()> {
        // use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

        while *running.read().await {
            match tokio::time::timeout(std::time::Duration::from_millis(100), listener.accept())
                .await
            {
                Ok(Ok((mut stream, addr))) => {
                    info!("Dashboard connection from {}", addr);

                    let dashboard_data = dashboard_data.clone();
                    let config = config.clone();

                    tokio::spawn(async move {
                        if let Err(e) =
                            Self::handle_connection(&mut stream, dashboard_data, config).await
                        {
                            warn!("Error handling dashboard connection: {}", e);
                        }
                    });
                }
                Ok(Err(e)) => {
                    warn!("Error accepting dashboard connection: {}", e);
                }
                Err(_) => {
                    // Timeout - continue loop to check running flag
                    continue;
                }
            }
        }

        Ok(())
    }

    /// Handle a single HTTP connection
    async fn handle_connection(
        stream: &mut tokio::net::TcpStream,
        dashboard_data: Arc<RwLock<DashboardData>>,
        config: TelemetryConfig,
    ) -> Result<()> {
        let mut reader = BufReader::new(&mut *stream);
        let mut request_line = String::new();
        reader.read_line(&mut request_line).await?;

        let path = request_line.split_whitespace().nth(1).unwrap_or("/");

        // Read and discard the rest of the HTTP headers
        let mut line = String::new();
        while reader.read_line(&mut line).await? > 0 {
            if line.trim().is_empty() {
                break;
            }
            line.clear();
        }

        let response = match path {
            "/" => Self::serve_dashboard_html(&config).await?,
            "/api/data" => Self::serve_dashboard_data(dashboard_data).await?,
            "/api/health" => Self::serve_health_check().await?,
            _ => Self::serve_404().await?,
        };

        stream.write_all(response.as_bytes()).await?;
        stream.flush().await?;

        Ok(())
    }

    /// Serve the main dashboard HTML page
    async fn serve_dashboard_html(config: &TelemetryConfig) -> Result<String> {
        let html = format!(
            r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{}</title>
    <style>
        body {{ 
            font-family: Arial, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background-color: #f5f5f5; 
        }}
        .header {{ 
            background-color: #2c3e50; 
            color: white; 
            padding: 20px; 
            border-radius: 8px; 
            margin-bottom: 20px; 
        }}
        .dashboard {{ 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); 
            gap: 20px; 
        }}
        .widget {{ 
            background: white; 
            border-radius: 8px; 
            padding: 20px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
        }}
        .widget h3 {{ 
            margin-top: 0; 
            color: #2c3e50; 
        }}
        .metric {{ 
            display: flex; 
            justify-content: space-between; 
            margin: 10px 0; 
        }}
        .status-healthy {{ color: #27ae60; }}
        .status-warning {{ color: #f39c12; }}
        .status-critical {{ color: #e74c3c; }}
        .refresh-info {{ 
            text-align: center; 
            color: #7f8c8d; 
            margin-top: 20px; 
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>{}</h1>
        <p>Real-time VPN System Monitoring</p>
    </div>
    
    <div class="dashboard" id="dashboard">
        <div class="widget">
            <h3>System Health</h3>
            <div id="system-health">Loading...</div>
        </div>
        
        <div class="widget">
            <h3>Performance Metrics</h3>
            <div id="performance-metrics">Loading...</div>
        </div>
        
        <div class="widget">
            <h3>Container Status</h3>
            <div id="container-status">Loading...</div>
        </div>
        
        <div class="widget">
            <h3>User Activity</h3>
            <div id="user-activity">Loading...</div>
        </div>
        
        <div class="widget">
            <h3>Network Statistics</h3>
            <div id="network-stats">Loading...</div>
        </div>
        
        <div class="widget">
            <h3>Recent Alerts</h3>
            <div id="alerts">Loading...</div>
        </div>
    </div>
    
    <div class="refresh-info">
        <p>Auto-refreshing every {} seconds | Last updated: <span id="last-updated">Never</span></p>
    </div>
    
    <script>
        async function updateDashboard() {{
            try {{
                const response = await fetch('/api/data');
                const data = await response.json();
                
                // Update system health
                const healthElement = document.getElementById('system-health');
                healthElement.innerHTML = `
                    <div class="metric">
                        <span>Overall Status:</span>
                        <span class="status-${{data.system_health.overall_status}}">${{data.system_health.overall_status}}</span>
                    </div>
                    <div class="metric">
                        <span>CPU Usage:</span>
                        <span>${{data.system_health.cpu_usage.toFixed(1)}}%</span>
                    </div>
                    <div class="metric">
                        <span>Memory Usage:</span>
                        <span>${{data.system_health.memory_usage.toFixed(1)}}%</span>
                    </div>
                    <div class="metric">
                        <span>Disk Usage:</span>
                        <span>${{data.system_health.disk_usage.toFixed(1)}}%</span>
                    </div>
                    <div class="metric">
                        <span>Uptime:</span>
                        <span>${{formatUptime(data.system_health.uptime)}}</span>
                    </div>
                `;
                
                // Update performance metrics
                const perfElement = document.getElementById('performance-metrics');
                perfElement.innerHTML = `
                    <div class="metric">
                        <span>Requests/sec:</span>
                        <span>${{data.performance_metrics.requests_per_second.toFixed(1)}}</span>
                    </div>
                    <div class="metric">
                        <span>Avg Response Time:</span>
                        <span>${{data.performance_metrics.average_response_time.toFixed(2)}}ms</span>
                    </div>
                    <div class="metric">
                        <span>Error Rate:</span>
                        <span>${{data.performance_metrics.error_rate.toFixed(2)}}%</span>
                    </div>
                    <div class="metric">
                        <span>Throughput:</span>
                        <span>${{data.performance_metrics.throughput_mbps.toFixed(1)}} Mbps</span>
                    </div>
                    <div class="metric">
                        <span>Active Connections:</span>
                        <span>${{data.performance_metrics.active_connections}}</span>
                    </div>
                `;
                
                // Update container status
                const containerElement = document.getElementById('container-status');
                containerElement.innerHTML = `
                    <div class="metric">
                        <span>Total:</span>
                        <span>${{data.container_status.total_containers}}</span>
                    </div>
                    <div class="metric">
                        <span>Running:</span>
                        <span class="status-healthy">${{data.container_status.running_containers}}</span>
                    </div>
                    <div class="metric">
                        <span>Stopped:</span>
                        <span>${{data.container_status.stopped_containers}}</span>
                    </div>
                    <div class="metric">
                        <span>Failed:</span>
                        <span class="status-critical">${{data.container_status.failed_containers}}</span>
                    </div>
                `;
                
                // Update user activity
                const userElement = document.getElementById('user-activity');
                userElement.innerHTML = `
                    <div class="metric">
                        <span>Active Users:</span>
                        <span>${{data.user_activity.active_users}}</span>
                    </div>
                    <div class="metric">
                        <span>Total Sessions:</span>
                        <span>${{data.user_activity.total_sessions}}</span>
                    </div>
                    <div class="metric">
                        <span>Data Transferred:</span>
                        <span>${{data.user_activity.data_transferred_gb.toFixed(2)}} GB</span>
                    </div>
                `;
                
                // Update network stats
                const networkElement = document.getElementById('network-stats');
                networkElement.innerHTML = `
                    <div class="metric">
                        <span>Total Bandwidth:</span>
                        <span>${{data.network_stats.total_bandwidth_mbps.toFixed(1)}} Mbps</span>
                    </div>
                    <div class="metric">
                        <span>Upload:</span>
                        <span>${{data.network_stats.upload_mbps.toFixed(1)}} Mbps</span>
                    </div>
                    <div class="metric">
                        <span>Download:</span>
                        <span>${{data.network_stats.download_mbps.toFixed(1)}} Mbps</span>
                    </div>
                    <div class="metric">
                        <span>Packet Loss:</span>
                        <span>${{data.network_stats.packet_loss_rate.toFixed(2)}}%</span>
                    </div>
                    <div class="metric">
                        <span>Latency:</span>
                        <span>${{data.network_stats.latency_ms.toFixed(1)}} ms</span>
                    </div>
                `;
                
                // Update alerts
                const alertsElement = document.getElementById('alerts');
                if (data.alerts.length === 0) {{
                    alertsElement.innerHTML = '<p>No active alerts</p>';
                }} else {{
                    alertsElement.innerHTML = data.alerts
                        .slice(0, 5)
                        .map(alert => `
                            <div class="metric">
                                <span class="status-${{alert.level}}">${{alert.title}}</span>
                                <span>${{new Date(alert.timestamp).toLocaleTimeString()}}</span>
                            </div>
                        `).join('');
                }}
                
                document.getElementById('last-updated').textContent = new Date().toLocaleTimeString();
            }} catch (error) {{
                console.error('Failed to update dashboard:', error);
            }}
        }}
        
        function formatUptime(seconds) {{
            const days = Math.floor(seconds / 86400);
            const hours = Math.floor((seconds % 86400) / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            return `${{days}}d ${{hours}}h ${{minutes}}m`;
        }}
        
        // Initial load and periodic updates
        updateDashboard();
        setInterval(updateDashboard, {} * 1000);
    </script>
</body>
</html>"#,
            config.dashboard.title,
            config.dashboard.title,
            config.dashboard.refresh_interval.as_secs(),
            config.dashboard.refresh_interval.as_secs()
        );

        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\n\r\n{}",
            html.len(),
            html
        );

        Ok(response)
    }

    /// Serve dashboard data as JSON
    async fn serve_dashboard_data(dashboard_data: Arc<RwLock<DashboardData>>) -> Result<String> {
        let data = dashboard_data.read().await;
        let json = serde_json::to_string(&*data)?;

        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            json.len(),
            json
        );

        Ok(response)
    }

    /// Serve health check endpoint
    async fn serve_health_check() -> Result<String> {
        let health = serde_json::json!({
            "status": "healthy",
            "timestamp": chrono::Utc::now()
        });

        let json = health.to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            json.len(),
            json
        );

        Ok(response)
    }

    /// Serve 404 response
    async fn serve_404() -> Result<String> {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
        Ok(response.to_string())
    }
}

impl Default for DashboardData {
    fn default() -> Self {
        Self {
            timestamp: chrono::Utc::now(),
            system_health: SystemHealthWidget {
                overall_status: HealthStatus::Unknown,
                cpu_usage: 0.0,
                memory_usage: 0.0,
                disk_usage: 0.0,
                uptime: 0,
                services: vec![],
            },
            performance_metrics: PerformanceWidget {
                total_requests: 0,
                requests_per_second: 0.0,
                average_response_time: 0.0,
                error_rate: 0.0,
                throughput_mbps: 0.0,
                active_connections: 0,
            },
            container_status: ContainerWidget {
                total_containers: 0,
                running_containers: 0,
                stopped_containers: 0,
                failed_containers: 0,
                recent_events: vec![],
            },
            user_activity: UserActivityWidget {
                active_users: 0,
                total_sessions: 0,
                data_transferred_gb: 0.0,
                top_users: vec![],
                connection_history: vec![],
            },
            network_stats: NetworkStatsWidget {
                total_bandwidth_mbps: 0.0,
                upload_mbps: 0.0,
                download_mbps: 0.0,
                packet_loss_rate: 0.0,
                latency_ms: 0.0,
            },
            alerts: vec![],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::TelemetryConfig;

    #[tokio::test]
    async fn test_dashboard_manager_creation() {
        let config = TelemetryConfig::default();
        let manager = DashboardManager::new(&config).await;
        assert!(manager.is_ok());
    }

    #[tokio::test]
    async fn test_dashboard_data_default() {
        let data = DashboardData::default();
        assert_eq!(data.system_health.cpu_usage, 0.0);
        assert_eq!(data.performance_metrics.total_requests, 0);
        assert_eq!(data.container_status.total_containers, 0);
    }

    #[tokio::test]
    async fn test_dashboard_data_update() {
        let config = TelemetryConfig::default();
        let manager = DashboardManager::new(&config).await.unwrap();

        let mut data = DashboardData::default();
        data.system_health.cpu_usage = 50.0;

        let result = manager.update_data(data.clone()).await;
        assert!(result.is_ok());

        let retrieved_data = manager.get_data().await;
        assert_eq!(retrieved_data.system_health.cpu_usage, 50.0);
    }
}
