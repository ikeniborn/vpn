use crate::{ContainerdError, Result};
use chrono::{DateTime, Utc};
use containerd_client::services::v1::{
    events_client::EventsClient,
    SubscribeRequest,
};
use futures_util::{Stream, StreamExt};
use serde_json::Value;
use std::pin::Pin;
use tonic::transport::Channel;
use tracing::{debug, info, warn, error};
use base64::prelude::*;

/// containerd event types
#[derive(Debug, Clone, PartialEq)]
pub enum ContainerdEventType {
    /// Container lifecycle events
    ContainerCreate,
    ContainerStart,
    ContainerStop,
    ContainerDelete,
    ContainerPause,
    ContainerResume,
    
    /// Task lifecycle events
    TaskCreate,
    TaskStart,
    TaskExit,
    TaskDelete,
    TaskPause,
    TaskResume,
    
    /// Image events
    ImagePull,
    ImagePush,
    ImageDelete,
    
    /// Snapshot events
    SnapshotPrepare,
    SnapshotCommit,
    SnapshotRemove,
    
    /// Generic/Unknown events
    Unknown(String),
}

impl From<&str> for ContainerdEventType {
    fn from(topic: &str) -> Self {
        match topic {
            "/containers/create" => ContainerdEventType::ContainerCreate,
            "/containers/start" => ContainerdEventType::ContainerStart,
            "/containers/stop" => ContainerdEventType::ContainerStop,
            "/containers/delete" => ContainerdEventType::ContainerDelete,
            "/containers/pause" => ContainerdEventType::ContainerPause,
            "/containers/resume" => ContainerdEventType::ContainerResume,
            "/tasks/create" => ContainerdEventType::TaskCreate,
            "/tasks/start" => ContainerdEventType::TaskStart,
            "/tasks/exit" => ContainerdEventType::TaskExit,
            "/tasks/delete" => ContainerdEventType::TaskDelete,
            "/tasks/pause" => ContainerdEventType::TaskPause,
            "/tasks/resume" => ContainerdEventType::TaskResume,
            "/images/pull" => ContainerdEventType::ImagePull,
            "/images/push" => ContainerdEventType::ImagePush,
            "/images/delete" => ContainerdEventType::ImageDelete,
            "/snapshots/prepare" => ContainerdEventType::SnapshotPrepare,
            "/snapshots/commit" => ContainerdEventType::SnapshotCommit,
            "/snapshots/remove" => ContainerdEventType::SnapshotRemove,
            other => ContainerdEventType::Unknown(other.to_string()),
        }
    }
}

impl ToString for ContainerdEventType {
    fn to_string(&self) -> String {
        match self {
            ContainerdEventType::ContainerCreate => "/containers/create".to_string(),
            ContainerdEventType::ContainerStart => "/containers/start".to_string(),
            ContainerdEventType::ContainerStop => "/containers/stop".to_string(),
            ContainerdEventType::ContainerDelete => "/containers/delete".to_string(),
            ContainerdEventType::ContainerPause => "/containers/pause".to_string(),
            ContainerdEventType::ContainerResume => "/containers/resume".to_string(),
            ContainerdEventType::TaskCreate => "/tasks/create".to_string(),
            ContainerdEventType::TaskStart => "/tasks/start".to_string(),
            ContainerdEventType::TaskExit => "/tasks/exit".to_string(),
            ContainerdEventType::TaskDelete => "/tasks/delete".to_string(),
            ContainerdEventType::TaskPause => "/tasks/pause".to_string(),
            ContainerdEventType::TaskResume => "/tasks/resume".to_string(),
            ContainerdEventType::ImagePull => "/images/pull".to_string(),
            ContainerdEventType::ImagePush => "/images/push".to_string(),
            ContainerdEventType::ImageDelete => "/images/delete".to_string(),
            ContainerdEventType::SnapshotPrepare => "/snapshots/prepare".to_string(),
            ContainerdEventType::SnapshotCommit => "/snapshots/commit".to_string(),
            ContainerdEventType::SnapshotRemove => "/snapshots/remove".to_string(),
            ContainerdEventType::Unknown(topic) => topic.clone(),
        }
    }
}

/// containerd event information
#[derive(Debug, Clone)]
pub struct ContainerdEvent {
    pub timestamp: DateTime<Utc>,
    pub namespace: String,
    pub topic: String,
    pub event_type: ContainerdEventType,
    pub event_data: Value,
}

impl ContainerdEvent {
    /// Get the container ID from the event data if available
    pub fn container_id(&self) -> Option<String> {
        self.event_data
            .get("id")
            .or_else(|| self.event_data.get("container_id"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    /// Get the image reference from the event data if available
    pub fn image_ref(&self) -> Option<String> {
        self.event_data
            .get("image")
            .or_else(|| self.event_data.get("ref"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    /// Check if this event is related to VPN-managed containers
    pub fn is_vpn_managed(&self) -> bool {
        if let Some(labels) = self.event_data.get("labels") {
            if let Some(labels_obj) = labels.as_object() {
                return labels_obj.contains_key("vpn.managed");
            }
        }
        false
    }
}

/// Event filter for subscription
#[derive(Debug, Clone)]
pub struct EventFilter {
    pub event_types: Vec<ContainerdEventType>,
    pub namespaces: Vec<String>,
    pub container_ids: Vec<String>,
    pub labels: std::collections::HashMap<String, String>,
    pub vpn_managed_only: bool,
}

impl Default for EventFilter {
    fn default() -> Self {
        Self {
            event_types: vec![],
            namespaces: vec!["default".to_string()],
            container_ids: vec![],
            labels: std::collections::HashMap::new(),
            vpn_managed_only: true, // By default, only show VPN-managed events
        }
    }
}

impl EventFilter {
    /// Create a filter for all container events
    pub fn container_events() -> Self {
        Self {
            event_types: vec![
                ContainerdEventType::ContainerCreate,
                ContainerdEventType::ContainerStart,
                ContainerdEventType::ContainerStop,
                ContainerdEventType::ContainerDelete,
                ContainerdEventType::ContainerPause,
                ContainerdEventType::ContainerResume,
            ],
            ..Default::default()
        }
    }

    /// Create a filter for all task events
    pub fn task_events() -> Self {
        Self {
            event_types: vec![
                ContainerdEventType::TaskCreate,
                ContainerdEventType::TaskStart,
                ContainerdEventType::TaskExit,
                ContainerdEventType::TaskDelete,
                ContainerdEventType::TaskPause,
                ContainerdEventType::TaskResume,
            ],
            ..Default::default()
        }
    }

    /// Create a filter for all image events
    pub fn image_events() -> Self {
        Self {
            event_types: vec![
                ContainerdEventType::ImagePull,
                ContainerdEventType::ImagePush,
                ContainerdEventType::ImageDelete,
            ],
            ..Default::default()
        }
    }

    /// Check if an event matches this filter
    pub fn matches(&self, event: &ContainerdEvent) -> bool {
        // Check event types
        if !self.event_types.is_empty() && !self.event_types.contains(&event.event_type) {
            return false;
        }

        // Check namespaces
        if !self.namespaces.is_empty() && !self.namespaces.contains(&event.namespace) {
            return false;
        }

        // Check container IDs
        if !self.container_ids.is_empty() {
            if let Some(container_id) = event.container_id() {
                if !self.container_ids.contains(&container_id) {
                    return false;
                }
            } else {
                return false;
            }
        }

        // Check VPN managed filter
        if self.vpn_managed_only && !event.is_vpn_managed() {
            return false;
        }

        // Check labels
        if !self.labels.is_empty() {
            if let Some(event_labels) = event.event_data.get("labels") {
                if let Some(labels_obj) = event_labels.as_object() {
                    for (key, value) in &self.labels {
                        if let Some(event_value) = labels_obj.get(key) {
                            if event_value.as_str() != Some(value) {
                                return false;
                            }
                        } else {
                            return false;
                        }
                    }
                } else {
                    return false;
                }
            } else {
                return false;
            }
        }

        true
    }

    /// Convert to containerd filter strings
    pub fn to_containerd_filters(&self) -> Vec<String> {
        let mut filters = Vec::new();

        // Add topic filters
        for event_type in &self.event_types {
            filters.push(format!("topic=={}", event_type.to_string()));
        }

        // Add namespace filters
        for namespace in &self.namespaces {
            filters.push(format!("namespace=={}", namespace));
        }

        // Add container ID filters
        for container_id in &self.container_ids {
            filters.push(format!("id=={}", container_id));
        }

        // Add label filters
        for (key, value) in &self.labels {
            filters.push(format!("labels.{}=={}", key, value));
        }

        // Add VPN managed filter
        if self.vpn_managed_only {
            filters.push("labels.vpn.managed==true".to_string());
        }

        filters
    }
}

/// Event stream type
pub type EventStream = Pin<Box<dyn Stream<Item = Result<ContainerdEvent>> + Send>>;

/// Event callback function type
pub type EventCallback = Box<dyn Fn(ContainerdEvent) + Send + Sync>;

/// Event management for containerd
pub struct EventManager {
    client: EventsClient<Channel>,
    namespace: String,
}

impl EventManager {
    pub fn new(channel: Channel, namespace: String) -> Self {
        Self {
            client: EventsClient::new(channel),
            namespace,
        }
    }

    /// Subscribe to events with filtering
    pub async fn subscribe_events(&mut self, filter: EventFilter) -> Result<EventStream> {
        debug!("Subscribing to containerd events with filter: {:?}", filter);

        let filters = filter.to_containerd_filters();
        let request = SubscribeRequest { filters };

        let response = self
            .client
            .subscribe(request)
            .await
            .map_err(|e| ContainerdError::GrpcError(e))?;

        let stream = response.into_inner();
        let filter_clone = filter.clone();

        let event_stream = stream.map(move |envelope_result| {
            match envelope_result {
                Ok(envelope) => {
                    let timestamp = envelope
                        .timestamp
                        .map(|ts| {
                            DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                                .unwrap_or_else(|| Utc::now())
                        })
                        .unwrap_or_else(Utc::now);

                    let namespace = envelope.namespace;
                    let topic = envelope.topic;
                    let event_type = ContainerdEventType::from(topic.as_str());

                    // Parse event data from protobuf Any type
                    let event_data = if let Some(event_any) = envelope.event {
                        // Try to parse as JSON if possible, otherwise create minimal data
                        serde_json::json!({
                            "type_url": event_any.type_url,
                            "raw_data": base64::prelude::BASE64_STANDARD.encode(&event_any.value)
                        })
                    } else {
                        serde_json::json!({})
                    };

                    let event = ContainerdEvent {
                        timestamp,
                        namespace,
                        topic,
                        event_type,
                        event_data,
                    };

                    // Apply additional filtering
                    if filter_clone.matches(&event) {
                        debug!("Event matches filter: {:?}", event.event_type);
                        Ok(event)
                    } else {
                        // Skip events that don't match the filter
                        // This is a bit inefficient but containerd filters are limited
                        debug!("Event filtered out: {:?}", event.event_type);
                        Err(ContainerdError::EventOperationFailed {
                            operation: "filter_event".to_string(),
                            message: "Event filtered out".to_string(),
                        })
                    }
                }
                Err(e) => {
                    error!("Error receiving event: {}", e);
                    Err(ContainerdError::GrpcError(e))
                }
            }
        }).filter_map(|result| async move {
            match result {
                Ok(event) => Some(Ok(event)),
                Err(ContainerdError::EventOperationFailed { message, .. }) if message == "Event filtered out" => None,
                Err(e) => Some(Err(e)),
            }
        });

        Ok(Box::pin(event_stream))
    }

    /// Subscribe to all events
    pub async fn subscribe_all_events(&mut self) -> Result<EventStream> {
        let filter = EventFilter {
            event_types: vec![],
            namespaces: vec![self.namespace.clone()],
            container_ids: vec![],
            labels: std::collections::HashMap::new(),
            vpn_managed_only: false,
        };

        self.subscribe_events(filter).await
    }

    /// Subscribe to container lifecycle events only
    pub async fn subscribe_container_events(&mut self) -> Result<EventStream> {
        self.subscribe_events(EventFilter::container_events()).await
    }

    /// Subscribe to task lifecycle events only
    pub async fn subscribe_task_events(&mut self) -> Result<EventStream> {
        self.subscribe_events(EventFilter::task_events()).await
    }

    /// Subscribe to image events only
    pub async fn subscribe_image_events(&mut self) -> Result<EventStream> {
        self.subscribe_events(EventFilter::image_events()).await
    }

    /// Subscribe to events for specific containers
    pub async fn subscribe_container_events_by_id(&mut self, container_ids: Vec<String>) -> Result<EventStream> {
        let filter = EventFilter {
            event_types: EventFilter::container_events().event_types,
            container_ids,
            ..Default::default()
        };

        self.subscribe_events(filter).await
    }

    /// Listen for events with a callback function
    pub async fn listen_with_callback(
        &mut self,
        filter: EventFilter,
        callback: EventCallback,
    ) -> Result<()> {
        info!("Starting event listener with callback");
        let mut stream = self.subscribe_events(filter).await?;

        while let Some(event_result) = stream.next().await {
            match event_result {
                Ok(event) => {
                    debug!("Received event: {:?}", event.event_type);
                    callback(event);
                }
                Err(e) => {
                    warn!("Error in event stream: {}", e);
                    // Continue listening despite errors
                }
            }
        }

        info!("Event listener stopped");
        Ok(())
    }

    /// Get events since a specific timestamp
    pub async fn get_events_since(
        &mut self,
        _since: DateTime<Utc>,
        _filter: EventFilter,
    ) -> Result<Vec<ContainerdEvent>> {
        // Note: containerd doesn't provide historical events by default
        // This would need to be implemented with external event storage
        warn!("Historical event retrieval not supported by containerd-client 0.8.0");
        
        Err(ContainerdError::OperationNotSupported {
            operation: "get_events_since".to_string(),
            reason: "Historical event retrieval not available in containerd-client 0.8.0".to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_type_conversion() {
        assert_eq!(
            ContainerdEventType::from("/containers/create"),
            ContainerdEventType::ContainerCreate
        );
        assert_eq!(
            ContainerdEventType::from("/tasks/start"),
            ContainerdEventType::TaskStart
        );
        assert_eq!(
            ContainerdEventType::from("/unknown/event"),
            ContainerdEventType::Unknown("/unknown/event".to_string())
        );
    }

    #[test]
    fn test_event_filter_creation() {
        let filter = EventFilter::container_events();
        assert_eq!(filter.event_types.len(), 6);
        assert!(filter.vpn_managed_only);

        let filter = EventFilter::task_events();
        assert_eq!(filter.event_types.len(), 6);
        
        let filter = EventFilter::image_events();
        assert_eq!(filter.event_types.len(), 3);
    }

    #[test]
    fn test_event_filter_to_containerd_filters() {
        let mut filter = EventFilter::default();
        filter.event_types = vec![ContainerdEventType::ContainerCreate];
        filter.container_ids = vec!["test-container".to_string()];
        
        let filters = filter.to_containerd_filters();
        assert!(filters.contains(&"topic==/containers/create".to_string()));
        assert!(filters.contains(&"id==test-container".to_string()));
        assert!(filters.contains(&"labels.vpn.managed==true".to_string()));
    }

    #[test]
    fn test_containerd_event_container_id() {
        let event = ContainerdEvent {
            timestamp: Utc::now(),
            namespace: "default".to_string(),
            topic: "/containers/create".to_string(),
            event_type: ContainerdEventType::ContainerCreate,
            event_data: serde_json::json!({
                "id": "test-container-123"
            }),
        };

        assert_eq!(event.container_id(), Some("test-container-123".to_string()));
    }

    #[test]
    fn test_containerd_event_is_vpn_managed() {
        let event = ContainerdEvent {
            timestamp: Utc::now(),
            namespace: "default".to_string(),
            topic: "/containers/create".to_string(),
            event_type: ContainerdEventType::ContainerCreate,
            event_data: serde_json::json!({
                "labels": {
                    "vpn.managed": "true"
                }
            }),
        };

        assert!(event.is_vpn_managed());
    }
}