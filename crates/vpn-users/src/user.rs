use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;
use vpn_types::protocol::VpnProtocol;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub short_id: String,
    pub name: String,
    pub email: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_active: Option<DateTime<Utc>>,
    pub status: UserStatus,
    pub protocol: VpnProtocol,
    pub config: UserConfig,
    pub stats: UserStats,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserConfig {
    pub public_key: Option<String>,
    pub private_key: Option<String>,
    pub server_host: String,
    pub server_port: u16,
    pub sni: Option<String>,
    pub path: Option<String>,
    pub security: String,
    pub network: String,
    pub header_type: Option<String>,
    pub flow: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserStats {
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub connection_count: u64,
    pub last_connection: Option<DateTime<Utc>>,
    pub total_uptime: u64, // seconds
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UserStatus {
    Active,
    Inactive,
    Suspended,
    Expired,
}

// VpnProtocol is now imported from vpn_types::protocol

impl User {
    pub fn new(name: String, protocol: VpnProtocol) -> Self {
        let id = Uuid::new_v4().to_string();
        let uuid_gen = vpn_crypto::UuidGenerator::new();
        let short_id = uuid_gen.generate_short_id(&id).unwrap_or_else(|_| "default".to_string());
        
        Self {
            id,
            short_id,
            name,
            email: None,
            created_at: Utc::now(),
            last_active: None,
            status: UserStatus::Active,
            protocol,
            config: UserConfig::default(),
            stats: UserStats::default(),
        }
    }
    
    pub fn with_email(mut self, email: String) -> Self {
        self.email = Some(email);
        self
    }
    
    pub fn with_config(mut self, config: UserConfig) -> Self {
        self.config = config;
        self
    }
    
    pub fn is_active(&self) -> bool {
        matches!(self.status, UserStatus::Active)
    }
    
    pub fn activate(&mut self) {
        self.status = UserStatus::Active;
    }
    
    pub fn deactivate(&mut self) {
        self.status = UserStatus::Inactive;
    }
    
    pub fn suspend(&mut self) {
        self.status = UserStatus::Suspended;
    }
    
    pub fn update_last_active(&mut self) {
        self.last_active = Some(Utc::now());
    }
    
    pub fn add_traffic(&mut self, sent: u64, received: u64) {
        self.stats.bytes_sent += sent;
        self.stats.bytes_received += received;
        self.stats.connection_count += 1;
        self.stats.last_connection = Some(Utc::now());
    }
    
    pub fn total_traffic(&self) -> u64 {
        self.stats.bytes_sent + self.stats.bytes_received
    }
    
    pub fn days_since_creation(&self) -> i64 {
        let now = Utc::now();
        (now - self.created_at).num_days()
    }
    
    pub fn days_since_last_active(&self) -> Option<i64> {
        self.last_active.map(|last| {
            let now = Utc::now();
            (now - last).num_days()
        })
    }
}

impl Default for UserConfig {
    fn default() -> Self {
        Self {
            public_key: None,
            private_key: None,
            server_host: "127.0.0.1".to_string(),
            server_port: 443,
            sni: None,
            path: Some("/".to_string()),
            security: "reality".to_string(),
            network: "tcp".to_string(),
            header_type: None,
            flow: Some("xtls-rprx-vision".to_string()),
        }
    }
}

impl Default for UserStats {
    fn default() -> Self {
        Self {
            bytes_sent: 0,
            bytes_received: 0,
            connection_count: 0,
            last_connection: None,
            total_uptime: 0,
        }
    }
}

impl UserStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            UserStatus::Active => "active",
            UserStatus::Inactive => "inactive",
            UserStatus::Suspended => "suspended",
            UserStatus::Expired => "expired",
        }
    }
}

// VpnProtocol methods are now provided by vpn_types::protocol::VpnProtocol