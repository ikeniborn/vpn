"""
JSON formatter for machine-readable output.
"""

import json
from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID

from .base import OutputFormatter


class JsonFormatter(OutputFormatter):
    """Format output as JSON."""
    
    def __init__(self, no_color: bool = False):
        """Initialize JSON formatter."""
        super().__init__(no_color)
        self.indent = 2
    
    def format_single(self, data: Dict[str, Any], **kwargs) -> str:
        """Format a single item as JSON."""
        return json.dumps(
            self._serialize(data),
            indent=self.indent,
            ensure_ascii=False
        )
    
    def format_list(self, data: List[Dict[str, Any]], **kwargs) -> str:
        """Format a list of items as JSON."""
        return json.dumps(
            [self._serialize(item) for item in data],
            indent=self.indent,
            ensure_ascii=False
        )
    
    def format_error(self, error: str, details: Optional[Dict] = None) -> str:
        """Format error as JSON."""
        error_data = {
            "error": True,
            "message": error,
            "details": details or {}
        }
        return json.dumps(error_data, indent=self.indent)
    
    def format_success(self, message: str) -> str:
        """Format success as JSON."""
        return json.dumps({
            "success": True,
            "message": message
        }, indent=self.indent)
    
    def format_warning(self, message: str) -> str:
        """Format warning as JSON."""
        return json.dumps({
            "warning": True,
            "message": message
        }, indent=self.indent)
    
    def format_info(self, message: str) -> str:
        """Format info as JSON."""
        return json.dumps({
            "info": True,
            "message": message
        }, indent=self.indent)
    
    def _serialize(self, obj: Any) -> Any:
        """
        Serialize object for JSON output.
        
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