//! Audit logging for privilege escalation events

use crate::error::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

/// Privilege escalation event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivilegeEvent {
    /// Timestamp of the event
    pub timestamp: DateTime<Utc>,
    /// User who requested privileges
    pub user: String,
    /// Original user (if using sudo)
    pub original_user: Option<String>,
    /// Operation that required privileges
    pub operation: String,
    /// Command arguments
    pub command: Vec<String>,
    /// Whether privilege was granted
    pub granted: bool,
    /// Reason for denial (if applicable)
    pub denial_reason: Option<String>,
    /// Process ID
    pub pid: u32,
    /// Session ID
    pub session_id: String,
}

/// Audit logger for privilege events
pub struct PrivilegeAuditor {
    log_path: PathBuf,
}

impl PrivilegeAuditor {
    /// Create a new privilege auditor
    pub fn new() -> Result<Self> {
        let log_path = if cfg!(target_os = "linux") {
            PathBuf::from("/var/log/vpn/privilege_audit.log")
        } else if cfg!(target_os = "macos") {
            PathBuf::from("/usr/local/var/log/vpn/privilege_audit.log")
        } else {
            PathBuf::from("./logs/privilege_audit.log")
        };

        // Don't create directory here - do it lazily when actually logging
        // This prevents permission errors when running without sudo
        Ok(Self { log_path })
    }

    /// Log a privilege escalation event
    pub fn log_event(&self, event: PrivilegeEvent) -> Result<()> {
        // Try to create parent directory if it doesn't exist
        // This will fail silently if we don't have permissions
        if let Some(parent) = self.log_path.parent() {
            if !parent.exists() {
                // Try to create directory, but ignore errors
                // This allows the program to run without sudo
                let _ = create_dir_all(parent);
            }
        }

        // Try to open the log file
        // If we can't (e.g., no permissions), we'll just skip logging
        let file_result = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.log_path);

        match file_result {
            Ok(mut file) => {
                let json = serde_json::to_string(&event)?;
                writeln!(file, "{}", json)?;
                Ok(())
            }
            Err(_) => {
                // Silently ignore logging errors when running without privileges
                // This allows the program to run without sudo for non-privileged operations
                Ok(())
            }
        }
    }

    /// Log a successful privilege grant
    pub fn log_grant(
        &self,
        user: String,
        original_user: Option<String>,
        operation: String,
        command: Vec<String>,
    ) -> Result<()> {
        let event = PrivilegeEvent {
            timestamp: Utc::now(),
            user,
            original_user,
            operation,
            command,
            granted: true,
            denial_reason: None,
            pid: std::process::id(),
            session_id: generate_session_id(),
        };

        self.log_event(event)
    }

    /// Log a privilege denial
    pub fn log_denial(
        &self,
        user: String,
        operation: String,
        command: Vec<String>,
        reason: String,
    ) -> Result<()> {
        let event = PrivilegeEvent {
            timestamp: Utc::now(),
            user,
            original_user: None,
            operation,
            command,
            granted: false,
            denial_reason: Some(reason),
            pid: std::process::id(),
            session_id: generate_session_id(),
        };

        self.log_event(event)
    }

    /// Get recent privilege events
    pub fn get_recent_events(&self, count: usize) -> Result<Vec<PrivilegeEvent>> {
        use std::fs::File;
        use std::io::{BufRead, BufReader};

        let file = File::open(&self.log_path)?;
        let reader = BufReader::new(file);
        let mut events = Vec::new();

        for line in reader.lines().flatten() {
            if let Ok(event) = serde_json::from_str::<PrivilegeEvent>(&line) {
                events.push(event);
            }
        }

        // Return last N events
        events.reverse();
        events.truncate(count);
        events.reverse();

        Ok(events)
    }

    /// Clean old audit logs
    pub fn clean_old_logs(&self, days_to_keep: i64) -> Result<()> {
        use std::fs::File;
        use std::io::{BufRead, BufReader};

        let cutoff_date = Utc::now() - chrono::Duration::days(days_to_keep);
        let file = File::open(&self.log_path)?;
        let reader = BufReader::new(file);
        let mut kept_events = Vec::new();

        for line in reader.lines().flatten() {
            if let Ok(event) = serde_json::from_str::<PrivilegeEvent>(&line) {
                if event.timestamp > cutoff_date {
                    kept_events.push(line);
                }
            }
        }

        // Rewrite the log file with only recent events
        let mut file = OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(&self.log_path)?;

        for event_line in kept_events {
            writeln!(file, "{}", event_line)?;
        }

        Ok(())
    }
}

/// Generate a unique session ID
fn generate_session_id() -> String {
    use rand::distributions::Alphanumeric;
    use rand::{thread_rng, Rng};

    thread_rng()
        .sample_iter(&Alphanumeric)
        .take(16)
        .map(char::from)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_privilege_auditor() {
        let temp_dir = TempDir::new().unwrap();
        let log_path = temp_dir.path().join("audit.log");

        let auditor = PrivilegeAuditor {
            log_path: log_path.clone(),
        };

        // Log a grant event
        auditor
            .log_grant(
                "testuser".to_string(),
                Some("originaluser".to_string()),
                "Install VPN Server".to_string(),
                vec!["vpn".to_string(), "install".to_string()],
            )
            .unwrap();

        // Log a denial event
        auditor
            .log_denial(
                "testuser".to_string(),
                "Delete User".to_string(),
                vec!["vpn".to_string(), "users".to_string(), "delete".to_string()],
                "User cancelled operation".to_string(),
            )
            .unwrap();

        // Get recent events
        let events = auditor.get_recent_events(10).unwrap();
        assert_eq!(events.len(), 2);
        assert!(events[0].granted);
        assert!(!events[1].granted);
    }
}
