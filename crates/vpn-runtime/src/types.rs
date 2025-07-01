use chrono::{DateTime, Utc};
use futures_util::Stream;
use pin_project::pin_project;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use crate::error::RuntimeError;

/// Container specification for creation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerSpec {
    pub name: String,
    pub image: String,
    pub command: Option<Vec<String>>,
    pub args: Option<Vec<String>>,
    pub environment: HashMap<String, String>,
    pub volumes: Vec<VolumeMount>,
    pub ports: Vec<PortMapping>,
    pub networks: Vec<String>,
    pub labels: HashMap<String, String>,
    pub working_dir: Option<String>,
    pub user: Option<String>,
    pub restart_policy: RestartPolicy,
}

impl Default for ContainerSpec {
    fn default() -> Self {
        Self {
            name: String::new(),
            image: String::new(),
            command: None,
            args: None,
            environment: HashMap::new(),
            volumes: Vec::new(),
            ports: Vec::new(),
            networks: Vec::new(),
            labels: HashMap::new(),
            working_dir: None,
            user: None,
            restart_policy: RestartPolicy::No,
        }
    }
}

/// Volume mount specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeMount {
    pub source: String,
    pub target: String,
    pub read_only: bool,
    pub mount_type: MountType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MountType {
    Bind,
    Volume,
    Tmpfs,
}

/// Port mapping specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortMapping {
    pub host_port: u16,
    pub container_port: u16,
    pub protocol: Protocol,
    pub host_ip: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Protocol {
    Tcp,
    Udp,
}

/// Container restart policy
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RestartPolicy {
    No,
    Always,
    OnFailure { max_retry_count: Option<u32> },
    UnlessStopped,
}

/// Container state
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ContainerState {
    Created,
    Running,
    Paused,
    Restarting,
    Removing,
    Exited,
    Dead,
    Unknown,
}

/// Container status information
#[derive(Debug, Clone)]
pub struct ContainerStatus {
    pub state: ContainerState,
    pub started_at: Option<DateTime<Utc>>,
    pub finished_at: Option<DateTime<Utc>>,
    pub exit_code: Option<i32>,
    pub error: Option<String>,
}

/// Container statistics
#[derive(Debug, Clone)]
pub struct ContainerStats {
    pub cpu_percent: f64,
    pub memory_usage: u64,
    pub memory_limit: u64,
    pub memory_percent: f64,
    pub network_rx: u64,
    pub network_tx: u64,
    pub block_read: u64,
    pub block_write: u64,
    pub pids: u64,
}

/// Container information
pub trait Container: Send + Sync {
    fn id(&self) -> &str;
    fn name(&self) -> &str;
    fn image(&self) -> &str;
    fn state(&self) -> ContainerState;
    fn status(&self) -> &ContainerStatus;
    fn labels(&self) -> &HashMap<String, String>;
    fn created_at(&self) -> DateTime<Utc>;
}

/// Task (running container process) information
pub trait Task: Send + Sync {
    fn id(&self) -> &str;
    fn container_id(&self) -> &str;
    fn pid(&self) -> Option<u32>;
    fn status(&self) -> TaskStatus;
    fn exit_code(&self) -> Option<i32>;
}

/// Task status
#[derive(Debug, Clone, PartialEq)]
pub enum TaskStatus {
    Created,
    Running,
    Stopped,
    Paused,
    Unknown,
}

/// Container filter for listing
#[derive(Debug, Clone, Default)]
pub struct ContainerFilter {
    pub names: Vec<String>,
    pub labels: HashMap<String, String>,
    pub states: Vec<ContainerState>,
    pub all: bool,
}

/// Log level enumeration
#[derive(Debug, Clone, PartialEq)]
pub enum LogLevel {
    Error,
    Warn,
    Info,
    Debug,
    Trace,
}

impl std::fmt::Display for LogLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LogLevel::Error => write!(f, "ERROR"),
            LogLevel::Warn => write!(f, "WARN"),
            LogLevel::Info => write!(f, "INFO"),
            LogLevel::Debug => write!(f, "DEBUG"),
            LogLevel::Trace => write!(f, "TRACE"),
        }
    }
}

/// Log entry from container
#[derive(Debug, Clone)]
pub struct LogEntry {
    pub timestamp: DateTime<Utc>,
    pub stream: LogStreamType,
    pub message: String,
}

/// Log stream type
#[derive(Debug, Clone, PartialEq)]
pub enum LogStreamType {
    Stdout,
    Stderr,
}

/// Log options for streaming
#[derive(Debug, Clone)]
pub struct LogOptions {
    pub follow: bool,
    pub stdout: bool,
    pub stderr: bool,
    pub timestamps: bool,
    pub since: Option<DateTime<Utc>>,
    pub until: Option<DateTime<Utc>>,
    pub tail: Option<usize>,
}

impl Default for LogOptions {
    fn default() -> Self {
        Self {
            follow: false,
            stdout: true,
            stderr: true,
            timestamps: false,
            since: None,
            until: None,
            tail: None,
        }
    }
}

/// Log stream type alias
pub type LogStream = Pin<Box<dyn Stream<Item = Result<LogEntry, RuntimeError>> + Send>>;

/// Command execution result
#[derive(Debug)]
pub struct ExecResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Batch operation options
#[derive(Debug, Clone)]
pub struct BatchOptions {
    pub max_concurrent: usize,
    pub timeout: Duration,
    pub fail_fast: bool,
}

impl Default for BatchOptions {
    fn default() -> Self {
        Self {
            max_concurrent: 5,
            timeout: Duration::from_secs(60),
            fail_fast: false,
        }
    }
}

/// Batch operation result
#[derive(Debug)]
pub struct BatchResult {
    pub successful: Vec<String>,
    pub failed: HashMap<String, String>,
    pub total_duration: Duration,
}

impl BatchResult {
    pub fn new() -> Self {
        Self {
            successful: Vec::new(),
            failed: HashMap::new(),
            total_duration: Duration::from_secs(0),
        }
    }

    pub fn add_success(&mut self, id: String) {
        self.successful.push(id);
    }

    pub fn add_failure(&mut self, id: String, error: String) {
        self.failed.insert(id, error);
    }

    pub fn set_duration(&mut self, duration: Duration) {
        self.total_duration = duration;
    }

    pub fn is_success(&self) -> bool {
        self.failed.is_empty()
    }

    pub fn success_count(&self) -> usize {
        self.successful.len()
    }

    pub fn failure_count(&self) -> usize {
        self.failed.len()
    }
}

/// Volume specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeSpec {
    pub name: String,
    pub driver: String,
    pub driver_opts: HashMap<String, String>,
    pub labels: HashMap<String, String>,
}

impl Default for VolumeSpec {
    fn default() -> Self {
        Self {
            name: String::new(),
            driver: "local".to_string(),
            driver_opts: HashMap::new(),
            labels: HashMap::new(),
        }
    }
}

/// Volume information
pub trait Volume: Send + Sync {
    fn name(&self) -> &str;
    fn driver(&self) -> &str;
    fn mount_point(&self) -> Option<&str>;
    fn labels(&self) -> &HashMap<String, String>;
    fn created_at(&self) -> DateTime<Utc>;
}

/// Volume filter for listing
#[derive(Debug, Clone, Default)]
pub struct VolumeFilter {
    pub names: Vec<String>,
    pub labels: HashMap<String, String>,
    pub drivers: Vec<String>,
}

/// Image information
pub trait Image: Send + Sync {
    fn id(&self) -> &str;
    fn tags(&self) -> &[String];
    fn size(&self) -> u64;
    fn created_at(&self) -> DateTime<Utc>;
    fn labels(&self) -> &HashMap<String, String>;
}

/// Image filter for listing
#[derive(Debug, Clone, Default)]
pub struct ImageFilter {
    pub reference: Option<String>,
    pub labels: HashMap<String, String>,
}

/// Event from the runtime
#[derive(Debug, Clone)]
pub struct RuntimeEvent {
    pub timestamp: DateTime<Utc>,
    pub event_type: EventType,
    pub container_id: Option<String>,
    pub image: Option<String>,
    pub message: String,
    pub attributes: HashMap<String, String>,
}

/// Event types
#[derive(Debug, Clone, PartialEq)]
pub enum EventType {
    ContainerCreate,
    ContainerStart,
    ContainerStop,
    ContainerRemove,
    ContainerDie,
    ImagePull,
    ImageRemove,
    VolumeCreate,
    VolumeRemove,
    TaskStart,
    TaskExit,
    Other(String),
}

/// Event stream type alias
pub type EventStream = Pin<Box<dyn Stream<Item = Result<RuntimeEvent, RuntimeError>> + Send>>;

/// Streaming wrapper for async streams
#[pin_project]
pub struct RuntimeStream<S> {
    #[pin]
    inner: S,
}

impl<S> RuntimeStream<S> {
    pub fn new(stream: S) -> Self {
        Self { inner: stream }
    }
}

impl<S> Stream for RuntimeStream<S>
where
    S: Stream,
{
    type Item = S::Item;

    fn poll_next(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Self::Item>> {
        self.project().inner.poll_next(cx)
    }
}