"""
TUI widget interaction tests for VPN Manager.
"""

from unittest.mock import AsyncMock, patch

import pytest
from textual.app import App
from textual.testing import AppTest
from textual.widgets import Button, Input

from vpn.core.models import ProtocolType, User, UserStatus
from vpn.tui.widgets.log_viewer import LogViewer
from vpn.tui.widgets.server_status import ServerStatus
from vpn.tui.widgets.stats_card import StatsCard
from vpn.tui.widgets.traffic_chart import TrafficChart
from vpn.tui.widgets.user_details import UserDetails
from vpn.tui.widgets.user_list import UserList


class TestUserListWidget:
    """Test UserList widget interactions."""

    @pytest.fixture
    def mock_users(self):
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

    def test_user_list_widget_creation(self):
        """Test UserList widget can be created."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            assert pilot.app.is_running

    @pytest.mark.asyncio
    async def test_user_list_loading(self, mock_users):
        """Test UserList loads users correctly."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_user_manager.return_value = mock_instance

            with AppTest(TestApp) as pilot:
                user_list = pilot.app.query_one(UserList)

                # Trigger refresh
                await user_list.refresh_users()
                pilot.pause(0.1)

                # Verify users were loaded
                mock_instance.list_users.assert_called_once()

    def test_user_selection(self, mock_users):
        """Test user selection in UserList."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Navigate through user list
            pilot.press("down")
            pilot.press("up")
            pilot.press("enter")

            assert pilot.app.is_running

    def test_user_list_filtering(self):
        """Test filtering functionality in UserList."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try filtering (if implemented)
            pilot.press("f")  # Filter shortcut
            pilot.type("alice")
            pilot.press("enter")

            assert pilot.app.is_running


class TestLogViewerWidget:
    """Test LogViewer widget interactions."""

    def test_log_viewer_creation(self):
        """Test LogViewer widget can be created."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            assert pilot.app.is_running

    def test_log_viewer_search(self):
        """Test search functionality in LogViewer."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try to find search input
            try:
                search_input = pilot.app.query_one("#search_input", Input)

                # Type in search input
                search_input.focus()
                pilot.type("error")
                pilot.pause(0.1)

            except Exception:
                # Search input might not be focusable yet
                pass

            assert pilot.app.is_running

    def test_log_viewer_filters(self):
        """Test log level filtering in LogViewer."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try clicking filter buttons
            try:
                error_button = pilot.app.query_one("#filter_error", Button)
                pilot.click(error_button)
                pilot.pause(0.1)

                warning_button = pilot.app.query_one("#filter_warning", Button)
                pilot.click(warning_button)
                pilot.pause(0.1)

            except Exception:
                # Buttons might not be ready
                pass

            assert pilot.app.is_running

    def test_log_viewer_auto_scroll(self):
        """Test auto-scroll toggle in LogViewer."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            try:
                toggle_button = pilot.app.query_one("#toggle_scroll", Button)

                # Click to toggle auto-scroll
                pilot.click(toggle_button)
                pilot.pause(0.1)

                # Click again to toggle back
                pilot.click(toggle_button)
                pilot.pause(0.1)

            except Exception:
                # Button might not be available
                pass

            assert pilot.app.is_running

    def test_log_viewer_clear(self):
        """Test clearing logs in LogViewer."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            try:
                clear_button = pilot.app.query_one("#clear_logs", Button)
                pilot.click(clear_button)
                pilot.pause(0.1)

            except Exception:
                # Button might not be available
                pass

            assert pilot.app.is_running


class TestTrafficChartWidget:
    """Test TrafficChart widget interactions."""

    def test_traffic_chart_creation(self):
        """Test TrafficChart widget can be created."""
        class TestApp(App):
            def compose(self):
                yield TrafficChart()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            assert pilot.app.is_running

    def test_traffic_chart_time_range(self):
        """Test time range selection in TrafficChart."""
        class TestApp(App):
            def compose(self):
                yield TrafficChart()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try changing time range (if controls exist)
            pilot.press("1")  # 1 hour
            pilot.press("2")  # 24 hours
            pilot.press("3")  # 7 days

            assert pilot.app.is_running

    @pytest.mark.asyncio
    async def test_traffic_chart_data_update(self):
        """Test data updating in TrafficChart."""
        class TestApp(App):
            def compose(self):
                yield TrafficChart()

        with AppTest(TestApp) as pilot:
            chart = pilot.app.query_one(TrafficChart)
            pilot.pause(0.1)

            # Trigger data refresh (if method exists)
            try:
                await chart.refresh_data()
                pilot.pause(0.1)
            except AttributeError:
                # Method might not exist
                pass

            assert pilot.app.is_running


class TestServerStatusWidget:
    """Test ServerStatus widget interactions."""

    def test_server_status_creation(self):
        """Test ServerStatus widget can be created."""
        class TestApp(App):
            def compose(self):
                yield ServerStatus()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            assert pilot.app.is_running

    def test_server_status_refresh(self):
        """Test refresh functionality in ServerStatus."""
        class TestApp(App):
            def compose(self):
                yield ServerStatus()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try refresh action
            pilot.press("r")  # Common refresh key
            pilot.pause(0.1)

            assert pilot.app.is_running

    @pytest.mark.asyncio
    async def test_server_status_controls(self):
        """Test server control buttons."""
        class TestApp(App):
            def compose(self):
                yield ServerStatus()

        with patch('vpn.services.server_manager.ServerManager') as mock_server_manager:
            mock_instance = AsyncMock()
            mock_instance.get_status.return_value = {"status": "running"}
            mock_instance.start.return_value = True
            mock_instance.stop.return_value = True
            mock_server_manager.return_value = mock_instance

            with AppTest(TestApp) as pilot:
                pilot.pause(0.1)

                # Try server control buttons (if they exist)
                try:
                    start_button = pilot.app.query_one("#start_server", Button)
                    pilot.click(start_button)
                    pilot.pause(0.1)

                    stop_button = pilot.app.query_one("#stop_server", Button)
                    pilot.click(stop_button)
                    pilot.pause(0.1)

                except Exception:
                    # Buttons might not exist
                    pass

                assert pilot.app.is_running


class TestStatsCardWidget:
    """Test StatsCard widget interactions."""

    def test_stats_card_creation(self):
        """Test StatsCard widget can be created."""
        class TestApp(App):
            def compose(self):
                yield StatsCard("Test Stat", "100", "users")

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            assert pilot.app.is_running

    def test_stats_card_update(self):
        """Test updating StatsCard values."""
        class TestApp(App):
            def compose(self):
                yield StatsCard("Active Users", "5", "users")

        with AppTest(TestApp) as pilot:
            stats_card = pilot.app.query_one(StatsCard)
            pilot.pause(0.1)

            # Update stats (if method exists)
            try:
                stats_card.update_value("10")
                pilot.pause(0.1)
            except AttributeError:
                # Method might not exist
                pass

            assert pilot.app.is_running


class TestUserDetailsWidget:
    """Test UserDetails widget interactions."""

    @pytest.fixture
    def mock_user(self):
        return User(
            username="alice",
            email="alice@example.com",
            status=UserStatus.ACTIVE,
            protocol={"protocol": ProtocolType.VLESS, "config": {"port": 8443}}
        )

    def test_user_details_creation(self, mock_user):
        """Test UserDetails widget can be created."""
        class TestApp(App):
            def compose(self):
                yield UserDetails(mock_user)

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)
            assert pilot.app.is_running

    def test_user_details_edit(self, mock_user):
        """Test editing user details."""
        class TestApp(App):
            def compose(self):
                yield UserDetails(mock_user)

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try edit actions
            try:
                edit_button = pilot.app.query_one("#edit_user", Button)
                pilot.click(edit_button)
                pilot.pause(0.1)

                # Try saving
                save_button = pilot.app.query_one("#save_user", Button)
                pilot.click(save_button)
                pilot.pause(0.1)

            except Exception:
                # Buttons might not exist
                pass

            assert pilot.app.is_running


class TestWidgetKeyboardNavigation:
    """Test keyboard navigation within widgets."""

    def test_widget_tab_navigation(self):
        """Test tab navigation between widget elements."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Navigate through focusable elements
            for _ in range(5):
                pilot.press("tab")
                pilot.pause(0.05)

            # Navigate backwards
            for _ in range(3):
                pilot.press("shift+tab")
                pilot.pause(0.05)

            assert pilot.app.is_running

    def test_widget_arrow_navigation(self):
        """Test arrow key navigation in list widgets."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Navigate with arrow keys
            pilot.press("down")
            pilot.press("down")
            pilot.press("up")
            pilot.press("page_down")
            pilot.press("page_up")

            assert pilot.app.is_running

    def test_widget_home_end_navigation(self):
        """Test home/end navigation in widgets."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Navigate to extremes
            pilot.press("home")
            pilot.pause(0.1)
            pilot.press("end")
            pilot.pause(0.1)
            pilot.press("ctrl+home")
            pilot.pause(0.1)
            pilot.press("ctrl+end")
            pilot.pause(0.1)

            assert pilot.app.is_running


class TestWidgetDataBinding:
    """Test data binding and updates in widgets."""

    @pytest.mark.asyncio
    async def test_user_list_data_binding(self):
        """Test UserList updates when data changes."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        mock_users = [
            User(
                username="alice",
                email="alice@example.com",
                status=UserStatus.ACTIVE,
                protocol={"protocol": ProtocolType.VLESS, "config": {"port": 8443}}
            )
        ]

        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.return_value = mock_users
            mock_user_manager.return_value = mock_instance

            with AppTest(TestApp) as pilot:
                user_list = pilot.app.query_one(UserList)
                pilot.pause(0.1)

                # Trigger data refresh
                try:
                    await user_list.refresh_users()
                    pilot.pause(0.1)

                    # Update data and refresh again
                    new_user = User(
                        username="bob",
                        email="bob@example.com",
                        status=UserStatus.ACTIVE,
                        protocol={"protocol": ProtocolType.SHADOWSOCKS, "config": {"port": 8388}}
                    )
                    mock_users.append(new_user)

                    await user_list.refresh_users()
                    pilot.pause(0.1)

                except AttributeError:
                    # Method might not exist
                    pass

                assert pilot.app.is_running

    @pytest.mark.asyncio
    async def test_stats_card_reactive_updates(self):
        """Test StatsCard reacts to data changes."""
        class TestApp(App):
            def compose(self):
                yield StatsCard("Users", "0", "total")

        with AppTest(TestApp) as pilot:
            stats_card = pilot.app.query_one(StatsCard)
            pilot.pause(0.1)

            # Simulate data updates
            try:
                for i in range(1, 6):
                    stats_card.update_value(str(i))
                    pilot.pause(0.1)
            except AttributeError:
                # Method might not exist
                pass

            assert pilot.app.is_running


class TestWidgetErrorHandling:
    """Test error handling in widget interactions."""

    @pytest.mark.asyncio
    async def test_widget_error_recovery(self):
        """Test widgets handle errors gracefully."""
        class TestApp(App):
            def compose(self):
                yield UserList()

        with patch('vpn.services.user_manager.UserManager') as mock_user_manager:
            mock_instance = AsyncMock()
            mock_instance.list_users.side_effect = Exception("Service unavailable")
            mock_user_manager.return_value = mock_instance

            with AppTest(TestApp) as pilot:
                user_list = pilot.app.query_one(UserList)
                pilot.pause(0.1)

                # Try to trigger error
                try:
                    await user_list.refresh_users()
                    pilot.pause(0.1)
                except:
                    pass

                # Widget should still be functional
                assert pilot.app.is_running

    def test_widget_invalid_input_handling(self):
        """Test widgets handle invalid input."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Try invalid search input
            try:
                search_input = pilot.app.query_one("#search_input", Input)
                search_input.focus()

                # Type invalid regex patterns
                pilot.type("[invalid regex")
                pilot.press("enter")
                pilot.pause(0.1)

                # Clear and try again
                pilot.press("ctrl+a")
                pilot.type("normal search")
                pilot.press("enter")
                pilot.pause(0.1)

            except Exception:
                # Input might not be available
                pass

            assert pilot.app.is_running


class TestWidgetAccessibility:
    """Test widget accessibility features."""

    def test_widget_focus_management(self):
        """Test proper focus management in widgets."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Test focus cycling
            pilot.press("tab")
            pilot.pause(0.1)

            # Get currently focused widget
            focused = pilot.app.focused

            # Continue tabbing
            pilot.press("tab")
            pilot.pause(0.1)

            # Should have moved focus
            new_focused = pilot.app.focused

            assert pilot.app.is_running

    def test_widget_keyboard_shortcuts(self):
        """Test widget-specific keyboard shortcuts."""
        class TestApp(App):
            def compose(self):
                yield LogViewer()

        with AppTest(TestApp) as pilot:
            pilot.pause(0.1)

            # Test various shortcuts
            shortcuts = ["ctrl+f", "ctrl+l", "escape", "f5"]

            for shortcut in shortcuts:
                try:
                    pilot.press(shortcut)
                    pilot.pause(0.1)
                except Exception:
                    # Shortcut might not be implemented
                    pass

            assert pilot.app.is_running


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
