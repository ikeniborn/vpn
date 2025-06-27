use bollard::Docker;
use bollard::container::{Config, CreateContainerOptions, StartContainerOptions, StopContainerOptions, RemoveContainerOptions};
use bollard::models::{ContainerSummary, ContainerInspectResponse};
use bollard::exec::{CreateExecOptions, StartExecResults};
use futures_util::stream::StreamExt;
use std::collections::HashMap;
use std::time::Duration;
use tokio::task::JoinSet;
use crate::error::{DockerError, Result};

#[derive(Debug, Clone)]
pub enum ContainerOperation {
    Start(String),
    Stop(String, Option<i64>),
    Restart(String, Option<i64>),
    Remove(String, bool),
}

#[derive(Debug, Clone)]
pub struct BatchOperationResult {
    pub successful: Vec<String>,
    pub failed: HashMap<String, String>,
    pub total_duration: Duration,
}

#[derive(Debug, Clone)]
pub struct BatchOperationOptions {
    pub max_concurrent: usize,
    pub timeout: Duration,
    pub fail_fast: bool,
}

#[derive(Clone)]
pub struct ContainerManager {
    docker: Docker,
}

impl ContainerManager {
    pub fn new() -> Result<Self> {
        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| DockerError::ConnectionError(e.to_string()))?;
        Ok(Self { docker })
    }
    
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
        
        Ok(self.docker.list_containers(Some(options)).await?)
    }
    
    pub async fn inspect_container(&self, name: &str) -> Result<ContainerInspectResponse> {
        self.docker.inspect_container(name, None).await
            .map_err(|_| DockerError::ContainerNotFound(name.to_string()).into())
    }
    
    pub async fn create_container(
        &self,
        name: &str,
        config: Config<String>,
    ) -> Result<String> {
        let options = CreateContainerOptions {
            name,
            ..Default::default()
        };
        
        let response = self.docker.create_container(Some(options), config).await?;
        Ok(response.id)
    }
    
    pub async fn start_container(&self, name: &str) -> Result<()> {
        self.docker.start_container(name, None::<StartContainerOptions<String>>).await?;
        Ok(())
    }
    
    pub async fn stop_container(&self, name: &str, timeout: Option<i64>) -> Result<()> {
        let options = StopContainerOptions {
            t: timeout.unwrap_or(10),
        };
        
        self.docker.stop_container(name, Some(options)).await?;
        Ok(())
    }
    
    pub async fn restart_container(&self, name: &str, timeout: Option<i64>) -> Result<()> {
        self.stop_container(name, timeout).await?;
        self.start_container(name).await?;
        Ok(())
    }
    
    pub async fn remove_container(&self, name: &str, force: bool) -> Result<()> {
        let options = RemoveContainerOptions {
            force,
            v: true,
            ..Default::default()
        };
        
        self.docker.remove_container(name, Some(options)).await?;
        Ok(())
    }
    
    pub async fn exec_command(
        &self,
        container: &str,
        cmd: Vec<&str>,
    ) -> Result<String> {
        let exec_options = CreateExecOptions {
            attach_stdout: Some(true),
            attach_stderr: Some(true),
            cmd: Some(cmd),
            ..Default::default()
        };
        
        let exec = self.docker.create_exec(container, exec_options).await?;
        
        if let StartExecResults::Attached { mut output, .. } = 
            self.docker.start_exec(&exec.id, None).await? {
            
            let mut result = String::new();
            while let Some(Ok(msg)) = output.next().await {
                result.push_str(&msg.to_string());
            }
            Ok(result)
        } else {
            Err(DockerError::ApiError(bollard::errors::Error::DockerResponseServerError {
                status_code: 500,
                message: "Failed to attach to exec".to_string(),
            }))
        }
    }
    
    pub async fn container_exists(&self, name: &str) -> bool {
        self.inspect_container(name).await.is_ok()
    }
    
    /// Execute multiple container operations concurrently with batching
    pub async fn batch_container_operations(
        &self,
        operations: Vec<ContainerOperation>,
        options: Option<BatchOperationOptions>
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
                    container_manager.execute_single_operation(operation.clone())
                ).await;
                
                match result {
                    Ok(Ok(_)) => Ok(operation.container_name()),
                    Ok(Err(e)) => Err((operation.container_name(), e.to_string())),
                    Err(_) => Err((operation.container_name(), 
                        format!("Operation timed out after {:?}", timeout))),
                }
            });
        }
        
        // Collect results as they complete
        while let Some(task_result) = tasks.join_next().await {
            match task_result {
                Ok(Ok(container_name)) => {
                    successful.push(container_name);
                },
                Ok(Err((container_name, error))) => {
                    failed.insert(container_name.clone(), error);
                    
                    // Fail fast if requested
                    if options.fail_fast {
                        tasks.abort_all();
                        break;
                    }
                },
                Err(join_error) => {
                    failed.insert(
                        "unknown".to_string(),
                        format!("Task join error: {}", join_error)
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
            ContainerOperation::Restart(name, timeout) => self.restart_container(&name, timeout).await,
            ContainerOperation::Remove(name, force) => self.remove_container(&name, force).await,
        }
    }
    
    /// Batch start multiple containers
    pub async fn batch_start_containers(
        &self,
        names: &[&str],
        options: Option<BatchOperationOptions>
    ) -> BatchOperationResult {
        let operations = names.iter()
            .map(|name| ContainerOperation::Start(name.to_string()))
            .collect();
        
        self.batch_container_operations(operations, options).await
    }
    
    /// Batch stop multiple containers
    pub async fn batch_stop_containers(
        &self,
        names: &[&str],
        timeout: Option<i64>,
        options: Option<BatchOperationOptions>
    ) -> BatchOperationResult {
        let operations = names.iter()
            .map(|name| ContainerOperation::Stop(name.to_string(), timeout))
            .collect();
        
        self.batch_container_operations(operations, options).await
    }
    
    /// Batch restart multiple containers
    pub async fn batch_restart_containers(
        &self,
        names: &[&str],
        timeout: Option<i64>,
        options: Option<BatchOperationOptions>
    ) -> BatchOperationResult {
        let operations = names.iter()
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
        options: Option<BatchOperationOptions>
    ) -> Vec<BatchOperationResult> {
        let mut results = Vec::new();
        
        for group in container_groups {
            let result = self.batch_restart_containers(&group, timeout, options.clone()).await;
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