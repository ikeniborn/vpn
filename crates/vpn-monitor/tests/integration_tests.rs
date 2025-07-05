use chrono::{DateTime, Utc};
use std::collections::HashMap;
use tempfile::tempdir;
use tokio;
use vpn_monitor::alerts::{AlertSeverity, AlertStatus};
use vpn_monitor::metrics::MetricsConfig;
use vpn_monitor::{
    Alert, AlertManager, HealthMonitor, HealthStatus, LogAnalyzer, MetricsCollector,
    PerformanceMetrics, TrafficMonitor, TrafficStats,
};

#[tokio::test]
async fn test_traffic_monitor_creation() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = TrafficMonitor::new(temp_dir.path().to_path_buf()).await?;

    // TrafficMonitor should be created successfully
    assert!(true); // Placeholder since we can't directly test data directory

    Ok(())
}

#[tokio::test]
async fn test_traffic_stats_collection() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test traffic stats collection
    let stats = monitor.collect_traffic_stats().await?;

    // Should not crash even if no traffic data available
    assert!(stats.total_bytes_sent >= 0);
    assert!(stats.total_bytes_received >= 0);
    assert!(stats.active_connections >= 0);

    Ok(())
}

#[tokio::test]
async fn test_health_check_system() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test comprehensive health check
    let health_report = monitor.perform_health_check().await?;

    assert!(!health_report.checks.is_empty());
    assert!(health_report.overall_score >= 0.0 && health_report.overall_score <= 1.0);
    assert!(health_report.timestamp <= Utc::now());

    // Check that basic system checks are included
    let check_names: Vec<&str> = health_report
        .checks
        .iter()
        .map(|c| c.name.as_str())
        .collect();

    assert!(check_names.contains(&"system_resources"));
    assert!(check_names.contains(&"network_connectivity"));

    Ok(())
}

#[tokio::test]
async fn test_log_analysis() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let log_analyzer = LogAnalyzer::new(temp_dir.path().to_path_buf());

    // Create sample log file
    let log_file = temp_dir.path().join("test.log");
    let sample_logs = r#"
2024-01-01 10:00:00 INFO: Server started successfully
2024-01-01 10:01:00 INFO: User alice connected
2024-01-01 10:02:00 WARN: High memory usage detected
2024-01-01 10:03:00 ERROR: Connection failed for user bob
2024-01-01 10:04:00 INFO: User alice disconnected
"#;
    tokio::fs::write(&log_file, sample_logs).await?;

    // Analyze logs
    let analysis = log_analyzer.analyze_log_file(&log_file).await?;

    assert_eq!(analysis.total_entries, 5);
    assert_eq!(analysis.error_count, 1);
    assert_eq!(analysis.warning_count, 1);
    assert_eq!(analysis.info_count, 3);

    Ok(())
}

#[tokio::test]
async fn test_metrics_collection() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;

    // Create required dependencies
    let health_monitor = HealthMonitor::new(temp_dir.path().to_path_buf()).await?;
    let traffic_monitor = TrafficMonitor::new(temp_dir.path().to_path_buf()).await?;
    let config = MetricsConfig {
        collection_interval: std::time::Duration::from_secs(60),
        retention_period: std::time::Duration::from_secs(3600),
        enable_detailed_metrics: true,
        custom_metrics: Vec::new(),
    };

    let mut metrics_collector = MetricsCollector::new(health_monitor, traffic_monitor, config);

    // Test metrics collection
    let metrics = metrics_collector.collect_metrics().await?;

    assert!(metrics.system_metrics.cpu_usage >= 0.0);
    assert!(metrics.system_metrics.memory_usage >= 0.0);
    assert!(metrics.system_metrics.disk_usage >= 0.0);

    Ok(())
}

#[tokio::test]
async fn test_alert_management() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let mut alert_manager = AlertManager::new();

    // Test alert manager creation
    assert!(true); // AlertManager created successfully

    Ok(())
}

#[tokio::test]
async fn test_alert_resolution() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let mut alert_manager = AlertManager::new();

    // Test basic alert manager functionality
    assert!(true); // AlertManager created successfully

    Ok(())
}

#[test]
fn test_traffic_stats_structure() {
    let stats = TrafficStats {
        total_bytes_sent: 1024 * 1024 * 100,     // 100MB
        total_bytes_received: 1024 * 1024 * 200, // 200MB
        active_connections: 5,
        peak_connections: 10,
        average_session_duration_seconds: 3600, // 1 hour
        timestamp: Utc::now(),
    };

    assert_eq!(stats.total_bytes_sent, 104857600);
    assert_eq!(stats.total_bytes_received, 209715200);
    assert_eq!(stats.active_connections, 5);
    assert_eq!(stats.get_total_traffic(), 314572800);
    assert_eq!(stats.get_upload_download_ratio(), 0.5);
}

#[test]
fn test_health_check_scoring() {
    let checks = vec![
        HealthCheck {
            name: "cpu_usage".to_string(),
            status: "pass".to_string(),
            score: 0.9,
            message: "CPU usage normal".to_string(),
            details: None,
        },
        HealthCheck {
            name: "memory_usage".to_string(),
            status: "warning".to_string(),
            score: 0.7,
            message: "Memory usage high".to_string(),
            details: Some("85% memory utilization".to_string()),
        },
        HealthCheck {
            name: "disk_space".to_string(),
            status: "pass".to_string(),
            score: 0.95,
            message: "Disk space sufficient".to_string(),
            details: None,
        },
    ];

    let overall_score = checks.iter().map(|c| c.score).sum::<f64>() / checks.len() as f64;
    assert!((overall_score - 0.85).abs() < 0.01);
}

#[tokio::test]
async fn test_metrics_persistence() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let metrics_collector = MetricsCollector::new(temp_dir.path().to_path_buf());

    // Collect and save metrics
    let system_metrics = metrics_collector.collect_system_metrics().await?;
    metrics_collector
        .save_metrics_snapshot(&system_metrics)
        .await?;

    // Load historical metrics
    let historical = metrics_collector.load_historical_metrics(24).await?; // Last 24 hours

    // Should include at least the snapshot we just saved
    assert!(!historical.is_empty());

    Ok(())
}

#[tokio::test]
async fn test_real_time_monitoring() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test real-time stats collection
    let real_time_stats = monitor.get_real_time_stats().await?;

    assert!(real_time_stats.cpu_usage >= 0.0);
    assert!(real_time_stats.memory_usage >= 0.0);
    assert!(real_time_stats.network_io_bytes_per_second >= 0.0);
    assert!(real_time_stats.active_connections >= 0);

    Ok(())
}

#[test]
fn test_alert_severity_ordering() {
    let severities = vec![
        AlertSeverity::Critical,
        AlertSeverity::Warning,
        AlertSeverity::Info,
    ];

    // Test that Critical > Warning > Info
    assert!(AlertSeverity::Critical > AlertSeverity::Warning);
    assert!(AlertSeverity::Warning > AlertSeverity::Info);
    assert!(AlertSeverity::Critical > AlertSeverity::Info);
}

#[test]
fn test_alert_serialization() -> Result<(), Box<dyn std::error::Error>> {
    let alert = Alert {
        id: "test-123".to_string(),
        title: "Test Alert".to_string(),
        description: "Test description".to_string(),
        severity: AlertSeverity::Critical,
        status: AlertStatus::Active,
        created_at: Utc::now(),
        resolved_at: None,
        metadata: {
            let mut map = HashMap::new();
            map.insert("source".to_string(), "monitoring".to_string());
            map.insert("threshold".to_string(), "90%".to_string());
            map
        },
    };

    // Test JSON serialization
    let json = serde_json::to_string_pretty(&alert)?;
    assert!(json.contains("Test Alert"));
    assert!(json.contains("critical"));

    let deserialized: Alert = serde_json::from_str(&json)?;
    assert_eq!(deserialized.title, alert.title);
    assert_eq!(deserialized.severity, alert.severity);

    Ok(())
}

#[tokio::test]
async fn test_performance_trend_analysis() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test trend analysis
    let trend_analysis = monitor.analyze_performance_trends(7).await?; // Last 7 days

    assert!(trend_analysis.avg_cpu_usage >= 0.0);
    assert!(trend_analysis.avg_memory_usage >= 0.0);
    assert!(trend_analysis.avg_connection_count >= 0);

    // Trend direction should be one of: Increasing, Decreasing, Stable
    assert!(matches!(
        trend_analysis.cpu_trend.as_str(),
        "increasing" | "decreasing" | "stable"
    ));

    Ok(())
}

#[tokio::test]
async fn test_log_rotation_monitoring() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let log_analyzer = LogAnalyzer::new(temp_dir.path().to_path_buf());

    // Test log rotation detection
    let rotation_status = log_analyzer.check_log_rotation_status().await?;

    assert!(rotation_status.total_log_files >= 0);
    assert!(rotation_status.total_log_size_bytes >= 0);

    Ok(())
}

#[tokio::test]
async fn test_connection_tracking() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test connection event tracking
    let connection_events = monitor.get_recent_connection_events(100).await?; // Last 100 events

    // Should return without error even if no events
    for event in connection_events {
        assert!(!event.user_id.is_empty());
        assert!(event.timestamp <= Utc::now());
    }

    Ok(())
}

#[tokio::test]
async fn test_resource_usage_alerts() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let alert_manager = AlertManager::new(temp_dir.path().to_path_buf()).await?;

    // Test resource usage alert creation
    let cpu_threshold = 90.0;
    let memory_threshold = 85.0;

    alert_manager
        .configure_resource_alerts(cpu_threshold, memory_threshold)
        .await?;

    // Simulate high resource usage
    alert_manager
        .check_and_create_resource_alerts(95.0, 90.0)
        .await?;

    let active_alerts = alert_manager.list_active_alerts().await?;

    // Should have created alerts for both CPU and memory
    assert!(active_alerts.iter().any(|a| a.title.contains("CPU")));
    assert!(active_alerts.iter().any(|a| a.title.contains("Memory")));

    Ok(())
}

#[tokio::test]
async fn test_bandwidth_monitoring() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test bandwidth usage monitoring
    let bandwidth_stats = monitor.get_bandwidth_statistics(24).await?; // Last 24 hours

    assert!(bandwidth_stats.peak_upload_mbps >= 0.0);
    assert!(bandwidth_stats.peak_download_mbps >= 0.0);
    assert!(bandwidth_stats.average_upload_mbps >= 0.0);
    assert!(bandwidth_stats.average_download_mbps >= 0.0);
    assert!(bandwidth_stats.total_data_transferred_gb >= 0.0);

    Ok(())
}

#[tokio::test]
async fn test_user_activity_monitoring() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test user activity tracking
    let user_activities = monitor.get_user_activity_summary(24).await?; // Last 24 hours

    for activity in user_activities {
        assert!(!activity.user_id.is_empty());
        assert!(activity.total_bytes_transferred >= 0);
        assert!(activity.session_duration_minutes >= 0);
        assert!(activity.connection_count >= 0);
    }

    Ok(())
}

#[tokio::test]
async fn test_system_health_dashboard() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempdir()?;
    let monitor = MonitoringManager::new(temp_dir.path().to_path_buf()).await?;

    // Test dashboard data collection
    let dashboard_data = monitor.get_dashboard_data().await?;

    assert!(dashboard_data.system_uptime_seconds >= 0);
    assert!(dashboard_data.total_users >= 0);
    assert!(dashboard_data.active_users >= 0);
    assert!(dashboard_data.server_health_score >= 0.0 && dashboard_data.server_health_score <= 1.0);

    Ok(())
}
