"""
CLI utility functions.
"""

import sys
from functools import wraps
from typing import Any, Callable, Optional

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Confirm

console = Console()


def confirm_action(
    message: str,
    default: bool = False,
    abort: bool = True
) -> bool:
    """
    Ask for confirmation.
    
    Args:
        message: Confirmation message
        default: Default choice
        abort: Exit if not confirmed
        
    Returns:
        True if confirmed
    """
    confirmed = Confirm.ask(message, default=default)
    
    if not confirmed and abort:
        console.print("[yellow]Operation cancelled[/yellow]")
        sys.exit(0)
    
    return confirmed


def show_progress(
    task_description: str,
    task_function: Callable,
    *args,
    **kwargs
) -> Any:
    """
    Show progress spinner while executing task.
    
    Args:
        task_description: Description to show
        task_function: Function to execute
        *args: Positional arguments for function
        **kwargs: Keyword arguments for function
        
    Returns:
        Function result
    """
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task(task_description, total=None)
        
        try:
            result = task_function(*args, **kwargs)
            progress.update(task, completed=True)
            return result
        except Exception as e:
            progress.stop()
            raise e


def handle_error(
    error: Exception,
    exit_code: int = 1,
    show_traceback: bool = False
) -> None:
    """
    Handle CLI errors consistently.
    
    Args:
        error: Exception to handle
        exit_code: Exit code
        show_traceback: Show full traceback
    """
    from vpn.core.exceptions import VPNError
    
    if isinstance(error, VPNError):
        console.print(f"[red]Error:[/red] {error.message}")
        if error.details:
            console.print("[yellow]Details:[/yellow]")
            for key, value in error.details.items():
                console.print(f"  {key}: {value}")
    else:
        console.print(f"[red]Error:[/red] {str(error)}")
    
    if show_traceback:
        console.print_exception()
    
    sys.exit(exit_code)


def handle_errors(func: Callable) -> Callable:
    """
    Decorator to handle CLI errors consistently.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            handle_error(e)
    return wrapper


def validate_choice(
    value: str,
    choices: list,
    error_message: Optional[str] = None
) -> str:
    """
    Validate user choice against allowed values.
    
    Args:
        value: User input
        choices: Allowed choices
        error_message: Custom error message
        
    Returns:
        Validated value
        
    Raises:
        ValueError: If value not in choices
    """
    if value not in choices:
        msg = error_message or f"Invalid choice. Must be one of: {', '.join(choices)}"
        raise ValueError(msg)
    
    return value


def format_size(bytes: int) -> str:
    """
    Format bytes as human-readable size.
    
    Args:
        bytes: Size in bytes
        
    Returns:
        Formatted size string
    """
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes < 1024.0:
            return f"{bytes:.2f} {unit}"
        bytes /= 1024.0
    
    return f"{bytes:.2f} PB"


def format_duration(seconds: int) -> str:
    """
    Format seconds as human-readable duration.
    
    Args:
        seconds: Duration in seconds
        
    Returns:
        Formatted duration string
    """
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        minutes = seconds // 60
        secs = seconds % 60
        return f"{minutes}m {secs}s"
    elif seconds < 86400:
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    else:
        days = seconds // 86400
        hours = (seconds % 86400) // 3600
        return f"{days}d {hours}h"