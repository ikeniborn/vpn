"""
Base formatter class for output formatting.
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

from vpn.core.config import runtime_config
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class OutputFormatter(ABC):
    """Base class for output formatters."""
    
    def __init__(self, no_color: bool = False):
        """
        Initialize formatter.
        
        Args:
            no_color: Disable colored output
        """
        self.no_color = no_color or runtime_config.no_color
    
    @abstractmethod
    def format_single(self, data: Dict[str, Any], **kwargs) -> str:
        """
        Format a single data item.
        
        Args:
            data: Data to format
            **kwargs: Additional formatting options
            
        Returns:
            Formatted string
        """
        pass
    
    @abstractmethod
    def format_list(self, data: List[Dict[str, Any]], **kwargs) -> str:
        """
        Format a list of data items.
        
        Args:
            data: List of data to format
            **kwargs: Additional formatting options
            
        Returns:
            Formatted string
        """
        pass
    
    def format_error(self, error: str, details: Optional[Dict] = None) -> str:
        """
        Format an error message.
        
        Args:
            error: Error message
            details: Optional error details
            
        Returns:
            Formatted error string
        """
        if details:
            return f"Error: {error}\nDetails: {details}"
        return f"Error: {error}"
    
    def format_success(self, message: str) -> str:
        """
        Format a success message.
        
        Args:
            message: Success message
            
        Returns:
            Formatted success string
        """
        return f"✓ {message}"
    
    def format_warning(self, message: str) -> str:
        """
        Format a warning message.
        
        Args:
            message: Warning message
            
        Returns:
            Formatted warning string
        """
        return f"⚠ {message}"
    
    def format_info(self, message: str) -> str:
        """
        Format an info message.
        
        Args:
            message: Info message
            
        Returns:
            Formatted info string
        """
        return f"ℹ {message}"


def get_formatter(format_type: Optional[str] = None) -> OutputFormatter:
    """
    Get formatter instance based on type.
    
    Args:
        format_type: Format type (table, json, yaml, plain)
        
    Returns:
        Formatter instance
    """
    from . import TableFormatter, JsonFormatter, YamlFormatter, PlainFormatter
    
    format_type = format_type or runtime_config.output_format
    
    formatters = {
        "table": TableFormatter,
        "json": JsonFormatter,
        "yaml": YamlFormatter,
        "plain": PlainFormatter,
    }
    
    formatter_class = formatters.get(format_type, TableFormatter)
    return formatter_class(no_color=runtime_config.no_color)