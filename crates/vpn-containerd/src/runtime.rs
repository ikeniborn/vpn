use crate::{
    ContainerdContainer, ContainerdError, ContainerdImage, ContainerdTask, ContainerdVolume,
    ProcessSpec, Result as ContainerdResult,
};
use async_trait::async_trait;
// use chrono::Utc; // Unused currently
use containerd_client::{connect, services::v1::version_client::VersionClient};
use futures_util::StreamExt;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tonic::transport::Channel;
use tracing::{debug, info}; // error, warn unused currently
use vpn_runtime::{
    BatchOperations, BatchOptions, BatchResult, CompleteRuntime, ContainerFilter,
    ContainerRuntime, ContainerSpec, ContainerStats, EventOperations, EventStream, ExecResult,
    HealthOperations, ImageFilter, ImageOperations, LogOptions, LogStream, RuntimeConfig,
    RuntimeError, RuntimeInfo, Task, VolumeFilter, VolumeOperations, VolumeSpec, // Image, Volume unused
};

use crate::{
    containers::ContainerManager, 
    events::EventManager,
    health::HealthMonitor,
    images::ImageManager, 
    logs::LogManager,
    stats::StatsCollector,
    // snapshots::SnapshotManager, // Disabled
    tasks::TaskManager,
};

/// Main containerd runtime implementation
pub struct ContainerdRuntime {
    channel: Channel,
    namespace: String,
    snapshotter: String,
    container_manager: Arc<RwLock<ContainerManager>>,
    task_manager: Arc<RwLock<TaskManager>>,
    image_manager: Arc<RwLock<ImageManager>>,
    event_manager: Arc<RwLock<EventManager>>,
    log_manager: Arc<RwLock<LogManager>>,
    health_monitor: Arc<RwLock<HealthMonitor>>,
    stats_collector: Arc<RwLock<StatsCollector>>,
    // snapshot_manager: Arc<RwLock<SnapshotManager>>, // Disabled due to missing APIs
    config: RuntimeConfig,
}

impl ContainerdRuntime {
    /// Create a new containerd runtime instance
    pub async fn new(config: RuntimeConfig) -> ContainerdResult<Self> {
        let socket_path = config.effective_socket_path();
        let namespace = config.effective_namespace();
        let snapshotter = config
            .containerd
            .as_ref()
            .map(|c| c.snapshotter.clone())
            .unwrap_or_else(|| "overlayfs".to_string());

        debug!("Connecting to containerd at: {}", socket_path);
        
        let channel = connect(&socket_path)
            .await
            .map_err(|e| ContainerdError::ConnectionError {
                message: format!("Failed to connect to containerd: {}", e),
            })?;

        // Test the connection
        let mut version_client = VersionClient::new(channel.clone());
        let version = version_client
            .version(())
            .await
            .map_err(|e| ContainerdError::ConnectionError {
                message: format!("Failed to get version: {}", e),
            })?;

        info!(
            "Connected to containerd version: {}",
            version.get_ref().version
        );

        Ok(Self {
            container_manager: Arc::new(RwLock::new(ContainerManager::new(
                channel.clone(),
                namespace.clone(),
            ))),
            task_manager: Arc::new(RwLock::new(TaskManager::new(
                channel.clone(),
                namespace.clone(),
            ))),
            image_manager: Arc::new(RwLock::new(ImageManager::new(
                channel.clone(),
                namespace.clone(),
            ))),
            event_manager: Arc::new(RwLock::new(EventManager::new(
                channel.clone(),
                namespace.clone(),
            ))),
            log_manager: Arc::new(RwLock::new(LogManager::new(
                namespace.clone(),
                "/var/log/containerd".to_string(), // Default log path
            ))),
            health_monitor: Arc::new(RwLock::new(HealthMonitor::new(
                channel.clone(),
                namespace.clone(),
            ))),
            stats_collector: Arc::new(RwLock::new(StatsCollector::new(
                channel.clone(),
                namespace.clone(),
            ))),
            // snapshot_manager: Arc::new(RwLock::new(SnapshotManager::new(
            //     channel.clone(),
            //     namespace.clone(),
            //     snapshotter.clone(),
            // ))), // Disabled due to missing APIs
            channel,
            namespace,
            snapshotter,
            config,
        })
    }

    /// Get the current namespace
    pub fn namespace(&self) -> &str {
        &self.namespace
    }

    /// Get the current snapshotter
    pub fn snapshotter(&self) -> &str {
        &self.snapshotter
    }
}

#[async_trait]
impl ContainerRuntime for ContainerdRuntime {
    type Container = ContainerdContainer;
    type Task = ContainerdTask;
    type Volume = ContainerdVolume;
    type Image = ContainerdImage;

    async fn connect(config: RuntimeConfig) -> std::result::Result<Self, RuntimeError>
    where
        Self: Sized,
    {
        ContainerdRuntime::new(config)
            .await
            .map_err(|e| RuntimeError::from(e))
    }

    async fn disconnect(&mut self) -> std::result::Result<(), RuntimeError> {
        debug!("Disconnecting from containerd");
        // containerd gRPC connections are closed automatically when dropped
        Ok(())
    }

    async fn ping(&self) -> std::result::Result<(), RuntimeError> {
        let mut version_client = VersionClient::new(self.channel.clone());
        version_client
            .version(())
            .await
            .map_err(|e| RuntimeError::ConnectionError {
                message: format!("Ping failed: {}", e),
            })?;
        Ok(())
    }

    async fn create_container(&self, spec: ContainerSpec) -> Result<Self::Container, RuntimeError> {
        let mut manager = self.container_manager.write().await;
        manager
            .create_container(spec)
            .await
            .map_err(|e| RuntimeError::from(ContainerdError::from(e)))
    }

    async fn list_containers(
        &self,
        filter: ContainerFilter,
    ) -> Result<Vec<Self::Container>, RuntimeError> {
        let mut manager = self.container_manager.write().await;
        manager
            .list_containers(filter)
            .await
            .map_err(|e| RuntimeError::from(ContainerdError::from(e)))
    }

    async fn get_container(&self, id: &str) -> Result<Self::Container, RuntimeError> {
        let mut manager = self.container_manager.write().await;
        manager.get_container(id).await.map_err(|e| e.into())
    }

    async fn remove_container(&self, id: &str, _force: bool) -> Result<(), RuntimeError> {
        let mut manager = self.container_manager.write().await;
        manager.remove_container(id).await.map_err(|e| e.into())
    }

    async fn start_container(&self, id: &str) -> Result<Self::Task, RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager
            .start_container(id)
            .await
            .map_err(|e| RuntimeError::from(ContainerdError::from(e)))
    }

    async fn stop_container(
        &self,
        id: &str,
        timeout: Option<Duration>,
    ) -> Result<(), RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager
            .stop_container(id, timeout)
            .await
            .map_err(|e| RuntimeError::from(ContainerdError::from(e)))
    }

    async fn restart_container(
        &self,
        id: &str,
        timeout: Option<Duration>,
    ) -> Result<(), RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager
            .restart_container(id, timeout)
            .await
            .map(|_| ())
            .map_err(|e| RuntimeError::from(ContainerdError::from(e)))
    }

    async fn pause_container(&self, id: &str) -> Result<(), RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager.pause_task(id).await.map_err(|e| e.into())
    }

    async fn unpause_container(&self, id: &str) -> Result<(), RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager.resume_task(id).await.map_err(|e| e.into())
    }

    async fn get_task(&self, container_id: &str) -> Result<Self::Task, RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager.get_task(container_id).await.map_err(|e| e.into())
    }

    async fn get_stats(&self, id: &str) -> Result<ContainerStats, RuntimeError> {
        let mut stats_collector = self.stats_collector.write().await;
        
        // Add container to collection if not already present
        if stats_collector.get_current_stats(id).is_none() {
            stats_collector.add_container(id.to_string());
        }
        
        // Collect current statistics
        match stats_collector.collect_container_stats(id).await {
            Ok(containerd_stats) => Ok(containerd_stats.into()),
            Err(_) => {
                // Fall back to placeholder stats
                Ok(ContainerStats {
                    cpu_percent: 0.0,
                    memory_usage: 0,
                    memory_limit: 0,
                    memory_percent: 0.0,
                    network_rx: 0,
                    network_tx: 0,
                    block_read: 0,
                    block_write: 0,
                    pids: 0,
                })
            }
        }
    }

    async fn container_exists(&self, id: &str) -> Result<bool, RuntimeError> {
        let mut manager = self.container_manager.write().await;
        manager.container_exists(id).await.map_err(|e| e.into())
    }

    async fn execute_command(
        &self,
        id: &str,
        cmd: Vec<&str>,
        _attach_stdout: bool,
        _attach_stderr: bool,
    ) -> Result<ExecResult, RuntimeError> {
        let mut manager = self.task_manager.write().await;
        let spec = ProcessSpec {
            args: cmd.iter().map(|s| s.to_string()).collect(),
            env: vec![],
            cwd: None,
            user: None,
            terminal: false,
        };
        manager
            .exec_process(id, spec)
            .await
            .map_err(|e| RuntimeError::from(ContainerdError::from(e)))
    }

    async fn get_logs(&self, _id: &str, _options: LogOptions) -> Result<LogStream, RuntimeError> {
        // For now, return a simple error until we implement proper log streaming
        // The lifetime issues require a more complex solution with owned data
        Err(RuntimeError::OperationFailed {
            operation: "get_logs".to_string(),
            message: "Log streaming with containerd integration in progress".to_string(),
        })
    }

    async fn wait_container(&self, id: &str) -> Result<i32, RuntimeError> {
        let mut manager = self.task_manager.write().await;
        manager.wait_task(id).await.map_err(|e| e.into())
    }
}

#[async_trait]
impl BatchOperations for ContainerdRuntime {
    async fn batch_start_containers(
        &self,
        ids: &[&str],
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError> {
        let start_time = std::time::Instant::now();
        let mut result = BatchResult::new();

        // Use tokio::task::JoinSet for concurrent operations
        let mut tasks = tokio::task::JoinSet::new();
        let semaphore = Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));

        for &id in ids {
            let task_manager = self.task_manager.clone();
            let permit = semaphore.clone();
            let timeout = options.timeout;
            let id = id.to_string();

            tasks.spawn(async move {
                let _permit = permit.acquire().await.expect("Semaphore closed");
                
                let operation_result = tokio::time::timeout(
                    timeout,
                    async {
                        let mut manager = task_manager.write().await;
                        manager.start_container(&id).await
                    }
                ).await;

                match operation_result {
                    Ok(Ok(_)) => Ok(id),
                    Ok(Err(e)) => Err((id, e.to_string())),
                    Err(_) => Err((id, format!("Operation timed out after {:?}", timeout))),
                }
            });
        }

        // Collect results
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok(id)) => result.add_success(id),
                Ok(Err((id, error))) => {
                    result.add_failure(id, error);
                    if options.fail_fast {
                        tasks.abort_all();
                        break;
                    }
                }
                Err(join_error) => {
                    result.add_failure("unknown".to_string(), format!("Task join error: {}", join_error));
                }
            }
        }

        result.set_duration(start_time.elapsed());
        Ok(result)
    }

    async fn batch_stop_containers(
        &self,
        ids: &[&str],
        timeout: Option<Duration>,
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError> {
        let start_time = std::time::Instant::now();
        let mut result = BatchResult::new();

        let mut tasks = tokio::task::JoinSet::new();
        let semaphore = Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));

        for &id in ids {
            let task_manager = self.task_manager.clone();
            let permit = semaphore.clone();
            let operation_timeout = options.timeout;
            let stop_timeout = timeout;
            let id = id.to_string();

            tasks.spawn(async move {
                let _permit = permit.acquire().await.expect("Semaphore closed");
                
                let operation_result = tokio::time::timeout(
                    operation_timeout,
                    async {
                        let mut manager = task_manager.write().await;
                        manager.stop_container(&id, stop_timeout).await
                    }
                ).await;

                match operation_result {
                    Ok(Ok(_)) => Ok(id),
                    Ok(Err(e)) => Err((id, e.to_string())),
                    Err(_) => Err((id, format!("Operation timed out after {:?}", operation_timeout))),
                }
            });
        }

        // Collect results
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok(id)) => result.add_success(id),
                Ok(Err((id, error))) => {
                    result.add_failure(id, error);
                    if options.fail_fast {
                        tasks.abort_all();
                        break;
                    }
                }
                Err(join_error) => {
                    result.add_failure("unknown".to_string(), format!("Task join error: {}", join_error));
                }
            }
        }

        result.set_duration(start_time.elapsed());
        Ok(result)
    }

    async fn batch_restart_containers(
        &self,
        ids: &[&str],
        timeout: Option<Duration>,
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError> {
        let start_time = std::time::Instant::now();
        let mut result = BatchResult::new();

        let mut tasks = tokio::task::JoinSet::new();
        let semaphore = Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));

        for &id in ids {
            let task_manager = self.task_manager.clone();
            let permit = semaphore.clone();
            let operation_timeout = options.timeout;
            let restart_timeout = timeout;
            let id = id.to_string();

            tasks.spawn(async move {
                let _permit = permit.acquire().await.expect("Semaphore closed");
                
                let operation_result = tokio::time::timeout(
                    operation_timeout,
                    async {
                        let mut manager = task_manager.write().await;
                        manager.restart_container(&id, restart_timeout).await
                    }
                ).await;

                match operation_result {
                    Ok(Ok(_)) => Ok(id),
                    Ok(Err(e)) => Err((id, e.to_string())),
                    Err(_) => Err((id, format!("Operation timed out after {:?}", operation_timeout))),
                }
            });
        }

        // Collect results
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok(id)) => result.add_success(id),
                Ok(Err((id, error))) => {
                    result.add_failure(id, error);
                    if options.fail_fast {
                        tasks.abort_all();
                        break;
                    }
                }
                Err(join_error) => {
                    result.add_failure("unknown".to_string(), format!("Task join error: {}", join_error));
                }
            }
        }

        result.set_duration(start_time.elapsed());
        Ok(result)
    }

    async fn batch_remove_containers(
        &self,
        ids: &[&str],
        _force: bool,
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError> {
        let start_time = std::time::Instant::now();
        let mut result = BatchResult::new();

        let mut tasks = tokio::task::JoinSet::new();
        let semaphore = Arc::new(tokio::sync::Semaphore::new(options.max_concurrent));

        for &id in ids {
            let container_manager = self.container_manager.clone();
            let permit = semaphore.clone();
            let operation_timeout = options.timeout;
            let id = id.to_string();

            tasks.spawn(async move {
                let _permit = permit.acquire().await.expect("Semaphore closed");
                
                let operation_result = tokio::time::timeout(
                    operation_timeout,
                    async {
                        let mut manager = container_manager.write().await;
                        manager.remove_container(&id).await
                    }
                ).await;

                match operation_result {
                    Ok(Ok(_)) => Ok(id),
                    Ok(Err(e)) => Err((id, e.to_string())),
                    Err(_) => Err((id, format!("Operation timed out after {:?}", operation_timeout))),
                }
            });
        }

        // Collect results
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok(id)) => result.add_success(id),
                Ok(Err((id, error))) => {
                    result.add_failure(id, error);
                    if options.fail_fast {
                        tasks.abort_all();
                        break;
                    }
                }
                Err(join_error) => {
                    result.add_failure("unknown".to_string(), format!("Task join error: {}", join_error));
                }
            }
        }

        result.set_duration(start_time.elapsed());
        Ok(result)
    }

    async fn batch_stats(
        &self,
        ids: &[&str],
        _options: BatchOptions,
    ) -> Result<Vec<(String, Result<ContainerStats, RuntimeError>)>, RuntimeError> {
        let mut results = Vec::new();
        
        for &id in ids {
            let stats_result = self.get_stats(id).await;
            results.push((id.to_string(), stats_result));
        }

        Ok(results)
    }
}

#[async_trait]
impl VolumeOperations for ContainerdRuntime {
    // Note: Volume operations temporarily disabled due to missing snapshots API in containerd-client 0.8.0
    type Volume = ContainerdVolume;

    async fn create_volume(&self, _spec: VolumeSpec) -> Result<Self::Volume, RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }

    async fn list_volumes(&self, _filter: VolumeFilter) -> Result<Vec<Self::Volume>, RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }

    async fn get_volume(&self, _name: &str) -> Result<Self::Volume, RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }

    async fn remove_volume(&self, _name: &str, _force: bool) -> Result<(), RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }

    async fn volume_exists(&self, _name: &str) -> Result<bool, RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }

    async fn backup_volume(&self, _name: &str, _target_path: &str) -> Result<(), RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }

    async fn restore_volume(&self, _name: &str, _source_path: &str) -> Result<(), RuntimeError> {
        // Snapshot operations not available in containerd-client 0.8.0
        Err(RuntimeError::OperationFailed {
            operation: "volume_operation".to_string(),
            message: "Volume operations not supported in containerd-client 0.8.0".to_string(),
        })
    }
}

#[async_trait]
impl ImageOperations for ContainerdRuntime {
    type Image = ContainerdImage;

    async fn list_images(&self, filter: ImageFilter) -> Result<Vec<Self::Image>, RuntimeError> {
        let mut manager = self.image_manager.write().await;
        manager.list_images(filter).await.map_err(|e| e.into())
    }

    async fn get_image(&self, reference: &str) -> Result<Self::Image, RuntimeError> {
        let mut manager = self.image_manager.write().await;
        manager.get_image(reference).await.map_err(|e| e.into())
    }

    async fn pull_image(&self, reference: &str) -> Result<Self::Image, RuntimeError> {
        let mut manager = self.image_manager.write().await;
        manager.pull_image(reference).await.map_err(|e| e.into())
    }

    async fn remove_image(&self, reference: &str, force: bool) -> Result<(), RuntimeError> {
        let mut manager = self.image_manager.write().await;
        manager.remove_image(reference, force).await.map_err(|e| e.into())
    }

    async fn image_exists(&self, reference: &str) -> Result<bool, RuntimeError> {
        let mut manager = self.image_manager.write().await;
        manager.image_exists(reference).await.map_err(|e| e.into())
    }

    async fn inspect_image(&self, reference: &str) -> Result<Self::Image, RuntimeError> {
        self.get_image(reference).await
    }
}

#[async_trait]
impl EventOperations for ContainerdRuntime {
    async fn subscribe_events(&self, filters: Vec<String>) -> Result<EventStream, RuntimeError> {
        let mut event_manager = self.event_manager.write().await;
        
        // Convert string filters to EventFilter
        let mut event_filter = crate::events::EventFilter {
            vpn_managed_only: true,
            ..Default::default()
        };

        // Parse basic filters
        for filter in filters {
            if filter.starts_with("container=") {
                let container_id = filter.strip_prefix("container=").unwrap_or("").to_string();
                event_filter.container_ids.push(container_id);
            } else if filter.starts_with("namespace=") {
                let namespace = filter.strip_prefix("namespace=").unwrap_or("").to_string();
                event_filter.namespaces = vec![namespace];
            } else if filter == "all" {
                event_filter.vpn_managed_only = false;
            }
        }

        let containerd_stream = event_manager.subscribe_events(event_filter).await
            .map_err(|e| RuntimeError::from(e))?;

        // Convert containerd events to runtime events
        let runtime_stream = containerd_stream.map(|event_result| {
            event_result.map(|containerd_event| {
                // Convert ContainerdEvent to RuntimeEvent
                vpn_runtime::RuntimeEvent {
                    timestamp: containerd_event.timestamp,
                    event_type: match containerd_event.event_type {
                        crate::events::ContainerdEventType::ContainerCreate => vpn_runtime::EventType::ContainerCreate,
                        crate::events::ContainerdEventType::ContainerStart => vpn_runtime::EventType::ContainerStart,
                        crate::events::ContainerdEventType::ContainerStop => vpn_runtime::EventType::ContainerStop,
                        crate::events::ContainerdEventType::ContainerDelete => vpn_runtime::EventType::ContainerRemove,
                        crate::events::ContainerdEventType::TaskExit => vpn_runtime::EventType::ContainerDie,
                        crate::events::ContainerdEventType::ImagePull => vpn_runtime::EventType::ImagePull,
                        crate::events::ContainerdEventType::ImagePush => vpn_runtime::EventType::Other("image.push".to_string()),
                        crate::events::ContainerdEventType::ImageDelete => vpn_runtime::EventType::ImageRemove,
                        _ => vpn_runtime::EventType::Other("unknown".to_string()),
                    },
                    container_id: containerd_event.container_id(),
                    image: containerd_event.image_ref(),
                    message: containerd_event.topic.clone(),
                    attributes: std::collections::HashMap::new(), // Could parse from event_data
                }
            }).map_err(|e| RuntimeError::from(e))
        });

        Ok(Box::pin(runtime_stream))
    }

    async fn get_events_since(&self, since: chrono::DateTime<chrono::Utc>) -> Result<EventStream, RuntimeError> {
        let mut event_manager = self.event_manager.write().await;
        
        // Use the containerd event manager
        event_manager.get_events_since(since, crate::events::EventFilter::default()).await
            .map(|events| {
                // Convert Vec<ContainerdEvent> to EventStream
                let stream = futures_util::stream::iter(events.into_iter().map(|containerd_event| {
                    Ok(vpn_runtime::RuntimeEvent {
                        timestamp: containerd_event.timestamp,
                        event_type: vpn_runtime::EventType::Other("historical".to_string()),
                        container_id: containerd_event.container_id(),
                        image: containerd_event.image_ref(),
                        message: containerd_event.topic.clone(),
                        attributes: std::collections::HashMap::new(),
                    })
                }));
                Box::pin(stream) as EventStream
            })
            .map_err(|e| RuntimeError::from(e))
    }
}

#[async_trait]
impl HealthOperations for ContainerdRuntime {
    async fn check_container_health(&self, id: &str) -> Result<bool, RuntimeError> {
        let mut health_monitor = self.health_monitor.write().await;
        
        // If no health check is configured, fall back to basic task status check
        if health_monitor.get_health_status(id).is_none() {
            // Add a basic health check configuration
            let basic_config = crate::health::HealthCheckConfig::default();
            health_monitor.add_health_check(id.to_string(), basic_config);
        }
        
        match health_monitor.check_container_health(id).await {
            Ok(result) => Ok(result.status == crate::health::HealthStatus::Healthy),
            Err(_) => {
                // Fall back to simple task status check
                match self.get_task(id).await {
                    Ok(task) => Ok(task.status() == vpn_runtime::TaskStatus::Running),
                    Err(_) => Ok(false),
                }
            }
        }
    }

    async fn wait_for_healthy(&self, id: &str, timeout: Duration) -> Result<bool, RuntimeError> {
        let start = std::time::Instant::now();
        
        while start.elapsed() < timeout {
            if self.check_container_health(id).await? {
                return Ok(true);
            }
            
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        
        Ok(false)
    }

    async fn batch_health_check(
        &self,
        ids: &[&str],
        _options: BatchOptions,
    ) -> Result<Vec<(String, Result<bool, RuntimeError>)>, RuntimeError> {
        let mut results = Vec::new();
        
        for &id in ids {
            let health_result = self.check_container_health(id).await;
            results.push((id.to_string(), health_result));
        }

        Ok(results)
    }
}

#[async_trait]
impl CompleteRuntime for ContainerdRuntime {
    async fn version(&self) -> Result<String, RuntimeError> {
        let mut version_client = VersionClient::new(self.channel.clone());
        let response = version_client
            .version(())
            .await
            .map_err(|e| RuntimeError::ConnectionError {
                message: format!("Failed to get version: {}", e),
            })?;

        Ok(response.get_ref().version.clone())
    }

    async fn info(&self) -> Result<RuntimeInfo, RuntimeError> {
        let version = self.version().await?;
        
        Ok(RuntimeInfo {
            name: "containerd".to_string(),
            version,
            commit: None,
            os: std::env::consts::OS.to_string(),
            architecture: std::env::consts::ARCH.to_string(),
            kernel_version: "unknown".to_string(), // Would need to be fetched from system
            total_memory: 0, // Would need to be fetched from system
            containers_running: 0, // Would need to be calculated
            containers_paused: 0,
            containers_stopped: 0,
            images: 0, // Would need to be calculated
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vpn_runtime::{ContainerdConfig, RuntimeType};

    fn create_test_config() -> RuntimeConfig {
        RuntimeConfig {
            runtime_type: RuntimeType::Containerd,
            containerd: Some(ContainerdConfig::default()),
            ..Default::default()
        }
    }

    #[test]
    fn test_runtime_config() {
        let config = create_test_config();
        assert_eq!(config.runtime_type, RuntimeType::Containerd);
        assert_eq!(config.effective_namespace(), "default");
        assert_eq!(config.effective_socket_path(), "/run/containerd/containerd.sock");
    }

    // Note: Integration tests would need actual containerd running
}