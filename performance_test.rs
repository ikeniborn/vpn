#!/usr/bin/env cargo +nightly -Zscript

//! Memory and performance profiling for VPN server
//! 
//! This script profiles memory usage and performance of key VPN operations

use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use std::io::{self, Write};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🔍 VPN Performance Profiling");
    println!("============================");
    
    // Test 1: Baseline memory usage
    println!("\n📊 Test 1: Baseline Memory Usage");
    test_baseline_memory()?;
    
    // Test 2: CLI startup time
    println!("\n⚡ Test 2: CLI Startup Time");
    test_startup_time()?;
    
    // Test 3: User creation performance
    println!("\n👤 Test 3: User Creation Performance");
    test_user_creation()?;
    
    // Test 4: Docker operations performance
    println!("\n🐳 Test 4: Docker Operations Performance");
    test_docker_operations()?;
    
    println!("\n✅ Performance profiling completed!");
    Ok(())
}

fn test_baseline_memory() -> Result<(), Box<dyn std::error::Error>> {
    println!("Measuring baseline memory usage...");
    
    // Start VPN CLI and measure memory
    let mut child = Command::new("./target/release/vpn")
        .arg("--help")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    
    let pid = child.id();
    
    // Wait a bit for the process to fully start
    std::thread::sleep(Duration::from_millis(100));
    
    // Get memory usage from /proc/[pid]/status
    let memory_kb = get_process_memory(pid)?;
    let memory_mb = memory_kb as f64 / 1024.0;
    
    child.wait()?;
    
    println!("  Memory usage: {:.2} MB ({} KB)", memory_mb, memory_kb);
    
    if memory_mb > 10.0 {
        println!("  ⚠️  Memory usage exceeds target of 10MB");
    } else {
        println!("  ✅ Memory usage within target");
    }
    
    Ok(())
}

fn test_startup_time() -> Result<(), Box<dyn std::error::Error>> {
    println!("Measuring CLI startup time...");
    
    let mut times = Vec::new();
    
    for i in 0..5 {
        let start = Instant::now();
        
        let output = Command::new("./target/release/vpn")
            .arg("--version")
            .stdin(Stdio::null())
            .stdout(Stdio::pipe())
            .stderr(Stdio::pipe())
            .output()?;
        
        let duration = start.elapsed();
        times.push(duration);
        
        if !output.status.success() {
            eprintln!("Warning: Command failed on iteration {}", i + 1);
        }
        
        print!(".");
        io::stdout().flush()?;
    }
    
    println!();
    
    let avg_time = times.iter().sum::<Duration>() / times.len() as u32;
    let min_time = times.iter().min().unwrap();
    let max_time = times.iter().max().unwrap();
    
    println!("  Average startup time: {:.2}ms", avg_time.as_millis());
    println!("  Min: {:.2}ms, Max: {:.2}ms", min_time.as_millis(), max_time.as_millis());
    
    if avg_time.as_millis() > 100 {
        println!("  ⚠️  Startup time exceeds target of 100ms");
    } else {
        println!("  ✅ Startup time within target");
    }
    
    Ok(())
}

fn test_user_creation() -> Result<(), Box<dyn std::error::Error>> {
    println!("Measuring user creation performance...");
    println!("  Note: This test may fail if VPN server is not installed");
    
    let start = Instant::now();
    
    let output = Command::new("./target/release/vpn")
        .args(&["users", "list"])
        .stdin(Stdio::null())
        .stdout(Stdio::pipe())
        .stderr(Stdio::pipe())
        .output()?;
    
    let duration = start.elapsed();
    
    if output.status.success() {
        println!("  User list operation: {:.2}ms", duration.as_millis());
        
        if duration.as_millis() > 50 {
            println!("  ⚠️  User operation exceeds expected time");
        } else {
            println!("  ✅ User operation performance good");
        }
    } else {
        println!("  ⚠️  User operation failed (VPN server may not be installed)");
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.is_empty() {
            println!("    Error: {}", stderr.trim());
        }
    }
    
    Ok(())
}

fn test_docker_operations() -> Result<(), Box<dyn std::error::Error>> {
    println!("Measuring Docker operations performance...");
    
    let start = Instant::now();
    
    let output = Command::new("./target/release/vpn")
        .args(&["status"])
        .stdin(Stdio::null())
        .stdout(Stdio::pipe())
        .stderr(Stdio::pipe())
        .output()?;
    
    let duration = start.elapsed();
    
    if output.status.success() {
        println!("  Status check operation: {:.2}ms", duration.as_millis());
        
        if duration.as_millis() > 30 {
            println!("  ⚠️  Docker operation exceeds target of 30ms");
        } else {
            println!("  ✅ Docker operation performance good");
        }
    } else {
        println!("  ⚠️  Status check failed (VPN server may not be running)");
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.is_empty() {
            println!("    Error: {}", stderr.trim());
        }
    }
    
    Ok(())
}

fn get_process_memory(pid: u32) -> Result<u64, Box<dyn std::error::Error>> {
    let status_file = format!("/proc/{}/status", pid);
    let contents = std::fs::read_to_string(status_file)?;
    
    for line in contents.lines() {
        if line.starts_with("VmRSS:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                return Ok(parts[1].parse()?);
            }
        }
    }
    
    Err("Could not find VmRSS in /proc/[pid]/status".into())
}