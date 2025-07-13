"""YAML formatter for human-readable structured output.
"""

from datetime import datetime
from typing import Any
from uuid import UUID

import yaml

from .base import OutputFormatter


class YamlFormatter(OutputFormatter):
    """Format output as YAML."""

    def __init__(self, no_color: bool = False):
        """Initialize YAML formatter."""
        super().__init__(no_color)

    def format_single(self, data: dict[str, Any], **kwargs) -> str:
        """Format a single item as YAML."""
        return yaml.dump(
            self._serialize(data),
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False
        )

    def format_list(self, data: list[dict[str, Any]], **kwargs) -> str:
        """Format a list of items as YAML."""
        return yaml.dump(
            [self._serialize(item) for item in data],
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False
        )

    def format_error(self, error: str, details: dict | None = None) -> str:
        """Format error as YAML."""
        error_data = {
            "error": True,
            "message": error,
            "details": details or {}
        }
        return yaml.dump(error_data, default_flow_style=False)

    def format_success(self, message: str) -> str:
        """Format success as YAML."""
        return yaml.dump({
            "success": True,
            "message": message
        }, default_flow_style=False)

    def format_warning(self, message: str) -> str:
        """Format warning as YAML."""
        return yaml.dump({
            "warning": True,
            "message": message
        }, default_flow_style=False)

    def format_info(self, message: str) -> str:
        """Format info as YAML."""
        return yaml.dump({
            "info": True,
            "message": message
        }, default_flow_style=False)

    def _serialize(self, obj: Any) -> Any:
        """Serialize object for YAML output.
        
        Handles special types like datetime, UUID, etc.
        """
        if isinstance(obj, dict):
            return {k: self._serialize(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [self._serialize(item) for item in obj]
        elif isinstance(obj, datetime):
            return obj.isoformat()
        elif isinstance(obj, UUID):
            return str(obj)
        elif hasattr(obj, 'model_dump'):  # Pydantic model
            return self._serialize(obj.model_dump())
        elif hasattr(obj, '__dict__'):  # Generic object
            return self._serialize(obj.__dict__)
        else:
            return obj
