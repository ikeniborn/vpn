use std::path::Path;
use std::collections::HashMap;
use chrono::{DateTime, Utc, Duration};
use serde::{Deserialize, Serialize};
use regex::Regex;
use vpn_docker::LogStreamer;
use crate::error::{MonitorError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub timestamp: DateTime<Utc>,
    pub level: LogLevel,
    pub source: String,
    pub message: String,
    pub user_id: Option<String>,
    pub ip_address: Option<String>,
    pub bytes_transferred: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogStats {
    pub total_entries: u64,
    pub entries_by_level: HashMap<LogLevel, u64>,
    pub entries_by_source: HashMap<String, u64>,
    pub unique_users: u64,
    pub unique_ips: u64,
    pub total_bytes_transferred: u64,
    pub period_start: DateTime<Utc>,
    pub period_end: DateTime<Utc>,
    pub error_rate: f64,
    pub warning_rate: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
    Critical,
}

#[derive(Debug, Clone)]
pub struct LogAnalysisOptions {
    pub time_range: Option<(DateTime<Utc>, DateTime<Utc>)>,
    pub log_levels: Vec<LogLevel>,
    pub sources: Vec<String>,
    pub user_filter: Option<String>,
    pub ip_filter: Option<String>,
    pub pattern_filter: Option<String>,
}

pub struct LogAnalyzer {
    log_streamer: LogStreamer,
    xray_log_regex: Regex,
    shadowsocks_log_regex: Regex,
}

impl LogAnalyzer {
    pub fn new() -> Result<Self> {
        let log_streamer = LogStreamer::new()?;
        
        // Xray log format: 2024/01/01 12:00:00 [Info] [123456789] accepted tcp:192.168.1.1:12345
        let xray_log_regex = Regex::new(
            r"(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(\w+)\] (?:\[(\w+)\] )?(.+)"
        )?;
        
        // Shadowsocks log format: [2024-01-01T12:00:00Z] INFO [user123] Connection from 192.168.1.1:12345
        let shadowsocks_log_regex = Regex::new(
            r"\[([^\]]+)\] (\w+) (?:\[(\w+)\] )?(.+)"
        )?;
        
        Ok(Self {
            log_streamer,
            xray_log_regex,
            shadowsocks_log_regex,
        })
    }
    
    pub async fn analyze_logs(
        &self,
        install_path: &Path,
        options: LogAnalysisOptions,
    ) -> Result<LogStats> {
        let mut stats = LogStats {
            total_entries: 0,
            entries_by_level: HashMap::new(),
            entries_by_source: HashMap::new(),
            unique_users: 0,
            unique_ips: 0,
            total_bytes_transferred: 0,
            period_start: options.time_range.map(|(start, _)| start).unwrap_or_else(|| Utc::now() - Duration::days(1)),
            period_end: options.time_range.map(|(_, end)| end).unwrap_or_else(|| Utc::now()),
            error_rate: 0.0,
            warning_rate: 0.0,
        };
        
        let mut unique_users = std::collections::HashSet::new();
        let mut unique_ips = std::collections::HashSet::new();
        let mut error_count = 0u64;
        let mut warning_count = 0u64;
        
        // Analyze different log files
        let log_files = [
            ("xray-access", install_path.join("logs/access.log")),
            ("xray-error", install_path.join("logs/error.log")),
            ("shadowbox", install_path.join("logs/shadowbox.log")),
        ];
        
        for (source, log_file) in &log_files {
            if log_file.exists() {
                let entries = self.parse_log_file(log_file, source, &options).await?;
                
                for entry in entries {
                    if self.entry_matches_filters(&entry, &options) {
                        stats.total_entries += 1;
                        
                        // Count by level
                        *stats.entries_by_level.entry(entry.level).or_insert(0) += 1;
                        
                        // Count by source
                        *stats.entries_by_source.entry(entry.source.clone()).or_insert(0) += 1;
                        
                        // Track unique users and IPs
                        if let Some(user_id) = &entry.user_id {
                            unique_users.insert(user_id.clone());
                        }
                        if let Some(ip) = &entry.ip_address {
                            unique_ips.insert(ip.clone());
                        }
                        
                        // Track bytes transferred
                        if let Some(bytes) = entry.bytes_transferred {
                            stats.total_bytes_transferred += bytes;
                        }
                        
                        // Count errors and warnings
                        match entry.level {
                            LogLevel::Error | LogLevel::Critical => error_count += 1,
                            LogLevel::Warning => warning_count += 1,
                            _ => {}
                        }
                    }
                }
            }
        }
        
        stats.unique_users = unique_users.len() as u64;
        stats.unique_ips = unique_ips.len() as u64;
        
        // Calculate rates
        if stats.total_entries > 0 {
            stats.error_rate = (error_count as f64 / stats.total_entries as f64) * 100.0;
            stats.warning_rate = (warning_count as f64 / stats.total_entries as f64) * 100.0;
        }
        
        Ok(stats)
    }
    
    async fn parse_log_file(
        &self,
        log_file: &Path,
        source: &str,
        options: &LogAnalysisOptions,
    ) -> Result<Vec<LogEntry>> {
        let content = tokio::fs::read_to_string(log_file).await?;
        let mut entries = Vec::new();
        
        for line in content.lines() {
            if let Some(entry) = self.parse_log_line(line, source)? {
                // Apply time range filter
                if let Some((start, end)) = options.time_range {
                    if entry.timestamp < start || entry.timestamp > end {
                        continue;
                    }
                }
                
                entries.push(entry);
            }
        }
        
        Ok(entries)
    }
    
    fn parse_log_line(&self, line: &str, source: &str) -> Result<Option<LogEntry>> {
        let entry = if source.starts_with("xray") {
            self.parse_xray_log_line(line, source)?
        } else if source.starts_with("shadowbox") {
            self.parse_shadowsocks_log_line(line, source)?
        } else {
            return Ok(None);
        };
        
        Ok(entry)
    }
    
    fn parse_xray_log_line(&self, line: &str, source: &str) -> Result<Option<LogEntry>> {
        if let Some(captures) = self.xray_log_regex.captures(line) {
            let timestamp_str = &captures[1];
            let level_str = &captures[2];
            let user_id = captures.get(3).map(|m| m.as_str().to_string());
            let message = captures[4].to_string();
            
            // Parse timestamp
            let timestamp = chrono::NaiveDateTime::parse_from_str(
                timestamp_str,
                "%Y/%m/%d %H:%M:%S"
            ).ok().map(|dt| DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc))
            .unwrap_or_else(|| Utc::now());
            
            // Parse log level
            let level = match level_str.to_lowercase().as_str() {
                "debug" => LogLevel::Debug,
                "info" => LogLevel::Info,
                "warning" | "warn" => LogLevel::Warning,
                "error" => LogLevel::Error,
                "critical" | "fatal" => LogLevel::Critical,
                _ => LogLevel::Info,
            };
            
            // Extract IP address from message
            let ip_regex = Regex::new(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})")?;
            let ip_address = ip_regex.find(&message)
                .map(|m| m.as_str().to_string());
            
            // Extract bytes transferred (if present)
            let bytes_regex = Regex::new(r"(\d+) bytes")?;
            let bytes_transferred = bytes_regex.captures(&message)
                .and_then(|caps| caps[1].parse::<u64>().ok());
            
            return Ok(Some(LogEntry {
                timestamp,
                level,
                source: source.to_string(),
                message,
                user_id,
                ip_address,
                bytes_transferred,
            }));
        }
        
        Ok(None)
    }
    
    fn parse_shadowsocks_log_line(&self, line: &str, source: &str) -> Result<Option<LogEntry>> {
        if let Some(captures) = self.shadowsocks_log_regex.captures(line) {
            let timestamp_str = &captures[1];
            let level_str = &captures[2];
            let user_id = captures.get(3).map(|m| m.as_str().to_string());
            let message = captures[4].to_string();
            
            // Parse timestamp (ISO format)
            let timestamp = DateTime::parse_from_rfc3339(timestamp_str)
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(|_| Utc::now());
            
            // Parse log level
            let level = match level_str.to_uppercase().as_str() {
                "DEBUG" => LogLevel::Debug,
                "INFO" => LogLevel::Info,
                "WARN" | "WARNING" => LogLevel::Warning,
                "ERROR" => LogLevel::Error,
                "CRITICAL" | "FATAL" => LogLevel::Critical,
                _ => LogLevel::Info,
            };
            
            // Extract IP address from message
            let ip_regex = Regex::new(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})")?;
            let ip_address = ip_regex.find(&message)
                .map(|m| m.as_str().to_string());
            
            return Ok(Some(LogEntry {
                timestamp,
                level,
                source: source.to_string(),
                message,
                user_id,
                ip_address,
                bytes_transferred: None,
            }));
        }
        
        Ok(None)
    }
    
    fn entry_matches_filters(&self, entry: &LogEntry, options: &LogAnalysisOptions) -> bool {
        // Filter by log level
        if !options.log_levels.is_empty() && !options.log_levels.contains(&entry.level) {
            return false;
        }
        
        // Filter by source
        if !options.sources.is_empty() && !options.sources.contains(&entry.source) {
            return false;
        }
        
        // Filter by user
        if let Some(user_filter) = &options.user_filter {
            if entry.user_id.as_ref() != Some(user_filter) {
                return false;
            }
        }
        
        // Filter by IP
        if let Some(ip_filter) = &options.ip_filter {
            if entry.ip_address.as_ref() != Some(ip_filter) {
                return false;
            }
        }
        
        // Filter by pattern
        if let Some(pattern) = &options.pattern_filter {
            if !entry.message.contains(pattern) {
                return false;
            }
        }
        
        true
    }
    
    pub async fn get_recent_errors(&self, install_path: &Path, hours: u32) -> Result<Vec<LogEntry>> {
        let start_time = Utc::now() - Duration::hours(hours as i64);
        let options = LogAnalysisOptions {
            time_range: Some((start_time, Utc::now())),
            log_levels: vec![LogLevel::Error, LogLevel::Critical],
            sources: vec![],
            user_filter: None,
            ip_filter: None,
            pattern_filter: None,
        };
        
        let _stats = self.analyze_logs(install_path, options).await?;
        
        // This is a simplified implementation - in practice, you'd need to
        // return the actual log entries, not just stats
        Ok(Vec::new())
    }
    
    pub async fn search_logs(
        &self,
        install_path: &Path,
        query: &str,
        _limit: Option<usize>,
    ) -> Result<Vec<LogEntry>> {
        let options = LogAnalysisOptions {
            time_range: None,
            log_levels: vec![],
            sources: vec![],
            user_filter: None,
            ip_filter: None,
            pattern_filter: Some(query.to_string()),
        };
        
        // This would need to be implemented to return actual entries
        let _stats = self.analyze_logs(install_path, options).await?;
        
        // Placeholder implementation
        Ok(Vec::new())
    }
    
    pub async fn tail_logs(
        &self,
        container: &str,
        lines: usize,
    ) -> Result<Vec<String>> {
        self.log_streamer.tail_logs(container, lines).await
            .map_err(|e| MonitorError::LogAnalysisError(e.to_string()))
    }
    
    pub fn generate_log_report(&self, stats: &LogStats) -> String {
        let mut report = String::new();
        
        report.push_str(&format!("Log Analysis Report\n"));
        report.push_str(&format!("Period: {} to {}\n", 
            stats.period_start.format("%Y-%m-%d %H:%M:%S"),
            stats.period_end.format("%Y-%m-%d %H:%M:%S")
        ));
        report.push_str(&format!("Total entries: {}\n", stats.total_entries));
        report.push_str(&format!("Unique users: {}\n", stats.unique_users));
        report.push_str(&format!("Unique IPs: {}\n", stats.unique_ips));
        report.push_str(&format!("Total bytes transferred: {}\n", Self::format_bytes(stats.total_bytes_transferred)));
        report.push_str(&format!("Error rate: {:.2}%\n", stats.error_rate));
        report.push_str(&format!("Warning rate: {:.2}%\n", stats.warning_rate));
        
        report.push_str("\nEntries by level:\n");
        for (level, count) in &stats.entries_by_level {
            report.push_str(&format!("  {}: {}\n", level.as_str(), count));
        }
        
        report.push_str("\nEntries by source:\n");
        for (source, count) in &stats.entries_by_source {
            report.push_str(&format!("  {}: {}\n", source, count));
        }
        
        report
    }
    
    fn format_bytes(bytes: u64) -> String {
        const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
        const THRESHOLD: f64 = 1024.0;
        
        if bytes == 0 {
            return "0 B".to_string();
        }
        
        let mut size = bytes as f64;
        let mut unit_index = 0;
        
        while size >= THRESHOLD && unit_index < UNITS.len() - 1 {
            size /= THRESHOLD;
            unit_index += 1;
        }
        
        format!("{:.2} {}", size, UNITS[unit_index])
    }
}

impl LogLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warning => "warning",
            LogLevel::Error => "error",
            LogLevel::Critical => "critical",
        }
    }
    
    pub fn severity(&self) -> u8 {
        match self {
            LogLevel::Debug => 0,
            LogLevel::Info => 1,
            LogLevel::Warning => 2,
            LogLevel::Error => 3,
            LogLevel::Critical => 4,
        }
    }
}

impl Default for LogAnalysisOptions {
    fn default() -> Self {
        Self {
            time_range: None,
            log_levels: vec![],
            sources: vec![],
            user_filter: None,
            ip_filter: None,
            pattern_filter: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_xray_log_parsing() {
        let analyzer = LogAnalyzer::new().unwrap();
        let line = "2024/01/01 12:00:00 [Info] [123456789] accepted tcp:192.168.1.1:12345";
        
        let entry = analyzer.parse_xray_log_line(line, "xray-access").unwrap();
        assert!(entry.is_some());
        
        let entry = entry.unwrap();
        assert_eq!(entry.level, LogLevel::Info);
        assert_eq!(entry.user_id, Some("123456789".to_string()));
        assert_eq!(entry.ip_address, Some("192.168.1.1".to_string()));
    }
    
    #[test]
    fn test_log_level_severity() {
        assert!(LogLevel::Critical.severity() > LogLevel::Error.severity());
        assert!(LogLevel::Error.severity() > LogLevel::Warning.severity());
        assert!(LogLevel::Warning.severity() > LogLevel::Info.severity());
        assert!(LogLevel::Info.severity() > LogLevel::Debug.severity());
    }
}