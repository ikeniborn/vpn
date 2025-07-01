//! User-related types shared across crates

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

/// User status enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum UserStatus {
    /// User is active and can connect
    Active,
    /// User is suspended temporarily
    Suspended,
    /// User is expired and needs renewal
    Expired,
    /// User is disabled permanently
    Disabled,
}

impl UserStatus {
    /// Check if the user can connect
    pub fn can_connect(&self) -> bool {
        matches!(self, UserStatus::Active)
    }
}

/// Basic user information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserInfo {
    /// Unique user identifier
    pub id: Uuid,
    /// Username
    pub username: String,
    /// User email (optional)
    pub email: Option<String>,
    /// User status
    pub status: UserStatus,
    /// Creation timestamp
    pub created_at: DateTime<Utc>,
    /// Last modification timestamp
    pub updated_at: DateTime<Utc>,
}

/// Traffic statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TrafficStats {
    /// Bytes uploaded
    pub bytes_up: u64,
    /// Bytes downloaded
    pub bytes_down: u64,
    /// Total connections
    pub connections: u64,
    /// Last connection time
    pub last_connected: Option<DateTime<Utc>>,
}

impl TrafficStats {
    /// Get total traffic in bytes
    pub fn total_bytes(&self) -> u64 {
        self.bytes_up + self.bytes_down
    }

    /// Check if user has ever connected
    pub fn has_connected(&self) -> bool {
        self.connections > 0
    }
}

/// User quota settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotaSettings {
    /// Maximum traffic in bytes (0 = unlimited)
    pub max_traffic: u64,
    /// Maximum connections (0 = unlimited)
    pub max_connections: u32,
    /// Expiration date (None = no expiration)
    pub expires_at: Option<DateTime<Utc>>,
}

impl Default for QuotaSettings {
    fn default() -> Self {
        Self {
            max_traffic: 0,
            max_connections: 0,
            expires_at: None,
        }
    }
}

impl QuotaSettings {
    /// Check if quota is unlimited
    pub fn is_unlimited(&self) -> bool {
        self.max_traffic == 0 && self.max_connections == 0 && self.expires_at.is_none()
    }

    /// Check if quota is exceeded
    pub fn is_exceeded(&self, stats: &TrafficStats) -> bool {
        if self.max_traffic > 0 && stats.total_bytes() >= self.max_traffic {
            return true;
        }
        
        if let Some(expires_at) = self.expires_at {
            if Utc::now() >= expires_at {
                return true;
            }
        }
        
        false
    }
}