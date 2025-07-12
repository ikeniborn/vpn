"""
Configuration hot-reload system for dynamic configuration updates.

Monitors configuration files and environment variables for changes
and automatically reloads configuration without restarting the application.
"""

import asyncio
import os
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

from vpn.core.config_loader import ConfigLoader
from vpn.core.config_overlay import get_config_overlay
from vpn.core.enhanced_config import EnhancedSettings, get_settings
from vpn.core.exceptions import ConfigurationError
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ConfigChangeEvent:
    """Represents a configuration change event."""
    
    def __init__(
        self,
        change_type: str,
        file_path: Optional[Path] = None,
        env_var: Optional[str] = None,
        old_value: Any = None,
        new_value: Any = None
    ):
        self.change_type = change_type  # "file_changed", "file_created", "file_deleted", "env_changed"
        self.file_path = file_path
        self.env_var = env_var
        self.old_value = old_value
        self.new_value = new_value
        self.timestamp = time.time()
    
    def __str__(self) -> str:
        if self.change_type.startswith("file_"):
            return f"ConfigChangeEvent({self.change_type}, {self.file_path})"
        else:
            return f"ConfigChangeEvent({self.change_type}, {self.env_var})"


class ConfigFileHandler(FileSystemEventHandler):
    """File system event handler for configuration files."""
    
    def __init__(self, hot_reload_manager: 'ConfigHotReload'):
        self.hot_reload_manager = hot_reload_manager
        self.debounce_delay = 0.5  # Seconds to wait before processing changes
        self.pending_events: Dict[str, float] = {}
    
    def on_modified(self, event: FileSystemEvent):
        """Handle file modification events."""
        if event.is_directory:
            return
        
        file_path = Path(event.src_path)
        
        # Only process configuration files
        if not self._is_config_file(file_path):
            return
        
        # Debounce rapid file changes
        current_time = time.time()
        if file_path.name in self.pending_events:
            if current_time - self.pending_events[file_path.name] < self.debounce_delay:
                return
        
        self.pending_events[file_path.name] = current_time
        
        logger.debug(f"Configuration file modified: {file_path}")
        
        change_event = ConfigChangeEvent(
            change_type="file_changed",
            file_path=file_path
        )
        
        # Schedule reload
        asyncio.create_task(self.hot_reload_manager._handle_config_change(change_event))
    
    def on_created(self, event: FileSystemEvent):
        """Handle file creation events."""
        if event.is_directory:
            return
        
        file_path = Path(event.src_path)
        
        if not self._is_config_file(file_path):
            return
        
        logger.debug(f"Configuration file created: {file_path}")
        
        change_event = ConfigChangeEvent(
            change_type="file_created",
            file_path=file_path
        )
        
        asyncio.create_task(self.hot_reload_manager._handle_config_change(change_event))
    
    def on_deleted(self, event: FileSystemEvent):
        """Handle file deletion events."""
        if event.is_directory:
            return
        
        file_path = Path(event.src_path)
        
        if not self._is_config_file(file_path):
            return
        
        logger.debug(f"Configuration file deleted: {file_path}")
        
        change_event = ConfigChangeEvent(
            change_type="file_deleted",
            file_path=file_path
        )
        
        asyncio.create_task(self.hot_reload_manager._handle_config_change(change_event))
    
    def _is_config_file(self, file_path: Path) -> bool:
        """Check if file is a configuration file."""
        config_extensions = {'.yaml', '.yml', '.toml', '.json'}
        config_names = {'config', '.env'}
        
        return (
            file_path.suffix.lower() in config_extensions or
            file_path.stem.lower() in config_names or
            file_path.name.lower() in config_names
        )


class ConfigHotReload:
    """Manages configuration hot-reloading."""
    
    def __init__(self):
        self.loader = ConfigLoader()
        self.overlay_manager = get_config_overlay()
        self.observer: Optional[Observer] = None
        self.is_watching = False
        self.change_callbacks: List[Callable[[ConfigChangeEvent, EnhancedSettings], None]] = []
        self.error_callbacks: List[Callable[[Exception], None]] = []
        
        # Environment monitoring
        self._env_snapshot: Dict[str, str] = {}
        self._env_monitor_task: Optional[asyncio.Task] = None
        self._reload_enabled = True
        
        # Reload settings
        self.reload_debounce_delay = 1.0  # Seconds to wait before reloading
        self.max_reload_attempts = 3
        self.reload_retry_delay = 2.0  # Seconds between reload attempts
    
    def enable_hot_reload(self) -> bool:
        """Enable configuration hot-reload.
        
        Returns:
            True if hot-reload was enabled successfully
        """
        if self.is_watching:
            logger.warning("Hot-reload is already enabled")
            return True
        
        try:
            # Check if reload is enabled in settings
            settings = get_settings()
            if not settings.reload:
                logger.info("Hot-reload is disabled in configuration")
                return False
            
            self._reload_enabled = True
            
            # Start file system monitoring
            self._start_file_monitoring()
            
            # Start environment monitoring
            self._start_env_monitoring()
            
            logger.info("Configuration hot-reload enabled")
            return True
            
        except Exception as e:
            logger.error(f"Failed to enable hot-reload: {e}")
            return False
    
    def disable_hot_reload(self):
        """Disable configuration hot-reload."""
        self._reload_enabled = False
        
        # Stop file system monitoring
        if self.observer and self.observer.is_alive():
            self.observer.stop()
            self.observer.join()
            self.observer = None
        
        # Stop environment monitoring
        if self._env_monitor_task and not self._env_monitor_task.done():
            self._env_monitor_task.cancel()
            self._env_monitor_task = None
        
        self.is_watching = False
        logger.info("Configuration hot-reload disabled")
    
    def _start_file_monitoring(self):
        """Start file system monitoring for configuration files."""
        settings = get_settings()
        
        # Paths to monitor
        watch_paths = []
        
        # Add config directory
        if settings.paths.config_path.exists():
            watch_paths.append(settings.paths.config_path)
        
        # Add overlay directory
        overlay_dir = settings.paths.config_path / "overlays"
        if overlay_dir.exists():
            watch_paths.append(overlay_dir)
        
        # Add current directory for .env files
        watch_paths.append(Path.cwd())
        
        if not watch_paths:
            logger.warning("No configuration directories found to monitor")
            return
        
        # Create observer
        self.observer = Observer()
        event_handler = ConfigFileHandler(self)
        
        # Add watches for each path
        for path in watch_paths:
            if path.exists():
                self.observer.schedule(event_handler, str(path), recursive=True)
                logger.debug(f"Watching configuration directory: {path}")
        
        # Start monitoring
        self.observer.start()
        self.is_watching = True
        logger.debug("File system monitoring started")
    
    def _start_env_monitoring(self):
        """Start environment variable monitoring."""
        # Take initial snapshot
        self._env_snapshot = {k: v for k, v in os.environ.items() if k.startswith("VPN_")}
        
        # Start monitoring task
        self._env_monitor_task = asyncio.create_task(self._monitor_environment())
        logger.debug("Environment monitoring started")
    
    async def _monitor_environment(self):
        """Monitor environment variables for changes."""
        while self._reload_enabled:
            try:
                await asyncio.sleep(2.0)  # Check every 2 seconds
                
                current_env = {k: v for k, v in os.environ.items() if k.startswith("VPN_")}
                
                # Check for changes
                changes = self._detect_env_changes(self._env_snapshot, current_env)
                
                if changes:
                    logger.debug(f"Detected {len(changes)} environment variable changes")
                    
                    for change_event in changes:
                        await self._handle_config_change(change_event)
                    
                    # Update snapshot
                    self._env_snapshot = current_env.copy()
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Environment monitoring error: {e}")
                await asyncio.sleep(5.0)  # Wait before retrying
    
    def _detect_env_changes(
        self,
        old_env: Dict[str, str],
        new_env: Dict[str, str]
    ) -> List[ConfigChangeEvent]:
        """Detect changes in environment variables."""
        changes = []
        
        # Check for modified and new variables
        for var, new_value in new_env.items():
            old_value = old_env.get(var)
            
            if old_value != new_value:
                changes.append(ConfigChangeEvent(
                    change_type="env_changed",
                    env_var=var,
                    old_value=old_value,
                    new_value=new_value
                ))
        
        # Check for deleted variables
        for var, old_value in old_env.items():
            if var not in new_env:
                changes.append(ConfigChangeEvent(
                    change_type="env_changed",
                    env_var=var,
                    old_value=old_value,
                    new_value=None
                ))
        
        return changes
    
    async def _handle_config_change(self, change_event: ConfigChangeEvent):
        """Handle a configuration change event."""
        if not self._reload_enabled:
            return
        
        logger.info(f"Processing configuration change: {change_event}")
        
        # Debounce rapid changes
        await asyncio.sleep(self.reload_debounce_delay)
        
        # Attempt to reload configuration
        for attempt in range(self.max_reload_attempts):
            try:
                # Reload configuration
                new_settings = await self._reload_configuration()
                
                # Notify callbacks
                for callback in self.change_callbacks:
                    try:
                        callback(change_event, new_settings)
                    except Exception as e:
                        logger.error(f"Error in change callback: {e}")
                
                logger.info("Configuration reloaded successfully")
                return
                
            except Exception as e:
                logger.warning(f"Configuration reload attempt {attempt + 1} failed: {e}")
                
                if attempt < self.max_reload_attempts - 1:
                    await asyncio.sleep(self.reload_retry_delay)
                else:
                    # Final attempt failed, notify error callbacks
                    for callback in self.error_callbacks:
                        try:
                            callback(e)
                        except Exception as cb_error:
                            logger.error(f"Error in error callback: {cb_error}")
                    
                    logger.error(f"Failed to reload configuration after {self.max_reload_attempts} attempts")
    
    async def _reload_configuration(self) -> EnhancedSettings:
        """Reload the configuration from files and environment."""
        try:
            # Clear overlay cache
            self.overlay_manager.clear_cache()
            
            # Get current settings to determine what to reload
            current_settings = get_settings()
            
            # Find configuration files
            config_paths = current_settings.config_file_paths
            base_config_path = None
            
            for path in config_paths:
                if path.exists():
                    base_config_path = path
                    break
            
            # Check for active overlays (this would need to be tracked elsewhere)
            # For now, just reload the base configuration
            new_settings = EnhancedSettings()
            
            # Validate new configuration
            from vpn.core.config_validator import get_config_validator
            validator = get_config_validator()
            
            if base_config_path:
                is_valid, issues = validator.validate_config_file(base_config_path)
                if not is_valid:
                    error_messages = [str(issue) for issue in issues if issue.severity == "error"]
                    raise ConfigurationError(f"Configuration validation failed: {error_messages}")
            
            # Validate environment variables
            env_valid, env_issues = validator.validate_environment_variables()
            if not env_valid:
                env_errors = [str(issue) for issue in env_issues if issue.severity == "error"]
                raise ConfigurationError(f"Environment validation failed: {env_errors}")
            
            logger.debug("Configuration validation passed")
            return new_settings
            
        except Exception as e:
            raise ConfigurationError(f"Configuration reload failed: {e}")
    
    def add_change_callback(self, callback: Callable[[ConfigChangeEvent, EnhancedSettings], None]):
        """Add a callback to be called when configuration changes.
        
        Args:
            callback: Function to call with (change_event, new_settings)
        """
        self.change_callbacks.append(callback)
        logger.debug(f"Added configuration change callback: {callback.__name__}")
    
    def remove_change_callback(self, callback: Callable[[ConfigChangeEvent, EnhancedSettings], None]):
        """Remove a configuration change callback."""
        if callback in self.change_callbacks:
            self.change_callbacks.remove(callback)
            logger.debug(f"Removed configuration change callback: {callback.__name__}")
    
    def add_error_callback(self, callback: Callable[[Exception], None]):
        """Add a callback to be called when configuration reload fails.
        
        Args:
            callback: Function to call with the exception
        """
        self.error_callbacks.append(callback)
        logger.debug(f"Added configuration error callback: {callback.__name__}")
    
    def remove_error_callback(self, callback: Callable[[Exception], None]):
        """Remove a configuration error callback."""
        if callback in self.error_callbacks:
            self.error_callbacks.remove(callback)
            logger.debug(f"Removed configuration error callback: {callback.__name__}")
    
    def get_status(self) -> Dict[str, Any]:
        """Get hot-reload status information.
        
        Returns:
            Dictionary with status information
        """
        return {
            "enabled": self._reload_enabled,
            "watching": self.is_watching,
            "observer_alive": self.observer.is_alive() if self.observer else False,
            "env_monitoring": self._env_monitor_task is not None and not self._env_monitor_task.done(),
            "change_callbacks": len(self.change_callbacks),
            "error_callbacks": len(self.error_callbacks),
            "env_vars_count": len(self._env_snapshot),
            "debounce_delay": self.reload_debounce_delay,
            "max_attempts": self.max_reload_attempts
        }
    
    def force_reload(self) -> bool:
        """Force a configuration reload.
        
        Returns:
            True if reload was successful
        """
        if not self._reload_enabled:
            logger.warning("Hot-reload is disabled, cannot force reload")
            return False
        
        try:
            # Create a manual change event
            change_event = ConfigChangeEvent(change_type="manual_reload")
            
            # Schedule reload
            asyncio.create_task(self._handle_config_change(change_event))
            
            logger.info("Manual configuration reload triggered")
            return True
            
        except Exception as e:
            logger.error(f"Failed to trigger manual reload: {e}")
            return False


# Global hot-reload manager instance
_hot_reload_manager: Optional[ConfigHotReload] = None


def get_hot_reload_manager() -> ConfigHotReload:
    """Get the global hot-reload manager instance."""
    global _hot_reload_manager
    if _hot_reload_manager is None:
        _hot_reload_manager = ConfigHotReload()
    return _hot_reload_manager


def enable_config_hot_reload() -> bool:
    """Enable configuration hot-reload globally.
    
    Returns:
        True if hot-reload was enabled successfully
    """
    manager = get_hot_reload_manager()
    return manager.enable_hot_reload()


def disable_config_hot_reload():
    """Disable configuration hot-reload globally."""
    manager = get_hot_reload_manager()
    manager.disable_hot_reload()


def add_config_change_callback(callback: Callable[[ConfigChangeEvent, EnhancedSettings], None]):
    """Add a global configuration change callback."""
    manager = get_hot_reload_manager()
    manager.add_change_callback(callback)


def add_config_error_callback(callback: Callable[[Exception], None]):
    """Add a global configuration error callback."""
    manager = get_hot_reload_manager()
    manager.add_error_callback(callback)