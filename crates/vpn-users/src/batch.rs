use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;
use crate::user::{User, VpnProtocol, UserStatus};
use crate::manager::UserManager;
use crate::error::{Result};
use tokio::task::JoinSet;
use tokio::sync::mpsc;
use serde::{Serialize, Deserialize};

pub struct BatchOperations {
    user_manager: Arc<UserManager>,
    progress_trackers: Arc<tokio::sync::RwLock<HashMap<String, ProgressTracker>>>,
}

#[derive(Debug, Clone)]
pub struct BatchCreateRequest {
    pub names: Vec<String>,
    pub protocol: VpnProtocol,
    pub emails: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchOperationResult {
    pub successful: Vec<String>,
    pub failed: HashMap<String, String>,
    pub total_processed: usize,
    pub duration_ms: u128,
    pub progress_info: Option<ProgressInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressInfo {
    pub operation_id: String,
    pub total_items: usize,
    pub completed_items: usize,
    pub failed_items: usize,
    pub current_item: Option<String>,
    pub estimated_remaining_ms: Option<u128>,
    pub can_resume: bool,
}

#[derive(Debug)]
pub struct ProgressTracker {
    operation_id: String,
    total_items: AtomicUsize,
    completed_items: AtomicUsize,
    failed_items: AtomicUsize,
    start_time: Instant,
    sender: Option<mpsc::UnboundedSender<ProgressInfo>>,
    can_resume: bool,
}

pub type ProgressReceiver = mpsc::UnboundedReceiver<ProgressInfo>;

#[derive(Debug, Clone)]
pub struct ImportOptions {
    pub overwrite_existing: bool,
    pub validate_configs: bool,
    pub generate_new_keys: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchOperationCheckpoint {
    pub operation_id: String,
    pub operation_type: String,
    pub completed_items: Vec<String>,
    pub failed_items: HashMap<String, String>,
    pub remaining_items: Vec<String>,
    pub created_at: u64,
    pub can_resume: bool,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug)]
pub struct ResumeableOperation {
    pub checkpoint: BatchOperationCheckpoint,
}

#[derive(Debug, Clone)]
pub struct BatchValidationResult {
    pub is_valid: bool,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub estimated_duration_ms: Option<u128>,
}

#[derive(Debug, Clone)]
pub struct RollbackInfo {
    pub operation_id: String,
    pub created_users: Vec<String>,
    pub modified_users: Vec<(String, User)>, // (id, original_user)
    pub deleted_users: Vec<User>,
    pub can_rollback: bool,
}

impl BatchOperations {
    pub fn new(user_manager: Arc<UserManager>) -> Self {
        Self { 
            user_manager,
            progress_trackers: Arc::new(tokio::sync::RwLock::new(HashMap::new())),
        }
    }
    
    pub async fn create_progress_tracker(&self, operation_id: String, total_items: usize, can_resume: bool) -> (ProgressTracker, ProgressReceiver) {
        let (sender, receiver) = mpsc::unbounded_channel();
        let tracker = ProgressTracker {
            operation_id: operation_id.clone(),
            total_items: AtomicUsize::new(total_items),
            completed_items: AtomicUsize::new(0),
            failed_items: AtomicUsize::new(0),
            start_time: Instant::now(),
            sender: Some(sender),
            can_resume,
        };
        
        let mut trackers = self.progress_trackers.write().await;
        trackers.insert(operation_id, tracker.clone());
        
        (tracker, receiver)
    }
    
    pub async fn get_progress(&self, operation_id: &str) -> Option<ProgressInfo> {
        let trackers = self.progress_trackers.read().await;
        trackers.get(operation_id).map(|tracker| tracker.get_progress())
    }
    
    pub async fn remove_progress_tracker(&self, operation_id: &str) {
        let mut trackers = self.progress_trackers.write().await;
        trackers.remove(operation_id);
    }
    
    pub async fn save_checkpoint(&self, checkpoint: &BatchOperationCheckpoint) -> Result<()> {
        let checkpoint_dir = self.user_manager.get_users_directory().join("checkpoints");
        std::fs::create_dir_all(&checkpoint_dir)?;
        
        let checkpoint_file = checkpoint_dir.join(format!("{}.json", checkpoint.operation_id));
        let checkpoint_json = serde_json::to_string_pretty(checkpoint)?;
        std::fs::write(checkpoint_file, checkpoint_json)?;
        
        Ok(())
    }
    
    pub async fn load_checkpoint(&self, operation_id: &str) -> Result<BatchOperationCheckpoint> {
        let checkpoint_dir = self.user_manager.get_users_directory().join("checkpoints");
        let checkpoint_file = checkpoint_dir.join(format!("{}.json", operation_id));
        
        if !checkpoint_file.exists() {
            return Err(crate::error::UserError::NotFound { 
                resource: "checkpoint".to_string(),
                id: operation_id.to_string(),
            }.into());
        }
        
        let checkpoint_json = std::fs::read_to_string(checkpoint_file)?;
        let checkpoint: BatchOperationCheckpoint = serde_json::from_str(&checkpoint_json)?;
        
        Ok(checkpoint)
    }
    
    pub async fn list_checkpoints(&self) -> Result<Vec<BatchOperationCheckpoint>> {
        let checkpoint_dir = self.user_manager.get_users_directory().join("checkpoints");
        
        if !checkpoint_dir.exists() {
            return Ok(Vec::new());
        }
        
        let mut checkpoints = Vec::new();
        
        for entry in std::fs::read_dir(checkpoint_dir)? {
            let entry = entry?;
            let path = entry.path();
            
            if path.extension().and_then(|s| s.to_str()) == Some("json") {
                if let Ok(checkpoint_json) = std::fs::read_to_string(&path) {
                    if let Ok(checkpoint) = serde_json::from_str::<BatchOperationCheckpoint>(&checkpoint_json) {
                        checkpoints.push(checkpoint);
                    }
                }
            }
        }
        
        // Sort by creation time, newest first
        checkpoints.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        
        Ok(checkpoints)
    }
    
    pub async fn remove_checkpoint(&self, operation_id: &str) -> Result<()> {
        let checkpoint_dir = self.user_manager.get_users_directory().join("checkpoints");
        let checkpoint_file = checkpoint_dir.join(format!("{}.json", operation_id));
        
        if checkpoint_file.exists() {
            std::fs::remove_file(checkpoint_file)?;
        }
        
        Ok(())
    }
    
    pub async fn create_multiple_users(
        &self,
        request: BatchCreateRequest,
    ) -> Result<BatchOperationResult> {
        self.create_multiple_users_with_progress(request, None).await
    }
    
    pub async fn create_multiple_users_with_progress(
        &self,
        request: BatchCreateRequest,
        _progress_sender: Option<mpsc::UnboundedSender<ProgressInfo>>,
    ) -> Result<BatchOperationResult> {
        let start_time = Instant::now();
        let operation_id = format!("batch_create_{}", start_time.elapsed().as_millis());
        let total_items = request.names.len();
        
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        let (tracker, _receiver) = self.create_progress_tracker(
            operation_id.clone(), 
            total_items, 
            true
        ).await;
        
        let mut tasks = JoinSet::new();
        
        for (index, name) in request.names.iter().enumerate() {
            let name = name.clone();
            let protocol = request.protocol;
            let email = request.emails.as_ref()
                .and_then(|emails| emails.get(index))
                .cloned();
            
            let user_manager = Arc::clone(&self.user_manager);
            let tracker_clone = tracker.clone();
            
            tasks.spawn(async move {
                tracker_clone.set_current_item(Some(name.clone()));
                
                match user_manager.create_user(name.clone(), protocol).await {
                    Ok(mut user) => {
                        if let Some(email) = email {
                            user.email = Some(email);
                            if let Err(e) = user_manager.update_user(user).await {
                                tracker_clone.increment_failed();
                                return (name, Err(e));
                            }
                        }
                        tracker_clone.increment_completed();
                        (name, Ok(()))
                    }
                    Err(e) => {
                        tracker_clone.increment_failed();
                        (name, Err(e))
                    }
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
        
        let duration = start_time.elapsed();
        let progress_info = Some(tracker.get_progress());
        
        // Clean up tracker
        self.remove_progress_tracker(&operation_id).await;
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_items,
            duration_ms: duration.as_millis(),
            progress_info,
        })
    }
    
    pub async fn create_multiple_users_resumable(
        &self,
        request: BatchCreateRequest,
        save_checkpoints: bool,
    ) -> Result<BatchOperationResult> {
        let start_time = Instant::now();
        let operation_id = format!("batch_create_{}", start_time.elapsed().as_millis());
        let total_items = request.names.len();
        
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        let mut remaining_items: Vec<String> = request.names.clone();
        
        let (tracker, _receiver) = self.create_progress_tracker(
            operation_id.clone(), 
            total_items, 
            true
        ).await;
        
        // Process items one by one for resumability
        for (index, name) in request.names.iter().enumerate() {
            tracker.set_current_item(Some(name.clone()));
            
            let protocol = request.protocol;
            let email = request.emails.as_ref()
                .and_then(|emails| emails.get(index))
                .cloned();
            
            match self.user_manager.create_user(name.clone(), protocol).await {
                Ok(mut user) => {
                    if let Some(email) = email {
                        user.email = Some(email);
                        if let Err(e) = self.user_manager.update_user(user).await {
                            failed.insert(name.clone(), e.to_string());
                            tracker.increment_failed();
                        } else {
                            successful.push(name.clone());
                            tracker.increment_completed();
                        }
                    } else {
                        successful.push(name.clone());
                        tracker.increment_completed();
                    }
                }
                Err(e) => {
                    failed.insert(name.clone(), e.to_string());
                    tracker.increment_failed();
                }
            }
            
            // Remove processed item from remaining list
            remaining_items.retain(|item| item != name);
            
            // Save checkpoint periodically if enabled
            if save_checkpoints && (index + 1) % 10 == 0 {
                let checkpoint = BatchOperationCheckpoint {
                    operation_id: operation_id.clone(),
                    operation_type: "create_multiple_users".to_string(),
                    completed_items: successful.clone(),
                    failed_items: failed.clone(),
                    remaining_items: remaining_items.clone(),
                    created_at: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs(),
                    can_resume: true,
                    metadata: {
                        let mut metadata = HashMap::new();
                        metadata.insert("protocol".to_string(), format!("{:?}", protocol));
                        if let Some(ref _emails) = request.emails {
                            metadata.insert("has_emails".to_string(), "true".to_string());
                        }
                        metadata
                    },
                };
                
                if let Err(e) = self.save_checkpoint(&checkpoint).await {
                    eprintln!("Warning: Failed to save checkpoint: {}", e);
                }
            }
        }
        
        let duration = start_time.elapsed();
        let progress_info = Some(tracker.get_progress());
        
        // Clean up tracker and checkpoint
        self.remove_progress_tracker(&operation_id).await;
        if save_checkpoints {
            let _ = self.remove_checkpoint(&operation_id).await;
        }
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_items,
            duration_ms: duration.as_millis(),
            progress_info,
        })
    }
    
    pub async fn resume_operation(&self, operation_id: &str) -> Result<BatchOperationResult> {
        let checkpoint = self.load_checkpoint(operation_id).await?;
        
        if !checkpoint.can_resume {
            return Err(crate::error::UserError::OperationError {
                operation: "resume".to_string(),
                details: "Operation cannot be resumed".to_string(),
            }.into());
        }
        
        match checkpoint.operation_type.as_str() {
            "create_multiple_users" => {
                // Reconstruct request from checkpoint metadata
                let protocol = checkpoint.metadata.get("protocol")
                    .and_then(|p| match p.as_str() {
                        "Vless" => Some(VpnProtocol::Vless),
                        "Shadowsocks" => Some(VpnProtocol::Shadowsocks),
                        _ => None,
                    })
                    .unwrap_or(VpnProtocol::Vless);
                
                let has_emails = checkpoint.metadata.get("has_emails")
                    .map(|v| v == "true")
                    .unwrap_or(false);
                
                let request = BatchCreateRequest {
                    names: checkpoint.remaining_items.clone(),
                    protocol,
                    emails: if has_emails { Some(vec![]) } else { None },
                };
                
                // Continue from where we left off
                let mut result = self.create_multiple_users_resumable(request, true).await?;
                
                // Merge with previous results
                let prev_completed_count = checkpoint.completed_items.len();
                let prev_failed_count = checkpoint.failed_items.len();
                
                result.successful.extend(checkpoint.completed_items);
                for (name, error) in checkpoint.failed_items {
                    result.failed.insert(name, error);
                }
                result.total_processed += prev_completed_count + prev_failed_count;
                
                Ok(result)
            }
            _ => Err(crate::error::UserError::OperationError {
                operation: "resume".to_string(),
                details: format!("Unknown operation type: {}", checkpoint.operation_type),
            }.into())
        }
    }
    
    pub async fn validate_batch_create(&self, request: &BatchCreateRequest) -> BatchValidationResult {
        let mut errors = Vec::new();
        let mut warnings = Vec::new();
        
        // Check for duplicate names in request
        let mut seen_names = std::collections::HashSet::new();
        for name in &request.names {
            if !seen_names.insert(name) {
                errors.push(format!("Duplicate user name in request: {}", name));
            }
        }
        
        // Check for existing users
        let existing_users = self.user_manager.list_users(None).await.unwrap_or_default();
        let existing_names: std::collections::HashSet<String> = existing_users.iter()
            .map(|u| u.name.clone())
            .collect();
        
        for name in &request.names {
            if existing_names.contains(name) {
                warnings.push(format!("User already exists: {}", name));
            }
        }
        
        // Validate user names
        for name in &request.names {
            if name.is_empty() {
                errors.push("User name cannot be empty".to_string());
            } else if name.len() > 64 {
                errors.push(format!("User name too long (>64 chars): {}", name));
            } else if !name.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-') {
                errors.push(format!("Invalid characters in user name: {}", name));
            }
        }
        
        // Validate emails if provided
        if let Some(emails) = &request.emails {
            if emails.len() != request.names.len() {
                errors.push("Email count does not match user count".to_string());
            } else {
                for (i, email) in emails.iter().enumerate() {
                    if !email.contains('@') || !email.contains('.') {
                        errors.push(format!("Invalid email format for user {}: {}", request.names.get(i).unwrap_or(&"unknown".to_string()), email));
                    }
                }
            }
        }
        
        // Estimate duration (rough estimate: 100ms per user)
        let estimated_duration_ms = Some(request.names.len() as u128 * 100);
        
        BatchValidationResult {
            is_valid: errors.is_empty(),
            errors,
            warnings,
            estimated_duration_ms,
        }
    }
    
    pub async fn create_multiple_users_with_rollback(
        &self,
        request: BatchCreateRequest,
        enable_rollback: bool,
    ) -> Result<(BatchOperationResult, Option<RollbackInfo>)> {
        let validation = self.validate_batch_create(&request).await;
        if !validation.is_valid {
            return Err(crate::error::UserError::ValidationError {
                field: "batch_request".to_string(),
                message: validation.errors.join("; "),
            }.into());
        }
        
        let start_time = Instant::now();
        let operation_id = format!("batch_create_rollback_{}", start_time.elapsed().as_millis());
        
        let mut rollback_info = if enable_rollback {
            Some(RollbackInfo {
                operation_id: operation_id.clone(),
                created_users: Vec::new(),
                modified_users: Vec::new(),
                deleted_users: Vec::new(),
                can_rollback: true,
            })
        } else {
            None
        };
        
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        for (index, name) in request.names.iter().enumerate() {
            let protocol = request.protocol;
            let email = request.emails.as_ref()
                .and_then(|emails| emails.get(index))
                .cloned();
            
            match self.user_manager.create_user(name.clone(), protocol).await {
                Ok(mut user) => {
                    let user_id = user.id.clone();
                    
                    // Track created user for potential rollback
                    if let Some(ref mut rb) = rollback_info {
                        rb.created_users.push(user_id.clone());
                    }
                    
                    if let Some(email) = email {
                        user.email = Some(email);
                        if let Err(e) = self.user_manager.update_user(user).await {
                            failed.insert(name.clone(), e.to_string());
                            
                            // Rollback on failure if enabled
                            if enable_rollback {
                                if let Err(rollback_err) = self.user_manager.delete_user(&user_id).await {
                                    eprintln!("Warning: Failed to rollback user creation for {}: {}", name, rollback_err);
                                }
                                if let Some(ref mut rb) = rollback_info {
                                    rb.created_users.retain(|id| id != &user_id);
                                }
                            }
                        } else {
                            successful.push(name.clone());
                        }
                    } else {
                        successful.push(name.clone());
                    }
                }
                Err(e) => {
                    failed.insert(name.clone(), e.to_string());
                }
            }
        }
        
        let duration = start_time.elapsed();
        let result = BatchOperationResult {
            successful,
            failed,
            total_processed: request.names.len(),
            duration_ms: duration.as_millis(),
            progress_info: None,
        };
        
        Ok((result, rollback_info))
    }
    
    pub async fn rollback_operation(&self, rollback_info: &RollbackInfo) -> Result<BatchOperationResult> {
        if !rollback_info.can_rollback {
            return Err(crate::error::UserError::OperationError {
                operation: "rollback".to_string(),
                details: "Operation cannot be rolled back".to_string(),
            }.into());
        }
        
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        
        // Rollback created users (delete them)
        for user_id in &rollback_info.created_users {
            match self.user_manager.delete_user(user_id).await {
                Ok(()) => successful.push(format!("deleted_{}", user_id)),
                Err(e) => {
                    failed.insert(format!("delete_{}", user_id), e.to_string());
                }
            }
        }
        
        // Rollback modified users (restore original state)
        for (user_id, original_user) in &rollback_info.modified_users {
            match self.user_manager.update_user(original_user.clone()).await {
                Ok(()) => successful.push(format!("restored_{}", user_id)),
                Err(e) => {
                    failed.insert(format!("restore_{}", user_id), e.to_string());
                }
            }
        }
        
        // Rollback deleted users (recreate them)
        for user in &rollback_info.deleted_users {
            match self.user_manager.update_user(user.clone()).await {
                Ok(()) => successful.push(format!("recreated_{}", user.id)),
                Err(e) => {
                    failed.insert(format!("recreate_{}", user.id), e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult {
            successful,
            failed,
            total_processed: rollback_info.created_users.len() + rollback_info.modified_users.len() + rollback_info.deleted_users.len(),
            duration_ms: 0, // Will be set by caller
            progress_info: None,
        })
    }
    
    pub async fn delete_multiple_users(&self, user_ids: Vec<String>) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        let total_count = user_ids.len();
        
        for user_id in user_ids {
            match self.user_manager.delete_user(&user_id).await {
                Ok(()) => successful.push(user_id),
                Err(e) => {
                    failed.insert(user_id, e.to_string());
                }
            }
        }
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_count,
            duration_ms: 0,
            progress_info: None,
        })
    }
    
    pub async fn update_user_status(
        &self,
        user_ids: Vec<String>,
        status: UserStatus,
    ) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        let total_count = user_ids.len();
        
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
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_count,
            duration_ms: 0,
            progress_info: None,
        })
    }
    
    pub async fn generate_all_qr_codes(&self, output_dir: &Path) -> Result<BatchOperationResult> {
        let users = self.user_manager.list_users(None).await?;
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        let total_count = users.len();
        
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
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_count,
            duration_ms: 0,
            progress_info: None,
        })
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
        let total_count = imported_users.len();
        
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
                let key_manager = vpn_crypto::X25519KeyManager::new();
                match key_manager.generate_keypair() {
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
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_count,
            duration_ms: 0,
            progress_info: None,
        })
    }
    
    pub async fn cleanup_inactive_users(&self, days_threshold: i64) -> Result<BatchOperationResult> {
        let users = self.user_manager.list_users(None).await?;
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        let mut total_processed = 0;
        
        for user in users {
            let should_cleanup = match user.days_since_last_active() {
                Some(days) => days > days_threshold,
                None => user.days_since_creation() > days_threshold,
            };
            
            if should_cleanup && user.status != UserStatus::Active {
                total_processed += 1;
                match self.user_manager.delete_user(&user.id).await {
                    Ok(()) => successful.push(user.name),
                    Err(e) => {
                        failed.insert(user.name, e.to_string());
                    }
                }
            }
        }
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed,
            duration_ms: 0,
            progress_info: None,
        })
    }
    
    pub async fn reset_user_traffic(&self, user_ids: Vec<String>) -> Result<BatchOperationResult> {
        let mut successful = Vec::new();
        let mut failed = HashMap::new();
        let total_count = user_ids.len();
        
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
        
        Ok(BatchOperationResult { 
            successful, 
            failed,
            total_processed: total_count,
            duration_ms: 0,
            progress_info: None,
        })
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

impl ProgressTracker {
    pub fn get_progress(&self) -> ProgressInfo {
        let completed = self.completed_items.load(Ordering::Relaxed);
        let failed = self.failed_items.load(Ordering::Relaxed);
        let total = self.total_items.load(Ordering::Relaxed);
        let elapsed = self.start_time.elapsed();
        
        let estimated_remaining_ms = if completed > 0 {
            let avg_time_per_item = elapsed.as_millis() as f64 / completed as f64;
            let remaining_items = total.saturating_sub(completed + failed);
            Some((avg_time_per_item * remaining_items as f64) as u128)
        } else {
            None
        };
        
        ProgressInfo {
            operation_id: self.operation_id.clone(),
            total_items: total,
            completed_items: completed,
            failed_items: failed,
            current_item: None,
            estimated_remaining_ms,
            can_resume: self.can_resume,
        }
    }
    
    pub fn increment_completed(&self) {
        self.completed_items.fetch_add(1, Ordering::Relaxed);
        self.send_progress_update(None);
    }
    
    pub fn increment_failed(&self) {
        self.failed_items.fetch_add(1, Ordering::Relaxed);
        self.send_progress_update(None);
    }
    
    pub fn set_current_item(&self, item: Option<String>) {
        self.send_progress_update(item);
    }
    
    fn send_progress_update(&self, current_item: Option<String>) {
        if let Some(sender) = &self.sender {
            let mut progress = self.get_progress();
            progress.current_item = current_item;
            let _ = sender.send(progress);
        }
    }
}

impl Clone for ProgressTracker {
    fn clone(&self) -> Self {
        Self {
            operation_id: self.operation_id.clone(),
            total_items: AtomicUsize::new(self.total_items.load(Ordering::Relaxed)),
            completed_items: AtomicUsize::new(self.completed_items.load(Ordering::Relaxed)),
            failed_items: AtomicUsize::new(self.failed_items.load(Ordering::Relaxed)),
            start_time: self.start_time,
            sender: None, // Clone without sender to avoid conflicts
            can_resume: self.can_resume,
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
        let batch_ops = BatchOperations::new(Arc::new(user_manager));
        
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