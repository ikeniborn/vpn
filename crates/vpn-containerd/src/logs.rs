use crate::{ContainerdError, Result};
use chrono::{DateTime, Utc};
use futures_util::{Stream, StreamExt};
use serde_json::Value;
use std::collections::HashMap;
use std::pin::Pin;
use tokio::fs::File;
use tokio::io::{AsyncBufReadExt, AsyncSeekExt, BufReader, SeekFrom};
use tracing::{debug, info, warn};
use vpn_runtime::LogLevel;

/// Log stream type for containerd
#[derive(Debug, Clone, PartialEq)]
pub enum LogStream {
    Stdout,
    Stderr,
}

impl std::fmt::Display for LogStream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LogStream::Stdout => write!(f, "stdout"),
            LogStream::Stderr => write!(f, "stderr"),
        }
    }
}

/// Log entry from containerd
#[derive(Debug, Clone)]
pub struct ContainerdLogEntry {
    pub timestamp: DateTime<Utc>,
    pub container_id: String,
    pub stream: LogStream,
    pub level: LogLevel,
    pub message: String,
    pub attributes: HashMap<String, String>,
}

impl ContainerdLogEntry {
    /// Parse a log line from containerd JSON format
    pub fn from_json_line(line: &str, container_id: &str) -> Result<Self> {
        let json: Value = serde_json::from_str(line)
            .map_err(|e| ContainerdError::JsonError(e))?;

        let timestamp = json
            .get("time")
            .and_then(|t| t.as_str())
            .and_then(|t| DateTime::parse_from_rfc3339(t).ok())
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        let stream = json
            .get("stream")
            .and_then(|s| s.as_str())
            .map(|s| match s {
                "stdout" => LogStream::Stdout,
                "stderr" => LogStream::Stderr,
                _ => LogStream::Stdout,
            })
            .unwrap_or(LogStream::Stdout);

        let message = json
            .get("log")
            .and_then(|m| m.as_str())
            .unwrap_or("")
            .trim_end_matches('\n')
            .to_string();

        // Try to parse log level from message content
        let level = if message.to_lowercase().contains("error") || stream == LogStream::Stderr {
            LogLevel::Error
        } else if message.to_lowercase().contains("warn") {
            LogLevel::Warn
        } else if message.to_lowercase().contains("debug") {
            LogLevel::Debug
        } else {
            LogLevel::Info
        };

        let mut attributes = HashMap::new();
        if let Some(attrs) = json.get("attrs").and_then(|a| a.as_object()) {
            for (key, value) in attrs {
                if let Some(val_str) = value.as_str() {
                    attributes.insert(key.clone(), val_str.to_string());
                }
            }
        }

        Ok(ContainerdLogEntry {
            timestamp,
            container_id: container_id.to_string(),
            stream,
            level,
            message,
            attributes,
        })
    }

    /// Convert to vpn_runtime LogEntry
    pub fn to_runtime_log_entry(&self) -> vpn_runtime::LogEntry {
        vpn_runtime::LogEntry {
            timestamp: self.timestamp,
            stream: match self.stream {
                LogStream::Stdout => vpn_runtime::LogStreamType::Stdout,
                LogStream::Stderr => vpn_runtime::LogStreamType::Stderr,
            },
            message: self.message.clone(),
        }
    }
}

/// Log filter for containerd logs
#[derive(Debug, Clone)]
pub struct LogFilter {
    pub container_ids: Vec<String>,
    pub since: Option<DateTime<Utc>>,
    pub until: Option<DateTime<Utc>>,
    pub tail: Option<usize>,
    pub follow: bool,
    pub levels: Vec<LogLevel>,
    pub streams: Vec<LogStream>,
}

impl Default for LogFilter {
    fn default() -> Self {
        Self {
            container_ids: vec![],
            since: None,
            until: None,
            tail: None,
            follow: false,
            levels: vec![],
            streams: vec![LogStream::Stdout, LogStream::Stderr],
        }
    }
}

impl LogFilter {
    /// Create a filter for following logs in real-time
    pub fn follow_all() -> Self {
        Self {
            follow: true,
            tail: Some(100), // Start with last 100 lines
            ..Default::default()
        }
    }

    /// Create a filter for specific container logs
    pub fn for_container(container_id: &str) -> Self {
        Self {
            container_ids: vec![container_id.to_string()],
            ..Default::default()
        }
    }

    /// Create a filter for error logs only
    pub fn errors_only() -> Self {
        Self {
            levels: vec![LogLevel::Error],
            // Don't filter by stream - errors can appear on both stdout and stderr
            ..Default::default()
        }
    }

    /// Check if a log entry matches this filter
    pub fn matches(&self, entry: &ContainerdLogEntry) -> bool {
        // Check container IDs
        if !self.container_ids.is_empty() && !self.container_ids.contains(&entry.container_id) {
            return false;
        }

        // Check time range
        if let Some(since) = self.since {
            if entry.timestamp < since {
                return false;
            }
        }

        if let Some(until) = self.until {
            if entry.timestamp > until {
                return false;
            }
        }

        // Check log levels
        if !self.levels.is_empty() && !self.levels.contains(&entry.level) {
            return false;
        }

        // Check streams
        if !self.streams.is_empty() && !self.streams.contains(&entry.stream) {
            return false;
        }

        true
    }
}

/// Log rotation configuration
#[derive(Debug, Clone)]
pub struct LogRotationConfig {
    pub max_size: u64,        // Maximum size in bytes
    pub max_files: usize,     // Maximum number of rotated files
    pub compress: bool,       // Whether to compress rotated files
    pub rotate_daily: bool,   // Whether to rotate daily
}

impl Default for LogRotationConfig {
    fn default() -> Self {
        Self {
            max_size: 100 * 1024 * 1024, // 100MB
            max_files: 5,
            compress: true,
            rotate_daily: false,
        }
    }
}

/// Log management for containerd
pub struct LogManager {
    namespace: String,
    log_root: String,
    rotation_config: LogRotationConfig,
}

impl LogManager {
    pub fn new(namespace: String, log_root: String) -> Self {
        Self {
            namespace,
            log_root,
            rotation_config: LogRotationConfig::default(),
        }
    }

    /// Set log rotation configuration
    pub fn with_rotation_config(mut self, config: LogRotationConfig) -> Self {
        self.rotation_config = config;
        self
    }

    /// Get log file path for a container
    fn get_log_file_path(&self, container_id: &str) -> String {
        format!("{}/containers/{}/{}.log", self.log_root, self.namespace, container_id)
    }

    /// Stream logs from a container's log file
    pub async fn stream_logs(&self, container_id: &str, filter: LogFilter) -> Result<Pin<Box<dyn Stream<Item = Result<ContainerdLogEntry>> + Send + '_>>> {
        let log_file_path = self.get_log_file_path(container_id);
        debug!("Streaming logs from: {}", log_file_path);

        let file = File::open(&log_file_path).await
            .map_err(|e| ContainerdError::IoError(e))?;

        let mut reader = BufReader::new(file);

        // If tail is specified, seek to the approximate position
        if let Some(tail_lines) = filter.tail {
            if let Err(e) = Self::seek_to_tail(&mut reader, tail_lines).await {
                warn!("Failed to seek to tail: {}", e);
                // Continue from beginning if seek fails
                reader.rewind().await.map_err(|e| ContainerdError::IoError(e))?;
            }
        }

        let container_id = container_id.to_string();
        let filter = filter.clone();
        let log_root = self.log_root.clone();
        let namespace = self.namespace.clone();

        let stream = async_stream::stream! {
            use tokio::io::AsyncBufReadExt;
            let mut lines = reader.lines();
            
            while let Ok(Some(line)) = lines.next_line().await {
                match ContainerdLogEntry::from_json_line(&line, &container_id) {
                    Ok(entry) => {
                        if filter.matches(&entry) {
                            yield Ok(entry);
                        }
                    }
                    Err(e) => {
                        warn!("Failed to parse log line: {}", e);
                        // Continue processing other lines
                    }
                }
            }

            // If follow is enabled, continue monitoring the file
            if filter.follow {
                debug!("Following log file for new entries");
                
                // Reopen file for follow mode to avoid borrowing issues
                loop {
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                    
                    let log_file_path = format!("{}/containers/{}/{}.log", log_root, namespace, container_id);
                    if let Ok(_metadata) = tokio::fs::metadata(&log_file_path).await {
                        // Simple approach: reread the file periodically
                        // In production, you'd use inotify or similar
                        if let Ok(content) = tokio::fs::read_to_string(&log_file_path).await {
                            for line in content.lines() {
                                match ContainerdLogEntry::from_json_line(line, &container_id) {
                                    Ok(entry) => {
                                        if filter.matches(&entry) {
                                            yield Ok(entry);
                                        }
                                    }
                                    Err(_) => {
                                        // Continue processing other lines
                                    }
                                }
                            }
                        }
                    }
                }
            }
        };

        Ok(Box::pin(stream))
    }

    /// Get logs for multiple containers
    pub async fn get_logs(&self, filter: LogFilter) -> Result<Vec<ContainerdLogEntry>> {
        let mut all_logs = Vec::new();

        for container_id in &filter.container_ids {
            let container_filter = LogFilter {
                container_ids: vec![container_id.clone()],
                follow: false, // Don't follow for batch collection
                ..filter.clone()
            };

            let mut stream = self.stream_logs(container_id, container_filter).await?;
            
            while let Some(entry_result) = stream.next().await {
                match entry_result {
                    Ok(entry) => all_logs.push(entry),
                    Err(e) => warn!("Error reading log entry: {}", e),
                }
            }
        }

        // Sort by timestamp
        all_logs.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

        // Apply tail limit if specified
        if let Some(tail) = filter.tail {
            if all_logs.len() > tail {
                let skip_count = all_logs.len() - tail;
                all_logs = all_logs.into_iter().skip(skip_count).collect();
            }
        }

        Ok(all_logs)
    }

    /// Search logs by pattern
    pub async fn search_logs(&self, pattern: &str, filter: LogFilter) -> Result<Vec<ContainerdLogEntry>> {
        let logs = self.get_logs(filter).await?;
        
        let matching_logs: Vec<ContainerdLogEntry> = logs
            .into_iter()
            .filter(|entry| {
                entry.message.contains(pattern) || 
                entry.attributes.values().any(|v| v.contains(pattern))
            })
            .collect();

        debug!("Found {} log entries matching pattern: {}", matching_logs.len(), pattern);
        Ok(matching_logs)
    }

    /// Get log statistics for containers
    pub async fn get_log_stats(&self, container_ids: &[String]) -> Result<HashMap<String, LogStats>> {
        let mut stats = HashMap::new();

        for container_id in container_ids {
            let log_file_path = self.get_log_file_path(container_id);
            
            match tokio::fs::metadata(&log_file_path).await {
                Ok(metadata) => {
                    // Count lines by reading the file
                    let (line_count, error_count) = self.count_log_lines(container_id).await?;
                    
                    stats.insert(container_id.clone(), LogStats {
                        total_size: metadata.len(),
                        line_count,
                        error_count,
                        last_modified: metadata.modified()
                            .ok()
                            .and_then(|t| DateTime::from_timestamp(
                                t.duration_since(std::time::UNIX_EPOCH).ok()?.as_secs() as i64, 0
                            ))
                            .unwrap_or_else(Utc::now),
                    });
                }
                Err(_) => {
                    // Container has no logs
                    stats.insert(container_id.clone(), LogStats::default());
                }
            }
        }

        Ok(stats)
    }

    /// Archive old logs
    pub async fn archive_logs(&self, container_id: &str, before: DateTime<Utc>) -> Result<String> {
        let log_file_path = self.get_log_file_path(container_id);
        let archive_path = format!("{}.archive-{}.log", log_file_path, before.format("%Y%m%d"));

        debug!("Archiving logs for {} before {} to {}", container_id, before, archive_path);

        let filter = LogFilter {
            container_ids: vec![container_id.to_string()],
            until: Some(before),
            follow: false,
            ..Default::default()
        };

        let logs = self.get_logs(filter).await?;
        
        // Write archived logs
        let mut archive_content = String::new();
        for entry in logs {
            archive_content.push_str(&format!(
                "{} [{}] {}: {}\n",
                entry.timestamp.to_rfc3339(),
                entry.level,
                entry.stream,
                entry.message
            ));
        }

        tokio::fs::write(&archive_path, archive_content).await
            .map_err(|e| ContainerdError::IoError(e))?;

        if self.rotation_config.compress {
            // Compress the archive (simplified - would use a compression library)
            info!("Archive created: {} (compression not implemented)", archive_path);
        } else {
            info!("Archive created: {}", archive_path);
        }

        Ok(archive_path)
    }

    /// Clean up old log files
    pub async fn cleanup_logs(&self, container_id: &str, keep_days: u64) -> Result<()> {
        let cutoff = Utc::now() - chrono::Duration::days(keep_days as i64);
        
        // Archive old logs
        let _archive_path = self.archive_logs(container_id, cutoff).await?;
        
        // Remove old entries from main log file (simplified implementation)
        let filter = LogFilter {
            container_ids: vec![container_id.to_string()],
            since: Some(cutoff),
            follow: false,
            ..Default::default()
        };

        let recent_logs = self.get_logs(filter).await?;
        
        // Rewrite log file with only recent entries
        let log_file_path = self.get_log_file_path(container_id);
        let mut new_content = String::new();
        
        for entry in recent_logs {
            // Convert back to JSON format (simplified)
            let json_line = serde_json::json!({
                "time": entry.timestamp.to_rfc3339(),
                "stream": match entry.stream {
                    LogStream::Stdout => "stdout",
                    LogStream::Stderr => "stderr",
                },
                "log": format!("{}\n", entry.message),
                "attrs": entry.attributes
            });
            new_content.push_str(&format!("{}\n", json_line));
        }

        tokio::fs::write(&log_file_path, new_content).await
            .map_err(|e| ContainerdError::IoError(e))?;

        info!("Cleaned up logs for {} (kept {} days)", container_id, keep_days);
        Ok(())
    }

    /// Helper function to seek to approximate tail position
    async fn seek_to_tail(reader: &mut BufReader<File>, tail_lines: usize) -> Result<()> {
        let file_size = reader.get_ref().metadata().await
            .map_err(|e| ContainerdError::IoError(e))?
            .len();

        // Estimate bytes per line (rough approximation)
        let estimated_bytes_per_line = 200;
        let seek_position = file_size.saturating_sub(tail_lines as u64 * estimated_bytes_per_line);

        reader.seek(SeekFrom::Start(seek_position)).await
            .map_err(|e| ContainerdError::IoError(e))?;

        // Read to next newline to align with line boundaries
        use tokio::io::AsyncBufReadExt;
        let mut _discard = String::new();
        reader.read_line(&mut _discard).await
            .map_err(|e| ContainerdError::IoError(e))?;

        Ok(())
    }

    /// Helper function to count log lines and errors
    async fn count_log_lines(&self, container_id: &str) -> Result<(usize, usize)> {
        let log_file_path = self.get_log_file_path(container_id);
        let file = File::open(&log_file_path).await
            .map_err(|e| ContainerdError::IoError(e))?;

        let reader = BufReader::new(file);
        let mut lines = reader.lines();
        let mut total_lines = 0;
        let mut error_lines = 0;

        while let Ok(Some(line)) = lines.next_line().await {
            total_lines += 1;
            
            if let Ok(entry) = ContainerdLogEntry::from_json_line(&line, container_id) {
                if entry.level == LogLevel::Error || entry.stream == LogStream::Stderr {
                    error_lines += 1;
                }
            }
        }

        Ok((total_lines, error_lines))
    }
}

/// Log statistics for a container
#[derive(Debug, Clone, Default)]
pub struct LogStats {
    pub total_size: u64,
    pub line_count: usize,
    pub error_count: usize,
    pub last_modified: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_entry_parsing() {
        let json_line = r#"{"time":"2025-06-30T10:00:00Z","stream":"stdout","log":"Test message\n","attrs":{"level":"info"}}"#;
        let entry = ContainerdLogEntry::from_json_line(json_line, "test-container").unwrap();
        
        assert_eq!(entry.container_id, "test-container");
        assert_eq!(entry.stream, LogStream::Stdout);
        assert_eq!(entry.message, "Test message");
        assert_eq!(entry.level, LogLevel::Info);
    }

    #[test]
    fn test_log_filter_matching() {
        let entry = ContainerdLogEntry {
            timestamp: Utc::now(),
            container_id: "test-container".to_string(),
            stream: LogStream::Stdout,
            level: LogLevel::Error,
            message: "Error message".to_string(),
            attributes: HashMap::new(),
        };

        let filter = LogFilter::errors_only();
        assert!(filter.matches(&entry));

        let filter = LogFilter {
            levels: vec![LogLevel::Info],
            ..Default::default()
        };
        assert!(!filter.matches(&entry));
    }

    #[test]
    fn test_log_filter_creation() {
        let filter = LogFilter::for_container("test-container");
        assert_eq!(filter.container_ids, vec!["test-container"]);
        
        let filter = LogFilter::follow_all();
        assert!(filter.follow);
        assert_eq!(filter.tail, Some(100));
    }

    #[test]
    fn test_rotation_config() {
        let config = LogRotationConfig::default();
        assert_eq!(config.max_size, 100 * 1024 * 1024);
        assert_eq!(config.max_files, 5);
        assert!(config.compress);
    }
}