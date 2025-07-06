use crate::error::{CliError, Result};
use regex::Regex;
use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};
use vpn_types::validation::*;

pub fn validate_username(username: &str) -> Result<()> {
    let validator = UsernameValidator::default();
    validator
        .validate(username)
        .map_err(|e| CliError::ValidationError(e.to_string()))
}

pub fn validate_email(email: &str) -> Result<()> {
    let validator = EmailValidator::default();
    validator
        .validate(email)
        .map_err(|e| CliError::ValidationError(e.to_string()))
}

pub fn validate_port(port: u16) -> Result<()> {
    if port < 1024 {
        return Err(CliError::ValidationError(
            "Port numbers below 1024 are privileged ports".to_string(),
        ));
    }

    PortValidator::validate(port).map_err(|e| CliError::ValidationError(e.to_string()))
}

pub fn validate_ip_address(ip: &str) -> Result<IpAddr> {
    IpValidator::validate(ip).map_err(|e| CliError::ValidationError(e.to_string()))
}

pub fn validate_socket_address(addr: &str) -> Result<SocketAddr> {
    IpValidator::validate_socket_addr(addr).map_err(|e| CliError::ValidationError(e.to_string()))
}

pub fn validate_domain_name(domain: &str) -> Result<()> {
    if domain.is_empty() {
        return Err(CliError::ValidationError(
            "Domain name cannot be empty".to_string(),
        ));
    }

    if domain.len() > 253 {
        return Err(CliError::ValidationError(
            "Domain name too long (max 253 characters)".to_string(),
        ));
    }

    // Check for valid domain format
    let domain_regex = Regex::new(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$")
        .map_err(|e| CliError::ValidationError(format!("Regex compilation failed: {}", e)))?;
    if !domain_regex.is_match(domain) {
        return Err(CliError::ValidationError(
            "Invalid domain name format".to_string(),
        ));
    }

    // Must contain at least one dot for FQDN
    if !domain.contains('.') {
        return Err(CliError::ValidationError(
            "Domain name must be fully qualified (contain at least one dot)".to_string(),
        ));
    }

    // Check each label
    for label in domain.split('.') {
        if label.is_empty() {
            return Err(CliError::ValidationError(
                "Domain labels cannot be empty".to_string(),
            ));
        }

        if label.len() > 63 {
            return Err(CliError::ValidationError(
                "Domain labels cannot exceed 63 characters".to_string(),
            ));
        }

        if label.starts_with('-') || label.ends_with('-') {
            return Err(CliError::ValidationError(
                "Domain labels cannot start or end with dash".to_string(),
            ));
        }
    }

    Ok(())
}

pub fn validate_file_path(path: &str, must_exist: bool) -> Result<()> {
    let path_obj = Path::new(path);

    // Validate filename
    if let Some(filename) = path_obj.file_name() {
        PathValidator::validate_filename(&filename.to_string_lossy())
            .map_err(|e| CliError::ValidationError(e.to_string()))?;
    }

    if must_exist && !path_obj.exists() {
        return Err(CliError::ValidationError(format!(
            "File does not exist: {}",
            path_obj.display()
        )));
    }

    if path_obj.exists() && path_obj.is_dir() {
        return Err(CliError::ValidationError(format!(
            "Path is a directory, not a file: {}",
            path_obj.display()
        )));
    }

    // Check if parent directory exists
    if let Some(parent) = path_obj.parent() {
        if !parent.exists() {
            return Err(CliError::ValidationError(format!(
                "Parent directory does not exist: {}",
                parent.display()
            )));
        }
    }

    Ok(())
}

pub fn validate_directory_path(path: &str, must_exist: bool) -> Result<()> {
    let path_obj = Path::new(path);

    if must_exist && !path_obj.exists() {
        return Err(CliError::ValidationError(format!(
            "Directory does not exist: {}",
            path_obj.display()
        )));
    }

    if path_obj.exists() && !path_obj.is_dir() {
        return Err(CliError::ValidationError(format!(
            "Path is not a directory: {}",
            path_obj.display()
        )));
    }

    // Use PathValidator for security checks
    let allowed_paths = vec![
        PathBuf::from("/etc/vpn"),
        PathBuf::from("/opt/vpn"),
        PathBuf::from("/var/lib/vpn"),
        PathBuf::from("/tmp"),
        dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home")),
    ];

    let validator = PathValidator::new(allowed_paths);
    if path_obj.exists() {
        validator
            .validate(path_obj)
            .map_err(|e| CliError::ValidationError(e.to_string()))?;
    }

    Ok(())
}

pub fn validate_json_string(json: &str) -> Result<serde_json::Value> {
    serde_json::from_str(json)
        .map_err(|e| CliError::ValidationError(format!("Invalid JSON: {}", e)))
}

pub fn validate_uuid(uuid: &str) -> Result<()> {
    uuid::Uuid::parse_str(uuid)
        .map_err(|_| CliError::ValidationError(format!("Invalid UUID format: {}", uuid)))?;
    Ok(())
}

pub fn validate_base64(base64: &str) -> Result<()> {
    use base64::Engine;
    base64::prelude::BASE64_STANDARD
        .decode(base64)
        .map_err(|_| CliError::ValidationError(format!("Invalid Base64 encoding: {}", base64)))?;
    Ok(())
}

pub fn validate_protocol_name(protocol: &str) -> Result<()> {
    let valid_protocols = ["vless", "shadowsocks", "wireguard", "socks", "http"];

    if !valid_protocols.contains(&protocol.to_lowercase().as_str()) {
        return Err(CliError::ValidationError(format!(
            "Unsupported protocol: {}. Valid protocols: {}",
            protocol,
            valid_protocols.join(", ")
        )));
    }

    Ok(())
}

pub fn validate_log_level(level: &str) -> Result<()> {
    let valid_levels = ["trace", "debug", "info", "warn", "error", "off"];

    if !valid_levels.contains(&level.to_lowercase().as_str()) {
        return Err(CliError::ValidationError(format!(
            "Invalid log level: {}. Valid levels: {}",
            level,
            valid_levels.join(", ")
        )));
    }

    Ok(())
}

pub fn validate_output_format(format: &str) -> Result<()> {
    let valid_formats = ["json", "table", "plain", "yaml"];

    if !valid_formats.contains(&format.to_lowercase().as_str()) {
        return Err(CliError::ValidationError(format!(
            "Invalid output format: {}. Valid formats: {}",
            format,
            valid_formats.join(", ")
        )));
    }

    Ok(())
}

pub fn validate_positive_integer(value: &str, field_name: &str) -> Result<u64> {
    let num = value.parse::<u64>().map_err(|_| {
        CliError::ValidationError(format!("{} must be a valid positive integer", field_name))
    })?;

    if num == 0 {
        return Err(CliError::ValidationError(format!(
            "{} must be greater than 0",
            field_name
        )));
    }

    Ok(num)
}

pub fn validate_percentage(value: f64, field_name: &str) -> Result<()> {
    if !(0.0..=100.0).contains(&value) {
        return Err(CliError::ValidationError(format!(
            "{} must be between 0 and 100",
            field_name
        )));
    }
    Ok(())
}

pub fn validate_config_key_path(path: &str) -> Result<()> {
    // Validate configuration key path like "server.port" or "monitoring.alerts.cpu_threshold"
    if path.is_empty() {
        return Err(CliError::ValidationError(
            "Config key path cannot be empty".to_string(),
        ));
    }

    let key_regex = Regex::new(r"^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*$")
        .map_err(|e| CliError::ValidationError(format!("Regex compilation failed: {}", e)))?;
    if !key_regex.is_match(path) {
        return Err(CliError::ValidationError(
            "Invalid config key path format. Use dot notation like 'section.key'".to_string(),
        ));
    }

    Ok(())
}

pub fn sanitize_filename(filename: &str) -> String {
    // Remove or replace invalid filename characters
    let invalid_chars_regex =
        Regex::new(r#"[<>:"/\\|?*]"#).expect("Static regex should always compile");
    let sanitized = invalid_chars_regex.replace_all(filename, "_");

    // Trim whitespace and dots from ends
    sanitized
        .trim_matches(|c: char| c.is_whitespace() || c == '.')
        .to_string()
}

pub fn validate_backup_retention_days(days: u32) -> Result<()> {
    if days == 0 {
        return Err(CliError::ValidationError(
            "Backup retention must be at least 1 day".to_string(),
        ));
    }

    if days > 365 {
        return Err(CliError::ValidationError(
            "Backup retention cannot exceed 365 days".to_string(),
        ));
    }

    Ok(())
}

/// Validate password strength for security
pub fn validate_password_strength(password: &str) -> Result<()> {
    if password.len() < 12 {
        return Err(CliError::ValidationError(
            "Password must be at least 12 characters long".to_string(),
        ));
    }

    if password.len() > 128 {
        return Err(CliError::ValidationError(
            "Password too long (max 128 characters)".to_string(),
        ));
    }

    let has_upper = password.chars().any(|c| c.is_ascii_uppercase());
    let has_lower = password.chars().any(|c| c.is_ascii_lowercase());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    let has_special = password
        .chars()
        .any(|c| "!@#$%^&*()_+-=[]{}|;:,.<>?".contains(c));

    if !(has_upper && has_lower && has_digit && has_special) {
        return Err(CliError::ValidationError(
            "Password must contain uppercase, lowercase, digit, and special character".to_string(),
        ));
    }

    // Check for common weak patterns
    let lower_password = password.to_lowercase();
    let weak_patterns = [
        "password", "123456", "qwerty", "admin", "root", "user", "test", "guest", "vpn", "server",
        "default",
    ];

    for pattern in &weak_patterns {
        if lower_password.contains(pattern) {
            return Err(CliError::ValidationError(format!(
                "Password contains weak pattern: {}",
                pattern
            )));
        }
    }

    Ok(())
}

/// Sanitize and validate log message to prevent log injection
pub fn sanitize_log_message(message: &str) -> String {
    // Remove control characters and potential ANSI escape sequences
    let control_char_regex = Regex::new(r"[\x00-\x1F\x7F]|\x1B\[[0-9;]*[a-zA-Z]")
        .expect("Static regex should always compile");

    let sanitized = control_char_regex.replace_all(message, "");

    // Limit length to prevent log flooding
    if sanitized.len() > 1000 {
        format!("{}...[truncated]", &sanitized[..997])
    } else {
        sanitized.to_string()
    }
}

/// Validate command arguments for shell execution safety
pub fn validate_command_arg(arg: &str) -> Result<()> {
    CommandValidator::validate(arg).map_err(|e| CliError::ValidationError(e.to_string()))
}

/// Validate SQL input to prevent injection
pub fn validate_sql_input(input: &str) -> Result<()> {
    SqlValidator::validate(input).map_err(|e| CliError::ValidationError(e.to_string()))
}

/// Validate configuration key
pub fn validate_config_key(key: &str) -> Result<()> {
    ConfigValidator::validate_key(key).map_err(|e| CliError::ValidationError(e.to_string()))
}

/// Validate configuration value
pub fn validate_config_value(value: &str) -> Result<()> {
    ConfigValidator::validate_value(value).map_err(|e| CliError::ValidationError(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_username() {
        assert!(validate_username("valid_user123").is_ok());
        assert!(validate_username("user-name").is_ok());
        assert!(validate_username("").is_err());
        assert!(validate_username("-invalid").is_err());
        assert!(validate_username("_invalid").is_err());
        assert!(validate_username("user with spaces").is_err());
    }

    #[test]
    fn test_validate_email() {
        assert!(validate_email("user@example.com").is_ok());
        assert!(validate_email("test.email+tag@domain.co.uk").is_ok());
        assert!(validate_email("invalid-email").is_err());
        assert!(validate_email("@domain.com").is_err());
        assert!(validate_email("user@").is_err());
    }

    #[test]
    fn test_validate_port() {
        assert!(validate_port(8080).is_ok());
        assert!(validate_port(65535).is_ok());
        assert!(validate_port(0).is_err());
        assert!(validate_port(80).is_err()); // Reserved port
        assert!(validate_port(443).is_err()); // Reserved port
    }

    #[test]
    fn test_validate_domain_name() {
        assert!(validate_domain_name("example.com").is_ok());
        assert!(validate_domain_name("sub.domain.example.org").is_ok());
        assert!(validate_domain_name("localhost").is_err()); // No dot
        assert!(validate_domain_name(".example.com").is_err()); // Starts with dot
        assert!(validate_domain_name("example..com").is_err()); // Double dot
    }

    #[test]
    fn test_validate_ip_address() {
        assert!(validate_ip_address("192.168.1.1").is_ok());
        assert!(validate_ip_address("::1").is_ok());
        assert!(validate_ip_address("2001:db8::1").is_ok());
        assert!(validate_ip_address("invalid-ip").is_err());
        assert!(validate_ip_address("256.256.256.256").is_err());
    }

    #[test]
    fn test_validate_protocol_name() {
        assert!(validate_protocol_name("vless").is_ok());
        assert!(validate_protocol_name("VLESS").is_ok()); // Case insensitive
        assert!(validate_protocol_name("shadowsocks").is_ok());
        assert!(validate_protocol_name("invalid-protocol").is_err());
    }

    #[test]
    fn test_validate_percentage() {
        assert!(validate_percentage(50.0, "test").is_ok());
        assert!(validate_percentage(0.0, "test").is_ok());
        assert!(validate_percentage(100.0, "test").is_ok());
        assert!(validate_percentage(-1.0, "test").is_err());
        assert!(validate_percentage(101.0, "test").is_err());
    }

    #[test]
    fn test_sanitize_filename() {
        assert_eq!(
            sanitize_filename("valid_filename.txt"),
            "valid_filename.txt"
        );
        assert_eq!(
            sanitize_filename("file<>with|invalid*chars.txt"),
            "file__with_invalid_chars.txt"
        );
        assert_eq!(sanitize_filename("  .trimmed.  "), "trimmed");
    }

    #[test]
    fn test_validate_config_key_path() {
        assert!(validate_config_key_path("server.port").is_ok());
        assert!(validate_config_key_path("monitoring.alerts.cpu_threshold").is_ok());
        assert!(validate_config_key_path("").is_err());
        assert!(validate_config_key_path(".invalid").is_err());
        assert!(validate_config_key_path("invalid.").is_err());
        assert!(validate_config_key_path("invalid..path").is_err());
    }
}
