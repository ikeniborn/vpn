use crate::{ContainerdError, ContainerdVolume, MountSpec, Result, SnapshotInfo, SnapshotKind};
use chrono::{DateTime, Utc};
use containerd_client::services::v1::{
    // snapshots_client::SnapshotsClient, // Missing in 0.8.0
    // CommitSnapshotRequest, ListSnapshotsRequest, PrepareSnapshotRequest, RemoveSnapshotRequest,
    // StatSnapshotRequest, ViewSnapshotRequest, MountsRequest, // Missing in 0.8.0
};
use std::collections::HashMap;
use tonic::transport::Channel;
use tracing::{debug, info, warn};
use vpn_runtime::{VolumeFilter, VolumeSpec};

/// Snapshot/Volume management operations for containerd
pub struct SnapshotManager {
    client: SnapshotsClient<Channel>,
    namespace: String,
    snapshotter: String,
}

impl SnapshotManager {
    pub fn new(channel: Channel, namespace: String, snapshotter: String) -> Self {
        Self {
            client: SnapshotsClient::new(channel),
            namespace,
            snapshotter,
        }
    }

    /// Create a new volume (snapshot)
    pub async fn create_volume(&mut self, spec: VolumeSpec) -> Result<ContainerdVolume> {
        debug!("Creating volume: {}", spec.name);

        // Prepare a new snapshot
        let request = PrepareSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: spec.name.clone(),
            parent: String::new(), // Empty for new volumes
            labels: spec.labels.clone(),
        };

        let response = self
            .client
            .prepare(request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "prepare".to_string(),
                message: e.to_string(),
            })?;

        let mounts = response.into_inner().mounts;
        let mount_point = mounts.first().map(|m| m.target.clone());

        // Commit the snapshot to make it a permanent volume
        let commit_request = CommitSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            name: format!("{}-committed", spec.name),
            key: spec.name.clone(),
            labels: spec.labels.clone(),
        };

        self.client
            .commit(commit_request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "commit".to_string(),
                message: e.to_string(),
            })?;

        info!("Volume created successfully: {}", spec.name);

        Ok(ContainerdVolume {
            name: spec.name,
            driver: self.snapshotter.clone(),
            mount_point,
            labels: spec.labels,
            created_at: Utc::now(),
        })
    }

    /// List volumes (snapshots) with optional filtering
    pub async fn list_volumes(&mut self, filter: VolumeFilter) -> Result<Vec<ContainerdVolume>> {
        debug!("Listing volumes with filter: {:?}", filter);

        let mut filters = Vec::new();

        // Build containerd filters from VolumeFilter
        if !filter.names.is_empty() {
            for name in &filter.names {
                filters.push(format!("name=={}", name));
            }
        }

        for (key, value) in &filter.labels {
            filters.push(format!("labels.{}=={}", key, value));
        }

        let request = ListSnapshotsRequest {
            snapshotter: self.snapshotter.clone(),
            filters,
        };

        let response = self
            .client
            .list(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let mut volumes = Vec::new();
        for snapshot in response.into_inner().info {
            let volume = self.convert_to_containerd_volume(snapshot)?;
            
            // Apply driver filtering if specified
            if !filter.drivers.is_empty() && !filter.drivers.contains(&volume.driver) {
                continue;
            }

            volumes.push(volume);
        }

        debug!("Found {} volumes", volumes.len());
        Ok(volumes)
    }

    /// Get a specific volume by name
    pub async fn get_volume(&mut self, name: &str) -> Result<ContainerdVolume> {
        debug!("Getting volume: {}", name);

        let request = StatSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: name.to_string(),
        };

        let response = self
            .client
            .stat(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::SnapshotNotFound { key: name.to_string() },
                _ => ContainerdError::GrpcError(e),
            })?;

        let snapshot = response.into_inner().info.ok_or_else(|| {
            ContainerdError::SnapshotNotFound { key: name.to_string() }
        })?;

        Ok(self.convert_to_containerd_volume(snapshot)?)
    }

    /// Remove a volume (snapshot)
    pub async fn remove_volume(&mut self, name: &str, _force: bool) -> Result<()> {
        debug!("Removing volume: {}", name);

        let request = RemoveSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: name.to_string(),
        };

        self.client
            .remove(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::SnapshotNotFound { key: name.to_string() },
                _ => ContainerdError::GrpcError(e),
            })?;

        info!("Volume removed successfully: {}", name);
        Ok(())
    }

    /// Check if a volume exists
    pub async fn volume_exists(&mut self, name: &str) -> Result<bool> {
        match self.get_volume(name).await {
            Ok(_) => Ok(true),
            Err(ContainerdError::SnapshotNotFound { .. }) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Backup a volume by creating a snapshot clone
    pub async fn backup_volume(&mut self, name: &str, backup_name: &str) -> Result<()> {
        debug!("Backing up volume {} to {}", name, backup_name);

        // Create a view snapshot (read-only clone)
        let request = ViewSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: backup_name.to_string(),
            parent: name.to_string(),
            labels: {
                let mut labels = HashMap::new();
                labels.insert("backup.source".to_string(), name.to_string());
                labels.insert("backup.created_at".to_string(), Utc::now().to_rfc3339());
                labels
            },
        };

        self.client
            .view(request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "backup".to_string(),
                message: e.to_string(),
            })?;

        info!("Volume backed up successfully: {} -> {}", name, backup_name);
        Ok(())
    }

    /// Restore a volume from a backup
    pub async fn restore_volume(&mut self, name: &str, backup_name: &str) -> Result<()> {
        debug!("Restoring volume {} from backup {}", name, backup_name);

        // Remove the existing volume if it exists
        if self.volume_exists(name).await? {
            self.remove_volume(name, true).await?;
        }

        // Create a new active snapshot from the backup
        let request = PrepareSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: name.to_string(),
            parent: backup_name.to_string(),
            labels: {
                let mut labels = HashMap::new();
                labels.insert("restored.from".to_string(), backup_name.to_string());
                labels.insert("restored.at".to_string(), Utc::now().to_rfc3339());
                labels
            },
        };

        self.client
            .prepare(request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "restore".to_string(),
                message: e.to_string(),
            })?;

        info!("Volume restored successfully: {} <- {}", name, backup_name);
        Ok(())
    }

    /// Get mount information for a volume
    pub async fn get_volume_mounts(&mut self, name: &str) -> Result<Vec<MountSpec>> {
        debug!("Getting mounts for volume: {}", name);

        let request = MountsRequest {
            snapshotter: self.snapshotter.clone(),
            key: name.to_string(),
        };

        let response = self
            .client
            .mounts(request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "mounts".to_string(),
                message: e.to_string(),
            })?;

        let mut mounts = Vec::new();
        for mount in response.into_inner().mounts {
            mounts.push(MountSpec {
                mount_type: mount.r#type,
                source: mount.source,
                target: mount.target,
                options: mount.options,
            });
        }

        Ok(mounts)
    }

    /// Clone a volume (create a new volume from an existing one)
    pub async fn clone_volume(&mut self, source: &str, target: &str) -> Result<ContainerdVolume> {
        debug!("Cloning volume {} to {}", source, target);

        // Prepare a new snapshot from the source
        let request = PrepareSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: target.to_string(),
            parent: source.to_string(),
            labels: {
                let mut labels = HashMap::new();
                labels.insert("cloned.from".to_string(), source.to_string());
                labels.insert("cloned.at".to_string(), Utc::now().to_rfc3339());
                labels
            },
        };

        let response = self
            .client
            .prepare(request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "clone".to_string(),
                message: e.to_string(),
            })?;

        let mounts = response.into_inner().mounts;
        let mount_point = mounts.first().map(|m| m.target.clone());

        // Commit the cloned snapshot
        let commit_request = CommitSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            name: format!("{}-committed", target),
            key: target.to_string(),
            labels: HashMap::new(),
        };

        self.client
            .commit(commit_request)
            .await
            .map_err(|e| ContainerdError::SnapshotOperationFailed {
                operation: "commit".to_string(),
                message: e.to_string(),
            })?;

        info!("Volume cloned successfully: {} -> {}", source, target);

        Ok(ContainerdVolume {
            name: target.to_string(),
            driver: self.snapshotter.clone(),
            mount_point,
            labels: HashMap::new(),
            created_at: Utc::now(),
        })
    }

    /// Get snapshot information
    pub async fn get_snapshot_info(&mut self, key: &str) -> Result<SnapshotInfo> {
        debug!("Getting snapshot info: {}", key);

        let request = StatSnapshotRequest {
            snapshotter: self.snapshotter.clone(),
            key: key.to_string(),
        };

        let response = self
            .client
            .stat(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let info = response.into_inner().info.ok_or_else(|| {
            ContainerdError::SnapshotNotFound { key: key.to_string() }
        })?;

        let kind = match info.kind {
            0 => SnapshotKind::View,
            1 => SnapshotKind::Active,
            2 => SnapshotKind::Committed,
            _ => SnapshotKind::View,
        };

        Ok(SnapshotInfo {
            key: info.name,
            parent: if info.parent.is_empty() { None } else { Some(info.parent) },
            kind,
            created_at: info.created_at
                .map(|ts| DateTime::from_timestamp(ts.seconds, ts.nanos as u32).unwrap_or_else(|| Utc::now()))
                .unwrap_or_else(Utc::now),
            updated_at: info.updated_at
                .map(|ts| DateTime::from_timestamp(ts.seconds, ts.nanos as u32).unwrap_or_else(|| Utc::now()))
                .unwrap_or_else(Utc::now),
        })
    }

    /// Convert containerd snapshot info to our volume type
    fn convert_to_containerd_volume(
        &self,
        info: containerd_client::types::Info,
    ) -> Result<ContainerdVolume> {
        let created_at = info.created_at
            .map(|ts| DateTime::from_timestamp(ts.seconds, ts.nanos as u32).unwrap_or_else(|| Utc::now()))
            .unwrap_or_else(Utc::now);

        Ok(ContainerdVolume {
            name: info.name,
            driver: self.snapshotter.clone(),
            mount_point: None, // Would need to call mounts() to get this
            labels: info.labels,
            created_at,
        })
    }

    /// Prune unused snapshots
    pub async fn prune_volumes(&mut self) -> Result<Vec<String>> {
        debug!("Pruning unused volumes");

        // This is a simplified implementation
        // In reality, we would need to check which snapshots are in use by containers
        let all_volumes = self.list_volumes(VolumeFilter::default()).await?;
        let mut pruned = Vec::new();

        for volume in all_volumes {
            // Simple heuristic - remove volumes with backup labels that are old
            if let Some(created_str) = volume.labels.get("backup.created_at") {
                if let Ok(created) = DateTime::parse_from_rfc3339(created_str) {
                    let age = Utc::now().signed_duration_since(created.with_timezone(&Utc));
                    if age.num_days() > 7 {
                        match self.remove_volume(&volume.name, false).await {
                            Ok(_) => {
                                pruned.push(volume.name.clone());
                                info!("Pruned old backup volume: {}", volume.name);
                            }
                            Err(e) => {
                                warn!("Failed to prune volume {}: {}", volume.name, e);
                            }
                        }
                    }
                }
            }
        }

        info!("Pruned {} volumes", pruned.len());
        Ok(pruned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_volume_spec_creation() {
        let mut labels = HashMap::new();
        labels.insert("purpose".to_string(), "data".to_string());

        let spec = VolumeSpec {
            name: "test-volume".to_string(),
            driver: "overlayfs".to_string(),
            driver_opts: HashMap::new(),
            labels,
        };

        assert_eq!(spec.name, "test-volume");
        assert_eq!(spec.driver, "overlayfs");
        assert_eq!(spec.labels.len(), 1);
    }

    #[test]
    fn test_snapshot_info_creation() {
        let info = SnapshotInfo {
            key: "test-snapshot".to_string(),
            parent: Some("parent-snapshot".to_string()),
            kind: SnapshotKind::Active,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        assert_eq!(info.key, "test-snapshot");
        assert_eq!(info.parent, Some("parent-snapshot".to_string()));
        assert_eq!(info.kind, SnapshotKind::Active);
    }

    #[test]
    fn test_mount_spec_creation() {
        let mount = MountSpec {
            mount_type: "overlay".to_string(),
            source: "/var/lib/containerd/snapshots".to_string(),
            target: "/mnt/container".to_string(),
            options: vec!["rw".to_string(), "relatime".to_string()],
        };

        assert_eq!(mount.mount_type, "overlay");
        assert_eq!(mount.source, "/var/lib/containerd/snapshots");
        assert_eq!(mount.target, "/mnt/container");
        assert_eq!(mount.options.len(), 2);
    }
}