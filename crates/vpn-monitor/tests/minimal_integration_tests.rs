//! Minimal integration tests for vpn-monitor crate
//! Tests only that basic imports and creation work

use vpn_monitor::{
    LogAnalyzer, AlertManager
};
use tempfile::tempdir;

#[tokio::test]
async fn test_basic_structs_can_be_imported() -> Result<(), Box<dyn std::error::Error>> {
    let _temp_dir = tempdir()?;
    
    // Test that basic structs can be imported and used
    // We're not testing functionality, just that the API is accessible
    
    // AlertManager doesn't need parameters
    let _alert_manager = AlertManager::new();
    
    // LogAnalyzer doesn't need parameters either
    let _log_analyzer = LogAnalyzer::new()?;
    
    // For now, just test that these types exist and can be referenced
    assert!(true); // Basic imports work
    
    Ok(())
}

#[test]
fn test_alert_status_variants() {
    use vpn_monitor::alerts::{AlertStatus, AlertSeverity};
    
    // Test that alert variants can be created
    let statuses = vec![
        AlertStatus::Active,
        AlertStatus::Acknowledged,
        AlertStatus::Resolved,
        AlertStatus::Suppressed,
    ];
    
    let severities = vec![
        AlertSeverity::Low,
        AlertSeverity::Medium,
        AlertSeverity::High,
        AlertSeverity::Critical,
    ];
    
    // Ensure all variants can be created
    assert_eq!(statuses.len(), 4);
    assert_eq!(severities.len(), 4);
}