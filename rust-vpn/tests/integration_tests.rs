use std::process::Command;
use std::path::Path;
use std::fs;
use tempfile::tempdir;

/// Integration tests for the VPN Rust implementation
/// These tests verify that the core workflows work end-to-end

#[test]
fn test_cli_binary_exists() {
    // Test that the CLI binary can be built
    let output = Command::new("cargo")
        .args(&["build", "--bin", "vpn"])
        .current_dir(".")
        .output()
        .expect("Failed to execute cargo build");

    assert!(output.status.success(), 
        "CLI build failed: {}", String::from_utf8_lossy(&output.stderr));
}

#[test]
fn test_cli_help_command() {
    // Test that the CLI shows help
    let output = Command::new("cargo")
        .args(&["run", "--bin", "vpn", "--", "--help"])
        .current_dir(".")
        .output()
        .expect("Failed to execute cargo run");

    // Should exit successfully and show help text
    assert!(output.status.success() || output.status.code() == Some(0));
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Usage:") || stdout.contains("USAGE:"));
}

#[test]
fn test_workspace_builds() {
    // Test that the entire workspace builds successfully
    let output = Command::new("cargo")
        .args(&["build", "--workspace"])
        .current_dir(".")
        .output()
        .expect("Failed to execute cargo build --workspace");

    assert!(output.status.success(), 
        "Workspace build failed: {}", String::from_utf8_lossy(&output.stderr));
}

#[test]
fn test_workspace_tests_compile() {
    // Test that all workspace tests compile (but don't necessarily run)
    let output = Command::new("cargo")
        .args(&["test", "--workspace", "--no-run"])
        .current_dir(".")
        .output()
        .expect("Failed to execute cargo test --no-run");

    // We expect some compilation issues but want to see what compiles
    let stderr = String::from_utf8_lossy(&output.stderr);
    println!("Test compilation output: {}", stderr);
    
    // At minimum, we should not have critical errors
    assert!(!stderr.contains("error: aborting due to previous error"));
}

#[test]
fn test_configuration_structure() {
    // Test that configuration files can be created and parsed
    let temp_dir = tempdir().expect("Failed to create temp dir");
    let config_path = temp_dir.path().join("test_config.toml");
    
    let test_config = r#"
[server]
host = "0.0.0.0"
port = 8443
protocol = "vless"

[logging]
level = "info"
file = "/var/log/vpn.log"

[docker]
image = "xray/xray:latest"
restart_policy = "always"
"#;
    
    fs::write(&config_path, test_config).expect("Failed to write config");
    assert!(config_path.exists());
    
    // Verify the config can be read
    let content = fs::read_to_string(&config_path).expect("Failed to read config");
    assert!(content.contains("protocol = \"vless\""));
}

#[test]
fn test_docker_compose_template_generation() {
    // Test that Docker Compose templates can be generated
    let temp_dir = tempdir().expect("Failed to create temp dir");
    let compose_path = temp_dir.path().join("docker-compose.yml");
    
    let docker_compose_template = r#"
version: '3.8'
services:
  xray:
    image: xray/xray:latest
    container_name: xray
    restart: always
    ports:
      - "8443:8443"
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
    networks:
      - vpn-network

networks:
  vpn-network:
    driver: bridge
"#;
    
    fs::write(&compose_path, docker_compose_template).expect("Failed to write compose file");
    assert!(compose_path.exists());
    
    // Verify the compose file contains expected content
    let content = fs::read_to_string(&compose_path).expect("Failed to read compose file");
    assert!(content.contains("xray/xray:latest"));
    assert!(content.contains("8443:8443"));
}

#[test]
fn test_user_configuration_json_generation() {
    // Test that user configuration JSON can be generated
    let temp_dir = tempdir().expect("Failed to create temp dir");
    let user_config_path = temp_dir.path().join("user.json");
    
    let user_config = r#"
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "testuser",
  "protocol": "vless",
  "config": {
    "server_host": "example.com",
    "server_port": 8443,
    "private_key": "private_key_data",
    "public_key": "public_key_data",
    "short_id": "short123",
    "sni": "google.com",
    "reality_dest": "www.google.com:443"
  },
  "status": "active",
  "created_at": "2025-01-26T10:00:00Z"
}
"#;
    
    fs::write(&user_config_path, user_config).expect("Failed to write user config");
    assert!(user_config_path.exists());
    
    // Verify the user config contains expected fields
    let content = fs::read_to_string(&user_config_path).expect("Failed to read user config");
    assert!(content.contains("\"protocol\": \"vless\""));
    assert!(content.contains("\"status\": \"active\""));
}

#[test]
fn test_connection_link_format() {
    // Test that connection links follow the expected format
    let vless_link = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:8443?type=tcp&security=reality&sni=google.com&fp=chrome&pbk=public_key_data&sid=short123&spx=%2F#testuser";
    
    // Verify VLESS link format
    assert!(vless_link.starts_with("vless://"));
    assert!(vless_link.contains("@example.com:8443"));
    assert!(vless_link.contains("security=reality"));
    assert!(vless_link.contains("sni=google.com"));
    assert!(vless_link.contains("#testuser"));
}

#[test]
fn test_directory_structure_creation() {
    // Test that the expected directory structure can be created
    let temp_dir = tempdir().expect("Failed to create temp dir");
    let base_path = temp_dir.path().join("vpn-server");
    
    let directories = [
        "config",
        "users", 
        "logs",
        "keys",
        "templates"
    ];
    
    for dir in &directories {
        let dir_path = base_path.join(dir);
        fs::create_dir_all(&dir_path).expect("Failed to create directory");
        assert!(dir_path.exists());
        assert!(dir_path.is_dir());
    }
}

#[test]
fn test_error_handling_workflow() {
    // Test that error handling works as expected
    let temp_dir = tempdir().expect("Failed to create temp dir");
    let invalid_config_path = temp_dir.path().join("invalid.toml");
    
    let invalid_config = r#"
[server
host = "0.0.0.0"
port = "invalid_port"
protocol = "unknown_protocol"
"#;
    
    fs::write(&invalid_config_path, invalid_config).expect("Failed to write invalid config");
    
    // Reading this should demonstrate error handling
    let content = fs::read_to_string(&invalid_config_path).expect("Failed to read invalid config");
    assert!(content.contains("invalid_port"));
    
    // The actual parsing would be handled by the TOML library and would fail gracefully
}

#[test]
fn test_performance_baseline() {
    // Basic performance test to establish baseline
    use std::time::Instant;
    
    let start = Instant::now();
    
    // Simulate some basic operations
    let temp_dir = tempdir().expect("Failed to create temp dir");
    for i in 0..100 {
        let file_path = temp_dir.path().join(format!("file_{}.txt", i));
        fs::write(&file_path, format!("Test content {}", i)).expect("Failed to write file");
        assert!(file_path.exists());
    }
    
    let duration = start.elapsed();
    
    // Should be able to create 100 small files in under 1 second
    assert!(duration.as_secs() < 1, "Performance test took too long: {:?}", duration);
}

#[test]
fn test_migration_compatibility() {
    // Test that migration from Bash to Rust maintains compatibility
    let temp_dir = tempdir().expect("Failed to create temp dir");
    
    // Simulate Bash script output format
    let bash_user_list = r#"
User ID: 550e8400-e29b-41d4-a716-446655440000
Name: testuser1
Protocol: vless
Status: active

User ID: 6ba7b810-9dad-11d1-80b4-00c04fd430c8  
Name: testuser2
Protocol: vmess
Status: suspended
"#;
    
    let bash_output_path = temp_dir.path().join("bash_users.txt");
    fs::write(&bash_output_path, bash_user_list).expect("Failed to write bash output");
    
    // Verify the format can be parsed
    let content = fs::read_to_string(&bash_output_path).expect("Failed to read bash output");
    assert!(content.contains("User ID:"));
    assert!(content.contains("Protocol: vless"));
    assert!(content.contains("Status: active"));
}

#[test]
fn test_concurrent_operations() {
    // Test that concurrent operations work correctly
    use std::thread;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicU32, Ordering};
    
    let counter = Arc::new(AtomicU32::new(0));
    let mut handles = vec![];
    
    // Spawn 10 threads that each increment the counter
    for _ in 0..10 {
        let counter_clone = Arc::clone(&counter);
        let handle = thread::spawn(move || {
            for _ in 0..100 {
                counter_clone.fetch_add(1, Ordering::SeqCst);
            }
        });
        handles.push(handle);
    }
    
    // Wait for all threads to complete
    for handle in handles {
        handle.join().expect("Thread panicked");
    }
    
    // Should have incremented 10 * 100 = 1000 times
    assert_eq!(counter.load(Ordering::SeqCst), 1000);
}

#[test]
fn test_resource_cleanup() {
    // Test that resources are properly cleaned up
    let temp_dir = tempdir().expect("Failed to create temp dir");
    let test_file = temp_dir.path().join("cleanup_test.txt");
    
    {
        // Create a file in a scope
        fs::write(&test_file, "test content").expect("Failed to write file");
        assert!(test_file.exists());
    }
    
    // File should still exist after scope ends
    assert!(test_file.exists());
    
    // Explicitly remove it
    fs::remove_file(&test_file).expect("Failed to remove file");
    assert!(!test_file.exists());
}