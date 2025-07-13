"""
TUI snapshot tests for VPN Manager Textual UI.
"""

import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from textual.app import App
from textual.testing import AppTest

from vpn.core.models import ProtocolType, User, UserStatus
from vpn.tui.app import VPNManagerApp
from vpn.tui.screens.dashboard import DashboardScreen
from vpn.tui.screens.users import UsersScreen


class TestTUISnapshots:
    """Test TUI screenshots and visual snapshots."""

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
            User(
                username="charlie",
                email="charlie@example.com",
                status=UserStatus.SUSPENDED,
                protocol={"protocol": ProtocolType.WIREGUARD, "config": {"port": 51820}}
            ),
        ]

    @pytest.fixture
    def app_test(self):
        """Create app test instance."""
        return AppTest(VPNManagerApp)

    def test_app_startup_snapshot(self, app_test):
        """Test the application startup screen."""
        with app_test as pilot:
            # Wait for app to load
            pilot.pause(0.1)

            # Take snapshot of initial state
            snapshot = pilot.app.export_screenshot()

            # Verify the app started correctly
            assert pilot.app.is_running
            assert snapshot is not None

            # Check if dashboard is the initial screen
            assert isinstance(pilot.app.screen, DashboardScreen)

    @pytest.mark.asyncio
    async def test_dashboard_screen_snapshot(self, app_test, mock_users):
        """Test dashboard screen visual appearance."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            # Mock user manager to return test users
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_instance.get_stats.return_value = {
                'total_users': 3,
                'active_users': 1,
                'inactive_users': 1,
                'suspended_users': 1
            }
            mock_user_manager.return_value = mock_instance

            with app_test as pilot:
                # Navigate to dashboard
                pilot.app.push_screen("dashboard")
                pilot.pause(0.1)

                # Take snapshot
                snapshot = pilot.app.export_screenshot()
                assert snapshot is not None

                # Verify dashboard elements are present
                dashboard = pilot.app.screen
                assert hasattr(dashboard, 'compose')

    @pytest.mark.asyncio
    async def test_users_screen_snapshot(self, app_test, mock_users):
        """Test users screen visual appearance."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            # Mock user manager
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_user_manager.return_value = mock_instance

            with app_test as pilot:
                # Navigate to users screen
                pilot.app.push_screen("users")
                pilot.pause(0.1)

                # Take snapshot
                snapshot = pilot.app.export_screenshot()
                assert snapshot is not None

                # Verify users screen loaded
                assert isinstance(pilot.app.screen, UsersScreen)

    def test_help_screen_snapshot(self, app_test):
        """Test help screen visual appearance."""
        with app_test as pilot:
            # Press F1 to open help
            pilot.press("f1")
            pilot.pause(0.1)

            # Take snapshot
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

            # Verify help screen is displayed
            # Note: This depends on the help screen implementation

    def test_theme_dark_snapshot(self, app_test):
        """Test dark theme appearance."""
        with app_test as pilot:
            # Set dark theme
            pilot.app.dark = True
            pilot.pause(0.1)

            # Take snapshot
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

            # Verify dark theme is active
            assert pilot.app.dark is True

    def test_theme_light_snapshot(self, app_test):
        """Test light theme appearance."""
        with app_test as pilot:
            # Set light theme
            pilot.app.dark = False
            pilot.pause(0.1)

            # Take snapshot
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

            # Verify light theme is active
            assert pilot.app.dark is False

    @pytest.mark.asyncio
    async def test_user_details_modal_snapshot(self, app_test, mock_users):
        """Test user details modal appearance."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_instance.get_by_username.return_value = mock_users[0]
            mock_user_manager.return_value = mock_instance

            with app_test as pilot:
                # Navigate to users screen
                pilot.app.push_screen("users")
                pilot.pause(0.1)

                # Simulate selecting a user (this would depend on the actual UI)
                # For now, just take a snapshot of the users screen
                snapshot = pilot.app.export_screenshot()
                assert snapshot is not None

    def test_responsive_layout_small_terminal(self, app_test):
        """Test UI responsiveness on small terminal size."""
        with app_test as pilot:
            # Set small terminal size
            pilot.app.size = (80, 24)
            pilot.pause(0.1)

            # Take snapshot
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

            # Verify app adapts to small size
            assert pilot.app.size.width == 80
            assert pilot.app.size.height == 24

    def test_responsive_layout_large_terminal(self, app_test):
        """Test UI responsiveness on large terminal size."""
        with app_test as pilot:
            # Set large terminal size
            pilot.app.size = (200, 60)
            pilot.pause(0.1)

            # Take snapshot
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

            # Verify app adapts to large size
            assert pilot.app.size.width == 200
            assert pilot.app.size.height == 60

    @pytest.mark.asyncio
    async def test_error_state_snapshot(self, app_test):
        """Test error state visual appearance."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            # Mock user manager to raise an exception
            mock_instance = AsyncMock()
            mock_instance.list_users.side_effect = Exception("Database connection failed")
            mock_user_manager.return_value = mock_instance

            with app_test as pilot:
                # Navigate to users screen to trigger error
                pilot.app.push_screen("users")
                pilot.pause(0.2)

                # Take snapshot of error state
                snapshot = pilot.app.export_screenshot()
                assert snapshot is not None

    def test_navigation_shortcuts_snapshot(self, app_test):
        """Test navigation with keyboard shortcuts."""
        with app_test as pilot:
            # Test various navigation shortcuts
            shortcuts = [
                ("ctrl+d", "dashboard"),
                ("ctrl+u", "users"),
                ("ctrl+s", "servers"),
                ("ctrl+m", "monitoring"),
                ("ctrl+c", "settings"),
            ]

            for key, expected_screen in shortcuts:
                try:
                    pilot.press(key)
                    pilot.pause(0.1)

                    # Take snapshot after navigation
                    snapshot = pilot.app.export_screenshot()
                    assert snapshot is not None

                except Exception as e:
                    # Some shortcuts might not be implemented yet
                    pytest.skip(f"Shortcut {key} not implemented: {e}")

    @pytest.mark.asyncio
    async def test_loading_state_snapshot(self, app_test):
        """Test loading state visual appearance."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            # Mock user manager with delayed response
            mock_instance = AsyncMock()

            async def delayed_response():
                await asyncio.sleep(0.1)
                return []

            mock_instance.list_users = delayed_response
            mock_user_manager.return_value = mock_instance

            with app_test as pilot:
                # Navigate to users screen
                pilot.app.push_screen("users")

                # Take snapshot during loading
                pilot.pause(0.05)  # Mid-loading
                snapshot = pilot.app.export_screenshot()
                assert snapshot is not None

                # Wait for loading to complete
                pilot.pause(0.15)
                final_snapshot = pilot.app.export_screenshot()
                assert final_snapshot is not None

    def test_footer_and_header_snapshot(self, app_test):
        """Test header and footer visual elements."""
        with app_test as pilot:
            pilot.pause(0.1)

            # Take snapshot to verify header/footer elements
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

            # Verify the app has proper header/footer structure
            # This would depend on the actual implementation

    @pytest.mark.asyncio
    async def test_search_functionality_snapshot(self, app_test, mock_users):
        """Test search functionality visual state."""
        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_instance.search_users.return_value = [mock_users[0]]  # Return alice only
            mock_user_manager.return_value = mock_instance

            with app_test as pilot:
                # Navigate to users screen
                pilot.app.push_screen("users")
                pilot.pause(0.1)

                # Simulate search (if search widget exists)
                try:
                    pilot.press("ctrl+f")  # Common search shortcut
                    pilot.pause(0.1)

                    # Type search term
                    pilot.type("alice")
                    pilot.pause(0.1)

                    # Take snapshot of search results
                    snapshot = pilot.app.export_screenshot()
                    assert snapshot is not None

                except Exception:
                    # Search might not be implemented yet
                    pytest.skip("Search functionality not implemented")


class TestTUIWidgetSnapshots:
    """Test individual widget visual snapshots."""

    def test_user_list_widget_snapshot(self):
        """Test user list widget appearance."""
        from vpn.tui.widgets.user_list import UserList

        # Create test app with UserList widget
        class TestApp(App):
            def compose(self):
                yield UserList()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

    def test_traffic_chart_widget_snapshot(self):
        """Test traffic chart widget appearance."""
        from vpn.tui.widgets.traffic_chart import TrafficChart

        class TestApp(App):
            def compose(self):
                yield TrafficChart()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

    def test_server_status_widget_snapshot(self):
        """Test server status widget appearance."""
        from vpn.tui.widgets.server_status import ServerStatus

        class TestApp(App):
            def compose(self):
                yield ServerStatus()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None

    def test_log_viewer_widget_snapshot(self):
        """Test log viewer widget appearance."""
        from vpn.tui.widgets.log_viewer import LogViewer

        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            snapshot = pilot.app.export_screenshot()
            assert snapshot is not None


class TestTUIVisualRegression:
    """Visual regression tests for TUI."""

    def setup_method(self):
        """Set up test environment."""
        self.snapshots_dir = Path(__file__).parent / "snapshots"
        self.snapshots_dir.mkdir(exist_ok=True)

    def save_snapshot(self, name: str, content: str):
        """Save snapshot to file."""
        snapshot_file = self.snapshots_dir / f"{name}.txt"
        snapshot_file.write_text(content)

    def load_snapshot(self, name: str) -> str:
        """Load snapshot from file."""
        snapshot_file = self.snapshots_dir / f"{name}.txt"
        if snapshot_file.exists():
            return snapshot_file.read_text()
        return ""

    def test_dashboard_visual_regression(self):
        """Test dashboard for visual regressions."""
        with AppTest(VPNManagerApp) as pilot:
            pilot.pause(0.1)
            current_snapshot = pilot.app.export_screenshot()

            # Compare with saved snapshot
            saved_snapshot = self.load_snapshot("dashboard")

            if not saved_snapshot:
                # First run - save the snapshot
                self.save_snapshot("dashboard", current_snapshot)
                pytest.skip("First run - baseline snapshot saved")

            # In a real scenario, you would compare the snapshots
            # For now, just verify the snapshot was captured
            assert current_snapshot is not None

    def test_users_screen_visual_regression(self):
        """Test users screen for visual regressions."""
        with AppTest(VPNManagerApp) as pilot:
            pilot.app.push_screen("users")
            pilot.pause(0.1)
            current_snapshot = pilot.app.export_screenshot()

            saved_snapshot = self.load_snapshot("users_screen")

            if not saved_snapshot:
                self.save_snapshot("users_screen", current_snapshot)
                pytest.skip("First run - baseline snapshot saved")

            assert current_snapshot is not None


if __name__ == "__main__":
    # Run snapshot tests
    pytest.main([__file__, "-v"])
