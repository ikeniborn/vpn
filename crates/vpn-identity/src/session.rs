//! Session management with Redis backend

use crate::{
    error::{IdentityError, Result},
    models::{AuthProvider, Session},
};
use chrono::{Duration, Utc};
use redis::{aio::ConnectionManager, AsyncCommands};
use serde_json;
use uuid::Uuid;

pub struct SessionManager {
    redis: ConnectionManager,
    default_expiration: Duration,
    key_prefix: String,
}

impl SessionManager {
    pub async fn new(redis_url: &str, default_expiration_secs: u64) -> Result<Self> {
        let client = redis::Client::open(redis_url)?;
        let redis = ConnectionManager::new(client).await?;
        
        Ok(Self {
            redis,
            default_expiration: Duration::seconds(default_expiration_secs as i64),
            key_prefix: "vpn:session:".to_string(),
        })
    }

    pub async fn create_session(
        &mut self,
        user_id: Uuid,
        provider: AuthProvider,
        ip_address: Option<String>,
        user_agent: Option<String>,
        custom_expiration: Option<Duration>,
    ) -> Result<String> {
        let session_id = Uuid::new_v4().to_string();
        let now = Utc::now();
        let expiration = custom_expiration.unwrap_or(self.default_expiration);
        
        let session = Session {
            id: session_id.clone(),
            user_id,
            provider,
            ip_address,
            user_agent,
            expires_at: now + expiration,
            created_at: now,
            last_accessed: now,
        };
        
        let key = format!("{}{}", self.key_prefix, session_id);
        let value = serde_json::to_string(&session)?;
        let expiry_secs = expiration.num_seconds() as usize;
        
        self.redis.set_ex(&key, value, expiry_secs).await?;
        
        // Also store in a user's session set for easy lookup
        let user_sessions_key = format!("{}user:{}", self.key_prefix, user_id);
        self.redis.sadd(&user_sessions_key, &session_id).await?;
        self.redis.expire(&user_sessions_key, expiry_secs).await?;
        
        Ok(session_id)
    }

    pub async fn get_session(&mut self, session_id: &str) -> Result<Option<Session>> {
        let key = format!("{}{}", self.key_prefix, session_id);
        let value: Option<String> = self.redis.get(&key).await?;
        
        match value {
            Some(json) => {
                let mut session: Session = serde_json::from_str(&json)?;
                
                // Check if expired
                if session.expires_at < Utc::now() {
                    self.delete_session(session_id).await?;
                    return Ok(None);
                }
                
                // Update last accessed time
                session.last_accessed = Utc::now();
                let updated_json = serde_json::to_string(&session)?;
                let ttl: isize = self.redis.ttl(&key).await?;
                if ttl > 0 {
                    self.redis.set_ex(&key, updated_json, ttl as usize).await?;
                }
                
                Ok(Some(session))
            }
            None => Ok(None),
        }
    }

    pub async fn extend_session(&mut self, session_id: &str, additional_time: Option<Duration>) -> Result<()> {
        let key = format!("{}{}", self.key_prefix, session_id);
        let extension = additional_time.unwrap_or(self.default_expiration);
        
        let exists: bool = self.redis.exists(&key).await?;
        if !exists {
            return Err(IdentityError::SessionError("Session not found".to_string()));
        }
        
        let current_ttl: isize = self.redis.ttl(&key).await?;
        if current_ttl > 0 {
            let new_ttl = current_ttl + extension.num_seconds() as isize;
            self.redis.expire(&key, new_ttl as usize).await?;
        }
        
        Ok(())
    }

    pub async fn delete_session(&mut self, session_id: &str) -> Result<()> {
        let key = format!("{}{}", self.key_prefix, session_id);
        
        // Get session to find user_id
        let value: Option<String> = self.redis.get(&key).await?;
        if let Some(json) = value {
            let session: Session = serde_json::from_str(&json)?;
            
            // Remove from user's session set
            let user_sessions_key = format!("{}user:{}", self.key_prefix, session.user_id);
            self.redis.srem(&user_sessions_key, session_id).await?;
        }
        
        // Delete the session
        self.redis.del(&key).await?;
        
        Ok(())
    }

    pub async fn delete_user_sessions(&mut self, user_id: Uuid) -> Result<()> {
        let user_sessions_key = format!("{}user:{}", self.key_prefix, user_id);
        
        // Get all session IDs for the user
        let session_ids: Vec<String> = self.redis.smembers(&user_sessions_key).await?;
        
        // Delete each session
        for session_id in session_ids {
            let key = format!("{}{}", self.key_prefix, session_id);
            self.redis.del(&key).await?;
        }
        
        // Delete the user's session set
        self.redis.del(&user_sessions_key).await?;
        
        Ok(())
    }

    pub async fn list_user_sessions(&mut self, user_id: Uuid) -> Result<Vec<Session>> {
        let user_sessions_key = format!("{}user:{}", self.key_prefix, user_id);
        let session_ids: Vec<String> = self.redis.smembers(&user_sessions_key).await?;
        
        let mut sessions = Vec::new();
        for session_id in session_ids {
            if let Some(session) = self.get_session(&session_id).await? {
                sessions.push(session);
            }
        }
        
        Ok(sessions)
    }

    pub async fn cleanup_expired_sessions(&mut self) -> Result<usize> {
        // This is handled automatically by Redis TTL, but we can implement
        // a manual cleanup if needed for the user session sets
        
        // In production, this would be more sophisticated
        Ok(0)
    }
}