//! Authentication module for proxy server

use crate::{
    config::{AuthBackend, AuthConfig},
    error::{ProxyError, Result},
};
use dashmap::DashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::debug;
use vpn_users::UserManager;

/// Cached authentication entry
#[derive(Clone, Debug)]
struct CachedAuth {
    user_id: String,
    expires_at: Instant,
}

/// Authentication manager
pub struct AuthManager {
    config: AuthConfig,
    cache: Arc<DashMap<String, CachedAuth>>,
    user_manager: Option<Arc<UserManager>>,
}

impl AuthManager {
    /// Create a new authentication manager
    pub fn new(config: &AuthConfig) -> Result<Self> {
        let user_manager = match &config.backend {
            AuthBackend::VpnUsers => {
                // Initialize user manager with a default server config
                let server_config = vpn_users::config::ServerConfig {
                    host: "proxy.local".to_string(),
                    port: 8080,
                    sni: None,
                    public_key: None,
                    private_key: None,
                    short_id: None,
                    reality_dest: None,
                    reality_server_names: vec![],
                };
                let user_mgr = UserManager::new(std::path::Path::new("/var/lib/vpn/users"), server_config)
                    .map_err(|e| ProxyError::config(format!("Failed to init user manager: {}", e)))?;
                Some(Arc::new(user_mgr))
            }
            _ => None,
        };
        
        Ok(Self {
            config: config.clone(),
            cache: Arc::new(DashMap::new()),
            user_manager,
        })
    }
    
    /// Authenticate a user with username and password
    pub async fn authenticate(&self, username: &str, password: &str) -> Result<String> {
        // Check cache first
        let cache_key = format!("{}:{}", username, password);
        if let Some(cached) = self.cache.get(&cache_key) {
            if cached.expires_at > Instant::now() {
                debug!("Authentication cache hit for user: {}", username);
                return Ok(cached.user_id.clone());
            } else {
                // Remove expired entry
                self.cache.remove(&cache_key);
            }
        }
        
        // Authenticate based on backend
        let user_id = match &self.config.backend {
            AuthBackend::VpnUsers => {
                self.authenticate_vpn_user(username, password).await?
            }
            AuthBackend::File { path } => {
                self.authenticate_from_file(username, password, path).await?
            }
            AuthBackend::Ldap { url } => {
                self.authenticate_ldap(username, password, url).await?
            }
            AuthBackend::Http { url } => {
                self.authenticate_http(username, password, url).await?
            }
        };
        
        // Cache successful authentication
        let cached = CachedAuth {
            user_id: user_id.clone(),
            expires_at: Instant::now() + self.config.cache_ttl,
        };
        self.cache.insert(cache_key, cached);
        
        Ok(user_id)
    }
    
    /// Authenticate using VPN user database
    async fn authenticate_vpn_user(&self, username: &str, password: &str) -> Result<String> {
        let user_manager = self.user_manager.as_ref()
            .ok_or_else(|| ProxyError::config("User manager not initialized"))?;
        
        // Find user by name
        let users = user_manager.list_users(None).await
            .map_err(|e| ProxyError::auth_failed(format!("Failed to list users: {}", e)))?;
        
        let user = users.iter()
            .find(|u| u.name == username)
            .ok_or_else(|| ProxyError::auth_failed("User not found"))?;
        
        // Check if user is active
        if !user.is_active() {
            return Err(ProxyError::auth_failed("User is not active"));
        }
        
        // Verify password (using user's private key as password for now)
        let expected_password = user.config.private_key.as_deref()
            .unwrap_or(&user.id);
        
        if password != expected_password {
            return Err(ProxyError::auth_failed("Invalid password"));
        }
        
        Ok(user.id.clone())
    }
    
    /// Authenticate from a static file
    async fn authenticate_from_file(
        &self,
        username: &str,
        password: &str,
        path: &std::path::Path,
    ) -> Result<String> {
        use tokio::io::{AsyncBufReadExt, BufReader};
        use tokio::fs::File;
        
        let file = File::open(path).await
            .map_err(|e| ProxyError::config(format!("Failed to open auth file: {}", e)))?;
        
        let reader = BufReader::new(file);
        let mut lines = reader.lines();
        
        while let Some(line) = lines.next_line().await? {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            
            // Format: username:password_hash
            let parts: Vec<&str> = line.splitn(2, ':').collect();
            if parts.len() != 2 {
                continue;
            }
            
            if parts[0] == username {
                // Verify password using argon2
                if verify_password(password, parts[1])? {
                    return Ok(username.to_string());
                } else {
                    return Err(ProxyError::auth_failed("Invalid password"));
                }
            }
        }
        
        Err(ProxyError::auth_failed("User not found"))
    }
    
    /// Authenticate via LDAP
    async fn authenticate_ldap(
        &self,
        _username: &str,
        _password: &str,
        _url: &str,
    ) -> Result<String> {
        // TODO: Implement LDAP authentication
        Err(ProxyError::config("LDAP authentication not yet implemented"))
    }
    
    /// Authenticate via HTTP API
    async fn authenticate_http(
        &self,
        username: &str,
        password: &str,
        url: &str,
    ) -> Result<String> {
        use reqwest::Client;
        use serde_json::json;
        
        let client = Client::new();
        let response = client
            .post(url)
            .json(&json!({
                "username": username,
                "password": password
            }))
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| ProxyError::auth_failed(format!("HTTP auth request failed: {}", e)))?;
        
        if response.status().is_success() {
            let body: serde_json::Value = response.json().await
                .map_err(|e| ProxyError::auth_failed(format!("Invalid auth response: {}", e)))?;
            
            let user_id = body["user_id"].as_str()
                .ok_or_else(|| ProxyError::auth_failed("Missing user_id in response"))?;
            
            Ok(user_id.to_string())
        } else {
            Err(ProxyError::auth_failed("Authentication failed"))
        }
    }
    
    /// Clear authentication cache
    pub fn clear_cache(&self) {
        self.cache.clear();
    }
    
    /// Remove expired cache entries
    pub fn cleanup_cache(&self) {
        let now = Instant::now();
        self.cache.retain(|_, v| v.expires_at > now);
    }
}

/// Verify password using argon2
fn verify_password(password: &str, hash: &str) -> Result<bool> {
    use argon2::{Argon2, PasswordHash, PasswordVerifier};
    
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|e| ProxyError::internal(format!("Invalid password hash: {}", e)))?;
    
    let argon2 = Argon2::default();
    Ok(argon2.verify_password(password.as_bytes(), &parsed_hash).is_ok())
}

/// Hash password using argon2
pub fn hash_password(password: &str) -> Result<String> {
    use argon2::{
        password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
        Argon2,
    };
    
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    
    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| ProxyError::internal(format!("Failed to hash password: {}", e)))?;
    
    Ok(password_hash.to_string())
}