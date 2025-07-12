"""
Tests for environment variable validation.
"""

import os
import tempfile
from unittest.mock import patch

import pytest

from vpn.core.config_validator import ConfigValidator, ValidationIssue


class TestEnvironmentValidation:
    """Test environment variable validation."""
    
    def test_no_environment_variables(self):
        """Test validation when no VPN environment variables are set."""
        validator = ConfigValidator()
        
        with patch.dict(os.environ, {}, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert is_valid
            assert len(issues) == 1
            assert issues[0].severity == "info"
            assert "No VPN environment variables found" in issues[0].message
    
    def test_deprecated_environment_variables(self):
        """Test detection of deprecated environment variables."""
        validator = ConfigValidator()
        
        deprecated_env = {
            "VPN_INSTALL_PATH": "/opt/vpn",
            "VPN_CONFIG_PATH": "~/.config/vpn",
            "VPN_DATABASE_URL": "sqlite:///test.db",
            "VPN_DOCKER_SOCKET": "/var/run/docker.sock"
        }
        
        with patch.dict(os.environ, deprecated_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            # Should be valid but have warnings
            assert is_valid
            
            # Should have deprecation warnings
            deprecation_warnings = [i for i in issues if "Deprecated" in i.message]
            assert len(deprecation_warnings) == 4
            
            # Check specific deprecation warnings
            warning_paths = [w.path for w in deprecation_warnings]
            assert "environment.VPN_INSTALL_PATH" in warning_paths
            assert "environment.VPN_CONFIG_PATH" in warning_paths
    
    def test_valid_environment_variables(self):
        """Test validation of valid environment variables."""
        validator = ConfigValidator()
        
        valid_env = {
            "VPN_DEBUG": "false",
            "VPN_LOG_LEVEL": "INFO",
            "VPN_DATABASE__URL": "sqlite+aiosqlite:///test.db",
            "VPN_DOCKER__TIMEOUT": "30",
            "VPN_NETWORK__DEFAULT_PORT_RANGE": "10000,20000",
            "VPN_SECURITY__ENABLE_AUTH": "true",
            "VPN_MONITORING__ENABLE_METRICS": "true",
            "VPN_TUI__THEME": "dark"
        }
        
        with patch.dict(os.environ, valid_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert is_valid
            
            # Should have info message about successful loading
            info_issues = [i for i in issues if i.severity == "info"]
            assert len(info_issues) >= 1
            assert any("successfully loaded" in i.message for i in info_issues)
    
    def test_invalid_boolean_values(self):
        """Test validation of invalid boolean values."""
        validator = ConfigValidator()
        
        invalid_env = {
            "VPN_DEBUG": "maybe",
            "VPN_SECURITY__ENABLE_AUTH": "sometimes",
            "VPN_MONITORING__ENABLE_METRICS": "invalid"
        }
        
        with patch.dict(os.environ, invalid_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert not is_valid
            
            # Should have errors for invalid boolean values
            boolean_errors = [i for i in issues if i.severity == "error" and "Boolean" in i.message]
            assert len(boolean_errors) == 3
    
    def test_invalid_numeric_values(self):
        """Test validation of invalid numeric values."""
        validator = ConfigValidator()
        
        invalid_env = {
            "VPN_DATABASE__POOL_SIZE": "not-a-number",
            "VPN_DOCKER__TIMEOUT": "invalid",
            "VPN_MONITORING__METRICS_PORT": "abc"
        }
        
        with patch.dict(os.environ, invalid_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert not is_valid
            
            # Should have errors for non-numeric values
            numeric_errors = [i for i in issues if i.severity == "error" and "non-numeric" in i.message.lower()]
            assert len(numeric_errors) == 3
    
    def test_out_of_range_numeric_values(self):
        """Test validation of numeric values outside recommended ranges."""
        validator = ConfigValidator()
        
        out_of_range_env = {
            "VPN_DATABASE__POOL_SIZE": "100",  # Max is 50
            "VPN_DOCKER__TIMEOUT": "1000",    # Max is 600
            "VPN_MONITORING__METRICS_PORT": "100"  # Min is 1024
        }
        
        with patch.dict(os.environ, out_of_range_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            # Should be valid but have warnings
            assert is_valid
            
            # Should have warnings for out-of-range values
            range_warnings = [i for i in issues if "outside" in i.message and "range" in i.message]
            assert len(range_warnings) == 3
    
    def test_invalid_choice_values(self):
        """Test validation of invalid choice values."""
        validator = ConfigValidator()
        
        invalid_env = {
            "VPN_LOG_LEVEL": "INVALID",
            "VPN_DEFAULT_PROTOCOL": "unknown",
            "VPN_TUI__THEME": "rainbow"
        }
        
        with patch.dict(os.environ, invalid_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert not is_valid
            
            # Should have errors for invalid choices
            choice_errors = [i for i in issues if i.severity == "error" and "Invalid choice" in i.message]
            assert len(choice_errors) == 3
    
    def test_port_range_format_validation(self):
        """Test validation of port range format."""
        validator = ConfigValidator()
        
        # Test invalid port range formats
        invalid_ranges = [
            "10000",           # Missing comma
            "10000,20000,30000",  # Too many parts
            "20000,10000",     # Min > Max
            "abc,def",         # Non-numeric
            "0,70000"          # Out of valid port range
        ]
        
        for invalid_range in invalid_ranges:
            invalid_env = {"VPN_NETWORK__DEFAULT_PORT_RANGE": invalid_range}
            
            with patch.dict(os.environ, invalid_env, clear=True):
                is_valid, issues = validator.validate_environment_variables()
                
                # Should have errors for invalid port ranges
                port_errors = [i for i in issues if i.severity == "error" and "VPN_NETWORK__DEFAULT_PORT_RANGE" in i.path]
                assert len(port_errors) >= 1, f"No error for invalid range: {invalid_range}"
    
    def test_database_url_format_validation(self):
        """Test validation of database URL format."""
        validator = ConfigValidator()
        
        # Test invalid database URLs
        invalid_urls = [
            "invalid-url",           # No scheme
            "unknown://test.db",     # Unsupported scheme
            "ftp://test.db"          # Wrong protocol
        ]
        
        for invalid_url in invalid_urls:
            invalid_env = {"VPN_DATABASE__URL": invalid_url}
            
            with patch.dict(os.environ, invalid_env, clear=True):
                is_valid, issues = validator.validate_environment_variables()
                
                # Should have errors or warnings for invalid URLs
                url_issues = [i for i in issues if "VPN_DATABASE__URL" in i.path]
                assert len(url_issues) >= 1, f"No issue for invalid URL: {invalid_url}"
    
    def test_conflicting_environment_variables(self):
        """Test detection of conflicting environment variables."""
        validator = ConfigValidator()
        
        conflicting_env = {
            "VPN_INSTALL_PATH": "/opt/vpn",        # Old format
            "VPN_PATHS__INSTALL_PATH": "/usr/vpn", # New format
            "VPN_DATABASE_URL": "sqlite:///old.db",
            "VPN_DATABASE__URL": "sqlite:///new.db"
        }
        
        with patch.dict(os.environ, conflicting_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            # Should be valid but have conflict warnings
            assert is_valid
            
            # Should have conflict warnings
            conflict_warnings = [i for i in issues if "conflict" in i.path]
            assert len(conflict_warnings) >= 2
    
    def test_security_configuration_conflicts(self):
        """Test detection of security configuration conflicts."""
        validator = ConfigValidator()
        
        conflicting_env = {
            "VPN_SECURITY__ENABLE_AUTH": "false",
            "VPN_SECURITY__SECRET_KEY": "some-secret-key"
        }
        
        with patch.dict(os.environ, conflicting_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            # Should be valid but have warning
            assert is_valid
            
            # Should have warning about unused secret key
            security_warnings = [i for i in issues if "security" in i.path and "disabled" in i.message]
            assert len(security_warnings) >= 1
    
    def test_nested_delimiter_validation(self):
        """Test validation of nested delimiter format."""
        validator = ConfigValidator()
        
        invalid_env = {
            "VPN_INVALID___FORMAT": "value",      # Triple underscores
            "VPN_TOO__MANY__NESTED__LEVELS": "value"  # Too many levels
        }
        
        with patch.dict(os.environ, invalid_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            # Should be valid but have format warnings
            assert is_valid
            
            # Should have warnings about format issues
            format_warnings = [i for i in issues if "underscore" in i.message or "nesting" in i.message]
            assert len(format_warnings) >= 2
    
    def test_url_format_validation(self):
        """Test validation of URL formats."""
        validator = ConfigValidator()
        
        invalid_env = {
            "VPN_MONITORING__OTLP_ENDPOINT": "invalid-url",
            "VPN_DOCKER__REGISTRY_URL": "ftp://registry.com"
        }
        
        with patch.dict(os.environ, invalid_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert not is_valid
            
            # Should have errors for invalid URL formats
            url_errors = [i for i in issues if i.severity == "error" and ("http://" in i.message or "https://" in i.message)]
            assert len(url_errors) >= 1
    
    def test_comprehensive_validation_scenario(self):
        """Test comprehensive validation scenario with mixed valid/invalid values."""
        validator = ConfigValidator()
        
        mixed_env = {
            # Valid values
            "VPN_DEBUG": "true",
            "VPN_LOG_LEVEL": "DEBUG",
            "VPN_DATABASE__URL": "postgresql://user:pass@localhost/db",
            "VPN_NETWORK__DEFAULT_PORT_RANGE": "8000,9000",
            
            # Invalid values
            "VPN_SECURITY__ENABLE_AUTH": "maybe",  # Invalid boolean
            "VPN_DOCKER__TIMEOUT": "abc",          # Invalid numeric
            "VPN_TUI__THEME": "rainbow",           # Invalid choice
            
            # Deprecated
            "VPN_INSTALL_PATH": "/opt/vpn",        # Deprecated
            
            # Format issues
            "VPN_INVALID___FORMAT": "value"       # Triple underscores
        }
        
        with patch.dict(os.environ, mixed_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            assert not is_valid  # Should fail due to errors
            
            # Should have mix of errors, warnings, and info
            errors = [i for i in issues if i.severity == "error"]
            warnings = [i for i in issues if i.severity == "warning"]
            info = [i for i in issues if i.severity == "info"]
            
            assert len(errors) >= 3    # Boolean, numeric, choice errors
            assert len(warnings) >= 2  # Deprecated and format warnings
            assert len(info) >= 1      # Info about loading
    
    def test_environment_variable_masking(self):
        """Test that sensitive environment variables are handled properly."""
        validator = ConfigValidator()
        
        sensitive_env = {
            "VPN_SECURITY__SECRET_KEY": "super-secret-key",
            "VPN_DOCKER__REGISTRY_PASSWORD": "secret-password",
            "VPN_DEBUG": "true"
        }
        
        with patch.dict(os.environ, sensitive_env, clear=True):
            is_valid, issues = validator.validate_environment_variables()
            
            # Should be valid
            assert is_valid
            
            # Check that validation doesn't expose sensitive values in non-sensitive issues
            for issue in issues:
                if issue.value and isinstance(issue.value, str):
                    # Secret values should not appear in validation messages
                    assert "super-secret-key" not in str(issue)
                    assert "secret-password" not in str(issue)