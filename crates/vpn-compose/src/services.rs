//! Service management for Docker Compose

use crate::config::{ServiceConfig, VolumeMount, PortMapping, HealthCheck, RestartPolicy};
use crate::error::{ComposeError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Service manager for Docker Compose services
pub struct ServiceManager {
    services: HashMap<String, ServiceDefinition>,
}

impl ServiceManager {
    /// Create a new service manager
    pub fn new() -> Self {
        Self {
            services: HashMap::new(),
        }
    }

    /// Add a service definition
    pub fn add_service(&mut self, name: String, definition: ServiceDefinition) {
        self.services.insert(name, definition);
    }

    /// Get a service definition
    pub fn get_service(&self, name: &str) -> Option<&ServiceDefinition> {
        self.services.get(name)
    }

    /// Get all services
    pub fn get_all_services(&self) -> &HashMap<String, ServiceDefinition> {
        &self.services
    }

    /// Remove a service
    pub fn remove_service(&mut self, name: &str) -> Option<ServiceDefinition> {
        self.services.remove(name)
    }

    /// Create VPN server service definition
    pub fn create_vpn_server_service() -> ServiceDefinition {
        ServiceDefinition {
            image: "ghcr.io/xtls/xray-core:latest".to_string(),
            container_name: Some("vpn-server".to_string()),
            restart: RestartPolicy::UnlessStopped,
            ports: vec![
                PortMapping::tcp(8443, 8443),
                PortMapping::tcp(443, 443),
            ],
            volumes: vec![
                VolumeMount::new("vpn-config", "/etc/xray"),
                VolumeMount::new("vpn-logs", "/var/log/xray"),
                VolumeMount::read_only("./configs/xray", "/etc/xray/configs"),
            ],
            environment: {
                let mut env = HashMap::new();
                env.insert("XRAY_VMESS_ALTID".to_string(), "0".to_string());
                env.insert("XRAY_LOG_LEVEL".to_string(), "${LOG_LEVEL:-warning}".to_string());
                env
            },
            depends_on: vec!["postgres".to_string(), "redis".to_string()],
            healthcheck: Some(HealthCheck::cmd_shell(
                "wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1"
            )),
            networks: vec!["vpn-network".to_string(), "vpn-internal".to_string()],
            security_opt: vec!["no-new-privileges:true".to_string()],
            cap_drop: vec!["ALL".to_string()],
            cap_add: vec!["NET_BIND_SERVICE".to_string()],
            labels: {
                let mut labels = HashMap::new();
                labels.insert("service.type".to_string(), "vpn-server".to_string());
                labels.insert("service.role".to_string(), "core".to_string());
                labels
            },
            deploy: Some(DeployConfig {
                replicas: Some(1),
                resources: Some(ResourcesConfig {
                    limits: Some(ResourceLimits {
                        memory: Some("512M".to_string()),
                        cpus: Some("0.5".to_string()),
                    }),
                    reservations: Some(ResourceLimits {
                        memory: Some("256M".to_string()),
                        cpus: Some("0.25".to_string()),
                    }),
                }),
                restart_policy: Some(RestartPolicyConfig {
                    condition: "on-failure".to_string(),
                    delay: Some("5s".to_string()),
                    max_attempts: Some(3),
                    window: Some("120s".to_string()),
                }),
                update_config: Some(UpdateConfig {
                    parallelism: Some(1),
                    delay: Some("10s".to_string()),
                    failure_action: Some("rollback".to_string()),
                }),
            }),
            logging: Some(LoggingConfig {
                driver: "json-file".to_string(),
                options: {
                    let mut opts = HashMap::new();
                    opts.insert("max-size".to_string(), "10m".to_string());
                    opts.insert("max-file".to_string(), "3".to_string());
                    opts
                },
            }),
            tmpfs: vec!["/tmp:noexec,nosuid,size=64m".to_string()],
            read_only: false,
            user: None,
            working_dir: None,
            command: None,
            entrypoint: None,
            expose: vec![],
            external_links: vec![],
            extra_hosts: vec![],
            hostname: None,
            domainname: None,
            mac_address: None,
            privileged: false,
            stdin_open: false,
            tty: false,
        }
    }

    /// Create Nginx proxy service definition
    pub fn create_nginx_proxy_service() -> ServiceDefinition {
        ServiceDefinition {
            image: "nginx:alpine".to_string(),
            container_name: Some("nginx-proxy".to_string()),
            restart: RestartPolicy::UnlessStopped,
            ports: vec![
                PortMapping::tcp(80, 80),
                PortMapping::tcp(443, 443),
            ],
            volumes: vec![
                VolumeMount::read_only("./configs/nginx", "/etc/nginx/conf.d"),
                VolumeMount::read_only("nginx-certs", "/etc/nginx/certs"),
                VolumeMount::new("vpn-logs", "/var/log/nginx"),
            ],
            environment: {
                let mut env = HashMap::new();
                env.insert("NGINX_HOST".to_string(), "${DOMAIN_NAME:-vpn.example.com}".to_string());
                env.insert("NGINX_PORT".to_string(), "80".to_string());
                env
            },
            depends_on: vec!["vpn-server".to_string()],
            healthcheck: Some(HealthCheck::cmd_shell(
                "wget --quiet --tries=1 --spider http://localhost/health || exit 1"
            )),
            networks: vec!["vpn-network".to_string()],
            security_opt: vec!["no-new-privileges:true".to_string()],
            cap_drop: vec!["ALL".to_string()],
            cap_add: vec!["CHOWN".to_string(), "SETGID".to_string(), "SETUID".to_string()],
            labels: {
                let mut labels = HashMap::new();
                labels.insert("service.type".to_string(), "proxy".to_string());
                labels.insert("service.role".to_string(), "edge".to_string());
                labels
            },
            deploy: Some(DeployConfig {
                replicas: Some(1),
                resources: Some(ResourcesConfig {
                    limits: Some(ResourceLimits {
                        memory: Some("256M".to_string()),
                        cpus: Some("0.25".to_string()),
                    }),
                    reservations: Some(ResourceLimits {
                        memory: Some("128M".to_string()),
                        cpus: Some("0.1".to_string()),
                    }),
                }),
                restart_policy: Some(RestartPolicyConfig {
                    condition: "on-failure".to_string(),
                    delay: Some("5s".to_string()),
                    max_attempts: Some(3),
                    window: None,
                }),
                update_config: None,
            }),
            logging: Some(LoggingConfig {
                driver: "json-file".to_string(),
                options: {
                    let mut opts = HashMap::new();
                    opts.insert("max-size".to_string(), "10m".to_string());
                    opts.insert("max-file".to_string(), "3".to_string());
                    opts
                },
            }),
            tmpfs: vec![
                "/var/cache/nginx:noexec,nosuid,size=64m".to_string(),
                "/var/run:noexec,nosuid,size=32m".to_string(),
            ],
            read_only: false,
            user: None,
            working_dir: None,
            command: None,
            entrypoint: None,
            expose: vec![],
            external_links: vec![],
            extra_hosts: vec![],
            hostname: None,
            domainname: None,
            mac_address: None,
            privileged: false,
            stdin_open: false,
            tty: false,
        }
    }

    /// Create PostgreSQL database service definition
    pub fn create_postgres_service() -> ServiceDefinition {
        ServiceDefinition {
            image: "postgres:15-alpine".to_string(),
            container_name: Some("vpn-postgres".to_string()),
            restart: RestartPolicy::UnlessStopped,
            ports: vec![],
            volumes: vec![
                VolumeMount::new("postgres-data", "/var/lib/postgresql/data"),
                VolumeMount::read_only("./configs/postgres/init", "/docker-entrypoint-initdb.d"),
            ],
            environment: {
                let mut env = HashMap::new();
                env.insert("POSTGRES_DB".to_string(), "${POSTGRES_DB:-vpndb}".to_string());
                env.insert("POSTGRES_USER".to_string(), "${POSTGRES_USER:-vpnuser}".to_string());
                env.insert("POSTGRES_PASSWORD".to_string(), "${POSTGRES_PASSWORD:-changepassword}".to_string());
                env.insert("POSTGRES_INITDB_ARGS".to_string(), "--auth-host=scram-sha-256".to_string());
                env
            },
            depends_on: vec![],
            healthcheck: Some(HealthCheck::cmd_shell(
                "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"
            )),
            networks: vec!["vpn-internal".to_string()],
            security_opt: vec!["no-new-privileges:true".to_string()],
            cap_drop: vec!["ALL".to_string()],
            cap_add: vec!["CHOWN".to_string(), "DAC_OVERRIDE".to_string(), "SETGID".to_string(), "SETUID".to_string()],
            labels: {
                let mut labels = HashMap::new();
                labels.insert("service.type".to_string(), "database".to_string());
                labels.insert("service.role".to_string(), "data".to_string());
                labels
            },
            deploy: Some(DeployConfig {
                replicas: Some(1),
                resources: Some(ResourcesConfig {
                    limits: Some(ResourceLimits {
                        memory: Some("512M".to_string()),
                        cpus: Some("0.5".to_string()),
                    }),
                    reservations: Some(ResourceLimits {
                        memory: Some("256M".to_string()),
                        cpus: Some("0.25".to_string()),
                    }),
                }),
                restart_policy: Some(RestartPolicyConfig {
                    condition: "on-failure".to_string(),
                    delay: Some("5s".to_string()),
                    max_attempts: Some(3),
                    window: None,
                }),
                update_config: None,
            }),
            logging: Some(LoggingConfig {
                driver: "json-file".to_string(),
                options: {
                    let mut opts = HashMap::new();
                    opts.insert("max-size".to_string(), "10m".to_string());
                    opts.insert("max-file".to_string(), "3".to_string());
                    opts
                },
            }),
            tmpfs: vec![],
            read_only: false,
            user: None,
            working_dir: None,
            command: None,
            entrypoint: None,
            expose: vec![],
            external_links: vec![],
            extra_hosts: vec![],
            hostname: None,
            domainname: None,
            mac_address: None,
            privileged: false,
            stdin_open: false,
            tty: false,
        }
    }

    /// Create Redis service definition
    pub fn create_redis_service() -> ServiceDefinition {
        ServiceDefinition {
            image: "redis:7-alpine".to_string(),
            container_name: Some("vpn-redis".to_string()),
            restart: RestartPolicy::UnlessStopped,
            ports: vec![],
            volumes: vec![
                VolumeMount::read_only("./configs/redis/redis.conf", "/etc/redis/redis.conf"),
            ],
            environment: HashMap::new(),
            depends_on: vec![],
            healthcheck: Some(HealthCheck::cmd_shell(
                "redis-cli --no-auth-warning -a $${REDIS_PASSWORD:-changepassword} ping | grep PONG"
            )),
            networks: vec!["vpn-internal".to_string()],
            security_opt: vec!["no-new-privileges:true".to_string()],
            cap_drop: vec!["ALL".to_string()],
            cap_add: vec!["SETGID".to_string(), "SETUID".to_string()],
            labels: {
                let mut labels = HashMap::new();
                labels.insert("service.type".to_string(), "cache".to_string());
                labels.insert("service.role".to_string(), "data".to_string());
                labels
            },
            deploy: Some(DeployConfig {
                replicas: Some(1),
                resources: Some(ResourcesConfig {
                    limits: Some(ResourceLimits {
                        memory: Some("128M".to_string()),
                        cpus: Some("0.25".to_string()),
                    }),
                    reservations: Some(ResourceLimits {
                        memory: Some("64M".to_string()),
                        cpus: Some("0.1".to_string()),
                    }),
                }),
                restart_policy: Some(RestartPolicyConfig {
                    condition: "on-failure".to_string(),
                    delay: Some("5s".to_string()),
                    max_attempts: Some(3),
                    window: None,
                }),
                update_config: None,
            }),
            logging: Some(LoggingConfig {
                driver: "json-file".to_string(),
                options: {
                    let mut opts = HashMap::new();
                    opts.insert("max-size".to_string(), "10m".to_string());
                    opts.insert("max-file".to_string(), "3".to_string());
                    opts
                },
            }),
            tmpfs: vec![],
            read_only: false,
            user: None,
            working_dir: None,
            command: Some(vec![
                "redis-server".to_string(),
                "--appendonly".to_string(),
                "yes".to_string(),
                "--requirepass".to_string(),
                "${REDIS_PASSWORD:-changepassword}".to_string(),
            ]),
            entrypoint: None,
            expose: vec![],
            external_links: vec![],
            extra_hosts: vec![],
            hostname: None,
            domainname: None,
            mac_address: None,
            privileged: false,
            stdin_open: false,
            tty: false,
        }
    }

    /// Load predefined service definitions
    pub fn load_predefined_services(&mut self) {
        self.add_service("vpn-server".to_string(), Self::create_vpn_server_service());
        self.add_service("nginx-proxy".to_string(), Self::create_nginx_proxy_service());
        self.add_service("postgres".to_string(), Self::create_postgres_service());
        self.add_service("redis".to_string(), Self::create_redis_service());
    }

    /// Validate service dependencies
    pub fn validate_dependencies(&self) -> Result<()> {
        for (service_name, service) in &self.services {
            for dependency in &service.depends_on {
                if !self.services.contains_key(dependency) {
                    return Err(ComposeError::dependency_error(service_name, dependency));
                }
            }
        }
        Ok(())
    }

    /// Get services in dependency order
    pub fn get_services_in_order(&self) -> Result<Vec<String>> {
        let mut ordered = Vec::new();
        let mut visited = std::collections::HashSet::new();
        let mut visiting = std::collections::HashSet::new();

        fn visit(
            service_name: &str,
            services: &HashMap<String, ServiceDefinition>,
            ordered: &mut Vec<String>,
            visited: &mut std::collections::HashSet<String>,
            visiting: &mut std::collections::HashSet<String>,
        ) -> Result<()> {
            if visiting.contains(service_name) {
                return Err(ComposeError::dependency_error(
                    service_name.to_string(),
                    "circular dependency detected".to_string(),
                ));
            }
            
            if visited.contains(service_name) {
                return Ok(());
            }

            visiting.insert(service_name.to_string());

            if let Some(service) = services.get(service_name) {
                for dependency in &service.depends_on {
                    visit(dependency, services, ordered, visited, visiting)?;
                }
            }

            visiting.remove(service_name);
            visited.insert(service_name.to_string());
            ordered.push(service_name.to_string());

            Ok(())
        }

        for service_name in self.services.keys() {
            visit(service_name, &self.services, &mut ordered, &mut visited, &mut visiting)?;
        }

        Ok(ordered)
    }
}

/// Complete service definition for Docker Compose
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceDefinition {
    pub image: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub container_name: Option<String>,
    pub restart: RestartPolicy,
    pub ports: Vec<PortMapping>,
    pub volumes: Vec<VolumeMount>,
    pub environment: HashMap<String, String>,
    pub depends_on: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub healthcheck: Option<HealthCheck>,
    pub networks: Vec<String>,
    pub security_opt: Vec<String>,
    pub cap_drop: Vec<String>,
    pub cap_add: Vec<String>,
    pub labels: HashMap<String, String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deploy: Option<DeployConfig>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logging: Option<LoggingConfig>,
    pub tmpfs: Vec<String>,
    pub read_only: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub working_dir: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entrypoint: Option<Vec<String>>,
    pub expose: Vec<String>,
    pub external_links: Vec<String>,
    pub extra_hosts: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hostname: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domainname: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mac_address: Option<String>,
    pub privileged: bool,
    pub stdin_open: bool,
    pub tty: bool,
}

/// Docker Swarm deployment configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeployConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replicas: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resources: Option<ResourcesConfig>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub restart_policy: Option<RestartPolicyConfig>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub update_config: Option<UpdateConfig>,
}

/// Resource configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourcesConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limits: Option<ResourceLimits>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reservations: Option<ResourceLimits>,
}

/// Resource limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memory: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cpus: Option<String>,
}

/// Restart policy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestartPolicyConfig {
    pub condition: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delay: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_attempts: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub window: Option<String>,
}

/// Update configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parallelism: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delay: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure_action: Option<String>,
}

/// Logging configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    pub driver: String,
    pub options: HashMap<String, String>,
}

/// Service status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub name: String,
    pub status: String,
    pub health: Option<String>,
    pub uptime: Option<String>,
    pub image: String,
    pub ports: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_service_manager_creation() {
        let manager = ServiceManager::new();
        assert_eq!(manager.services.len(), 0);
    }

    #[test]
    fn test_predefined_services() {
        let mut manager = ServiceManager::new();
        manager.load_predefined_services();
        
        assert!(manager.get_service("vpn-server").is_some());
        assert!(manager.get_service("nginx-proxy").is_some());
        assert!(manager.get_service("postgres").is_some());
        assert!(manager.get_service("redis").is_some());
    }

    #[test]
    fn test_dependency_validation() {
        let mut manager = ServiceManager::new();
        manager.load_predefined_services();
        
        let result = manager.validate_dependencies();
        assert!(result.is_ok());
    }

    #[test]
    fn test_service_ordering() {
        let mut manager = ServiceManager::new();
        manager.load_predefined_services();
        
        let result = manager.get_services_in_order();
        assert!(result.is_ok());
        
        let ordered = result.unwrap();
        let postgres_pos = ordered.iter().position(|s| s == "postgres").unwrap();
        let vpn_server_pos = ordered.iter().position(|s| s == "vpn-server").unwrap();
        
        // postgres should come before vpn-server
        assert!(postgres_pos < vpn_server_pos);
    }

    #[test]
    fn test_vpn_server_service() {
        let service = ServiceManager::create_vpn_server_service();
        assert_eq!(service.image, "ghcr.io/xtls/xray-core:latest");
        assert!(service.depends_on.contains(&"postgres".to_string()));
        assert!(service.depends_on.contains(&"redis".to_string()));
    }
}