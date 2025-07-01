//! Cluster configuration management

use crate::error::{ClusterError, Result};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

/// Main cluster configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterConfig {
    /// Name of this node
    pub node_name: String,
    
    /// Name of the cluster
    pub cluster_name: String,
    
    /// Address this node binds to
    pub bind_address: SocketAddr,
    
    /// Storage backend configuration
    pub storage_backend: StorageBackendConfig,
    
    /// Consensus algorithm to use
    pub consensus_algorithm: ConsensusAlgorithm,
    
    /// Whether this is the initial node (bootstrap node)
    pub is_initial_node: bool,
    
    /// List of bootstrap nodes to join
    pub bootstrap_nodes: Vec<SocketAddr>,
    
    /// Gossip protocol interval
    pub gossip_interval: Duration,
    
    /// Heartbeat interval for health checks
    pub heartbeat_interval: Duration,
    
    /// Leader election timeout
    pub election_timeout: Duration,
}

impl Default for ClusterConfig {
    fn default() -> Self {
        Self {
            node_name: format!("node-{}", uuid::Uuid::new_v4()),
            cluster_name: "vpn-cluster".to_string(),
            bind_address: "127.0.0.1:8080".parse().unwrap(),
            storage_backend: StorageBackendConfig::default(),
            consensus_algorithm: ConsensusAlgorithm::Raft,
            is_initial_node: false,
            bootstrap_nodes: vec![],
            gossip_interval: Duration::from_secs(5),
            heartbeat_interval: Duration::from_secs(1),
            election_timeout: Duration::from_secs(10),
        }
    }
}

/// Storage backend configuration options
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum StorageBackendConfig {
    /// Local embedded storage using Sled
    Sled {
        path: PathBuf,
    },
    
    /// Distributed etcd storage
    Etcd {
        endpoints: Vec<String>,
        username: Option<String>,
        password: Option<String>,
        tls_enabled: bool,
        ca_cert: Option<PathBuf>,
        client_cert: Option<PathBuf>,
        client_key: Option<PathBuf>,
    },
    
    /// Consul distributed storage
    Consul {
        address: String,
        datacenter: Option<String>,
        token: Option<String>,
        tls_enabled: bool,
        ca_cert: Option<PathBuf>,
        client_cert: Option<PathBuf>,
        client_key: Option<PathBuf>,
    },
    
    /// TiKV distributed storage
    TiKV {
        pd_endpoints: Vec<String>,
        ca_cert: Option<PathBuf>,
        client_cert: Option<PathBuf>,
        client_key: Option<PathBuf>,
    },
    
    /// In-memory storage (for testing)
    Memory,
}

impl Default for StorageBackendConfig {
    fn default() -> Self {
        Self::Sled {
            path: PathBuf::from("/tmp/vpn-cluster"),
        }
    }
}

/// Consensus algorithm options
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConsensusAlgorithm {
    /// Raft consensus algorithm
    Raft,
    
    /// PBFT (Practical Byzantine Fault Tolerance)
    PBFT,
    
    /// Simple leader election (for testing)
    Simple,
}

/// Network configuration for cluster communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkConfig {
    /// Maximum message size for cluster communication
    pub max_message_size: usize,
    
    /// Connection timeout
    pub connection_timeout: Duration,
    
    /// Request timeout
    pub request_timeout: Duration,
    
    /// Maximum concurrent connections
    pub max_connections: usize,
    
    /// Enable TLS for cluster communication
    pub tls_enabled: bool,
    
    /// TLS configuration
    pub tls_config: Option<TlsConfig>,
}

impl Default for NetworkConfig {
    fn default() -> Self {
        Self {
            max_message_size: 1024 * 1024, // 1MB
            connection_timeout: Duration::from_secs(10),
            request_timeout: Duration::from_secs(30),
            max_connections: 100,
            tls_enabled: false,
            tls_config: None,
        }
    }
}

/// TLS configuration for secure cluster communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TlsConfig {
    /// CA certificate file
    pub ca_cert: PathBuf,
    
    /// Server certificate file
    pub server_cert: PathBuf,
    
    /// Server private key file
    pub server_key: PathBuf,
    
    /// Client certificate file (for mutual TLS)
    pub client_cert: Option<PathBuf>,
    
    /// Client private key file (for mutual TLS)
    pub client_key: Option<PathBuf>,
    
    /// Verify peer certificates
    pub verify_peer: bool,
}

/// Gossip protocol configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GossipConfig {
    /// Gossip interval
    pub interval: Duration,
    
    /// Number of nodes to gossip with per round
    pub fanout: usize,
    
    /// Maximum gossip message size
    pub max_message_size: usize,
    
    /// Suspicion timeout before marking node as failed
    pub suspicion_timeout: Duration,
    
    /// Maximum number of missed heartbeats before failure
    pub max_missed_heartbeats: usize,
}

impl Default for GossipConfig {
    fn default() -> Self {
        Self {
            interval: Duration::from_secs(1),
            fanout: 3,
            max_message_size: 65536, // 64KB
            suspicion_timeout: Duration::from_secs(5),
            max_missed_heartbeats: 3,
        }
    }
}

/// Health check configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthConfig {
    /// Health check interval
    pub check_interval: Duration,
    
    /// Health check timeout
    pub check_timeout: Duration,
    
    /// Number of failed checks before marking unhealthy
    pub failure_threshold: usize,
    
    /// Number of successful checks to mark healthy again
    pub success_threshold: usize,
}

impl Default for HealthConfig {
    fn default() -> Self {
        Self {
            check_interval: Duration::from_secs(30),
            check_timeout: Duration::from_secs(5),
            failure_threshold: 3,
            success_threshold: 2,
        }
    }
}

impl ClusterConfig {
    /// Load configuration from file
    pub fn from_file<P: AsRef<std::path::Path>>(path: P) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .map_err(|e| ClusterError::configuration(format!("Failed to read config file: {}", e)))?;
        
        toml::from_str(&content)
            .map_err(|e| ClusterError::configuration(format!("Failed to parse config: {}", e)))
    }
    
    /// Save configuration to file
    pub fn to_file<P: AsRef<std::path::Path>>(&self, path: P) -> Result<()> {
        let content = toml::to_string_pretty(self)
            .map_err(|e| ClusterError::configuration(format!("Failed to serialize config: {}", e)))?;
        
        std::fs::write(path, content)
            .map_err(|e| ClusterError::configuration(format!("Failed to write config file: {}", e)))?;
        
        Ok(())
    }
    
    /// Validate configuration
    pub fn validate(&self) -> Result<()> {
        if self.node_name.is_empty() {
            return Err(ClusterError::configuration("Node name cannot be empty"));
        }
        
        if self.cluster_name.is_empty() {
            return Err(ClusterError::configuration("Cluster name cannot be empty"));
        }
        
        if !self.is_initial_node && self.bootstrap_nodes.is_empty() {
            return Err(ClusterError::configuration(
                "Non-initial nodes must have bootstrap nodes configured"
            ));
        }
        
        if self.gossip_interval < Duration::from_millis(100) {
            return Err(ClusterError::configuration(
                "Gossip interval must be at least 100ms"
            ));
        }
        
        if self.heartbeat_interval < Duration::from_millis(100) {
            return Err(ClusterError::configuration(
                "Heartbeat interval must be at least 100ms"
            ));
        }
        
        if self.election_timeout < Duration::from_secs(1) {
            return Err(ClusterError::configuration(
                "Election timeout must be at least 1 second"
            ));
        }
        
        Ok(())
    }
    
    /// Get quorum size for consensus
    pub fn quorum_size(&self, total_nodes: usize) -> usize {
        (total_nodes / 2) + 1
    }
    
    /// Check if we have quorum
    pub fn has_quorum(&self, active_nodes: usize, total_nodes: usize) -> bool {
        active_nodes >= self.quorum_size(total_nodes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_default_config() {
        let config = ClusterConfig::default();
        assert!(!config.node_name.is_empty());
        assert_eq!(config.cluster_name, "vpn-cluster");
        assert!(!config.is_initial_node);
    }

    #[test]
    fn test_config_validation() {
        let mut config = ClusterConfig::default();
        
        // Valid config
        config.is_initial_node = true;
        assert!(config.validate().is_ok());
        
        // Invalid: empty node name
        config.node_name = String::new();
        assert!(config.validate().is_err());
        
        // Invalid: non-initial node without bootstrap nodes
        config.node_name = "test".to_string();
        config.is_initial_node = false;
        config.bootstrap_nodes = vec![];
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_quorum_calculation() {
        let config = ClusterConfig::default();
        
        assert_eq!(config.quorum_size(1), 1);
        assert_eq!(config.quorum_size(3), 2);
        assert_eq!(config.quorum_size(5), 3);
        assert_eq!(config.quorum_size(7), 4);
        
        assert!(config.has_quorum(2, 3));
        assert!(!config.has_quorum(1, 3));
        assert!(config.has_quorum(3, 5));
        assert!(!config.has_quorum(2, 5));
    }

    #[test]
    fn test_config_serialization() {
        let config = ClusterConfig::default();
        let serialized = toml::to_string(&config).unwrap();
        let deserialized: ClusterConfig = toml::from_str(&serialized).unwrap();
        
        assert_eq!(config.cluster_name, deserialized.cluster_name);
        assert_eq!(config.bind_address, deserialized.bind_address);
    }

    #[test]
    fn test_config_file_operations() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("cluster.toml");
        
        let config = ClusterConfig::default();
        
        // Save to file
        config.to_file(&config_path).unwrap();
        assert!(config_path.exists());
        
        // Load from file
        let loaded_config = ClusterConfig::from_file(&config_path).unwrap();
        assert_eq!(config.cluster_name, loaded_config.cluster_name);
        assert_eq!(config.bind_address, loaded_config.bind_address);
    }
}