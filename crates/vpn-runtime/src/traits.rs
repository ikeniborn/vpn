use async_trait::async_trait;
use std::time::Duration;

use crate::{
    BatchOptions, BatchResult, Container, ContainerFilter, ContainerSpec, ContainerStats,
    ExecResult, Image, ImageFilter, LogOptions, LogStream, RuntimeConfig, RuntimeError, Task,
    Volume, VolumeFilter, VolumeSpec, EventStream,
};

/// Core container runtime interface
#[async_trait]
pub trait ContainerRuntime: Send + Sync {
    type Container: Container;
    type Task: Task;
    type Volume: Volume;
    type Image: Image;

    // Connection management
    async fn connect(config: RuntimeConfig) -> Result<Self, RuntimeError>
    where
        Self: Sized;
    
    async fn disconnect(&mut self) -> Result<(), RuntimeError>;
    
    async fn ping(&self) -> Result<(), RuntimeError>;

    // Container lifecycle operations
    async fn create_container(&self, spec: ContainerSpec) -> Result<Self::Container, RuntimeError>;
    
    async fn list_containers(&self, filter: ContainerFilter) -> Result<Vec<Self::Container>, RuntimeError>;
    
    async fn get_container(&self, id: &str) -> Result<Self::Container, RuntimeError>;
    
    async fn remove_container(&self, id: &str, force: bool) -> Result<(), RuntimeError>;

    // Task management operations
    async fn start_container(&self, id: &str) -> Result<Self::Task, RuntimeError>;
    
    async fn stop_container(&self, id: &str, timeout: Option<Duration>) -> Result<(), RuntimeError>;
    
    async fn restart_container(&self, id: &str, timeout: Option<Duration>) -> Result<(), RuntimeError>;
    
    async fn pause_container(&self, id: &str) -> Result<(), RuntimeError>;
    
    async fn unpause_container(&self, id: &str) -> Result<(), RuntimeError>;

    // Container inspection and monitoring
    async fn get_task(&self, container_id: &str) -> Result<Self::Task, RuntimeError>;
    
    async fn get_stats(&self, id: &str) -> Result<ContainerStats, RuntimeError>;
    
    async fn container_exists(&self, id: &str) -> Result<bool, RuntimeError>;

    // Command execution
    async fn execute_command(
        &self,
        id: &str,
        cmd: Vec<&str>,
        attach_stdout: bool,
        attach_stderr: bool,
    ) -> Result<ExecResult, RuntimeError>;

    // Log operations
    async fn get_logs(&self, id: &str, options: LogOptions) -> Result<LogStream, RuntimeError>;

    // Wait operations
    async fn wait_container(&self, id: &str) -> Result<i32, RuntimeError>;
}

/// Batch operations trait for concurrent container management
#[async_trait]
pub trait BatchOperations: ContainerRuntime {
    async fn batch_start_containers(
        &self,
        ids: &[&str],
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError>;

    async fn batch_stop_containers(
        &self,
        ids: &[&str],
        timeout: Option<Duration>,
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError>;

    async fn batch_restart_containers(
        &self,
        ids: &[&str],
        timeout: Option<Duration>,
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError>;

    async fn batch_remove_containers(
        &self,
        ids: &[&str],
        force: bool,
        options: BatchOptions,
    ) -> Result<BatchResult, RuntimeError>;

    async fn batch_stats(
        &self,
        ids: &[&str],
        options: BatchOptions,
    ) -> Result<Vec<(String, Result<ContainerStats, RuntimeError>)>, RuntimeError>;
}

/// Volume management operations
#[async_trait]
pub trait VolumeOperations: Send + Sync {
    type Volume: Volume;

    async fn create_volume(&self, spec: VolumeSpec) -> Result<Self::Volume, RuntimeError>;
    
    async fn list_volumes(&self, filter: VolumeFilter) -> Result<Vec<Self::Volume>, RuntimeError>;
    
    async fn get_volume(&self, name: &str) -> Result<Self::Volume, RuntimeError>;
    
    async fn remove_volume(&self, name: &str, force: bool) -> Result<(), RuntimeError>;
    
    async fn volume_exists(&self, name: &str) -> Result<bool, RuntimeError>;

    // Volume backup and restore operations
    async fn backup_volume(&self, name: &str, target_path: &str) -> Result<(), RuntimeError>;
    
    async fn restore_volume(&self, name: &str, source_path: &str) -> Result<(), RuntimeError>;
}

/// Image management operations
#[async_trait]
pub trait ImageOperations: Send + Sync {
    type Image: Image;

    async fn list_images(&self, filter: ImageFilter) -> Result<Vec<Self::Image>, RuntimeError>;
    
    async fn get_image(&self, reference: &str) -> Result<Self::Image, RuntimeError>;
    
    async fn pull_image(&self, reference: &str) -> Result<Self::Image, RuntimeError>;
    
    async fn remove_image(&self, reference: &str, force: bool) -> Result<(), RuntimeError>;
    
    async fn image_exists(&self, reference: &str) -> Result<bool, RuntimeError>;

    // Image inspection
    async fn inspect_image(&self, reference: &str) -> Result<Self::Image, RuntimeError>;
}

/// Event streaming operations
#[async_trait]
pub trait EventOperations: Send + Sync {
    async fn subscribe_events(&self, filters: Vec<String>) -> Result<EventStream, RuntimeError>;
    
    async fn get_events_since(&self, since: chrono::DateTime<chrono::Utc>) -> Result<EventStream, RuntimeError>;
}

/// Health monitoring operations
#[async_trait]
pub trait HealthOperations: Send + Sync {
    async fn check_container_health(&self, id: &str) -> Result<bool, RuntimeError>;
    
    async fn wait_for_healthy(
        &self,
        id: &str,
        timeout: Duration,
    ) -> Result<bool, RuntimeError>;

    async fn batch_health_check(
        &self,
        ids: &[&str],
        options: BatchOptions,
    ) -> Result<Vec<(String, Result<bool, RuntimeError>)>, RuntimeError>;
}

/// Complete runtime interface combining all operations
#[async_trait]
pub trait CompleteRuntime: 
    ContainerRuntime 
    + BatchOperations 
    + EventOperations 
    + HealthOperations 
{
    // Runtime information
    async fn version(&self) -> Result<String, RuntimeError>;
    
    async fn info(&self) -> Result<RuntimeInfo, RuntimeError>;
}

/// Runtime information
#[derive(Debug, Clone)]
pub struct RuntimeInfo {
    pub name: String,
    pub version: String,
    pub commit: Option<String>,
    pub os: String,
    pub architecture: String,
    pub kernel_version: String,
    pub total_memory: u64,
    pub containers_running: u32,
    pub containers_paused: u32,
    pub containers_stopped: u32,
    pub images: u32,
}