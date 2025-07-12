"""
Advanced focus management system for Textual TUI.

This module provides comprehensive focus management capabilities including:
- Focus rings and groups
- Tab navigation
- Modal focus handling
- Focus restoration
- Accessibility features
"""

from typing import Dict, List, Optional, Callable, Any, Set, Union
from dataclasses import dataclass, field
from enum import Enum
import weakref

from textual import on
from textual.app import App
from textual.binding import Binding
from textual.dom import DOMNode
from textual.events import Focus, Blur, Key
from textual.message import Message
from textual.screen import Screen
from textual.widget import Widget
from textual.geometry import Region


class FocusDirection(Enum):
    """Direction of focus movement."""
    NEXT = "next"
    PREVIOUS = "previous"
    UP = "up"
    DOWN = "down"
    LEFT = "left"
    RIGHT = "right"
    FIRST = "first"
    LAST = "last"


class FocusMode(Enum):
    """Focus traversal modes."""
    TAB_ORDER = "tab_order"  # Standard tab order
    SPATIAL = "spatial"      # Based on widget positions
    CUSTOM = "custom"        # Custom order defined by developer


@dataclass
class FocusConfig:
    """Configuration for focus behavior."""
    
    # Navigation settings
    wrap_around: bool = True          # Wrap to first/last when reaching end
    skip_disabled: bool = True        # Skip disabled widgets
    modal_focus_trap: bool = True     # Trap focus in modals
    
    # Spatial navigation
    spatial_threshold: int = 10       # Pixel threshold for spatial navigation
    prefer_tab_order: bool = True     # Prefer tab order over spatial when ambiguous
    
    # Visual feedback
    show_focus_ring: bool = True      # Show visual focus indicators
    focus_ring_style: str = "solid"   # Focus ring style
    
    # Accessibility
    announce_focus: bool = True       # Announce focus changes for screen readers
    focus_restore: bool = True        # Restore focus when returning to screens


class FocusableWidget:
    """Mixin for widgets that can receive focus."""
    
    def __init__(self, *args, **kwargs):
        """Initialize focusable widget."""
        super().__init__(*args, **kwargs)
        self._focus_group: Optional['FocusGroup'] = None
        self._focus_ring: Optional['FocusRing'] = None
        self._tab_index: Optional[int] = None
        self._focus_neighbors: Dict[FocusDirection, Optional[Widget]] = {}
        self._last_focused_child: Optional[Widget] = None
    
    @property
    def focus_group(self) -> Optional['FocusGroup']:
        """Get the focus group this widget belongs to."""
        return self._focus_group
    
    @focus_group.setter
    def focus_group(self, group: Optional['FocusGroup']) -> None:
        """Set the focus group for this widget."""
        if self._focus_group:
            self._focus_group.remove_widget(self)
        
        self._focus_group = group
        
        if group:
            group.add_widget(self)
    
    @property
    def tab_index(self) -> Optional[int]:
        """Get the tab index for this widget."""
        return self._tab_index
    
    @tab_index.setter
    def tab_index(self, index: Optional[int]) -> None:
        """Set the tab index for this widget."""
        self._tab_index = index
        if self._focus_group:
            self._focus_group._rebuild_tab_order()
    
    def set_focus_neighbor(self, direction: FocusDirection, widget: Optional[Widget]) -> None:
        """Set a focus neighbor in a specific direction."""
        self._focus_neighbors[direction] = widget
    
    def get_focus_neighbor(self, direction: FocusDirection) -> Optional[Widget]:
        """Get the focus neighbor in a specific direction."""
        return self._focus_neighbors.get(direction)
    
    def can_focus(self) -> bool:
        """Check if this widget can currently receive focus."""
        return (
            hasattr(self, 'can_focus') and self.can_focus and
            hasattr(self, 'disabled') and not self.disabled and
            hasattr(self, 'display') and self.display
        )
    
    def on_focus(self, event: Focus) -> None:
        """Handle focus events."""
        super().on_focus(event)
        
        # Update focus ring
        if self._focus_ring:
            self._focus_ring.set_focused_widget(self)
        
        # Notify focus group
        if self._focus_group:
            self._focus_group._on_widget_focused(self)
    
    def on_blur(self, event: Blur) -> None:
        """Handle blur events."""
        super().on_blur(event)
        
        # Update last focused child for containers
        if hasattr(self, 'parent') and self.parent:
            if hasattr(self.parent, '_last_focused_child'):
                self.parent._last_focused_child = self


class FocusGroup:
    """Manages focus for a group of widgets."""
    
    def __init__(
        self,
        name: str,
        mode: FocusMode = FocusMode.TAB_ORDER,
        config: Optional[FocusConfig] = None
    ):
        """Initialize focus group."""
        self.name = name
        self.mode = mode
        self.config = config or FocusConfig()
        self._widgets: List[Widget] = []
        self._tab_order: List[Widget] = []
        self._current_focus: Optional[Widget] = None
        self._focus_history: List[Widget] = []
        self._enabled = True
    
    def add_widget(self, widget: Widget) -> None:
        """Add a widget to the focus group."""
        if widget not in self._widgets:
            self._widgets.append(widget)
            self._rebuild_tab_order()
    
    def remove_widget(self, widget: Widget) -> None:
        """Remove a widget from the focus group."""
        if widget in self._widgets:
            self._widgets.remove(widget)
            if widget in self._tab_order:
                self._tab_order.remove(widget)
            if self._current_focus == widget:
                self._current_focus = None
            if widget in self._focus_history:
                self._focus_history.remove(widget)
    
    def _rebuild_tab_order(self) -> None:
        """Rebuild the tab order based on current mode."""
        if self.mode == FocusMode.TAB_ORDER:
            # Sort by tab index, then by order added
            widgets_with_index = [(w, getattr(w, '_tab_index', None)) for w in self._widgets]
            widgets_with_index.sort(key=lambda x: (x[1] if x[1] is not None else 999, self._widgets.index(x[0])))
            self._tab_order = [w for w, _ in widgets_with_index]
        
        elif self.mode == FocusMode.SPATIAL:
            # Sort by position (top-to-bottom, left-to-right)
            self._tab_order = sorted(
                self._widgets,
                key=lambda w: (
                    getattr(w, 'region', Region(0, 0, 0, 0)).y,
                    getattr(w, 'region', Region(0, 0, 0, 0)).x
                )
            )
        
        else:  # CUSTOM mode
            # Use explicit order if set, otherwise maintain current order
            self._tab_order = [w for w in self._tab_order if w in self._widgets]
            for widget in self._widgets:
                if widget not in self._tab_order:
                    self._tab_order.append(widget)
    
    def focus_next(self, current: Optional[Widget] = None) -> Optional[Widget]:
        """Focus the next widget in the group."""
        return self._move_focus(FocusDirection.NEXT, current)
    
    def focus_previous(self, current: Optional[Widget] = None) -> Optional[Widget]:
        """Focus the previous widget in the group."""
        return self._move_focus(FocusDirection.PREVIOUS, current)
    
    def focus_first(self) -> Optional[Widget]:
        """Focus the first widget in the group."""
        return self._move_focus(FocusDirection.FIRST)
    
    def focus_last(self) -> Optional[Widget]:
        """Focus the last widget in the group."""
        return self._move_focus(FocusDirection.LAST)
    
    def _move_focus(self, direction: FocusDirection, current: Optional[Widget] = None) -> Optional[Widget]:
        """Move focus in the specified direction."""
        if not self._enabled or not self._tab_order:
            return None
        
        current = current or self._current_focus
        focusable_widgets = [w for w in self._tab_order if self._can_widget_focus(w)]
        
        if not focusable_widgets:
            return None
        
        if direction == FocusDirection.FIRST:
            target = focusable_widgets[0]
        elif direction == FocusDirection.LAST:
            target = focusable_widgets[-1]
        elif current is None:
            target = focusable_widgets[0]
        else:
            try:
                current_index = focusable_widgets.index(current)
            except ValueError:
                # Current widget not in focusable list, start from beginning
                target = focusable_widgets[0]
            else:
                if direction == FocusDirection.NEXT:
                    next_index = current_index + 1
                    if next_index >= len(focusable_widgets):
                        target = focusable_widgets[0] if self.config.wrap_around else None
                    else:
                        target = focusable_widgets[next_index]
                
                elif direction == FocusDirection.PREVIOUS:
                    prev_index = current_index - 1
                    if prev_index < 0:
                        target = focusable_widgets[-1] if self.config.wrap_around else None
                    else:
                        target = focusable_widgets[prev_index]
                
                else:
                    # Spatial navigation
                    target = self._find_spatial_neighbor(current, direction)
        
        if target and self._can_widget_focus(target):
            target.focus()
            return target
        
        return None
    
    def _find_spatial_neighbor(self, current: Widget, direction: FocusDirection) -> Optional[Widget]:
        """Find the nearest widget in a spatial direction."""
        if not hasattr(current, 'region'):
            return None
        
        current_region = current.region
        candidates = []
        
        for widget in self._tab_order:
            if widget == current or not self._can_widget_focus(widget):
                continue
            
            if not hasattr(widget, 'region'):
                continue
            
            widget_region = widget.region
            
            # Check if widget is in the correct direction
            if direction == FocusDirection.UP and widget_region.y >= current_region.y:
                continue
            elif direction == FocusDirection.DOWN and widget_region.y <= current_region.y:
                continue
            elif direction == FocusDirection.LEFT and widget_region.x >= current_region.x:
                continue
            elif direction == FocusDirection.RIGHT and widget_region.x <= current_region.x:
                continue
            
            # Calculate distance
            if direction in (FocusDirection.UP, FocusDirection.DOWN):
                primary_distance = abs(widget_region.y - current_region.y)
                secondary_distance = abs(widget_region.x - current_region.x)
            else:  # LEFT or RIGHT
                primary_distance = abs(widget_region.x - current_region.x)
                secondary_distance = abs(widget_region.y - current_region.y)
            
            candidates.append((widget, primary_distance, secondary_distance))
        
        if not candidates:
            return None
        
        # Sort by primary distance, then secondary distance
        candidates.sort(key=lambda x: (x[1], x[2]))
        return candidates[0][0]
    
    def _can_widget_focus(self, widget: Widget) -> bool:
        """Check if a widget can receive focus."""
        if self.config.skip_disabled:
            if hasattr(widget, 'can_focus'):
                return widget.can_focus()
            return getattr(widget, 'can_focus', False) and not getattr(widget, 'disabled', True)
        return True
    
    def _on_widget_focused(self, widget: Widget) -> None:
        """Handle widget focus event."""
        self._current_focus = widget
        
        # Update focus history
        if widget in self._focus_history:
            self._focus_history.remove(widget)
        self._focus_history.append(widget)
        
        # Limit history size
        if len(self._focus_history) > 10:
            self._focus_history.pop(0)
    
    def restore_focus(self) -> Optional[Widget]:
        """Restore focus to the last focused widget."""
        for widget in reversed(self._focus_history):
            if self._can_widget_focus(widget):
                widget.focus()
                return widget
        return None
    
    def enable(self) -> None:
        """Enable focus management for this group."""
        self._enabled = True
    
    def disable(self) -> None:
        """Disable focus management for this group."""
        self._enabled = False


class FocusRing:
    """Manages focus rings across multiple groups."""
    
    def __init__(self, name: str, config: Optional[FocusConfig] = None):
        """Initialize focus ring."""
        self.name = name
        self.config = config or FocusConfig()
        self._groups: Dict[str, FocusGroup] = {}
        self._current_group: Optional[FocusGroup] = None
        self._focused_widget: Optional[Widget] = None
        self._modal_stack: List[FocusGroup] = []
    
    def add_group(self, group: FocusGroup) -> None:
        """Add a focus group to the ring."""
        self._groups[group.name] = group
        group._focus_ring = self
        
        if self._current_group is None:
            self._current_group = group
    
    def remove_group(self, group_name: str) -> None:
        """Remove a focus group from the ring."""
        if group_name in self._groups:
            group = self._groups[group_name]
            group._focus_ring = None
            del self._groups[group_name]
            
            if self._current_group == group:
                self._current_group = next(iter(self._groups.values()), None)
    
    def set_active_group(self, group_name: str) -> None:
        """Set the active focus group."""
        if group_name in self._groups:
            self._current_group = self._groups[group_name]
    
    def push_modal(self, group: FocusGroup) -> None:
        """Push a modal focus group onto the stack."""
        if self.config.modal_focus_trap:
            self._modal_stack.append(group)
            self._current_group = group
    
    def pop_modal(self) -> Optional[FocusGroup]:
        """Pop the current modal focus group."""
        if self._modal_stack:
            group = self._modal_stack.pop()
            self._current_group = self._modal_stack[-1] if self._modal_stack else None
            
            # Restore focus if configured
            if self.config.focus_restore and self._current_group:
                self._current_group.restore_focus()
            
            return group
        return None
    
    def focus_next(self) -> Optional[Widget]:
        """Focus the next widget in the current group."""
        if self._current_group:
            return self._current_group.focus_next(self._focused_widget)
        return None
    
    def focus_previous(self) -> Optional[Widget]:
        """Focus the previous widget in the current group."""
        if self._current_group:
            return self._current_group.focus_previous(self._focused_widget)
        return None
    
    def set_focused_widget(self, widget: Widget) -> None:
        """Set the currently focused widget."""
        self._focused_widget = widget


class FocusManager:
    """Global focus manager for the application."""
    
    def __init__(self, app: App, config: Optional[FocusConfig] = None):
        """Initialize focus manager."""
        self.app = app
        self.config = config or FocusConfig()
        self._rings: Dict[str, FocusRing] = {}
        self._current_ring: Optional[FocusRing] = None
        self._screen_rings: Dict[Screen, FocusRing] = {}
        
        # Set up key bindings
        self._setup_bindings()
    
    def _setup_bindings(self) -> None:
        """Set up default key bindings."""
        bindings = [
            Binding("tab", "focus_next", "Next Widget", priority=True),
            Binding("shift+tab", "focus_previous", "Previous Widget", priority=True),
            Binding("ctrl+home", "focus_first", "First Widget"),
            Binding("ctrl+end", "focus_last", "Last Widget"),
        ]
        
        # Add bindings to app
        for binding in bindings:
            if hasattr(self.app, 'bind'):
                self.app.bind(binding.key, binding.action, binding.description)
    
    def create_ring(self, name: str, config: Optional[FocusConfig] = None) -> FocusRing:
        """Create a new focus ring."""
        ring = FocusRing(name, config or self.config)
        self._rings[name] = ring
        
        if self._current_ring is None:
            self._current_ring = ring
        
        return ring
    
    def get_ring(self, name: str) -> Optional[FocusRing]:
        """Get a focus ring by name."""
        return self._rings.get(name)
    
    def set_screen_ring(self, screen: Screen, ring: FocusRing) -> None:
        """Associate a focus ring with a screen."""
        self._screen_rings[screen] = ring
    
    def get_screen_ring(self, screen: Screen) -> Optional[FocusRing]:
        """Get the focus ring for a screen."""
        return self._screen_rings.get(screen)
    
    def switch_to_screen_ring(self, screen: Screen) -> None:
        """Switch to the focus ring for a screen."""
        ring = self.get_screen_ring(screen)
        if ring:
            self._current_ring = ring
    
    def action_focus_next(self) -> None:
        """Action to focus next widget."""
        if self._current_ring:
            self._current_ring.focus_next()
    
    def action_focus_previous(self) -> None:
        """Action to focus previous widget."""
        if self._current_ring:
            self._current_ring.focus_previous()
    
    def action_focus_first(self) -> None:
        """Action to focus first widget."""
        if self._current_ring and self._current_ring._current_group:
            self._current_ring._current_group.focus_first()
    
    def action_focus_last(self) -> None:
        """Action to focus last widget."""
        if self._current_ring and self._current_ring._current_group:
            self._current_ring._current_group.focus_last()


# Global focus manager instance
_global_focus_manager: Optional[FocusManager] = None


def get_global_focus_manager() -> Optional[FocusManager]:
    """Get the global focus manager instance."""
    return _global_focus_manager


def initialize_focus_manager(app: App, config: Optional[FocusConfig] = None) -> FocusManager:
    """Initialize the global focus manager."""
    global _global_focus_manager
    _global_focus_manager = FocusManager(app, config)
    return _global_focus_manager


# Convenience functions for creating focus structures

def create_focus_group(
    name: str,
    widgets: List[Widget],
    mode: FocusMode = FocusMode.TAB_ORDER,
    config: Optional[FocusConfig] = None
) -> FocusGroup:
    """Create a focus group with widgets."""
    group = FocusGroup(name, mode, config)
    
    for i, widget in enumerate(widgets):
        if hasattr(widget, 'focus_group'):
            widget.focus_group = group
        if hasattr(widget, 'tab_index') and widget.tab_index is None:
            widget.tab_index = i
    
    return group


def create_modal_focus_group(
    name: str,
    widgets: List[Widget],
    focus_ring: FocusRing
) -> FocusGroup:
    """Create a modal focus group."""
    group = create_focus_group(name, widgets)
    focus_ring.push_modal(group)
    return group