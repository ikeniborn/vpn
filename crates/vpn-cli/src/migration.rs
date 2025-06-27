use std::path::{Path, PathBuf};
// use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use indicatif::{ProgressBar, ProgressStyle};
use vpn_users::{User, UserStatus};
use vpn_users::user::VpnProtocol;
use crate::error::{CliError, Result};
use crate::utils::display;

#[derive(Debug, Clone)]
pub struct MigrationOptions {
    pub source_path: PathBuf,
    pub target_path: PathBuf,
    pub keep_original: bool,
    pub migrate_users: bool,
    pub migrate_config: bool,
    pub migrate_logs: bool,
    pub validate_after_migration: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrationReport {
    pub success: bool,
    pub users_migrated: u32,
    pub configs_migrated: u32,
    pub files_migrated: u32,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub migration_time_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BashVpnConfig {
    pub server_host: String,
    pub server_port: u16,
    pub protocol: String,
    pub private_key: Option<String>,
    pub public_key: Option<String>,
    pub short_id: Option<String>,
    pub sni: Option<String>,
    pub reality_dest: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BashUser {
    pub name: String,
    pub id: String,
    pub email: Option<String>,
    pub config_file: Option<PathBuf>,
    pub link_file: Option<PathBuf>,
    pub qr_file: Option<PathBuf>,
}

pub struct MigrationManager;

impl MigrationManager {
    pub fn new() -> Self {
        Self
    }

    pub async fn migrate_from_bash(&self, options: MigrationOptions) -> Result<MigrationReport> {
        let start_time = std::time::Instant::now();
        let mut report = MigrationReport {
            success: false,
            users_migrated: 0,
            configs_migrated: 0,
            files_migrated: 0,
            errors: Vec::new(),
            warnings: Vec::new(),
            migration_time_seconds: 0,
        };

        display::info("Starting migration from Bash VPN implementation...");

        // Setup progress tracking
        let pb = ProgressBar::new(100);
        pb.set_style(ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos:>7}/{len:7} {msg}")
            .unwrap());

        // Step 1: Validate source installation
        pb.set_message("Validating source installation...");
        pb.set_position(10);

        if let Err(e) = self.validate_bash_installation(&options.source_path) {
            report.errors.push(format!("Source validation failed: {}", e));
            return Ok(report);
        }

        // Step 2: Create target directory structure
        pb.set_message("Creating target directory structure...");
        pb.set_position(20);

        if let Err(e) = self.create_target_structure(&options.target_path) {
            report.errors.push(format!("Failed to create target structure: {}", e));
            return Ok(report);
        }

        // Step 3: Migrate server configuration
        pb.set_message("Migrating server configuration...");
        pb.set_position(30);

        if options.migrate_config {
            match self.migrate_server_config(&options.source_path, &options.target_path).await {
                Ok(_) => {
                    report.configs_migrated += 1;
                    display::success("Server configuration migrated successfully");
                }
                Err(e) => {
                    report.errors.push(format!("Config migration failed: {}", e));
                }
            }
        }

        // Step 4: Discover and migrate users
        pb.set_message("Discovering users...");
        pb.set_position(40);

        let discovered_users = self.discover_bash_users(&options.source_path)?;
        display::info(&format!("Found {} users to migrate", discovered_users.len()));

        if options.migrate_users && !discovered_users.is_empty() {
            pb.set_message("Migrating users...");
            pb.set_position(50);

            for (i, bash_user) in discovered_users.iter().enumerate() {
                let progress = 50 + (30 * i / discovered_users.len()) as u64;
                pb.set_position(progress);
                let message = format!("Migrating user: {}", bash_user.name);
                pb.set_message(message);

                match self.migrate_user(bash_user, &options.target_path).await {
                    Ok(_) => {
                        report.users_migrated += 1;
                    }
                    Err(e) => {
                        report.errors.push(format!("Failed to migrate user {}: {}", bash_user.name, e));
                    }
                }
            }
        }

        // Step 5: Migrate logs and additional files
        pb.set_message("Migrating logs and files...");
        pb.set_position(80);

        if options.migrate_logs {
            match self.migrate_logs(&options.source_path, &options.target_path) {
                Ok(count) => {
                    report.files_migrated += count;
                }
                Err(e) => {
                    report.warnings.push(format!("Log migration partially failed: {}", e));
                }
            }
        }

        // Step 6: Validation
        pb.set_message("Validating migration...");
        pb.set_position(90);

        if options.validate_after_migration {
            if let Err(e) = self.validate_migration(&options.target_path).await {
                report.warnings.push(format!("Migration validation warnings: {}", e));
            }
        }

        // Step 7: Cleanup (if not keeping original)
        pb.set_message("Finalizing...");
        pb.set_position(100);

        if !options.keep_original {
            if let Err(e) = self.cleanup_original(&options.source_path) {
                report.warnings.push(format!("Cleanup warning: {}", e));
            }
        }

        pb.finish_with_message("Migration completed!");

        report.success = report.errors.is_empty();
        report.migration_time_seconds = start_time.elapsed().as_secs();

        // Generate migration summary
        self.print_migration_summary(&report);

        Ok(report)
    }

    fn validate_bash_installation(&self, source_path: &Path) -> Result<()> {
        // Check if it looks like a valid Bash VPN installation
        let required_indicators = [
            "docker-compose.yml",
            "config",
        ];

        for indicator in &required_indicators {
            let path = source_path.join(indicator);
            if !path.exists() {
                return Err(CliError::MigrationError(
                    format!("Source installation missing: {}", indicator)
                ));
            }
        }

        // Additional validation
        let compose_file = source_path.join("docker-compose.yml");
        if let Ok(content) = std::fs::read_to_string(&compose_file) {
            if !content.contains("xray") && !content.contains("shadowbox") {
                return Err(CliError::MigrationError(
                    "Docker compose file doesn't appear to be for a VPN server".to_string()
                ));
            }
        }

        Ok(())
    }

    fn create_target_structure(&self, target_path: &Path) -> Result<()> {
        let directories = [
            "config",
            "users",
            "logs",
            "backups",
        ];

        for dir in &directories {
            let dir_path = target_path.join(dir);
            std::fs::create_dir_all(&dir_path)
                .map_err(|e| CliError::MigrationError(
                    format!("Failed to create directory {}: {}", dir_path.display(), e)
                ))?;
        }

        Ok(())
    }

    async fn migrate_server_config(&self, source_path: &Path, target_path: &Path) -> Result<()> {
        // Read Bash configuration
        let bash_config = self.read_bash_config(source_path)?;
        
        // Convert to Rust format
        let rust_config = self.convert_config_format(&bash_config)?;
        
        // Save to target location
        let target_config_file = target_path.join("config").join("config.json");
        let config_json = serde_json::to_string_pretty(&rust_config)
            .map_err(|e| CliError::MigrationError(format!("Failed to serialize config: {}", e)))?;
        
        std::fs::write(&target_config_file, config_json)
            .map_err(|e| CliError::MigrationError(format!("Failed to write config: {}", e)))?;

        // Copy key files if they exist
        self.copy_key_files(source_path, target_path)?;

        Ok(())
    }

    fn read_bash_config(&self, source_path: &Path) -> Result<BashVpnConfig> {
        let config_dir = source_path.join("config");
        
        // Try to read from various possible locations
        let config_sources = [
            config_dir.join("config.json"),
            source_path.join("config.json"),
            source_path.join("server.conf"),
        ];

        for config_file in &config_sources {
            if config_file.exists() {
                if let Ok(content) = std::fs::read_to_string(config_file) {
                    // Try to parse as JSON first
                    if let Ok(json_config) = serde_json::from_str::<serde_json::Value>(&content) {
                        return self.parse_json_config(&json_config);
                    }
                    
                    // Fall back to parsing as key-value pairs
                    return self.parse_text_config(&content);
                }
            }
        }

        // If no config file found, try to infer from other files
        self.infer_config_from_files(source_path)
    }

    fn parse_json_config(&self, json: &serde_json::Value) -> Result<BashVpnConfig> {
        // Extract configuration from Xray JSON format
        let mut config = BashVpnConfig {
            server_host: "0.0.0.0".to_string(),
            server_port: 443,
            protocol: "vless".to_string(),
            private_key: None,
            public_key: None,
            short_id: None,
            sni: None,
            reality_dest: None,
        };

        // Parse inbounds
        if let Some(inbounds) = json["inbounds"].as_array() {
            for inbound in inbounds {
                if let Some(port) = inbound["port"].as_u64() {
                    config.server_port = port as u16;
                }
                
                if let Some(protocol) = inbound["protocol"].as_str() {
                    config.protocol = protocol.to_string();
                }

                // Parse Reality settings
                if let Some(reality) = inbound["streamSettings"]["realitySettings"].as_object() {
                    config.private_key = reality["privateKey"].as_str().map(|s| s.to_string());
                    config.reality_dest = reality["dest"].as_str().map(|s| s.to_string());
                    
                    if let Some(server_names) = reality["serverNames"].as_array() {
                        if let Some(sni) = server_names.first().and_then(|s| s.as_str()) {
                            config.sni = Some(sni.to_string());
                        }
                    }
                    
                    if let Some(short_ids) = reality["shortId"].as_array() {
                        if let Some(short_id) = short_ids.first().and_then(|s| s.as_str()) {
                            config.short_id = Some(short_id.to_string());
                        }
                    }
                }
            }
        }

        Ok(config)
    }

    fn parse_text_config(&self, content: &str) -> Result<BashVpnConfig> {
        let mut config = BashVpnConfig {
            server_host: "0.0.0.0".to_string(),
            server_port: 443,
            protocol: "vless".to_string(),
            private_key: None,
            public_key: None,
            short_id: None,
            sni: None,
            reality_dest: None,
        };

        // Parse key-value pairs
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            if let Some((key, value)) = line.split_once('=') {
                let key = key.trim();
                let value = value.trim().trim_matches('"');

                match key {
                    "SERVER_HOST" | "HOST" => config.server_host = value.to_string(),
                    "SERVER_PORT" | "PORT" => {
                        if let Ok(port) = value.parse::<u16>() {
                            config.server_port = port;
                        }
                    }
                    "PROTOCOL" => config.protocol = value.to_string(),
                    "PRIVATE_KEY" => config.private_key = Some(value.to_string()),
                    "PUBLIC_KEY" => config.public_key = Some(value.to_string()),
                    "SHORT_ID" => config.short_id = Some(value.to_string()),
                    "SNI" | "SNI_DOMAIN" => config.sni = Some(value.to_string()),
                    "REALITY_DEST" => config.reality_dest = Some(value.to_string()),
                    _ => {}
                }
            }
        }

        Ok(config)
    }

    fn infer_config_from_files(&self, source_path: &Path) -> Result<BashVpnConfig> {
        let mut config = BashVpnConfig {
            server_host: "0.0.0.0".to_string(),
            server_port: 443,
            protocol: "vless".to_string(),
            private_key: None,
            public_key: None,
            short_id: None,
            sni: None,
            reality_dest: None,
        };

        let config_dir = source_path.join("config");

        // Try to read individual key files
        if let Ok(private_key) = std::fs::read_to_string(config_dir.join("private_key.txt")) {
            config.private_key = Some(private_key.trim().to_string());
        }

        if let Ok(public_key) = std::fs::read_to_string(config_dir.join("public_key.txt")) {
            config.public_key = Some(public_key.trim().to_string());
        }

        if let Ok(short_id) = std::fs::read_to_string(config_dir.join("short_id.txt")) {
            config.short_id = Some(short_id.trim().to_string());
        }

        if let Ok(sni) = std::fs::read_to_string(config_dir.join("sni.txt")) {
            config.sni = Some(sni.trim().to_string());
        }

        Ok(config)
    }

    fn convert_config_format(&self, bash_config: &BashVpnConfig) -> Result<serde_json::Value> {
        // Convert Bash config to Rust Xray format
        let config = serde_json::json!({
            "log": {
                "level": "warning",
                "access": "/opt/vpn/logs/access.log",
                "error": "/opt/vpn/logs/error.log"
            },
            "inbounds": [{
                "tag": "vless-in",
                "port": bash_config.server_port,
                "protocol": bash_config.protocol,
                "settings": {
                    "clients": [],
                    "decryption": "none",
                    "fallbacks": []
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "show": false,
                        "dest": bash_config.reality_dest.as_deref().unwrap_or("www.google.com:443"),
                        "xver": 0,
                        "serverNames": [bash_config.sni.as_deref().unwrap_or("www.google.com")],
                        "privateKey": bash_config.private_key.as_deref().unwrap_or(""),
                        "shortId": bash_config.short_id.as_ref().map(|s| vec![s.clone()]).unwrap_or_default()
                    },
                    "tcpSettings": {
                        "header": {
                            "type": "none"
                        }
                    }
                }
            }],
            "outbounds": [{
                "tag": "direct",
                "protocol": "freedom",
                "settings": {}
            }]
        });

        Ok(config)
    }

    fn copy_key_files(&self, source_path: &Path, target_path: &Path) -> Result<()> {
        let source_config = source_path.join("config");
        let target_config = target_path.join("config");

        let key_files = [
            "private_key.txt",
            "public_key.txt",
            "short_id.txt",
            "sni.txt",
        ];

        for key_file in &key_files {
            let source_file = source_config.join(key_file);
            let target_file = target_config.join(key_file);

            if source_file.exists() {
                std::fs::copy(&source_file, &target_file)
                    .map_err(|e| CliError::MigrationError(
                        format!("Failed to copy {}: {}", key_file, e)
                    ))?;
            }
        }

        Ok(())
    }

    fn discover_bash_users(&self, source_path: &Path) -> Result<Vec<BashUser>> {
        let mut users = Vec::new();
        let users_dir = source_path.join("users");

        if !users_dir.exists() {
            return Ok(users);
        }

        for entry in std::fs::read_dir(&users_dir)
            .map_err(|e| CliError::MigrationError(format!("Failed to read users directory: {}", e)))?
        {
            let entry = entry?;
            if entry.file_type()?.is_dir() {
                let user_dir = entry.path();
                if let Some(user_name) = user_dir.file_name().and_then(|n| n.to_str()) {
                    let user = self.parse_bash_user(user_name, &user_dir)?;
                    users.push(user);
                }
            }
        }

        Ok(users)
    }

    fn parse_bash_user(&self, name: &str, user_dir: &Path) -> Result<BashUser> {
        let mut user = BashUser {
            name: name.to_string(),
            id: name.to_string(), // Will try to get UUID if available
            email: None,
            config_file: None,
            link_file: None,
            qr_file: None,
        };

        // Check for user configuration file
        let config_file = user_dir.join("config.json");
        if config_file.exists() {
            user.config_file = Some(config_file.clone());
            
            // Try to extract UUID from config
            if let Ok(content) = std::fs::read_to_string(&config_file) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(id) = json["id"].as_str() {
                        user.id = id.to_string();
                    }
                    if let Some(email) = json["email"].as_str() {
                        user.email = Some(email.to_string());
                    }
                }
            }
        }

        // Check for connection link file
        let link_file = user_dir.join("connection.link");
        if link_file.exists() {
            user.link_file = Some(link_file);
        }

        // Check for QR code file
        let qr_file = user_dir.join("qr.png");
        if qr_file.exists() {
            user.qr_file = Some(qr_file);
        }

        Ok(user)
    }

    async fn migrate_user(&self, bash_user: &BashUser, target_path: &Path) -> Result<()> {
        // Create new user in Rust format
        let protocol = VpnProtocol::Vless; // Default, could be inferred from config
        
        let mut user = User::new(bash_user.name.clone(), protocol);
        user.id = bash_user.id.clone();
        user.email = bash_user.email.clone();
        user.status = UserStatus::Active;

        // If we have a config file, try to extract more information
        if let Some(config_file) = &bash_user.config_file {
            if let Ok(content) = std::fs::read_to_string(config_file) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    // Extract user-specific configuration
                    if let Some(private_key) = json["private_key"].as_str() {
                        user.config.private_key = Some(private_key.to_string());
                    }
                    if let Some(public_key) = json["public_key"].as_str() {
                        user.config.public_key = Some(public_key.to_string());
                    }
                }
            }
        }

        // Save user to target directory
        let target_user_dir = target_path.join("users").join(&user.id);
        std::fs::create_dir_all(&target_user_dir)
            .map_err(|e| CliError::MigrationError(format!("Failed to create user directory: {}", e)))?;

        let user_config_file = target_user_dir.join("config.json");
        let user_json = serde_json::to_string_pretty(&user)
            .map_err(|e| CliError::MigrationError(format!("Failed to serialize user: {}", e)))?;

        std::fs::write(&user_config_file, user_json)
            .map_err(|e| CliError::MigrationError(format!("Failed to write user config: {}", e)))?;

        // Copy additional files if they exist
        if let Some(link_file) = &bash_user.link_file {
            let target_link_file = target_user_dir.join("connection.link");
            std::fs::copy(link_file, &target_link_file)?;
        }

        if let Some(qr_file) = &bash_user.qr_file {
            let target_qr_file = target_user_dir.join("qr.png");
            std::fs::copy(qr_file, &target_qr_file)?;
        }

        Ok(())
    }

    fn migrate_logs(&self, source_path: &Path, target_path: &Path) -> Result<u32> {
        let source_logs = source_path.join("logs");
        let target_logs = target_path.join("logs");

        if !source_logs.exists() {
            return Ok(0);
        }

        let mut files_copied = 0;

        for entry in std::fs::read_dir(&source_logs)? {
            let entry = entry?;
            if entry.file_type()?.is_file() {
                let source_file = entry.path();
                let target_file = target_logs.join(entry.file_name());
                
                std::fs::copy(&source_file, &target_file)?;
                files_copied += 1;
            }
        }

        Ok(files_copied)
    }

    async fn validate_migration(&self, target_path: &Path) -> Result<()> {
        // Validate that the migration was successful
        let required_files = [
            "config/config.json",
        ];

        for file in &required_files {
            let file_path = target_path.join(file);
            if !file_path.exists() {
                return Err(CliError::MigrationError(
                    format!("Migration validation failed: missing {}", file)
                ));
            }
        }

        // Validate configuration JSON
        let config_file = target_path.join("config/config.json");
        let config_content = std::fs::read_to_string(&config_file)?;
        serde_json::from_str::<serde_json::Value>(&config_content)
            .map_err(|e| CliError::MigrationError(format!("Invalid migrated config: {}", e)))?;

        Ok(())
    }

    fn cleanup_original(&self, source_path: &Path) -> Result<()> {
        // Create a backup before cleanup
        let backup_path = source_path.with_extension("backup");
        
        display::warning("Creating backup of original installation before cleanup...");
        
        // Copy instead of move to be safe
        self.copy_directory_recursive(source_path, &backup_path)?;
        
        display::info(&format!("Original installation backed up to: {}", backup_path.display()));
        
        // Only remove if backup was successful
        if backup_path.exists() {
            std::fs::remove_dir_all(source_path)
                .map_err(|e| CliError::MigrationError(format!("Failed to cleanup original: {}", e)))?;
        }

        Ok(())
    }

    fn copy_directory_recursive(&self, source: &Path, target: &Path) -> Result<()> {
        std::fs::create_dir_all(target)?;

        for entry in std::fs::read_dir(source)? {
            let entry = entry?;
            let source_path = entry.path();
            let target_path = target.join(entry.file_name());

            if source_path.is_dir() {
                self.copy_directory_recursive(&source_path, &target_path)?;
            } else {
                std::fs::copy(&source_path, &target_path)?;
            }
        }

        Ok(())
    }

    fn print_migration_summary(&self, report: &MigrationReport) {
        display::header("Migration Summary");
        
        if report.success {
            display::success("Migration completed successfully!");
        } else {
            display::error("Migration completed with errors!");
        }

        println!("Statistics:");
        println!("  Users migrated: {}", report.users_migrated);
        println!("  Configs migrated: {}", report.configs_migrated);
        println!("  Files migrated: {}", report.files_migrated);
        println!("  Migration time: {}s", report.migration_time_seconds);

        if !report.errors.is_empty() {
            display::header("Errors");
            for error in &report.errors {
                display::error(error);
            }
        }

        if !report.warnings.is_empty() {
            display::header("Warnings");
            for warning in &report.warnings {
                display::warning(warning);
            }
        }

        if report.success {
            display::header("Next Steps");
            println!("1. Start the new Rust-based VPN server");
            println!("2. Test user connections");
            println!("3. Monitor logs for any issues");
            println!("4. Update client configurations if necessary");
        }
    }
}

impl Default for MigrationOptions {
    fn default() -> Self {
        Self {
            source_path: PathBuf::from("/opt/v2ray"),
            target_path: PathBuf::from("/opt/vpn"),
            keep_original: true,
            migrate_users: true,
            migrate_config: true,
            migrate_logs: true,
            validate_after_migration: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_parse_text_config() {
        let manager = MigrationManager::new();
        let config_text = r#"
            SERVER_HOST=192.168.1.100
            SERVER_PORT=8443
            PROTOCOL=vless
            PRIVATE_KEY=test-private-key
            SNI=example.com
        "#;

        let config = manager.parse_text_config(config_text).unwrap();
        assert_eq!(config.server_host, "192.168.1.100");
        assert_eq!(config.server_port, 8443);
        assert_eq!(config.protocol, "vless");
        assert_eq!(config.private_key, Some("test-private-key".to_string()));
        assert_eq!(config.sni, Some("example.com".to_string()));
    }

    #[test]
    fn test_validate_bash_installation() {
        let temp_dir = tempdir().unwrap();
        let manager = MigrationManager::new();

        // Should fail on empty directory
        assert!(manager.validate_bash_installation(temp_dir.path()).is_err());

        // Create required files
        std::fs::write(temp_dir.path().join("docker-compose.yml"), "version: '3'\nservices:\n  xray: {}")
            .unwrap();
        std::fs::create_dir_all(temp_dir.path().join("config")).unwrap();

        // Should now pass
        assert!(manager.validate_bash_installation(temp_dir.path()).is_ok());
    }

    #[tokio::test]
    async fn test_migration_workflow() {
        let temp_source = tempdir().unwrap();
        let temp_target = tempdir().unwrap();
        let manager = MigrationManager::new();

        // Create mock source installation
        let source_path = temp_source.path();
        let config_dir = source_path.join("config");
        std::fs::create_dir_all(&config_dir).unwrap();
        
        std::fs::write(source_path.join("docker-compose.yml"), 
            "version: '3'\nservices:\n  xray:\n    image: xray").unwrap();
        
        std::fs::write(config_dir.join("private_key.txt"), "test-private-key").unwrap();
        std::fs::write(config_dir.join("sni.txt"), "example.com").unwrap();

        // Test migration options
        let options = MigrationOptions {
            source_path: source_path.to_path_buf(),
            target_path: temp_target.path().to_path_buf(),
            keep_original: true,
            migrate_users: true,
            migrate_config: true,
            migrate_logs: false,
            validate_after_migration: true,
        };

        let result = manager.migrate_from_bash(options).await;
        assert!(result.is_ok());

        let report = result.unwrap();
        assert!(report.success);
        assert_eq!(report.configs_migrated, 1);
    }
}