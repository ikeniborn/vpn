use crate::error::{DockerError, Result};
use bollard::container::{LogOutput, LogsOptions};
use bollard::Docker;
use futures_util::stream::StreamExt;
use std::time::SystemTime;
use tokio::sync::mpsc;

/// Docker container log streaming service
///
/// Provides functionality to retrieve and stream logs from Docker containers
/// with support for filtering, following, and real-time log streaming.
///
/// # Examples
///
/// ```rust,no_run
/// use vpn_docker::LogStreamer;
///
/// #[tokio::main]
/// async fn main() -> Result<(), Box<dyn std::error::Error>> {
///     let log_streamer = LogStreamer::new()?;
///     
///     // Get recent logs
///     let logs = log_streamer.get_logs("vpn-server", Some(100), false).await?;
///     for entry in logs {
///         println!("[{}] {}: {}", entry.timestamp.elapsed().unwrap().as_secs(),
///                  entry.container, entry.message);
///     }
///     
///     Ok(())
/// }
/// ```
pub struct LogStreamer {
    docker: Docker,
}

/// A single log entry from a Docker container
///
/// Contains the log message along with metadata about when it was created,
/// which container it came from, and which stream (stdout/stderr) it originated from.
#[derive(Debug, Clone)]
pub struct LogEntry {
    /// When the log entry was created
    pub timestamp: SystemTime,
    /// Name of the container that generated this log
    pub container: String,
    /// Which output stream this log came from
    pub stream: LogStream,
    /// The actual log message content
    pub message: String,
}

/// The output stream that a log entry originated from
///
/// Docker containers have two standard output streams that can be monitored separately.
#[derive(Debug, Clone, PartialEq)]
pub enum LogStream {
    /// Standard output stream (stdout)
    Stdout,
    /// Standard error stream (stderr)
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
            tail: lines
                .map(|n| n.to_string())
                .unwrap_or_else(|| "all".to_string()),
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

    pub async fn stream_logs(&self, container: &str, tx: mpsc::Sender<LogEntry>) -> Result<()> {
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
                        // Channel closed, stop streaming
                        break;
                    }
                }
                Err(e) => {
                    // Explicitly drop stream before returning error
                    drop(stream);
                    return Err(e.into());
                }
            }
        }

        // Ensure stream is dropped to free resources
        drop(stream);
        Ok(())
    }

    pub async fn tail_logs(&self, container: &str, lines: usize) -> Result<Vec<String>> {
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
        Ok(logs
            .into_iter()
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
