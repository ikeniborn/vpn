"""
Tests for configuration overlay system.
"""

import json
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest
import yaml

from vpn.core.config_overlay import ConfigOverlay, get_config_overlay
from vpn.core.enhanced_config import EnhancedSettings
from vpn.core.exceptions import ConfigurationError


class TestConfigOverlay:
    """Test ConfigOverlay class."""
    
    def test_overlay_initialization(self):
        """Test overlay manager initialization."""
        overlay = ConfigOverlay()
        
        assert overlay.loader is not None
        assert overlay._overlay_cache == {}
    
    def test_deep_merge_simple(self):
        """Test simple dictionary merging."""
        overlay = ConfigOverlay()
        
        base = {"a": 1, "b": 2}
        override = {"b": 3, "c": 4}
        
        result = overlay._deep_merge(base, override)
        
        assert result == {"a": 1, "b": 3, "c": 4}
    
    def test_deep_merge_nested(self):
        """Test nested dictionary merging."""
        overlay = ConfigOverlay()
        
        base = {
            "database": {
                "url": "sqlite:///base.db",
                "pool_size": 5
            },
            "debug": False
        }
        
        override = {
            "database": {
                "url": "postgresql://localhost/db",
                "echo": True
            },
            "log_level": "DEBUG"
        }
        
        result = overlay._deep_merge(base, override)
        
        expected = {
            "database": {
                "url": "postgresql://localhost/db",
                "pool_size": 5,
                "echo": True
            },
            "debug": False,
            "log_level": "DEBUG"
        }
        
        assert result == expected
    
    def test_merge_configs_multiple(self):
        """Test merging multiple configurations."""
        overlay = ConfigOverlay()
        
        base = {"a": 1, "b": {"x": 1, "y": 2}}
        overlay1 = {"b": {"x": 10}, "c": 3}
        overlay2 = {"b": {"z": 30}, "d": 4}
        
        result = overlay.merge_configs(base, overlay1, overlay2)
        
        expected = {
            "a": 1,
            "b": {"x": 10, "y": 2, "z": 30},
            "c": 3,
            "d": 4
        }
        
        assert result == expected
    
    def test_create_overlay(self):
        """Test creating an overlay file."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Mock settings to use temp directory
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                config_data = {
                    "debug": True,
                    "database": {"url": "sqlite:///test.db"}
                }
                
                overlay_path = overlay.create_overlay(
                    "test-overlay",
                    config_data,
                    description="Test overlay"
                )
                
                # Check file was created
                assert overlay_path.exists()
                assert overlay_path.name == "test-overlay.yaml"
                
                # Check content
                with open(overlay_path) as f:
                    content = yaml.safe_load(f)
                
                assert content["meta"]["overlay_name"] == "test-overlay"
                assert content["meta"]["description"] == "Test overlay"
                assert content["debug"] is True
                assert content["database"]["url"] == "sqlite:///test.db"
    
    def test_load_overlay(self):
        """Test loading an overlay."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay file
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            overlay_file = overlay_dir / "test.yaml"
            
            overlay_content = {
                "meta": {
                    "overlay_name": "test",
                    "description": "Test overlay"
                },
                "debug": True,
                "log_level": "DEBUG"
            }
            
            with open(overlay_file, 'w') as f:
                yaml.dump(overlay_content, f)
            
            # Mock settings
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                config_data = overlay.load_overlay("test")
                
                # Should return config without meta
                assert config_data == {"debug": True, "log_level": "DEBUG"}
    
    def test_load_nonexistent_overlay(self):
        """Test loading non-existent overlay."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                with pytest.raises(ConfigurationError, match="Overlay not found"):
                    overlay.load_overlay("nonexistent")
    
    def test_list_overlays(self):
        """Test listing available overlays."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay directory and files
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            
            # Create test overlays
            overlays_data = {
                "dev.yaml": {
                    "meta": {
                        "overlay_name": "dev",
                        "description": "Development settings",
                        "overlay_version": "1.0"
                    },
                    "debug": True
                },
                "prod.yaml": {
                    "meta": {
                        "overlay_name": "prod",
                        "description": "Production settings"
                    },
                    "debug": False
                }
            }
            
            for filename, content in overlays_data.items():
                with open(overlay_dir / filename, 'w') as f:
                    yaml.dump(content, f)
            
            # Mock settings
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                overlays = overlay.list_overlays()
                
                assert len(overlays) == 2
                
                # Check dev overlay
                dev_overlay = next(o for o in overlays if o["name"] == "dev")
                assert dev_overlay["description"] == "Development settings"
                assert dev_overlay["overlay_version"] == "1.0"
                
                # Check prod overlay
                prod_overlay = next(o for o in overlays if o["name"] == "prod")
                assert prod_overlay["description"] == "Production settings"
                assert prod_overlay["overlay_version"] == "unknown"
    
    def test_delete_overlay(self):
        """Test deleting an overlay."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            overlay_file = overlay_dir / "test.yaml"
            overlay_file.write_text("debug: true")
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                # Delete overlay
                success = overlay.delete_overlay("test")
                
                assert success
                assert not overlay_file.exists()
    
    def test_delete_nonexistent_overlay(self):
        """Test deleting non-existent overlay."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                success = overlay.delete_overlay("nonexistent")
                
                assert not success
    
    def test_export_overlay_yaml(self):
        """Test exporting overlay to YAML."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            overlay_file = overlay_dir / "test.yaml"
            
            overlay_content = {
                "meta": {"overlay_name": "test"},
                "debug": True,
                "database": {"url": "sqlite:///test.db"}
            }
            
            with open(overlay_file, 'w') as f:
                yaml.dump(overlay_content, f)
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                output_file = Path(temp_dir) / "exported.yaml"
                success = overlay.export_overlay("test", output_file, "yaml")
                
                assert success
                assert output_file.exists()
                
                # Check exported content
                with open(output_file) as f:
                    exported = yaml.safe_load(f)
                
                # Should not include meta
                assert exported == {"debug": True, "database": {"url": "sqlite:///test.db"}}
    
    def test_export_overlay_json(self):
        """Test exporting overlay to JSON."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            overlay_file = overlay_dir / "test.yaml"
            
            overlay_content = {
                "meta": {"overlay_name": "test"},
                "debug": True
            }
            
            with open(overlay_file, 'w') as f:
                yaml.dump(overlay_content, f)
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                output_file = Path(temp_dir) / "exported.json"
                success = overlay.export_overlay("test", output_file, "json")
                
                assert success
                assert output_file.exists()
                
                # Check exported content
                with open(output_file) as f:
                    exported = json.load(f)
                
                assert exported == {"debug": True}
    
    def test_apply_overlays(self):
        """Test applying overlays to create final configuration."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create base config
            base_config_file = Path(temp_dir) / "base.yaml"
            base_config = {
                "app_name": "VPN Manager",
                "debug": False,
                "database": {
                    "url": "sqlite:///base.db",
                    "pool_size": 5
                }
            }
            with open(base_config_file, 'w') as f:
                yaml.dump(base_config, f)
            
            # Create overlays
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            
            # Development overlay
            dev_overlay = {
                "meta": {"overlay_name": "dev"},
                "debug": True,
                "log_level": "DEBUG",
                "database": {
                    "echo": True
                }
            }
            with open(overlay_dir / "dev.yaml", 'w') as f:
                yaml.dump(dev_overlay, f)
            
            # Security overlay
            security_overlay = {
                "meta": {"overlay_name": "security"},
                "security": {
                    "enable_auth": True,
                    "password_min_length": 12
                }
            }
            with open(overlay_dir / "security.yaml", 'w') as f:
                yaml.dump(security_overlay, f)
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                # Apply overlays
                settings = overlay.apply_overlays(
                    base_config_path=base_config_file,
                    overlay_names=["dev", "security"]
                )
                
                # Check merged configuration
                assert settings.debug is True  # From dev overlay
                assert settings.log_level == "DEBUG"  # From dev overlay
                assert settings.database.url == "sqlite:///base.db"  # From base
                assert settings.database.pool_size == 5  # From base
                assert settings.database.echo is True  # From dev overlay
                assert settings.security.enable_auth is True  # From security overlay
                assert settings.security.password_min_length == 12  # From security overlay
    
    def test_apply_overlays_with_environment(self):
        """Test applying overlays with environment overrides."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            
            test_overlay = {
                "meta": {"overlay_name": "test"},
                "debug": False,
                "log_level": "INFO"
            }
            with open(overlay_dir / "test.yaml", 'w') as f:
                yaml.dump(test_overlay, f)
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                # Environment overrides
                env_overrides = {
                    "debug": True,
                    "log_level": "DEBUG"
                }
                
                settings = overlay.apply_overlays(
                    overlay_names=["test"],
                    environment_overrides=env_overrides
                )
                
                # Environment should override overlay
                assert settings.debug is True  # Environment override
                assert settings.log_level == "DEBUG"  # Environment override
    
    def test_create_predefined_overlays(self):
        """Test creating predefined overlays."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                created_overlays = overlay.create_predefined_overlays()
                
                assert len(created_overlays) == 5
                
                # Check that overlay files were created
                overlay_dir = Path(temp_dir) / "overlays"
                assert (overlay_dir / "development.yaml").exists()
                assert (overlay_dir / "production.yaml").exists()
                assert (overlay_dir / "testing.yaml").exists()
                assert (overlay_dir / "docker.yaml").exists()
                assert (overlay_dir / "high-security.yaml").exists()
                
                # Check development overlay content
                dev_content = overlay.load_overlay("development")
                assert dev_content["debug"] is True
                assert dev_content["log_level"] == "DEBUG"
                assert dev_content["database"]["echo"] is True
    
    def test_overlay_caching(self):
        """Test overlay caching functionality."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create overlay
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            overlay_file = overlay_dir / "test.yaml"
            
            overlay_content = {
                "meta": {"overlay_name": "test"},
                "debug": True
            }
            
            with open(overlay_file, 'w') as f:
                yaml.dump(overlay_content, f)
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                # First load
                config1 = overlay.load_overlay("test")
                
                # Second load should use cache
                config2 = overlay.load_overlay("test")
                
                assert config1 == config2
                assert "test" in overlay._overlay_cache
                
                # Clear cache
                overlay.clear_cache()
                assert overlay._overlay_cache == {}


class TestGlobalFunctions:
    """Test global overlay functions."""
    
    def test_get_config_overlay(self):
        """Test get_config_overlay function."""
        overlay1 = get_config_overlay()
        overlay2 = get_config_overlay()
        
        # Should return same instance
        assert overlay1 is overlay2
        assert isinstance(overlay1, ConfigOverlay)


class TestIntegrationScenarios:
    """Test integration scenarios."""
    
    def test_complex_overlay_scenario(self):
        """Test complex overlay application scenario."""
        overlay = ConfigOverlay()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Base configuration
            base_config_file = Path(temp_dir) / "base.yaml"
            base_config = {
                "app_name": "VPN Manager",
                "debug": False,
                "log_level": "INFO",
                "database": {
                    "url": "sqlite:///prod.db",
                    "pool_size": 5,
                    "echo": False
                },
                "security": {
                    "enable_auth": True,
                    "token_expire_minutes": 1440
                },
                "monitoring": {
                    "enable_metrics": False
                }
            }
            with open(base_config_file, 'w') as f:
                yaml.dump(base_config, f)
            
            # Create overlay directory
            overlay_dir = Path(temp_dir) / "overlays"
            overlay_dir.mkdir()
            
            # Environment-specific overlay
            env_overlay = {
                "meta": {"overlay_name": "staging"},
                "database": {
                    "url": "postgresql://staging-db:5432/vpn",
                    "pool_size": 10
                },
                "monitoring": {
                    "enable_metrics": True,
                    "metrics_port": 9090
                }
            }
            with open(overlay_dir / "staging.yaml", 'w') as f:
                yaml.dump(env_overlay, f)
            
            # Feature-specific overlay
            feature_overlay = {
                "meta": {"overlay_name": "enhanced-security"},
                "security": {
                    "password_min_length": 12,
                    "require_password_complexity": True,
                    "token_expire_minutes": 60
                }
            }
            with open(overlay_dir / "enhanced-security.yaml", 'w') as f:
                yaml.dump(feature_overlay, f)
            
            # Debug overlay
            debug_overlay = {
                "meta": {"overlay_name": "debug"},
                "debug": True,
                "log_level": "DEBUG",
                "database": {
                    "echo": True
                }
            }
            with open(overlay_dir / "debug.yaml", 'w') as f:
                yaml.dump(debug_overlay, f)
            
            with patch('vpn.core.config_overlay.EnhancedSettings') as mock_settings:
                mock_instance = mock_settings.return_value
                mock_instance.paths.config_path = Path(temp_dir)
                
                # Apply overlays: staging + enhanced-security + debug
                settings = overlay.apply_overlays(
                    base_config_path=base_config_file,
                    overlay_names=["staging", "enhanced-security", "debug"]
                )
                
                # Verify final configuration
                assert settings.app_name == "VPN Manager"  # From base
                assert settings.debug is True  # From debug overlay
                assert settings.log_level == "DEBUG"  # From debug overlay
                
                # Database config (merged from base + staging + debug)
                assert settings.database.url == "postgresql://staging-db:5432/vpn"  # From staging
                assert settings.database.pool_size == 10  # From staging
                assert settings.database.echo is True  # From debug
                
                # Security config (merged from base + enhanced-security)
                assert settings.security.enable_auth is True  # From base
                assert settings.security.password_min_length == 12  # From enhanced-security
                assert settings.security.require_password_complexity is True  # From enhanced-security
                assert settings.security.token_expire_minutes == 60  # From enhanced-security
                
                # Monitoring config (from staging)
                assert settings.monitoring.enable_metrics is True  # From staging
                assert settings.monitoring.metrics_port == 9090  # From staging