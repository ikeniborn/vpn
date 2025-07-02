use bollard::Docker;
use bollard::volume::{CreateVolumeOptions, ListVolumesOptions, RemoveVolumeOptions};
use bollard::models::Volume;
use std::collections::HashMap;
use futures_util::StreamExt;
use crate::error::{DockerError, Result};

pub struct VolumeManager {
    docker: Docker,
}

#[derive(Debug, Clone)]
pub struct VolumeInfo {
    pub name: String,
    pub driver: String,
    pub mountpoint: String,
    pub labels: HashMap<String, String>,
    pub options: HashMap<String, String>,
}

impl VolumeManager {
    pub fn new() -> Result<Self> {
        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| DockerError::ConnectionError(e.to_string()))?;
        Ok(Self { docker })
    }
    
    pub async fn create_volume(
        &self,
        name: &str,
        driver: Option<&str>,
        labels: Option<HashMap<String, String>>,
    ) -> Result<VolumeInfo> {
        let config = CreateVolumeOptions {
            name,
            driver: driver.unwrap_or("local"),
            driver_opts: HashMap::new(),
            labels: labels.as_ref().map(|l| l.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect()).unwrap_or_default(),
        };
        
        let volume = self.docker.create_volume(config).await?;
        self.volume_to_info(volume)
    }
    
    pub async fn list_volumes(&self, filters: Option<HashMap<&str, Vec<&str>>>) -> Result<Vec<VolumeInfo>> {
        let options = ListVolumesOptions {
            filters: filters.unwrap_or_default(),
        };
        
        let response = self.docker.list_volumes(Some(options)).await?;
        
        let mut volumes = Vec::new();
        if let Some(volume_list) = response.volumes {
            for volume in volume_list {
                if let Ok(info) = self.volume_to_info(volume) {
                    volumes.push(info);
                }
            }
        }
        
        Ok(volumes)
    }
    
    pub async fn inspect_volume(&self, name: &str) -> Result<VolumeInfo> {
        let volume = self.docker.inspect_volume(name).await
            .map_err(|_| DockerError::VolumeError(format!("Volume {} not found", name)))?;
        self.volume_to_info(volume)
    }
    
    pub async fn remove_volume(&self, name: &str, force: bool) -> Result<()> {
        let options = RemoveVolumeOptions {
            force,
        };
        
        self.docker.remove_volume(name, Some(options)).await?;
        Ok(())
    }
    
    pub async fn volume_exists(&self, name: &str) -> bool {
        self.inspect_volume(name).await.is_ok()
    }
    
    pub async fn backup_volume(&self, volume_name: &str, backup_path: &str) -> Result<()> {
        let backup_file = format!("/backup/{}.tar.gz", volume_name);
        let tar_cmd = vec![
            "tar",
            "-czf",
            &backup_file,
            "-C",
            "/volume",
            ".",
        ];
        
        let backup_config = bollard::container::Config {
            image: Some("alpine:latest"),
            cmd: Some(tar_cmd),
            host_config: Some(bollard::models::HostConfig {
                binds: Some(vec![
                    format!("{}:/volume:ro", volume_name),
                    format!("{}:/backup", backup_path),
                ]),
                ..Default::default()
            }),
            ..Default::default()
        };
        
        let container_name = format!("backup-{}-{}", volume_name, chrono::Utc::now().timestamp());
        
        let options = bollard::container::CreateContainerOptions {
            name: container_name.as_str(),
            ..Default::default()
        };
        
        let container = self.docker.create_container(Some(options), backup_config).await?;
        self.docker.start_container(&container.id, None::<bollard::container::StartContainerOptions<String>>).await?;
        
        let mut wait_stream = self.docker.wait_container(&container.id, None::<bollard::container::WaitContainerOptions<String>>);
        while let Some(_) = wait_stream.next().await {}
        // Explicitly drop the stream to free resources
        drop(wait_stream);
        
        self.docker.remove_container(&container.id, None).await?;
        
        Ok(())
    }
    
    pub async fn restore_volume(&self, volume_name: &str, backup_path: &str) -> Result<()> {
        if !self.volume_exists(volume_name).await {
            self.create_volume(volume_name, None, None).await?;
        }
        
        let backup_file = format!("/backup/{}.tar.gz", volume_name);
        let tar_cmd = vec![
            "tar",
            "-xzf",
            &backup_file,
            "-C",
            "/volume",
        ];
        
        let restore_config = bollard::container::Config {
            image: Some("alpine:latest"),
            cmd: Some(tar_cmd),
            host_config: Some(bollard::models::HostConfig {
                binds: Some(vec![
                    format!("{}:/volume", volume_name),
                    format!("{}:/backup:ro", backup_path),
                ]),
                ..Default::default()
            }),
            ..Default::default()
        };
        
        let container_name = format!("restore-{}-{}", volume_name, chrono::Utc::now().timestamp());
        
        let options = bollard::container::CreateContainerOptions {
            name: container_name.as_str(),
            ..Default::default()
        };
        
        let container = self.docker.create_container(Some(options), restore_config).await?;
        self.docker.start_container(&container.id, None::<bollard::container::StartContainerOptions<String>>).await?;
        
        let mut wait_stream = self.docker.wait_container(&container.id, None::<bollard::container::WaitContainerOptions<String>>);
        while let Some(_) = wait_stream.next().await {}
        // Explicitly drop the stream to free resources
        drop(wait_stream);
        
        self.docker.remove_container(&container.id, None).await?;
        
        Ok(())
    }
    
    fn volume_to_info(&self, volume: Volume) -> Result<VolumeInfo> {
        Ok(VolumeInfo {
            name: volume.name,
            driver: volume.driver,
            mountpoint: volume.mountpoint,
            labels: volume.labels,
            options: volume.options,
        })
    }
}