//! Comprehensive input validation utilities

use crate::error::{CommonError, Result};
use regex::Regex;
use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};

/// Username validation rules
pub struct UsernameValidator {
    min_length: usize,
    max_length: usize,
    pattern: Regex,
}

impl Default for UsernameValidator {
    fn default() -> Self {
        Self {
            min_length: 3,
            max_length: 32,
            pattern: Regex::new(r"^[a-zA-Z0-9_-]+$").unwrap(),
        }
    }
}

impl UsernameValidator {
    /// Validate a username
    pub fn validate(&self, username: &str) -> Result<()> {
        // Check length
        if username.len() < self.min_length {
            return Err(CommonError::Validation(format!(
                "Username must be at least {} characters long",
                self.min_length
            )));
        }

        if username.len() > self.max_length {
            return Err(CommonError::Validation(format!(
                "Username must be at most {} characters long",
                self.max_length
            )));
        }

        // Check pattern
        if !self.pattern.is_match(username) {
            return Err(CommonError::Validation(
                "Username can only contain letters, numbers, underscores, and hyphens".to_string(),
            ));
        }

        // Check for reserved names
        let reserved = ["root", "admin", "system", "daemon", "nobody", "bin"];
        if reserved.contains(&username.to_lowercase().as_str()) {
            return Err(CommonError::Validation(
                "Username is reserved and cannot be used".to_string(),
            ));
        }

        Ok(())
    }
}

/// Email validation
pub struct EmailValidator {
    pattern: Regex,
}

impl Default for EmailValidator {
    fn default() -> Self {
        Self {
            pattern: Regex::new(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$").unwrap(),
        }
    }
}

impl EmailValidator {
    /// Validate an email address
    pub fn validate(&self, email: &str) -> Result<()> {
        if !self.pattern.is_match(email) {
            return Err(CommonError::Validation(
                "Invalid email address format".to_string(),
            ));
        }

        // Additional checks
        if email.len() > 254 {
            return Err(CommonError::Validation(
                "Email address is too long".to_string(),
            ));
        }

        Ok(())
    }
}

/// Path validation to prevent directory traversal
pub struct PathValidator {
    allowed_base_paths: Vec<PathBuf>,
}

impl PathValidator {
    pub fn new(allowed_base_paths: Vec<PathBuf>) -> Self {
        Self { allowed_base_paths }
    }

    /// Validate a path to ensure it's safe
    pub fn validate(&self, path: &Path) -> Result<PathBuf> {
        // Normalize the path
        let canonical = path
            .canonicalize()
            .map_err(|e| CommonError::Validation(format!("Invalid path: {}", e)))?;

        // Check for directory traversal attempts
        let path_str = path.to_string_lossy();
        if path_str.contains("..") || path_str.contains("~") {
            return Err(CommonError::Validation(
                "Path contains directory traversal attempt".to_string(),
            ));
        }

        // Check if path is within allowed base paths
        if !self.allowed_base_paths.is_empty() {
            let is_allowed = self
                .allowed_base_paths
                .iter()
                .any(|base| canonical.starts_with(base));

            if !is_allowed {
                return Err(CommonError::Validation(
                    "Path is outside allowed directories".to_string(),
                ));
            }
        }

        Ok(canonical)
    }

    /// Validate a filename (no path components)
    pub fn validate_filename(filename: &str) -> Result<()> {
        // Check for path separators
        if filename.contains('/') || filename.contains('\\') {
            return Err(CommonError::Validation(
                "Filename cannot contain path separators".to_string(),
            ));
        }

        // Check for null bytes
        if filename.contains('\0') {
            return Err(CommonError::Validation(
                "Filename cannot contain null bytes".to_string(),
            ));
        }

        // Check for special characters that might be problematic
        let invalid_chars = ['<', '>', ':', '"', '|', '?', '*'];
        for ch in invalid_chars {
            if filename.contains(ch) {
                return Err(CommonError::Validation(format!(
                    "Filename cannot contain character '{}'",
                    ch
                )));
            }
        }

        // Check length
        if filename.is_empty() {
            return Err(CommonError::Validation(
                "Filename cannot be empty".to_string(),
            ));
        }

        if filename.len() > 255 {
            return Err(CommonError::Validation("Filename is too long".to_string()));
        }

        Ok(())
    }
}

/// Port number validation
pub struct PortValidator;

impl PortValidator {
    /// Validate a port number
    pub fn validate(port: u16) -> Result<()> {
        if port == 0 {
            return Err(CommonError::Validation(
                "Port number cannot be 0".to_string(),
            ));
        }

        // Check for well-known ports that shouldn't be used
        let reserved_ports = [22, 25, 80, 443, 445, 3389];
        if reserved_ports.contains(&port) {
            return Err(CommonError::Validation(format!(
                "Port {} is reserved and should not be used",
                port
            )));
        }

        Ok(())
    }

    /// Validate a port range
    pub fn validate_range(start: u16, end: u16) -> Result<()> {
        if start == 0 || end == 0 {
            return Err(CommonError::Validation(
                "Port numbers cannot be 0".to_string(),
            ));
        }

        if start > end {
            return Err(CommonError::Validation(
                "Invalid port range: start port is greater than end port".to_string(),
            ));
        }

        if end - start > 1000 {
            return Err(CommonError::Validation(
                "Port range is too large (maximum 1000 ports)".to_string(),
            ));
        }

        Ok(())
    }
}

/// IP address validation
pub struct IpValidator;

impl IpValidator {
    /// Validate an IP address
    pub fn validate(ip: &str) -> Result<IpAddr> {
        let addr = ip
            .parse::<IpAddr>()
            .map_err(|_| CommonError::Validation("Invalid IP address format".to_string()))?;

        // Check for special addresses
        if addr.is_unspecified() {
            return Err(CommonError::Validation(
                "Cannot use unspecified IP address (0.0.0.0 or ::)".to_string(),
            ));
        }

        if addr.is_multicast() {
            return Err(CommonError::Validation(
                "Cannot use multicast IP address".to_string(),
            ));
        }

        Ok(addr)
    }

    /// Validate a socket address
    pub fn validate_socket_addr(addr: &str) -> Result<SocketAddr> {
        let socket_addr = addr
            .parse::<SocketAddr>()
            .map_err(|_| CommonError::Validation("Invalid socket address format".to_string()))?;

        // Validate IP part
        Self::validate(&socket_addr.ip().to_string())?;

        // Validate port part
        PortValidator::validate(socket_addr.port())?;

        Ok(socket_addr)
    }
}

/// SQL injection prevention
pub struct SqlValidator;

impl SqlValidator {
    /// Check for potential SQL injection patterns
    pub fn validate(input: &str) -> Result<()> {
        let dangerous_patterns = [
            "';",
            "'; --",
            "' OR '",
            "' OR 1=1",
            "1=1",
            "DROP TABLE",
            "DELETE FROM",
            "INSERT INTO",
            "UPDATE SET",
            "UNION SELECT",
            "/*",
            "*/",
        ];

        let input_upper = input.to_uppercase();
        for pattern in dangerous_patterns {
            if input_upper.contains(pattern) {
                return Err(CommonError::Validation(
                    "Input contains potentially dangerous SQL patterns".to_string(),
                ));
            }
        }

        Ok(())
    }

    /// Escape special characters for SQL
    pub fn escape(input: &str) -> String {
        input
            .replace('\\', "\\\\")
            .replace('\'', "\\'")
            .replace('"', "\\\"")
            .replace('\0', "\\0")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\x1a', "\\Z")
    }
}

/// Command injection prevention
pub struct CommandValidator;

impl CommandValidator {
    /// Check for shell metacharacters
    pub fn validate(input: &str) -> Result<()> {
        let dangerous_chars = [
            '|', '&', ';', '$', '`', '\\', '(', ')', '<', '>', '\n', '\r',
        ];

        for ch in dangerous_chars {
            if input.contains(ch) {
                return Err(CommonError::Validation(format!(
                    "Input contains dangerous character '{}'",
                    ch
                )));
            }
        }

        Ok(())
    }

    /// Validate environment variable name
    pub fn validate_env_var_name(name: &str) -> Result<()> {
        let pattern = Regex::new(r"^[A-Z_][A-Z0-9_]*$").unwrap();
        if !pattern.is_match(name) {
            return Err(CommonError::Validation(
                "Invalid environment variable name".to_string(),
            ));
        }
        Ok(())
    }
}

/// Configuration value validation
pub struct ConfigValidator;

impl ConfigValidator {
    /// Validate a configuration key
    pub fn validate_key(key: &str) -> Result<()> {
        let pattern = Regex::new(r"^[a-zA-Z][a-zA-Z0-9_.-]*$").unwrap();
        if !pattern.is_match(key) {
            return Err(CommonError::Validation(
                "Invalid configuration key format".to_string(),
            ));
        }

        if key.len() > 128 {
            return Err(CommonError::Validation(
                "Configuration key is too long".to_string(),
            ));
        }

        Ok(())
    }

    /// Validate a configuration value
    pub fn validate_value(value: &str) -> Result<()> {
        // Check for control characters
        if value
            .chars()
            .any(|c| c.is_control() && c != '\n' && c != '\r' && c != '\t')
        {
            return Err(CommonError::Validation(
                "Configuration value contains invalid control characters".to_string(),
            ));
        }

        if value.len() > 4096 {
            return Err(CommonError::Validation(
                "Configuration value is too long".to_string(),
            ));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_username_validation() {
        let validator = UsernameValidator::default();

        assert!(validator.validate("john_doe").is_ok());
        assert!(validator.validate("user-123").is_ok());

        assert!(validator.validate("ab").is_err()); // Too short
        assert!(validator.validate("root").is_err()); // Reserved
        assert!(validator.validate("user@domain").is_err()); // Invalid character
    }

    #[test]
    fn test_email_validation() {
        let validator = EmailValidator::default();

        assert!(validator.validate("user@example.com").is_ok());
        assert!(validator.validate("user.name+tag@example.co.uk").is_ok());

        assert!(validator.validate("invalid.email").is_err());
        assert!(validator.validate("@example.com").is_err());
    }

    #[test]
    fn test_path_validation() {
        let _validator = PathValidator::new(vec![PathBuf::from("/tmp")]);

        assert!(PathValidator::validate_filename("test.txt").is_ok());
        assert!(PathValidator::validate_filename("test/file.txt").is_err());
        assert!(PathValidator::validate_filename("test\0file").is_err());
    }

    #[test]
    fn test_sql_validation() {
        assert!(SqlValidator::validate("normal input").is_ok());
        assert!(SqlValidator::validate("user'; DROP TABLE users; --").is_err());
        assert!(SqlValidator::validate("' OR 1=1").is_err());
    }

    #[test]
    fn test_command_validation() {
        assert!(CommandValidator::validate("normal-command").is_ok());
        assert!(CommandValidator::validate("cmd | other").is_err());
        assert!(CommandValidator::validate("cmd; rm -rf /").is_err());
        assert!(CommandValidator::validate("$(whoami)").is_err());
    }
}
