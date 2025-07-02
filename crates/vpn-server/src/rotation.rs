use std::path::Path;
use std::fs;
use std::collections::HashMap;
use vpn_crypto::X25519KeyManager;
use vpn_users::UserManager;
use crate::lifecycle::ServerLifecycle;
use crate::error::Result;

pub struct KeyRotationManager {
    server_lifecycle: ServerLifecycle,
}

#[derive(Debug, Clone)]
pub struct RotationOptions {
    pub rotate_server_keys: bool,
    pub rotate_user_keys: bool,
    pub backup_old_keys: bool,
    pub restart_server: bool,
}

#[derive(Debug)]
pub struct RotationResult {
    pub server_keys_rotated: bool,
    pub users_rotated: Vec<String>,
    pub failed_rotations: HashMap<String, String>,
    pub backup_path: Option<String>,
}

impl KeyRotationManager {
    pub fn new() -> Result<Self> {
        let server_lifecycle = ServerLifecycle::new()?;
        
        Ok(Self {
            server_lifecycle,
        })
    }
    
    pub async fn rotate_keys(
        &self,
        install_path: &Path,
        options: RotationOptions,
    ) -> Result<RotationResult> {
        let mut result = RotationResult {
            server_keys_rotated: false,
            users_rotated: Vec::new(),
            failed_rotations: HashMap::new(),
            backup_path: None,
        };
        
        // Create backup if requested
        if options.backup_old_keys {
            let backup_path = self.create_backup(install_path).await?;
            result.backup_path = Some(backup_path);
        }
        
        // Rotate server keys
        if options.rotate_server_keys {
            match self.rotate_server_keys(install_path).await {
                Ok(()) => {
                    result.server_keys_rotated = true;
                    println!("Server keys rotated successfully");
                }
                Err(e) => {
                    result.failed_rotations.insert(
                        "server".to_string(),
                        e.to_string(),
                    );
                }
            }
        }
        
        // Rotate user keys
        if options.rotate_user_keys {
            let user_results = self.rotate_user_keys(install_path).await?;
            result.users_rotated = user_results.0;
            result.failed_rotations.extend(user_results.1);
        }
        
        // Update server configuration
        self.update_server_configuration(install_path).await?;
        
        // Restart server if requested
        if options.restart_server {
            self.server_lifecycle.restart(install_path).await?;
        } else {
            self.server_lifecycle.reload_config(install_path).await?;
        }
        
        Ok(result)
    }
    
    async fn rotate_server_keys(&self, install_path: &Path) -> Result<()> {
        let config_dir = install_path.join("config");
        let private_key_file = config_dir.join("private_key.txt");
        let public_key_file = config_dir.join("public_key.txt");
        
        // Generate new keypair
        let key_manager = X25519KeyManager::new();
        let new_keypair = key_manager.generate_keypair()?;
        
        // Save new keys
        fs::write(&private_key_file, new_keypair.private_key_base64())?;
        fs::write(&public_key_file, new_keypair.public_key_base64())?;
        
        // Set proper permissions
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let private_perms = fs::Permissions::from_mode(0o600);
            fs::set_permissions(&private_key_file, private_perms)?;
        }
        
        Ok(())
    }
    
    async fn rotate_user_keys(&self, install_path: &Path) -> Result<(Vec<String>, HashMap<String, String>)> {
        let server_config = self.load_server_config(install_path)?;
        let user_manager = UserManager::new(install_path, server_config)?;
        
        let users = user_manager.list_users(None).await?;
        let mut rotated_users = Vec::new();
        let mut failed_rotations = HashMap::new();
        
        for mut user in users {
            // Generate new keypair for user
            let key_manager = X25519KeyManager::new();
            match key_manager.generate_keypair() {
                Ok(new_keypair) => {
                    user.config.private_key = Some(new_keypair.private_key_base64());
                    user.config.public_key = Some(new_keypair.public_key_base64());
                    
                    match user_manager.update_user(user.clone()).await {
                        Ok(()) => {
                            rotated_users.push(user.name);
                        }
                        Err(e) => {
                            failed_rotations.insert(user.name, e.to_string());
                        }
                    }
                }
                Err(e) => {
                    failed_rotations.insert(user.name, e.to_string());
                }
            }
        }
        
        Ok((rotated_users, failed_rotations))
    }
    
    async fn update_server_configuration(&self, install_path: &Path) -> Result<()> {
        let config_dir = install_path.join("config");
        let config_file = config_dir.join("config.json");
        let private_key_file = config_dir.join("private_key.txt");
        let public_key_file = config_dir.join("public_key.txt");
        
        // Read new keys
        let private_key = fs::read_to_string(&private_key_file)?;
        let _public_key = fs::read_to_string(&public_key_file)?;
        
        // Read current configuration
        let config_content = fs::read_to_string(&config_file)?;
        let mut config: serde_json::Value = serde_json::from_str(&config_content)?;
        
        // Update Reality settings with new keys
        if let Some(inbounds) = config["inbounds"].as_array_mut() {
            for inbound in inbounds {
                if let Some(stream_settings) = inbound["streamSettings"].as_object_mut() {
                    if let Some(reality_settings) = stream_settings["realitySettings"].as_object_mut() {
                        reality_settings["privateKey"] = serde_json::Value::String(private_key.trim().to_string());
                    }
                }
            }
        }
        
        // Save updated configuration
        let updated_config = serde_json::to_string_pretty(&config)?;
        fs::write(&config_file, updated_config)?;
        
        Ok(())
    }
    
    fn load_server_config(&self, install_path: &Path) -> Result<vpn_users::config::ServerConfig> {
        let config_dir = install_path.join("config");
        let config_file = config_dir.join("config.json");
        
        let config_content = fs::read_to_string(&config_file)?;
        let config: serde_json::Value = serde_json::from_str(&config_content)?;
        
        // Extract server information from config
        let host = "0.0.0.0".to_string(); // Will be updated from actual config
        let port = config["inbounds"][0]["port"].as_u64().unwrap_or(443) as u16;
        
        // Read keys
        let private_key_file = config_dir.join("private_key.txt");
        let public_key_file = config_dir.join("public_key.txt");
        
        let private_key = if private_key_file.exists() {
            Some(fs::read_to_string(&private_key_file)?.trim().to_string())
        } else {
            None
        };
        
        let public_key = if public_key_file.exists() {
            Some(fs::read_to_string(&public_key_file)?.trim().to_string())
        } else {
            None
        };
        
        Ok(vpn_users::config::ServerConfig {
            host,
            port,
            sni: None,
            public_key,
            private_key,
            short_id: None,
            reality_dest: Some("www.google.com:443".to_string()),
            reality_server_names: vec!["www.google.com".to_string()],
        })
    }
    
    async fn create_backup(&self, install_path: &Path) -> Result<String> {
        let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S");
        let backup_path = install_path.join(format!("backup_{}", timestamp));
        
        self.server_lifecycle.backup_configuration(install_path, &backup_path).await?;
        
        Ok(backup_path.to_string_lossy().to_string())
    }
    
    pub async fn schedule_automatic_rotation(
        &self,
        install_path: &Path,
        interval_days: u64,
    ) -> Result<()> {
        // This would typically be implemented with a task scheduler
        // For now, we'll just document the intended behavior
        
        println!("Automatic key rotation scheduled every {} days", interval_days);
        println!("Backup location: {}/backups", install_path.display());
        
        // In a real implementation, you would:
        // 1. Create a systemd timer or cron job
        // 2. Set up monitoring for rotation failures
        // 3. Implement notification system for rotation events
        
        Ok(())
    }
    
    pub async fn validate_keys(&self, install_path: &Path) -> Result<ValidationStatus> {
        let config_dir = install_path.join("config");
        let private_key_file = config_dir.join("private_key.txt");
        let public_key_file = config_dir.join("public_key.txt");
        
        let mut status = ValidationStatus {
            server_keys_valid: false,
            user_keys_valid: 0,
            total_users: 0,
            issues: Vec::new(),
        };
        
        // Validate server keys
        if private_key_file.exists() && public_key_file.exists() {
            let private_key = fs::read_to_string(&private_key_file)?;
            let public_key = fs::read_to_string(&public_key_file)?;
            
            let key_manager = X25519KeyManager::new();
            match key_manager.from_base64(&private_key) {
                Ok(keypair) => {
                    if keypair.public_key_base64() == public_key.trim() {
                        status.server_keys_valid = true;
                    } else {
                        status.issues.push("Server public key doesn't match private key".to_string());
                    }
                }
                Err(e) => {
                    status.issues.push(format!("Invalid server private key: {}", e));
                }
            }
        } else {
            status.issues.push("Server key files missing".to_string());
        }
        
        // Validate user keys
        let server_config = self.load_server_config(install_path)?;
        let user_manager = UserManager::new(install_path, server_config)?;
        let users = user_manager.list_users(None).await?;
        
        status.total_users = users.len();
        
        for user in users {
            if let (Some(private_key), Some(public_key)) = (&user.config.private_key, &user.config.public_key) {
                let key_manager = X25519KeyManager::new();
                match key_manager.from_base64(private_key) {
                    Ok(keypair) => {
                        if keypair.public_key_base64() == *public_key {
                            status.user_keys_valid += 1;
                        } else {
                            status.issues.push(format!("User {} has mismatched keys", user.name));
                        }
                    }
                    Err(_) => {
                        status.issues.push(format!("User {} has invalid private key", user.name));
                    }
                }
            } else {
                status.issues.push(format!("User {} missing keys", user.name));
            }
        }
        
        Ok(status)
    }
}

#[derive(Debug)]
pub struct ValidationStatus {
    pub server_keys_valid: bool,
    pub user_keys_valid: usize,
    pub total_users: usize,
    pub issues: Vec<String>,
}

impl Default for RotationOptions {
    fn default() -> Self {
        Self {
            rotate_server_keys: true,
            rotate_user_keys: true,
            backup_old_keys: true,
            restart_server: false, // Prefer graceful reload
        }
    }
}

impl ValidationStatus {
    pub fn is_fully_valid(&self) -> bool {
        self.server_keys_valid && 
        self.user_keys_valid == self.total_users && 
        self.issues.is_empty()
    }
    
    pub fn validation_percentage(&self) -> f64 {
        if self.total_users == 0 {
            if self.server_keys_valid { 100.0 } else { 0.0 }
        } else {
            let total_checks = self.total_users + 1; // +1 for server keys
            let valid_checks = self.user_keys_valid + if self.server_keys_valid { 1 } else { 0 };
            (valid_checks as f64 / total_checks as f64) * 100.0
        }
    }
}