use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::fs;
use dashmap::DashMap;
use crate::user::{User, UserStatus, VpnProtocol};
use crate::config::{ConfigGenerator, ServerConfig};
use crate::links::ConnectionLinkGenerator;
use crate::error::{UserError, Result};
use vpn_crypto::QrCodeGenerator;

pub struct UserManager {
    users: DashMap<String, User>,
    storage_path: PathBuf,
    max_users: Option<usize>,
    server_config: ServerConfig,
    read_only_mode: bool,
}

#[derive(Debug, Clone)]
pub struct UserListOptions {
    pub status_filter: Option<UserStatus>,
    pub protocol_filter: Option<VpnProtocol>,
    pub sort_by: SortBy,
    pub limit: Option<usize>,
}

#[derive(Debug, Clone, Copy)]
pub enum SortBy {
    Name,
    CreatedAt,
    LastActive,
    TotalTraffic,
}

impl UserManager {
    pub fn new<P: AsRef<Path>>(storage_path: P, server_config: ServerConfig) -> Result<Self> {
        let storage_path = storage_path.as_ref().to_path_buf();
        let mut read_only_mode = false;
        
        if !storage_path.exists() {
            if let Err(e) = fs::create_dir_all(&storage_path) {
                if e.kind() == std::io::ErrorKind::PermissionDenied {
                    eprintln!("Warning: Cannot create storage directory ({}): Permission denied", storage_path.display());
                    eprintln!("Running in read-only mode. User management operations will be limited.");
                    read_only_mode = true;
                } else {
                    return Err(UserError::IoError(e));
                }
            }
        }
        
        let manager = Self {
            users: DashMap::new(),
            storage_path,
            max_users: None,
            server_config,
            read_only_mode,
        };
        
        manager.load_users_from_disk()?;
        Ok(manager)
    }
    
    pub fn with_max_users(mut self, max_users: usize) -> Self {
        self.max_users = Some(max_users);
        self
    }
    
    pub fn is_read_only(&self) -> bool {
        self.read_only_mode
    }
    
    pub fn get_users_directory(&self) -> &Path {
        &self.storage_path
    }
    
    pub async fn create_user(&self, name: String, protocol: VpnProtocol) -> Result<User> {
        if self.read_only_mode {
            return Err(UserError::ReadOnlyMode);
        }
        
        if let Some(max) = self.max_users {
            if self.users.len() >= max {
                return Err(UserError::UserLimitExceeded(max));
            }
        }
        
        // Check if user with this name already exists
        if self.users.iter().any(|entry| entry.value().name == name) {
            return Err(UserError::UserAlreadyExists(name));
        }
        
        let mut user = User::new(name, protocol);
        
        // Generate crypto keys for the user
        let keypair = vpn_crypto::X25519KeyManager::generate_keypair()
            .map_err(|e| UserError::CryptoError(e))?;
        
        user.config.private_key = Some(keypair.private_key_base64());
        user.config.public_key = Some(keypair.public_key_base64());
        user.config.server_host = self.server_config.host.clone();
        user.config.server_port = self.server_config.port;
        user.config.sni = self.server_config.sni.clone();
        
        self.users.insert(user.id.clone(), user.clone());
        
        self.save_user_to_disk(&user).await?;
        self.regenerate_server_config().await?;
        
        Ok(user)
    }
    
    pub async fn get_user(&self, id: &str) -> Result<User> {
        self.users.get(id)
            .map(|entry| entry.value().clone())
            .ok_or_else(|| UserError::UserNotFound(id.to_string()))
    }
    
    pub async fn get_user_by_name(&self, name: &str) -> Result<User> {
        self.users.iter()
            .find(|entry| entry.value().name == name)
            .map(|entry| entry.value().clone())
            .ok_or_else(|| UserError::UserNotFound(name.to_string()))
    }
    
    pub async fn update_user(&self, mut user: User) -> Result<()> {
        if self.read_only_mode {
            return Err(UserError::ReadOnlyMode);
        }
        
        if !self.users.contains_key(&user.id) {
            return Err(UserError::UserNotFound(user.id));
        }
        
        user.update_last_active();
        self.users.insert(user.id.clone(), user.clone());
        
        self.save_user_to_disk(&user).await?;
        self.regenerate_server_config().await?;
        
        Ok(())
    }
    
    pub async fn delete_user(&self, id: &str) -> Result<()> {
        if self.read_only_mode {
            return Err(UserError::ReadOnlyMode);
        }
        
        let user = self.users.remove(id)
            .map(|(_, user)| user)
            .ok_or_else(|| UserError::UserNotFound(id.to_string()))?;
        
        self.delete_user_from_disk(&user).await?;
        self.regenerate_server_config().await?;
        
        Ok(())
    }
    
    pub async fn list_users(&self, options: Option<UserListOptions>) -> Result<Vec<User>> {
        let mut user_list: Vec<User> = self.users.iter()
            .map(|entry| entry.value().clone())
            .collect();
        
        let options = options.unwrap_or_default();
        
        // Apply filters
        if let Some(status) = options.status_filter {
            user_list.retain(|u| u.status == status);
        }
        
        if let Some(protocol) = options.protocol_filter {
            user_list.retain(|u| u.protocol == protocol);
        }
        
        // Sort
        match options.sort_by {
            SortBy::Name => user_list.sort_by(|a, b| a.name.cmp(&b.name)),
            SortBy::CreatedAt => user_list.sort_by(|a, b| a.created_at.cmp(&b.created_at)),
            SortBy::LastActive => user_list.sort_by(|a, b| {
                match (a.last_active, b.last_active) {
                    (Some(a_time), Some(b_time)) => b_time.cmp(&a_time),
                    (Some(_), None) => std::cmp::Ordering::Less,
                    (None, Some(_)) => std::cmp::Ordering::Greater,
                    (None, None) => std::cmp::Ordering::Equal,
                }
            }),
            SortBy::TotalTraffic => user_list.sort_by(|a, b| {
                b.total_traffic().cmp(&a.total_traffic())
            }),
        }
        
        // Apply limit
        if let Some(limit) = options.limit {
            user_list.truncate(limit);
        }
        
        Ok(user_list)
    }
    
    pub async fn get_user_count(&self) -> usize {
        self.users.len()
    }
    
    pub async fn get_active_user_count(&self) -> usize {
        self.users.iter().filter(|entry| entry.value().is_active()).count()
    }
    
    pub async fn generate_connection_link(&self, user_id: &str) -> Result<String> {
        let user = self.get_user(user_id).await?;
        ConnectionLinkGenerator::generate(&user, &self.server_config)
    }
    
    pub async fn generate_qr_code(&self, user_id: &str, output_path: &Path) -> Result<()> {
        let link = self.generate_connection_link(user_id).await?;
        QrCodeGenerator::save_as_png(&link, output_path)
            .map_err(|e| UserError::CryptoError(e))?;
        Ok(())
    }
    
    async fn save_user_to_disk(&self, user: &User) -> Result<()> {
        let user_dir = self.storage_path.join("users").join(&user.id);
        fs::create_dir_all(&user_dir)?;
        
        let user_file = user_dir.join("config.json");
        let json = serde_json::to_string_pretty(user)?;
        fs::write(user_file, json)?;
        
        // Save connection link
        if let Ok(link) = self.generate_connection_link(&user.id).await {
            let link_file = user_dir.join("connection.link");
            fs::write(link_file, link)?;
        }
        
        Ok(())
    }
    
    async fn delete_user_from_disk(&self, user: &User) -> Result<()> {
        let user_dir = self.storage_path.join("users").join(&user.id);
        if user_dir.exists() {
            fs::remove_dir_all(user_dir)?;
        }
        Ok(())
    }
    
    fn load_users_from_disk(&self) -> Result<()> {
        let users_dir = self.storage_path.join("users");
        if !users_dir.exists() {
            return Ok(());
        }
        
        let mut users = HashMap::new();
        
        // Try to read directory, but handle permission errors gracefully
        let entries = match fs::read_dir(&users_dir) {
            Ok(entries) => entries,
            Err(e) => {
                if e.kind() == std::io::ErrorKind::PermissionDenied {
                    // If we don't have permission, just return empty user list
                    eprintln!("Warning: Cannot access users directory ({}): Permission denied", users_dir.display());
                    return Ok(());
                } else {
                    return Err(UserError::IoError(e));
                }
            }
        };
        
        for entry in entries {
            let entry = entry?;
            let user_dir = entry.path();
            
            if user_dir.is_dir() {
                let config_file = user_dir.join("config.json");
                if config_file.exists() {
                    match fs::read_to_string(&config_file) {
                        Ok(content) => {
                            match serde_json::from_str::<User>(&content) {
                                Ok(user) => {
                                    users.insert(user.id.clone(), user);
                                }
                                Err(e) => {
                                    eprintln!("Failed to parse user config {}: {}", 
                                        config_file.display(), e);
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("Failed to read user config {}: {}", 
                                config_file.display(), e);
                        }
                    }
                }
            }
        }
        
        // Insert users into DashMap
        for (id, user) in users {
            self.users.insert(id, user);
        }
        
        Ok(())
    }
    
    async fn regenerate_server_config(&self) -> Result<()> {
        let user_list: Vec<User> = self.users.iter()
            .map(|entry| entry.value().clone())
            .collect();
        
        let xray_config = ConfigGenerator::generate_xray_config(&user_list, &self.server_config)?;
        ConfigGenerator::validate_config(&xray_config)?;
        
        let config_path = self.storage_path.join("config").join("config.json");
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent)?;
        }
        
        ConfigGenerator::save_config_to_file(&xray_config, &config_path)?;
        
        Ok(())
    }
}

impl Default for UserListOptions {
    fn default() -> Self {
        Self {
            status_filter: None,
            protocol_filter: None,
            sort_by: SortBy::CreatedAt,
            limit: None,
        }
    }
}