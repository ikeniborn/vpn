//! Authentication service and providers

use crate::{
    error::{IdentityError, Result},
    models::{AuthProvider as AuthProviderType, AuthToken, User, UserInfo},
    storage::Storage,
    ldap::LdapProvider,
};
use async_trait::async_trait;
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

#[async_trait]
pub trait AuthProvider: Send + Sync {
    /// Authenticate a user with credentials
    async fn authenticate(&self, username: &str, password: &str) -> Result<User>;
    
    /// Get provider type
    fn provider_type(&self) -> AuthProviderType;
    
    /// Verify if the provider is properly configured
    async fn verify_configuration(&self) -> Result<()>;
}

// Local auth provider implementation
#[derive(Clone)]
pub struct LocalAuthProvider {
    storage: Arc<Storage>,
}

impl LocalAuthProvider {
    pub fn new(storage: Arc<Storage>) -> Self {
        Self { storage }
    }
}

#[async_trait]
impl AuthProvider for LocalAuthProvider {
    async fn authenticate(&self, username: &str, password: &str) -> Result<User> {
        let user = self.storage.find_user_by_username(username).await?
            .ok_or(IdentityError::InvalidCredentials)?;
        
        if let Some(password_hash) = &user.password_hash {
            // Verify password with argon2
            use argon2::{Argon2, PasswordHash, PasswordVerifier};
            let parsed_hash = PasswordHash::new(password_hash)
                .map_err(|_| IdentityError::InvalidCredentials)?;
            
            Argon2::default()
                .verify_password(password.as_bytes(), &parsed_hash)
                .map_err(|_| IdentityError::InvalidCredentials)?;
            
            Ok(user)
        } else {
            Err(IdentityError::InvalidCredentials)
        }
    }
    
    fn provider_type(&self) -> AuthProviderType {
        AuthProviderType::Local
    }
    
    async fn verify_configuration(&self) -> Result<()> {
        // Check database connection
        let _ = self.storage.list_users(1, 0).await?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String, // User ID
    pub email: String,
    pub username: String,
    pub roles: Vec<String>,
    pub exp: i64,
    pub iat: i64,
    pub iss: String,
    pub aud: Vec<String>,
}

// Enum for different auth providers to avoid trait object issues
#[derive(Clone)]
pub enum AuthProviderEnum {
    Local(LocalAuthProvider),
    Ldap(LdapProvider),
}

impl AuthProviderEnum {
    pub async fn authenticate(&self, username: &str, password: &str) -> Result<User> {
        match self {
            AuthProviderEnum::Local(provider) => provider.authenticate(username, password).await,
            AuthProviderEnum::Ldap(provider) => provider.authenticate(username, password).await,
        }
    }
    
    pub fn provider_type(&self) -> AuthProviderType {
        match self {
            AuthProviderEnum::Local(provider) => provider.provider_type(),
            AuthProviderEnum::Ldap(provider) => provider.provider_type(),
        }
    }
    
    pub async fn verify_configuration(&self) -> Result<()> {
        match self {
            AuthProviderEnum::Local(provider) => provider.verify_configuration().await,
            AuthProviderEnum::Ldap(provider) => provider.verify_configuration().await,
        }
    }
}

pub struct AuthService {
    storage: Arc<Storage>,
    jwt_secret: String,
    jwt_expiration: Duration,
    jwt_refresh_expiration: Duration,
    jwt_issuer: String,
    jwt_audience: Vec<String>,
    providers: Vec<AuthProviderEnum>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthenticationResult {
    pub user: UserInfo,
    pub token: AuthToken,
    pub session_id: String,
}

impl AuthService {
    pub fn new(
        storage: Arc<Storage>,
        jwt_secret: String,
        jwt_expiration_secs: u64,
        jwt_refresh_expiration_secs: u64,
        jwt_issuer: String,
        jwt_audience: Vec<String>,
    ) -> Self {
        Self {
            storage,
            jwt_secret,
            jwt_expiration: Duration::seconds(jwt_expiration_secs as i64),
            jwt_refresh_expiration: Duration::seconds(jwt_refresh_expiration_secs as i64),
            jwt_issuer,
            jwt_audience,
            providers: Vec::new(),
        }
    }

    pub fn add_provider(&mut self, provider: AuthProviderEnum) {
        self.providers.push(provider);
    }

    pub async fn authenticate(
        &self,
        username: &str,
        password: &str,
    ) -> Result<AuthenticationResult> {
        // Try each provider in order
        let mut last_error = None;
        
        for provider in &self.providers {
            match provider.authenticate(username, password).await {
                Ok(mut user) => {
                    // Update last login
                    user.last_login = Some(Utc::now());
                    self.storage.update_user(&user).await?;
                    
                    // Get user permissions
                    let permissions = self.storage.get_user_permissions(user.id).await?
                        .into_iter()
                        .map(|p| p.name)
                        .collect();
                    
                    // Create JWT token
                    let token = self.create_token(&user)?;
                    
                    // Create session
                    let session_id = self.storage.create_session(
                        user.id,
                        provider.provider_type(),
                        self.jwt_expiration,
                    ).await?;
                    
                    let user_info = UserInfo {
                        id: user.id,
                        email: user.email,
                        username: user.username,
                        display_name: user.display_name,
                        roles: user.roles,
                        permissions,
                    };
                    
                    return Ok(AuthenticationResult {
                        user: user_info,
                        token,
                        session_id,
                    });
                }
                Err(e) => {
                    last_error = Some(e);
                    continue;
                }
            }
        }
        
        Err(last_error.unwrap_or(IdentityError::InvalidCredentials))
    }

    pub async fn authenticate_oauth2(
        &self,
        provider_name: &str,
        user_info: serde_json::Value,
    ) -> Result<AuthenticationResult> {
        // Extract user information from OAuth2 response
        let email = user_info["email"]
            .as_str()
            .ok_or_else(|| IdentityError::OAuth2Error("Missing email".to_string()))?;
        
        let username = user_info["preferred_username"]
            .as_str()
            .or_else(|| user_info["login"].as_str())
            .or_else(|| user_info["name"].as_str())
            .unwrap_or(email);
        
        let display_name = user_info["name"].as_str().map(String::from);
        
        // Find or create user
        let mut user = match self.storage.find_user_by_email(email).await? {
            Some(user) => user,
            None => {
                // Create new user from OAuth2
                let provider = match provider_name {
                    "google" => AuthProviderType::Google,
                    "github" => AuthProviderType::Github,
                    "azure" => AuthProviderType::Azure,
                    other => AuthProviderType::Custom(other.to_string()),
                };
                
                let new_user = User {
                    id: Uuid::new_v4(),
                    email: email.to_string(),
                    username: username.to_string(),
                    display_name,
                    provider,
                    provider_id: user_info["sub"].as_str().map(String::from),
                    password_hash: None,
                    roles: vec!["user".to_string()],
                    attributes: user_info,
                    is_active: true,
                    email_verified: true,
                    created_at: Utc::now(),
                    updated_at: Utc::now(),
                    last_login: Some(Utc::now()),
                };
                
                self.storage.create_user(&new_user).await?;
                new_user
            }
        };
        
        // Update last login
        user.last_login = Some(Utc::now());
        self.storage.update_user(&user).await?;
        
        // Get user permissions
        let permissions = self.storage.get_user_permissions(user.id).await?
            .into_iter()
            .map(|p| p.name)
            .collect();
        
        // Create JWT token
        let token = self.create_token(&user)?;
        
        // Create session
        let session_id = self.storage.create_session(
            user.id,
            user.provider.clone(),
            self.jwt_expiration,
        ).await?;
        
        let user_info = UserInfo {
            id: user.id,
            email: user.email,
            username: user.username,
            display_name: user.display_name,
            roles: user.roles,
            permissions,
        };
        
        Ok(AuthenticationResult {
            user: user_info,
            token,
            session_id,
        })
    }

    pub async fn refresh_token(&self, refresh_token: &str) -> Result<AuthToken> {
        // Decode refresh token
        let token_data = decode::<Claims>(
            refresh_token,
            &DecodingKey::from_secret(self.jwt_secret.as_bytes()),
            &Validation::new(Algorithm::HS256),
        )?;
        
        let user_id = Uuid::parse_str(&token_data.claims.sub)
            .map_err(|_| IdentityError::JwtError(jsonwebtoken::errors::ErrorKind::InvalidSubject.into()))?;
        
        // Get user
        let user = self.storage.get_user(user_id).await?
            .ok_or(IdentityError::UserNotFound(user_id.to_string()))?;
        
        // Create new token
        self.create_token(&user)
    }

    pub async fn validate_token(&self, token: &str) -> Result<Claims> {
        let token_data = decode::<Claims>(
            token,
            &DecodingKey::from_secret(self.jwt_secret.as_bytes()),
            &Validation::new(Algorithm::HS256),
        )?;
        
        Ok(token_data.claims)
    }

    pub async fn logout(&self, session_id: &str) -> Result<()> {
        self.storage.delete_session(session_id).await
    }

    fn create_token(&self, user: &User) -> Result<AuthToken> {
        let now = Utc::now();
        let exp = now + self.jwt_expiration;
        let refresh_exp = now + self.jwt_refresh_expiration;
        
        let claims = Claims {
            sub: user.id.to_string(),
            email: user.email.clone(),
            username: user.username.clone(),
            roles: user.roles.clone(),
            exp: exp.timestamp(),
            iat: now.timestamp(),
            iss: self.jwt_issuer.clone(),
            aud: self.jwt_audience.clone(),
        };
        
        let token = encode(
            &Header::new(Algorithm::HS256),
            &claims,
            &EncodingKey::from_secret(self.jwt_secret.as_bytes()),
        )?;
        
        // Create refresh token with longer expiration
        let refresh_claims = Claims {
            exp: refresh_exp.timestamp(),
            ..claims
        };
        
        let refresh_token = encode(
            &Header::new(Algorithm::HS256),
            &refresh_claims,
            &EncodingKey::from_secret(self.jwt_secret.as_bytes()),
        )?;
        
        Ok(AuthToken {
            access_token: token,
            token_type: "Bearer".to_string(),
            expires_in: self.jwt_expiration.num_seconds() as u64,
            refresh_token: Some(refresh_token),
            scope: Some(user.roles.join(" ")),
        })
    }
}