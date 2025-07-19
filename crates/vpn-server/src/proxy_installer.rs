//! Proxy server installer implementation

use crate::error::{Result, ServerError};
use std::path::PathBuf;
use tokio::fs;
use tracing::{debug, info};
use vpn_docker::{ContainerManager, ContainerStatus};

pub struct ProxyInstaller {
    install_path: PathBuf,
    container_manager: ContainerManager,
    port: u16,
}

impl ProxyInstaller {
    pub fn new(install_path: PathBuf, port: u16) -> Result<Self> {
        let container_manager = ContainerManager::new().map_err(|e| {
            ServerError::InstallationError(format!("Failed to create container manager: {}", e))
        })?;

        Ok(Self {
            install_path,
            container_manager,
            port,
        })
    }

    pub async fn install(&self, proxy_type: &str) -> Result<()> {
        info!(
            "Installing {} proxy server on port {}",
            proxy_type, self.port
        );

        // Create directory structure
        self.create_directories().await?;

        // Generate configuration files
        self.generate_configs(proxy_type).await?;

        // Deploy with Docker Compose
        self.deploy_proxy(proxy_type).await?;

        info!("Proxy server installation completed successfully");
        Ok(())
    }

    async fn create_directories(&self) -> Result<()> {
        let dirs = [
            self.install_path.join("proxy"),
            self.install_path.join("proxy/dynamic"),
            self.install_path.join("proxy/logs"),
            self.install_path.join("proxy/certs"),
        ];

        for dir in &dirs {
            fs::create_dir_all(dir).await?;
        }

        Ok(())
    }

    async fn generate_configs(&self, proxy_type: &str) -> Result<()> {
        // Generate Docker Compose file
        let compose_content = match proxy_type {
            "http" => self.generate_http_compose(),
            "socks5" => self.generate_socks5_compose(),
            "all" => self.generate_http_compose(),
            _ => {
                return Err(ServerError::ValidationError(format!(
                    "Unknown proxy type: {}",
                    proxy_type
                )))
            }
        };

        let compose_path = self.install_path.join("proxy/docker-compose.yml");
        fs::write(&compose_path, compose_content).await?;

        // Generate Squid configuration for HTTP proxy
        if proxy_type == "http" || proxy_type == "all" {
            let squid_config = self.generate_squid_config();
            let squid_path = self.install_path.join("proxy/squid.conf");
            fs::write(&squid_path, squid_config).await?;
        }

        // Generate auth configuration
        let auth_config = self.generate_auth_config();
        let auth_path = self.install_path.join("proxy/auth-config.toml");
        fs::write(&auth_path, auth_config).await?;

        // Generate Prometheus configuration
        let prometheus_config = self.generate_prometheus_config();
        let prometheus_path = self.install_path.join("proxy/prometheus.yml");
        fs::write(&prometheus_path, prometheus_config).await?;

        Ok(())
    }

    async fn deploy_proxy(&self, _proxy_type: &str) -> Result<()> {
        info!("Deploying proxy server with Docker Compose");

        let compose_path = self.install_path.join("proxy/docker-compose.yml");

        // Run docker-compose up -d
        let output = tokio::process::Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_path)
            .arg("up")
            .arg("-d")
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ServerError::InstallationError(format!(
                "Docker compose failed: {}",
                stderr
            )));
        }

        // Wait for services to be healthy
        self.wait_for_health().await?;

        Ok(())
    }

    async fn wait_for_health(&self) -> Result<()> {
        info!("Waiting for proxy services to be healthy");

        let services = ["vpn-squid-proxy", "vpn-proxy-auth", "vpn-proxy-metrics"];
        let max_attempts = 30;
        let delay = std::time::Duration::from_secs(2);

        for service in &services {
            let mut attempts = 0;
            loop {
                match self.container_manager.get_container_status(service).await {
                    Ok(status) => {
                        if status == ContainerStatus::Running {
                            debug!("Service {} is running", service);
                            break;
                        }
                    }
                    Err(e) => {
                        debug!("Service {} not ready yet: {}", service, e);
                    }
                }

                attempts += 1;
                if attempts >= max_attempts {
                    return Err(ServerError::InstallationError(format!(
                        "Service {} failed to start",
                        service
                    )));
                }

                tokio::time::sleep(delay).await;
            }
        }

        info!("All proxy services are healthy");
        Ok(())
    }

    fn generate_http_compose(&self) -> String {
        format!(
            r#"version: '3.8'

services:
  squid-proxy:
    image: ubuntu/squid:latest
    container_name: vpn-squid-proxy
    restart: unless-stopped
    ports:
      - "{}:3128"
    volumes:
      - ./squid.conf:/etc/squid/squid.conf:ro
      - ./logs:/var/log/squid
      - squid-cache:/var/spool/squid
    networks:
      - proxy-network
    environment:
      - SQUID_CACHE_DIR=/var/spool/squid
      - SQUID_LOG_DIR=/var/log/squid
      - SQUID_USER=proxy
    healthcheck:
      test: ["CMD", "squidclient", "-h", "localhost", "cache_object://localhost/info"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  proxy-auth:
    image: vpn-proxy:latest
    build:
      context: ../../
      dockerfile: docker/proxy/Dockerfile.auth
    container_name: vpn-proxy-auth
    restart: unless-stopped
    ports:
      - "127.0.0.1:8089:8080"
    environment:
      - AUTH_SERVICE_PORT=8080
      - USERS_DB_PATH=/var/lib/vpn/users
    volumes:
      - vpn-users-data:/var/lib/vpn/users:ro
      - ./auth-config.toml:/etc/proxy/config.toml:ro
    networks:
      - proxy-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  proxy-metrics:
    image: prom/prometheus:latest
    container_name: vpn-proxy-metrics
    restart: unless-stopped
    ports:
      - "127.0.0.1:9092:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    networks:
      - proxy-network
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'

networks:
  proxy-network:
    driver: bridge

volumes:
  vpn-users-data:
    external: true
  squid-cache:
  prometheus-data:"#,
            self.port
        )
    }

    fn generate_socks5_compose(&self) -> String {
        format!(
            r#"version: '3.8'

services:
  vpn-socks5-proxy:
    image: vpn-proxy:latest
    build:
      context: ../../
      dockerfile: docker/proxy/Dockerfile.socks5
    container_name: vpn-socks5-proxy
    restart: unless-stopped
    ports:
      - "{}:1080"
    environment:
      - PROXY_TYPE=socks5
      - AUTH_ENABLED=true
      - RATE_LIMIT_ENABLED=true
    volumes:
      - ./config.toml:/etc/proxy/config.toml:ro
      - vpn-users-data:/var/lib/vpn/users:ro
    networks:
      - proxy-network

networks:
  proxy-network:
    driver: bridge

volumes:
  vpn-users-data:
    external: true"#,
            self.port
        )
    }

    fn generate_squid_config(&self) -> &'static str {
        r#"# Squid Configuration for VPN Proxy Server
# This configuration allows proxying to any internet resource

# Network ACLs
acl localnet src 10.0.0.0/8     # RFC1918 possible internal network
acl localnet src 172.16.0.0/12  # RFC1918 possible internal network
acl localnet src 192.168.0.0/16 # RFC1918 possible internal network
acl localnet src fc00::/7       # RFC 4193 local private network range
acl localnet src fe80::/10      # RFC 4291 link-local (directly plugged) machines

# Port ACLs
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443         # https
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http
acl CONNECT method CONNECT

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm VPN Proxy Authentication
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED

# Access rules
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow authenticated
http_access allow localnet
http_access allow localhost
http_access deny all

# Proxy port
http_port 3128

# Cache settings
cache_dir ufs /var/spool/squid 10000 16 256
cache_mem 256 MB
maximum_object_size 512 MB
minimum_object_size 0 KB
maximum_object_size_in_memory 8 MB

# Refresh patterns for common content types
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# Log settings
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_store_log daemon:/var/log/squid/store.log

# Performance tuning
max_filedesc 65536
cache_effective_user proxy
cache_effective_group proxy

# Core dumps
coredump_dir /var/spool/squid

# Headers for anonymity (optional)
request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access WWW-Authenticate allow all
request_header_access Proxy-Authorization allow all
request_header_access Proxy-Authenticate allow all
request_header_access Cache-Control allow all
request_header_access Content-Encoding allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Expires allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Last-Modified allow all
request_header_access Location allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Content-Language allow all
request_header_access Mime-Version allow all
request_header_access Retry-After allow all
request_header_access Title allow all
request_header_access Connection allow all
request_header_access Proxy-Connection allow all
request_header_access User-Agent allow all
request_header_access Cookie allow all
request_header_access All deny all

# Enable X-Forwarded-For header
forwarded_for on

# DNS settings
dns_v4_first on
positive_dns_ttl 6 hours
negative_dns_ttl 1 minute

# Shutdown lifetime
shutdown_lifetime 3 seconds"#
    }

    fn generate_auth_config(&self) -> &'static str {
        r#"# VPN Proxy Authentication Service Configuration

protocol = "both"
bind_host = "0.0.0.0"
http_port = 8080
socks5_port = 1080

[auth]
enabled = true
backend = "vpn-users"
cache_ttl = { secs = 300, nanos = 0 }
allow_anonymous = false
ip_whitelist = [
    "127.0.0.1",
    "172.30.0.0/16",
]

[rate_limit]
enabled = true
requests_per_second = 100
burst_size = 200
bandwidth_limit = 10485760
global_limit = 10000

[pool]
max_connections_per_host = 100
max_total_connections = 1000
idle_timeout = { secs = 300, nanos = 0 }
max_lifetime = { secs = 3600, nanos = 0 }

[metrics]
enabled = true
bind_address = "0.0.0.0:9090"
path = "/metrics"

[timeouts]
connect = { secs = 10, nanos = 0 }
read = { secs = 30, nanos = 0 }
write = { secs = 30, nanos = 0 }
idle = { secs = 300, nanos = 0 }

log_level = "info""#
    }

    fn generate_prometheus_config(&self) -> &'static str {
        r#"global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
  external_labels:
    monitor: 'vpn-proxy'
    environment: 'production'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          service: 'prometheus'

  - job_name: 'vpn-proxy-auth'
    static_configs:
      - targets: ['proxy-auth:9090']
        labels:
          service: 'proxy-auth'
    metrics_path: '/metrics'

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik-proxy:8090']
        labels:
          service: 'traefik-proxy'
    metrics_path: '/metrics'

  - job_name: 'vpn-proxy-server'
    static_configs:
      - targets: ['vpn-proxy:9090']
        labels:
          service: 'vpn-proxy'
    metrics_path: '/metrics'"#
    }

    pub async fn uninstall(&self) -> Result<()> {
        info!("Uninstalling proxy server");

        let compose_path = self.install_path.join("proxy/docker-compose.yml");

        if compose_path.exists() {
            // Run docker-compose down
            let output = tokio::process::Command::new("docker-compose")
                .arg("-f")
                .arg(&compose_path)
                .arg("down")
                .arg("-v")
                .output()
                .await?;

            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                return Err(ServerError::InstallationError(format!(
                    "Docker compose down failed: {}",
                    stderr
                )));
            }
        }

        // Remove configuration files
        if let Err(e) = fs::remove_dir_all(self.install_path.join("proxy")).await {
            debug!("Failed to remove proxy directory: {}", e);
        }

        info!("Proxy server uninstalled successfully");
        Ok(())
    }
}
