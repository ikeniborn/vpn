//! Privilege bracketing implementation

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use crate::error::{CliError, Result};
use super::audit::PrivilegeAuditor;

/// Privilege bracket for temporarily elevated operations
pub struct PrivilegeBracket {
    /// Operation name
    operation: String,
    /// Start time
    start_time: Instant,
    /// Maximum duration
    max_duration: Duration,
    /// Auditor
    auditor: Arc<PrivilegeAuditor>,
    /// Whether privileges are currently elevated
    elevated: bool,
    /// Original user ID (for dropping privileges)
    #[cfg(unix)]
    original_uid: Option<u32>,
    #[cfg(unix)]
    original_gid: Option<u32>,
}

impl PrivilegeBracket {
    /// Create a new privilege bracket
    pub fn new(operation: String, max_duration: Duration) -> Result<Self> {
        let auditor = Arc::new(PrivilegeAuditor::new()?);
        
        #[cfg(unix)]
        let (original_uid, original_gid) = unsafe {
            (Some(libc::getuid()), Some(libc::getgid()))
        };

        Ok(Self {
            operation,
            start_time: Instant::now(),
            max_duration,
            auditor,
            elevated: false,
            #[cfg(unix)]
            original_uid,
            #[cfg(unix)]
            original_gid,
        })
    }

    /// Acquire minimal privileges for the operation
    pub fn acquire(&mut self) -> Result<()> {
        if self.elevated {
            return Ok(());
        }

        // Check if we're already running as root
        if !super::PrivilegeManager::is_root() {
            return Err(CliError::PermissionError(
                "Cannot acquire privileges: not running as root".to_string()
            ));
        }

        // Log the privilege acquisition
        let user = std::env::var("USER").unwrap_or_else(|_| "unknown".to_string());
        let sudo_user = std::env::var("SUDO_USER").ok();
        self.auditor.log_grant(
            user,
            sudo_user,
            self.operation.clone(),
            std::env::args().collect(),
        )?;

        self.elevated = true;
        Ok(())
    }

    /// Drop privileges back to original user
    pub fn drop(&mut self) -> Result<()> {
        if !self.elevated {
            return Ok(());
        }

        #[cfg(unix)]
        {
            if let (Some(uid), Some(gid)) = (self.original_uid, self.original_gid) {
                unsafe {
                    // Drop group privileges first
                    if libc::setgid(gid) != 0 {
                        return Err(CliError::PermissionError(
                            "Failed to drop group privileges".to_string()
                        ));
                    }
                    
                    // Then drop user privileges
                    if libc::setuid(uid) != 0 {
                        return Err(CliError::PermissionError(
                            "Failed to drop user privileges".to_string()
                        ));
                    }
                }
            }
        }

        self.elevated = false;
        Ok(())
    }

    /// Check if privileges have expired
    pub fn is_expired(&self) -> bool {
        self.start_time.elapsed() > self.max_duration
    }

    /// Execute a function with elevated privileges
    pub fn with_privileges<F, T>(&mut self, f: F) -> Result<T>
    where
        F: FnOnce() -> Result<T>,
    {
        // Check expiration
        if self.is_expired() {
            return Err(CliError::PermissionError(
                "Privilege bracket expired".to_string()
            ));
        }

        // Acquire privileges
        self.acquire()?;

        // Execute the function
        let result = f();

        // Always try to drop privileges, even if the function failed
        let drop_result = self.drop();

        // Return the original error if function failed
        match (result, drop_result) {
            (Ok(value), Ok(())) => Ok(value),
            (Err(e), _) => Err(e),
            (Ok(_), Err(e)) => Err(e),
        }
    }
}

impl Drop for PrivilegeBracket {
    fn drop(&mut self) {
        // Ensure privileges are dropped when bracket goes out of scope
        let _ = self.drop();
    }
}

/// Manager for privilege brackets with rate limiting
pub struct BracketManager {
    /// Active brackets
    brackets: Arc<Mutex<Vec<BracketInfo>>>,
    /// Maximum brackets per hour
    max_brackets_per_hour: usize,
}

struct BracketInfo {
    operation: String,
    start_time: Instant,
}

impl BracketManager {
    /// Create a new bracket manager
    pub fn new(max_brackets_per_hour: usize) -> Self {
        Self {
            brackets: Arc::new(Mutex::new(Vec::new())),
            max_brackets_per_hour,
        }
    }

    /// Create a new privilege bracket with rate limiting
    pub fn create_bracket(
        &self,
        operation: String,
        duration: Duration,
    ) -> Result<PrivilegeBracket> {
        let mut brackets = self.brackets.lock().unwrap();
        
        // Clean old brackets (older than 1 hour)
        let one_hour_ago = Instant::now() - Duration::from_secs(3600);
        brackets.retain(|b| b.start_time > one_hour_ago);

        // Check rate limit
        if brackets.len() >= self.max_brackets_per_hour {
            return Err(CliError::PermissionError(
                format!(
                    "Rate limit exceeded: maximum {} privilege escalations per hour",
                    self.max_brackets_per_hour
                )
            ));
        }

        // Add new bracket
        brackets.push(BracketInfo {
            operation: operation.clone(),
            start_time: Instant::now(),
        });

        PrivilegeBracket::new(operation, duration)
    }

    /// Get recent bracket usage
    pub fn get_recent_usage(&self) -> Vec<(String, Duration)> {
        let brackets = self.brackets.lock().unwrap();
        let now = Instant::now();
        
        brackets
            .iter()
            .map(|b| (b.operation.clone(), now - b.start_time))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_privilege_bracket_expiration() {
        let mut bracket = PrivilegeBracket::new(
            "Test Operation".to_string(),
            Duration::from_millis(100),
        ).unwrap();

        assert!(!bracket.is_expired());
        
        std::thread::sleep(Duration::from_millis(150));
        assert!(bracket.is_expired());
    }

    #[test]
    fn test_bracket_manager_rate_limiting() {
        let manager = BracketManager::new(3);
        
        // Create 3 brackets (should succeed)
        for i in 0..3 {
            let bracket = manager.create_bracket(
                format!("Operation {}", i),
                Duration::from_secs(60),
            );
            assert!(bracket.is_ok());
        }

        // 4th bracket should fail due to rate limit
        let bracket = manager.create_bracket(
            "Operation 4".to_string(),
            Duration::from_secs(60),
        );
        assert!(bracket.is_err());
    }
}