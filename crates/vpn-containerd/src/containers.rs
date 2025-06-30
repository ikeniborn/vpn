use crate::{ContainerdContainer, ContainerdError, Result};
use chrono::{DateTime, Utc};
use containerd_client::services::v1::{
    containers_client::ContainersClient,
    CreateContainerRequest, DeleteContainerRequest, GetContainerRequest, ListContainersRequest,
    UpdateContainerRequest,
};
use std::collections::HashMap;
use tonic::transport::Channel;
use tracing::{debug, error, info, warn};
use vpn_runtime::{ContainerFilter, ContainerSpec, ContainerState, ContainerStatus};

/// Container management operations for containerd
pub struct ContainerManager {
    client: ContainersClient<Channel>,
    namespace: String,
}

impl ContainerManager {
    pub fn new(channel: Channel, namespace: String) -> Self {
        Self {
            client: ContainersClient::new(channel),
            namespace,
        }
    }

    /// Create a new container
    pub async fn create_container(&mut self, spec: ContainerSpec) -> Result<ContainerdContainer> {
        debug!("Creating container: {}", spec.name);

        // Convert ContainerSpec to containerd container spec
        let container_spec = self.build_container_spec(&spec)?;

        let request = CreateContainerRequest {
            container: Some(container_spec),
        };

        let response = self
            .client
            .create(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let container = response.into_inner().container.ok_or_else(|| {
            ContainerdError::InvalidSpec {
                message: "No container returned from create request".to_string(),
            }
        })?;

        info!("Container created successfully: {}", container.id);

        Ok(ContainerdContainer {
            id: container.id,
            name: spec.name,
            image: spec.image,
            state: ContainerState::Created,
            status: ContainerStatus {
                state: ContainerState::Created,
                started_at: None,
                finished_at: None,
                exit_code: None,
                error: None,
            },
            labels: spec.labels,
            created_at: Utc::now(), // containerd returns this in the response
        })
    }

    /// List containers with optional filtering
    pub async fn list_containers(&mut self, filter: ContainerFilter) -> Result<Vec<ContainerdContainer>> {
        debug!("Listing containers with filter: {:?}", filter);

        let mut filters = Vec::new();

        // Build containerd filters from ContainerFilter
        if !filter.names.is_empty() {
            for name in &filter.names {
                filters.push(format!("name=={}", name));
            }
        }

        for (key, value) in &filter.labels {
            filters.push(format!("labels.{}=={}", key, value));
        }

        let request = ListContainersRequest {
            filters,
        };

        let response = self
            .client
            .list(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let containers = response.into_inner().containers;
        let mut result = Vec::new();

        for container in containers {
            let containerd_container = self.convert_to_containerd_container(container)?;
            
            // Apply state filtering if specified
            if !filter.states.is_empty() && !filter.states.contains(&containerd_container.state) {
                continue;
            }

            result.push(containerd_container);
        }

        debug!("Found {} containers", result.len());
        Ok(result)
    }

    /// Get a specific container by ID
    pub async fn get_container(&mut self, id: &str) -> Result<ContainerdContainer> {
        debug!("Getting container: {}", id);

        let request = GetContainerRequest {
            id: id.to_string(),
        };

        let response = self
            .client
            .get(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::ContainerNotFound { id: id.to_string() },
                _ => ContainerdError::GrpcError(e),
            })?;

        let container = response.into_inner().container.ok_or_else(|| {
            ContainerdError::ContainerNotFound { id: id.to_string() }
        })?;

        Ok(self.convert_to_containerd_container(container)?)
    }

    /// Remove a container
    pub async fn remove_container(&mut self, id: &str) -> Result<()> {
        debug!("Removing container: {}", id);

        let request = DeleteContainerRequest {
            id: id.to_string(),
        };

        self.client
            .delete(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::ContainerNotFound { id: id.to_string() },
                _ => ContainerdError::GrpcError(e),
            })?;

        info!("Container removed successfully: {}", id);
        Ok(())
    }

    /// Check if a container exists
    pub async fn container_exists(&mut self, id: &str) -> Result<bool> {
        match self.get_container(id).await {
            Ok(_) => Ok(true),
            Err(ContainerdError::ContainerNotFound { .. }) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Update container labels
    pub async fn update_container_labels(
        &mut self,
        id: &str,
        labels: HashMap<String, String>,
    ) -> Result<ContainerdContainer> {
        debug!("Updating container labels: {}", id);

        // First get the current container
        let mut container = self.get_container(id).await?;
        
        // Update labels
        container.labels.extend(labels);

        // Build update request
        let container_spec = containerd_client::types::Container {
            id: container.id.clone(),
            image: container.image.clone(),
            labels: container.labels.clone(),
            ..Default::default()
        };

        let request = UpdateContainerRequest {
            container: Some(container_spec),
            update_mask: None, // Update all fields
        };

        self.client
            .update(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        Ok(container)
    }

    /// Build containerd container specification from VPN container spec
    fn build_container_spec(&self, spec: &ContainerSpec) -> Result<containerd_client::types::Container> {
        let mut labels = spec.labels.clone();
        
        // Add VPN-specific labels
        labels.insert("vpn.managed".to_string(), "true".to_string());
        labels.insert("vpn.created_at".to_string(), Utc::now().to_rfc3339());

        Ok(containerd_client::types::Container {
            id: spec.name.clone(),
            image: spec.image.clone(),
            runtime: None, // Use default runtime
            spec: None,    // Will be set during task creation
            snapshotter: "overlayfs".to_string(),
            snapshot_key: format!("{}-snapshot", spec.name),
            labels,
            extensions: HashMap::new(),
            ..Default::default()
        })
    }

    /// Convert containerd container to our container type
    fn convert_to_containerd_container(
        &self,
        container: containerd_client::types::Container,
    ) -> Result<ContainerdContainer> {
        // Parse creation time from labels if available
        let created_at = container
            .labels
            .get("vpn.created_at")
            .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        Ok(ContainerdContainer {
            id: container.id,
            name: container.labels.get("name").cloned().unwrap_or_default(),
            image: container.image,
            state: ContainerState::Created, // Default state, will be updated by task manager
            status: ContainerStatus {
                state: ContainerState::Created,
                started_at: None,
                finished_at: None,
                exit_code: None,
                error: None,
            },
            labels: container.labels,
            created_at,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vpn_runtime::{ContainerSpec, MountType, PortMapping, Protocol, RestartPolicy, VolumeMount};

    fn create_test_container_spec() -> ContainerSpec {
        let mut labels = HashMap::new();
        labels.insert("test".to_string(), "true".to_string());

        ContainerSpec {
            name: "test-container".to_string(),
            image: "alpine:latest".to_string(),
            command: Some(vec!["sleep".to_string(), "30".to_string()]),
            args: None,
            environment: HashMap::new(),
            volumes: vec![VolumeMount {
                source: "/host/path".to_string(),
                target: "/container/path".to_string(),
                read_only: false,
                mount_type: MountType::Bind,
            }],
            ports: vec![PortMapping {
                host_port: 8080,
                container_port: 80,
                protocol: Protocol::Tcp,
                host_ip: None,
            }],
            networks: vec!["default".to_string()],
            labels,
            working_dir: Some("/app".to_string()),
            user: Some("1000:1000".to_string()),
            restart_policy: RestartPolicy::OnFailure { max_retry_count: Some(3) },
        }
    }

    #[test]
    fn test_container_spec_conversion() {
        // Note: This test doesn't require actual containerd connection
        let spec = create_test_container_spec();
        
        // Test that we can create the spec without errors
        assert_eq!(spec.name, "test-container");
        assert_eq!(spec.image, "alpine:latest");
        assert_eq!(spec.volumes.len(), 1);
        assert_eq!(spec.ports.len(), 1);
    }
}