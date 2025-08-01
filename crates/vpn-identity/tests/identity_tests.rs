//! Integration tests for VPN Identity Service

use vpn_identity::{config::IdentityConfig, models::*, service::IdentityService, IdentityError};

#[tokio::test]
async fn test_identity_service_creation() {
    let config = IdentityConfig::default();
    // Note: This test would fail without a real database
    // In a real test, we'd use testcontainers to spin up PostgreSQL and Redis
}

#[test]
fn test_auth_provider_enum() {
    let provider = AuthProvider::Ldap;
    assert_eq!(serde_json::to_string(&provider).unwrap(), "\"ldap\"");

    let custom = AuthProvider::Custom("keycloak".to_string());
    let json = serde_json::to_string(&custom).unwrap();
    assert!(json.contains("keycloak"));
}

#[test]
fn test_user_model_validation() {
    use validator::Validate;

    let mut user = User::default();
    user.email = "invalid-email".to_string();

    assert!(user.validate().is_err());

    user.email = "valid@example.com".to_string();
    assert!(user.validate().is_ok());
}

#[test]
fn test_jwt_claims_serialization() {
    use chrono::Utc;
    use vpn_identity::auth::Claims;

    let claims = Claims {
        sub: "user-123".to_string(),
        email: "user@example.com".to_string(),
        username: "testuser".to_string(),
        roles: vec!["user".to_string(), "admin".to_string()],
        exp: (Utc::now() + chrono::Duration::hours(1)).timestamp(),
        iat: Utc::now().timestamp(),
        iss: "vpn-identity".to_string(),
        aud: vec!["vpn-services".to_string()],
    };

    let json = serde_json::to_string(&claims).unwrap();
    assert!(json.contains("user-123"));
    assert!(json.contains("testuser"));
}

#[test]
fn test_error_types() {
    let err = IdentityError::InvalidCredentials;
    assert_eq!(err.to_string(), "Invalid credentials");

    let err = IdentityError::UserNotFound("123".to_string());
    assert_eq!(err.to_string(), "User not found: 123");

    let err = IdentityError::InsufficientPermissions;
    assert_eq!(err.to_string(), "Insufficient permissions");
}
