//! Error types for the identity service

use thiserror::Error;

pub type Result<T> = std::result::Result<T, IdentityError>;

#[derive(Error, Debug)]
pub enum IdentityError {
    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    #[error("Authorization failed: {0}")]
    AuthorizationFailed(String),

    #[error("LDAP error: {0}")]
    LdapError(#[from] ldap3::LdapError),

    #[error("OAuth2 error: {0}")]
    OAuth2Error(String),

    #[error("JWT error: {0}")]
    JwtError(#[from] jsonwebtoken::errors::Error),

    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Migration error: {0}")]
    MigrationError(#[from] sqlx::migrate::MigrateError),

    #[error("Session error: {0}")]
    SessionError(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("User not found: {0}")]
    UserNotFound(String),

    #[error("Invalid credentials")]
    InvalidCredentials,

    #[error("Token expired")]
    TokenExpired,

    #[error("Insufficient permissions")]
    InsufficientPermissions,

    #[error("Provider not configured: {0}")]
    ProviderNotConfigured(String),

    #[error("Redis error: {0}")]
    RedisError(#[from] redis::RedisError),

    #[error("Internal error: {0}")]
    Internal(String),
}
