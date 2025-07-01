//! Main identity service that orchestrates all components

use crate::{
    auth::{AuthProvider, AuthService},
    config::IdentityConfig,
    error::Result,
    ldap::LdapProvider,
    oauth::{OAuth2Provider, OidcProvider},
    rbac::RbacService,
    session::SessionManager,
    storage::Storage,
};
use std::sync::Arc;
use tokio::sync::RwLock;

pub struct IdentityService {
    pub config: IdentityConfig,
    pub storage: Arc<Storage>,
    pub auth_service: Arc<RwLock<AuthService>>,
    pub rbac_service: Arc<RbacService>,
    pub session_manager: Arc<RwLock<SessionManager>>,
}

impl IdentityService {
    pub async fn new(config: IdentityConfig) -> Result<Self> {
        // Initialize storage
        let storage = Arc::new(Storage::new(&config.database_url).await?);
        
        // Run migrations
        storage.migrate().await?;
        
        // Initialize session manager
        let session_manager = Arc::new(RwLock::new(
            SessionManager::new(&config.redis_url, config.session.expiration_secs).await?
        ));
        
        // Initialize auth service
        let auth_service = AuthService::new(
            storage.clone(),
            config.jwt.secret_key.clone(),
            config.jwt.expiration_secs,
            config.jwt.refresh_expiration_secs,
            config.jwt.issuer.clone(),
            config.jwt.audience.clone(),
        );
        
        let auth_service = Arc::new(RwLock::new(auth_service));
        
        // Initialize RBAC service
        let rbac_service = Arc::new(RbacService::new(
            storage.clone(),
            config.rbac.cache_permissions,
            config.rbac.cache_ttl_secs,
        ));
        
        let service = Self {
            config,
            storage,
            auth_service,
            rbac_service,
            session_manager,
        };
        
        // Initialize auth providers
        service.initialize_providers().await?;
        
        // Initialize default roles and permissions
        service.initialize_rbac().await?;
        
        Ok(service)
    }

    async fn initialize_providers(&self) -> Result<()> {
        let mut auth_service = self.auth_service.write().await;
        
        // Add LDAP provider if configured
        if let Some(ldap_config) = &self.config.ldap {
            let ldap_provider = LdapProvider::new(ldap_config.clone());
            auth_service.add_provider(Box::new(ldap_provider));
        }
        
        // Add OAuth2 providers
        for (name, oauth_config) in &self.config.oauth2_providers {
            let provider = OAuth2Provider::new(name.clone(), oauth_config.clone())?;
            // Note: In a real implementation, we'd need to adapt OAuth2Provider to implement AuthProvider
            // This is a simplified example
        }
        
        Ok(())
    }

    async fn initialize_rbac(&self) -> Result<()> {
        // Create default permissions if they don't exist
        let default_permissions = vec![
            ("users:read", "users", "read", "Read user information"),
            ("users:write", "users", "write", "Create and update users"),
            ("users:delete", "users", "delete", "Delete users"),
            ("vpn:connect", "vpn", "connect", "Connect to VPN"),
            ("vpn:manage", "vpn", "manage", "Manage VPN configurations"),
            ("admin:all", "admin", "all", "Full administrative access"),
        ];
        
        for (name, resource, action, description) in default_permissions {
            // Check if permission exists
            let permissions = self.storage.list_permissions().await?;
            if !permissions.iter().any(|p| p.name == name) {
                self.rbac_service.create_permission(
                    name,
                    resource,
                    action,
                    Some(description.to_string()),
                ).await?;
            }
        }
        
        // Create default roles if they don't exist
        let roles = self.storage.list_roles().await?;
        
        if !roles.iter().any(|r| r.name == "admin") {
            self.rbac_service.create_role(
                "admin",
                Some("Administrator with full access".to_string()),
                vec!["admin:all".to_string()],
            ).await?;
        }
        
        if !roles.iter().any(|r| r.name == "user") {
            self.rbac_service.create_role(
                "user",
                Some("Regular user with VPN access".to_string()),
                vec!["users:read".to_string(), "vpn:connect".to_string()],
            ).await?;
        }
        
        if !roles.iter().any(|r| r.name == "manager") {
            self.rbac_service.create_role(
                "manager",
                Some("VPN manager with configuration access".to_string()),
                vec![
                    "users:read".to_string(),
                    "users:write".to_string(),
                    "vpn:connect".to_string(),
                    "vpn:manage".to_string(),
                ],
            ).await?;
        }
        
        Ok(())
    }

    pub async fn health_check(&self) -> Result<bool> {
        // Check database connection
        let _ = self.storage.list_users(1, 0).await?;
        
        // Check Redis connection
        let mut session_manager = self.session_manager.write().await;
        session_manager.cleanup_expired_sessions().await?;
        
        Ok(true)
    }
}