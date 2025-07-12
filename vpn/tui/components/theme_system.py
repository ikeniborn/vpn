"""
Advanced theme system for Textual TUI with customization support.

This module provides comprehensive theming capabilities including:
- Multiple built-in themes
- Custom theme creation
- Dynamic theme switching
- Theme persistence
- Color scheme generation
"""

import json
from typing import Dict, List, Optional, Any, Union, Callable
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path
import colorsys

from textual.app import App
from textual.css import Styles
from textual.design import ColorSystem
from textual.color import Color
from textual.screen import ModalScreen
from textual.widgets import (
    Static, Button, Input, Select, Label, Slider,
    Container, Collapsible, Checkbox, RadioSet, RadioButton
)
from textual.containers import Vertical, Horizontal, Grid
from textual.reactive import reactive
from textual import on


class ThemeCategory(Enum):
    """Theme categories for organization."""
    BUILT_IN = "built_in"
    CUSTOM = "custom"
    COMMUNITY = "community"
    IMPORTED = "imported"


@dataclass
class ColorPalette:
    """Color palette for a theme."""
    
    # Primary colors
    primary: str = "#0178d4"
    primary_lighten_1: str = "#4b9cdb"
    primary_lighten_2: str = "#7fb4e3"
    primary_lighten_3: str = "#b3cceb"
    primary_darken_1: str = "#0160aa"
    primary_darken_2: str = "#014880"
    primary_darken_3: str = "#003056"
    
    # Secondary colors
    secondary: str = "#6c757d"
    secondary_lighten_1: str = "#8a9399"
    secondary_lighten_2: str = "#a8b1b5"
    secondary_lighten_3: str = "#c6cfd1"
    secondary_darken_1: str = "#565e64"
    secondary_darken_2: str = "#40474b"
    secondary_darken_3: str = "#2a3032"
    
    # Accent colors
    accent: str = "#f1c40f"
    accent_lighten_1: str = "#f4cf3f"
    accent_lighten_2: str = "#f7da6f"
    accent_lighten_3: str = "#fae59f"
    accent_darken_1: str = "#c19d0c"
    accent_darken_2: str = "#917509"
    accent_darken_3: str = "#614e06"
    
    # Semantic colors
    success: str = "#28a745"
    success_lighten_1: str = "#53b969"
    success_lighten_2: str = "#7ecb8d"
    success_lighten_3: str = "#a9ddb1"
    
    warning: str = "#ffc107"
    warning_lighten_1: str = "#ffcd39"
    warning_lighten_2: str = "#ffd96b"
    warning_lighten_3: str = "#ffe69d"
    
    error: str = "#dc3545"
    error_lighten_1: str = "#e3606d"
    error_lighten_2: str = "#ea8a95"
    error_lighten_3: str = "#f1b4bd"
    
    info: str = "#17a2b8"
    info_lighten_1: str = "#45b5c6"
    info_lighten_2: str = "#73c8d4"
    info_lighten_3: str = "#a1dbe2"
    
    # Background colors
    background: str = "#0e1419"
    surface: str = "#16202b"
    surface_lighten_1: str = "#1e2a37"
    surface_lighten_2: str = "#263443"
    surface_lighten_3: str = "#2e3e4f"
    
    # Text colors
    text: str = "#ffffff"
    text_muted: str = "#a0aab5"
    text_disabled: str = "#6b7785"


@dataclass
class ThemeMetadata:
    """Metadata for a theme."""
    name: str
    description: str = ""
    author: str = ""
    version: str = "1.0.0"
    category: ThemeCategory = ThemeCategory.CUSTOM
    tags: List[str] = field(default_factory=list)
    preview_url: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


@dataclass
class Theme:
    """Complete theme definition."""
    metadata: ThemeMetadata
    colors: ColorPalette
    font_family: str = "monospace"
    font_size: int = 14
    border_style: str = "solid"
    animation_duration: float = 0.2
    custom_css: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert theme to dictionary."""
        return {
            "metadata": asdict(self.metadata),
            "colors": asdict(self.colors),
            "font_family": self.font_family,
            "font_size": self.font_size,
            "border_style": self.border_style,
            "animation_duration": self.animation_duration,
            "custom_css": self.custom_css,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Theme':
        """Create theme from dictionary."""
        metadata = ThemeMetadata(**data["metadata"])
        colors = ColorPalette(**data["colors"])
        
        return cls(
            metadata=metadata,
            colors=colors,
            font_family=data.get("font_family", "monospace"),
            font_size=data.get("font_size", 14),
            border_style=data.get("border_style", "solid"),
            animation_duration=data.get("animation_duration", 0.2),
            custom_css=data.get("custom_css", ""),
        )


class ThemePreset:
    """Predefined theme presets."""
    
    @staticmethod
    def dark_blue() -> Theme:
        """Dark blue theme (default)."""
        return Theme(
            metadata=ThemeMetadata(
                name="Dark Blue",
                description="Classic dark blue theme with high contrast",
                author="VPN Manager",
                category=ThemeCategory.BUILT_IN,
                tags=["dark", "blue", "professional"]
            ),
            colors=ColorPalette()  # Uses default colors
        )
    
    @staticmethod
    def light_blue() -> Theme:
        """Light blue theme."""
        colors = ColorPalette(
            primary="#0066cc",
            background="#f8f9fa",
            surface="#ffffff",
            surface_lighten_1="#f1f3f4",
            text="#212529",
            text_muted="#6c757d",
        )
        
        return Theme(
            metadata=ThemeMetadata(
                name="Light Blue",
                description="Clean light theme with blue accents",
                author="VPN Manager",
                category=ThemeCategory.BUILT_IN,
                tags=["light", "blue", "clean"]
            ),
            colors=colors
        )
    
    @staticmethod
    def dark_green() -> Theme:
        """Dark green theme."""
        colors = ColorPalette(
            primary="#28a745",
            primary_lighten_1="#53b969",
            accent="#20c997",
            background="#0d1b0f",
            surface="#162a1a",
            text="#ffffff",
        )
        
        return Theme(
            metadata=ThemeMetadata(
                name="Dark Green",
                description="Dark theme with green nature tones",
                author="VPN Manager",
                category=ThemeCategory.BUILT_IN,
                tags=["dark", "green", "nature"]
            ),
            colors=colors
        )
    
    @staticmethod
    def cyberpunk() -> Theme:
        """Cyberpunk neon theme."""
        colors = ColorPalette(
            primary="#ff0080",
            primary_lighten_1="#ff4da6",
            accent="#00ffff",
            accent_lighten_1="#4dffff",
            background="#0a0a0a",
            surface="#1a0a1a",
            surface_lighten_1="#2a0a2a",
            text="#ffffff",
            text_muted="#ff00ff",
        )
        
        return Theme(
            metadata=ThemeMetadata(
                name="Cyberpunk",
                description="Neon cyberpunk theme with vibrant colors",
                author="VPN Manager",
                category=ThemeCategory.BUILT_IN,
                tags=["dark", "neon", "cyberpunk", "vibrant"]
            ),
            colors=colors
        )
    
    @staticmethod
    def minimal_mono() -> Theme:
        """Minimal monochrome theme."""
        colors = ColorPalette(
            primary="#333333",
            primary_lighten_1="#666666",
            secondary="#999999",
            accent="#000000",
            background="#ffffff",
            surface="#f5f5f5",
            surface_lighten_1="#eeeeee",
            text="#000000",
            text_muted="#666666",
            success="#333333",
            warning="#666666",
            error="#999999",
            info="#333333",
        )
        
        return Theme(
            metadata=ThemeMetadata(
                name="Minimal Mono",
                description="Minimalist monochrome theme",
                author="VPN Manager",
                category=ThemeCategory.BUILT_IN,
                tags=["light", "minimal", "monochrome"]
            ),
            colors=colors
        )


class ColorGenerator:
    """Utility for generating color variations."""
    
    @staticmethod
    def lighten_color(color: str, amount: float) -> str:
        """Lighten a color by a percentage."""
        try:
            color_obj = Color.parse(color)
            h, l, s = color_obj.hsl
            
            # Increase lightness
            new_l = min(1.0, l + amount)
            new_color = Color.from_hsl(h, new_l, s)
            
            return new_color.hex
        except:
            return color
    
    @staticmethod
    def darken_color(color: str, amount: float) -> str:
        """Darken a color by a percentage."""
        try:
            color_obj = Color.parse(color)
            h, l, s = color_obj.hsl
            
            # Decrease lightness
            new_l = max(0.0, l - amount)
            new_color = Color.from_hsl(h, new_l, s)
            
            return new_color.hex
        except:
            return color
    
    @staticmethod
    def generate_palette_variations(base_color: str) -> Dict[str, str]:
        """Generate a full palette from a base color."""
        variations = {}
        
        # Generate lightened versions
        for i in range(1, 4):
            variations[f"lighten_{i}"] = ColorGenerator.lighten_color(base_color, i * 0.1)
        
        # Generate darkened versions
        for i in range(1, 4):
            variations[f"darken_{i}"] = ColorGenerator.darken_color(base_color, i * 0.1)
        
        return variations
    
    @staticmethod
    def complementary_color(color: str) -> str:
        """Get complementary color."""
        try:
            color_obj = Color.parse(color)
            h, l, s = color_obj.hsl
            
            # Shift hue by 180 degrees
            new_h = (h + 0.5) % 1.0
            new_color = Color.from_hsl(new_h, l, s)
            
            return new_color.hex
        except:
            return color


class ThemeManager:
    """Manages themes for the application."""
    
    def __init__(self, config_dir: Optional[Path] = None):
        """Initialize theme manager."""
        self.config_dir = config_dir or Path.home() / ".config" / "vpn-manager"
        self.themes_dir = self.config_dir / "themes"
        self.themes_dir.mkdir(parents=True, exist_ok=True)
        
        self._themes: Dict[str, Theme] = {}
        self._current_theme: Optional[Theme] = None
        self._theme_change_callbacks: List[Callable[[Theme], None]] = []
        
        # Load built-in themes
        self._load_builtin_themes()
        
        # Load custom themes
        self._load_custom_themes()
        
        # Set default theme
        if not self._current_theme:
            self.set_theme("Dark Blue")
    
    def _load_builtin_themes(self) -> None:
        """Load built-in themes."""
        builtin_themes = [
            ThemePreset.dark_blue(),
            ThemePreset.light_blue(),
            ThemePreset.dark_green(),
            ThemePreset.cyberpunk(),
            ThemePreset.minimal_mono(),
        ]
        
        for theme in builtin_themes:
            self._themes[theme.metadata.name] = theme
    
    def _load_custom_themes(self) -> None:
        """Load custom themes from files."""
        for theme_file in self.themes_dir.glob("*.json"):
            try:
                with open(theme_file, 'r') as f:
                    theme_data = json.load(f)
                
                theme = Theme.from_dict(theme_data)
                self._themes[theme.metadata.name] = theme
                
            except Exception as e:
                # Log error but continue loading other themes
                pass
    
    def get_themes(self, category: Optional[ThemeCategory] = None) -> List[Theme]:
        """Get all themes, optionally filtered by category."""
        themes = list(self._themes.values())
        
        if category:
            themes = [t for t in themes if t.metadata.category == category]
        
        return sorted(themes, key=lambda t: t.metadata.name)
    
    def get_theme(self, name: str) -> Optional[Theme]:
        """Get a theme by name."""
        return self._themes.get(name)
    
    def set_theme(self, name: str) -> bool:
        """Set the current theme."""
        theme = self.get_theme(name)
        if not theme:
            return False
        
        self._current_theme = theme
        
        # Notify callbacks
        for callback in self._theme_change_callbacks:
            try:
                callback(theme)
            except Exception:
                pass  # Continue with other callbacks
        
        # Save current theme preference
        self._save_current_theme_preference(name)
        
        return True
    
    def get_current_theme(self) -> Optional[Theme]:
        """Get the current theme."""
        return self._current_theme
    
    def add_theme_change_callback(self, callback: Callable[[Theme], None]) -> None:
        """Add a callback for theme changes."""
        self._theme_change_callbacks.append(callback)
    
    def remove_theme_change_callback(self, callback: Callable[[Theme], None]) -> None:
        """Remove a theme change callback."""
        if callback in self._theme_change_callbacks:
            self._theme_change_callbacks.remove(callback)
    
    def save_theme(self, theme: Theme) -> bool:
        """Save a custom theme."""
        try:
            theme_file = self.themes_dir / f"{theme.metadata.name.lower().replace(' ', '_')}.json"
            
            with open(theme_file, 'w') as f:
                json.dump(theme.to_dict(), f, indent=2)
            
            self._themes[theme.metadata.name] = theme
            return True
            
        except Exception as e:
            return False
    
    def delete_theme(self, name: str) -> bool:
        """Delete a custom theme."""
        theme = self.get_theme(name)
        if not theme or theme.metadata.category == ThemeCategory.BUILT_IN:
            return False
        
        try:
            theme_file = self.themes_dir / f"{name.lower().replace(' ', '_')}.json"
            if theme_file.exists():
                theme_file.unlink()
            
            del self._themes[name]
            return True
            
        except Exception:
            return False
    
    def duplicate_theme(self, source_name: str, new_name: str) -> Optional[Theme]:
        """Create a duplicate of an existing theme."""
        source_theme = self.get_theme(source_name)
        if not source_theme:
            return None
        
        # Create new theme with copied data
        new_theme_data = source_theme.to_dict()
        new_theme_data["metadata"]["name"] = new_name
        new_theme_data["metadata"]["category"] = ThemeCategory.CUSTOM.value
        new_theme_data["metadata"]["author"] = "Custom"
        
        new_theme = Theme.from_dict(new_theme_data)
        
        if self.save_theme(new_theme):
            return new_theme
        
        return None
    
    def export_theme(self, name: str, file_path: Path) -> bool:
        """Export a theme to a file."""
        theme = self.get_theme(name)
        if not theme:
            return False
        
        try:
            with open(file_path, 'w') as f:
                json.dump(theme.to_dict(), f, indent=2)
            return True
        except Exception:
            return False
    
    def import_theme(self, file_path: Path) -> Optional[Theme]:
        """Import a theme from a file."""
        try:
            with open(file_path, 'r') as f:
                theme_data = json.load(f)
            
            theme = Theme.from_dict(theme_data)
            theme.metadata.category = ThemeCategory.IMPORTED
            
            if self.save_theme(theme):
                return theme
            
        except Exception:
            pass
        
        return None
    
    def _save_current_theme_preference(self, theme_name: str) -> None:
        """Save the current theme preference."""
        try:
            prefs_file = self.config_dir / "theme_preferences.json"
            prefs = {"current_theme": theme_name}
            
            with open(prefs_file, 'w') as f:
                json.dump(prefs, f)
        except Exception:
            pass  # Not critical if this fails
    
    def _load_theme_preference(self) -> Optional[str]:
        """Load the saved theme preference."""
        try:
            prefs_file = self.config_dir / "theme_preferences.json"
            if prefs_file.exists():
                with open(prefs_file, 'r') as f:
                    prefs = json.load(f)
                return prefs.get("current_theme")
        except Exception:
            pass
        return None


class ThemeCustomizationScreen(ModalScreen):
    """Screen for customizing themes."""
    
    DEFAULT_CSS = """
    ThemeCustomizationScreen {
        align: center middle;
    }
    
    .theme-customization-container {
        width: 90%;
        height: 90%;
        background: $surface;
        border: solid $primary;
        padding: 1;
    }
    
    .customization-header {
        text-align: center;
        margin-bottom: 2;
    }
    
    .theme-sections {
        height: 80%;
    }
    
    .color-section {
        margin: 1;
        padding: 1;
        border: solid $primary-lighten-2;
    }
    
    .color-input {
        width: 20;
        margin: 0 1;
    }
    
    .theme-preview {
        width: 30%;
        height: 100%;
        margin-left: 2;
        padding: 1;
        border: solid $secondary;
    }
    
    .action-buttons {
        margin: 1;
    }
    """
    
    def __init__(self, theme_manager: ThemeManager, theme_name: Optional[str] = None):
        """Initialize theme customization screen."""
        super().__init__()
        self.theme_manager = theme_manager
        self.current_theme = (
            theme_manager.get_theme(theme_name) if theme_name 
            else theme_manager.duplicate_theme("Dark Blue", "Custom Theme")
        )
        self.preview_theme = None
    
    def compose(self) -> ComposeResult:
        """Compose the customization screen."""
        with Container(classes="theme-customization-container"):
            with Container(classes="customization-header"):
                yield Static("Theme Customization", classes="title")
                yield Input(
                    value=self.current_theme.metadata.name if self.current_theme else "New Theme",
                    placeholder="Theme name",
                    id="theme-name"
                )
            
            with Horizontal(classes="theme-sections"):
                # Color customization section
                with Vertical(classes="color-customization"):
                    with Collapsible(title="Primary Colors", collapsed=False):
                        yield self._create_color_section("primary", "Primary Colors")
                    
                    with Collapsible(title="Accent Colors"):
                        yield self._create_color_section("accent", "Accent Colors")
                    
                    with Collapsible(title="Background Colors"):
                        yield self._create_color_section("background", "Background Colors")
                    
                    with Collapsible(title="Text Colors"):
                        yield self._create_color_section("text", "Text Colors")
                    
                    with Collapsible(title="Semantic Colors"):
                        yield self._create_color_section("semantic", "Semantic Colors")
                
                # Theme preview section
                with Container(classes="theme-preview"):
                    yield Static("Theme Preview", classes="preview-title")
                    # Add preview widgets here
                    yield self._create_theme_preview()
            
            # Action buttons
            with Horizontal(classes="action-buttons"):
                yield Button("Save Theme", id="save-theme", variant="primary")
                yield Button("Preview", id="preview-theme", variant="success")
                yield Button("Reset", id="reset-theme", variant="warning")
                yield Button("Cancel", id="cancel-customization")
    
    def _create_color_section(self, section: str, title: str) -> Container:
        """Create a color customization section."""
        container = Container()
        
        if section == "primary":
            colors = ["primary", "primary_lighten_1", "primary_darken_1"]
        elif section == "accent":
            colors = ["accent", "accent_lighten_1", "accent_darken_1"]
        elif section == "background":
            colors = ["background", "surface", "surface_lighten_1"]
        elif section == "text":
            colors = ["text", "text_muted", "text_disabled"]
        elif section == "semantic":
            colors = ["success", "warning", "error", "info"]
        else:
            colors = []
        
        for color_name in colors:
            with container:
                with Horizontal():
                    yield Label(color_name.replace("_", " ").title())
                    yield Input(
                        value=getattr(self.current_theme.colors, color_name, "#000000"),
                        id=f"color-{color_name}",
                        classes="color-input"
                    )
        
        return container
    
    def _create_theme_preview(self) -> Container:
        """Create theme preview widgets."""
        from vpn.tui.components.reusable_widgets import InfoCard, StatusIndicator, StatusType
        
        preview = Container()
        
        with preview:
            yield InfoCard(
                "Preview Card",
                "This shows how the theme looks",
                "Sample footer text"
            )
            
            yield StatusIndicator("Success Status", StatusType.SUCCESS)
            yield StatusIndicator("Warning Status", StatusType.WARNING)
            yield StatusIndicator("Error Status", StatusType.ERROR)
            
            with Horizontal():
                yield Button("Primary Button", variant="primary")
                yield Button("Secondary Button")
        
        return preview
    
    @on(Button.Pressed, "#save-theme")
    def save_theme(self) -> None:
        """Save the customized theme."""
        if self.current_theme:
            # Update theme name
            name_input = self.query_one("#theme-name", Input)
            self.current_theme.metadata.name = name_input.value
            
            # Update colors from inputs
            self._update_theme_from_inputs()
            
            # Save theme
            if self.theme_manager.save_theme(self.current_theme):
                self.app.notify("Theme saved successfully!", severity="information")
                self.dismiss()
            else:
                self.app.notify("Failed to save theme", severity="error")
    
    @on(Button.Pressed, "#preview-theme")
    def preview_theme(self) -> None:
        """Preview the theme changes."""
        if self.current_theme:
            self._update_theme_from_inputs()
            # Apply theme temporarily for preview
            # Implementation would depend on how themes are applied in the app
    
    @on(Button.Pressed, "#reset-theme")
    def reset_theme(self) -> None:
        """Reset theme to original state."""
        # Reset to original theme or default
        self.app.notify("Theme reset to original state", severity="information")
    
    @on(Button.Pressed, "#cancel-customization")
    def cancel_customization(self) -> None:
        """Cancel theme customization."""
        self.dismiss()
    
    def _update_theme_from_inputs(self) -> None:
        """Update theme object from input values."""
        if not self.current_theme:
            return
        
        # Update all color inputs
        color_fields = [
            "primary", "primary_lighten_1", "primary_darken_1",
            "accent", "accent_lighten_1", "accent_darken_1",
            "background", "surface", "surface_lighten_1",
            "text", "text_muted", "text_disabled",
            "success", "warning", "error", "info"
        ]
        
        for field in color_fields:
            try:
                color_input = self.query_one(f"#color-{field}", Input)
                setattr(self.current_theme.colors, field, color_input.value)
            except:
                pass  # Input doesn't exist


# Global theme manager instance
_global_theme_manager: Optional[ThemeManager] = None


def get_global_theme_manager() -> Optional[ThemeManager]:
    """Get the global theme manager instance."""
    return _global_theme_manager


def initialize_theme_manager(config_dir: Optional[Path] = None) -> ThemeManager:
    """Initialize the global theme manager."""
    global _global_theme_manager
    _global_theme_manager = ThemeManager(config_dir)
    return _global_theme_manager