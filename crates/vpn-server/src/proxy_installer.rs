//! Proxy server installer implementation

use crate::error::{Result, ServerError};
use std::path::PathBuf;
use tokio::fs;
use tracing::{info, debug};
use vpn_docker::{ContainerManager, ContainerStatus};

pub struct ProxyInstaller {
    install_path: PathBuf,
    container_manager: ContainerManager,
    port: u16,
}

impl ProxyInstaller {
    pub fn new(install_path: PathBuf, port: u16) -> Result<Self> {
        let container_manager = ContainerManager::new()
            .map_err(|e| ServerError::InstallationError(format!("Failed to create container manager: {}", e)))?;
        
        Ok(Self {
            install_path,
            container_manager,
            port,
        })
    }
    
    pub async fn install(&self, proxy_type: &str) -> Result<()> {
        info!("Installing {} proxy server on port {}", proxy_type, self.port);
        
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
            _ => return Err(ServerError::ValidationError(format!("Unknown proxy type: {}", proxy_type))),
        };
        
        let compose_path = self.install_path.join("proxy/docker-compose.yml");
        fs::write(&compose_path, compose_content).await?;
        
        // Generate dynamic configuration
        let dynamic_config = self.generate_dynamic_config();
        let dynamic_path = self.install_path.join("proxy/dynamic/http-proxy.yml");
        fs::write(&dynamic_path, dynamic_config).await?;
        
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
            .await
?;
        
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ServerError::InstallationError(format!("Docker compose failed: {}", stderr)));
        }
        
        // Wait for services to be healthy
        self.wait_for_health().await?;
        
        Ok(())
    }
    
    async fn wait_for_health(&self) -> Result<()> {
        info!("Waiting for proxy services to be healthy");
        
        let services = ["vpn-traefik-proxy", "vpn-proxy-auth", "vpn-proxy-metrics"];
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
                    return Err(ServerError::InstallationError(format!("Service {} failed to start", service)));
                }
                
                tokio::time::sleep(delay).await;
            }
        }
        
        info!("All proxy services are healthy");
        Ok(())
    }
    
    fn generate_http_compose(&self) -> String {
        format!(r#"version: '3.8'

services:
  traefik-proxy:
    image: traefik:v3.0
    container_name: vpn-traefik-proxy
    restart: unless-stopped
    command:
      - "--log.level=INFO"
      - "--api.dashboard=true"
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--providers.file.watch=true"
      - "--entrypoints.http-proxy.address=:8080"
      - "--entrypoints.https-proxy.address=:8443"
      - "--entrypoints.socks5.address=:1080"
      - "--metrics.prometheus=true"
      - "--metrics.prometheus.buckets=0.1,0.3,1.2,5.0"
      - "--accesslog=true"
      - "--accesslog.filepath=/logs/access.log"
      - "--accesslog.format=json"
    ports:
      - "{}:8080"
      - "8443:8443"
      - "1080:1080"
      - "127.0.0.1:8090:8090"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - ./logs:/logs
      - ./certs:/certs:ro
    networks:
      - proxy-network
    environment:
      - TRAEFIK_LOG_LEVEL=INFO
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`proxy-dashboard.local`)"
      - "traefik.http.routers.api.service=api@internal"
      - "traefik.http.routers.api.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=admin:$$2y$$10$$..."
    healthcheck:
      test: ["CMD", "traefik", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  proxy-auth:
    image: vpn-proxy-auth:latest
    build:
      context: ../../
      dockerfile: docker/proxy/Dockerfile.auth
    container_name: vpn-proxy-auth
    restart: unless-stopped
    environment:
      - AUTH_BACKEND=vpn-users
      - VPN_USERS_PATH=/var/lib/vpn/users
      - RATE_LIMIT_ENABLED=true
      - RATE_LIMIT_RPS=100
      - METRICS_ENABLED=true
      - LOG_LEVEL=info
    volumes:
      - vpn-users-data:/var/lib/vpn/users:ro
      - ./auth-config.toml:/etc/proxy/config.toml:ro
    networks:
      - proxy-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.auth.rule=PathPrefix(`/auth`)"
      - "traefik.http.services.auth.loadbalancer.server.port=3000"
      
  proxy-metrics:
    image: prom/prometheus:latest
    container_name: vpn-proxy-metrics
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    networks:
      - proxy-network
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      
networks:
  proxy-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
          
volumes:
  vpn-users-data:
    external: true
  prometheus-data:
    driver: local"#, self.port)
    }
    
    fn generate_socks5_compose(&self) -> String {
        format!(r#"version: '3.8'

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
    external: true"#, self.port)
    }
    
    fn generate_dynamic_config(&self) -> &'static str {
        r#"# Dynamic configuration for HTTP/HTTPS proxy

http:
  middlewares:
    proxy-auth:
      forwardAuth:
        address: "http://proxy-auth:3000/auth/verify"
        authResponseHeaders:
          - "X-User-ID"
          - "X-User-Email"
          - "X-Rate-Limit"
        trustForwardHeader: true
        
    rate-limit:
      rateLimit:
        average: 100
        burst: 200
        period: 1s
        
    proxy-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
          X-Real-IP: "true"
        customResponseHeaders:
          X-Proxy-Server: "VPN-Proxy"
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "DENY"
          X-XSS-Protection: "1; mode=block"

  services:
    http-proxy:
      loadBalancer:
        servers:
          - url: "http://{{.Request.Host}}"
        passHostHeader: true
        
    https-proxy:
      loadBalancer:
        servers:
          - url: "https://{{.Request.Host}}"
        passHostHeader: true

  routers:
    http-proxy-router:
      entryPoints:
        - http-proxy
      rule: "PathPrefix(`/`)"
      service: http-proxy
      middlewares:
        - proxy-auth
        - rate-limit
        - proxy-headers
      priority: 1
      
    https-proxy-router:
      entryPoints:
        - https-proxy
      rule: "Method(`CONNECT`)"
      service: https-proxy
      middlewares:
        - proxy-auth
        - rate-limit
        - proxy-headers
      priority: 10

tcp:
  routers:
    socks5-router:
      entryPoints:
        - socks5
      rule: "HostSNI(`*`)"
      service: vpn-socks5-proxy
      
  services:
    vpn-socks5-proxy:
      loadBalancer:
        servers:
          - address: "vpn-proxy:1080""#
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
                .await
?;
            
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                return Err(ServerError::InstallationError(format!("Docker compose down failed: {}", stderr)));
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