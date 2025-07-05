use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Runtime configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeConfig {
    pub runtime_type: RuntimeType,
    pub socket_path: Option<String>,
    pub namespace: Option<String>,
    pub timeout: Duration,
    pub max_connections: usize,
    pub docker: Option<DockerConfig>,
    pub containerd: Option<ContainerdConfig>,
    pub fallback_enabled: bool,
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            runtime_type: RuntimeType::Auto,
            socket_path: None,
            namespace: None,
            timeout: Duration::from_secs(30),
            max_connections: 10,
            docker: None,
            containerd: Some(ContainerdConfig::default()),
            fallback_enabled: true,
        }
    }
}

/// Runtime type selection
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RuntimeType {
    Docker,
    Containerd,
    Auto, // Automatic detection
}

/// Docker-specific configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerConfig {
    pub socket_path: String,
    pub api_version: Option<String>,
    pub timeout_seconds: u64,
    pub max_connections: usize,
}

impl Default for DockerConfig {
    fn default() -> Self {
        Self {
            socket_path: "/var/run/docker.sock".to_string(),
            api_version: None,
            timeout_seconds: 30,
            max_connections: 10,
        }
    }
}

/// containerd-specific configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerdConfig {
    pub socket_path: String,
    pub namespace: String,
    pub timeout_seconds: u64,
    pub max_connections: usize,
    pub snapshotter: String,
    pub runtime: String,
}

impl Default for ContainerdConfig {
    fn default() -> Self {
        Self {
            socket_path: "/run/containerd/containerd.sock".to_string(),
            namespace: "default".to_string(),
            timeout_seconds: 30,
            max_connections: 10,
            snapshotter: "overlayfs".to_string(),
            runtime: "io.containerd.runc.v2".to_string(),
        }
    }
}

impl RuntimeConfig {
    /// Create configuration for Docker runtime
    pub fn docker() -> Self {
        Self {
            runtime_type: RuntimeType::Docker,
            docker: Some(DockerConfig::default()),
            ..Default::default()
        }
    }

    /// Create configuration for containerd runtime
    pub fn containerd() -> Self {
        Self {
            runtime_type: RuntimeType::Containerd,
            containerd: Some(ContainerdConfig::default()),
            ..Default::default()
        }
    }

    /// Create configuration with auto-detection
    pub fn auto() -> Self {
        Self {
            runtime_type: RuntimeType::Auto,
            docker: Some(DockerConfig::default()),
            containerd: Some(ContainerdConfig::default()),
            fallback_enabled: true,
            ..Default::default()
        }
    }

    /// Get effective socket path for the runtime type
    pub fn effective_socket_path(&self) -> String {
        if let Some(path) = &self.socket_path {
            return path.clone();
        }

        match self.runtime_type {
            RuntimeType::Docker => self
                .docker
                .as_ref()
                .map(|c| c.socket_path.clone())
                .unwrap_or_else(|| "/var/run/docker.sock".to_string()),
            RuntimeType::Containerd => self
                .containerd
                .as_ref()
                .map(|c| c.socket_path.clone())
                .unwrap_or_else(|| "/run/containerd/containerd.sock".to_string()),
            RuntimeType::Auto => "/run/containerd/containerd.sock".to_string(),
        }
    }

    /// Get effective namespace
    pub fn effective_namespace(&self) -> String {
        if let Some(namespace) = &self.namespace {
            return namespace.clone();
        }

        match self.runtime_type {
            RuntimeType::Containerd => self
                .containerd
                .as_ref()
                .map(|c| c.namespace.clone())
                .unwrap_or_else(|| "default".to_string()),
            _ => "default".to_string(),
        }
    }

    /// Get effective timeout
    pub fn effective_timeout(&self) -> Duration {
        self.timeout
    }

    /// Get effective max connections
    pub fn effective_max_connections(&self) -> usize {
        self.max_connections
    }
}
