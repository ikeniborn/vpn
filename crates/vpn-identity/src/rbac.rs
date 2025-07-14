//! Role-Based Access Control (RBAC) implementation

use crate::{
    error::{IdentityError, Result},
    models::{Permission, Role},
    storage::Storage,
};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

pub struct RbacService {
    storage: Arc<Storage>,
    permission_cache: Arc<RwLock<HashMap<Uuid, (Vec<Permission>, chrono::DateTime<chrono::Utc>)>>>,
    cache_ttl: chrono::Duration,
    cache_enabled: bool,
}

impl RbacService {
    pub fn new(storage: Arc<Storage>, cache_enabled: bool, cache_ttl_secs: u64) -> Self {
        Self {
            storage,
            permission_cache: Arc::new(RwLock::new(HashMap::new())),
            cache_ttl: chrono::Duration::seconds(cache_ttl_secs as i64),
            cache_enabled,
        }
    }

    /// Check if a user has a specific permission
    pub async fn check_permission(
        &self,
        user_id: Uuid,
        resource: &str,
        action: &str,
    ) -> Result<bool> {
        let permissions = self.get_user_permissions(user_id).await?;
        
        Ok(permissions.iter().any(|p| {
            p.resource == resource && p.action == action
        }))
    }

    /// Check if a user has any of the specified roles
    pub async fn check_roles(&self, user_id: Uuid, required_roles: &[String]) -> Result<bool> {
        let user = self.storage.get_user(user_id).await?
            .ok_or(IdentityError::UserNotFound(user_id.to_string()))?;
        
        let user_roles: HashSet<_> = user.roles.iter().collect();
        let required: HashSet<_> = required_roles.iter().collect();
        
        Ok(!user_roles.is_disjoint(&required))
    }

    /// Get all permissions for a user
    pub async fn get_user_permissions(&self, user_id: Uuid) -> Result<Vec<Permission>> {
        // Check cache first if enabled
        if self.cache_enabled {
            let cache = self.permission_cache.read().await;
            if let Some((permissions, cached_at)) = cache.get(&user_id) {
                if chrono::Utc::now() - *cached_at < self.cache_ttl {
                    return Ok(permissions.clone());
                }
            }
        }

        // Get from storage
        let permissions = self.storage.get_user_permissions(user_id).await?;

        // Update cache if enabled
        if self.cache_enabled {
            let mut cache = self.permission_cache.write().await;
            cache.insert(user_id, (permissions.clone(), chrono::Utc::now()));
        }

        Ok(permissions)
    }

    /// Assign a role to a user
    pub async fn assign_role(&self, user_id: Uuid, role_name: &str) -> Result<()> {
        // Verify role exists
        let _role = self.storage.get_role_by_name(role_name).await?
            .ok_or_else(|| IdentityError::ValidationError(format!("Role '{}' not found", role_name)))?;

        // Get user
        let mut user = self.storage.get_user(user_id).await?
            .ok_or(IdentityError::UserNotFound(user_id.to_string()))?;

        // Add role if not already assigned
        if !user.roles.contains(&role_name.to_string()) {
            user.roles.push(role_name.to_string());
            self.storage.update_user(&user).await?;
        }

        // Invalidate cache
        if self.cache_enabled {
            let mut cache = self.permission_cache.write().await;
            cache.remove(&user_id);
        }

        Ok(())
    }

    /// Remove a role from a user
    pub async fn remove_role(&self, user_id: Uuid, role_name: &str) -> Result<()> {
        // Get user
        let mut user = self.storage.get_user(user_id).await?
            .ok_or(IdentityError::UserNotFound(user_id.to_string()))?;

        // Remove role
        user.roles.retain(|r| r != role_name);
        self.storage.update_user(&user).await?;

        // Invalidate cache
        if self.cache_enabled {
            let mut cache = self.permission_cache.write().await;
            cache.remove(&user_id);
        }

        Ok(())
    }

    /// Create a new role
    pub async fn create_role(
        &self,
        name: &str,
        description: Option<String>,
        permission_names: Vec<String>,
    ) -> Result<Role> {
        // Verify permissions exist
        for perm_name in &permission_names {
            let parts: Vec<&str> = perm_name.split(':').collect();
            if parts.len() != 2 {
                return Err(IdentityError::ValidationError(
                    format!("Invalid permission format: {}. Expected 'resource:action'", perm_name)
                ));
            }
        }

        let role = Role {
            id: Uuid::new_v4(),
            name: name.to_string(),
            description,
            permissions: permission_names,
            is_system: false,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };

        self.storage.create_role(&role).await?;
        Ok(role)
    }

    /// Update a role
    pub async fn update_role(
        &self,
        role_id: Uuid,
        description: Option<String>,
        permission_names: Option<Vec<String>>,
    ) -> Result<Role> {
        let mut role = self.storage.get_role(role_id).await?
            .ok_or_else(|| IdentityError::ValidationError(format!("Role not found: {}", role_id)))?;

        if role.is_system {
            return Err(IdentityError::ValidationError("Cannot modify system roles".to_string()));
        }

        if let Some(desc) = description {
            role.description = Some(desc);
        }

        if let Some(perms) = permission_names {
            role.permissions = perms;
        }

        role.updated_at = chrono::Utc::now();
        self.storage.update_role(&role).await?;

        // Invalidate all user caches since role permissions changed
        if self.cache_enabled {
            let mut cache = self.permission_cache.write().await;
            cache.clear();
        }

        Ok(role)
    }

    /// Delete a role
    pub async fn delete_role(&self, role_id: Uuid) -> Result<()> {
        let role = self.storage.get_role(role_id).await?
            .ok_or_else(|| IdentityError::ValidationError(format!("Role not found: {}", role_id)))?;

        if role.is_system {
            return Err(IdentityError::ValidationError("Cannot delete system roles".to_string()));
        }

        self.storage.delete_role(role_id).await?;

        // Invalidate all user caches
        if self.cache_enabled {
            let mut cache = self.permission_cache.write().await;
            cache.clear();
        }

        Ok(())
    }

    /// Create a new permission
    pub async fn create_permission(
        &self,
        name: &str,
        resource: &str,
        action: &str,
        description: Option<String>,
    ) -> Result<Permission> {
        let permission = Permission {
            id: Uuid::new_v4(),
            name: name.to_string(),
            resource: resource.to_string(),
            action: action.to_string(),
            description,
            created_at: chrono::Utc::now(),
        };

        self.storage.create_permission(&permission).await?;
        Ok(permission)
    }

    /// Get all roles
    pub async fn list_roles(&self) -> Result<Vec<Role>> {
        self.storage.list_roles().await
    }

    /// Get all permissions
    pub async fn list_permissions(&self) -> Result<Vec<Permission>> {
        self.storage.list_permissions().await
    }
}