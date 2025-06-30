use crate::{
    ContainerdContainer, ContainerdError, ContainerdImage, ContainerdTask, ContainerdVolume,
    ProcessSpec, Result,
};
use async_trait::async_trait;
use chrono::Utc;
use containerd_client::{connect, services::v1::version_client::VersionClient};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tonic::transport::Channel;
use tracing::{debug, error, info, warn};
use vpn_runtime::{
    BatchOperations, BatchOptions, BatchResult, CompleteRuntime, Container, ContainerFilter,
    ContainerRuntime, ContainerSpec, ContainerStats, EventOperations, EventStream, ExecResult,
    HealthOperations, Image, ImageFilter, ImageOperations, LogOptions, LogStream, RuntimeConfig,
    RuntimeError, RuntimeInfo, Task, VolumeFilter, VolumeOperations, VolumeSpec, Volume,
};

use crate::{
    containers::ContainerManager, images::ImageManager, snapshots::SnapshotManager,
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
    snapshot_manager: Arc<RwLock<SnapshotManager>>,
    config: RuntimeConfig,
}

impl ContainerdRuntime {
    /// Create a new containerd runtime instance
    pub async fn new(config: RuntimeConfig) -> Result<Self> {
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
            snapshot_manager: Arc::new(RwLock::new(SnapshotManager::new(
                channel.clone(),
                namespace.clone(),
                snapshotter.clone(),
            ))),
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

    async fn connect(config: RuntimeConfig) -> Result<Self, RuntimeError>
    where
        Self: Sized,
    {
        ContainerdRuntime::new(config)
            .await
            .map_err(|e| e.into())
    }

    async fn disconnect(&mut self) -> Result<(), RuntimeError> {
        debug!("Disconnecting from containerd");
        // containerd gRPC connections are closed automatically when dropped
        Ok(())
    }

    async fn ping(&self) -> Result<(), RuntimeError> {
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
            .map_err(|e| e.into())
    }

    async fn list_containers(
        &self,
        filter: ContainerFilter,
    ) -> Result<Vec<Self::Container>, RuntimeError> {
        let mut manager = self.container_manager.write().await;
        manager
            .list_containers(filter)
            .await
            .map_err(|e| e.into())
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
            .map_err(|e| e.into())
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
            .map_err(|e| e.into())
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
            .map_err(|e| e.into())
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

    async fn get_stats(&self, _id: &str) -> Result<ContainerStats, RuntimeError> {
        // This would need to be implemented using cgroup access
        // For now, return a placeholder
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
            .map_err(|e| e.into())
    }

    async fn get_logs(&self, _id: &str, _options: LogOptions) -> Result<LogStream, RuntimeError> {
        // This would need to be implemented using log collection
        // For now, return an error
        Err(RuntimeError::OperationFailed {
            operation: "get_logs".to_string(),
            message: "Log streaming not yet implemented".to_string(),
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
        force: bool,
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
    type Volume = ContainerdVolume;

    async fn create_volume(&self, spec: VolumeSpec) -> Result<Self::Volume, RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.create_volume(spec).await.map_err(|e| e.into())
    }

    async fn list_volumes(&self, filter: VolumeFilter) -> Result<Vec<Self::Volume>, RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.list_volumes(filter).await.map_err(|e| e.into())
    }

    async fn get_volume(&self, name: &str) -> Result<Self::Volume, RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.get_volume(name).await.map_err(|e| e.into())
    }

    async fn remove_volume(&self, name: &str, force: bool) -> Result<(), RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.remove_volume(name, force).await.map_err(|e| e.into())
    }

    async fn volume_exists(&self, name: &str) -> Result<bool, RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.volume_exists(name).await.map_err(|e| e.into())
    }

    async fn backup_volume(&self, name: &str, target_path: &str) -> Result<(), RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.backup_volume(name, target_path).await.map_err(|e| e.into())
    }

    async fn restore_volume(&self, name: &str, source_path: &str) -> Result<(), RuntimeError> {
        let mut manager = self.snapshot_manager.write().await;
        manager.restore_volume(name, source_path).await.map_err(|e| e.into())
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
    async fn subscribe_events(&self, _filters: Vec<String>) -> Result<EventStream, RuntimeError> {
        // This would need to be implemented using the events service
        Err(RuntimeError::OperationFailed {
            operation: "subscribe_events".to_string(),
            message: "Event streaming not yet implemented".to_string(),
        })
    }

    async fn get_events_since(&self, _since: chrono::DateTime<chrono::Utc>) -> Result<EventStream, RuntimeError> {
        // This would need to be implemented using the events service
        Err(RuntimeError::OperationFailed {
            operation: "get_events_since".to_string(),
            message: "Event streaming not yet implemented".to_string(),
        })
    }
}

#[async_trait]
impl HealthOperations for ContainerdRuntime {
    async fn check_container_health(&self, id: &str) -> Result<bool, RuntimeError> {
        // Simple health check based on task status
        match self.get_task(id).await {
            Ok(task) => Ok(task.status() == vpn_runtime::TaskStatus::Running),
            Err(_) => Ok(false),
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