"""
Context menu widget for Textual TUI applications.
"""

from typing import Callable, List, Optional, Tuple

from rich.text import Text
from textual import on
from textual.app import ComposeResult
from textual.containers import Vertical
from textual.coordinate import Coordinate
from textual.css.query import NoMatches
from textual.message import Message
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import Button, Static

from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ContextMenuItem:
    """Represents a single context menu item."""
    
    def __init__(
        self,
        label: str,
        action: Optional[Callable] = None,
        shortcut: Optional[str] = None,
        enabled: bool = True,
        separator: bool = False,
        submenu: Optional[List["ContextMenuItem"]] = None
    ):
        self.label = label
        self.action = action
        self.shortcut = shortcut
        self.enabled = enabled
        self.separator = separator
        self.submenu = submenu or []
    
    def __str__(self) -> str:
        if self.separator:
            return "───────────"
        
        shortcut_text = f" {self.shortcut}" if self.shortcut else ""
        return f"{self.label}{shortcut_text}"


class ContextMenu(Widget):
    """Context menu widget that appears on right-click or keyboard shortcut."""
    
    DEFAULT_CSS = """
    ContextMenu {
        display: none;
        background: $surface;
        border: solid $primary;
        width: auto;
        height: auto;
        max-width: 30;
        max-height: 20;
        dock: float;
        layer: context_menu;
    }
    
    ContextMenu.visible {
        display: block;
    }
    
    ContextMenu > Vertical {
        padding: 1;
        height: auto;
        width: auto;
    }
    
    ContextMenu Button {
        width: 100%;
        height: 1;
        margin: 0;
        padding: 0 1;
        border: none;
        background: transparent;
        color: $text;
        text-align: left;
    }
    
    ContextMenu Button:hover {
        background: $primary;
        color: $text;
    }
    
    ContextMenu Button:disabled {
        color: $text-disabled;
        background: transparent;
    }
    
    ContextMenu .separator {
        height: 1;
        width: 100%;
        color: $text-muted;
        text-align: center;
    }
    """
    
    visible: reactive[bool] = reactive(False)
    
    class ItemSelected(Message):
        """Message sent when a context menu item is selected."""
        
        def __init__(self, item: ContextMenuItem) -> None:
            self.item = item
            super().__init__()
    
    class MenuClosed(Message):
        """Message sent when the context menu is closed."""
        pass
    
    def __init__(
        self,
        items: List[ContextMenuItem],
        position: Optional[Coordinate] = None,
        **kwargs
    ):
        super().__init__(**kwargs)
        self.items = items
        self.position = position or Coordinate(0, 0)
        self._item_buttons: List[Button] = []
    
    def compose(self) -> ComposeResult:
        """Compose the context menu."""
        with Vertical():
            for i, item in enumerate(self.items):
                if item.separator:
                    yield Static("───────────", classes="separator")
                else:
                    button = Button(
                        self._format_item_text(item),
                        id=f"item_{i}",
                        disabled=not item.enabled
                    )
                    button.context_item = item  # Store reference to item
                    self._item_buttons.append(button)
                    yield button
    
    def _format_item_text(self, item: ContextMenuItem) -> str:
        """Format the text for a menu item."""
        text = item.label
        if item.shortcut:
            # Right-align shortcut
            padding = max(0, 20 - len(text) - len(item.shortcut))
            text = f"{text}{' ' * padding}{item.shortcut}"
        return text
    
    def show_at(self, position: Coordinate) -> None:
        """Show the context menu at the specified position."""
        self.position = position
        
        # Update position styles
        self.styles.offset = (position.x, position.y)
        
        # Make visible
        self.visible = True
        self.add_class("visible")
        
        # Focus the first enabled item
        self._focus_first_item()
    
    def hide(self) -> None:
        """Hide the context menu."""
        self.visible = False
        self.remove_class("visible")
        self.post_message(self.MenuClosed())
    
    def _focus_first_item(self) -> None:
        """Focus the first enabled menu item."""
        for button in self._item_buttons:
            if not button.disabled:
                button.focus()
                break
    
    @on(Button.Pressed)
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press in context menu."""
        button = event.button
        
        # Get the associated context item
        if hasattr(button, 'context_item'):
            item = button.context_item
            
            # Hide menu first
            self.hide()
            
            # Execute action if available
            if item.action:
                try:
                    item.action()
                except Exception as e:
                    logger.error(f"Context menu action failed: {e}")
            
            # Send message
            self.post_message(self.ItemSelected(item))
    
    def on_key(self, event) -> None:
        """Handle keyboard events."""
        if event.key == "escape":
            self.hide()
            event.prevent_default()
        elif event.key == "up":
            self._navigate_up()
            event.prevent_default()
        elif event.key == "down":
            self._navigate_down()
            event.prevent_default()
        elif event.key == "enter":
            self._activate_focused_item()
            event.prevent_default()
    
    def _navigate_up(self) -> None:
        """Navigate to the previous menu item."""
        focused = self.app.focused
        if focused in self._item_buttons:
            current_index = self._item_buttons.index(focused)
            
            # Find previous enabled item
            for i in range(current_index - 1, -1, -1):
                if not self._item_buttons[i].disabled:
                    self._item_buttons[i].focus()
                    return
            
            # Wrap to last enabled item
            for i in range(len(self._item_buttons) - 1, current_index, -1):
                if not self._item_buttons[i].disabled:
                    self._item_buttons[i].focus()
                    return
    
    def _navigate_down(self) -> None:
        """Navigate to the next menu item."""
        focused = self.app.focused
        if focused in self._item_buttons:
            current_index = self._item_buttons.index(focused)
            
            # Find next enabled item
            for i in range(current_index + 1, len(self._item_buttons)):
                if not self._item_buttons[i].disabled:
                    self._item_buttons[i].focus()
                    return
            
            # Wrap to first enabled item
            for i in range(0, current_index):
                if not self._item_buttons[i].disabled:
                    self._item_buttons[i].focus()
                    return
    
    def _activate_focused_item(self) -> None:
        """Activate the currently focused menu item."""
        focused = self.app.focused
        if focused in self._item_buttons:
            # Simulate button press
            focused.action_press()


class ContextMenuMixin:
    """Mixin to add context menu support to widgets."""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._context_menu: Optional[ContextMenu] = None
        self._context_menu_items: List[ContextMenuItem] = []
    
    def set_context_menu_items(self, items: List[ContextMenuItem]) -> None:
        """Set the context menu items for this widget."""
        self._context_menu_items = items
    
    def show_context_menu(self, position: Optional[Coordinate] = None) -> None:
        """Show the context menu at the specified position."""
        if not self._context_menu_items:
            return
        
        # Close existing context menu
        self.hide_context_menu()
        
        # Calculate position
        if position is None:
            # Show at center of widget
            region = self.region
            position = Coordinate(region.x + region.width // 2, region.y + region.height // 2)
        
        # Create and show context menu
        self._context_menu = ContextMenu(self._context_menu_items, position)
        
        # Mount to the screen
        try:
            self.screen.mount(self._context_menu)
            self._context_menu.show_at(position)
        except Exception as e:
            logger.error(f"Failed to show context menu: {e}")
    
    def hide_context_menu(self) -> None:
        """Hide the context menu if it's visible."""
        if self._context_menu and self._context_menu.visible:
            self._context_menu.hide()
            
            # Remove from screen
            try:
                self._context_menu.remove()
            except Exception:
                pass
            
            self._context_menu = None
    
    def on_click(self, event) -> None:
        """Handle click events for context menu."""
        if hasattr(event, 'button') and event.button == 3:  # Right click
            self.show_context_menu(Coordinate(event.x, event.y))
            event.prevent_default()
        else:
            # Hide context menu on left click
            self.hide_context_menu()
        
        # Call parent handler if it exists
        if hasattr(super(), 'on_click'):
            super().on_click(event)
    
    def on_key(self, event) -> None:
        """Handle keyboard events for context menu."""
        if event.key == "f10" or (event.key == "f" and event.shift):
            # Show context menu with keyboard
            self.show_context_menu()
            event.prevent_default()
        elif event.key == "escape":
            # Hide context menu
            self.hide_context_menu()
        
        # Call parent handler if it exists
        if hasattr(super(), 'on_key'):
            super().on_key(event)
    
    @on(ContextMenu.ItemSelected)
    def on_context_menu_item_selected(self, event: ContextMenu.ItemSelected) -> None:
        """Handle context menu item selection."""
        # Override in subclasses to handle menu actions
        pass
    
    @on(ContextMenu.MenuClosed)
    def on_context_menu_closed(self, event: ContextMenu.MenuClosed) -> None:
        """Handle context menu closed."""
        self.hide_context_menu()


def create_user_context_menu(user_id: str) -> List[ContextMenuItem]:
    """Create context menu items for user management."""
    return [
        ContextMenuItem("View Details", shortcut="Enter"),
        ContextMenuItem("Edit User", shortcut="F2"),
        ContextMenuItem("", separator=True),
        ContextMenuItem("Generate QR Code", shortcut="Q"),
        ContextMenuItem("Show Connection", shortcut="C"),
        ContextMenuItem("Reset Traffic", shortcut="R"),
        ContextMenuItem("", separator=True),
        ContextMenuItem("Suspend User", shortcut="S"),
        ContextMenuItem("Delete User", shortcut="Del", enabled=True),
    ]


def create_server_context_menu(server_protocol: str = None) -> List[ContextMenuItem]:
    """Create context menu items for server management."""
    items = [
        ContextMenuItem("Start Server", shortcut="F5"),
        ContextMenuItem("Stop Server", shortcut="F6"),
        ContextMenuItem("Restart Server", shortcut="F7"),
        ContextMenuItem("", separator=True),
        ContextMenuItem("View Logs", shortcut="L"),
        ContextMenuItem("Edit Config", shortcut="F4"),
    ]
    
    # Add proxy-specific items
    if server_protocol in ["proxy", "unified_proxy"]:
        items.extend([
            ContextMenuItem("", separator=True),
            ContextMenuItem("Configure Authentication", shortcut="A"),
            ContextMenuItem("Add User Credentials", shortcut="U"),
            ContextMenuItem("View Active Connections", shortcut="C"),
        ])
    
    items.extend([
        ContextMenuItem("", separator=True),
        ContextMenuItem("Export Config", shortcut="E"),
        ContextMenuItem("Backup Data", shortcut="B"),
    ])
    
    return items


def create_log_context_menu() -> List[ContextMenuItem]:
    """Create context menu items for log viewer."""
    return [
        ContextMenuItem("Copy Line", shortcut="Ctrl+C"),
        ContextMenuItem("Copy All", shortcut="Ctrl+A"),
        ContextMenuItem("", separator=True),
        ContextMenuItem("Save to File", shortcut="Ctrl+S"),
        ContextMenuItem("", separator=True),
        ContextMenuItem("Clear Logs", shortcut="Ctrl+L"),
        ContextMenuItem("Refresh", shortcut="F5"),
        ContextMenuItem("", separator=True),
        ContextMenuItem("Filter Error", shortcut="E"),
        ContextMenuItem("Filter Warning", shortcut="W"),
        ContextMenuItem("Show All", shortcut="A"),
    ]