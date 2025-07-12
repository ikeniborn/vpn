"""
Reusable TUI components library for VPN Manager.

This package provides a comprehensive set of reusable Textual components
optimized for the VPN Manager application.
"""

from .lazy_loading import (
    LazyLoadableWidget,
    VirtualScrollingList,
    LazyScreen,
    LoadingState,
    LoadingConfig,
    create_loading_config,
)

from .keyboard_shortcuts import (
    ShortcutManager,
    ShortcutAction,
    ShortcutContext,
    ShortcutHelpScreen,
    ShortcutCustomizationScreen,
    ShortcutMixin,
    get_global_shortcut_manager,
    initialize_shortcuts,
)

from .reusable_widgets import (
    # Data display widgets
    InfoCard,
    StatusIndicator,
    ProgressCard,
    MetricCard,
    DataGrid,
    
    # Input widgets
    FormField,
    ValidatedInput,
    MultiSelectList,
    TagSelector,
    FileSelector,
    
    # Navigation widgets
    Breadcrumb,
    TabContainer,
    SidebarMenu,
    ActionBar,
    
    # Dialog widgets
    ConfirmDialog,
    InputDialog,
    SelectDialog,
    ProgressDialog,
    
    # Layout widgets
    SplitView,
    ResizableContainer,
    CollapsibleSection,
    CardLayout,
    
    # Utility widgets
    LoadingSpinner,
    Toast,
    ContextMenu,
    Tooltip,
)

from .focus_management import (
    FocusManager,
    FocusGroup,
    FocusRing,
    FocusableWidget,
    get_global_focus_manager,
)

from .theme_system import (
    ThemeManager,
    Theme,
    ThemePreset,
    CustomTheme,
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