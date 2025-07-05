// use bollard::Docker; // No longer needed, using connection pool
use crate::cache::get_container_cache;
use crate::error::{DockerError, Result};
use crate::pool::get_docker_connection;
use bollard::container::{
    Config, CreateContainerOptions, RemoveContainerOptions, StartContainerOptions,
    StopContainerOptions,
};
use bollard::exec::{CreateExecOptions, StartExecResults};
use bollard::models::{ContainerInspectResponse, ContainerSummary};
use futures_util::stream::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;
use tokio::task::JoinSet;

/// Operations that can be performed on containers in batch mode
#[derive(Debug, Clone)]
pub enum ContainerOperation {
    /// Start a container
    Start(String),
    /// Stop a container with optional timeout in seconds
    Stop(String, Option<i64>),
    /// Restart a container with optional timeout in seconds
    Restart(String, Option<i64>),
    /// Remove a container with force flag
    Remove(String, bool),
}

/// Result of a batch container operation
#[derive(Debug, Clone)]
pub struct BatchOperationResult {
    /// List of containers that were successfully processed
    pub successful: Vec<String>,
    /// Map of container names to error messages for failed operations
    pub failed: HashMap<String, String>,
    /// Total time taken for the batch operation
    pub total_duration: Duration,
}

/// Configuration options for batch operations
#[derive(Debug, Clone)]
pub struct BatchOperationOptions {
    /// Maximum number of concurrent operations (default: 5)
    pub max_concurrent: usize,
    /// Timeout for each individual operation
    pub timeout: Duration,
    /// Whether to stop on first failure (default: false)
    pub fail_fast: bool,
}

/// Configuration for creating and managing Docker containers
///
/// This struct provides a high-level interface for configuring Docker containers
/// with all necessary settings including networking, volumes, and environment.
///
/// # Examples
///
/// ```rust
/// use vpn_docker::ContainerConfig;
///
/// let mut config = ContainerConfig::new("my-vpn", "xray:latest");
/// config.add_port_mapping(8443, 8443);
/// config.add_environment_variable("LOG_LEVEL", "info");
/// config.add_volume_mount("/host/data", "/container/data");
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerConfig {
    /// Container name (must be unique)
    pub name: String,
    /// Docker image name and tag
    pub image: String,
    /// Port mappings: host_port -> container_port
    pub port_mappings: HashMap<u16, u16>,
    /// Environment variables to set in the container
    pub environment_variables: HashMap<String, String>,
    /// Volume mounts: host_path -> container_path
    pub volume_mounts: HashMap<String, String>,
    /// Docker restart policy (default: "unless-stopped")
    pub restart_policy: String,
    /// Networks to connect the container to
    pub networks: Vec<String>,
}

/// Current status of a Docker container
///
/// This enum represents all possible states a container can be in,
/// including error conditions and unknown states.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ContainerStatus {
    /// Container is running normally
    Running,
    /// Container is stopped
    Stopped,
    /// Container is paused
    Paused,
    /// Container is in the process of restarting
    Restarting,
    /// Container is being removed
    Removing,
    /// Container process is dead
    Dead,
    /// Container is created but not started
    Created,
    /// Container has exited with the given exit code
    Exited(i64),
    /// Container was not found
    NotFound,
    /// Container is in an error state
    Error(String),
    /// Container status is unknown
    Unknown(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerStats {
    pub cpu_usage_percent: f64,
    pub memory_usage_bytes: u64,
    pub memory_limit_bytes: u64,
    pub network_rx_bytes: u64,
    pub network_tx_bytes: u64,
    pub block_read_bytes: u64,
    pub block_write_bytes: u64,
    pub pids: u64,
}

// Alias for backward compatibility
pub type DockerManager = ContainerManager;

impl ContainerConfig {
    pub fn new(name: &str, image: &str) -> Self {
        Self {
            name: name.to_owned(),
            image: image.to_owned(),
            port_mappings: HashMap::new(),
            environment_variables: HashMap::new(),
            volume_mounts: HashMap::new(),
            restart_policy: "unless-stopped".to_owned(),
            networks: vec!["default".to_owned()],
        }
    }

    pub fn add_port_mapping(&mut self, host_port: u16, container_port: u16) {
        self.port_mappings.insert(host_port, container_port);
    }

    pub fn add_environment_variable(&mut self, key: &str, value: &str) {
        self.environment_variables
            .insert(key.to_owned(), value.to_owned());
    }

    pub fn add_volume_mount(&mut self, host_path: &str, container_path: &str) {
        self.volume_mounts
            .insert(host_path.to_owned(), container_path.to_owned());
    }

    pub fn set_restart_policy(&mut self, policy: &str) {
        self.restart_policy = policy.to_owned();
    }

    pub fn add_network(&mut self, network: &str) {
        if !self.networks.iter().any(|n| n == network) {
            self.networks.push(network.to_owned());
        }
    }

    // Builder-style methods for fluent API
    pub fn with_port_mapping(mut self, host_port: u16, container_port: u16) -> Self {
        self.add_port_mapping(host_port, container_port);
        self
    }

    pub fn with_environment_variable(mut self, key: &str, value: &str) -> Self {
        self.add_environment_variable(key, value);
        self
    }

    pub fn with_volume_mount(mut self, host_path: &str, container_path: &str) -> Self {
        self.add_volume_mount(host_path, container_path);
        self
    }

    pub fn with_restart_policy(mut self, policy: &str) -> Self {
        self.set_restart_policy(policy);
        self
    }

    pub fn with_network(mut self, network: &str) -> Self {
        self.add_network(network);
        self
    }
}

impl From<&str> for ContainerStatus {
    fn from(status: &str) -> Self {
        match status.to_lowercase().as_str() {
            "running" => ContainerStatus::Running,
            "stopped" => ContainerStatus::Stopped,
            "paused" => ContainerStatus::Paused,
            "restarting" => ContainerStatus::Restarting,
            "removing" => ContainerStatus::Removing,
            "dead" => ContainerStatus::Dead,
            "created" => ContainerStatus::Created,
            s if s.starts_with("exited") => {
                // Parse exit code from "exited (code)"
                let code = s
                    .strip_prefix("exited (")
                    .and_then(|s| s.strip_suffix(")"))
                    .and_then(|s| s.parse::<i64>().ok())
                    .unwrap_or(0);
                ContainerStatus::Exited(code)
            }
            _ => ContainerStatus::Unknown(status.to_string()),
        }
    }
}

impl Default for ContainerStats {
    fn default() -> Self {
        Self {
            cpu_usage_percent: 0.0,
            memory_usage_bytes: 0,
            memory_limit_bytes: 0,
            network_rx_bytes: 0,
            network_tx_bytes: 0,
            block_read_bytes: 0,
            block_write_bytes: 0,
            pids: 0,
        }
    }
}

impl ContainerStats {
    pub fn get_memory_usage_percent(&self) -> f64 {
        if self.memory_limit_bytes == 0 {
            0.0
        } else {
            (self.memory_usage_bytes as f64 / self.memory_limit_bytes as f64) * 100.0
        }
    }
}

impl std::fmt::Display for ContainerStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ContainerStatus::Running => write!(f, "running"),
            ContainerStatus::Stopped => write!(f, "stopped"),
            ContainerStatus::Paused => write!(f, "paused"),
            ContainerStatus::Restarting => write!(f, "restarting"),
            ContainerStatus::Removing => write!(f, "removing"),
            ContainerStatus::Dead => write!(f, "dead"),
            ContainerStatus::Created => write!(f, "created"),
            ContainerStatus::Exited(code) => write!(f, "exited({})", code),
            ContainerStatus::NotFound => write!(f, "not_found"),
            ContainerStatus::Error(msg) => write!(f, "error: {}", msg),
            ContainerStatus::Unknown(status) => write!(f, "unknown({})", status),
        }
    }
}

/// High-performance Docker container manager with connection pooling and caching
///
/// `ContainerManager` provides a comprehensive interface for managing Docker containers
/// with built-in performance optimizations including connection pooling and intelligent
/// caching to reduce Docker API overhead.
///
/// # Features
///
/// - **Connection Pooling**: Automatic connection reuse and management
/// - **Intelligent Caching**: Reduces redundant API calls for status and statistics
/// - **Batch Operations**: Efficient concurrent container operations
/// - **Health Monitoring**: Built-in health check and status monitoring
/// - **Error Handling**: Comprehensive error handling and recovery
///
/// # Examples
///
/// ## Basic Usage
///
/// ```rust,no_run
/// use vpn_docker::{ContainerManager, ContainerConfig};
///
/// #[tokio::main]
/// async fn main() -> Result<(), Box<dyn std::error::Error>> {
///     let manager = ContainerManager::new()?;
///     
///     // List all containers
///     let containers = manager.list_containers(true).await?;
///     println!("Found {} containers", containers.len());
///     
///     // Check container status (cached for performance)
///     let status = manager.get_container_status("my-container").await?;
///     println!("Container status: {}", status);
///     
///     Ok(())
/// }
/// ```
///
/// ## Batch Operations
///
/// ```rust,no_run
/// use vpn_docker::{ContainerManager, BatchOperationOptions};
/// use std::time::Duration;
///
/// # #[tokio::main]
/// # async fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let manager = ContainerManager::new()?;
///
/// let containers = ["container1", "container2", "container3"];
/// let options = Some(BatchOperationOptions {
///     max_concurrent: 3,
///     timeout: Duration::from_secs(30),
///     fail_fast: false,
/// });
///
/// let result = manager.batch_start_containers(&containers, options).await;
/// println!("Started {} containers, {} failed",
///          result.successful.len(), result.failed.len());
/// # Ok(())
/// # }
/// ```
#[derive(Clone)]
pub struct ContainerManager {
    // Uses connection pool instead of direct Docker connection for better performance
}

impl ContainerManager {
    /// Create a new container manager instance
    ///
    /// This initializes the connection pool and starts background cache cleanup tasks.
    /// The manager is lightweight and can be cloned efficiently.
    ///
    /// # Returns
    ///
    /// Returns a `Result<ContainerManager, DockerError>` where the error indicates
    /// issues with Docker daemon connectivity or initialization.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// let manager = ContainerManager::new()?;
    /// # Ok::<(), vpn_docker::DockerError>(())
    /// ```
    pub fn new() -> Result<Self> {
        // Initialize cache cleanup task
        crate::cache::start_cache_cleanup_task();
        Ok(Self {})
    }

    /// List all Docker containers with optional filtering
    ///
    /// Returns a list of containers based on the `all` parameter. When `all` is false,
    /// only running containers are returned. When true, all containers regardless of
    /// their state are included.
    ///
    /// # Arguments
    ///
    /// * `all` - If true, return all containers; if false, only running containers
    ///
    /// # Returns
    ///
    /// Returns `Result<Vec<ContainerSummary>, DockerError>` containing the list of containers
    /// or an error if the Docker API call fails.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// // List only running containers
    /// let running = manager.list_containers(false).await?;
    /// println!("Running containers: {}", running.len());
    ///
    /// // List all containers
    /// let all = manager.list_containers(true).await?;
    /// println!("Total containers: {}", all.len());
    /// # Ok(())
    /// # }
    /// ```
    pub async fn list_containers(&self, all: bool) -> Result<Vec<ContainerSummary>> {
        let mut filters = HashMap::new();
        if !all {
            filters.insert("status", vec!["running"]);
        }

        let options = bollard::container::ListContainersOptions {
            all,
            filters,
            ..Default::default()
        };

        let connection = get_docker_connection().await?;
        Ok(connection.docker().list_containers(Some(options)).await?)
    }

    /// Inspect a specific container and return detailed information
    ///
    /// Retrieves comprehensive information about a container including its configuration,
    /// state, network settings, and mount points. This is useful for debugging and
    /// monitoring container health.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to inspect
    ///
    /// # Returns
    ///
    /// Returns `Result<ContainerInspectResponse, DockerError>` containing detailed
    /// container information or `ContainerNotFound` error if the container doesn't exist.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// let info = manager.inspect_container("vpn-server").await?;
    /// if let Some(state) = &info.state {
    ///     println!("Container running: {}", state.running.unwrap_or(false));
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub async fn inspect_container(&self, name: &str) -> Result<ContainerInspectResponse> {
        let connection = get_docker_connection().await?;
        connection
            .docker()
            .inspect_container(name, None)
            .await
            .map_err(|_| DockerError::ContainerNotFound(name.to_owned()).into())
    }

    /// Create a new Docker container with the specified configuration
    ///
    /// Creates a new container using the provided Docker configuration. The container
    /// is only created, not started. Use `start_container()` to start it afterwards.
    ///
    /// # Arguments
    ///
    /// * `name` - Unique name for the container
    /// * `config` - Docker container configuration including image, ports, volumes, etc.
    ///
    /// # Returns
    ///
    /// Returns `Result<String, DockerError>` containing the created container ID
    /// or an error if the creation fails.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    /// use bollard::container::Config;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// let config = Config {
    ///     image: Some("xray:latest".to_string()),
    ///     ..Default::default()
    /// };
    ///
    /// let container_id = manager.create_container("vpn-server", config).await?;
    /// println!("Created container: {}", container_id);
    /// # Ok(())
    /// # }
    /// ```
    pub async fn create_container(&self, name: &str, config: Config<String>) -> Result<String> {
        let options = CreateContainerOptions {
            name,
            ..Default::default()
        };

        let connection = get_docker_connection().await?;
        let response = connection
            .docker()
            .create_container(Some(options), config)
            .await?;

        // Invalidate cache since container list has changed
        get_container_cache().invalidate_container(name).await;

        Ok(response.id)
    }

    /// Start a previously created container
    ///
    /// Starts a container that was previously created with `create_container()`.
    /// The cache is automatically invalidated to ensure status queries return
    /// fresh information.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to start
    ///
    /// # Returns
    ///
    /// Returns `Result<(), DockerError>` indicating success or failure.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// manager.start_container("vpn-server").await?;
    /// println!("Container started successfully");
    /// # Ok(())
    /// # }
    /// ```
    pub async fn start_container(&self, name: &str) -> Result<()> {
        let connection = get_docker_connection().await?;
        connection
            .docker()
            .start_container(name, None::<StartContainerOptions<String>>)
            .await?;

        // Invalidate cached status since container state changed
        get_container_cache().invalidate_container(name).await;

        Ok(())
    }

    /// Stop a running container with optional timeout
    ///
    /// Gracefully stops a running container by sending a SIGTERM signal followed by
    /// SIGKILL after the timeout period. The cache is automatically invalidated.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to stop
    /// * `timeout` - Optional timeout in seconds before force killing (default: 10)
    ///
    /// # Returns
    ///
    /// Returns `Result<(), DockerError>` indicating success or failure.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// // Stop with default timeout (10 seconds)
    /// manager.stop_container("vpn-server", None).await?;
    ///
    /// // Stop with custom timeout
    /// manager.stop_container("vpn-server", Some(30)).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn stop_container(&self, name: &str, timeout: Option<i64>) -> Result<()> {
        let options = StopContainerOptions {
            t: timeout.unwrap_or(10),
        };

        let connection = get_docker_connection().await?;
        connection
            .docker()
            .stop_container(name, Some(options))
            .await?;

        // Invalidate cached status since container state changed
        get_container_cache().invalidate_container(name).await;

        Ok(())
    }

    /// Restart a container by stopping and starting it
    ///
    /// Combines stop and start operations with the specified timeout. This is useful
    /// for applying configuration changes or recovering from container issues.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to restart
    /// * `timeout` - Optional timeout in seconds for the stop operation
    ///
    /// # Returns
    ///
    /// Returns `Result<(), DockerError>` indicating success or failure.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// manager.restart_container("vpn-server", Some(10)).await?;
    /// println!("Container restarted successfully");
    /// # Ok(())
    /// # }
    /// ```
    pub async fn restart_container(&self, name: &str, timeout: Option<i64>) -> Result<()> {
        self.stop_container(name, timeout).await?;
        self.start_container(name).await?;
        Ok(())
    }

    /// Remove a container and optionally its volumes
    ///
    /// Permanently removes a container and optionally associated volumes. Use force=true
    /// to remove running containers. The cache is automatically invalidated.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to remove
    /// * `force` - If true, forcefully remove even if running
    ///
    /// # Returns
    ///
    /// Returns `Result<(), DockerError>` indicating success or failure.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// // Remove stopped container
    /// manager.remove_container("old-container", false).await?;
    ///
    /// // Force remove running container
    /// manager.remove_container("vpn-server", true).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn remove_container(&self, name: &str, force: bool) -> Result<()> {
        let options = RemoveContainerOptions {
            force,
            v: true,
            ..Default::default()
        };

        let connection = get_docker_connection().await?;
        connection
            .docker()
            .remove_container(name, Some(options))
            .await?;

        // Invalidate cache since container has been removed
        get_container_cache().invalidate_container(name).await;

        Ok(())
    }

    /// Get container status with caching for better performance
    pub async fn get_container_status(&self, name: &str) -> Result<ContainerStatus> {
        // Check cache first
        if let Some(cached_status) = get_container_cache().get_status(name).await {
            return Ok(cached_status);
        }

        // Fetch from Docker API if not cached
        let status = match self.inspect_container(name).await {
            Ok(info) => {
                if let Some(state) = info.state {
                    if state.running.unwrap_or(false) {
                        ContainerStatus::Running
                    } else if state.paused.unwrap_or(false) {
                        ContainerStatus::Paused
                    } else if state.restarting.unwrap_or(false) {
                        ContainerStatus::Restarting
                    } else if state.dead.unwrap_or(false) {
                        ContainerStatus::Dead
                    } else if let Some(exit_code) = state.exit_code {
                        ContainerStatus::Exited(exit_code)
                    } else {
                        ContainerStatus::Stopped
                    }
                } else {
                    ContainerStatus::Unknown("No state information".to_owned())
                }
            }
            Err(_) => ContainerStatus::NotFound,
        };

        // Cache the result
        get_container_cache()
            .cache_status(name, status.clone())
            .await;

        Ok(status)
    }

    /// Execute a command inside a running container
    ///
    /// Runs a command inside the specified container and returns the output.
    /// This is useful for debugging, configuration changes, or health checks.
    ///
    /// # Arguments
    ///
    /// * `container` - The container name or ID to execute the command in
    /// * `cmd` - Vector of command and arguments to execute
    ///
    /// # Returns
    ///
    /// Returns `Result<String, DockerError>` containing the command output
    /// or an error if execution fails.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// // Execute a simple command
    /// let output = manager.exec_command("vpn-server", vec!["ps", "aux"]).await?;
    /// println!("Process list: {}", output);
    ///
    /// // Check configuration
    /// let config = manager.exec_command("vpn-server", vec!["cat", "/etc/xray/config.json"]).await?;
    /// println!("Config: {}", config);
    /// # Ok(())
    /// # }
    /// ```
    pub async fn exec_command(&self, container: &str, cmd: Vec<&str>) -> Result<String> {
        let exec_options = CreateExecOptions {
            attach_stdout: Some(true),
            attach_stderr: Some(true),
            cmd: Some(cmd),
            ..Default::default()
        };

        let connection = get_docker_connection().await?;
        let exec = connection
            .docker()
            .create_exec(container, exec_options)
            .await?;

        if let StartExecResults::Attached { mut output, .. } =
            connection.docker().start_exec(&exec.id, None).await?
        {
            let mut result = String::new();
            while let Some(Ok(msg)) = output.next().await {
                result.push_str(&msg.to_string());
            }
            Ok(result)
        } else {
            Err(DockerError::ApiError(
                bollard::errors::Error::DockerResponseServerError {
                    status_code: 500,
                    message: "Failed to attach to exec".to_owned(),
                },
            ))
        }
    }

    /// Check if a container exists
    ///
    /// Quickly checks whether a container with the given name exists.
    /// This is a lightweight operation that doesn't return detailed information.
    ///
    /// # Arguments
    ///
    /// * `name` - The container name or ID to check
    ///
    /// # Returns
    ///
    /// Returns `true` if the container exists, `false` otherwise.
    ///
    /// # Examples
    ///
    /// ```rust,no_run
    /// use vpn_docker::ContainerManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ContainerManager::new()?;
    ///
    /// if manager.container_exists("vpn-server").await {
    ///     println!("Container exists");
    /// } else {
    ///     println!("Container not found");
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub async fn container_exists(&self, name: &str) -> bool {
        self.inspect_container(name).await.is_ok()
    }

    /// Execute multiple container operations concurrently with batching
    pub async fn batch_container_operations(
        &self,
        operations: Vec<ContainerOperation>,
        options: Option<BatchOperationOptions>,
    ) -> BatchOperationResult {
        let start_time = std::time::Instant::now();
        let options = options.unwrap_or_default();

        let mut successful = Vec::new();
        let mut failed = HashMap::new();

        // Create semaphore to limit concurrent operations
        let semaphore = std::sync::Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));
        let mut tasks = JoinSet::new();

        // Spawn concurrent operation tasks
        for operation in operations {
            let container_manager = self.clone();
            let permit = semaphore.clone();
            let timeout = options.timeout;

            tasks.spawn(async move {
                let _permit = permit.acquire().await.expect("Semaphore closed");

                // Apply timeout to individual operations
                let result = tokio::time::timeout(
                    timeout,
                    container_manager.execute_single_operation(operation.clone()),
                )
                .await;

                match result {
                    Ok(Ok(_)) => Ok(operation.container_name()),
                    Ok(Err(e)) => Err((operation.container_name(), e.to_string())),
                    Err(_) => Err((
                        operation.container_name(),
                        format!("Operation timed out after {:?}", timeout),
                    )),
                }
            });
        }

        // Collect results as they complete
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok(container_name)) => {
                    successful.push(container_name);
                }
                Ok(Err((container_name, error))) => {
                    failed.insert(container_name.clone(), error);

                    // Fail fast if requested
                    if options.fail_fast {
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

        BatchOperationResult {
            successful,
            failed,
            total_duration: start_time.elapsed(),
        }
    }

    /// Execute a single container operation
    async fn execute_single_operation(&self, operation: ContainerOperation) -> Result<()> {
        match operation {
            ContainerOperation::Start(name) => self.start_container(&name).await,
            ContainerOperation::Stop(name, timeout) => self.stop_container(&name, timeout).await,
            ContainerOperation::Restart(name, timeout) => {
                self.restart_container(&name, timeout).await
            }
            ContainerOperation::Remove(name, force) => self.remove_container(&name, force).await,
        }
    }

    /// Batch start multiple containers
    pub async fn batch_start_containers(
        &self,
        names: &[&str],
        options: Option<BatchOperationOptions>,
    ) -> BatchOperationResult {
        let operations = names
            .iter()
            .map(|name| ContainerOperation::Start(name.to_string()))
            .collect();

        self.batch_container_operations(operations, options).await
    }

    /// Batch stop multiple containers
    pub async fn batch_stop_containers(
        &self,
        names: &[&str],
        timeout: Option<i64>,
        options: Option<BatchOperationOptions>,
    ) -> BatchOperationResult {
        let operations = names
            .iter()
            .map(|name| ContainerOperation::Stop(name.to_string(), timeout))
            .collect();

        self.batch_container_operations(operations, options).await
    }

    /// Batch restart multiple containers
    pub async fn batch_restart_containers(
        &self,
        names: &[&str],
        timeout: Option<i64>,
        options: Option<BatchOperationOptions>,
    ) -> BatchOperationResult {
        let operations = names
            .iter()
            .map(|name| ContainerOperation::Restart(name.to_string(), timeout))
            .collect();

        self.batch_container_operations(operations, options).await
    }

    /// Batch restart with dependency management
    /// Groups are processed sequentially, but containers within each group are processed concurrently
    pub async fn batch_restart_with_dependencies(
        &self,
        container_groups: Vec<Vec<&str>>,
        timeout: Option<i64>,
        options: Option<BatchOperationOptions>,
    ) -> Vec<BatchOperationResult> {
        let mut results = Vec::new();

        for group in container_groups {
            let result = self
                .batch_restart_containers(&group, timeout, options.clone())
                .await;
            results.push(result);

            // Add a small delay between dependency groups
            tokio::time::sleep(Duration::from_secs(2)).await;
        }

        results
    }
}

impl ContainerOperation {
    pub fn container_name(&self) -> String {
        match self {
            ContainerOperation::Start(name) => name.clone(),
            ContainerOperation::Stop(name, _) => name.clone(),
            ContainerOperation::Restart(name, _) => name.clone(),
            ContainerOperation::Remove(name, _) => name.clone(),
        }
    }
}

impl Default for BatchOperationOptions {
    fn default() -> Self {
        Self {
            max_concurrent: 5,
            timeout: Duration::from_secs(60),
            fail_fast: false,
        }
    }
}
