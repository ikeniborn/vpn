//! Custom Resource Definitions for VPN resources

use kube::CustomResource;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// VPN Server custom resource
#[derive(CustomResource, Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[kube(
    group = "vpn.io",
    version = "v1alpha1",
    kind = "VpnServer",
    plural = "vpnservers",
    shortname = "vpn",
    namespaced,
    status = "VpnServerStatus",
    printcolumn = r#"{"name": "Protocol", "type": "string", "jsonPath": ".spec.protocol"}"#,
    printcolumn = r#"{"name": "Port", "type": "integer", "jsonPath": ".spec.port"}"#,
    printcolumn = r#"{"name": "Status", "type": "string", "jsonPath": ".status.phase"}"#,
    printcolumn = r#"{"name": "Age", "type": "date", "jsonPath": ".metadata.creationTimestamp"}"#
)]
pub struct VpnServerSpec {
    /// VPN protocol to use (vless, outline, etc.)
    pub protocol: VpnProtocol,
    
    /// Port to expose the VPN service
    pub port: u16,
    
    /// Number of replicas (for HA mode)
    #[serde(default = "default_replicas")]
    pub replicas: i32,
    
    /// Enable high availability mode
    #[serde(default)]
    pub high_availability: bool,
    
    /// Resource requirements
    #[serde(default)]
    pub resources: ResourceRequirements,
    
    /// User management configuration
    pub users: UserManagement,
    
    /// Network configuration
    #[serde(default)]
    pub network: NetworkConfig,
    
    /// Security settings
    #[serde(default)]
    pub security: SecurityConfig,
    
    /// Monitoring configuration
    #[serde(default)]
    pub monitoring: MonitoringConfig,
    
    /// Additional labels to apply
    #[serde(default)]
    pub labels: BTreeMap<String, String>,
    
    /// Additional annotations
    #[serde(default)]
    pub annotations: BTreeMap<String, String>,
}

/// VPN protocol types
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum VpnProtocol {
    Vless,
    Outline,
    Wireguard,
    OpenVPN,
}

/// Resource requirements
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ResourceRequirements {
    /// CPU request
    #[serde(default = "default_cpu_request")]
    pub cpu_request: String,
    
    /// CPU limit
    #[serde(default = "default_cpu_limit")]
    pub cpu_limit: String,
    
    /// Memory request
    #[serde(default = "default_memory_request")]
    pub memory_request: String,
    
    /// Memory limit
    #[serde(default = "default_memory_limit")]
    pub memory_limit: String,
    
    /// Storage size for persistent data
    #[serde(default = "default_storage_size")]
    pub storage_size: String,
}

/// User management configuration
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct UserManagement {
    /// Maximum number of users
    pub max_users: u32,
    
    /// Enable automatic user creation
    #[serde(default)]
    pub auto_create: bool,
    
    /// User quota (in GB, 0 for unlimited)
    #[serde(default)]
    pub quota_gb: u64,
    
    /// Enable external authentication
    #[serde(default)]
    pub external_auth: Option<ExternalAuth>,
}

/// External authentication configuration
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ExternalAuth {
    /// Authentication type
    pub auth_type: AuthType,
    
    /// Endpoint URL
    pub endpoint: String,
    
    /// Secret name containing credentials
    pub secret_name: String,
}

/// Authentication types
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum AuthType {
    Ldap,
    OAuth2,
    Oidc,
    Saml,
}

/// Network configuration
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, Default)]
pub struct NetworkConfig {
    /// Service type (ClusterIP, NodePort, LoadBalancer)
    #[serde(default = "default_service_type")]
    pub service_type: String,
    
    /// Load balancer source ranges
    #[serde(default)]
    pub load_balancer_source_ranges: Vec<String>,
    
    /// Node port (if service type is NodePort)
    pub node_port: Option<u32>,
    
    /// Enable IPv6
    #[serde(default)]
    pub enable_ipv6: bool,
}

/// Security configuration
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, Default)]
pub struct SecurityConfig {
    /// Enable TLS
    #[serde(default = "default_true")]
    pub enable_tls: bool,
    
    /// TLS certificate secret name
    pub tls_secret: Option<String>,
    
    /// Enable firewall rules
    #[serde(default = "default_true")]
    pub enable_firewall: bool,
    
    /// Allowed IP ranges
    #[serde(default)]
    pub allowed_ips: Vec<String>,
    
    /// Enable intrusion detection
    #[serde(default)]
    pub enable_ids: bool,
}

/// Monitoring configuration
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, Default)]
pub struct MonitoringConfig {
    /// Enable metrics
    #[serde(default = "default_true")]
    pub enable_metrics: bool,
    
    /// Metrics port
    #[serde(default = "default_metrics_port")]
    pub metrics_port: u16,
    
    /// Enable tracing
    #[serde(default)]
    pub enable_tracing: bool,
    
    /// Tracing endpoint
    pub tracing_endpoint: Option<String>,
}

/// VPN Server status
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct VpnServerStatus {
    /// Current phase of the VPN server
    pub phase: VpnPhase,
    
    /// Status message
    pub message: Option<String>,
    
    /// Number of ready replicas
    pub ready_replicas: i32,
    
    /// Total number of replicas
    pub replicas: i32,
    
    /// Active users count
    pub active_users: u32,
    
    /// Total traffic in bytes
    pub total_traffic_bytes: u64,
    
    /// Service endpoint
    pub endpoint: Option<String>,
    
    /// Conditions
    #[serde(default)]
    pub conditions: Vec<Condition>,
    
    /// Last update time (RFC3339 format)
    pub last_updated: String,
}

impl Default for VpnServerStatus {
    fn default() -> Self {
        Self {
            phase: VpnPhase::Pending,
            message: None,
            ready_replicas: 0,
            replicas: 0,
            active_users: 0,
            total_traffic_bytes: 0,
            endpoint: None,
            conditions: Vec::new(),
            last_updated: chrono::Utc::now().to_rfc3339(),
        }
    }
}

/// VPN server phases
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq)]
pub enum VpnPhase {
    Pending,
    Creating,
    Running,
    Updating,
    Degraded,
    Failed,
    Terminating,
}

/// Status condition
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Condition {
    /// Type of condition
    pub condition_type: String,
    
    /// Status (True, False, Unknown)
    pub status: String,
    
    /// Reason for the condition
    pub reason: String,
    
    /// Human-readable message
    pub message: String,
    
    /// Last transition time (RFC3339 format)
    pub last_transition_time: String,
}

// Default functions
fn default_replicas() -> i32 { 1 }
fn default_cpu_request() -> String { "100m".to_string() }
fn default_cpu_limit() -> String { "500m".to_string() }
fn default_memory_request() -> String { "128Mi".to_string() }
fn default_memory_limit() -> String { "512Mi".to_string() }
fn default_storage_size() -> String { "1Gi".to_string() }
fn default_service_type() -> String { "ClusterIP".to_string() }
fn default_true() -> bool { true }
fn default_metrics_port() -> u16 { 9090 }

impl Default for ResourceRequirements {
    fn default() -> Self {
        Self {
            cpu_request: default_cpu_request(),
            cpu_limit: default_cpu_limit(),
            memory_request: default_memory_request(),
            memory_limit: default_memory_limit(),
            storage_size: default_storage_size(),
        }
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vpn_server_serialization() {
        let spec = VpnServerSpec {
            protocol: VpnProtocol::Vless,
            port: 8443,
            replicas: 3,
            high_availability: true,
            resources: ResourceRequirements::default(),
            users: UserManagement {
                max_users: 100,
                auto_create: true,
                quota_gb: 50,
                external_auth: None,
            },
            network: NetworkConfig::default(),
            security: SecurityConfig::default(),
            monitoring: MonitoringConfig::default(),
            labels: BTreeMap::new(),
            annotations: BTreeMap::new(),
        };

        let json = serde_json::to_string(&spec).unwrap();
        let _deserialized: VpnServerSpec = serde_json::from_str(&json).unwrap();
    }
}