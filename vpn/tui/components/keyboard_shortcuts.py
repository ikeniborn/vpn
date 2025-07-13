"""Advanced keyboard shortcuts system for Textual 0.47+ TUI.

This module provides a comprehensive keyboard shortcut system with:
- Dynamic binding management
- Context-aware shortcuts
- Shortcut discovery and help
- Customizable key mappings
"""

import json
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal
from textual.screen import ModalScreen
from textual.widgets import Button, Container, DataTable, Static


class ShortcutContext(Enum):
    """Context in which shortcuts are active."""
    GLOBAL = "global"  # Active everywhere
    SCREEN = "screen"  # Active on specific screen
    WIDGET = "widget"  # Active on specific widget
    MODAL = "modal"    # Active in modal dialogs


@dataclass
class ShortcutAction:
    """Represents a keyboard shortcut action."""
    key: str
    action: str
    description: str
    context: ShortcutContext = ShortcutContext.GLOBAL
    screen_name: str | None = None
    widget_class: str | None = None
    enabled: bool = True
    priority: int = 0
    show_in_footer: bool = True
    category: str = "General"


@dataclass
class ShortcutCategory:
    """Represents a category of shortcuts."""
    name: str
    description: str
    shortcuts: list[ShortcutAction] = field(default_factory=list)
    enabled: bool = True


class ShortcutManager:
    """Manages keyboard shortcuts across the application."""

    def __init__(self, config_file: Path | None = None):
        """Initialize shortcut manager."""
        self.config_file = config_file
        self.shortcuts: dict[str, ShortcutAction] = {}
        self.categories: dict[str, ShortcutCategory] = {}
        self.context_stack: list[ShortcutContext] = [ShortcutContext.GLOBAL]
        self._custom_bindings: dict[str, Binding] = {}

        # Load default shortcuts
        self._load_default_shortcuts()

        # Load custom shortcuts if config exists
        if config_file and config_file.exists():
            self.load_shortcuts(config_file)

    def _load_default_shortcuts(self) -> None:
        """Load default keyboard shortcuts."""
        default_shortcuts = [
            # Navigation shortcuts
            ShortcutAction("ctrl+d", "push_screen('dashboard')", "Dashboard",
                         category="Navigation", priority=100),
            ShortcutAction("ctrl+u", "push_screen('users')", "Users",
                         category="Navigation", priority=100),
            ShortcutAction("ctrl+s", "push_screen('servers')", "Servers",
                         category="Navigation", priority=100),
            ShortcutAction("ctrl+m", "push_screen('monitoring')", "Monitoring",
                         category="Navigation", priority=100),
            ShortcutAction("ctrl+shift+s", "push_screen('settings')", "Settings",
                         category="Navigation", priority=90),

            # General shortcuts
            ShortcutAction("q", "quit", "Quit Application",
                         category="General", priority=100),
            ShortcutAction("ctrl+c", "quit", "Force Quit",
                         category="General", show_in_footer=False),
            ShortcutAction("escape", "pop_screen", "Back/Cancel",
                         category="General", priority=95),
            ShortcutAction("?", "show_help", "Show Help",
                         category="General", priority=90),
            ShortcutAction("f1", "show_shortcuts", "Show Shortcuts",
                         category="General", priority=90),

            # Theme and appearance
            ShortcutAction("ctrl+t", "toggle_theme", "Toggle Theme",
                         category="Appearance", priority=80),
            ShortcutAction("ctrl+plus", "increase_font_size", "Increase Font",
                         category="Appearance", priority=70),
            ShortcutAction("ctrl+minus", "decrease_font_size", "Decrease Font",
                         category="Appearance", priority=70),

            # User management shortcuts (context: users screen)
            ShortcutAction("n", "new_user", "New User",
                         context=ShortcutContext.SCREEN, screen_name="users",
                         category="User Management", priority=90),
            ShortcutAction("delete", "delete_user", "Delete User",
                         context=ShortcutContext.SCREEN, screen_name="users",
                         category="User Management", priority=85),
            ShortcutAction("e", "edit_user", "Edit User",
                         context=ShortcutContext.SCREEN, screen_name="users",
                         category="User Management", priority=85),
            ShortcutAction("r", "refresh_users", "Refresh List",
                         context=ShortcutContext.SCREEN, screen_name="users",
                         category="User Management", priority=80),

            # Server management shortcuts (context: servers screen)
            ShortcutAction("n", "new_server", "New Server",
                         context=ShortcutContext.SCREEN, screen_name="servers",
                         category="Server Management", priority=90),
            ShortcutAction("space", "toggle_server", "Start/Stop Server",
                         context=ShortcutContext.SCREEN, screen_name="servers",
                         category="Server Management", priority=95),
            ShortcutAction("l", "view_logs", "View Logs",
                         context=ShortcutContext.SCREEN, screen_name="servers",
                         category="Server Management", priority=85),
            ShortcutAction("r", "refresh_servers", "Refresh List",
                         context=ShortcutContext.SCREEN, screen_name="servers",
                         category="Server Management", priority=80),

            # Quick actions
            ShortcutAction("ctrl+r", "refresh_current", "Refresh Current View",
                         category="Quick Actions", priority=85),
            ShortcutAction("ctrl+f", "search", "Search/Filter",
                         category="Quick Actions", priority=85),
            ShortcutAction("ctrl+e", "export", "Export Data",
                         category="Quick Actions", priority=70),

            # Development shortcuts (only in debug mode)
            ShortcutAction("ctrl+shift+d", "toggle_debug", "Toggle Debug Mode",
                         category="Development", priority=50, show_in_footer=False),
            ShortcutAction("ctrl+shift+l", "show_logs", "Show Logs",
                         category="Development", priority=50, show_in_footer=False),
        ]

        for shortcut in default_shortcuts:
            self.add_shortcut(shortcut)

    def add_shortcut(self, shortcut: ShortcutAction) -> None:
        """Add a shortcut to the manager."""
        self.shortcuts[shortcut.key] = shortcut

        # Add to category
        if shortcut.category not in self.categories:
            self.categories[shortcut.category] = ShortcutCategory(
                name=shortcut.category,
                description=f"{shortcut.category} shortcuts"
            )
        self.categories[shortcut.category].shortcuts.append(shortcut)

    def remove_shortcut(self, key: str) -> None:
        """Remove a shortcut by key."""
        if key in self.shortcuts:
            shortcut = self.shortcuts[key]
            del self.shortcuts[key]

            # Remove from category
            if shortcut.category in self.categories:
                self.categories[shortcut.category].shortcuts = [
                    s for s in self.categories[shortcut.category].shortcuts
                    if s.key != key
                ]

    def get_active_shortcuts(
        self,
        context: ShortcutContext = ShortcutContext.GLOBAL,
        screen_name: str | None = None,
        widget_class: str | None = None
    ) -> list[ShortcutAction]:
        """Get shortcuts active in the given context."""
        active_shortcuts = []

        for shortcut in self.shortcuts.values():
            if not shortcut.enabled:
                continue

            # Check context
            if shortcut.context == ShortcutContext.GLOBAL:
                active_shortcuts.append(shortcut)
            elif shortcut.context == context:
                if (context == ShortcutContext.SCREEN and shortcut.screen_name == screen_name) or (context == ShortcutContext.WIDGET and shortcut.widget_class == widget_class) or context == ShortcutContext.MODAL:
                    active_shortcuts.append(shortcut)

        # Sort by priority (higher first)
        return sorted(active_shortcuts, key=lambda x: x.priority, reverse=True)

    def get_bindings_for_context(
        self,
        context: ShortcutContext = ShortcutContext.GLOBAL,
        screen_name: str | None = None,
        widget_class: str | None = None
    ) -> list[Binding]:
        """Get Textual bindings for the given context."""
        active_shortcuts = self.get_active_shortcuts(context, screen_name, widget_class)
        bindings = []

        for shortcut in active_shortcuts:
            binding = Binding(
                key=shortcut.key,
                action=shortcut.action,
                description=shortcut.description,
                show=shortcut.show_in_footer,
                priority=shortcut.priority > 50
            )
            bindings.append(binding)

        return bindings

    def customize_shortcut(self, key: str, new_key: str) -> bool:
        """Customize a shortcut key."""
        if key not in self.shortcuts:
            return False

        shortcut = self.shortcuts[key]

        # Remove old key
        del self.shortcuts[key]

        # Update key
        shortcut.key = new_key

        # Add with new key
        self.shortcuts[new_key] = shortcut

        return True

    def toggle_shortcut(self, key: str) -> bool:
        """Toggle a shortcut on/off."""
        if key not in self.shortcuts:
            return False

        self.shortcuts[key].enabled = not self.shortcuts[key].enabled
        return True

    def save_shortcuts(self, config_file: Path | None = None) -> None:
        """Save shortcuts to configuration file."""
        file_path = config_file or self.config_file
        if not file_path:
            return

        config_data = {
            "shortcuts": [
                {
                    "key": shortcut.key,
                    "action": shortcut.action,
                    "description": shortcut.description,
                    "context": shortcut.context.value,
                    "screen_name": shortcut.screen_name,
                    "widget_class": shortcut.widget_class,
                    "enabled": shortcut.enabled,
                    "priority": shortcut.priority,
                    "show_in_footer": shortcut.show_in_footer,
                    "category": shortcut.category,
                }
                for shortcut in self.shortcuts.values()
            ]
        }

        with open(file_path, 'w') as f:
            json.dump(config_data, f, indent=2)

    def load_shortcuts(self, config_file: Path) -> None:
        """Load shortcuts from configuration file."""
        try:
            with open(config_file) as f:
                config_data = json.load(f)

            for shortcut_data in config_data.get("shortcuts", []):
                shortcut = ShortcutAction(
                    key=shortcut_data["key"],
                    action=shortcut_data["action"],
                    description=shortcut_data["description"],
                    context=ShortcutContext(shortcut_data["context"]),
                    screen_name=shortcut_data.get("screen_name"),
                    widget_class=shortcut_data.get("widget_class"),
                    enabled=shortcut_data.get("enabled", True),
                    priority=shortcut_data.get("priority", 0),
                    show_in_footer=shortcut_data.get("show_in_footer", True),
                    category=shortcut_data.get("category", "General"),
                )
                self.shortcuts[shortcut.key] = shortcut

        except (FileNotFoundError, json.JSONDecodeError):
            # Log error but continue with defaults
            pass


class ShortcutHelpScreen(ModalScreen):
    """Screen showing available keyboard shortcuts."""

    DEFAULT_CSS = """
    ShortcutHelpScreen {
        align: center middle;
    }
    
    .shortcut-help-container {
        width: 80%;
        height: 80%;
        background: $surface;
        border: solid $primary;
    }
    
    .shortcut-category {
        margin: 1;
        padding: 1;
        border: solid $primary-lighten-2;
    }
    
    .category-title {
        text-style: bold;
        color: $primary;
        margin-bottom: 1;
    }
    
    .shortcut-item {
        margin: 0 1;
        height: 1;
    }
    
    .shortcut-key {
        width: 20;
        text-style: bold;
        color: $accent;
    }
    
    .shortcut-desc {
        color: $text;
    }
    
    .help-footer {
        margin-top: 1;
        text-align: center;
    }
    """

    def __init__(self, shortcut_manager: ShortcutManager, context: str = ""):
        """Initialize help screen."""
        super().__init__()
        self.shortcut_manager = shortcut_manager
        self.context = context

    def compose(self) -> ComposeResult:
        """Compose the help screen."""
        with Container(classes="shortcut-help-container"):
            yield Static(f"Keyboard Shortcuts{' - ' + self.context if self.context else ''}",
                        classes="category-title")

            # Group shortcuts by category
            for category_name, category in self.shortcut_manager.categories.items():
                if not category.shortcuts:
                    continue

                with Container(classes="shortcut-category"):
                    yield Static(category.name, classes="category-title")

                    for shortcut in sorted(category.shortcuts, key=lambda x: x.priority, reverse=True):
                        if shortcut.enabled:
                            with Horizontal(classes="shortcut-item"):
                                yield Static(shortcut.key, classes="shortcut-key")
                                yield Static(shortcut.description, classes="shortcut-desc")

            with Container(classes="help-footer"):
                yield Static("Press Escape to close", classes="help-text")
                yield Button("Close", id="close-help")

    @on(Button.Pressed, "#close-help")
    def close_help(self) -> None:
        """Close the help screen."""
        self.dismiss()

    def on_key(self, event) -> None:
        """Handle key presses."""
        if event.key == "escape":
            self.dismiss()


class ShortcutCustomizationScreen(ModalScreen):
    """Screen for customizing keyboard shortcuts."""

    DEFAULT_CSS = """
    ShortcutCustomizationScreen {
        align: center middle;
    }
    
    .customization-container {
        width: 90%;
        height: 90%;
        background: $surface;
        border: solid $primary;
    }
    
    .customization-header {
        margin: 1;
        text-align: center;
    }
    
    .shortcut-table {
        height: 70%;
        margin: 1;
    }
    
    .customization-footer {
        margin: 1;
        text-align: center;
    }
    
    .action-buttons {
        margin: 1;
    }
    """

    def __init__(self, shortcut_manager: ShortcutManager):
        """Initialize customization screen."""
        super().__init__()
        self.shortcut_manager = shortcut_manager

    def compose(self) -> ComposeResult:
        """Compose the customization screen."""
        with Container(classes="customization-container"):
            with Container(classes="customization-header"):
                yield Static("Customize Keyboard Shortcuts", classes="title")
                yield Static("Click on a shortcut to edit, check/uncheck to enable/disable",
                           classes="subtitle")

            # Shortcuts table
            yield DataTable(id="shortcuts-table", classes="shortcut-table")

            # Action buttons
            with Horizontal(classes="action-buttons"):
                yield Button("Save", id="save-shortcuts", variant="primary")
                yield Button("Reset", id="reset-shortcuts", variant="warning")
                yield Button("Cancel", id="cancel-customize")

    def on_mount(self) -> None:
        """Setup the shortcuts table."""
        table = self.query_one("#shortcuts-table", DataTable)
        table.add_columns("Enabled", "Key", "Action", "Description", "Category", "Context")

        # Populate table
        for shortcut in self.shortcut_manager.shortcuts.values():
            table.add_row(
                "✓" if shortcut.enabled else "✗",
                shortcut.key,
                shortcut.action,
                shortcut.description,
                shortcut.category,
                shortcut.context.value,
                key=shortcut.key
            )

    @on(Button.Pressed, "#save-shortcuts")
    def save_shortcuts(self) -> None:
        """Save shortcut customizations."""
        self.shortcut_manager.save_shortcuts()
        self.app.notify("Shortcuts saved successfully!", severity="information")
        self.dismiss()

    @on(Button.Pressed, "#reset-shortcuts")
    def reset_shortcuts(self) -> None:
        """Reset shortcuts to defaults."""
        self.shortcut_manager._load_default_shortcuts()
        self.app.notify("Shortcuts reset to defaults", severity="warning")
        # Refresh table
        self.on_mount()

    @on(Button.Pressed, "#cancel-customize")
    def cancel_customize(self) -> None:
        """Cancel customization."""
        self.dismiss()

    @on(DataTable.RowSelected)
    def row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection for editing."""
        # Get the shortcut key from the row
        key = event.row_key.value
        if key in self.shortcut_manager.shortcuts:
            # Toggle enabled state for now (could open edit dialog)
            self.shortcut_manager.toggle_shortcut(key)

            # Update table row
            table = self.query_one("#shortcuts-table", DataTable)
            shortcut = self.shortcut_manager.shortcuts[key]
            table.update_cell(event.row_key, "Enabled", "✓" if shortcut.enabled else "✗")


class ShortcutMixin:
    """Mixin for adding shortcut support to Textual widgets."""

    def __init__(self, *args, shortcut_manager: ShortcutManager | None = None, **kwargs):
        """Initialize with shortcut support."""
        super().__init__(*args, **kwargs)
        self.shortcut_manager = shortcut_manager or get_global_shortcut_manager()

    def get_context_bindings(self) -> list[Binding]:
        """Get bindings for this widget's context."""
        context = ShortcutContext.WIDGET
        widget_class = self.__class__.__name__
        return self.shortcut_manager.get_bindings_for_context(
            context=context,
            widget_class=widget_class
        )

    def action_show_shortcuts(self) -> None:
        """Show shortcuts help for this context."""
        if hasattr(self, 'app'):
            self.app.push_screen(ShortcutHelpScreen(
                self.shortcut_manager,
                context=self.__class__.__name__
            ))


# Global shortcut manager instance
_global_shortcut_manager: ShortcutManager | None = None


def get_global_shortcut_manager() -> ShortcutManager:
    """Get the global shortcut manager instance."""
    global _global_shortcut_manager
    if _global_shortcut_manager is None:
        _global_shortcut_manager = ShortcutManager()
    return _global_shortcut_manager


def initialize_shortcuts(config_file: Path | None = None) -> ShortcutManager:
    """Initialize the global shortcut manager."""
    global _global_shortcut_manager
    _global_shortcut_manager = ShortcutManager(config_file)
    return _global_shortcut_manager
