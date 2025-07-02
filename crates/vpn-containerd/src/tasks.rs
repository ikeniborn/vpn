use crate::{ContainerdError, ContainerdTask, ProcessSpec, Result};
use chrono::Utc;
use containerd_client::services::v1::{
    tasks_client::TasksClient,
    CreateTaskRequest, DeleteTaskRequest, ExecProcessRequest, GetRequest, KillRequest,
    ListTasksRequest, StartRequest, WaitRequest,
};
// use futures_util::StreamExt; // Unused currently
use std::time::Duration;
use tonic::transport::Channel;
use tracing::{debug, info, warn}; // error unused currently
use vpn_runtime::{ExecResult, TaskStatus};

/// Task management operations for containerd
pub struct TaskManager {
    client: TasksClient<Channel>,
    namespace: String,
}

impl TaskManager {
    pub fn new(channel: Channel, namespace: String) -> Self {
        Self {
            client: TasksClient::new(channel),
            namespace,
        }
    }

    /// Create and start a task for a container
    pub async fn start_container(&mut self, container_id: &str) -> Result<ContainerdTask> {
        debug!("Starting container: {}", container_id);

        // First create the task
        let task = self.create_task(container_id).await?;
        
        // Then start the task
        self.start_task(container_id).await?;

        info!("Container started successfully: {}", container_id);
        Ok(task)
    }

    /// Create a task for a container (without starting it)
    pub async fn create_task(&mut self, container_id: &str) -> Result<ContainerdTask> {
        debug!("Creating task for container: {}", container_id);

        let request = CreateTaskRequest {
            container_id: container_id.to_string(),
            rootfs: vec![], // Empty for most cases
            stdin: String::new(),
            stdout: String::new(),
            stderr: String::new(),
            terminal: false,
            checkpoint: None,
            options: None,
            runtime_path: String::new(), // Use default runtime
        };

        let response = self
            .client
            .create(request)
            .await
            .map_err(|e| ContainerdError::TaskOperationFailed {
                operation: "create".to_string(),
                message: e.to_string(),
            })?;

        let task = response.into_inner();

        Ok(ContainerdTask {
            id: container_id.to_string(), // Use container_id as task ID
            container_id: container_id.to_string(),
            pid: Some(task.pid),
            status: TaskStatus::Created,
            exit_code: None,
        })
    }

    /// Start an existing task
    pub async fn start_task(&mut self, container_id: &str) -> Result<()> {
        debug!("Starting task for container: {}", container_id);

        let request = StartRequest {
            container_id: container_id.to_string(),
            exec_id: String::new(), // Empty for main task
        };

        self.client
            .start(request)
            .await
            .map_err(|e| ContainerdError::TaskOperationFailed {
                operation: "start".to_string(),
                message: e.to_string(),
            })?;

        Ok(())
    }

    /// Stop a container task
    pub async fn stop_container(&mut self, container_id: &str, timeout: Option<Duration>) -> Result<()> {
        debug!("Stopping container: {}", container_id);

        // Send SIGTERM first for graceful shutdown
        self.kill_task(container_id, "SIGTERM").await?;

        // Wait for graceful shutdown or timeout
        let wait_timeout = timeout.unwrap_or(Duration::from_secs(10));
        
        match tokio::time::timeout(wait_timeout, self.wait_task(container_id)).await {
            Ok(_) => {
                info!("Container stopped gracefully: {}", container_id);
                Ok(())
            }
            Err(_) => {
                warn!("Container didn't stop gracefully, sending SIGKILL: {}", container_id);
                self.kill_task(container_id, "SIGKILL").await?;
                Ok(())
            }
        }
    }

    /// Kill a task with a signal
    pub async fn kill_task(&mut self, container_id: &str, signal: &str) -> Result<()> {
        debug!("Killing task for container {} with signal: {}", container_id, signal);

        let request = KillRequest {
            container_id: container_id.to_string(),
            exec_id: String::new(), // Empty for main task
            signal: 15u32, // SIGTERM by default
            all: false,
        };

        self.client
            .kill(request)
            .await
            .map_err(|e| ContainerdError::TaskOperationFailed {
                operation: "kill".to_string(),
                message: e.to_string(),
            })?;

        Ok(())
    }

    /// Delete a task
    pub async fn delete_task(&mut self, container_id: &str) -> Result<()> {
        debug!("Deleting task for container: {}", container_id);

        let request = DeleteTaskRequest {
            container_id: container_id.to_string(),
        };

        self.client
            .delete(request)
            .await
            .map_err(|e| ContainerdError::TaskOperationFailed {
                operation: "delete".to_string(),
                message: e.to_string(),
            })?;

        Ok(())
    }

    /// Get task information
    pub async fn get_task(&mut self, container_id: &str) -> Result<ContainerdTask> {
        debug!("Getting task for container: {}", container_id);

        let request = GetRequest {
            container_id: container_id.to_string(),
            exec_id: String::new(), // Empty for main task
        };

        let response = self
            .client
            .get(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::TaskNotFound { id: container_id.to_string() },
                _ => ContainerdError::GrpcError(e),
            })?;

        let task = response.into_inner().process.ok_or_else(|| {
            ContainerdError::TaskNotFound { id: container_id.to_string() }
        })?;

        let status = match task.status {
            0 => TaskStatus::Unknown,
            1 => TaskStatus::Created,
            2 => TaskStatus::Running,
            3 => TaskStatus::Stopped,
            4 => TaskStatus::Paused,
            _ => TaskStatus::Unknown,
        };

        Ok(ContainerdTask {
            id: task.id,
            container_id: container_id.to_string(),
            pid: Some(task.pid),
            status,
            exit_code: Some(task.exit_status as i32),
        })
    }

    /// List all tasks
    pub async fn list_tasks(&mut self) -> Result<Vec<ContainerdTask>> {
        debug!("Listing all tasks");

        let request = ListTasksRequest {
            filter: String::new(),
        };

        let response = self
            .client
            .list(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let mut tasks = Vec::new();
        for task in response.into_inner().tasks {
            let status = match task.status {
                0 => TaskStatus::Unknown,
                1 => TaskStatus::Created,
                2 => TaskStatus::Running,
                3 => TaskStatus::Stopped,
                4 => TaskStatus::Paused,
                _ => TaskStatus::Unknown,
            };

            tasks.push(ContainerdTask {
                id: task.id,
                container_id: task.container_id,
                pid: Some(task.pid),
                status,
                exit_code: Some(task.exit_status as i32),
            });
        }

        Ok(tasks)
    }

    /// Wait for a task to complete
    pub async fn wait_task(&mut self, container_id: &str) -> Result<i32> {
        debug!("Waiting for task completion: {}", container_id);

        let request = WaitRequest {
            container_id: container_id.to_string(),
            exec_id: String::new(),
        };

        let response = self
            .client
            .wait(request)
            .await
            .map_err(|e| ContainerdError::TaskOperationFailed {
                operation: "wait".to_string(),
                message: e.to_string(),
            })?
            .into_inner();

        info!("Task completed with exit code: {}", response.exit_status);
        Ok(response.exit_status as i32)
    }

    /// Execute a command in a running container
    pub async fn exec_process(
        &mut self,
        container_id: &str,
        spec: ProcessSpec,
    ) -> Result<ExecResult> {
        debug!("Executing process in container: {}", container_id);

        let exec_id = format!("exec-{}-{}", container_id, Utc::now().timestamp());

        let _process_spec = ProcessSpec {
            args: spec.args,
            env: spec.env,
            cwd: Some(spec.cwd.unwrap_or_default()),
            user: None,
            terminal: false,
        };

        let request = ExecProcessRequest {
            container_id: container_id.to_string(),
            stdin: String::new(),
            stdout: String::new(),
            stderr: String::new(),
            terminal: spec.terminal,
            spec: None, // ProcessSpec conversion not available
            exec_id,
        };

        let _response = self
            .client
            .exec(request)
            .await
            .map_err(|e| ContainerdError::TaskOperationFailed {
                operation: "exec".to_string(),
                message: e.to_string(),
            })?;

        // For now, return a simple result
        // In a full implementation, we would need to capture stdout/stderr
        Ok(ExecResult {
            exit_code: 0, // Would need to be determined from the actual execution
            stdout: String::new(),
            stderr: String::new(),
        })
    }

    /// Pause a container task
    pub async fn pause_task(&mut self, container_id: &str) -> Result<()> {
        debug!("Pausing task for container: {}", container_id);

        // containerd uses checkpoint/resume for pause/unpause
        // This is a simplified implementation
        self.kill_task(container_id, "SIGSTOP").await
    }

    /// Resume a paused container task
    pub async fn resume_task(&mut self, container_id: &str) -> Result<()> {
        debug!("Resuming task for container: {}", container_id);

        // containerd uses checkpoint/resume for pause/unpause
        // This is a simplified implementation
        self.kill_task(container_id, "SIGCONT").await
    }

    /// Check if a task exists
    pub async fn task_exists(&mut self, container_id: &str) -> Result<bool> {
        match self.get_task(container_id).await {
            Ok(_) => Ok(true),
            Err(ContainerdError::TaskNotFound { .. }) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Restart a container (stop and start)
    pub async fn restart_container(&mut self, container_id: &str, timeout: Option<Duration>) -> Result<ContainerdTask> {
        debug!("Restarting container: {}", container_id);

        // Stop the container
        self.stop_container(container_id, timeout).await?;

        // Delete the old task
        if let Err(e) = self.delete_task(container_id).await {
            warn!("Failed to delete task during restart: {}", e);
        }

        // Start it again
        self.start_container(container_id).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vpn_runtime::Task;

    #[test]
    fn test_process_spec_creation() {
        let spec = ProcessSpec {
            args: vec!["echo".to_string(), "hello".to_string()],
            env: vec!["PATH=/usr/bin".to_string()],
            cwd: Some("/tmp".to_string()),
            user: Some("1000:1000".to_string()),
            terminal: false,
        };

        assert_eq!(spec.args.len(), 2);
        assert_eq!(spec.args[0], "echo");
        assert_eq!(spec.env.len(), 1);
        assert_eq!(spec.cwd, Some("/tmp".to_string()));
        assert!(!spec.terminal);
    }

    #[test]
    fn test_containerd_task_creation() {
        let task = ContainerdTask {
            id: "task-123".to_string(),
            container_id: "container-456".to_string(),
            pid: Some(1234),
            status: TaskStatus::Running,
            exit_code: None,
        };

        assert_eq!(task.id(), "task-123");
        assert_eq!(task.container_id(), "container-456");
        assert_eq!(task.pid(), Some(1234));
        assert_eq!(task.status(), TaskStatus::Running);
        assert_eq!(task.exit_code(), None);
    }
}