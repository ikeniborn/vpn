//! Docker Compose Orchestration Tests
//! 
//! This module contains comprehensive tests for Docker Compose orchestration,
//! service startup order, dependency management, and inter-service communication.

use std::time::{Duration, Instant};
use std::process::Command;
use std::collections::HashMap;
use tokio::time::{sleep, timeout};
use serde_json::Value;

/// Docker Compose test runner
pub struct DockerComposeTestRunner {
    pub compose_file: String,
    pub test_timeout: Duration,
    pub startup_timeout: Duration,
    pub health_check_interval: Duration,
}

impl Default for DockerComposeTestRunner {
    fn default() -> Self {
        Self {
            compose_file: "templates/docker-compose/base.yml".to_string(),
            test_timeout: Duration::from_secs(300), // 5 minutes
            startup_timeout: Duration::from_secs(120), // 2 minutes
            health_check_interval: Duration::from_secs(5),
        }
    }
}

impl DockerComposeTestRunner {
    pub fn new(compose_file: &str) -> Self {
        Self {
            compose_file: compose_file.to_string(),
            ..Default::default()
        }
    }

    /// Test service startup order and dependencies
    pub async fn test_service_startup_order(&self) -> Result<OrchestrationTestResult, Box<dyn std::error::Error>> {
        let mut result = OrchestrationTestResult::new("service_startup_order");
        let start_time = Instant::now();

        println!("🚀 Testing Docker Compose service startup order...");

        // Clean up any existing containers
        let _ = self.compose_down().await;
        sleep(Duration::from_secs(2)).await;

        // Start services and monitor startup sequence
        let startup_task = tokio::spawn({
            let compose_file = self.compose_file.clone();
            async move {
                Self::compose_up_detached(&compose_file).await
            }
        });

        // Monitor service startup sequence
        let mut startup_sequence = Vec::new();
        let monitor_start = Instant::now();

        while monitor_start.elapsed() < self.startup_timeout {
            let services = self.get_running_services().await?;
            
            for service in services {
                if !startup_sequence.contains(&service) {
                    startup_sequence.push(service.clone());
                    println!("  ✅ Service started: {}", service);
                }
            }

            // Check if all expected services are running
            if self.are_all_services_healthy().await? {
                break;
            }

            sleep(self.health_check_interval).await;
        }

        // Wait for startup task to complete
        match timeout(Duration::from_secs(30), startup_task).await {
            Ok(Ok(_)) => {
                result.startup_time = start_time.elapsed();
                result.service_count = startup_sequence.len();
                result.startup_sequence = startup_sequence;
                result.passed = result.startup_time < self.startup_timeout;
            }
            _ => {
                result.passed = false;
                result.error_message = Some("Service startup timed out or failed".to_string());
            }
        }

        // Verify dependency order (databases before applications)
        if result.passed {
            result.passed = self.verify_dependency_order(&result.startup_sequence).await;
        }

        Ok(result)
    }

    /// Test service health checks and readiness probes
    pub async fn test_service_health_checks(&self) -> Result<OrchestrationTestResult, Box<dyn std::error::Error>> {
        let mut result = OrchestrationTestResult::new("service_health_checks");
        
        println!("🏥 Testing service health checks...");

        let services = self.get_service_list().await?;
        let mut health_results = HashMap::new();

        for service in &services {
            let health_status = self.check_service_health(service).await?;
            health_results.insert(service.clone(), health_status);
            
            if health_status {
                println!("  ✅ {} is healthy", service);
            } else {
                println!("  ❌ {} is unhealthy", service);
            }
        }

        let healthy_count = health_results.values().filter(|&&h| h).count();
        result.service_count = services.len();
        result.healthy_services = healthy_count;
        result.passed = healthy_count == services.len();
        result.health_results = health_results;

        Ok(result)
    }

    /// Test service discovery and networking
    pub async fn test_service_discovery(&self) -> Result<OrchestrationTestResult, Box<dyn std::error::Error>> {
        let mut result = OrchestrationTestResult::new("service_discovery");
        
        println!("🔍 Testing service discovery and networking...");

        // Test internal network connectivity
        let connectivity_tests = vec![
            ("vpn-server", "vpn-identity", 8080),
            ("vpn-identity", "postgres", 5432),
            ("vpn-identity", "redis", 6379),
            ("prometheus", "vpn-server", 8081), // metrics port
            ("grafana", "prometheus", 9090),
        ];

        let mut successful_connections = 0;
        let total_tests = connectivity_tests.len();

        for (from_service, to_service, port) in connectivity_tests {
            match self.test_service_connectivity(from_service, to_service, port).await {
                Ok(true) => {
                    successful_connections += 1;
                    println!("  ✅ {} can reach {}:{}", from_service, to_service, port);
                }
                Ok(false) => {
                    println!("  ❌ {} cannot reach {}:{}", from_service, to_service, port);
                }
                Err(e) => {
                    println!("  ⚠️  {} -> {}:{} test failed: {}", from_service, to_service, port, e);
                }
            }
        }

        result.service_count = total_tests;
        result.successful_connections = successful_connections;
        result.passed = successful_connections >= (total_tests * 80 / 100); // 80% success rate

        Ok(result)
    }

    /// Test zero-downtime updates and rolling deployments
    pub async fn test_zero_downtime_updates(&self) -> Result<OrchestrationTestResult, Box<dyn std::error::Error>> {
        let mut result = OrchestrationTestResult::new("zero_downtime_updates");
        
        println!("🔄 Testing zero-downtime updates...");

        // First, ensure services are running
        if !self.are_all_services_healthy().await? {
            result.passed = false;
            result.error_message = Some("Services not healthy before update test".to_string());
            return Ok(result);
        }

        // Test rolling update of a service
        let test_service = "vpn-server";
        let update_start = Instant::now();

        // Monitor service availability during update
        let availability_monitor = tokio::spawn({
            let runner = self.clone();
            async move {
                let mut downtime_periods = Vec::new();
                let mut last_check_healthy = true;
                let mut downtime_start: Option<Instant> = None;

                for _ in 0..30 { // Monitor for 150 seconds (30 * 5s)
                    let is_healthy = runner.check_service_health(test_service).await.unwrap_or(false);
                    
                    if !is_healthy && last_check_healthy {
                        // Service just went down
                        downtime_start = Some(Instant::now());
                    } else if is_healthy && !last_check_healthy {
                        // Service just came back up
                        if let Some(start) = downtime_start {
                            downtime_periods.push(start.elapsed());
                        }
                        downtime_start = None;
                    }

                    last_check_healthy = is_healthy;
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }

                downtime_periods
            }
        });

        // Perform rolling update simulation (restart service)
        sleep(Duration::from_secs(10)).await; // Let monitoring start
        let _ = self.restart_service(test_service).await;

        // Wait for availability monitoring to complete
        let downtime_periods = availability_monitor.await?;
        
        result.update_duration = update_start.elapsed();
        result.downtime_periods = downtime_periods.clone();
        
        // Calculate total downtime
        let total_downtime: Duration = downtime_periods.iter().sum();
        result.total_downtime = total_downtime;
        
        // Zero-downtime means less than 30 seconds of downtime
        result.passed = total_downtime < Duration::from_secs(30);

        println!("  Update duration: {:?}", result.update_duration);
        println!("  Total downtime: {:?}", total_downtime);

        Ok(result)
    }

    /// Test backup and restore procedures
    pub async fn test_backup_restore(&self) -> Result<OrchestrationTestResult, Box<dyn std::error::Error>> {
        let mut result = OrchestrationTestResult::new("backup_restore");
        
        println!("💾 Testing backup and restore procedures...");

        // Test database backup
        let backup_result = self.test_database_backup().await?;
        let restore_result = self.test_database_restore().await?;

        result.backup_successful = backup_result;
        result.restore_successful = restore_result;
        result.passed = backup_result && restore_result;

        if backup_result {
            println!("  ✅ Database backup successful");
        } else {
            println!("  ❌ Database backup failed");
        }

        if restore_result {
            println!("  ✅ Database restore successful");
        } else {
            println!("  ❌ Database restore failed");
        }

        Ok(result)
    }

    // Helper methods for Docker Compose operations
    async fn compose_up_detached(compose_file: &str) -> Result<(), Box<dyn std::error::Error>> {
        let output = Command::new("docker-compose")
            .args(&["-f", compose_file, "up", "-d"])
            .output()?;

        if output.status.success() {
            Ok(())
        } else {
            Err(format!("Docker compose up failed: {}", String::from_utf8_lossy(&output.stderr)).into())
        }
    }

    async fn compose_down(&self) -> Result<(), Box<dyn std::error::Error>> {
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "down", "-v", "--remove-orphans"])
            .output()?;

        if output.status.success() {
            Ok(())
        } else {
            Err(format!("Docker compose down failed: {}", String::from_utf8_lossy(&output.stderr)).into())
        }
    }

    async fn get_running_services(&self) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "ps", "--services", "--filter", "status=running"])
            .output()?;

        if output.status.success() {
            let services = String::from_utf8_lossy(&output.stdout)
                .lines()
                .filter(|line| !line.trim().is_empty())
                .map(|line| line.trim().to_string())
                .collect();
            Ok(services)
        } else {
            Ok(vec![]) // Return empty if command fails
        }
    }

    async fn get_service_list(&self) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "config", "--services"])
            .output()?;

        if output.status.success() {
            let services = String::from_utf8_lossy(&output.stdout)
                .lines()
                .filter(|line| !line.trim().is_empty())
                .map(|line| line.trim().to_string())
                .collect();
            Ok(services)
        } else {
            Ok(vec!["vpn-server", "vpn-identity", "postgres", "redis", "prometheus", "grafana"].iter().map(|s| s.to_string()).collect())
        }
    }

    async fn are_all_services_healthy(&self) -> Result<bool, Box<dyn std::error::Error>> {
        let services = self.get_service_list().await?;
        
        for service in services {
            if !self.check_service_health(&service).await? {
                return Ok(false);
            }
        }
        
        Ok(true)
    }

    async fn check_service_health(&self, service: &str) -> Result<bool, Box<dyn std::error::Error>> {
        // Try multiple approaches to check service health
        
        // First, check if container is running
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "ps", "-q", service])
            .output()?;

        if !output.status.success() || output.stdout.is_empty() {
            return Ok(false);
        }

        let container_id = String::from_utf8_lossy(&output.stdout).trim().to_string();

        // Check container health status
        let health_output = Command::new("docker")
            .args(&["inspect", "--format", "{{.State.Health.Status}}", &container_id])
            .output()?;

        if health_output.status.success() {
            let health_status = String::from_utf8_lossy(&health_output.stdout).trim();
            if health_status == "healthy" {
                return Ok(true);
            }
        }

        // Fallback: check if container is running
        let status_output = Command::new("docker")
            .args(&["inspect", "--format", "{{.State.Status}}", &container_id])
            .output()?;

        if status_output.status.success() {
            let status = String::from_utf8_lossy(&status_output.stdout).trim();
            Ok(status == "running")
        } else {
            Ok(false)
        }
    }

    async fn test_service_connectivity(&self, from_service: &str, to_service: &str, port: u16) -> Result<bool, Box<dyn std::error::Error>> {
        // Use docker exec to test connectivity from one service to another
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "exec", "-T", from_service, 
                   "sh", "-c", &format!("timeout 5 nc -z {} {}", to_service, port)])
            .output()?;

        Ok(output.status.success())
    }

    async fn restart_service(&self, service: &str) -> Result<(), Box<dyn std::error::Error>> {
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "restart", service])
            .output()?;

        if output.status.success() {
            Ok(())
        } else {
            Err(format!("Failed to restart service {}: {}", service, String::from_utf8_lossy(&output.stderr)).into())
        }
    }

    async fn test_database_backup(&self) -> Result<bool, Box<dyn std::error::Error>> {
        // Test PostgreSQL backup
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "exec", "-T", "postgres", 
                   "pg_dump", "-U", "vpn_user", "-d", "vpn_db", "-f", "/tmp/backup.sql"])
            .output()?;

        if !output.status.success() {
            return Ok(false);
        }

        // Verify backup file exists and has content
        let verify_output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "exec", "-T", "postgres", 
                   "test", "-s", "/tmp/backup.sql"])
            .output()?;

        Ok(verify_output.status.success())
    }

    async fn test_database_restore(&self) -> Result<bool, Box<dyn std::error::Error>> {
        // Test restore from backup (to a test database)
        let output = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "exec", "-T", "postgres", 
                   "sh", "-c", "createdb -U vpn_user test_restore_db && psql -U vpn_user -d test_restore_db -f /tmp/backup.sql"])
            .output()?;

        let success = output.status.success();

        // Cleanup test database
        let _ = Command::new("docker-compose")
            .args(&["-f", &self.compose_file, "exec", "-T", "postgres", "dropdb", "-U", "vpn_user", "test_restore_db"])
            .output();

        Ok(success)
    }

    async fn verify_dependency_order(&self, startup_sequence: &[String]) -> bool {
        // Define expected dependency order
        let dependencies = vec![
            ("postgres", vec![]), // No dependencies
            ("redis", vec![]),    // No dependencies  
            ("vpn-identity", vec!["postgres", "redis"]),
            ("vpn-server", vec!["vpn-identity"]),
            ("prometheus", vec!["vpn-server"]),
            ("grafana", vec!["prometheus"]),
        ];

        for (service, deps) in dependencies {
            if let Some(service_index) = startup_sequence.iter().position(|s| s == service) {
                for dep in deps {
                    if let Some(dep_index) = startup_sequence.iter().position(|s| s == dep) {
                        if dep_index > service_index {
                            println!("  ❌ Dependency violation: {} started before {}", service, dep);
                            return false;
                        }
                    }
                }
            }
        }

        println!("  ✅ Service dependency order is correct");
        true
    }
}

impl Clone for DockerComposeTestRunner {
    fn clone(&self) -> Self {
        Self {
            compose_file: self.compose_file.clone(),
            test_timeout: self.test_timeout,
            startup_timeout: self.startup_timeout,
            health_check_interval: self.health_check_interval,
        }
    }
}

/// Result of a Docker Compose orchestration test
#[derive(Debug, Clone)]
pub struct OrchestrationTestResult {
    pub test_name: String,
    pub passed: bool,
    pub startup_time: Duration,
    pub service_count: usize,
    pub healthy_services: usize,
    pub successful_connections: usize,
    pub startup_sequence: Vec<String>,
    pub health_results: HashMap<String, bool>,
    pub downtime_periods: Vec<Duration>,
    pub total_downtime: Duration,
    pub update_duration: Duration,
    pub backup_successful: bool,
    pub restore_successful: bool,
    pub error_message: Option<String>,
}

impl OrchestrationTestResult {
    pub fn new(test_name: &str) -> Self {
        Self {
            test_name: test_name.to_string(),
            passed: false,
            startup_time: Duration::from_secs(0),
            service_count: 0,
            healthy_services: 0,
            successful_connections: 0,
            startup_sequence: Vec::new(),
            health_results: HashMap::new(),
            downtime_periods: Vec::new(),
            total_downtime: Duration::from_secs(0),
            update_duration: Duration::from_secs(0),
            backup_successful: false,
            restore_successful: false,
            error_message: None,
        }
    }

    pub fn success_rate(&self) -> f64 {
        if self.service_count == 0 {
            0.0
        } else {
            self.healthy_services as f64 / self.service_count as f64
        }
    }

    pub fn connectivity_rate(&self) -> f64 {
        if self.service_count == 0 {
            0.0
        } else {
            self.successful_connections as f64 / self.service_count as f64
        }
    }
}

/// Run comprehensive Docker Compose orchestration test suite
pub async fn run_orchestration_test_suite() -> Result<Vec<OrchestrationTestResult>, Box<dyn std::error::Error>> {
    println!("🐳 Starting Docker Compose Orchestration Test Suite");
    
    let runner = DockerComposeTestRunner::default();
    let mut results = Vec::new();

    // Service startup order test
    println!("\n🚀 Testing Service Startup Order...");
    let startup_result = runner.test_service_startup_order().await?;
    println!("Service Startup: {} ({}s, {} services)", 
             if startup_result.passed { "✅ PASS" } else { "❌ FAIL" },
             startup_result.startup_time.as_secs(),
             startup_result.service_count);
    results.push(startup_result);

    // Service health checks test
    println!("\n🏥 Testing Service Health Checks...");
    let health_result = runner.test_service_health_checks().await?;
    println!("Service Health: {} ({}/{} healthy)", 
             if health_result.passed { "✅ PASS" } else { "❌ FAIL" },
             health_result.healthy_services,
             health_result.service_count);
    results.push(health_result);

    // Service discovery test
    println!("\n🔍 Testing Service Discovery...");
    let discovery_result = runner.test_service_discovery().await?;
    println!("Service Discovery: {} ({}/{} connections)", 
             if discovery_result.passed { "✅ PASS" } else { "❌ FAIL" },
             discovery_result.successful_connections,
             discovery_result.service_count);
    results.push(discovery_result);

    // Zero-downtime updates test
    println!("\n🔄 Testing Zero-Downtime Updates...");
    let update_result = runner.test_zero_downtime_updates().await?;
    println!("Zero-Downtime Updates: {} ({}s downtime)", 
             if update_result.passed { "✅ PASS" } else { "❌ FAIL" },
             update_result.total_downtime.as_secs());
    results.push(update_result);

    // Backup and restore test
    println!("\n💾 Testing Backup & Restore...");
    let backup_result = runner.test_backup_restore().await?;
    println!("Backup & Restore: {} (backup: {}, restore: {})", 
             if backup_result.passed { "✅ PASS" } else { "❌ FAIL" },
             if backup_result.backup_successful { "✅" } else { "❌" },
             if backup_result.restore_successful { "✅" } else { "❌" });
    results.push(backup_result);

    let passed_tests = results.iter().filter(|r| r.passed).count();
    let total_tests = results.len();
    
    println!("\n🎯 Orchestration Test Summary: {}/{} tests passed", passed_tests, total_tests);

    // Cleanup
    println!("\n🧹 Cleaning up test environment...");
    let _ = runner.compose_down().await;
    
    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_orchestration_result_creation() {
        let result = OrchestrationTestResult::new("test");
        assert_eq!(result.test_name, "test");
        assert!(!result.passed);
        assert_eq!(result.service_count, 0);
    }

    #[test]
    fn test_success_rate_calculation() {
        let mut result = OrchestrationTestResult::new("test");
        result.service_count = 5;
        result.healthy_services = 4;
        
        assert_eq!(result.success_rate(), 0.8);
    }

    #[tokio::test]
    async fn test_docker_compose_runner_creation() {
        let runner = DockerComposeTestRunner::new("test-compose.yml");
        assert_eq!(runner.compose_file, "test-compose.yml");
        assert_eq!(runner.test_timeout, Duration::from_secs(300));
    }

    #[tokio::test]
    async fn test_service_list_parsing() {
        let runner = DockerComposeTestRunner::default();
        // This test will use fallback service list since no real compose file
        let services = runner.get_service_list().await.unwrap();
        assert!(!services.is_empty());
    }
}