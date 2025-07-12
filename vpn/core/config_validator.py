"""
Configuration validation system with startup validation and schema generation.
"""

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from pydantic import ValidationError
from pydantic._internal._config import ConfigWrapper
from pydantic.json_schema import GenerateJsonSchema, JsonSchemaMode, JsonSchemaValue

from vpn.core.config_loader import ConfigLoader
from vpn.core.config_migration import ConfigMigrator, migrate_user_config
from vpn.core.enhanced_config import EnhancedSettings, get_settings
from vpn.core.exceptions import ConfigurationError
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ValidationIssue:
    """Represents a configuration validation issue."""
    
    def __init__(
        self,
        severity: str,
        path: str,
        message: str,
        suggestion: Optional[str] = None,
        value: Any = None
    ):
        self.severity = severity  # "error", "warning", "info"
        self.path = path  # Dotted path to the config key
        self.message = message
        self.suggestion = suggestion
        self.value = value
    
    def __str__(self) -> str:
        """String representation of validation issue."""
        result = f"[{self.severity.upper()}] {self.path}: {self.message}"
        if self.suggestion:
            result += f" Suggestion: {self.suggestion}"
        return result


class ConfigValidator:
    """Validates configuration files and settings."""
    
    def __init__(self):
        """Initialize config validator."""
        self.loader = ConfigLoader()
        self.migrator = ConfigMigrator()
    
    def validate_config_file(
        self,
        config_path: Path,
        auto_migrate: bool = True,
        strict: bool = False
    ) -> Tuple[bool, List[ValidationIssue]]:
        """Validate configuration file.
        
        Args:
            config_path: Path to configuration file
            auto_migrate: Whether to automatically migrate old configs
            strict: Whether to use strict validation
            
        Returns:
            Tuple of (is_valid, issues_list)
        """
        issues = []
        
        # Check if file exists
        if not config_path.exists():
            issues.append(ValidationIssue(
                severity="error",
                path="file",
                message=f"Configuration file not found: {config_path}",
                suggestion=f"Create config file or use 'vpn config generate'"
            ))
            return False, issues
        
        # Check if migration is needed
        if auto_migrate and self.migrator.needs_migration(config_path):
            logger.info(f"Configuration needs migration: {config_path}")
            
            try:
                result = self.migrator.migrate_config(config_path, backup=True)
                if result.success:
                    issues.append(ValidationIssue(
                        severity="info",
                        path="migration",
                        message=f"Configuration migrated from {result.from_version} to {result.to_version}",
                        suggestion="Review migrated configuration for accuracy"
                    ))
                    
                    # Add warnings from migration
                    for warning in result.warnings:
                        issues.append(ValidationIssue(
                            severity="warning",
                            path="migration",
                            message=warning
                        ))
                else:
                    issues.append(ValidationIssue(
                        severity="error",
                        path="migration",
                        message=f"Configuration migration failed",
                        suggestion="Manually update configuration or restore from backup"
                    ))
                    return False, issues
                    
            except Exception as e:
                issues.append(ValidationIssue(
                    severity="error",
                    path="migration",
                    message=f"Migration error: {e}",
                    suggestion="Check file permissions and format"
                ))
                return False, issues
        
        # Load and validate configuration
        try:
            config_data = self.loader.load_config(config_path)
        except Exception as e:
            issues.append(ValidationIssue(
                severity="error",
                path="loading",
                message=f"Failed to load configuration: {e}",
                suggestion="Check file format and syntax"
            ))
            return False, issues
        
        # Validate against schema
        try:
            settings = EnhancedSettings(**config_data)
            
            # Additional validation checks
            validation_issues = self._perform_additional_validation(settings, strict)
            issues.extend(validation_issues)
            
            # Check for unknown keys in strict mode
            if strict:
                unknown_issues = self._check_unknown_keys(config_data, settings)
                issues.extend(unknown_issues)
            
        except ValidationError as e:
            for error in e.errors():
                path = ".".join(str(loc) for loc in error["loc"])
                issues.append(ValidationIssue(
                    severity="error",
                    path=path,
                    message=error["msg"],
                    value=error.get("input")
                ))
            return False, issues
        
        # Determine overall validity
        has_errors = any(issue.severity == "error" for issue in issues)
        return not has_errors, issues
    
    def _perform_additional_validation(
        self,
        settings: EnhancedSettings,
        strict: bool
    ) -> List[ValidationIssue]:
        """Perform additional validation checks beyond Pydantic validation.
        
        Args:
            settings: Validated settings instance
            strict: Whether to use strict validation
            
        Returns:
            List of validation issues
        """
        issues = []
        
        # Check file system permissions
        issues.extend(self._validate_file_permissions(settings))
        
        # Check network configuration
        issues.extend(self._validate_network_config(settings))
        
        # Check Docker configuration
        issues.extend(self._validate_docker_config(settings))
        
        # Check security configuration
        issues.extend(self._validate_security_config(settings, strict))
        
        # Check resource limits
        issues.extend(self._validate_resource_limits(settings))
        
        return issues
    
    def _validate_file_permissions(self, settings: EnhancedSettings) -> List[ValidationIssue]:
        """Validate file system permissions."""
        issues = []
        
        # Check if install path is writable
        install_path = settings.paths.install_path
        if not os.access(install_path.parent, os.W_OK):
            issues.append(ValidationIssue(
                severity="warning",
                path="paths.install_path",
                message=f"Install path may not be writable: {install_path}",
                suggestion="Ensure proper permissions or use user directory"
            ))
        
        # Check if config directory exists and is writable
        config_path = settings.paths.config_path
        if config_path.exists() and not os.access(config_path, os.W_OK):
            issues.append(ValidationIssue(
                severity="error",
                path="paths.config_path",
                message=f"Config directory is not writable: {config_path}",
                suggestion="Fix directory permissions or choose different location"
            ))
        
        # Check data directory
        data_path = settings.paths.data_path
        if data_path.exists() and not os.access(data_path, os.W_OK):
            issues.append(ValidationIssue(
                severity="error",
                path="paths.data_path",
                message=f"Data directory is not writable: {data_path}",
                suggestion="Fix directory permissions or choose different location"
            ))
        
        return issues
    
    def _validate_network_config(self, settings: EnhancedSettings) -> List[ValidationIssue]:
        """Validate network configuration."""
        issues = []
        
        # Check port range sanity
        port_range = settings.network.default_port_range
        range_size = port_range[1] - port_range[0] + 1
        
        if range_size < 100:
            issues.append(ValidationIssue(
                severity="warning",
                path="network.default_port_range",
                message=f"Port range is quite small ({range_size} ports)",
                suggestion="Consider expanding port range for better availability"
            ))
        
        # Check for commonly used ports in range
        common_ports = {22, 80, 443, 3000, 5432, 6379, 8080, 8443, 9090}
        range_ports = set(range(port_range[0], port_range[1] + 1))
        conflicts = common_ports.intersection(range_ports)
        
        if conflicts:
            issues.append(ValidationIssue(
                severity="warning",
                path="network.default_port_range",
                message=f"Port range includes commonly used ports: {sorted(conflicts)}",
                suggestion="Consider excluding these ports or use higher range"
            ))
        
        # Validate blocked ports
        blocked_ports = settings.network.blocked_ports
        if blocked_ports:
            invalid_blocked = [p for p in blocked_ports if not (1 <= p <= 65535)]
            if invalid_blocked:
                issues.append(ValidationIssue(
                    severity="error",
                    path="network.blocked_ports",
                    message=f"Invalid port numbers in blocked_ports: {invalid_blocked}",
                    suggestion="Use valid port numbers (1-65535)"
                ))
        
        return issues
    
    def _validate_docker_config(self, settings: EnhancedSettings) -> List[ValidationIssue]:
        """Validate Docker configuration."""
        issues = []
        
        # Check Docker socket accessibility
        docker_socket = settings.docker.socket
        if docker_socket.startswith("unix://"):
            socket_path = docker_socket[7:]
        else:
            socket_path = docker_socket
        
        if socket_path.startswith("/") and not Path(socket_path).exists():
            issues.append(ValidationIssue(
                severity="warning",
                path="docker.socket",
                message=f"Docker socket not found: {socket_path}",
                suggestion="Ensure Docker is installed and running"
            ))
        
        # Check Docker timeout sanity
        if settings.docker.timeout < 10:
            issues.append(ValidationIssue(
                severity="warning",
                path="docker.timeout",
                message="Docker timeout is very low, may cause operations to fail",
                suggestion="Consider using at least 30 seconds"
            ))
        
        # Check connection pool size
        if settings.docker.max_connections > 20:
            issues.append(ValidationIssue(
                severity="warning",
                path="docker.max_connections",
                message="Docker connection pool is quite large",
                suggestion="High connection count may impact performance"
            ))
        
        return issues
    
    def _validate_security_config(
        self,
        settings: EnhancedSettings,
        strict: bool
    ) -> List[ValidationIssue]:
        """Validate security configuration."""
        issues = []
        
        # Check secret key strength
        if settings.security.enable_auth:
            secret_key = settings.security.secret_key
            if secret_key and len(secret_key) < 32:
                issues.append(ValidationIssue(
                    severity="error",
                    path="security.secret_key",
                    message="Secret key is too short",
                    suggestion="Use at least 32 characters for security"
                ))
        
        # Check token expiration
        token_expire = settings.security.token_expire_minutes
        if token_expire > 60 * 24 * 7:  # 1 week
            severity = "error" if strict else "warning"
            issues.append(ValidationIssue(
                severity=severity,
                path="security.token_expire_minutes",
                message="Token expiration is very long, may be security risk",
                suggestion="Consider shorter expiration time"
            ))
        
        # Check password requirements
        if settings.security.password_min_length < 8:
            issues.append(ValidationIssue(
                severity="warning",
                path="security.password_min_length",
                message="Minimum password length is below recommended",
                suggestion="Consider requiring at least 8 characters"
            ))
        
        return issues
    
    def _validate_resource_limits(self, settings: EnhancedSettings) -> List[ValidationIssue]:
        """Validate resource limits and thresholds."""
        issues = []
        
        # Check monitoring thresholds
        cpu_threshold = settings.monitoring.alert_cpu_threshold
        memory_threshold = settings.monitoring.alert_memory_threshold
        disk_threshold = settings.monitoring.alert_disk_threshold
        
        if cpu_threshold > 95:
            issues.append(ValidationIssue(
                severity="warning",
                path="monitoring.alert_cpu_threshold",
                message="CPU alert threshold is very high",
                suggestion="Consider lower threshold for early warnings"
            ))
        
        if memory_threshold > 95:
            issues.append(ValidationIssue(
                severity="warning",
                path="monitoring.alert_memory_threshold",
                message="Memory alert threshold is very high",
                suggestion="Consider lower threshold for early warnings"
            ))
        
        if disk_threshold > 90:
            issues.append(ValidationIssue(
                severity="warning",
                path="monitoring.alert_disk_threshold",
                message="Disk alert threshold is very high",
                suggestion="Consider lower threshold to prevent disk full issues"
            ))
        
        # Check database pool sizes
        if settings.database.pool_size > 20:
            issues.append(ValidationIssue(
                severity="warning",
                path="database.pool_size",
                message="Database pool size is quite large",
                suggestion="Large pools may impact memory usage"
            ))
        
        return issues
    
    def validate_environment_variables(self) -> Tuple[bool, List[ValidationIssue]]:
        """Validate environment variables.
        
        Returns:
            Tuple of (is_valid, issues_list)
        """
        issues = []
        
        # Get all VPN_* environment variables
        vpn_env_vars = {k: v for k, v in os.environ.items() if k.startswith("VPN_")}
        
        if not vpn_env_vars:
            issues.append(ValidationIssue(
                severity="info",
                path="environment",
                message="No VPN environment variables found",
                suggestion="This is normal if using configuration files only"
            ))
            return True, issues
        
        # Check for deprecated variables
        deprecated_vars = {
            "VPN_INSTALL_PATH": "VPN_PATHS__INSTALL_PATH",
            "VPN_CONFIG_PATH": "VPN_PATHS__CONFIG_PATH", 
            "VPN_DATA_PATH": "VPN_PATHS__DATA_PATH",
            "VPN_DATABASE_URL": "VPN_DATABASE__URL",
            "VPN_DOCKER_HOST": "VPN_DOCKER__SOCKET",
            "VPN_DOCKER_SOCKET": "VPN_DOCKER__SOCKET",
            "VPN_NO_COLOR": "Use --no-color CLI flag"
        }
        
        for old_var, new_var in deprecated_vars.items():
            if old_var in vpn_env_vars:
                issues.append(ValidationIssue(
                    severity="warning",
                    path=f"environment.{old_var}",
                    message=f"Deprecated environment variable: {old_var}",
                    suggestion=f"Use {new_var} instead",
                    value=vpn_env_vars[old_var]
                ))
        
        # Validate specific environment variable formats
        issues.extend(self._validate_env_var_formats(vpn_env_vars))
        
        # Check for environment variable conflicts
        issues.extend(self._check_env_var_conflicts(vpn_env_vars))
        
        # Validate environment variable values
        issues.extend(self._validate_env_var_values(vpn_env_vars))
        
        # Check if environment can create valid settings
        try:
            # Test loading settings with environment variables
            test_settings = EnhancedSettings()
            issues.append(ValidationIssue(
                severity="info",
                path="environment",
                message=f"Environment variables successfully loaded ({len(vpn_env_vars)} variables)",
                suggestion="Configuration is valid"
            ))
        except ValidationError as e:
            for error in e.errors():
                env_path = ".".join(str(loc) for loc in error["loc"])
                issues.append(ValidationIssue(
                    severity="error",
                    path=f"environment.{env_path}",
                    message=f"Environment variable validation error: {error['msg']}",
                    suggestion="Check environment variable format and value",
                    value=error.get("input")
                ))
        
        # Determine overall validity
        has_errors = any(issue.severity == "error" for issue in issues)
        return not has_errors, issues
    
    def _validate_env_var_formats(self, env_vars: Dict[str, str]) -> List[ValidationIssue]:
        """Validate environment variable formats."""
        issues = []
        
        # Check for proper nested delimiter format
        for var_name, value in env_vars.items():
            if "__" in var_name:
                # Check for triple or more underscores (likely mistake)
                if "___" in var_name:
                    issues.append(ValidationIssue(
                        severity="warning",
                        path=f"environment.{var_name}",
                        message="Environment variable contains triple underscores",
                        suggestion="Use double underscores (__) for nesting",
                        value=value
                    ))
                
                # Check for invalid nested formats
                parts = var_name.split("__")
                if len(parts) > 3:  # VPN_SECTION__SUBSECTION__KEY is max depth
                    issues.append(ValidationIssue(
                        severity="warning",
                        path=f"environment.{var_name}",
                        message="Environment variable has too many nesting levels",
                        suggestion="Maximum nesting is VPN_SECTION__KEY format",
                        value=value
                    ))
        
        # Check for specific format requirements
        format_checks = {
            "VPN_NETWORK__DEFAULT_PORT_RANGE": self._validate_port_range_format,
            "VPN_DATABASE__URL": self._validate_database_url_format,
            "VPN_MONITORING__OTLP_ENDPOINT": self._validate_url_format,
            "VPN_DOCKER__REGISTRY_URL": self._validate_url_format,
        }
        
        for var_name, validator in format_checks.items():
            if var_name in env_vars:
                validation_issues = validator(var_name, env_vars[var_name])
                issues.extend(validation_issues)
        
        return issues
    
    def _validate_port_range_format(self, var_name: str, value: str) -> List[ValidationIssue]:
        """Validate port range format."""
        issues = []
        
        try:
            # Should be "min,max" format
            if "," not in value:
                issues.append(ValidationIssue(
                    severity="error",
                    path=f"environment.{var_name}",
                    message="Port range should be in 'min,max' format",
                    suggestion="Example: '10000,65000'",
                    value=value
                ))
                return issues
            
            parts = value.split(",")
            if len(parts) != 2:
                issues.append(ValidationIssue(
                    severity="error",
                    path=f"environment.{var_name}",
                    message="Port range should contain exactly two numbers",
                    suggestion="Example: '10000,65000'",
                    value=value
                ))
                return issues
            
            min_port, max_port = int(parts[0].strip()), int(parts[1].strip())
            
            if min_port >= max_port:
                issues.append(ValidationIssue(
                    severity="error",
                    path=f"environment.{var_name}",
                    message="Minimum port must be less than maximum port",
                    suggestion="Ensure first number is smaller than second",
                    value=value
                ))
            
            if not (1 <= min_port <= 65535) or not (1 <= max_port <= 65535):
                issues.append(ValidationIssue(
                    severity="error",
                    path=f"environment.{var_name}",
                    message="Port numbers must be between 1 and 65535",
                    suggestion="Use valid port range",
                    value=value
                ))
                
        except ValueError:
            issues.append(ValidationIssue(
                severity="error",
                path=f"environment.{var_name}",
                message="Port range contains non-numeric values",
                suggestion="Use numeric values: '10000,65000'",
                value=value
            ))
        
        return issues
    
    def _validate_database_url_format(self, var_name: str, value: str) -> List[ValidationIssue]:
        """Validate database URL format."""
        issues = []
        
        supported_schemes = ["sqlite", "sqlite+aiosqlite", "postgresql", "mysql"]
        
        if "://" not in value:
            issues.append(ValidationIssue(
                severity="error",
                path=f"environment.{var_name}",
                message="Database URL missing scheme",
                suggestion=f"Use one of: {', '.join(supported_schemes)}://",
                value=value
            ))
            return issues
        
        scheme = value.split("://")[0]
        if scheme not in supported_schemes:
            issues.append(ValidationIssue(
                severity="warning",
                path=f"environment.{var_name}",
                message=f"Unsupported database scheme: {scheme}",
                suggestion=f"Supported schemes: {', '.join(supported_schemes)}",
                value=value
            ))
        
        return issues
    
    def _validate_url_format(self, var_name: str, value: str) -> List[ValidationIssue]:
        """Validate general URL format."""
        issues = []
        
        if not value.startswith(("http://", "https://")):
            issues.append(ValidationIssue(
                severity="error",
                path=f"environment.{var_name}",
                message="URL must start with http:// or https://",
                suggestion="Add proper URL scheme",
                value=value
            ))
        
        return issues
    
    def _check_env_var_conflicts(self, env_vars: Dict[str, str]) -> List[ValidationIssue]:
        """Check for conflicting environment variables."""
        issues = []
        
        # Check for old/new variable conflicts
        conflicts = [
            ("VPN_INSTALL_PATH", "VPN_PATHS__INSTALL_PATH"),
            ("VPN_CONFIG_PATH", "VPN_PATHS__CONFIG_PATH"),
            ("VPN_DATA_PATH", "VPN_PATHS__DATA_PATH"),
            ("VPN_DATABASE_URL", "VPN_DATABASE__URL"),
            ("VPN_DOCKER_SOCKET", "VPN_DOCKER__SOCKET"),
        ]
        
        for old_var, new_var in conflicts:
            if old_var in env_vars and new_var in env_vars:
                issues.append(ValidationIssue(
                    severity="warning",
                    path=f"environment.conflict",
                    message=f"Both {old_var} and {new_var} are set",
                    suggestion=f"Remove {old_var} and use only {new_var}",
                    value=f"{old_var}={env_vars[old_var]}, {new_var}={env_vars[new_var]}"
                ))
        
        # Check for conflicting authentication settings
        if env_vars.get("VPN_SECURITY__ENABLE_AUTH") == "false" and "VPN_SECURITY__SECRET_KEY" in env_vars:
            issues.append(ValidationIssue(
                severity="warning",
                path="environment.security",
                message="Secret key set but authentication is disabled",
                suggestion="Enable authentication or remove secret key",
                value="AUTH=false but SECRET_KEY is set"
            ))
        
        return issues
    
    def _validate_env_var_values(self, env_vars: Dict[str, str]) -> List[ValidationIssue]:
        """Validate environment variable values."""
        issues = []
        
        # Boolean value checks
        boolean_vars = [
            "VPN_DEBUG", "VPN_AUTO_START_SERVERS", "VPN_RELOAD", "VPN_PROFILE",
            "VPN_DATABASE__ECHO", "VPN_NETWORK__ENABLE_FIREWALL", 
            "VPN_NETWORK__FIREWALL_BACKUP", "VPN_SECURITY__ENABLE_AUTH",
            "VPN_SECURITY__REQUIRE_PASSWORD_COMPLEXITY", "VPN_MONITORING__ENABLE_METRICS",
            "VPN_MONITORING__ENABLE_OPENTELEMETRY", "VPN_TUI__SHOW_STATS",
            "VPN_TUI__SHOW_HELP", "VPN_TUI__ENABLE_MOUSE"
        ]
        
        for var in boolean_vars:
            if var in env_vars:
                value = env_vars[var].lower()
                if value not in ["true", "false", "1", "0", "yes", "no", "on", "off"]:
                    issues.append(ValidationIssue(
                        severity="error",
                        path=f"environment.{var}",
                        message="Boolean environment variable has invalid value",
                        suggestion="Use: true/false, 1/0, yes/no, or on/off",
                        value=env_vars[var]
                    ))
        
        # Numeric value checks
        numeric_vars = {
            "VPN_DATABASE__POOL_SIZE": (1, 50),
            "VPN_DATABASE__MAX_OVERFLOW": (0, 100),
            "VPN_DATABASE__POOL_TIMEOUT": (1, 300),
            "VPN_DOCKER__TIMEOUT": (5, 600),
            "VPN_DOCKER__MAX_CONNECTIONS": (1, 50),
            "VPN_SECURITY__TOKEN_EXPIRE_MINUTES": (1, 43200),  # 1 min to 30 days
            "VPN_SECURITY__MAX_LOGIN_ATTEMPTS": (1, 10),
            "VPN_SECURITY__LOCKOUT_DURATION": (1, 1440),  # 1 min to 24 hours
            "VPN_SECURITY__PASSWORD_MIN_LENGTH": (4, 128),
            "VPN_MONITORING__METRICS_PORT": (1024, 65535),
            "VPN_MONITORING__METRICS_RETENTION_DAYS": (1, 365),
            "VPN_MONITORING__HEALTH_CHECK_INTERVAL": (5, 3600),
            "VPN_TUI__REFRESH_RATE": (1, 60),
            "VPN_TUI__PAGE_SIZE": (5, 1000),
        }
        
        for var, (min_val, max_val) in numeric_vars.items():
            if var in env_vars:
                try:
                    value = int(env_vars[var])
                    if not (min_val <= value <= max_val):
                        issues.append(ValidationIssue(
                            severity="warning",
                            path=f"environment.{var}",
                            message=f"Value {value} outside recommended range ({min_val}-{max_val})",
                            suggestion=f"Use value between {min_val} and {max_val}",
                            value=env_vars[var]
                        ))
                except ValueError:
                    issues.append(ValidationIssue(
                        severity="error",
                        path=f"environment.{var}",
                        message="Numeric environment variable has non-numeric value",
                        suggestion="Use a numeric value",
                        value=env_vars[var]
                    ))
        
        # Float value checks
        float_vars = {
            "VPN_MONITORING__ALERT_CPU_THRESHOLD": (0.0, 100.0),
            "VPN_MONITORING__ALERT_MEMORY_THRESHOLD": (0.0, 100.0),
            "VPN_MONITORING__ALERT_DISK_THRESHOLD": (0.0, 100.0),
            "VPN_TUI__ANIMATION_DURATION": (0.0, 5.0),
        }
        
        for var, (min_val, max_val) in float_vars.items():
            if var in env_vars:
                try:
                    value = float(env_vars[var])
                    if not (min_val <= value <= max_val):
                        issues.append(ValidationIssue(
                            severity="warning",
                            path=f"environment.{var}",
                            message=f"Value {value} outside valid range ({min_val}-{max_val})",
                            suggestion=f"Use value between {min_val} and {max_val}",
                            value=env_vars[var]
                        ))
                except ValueError:
                    issues.append(ValidationIssue(
                        severity="error",
                        path=f"environment.{var}",
                        message="Numeric environment variable has non-numeric value",
                        suggestion="Use a numeric value",
                        value=env_vars[var]
                    ))
        
        # Choice value checks
        choice_vars = {
            "VPN_LOG_LEVEL": ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
            "VPN_DEFAULT_PROTOCOL": ["vless", "shadowsocks", "wireguard", "openvpn"],
            "VPN_TUI__THEME": ["dark", "light"],
        }
        
        for var, valid_choices in choice_vars.items():
            if var in env_vars:
                value = env_vars[var]
                if value not in valid_choices:
                    issues.append(ValidationIssue(
                        severity="error",
                        path=f"environment.{var}",
                        message=f"Invalid choice: {value}",
                        suggestion=f"Valid choices: {', '.join(valid_choices)}",
                        value=value
                    ))
        
        return issues
    
    def _check_unknown_keys(
        self,
        config_data: Dict[str, Any],
        settings: EnhancedSettings
    ) -> List[ValidationIssue]:
        """Check for unknown configuration keys."""
        issues = []
        
        # Get valid keys from schema
        schema = settings.model_json_schema()
        valid_keys = self._extract_valid_keys(schema)
        
        # Find unknown keys
        unknown_keys = self._find_unknown_keys(config_data, valid_keys)
        
        for key in unknown_keys:
            issues.append(ValidationIssue(
                severity="warning",
                path=key,
                message="Unknown configuration key",
                suggestion="Remove unknown key or check for typos"
            ))
        
        return issues
    
    def _extract_valid_keys(self, schema: Dict[str, Any], prefix: str = "") -> Set[str]:
        """Extract valid configuration keys from JSON schema."""
        valid_keys = set()
        
        if "properties" in schema:
            for key, value in schema["properties"].items():
                full_key = f"{prefix}.{key}" if prefix else key
                valid_keys.add(full_key)
                
                # Recursively process nested objects
                if isinstance(value, dict) and "properties" in value:
                    nested_keys = self._extract_valid_keys(value, full_key)
                    valid_keys.update(nested_keys)
        
        return valid_keys
    
    def _find_unknown_keys(
        self,
        config_data: Dict[str, Any],
        valid_keys: Set[str],
        prefix: str = ""
    ) -> Set[str]:
        """Find unknown keys in configuration data."""
        unknown_keys = set()
        
        for key, value in config_data.items():
            if key == "meta":  # Skip metadata
                continue
                
            full_key = f"{prefix}.{key}" if prefix else key
            
            if full_key not in valid_keys:
                unknown_keys.add(full_key)
            
            # Check nested dictionaries
            if isinstance(value, dict):
                nested_unknown = self._find_unknown_keys(value, valid_keys, full_key)
                unknown_keys.update(nested_unknown)
        
        return unknown_keys
    
    def validate_on_startup(
        self,
        config_paths: Optional[List[Path]] = None,
        exit_on_error: bool = True
    ) -> bool:
        """Validate configuration on application startup.
        
        Args:
            config_paths: Optional list of config paths to validate
            exit_on_error: Whether to exit application on validation errors
            
        Returns:
            True if validation passed
        """
        logger.info("Validating configuration on startup...")
        
        if config_paths is None:
            # Use default config paths
            settings = get_settings()
            config_paths = settings.config_file_paths
        
        validation_passed = True
        found_config = False
        
        for config_path in config_paths:
            if not config_path.exists():
                continue
            
            found_config = True
            logger.info(f"Validating config file: {config_path}")
            
            is_valid, issues = self.validate_config_file(
                config_path,
                auto_migrate=True,
                strict=False
            )
            
            # Log validation results
            if issues:
                for issue in issues:
                    if issue.severity == "error":
                        logger.error(str(issue))
                    elif issue.severity == "warning":
                        logger.warning(str(issue))
                    else:
                        logger.info(str(issue))
            
            if not is_valid:
                validation_passed = False
                logger.error(f"Configuration validation failed: {config_path}")
            else:
                logger.info(f"Configuration validation passed: {config_path}")
        
        if not found_config:
            logger.warning("No configuration files found, using defaults")
            # Try to create an example config
            self._create_default_config()
        
        if not validation_passed and exit_on_error:
            logger.critical("Configuration validation failed, exiting...")
            sys.exit(1)
        
        return validation_passed
    
    def _create_default_config(self):
        """Create default configuration file."""
        try:
            settings = get_settings()
            config_path = settings.paths.config_path / "config.yaml"
            
            if not config_path.exists():
                logger.info(f"Creating default configuration: {config_path}")
                
                # Use the enhanced config loader to generate example
                example_content = self.loader.generate_example_config(
                    format_type="yaml",
                    include_comments=True
                )
                
                config_path.parent.mkdir(parents=True, exist_ok=True)
                config_path.write_text(example_content)
                
                logger.info(f"Default configuration created: {config_path}")
                
        except Exception as e:
            logger.error(f"Failed to create default configuration: {e}")


class ConfigSchemaGenerator:
    """Generates JSON schema and documentation for configuration."""
    
    def __init__(self):
        """Initialize schema generator."""
        self.settings_class = EnhancedSettings
    
    def generate_json_schema(
        self,
        mode: JsonSchemaMode = "validation"
    ) -> Dict[str, Any]:
        """Generate JSON schema for configuration.
        
        Args:
            mode: Schema generation mode
            
        Returns:
            JSON schema dictionary
        """
        return self.settings_class.model_json_schema(mode=mode)
    
    def generate_schema_documentation(
        self,
        format_type: str = "markdown"
    ) -> str:
        """Generate human-readable schema documentation.
        
        Args:
            format_type: Output format ("markdown", "html", "text")
            
        Returns:
            Formatted documentation string
        """
        schema = self.generate_json_schema()
        
        if format_type == "markdown":
            return self._generate_markdown_docs(schema)
        elif format_type == "html":
            return self._generate_html_docs(schema)
        else:
            return self._generate_text_docs(schema)
    
    def _generate_markdown_docs(self, schema: Dict[str, Any]) -> str:
        """Generate Markdown documentation from schema."""
        docs = ["# VPN Manager Configuration Schema", ""]
        docs.extend(self._process_schema_properties(schema, level=2))
        return "\n".join(docs)
    
    def _process_schema_properties(
        self,
        schema: Dict[str, Any],
        level: int = 2
    ) -> List[str]:
        """Process schema properties recursively."""
        docs = []
        
        if "properties" not in schema:
            return docs
        
        for prop_name, prop_schema in schema["properties"].items():
            docs.append(f"{'#' * level} {prop_name}")
            docs.append("")
            
            # Add description
            if "description" in prop_schema:
                docs.append(prop_schema["description"])
                docs.append("")
            
            # Add type information
            if "type" in prop_schema:
                docs.append(f"**Type:** `{prop_schema['type']}`")
            
            # Add default value
            if "default" in prop_schema:
                docs.append(f"**Default:** `{prop_schema['default']}`")
            
            # Add constraints
            constraints = []
            if "minimum" in prop_schema:
                constraints.append(f"≥ {prop_schema['minimum']}")
            if "maximum" in prop_schema:
                constraints.append(f"≤ {prop_schema['maximum']}")
            if "minLength" in prop_schema:
                constraints.append(f"min length: {prop_schema['minLength']}")
            if "maxLength" in prop_schema:
                constraints.append(f"max length: {prop_schema['maxLength']}")
            if "enum" in prop_schema:
                constraints.append(f"one of: {', '.join(map(str, prop_schema['enum']))}")
            
            if constraints:
                docs.append(f"**Constraints:** {', '.join(constraints)}")
            
            docs.append("")
            
            # Process nested properties
            if prop_schema.get("type") == "object" and "properties" in prop_schema:
                nested_docs = self._process_schema_properties(prop_schema, level + 1)
                docs.extend(nested_docs)
        
        return docs
    
    def _generate_html_docs(self, schema: Dict[str, Any]) -> str:
        """Generate HTML documentation from schema."""
        # Simplified HTML generation
        html = ["<h1>VPN Manager Configuration Schema</h1>"]
        # Add HTML processing here
        return "\n".join(html)
    
    def _generate_text_docs(self, schema: Dict[str, Any]) -> str:
        """Generate plain text documentation from schema."""
        # Simplified text generation
        text = ["VPN Manager Configuration Schema", "=" * 35, ""]
        # Add text processing here
        return "\n".join(text)
    
    def save_schema_file(
        self,
        output_path: Path,
        format_type: str = "json"
    ):
        """Save schema to file.
        
        Args:
            output_path: Path to save schema file
            format_type: Output format ("json", "markdown", "html")
        """
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        if format_type == "json":
            schema = self.generate_json_schema()
            with open(output_path, 'w') as f:
                json.dump(schema, f, indent=2)
        else:
            docs = self.generate_schema_documentation(format_type)
            output_path.write_text(docs)
        
        logger.info(f"Schema saved to: {output_path}")


# Global validator instance
_config_validator: Optional[ConfigValidator] = None


def get_config_validator() -> ConfigValidator:
    """Get the global config validator instance."""
    global _config_validator
    if _config_validator is None:
        _config_validator = ConfigValidator()
    return _config_validator


def validate_startup_config(exit_on_error: bool = True) -> bool:
    """Validate configuration on application startup.
    
    Args:
        exit_on_error: Whether to exit on validation errors
        
    Returns:
        True if validation passed
    """
    validator = get_config_validator()
    return validator.validate_on_startup(exit_on_error=exit_on_error)