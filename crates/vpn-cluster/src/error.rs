//! Cluster error types

use std::net::AddrParseError;

/// Result type for cluster operations
pub type Result<T> = std::result::Result<T, ClusterError>;

/// Cluster-specific error types
#[derive(Debug, thiserror::Error)]
pub enum ClusterError {
    #[error("Consensus error: {0}")]
    Consensus(String),
    
    #[error("Storage error: {0}")]
    Storage(String),
    
    #[error("Network error: {0}")]
    Network(String),
    
    #[error("Node not found: {0}")]
    NodeNotFound(String),
    
    #[error("Cluster not initialized")]
    NotInitialized,
    
    #[error("Leader election failed: {0}")]
    LeaderElectionFailed(String),
    
    #[error("Configuration error: {0}")]
    Configuration(String),
    
    #[error("Membership error: {0}")]
    Membership(String),
    
    #[error("Coordination error: {0}")]
    Coordination(String),
    
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
    
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("Address parse error: {0}")]
    AddrParse(#[from] AddrParseError),
    
    #[error("Generic error: {0}")]
    Generic(#[from] anyhow::Error),

    #[error("Timeout error: {0}")]
    Timeout(String),

    #[error("Split brain detected: multiple leaders found")]
    SplitBrain,

    #[error("Quorum not available: {current}/{required} nodes")]
    QuorumNotAvailable { current: usize, required: usize },

    #[error("Node already exists: {0}")]
    NodeAlreadyExists(String),

    #[error("Invalid cluster state: {0}")]
    InvalidState(String),

    #[error("Authentication failed: {0}")]
    Authentication(String),

    #[error("Authorization failed: {0}")]
    Authorization(String),
}

impl ClusterError {
    pub fn consensus<T: Into<String>>(msg: T) -> Self {
        Self::Consensus(msg.into())
    }

    pub fn storage<T: Into<String>>(msg: T) -> Self {
        Self::Storage(msg.into())
    }

    pub fn network<T: Into<String>>(msg: T) -> Self {
        Self::Network(msg.into())
    }

    pub fn node_not_found<T: Into<String>>(node_id: T) -> Self {
        Self::NodeNotFound(node_id.into())
    }

    pub fn leader_election_failed<T: Into<String>>(msg: T) -> Self {
        Self::LeaderElectionFailed(msg.into())
    }

    pub fn configuration<T: Into<String>>(msg: T) -> Self {
        Self::Configuration(msg.into())
    }

    pub fn membership<T: Into<String>>(msg: T) -> Self {
        Self::Membership(msg.into())
    }

    pub fn coordination<T: Into<String>>(msg: T) -> Self {
        Self::Coordination(msg.into())
    }

    pub fn timeout<T: Into<String>>(msg: T) -> Self {
        Self::Timeout(msg.into())
    }

    pub fn invalid_state<T: Into<String>>(msg: T) -> Self {
        Self::InvalidState(msg.into())
    }

    pub fn authentication<T: Into<String>>(msg: T) -> Self {
        Self::Authentication(msg.into())
    }

    pub fn authorization<T: Into<String>>(msg: T) -> Self {
        Self::Authorization(msg.into())
    }

    pub fn quorum_not_available(current: usize, required: usize) -> Self {
        Self::QuorumNotAvailable { current, required }
    }

    pub fn node_already_exists<T: Into<String>>(node_id: T) -> Self {
        Self::NodeAlreadyExists(node_id.into())
    }
}

/// Convert from various external error types
// TODO: Re-enable when raft dependency is fixed
// impl From<raft::Error> for ClusterError {
//     fn from(err: raft::Error) -> Self {
//         Self::consensus(format!("Raft error: {:?}", err))
//     }
// }

impl From<sled::Error> for ClusterError {
    fn from(err: sled::Error) -> Self {
        Self::storage(format!("Sled error: {}", err))
    }
}

impl From<tonic::Status> for ClusterError {
    fn from(err: tonic::Status) -> Self {
        Self::network(format!("gRPC error: {}", err))
    }
}

impl From<hyper::Error> for ClusterError {
    fn from(err: hyper::Error) -> Self {
        Self::network(format!("HTTP error: {}", err))
    }
}

impl From<reqwest::Error> for ClusterError {
    fn from(err: reqwest::Error) -> Self {
        Self::network(format!("HTTP client error: {}", err))
    }
}