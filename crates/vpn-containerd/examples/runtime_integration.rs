use vpn_containerd::ContainerdFactory;
use vpn_runtime::{RuntimeConfig, RuntimeType, ContainerdConfig, ContainerRuntime};
use std::sync::Arc;

/// Example showing how to integrate containerd runtime with the abstract factory
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("=== Containerd Runtime Integration Example ===\n");

    // Check if containerd is available
    let available = ContainerdFactory::is_available().await;
    println!("Containerd available: {}", available);

    if !available {
        println!("Containerd is not available on this system. Exiting...");
        return Ok(());
    }

    // Create runtime configuration
    let config = RuntimeConfig {
        runtime_type: RuntimeType::Containerd,
        containerd: Some(ContainerdConfig {
            socket_path: "/run/containerd/containerd.sock".to_string(),
            namespace: "default".to_string(),
            timeout: std::time::Duration::from_secs(30),
        }),
        docker: None,
        fallback_enabled: false,
    };

    println!("Verifying containerd connection...");
    match ContainerdFactory::verify_connection(config.clone()).await {
        Ok(version) => println!("✓ Connected to containerd version: {}", version),
        Err(e) => {
            println!("✗ Failed to connect to containerd: {}", e);
            return Ok(());
        }
    }

    println!("\nCreating containerd runtime instance...");
    match ContainerdFactory::create_runtime(config).await {
        Ok(runtime) => {
            println!("✓ Successfully created containerd runtime");
            
            // Demonstrate runtime usage
            println!("\nRuntime capabilities:");
            let version = runtime.version().await?;
            println!("  - Version: {}", version);
            
            let containers = runtime.list_containers().await?;
            println!("  - Container count: {}", containers.len());
            
            println!("\n=== Integration Complete ===");
        }
        Err(e) => {
            println!("✗ Failed to create containerd runtime: {}", e);
        }
    }

    Ok(())
}

/// Example of how an application might provide runtime selection
pub async fn create_runtime_with_fallback(
    preferred: RuntimeType,
) -> Result<Arc<dyn ContainerRuntime<
    Container = Box<dyn vpn_runtime::Container>,
    Task = Box<dyn vpn_runtime::Task>,
    Volume = Box<dyn vpn_runtime::Volume>,
    Image = Box<dyn vpn_runtime::Image>,
>>, vpn_runtime::RuntimeError> {
    match preferred {
        RuntimeType::Containerd => {
            if ContainerdFactory::is_available().await {
                let config = RuntimeConfig {
                    runtime_type: RuntimeType::Containerd,
                    containerd: Some(ContainerdConfig {
                        socket_path: "/run/containerd/containerd.sock".to_string(),
                        namespace: "default".to_string(),
                        timeout: std::time::Duration::from_secs(30),
                    }),
                    docker: None,
                    fallback_enabled: false,
                };
                
                // Note: This would require implementing the trait wrappers
                // For now, this shows the intended architecture
                todo!("Implement trait object wrappers for ContainerdRuntime")
            } else {
                Err(vpn_runtime::RuntimeError::NoRuntimeAvailable)
            }
        }
        _ => Err(vpn_runtime::RuntimeError::ConfigError {
            message: "Only containerd runtime implemented in this example".to_string(),
        }),
    }
}