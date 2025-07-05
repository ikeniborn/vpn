//! Distributed configuration storage implementations

use crate::config::StorageBackendConfig;
use crate::error::{ClusterError, Result};
use async_trait::async_trait;
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Trait for distributed configuration storage
#[async_trait]
pub trait DistributedConfigStorage: Send + Sync {
    /// Store a configuration value
    async fn store_config(&self, key: &str, value: Value) -> Result<()>;

    /// Retrieve a configuration value
    async fn get_config(&self, key: &str) -> Result<Option<Value>>;

    /// Remove a configuration value
    async fn remove_config(&self, key: &str) -> Result<Option<Value>>;

    /// List all configuration keys
    async fn list_keys(&self) -> Result<Vec<String>>;

    /// Get all configuration values
    async fn get_all_config(&self) -> Result<HashMap<String, Value>>;

    /// Watch for configuration changes
    async fn watch_config(&self, key: &str) -> Result<tokio::sync::mpsc::Receiver<ConfigChange>>;

    /// Perform atomic transaction
    async fn transaction(&self, ops: Vec<TransactionOp>) -> Result<()>;

    /// Health check for storage backend
    async fn health_check(&self) -> Result<StorageHealth>;
}

/// Configuration change event
#[derive(Debug, Clone)]
pub struct ConfigChange {
    pub key: String,
    pub old_value: Option<Value>,
    pub new_value: Option<Value>,
    pub timestamp: u64,
}

/// Transaction operation
#[derive(Debug, Clone)]
pub enum TransactionOp {
    Set {
        key: String,
        value: Value,
    },
    Delete {
        key: String,
    },
    ConditionalSet {
        key: String,
        value: Value,
        expected: Option<Value>,
    },
}

/// Storage backend health information
#[derive(Debug, Clone)]
pub struct StorageHealth {
    pub healthy: bool,
    pub latency_ms: u64,
    pub error: Option<String>,
    pub metadata: HashMap<String, String>,
}

/// Create storage backend based on configuration
pub async fn create_storage_backend(
    config: &StorageBackendConfig,
) -> Result<Arc<dyn DistributedConfigStorage>> {
    match config {
        StorageBackendConfig::Sled { path } => Ok(Arc::new(SledStorage::new(path).await?)),
        StorageBackendConfig::Etcd { endpoints, .. } => {
            Ok(Arc::new(EtcdStorage::new(endpoints).await?))
        }
        StorageBackendConfig::Consul { address, .. } => {
            Ok(Arc::new(ConsulStorage::new(address).await?))
        }
        StorageBackendConfig::TiKV { pd_endpoints, .. } => {
            Ok(Arc::new(TiKVStorage::new(pd_endpoints).await?))
        }
        StorageBackendConfig::Memory => Ok(Arc::new(MemoryStorage::new())),
    }
}

/// In-memory storage implementation (for testing)
pub struct MemoryStorage {
    data: Arc<RwLock<HashMap<String, Value>>>,
    watchers: Arc<RwLock<HashMap<String, tokio::sync::broadcast::Sender<ConfigChange>>>>,
}

impl MemoryStorage {
    pub fn new() -> Self {
        Self {
            data: Arc::new(RwLock::new(HashMap::new())),
            watchers: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    async fn notify_watchers(&self, key: &str, old_value: Option<Value>, new_value: Option<Value>) {
        let watchers = self.watchers.read().await;
        if let Some(sender) = watchers.get(key) {
            let change = ConfigChange {
                key: key.to_string(),
                old_value,
                new_value,
                timestamp: current_timestamp(),
            };
            let _ = sender.send(change);
        }
    }
}

#[async_trait]
impl DistributedConfigStorage for MemoryStorage {
    async fn store_config(&self, key: &str, value: Value) -> Result<()> {
        let mut data = self.data.write().await;
        let old_value = data.insert(key.to_string(), value.clone());
        drop(data);

        self.notify_watchers(key, old_value, Some(value)).await;
        Ok(())
    }

    async fn get_config(&self, key: &str) -> Result<Option<Value>> {
        let data = self.data.read().await;
        Ok(data.get(key).cloned())
    }

    async fn remove_config(&self, key: &str) -> Result<Option<Value>> {
        let mut data = self.data.write().await;
        let old_value = data.remove(key);
        drop(data);

        if old_value.is_some() {
            self.notify_watchers(key, old_value.clone(), None).await;
        }

        Ok(old_value)
    }

    async fn list_keys(&self) -> Result<Vec<String>> {
        let data = self.data.read().await;
        Ok(data.keys().cloned().collect())
    }

    async fn get_all_config(&self) -> Result<HashMap<String, Value>> {
        let data = self.data.read().await;
        Ok(data.clone())
    }

    async fn watch_config(&self, key: &str) -> Result<tokio::sync::mpsc::Receiver<ConfigChange>> {
        let mut watchers = self.watchers.write().await;
        let sender = watchers
            .entry(key.to_string())
            .or_insert_with(|| tokio::sync::broadcast::channel(100).0);

        let mut receiver = sender.subscribe();
        let (tx, rx) = tokio::sync::mpsc::channel(100);

        tokio::spawn(async move {
            while let Ok(change) = receiver.recv().await {
                if tx.send(change).await.is_err() {
                    break;
                }
            }
        });

        Ok(rx)
    }

    async fn transaction(&self, ops: Vec<TransactionOp>) -> Result<()> {
        let mut data = self.data.write().await;
        let mut changes = Vec::new();

        // Validate all operations first
        for op in &ops {
            match op {
                TransactionOp::ConditionalSet { key, expected, .. } => {
                    let current = data.get(key);
                    if current != expected.as_ref() {
                        return Err(ClusterError::invalid_state(format!(
                            "Conditional set failed for key {}: expected {:?}, got {:?}",
                            key, expected, current
                        )));
                    }
                }
                _ => {}
            }
        }

        // Apply all operations
        for op in ops {
            match op {
                TransactionOp::Set { key, value } => {
                    let old_value = data.insert(key.clone(), value.clone());
                    changes.push((key, old_value, Some(value)));
                }
                TransactionOp::Delete { key } => {
                    let old_value = data.remove(&key);
                    if old_value.is_some() {
                        changes.push((key, old_value, None));
                    }
                }
                TransactionOp::ConditionalSet { key, value, .. } => {
                    let old_value = data.insert(key.clone(), value.clone());
                    changes.push((key, old_value, Some(value)));
                }
            }
        }

        drop(data);

        // Notify watchers
        for (key, old_value, new_value) in changes {
            self.notify_watchers(&key, old_value, new_value).await;
        }

        Ok(())
    }

    async fn health_check(&self) -> Result<StorageHealth> {
        let start = std::time::Instant::now();
        let _ = self.data.read().await;
        let latency = start.elapsed();

        Ok(StorageHealth {
            healthy: true,
            latency_ms: latency.as_millis() as u64,
            error: None,
            metadata: {
                let mut meta = HashMap::new();
                meta.insert("backend".to_string(), "memory".to_string());
                meta
            },
        })
    }
}

/// Sled-based storage implementation
pub struct SledStorage {
    db: sled::Db,
    watchers: Arc<RwLock<HashMap<String, tokio::sync::broadcast::Sender<ConfigChange>>>>,
}

impl SledStorage {
    pub async fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let db = sled::open(path)?;

        Ok(Self {
            db,
            watchers: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    async fn notify_watchers(&self, key: &str, old_value: Option<Value>, new_value: Option<Value>) {
        let watchers = self.watchers.read().await;
        if let Some(sender) = watchers.get(key) {
            let change = ConfigChange {
                key: key.to_string(),
                old_value,
                new_value,
                timestamp: current_timestamp(),
            };
            let _ = sender.send(change);
        }
    }
}

#[async_trait]
impl DistributedConfigStorage for SledStorage {
    async fn store_config(&self, key: &str, value: Value) -> Result<()> {
        let serialized = serde_json::to_vec(&value)?;
        let old_data = self.db.insert(key, serialized)?;

        let old_value = if let Some(data) = old_data {
            serde_json::from_slice(&data).ok()
        } else {
            None
        };

        self.notify_watchers(key, old_value, Some(value)).await;
        Ok(())
    }

    async fn get_config(&self, key: &str) -> Result<Option<Value>> {
        if let Some(data) = self.db.get(key)? {
            let value = serde_json::from_slice(&data)?;
            Ok(Some(value))
        } else {
            Ok(None)
        }
    }

    async fn remove_config(&self, key: &str) -> Result<Option<Value>> {
        let old_data = self.db.remove(key)?;

        let old_value = if let Some(data) = old_data {
            serde_json::from_slice(&data).ok()
        } else {
            None
        };

        if old_value.is_some() {
            self.notify_watchers(key, old_value.clone(), None).await;
        }

        Ok(old_value)
    }

    async fn list_keys(&self) -> Result<Vec<String>> {
        let keys = self
            .db
            .iter()
            .keys()
            .collect::<std::result::Result<Vec<_>, _>>()?
            .into_iter()
            .filter_map(|k| String::from_utf8(k.to_vec()).ok())
            .collect();

        Ok(keys)
    }

    async fn get_all_config(&self) -> Result<HashMap<String, Value>> {
        let mut result = HashMap::new();

        for item in self.db.iter() {
            let (key_bytes, value_bytes) = item?;
            if let (Ok(key), Ok(value)) = (
                String::from_utf8(key_bytes.to_vec()),
                serde_json::from_slice::<Value>(&value_bytes),
            ) {
                result.insert(key, value);
            }
        }

        Ok(result)
    }

    async fn watch_config(&self, key: &str) -> Result<tokio::sync::mpsc::Receiver<ConfigChange>> {
        let mut watchers = self.watchers.write().await;
        let sender = watchers
            .entry(key.to_string())
            .or_insert_with(|| tokio::sync::broadcast::channel(100).0);

        let mut receiver = sender.subscribe();
        let (tx, rx) = tokio::sync::mpsc::channel(100);

        tokio::spawn(async move {
            while let Ok(change) = receiver.recv().await {
                if tx.send(change).await.is_err() {
                    break;
                }
            }
        });

        Ok(rx)
    }

    async fn transaction(&self, ops: Vec<TransactionOp>) -> Result<()> {
        let mut batch = sled::Batch::default();
        let mut changes = Vec::new();

        // Validate conditional operations first
        for op in &ops {
            if let TransactionOp::ConditionalSet { key, expected, .. } = op {
                let current = self.get_config(key).await?;
                if &current != expected {
                    return Err(ClusterError::invalid_state(format!(
                        "Conditional set failed for key {}",
                        key
                    )));
                }
            }
        }

        // Prepare batch operations
        for op in ops {
            match op {
                TransactionOp::Set { key, value } => {
                    let old_value = self.get_config(&key).await?;
                    let serialized = serde_json::to_vec(&value)?;
                    batch.insert(key.as_bytes(), serialized);
                    changes.push((key, old_value, Some(value)));
                }
                TransactionOp::Delete { key } => {
                    let old_value = self.get_config(&key).await?;
                    batch.remove(key.as_bytes());
                    if old_value.is_some() {
                        changes.push((key, old_value, None));
                    }
                }
                TransactionOp::ConditionalSet { key, value, .. } => {
                    let old_value = self.get_config(&key).await?;
                    let serialized = serde_json::to_vec(&value)?;
                    batch.insert(key.as_bytes(), serialized);
                    changes.push((key, old_value, Some(value)));
                }
            }
        }

        // Apply batch
        self.db.apply_batch(batch)?;

        // Notify watchers
        for (key, old_value, new_value) in changes {
            self.notify_watchers(&key, old_value, new_value).await;
        }

        Ok(())
    }

    async fn health_check(&self) -> Result<StorageHealth> {
        let start = std::time::Instant::now();

        // Test basic operations
        let test_key = "__health_check__";
        let test_value = serde_json::json!({"timestamp": current_timestamp()});

        match self.store_config(test_key, test_value).await {
            Ok(_) => {
                let _ = self.remove_config(test_key).await;
                let latency = start.elapsed();

                Ok(StorageHealth {
                    healthy: true,
                    latency_ms: latency.as_millis() as u64,
                    error: None,
                    metadata: {
                        let mut meta = HashMap::new();
                        meta.insert("backend".to_string(), "sled".to_string());
                        meta.insert("path".to_string(), "sled_db".to_string());
                        meta
                    },
                })
            }
            Err(e) => Ok(StorageHealth {
                healthy: false,
                latency_ms: start.elapsed().as_millis() as u64,
                error: Some(e.to_string()),
                metadata: HashMap::new(),
            }),
        }
    }
}

/// Placeholder for etcd storage implementation
pub struct EtcdStorage;

impl EtcdStorage {
    pub async fn new(_endpoints: &[String]) -> Result<Self> {
        // TODO: Implement etcd client
        Err(ClusterError::configuration(
            "etcd storage not yet implemented",
        ))
    }
}

#[async_trait]
impl DistributedConfigStorage for EtcdStorage {
    async fn store_config(&self, _key: &str, _value: Value) -> Result<()> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn get_config(&self, _key: &str) -> Result<Option<Value>> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn remove_config(&self, _key: &str) -> Result<Option<Value>> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn list_keys(&self) -> Result<Vec<String>> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn get_all_config(&self) -> Result<HashMap<String, Value>> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn watch_config(&self, _key: &str) -> Result<tokio::sync::mpsc::Receiver<ConfigChange>> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn transaction(&self, _ops: Vec<TransactionOp>) -> Result<()> {
        unimplemented!("etcd storage not yet implemented")
    }

    async fn health_check(&self) -> Result<StorageHealth> {
        unimplemented!("etcd storage not yet implemented")
    }
}

/// Placeholder for Consul storage implementation
pub struct ConsulStorage;

impl ConsulStorage {
    pub async fn new(_address: &str) -> Result<Self> {
        // TODO: Implement Consul client
        Err(ClusterError::configuration(
            "consul storage not yet implemented",
        ))
    }
}

#[async_trait]
impl DistributedConfigStorage for ConsulStorage {
    async fn store_config(&self, _key: &str, _value: Value) -> Result<()> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn get_config(&self, _key: &str) -> Result<Option<Value>> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn remove_config(&self, _key: &str) -> Result<Option<Value>> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn list_keys(&self) -> Result<Vec<String>> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn get_all_config(&self) -> Result<HashMap<String, Value>> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn watch_config(&self, _key: &str) -> Result<tokio::sync::mpsc::Receiver<ConfigChange>> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn transaction(&self, _ops: Vec<TransactionOp>) -> Result<()> {
        unimplemented!("consul storage not yet implemented")
    }

    async fn health_check(&self) -> Result<StorageHealth> {
        unimplemented!("consul storage not yet implemented")
    }
}

/// Placeholder for TiKV storage implementation
pub struct TiKVStorage;

impl TiKVStorage {
    pub async fn new(_pd_endpoints: &[String]) -> Result<Self> {
        // TODO: Implement TiKV client
        Err(ClusterError::configuration(
            "tikv storage not yet implemented",
        ))
    }
}

#[async_trait]
impl DistributedConfigStorage for TiKVStorage {
    async fn store_config(&self, _key: &str, _value: Value) -> Result<()> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn get_config(&self, _key: &str) -> Result<Option<Value>> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn remove_config(&self, _key: &str) -> Result<Option<Value>> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn list_keys(&self) -> Result<Vec<String>> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn get_all_config(&self) -> Result<HashMap<String, Value>> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn watch_config(&self, _key: &str) -> Result<tokio::sync::mpsc::Receiver<ConfigChange>> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn transaction(&self, _ops: Vec<TransactionOp>) -> Result<()> {
        unimplemented!("tikv storage not yet implemented")
    }

    async fn health_check(&self) -> Result<StorageHealth> {
        unimplemented!("tikv storage not yet implemented")
    }
}

/// Get current timestamp in seconds since UNIX epoch
fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use tokio::time::{timeout, Duration};

    #[tokio::test]
    async fn test_memory_storage() {
        let storage = MemoryStorage::new();

        // Test store and get
        let value = serde_json::json!({"test": "value"});
        storage
            .store_config("test_key", value.clone())
            .await
            .unwrap();

        let retrieved = storage.get_config("test_key").await.unwrap();
        assert_eq!(retrieved, Some(value));

        // Test list keys
        let keys = storage.list_keys().await.unwrap();
        assert!(keys.contains(&"test_key".to_string()));

        // Test remove
        let removed = storage.remove_config("test_key").await.unwrap();
        assert_eq!(removed, Some(serde_json::json!({"test": "value"})));

        let after_remove = storage.get_config("test_key").await.unwrap();
        assert_eq!(after_remove, None);
    }

    #[tokio::test]
    async fn test_memory_storage_watch() {
        let storage = MemoryStorage::new();

        let mut watcher = storage.watch_config("watch_key").await.unwrap();

        // Store value and check notification
        let value = serde_json::json!("watched_value");
        storage
            .store_config("watch_key", value.clone())
            .await
            .unwrap();

        let change = timeout(Duration::from_millis(100), watcher.recv())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(change.key, "watch_key");
        assert_eq!(change.new_value, Some(value));
        assert_eq!(change.old_value, None);
    }

    #[tokio::test]
    async fn test_memory_storage_transaction() {
        let storage = MemoryStorage::new();

        // Set initial value
        storage
            .store_config("key1", serde_json::json!("value1"))
            .await
            .unwrap();

        // Test successful transaction
        let ops = vec![
            TransactionOp::Set {
                key: "key2".to_string(),
                value: serde_json::json!("value2"),
            },
            TransactionOp::ConditionalSet {
                key: "key1".to_string(),
                value: serde_json::json!("updated_value1"),
                expected: Some(serde_json::json!("value1")),
            },
        ];

        storage.transaction(ops).await.unwrap();

        assert_eq!(
            storage.get_config("key1").await.unwrap(),
            Some(serde_json::json!("updated_value1"))
        );
        assert_eq!(
            storage.get_config("key2").await.unwrap(),
            Some(serde_json::json!("value2"))
        );

        // Test failed conditional transaction
        let failing_ops = vec![TransactionOp::ConditionalSet {
            key: "key1".to_string(),
            value: serde_json::json!("should_not_update"),
            expected: Some(serde_json::json!("wrong_expected_value")),
        }];

        assert!(storage.transaction(failing_ops).await.is_err());
        assert_eq!(
            storage.get_config("key1").await.unwrap(),
            Some(serde_json::json!("updated_value1"))
        );
    }

    #[tokio::test]
    async fn test_sled_storage() {
        let temp_dir = tempdir().unwrap();
        let storage = SledStorage::new(temp_dir.path()).await.unwrap();

        // Test basic operations
        let value = serde_json::json!({"sled": "test"});
        storage
            .store_config("sled_key", value.clone())
            .await
            .unwrap();

        let retrieved = storage.get_config("sled_key").await.unwrap();
        assert_eq!(retrieved, Some(value));

        // Test persistence by creating new instance
        let storage2 = SledStorage::new(temp_dir.path()).await.unwrap();
        let retrieved2 = storage2.get_config("sled_key").await.unwrap();
        assert_eq!(retrieved2, Some(serde_json::json!({"sled": "test"})));
    }

    #[tokio::test]
    async fn test_storage_health_check() {
        let storage = MemoryStorage::new();
        let health = storage.health_check().await.unwrap();

        assert!(health.healthy);
        assert!(health.error.is_none());
        assert_eq!(health.metadata.get("backend"), Some(&"memory".to_string()));
    }

    #[tokio::test]
    async fn test_create_storage_backend() {
        // Test memory backend
        let memory_config = StorageBackendConfig::Memory;
        let storage = create_storage_backend(&memory_config).await.unwrap();

        // Test basic operation
        storage
            .store_config("test", serde_json::json!("value"))
            .await
            .unwrap();
        let value = storage.get_config("test").await.unwrap();
        assert_eq!(value, Some(serde_json::json!("value")));

        // Test sled backend
        let temp_dir = tempdir().unwrap();
        let sled_config = StorageBackendConfig::Sled {
            path: temp_dir.path().to_path_buf(),
        };
        let sled_storage = create_storage_backend(&sled_config).await.unwrap();

        sled_storage
            .store_config("sled_test", serde_json::json!("sled_value"))
            .await
            .unwrap();
        let sled_value = sled_storage.get_config("sled_test").await.unwrap();
        assert_eq!(sled_value, Some(serde_json::json!("sled_value")));
    }
}
