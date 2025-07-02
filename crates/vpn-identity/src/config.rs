//! Configuration for the identity service

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IdentityConfig {
    /// Database connection URL
    pub database_url: String,
    
    /// Redis connection URL for session storage
    pub redis_url: String,
    
    /// JWT configuration
    pub jwt: JwtConfig,
    
    /// LDAP configuration (optional)
    pub ldap: Option<LdapConfig>,
    
    /// OAuth2 providers configuration
    pub oauth2_providers: HashMap<String, OAuth2ProviderConfig>,
    
    /// Session configuration
    pub session: SessionConfig,
    
    /// RBAC configuration
    pub rbac: RbacConfig,
    
    /// Service binding configuration
    pub server: ServerConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtConfig {
    /// Secret key for signing JWTs
    pub secret_key: String,
    
    /// Token expiration in seconds
    pub expiration_secs: u64,
    
    /// Refresh token expiration in seconds
    pub refresh_expiration_secs: u64,
    
    /// JWT issuer
    pub issuer: String,
    
    /// JWT audience
    pub audience: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LdapConfig {
    /// LDAP server URL (ldap:// or ldaps://)
    pub url: String,
    
    /// Base DN for user searches
    pub base_dn: String,
    
    /// Bind DN for LDAP authentication
    pub bind_dn: Option<String>,
    
    /// Bind password
    pub bind_password: Option<String>,
    
    /// User search filter (e.g., "(uid={username})")
    pub user_filter: String,
    
    /// User attributes to fetch
    pub user_attributes: Vec<String>,
    
    /// Group search filter
    pub group_filter: Option<String>,
    
    /// TLS configuration
    pub tls: Option<LdapTlsConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LdapTlsConfig {
    /// Whether to verify server certificate
    pub verify_cert: bool,
    
    /// CA certificate path
    pub ca_cert_path: Option<PathBuf>,
    
    /// Client certificate path
    pub client_cert_path: Option<PathBuf>,
    
    /// Client key path
    pub client_key_path: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuth2ProviderConfig {
    /// Provider type (google, github, azure, custom)
    pub provider_type: String,
    
    /// Client ID
    pub client_id: String,
    
    /// Client secret
    pub client_secret: String,
    
    /// Authorization URL
    pub auth_url: String,
    
    /// Token URL
    pub token_url: String,
    
    /// User info URL
    pub userinfo_url: Option<String>,
    
    /// Redirect URL
    pub redirect_url: String,
    
    /// Scopes to request
    pub scopes: Vec<String>,
    
    /// Additional provider-specific settings
    pub extra: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionConfig {
    /// Session cookie name
    pub cookie_name: String,
    
    /// Session expiration in seconds
    pub expiration_secs: u64,
    
    /// Whether to use secure cookies (HTTPS only)
    pub secure: bool,
    
    /// SameSite cookie policy
    pub same_site: String,
    
    /// HTTP only flag
    pub http_only: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RbacConfig {
    /// Default role for new users
    pub default_role: String,
    
    /// Whether to sync roles from external providers
    pub sync_external_roles: bool,
    
    /// Role mapping from external providers
    pub role_mappings: HashMap<String, String>,
    
    /// Whether to enable permission caching
    pub cache_permissions: bool,
    
    /// Permission cache TTL in seconds
    pub cache_ttl_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Server bind address
    pub bind_address: String,
    
    /// Server port
    pub port: u16,
    
    /// Whether to enable CORS
    pub enable_cors: bool,
    
    /// Allowed CORS origins
    pub cors_origins: Vec<String>,
    
    /// Request timeout in seconds
    pub request_timeout_secs: u64,
}

impl Default for IdentityConfig {
    fn default() -> Self {
        Self {
            database_url: "postgres://vpn:vpn@localhost/vpn_identity".to_string(),
            redis_url: "redis://localhost:6379".to_string(),
            jwt: JwtConfig::default(),
            ldap: None,
            oauth2_providers: HashMap::new(),
            session: SessionConfig::default(),
            rbac: RbacConfig::default(),
            server: ServerConfig::default(),
        }
    }
}

impl Default for JwtConfig {
    fn default() -> Self {
        Self {
            secret_key: "change-me-in-production".to_string(),
            expiration_secs: 3600, // 1 hour
            refresh_expiration_secs: 86400 * 7, // 7 days
            issuer: "vpn-identity".to_string(),
            audience: vec!["vpn-services".to_string()],
        }
    }
}

impl Default for SessionConfig {
    fn default() -> Self {
        Self {
            cookie_name: "vpn_session".to_string(),
            expiration_secs: 86400, // 24 hours
            secure: true,
            same_site: "lax".to_string(),
            http_only: true,
        }
    }
}

impl Default for RbacConfig {
    fn default() -> Self {
        Self {
            default_role: "user".to_string(),
            sync_external_roles: true,
            role_mappings: HashMap::new(),
            cache_permissions: true,
            cache_ttl_secs: 300, // 5 minutes
        }
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind_address: "0.0.0.0".to_string(),
            port: 8080,
            enable_cors: true,
            cors_origins: vec!["http://localhost:3000".to_string()],
            request_timeout_secs: 30,
        }
    }
}