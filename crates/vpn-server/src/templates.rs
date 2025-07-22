use crate::error::{Result, ServerError};
use crate::installer::{InstallationOptions, LogLevel, ServerConfig};
use std::fs;
use std::path::Path;

pub struct DockerComposeTemplate;

impl DockerComposeTemplate {
    pub fn new() -> Self {
        Self
    }

    pub async fn generate_xray_compose(
        &self,
        install_path: &Path,
        server_config: &ServerConfig,
        options: &InstallationOptions,
        subnet: Option<&str>,
    ) -> Result<()> {
        let compose_content = self.create_xray_compose_content(server_config, options, subnet)?;

        let compose_file = install_path.join("docker-compose.yml");
        fs::write(&compose_file, compose_content)?;

        // Create directory structure
        self.create_xray_directories(install_path)?;

        // Generate Xray configuration
        self.generate_xray_config(install_path, server_config, options)
            .await?;

        Ok(())
    }

    pub async fn generate_outline_compose(
        &self,
        install_path: &Path,
        server_config: &ServerConfig,
        options: &InstallationOptions,
        subnet: Option<&str>,
    ) -> Result<()> {
        let compose_content =
            self.create_outline_compose_content(server_config, options, subnet)?;

        let compose_file = install_path.join("docker-compose.yml");
        fs::write(&compose_file, compose_content)?;

        // Create directory structure
        self.create_outline_directories(install_path)?;

        Ok(())
    }

    fn create_xray_compose_content(
        &self,
        server_config: &ServerConfig,
        options: &InstallationOptions,
        subnet: Option<&str>,
    ) -> Result<String> {
        let restart_policy = if options.auto_start {
            "unless-stopped"
        } else {
            "no"
        };

        let compose = format!(
            r#"services:
  vless-xray:
    build:
      context: /home/ikeniborn/Documents/Project/vpn
      dockerfile: templates/xray/Dockerfile
    image: vpn-xray:latest
    container_name: vless-xray
    restart: {}
    ports:
      - "{}:{}"
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
      - ./users:/etc/xray/users
    environment:
      - XRAY_LOCATION_ASSET=/usr/share/xray
    command: ["run", "-config", "/etc/xray/config.json"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - vless_vpn-network

  vless-watchtower:
    build:
      context: /home/ikeniborn/Documents/Project/vpn
      dockerfile: templates/watchtower/Dockerfile
    image: vpn-watchtower:latest
    container_name: vless-watchtower
    restart: {}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_REVIVE_STOPPED=false
      - WATCHTOWER_LIFECYCLE_HOOKS=false
      - WATCHTOWER_LABEL_ENABLE=true
    command: ["--cleanup", "--include-restarting=false", "--include-stopped=false", "--label-enable"]
    labels:
      - "com.centurylinklabs.watchtower.scope=vless"
    networks:
      - vless_vpn-network

networks:
  vless_vpn-network:
    driver: bridge{subnet_config}
"#,
            restart_policy,
            server_config.port,
            server_config.port,
            restart_policy,
            subnet_config = Self::format_subnet_config(subnet)
        );

        Ok(compose)
    }

    fn create_outline_compose_content(
        &self,
        server_config: &ServerConfig,
        options: &InstallationOptions,
        subnet: Option<&str>,
    ) -> Result<String> {
        let restart_policy = if options.auto_start {
            "unless-stopped"
        } else {
            "no"
        };

        let compose = format!(
            r#"services:
  outline-shadowbox:
    build:
      context: /home/ikeniborn/Documents/Project/vpn
      dockerfile: templates/outline/Dockerfile
    image: vpn-outline:latest
    container_name: outline-shadowbox
    restart: {}
    ports:
      - "{}:8080"
      - "{}:443"
    volumes:
      - ./persisted-state:/opt/outline/persisted-state
      - ./management:/opt/outline/management
    environment:
      - LOG_LEVEL={}
    labels:
      - "com.centurylinklabs.watchtower.scope=outline"
    networks:
      - outline_vpn-network

  outline-watchtower:
    image: containrrr/watchtower:latest
    container_name: outline-watchtower
    restart: {}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_REVIVE_STOPPED=false
      - WATCHTOWER_LIFECYCLE_HOOKS=false
      - WATCHTOWER_LABEL_ENABLE=true
    command: ["--cleanup", "--include-restarting=false", "--include-stopped=false", "--label-enable"]
    labels:
      - "com.centurylinklabs.watchtower.scope=outline"
    networks:
      - outline_vpn-network

networks:
  outline_vpn-network:
    driver: bridge{subnet_config}
"#,
            restart_policy,
            server_config.port + 1000,
            server_config.port,
            server_config.log_level.as_str(),
            restart_policy,
            subnet_config = Self::format_subnet_config(subnet)
        );

        Ok(compose)
    }

    /// Format subnet configuration for Docker Compose network
    fn format_subnet_config(subnet: Option<&str>) -> String {
        match subnet {
            Some(subnet_cidr) => {
                format!(
                    "\n    ipam:\n      config:\n        - subnet: {}",
                    subnet_cidr
                )
            }
            None => String::new(),
        }
    }

    fn create_xray_directories(&self, install_path: &Path) -> Result<()> {
        let directories = ["config", "logs", "users"];

        for dir in &directories {
            let dir_path = install_path.join(dir);
            fs::create_dir_all(&dir_path)?;
        }

        Ok(())
    }

    pub async fn generate_wireguard_compose(
        &self,
        install_path: &Path,
        server_config: &ServerConfig,
        options: &InstallationOptions,
        subnet: Option<&str>,
    ) -> Result<()> {
        let compose_content =
            self.create_wireguard_compose_content(server_config, options, subnet)?;

        let compose_file = install_path.join("docker-compose.yml");
        fs::write(&compose_file, compose_content)?;

        // Create directory structure
        self.create_wireguard_directories(install_path)?;

        Ok(())
    }

    fn create_wireguard_compose_content(
        &self,
        server_config: &ServerConfig,
        options: &InstallationOptions,
        subnet: Option<&str>,
    ) -> Result<String> {
        let restart_policy = if options.auto_start {
            "unless-stopped"
        } else {
            "no"
        };

        let compose = format!(
            r#"services:
  wireguard-server:
    build:
      context: /home/ikeniborn/Documents/Project/vpn
      dockerfile: templates/wireguard/Dockerfile
    image: vpn-wireguard:latest
    container_name: wireguard-server
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - SERVERPORT={}
      - PEERS=50
      - PEERDNS=auto
      - INTERNAL_SUBNET=10.13.13.0
      - ALLOWEDIPS=0.0.0.0/0
      - LOG_CONFS=true
    volumes:
      - ./config:/config
      - /lib/modules:/lib/modules:ro
    ports:
      - "{}:{}/udp"
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: {restart_policy}
    labels:
      - "com.centurylinklabs.watchtower.scope=wireguard"
    networks:
      - wireguard_vpn-network

  wireguard-watchtower:
    build:
      context: /home/ikeniborn/Documents/Project/vpn
      dockerfile: templates/watchtower/Dockerfile
    image: vpn-watchtower:latest
    container_name: wireguard-watchtower
    restart: {restart_policy}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_REVIVE_STOPPED=false
      - WATCHTOWER_LIFECYCLE_HOOKS=false
      - WATCHTOWER_LABEL_ENABLE=true
    command: ["--cleanup", "--include-restarting=false", "--include-stopped=false", "--label-enable"]
    labels:
      - "com.centurylinklabs.watchtower.scope=wireguard"
    networks:
      - wireguard_vpn-network

networks:
  wireguard_vpn-network:
    driver: bridge{subnet_config}
"#,
            server_config.port,
            server_config.port,
            server_config.port,
            restart_policy = restart_policy,
            subnet_config = Self::format_subnet_config(subnet)
        );

        Ok(compose)
    }

    fn create_wireguard_directories(&self, install_path: &Path) -> Result<()> {
        let directories = ["config"];

        for dir in &directories {
            let dir_path = install_path.join(dir);
            fs::create_dir_all(&dir_path)?;
        }

        Ok(())
    }

    fn create_outline_directories(&self, install_path: &Path) -> Result<()> {
        let directories = ["persisted-state", "management"];

        for dir in &directories {
            let dir_path = install_path.join(dir);
            fs::create_dir_all(&dir_path)?;
        }

        Ok(())
    }

    async fn generate_xray_config(
        &self,
        install_path: &Path,
        server_config: &ServerConfig,
        options: &InstallationOptions,
    ) -> Result<()> {
        let config_dir = install_path.join("config");

        // Save server keys
        let private_key_file = config_dir.join("private_key.txt");
        let public_key_file = config_dir.join("public_key.txt");
        let short_id_file = config_dir.join("short_id.txt");
        let sni_file = config_dir.join("sni.txt");

        fs::write(&private_key_file, &server_config.private_key)?;
        fs::write(&public_key_file, &server_config.public_key)?;
        fs::write(&short_id_file, &server_config.short_id)?;
        fs::write(&sni_file, &server_config.sni_domain)?;

        // Set proper permissions for private key
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let private_perms = fs::Permissions::from_mode(0o600);
            fs::set_permissions(&private_key_file, private_perms)?;
        }

        // Generate initial Xray configuration
        let xray_config = self.create_initial_xray_config(server_config, options)?;
        let config_file = config_dir.join("config.json");
        fs::write(&config_file, xray_config)?;

        Ok(())
    }

    fn create_initial_xray_config(
        &self,
        server_config: &ServerConfig,
        options: &InstallationOptions,
    ) -> Result<String> {
        let log_level = match options.log_level {
            LogLevel::None => "none",
            LogLevel::Error => "error",
            LogLevel::Warning => "warning",
            LogLevel::Info => "info",
            LogLevel::Debug => "debug",
        };

        let config = serde_json::json!({
            "log": {
                "level": log_level,
                "access": null,
                "error": null
            },
            "inbounds": [{
                "tag": "vless-in",
                "port": server_config.port,
                "protocol": "vless",
                "settings": {
                    "clients": [],
                    "decryption": "none",
                    "fallbacks": []
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "show": false,
                        "dest": server_config.reality_dest,
                        "xver": 0,
                        "serverNames": [server_config.sni_domain.clone()],
                        "privateKey": server_config.private_key,
                        "shortIds": ["", server_config.short_id.clone()],
                        "fingerprint": "chrome"
                    },
                    "tcpSettings": {
                        "header": {
                            "type": "none"
                        }
                    }
                }
            }],
            "outbounds": [{
                "tag": "direct",
                "protocol": "freedom",
                "settings": {}
            }]
        });

        serde_json::to_string_pretty(&config).map_err(|e| ServerError::TemplateError(e.to_string()))
    }

    pub fn generate_systemd_service(
        &self,
        install_path: &Path,
        service_name: &str,
    ) -> Result<String> {
        let service_content = format!(
            r#"[Unit]
Description=VPN Server ({})
Requires=docker.service
After=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={}
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
"#,
            service_name,
            install_path.display()
        );

        Ok(service_content)
    }

    pub fn generate_nginx_config(
        &self,
        server_config: &ServerConfig,
        domain: &str,
    ) -> Result<String> {
        let nginx_config = format!(
            r#"server {{
    listen 80;
    server_name {};
    
    location / {{
        return 301 https://$server_name$request_uri;
    }}
}}

server {{
    listen 443 ssl http2;
    server_name {};
    
    ssl_certificate /etc/letsencrypt/live/{}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{}/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    location / {{
        proxy_pass http://127.0.0.1:{};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}
}}
"#,
            domain, domain, domain, domain, server_config.port
        );

        Ok(nginx_config)
    }

    pub fn generate_health_check_script(&self, install_path: &Path) -> Result<String> {
        let script_content = format!(
            r#"#!/bin/bash

# VPN Server Health Check Script
# Generated automatically - do not edit manually

INSTALL_PATH="{}"
LOG_FILE="$INSTALL_PATH/logs/health_check.log"

# Function to log messages
log_message() {{
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}}

# Check if containers are running
check_containers() {{
    local containers=("xray" "shadowbox" "watchtower")
    local running_count=0
    
    for container in "${{containers[@]}}"; do
        if docker ps --format "table {{{{.Names}}}}" | grep -q "^$container$"; then
            log_message "Container $container is running"
            ((running_count++))
        else
            log_message "Container $container is not running"
        fi
    done
    
    if [ $running_count -eq 0 ]; then
        log_message "ERROR: No containers are running"
        return 1
    fi
    
    return 0
}}

# Check port connectivity
check_ports() {{
    local ports=(443 8080)
    
    for port in "${{ports[@]}}"; do
        if netstat -tuln | grep -q ":$port "; then
            log_message "Port $port is listening"
        else
            log_message "WARNING: Port $port is not listening"
        fi
    done
}}

# Main health check
main() {{
    log_message "Starting health check"
    
    check_containers
    container_status=$?
    
    check_ports
    
    if [ $container_status -eq 0 ]; then
        log_message "Health check PASSED"
        exit 0
    else
        log_message "Health check FAILED"
        exit 1
    fi
}}

main "$@"
"#,
            install_path.display()
        );

        Ok(script_content)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::installer::{InstallationOptions, LogLevel};
    use tempfile::tempdir;

    #[test]
    fn test_xray_compose_generation() {
        let template = DockerComposeTemplate::new();
        let server_config = ServerConfig {
            host: "127.0.0.1".to_string(),
            port: 443,
            public_key: "test-public-key".to_string(),
            private_key: "test-private-key".to_string(),
            short_id: "test-short-id".to_string(),
            sni_domain: "www.google.com".to_string(),
            reality_dest: "www.google.com:443".to_string(),
            log_level: LogLevel::Warning,
        };
        let options = InstallationOptions::default();

        let compose_content = template
            .create_xray_compose_content(&server_config, &options, None)
            .unwrap();

        assert!(compose_content.contains("xray"));
        assert!(compose_content.contains("watchtower"));
        assert!(compose_content.contains("443:443"));
    }

    #[tokio::test]
    async fn test_directory_creation() {
        let temp_dir = tempdir().unwrap();
        let template = DockerComposeTemplate::new();

        template.create_xray_directories(temp_dir.path()).unwrap();

        assert!(temp_dir.path().join("config").exists());
        assert!(temp_dir.path().join("logs").exists());
        assert!(temp_dir.path().join("users").exists());
    }

    #[test]
    fn test_xray_config_generation() {
        let template = DockerComposeTemplate::new();
        let server_config = ServerConfig {
            host: "127.0.0.1".to_string(),
            port: 443,
            public_key: "test-public-key".to_string(),
            private_key: "test-private-key".to_string(),
            short_id: "0123456789abcdef".to_string(),
            sni_domain: "www.google.com".to_string(),
            reality_dest: "www.google.com:443".to_string(),
            log_level: LogLevel::Warning,
        };
        let options = InstallationOptions::default();

        let xray_config = template
            .create_initial_xray_config(&server_config, &options)
            .unwrap();

        // Parse the generated JSON to verify structure
        let config: serde_json::Value = serde_json::from_str(&xray_config).unwrap();

        // Check that the realitySettings contains shortIds as an array
        let inbounds = config["inbounds"].as_array().unwrap();
        let inbound = &inbounds[0];
        let reality_settings = inbound["streamSettings"]["realitySettings"]
            .as_object()
            .unwrap();

        // Verify shortIds field exists and is an array with empty string and short_id
        assert!(reality_settings.contains_key("shortIds"));
        let short_ids = reality_settings["shortIds"].as_array().unwrap();
        assert_eq!(short_ids.len(), 2);
        assert_eq!(short_ids[0], "");
        assert_eq!(short_ids[1], "0123456789abcdef");

        // Verify there's no shortId field (the problematic one)
        assert!(!reality_settings.contains_key("shortId"));

        // Verify fingerprint field is included
        assert!(reality_settings.contains_key("fingerprint"));
        assert_eq!(reality_settings["fingerprint"], "chrome");

        // Verify other Reality settings
        assert_eq!(reality_settings["dest"], "www.google.com:443");
        assert_eq!(reality_settings["privateKey"], "test-private-key");
        assert_eq!(reality_settings["show"], false);
        assert_eq!(reality_settings["xver"], 0);

        let server_names = reality_settings["serverNames"].as_array().unwrap();
        assert_eq!(server_names[0], "www.google.com");
    }
}
