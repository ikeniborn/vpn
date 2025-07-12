"""
Tests for configuration validation system.
"""

import json
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest
import yaml

from vpn.core.config_validator import (
    ConfigSchemaGenerator,
    ConfigValidator,
    ValidationIssue,
    get_config_validator,
    validate_startup_config,
)
from vpn.core.enhanced_config import EnhancedSettings


class TestValidationIssue:
    """Test ValidationIssue class."""
    
    def test_basic_issue(self):
        """Test basic validation issue."""
        issue = ValidationIssue(
            severity="error",
            path="database.url",
            message="Invalid URL format",
            suggestion="Use sqlite:// or postgresql:// scheme",
            value="invalid-url"
        )
        
        assert issue.severity == "error"
        assert issue.path == "database.url"
        assert issue.message == "Invalid URL format"
        assert issue.suggestion == "Use sqlite:// or postgresql:// scheme"
        assert issue.value == "invalid-url"
    
    def test_issue_string_representation(self):
        """Test string representation of issue."""
        issue = ValidationIssue(
            severity="warning",
            path="network.port_range",
            message="Port range is small",
            suggestion="Consider larger range"
        )
        
        expected = "[WARNING] network.port_range: Port range is small Suggestion: Consider larger range"
        assert str(issue) == expected
    
    def test_issue_without_suggestion(self):
        """Test issue without suggestion."""
        issue = ValidationIssue(
            severity="error",
            path="paths.install",
            message="Directory not found"
        )
        
        expected = "[ERROR] paths.install: Directory not found"
        assert str(issue) == expected


class TestConfigValidator:
    """Test ConfigValidator class."""
    
    def test_validator_initialization(self):
        """Test validator initialization."""
        validator = ConfigValidator()
        
        assert validator.loader is not None
        assert validator.migrator is not None
    
    def test_validate_nonexistent_file(self):
        """Test validation of non-existent config file."""
        validator = ConfigValidator()
        nonexistent_path = Path("/nonexistent/config.yaml")
        
        is_valid, issues = validator.validate_config_file(nonexistent_path)
        
        assert not is_valid
        assert len(issues) == 1
        assert issues[0].severity == "error"
        assert "not found" in issues[0].message
    
    def test_validate_valid_config(self):
        """Test validation of valid configuration."""
        validator = ConfigValidator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            valid_config = {
                "meta": {"version": "2.0.0"},
                "app_name": "Test VPN",
                "debug": False,
                "log_level": "INFO",
                "database": {
                    "url": "sqlite:///test.db",
                    "echo": False
                },
                "docker": {
                    "socket": "/var/run/docker.sock",
                    "timeout": 30
                },
                "network": {
                    "default_port_range": [10000, 20000],
                    "enable_firewall": True
                },
                "security": {
                    "enable_auth": True,
                    "secret_key": "very-secret-key-that-is-long-enough",
                    "token_expire_minutes": 1440
                }
            }
            yaml.dump(valid_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            is_valid, issues = validator.validate_config_file(config_path, auto_migrate=False)
            
            assert is_valid
            # May have warnings but no errors
            error_issues = [i for i in issues if i.severity == "error"]
            assert len(error_issues) == 0
            
        finally:
            config_path.unlink()
    
    def test_validate_config_with_errors(self):
        """Test validation of config with errors."""
        validator = ConfigValidator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            invalid_config = {
                "database": {
                    "url": "invalid-scheme://test.db",  # Invalid scheme
                    "pool_size": 0  # Invalid pool size
                },
                "network": {
                    "default_port_range": [80, 70]  # Invalid range (min > max)
                },
                "security": {
                    "secret_key": "short",  # Too short
                    "token_expire_minutes": 5  # Too short
                }
            }
            yaml.dump(invalid_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            is_valid, issues = validator.validate_config_file(config_path, auto_migrate=False)
            
            assert not is_valid
            error_issues = [i for i in issues if i.severity == "error"]
            assert len(error_issues) > 0
            
            # Check specific errors
            error_paths = [i.path for i in error_issues]
            assert any("database.url" in path for path in error_paths)
            assert any("pool_size" in path for path in error_paths)
            assert any("port_range" in path for path in error_paths)
            
        finally:
            config_path.unlink()
    
    def test_validate_with_migration(self):
        """Test validation with automatic migration."""
        validator = ConfigValidator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Old format config that needs migration
            old_config = {
                "database_url": "sqlite:///old.db",
                "docker_socket": "/var/run/docker.sock",
                "tui_theme": "dark",
                "enable_firewall": True
            }
            yaml.dump(old_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            is_valid, issues = validator.validate_config_file(
                config_path,
                auto_migrate=True,
                strict=False
            )
            
            # Should be valid after migration
            assert is_valid
            
            # Should have migration info issues
            migration_issues = [i for i in issues if "migration" in i.path]
            assert len(migration_issues) > 0
            
            # Check that file was actually migrated
            migrated_content = yaml.safe_load(config_path.read_text())
            assert "database" in migrated_content
            assert "docker" in migrated_content
            assert migrated_content["database"]["url"] == "sqlite:///old.db"
            
        finally:
            config_path.unlink(missing_ok=True)
            # Clean up backup file if created
            backup_files = list(config_path.parent.glob(f"{config_path.stem}_backup_*"))
            for backup in backup_files:
                backup.unlink(missing_ok=True)
    
    def test_file_permissions_validation(self):
        """Test file permissions validation."""
        validator = ConfigValidator()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            
            # Create settings with paths in temp directory
            settings = EnhancedSettings()
            settings.paths.config_path = temp_path / "config"
            settings.paths.data_path = temp_path / "data"
            settings.paths.install_path = temp_path / "install"
            
            # Create directories
            settings.paths.config_path.mkdir()
            settings.paths.data_path.mkdir()
            settings.paths.install_path.mkdir()
            
            # Test with accessible directories
            issues = validator._validate_file_permissions(settings)
            
            # Should have no permission issues in temp directory
            permission_errors = [i for i in issues if i.severity == "error" and "writable" in i.message]
            assert len(permission_errors) == 0
    
    def test_network_config_validation(self):
        """Test network configuration validation."""
        validator = ConfigValidator()
        
        # Test with small port range
        settings = EnhancedSettings()
        settings.network.default_port_range = (8000, 8050)  # Only 51 ports
        
        issues = validator._validate_network_config(settings)
        
        # Should warn about small range
        small_range_warnings = [i for i in issues if "small" in i.message.lower()]
        assert len(small_range_warnings) > 0
        
        # Test with commonly used ports
        settings.network.default_port_range = (80, 8080)  # Includes common ports
        
        issues = validator._validate_network_config(settings)
        
        # Should warn about common ports
        common_port_warnings = [i for i in issues if "commonly used" in i.message]
        assert len(common_port_warnings) > 0
    
    def test_docker_config_validation(self):
        """Test Docker configuration validation."""
        validator = ConfigValidator()
        
        # Test with very low timeout
        settings = EnhancedSettings()
        settings.docker.timeout = 5
        
        issues = validator._validate_docker_config(settings)
        
        # Should warn about low timeout
        timeout_warnings = [i for i in issues if "timeout" in i.message.lower()]
        assert len(timeout_warnings) > 0
        
        # Test with high connection count
        settings.docker.max_connections = 25
        
        issues = validator._validate_docker_config(settings)
        
        # Should warn about high connection count
        connection_warnings = [i for i in issues if "connection" in i.message.lower()]
        assert len(connection_warnings) > 0
    
    def test_security_config_validation(self):
        """Test security configuration validation."""
        validator = ConfigValidator()
        
        # Test with short secret key
        settings = EnhancedSettings()
        settings.security.secret_key = "short"
        
        issues = validator._validate_security_config(settings, strict=False)
        
        # Should error on short secret key
        secret_errors = [i for i in issues if "secret" in i.message.lower()]
        assert len(secret_errors) > 0
        
        # Test with very long token expiration
        settings.security.token_expire_minutes = 60 * 24 * 30  # 30 days
        
        issues = validator._validate_security_config(settings, strict=True)
        
        # Should warn/error on long expiration
        expiration_issues = [i for i in issues if "expiration" in i.message.lower()]
        assert len(expiration_issues) > 0
    
    def test_unknown_keys_detection(self):
        """Test detection of unknown configuration keys."""
        validator = ConfigValidator()
        
        config_data = {
            "app_name": "Test",
            "unknown_key": "value",
            "database": {
                "url": "sqlite:///test.db",
                "unknown_nested": "nested_value"
            },
            "completely_unknown_section": {
                "key": "value"
            }
        }
        
        settings = EnhancedSettings(**{k: v for k, v in config_data.items() 
                                    if k not in ["unknown_key", "completely_unknown_section"]})
        
        issues = validator._check_unknown_keys(config_data, settings)
        
        # Should detect unknown keys
        unknown_paths = [i.path for i in issues]
        assert "unknown_key" in unknown_paths
        assert "database.unknown_nested" in unknown_paths
        assert "completely_unknown_section" in unknown_paths
    
    @patch('vpn.core.config_validator.logger')
    def test_validate_on_startup_no_config(self, mock_logger):
        """Test startup validation when no config files exist."""
        validator = ConfigValidator()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Empty directory with no config files
            nonexistent_paths = [Path(temp_dir) / "config.yaml"]
            
            result = validator.validate_on_startup(
                config_paths=nonexistent_paths,
                exit_on_error=False
            )
            
            # Should return True (using defaults) but log warnings
            assert result
            mock_logger.warning.assert_called()
    
    @patch('vpn.core.config_validator.logger')
    @patch('sys.exit')
    def test_validate_on_startup_with_errors_exit(self, mock_exit, mock_logger):
        """Test startup validation with errors and exit enabled."""
        validator = ConfigValidator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Invalid config
            invalid_config = {
                "database": {"url": "invalid-scheme://test.db"}
            }
            yaml.dump(invalid_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            validator.validate_on_startup(
                config_paths=[config_path],
                exit_on_error=True
            )
            
            # Should call sys.exit
            mock_exit.assert_called_with(1)
            
        finally:
            config_path.unlink()


class TestConfigSchemaGenerator:
    """Test ConfigSchemaGenerator class."""
    
    def test_schema_generator_initialization(self):
        """Test schema generator initialization."""
        generator = ConfigSchemaGenerator()
        
        assert generator.settings_class == EnhancedSettings
    
    def test_generate_json_schema(self):
        """Test JSON schema generation."""
        generator = ConfigSchemaGenerator()
        
        schema = generator.generate_json_schema()
        
        assert isinstance(schema, dict)
        assert "properties" in schema
        assert "type" in schema
        assert schema["type"] == "object"
        
        # Check for key sections
        properties = schema["properties"]
        assert "app_name" in properties
        assert "database" in properties
        assert "docker" in properties
        assert "network" in properties
        assert "security" in properties
    
    def test_generate_markdown_documentation(self):
        """Test Markdown documentation generation."""
        generator = ConfigSchemaGenerator()
        
        docs = generator.generate_schema_documentation("markdown")
        
        assert isinstance(docs, str)
        assert "# VPN Manager Configuration Schema" in docs
        assert "## app_name" in docs
        assert "## database" in docs
        assert "**Type:**" in docs
        assert "**Default:**" in docs
    
    def test_save_schema_file_json(self):
        """Test saving JSON schema file."""
        generator = ConfigSchemaGenerator()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "schema.json"
            
            generator.save_schema_file(output_path, "json")
            
            assert output_path.exists()
            
            # Verify content
            with open(output_path) as f:
                schema = json.load(f)
            
            assert "properties" in schema
            assert "type" in schema
    
    def test_save_schema_file_markdown(self):
        """Test saving Markdown schema file."""
        generator = ConfigSchemaGenerator()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "schema.md"
            
            generator.save_schema_file(output_path, "markdown")
            
            assert output_path.exists()
            
            # Verify content
            content = output_path.read_text()
            assert "# VPN Manager Configuration Schema" in content


class TestGlobalFunctions:
    """Test global validator functions."""
    
    def test_get_config_validator(self):
        """Test get_config_validator function."""
        validator1 = get_config_validator()
        validator2 = get_config_validator()
        
        # Should return same instance
        assert validator1 is validator2
        assert isinstance(validator1, ConfigValidator)
    
    @patch('vpn.core.config_validator.get_config_validator')
    def test_validate_startup_config(self, mock_get_validator):
        """Test validate_startup_config function."""
        mock_validator = mock_get_validator.return_value
        mock_validator.validate_on_startup.return_value = True
        
        result = validate_startup_config(exit_on_error=False)
        
        assert result is True
        mock_validator.validate_on_startup.assert_called_once_with(exit_on_error=False)


class TestIntegrationScenarios:
    """Test integration scenarios."""
    
    def test_full_validation_workflow(self):
        """Test complete validation workflow."""
        validator = ConfigValidator()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "config.yaml"
            
            # Create initial old config
            old_config = {
                "database_url": "sqlite:///test.db",
                "docker_socket": "/var/run/docker.sock",
                "enable_firewall": True,
                "tui_theme": "dark"
            }
            
            with open(config_path, 'w') as f:
                yaml.dump(old_config, f)
            
            # Validate with auto-migration
            is_valid, issues = validator.validate_config_file(
                config_path,
                auto_migrate=True,
                strict=False
            )
            
            # Should be valid after migration
            assert is_valid
            
            # Should have some issues (migration info, possibly warnings)
            assert len(issues) > 0
            
            # Should have migration info
            migration_issues = [i for i in issues if "migration" in i.path]
            assert len(migration_issues) > 0
            
            # Verify migrated structure
            migrated_content = yaml.safe_load(config_path.read_text())
            assert "database" in migrated_content
            assert "docker" in migrated_content
            assert "network" in migrated_content
            assert migrated_content["database"]["url"] == "sqlite:///test.db"
    
    def test_strict_validation_mode(self):
        """Test strict validation mode."""
        validator = ConfigValidator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            config_with_unknowns = {
                "meta": {"version": "2.0.0"},
                "app_name": "Test",
                "unknown_setting": "value",
                "database": {
                    "url": "sqlite:///test.db",
                    "unknown_db_setting": "value"
                },
                "security": {
                    "enable_auth": True,
                    "token_expire_minutes": 60 * 24 * 10  # 10 days - long expiration
                }
            }
            yaml.dump(config_with_unknowns, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            # Validate in strict mode
            is_valid, issues = validator.validate_config_file(
                config_path,
                auto_migrate=False,
                strict=True
            )
            
            # Should have warnings/errors for unknown keys and long expiration
            unknown_key_issues = [i for i in issues if "unknown" in i.message.lower()]
            assert len(unknown_key_issues) > 0
            
            expiration_issues = [i for i in issues if "expiration" in i.message.lower()]
            assert len(expiration_issues) > 0
            
        finally:
            config_path.unlink()