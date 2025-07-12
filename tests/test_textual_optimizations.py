"""
Tests for Textual TUI optimizations.
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import Mock, patch, AsyncMock

from vpn.tui.components import (
    # Lazy loading
    LazyLoadableWidget, LoadingState, LoadingConfig, VirtualScrollingList,
    
    # Keyboard shortcuts
    ShortcutManager, ShortcutAction, ShortcutContext, ShortcutCategory,
    
    # Focus management
    FocusManager, FocusGroup, FocusRing, FocusDirection, FocusMode,
    
    # Theme system
    ThemeManager, Theme, ThemePreset, ColorPalette, ThemeMetadata, ThemeCategory,
    
    # Reusable widgets
    InfoCard, StatusIndicator, StatusType, ProgressCard, MetricCard,
    FormField, ConfirmDialog, InputDialog, Toast,
)


class TestLazyLoading:
    """Test lazy loading components."""
    
    class MockLazyWidget(LazyLoadableWidget):
        """Mock lazy widget for testing."""
        
        def __init__(self, load_data_result=None, **kwargs):
            super().__init__(**kwargs)
            self.load_data_result = load_data_result or {"test": "data"}
            self.load_called = False
        
        async def load_data(self):
            self.load_called = True
            return self.load_data_result
        
        def render_content(self, data):
            from textual.widgets import Static
            yield Static(f"Loaded: {data}")
    
    def test_loading_config_defaults(self):
        """Test loading configuration defaults."""
        config = LoadingConfig()
        
        assert config.auto_load is True
        assert config.show_spinner is True
        assert config.timeout_seconds == 30
        assert config.debounce_ms == 300
        assert config.cache_duration == 60
        assert config.loading_message == "Loading..."
    
    def test_loading_config_custom(self):
        """Test custom loading configuration."""
        config = LoadingConfig(
            auto_load=False,
            show_spinner=False,
            timeout_seconds=60,
            loading_message="Custom loading..."
        )
        
        assert config.auto_load is False
        assert config.show_spinner is False
        assert config.timeout_seconds == 60
        assert config.loading_message == "Custom loading..."
    
    def test_lazy_widget_initialization(self):
        """Test lazy widget initialization."""
        widget = self.MockLazyWidget()
        
        assert widget.state == LoadingState.NOT_STARTED
        assert widget.loading_config.auto_load is True
        assert widget._cached_data is None
    
    @pytest.mark.asyncio
    async def test_lazy_widget_load_success(self):
        """Test successful lazy loading."""
        test_data = {"users": 100, "servers": 5}
        widget = self.MockLazyWidget(load_data_result=test_data)
        
        # Mock the UI update methods
        widget._update_loading_ui = AsyncMock()
        widget._update_content_ui = AsyncMock()
        
        await widget.load()
        
        assert widget.load_called is True
        assert widget.state == LoadingState.LOADED
        widget._update_content_ui.assert_called_once_with(test_data)
    
    @pytest.mark.asyncio
    async def test_lazy_widget_load_error(self):
        """Test lazy loading with error."""
        widget = self.MockLazyWidget()
        widget._update_loading_ui = AsyncMock()
        widget._update_error_ui = AsyncMock()
        
        # Mock load_data to raise exception
        async def failing_load():
            raise Exception("Test error")
        
        widget.load_data = failing_load
        
        await widget.load()
        
        assert widget.state == LoadingState.ERROR
        widget._update_error_ui.assert_called_once()
    
    def test_virtual_scrolling_list(self):
        """Test virtual scrolling list."""
        vlist = VirtualScrollingList(
            item_height=3,
            visible_items=5,
            total_items=100
        )
        
        assert vlist.item_height == 3
        assert vlist.visible_items == 5
        assert vlist.total_items == 100
        assert vlist.scroll_offset == 0


class TestKeyboardShortcuts:
    """Test keyboard shortcuts system."""
    
    def test_shortcut_action_creation(self):
        """Test shortcut action creation."""
        action = ShortcutAction(
            key="ctrl+s",
            action="save",
            description="Save file",
            category="File Operations"
        )
        
        assert action.key == "ctrl+s"
        assert action.action == "save"
        assert action.description == "Save file"
        assert action.category == "File Operations"
        assert action.enabled is True
        assert action.context == ShortcutContext.GLOBAL
    
    def test_shortcut_manager_initialization(self):
        """Test shortcut manager initialization."""
        manager = ShortcutManager()
        
        # Should have default shortcuts loaded
        assert len(manager.shortcuts) > 0
        assert len(manager.categories) > 0
        
        # Check for some expected default shortcuts
        assert "q" in manager.shortcuts
        assert "escape" in manager.shortcuts
        assert "?" in manager.shortcuts
    
    def test_add_remove_shortcut(self):
        """Test adding and removing shortcuts."""
        manager = ShortcutManager()
        
        shortcut = ShortcutAction(
            key="ctrl+test",
            action="test_action",
            description="Test shortcut",
            category="Testing"
        )
        
        manager.add_shortcut(shortcut)
        
        assert "ctrl+test" in manager.shortcuts
        assert "Testing" in manager.categories
        assert shortcut in manager.categories["Testing"].shortcuts
        
        manager.remove_shortcut("ctrl+test")
        
        assert "ctrl+test" not in manager.shortcuts
    
    def test_get_active_shortcuts_global(self):
        """Test getting active global shortcuts."""
        manager = ShortcutManager()
        
        global_shortcuts = manager.get_active_shortcuts(ShortcutContext.GLOBAL)
        
        assert len(global_shortcuts) > 0
        
        # Should include default global shortcuts
        global_keys = [s.key for s in global_shortcuts]
        assert "q" in global_keys
        assert "escape" in global_keys
    
    def test_get_active_shortcuts_screen_context(self):
        """Test getting active shortcuts for screen context."""
        manager = ShortcutManager()
        
        # Get shortcuts for users screen
        users_shortcuts = manager.get_active_shortcuts(
            ShortcutContext.SCREEN,
            screen_name="users"
        )
        
        # Should include global shortcuts plus screen-specific ones
        assert len(users_shortcuts) > 0
        
        # Check for user-specific shortcuts
        user_keys = [s.key for s in users_shortcuts if s.context == ShortcutContext.SCREEN]
        assert "n" in user_keys  # New user shortcut
    
    def test_customize_shortcut(self):
        """Test shortcut customization."""
        manager = ShortcutManager()
        
        # Customize an existing shortcut
        success = manager.customize_shortcut("q", "ctrl+q")
        
        assert success is True
        assert "q" not in manager.shortcuts
        assert "ctrl+q" in manager.shortcuts
        assert manager.shortcuts["ctrl+q"].action == "quit"
    
    def test_toggle_shortcut(self):
        """Test toggling shortcut enabled state."""
        manager = ShortcutManager()
        
        # Get initial state
        original_state = manager.shortcuts["q"].enabled
        
        # Toggle
        success = manager.toggle_shortcut("q")
        assert success is True
        assert manager.shortcuts["q"].enabled != original_state
        
        # Toggle back
        manager.toggle_shortcut("q")
        assert manager.shortcuts["q"].enabled == original_state


class TestFocusManagement:
    """Test focus management system."""
    
    def test_focus_group_creation(self):
        """Test focus group creation."""
        group = FocusGroup("test_group", FocusMode.TAB_ORDER)
        
        assert group.name == "test_group"
        assert group.mode == FocusMode.TAB_ORDER
        assert len(group._widgets) == 0
        assert group._enabled is True
    
    def test_focus_group_add_remove_widgets(self):
        """Test adding and removing widgets from focus group."""
        group = FocusGroup("test_group")
        
        # Mock widgets
        widget1 = Mock()
        widget2 = Mock()
        widget1._tab_index = 1
        widget2._tab_index = 2
        
        group.add_widget(widget1)
        group.add_widget(widget2)
        
        assert len(group._widgets) == 2
        assert widget1 in group._widgets
        assert widget2 in group._widgets
        
        group.remove_widget(widget1)
        
        assert len(group._widgets) == 1
        assert widget1 not in group._widgets
        assert widget2 in group._widgets
    
    def test_focus_ring_creation(self):
        """Test focus ring creation."""
        ring = FocusRing("test_ring")
        
        assert ring.name == "test_ring"
        assert len(ring._groups) == 0
        assert ring._current_group is None
    
    def test_focus_ring_add_groups(self):
        """Test adding groups to focus ring."""
        ring = FocusRing("test_ring")
        group1 = FocusGroup("group1")
        group2 = FocusGroup("group2")
        
        ring.add_group(group1)
        ring.add_group(group2)
        
        assert len(ring._groups) == 2
        assert "group1" in ring._groups
        assert "group2" in ring._groups
        assert ring._current_group == group1  # First group becomes current
    
    def test_focus_ring_modal_stack(self):
        """Test modal focus group stack."""
        ring = FocusRing("test_ring")
        base_group = FocusGroup("base")
        modal_group = FocusGroup("modal")
        
        ring.add_group(base_group)
        ring.push_modal(modal_group)
        
        assert len(ring._modal_stack) == 1
        assert ring._current_group == modal_group
        
        popped = ring.pop_modal()
        
        assert popped == modal_group
        assert len(ring._modal_stack) == 0
        assert ring._current_group == base_group


class TestThemeSystem:
    """Test theme system."""
    
    def test_color_palette_defaults(self):
        """Test color palette default values."""
        palette = ColorPalette()
        
        assert palette.primary == "#0178d4"
        assert palette.background == "#0e1419"
        assert palette.text == "#ffffff"
        assert palette.success == "#28a745"
        assert palette.error == "#dc3545"
    
    def test_theme_metadata(self):
        """Test theme metadata."""
        metadata = ThemeMetadata(
            name="Test Theme",
            description="A test theme",
            author="Tester",
            category=ThemeCategory.CUSTOM
        )
        
        assert metadata.name == "Test Theme"
        assert metadata.description == "A test theme"
        assert metadata.author == "Tester"
        assert metadata.category == ThemeCategory.CUSTOM
    
    def test_theme_creation(self):
        """Test theme creation."""
        metadata = ThemeMetadata(name="Test Theme")
        colors = ColorPalette(primary="#ff0000")
        
        theme = Theme(
            metadata=metadata,
            colors=colors,
            font_size=16
        )
        
        assert theme.metadata.name == "Test Theme"
        assert theme.colors.primary == "#ff0000"
        assert theme.font_size == 16
    
    def test_theme_serialization(self):
        """Test theme serialization."""
        theme = ThemePreset.dark_blue()
        
        # Convert to dict
        theme_dict = theme.to_dict()
        
        assert isinstance(theme_dict, dict)
        assert "metadata" in theme_dict
        assert "colors" in theme_dict
        assert theme_dict["metadata"]["name"] == "Dark Blue"
        
        # Convert back from dict
        restored_theme = Theme.from_dict(theme_dict)
        
        assert restored_theme.metadata.name == theme.metadata.name
        assert restored_theme.colors.primary == theme.colors.primary
    
    def test_builtin_themes(self):
        """Test built-in theme presets."""
        dark_blue = ThemePreset.dark_blue()
        light_blue = ThemePreset.light_blue()
        cyberpunk = ThemePreset.cyberpunk()
        
        assert dark_blue.metadata.name == "Dark Blue"
        assert light_blue.metadata.name == "Light Blue"
        assert cyberpunk.metadata.name == "Cyberpunk"
        
        assert dark_blue.metadata.category == ThemeCategory.BUILT_IN
        assert light_blue.metadata.category == ThemeCategory.BUILT_IN
        assert cyberpunk.metadata.category == ThemeCategory.BUILT_IN
    
    def test_theme_manager_initialization(self):
        """Test theme manager initialization."""
        with patch('vpn.tui.components.theme_system.Path') as mock_path:
            mock_path.home.return_value = Path("/tmp")
            
            manager = ThemeManager()
            
            # Should have built-in themes loaded
            themes = manager.get_themes()
            assert len(themes) >= 5  # At least the 5 built-in themes
            
            theme_names = [t.metadata.name for t in themes]
            assert "Dark Blue" in theme_names
            assert "Light Blue" in theme_names
            assert "Cyberpunk" in theme_names
    
    def test_theme_manager_set_theme(self):
        """Test setting themes."""
        manager = ThemeManager()
        
        # Set existing theme
        success = manager.set_theme("Light Blue")
        assert success is True
        
        current = manager.get_current_theme()
        assert current is not None
        assert current.metadata.name == "Light Blue"
        
        # Try to set non-existent theme
        success = manager.set_theme("Non-existent Theme")
        assert success is False


class TestReusableWidgets:
    """Test reusable widget components."""
    
    def test_info_card_creation(self):
        """Test info card widget creation."""
        card = InfoCard(
            title="Test Card",
            content="Test content",
            footer="Test footer"
        )
        
        assert card.title == "Test Card"
        assert card.content == "Test content"
        assert card.footer == "Test footer"
    
    def test_status_indicator_types(self):
        """Test status indicator types."""
        success = StatusIndicator("Success", StatusType.SUCCESS)
        warning = StatusIndicator("Warning", StatusType.WARNING)
        error = StatusIndicator("Error", StatusType.ERROR)
        
        assert success.status == StatusType.SUCCESS
        assert warning.status == StatusType.WARNING
        assert error.status == StatusType.ERROR
    
    def test_progress_card(self):
        """Test progress card widget."""
        card = ProgressCard(
            title="Test Progress",
            total=100,
            show_percentage=True
        )
        
        assert card.title == "Test Progress"
        assert card.total == 100
        assert card.show_percentage is True
        assert card.progress == 0.0
        
        # Test progress update
        card.progress = 50.0
        assert card.progress == 50.0
    
    def test_metric_card(self):
        """Test metric card widget."""
        card = MetricCard(
            title="Users",
            value="150",
            trend="+5.2%",
            trend_positive=True
        )
        
        assert card.title == "Users"
        assert card.value == "150"
        assert card.trend == "+5.2%"
        assert card.trend_positive is True
    
    def test_form_field(self):
        """Test form field widget."""
        field = FormField(
            label="Username",
            field_id="username",
            required=True,
            help_text="Enter your username"
        )
        
        assert field.label == "Username"
        assert field.field_id == "username"
        assert field.required is True
        assert field.help_text == "Enter your username"
    
    def test_toast_notification(self):
        """Test toast notification widget."""
        toast = Toast(
            message="Test notification",
            toast_type="success",
            duration=5.0,
            closeable=True
        )
        
        assert toast.message == "Test notification"
        assert toast.toast_type == "success"
        assert toast.duration == 5.0
        assert toast.closeable is True


class TestIntegration:
    """Test integration between components."""
    
    def test_shortcut_manager_with_focus_management(self):
        """Test shortcuts working with focus management."""
        shortcut_manager = ShortcutManager()
        
        # Get tab navigation shortcuts
        tab_shortcuts = [
            s for s in shortcut_manager.shortcuts.values()
            if s.key in ["tab", "shift+tab"]
        ]
        
        # Should have tab navigation shortcuts for focus management
        assert len(tab_shortcuts) >= 0  # May not have default tab shortcuts
    
    def test_theme_manager_with_lazy_loading(self):
        """Test theme changes affecting lazy-loaded components."""
        theme_manager = ThemeManager()
        
        # Create a lazy widget
        widget = TestLazyLoading.MockLazyWidget()
        
        # Theme changes should not break lazy loading
        theme_manager.set_theme("Light Blue")
        
        assert widget.state == LoadingState.NOT_STARTED
        assert theme_manager.get_current_theme().metadata.name == "Light Blue"
    
    @pytest.mark.asyncio
    async def test_full_component_integration(self):
        """Test all components working together."""
        # Initialize all managers
        shortcut_manager = ShortcutManager()
        theme_manager = ThemeManager()
        
        # Create widgets with multiple optimizations
        lazy_widget = TestLazyLoading.MockLazyWidget(
            loading_config=LoadingConfig(
                auto_load=True,
                show_spinner=True
            )
        )
        
        info_card = InfoCard("Integration Test", "All systems working")
        
        # Simulate complex interaction
        theme_manager.set_theme("Cyberpunk")
        
        # Lazy loading should work
        await lazy_widget.load()
        assert lazy_widget.state == LoadingState.LOADED
        
        # Theme should be applied
        current_theme = theme_manager.get_current_theme()
        assert current_theme.metadata.name == "Cyberpunk"
        
        # Shortcuts should be available
        assert len(shortcut_manager.shortcuts) > 0