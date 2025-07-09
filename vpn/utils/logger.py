"""
Logging configuration for VPN Manager.
"""

import logging
import sys
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.logging import RichHandler

from vpn.core.config import settings


# Console for rich output
console = Console()


def setup_logging(
    log_level: Optional[str] = None,
    log_file: Optional[Path] = None,
    rich_output: bool = True,
) -> None:
    """
    Configure logging for the application.
    
    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: Path to log file (optional)
        rich_output: Use rich formatting for console output
    """
    # Use provided level or from settings
    level = log_level or settings.log_level
    
    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    
    # Remove existing handlers
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Console handler with rich formatting
    if rich_output:
        console_handler = RichHandler(
            console=console,
            show_time=True,
            show_path=settings.debug,
            markup=True,
            rich_tracebacks=True,
            tracebacks_show_locals=settings.debug,
        )
    else:
        console_handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        )
        console_handler.setFormatter(formatter)
    
    console_handler.setLevel(level)
    root_logger.addHandler(console_handler)
    
    # File handler if specified
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(level)
        
        file_formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        )
        file_handler.setFormatter(file_formatter)
        root_logger.addHandler(file_handler)
    
    # Configure third-party loggers
    logging.getLogger("sqlalchemy").setLevel(logging.WARNING)
    logging.getLogger("asyncio").setLevel(logging.WARNING)
    logging.getLogger("docker").setLevel(logging.WARNING)
    
    # Enable SQL logging in debug mode
    if settings.debug and settings.database_echo:
        logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance.
    
    Args:
        name: Logger name (usually __name__)
        
    Returns:
        Logger instance
    """
    return logging.getLogger(name)


class LogContext:
    """Context manager for temporary logging configuration."""
    
    def __init__(
        self,
        level: Optional[str] = None,
        quiet: bool = False,
        verbose: bool = False,
    ):
        self.level = level
        self.quiet = quiet
        self.verbose = verbose
        self.original_level = None
        self.logger = logging.getLogger()
    
    def __enter__(self):
        """Enter context."""
        self.original_level = self.logger.level
        
        if self.quiet:
            self.logger.setLevel(logging.ERROR)
        elif self.verbose:
            self.logger.setLevel(logging.DEBUG)
        elif self.level:
            self.logger.setLevel(self.level)
        
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Exit context."""
        if self.original_level is not None:
            self.logger.setLevel(self.original_level)


# Initialize logging on module import
setup_logging()