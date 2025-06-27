use bollard::Docker;
use bollard::container::{Config, CreateContainerOptions, StartContainerOptions, StopContainerOptions, RemoveContainerOptions};
use bollard::models::{ContainerSummary, ContainerInspectResponse};
use bollard::exec::{CreateExecOptions, StartExecResults};
use futures_util::stream::StreamExt;
use std::collections::HashMap;
use crate::error::{DockerError, Result};

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
}