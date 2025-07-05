use crate::error::Result;
use std::path::Path;
use std::process::Command;
use vpn_docker::{ContainerManager, HealthChecker};
use vpn_network::{PortChecker, SniValidator};

pub struct ConfigValidator {
    container_manager: ContainerManager,
    health_checker: HealthChecker,
}

#[derive(Debug, Clone)]
pub struct ValidationResult {
    pub is_valid: bool,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub checks: Vec<ValidationCheck>,
}

#[derive(Debug, Clone)]
pub struct ValidationCheck {
    pub name: String,
    pub status: CheckStatus,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CheckStatus {
    Pass,
    Warning,
    Fail,
}

impl ConfigValidator {
    pub fn new() -> Result<Self> {
        let container_manager = ContainerManager::new()?;
        let health_checker = HealthChecker::new()?;

        Ok(Self {
            container_manager,
            health_checker,
        })
    }

    pub async fn validate_installation(&self, install_path: &Path) -> Result<ValidationResult> {
        let mut result = ValidationResult {
            is_valid: true,
            errors: Vec::new(),
            warnings: Vec::new(),
            checks: Vec::new(),
        };

        // Check installation directory
        self.check_installation_directory(install_path, &mut result)
            .await;

        // Check Docker configuration
        self.check_docker_configuration(install_path, &mut result)
            .await;

        // Check container status
        self.check_container_status(&mut result).await;

        // Check network configuration
        self.check_network_configuration(install_path, &mut result)
            .await;

        // Check firewall rules
        self.check_firewall_configuration(&mut result).await;

        // Check logs
        self.check_log_files(install_path, &mut result).await;

        result.is_valid = result.errors.is_empty();

        Ok(result)
    }

    async fn check_installation_directory(
        &self,
        install_path: &Path,
        result: &mut ValidationResult,
    ) {
        let check_name = "Installation Directory";

        if !install_path.exists() {
            self.add_error(result, check_name, "Installation directory does not exist");
            return;
        }

        let required_files = ["docker-compose.yml", "config/config.json"];

        for file in &required_files {
            let file_path = install_path.join(file);
            if !file_path.exists() {
                self.add_error(
                    result,
                    check_name,
                    &format!("Required file missing: {}", file),
                );
            }
        }

        let optional_dirs = ["users", "logs"];
        for dir in &optional_dirs {
            let dir_path = install_path.join(dir);
            if !dir_path.exists() {
                self.add_warning(
                    result,
                    check_name,
                    &format!("Optional directory missing: {}", dir),
                );
            }
        }

        if result.errors.is_empty() {
            self.add_pass(
                result,
                check_name,
                "Installation directory structure is valid",
            );
        }
    }

    async fn check_docker_configuration(&self, install_path: &Path, result: &mut ValidationResult) {
        let check_name = "Docker Configuration";

        let compose_file = install_path.join("docker-compose.yml");
        if !compose_file.exists() {
            self.add_error(result, check_name, "docker-compose.yml not found");
            return;
        }

        // Validate docker-compose.yml syntax
        let output = Command::new("docker-compose")
            .arg("-f")
            .arg(&compose_file)
            .arg("config")
            .output();

        match output {
            Ok(output) => {
                if output.status.success() {
                    self.add_pass(result, check_name, "Docker Compose configuration is valid");
                } else {
                    self.add_error(
                        result,
                        check_name,
                        &format!(
                            "Docker Compose validation failed: {}",
                            String::from_utf8_lossy(&output.stderr)
                        ),
                    );
                }
            }
            Err(e) => {
                self.add_error(
                    result,
                    check_name,
                    &format!("Failed to validate Docker Compose: {}", e),
                );
            }
        }
    }

    async fn check_container_status(&self, result: &mut ValidationResult) {
        let check_name = "Container Status";

        let containers = ["xray", "shadowbox", "watchtower"];
        let mut running_containers = 0;

        for container in &containers {
            if self.container_manager.container_exists(container).await {
                match self.health_checker.check_container_health(container).await {
                    Ok(health) => {
                        if health.is_running {
                            running_containers += 1;
                            self.add_pass(
                                result,
                                &format!("{} Container", container),
                                &format!("Container {} is running and healthy", container),
                            );
                        } else {
                            self.add_error(
                                result,
                                &format!("{} Container", container),
                                &format!("Container {} is not running", container),
                            );
                        }
                    }
                    Err(e) => {
                        self.add_error(
                            result,
                            &format!("{} Container", container),
                            &format!("Failed to check container {}: {}", container, e),
                        );
                    }
                }
            }
        }

        if running_containers == 0 {
            self.add_error(result, check_name, "No VPN containers are running");
        } else {
            self.add_pass(
                result,
                check_name,
                &format!("{} containers running", running_containers),
            );
        }
    }

    async fn check_network_configuration(
        &self,
        install_path: &Path,
        result: &mut ValidationResult,
    ) {
        let check_name = "Network Configuration";

        // Read server configuration
        let config_file = install_path.join("config/config.json");
        if !config_file.exists() {
            self.add_error(result, check_name, "Server configuration file not found");
            return;
        }

        let config_content = match std::fs::read_to_string(&config_file) {
            Ok(content) => content,
            Err(e) => {
                self.add_error(result, check_name, &format!("Failed to read config: {}", e));
                return;
            }
        };

        let config: serde_json::Value = match serde_json::from_str(&config_content) {
            Ok(config) => config,
            Err(e) => {
                self.add_error(result, check_name, &format!("Invalid JSON config: {}", e));
                return;
            }
        };

        // Check port configuration
        if let Some(inbounds) = config["inbounds"].as_array() {
            for inbound in inbounds {
                if let Some(port) = inbound["port"].as_u64() {
                    let port = port as u16;

                    if !PortChecker::is_port_available(port) {
                        self.add_warning(
                            result,
                            "Port Check",
                            &format!(
                                "Port {} appears to be in use (expected for running server)",
                                port
                            ),
                        );
                    } else {
                        self.add_error(
                            result,
                            "Port Check",
                            &format!("Port {} is not in use (server may not be running)", port),
                        );
                    }
                }
            }
        }

        // Check SNI domain if present
        if let Some(reality_settings) =
            config["inbounds"][0]["streamSettings"]["realitySettings"].as_object()
        {
            if let Some(server_names) = reality_settings["serverNames"].as_array() {
                for server_name in server_names {
                    if let Some(sni) = server_name.as_str() {
                        match SniValidator::validate_sni(sni).await {
                            Ok(true) => {
                                self.add_pass(
                                    result,
                                    "SNI Validation",
                                    &format!("SNI domain {} is valid and reachable", sni),
                                );
                            }
                            Ok(false) => {
                                self.add_warning(
                                    result,
                                    "SNI Validation",
                                    &format!("SNI domain {} may not be optimal", sni),
                                );
                            }
                            Err(e) => {
                                self.add_error(
                                    result,
                                    "SNI Validation",
                                    &format!("SNI validation failed for {}: {}", sni, e),
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    async fn check_firewall_configuration(&self, result: &mut ValidationResult) {
        let check_name = "Firewall Configuration";

        if vpn_network::FirewallManager::is_ufw_installed().await {
            match vpn_network::FirewallManager::check_ufw_status().await {
                Ok(true) => {
                    self.add_pass(result, check_name, "UFW firewall is active");
                }
                Ok(false) => {
                    self.add_warning(result, check_name, "UFW firewall is inactive");
                }
                Err(e) => {
                    self.add_error(
                        result,
                        check_name,
                        &format!("Failed to check UFW status: {}", e),
                    );
                }
            }
        } else if vpn_network::FirewallManager::is_iptables_installed().await {
            self.add_pass(result, check_name, "iptables is available");
        } else {
            self.add_warning(result, check_name, "No firewall management tools found");
        }
    }

    async fn check_log_files(&self, install_path: &Path, result: &mut ValidationResult) {
        let check_name = "Log Files";

        let log_files = ["access.log", "error.log"];
        let logs_dir = install_path.join("logs");

        if !logs_dir.exists() {
            self.add_warning(result, check_name, "Logs directory does not exist");
            return;
        }

        for log_file in &log_files {
            let log_path = logs_dir.join(log_file);
            if log_path.exists() {
                let metadata = match std::fs::metadata(&log_path) {
                    Ok(metadata) => metadata,
                    Err(e) => {
                        self.add_error(
                            result,
                            check_name,
                            &format!("Failed to read log metadata: {}", e),
                        );
                        continue;
                    }
                };

                if metadata.len() > 0 {
                    self.add_pass(
                        result,
                        check_name,
                        &format!("Log file {} exists and has content", log_file),
                    );
                } else {
                    self.add_warning(
                        result,
                        check_name,
                        &format!("Log file {} is empty", log_file),
                    );
                }
            } else {
                self.add_warning(
                    result,
                    check_name,
                    &format!("Log file {} not found", log_file),
                );
            }
        }
    }

    fn add_pass(&self, result: &mut ValidationResult, name: &str, message: &str) {
        result.checks.push(ValidationCheck {
            name: name.to_string(),
            status: CheckStatus::Pass,
            message: message.to_string(),
        });
    }

    fn add_warning(&self, result: &mut ValidationResult, name: &str, message: &str) {
        result.warnings.push(message.to_string());
        result.checks.push(ValidationCheck {
            name: name.to_string(),
            status: CheckStatus::Warning,
            message: message.to_string(),
        });
    }

    fn add_error(&self, result: &mut ValidationResult, name: &str, message: &str) {
        result.errors.push(message.to_string());
        result.checks.push(ValidationCheck {
            name: name.to_string(),
            status: CheckStatus::Fail,
            message: message.to_string(),
        });
    }
}

impl CheckStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            CheckStatus::Pass => "PASS",
            CheckStatus::Warning => "WARN",
            CheckStatus::Fail => "FAIL",
        }
    }

    pub fn as_emoji(&self) -> &'static str {
        match self {
            CheckStatus::Pass => "✅",
            CheckStatus::Warning => "⚠️",
            CheckStatus::Fail => "❌",
        }
    }
}
