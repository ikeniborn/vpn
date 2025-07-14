//! Database storage layer for identity management

use crate::{
    error::Result,
    models::{AuthProvider, Permission, Role, User},
};
use chrono::Duration;
use sqlx::{sqlite::SqlitePoolOptions, SqlitePool, Row};
use uuid::Uuid;

pub struct Storage {
    pool: SqlitePool,
}

impl Storage {
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = SqlitePoolOptions::new()
            .max_connections(32)
            .connect(database_url)
            .await?;
        
        Ok(Self { pool })
    }

    pub async fn migrate(&self) -> Result<()> {
        sqlx::migrate!("./migrations").run(&self.pool).await?;
        Ok(())
    }

    // User operations
    pub async fn create_user(&self, user: &User) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO users (
                id, email, username, display_name, provider, provider_id,
                password_hash, roles, attributes, is_active, email_verified,
                created_at, updated_at, last_login
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
            "#,
        )
        .bind(user.id)
        .bind(&user.email)
        .bind(&user.username)
        .bind(&user.display_name)
        .bind(serde_json::to_value(&user.provider)?)
        .bind(&user.provider_id)
        .bind(&user.password_hash)
        .bind(&user.roles)
        .bind(&user.attributes)
        .bind(user.is_active)
        .bind(user.email_verified)
        .bind(user.created_at)
        .bind(user.updated_at)
        .bind(user.last_login)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn get_user(&self, user_id: Uuid) -> Result<Option<User>> {
        let row = sqlx::query(
            "SELECT id, username, email, display_name, provider, provider_id, roles, created_at, updated_at, last_login FROM users WHERE id = ?"
        )
        .bind(user_id.to_string())
        .fetch_optional(&self.pool)
        .await?;
        
        if let Some(row) = row {
            let user = User {
                id: row.get("id"),
                username: row.get("username"),
                email: row.get("email"),
                display_name: row.get("display_name"),
                provider: row.get("provider"),
                provider_id: row.get("provider_id"),
                roles: row.get("roles"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
                last_login: row.get("last_login"),
            };
            Ok(Some(user))
        } else {
            Ok(None)
        }
    }

    pub async fn find_user_by_email(&self, email: &str) -> Result<Option<User>> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, username, display_name,
                provider as "provider: _",
                provider_id, password_hash, roles, attributes,
                is_active, email_verified, created_at, updated_at, last_login
            FROM users WHERE email = $1
            "#,
            email
        )
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(user)
    }

    pub async fn find_user_by_username(&self, username: &str) -> Result<Option<User>> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, username, display_name,
                provider as "provider: _",
                provider_id, password_hash, roles, attributes,
                is_active, email_verified, created_at, updated_at, last_login
            FROM users WHERE username = $1
            "#,
            username
        )
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(user)
    }

    pub async fn update_user(&self, user: &User) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE users SET
                email = $2, username = $3, display_name = $4,
                provider = $5, provider_id = $6, password_hash = $7,
                roles = $8, attributes = $9, is_active = $10,
                email_verified = $11, updated_at = $12, last_login = $13
            WHERE id = $1
            "#,
            user.id,
            user.email,
            user.username,
            user.display_name,
            serde_json::to_value(&user.provider)?,
            user.provider_id,
            user.password_hash,
            &user.roles,
            user.attributes,
            user.is_active,
            user.email_verified,
            user.updated_at,
            user.last_login,
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn delete_user(&self, user_id: Uuid) -> Result<()> {
        sqlx::query!("DELETE FROM users WHERE id = $1", user_id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }

    pub async fn list_users(&self, limit: i64, offset: i64) -> Result<Vec<User>> {
        let users = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, username, display_name,
                provider as "provider: _",
                provider_id, password_hash, roles, attributes,
                is_active, email_verified, created_at, updated_at, last_login
            FROM users
            ORDER BY created_at DESC
            LIMIT $1 OFFSET $2
            "#,
            limit,
            offset
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(users)
    }

    // Role operations
    pub async fn create_role(&self, role: &Role) -> Result<()> {
        sqlx::query!(
            r#"
            INSERT INTO roles (id, name, description, permissions, is_system, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            "#,
            role.id,
            role.name,
            role.description,
            &role.permissions,
            role.is_system,
            role.created_at,
            role.updated_at,
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn get_role(&self, role_id: Uuid) -> Result<Option<Role>> {
        let role = sqlx::query_as!(
            Role,
            r#"
            SELECT id, name, description, permissions, is_system, created_at, updated_at
            FROM roles WHERE id = $1
            "#,
            role_id
        )
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(role)
    }

    pub async fn get_role_by_name(&self, name: &str) -> Result<Option<Role>> {
        let role = sqlx::query_as!(
            Role,
            r#"
            SELECT id, name, description, permissions, is_system, created_at, updated_at
            FROM roles WHERE name = $1
            "#,
            name
        )
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(role)
    }

    pub async fn update_role(&self, role: &Role) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE roles SET
                name = $2, description = $3, permissions = $4, updated_at = $5
            WHERE id = $1
            "#,
            role.id,
            role.name,
            role.description,
            &role.permissions,
            role.updated_at,
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn delete_role(&self, role_id: Uuid) -> Result<()> {
        sqlx::query!("DELETE FROM roles WHERE id = $1", role_id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }

    pub async fn list_roles(&self) -> Result<Vec<Role>> {
        let roles = sqlx::query_as!(
            Role,
            r#"
            SELECT id, name, description, permissions, is_system, created_at, updated_at
            FROM roles ORDER BY name
            "#
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(roles)
    }

    // Permission operations
    pub async fn create_permission(&self, permission: &Permission) -> Result<()> {
        sqlx::query!(
            r#"
            INSERT INTO permissions (id, name, resource, action, description, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            "#,
            permission.id,
            permission.name,
            permission.resource,
            permission.action,
            permission.description,
            permission.created_at,
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn list_permissions(&self) -> Result<Vec<Permission>> {
        let permissions = sqlx::query_as!(
            Permission,
            r#"
            SELECT id, name, resource, action, description, created_at
            FROM permissions ORDER BY resource, action
            "#
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(permissions)
    }

    pub async fn get_user_permissions(&self, user_id: Uuid) -> Result<Vec<Permission>> {
        let permissions = sqlx::query_as!(
            Permission,
            r#"
            SELECT DISTINCT p.id, p.name, p.resource, p.action, p.description, p.created_at
            FROM permissions p
            JOIN roles r ON p.name = ANY(r.permissions)
            JOIN users u ON r.name = ANY(u.roles)
            WHERE u.id = $1
            ORDER BY p.resource, p.action
            "#,
            user_id
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(permissions)
    }

    // Session operations (for database-based session tracking if needed)
    pub async fn create_session(
        &self,
        _user_id: Uuid,
        _provider: AuthProvider,
        _expiration: Duration,
    ) -> Result<String> {
        // This is a placeholder - actual implementation would depend on whether
        // you want database-backed sessions in addition to Redis
        let session_id = Uuid::new_v4().to_string();
        Ok(session_id)
    }

    pub async fn delete_session(&self, _session_id: &str) -> Result<()> {
        // Placeholder for database-backed session deletion
        Ok(())
    }
}