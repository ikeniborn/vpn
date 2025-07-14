//! VPN Identity and Authentication Service
//!
//! This crate provides comprehensive identity management including:
//! - LDAP authentication
//! - OAuth2/OIDC integration
//! - Single Sign-On (SSO)
//! - Role-Based Access Control (RBAC)
//! - Session management
//! - JWT token handling

pub mod auth;
pub mod config;
pub mod error;
pub mod ldap;
pub mod models;
pub mod oauth;
pub mod rbac;
pub mod service;
pub mod session;
pub mod storage;

pub use auth::{AuthProvider, AuthService, AuthenticationResult};
pub use config::IdentityConfig;
pub use error::{IdentityError, Result};
pub use models::{User, Role, Permission, Session};
pub use oauth::{OAuth2Provider, OAuthConfig};
pub use rbac::RbacService;
pub use service::IdentityService;
pub use session::SessionManager;