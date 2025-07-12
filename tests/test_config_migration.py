"""
Tests for configuration migration system.
"""

import json
import tempfile
from datetime import datetime
from pathlib import Path

import pytest
import toml
import yaml

from vpn.core.config_migration import (
    ConfigMigrator,
    ConfigVersion,
    MigrationResult,
    migrate_user_config,
    rollback_migration,
)


class TestConfigMigrator:
    """Test configuration migrator."""
    
    def test_detect_config_version(self):
        """Test configuration version detection."""
        migrator = ConfigMigrator()
        
        # Explicit version
        config_with_version = {"version": "1.5.0", "debug": True}
        assert migrator.detect_config_version(config_with_version) == "1.5.0"
        
        # Version in metadata
        config_with_meta = {"meta": {"version": "1.0.0"}, "debug": True}
        assert migrator.detect_config_version(config_with_meta) == "1.0.0"
        
        # New structure (2.0.0)
        new_structure = {
            "paths": {"config_path": "/test"},
            "database": {"url": "sqlite:///test.db"}
        }
        assert migrator.detect_config_version(new_structure) == "2.0.0"
        
        # Mid-version structure (1.5.0)
        mid_structure = {"tui_theme": "dark", "docker_socket": "/var/run/docker.sock"}
        assert migrator.detect_config_version(mid_structure) == "1.5.0"
        
        # Legacy structure (1.0.0)
        legacy_structure = {"some_old_setting": "value"}
        assert migrator.detect_config_version(legacy_structure) == "1.0.0"
    
    def test_needs_migration(self):
        """Test migration need detection."""
        migrator = ConfigMigrator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Current version config
            current_config = {"meta": {"version": "2.0.0"}, "debug": True}
            yaml.dump(current_config, f)
            f.flush()
            
            config_path = Path(f.name)
            
        try:
            # Should not need migration
            assert not migrator.needs_migration(config_path)
        finally:
            config_path.unlink()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Old version config
            old_config = {"tui_theme": "dark", "debug": True}
            yaml.dump(old_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            # Should need migration
            assert migrator.needs_migration(config_path)
        finally:
            config_path.unlink()
    
    def test_migration_path(self):
        """Test migration path generation."""
        migrator = ConfigMigrator()
        
        # Forward migration
        path = migrator._get_migration_path("1.0.0", "2.0.0")
        assert path == ["1.0.0", "1.5.0"]
        
        # Partial migration
        path = migrator._get_migration_path("1.5.0", "2.0.0")
        assert path == ["1.5.0"]
        
        # No migration needed
        path = migrator._get_migration_path("2.0.0", "2.0.0")
        assert path == []
    
    def test_key_mapping(self):
        """Test configuration key mapping."""
        migrator = ConfigMigrator()
        
        # Test known mappings
        assert migrator._find_key_mapping("database_url") == "database.url"
        assert migrator._find_key_mapping("docker_socket") == "docker.socket"
        assert migrator._find_key_mapping("tui_theme") == "tui.theme"
        
        # Test unknown mapping
        assert migrator._find_key_mapping("unknown_key") is None
    
    def test_set_nested_value(self):
        """Test setting nested values."""
        migrator = ConfigMigrator()
        config = {}
        
        # Set simple nested value
        migrator._set_nested_value(config, "database.url", "sqlite:///test.db")
        assert config["database"]["url"] == "sqlite:///test.db"
        
        # Set deeper nested value
        migrator._set_nested_value(config, "paths.config.dir", "/test/config")
        assert config["paths"]["config"]["dir"] == "/test/config"
    
    def test_create_new_structure(self):
        """Test creating new configuration structure."""
        migrator = ConfigMigrator()
        
        old_config = {
            "database_url": "sqlite:///test.db",
            "docker_socket": "/var/run/docker.sock",
            "tui_theme": "light",
            "unknown_setting": "value"
        }
        
        new_config = migrator._create_new_structure(old_config)
        
        # Check mapped values
        assert new_config["database"]["url"] == "sqlite:///test.db"
        assert new_config["docker"]["socket"] == "/var/run/docker.sock"
        assert new_config["tui"]["theme"] == "light"
        
        # Check unmapped value is preserved
        assert new_config["unknown_setting"] == "value"
    
    def test_migrate_config_yaml(self):
        """Test configuration migration for YAML file."""
        migrator = ConfigMigrator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            old_config = {
                "database_url": "sqlite:///old.db",
                "docker_socket": "/var/run/docker.sock",
                "tui_theme": "dark",
                "old_feature_flag": True,  # Will be deprecated
            }
            yaml.dump(old_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            # Perform migration
            result = migrator.migrate_config(config_path, backup=True, dry_run=False)
            
            assert result.success
            assert result.from_version == "1.5.0"  # Detected from tui_theme
            assert result.to_version == "2.0.0"
            assert len(result.changes_made) > 0
            assert result.backup_path is not None
            assert result.backup_path.exists()
            
            # Check migrated content
            migrated_data = yaml.safe_load(config_path.read_text())
            assert migrated_data["database"]["url"] == "sqlite:///old.db"
            assert migrated_data["docker"]["socket"] == "/var/run/docker.sock"
            assert migrated_data["tui"]["theme"] == "dark"
            assert "old_feature_flag" not in migrated_data
            assert migrated_data["meta"]["version"] == "2.0.0"
            
        finally:
            config_path.unlink(missing_ok=True)
            if 'result' in locals() and result.backup_path:
                result.backup_path.unlink(missing_ok=True)
    
    def test_migrate_config_toml(self):
        """Test configuration migration for TOML file."""
        migrator = ConfigMigrator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as f:
            old_config = {
                "database_url": "sqlite:///old.db",
                "enable_firewall": True,
                "default_port_range": [8000, 9000],
            }
            toml.dump(old_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            # Perform migration
            result = migrator.migrate_config(config_path, backup=False, dry_run=False)
            
            assert result.success
            assert result.backup_path is None  # No backup requested
            
            # Check migrated content
            migrated_data = toml.load(config_path)
            assert migrated_data["network"]["enable_firewall"] is True
            assert migrated_data["network"]["default_port_range"] == [8000, 9000]
            
        finally:
            config_path.unlink(missing_ok=True)
    
    def test_migrate_config_dry_run(self):
        """Test dry run migration."""
        migrator = ConfigMigrator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            old_config = {"database_url": "sqlite:///test.db"}
            yaml.dump(old_config, f)
            f.flush()
            
            config_path = Path(f.name)
            original_content = config_path.read_text()
        
        try:
            # Perform dry run
            result = migrator.migrate_config(config_path, backup=True, dry_run=True)
            
            assert result.success
            assert result.backup_path is None  # No backup in dry run
            
            # File should be unchanged
            assert config_path.read_text() == original_content
            
        finally:
            config_path.unlink()
    
    def test_migrate_config_no_migration_needed(self):
        """Test migration when no migration is needed."""
        migrator = ConfigMigrator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Already current version
            current_config = {
                "meta": {"version": "2.0.0"},
                "database": {"url": "sqlite:///test.db"}
            }
            yaml.dump(current_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            result = migrator.migrate_config(config_path)
            
            assert result.success
            assert result.from_version == "2.0.0"
            assert result.to_version == "2.0.0"
            assert "No migration needed" in result.changes_made[0]
            
        finally:
            config_path.unlink()
    
    def test_migrate_all_configs(self):
        """Test migrating all configs in search paths."""
        migrator = ConfigMigrator()
        
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            
            # Create multiple config files
            config1 = temp_path / "config1.yaml"
            config2 = temp_path / "config2.toml"
            config3 = temp_path / "current.yaml"
            
            # Old configs that need migration
            with open(config1, 'w') as f:
                yaml.dump({"database_url": "sqlite:///test1.db"}, f)
            
            with open(config2, 'w') as f:
                toml.dump({"docker_socket": "/test/docker.sock"}, f)
            
            # Current config that doesn't need migration
            with open(config3, 'w') as f:
                yaml.dump({"meta": {"version": "2.0.0"}}, f)
            
            # Migrate all
            results = migrator.migrate_all_configs([temp_path], dry_run=True)
            
            # Should migrate 2 files (config1, config2), skip config3
            assert len(results) == 2
            assert all(r.success for r in results)
    
    def test_validate_migrated_config(self):
        """Test validation of migrated configuration."""
        migrator = ConfigMigrator()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Valid migrated config
            valid_config = {
                "meta": {"version": "2.0.0"},
                "app_name": "Test VPN",
                "debug": False,
                "database": {"url": "sqlite:///test.db"},
                "docker": {"socket": "/var/run/docker.sock"},
            }
            yaml.dump(valid_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            assert migrator.validate_migrated_config(config_path)
        finally:
            config_path.unlink()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            # Invalid config
            invalid_config = {
                "database": {"url": "invalid-scheme://test.db"}  # Invalid URL
            }
            yaml.dump(invalid_config, f)
            f.flush()
            
            config_path = Path(f.name)
        
        try:
            assert not migrator.validate_migrated_config(config_path)
        finally:
            config_path.unlink()


class TestMigrationModels:
    """Test migration data models."""
    
    def test_config_version(self):
        """Test ConfigVersion model."""
        version = ConfigVersion(
            version="1.0.0",
            created_at=datetime.utcnow(),
            app_version="1.0.0",
            migration_history=["initial"]
        )
        
        assert version.version == "1.0.0"
        assert version.app_version == "1.0.0"
        assert "initial" in version.migration_history
    
    def test_migration_result(self):
        """Test MigrationResult model."""
        result = MigrationResult(
            success=True,
            from_version="1.0.0",
            to_version="2.0.0",
            changes_made=["Migrated database config"],
            warnings=["Some deprecated setting removed"],
            backup_path=Path("/test/backup.yaml")
        )
        
        assert result.success
        assert result.from_version == "1.0.0"
        assert result.to_version == "2.0.0"
        assert len(result.changes_made) == 1
        assert len(result.warnings) == 1
        assert result.backup_path == Path("/test/backup.yaml")


class TestMigrationFunctions:
    """Test migration utility functions."""
    
    def test_migrate_user_config(self):
        """Test user config migration function."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            
            # Create old config in temp directory
            config_file = temp_path / "config.yaml"
            with open(config_file, 'w') as f:
                yaml.dump({"database_url": "sqlite:///test.db"}, f)
            
            # Mock search paths to include our temp directory
            import vpn.core.config_migration
            original_search_paths = None
            
            def mock_migrate_all_configs(search_paths, **kwargs):
                # Use our temp directory instead of default paths
                migrator = ConfigMigrator()
                return migrator.migrate_all_configs([temp_path], **kwargs)
            
            # Patch the migrate_all_configs method
            ConfigMigrator.migrate_all_configs = mock_migrate_all_configs
            
            try:
                results = migrate_user_config(dry_run=True)
                assert len(results) >= 1
                assert all(r.success for r in results)
                
            finally:
                # Restore original method (not critical for test)
                pass
    
    def test_rollback_migration(self):
        """Test migration rollback."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            
            # Create original and backup files
            original_file = temp_path / "config.yaml"
            backup_file = temp_path / "config_backup.yaml"
            
            original_content = {"old": "config"}
            backup_content = {"backup": "config"}
            
            with open(original_file, 'w') as f:
                yaml.dump(original_content, f)
            
            with open(backup_file, 'w') as f:
                yaml.dump(backup_content, f)
            
            # Perform rollback
            success = rollback_migration(backup_file, original_file)
            assert success
            
            # Check that original file now has backup content
            restored_content = yaml.safe_load(original_file.read_text())
            assert restored_content == backup_content
    
    def test_rollback_migration_no_backup(self):
        """Test rollback when backup doesn't exist."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            
            original_file = temp_path / "config.yaml"
            backup_file = temp_path / "nonexistent_backup.yaml"
            
            with open(original_file, 'w') as f:
                yaml.dump({"test": "config"}, f)
            
            # Rollback should fail
            success = rollback_migration(backup_file, original_file)
            assert not success


class TestComplexMigrationScenarios:
    """Test complex migration scenarios."""
    
    def test_multi_version_migration(self):
        """Test migration across multiple versions."""
        migrator = ConfigMigrator()
        
        # Create a 1.0.0 config that needs to go through multiple migrations
        old_config = {
            "install_path": "/opt/vpn",
            "database_url": "sqlite:///old.db",
            "docker_socket": "/var/run/docker.sock",
            "old_feature_flag": True,  # Will be removed in 1.0.0 -> 1.5.0
            "old_monitoring_endpoint": "http://old.endpoint",  # Will be removed in 1.5.0 -> 2.0.0
        }
        
        migrated_data, changes, warnings = migrator._migrate_data(
            old_config, "1.0.0", "2.0.0"
        )
        
        # Should have migrated through both versions
        assert "old_feature_flag" not in migrated_data
        assert "old_monitoring_endpoint" not in migrated_data
        assert migrated_data["paths"]["install_path"] == "/opt/vpn"
        assert migrated_data["database"]["url"] == "sqlite:///old.db"
        assert migrated_data["docker"]["socket"] == "/var/run/docker.sock"
        
        # Should have change records
        assert len(changes) > 0
        assert any("deprecated" in change.lower() for change in changes)
    
    def test_partial_config_migration(self):
        """Test migration of partial configuration."""
        migrator = ConfigMigrator()
        
        # Config with only some known keys
        partial_config = {
            "database_url": "sqlite:///partial.db",
            "custom_setting": "custom_value",
            "another_custom": 42
        }
        
        new_config = migrator._create_new_structure(partial_config)
        
        # Known key should be mapped
        assert new_config["database"]["url"] == "sqlite:///partial.db"
        
        # Unknown keys should be preserved at root level
        assert new_config["custom_setting"] == "custom_value"
        assert new_config["another_custom"] == 42
        
        # Should still have default structure for unmapped sections
        assert "paths" in new_config
        assert "docker" in new_config
    
    def test_config_with_complex_values(self):
        """Test migration with complex data types."""
        migrator = ConfigMigrator()
        
        complex_config = {
            "default_port_range": [8000, 9000],  # List
            "nested_dict": {  # Nested dictionary
                "sub_key": "sub_value",
                "sub_dict": {"deep": "value"}
            },
            "database_url": "sqlite:///test.db"
        }
        
        new_config = migrator._create_new_structure(complex_config)
        
        # Complex values should be preserved
        assert new_config["network"]["default_port_range"] == [8000, 9000]
        assert new_config["nested_dict"]["sub_key"] == "sub_value"
        assert new_config["nested_dict"]["sub_dict"]["deep"] == "value"
        assert new_config["database"]["url"] == "sqlite:///test.db"