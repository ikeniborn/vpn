//! VPN Proxy Authentication Service
//! 
//! This service provides ForwardAuth authentication for Traefik proxy

use anyhow::Result;
use axum::{
    extract::{Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tracing::{error, info};
use vpn_proxy::{
    auth::AuthManager,
    config::{AuthConfig, ProxyConfig, RateLimitConfig},
    error::ProxyError,
    manager::ProxyManager,
    metrics::ProxyMetrics,
};

#[derive(Clone)]
struct AppState {
    manager: Arc<ProxyManager>,
}

#[derive(Deserialize)]
struct AuthQuery {
    #[serde(default)]
    username: Option<String>,
    #[serde(default)]
    password: Option<String>,
}

#[derive(Serialize)]
struct AuthResponse {
    success: bool,
    user_id: Option<String>,
    message: Option<String>,
}

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    version: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("vpn_proxy=info".parse()?)
        )
        .init();

    info!("Starting VPN Proxy Authentication Service");

    // Load configuration
    let config = load_config().await?;
    
    // Create metrics
    let metrics = ProxyMetrics::new()
        .map_err(|e| anyhow::anyhow!("Failed to create metrics: {}", e))?;
    
    // Create proxy manager
    let manager = ProxyManager::new(config.clone(), metrics)
        .map_err(|e| anyhow::anyhow!("Failed to create proxy manager: {}", e))?;
    
    let state = AppState {
        manager: Arc::new(manager),
    };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/auth/verify", post(verify_auth).get(verify_auth))
        .route("/metrics", get(metrics_handler))
        .with_state(state);

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    let listener = TcpListener::bind(&addr).await?;
    
    info!("Authentication service listening on {}", addr);
    
    axum::serve(listener, app).await?;
    
    Ok(())
}

async fn health_check() -> impl IntoResponse {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

async fn verify_auth(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<AuthQuery>,
) -> impl IntoResponse {
    // Extract credentials from Authorization header or query params
    let credentials = extract_credentials(&headers, query);
    
    // Get client IP from X-Forwarded-For or X-Real-IP
    let client_ip = extract_client_ip(&headers);
    let peer_addr = match client_ip.parse::<SocketAddr>() {
        Ok(addr) => addr,
        Err(_) => SocketAddr::from(([0, 0, 0, 0], 0)),
    };
    
    // Authenticate
    match state.manager.authenticate(credentials.map(|(u, p)| (u, p)), peer_addr).await {
        Ok(user_id) => {
            info!("Authentication successful for user: {}", user_id);
            
            // Return success with custom headers
            let mut headers = HeaderMap::new();
            headers.insert("X-User-ID", user_id.parse().unwrap());
            headers.insert("X-Auth-Status", "success".parse().unwrap());
            
            (StatusCode::OK, headers, Json(AuthResponse {
                success: true,
                user_id: Some(user_id),
                message: None,
            }))
        }
        Err(e) => {
            error!("Authentication failed: {}", e);
            
            let status = match e {
                ProxyError::RateLimitExceeded => StatusCode::TOO_MANY_REQUESTS,
                ProxyError::AuthenticationFailed(_) => StatusCode::UNAUTHORIZED,
                _ => StatusCode::INTERNAL_SERVER_ERROR,
            };
            
            (status, HeaderMap::new(), Json(AuthResponse {
                success: false,
                user_id: None,
                message: Some(format!("Authentication failed: {}", e)),
            }))
        }
    }
}

async fn metrics_handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.manager.metrics().export() {
        Ok(metrics) => (
            StatusCode::OK,
            [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
            metrics,
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            [(header::CONTENT_TYPE, "text/plain")],
            format!("Error exporting metrics: {}", e),
        ),
    }
}

fn extract_credentials(headers: &HeaderMap, query: AuthQuery) -> Option<(String, String)> {
    // First check Authorization header
    if let Some(auth_header) = headers.get(header::AUTHORIZATION) {
        if let Ok(auth_str) = auth_header.to_str() {
            if auth_str.starts_with("Basic ") {
                let encoded = &auth_str[6..];
                use base64::{Engine as _, engine::general_purpose};
                if let Ok(decoded) = general_purpose::STANDARD.decode(encoded) {
                    if let Ok(creds) = String::from_utf8(decoded) {
                        let parts: Vec<&str> = creds.splitn(2, ':').collect();
                        if parts.len() == 2 {
                            return Some((parts[0].to_string(), parts[1].to_string()));
                        }
                    }
                }
            }
        }
    }
    
    // Check Proxy-Authorization header
    if let Some(auth_header) = headers.get("proxy-authorization") {
        if let Ok(auth_str) = auth_header.to_str() {
            if auth_str.starts_with("Basic ") {
                let encoded = &auth_str[6..];
                use base64::{Engine as _, engine::general_purpose};
                if let Ok(decoded) = general_purpose::STANDARD.decode(encoded) {
                    if let Ok(creds) = String::from_utf8(decoded) {
                        let parts: Vec<&str> = creds.splitn(2, ':').collect();
                        if parts.len() == 2 {
                            return Some((parts[0].to_string(), parts[1].to_string()));
                        }
                    }
                }
            }
        }
    }
    
    // Fall back to query parameters
    if let (Some(username), Some(password)) = (query.username, query.password) {
        return Some((username, password));
    }
    
    None
}

fn extract_client_ip(headers: &HeaderMap) -> String {
    // Check X-Forwarded-For
    if let Some(forwarded) = headers.get("x-forwarded-for") {
        if let Ok(forwarded_str) = forwarded.to_str() {
            // Take the first IP in the chain
            if let Some(ip) = forwarded_str.split(',').next() {
                return ip.trim().to_string();
            }
        }
    }
    
    // Check X-Real-IP
    if let Some(real_ip) = headers.get("x-real-ip") {
        if let Ok(ip_str) = real_ip.to_str() {
            return ip_str.to_string();
        }
    }
    
    // Default
    "0.0.0.0".to_string()
}

async fn load_config() -> Result<ProxyConfig> {
    // Try to load from file first
    let config_path = std::env::var("CONFIG_PATH")
        .unwrap_or_else(|_| "/etc/proxy/config.toml".to_string());
    
    if std::path::Path::new(&config_path).exists() {
        ProxyConfig::load_from_file(std::path::Path::new(&config_path)).await
            .map_err(|e| anyhow::anyhow!("Failed to load config: {}", e))
    } else {
        // Use environment variables
        Ok(ProxyConfig {
            auth: AuthConfig {
                enabled: std::env::var("AUTH_ENABLED")
                    .unwrap_or_else(|_| "true".to_string())
                    .parse()
                    .unwrap_or(true),
                backend: vpn_proxy::config::AuthBackend::VpnUsers,
                cache_ttl: std::time::Duration::from_secs(300),
                allow_anonymous: false,
                ip_whitelist: vec![],
            },
            rate_limit: RateLimitConfig {
                enabled: std::env::var("RATE_LIMIT_ENABLED")
                    .unwrap_or_else(|_| "true".to_string())
                    .parse()
                    .unwrap_or(true),
                requests_per_second: std::env::var("RATE_LIMIT_RPS")
                    .unwrap_or_else(|_| "100".to_string())
                    .parse()
                    .unwrap_or(100),
                burst_size: 200,
                bandwidth_limit: None,
                global_limit: Some(10000),
            },
            ..Default::default()
        })
    }
}