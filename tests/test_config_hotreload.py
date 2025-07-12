"""
Tests for configuration hot-reload system.
"""

import asyncio
import os
import tempfile
import time
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import yaml

from vpn.core.config_hotreload import (
    ConfigChangeEvent,
    ConfigFileHandler,
    ConfigHotReload,
    get_hot_reload_manager,
)


class TestConfigChangeEvent:
    """Test ConfigChangeEvent class."""
    
    def test_file_change_event(self):
        """Test file change event creation."""
        file_path = Path("/test/config.yaml")
        event = ConfigChangeEvent(
            change_type="file_changed",
            file_path=file_path
        )
        
        assert event.change_type == "file_changed"
        assert event.file_path == file_path
        assert event.env_var is None
        assert event.timestamp > 0
    
    def test_env_change_event(self):
        """Test environment variable change event."""
        event = ConfigChangeEvent(
            change_type="env_changed",
            env_var="VPN_DEBUG",
            old_value="false",
            new_value="true"
        )
        
        assert event.change_type == "env_changed"
        assert event.env_var == "VPN_DEBUG"
        assert event.old_value == "false"
        assert event.new_value == "true"
        assert event.file_path is None
    
    def test_event_string_representation(self):
        """Test string representation of events."""
        file_event = ConfigChangeEvent(
            change_type="file_changed",
            file_path=Path("/test/config.yaml")
        )
        
        env_event = ConfigChangeEvent(
            change_type="env_changed",
            env_var="VPN_DEBUG"
        )
        
        assert "file_changed" in str(file_event)
        assert "config.yaml" in str(file_event)
        assert "env_changed" in str(env_event)
        assert "VPN_DEBUG" in str(env_event)


class TestConfigFileHandler:
    """Test ConfigFileHandler class."""
    
    def test_is_config_file(self):
        """Test configuration file detection."""
        hot_reload = MagicMock()
        handler = ConfigFileHandler(hot_reload)
        
        # Test config file extensions
        assert handler._is_config_file(Path("config.yaml"))
        assert handler._is_config_file(Path("config.yml"))
        assert handler._is_config_file(Path("config.toml"))
        assert handler._is_config_file(Path("config.json"))
        
        # Test config file names
        assert handler._is_config_file(Path("config"))
        assert handler._is_config_file(Path(".env"))
        
        # Test non-config files
        assert not handler._is_config_file(Path("script.py"))
        assert not handler._is_config_file(Path("data.txt"))
        assert not handler._is_config_file(Path("image.png"))
    
    @patch('asyncio.create_task')
    def test_on_modified(self, mock_create_task):
        """Test file modification handling."""
        hot_reload = MagicMock()
        handler = ConfigFileHandler(hot_reload)
        
        # Mock file system event
        event = MagicMock()
        event.is_directory = False
        event.src_path = "/test/config.yaml"
        
        handler.on_modified(event)
        
        # Should create a task to handle the change
        mock_create_task.assert_called_once()
    
    @patch('asyncio.create_task')
    def test_on_created(self, mock_create_task):
        """Test file creation handling."""
        hot_reload = MagicMock()
        handler = ConfigFileHandler(hot_reload)
        
        event = MagicMock()
        event.is_directory = False
        event.src_path = "/test/new-config.yaml"
        
        handler.on_created(event)
        
        mock_create_task.assert_called_once()
    
    @patch('asyncio.create_task')
    def test_on_deleted(self, mock_create_task):
        """Test file deletion handling."""
        hot_reload = MagicMock()
        handler = ConfigFileHandler(hot_reload)
        
        event = MagicMock()
        event.is_directory = False
        event.src_path = "/test/old-config.yaml"
        
        handler.on_deleted(event)
        
        mock_create_task.assert_called_once()
    
    def test_ignore_directory_events(self):
        """Test that directory events are ignored."""
        hot_reload = MagicMock()
        handler = ConfigFileHandler(hot_reload)
        
        event = MagicMock()
        event.is_directory = True
        event.src_path = "/test/config-dir"
        
        with patch('asyncio.create_task') as mock_create_task:
            handler.on_modified(event)
            handler.on_created(event)
            handler.on_deleted(event)
            
            # No tasks should be created for directory events
            mock_create_task.assert_not_called()
    
    def test_ignore_non_config_files(self):
        """Test that non-config files are ignored."""
        hot_reload = MagicMock()
        handler = ConfigFileHandler(hot_reload)
        
        event = MagicMock()
        event.is_directory = False
        event.src_path = "/test/script.py"
        
        with patch('asyncio.create_task') as mock_create_task:
            handler.on_modified(event)
            
            mock_create_task.assert_not_called()


class TestConfigHotReload:
    """Test ConfigHotReload class."""
    
    def test_initialization(self):
        """Test hot-reload manager initialization."""
        hot_reload = ConfigHotReload()
        
        assert hot_reload.loader is not None
        assert hot_reload.overlay_manager is not None
        assert hot_reload.observer is None
        assert not hot_reload.is_watching
        assert hot_reload.change_callbacks == []
        assert hot_reload.error_callbacks == []
        assert hot_reload._env_snapshot == {}
    
    def test_detect_env_changes(self):
        """Test environment variable change detection."""
        hot_reload = ConfigHotReload()
        
        old_env = {
            "VPN_DEBUG": "false",
            "VPN_LOG_LEVEL": "INFO"
        }
        
        new_env = {
            "VPN_DEBUG": "true",  # Modified
            "VPN_LOG_LEVEL": "INFO",  # Unchanged
            "VPN_NEW_VAR": "value"  # Added
            # VPN_DELETED_VAR removed
        }
        
        changes = hot_reload._detect_env_changes(old_env, new_env)
        
        # Should detect 2 changes: modification and addition
        assert len(changes) == 2
        
        # Check modification
        debug_change = next(c for c in changes if c.env_var == "VPN_DEBUG")
        assert debug_change.change_type == "env_changed"
        assert debug_change.old_value == "false"
        assert debug_change.new_value == "true"
        
        # Check addition
        new_var_change = next(c for c in changes if c.env_var == "VPN_NEW_VAR")
        assert new_var_change.change_type == "env_changed"
        assert new_var_change.old_value is None
        assert new_var_change.new_value == "value"
    
    def test_detect_env_deletions(self):
        """Test detection of deleted environment variables."""
        hot_reload = ConfigHotReload()
        
        old_env = {
            "VPN_DEBUG": "false",
            "VPN_DELETED": "value"
        }
        
        new_env = {
            "VPN_DEBUG": "false"
        }
        
        changes = hot_reload._detect_env_changes(old_env, new_env)
        
        assert len(changes) == 1
        
        deleted_change = changes[0]
        assert deleted_change.env_var == "VPN_DELETED"
        assert deleted_change.old_value == "value"
        assert deleted_change.new_value is None
    
    def test_add_remove_callbacks(self):
        """Test adding and removing callbacks."""
        hot_reload = ConfigHotReload()
        
        def change_callback(event, settings):
            pass
        
        def error_callback(error):
            pass
        
        # Add callbacks
        hot_reload.add_change_callback(change_callback)
        hot_reload.add_error_callback(error_callback)
        
        assert change_callback in hot_reload.change_callbacks
        assert error_callback in hot_reload.error_callbacks
        
        # Remove callbacks
        hot_reload.remove_change_callback(change_callback)
        hot_reload.remove_error_callback(error_callback)
        
        assert change_callback not in hot_reload.change_callbacks
        assert error_callback not in hot_reload.error_callbacks
    
    def test_get_status(self):
        """Test status information retrieval."""
        hot_reload = ConfigHotReload()
        
        status = hot_reload.get_status()
        
        assert isinstance(status, dict)
        assert "enabled" in status
        assert "watching" in status
        assert "observer_alive" in status
        assert "env_monitoring" in status
        assert "change_callbacks" in status
        assert "error_callbacks" in status
        assert "env_vars_count" in status
        assert "debounce_delay" in status
        assert "max_attempts" in status
    
    @patch('vpn.core.config_hotreload.get_settings')
    def test_enable_hot_reload_disabled_in_config(self, mock_get_settings):
        """Test enabling hot-reload when disabled in configuration."""
        # Mock settings with reload disabled
        mock_settings = MagicMock()
        mock_settings.reload = False
        mock_get_settings.return_value = mock_settings
        
        hot_reload = ConfigHotReload()
        result = hot_reload.enable_hot_reload()
        
        assert not result
        assert not hot_reload.is_watching
    
    def test_disable_hot_reload(self):
        """Test disabling hot-reload."""
        hot_reload = ConfigHotReload()
        hot_reload._reload_enabled = True
        hot_reload.is_watching = True
        
        # Mock observer
        mock_observer = MagicMock()
        mock_observer.is_alive.return_value = True
        hot_reload.observer = mock_observer
        
        # Mock environment monitor task
        mock_task = MagicMock()
        mock_task.done.return_value = False
        hot_reload._env_monitor_task = mock_task
        
        hot_reload.disable_hot_reload()
        
        assert not hot_reload._reload_enabled
        assert not hot_reload.is_watching
        mock_observer.stop.assert_called_once()
        mock_observer.join.assert_called_once()
        mock_task.cancel.assert_called_once()
    
    @patch('vpn.core.config_hotreload.get_settings')
    def test_force_reload(self, mock_get_settings):
        """Test forcing a configuration reload."""
        mock_settings = MagicMock()
        mock_get_settings.return_value = mock_settings
        
        hot_reload = ConfigHotReload()
        hot_reload._reload_enabled = True
        
        with patch('asyncio.create_task') as mock_create_task:
            result = hot_reload.force_reload()
            
            assert result
            mock_create_task.assert_called_once()
    
    def test_force_reload_disabled(self):
        """Test forcing reload when hot-reload is disabled."""
        hot_reload = ConfigHotReload()
        hot_reload._reload_enabled = False
        
        result = hot_reload.force_reload()
        
        assert not result
    
    @pytest.mark.asyncio
    async def test_handle_config_change(self):
        """Test configuration change handling."""
        hot_reload = ConfigHotReload()
        hot_reload._reload_enabled = True
        hot_reload.reload_debounce_delay = 0.01  # Fast for testing
        hot_reload.max_reload_attempts = 1
        
        # Mock reload method
        mock_settings = MagicMock()
        hot_reload._reload_configuration = AsyncMock(return_value=mock_settings)
        
        # Mock callback
        callback_called = False
        def test_callback(event, settings):
            nonlocal callback_called
            callback_called = True
        
        hot_reload.add_change_callback(test_callback)
        
        # Create test event
        event = ConfigChangeEvent(change_type="file_changed")
        
        # Handle change
        await hot_reload._handle_config_change(event)
        
        # Verify callback was called
        assert callback_called
        hot_reload._reload_configuration.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_handle_config_change_with_error(self):
        """Test configuration change handling with errors."""
        hot_reload = ConfigHotReload()
        hot_reload._reload_enabled = True
        hot_reload.reload_debounce_delay = 0.01
        hot_reload.max_reload_attempts = 2
        hot_reload.reload_retry_delay = 0.01
        
        # Mock reload method to fail
        from vpn.core.exceptions import ConfigurationError
        hot_reload._reload_configuration = AsyncMock(
            side_effect=ConfigurationError("Test error")
        )
        
        # Mock error callback
        error_called = False
        def test_error_callback(error):
            nonlocal error_called
            error_called = True
        
        hot_reload.add_error_callback(test_error_callback)
        
        # Create test event
        event = ConfigChangeEvent(change_type="file_changed")
        
        # Handle change
        await hot_reload._handle_config_change(event)
        
        # Verify error callback was called
        assert error_called
        # Should have attempted reload max_attempts times
        assert hot_reload._reload_configuration.call_count == 2
    
    @pytest.mark.asyncio
    async def test_reload_configuration(self):
        """Test configuration reloading."""
        hot_reload = ConfigHotReload()
        
        with patch('vpn.core.config_hotreload.get_settings') as mock_get_settings:
            with patch('vpn.core.config_hotreload.get_config_validator') as mock_get_validator:
                # Mock settings
                mock_settings = MagicMock()
                mock_settings.config_file_paths = []
                mock_get_settings.return_value = mock_settings
                
                # Mock validator
                mock_validator = MagicMock()
                mock_validator.validate_environment_variables.return_value = (True, [])
                mock_get_validator.return_value = mock_validator
                
                # Mock EnhancedSettings
                with patch('vpn.core.config_hotreload.EnhancedSettings') as mock_enhanced_settings:
                    mock_new_settings = MagicMock()
                    mock_enhanced_settings.return_value = mock_new_settings
                    
                    result = await hot_reload._reload_configuration()
                    
                    assert result == mock_new_settings
                    mock_validator.validate_environment_variables.assert_called_once()


class TestGlobalFunctions:
    """Test global hot-reload functions."""
    
    def test_get_hot_reload_manager(self):
        """Test get_hot_reload_manager function."""
        manager1 = get_hot_reload_manager()
        manager2 = get_hot_reload_manager()
        
        # Should return same instance
        assert manager1 is manager2
        assert isinstance(manager1, ConfigHotReload)


class TestIntegrationScenarios:
    """Test integration scenarios."""
    
    @pytest.mark.asyncio
    async def test_environment_monitoring_integration(self):
        """Test environment variable monitoring integration."""
        hot_reload = ConfigHotReload()
        hot_reload._reload_enabled = True
        
        # Set initial environment
        initial_env = {"VPN_DEBUG": "false"}
        hot_reload._env_snapshot = initial_env.copy()
        
        # Mock environment changes
        changed_env = {"VPN_DEBUG": "true", "VPN_NEW": "value"}
        
        with patch.dict(os.environ, changed_env, clear=False):
            with patch.object(hot_reload, '_handle_config_change') as mock_handle:
                # Simulate one monitoring cycle
                current_env = {k: v for k, v in os.environ.items() if k.startswith("VPN_")}
                changes = hot_reload._detect_env_changes(initial_env, current_env)
                
                # Should detect changes
                assert len(changes) == 2
                
                # Verify environment snapshot gets updated
                hot_reload._env_snapshot = current_env.copy()
                assert hot_reload._env_snapshot["VPN_DEBUG"] == "true"
                assert hot_reload._env_snapshot["VPN_NEW"] == "value"
    
    def test_file_monitoring_integration(self):
        """Test file monitoring integration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_dir = Path(temp_dir) / "config"
            config_dir.mkdir()
            
            # Create a config file
            config_file = config_dir / "test.yaml"
            config_content = {"debug": False}
            
            with open(config_file, 'w') as f:
                yaml.dump(config_content, f)
            
            hot_reload = ConfigHotReload()
            handler = ConfigFileHandler(hot_reload)
            
            # Test file detection
            assert handler._is_config_file(config_file)
            
            # Mock file system event
            event = MagicMock()
            event.is_directory = False
            event.src_path = str(config_file)
            
            with patch('asyncio.create_task') as mock_create_task:
                handler.on_modified(event)
                
                # Should create task to handle change
                mock_create_task.assert_called_once()
                
                # Verify the task argument is correct
                args, kwargs = mock_create_task.call_args
                task_coro = args[0]
                # The coroutine should be _handle_config_change
                assert hasattr(task_coro, 'cr_code')
                assert 'handle_config_change' in task_coro.cr_code.co_name