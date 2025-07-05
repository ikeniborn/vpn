//! High Availability management for Docker Compose deployments

use crate::config::ComposeConfig;
use crate::environment::Environment;
use crate::error::{ComposeError, Result};
use crate::generator::ComposeGenerator;
use crate::manager::ComposeManager;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info, warn};

/// High Availability configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HAConfig {
    /// Enable high availability features
    pub enabled: bool,

    /// Number of VPN server replicas
    pub vpn_replicas: u32,

    /// Number of API replicas
    pub api_replicas: u32,

    /// Number of Nginx replicas
    pub nginx_replicas: u32,

    /// Virtual IP address for load balancer
    pub virtual_ip: String,

    /// Enable automatic failover
    pub auto_failover: bool,

    /// Health check interval in seconds
    pub health_check_interval: u32,

    /// Failover timeout in seconds
    pub failover_timeout: u32,

    /// Enable service discovery via Consul
    pub service_discovery: bool,

    /// Enable Redis Sentinel for cache HA
    pub redis_sentinel: bool,

    /// Enable PostgreSQL replication
    pub postgres_replication: bool,

    /// Number of PostgreSQL replicas
    pub postgres_replicas: u32,

    /// Enable Keepalived for virtual IP management
    pub keepalived: bool,

    /// Multi-region deployment settings
    pub multi_region: Option<MultiRegionConfig>,
}

impl Default for HAConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            vpn_replicas: 3,
            api_replicas: 3,
            nginx_replicas: 3,
            virtual_ip: "172.20.0.100".to_string(),
            auto_failover: true,
            health_check_interval: 10,
            failover_timeout: 30,
            service_discovery: true,
            redis_sentinel: true,
            postgres_replication: true,
            postgres_replicas: 2,
            keepalived: true,
            multi_region: None,
        }
    }
}

/// Multi-region deployment configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultiRegionConfig {
    /// Primary region
    pub primary_region: String,

    /// Secondary regions
    pub secondary_regions: Vec<String>,

    /// Cross-region replication enabled
    pub cross_region_replication: bool,

    /// Region-specific endpoints
    pub region_endpoints: HashMap<String, String>,

    /// Traffic routing policy
    pub routing_policy: RoutingPolicy,
}

/// Traffic routing policy for multi-region deployments
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RoutingPolicy {
    /// Route to nearest region
    GeoProximity,
    /// Active-passive failover
    Failover,
    /// Weighted distribution
    Weighted(HashMap<String, u32>),
    /// Round-robin across regions
    RoundRobin,
}

/// High Availability manager
pub struct HAManager {
    config: HAConfig,
    compose_config: ComposeConfig,
    compose_manager: ComposeManager,
}

impl HAManager {
    /// Create a new HA manager
    pub async fn new(ha_config: HAConfig, compose_config: ComposeConfig) -> Result<Self> {
        let compose_manager = ComposeManager::new(&compose_config).await?;

        Ok(Self {
            config: ha_config,
            compose_config,
            compose_manager,
        })
    }

    /// Enable high availability features
    pub async fn enable_ha(&mut self) -> Result<()> {
        info!("Enabling high availability features");

        self.config.enabled = true;

        // Generate HA-specific Docker Compose configuration
        self.generate_ha_compose().await?;

        // Deploy HA services
        self.deploy_ha_services().await?;

        // Configure service discovery
        if self.config.service_discovery {
            self.setup_service_discovery().await?;
        }

        // Setup database replication
        if self.config.postgres_replication {
            self.setup_database_replication().await?;
        }

        // Configure Redis Sentinel
        if self.config.redis_sentinel {
            self.setup_redis_sentinel().await?;
        }

        // Setup virtual IP management
        if self.config.keepalived {
            self.setup_keepalived().await?;
        }

        info!("High availability features enabled successfully");
        Ok(())
    }

    /// Disable high availability features
    pub async fn disable_ha(&mut self) -> Result<()> {
        info!("Disabling high availability features");

        self.config.enabled = false;

        // Scale down to single instances
        self.scale_down_services().await?;

        // Remove HA-specific services
        self.remove_ha_services().await?;

        info!("High availability features disabled");
        Ok(())
    }

    /// Scale services for high availability
    pub async fn scale_for_ha(&self) -> Result<()> {
        info!("Scaling services for high availability");

        // Scale VPN servers
        self.compose_manager
            .scale_service("vpn-server", self.config.vpn_replicas)
            .await?;

        // Scale API servers
        self.compose_manager
            .scale_service("vpn-api", self.config.api_replicas)
            .await?;

        // Scale Nginx instances
        self.compose_manager
            .scale_service("nginx-proxy", self.config.nginx_replicas)
            .await?;

        info!(
            "Services scaled for HA: VPN={}, API={}, Nginx={}",
            self.config.vpn_replicas, self.config.api_replicas, self.config.nginx_replicas
        );

        Ok(())
    }

    /// Check HA system health
    pub async fn check_health(&self) -> Result<HAHealthStatus> {
        debug!("Checking HA system health");

        let compose_status = self.compose_manager.get_status().await?;

        // Check critical services
        let vpn_healthy = self.check_service_health(&compose_status.services, "vpn-server")?;
        let api_healthy = self.check_service_health(&compose_status.services, "vpn-api")?;
        let lb_healthy = self.check_service_health(&compose_status.services, "vpn-lb")?;
        let consul_healthy = if self.config.service_discovery {
            self.check_service_health(&compose_status.services, "consul")?
        } else {
            true
        };

        // Calculate overall health
        let all_healthy = vpn_healthy && api_healthy && lb_healthy && consul_healthy;

        Ok(HAHealthStatus {
            overall_health: if all_healthy { "healthy" } else { "degraded" }.to_string(),
            vpn_servers_healthy: vpn_healthy,
            api_servers_healthy: api_healthy,
            load_balancer_healthy: lb_healthy,
            service_discovery_healthy: consul_healthy,
            active_replicas: self.count_active_replicas(&compose_status.services),
            expected_replicas: self.get_expected_replicas(),
        })
    }

    /// Perform failover for a specific service
    pub async fn failover_service(&self, service: &str) -> Result<()> {
        warn!("Initiating failover for service: {}", service);

        if !self.config.auto_failover {
            return Err(ComposeError::ha_error("Automatic failover is disabled"));
        }

        // Get unhealthy instances
        let unhealthy_instances = self.get_unhealthy_instances(service).await?;

        for instance in unhealthy_instances {
            // Remove unhealthy instance
            self.remove_instance(&instance).await?;

            // Start replacement instance
            self.start_replacement_instance(service).await?;
        }

        info!("Failover completed for service: {}", service);
        Ok(())
    }

    /// Setup multi-region deployment
    pub async fn setup_multi_region(&mut self, config: MultiRegionConfig) -> Result<()> {
        info!("Setting up multi-region deployment");

        self.config.multi_region = Some(config.clone());

        // Generate region-specific compose files
        for region in &config.secondary_regions {
            self.generate_region_compose(region).await?;
        }

        // Configure cross-region replication
        if config.cross_region_replication {
            self.setup_cross_region_replication().await?;
        }

        // Setup region-specific routing
        self.setup_region_routing(&config.routing_policy).await?;

        info!("Multi-region deployment configured");
        Ok(())
    }

    /// Generate HA-specific Docker Compose configuration
    async fn generate_ha_compose(&self) -> Result<()> {
        let mut generator = ComposeGenerator::new(&self.compose_config).await?;

        // Set environment to production with HA
        generator
            .set_environment(&Environment::production())
            .await?;

        // Generate compose files with HA settings
        generator.generate_compose_files().await?;

        // Copy HA overlay file to output directory
        let ha_overlay_content =
            include_str!("../../../templates/docker-compose/high-availability.yml");
        let ha_path = self
            .compose_config
            .compose_dir
            .join("docker-compose.ha.yml");
        tokio::fs::write(&ha_path, ha_overlay_content).await?;

        Ok(())
    }

    /// Deploy HA-specific services
    async fn deploy_ha_services(&self) -> Result<()> {
        info!("Deploying HA services");

        // Deploy using HA compose file
        self.compose_manager.up().await?;

        // Wait for services to be ready
        tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;

        // Scale services
        self.scale_for_ha().await?;

        Ok(())
    }

    /// Setup service discovery with Consul
    async fn setup_service_discovery(&self) -> Result<()> {
        info!("Setting up service discovery with Consul");

        // Consul should be started by docker-compose
        // Register services with Consul
        self.register_services_with_consul().await?;

        Ok(())
    }

    /// Register services with Consul
    async fn register_services_with_consul(&self) -> Result<()> {
        // This would typically make API calls to Consul
        // For now, services are registered via consul.json config
        debug!("Services registered with Consul via configuration");
        Ok(())
    }

    /// Setup PostgreSQL replication
    async fn setup_database_replication(&self) -> Result<()> {
        info!("Setting up PostgreSQL replication");

        // Execute initialization script on primary
        let output = self
            .compose_manager
            .exec(
                "postgres-primary",
                &["bash", "/docker-entrypoint-initdb.d/init-replication.sh"],
            )
            .await?;

        debug!("PostgreSQL replication setup output: {}", output);

        Ok(())
    }

    /// Setup Redis Sentinel
    async fn setup_redis_sentinel(&self) -> Result<()> {
        info!("Setting up Redis Sentinel");

        // Sentinel configuration is loaded from sentinel.conf
        // Just ensure the service is running
        let status = self.compose_manager.get_status().await?;
        let sentinel_running = status
            .services
            .iter()
            .any(|s| s.name.contains("redis-sentinel") && s.state == "running");

        if !sentinel_running {
            return Err(ComposeError::ha_error("Redis Sentinel is not running"));
        }

        Ok(())
    }

    /// Setup Keepalived for virtual IP management
    async fn setup_keepalived(&self) -> Result<()> {
        info!("Setting up Keepalived for virtual IP management");

        // Keepalived configuration is loaded from keepalived.conf
        // Ensure the service is running
        let status = self.compose_manager.get_status().await?;
        let keepalived_running = status
            .services
            .iter()
            .any(|s| s.name == "keepalived" && s.state == "running");

        if !keepalived_running {
            warn!("Keepalived is not running, virtual IP may not be available");
        }

        Ok(())
    }

    /// Scale down services for non-HA mode
    async fn scale_down_services(&self) -> Result<()> {
        info!("Scaling down services to single instances");

        self.compose_manager.scale_service("vpn-server", 1).await?;
        self.compose_manager.scale_service("vpn-api", 1).await?;
        self.compose_manager.scale_service("nginx-proxy", 1).await?;

        Ok(())
    }

    /// Remove HA-specific services
    async fn remove_ha_services(&self) -> Result<()> {
        info!("Removing HA-specific services");

        // Stop HA services
        let ha_services = vec!["vpn-lb", "consul", "keepalived", "redis-sentinel"];
        for service in ha_services {
            let _ = self
                .compose_manager
                .exec("docker", &["stop", service])
                .await;
            let _ = self.compose_manager.exec("docker", &["rm", service]).await;
        }

        Ok(())
    }

    /// Check if a service is healthy
    fn check_service_health(
        &self,
        services: &[crate::manager::ServiceStatus],
        service_name: &str,
    ) -> Result<bool> {
        let healthy = services
            .iter()
            .filter(|s| s.name.contains(service_name))
            .all(|s| s.state == "running" && s.health.as_deref() != Some("unhealthy"));

        Ok(healthy)
    }

    /// Count active replicas
    fn count_active_replicas(
        &self,
        services: &[crate::manager::ServiceStatus],
    ) -> HashMap<String, u32> {
        let mut replicas = HashMap::new();

        for service in services {
            if service.state == "running" {
                let base_name = service.name.split('_').next().unwrap_or(&service.name);
                *replicas.entry(base_name.to_string()).or_insert(0) += 1;
            }
        }

        replicas
    }

    /// Get expected replica counts
    fn get_expected_replicas(&self) -> HashMap<String, u32> {
        let mut expected = HashMap::new();

        if self.config.enabled {
            expected.insert("vpn-server".to_string(), self.config.vpn_replicas);
            expected.insert("vpn-api".to_string(), self.config.api_replicas);
            expected.insert("nginx-proxy".to_string(), self.config.nginx_replicas);

            if self.config.postgres_replication {
                expected.insert(
                    "postgres-replica".to_string(),
                    self.config.postgres_replicas,
                );
            }
        }

        expected
    }

    /// Get unhealthy instances of a service
    async fn get_unhealthy_instances(&self, service: &str) -> Result<Vec<String>> {
        let status = self.compose_manager.get_status().await?;

        let unhealthy = status
            .services
            .iter()
            .filter(|s| s.name.contains(service))
            .filter(|s| s.state != "running" || s.health.as_deref() == Some("unhealthy"))
            .map(|s| s.name.clone())
            .collect();

        Ok(unhealthy)
    }

    /// Remove a specific instance
    async fn remove_instance(&self, instance: &str) -> Result<()> {
        warn!("Removing unhealthy instance: {}", instance);

        self.compose_manager
            .exec("docker", &["stop", instance])
            .await?;

        self.compose_manager
            .exec("docker", &["rm", instance])
            .await?;

        Ok(())
    }

    /// Start a replacement instance
    async fn start_replacement_instance(&self, service: &str) -> Result<()> {
        info!("Starting replacement instance for service: {}", service);

        // Docker Compose will handle creating new instances
        // when scaling up after removing unhealthy ones
        let current_scale = self
            .count_active_replicas(&self.compose_manager.get_status().await?.services)
            .get(service)
            .copied()
            .unwrap_or(0);

        let target_scale = match service {
            "vpn-server" => self.config.vpn_replicas,
            "vpn-api" => self.config.api_replicas,
            "nginx-proxy" => self.config.nginx_replicas,
            _ => 1,
        };

        if current_scale < target_scale {
            self.compose_manager
                .scale_service(service, target_scale)
                .await?;
        }

        Ok(())
    }

    /// Generate region-specific compose file
    async fn generate_region_compose(&self, region: &str) -> Result<()> {
        info!("Generating compose file for region: {}", region);

        // This would generate a region-specific overlay
        // For now, we'll create a placeholder
        let region_config = format!(
            "# Region-specific configuration for {}\n\
             version: '3.8'\n\
             \n\
             x-region: &region\n\
               {}\n\
             \n\
             services:\n\
               vpn-server:\n\
                 environment:\n\
                   - REGION={}\n\
                   - REGION_ENDPOINT=${{REGION_{}_ENDPOINT}}\n",
            region,
            region,
            region,
            region.to_uppercase()
        );

        let path = self
            .compose_config
            .compose_dir
            .join(format!("region-{}.yml", region));
        tokio::fs::write(path, region_config).await?;

        Ok(())
    }

    /// Setup cross-region replication
    async fn setup_cross_region_replication(&self) -> Result<()> {
        info!("Setting up cross-region replication");

        // This would configure database and cache replication across regions
        // Implementation depends on specific infrastructure setup

        Ok(())
    }

    /// Setup region-specific routing
    async fn setup_region_routing(&self, policy: &RoutingPolicy) -> Result<()> {
        info!("Setting up region routing with policy: {:?}", policy);

        // This would configure load balancer or DNS for region routing
        // Implementation depends on specific infrastructure

        Ok(())
    }
}

/// HA system health status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HAHealthStatus {
    pub overall_health: String,
    pub vpn_servers_healthy: bool,
    pub api_servers_healthy: bool,
    pub load_balancer_healthy: bool,
    pub service_discovery_healthy: bool,
    pub active_replicas: HashMap<String, u32>,
    pub expected_replicas: HashMap<String, u32>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_ha_config_default() {
        let config = HAConfig::default();
        assert!(!config.enabled);
        assert_eq!(config.vpn_replicas, 3);
        assert_eq!(config.api_replicas, 3);
        assert_eq!(config.virtual_ip, "172.20.0.100");
    }

    #[test]
    fn test_routing_policy_serialization() {
        let policy = RoutingPolicy::GeoProximity;
        let serialized = serde_json::to_string(&policy).unwrap();
        assert_eq!(serialized, "\"GeoProximity\"");

        let weighted = RoutingPolicy::Weighted(
            vec![("us-east".to_string(), 50), ("us-west".to_string(), 50)]
                .into_iter()
                .collect(),
        );
        let serialized = serde_json::to_string(&weighted).unwrap();
        assert!(serialized.contains("Weighted"));
    }
}
