"""Reusable TUI components library for VPN Manager.

This package provides a comprehensive set of reusable Textual components
optimized for the VPN Manager application.
"""

from .focus_management import (
    FocusableWidget,
    FocusGroup,
    FocusManager,
    FocusRing,
    get_global_focus_manager,
)
from .keyboard_shortcuts import (
    ShortcutAction,
    ShortcutContext,
    ShortcutCustomizationScreen,
    ShortcutHelpScreen,
    ShortcutManager,
    ShortcutMixin,
    get_global_shortcut_manager,
    initialize_shortcuts,
)
from .lazy_loading import (
    LazyLoadableWidget,
    LazyScreen,
    LoadingConfig,
    LoadingState,
    VirtualScrollingList,
    create_loading_config,
)
from .reusable_widgets import (
    ActionBar,
    # Navigation widgets
    Breadcrumb,
    CardLayout,
    CollapsibleSection,
    # Dialog widgets
    ConfirmDialog,
    ContextMenu,
    DataGrid,
    FileSelector,
    # Input widgets
    FormField,
    # Data display widgets
    InfoCard,
    InputDialog,
    # Utility widgets
    LoadingSpinner,
    MetricCard,
    MultiSelectList,
    ProgressCard,
    ProgressDialog,
    ResizableContainer,
    SelectDialog,
    SidebarMenu,
    # Layout widgets
    SplitView,
    StatusIndicator,
    TabContainer,
    TagSelector,
    Toast,
    Tooltip,
    ValidatedInput,
)
from .theme_system import (
    CustomTheme,
    Theme,
    ThemeManager,
    ThemePreset,
    get_global_theme_manager,
)

__all__ = [
    # Lazy loading
    "LazyLoadableWidget",
    "VirtualScrollingList",
    "LazyScreen",
    "LoadingState",
    "LoadingConfig",
    "create_loading_config",

    # Keyboard shortcuts
    "ShortcutManager",
    "ShortcutAction",
    "ShortcutContext",
    "ShortcutHelpScreen",
    "ShortcutCustomizationScreen",
    "ShortcutMixin",
    "get_global_shortcut_manager",
    "initialize_shortcuts",

    # Reusable widgets
    "InfoCard",
    "StatusIndicator",
    "ProgressCard",
    "MetricCard",
    "DataGrid",
    "FormField",
    "ValidatedInput",
    "MultiSelectList",
    "TagSelector",
    "FileSelector",
    "Breadcrumb",
    "TabContainer",
    "SidebarMenu",
    "ActionBar",
    "ConfirmDialog",
    "InputDialog",
    "SelectDialog",
    "ProgressDialog",
    "SplitView",
    "ResizableContainer",
    "CollapsibleSection",
    "CardLayout",
    "LoadingSpinner",
    "Toast",
    "ContextMenu",
    "Tooltip",

    # Focus management
    "FocusManager",
    "FocusGroup",
    "FocusRing",
    "FocusableWidget",
    "get_global_focus_manager",

    # Theme system
    "ThemeManager",
    "Theme",
    "ThemePreset",
    "CustomTheme",
    "get_global_theme_manager",
]
