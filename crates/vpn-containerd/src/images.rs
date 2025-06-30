use crate::{ContainerdError, ContainerdImage, Result};
use chrono::{DateTime, Utc};
use containerd_client::services::v1::{
    images_client::ImagesClient,
    DeleteImageRequest, GetImageRequest, ListImagesRequest, PutImageRequest,
};
use std::collections::HashMap;
use tonic::transport::Channel;
use tracing::{debug, info, warn};
use vpn_runtime::ImageFilter;

/// Image management operations for containerd
pub struct ImageManager {
    client: ImagesClient<Channel>,
    namespace: String,
}

impl ImageManager {
    pub fn new(channel: Channel, namespace: String) -> Self {
        Self {
            client: ImagesClient::new(channel),
            namespace,
        }
    }

    /// List images with optional filtering
    pub async fn list_images(&mut self, filter: ImageFilter) -> Result<Vec<ContainerdImage>> {
        debug!("Listing images with filter: {:?}", filter);

        let mut filters = Vec::new();

        // Build containerd filters from ImageFilter
        if let Some(reference) = &filter.reference {
            filters.push(format!("name=={}", reference));
        }

        for (key, value) in &filter.labels {
            filters.push(format!("labels.{}=={}", key, value));
        }

        let request = ListImagesRequest {
            filters,
        };

        let response = self
            .client
            .list(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let mut images = Vec::new();
        for image in response.into_inner().images {
            images.push(self.convert_to_containerd_image(image)?);
        }

        debug!("Found {} images", images.len());
        Ok(images)
    }

    /// Get a specific image by reference
    pub async fn get_image(&mut self, reference: &str) -> Result<ContainerdImage> {
        debug!("Getting image: {}", reference);

        let request = GetImageRequest {
            name: reference.to_string(),
        };

        let response = self
            .client
            .get(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::ImageNotFound {
                    reference: reference.to_string(),
                },
                _ => ContainerdError::GrpcError(e),
            })?;

        let image = response.into_inner().image.ok_or_else(|| {
            ContainerdError::ImageNotFound {
                reference: reference.to_string(),
            }
        })?;

        Ok(self.convert_to_containerd_image(image)?)
    }

    /// Pull an image (simplified - would need content service integration)
    pub async fn pull_image(&mut self, reference: &str) -> Result<ContainerdImage> {
        debug!("Pulling image: {}", reference);

        // This is a simplified implementation
        // In a full implementation, we would need to:
        // 1. Use the content service to pull image layers
        // 2. Use the snapshots service to prepare rootfs
        // 3. Register the image with the images service

        // For now, we'll create a placeholder image entry
        let image_spec = containerd_client::types::Image {
            name: reference.to_string(),
            labels: HashMap::new(),
            target: None, // Would contain the actual image manifest
            created_at: Some(prost_types::Timestamp::from(std::time::SystemTime::now())),
            updated_at: Some(prost_types::Timestamp::from(std::time::SystemTime::now())),
        };

        let request = PutImageRequest {
            image: Some(image_spec),
        };

        let response = self
            .client
            .put(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let image = response.into_inner().image.ok_or_else(|| {
            ContainerdError::ImageNotFound {
                reference: reference.to_string(),
            }
        })?;

        info!("Image pulled successfully: {}", reference);
        Ok(self.convert_to_containerd_image(image)?)
    }

    /// Remove an image
    pub async fn remove_image(&mut self, reference: &str, _force: bool) -> Result<()> {
        debug!("Removing image: {}", reference);

        let request = DeleteImageRequest {
            name: reference.to_string(),
            sync: true, // Wait for deletion to complete
        };

        self.client
            .delete(request)
            .await
            .map_err(|e| match e.code() {
                tonic::Code::NotFound => ContainerdError::ImageNotFound {
                    reference: reference.to_string(),
                },
                _ => ContainerdError::GrpcError(e),
            })?;

        info!("Image removed successfully: {}", reference);
        Ok(())
    }

    /// Check if an image exists
    pub async fn image_exists(&mut self, reference: &str) -> Result<bool> {
        match self.get_image(reference).await {
            Ok(_) => Ok(true),
            Err(ContainerdError::ImageNotFound { .. }) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Update image labels
    pub async fn update_image_labels(
        &mut self,
        reference: &str,
        labels: HashMap<String, String>,
    ) -> Result<ContainerdImage> {
        debug!("Updating image labels: {}", reference);

        // Get current image
        let mut image = self.get_image(reference).await?;
        
        // Update labels
        image.labels.extend(labels);

        // Build update request
        let image_spec = containerd_client::types::Image {
            name: image.id.clone(),
            labels: image.labels.clone(),
            target: None, // Keep existing target
            created_at: None, // Keep existing creation time
            updated_at: Some(prost_types::Timestamp::from(std::time::SystemTime::now())),
        };

        let request = PutImageRequest {
            image: Some(image_spec),
        };

        self.client
            .put(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        Ok(image)
    }

    /// Get image size (from target manifest)
    pub async fn get_image_size(&mut self, reference: &str) -> Result<u64> {
        let image = self.get_image(reference).await?;
        Ok(image.size)
    }

    /// Tag an image with a new reference
    pub async fn tag_image(&mut self, source: &str, target: &str) -> Result<()> {
        debug!("Tagging image {} as {}", source, target);

        // Get the source image
        let source_image = self.get_image(source).await?;

        // Create a new image entry with the target name
        let image_spec = containerd_client::types::Image {
            name: target.to_string(),
            labels: source_image.labels.clone(),
            target: None, // Copy from source
            created_at: Some(prost_types::Timestamp::from(std::time::SystemTime::now())),
            updated_at: Some(prost_types::Timestamp::from(std::time::SystemTime::now())),
        };

        let request = PutImageRequest {
            image: Some(image_spec),
        };

        self.client
            .put(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        info!("Image tagged successfully: {} -> {}", source, target);
        Ok(())
    }

    /// Convert containerd image to our image type
    fn convert_to_containerd_image(
        &self,
        image: containerd_client::types::Image,
    ) -> Result<ContainerdImage> {
        // Parse creation time
        let created_at = image
            .created_at
            .map(|ts| {
                DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                    .unwrap_or_else(|| Utc::now())
            })
            .unwrap_or_else(Utc::now);

        // Extract tags from the image name
        let tags = if image.name.contains(':') {
            vec![image.name.clone()]
        } else {
            vec![format!("{}:latest", image.name)]
        };

        // Calculate size from target if available
        let size = image
            .target
            .as_ref()
            .map(|target| target.size as u64)
            .unwrap_or(0);

        Ok(ContainerdImage {
            id: image.name.clone(),
            tags,
            size,
            created_at,
            labels: image.labels,
        })
    }

    /// Prune unused images
    pub async fn prune_images(&mut self, dangling_only: bool) -> Result<Vec<String>> {
        debug!("Pruning unused images (dangling_only: {})", dangling_only);

        let all_images = self.list_images(ImageFilter::default()).await?;
        let mut pruned = Vec::new();

        for image in all_images {
            // Simple pruning logic - in reality would need to check if image is in use
            let should_prune = if dangling_only {
                // Check if image has no tags or is tagged as <none>
                image.tags.is_empty() || image.tags.iter().any(|tag| tag.contains("<none>"))
            } else {
                // More aggressive pruning - would need to check container usage
                false
            };

            if should_prune {
                match self.remove_image(&image.id, false).await {
                    Ok(_) => {
                        pruned.push(image.id.clone());
                        info!("Pruned image: {}", image.id);
                    }
                    Err(e) => {
                        warn!("Failed to prune image {}: {}", image.id, e);
                    }
                }
            }
        }

        info!("Pruned {} images", pruned.len());
        Ok(pruned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_image_filter_creation() {
        let mut labels = HashMap::new();
        labels.insert("version".to_string(), "1.0".to_string());

        let filter = ImageFilter {
            reference: Some("alpine:latest".to_string()),
            labels,
        };

        assert_eq!(filter.reference, Some("alpine:latest".to_string()));
        assert_eq!(filter.labels.len(), 1);
        assert_eq!(filter.labels.get("version"), Some(&"1.0".to_string()));
    }

    #[test]
    fn test_containerd_image_creation() {
        let mut labels = HashMap::new();
        labels.insert("maintainer".to_string(), "test".to_string());

        let image = ContainerdImage {
            id: "alpine:latest".to_string(),
            tags: vec!["alpine:latest".to_string(), "alpine:3.18".to_string()],
            size: 5000000,
            created_at: Utc::now(),
            labels,
        };

        assert_eq!(image.id(), "alpine:latest");
        assert_eq!(image.tags().len(), 2);
        assert_eq!(image.size(), 5000000);
        assert_eq!(image.labels().len(), 1);
    }
}