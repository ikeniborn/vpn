//! VPN Identity Service Binary

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    middleware,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use axum_extra::extract::cookie::CookieJar;
use std::net::SocketAddr;
use std::sync::Arc;
use tower::ServiceBuilder;
use tower_http::{
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing::{info, warn};
use vpn_identity::{
    config::IdentityConfig,
    error::IdentityError,
    models::*,
    service::IdentityService,
};

#[derive(Clone)]
struct AppState {
    service: Arc<IdentityService>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,vpn_identity=debug".into()),
        )
        .init();

    // Load configuration
    let config = load_config()?;
    let bind_addr: SocketAddr = format!("{}:{}", config.server.bind_address, config.server.port)
        .parse()?;

    // Initialize service
    info!("Initializing VPN Identity Service...");
    let service = Arc::new(IdentityService::new(config.clone()).await?);

    // Create app state
    let state = AppState {
        service: service.clone(),
    };

    // Build router
    let app = Router::new()
        // Health check
        .route("/health", get(health_check))
        // Authentication endpoints
        .route("/auth/login", post(login))
        .route("/auth/logout", post(logout))
        .route("/auth/refresh", post(refresh_token))
        .route("/auth/oauth2/:provider/authorize", get(oauth2_authorize))
        .route("/auth/oauth2/:provider/callback", get(oauth2_callback))
        // User management
        .route("/users", get(list_users).post(create_user))
        .route("/users/:id", get(get_user).put(update_user).delete(delete_user))
        .route("/users/me", get(get_current_user))
        .route("/users/:id/password", post(change_password))
        // Role management
        .route("/roles", get(list_roles).post(create_role))
        .route("/roles/:id", get(get_role).put(update_role).delete(delete_role))
        .route("/users/:id/roles", post(assign_role).delete(remove_role))
        // Permission management
        .route("/permissions", get(list_permissions))
        // Session management
        .route("/sessions", get(list_sessions))
        .route("/sessions/:id", delete(delete_session))
        // Add state
        .with_state(state)
        // Add middleware
        .layer(
            ServiceBuilder::new()
                .layer(TraceLayer::new_for_http())
                .layer(
                    CorsLayer::new()
                        .allow_origin(Any)
                        .allow_methods(Any)
                        .allow_headers(Any),
                ),
        );

    // Start server
    info!("Starting VPN Identity Service on {}", bind_addr);
    axum::Server::bind(&bind_addr)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}

fn load_config() -> anyhow::Result<IdentityConfig> {
    // Try to load from environment variables or config file
    if let Ok(config_path) = std::env::var("IDENTITY_CONFIG_PATH") {
        let config_str = std::fs::read_to_string(config_path)?;
        Ok(toml::from_str(&config_str)?)
    } else {
        // Load from environment variables
        let config = IdentityConfig {
            database_url: std::env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgres://vpn:vpn@localhost/vpn_identity".to_string()),
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            jwt: vpn_identity::config::JwtConfig {
                secret_key: std::env::var("JWT_SECRET")
                    .unwrap_or_else(|_| "change-me-in-production".to_string()),
                ..Default::default()
            },
            ..Default::default()
        };
        Ok(config)
    }
}

// Handler functions
async fn health_check(State(state): State<AppState>) -> impl IntoResponse {
    match state.service.health_check().await {
        Ok(true) => (StatusCode::OK, Json(serde_json::json!({"status": "healthy"}))),
        _ => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({"status": "unhealthy"})),
        ),
    }
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<AuthenticationResult>, IdentityError> {
    let auth_service = state.service.auth_service.read().await;
    let result = auth_service.authenticate(&req.username, &req.password).await?;
    Ok(Json(result))
}

async fn logout(
    State(state): State<AppState>,
    cookies: CookieJar,
) -> Result<StatusCode, IdentityError> {
    if let Some(session_cookie) = cookies.get("vpn_session") {
        let auth_service = state.service.auth_service.read().await;
        auth_service.logout(session_cookie.value()).await?;
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn refresh_token(
    State(state): State<AppState>,
    Json(req): Json<RefreshTokenRequest>,
) -> Result<Json<AuthToken>, IdentityError> {
    let auth_service = state.service.auth_service.read().await;
    let token = auth_service.refresh_token(&req.refresh_token).await?;
    Ok(Json(token))
}

async fn oauth2_authorize(
    State(state): State<AppState>,
    Path(provider): Path<String>,
) -> Result<Json<serde_json::Value>, IdentityError> {
    // Implementation would handle OAuth2 authorization
    Ok(Json(serde_json::json!({
        "auth_url": "https://provider.com/authorize",
        "state": "random-state"
    })))
}

async fn oauth2_callback(
    State(state): State<AppState>,
    Path(provider): Path<String>,
    Query(params): Query<OAuth2LoginRequest>,
) -> Result<Json<AuthenticationResult>, IdentityError> {
    // Implementation would handle OAuth2 callback
    let auth_service = state.service.auth_service.read().await;
    let user_info = serde_json::json!({
        "email": "user@example.com",
        "sub": "12345"
    });
    let result = auth_service.authenticate_oauth2(&provider, user_info).await?;
    Ok(Json(result))
}

async fn list_users(
    State(state): State<AppState>,
) -> Result<Json<Vec<User>>, IdentityError> {
    let users = state.service.storage.list_users(100, 0).await?;
    Ok(Json(users))
}

async fn create_user(
    State(state): State<AppState>,
    Json(req): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<User>), IdentityError> {
    // Implementation would create user
    Ok((StatusCode::CREATED, Json(User::default())))
}

async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<User>, IdentityError> {
    let user = state.service.storage.get_user(id).await?
        .ok_or(IdentityError::UserNotFound(id.to_string()))?;
    Ok(Json(user))
}

async fn update_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateUserRequest>,
) -> Result<Json<User>, IdentityError> {
    // Implementation would update user
    Ok(Json(User::default()))
}

async fn delete_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, IdentityError> {
    state.service.storage.delete_user(id).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn get_current_user() -> Result<Json<UserInfo>, IdentityError> {
    // Implementation would get current user from JWT
    Ok(Json(UserInfo {
        id: Uuid::new_v4(),
        email: "current@example.com".to_string(),
        username: "current".to_string(),
        display_name: None,
        roles: vec!["user".to_string()],
        permissions: vec![],
    }))
}

async fn change_password(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<ChangePasswordRequest>,
) -> Result<StatusCode, IdentityError> {
    // Implementation would change password
    Ok(StatusCode::NO_CONTENT)
}

async fn list_roles(
    State(state): State<AppState>,
) -> Result<Json<Vec<Role>>, IdentityError> {
    let roles = state.service.rbac_service.list_roles().await?;
    Ok(Json(roles))
}

async fn create_role(
    State(state): State<AppState>,
    Json(req): Json<CreateRoleRequest>,
) -> Result<(StatusCode, Json<Role>), IdentityError> {
    let role = state.service.rbac_service.create_role(
        &req.name,
        req.description,
        req.permissions,
    ).await?;
    Ok((StatusCode::CREATED, Json(role)))
}

async fn get_role(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Role>, IdentityError> {
    let role = state.service.storage.get_role(id).await?
        .ok_or_else(|| IdentityError::ValidationError(format!("Role not found: {}", id)))?;
    Ok(Json(role))
}

async fn update_role(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<serde_json::Value>,
) -> Result<Json<Role>, IdentityError> {
    // Implementation would update role
    Ok(Json(Role {
        id,
        name: "updated".to_string(),
        description: None,
        permissions: vec![],
        is_system: false,
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
    }))
}

async fn delete_role(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, IdentityError> {
    state.service.rbac_service.delete_role(id).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn assign_role(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<AssignRoleRequest>,
) -> Result<StatusCode, IdentityError> {
    state.service.rbac_service.assign_role(id, &req.role_name).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn remove_role(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<StatusCode, IdentityError> {
    if let Some(role_name) = params.get("role") {
        state.service.rbac_service.remove_role(id, role_name).await?;
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn list_permissions(
    State(state): State<AppState>,
) -> Result<Json<Vec<Permission>>, IdentityError> {
    let permissions = state.service.rbac_service.list_permissions().await?;
    Ok(Json(permissions))
}

async fn list_sessions(
    State(state): State<AppState>,
) -> Result<Json<Vec<Session>>, IdentityError> {
    // Implementation would list sessions
    Ok(Json(vec![]))
}

async fn delete_session(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<StatusCode, IdentityError> {
    let mut session_manager = state.service.session_manager.write().await;
    session_manager.delete_session(&id).await?;
    Ok(StatusCode::NO_CONTENT)
}

// Error handling
impl IntoResponse for IdentityError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match &self {
            IdentityError::AuthenticationFailed(_) => (StatusCode::UNAUTHORIZED, self.to_string()),
            IdentityError::AuthorizationFailed(_) => (StatusCode::FORBIDDEN, self.to_string()),
            IdentityError::InvalidCredentials => (StatusCode::UNAUTHORIZED, self.to_string()),
            IdentityError::TokenExpired => (StatusCode::UNAUTHORIZED, self.to_string()),
            IdentityError::InsufficientPermissions => (StatusCode::FORBIDDEN, self.to_string()),
            IdentityError::UserNotFound(_) => (StatusCode::NOT_FOUND, self.to_string()),
            IdentityError::ValidationError(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string()),
        };
        
        (status, Json(serde_json::json!({"error": message}))).into_response()
    }
}

use std::collections::HashMap;
use uuid::Uuid;