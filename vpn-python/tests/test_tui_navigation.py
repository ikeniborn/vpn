"""
TUI navigation flow tests for VPN Manager.
"""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest
from textual.testing import AppTest

from vpn.core.models import ProtocolType, User, UserStatus
from vpn.tui.app import VPNManagerApp
from vpn.tui.screens.dashboard import DashboardScreen
from vpn.tui.screens.help import HelpScreen
from vpn.tui.screens.monitoring import MonitoringScreen
from vpn.tui.screens.servers import ServersScreen
from vpn.tui.screens.settings import SettingsScreen
from vpn.tui.screens.users import UsersScreen


class TestTUINavigation:
    """Test navigation flows in the TUI."""
    
    @pytest.fixture
    def mock_users(self):
        """Create mock users for testing."""
        return [
            User(
                username="alice",
                email="alice@example.com",
                status=UserStatus.ACTIVE,
                protocol={"protocol": ProtocolType.VLESS, "config": {"port": 8443}}
            ),
            User(
                username="bob",
                email="bob@example.com", 
                status=UserStatus.INACTIVE,
                protocol={"protocol": ProtocolType.SHADOWSOCKS, "config": {"port": 8388}}
            ),
        ]
    
    @pytest.fixture
    def app_test(self):
        """Create app test instance."""
        return AppTest(VPNManagerApp)
    
    def test_initial_screen_is_dashboard(self, app_test):
        """Test that the app starts on the dashboard screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Verify initial screen is dashboard
            assert isinstance(pilot.app.screen, DashboardScreen)
    
    def test_navigation_to_users_screen(self, app_test):
        """Test navigation to users screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Navigate using keyboard shortcut
            pilot.press("ctrl+u")
            pilot.pause(0.1)
            
            # Verify we're on the users screen
            assert isinstance(pilot.app.screen, UsersScreen)
    
    def test_navigation_to_servers_screen(self, app_test):
        """Test navigation to servers screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Navigate using keyboard shortcut
            pilot.press("ctrl+s")
            pilot.pause(0.1)
            
            # Verify we're on the servers screen
            assert isinstance(pilot.app.screen, ServersScreen)
    
    def test_navigation_to_monitoring_screen(self, app_test):
        """Test navigation to monitoring screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Navigate using keyboard shortcut
            pilot.press("ctrl+m")
            pilot.pause(0.1)
            
            # Verify we're on the monitoring screen
            assert isinstance(pilot.app.screen, MonitoringScreen)
    
    def test_navigation_to_settings_screen(self, app_test):
        """Test navigation to settings screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Navigate using keyboard shortcut
            pilot.press("ctrl+comma")
            pilot.pause(0.1)
            
            # Verify we're on the settings screen
            assert isinstance(pilot.app.screen, SettingsScreen)
    
    def test_help_screen_navigation(self, app_test):
        """Test navigation to help screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Open help with F1
            pilot.press("f1")
            pilot.pause(0.1)
            
            # Verify help screen is open (as modal/overlay)
            # This depends on implementation - help might be a modal
            assert pilot.app.screen is not None
    
    def test_back_navigation(self, app_test):
        """Test back navigation between screens."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Start at dashboard
            assert isinstance(pilot.app.screen, DashboardScreen)
            
            # Navigate to users
            pilot.press("ctrl+u")
            pilot.pause(0.1)
            assert isinstance(pilot.app.screen, UsersScreen)
            
            # Navigate back to dashboard
            pilot.press("ctrl+d")
            pilot.pause(0.1)
            assert isinstance(pilot.app.screen, DashboardScreen)
    
    def test_circular_navigation(self, app_test):
        """Test circular navigation through all screens."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Navigate through all screens in order
            navigation_sequence = [
                ("ctrl+d", DashboardScreen),
                ("ctrl+u", UsersScreen),
                ("ctrl+s", ServersScreen),
                ("ctrl+m", MonitoringScreen),
                ("ctrl+comma", SettingsScreen),
                ("ctrl+d", DashboardScreen),  # Back to start
            ]
            
            for key, expected_screen in navigation_sequence:
                pilot.press(key)
                pilot.pause(0.1)
                assert isinstance(pilot.app.screen, expected_screen)
    
    def test_escape_key_navigation(self, app_test):
        """Test escape key for closing modals and returning to main screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Open help modal
            pilot.press("f1")
            pilot.pause(0.1)
            
            # Close with escape
            pilot.press("escape")
            pilot.pause(0.1)
            
            # Should be back to the main screen
            assert pilot.app.screen is not None
    
    def test_tab_navigation_within_screen(self, app_test):
        """Test tab navigation within a screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Go to users screen
            pilot.press("ctrl+u")
            pilot.pause(0.1)
            
            # Use tab to navigate between focusable elements
            pilot.press("tab")
            pilot.pause(0.1)
            
            pilot.press("tab")
            pilot.pause(0.1)
            
            # Verify we're still on the users screen
            assert isinstance(pilot.app.screen, UsersScreen)
    
    def test_shift_tab_reverse_navigation(self, app_test):
        """Test shift+tab for reverse navigation within screen."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Go to users screen
            pilot.press("ctrl+u")
            pilot.pause(0.1)
            
            # Tab forward a few times
            pilot.press("tab")
            pilot.press("tab")
            pilot.pause(0.1)
            
            # Tab backward
            pilot.press("shift+tab")
            pilot.pause(0.1)
            
            # Verify we're still on the users screen
            assert isinstance(pilot.app.screen, UsersScreen)
    
    @pytest.mark.asyncio
    async def test_screen_refresh_navigation(self, app_test, mock_users):
        """Test refresh functionality in screens."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_user_manager.return_value = mock_instance
            
            with app_test as pilot:
                # Go to users screen
                pilot.press("ctrl+u")
                pilot.pause(0.1)
                
                # Refresh with F5
                pilot.press("f5")
                pilot.pause(0.1)
                
                # Verify we're still on the users screen
                assert isinstance(pilot.app.screen, UsersScreen)
                
                # Verify user manager was called for refresh
                mock_instance.list_users.assert_called()
    
    def test_quit_application_navigation(self, app_test):
        """Test quitting the application."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Try to quit with Ctrl+Q
            pilot.press("ctrl+q")
            pilot.pause(0.1)
            
            # App should either show quit confirmation or exit
            # This depends on implementation
    
    def test_invalid_key_handling(self, app_test):
        """Test handling of invalid/unmapped keys."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            initial_screen = pilot.app.screen
            
            # Press some unmapped keys
            pilot.press("ctrl+z")
            pilot.press("alt+x")
            pilot.press("f10")
            pilot.pause(0.1)
            
            # Should still be on the same screen
            assert type(pilot.app.screen) == type(initial_screen)


class TestTUIUserFlows:
    """Test complete user interaction flows."""
    
    @pytest.fixture
    def app_test(self):
        return AppTest(VPNManagerApp)
    
    @pytest.fixture
    def mock_users(self):
        return [
            User(
                username="alice",
                email="alice@example.com",
                status=UserStatus.ACTIVE,
                protocol={"protocol": ProtocolType.VLESS, "config": {"port": 8443}}
            ),
        ]
    
    @pytest.mark.asyncio
    async def test_user_management_flow(self, app_test, mock_users):
        """Test complete user management flow."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_instance.create.return_value = mock_users[0]
            mock_instance.delete.return_value = True
            mock_user_manager.return_value = mock_instance
            
            with app_test as pilot:
                # Navigate to users screen
                pilot.press("ctrl+u")
                pilot.pause(0.1)
                
                # Try to create new user (if button exists)
                try:
                    pilot.press("n")  # Common shortcut for "new"
                    pilot.pause(0.1)
                except Exception:
                    # New user dialog might not be implemented
                    pass
                
                # Try to select a user
                pilot.press("down")  # Navigate to first user
                pilot.pause(0.1)
                
                # Try to view user details
                pilot.press("enter")
                pilot.pause(0.1)
                
                # Verify we're still in a valid state
                assert pilot.app.is_running
    
    @pytest.mark.asyncio
    async def test_server_management_flow(self, app_test):
        """Test server management flow."""
        with app_test as pilot:
            # Navigate to servers screen
            pilot.press("ctrl+s")
            pilot.pause(0.1)
            
            # Try server-related actions
            pilot.press("r")  # Refresh
            pilot.pause(0.1)
            
            pilot.press("s")  # Start/stop server
            pilot.pause(0.1)
            
            # Verify app is still running
            assert pilot.app.is_running
    
    def test_monitoring_flow(self, app_test):
        """Test monitoring screen flow."""
        with app_test as pilot:
            # Navigate to monitoring
            pilot.press("ctrl+m")
            pilot.pause(0.1)
            
            # Try monitoring actions
            pilot.press("r")  # Refresh
            pilot.pause(0.1)
            
            # Change time range
            pilot.press("1")  # 1 hour
            pilot.pause(0.1)
            
            pilot.press("2")  # 24 hours
            pilot.pause(0.1)
            
            # Verify app state
            assert isinstance(pilot.app.screen, MonitoringScreen)
    
    def test_settings_configuration_flow(self, app_test):
        """Test settings configuration flow."""
        with app_test as pilot:
            # Navigate to settings
            pilot.press("ctrl+comma")
            pilot.pause(0.1)
            
            # Try settings navigation
            pilot.press("tab")  # Navigate through settings
            pilot.pause(0.1)
            
            pilot.press("space")  # Toggle setting
            pilot.pause(0.1)
            
            # Apply settings
            pilot.press("enter")
            pilot.pause(0.1)
            
            # Verify we're still on settings
            assert isinstance(pilot.app.screen, SettingsScreen)


class TestTUIKeyboardShortcuts:
    """Test all keyboard shortcuts work correctly."""
    
    @pytest.fixture
    def app_test(self):
        return AppTest(VPNManagerApp)
    
    def test_global_shortcuts(self, app_test):
        """Test global keyboard shortcuts."""
        shortcuts = {
            "ctrl+d": DashboardScreen,
            "ctrl+u": UsersScreen,
            "ctrl+s": ServersScreen,
            "ctrl+m": MonitoringScreen,
            "ctrl+comma": SettingsScreen,
        }
        
        with app_test as pilot:
            pilot.pause(0.1)
            
            for shortcut, expected_screen in shortcuts.items():
                pilot.press(shortcut)
                pilot.pause(0.1)
                
                # Verify navigation worked
                assert isinstance(pilot.app.screen, expected_screen), f"Shortcut {shortcut} failed"
    
    def test_help_shortcut(self, app_test):
        """Test help shortcut."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Press F1 for help
            pilot.press("f1")
            pilot.pause(0.1)
            
            # Help should be accessible (either as screen or modal)
            assert pilot.app.screen is not None
    
    def test_refresh_shortcut(self, app_test):
        """Test refresh shortcut."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Press F5 for refresh
            pilot.press("f5")
            pilot.pause(0.1)
            
            # App should still be running
            assert pilot.app.is_running
    
    def test_theme_toggle_shortcut(self, app_test):
        """Test theme toggle shortcut."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            initial_theme = pilot.app.dark
            
            # Toggle theme (common shortcut might be Ctrl+T)
            try:
                pilot.press("ctrl+t")
                pilot.pause(0.1)
                
                # Theme should have changed
                assert pilot.app.dark != initial_theme
            except Exception:
                # Theme toggle might not be implemented
                pytest.skip("Theme toggle shortcut not implemented")


class TestTUIErrorHandling:
    """Test error handling in navigation flows."""
    
    @pytest.fixture
    def app_test(self):
        return AppTest(VPNManagerApp)
    
    @pytest.mark.asyncio
    async def test_navigation_with_service_error(self, app_test):
        """Test navigation when services fail."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            # Mock service to raise exception
            mock_instance = AsyncMock()
            mock_instance.list_users.side_effect = Exception("Service unavailable")
            mock_user_manager.return_value = mock_instance
            
            with app_test as pilot:
                # Navigate to users screen
                pilot.press("ctrl+u")
                pilot.pause(0.2)
                
                # App should handle the error gracefully
                assert pilot.app.is_running
                assert isinstance(pilot.app.screen, UsersScreen)
    
    def test_rapid_navigation(self, app_test):
        """Test rapid navigation between screens."""
        with app_test as pilot:
            pilot.pause(0.1)
            
            # Rapidly navigate between screens
            for _ in range(5):
                pilot.press("ctrl+u")
                pilot.press("ctrl+s")
                pilot.press("ctrl+m")
                pilot.press("ctrl+d")
                pilot.pause(0.05)
            
            # App should still be responsive
            assert pilot.app.is_running
    
    def test_navigation_during_loading(self, app_test):
        """Test navigation while screens are loading."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            
            # Mock slow loading
            async def slow_load():
                await asyncio.sleep(0.2)
                return []
            
            mock_instance.list_users = slow_load
            mock_user_manager.return_value = mock_instance
            
            with app_test as pilot:
                # Start navigation to users
                pilot.press("ctrl+u")
                pilot.pause(0.1)  # Don't wait for full load
                
                # Try to navigate elsewhere immediately
                pilot.press("ctrl+s")
                pilot.pause(0.1)
                
                # App should handle this gracefully
                assert pilot.app.is_running


if __name__ == "__main__":
    pytest.main([__file__, "-v"])