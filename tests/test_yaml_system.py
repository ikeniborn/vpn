"""
Comprehensive tests for YAML configuration system.
"""

import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from vpn.core.yaml_config import (
    YamlConfigManager,
)
from vpn.core.yaml_migration import (
    MigrationResult,
    YamlMigrationEngine,
)
from vpn.core.yaml_presets import (
    PresetApplicationResult,
    PresetCategory,
    PresetScope,
    YamlPresetManager,
)
from vpn.core.yaml_schema import (
    VPNConfigSchema,
    yaml_schema_validator,
)
from vpn.core.yaml_templates import (
    TemplateContext,
    TemplateType,
    VPNTemplateEngine,
)


class TestYamlConfigManager:
    """Test YAML configuration manager."""

    @pytest.fixture
    def manager(self):
        """Create YAML config manager."""
        return YamlConfigManager()

    @pytest.fixture
    def temp_yaml_file(self):
        """Create temporary YAML file."""
        content = """
app:
  name: "Test VPN Manager"
  debug: true
  log_level: "DEBUG"

database:
  type: "sqlite"
  path: "/tmp/test.db"

network:
  bind_address: "127.0.0.1"
  ports:
    vless: 8443
    shadowsocks: 8388
"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(content)
            yield Path(f.name)
        Path(f.name).unlink(missing_ok=True)

    def test_load_yaml_file(self, manager, temp_yaml_file):
        """Test loading YAML file."""
        result = manager.load_yaml(temp_yaml_file, validate_schema=False)

        assert result.is_valid
        assert result.data['app']['name'] == "Test VPN Manager"
        assert result.data['app']['debug'] is True
        assert result.data['database']['type'] == "sqlite"
        assert result.source_file == temp_yaml_file

    def test_load_yaml_with_validation(self, manager, temp_yaml_file):
        """Test loading YAML with schema validation."""
        result = manager.load_yaml(
            temp_yaml_file,
            validate_schema=True,
            schema_model=VPNConfigSchema
        )

        assert result.is_valid
        assert isinstance(result.data, dict)

    def test_load_yaml_with_template_vars(self, manager):
        """Test loading YAML with template variables."""
        yaml_content = """
app:
  name: "{{ app_name }}"
  debug: {{ debug_mode }}

database:
  path: "{{ db_path }}"
"""
        template_vars = {
            'app_name': 'Templated VPN',
            'debug_mode': False,
            'db_path': '/custom/path.db'
        }

        result = manager.load_yaml(
            yaml_content,
            validate_schema=False,
            template_vars=template_vars
        )

        assert result.is_valid
        assert result.data['app']['name'] == "Templated VPN"
        assert result.data['app']['debug'] is False
        assert result.data['database']['path'] == "/custom/path.db"

    def test_save_yaml(self, manager):
        """Test saving YAML file."""
        data = {
            'app': {
                'name': 'Test App',
                'debug': True
            },
            'database': {
                'type': 'sqlite',
                'path': '/tmp/test.db'
            }
        }

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as f:
            output_path = Path(f.name)

        try:
            success = manager.save_yaml(data, output_path)
            assert success
            assert output_path.exists()

            # Verify content
            result = manager.load_yaml(output_path, validate_schema=False)
            assert result.is_valid
            assert result.data['app']['name'] == 'Test App'
        finally:
            output_path.unlink(missing_ok=True)

    def test_merge_configs(self, manager):
        """Test merging configurations."""
        base_config = {
            'app': {
                'name': 'Base App',
                'debug': False
            },
            'database': {
                'type': 'sqlite'
            }
        }

        override_config = {
            'app': {
                'debug': True,
                'version': '2.0.0'
            },
            'network': {
                'bind_address': '0.0.0.0'
            }
        }

        merged = manager.merge_configs(base_config, override_config)

        assert merged['app']['name'] == 'Base App'  # From base
        assert merged['app']['debug'] is True  # Overridden
        assert merged['app']['version'] == '2.0.0'  # Added
        assert merged['database']['type'] == 'sqlite'  # From base
        assert merged['network']['bind_address'] == '0.0.0.0'  # Added

    def test_convert_from_toml(self, manager):
        """Test converting TOML to YAML."""
        toml_content = """
[app]
name = "TOML App"
debug = true

[database]
type = "sqlite"
path = "/tmp/toml.db"
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as toml_file:
            toml_file.write(toml_content)
            toml_path = Path(toml_file.name)

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as yaml_file:
            yaml_path = Path(yaml_file.name)

        try:
            success = manager.convert_from_toml(toml_path, yaml_path)
            assert success
            assert yaml_path.exists()

            # Verify conversion
            result = manager.load_yaml(yaml_path, validate_schema=False)
            assert result.is_valid
            assert result.data['app']['name'] == "TOML App"
        finally:
            toml_path.unlink(missing_ok=True)
            yaml_path.unlink(missing_ok=True)


class TestYamlSchema:
    """Test YAML schema validation."""

    def test_validate_valid_config(self):
        """Test validating valid configuration."""
        valid_data = {
            'app': {
                'name': 'Test App',
                'debug': False,
                'log_level': 'INFO'
            },
            'database': {
                'type': 'sqlite',
                'path': '/tmp/test.db'
            },
            'docker': {
                'host': 'unix:///var/run/docker.sock',
                'timeout': 30
            }
        }

        result = yaml_schema_validator.validate_yaml_data(valid_data, "config")
        assert result.is_valid
        assert not result.has_errors

    def test_validate_invalid_config(self):
        """Test validating invalid configuration."""
        invalid_data = {
            'app': {
                'name': 'Test App',
                'debug': 'invalid_boolean',  # Should be boolean
                'log_level': 'INVALID_LEVEL'  # Should be valid log level
            },
            'database': {
                'type': 'invalid_type',  # Should be sqlite, postgresql, or mysql
                'port': 99999  # Should be valid port range
            }
        }

        result = yaml_schema_validator.validate_yaml_data(invalid_data, "config")
        assert not result.is_valid
        assert result.has_errors
        assert len(result.errors) > 0

    def test_generate_json_schema(self):
        """Test generating JSON schema."""
        schema = yaml_schema_validator.generate_json_schema("config")

        assert isinstance(schema, dict)
        assert '$schema' in schema
        assert 'title' in schema
        assert 'properties' in schema
        assert 'app' in schema['properties']
        assert 'database' in schema['properties']

    def test_validate_user_preset(self):
        """Test validating user preset."""
        preset_data = {
            'preset': {
                'name': 'test_preset',
                'description': 'Test preset',
                'category': 'development',
                'scope': 'user',
                'version': '1.0.0',
                'author': 'test'
            },
            'users': [
                {
                    'username': 'test_user',
                    'protocol': 'vless',
                    'email': 'test@example.com',
                    'active': True
                }
            ],
            'servers': [
                {
                    'name': 'test_server',
                    'protocol': 'vless',
                    'port': 8443,
                    'auto_start': True
                }
            ]
        }

        result = yaml_schema_validator.validate_yaml_data(preset_data, "user_preset")
        assert result.is_valid


class TestYamlTemplates:
    """Test YAML template system."""

    @pytest.fixture
    def engine(self):
        """Create template engine."""
        return VPNTemplateEngine()

    def test_render_simple_template(self, engine):
        """Test rendering simple template."""
        template_content = """
server:
  name: "{{ server_name }}"
  port: {{ port }}
  protocol: "{{ protocol }}"
"""

        # Create temporary template
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(template_content)
            template_path = Path(f.name)

        try:
            # Create template context
            context = TemplateContext(
                template_type=TemplateType.VLESS,
                variables={
                    'server_name': 'test-server',
                    'port': 8443,
                    'protocol': 'vless'
                }
            )

            # Render template
            result = engine.render_template(template_path.name, context)

            assert result.is_valid
            assert 'test-server' in result.content
            assert '8443' in result.content
            assert 'vless' in result.content
        finally:
            template_path.unlink(missing_ok=True)

    def test_template_functions(self, engine):
        """Test template functions."""
        template_content = """
server:
  uuid: "{{ uuid4() }}"
  password: "{{ random_password(16) }}"
  key: "{{ random_hex(32) }}"
  created: "{{ now().isoformat() }}"
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(template_content)
            template_path = Path(f.name)

        try:
            context = TemplateContext(template_type=TemplateType.VLESS)
            result = engine.render_template(template_path.name, context)

            assert result.is_valid
            # Check that functions were called (content contains generated values)
            assert len(result.content.split('uuid:')[1].split('\n')[0].strip().strip('"')) > 10
        finally:
            template_path.unlink(missing_ok=True)

    def test_template_filters(self, engine):
        """Test template filters."""
        template_content = """
server:
  port_range: "{{ port_range | to_port_range }}"
  duration: "{{ 3600 | to_duration }}"
  file_size: "{{ 1048576 | to_file_size }}"
  slug: "{{ 'Test Server Name' | slugify }}"
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(template_content)
            template_path = Path(f.name)

        try:
            context = TemplateContext(
                template_type=TemplateType.VLESS,
                variables={'port_range': '8000-8100'}
            )

            result = engine.render_template(template_path.name, context)

            assert result.is_valid
            assert '1h' in result.content  # Duration filter
            assert '1.0MB' in result.content  # File size filter
            assert 'test-server-name' in result.content  # Slugify filter
        finally:
            template_path.unlink(missing_ok=True)

    def test_validate_template(self, engine):
        """Test template validation."""
        # Valid template
        valid_template = """
server:
  name: "{{ server_name }}"
  port: {{ port }}
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(valid_template)
            template_path = Path(f.name)

        try:
            result = engine.validate_template(template_path.stem)
            assert result.is_valid
        finally:
            template_path.unlink(missing_ok=True)

        # Invalid template
        invalid_template = """
server:
  name: "{{ unclosed_bracket"
  port: {{ missing_closing_bracket
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(invalid_template)
            template_path = Path(f.name)

        try:
            result = engine.validate_template(template_path.stem)
            assert not result.is_valid
            assert result.has_errors
        finally:
            template_path.unlink(missing_ok=True)


class TestYamlPresets:
    """Test YAML presets system."""

    @pytest.fixture
    def manager(self):
        """Create preset manager with temporary directory."""
        with tempfile.TemporaryDirectory() as temp_dir:
            yield YamlPresetManager(Path(temp_dir))

    def test_create_preset(self, manager):
        """Test creating preset."""
        success = manager.create_preset(
            "test_preset",
            PresetCategory.DEVELOPMENT,
            PresetScope.USER,
            "Test preset description"
        )

        assert success
        assert manager.preset_exists("test_preset")

    def test_load_preset(self, manager):
        """Test loading preset."""
        # Create preset first
        manager.create_preset(
            "load_test",
            PresetCategory.DEVELOPMENT,
            PresetScope.USER,
            "Load test preset"
        )

        preset_data = manager.load_preset("load_test")
        assert preset_data is not None
        assert preset_data['preset']['name'] == "load_test"
        assert preset_data['preset']['category'] == 'development'

    def test_list_presets(self, manager):
        """Test listing presets."""
        # Create multiple presets
        manager.create_preset("preset1", PresetCategory.DEVELOPMENT, PresetScope.USER)
        manager.create_preset("preset2", PresetCategory.PRODUCTION, PresetScope.SERVER)

        # List all presets
        all_presets = manager.list_presets()
        assert len(all_presets) >= 2

        # List by category
        dev_presets = manager.list_presets(category=PresetCategory.DEVELOPMENT)
        assert len(dev_presets) >= 1
        assert all(p.category == PresetCategory.DEVELOPMENT for p in dev_presets)

        # List by scope
        user_presets = manager.list_presets(scope=PresetScope.USER)
        assert len(user_presets) >= 1
        assert all(p.scope == PresetScope.USER for p in user_presets)

    def test_delete_preset(self, manager):
        """Test deleting preset."""
        # Create preset
        manager.create_preset("delete_test", PresetCategory.CUSTOM, PresetScope.USER)
        assert manager.preset_exists("delete_test")

        # Delete preset
        success = manager.delete_preset("delete_test", confirm=True)
        assert success
        assert not manager.preset_exists("delete_test")

    def test_apply_preset(self, manager):
        """Test applying preset."""
        # Create preset with mock data
        preset_data = {
            'preset': {
                'name': 'apply_test',
                'category': 'development',
                'scope': 'user'
            },
            'users': [
                {
                    'username': 'test_user',
                    'protocol': 'vless',
                    'active': True
                }
            ]
        }

        manager.save_preset("apply_test", preset_data)

        # Apply preset (dry run)
        result = manager.apply_preset("apply_test", dry_run=True)

        assert isinstance(result, PresetApplicationResult)
        assert result.preset_name == "apply_test"
        # Should have warnings about dry run and simulation
        assert result.has_warnings

    def test_export_import_preset(self, manager):
        """Test exporting and importing presets."""
        # Create preset
        manager.create_preset("export_test", PresetCategory.DEVELOPMENT, PresetScope.USER)

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as f:
            export_path = Path(f.name)

        try:
            # Export preset
            success = manager.export_preset("export_test", export_path)
            assert success
            assert export_path.exists()

            # Delete original
            manager.delete_preset("export_test", confirm=True)
            assert not manager.preset_exists("export_test")

            # Import preset
            success = manager.import_preset(export_path, "imported_test")
            assert success
            assert manager.preset_exists("imported_test")
        finally:
            export_path.unlink(missing_ok=True)


class TestYamlMigration:
    """Test YAML migration system."""

    @pytest.fixture
    def engine(self):
        """Create migration engine."""
        return YamlMigrationEngine()

    def test_migrate_toml_to_yaml(self, engine):
        """Test migrating TOML to YAML."""
        toml_content = """
[app]
name = "TOML App"
debug = true

[database]
type = "sqlite"
path = "/tmp/toml.db"
"""

        # Create temporary files
        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as toml_file:
            toml_file.write(toml_content)
            source_path = Path(toml_file.name)

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as yaml_file:
            target_path = Path(yaml_file.name)

        try:
            result = engine.migrate_config(
                source_path,
                target_path,
                "toml_to_yaml"
            )

            assert result.success
            assert target_path.exists()
            assert result.migrated_data is not None
            assert result.migrated_data['app']['name'] == "TOML App"
        finally:
            source_path.unlink(missing_ok=True)
            target_path.unlink(missing_ok=True)

    def test_migrate_env_to_yaml(self, engine):
        """Test migrating environment variables to YAML."""
        env_content = """
VPN_APP_NAME=Environment App
VPN_DEBUG=true
VPN_LOG_LEVEL=DEBUG
VPN_DATABASE_PATH=/tmp/env.db
VPN_BIND_ADDRESS=127.0.0.1
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as env_file:
            env_file.write(env_content)
            source_path = Path(env_file.name)

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as yaml_file:
            target_path = Path(yaml_file.name)

        try:
            result = engine.migrate_config(
                source_path,
                target_path,
                "env_to_yaml"
            )

            assert result.success
            assert target_path.exists()
            assert result.migrated_data['app']['name'] == "Environment App"
            assert result.migrated_data['app']['debug'] is True
        finally:
            source_path.unlink(missing_ok=True)
            target_path.unlink(missing_ok=True)

    def test_migration_with_backup(self, engine):
        """Test migration with backup creation."""
        source_content = """
[app]
name = "Backup Test"
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as source_file:
            source_file.write(source_content)
            source_path = Path(source_file.name)

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as target_file:
            target_path = Path(target_file.name)

        try:
            result = engine.migrate_config(
                source_path,
                target_path,
                "toml_to_yaml",
                backup=True
            )

            assert result.success
            assert result.backup_file is not None
            assert result.backup_file.exists()

            # Verify backup content
            with open(result.backup_file) as f:
                backup_content = f.read()
            assert "Backup Test" in backup_content

            # Clean up backup
            result.backup_file.unlink(missing_ok=True)
        finally:
            source_path.unlink(missing_ok=True)
            target_path.unlink(missing_ok=True)

    def test_batch_migration(self, engine):
        """Test batch migration."""
        with tempfile.TemporaryDirectory() as source_dir, tempfile.TemporaryDirectory() as target_dir:
            source_path = Path(source_dir)
            target_path = Path(target_dir)

            # Create multiple TOML files
            for i in range(3):
                toml_content = f"""
[app]
name = "App {i}"
debug = false
"""
                (source_path / f"config{i}.toml").write_text(toml_content)

            # Perform batch migration
            results = engine.batch_migrate(
                source_path,
                target_path,
                "toml_to_yaml",
                "*.toml"
            )

            assert len(results) == 3
            assert all(r.success for r in results)

            # Verify target files
            yaml_files = list(target_path.glob("*.yaml"))
            assert len(yaml_files) == 3

    def test_rollback_migration(self, engine):
        """Test rolling back migration."""
        source_content = """
[app]
name = "Rollback Test"
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as source_file:
            source_file.write(source_content)
            source_path = Path(source_file.name)

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as target_file:
            target_path = Path(target_file.name)

        try:
            # Migrate with backup
            result = engine.migrate_config(
                source_path,
                target_path,
                "toml_to_yaml",
                backup=True
            )

            assert result.success
            assert result.backup_file is not None

            # Modify source file
            source_path.write_text("[app]\nname = \"Modified\"")

            # Rollback
            rollback_success = engine.rollback_migration(result)
            assert rollback_success

            # Verify rollback
            restored_content = source_path.read_text()
            assert "Rollback Test" in restored_content

            # Clean up
            if result.backup_file:
                result.backup_file.unlink(missing_ok=True)
        finally:
            source_path.unlink(missing_ok=True)
            target_path.unlink(missing_ok=True)

    def test_migration_report(self, engine):
        """Test generating migration report."""
        # Create dummy migration results
        results = [
            MigrationResult(
                success=True,
                plan_name="test_plan",
                source_file=Path("/source1.toml"),
                target_file=Path("/target1.yaml")
            ),
            MigrationResult(
                success=False,
                plan_name="test_plan",
                source_file=Path("/source2.toml"),
                errors=["Test error"]
            )
        ]

        with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as report_file:
            report_path = Path(report_file.name)

        try:
            success = engine.export_migration_report(results, report_path)
            assert success
            assert report_path.exists()

            # Verify report content
            report_data = yaml_config_manager.load_yaml(report_path, validate_schema=False)
            assert report_data.is_valid
            assert 'migration_report' in report_data.data
            assert report_data.data['migration_report']['total_migrations'] == 2
            assert report_data.data['migration_report']['successful'] == 1
            assert report_data.data['migration_report']['failed'] == 1
        finally:
            report_path.unlink(missing_ok=True)


class TestYamlCustomConstructors:
    """Test custom YAML constructors and representers."""

    def test_duration_constructor(self):
        """Test duration constructor."""
        yaml_content = """
timeout: !duration "5m"
keepalive: !duration "30s"
cache_ttl: !duration "1h"
"""

        manager = YamlConfigManager()
        result = manager.load_yaml(yaml_content, validate_schema=False)

        assert result.is_valid
        assert result.data['timeout'] == 300  # 5 minutes in seconds
        assert result.data['keepalive'] == 30  # 30 seconds
        assert result.data['cache_ttl'] == 3600  # 1 hour in seconds

    def test_port_range_constructor(self):
        """Test port range constructor."""
        yaml_content = """
vless_ports: !port_range "8443"
shadowsocks_ports: !port_range "8000-8100"
"""

        manager = YamlConfigManager()
        result = manager.load_yaml(yaml_content, validate_schema=False)

        assert result.is_valid
        assert result.data['vless_ports'] == {'start': 8443, 'end': 8443}
        assert result.data['shadowsocks_ports'] == {'start': 8000, 'end': 8100}

    def test_file_size_constructor(self):
        """Test file size constructor."""
        yaml_content = """
max_log_size: !file_size "100MB"
cache_size: !file_size "1GB"
small_file: !file_size "1024B"
"""

        manager = YamlConfigManager()
        result = manager.load_yaml(yaml_content, validate_schema=False)

        assert result.is_valid
        assert result.data['max_log_size'] == 100 * 1024 * 1024  # 100MB in bytes
        assert result.data['cache_size'] == 1024 * 1024 * 1024  # 1GB in bytes
        assert result.data['small_file'] == 1024  # 1024 bytes

    @patch.dict('os.environ', {'TEST_VAR': 'test_value'})
    def test_env_constructor(self):
        """Test environment variable constructor."""
        yaml_content = """
simple_var: !env "TEST_VAR"
var_with_default: !env
  name: "MISSING_VAR"
  default: "default_value"
"""

        manager = YamlConfigManager()
        result = manager.load_yaml(yaml_content, validate_schema=False)

        assert result.is_valid
        assert result.data['simple_var'] == 'test_value'
        assert result.data['var_with_default'] == 'default_value'


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
