use bollard::Docker;
use bollard::container::{LogsOptions, LogOutput};
use futures_util::stream::StreamExt;
use tokio::sync::mpsc;
use std::time::SystemTime;
use crate::error::{DockerError, Result};

pub struct LogStreamer {
    docker: Docker,
}

#[derive(Debug, Clone)]
pub struct LogEntry {
    pub timestamp: SystemTime,
    pub container: String,
    pub stream: LogStream,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LogStream {
    Stdout,
    Stderr,
}

impl LogStreamer {
    pub fn new() -> Result<Self> {
        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| DockerError::ConnectionError(e.to_string()))?;
        Ok(Self { docker })
    }
    
    pub async fn get_logs(
        &self,
        container: &str,
        lines: Option<usize>,
        follow: bool,
    ) -> Result<Vec<LogEntry>> {
        let options = LogsOptions::<String> {
            stdout: true,
            stderr: true,
            follow,
            tail: lines.map(|n| n.to_string()).unwrap_or_else(|| "all".to_string()),
            timestamps: true,
            ..Default::default()
        };
        
        let mut stream = self.docker.logs(container, Some(options));
        let mut logs = Vec::new();
        
        while let Some(Ok(output)) = stream.next().await {
            let entry = self.parse_log_output(container, output)?;
            logs.push(entry);
            
            if !follow && logs.len() >= lines.unwrap_or(usize::MAX) {
                break;
            }
        }
        
        Ok(logs)
    }
    
    pub async fn stream_logs(
        &self,
        container: &str,
        tx: mpsc::Sender<LogEntry>,
    ) -> Result<()> {
        let options = LogsOptions::<String> {
            stdout: true,
            stderr: true,
            follow: true,
            timestamps: true,
            ..Default::default()
        };
        
        let mut stream = self.docker.logs(container, Some(options));
        
        while let Some(result) = stream.next().await {
            match result {
                Ok(output) => {
                    let entry = self.parse_log_output(container, output)?;
                    if tx.send(entry).await.is_err() {
                        break;
                    }
                }
                Err(e) => return Err(e.into()),
            }
        }
        
        Ok(())
    }
    
    pub async fn tail_logs(
        &self,
        container: &str,
        lines: usize,
    ) -> Result<Vec<String>> {
        let logs = self.get_logs(container, Some(lines), false).await?;
        Ok(logs.into_iter().map(|entry| entry.message).collect())
    }
    
    pub async fn search_logs(
        &self,
        container: &str,
        pattern: &str,
        lines: Option<usize>,
    ) -> Result<Vec<LogEntry>> {
        let logs = self.get_logs(container, lines, false).await?;
        Ok(logs.into_iter()
            .filter(|entry| entry.message.contains(pattern))
            .collect())
    }
    
    fn parse_log_output(&self, container: &str, output: LogOutput) -> Result<LogEntry> {
        let (stream, message) = match output {
            LogOutput::StdOut { message } => (LogStream::Stdout, message),
            LogOutput::StdErr { message } => (LogStream::Stderr, message),
            LogOutput::Console { message } => (LogStream::Stdout, message),
            LogOutput::StdIn { message } => (LogStream::Stdout, message),
        };
        
        let message = String::from_utf8_lossy(&message).to_string();
        
        Ok(LogEntry {
            timestamp: SystemTime::now(),
            container: container.to_string(),
            stream,
            message: message.trim().to_string(),
        })
    }
    
    pub async fn clear_logs(&self, container: &str) -> Result<()> {
        self.docker.restart_container(container, None).await?;
        Ok(())
    }
}