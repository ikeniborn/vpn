use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use crate::user::{User, VpnProtocol, UserStatus};
use crate::manager::UserManager;
use crate::error::{Result};
use tokio::task::JoinSet;

pub struct BatchOperations {
    user_manager: Arc<UserManager>,
}

#[derive(Debug, Clone)]
pub struct BatchCreateRequest {
    pub names: Vec<String>,
    pub protocol: VpnProtocol,
    pub emails: Option<Vec<String>>,
}

#[derive(Debug, Clone)]
pub struct BatchOperationResult {
    pub successful: Vec<String>,
    pub failed: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct ImportOptions {
    pub overwrite_existing: bool,
    pub validate_configs: bool,
    pub generate_new_keys: bool,
}

impl BatchOperations {
    pub fn new(user_manager: Arc<UserManager>) -> Self {
        Self { user_manager }
    }
    
    pub async fn create_multiple_users(
        &self,
        request: BatchCreateRequest,
    ) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        let mut tasks = JoinSet::new();
        
        for (index, name) in request.names.iter().enumerate() {
            let name = name.clone();
            let protocol = request.protocol;
            let email = request.emails.as_ref()
                .and_then(|emails| emails.get(index))
                .cloned();
            
            let user_manager = Arc::clone(&self.user_manager);
            
            tasks.spawn(async move {
                match user_manager.create_user(name.clone(), protocol).await {
                    Ok(mut user) => {
                        if let Some(email) = email {
                            user.email = Some(email);
                            if let Err(e) = user_manager.update_user(user).await {
                                return (name, Err(e));
                            }
                        }
                        (name, Ok(()))
                    }
                    Err(e) => (name, Err(e)),
                }
            });
        }
        
        while let Some(result) = tasks.join_next().await {
            match result {
                Ok((name, Ok(()))) => successful.push(name),
                Ok((name, Err(e))) => {
                    failed.insert(name, e.to_string());
                }
                Err(e) => {
                    failed.insert("unknown".to_string(), e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
    
    pub async fn delete_multiple_users(&self, user_ids: Vec<String>) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        for user_id in user_ids {
            match self.user_manager.delete_user(&user_id).await {
                Ok(()) => successful.push(user_id),
                Err(e) => {
                    failed.insert(user_id, e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
    
    pub async fn update_user_status(
        &self,
        user_ids: Vec<String>,
        status: UserStatus,
    ) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        for user_id in user_ids {
            match self.user_manager.get_user(&user_id).await {
                Ok(mut user) => {
                    user.status = status;
                    match self.user_manager.update_user(user).await {
                        Ok(()) => successful.push(user_id),
                        Err(e) => {
                            failed.insert(user_id, e.to_string());
                        }
                    }
                }
                Err(e) => {
                    failed.insert(user_id, e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
    
    pub async fn generate_all_qr_codes(&self, output_dir: &Path) -> Result<BatchOperationResult> {
        let users = self.user_manager.list_users(None).await?;
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        std::fs::create_dir_all(output_dir)?;
        
        for user in users {
            let qr_path = output_dir.join(format!("{}.png", user.name));
            
            match self.user_manager.generate_qr_code(&user.id, &qr_path).await {
                Ok(()) => successful.push(user.name),
                Err(e) => {
                    failed.insert(user.name, e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
    
    pub async fn export_users_to_json(&self, output_path: &Path) -> Result<()> {
        let users = self.user_manager.list_users(None).await?;
        let json = serde_json::to_string_pretty(&users)?;
        std::fs::write(output_path, json)?;
        Ok(())
    }
    
    pub async fn import_users_from_json(
        &self,
        input_path: &Path,
        options: ImportOptions,
    ) -> Result<BatchOperationResult> {
        let content = std::fs::read_to_string(input_path)?;
        let imported_users: Vec<User> = serde_json::from_str(&content)?;
        
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        for mut user in imported_users {
            // Check if user already exists
            if self.user_manager.get_user(&user.id).await.is_ok() {
                if !options.overwrite_existing {
                    failed.insert(
                        user.name.clone(),
                        "User already exists and overwrite is disabled".to_string(),
                    );
                    continue;
                }
            }
            
            // Generate new keys if requested
            if options.generate_new_keys {
                match vpn_crypto::X25519KeyManager::generate_keypair() {
                    Ok(keypair) => {
                        user.config.private_key = Some(keypair.private_key_base64());
                        user.config.public_key = Some(keypair.public_key_base64());
                    }
                    Err(e) => {
                        failed.insert(user.name.clone(), e.to_string());
                        continue;
                    }
                }
            }
            
            // Validate configuration if requested
            if options.validate_configs {
                if user.config.private_key.is_none() || user.config.public_key.is_none() {
                    failed.insert(
                        user.name.clone(),
                        "Missing cryptographic keys".to_string(),
                    );
                    continue;
                }
            }
            
            match self.user_manager.update_user(user.clone()).await {
                Ok(()) => successful.push(user.name),
                Err(e) => {
                    failed.insert(user.name, e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
    
    pub async fn cleanup_inactive_users(&self, days_threshold: i64) -> Result<BatchOperationResult> {
        let users = self.user_manager.list_users(None).await?;
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        for user in users {
            let should_cleanup = match user.days_since_last_active() {
                Some(days) => days > days_threshold,
                None => user.days_since_creation() > days_threshold,
            };
            
            if should_cleanup && user.status != UserStatus::Active {
                match self.user_manager.delete_user(&user.id).await {
                    Ok(()) => successful.push(user.name),
                    Err(e) => {
                        failed.insert(user.name, e.to_string());
                    }
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
    
    pub async fn reset_user_traffic(&self, user_ids: Vec<String>) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        for user_id in user_ids {
            match self.user_manager.get_user(&user_id).await {
                Ok(mut user) => {
                    user.stats.bytes_sent = 0;
                    user.stats.bytes_received = 0;
                    user.stats.connection_count = 0;
                    user.stats.last_connection = None;
                    
                    match self.user_manager.update_user(user).await {
                        Ok(()) => successful.push(user_id),
                        Err(e) => {
                            failed.insert(user_id, e.to_string());
                        }
                    }
                }
                Err(e) => {
                    failed.insert(user_id, e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { successful, failed })
    }
}

impl Default for ImportOptions {
    fn default() -> Self {
        Self {
            overwrite_existing: false,
            validate_configs: true,
            generate_new_keys: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ServerConfig;
    use tempfile::tempdir;
    
    #[tokio::test]
    async fn test_batch_create_users() {
        let temp_dir = tempdir().unwrap();
        let server_config = ServerConfig::default();
        let user_manager = UserManager::new(temp_dir.path(), server_config).unwrap();
        let batch_ops = BatchOperations::new(&user_manager);
        
        let request = BatchCreateRequest {
            names: vec!["user1".to_string(), "user2".to_string()],
            protocol: VpnProtocol::Vless,
            emails: Some(vec!["user1@example.com".to_string(), "user2@example.com".to_string()]),
        };
        
        let result = batch_ops.create_multiple_users(request).await.unwrap();
        
        assert_eq!(result.successful.len(), 2);
        assert!(result.failed.is_empty());
    }
}