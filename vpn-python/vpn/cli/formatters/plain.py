"""
Plain text formatter for simple output.
"""

from typing import Any, Dict, List, Optional

from .base import OutputFormatter


class PlainFormatter(OutputFormatter):
    """Format output as plain text."""
    
    def format_single(self, data: Dict[str, Any], **kwargs) -> str:
        """Format a single item as plain text."""
        lines = []
        for key, value in data.items():
            # Convert key from snake_case to readable format
            display_key = key.replace("_", " ").title()
            
            # Format value
            if isinstance(value, bool):
                display_value = "Yes" if value else "No"
            elif isinstance(value, (list, dict)):
                display_value = str(value)
            elif value is None:
                display_value = "Not set"
            else:
                display_value = str(value)
            
            lines.append(f"{display_key}: {display_value}")
        
        return "\n".join(lines)
    
    def format_list(
        self,
        data: List[Dict[str, Any]],
        columns: Optional[List[str]] = None,
        **kwargs
    ) -> str:
        """Format a list of items as plain text."""
        if not data:
            return "No data to display"
        
        # Determine columns
        if not columns:
            columns = list(data[0].keys()) if data else []
        
        lines = []
        
        # Simple format: one item per line
        for i, item in enumerate(data):
            if i > 0:
                lines.append("")  # Empty line between items
            
            # Format each field
            for col in columns:
                value = item.get(col, "")
                display_col = col.replace("_", " ").title()
                
                # Format special values
                if col == "status":
                    if value == "active":
                        display_value = "Active"
                    elif value == "inactive":
                        display_value = "Inactive"
                    elif value == "suspended":
                        display_value = "Suspended"
                    else:
                        display_value = str(value)
                elif col == "traffic":
                    if isinstance(value, dict):
                        total_mb = value.get("total_mb", 0)
                        display_value = f"{total_mb:.2f} MB"
                    else:
                        display_value = str(value)
                elif isinstance(value, bool):
                    display_value = "Yes" if value else "No"
                elif value is None:
                    display_value = "-"
                else:
                    display_value = str(value)
                
                lines.append(f"{display_col}: {display_value}")
        
        return "\n".join(lines)
    
    def format_error(self, error: str, details: Optional[Dict] = None) -> str:
        """Format error as plain text."""
        output = f"Error: {error}"
        if details:
            output += "\nDetails:"
            for key, value in details.items():
                output += f"\n  {key}: {value}"
        return output
    
    def format_success(self, message: str) -> str:
        """Format success as plain text."""
        return f"Success: {message}"
    
    def format_warning(self, message: str) -> str:
        """Format warning as plain text."""
        return f"Warning: {message}"
    
    def format_info(self, message: str) -> str:
        """Format info as plain text."""
        return f"Info: {message}"