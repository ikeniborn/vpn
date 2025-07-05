use crate::container::ContainerManager;
use crate::error::{DockerError, Result};
use bollard::container::StatsOptions;
use bollard::models::ContainerStateStatusEnum;
use bollard::Docker;
use futures_util::stream::StreamExt;
use std::collections::HashMap;
use std::time::Duration;
use tokio::task::JoinSet;

/// Health status information for a Docker container
///
/// Contains comprehensive health and performance metrics for a container
/// including resource usage, network statistics, and operational status.
#[derive(Debug, Clone)]
pub struct HealthStatus {
    /// Name or ID of the container
    pub container_name: String,
    /// Whether the container is currently running
    pub is_running: bool,
    /// Current container status (running, stopped, paused, etc.)
    pub status: String,
    /// CPU usage as a percentage (0.0 - 100.0)
    pub cpu_usage: f64,
    /// Current memory usage in bytes
    pub memory_usage: u64,
    /// Memory limit in bytes (0 indicates no limit)
    pub memory_limit: u64,
    /// Network bytes received since container start
    pub network_rx_bytes: u64,
    /// Network bytes transmitted since container start
    pub network_tx_bytes: u64,
}

/// Result of a batch health check operation
///
/// Contains the results of checking multiple containers simultaneously,
/// with separate collections for successful and failed operations.
#[derive(Debug, Clone)]
pub struct BatchHealthResult {
    /// Successfully checked containers with their health status
    pub successful: HashMap<String, HealthStatus>,
    /// Failed container checks with error messages
    pub failed: HashMap<String, String>,
    /// Total time taken to complete all health checks
    pub total_duration: Duration,
}

/// Configuration options for batch health checking operations
///
/// Controls the behavior of concurrent health checks including timeouts,
/// concurrency limits, and failure handling strategies.
#[derive(Debug, Clone)]
pub struct BatchHealthOptions {
    /// Maximum time to wait for individual health checks
    pub timeout: Duration,
    /// Maximum number of concurrent health check operations
    pub max_concurrent: usize,
    /// Whether to stop all operations on first failure
    pub fail_fast: bool,
}

/// Docker container health monitoring service
///
/// Provides comprehensive health checking capabilities for Docker containers
/// including resource monitoring, performance metrics, and batch operations.
///
/// # Features
///
/// - Real-time container health status monitoring
/// - CPU, memory, and network usage statistics
/// - Concurrent batch health checking
/// - Memory leak prevention with proper resource cleanup
///
/// # Examples
///
/// ```rust,no_run
/// use vpn_docker::HealthChecker;
///
/// #[tokio::main]
/// async fn main() -> Result<(), Box<dyn std::error::Error>> {
///     let health_checker = HealthChecker::new()?;
///     
///     // Check single container health
///     let status = health_checker.check_container_health("vpn-server").await?;
///     println!("CPU usage: {}%", status.cpu_usage);
///     
///     // Batch check multiple containers
///     let containers = ["vpn-server", "traefik", "prometheus"];
///     let results = health_checker.batch_check_health(&containers, None).await;
///     println!("Checked {} containers", results.successful.len());
///     
///     Ok(())
/// }
/// ```
#[derive(Clone)]
pub struct HealthChecker {
    docker: Docker,
    container_manager: ContainerManager,
}

impl HealthChecker {
    /// Create a new health checker instance
    ///
    /// Initializes connections to the Docker daemon and container manager.
    ///
    /// # Returns
    ///
    /// Returns `Result<HealthChecker, DockerError>` where the error indicates
    /// issues with Docker daemon connectivity.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::HealthChecker;
    ///
    /// let checker = HealthChecker::new()?;
    /// # Ok::<(), vpn_docker::DockerError>(())
    /// ```
    pub fn new() -> Result<Self> {
        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| DockerError::ConnectionError(e.to_string()))?;
        let container_manager = ContainerManager::new()?;
        Ok(Self {
            docker,
            container_manager,
        })
    }

    /// Check the health status of a single container
    ///
    /// Retrieves comprehensive health information including running status,
    /// CPU usage, memory consumption, and network statistics.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to check
    ///
    /// # Returns
    ///
    /// Returns `Result<HealthStatus, DockerError>` containing the health status
    /// or an error if the container cannot be found or checked.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::HealthChecker;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let checker = HealthChecker::new()?;
    ///
    /// let status = checker.check_container_health("vpn-server").await?;
    /// println!("Container running: {}", status.is_running);
    /// println!("CPU usage: {:.1}%", status.cpu_usage);
    /// println!("Memory usage: {} MB", status.memory_usage / 1024 / 1024);
    /// # Ok(())
    /// # }
    /// ```
    pub async fn check_container_health(&self, name: &str) -> Result<HealthStatus> {
        let inspect = self.container_manager.inspect_container(name).await?;

        let state = inspect
            .state
            .as_ref()
            .ok_or_else(|| DockerError::HealthCheckFailed("No state information".to_string()))?;

        let is_running = matches!(state.status, Some(ContainerStateStatusEnum::RUNNING));

        let status = state
            .status
            .as_ref()
            .map(|s| format!("{:?}", s))
            .unwrap_or_else(|| "unknown".to_string());

        let stats = self.get_container_stats(name).await?;

        Ok(HealthStatus {
            container_name: name.to_string(),
            is_running,
            status,
            cpu_usage: stats.0,
            memory_usage: stats.1,
            memory_limit: stats.2,
            network_rx_bytes: stats.3,
            network_tx_bytes: stats.4,
        })
    }

    async fn get_container_stats(&self, name: &str) -> Result<(f64, u64, u64, u64, u64)> {
        let options = StatsOptions {
            stream: false,
            one_shot: true,
        };

        let mut stream = self.docker.stats(name, Some(options));

        if let Some(Ok(stats)) = stream.next().await {
            // Explicitly drop the stream to ensure resources are freed
            drop(stream);

            let cpu_usage = calculate_cpu_percentage(&stats);

            let memory_stats = &stats.memory_stats;

            let memory_usage = memory_stats.usage.unwrap_or(0);
            let memory_limit = memory_stats.limit.unwrap_or(0);

            let (rx_bytes, tx_bytes) = if let Some(networks) = &stats.networks {
                let rx: u64 = networks.values().map(|n| n.rx_bytes).sum();
                let tx: u64 = networks.values().map(|n| n.tx_bytes).sum();
                (rx, tx)
            } else {
                (0, 0)
            };

            Ok((cpu_usage, memory_usage, memory_limit, rx_bytes, tx_bytes))
        } else {
            Err(DockerError::HealthCheckFailed(
                "Failed to get stats".to_string(),
            ))
        }
    }

    /// Wait for a container to become healthy within a timeout period
    ///
    /// Continuously checks container health until it becomes running or the timeout
    /// expires. This is useful for waiting for containers to start up properly.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to wait for
    /// * `timeout` - Maximum time to wait for the container to become healthy
    ///
    /// # Returns
    ///
    /// Returns `Result<(), DockerError>` indicating success or timeout/error.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::HealthChecker;
    /// use std::time::Duration;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let checker = HealthChecker::new()?;
    ///
    /// // Wait up to 60 seconds for container to become healthy
    /// checker.wait_for_healthy("vpn-server", Duration::from_secs(60)).await?;
    /// println!("Container is now healthy!");
    /// # Ok(())
    /// # }
    /// ```
    pub async fn wait_for_healthy(&self, name: &str, timeout: Duration) -> Result<()> {
        let start = std::time::Instant::now();

        while start.elapsed() < timeout {
            match self.check_container_health(name).await {
                Ok(status) if status.is_running => return Ok(()),
                _ => tokio::time::sleep(Duration::from_secs(1)).await,
            }
        }

        Err(DockerError::HealthCheckFailed(format!(
            "Container {} did not become healthy within {:?}",
            name, timeout
        )))
    }

    /// Wait for multiple containers to become healthy concurrently
    pub async fn wait_for_multiple_healthy(
        &self,
        names: &[&str],
        timeout: Duration,
    ) -> HashMap<String, Result<()>> {
        let mut tasks = JoinSet::new();

        // Spawn concurrent wait tasks
        for name in names {
            let name = name.to_string();
            let health_checker = self.clone();

            tasks.spawn(async move {
                let result = health_checker.wait_for_healthy(&name, timeout).await;
                (name, result)
            });
        }

        let mut results = HashMap::new();

        // Collect results
        while let Some(task_result) = tasks.join_next().await {
            if let Ok((name, result)) = task_result {
                results.insert(name, result);
            }
        }

        results
    }

    pub async fn check_multiple_containers(&self, names: &[&str]) -> Vec<Result<HealthStatus>> {
        let mut results = Vec::new();

        for name in names {
            results.push(self.check_container_health(name).await);
        }

        results
    }

    /// Concurrent health check for multiple containers with batching
    pub async fn batch_health_check(
        &self,
        names: &[&str],
        options: Option<BatchHealthOptions>,
    ) -> BatchHealthResult {
        let start_time = std::time::Instant::now();
        let options = options.unwrap_or_default();

        let mut successful = HashMap::new();
        let mut failed = HashMap::new();

        // Create a semaphore to limit concurrent operations
        let semaphore = std::sync::Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));
        let mut tasks = JoinSet::new();

        // Spawn concurrent health check tasks
        for name in names {
            let name = name.to_string();
            let health_checker = self.clone();
            let permit = semaphore.clone();
            let timeout = options.timeout;

            tasks.spawn(async move {
                let _permit = permit.acquire().await.expect("Semaphore closed");

                // Use timeout for individual health checks
                let result =
                    tokio::time::timeout(timeout, health_checker.check_container_health(&name))
                        .await;

                match result {
                    Ok(Ok(health_status)) => Ok((name, health_status)),
                    Ok(Err(e)) => Err((name, e.to_string())),
                    Err(_) => Err((name, format!("Health check timed out after {:?}", timeout))),
                }
            });
        }

        // Collect results as they complete
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok((name, health_status))) => {
                    successful.insert(name, health_status);
                }
                Ok(Err((name, error))) => {
                    failed.insert(name.clone(), error);

                    // Fail fast if requested and we have any failure
                    if options.fail_fast {
                        // Cancel remaining tasks
                        tasks.abort_all();
                        break;
                    }
                }
                Err(join_error) => {
                    failed.insert(
                        "unknown".to_string(),
                        format!("Task join error: {}", join_error),
                    );
                }
            }
        }

        BatchHealthResult {
            successful,
            failed,
            total_duration: start_time.elapsed(),
        }
    }

    /// Concurrent health check with simplified API that returns Results
    pub async fn check_multiple_containers_concurrent(
        &self,
        names: &[&str],
    ) -> Vec<Result<HealthStatus>> {
        let batch_result = self
            .batch_health_check(
                names,
                Some(BatchHealthOptions {
                    timeout: Duration::from_secs(30),
                    max_concurrent: 10,
                    fail_fast: false,
                }),
            )
            .await;

        // Convert to the expected Vec<Result<HealthStatus>> format
        let mut results = Vec::with_capacity(names.len());

        for name in names {
            if let Some(health_status) = batch_result.successful.get(*name) {
                results.push(Ok(health_status.clone()));
            } else if let Some(error) = batch_result.failed.get(*name) {
                results.push(Err(DockerError::HealthCheckFailed(error.clone())));
            } else {
                results.push(Err(DockerError::HealthCheckFailed(
                    "Container not found in batch results".to_string(),
                )));
            }
        }

        results
    }

    /// Batch health check for multiple containers with streaming results
    pub async fn stream_batch_health_checks(
        &self,
        names: Vec<String>,
        options: Option<BatchHealthOptions>,
    ) -> tokio::sync::mpsc::Receiver<(String, Result<HealthStatus>)> {
        let (tx, rx) = tokio::sync::mpsc::channel(100);
        let options = options.unwrap_or_default();

        let health_checker = self.clone();

        tokio::spawn(async move {
            let semaphore =
                std::sync::Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));
            let mut tasks = JoinSet::new();

            // Spawn tasks for each container
            for name in names {
                let tx = tx.clone();
                let health_checker = health_checker.clone();
                let permit = semaphore.clone();
                let timeout = options.timeout;

                tasks.spawn(async move {
                    let _permit = permit.acquire().await.expect("Semaphore closed");

                    let result =
                        tokio::time::timeout(timeout, health_checker.check_container_health(&name))
                            .await;

                    let health_result = match result {
                        Ok(Ok(health_status)) => Ok(health_status),
                        Ok(Err(e)) => Err(e),
                        Err(_) => Err(DockerError::HealthCheckFailed(format!(
                            "Health check timed out after {:?}",
                            timeout
                        ))),
                    };

                    let _ = tx.send((name, health_result)).await;
                });
            }

            // Wait for all tasks to complete
            while tasks.join_next().await.is_some() {}
        });

        rx
    }
}

impl Default for BatchHealthOptions {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(30),
            max_concurrent: 10,
            fail_fast: false,
        }
    }
}

fn calculate_cpu_percentage(stats: &bollard::container::Stats) -> f64 {
    let cpu_stats = &stats.cpu_stats;

    let precpu_stats = &stats.precpu_stats;

    let cpu_usage = cpu_stats.cpu_usage.total_usage as f64;

    let precpu_usage = precpu_stats.cpu_usage.total_usage as f64;

    let system_cpu = cpu_stats.system_cpu_usage.unwrap_or(0) as f64;
    let presystem_cpu = precpu_stats.system_cpu_usage.unwrap_or(0) as f64;

    let cpu_delta = cpu_usage - precpu_usage;
    let system_delta = system_cpu - presystem_cpu;

    if system_delta > 0.0 && cpu_delta > 0.0 {
        let cpu_count = cpu_stats.online_cpus.unwrap_or(1) as f64;
        (cpu_delta / system_delta) * cpu_count * 100.0
    } else {
        0.0
    }
}
