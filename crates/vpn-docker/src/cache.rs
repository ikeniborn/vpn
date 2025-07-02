//! Container information caching for improved performance
//!
//! This module provides caching for frequently accessed container information
//! to reduce Docker API calls and improve overall performance.

use crate::{ContainerStatus, ContainerStats};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Cache entry for container information
#[derive(Debug, Clone)]
struct CacheEntry<T> {
    data: T,
    timestamp: Instant,
    ttl: Duration,
}

impl<T> CacheEntry<T> {
    fn new(data: T, ttl: Duration) -> Self {
        Self {
            data,
            timestamp: Instant::now(),
            ttl,
        }
    }

    fn is_expired(&self) -> bool {
        self.timestamp.elapsed() > self.ttl
    }

    fn _into_data(self) -> T {
        self.data
    }
}

/// Configuration for the container cache
#[derive(Debug, Clone)]
pub struct CacheConfig {
    /// Time-to-live for container status information
    pub status_ttl: Duration,
    /// Time-to-live for container statistics
    pub stats_ttl: Duration,
    /// Time-to-live for container list
    pub list_ttl: Duration,
    /// Maximum number of entries to cache
    pub max_entries: usize,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            status_ttl: Duration::from_secs(30),
            stats_ttl: Duration::from_secs(5),
            list_ttl: Duration::from_secs(60),
            max_entries: 1000,
        }
    }
}

/// Cache for container information to reduce Docker API calls
pub struct ContainerCache {
    status_cache: Arc<RwLock<HashMap<String, CacheEntry<ContainerStatus>>>>,
    stats_cache: Arc<RwLock<HashMap<String, CacheEntry<ContainerStats>>>>,
    list_cache: Arc<RwLock<Option<CacheEntry<Vec<String>>>>>,
    config: CacheConfig,
}

impl ContainerCache {
    /// Create a new container cache
    pub fn new(config: CacheConfig) -> Self {
        Self {
            status_cache: Arc::new(RwLock::new(HashMap::new())),
            stats_cache: Arc::new(RwLock::new(HashMap::new())),
            list_cache: Arc::new(RwLock::new(None)),
            config,
        }
    }

    /// Get cached container status
    pub async fn get_status(&self, container_name: &str) -> Option<ContainerStatus> {
        let cache = self.status_cache.read().await;
        cache.get(container_name).and_then(|entry| {
            if !entry.is_expired() {
                Some(entry.data.clone())
            } else {
                None
            }
        })
    }

    /// Cache container status
    pub async fn cache_status(&self, container_name: &str, status: ContainerStatus) {
        let mut cache = self.status_cache.write().await;
        
        // Clean up expired entries if cache is getting large
        if cache.len() >= self.config.max_entries {
            cache.retain(|_, entry| !entry.is_expired());
        }
        
        cache.insert(
            container_name.to_owned(),
            CacheEntry::new(status, self.config.status_ttl),
        );
    }

    /// Get cached container statistics
    pub async fn get_stats(&self, container_name: &str) -> Option<ContainerStats> {
        let cache = self.stats_cache.read().await;
        cache.get(container_name).and_then(|entry| {
            if !entry.is_expired() {
                Some(entry.data.clone())
            } else {
                None
            }
        })
    }

    /// Cache container statistics
    pub async fn cache_stats(&self, container_name: &str, stats: ContainerStats) {
        let mut cache = self.stats_cache.write().await;
        
        // Clean up expired entries if cache is getting large
        if cache.len() >= self.config.max_entries {
            cache.retain(|_, entry| !entry.is_expired());
        }
        
        cache.insert(
            container_name.to_owned(),
            CacheEntry::new(stats, self.config.stats_ttl),
        );
    }

    /// Get cached container list
    pub async fn get_container_list(&self) -> Option<Vec<String>> {
        let cache = self.list_cache.read().await;
        cache.as_ref().and_then(|entry| {
            if !entry.is_expired() {
                Some(entry.data.clone())
            } else {
                None
            }
        })
    }

    /// Cache container list
    pub async fn cache_container_list(&self, containers: Vec<String>) {
        let mut cache = self.list_cache.write().await;
        *cache = Some(CacheEntry::new(containers, self.config.list_ttl));
    }

    /// Invalidate cache entry for a specific container
    pub async fn invalidate_container(&self, container_name: &str) {
        let mut status_cache = self.status_cache.write().await;
        let mut stats_cache = self.stats_cache.write().await;
        
        status_cache.remove(container_name);
        stats_cache.remove(container_name);
        
        // Also invalidate the container list since it might have changed
        let mut list_cache = self.list_cache.write().await;
        *list_cache = None;
    }

    /// Clear all cached data
    pub async fn clear(&self) {
        let mut status_cache = self.status_cache.write().await;
        let mut stats_cache = self.stats_cache.write().await;
        let mut list_cache = self.list_cache.write().await;
        
        status_cache.clear();
        stats_cache.clear();
        *list_cache = None;
    }

    /// Get cache statistics
    pub async fn get_cache_stats(&self) -> CacheStats {
        let status_cache = self.status_cache.read().await;
        let stats_cache = self.stats_cache.read().await;
        let list_cache = self.list_cache.read().await;
        
        CacheStats {
            status_entries: status_cache.len(),
            stats_entries: stats_cache.len(),
            has_container_list: list_cache.is_some(),
            config: self.config.clone(),
        }
    }

    /// Cleanup expired entries
    pub async fn cleanup_expired(&self) {
        {
            let mut status_cache = self.status_cache.write().await;
            status_cache.retain(|_, entry| !entry.is_expired());
        }
        
        {
            let mut stats_cache = self.stats_cache.write().await;
            stats_cache.retain(|_, entry| !entry.is_expired());
        }
        
        {
            let mut list_cache = self.list_cache.write().await;
            if let Some(entry) = list_cache.as_ref() {
                if entry.is_expired() {
                    *list_cache = None;
                }
            }
        }
    }
}

/// Cache statistics
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub status_entries: usize,
    pub stats_entries: usize,
    pub has_container_list: bool,
    pub config: CacheConfig,
}

/// Global container cache instance
static CONTAINER_CACHE: once_cell::sync::Lazy<ContainerCache> = once_cell::sync::Lazy::new(|| {
    ContainerCache::new(CacheConfig::default())
});

/// Get the global container cache
pub fn get_container_cache() -> &'static ContainerCache {
    &CONTAINER_CACHE
}

/// Start background cleanup task for the global cache
pub fn start_cache_cleanup_task() {
    tokio::spawn(async {
        let mut interval = tokio::time::interval(Duration::from_secs(300)); // 5 minutes
        
        loop {
            interval.tick().await;
            CONTAINER_CACHE.cleanup_expired().await;
        }
    });
}