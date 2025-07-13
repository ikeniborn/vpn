"""Standardized exit codes for VPN Manager CLI.

This module provides a comprehensive system for handling exit codes across all CLI commands:
- Standard Unix exit codes for common scenarios
- Custom exit codes for VPN-specific operations
- Exit code managers for consistent error handling
- Context managers for automatic exit code handling
- Exit code documentation and best practices
"""

from contextlib import contextmanager
from dataclasses import dataclass
from enum import IntEnum
from typing import Any

import typer
from rich.console import Console

console = Console()


class ExitCode(IntEnum):
    """Standard exit codes for VPN Manager CLI."""

    # Success codes
    SUCCESS = 0

    # General error codes (1-16)
    GENERAL_ERROR = 1
    MISUSE_OF_SHELL_BUILTINS = 2

    # Permission and access errors (17-32)
    PERMISSION_DENIED = 13
    FILE_NOT_FOUND = 14
    DIRECTORY_NOT_FOUND = 15
    ACCESS_DENIED = 16

    # Configuration errors (33-48)
    CONFIG_ERROR = 33
    CONFIG_FILE_NOT_FOUND = 34
    CONFIG_INVALID = 35
    CONFIG_PERMISSION_DENIED = 36

    # Database errors (49-64)
    DATABASE_ERROR = 49
    DATABASE_CONNECTION_FAILED = 50
    DATABASE_SCHEMA_ERROR = 51
    DATABASE_CORRUPTION = 52

    # Network errors (65-80)
    NETWORK_ERROR = 65
    CONNECTION_TIMEOUT = 66
    CONNECTION_REFUSED = 67
    DNS_ERROR = 68

    # Docker errors (81-96)
    DOCKER_ERROR = 81
    DOCKER_NOT_FOUND = 82
    DOCKER_CONNECTION_FAILED = 83
    DOCKER_PERMISSION_DENIED = 84
    CONTAINER_NOT_FOUND = 85
    CONTAINER_ALREADY_EXISTS = 86
    CONTAINER_START_FAILED = 87
    CONTAINER_STOP_FAILED = 88

    # User management errors (97-112)
    USER_ERROR = 97
    USER_NOT_FOUND = 98
    USER_ALREADY_EXISTS = 99
    USER_CREATION_FAILED = 100
    USER_DELETION_FAILED = 101
    USER_UPDATE_FAILED = 102

    # Server management errors (113-128)
    SERVER_ERROR = 113
    SERVER_NOT_FOUND = 114
    SERVER_ALREADY_EXISTS = 115
    SERVER_START_FAILED = 116
    SERVER_STOP_FAILED = 117
    SERVER_RESTART_FAILED = 118
    SERVER_CONFIG_ERROR = 119

    # Protocol errors (129-144)
    PROTOCOL_ERROR = 129
    PROTOCOL_NOT_SUPPORTED = 130
    PROTOCOL_CONFIG_ERROR = 131
    VLESS_ERROR = 132
    SHADOWSOCKS_ERROR = 133
    WIREGUARD_ERROR = 134

    # Security errors (145-160)
    SECURITY_ERROR = 145
    AUTHENTICATION_FAILED = 146
    AUTHORIZATION_FAILED = 147
    CERTIFICATE_ERROR = 148
    KEY_ERROR = 149

    # Validation errors (161-176)
    VALIDATION_ERROR = 161
    INVALID_INPUT = 162
    INVALID_FORMAT = 163
    INVALID_RANGE = 164
    REQUIRED_FIELD_MISSING = 165

    # System errors (177-192)
    SYSTEM_ERROR = 177
    INSUFFICIENT_RESOURCES = 178
    DISK_FULL = 179
    MEMORY_ERROR = 180

    # Operation errors (193-208)
    OPERATION_FAILED = 193
    OPERATION_CANCELLED = 194
    OPERATION_TIMEOUT = 195
    OPERATION_NOT_SUPPORTED = 196

    # Import/Export errors (209-224)
    IMPORT_ERROR = 209
    EXPORT_ERROR = 210
    BACKUP_ERROR = 211
    RESTORE_ERROR = 212

    # Special exit codes
    KEYBOARD_INTERRUPT = 130  # Standard Ctrl+C
    PIPE_ERROR = 141          # Broken pipe
    TERM_SIGNAL = 143         # SIGTERM received


@dataclass
class ExitResult:
    """Result of an operation with exit code and details."""
    code: ExitCode
    message: str = ""
    details: dict[str, Any] | None = None
    suggestion: str = ""

    def is_success(self) -> bool:
        """Check if the result indicates success."""
        return self.code == ExitCode.SUCCESS

    def is_error(self) -> bool:
        """Check if the result indicates an error."""
        return self.code != ExitCode.SUCCESS


class ExitCodeManager:
    """Manages exit codes and provides utilities for consistent error handling."""

    def __init__(self):
        """Initialize exit code manager."""
        self._exit_code_descriptions = {
            ExitCode.SUCCESS: "Operation completed successfully",
            ExitCode.GENERAL_ERROR: "General error occurred",
            ExitCode.PERMISSION_DENIED: "Permission denied",
            ExitCode.FILE_NOT_FOUND: "File not found",
            ExitCode.CONFIG_ERROR: "Configuration error",
            ExitCode.DATABASE_ERROR: "Database error",
            ExitCode.NETWORK_ERROR: "Network error",
            ExitCode.DOCKER_ERROR: "Docker error",
            ExitCode.USER_ERROR: "User management error",
            ExitCode.SERVER_ERROR: "Server management error",
            ExitCode.PROTOCOL_ERROR: "Protocol error",
            ExitCode.SECURITY_ERROR: "Security error",
            ExitCode.VALIDATION_ERROR: "Validation error",
            ExitCode.SYSTEM_ERROR: "System error",
            ExitCode.OPERATION_FAILED: "Operation failed",
            ExitCode.KEYBOARD_INTERRUPT: "Operation cancelled by user",
        }

        self._suggestions = {
            ExitCode.PERMISSION_DENIED: "Try running with sudo or check file permissions",
            ExitCode.FILE_NOT_FOUND: "Check the file path and ensure the file exists",
            ExitCode.CONFIG_ERROR: "Verify your configuration file syntax and values",
            ExitCode.DATABASE_ERROR: "Check database connection and permissions",
            ExitCode.DOCKER_ERROR: "Ensure Docker is running and accessible",
            ExitCode.USER_NOT_FOUND: "Use 'vpn users list' to see available users",
            ExitCode.SERVER_NOT_FOUND: "Use 'vpn server list' to see available servers",
            ExitCode.NETWORK_ERROR: "Check your network connection and firewall settings",
        }

    def get_description(self, code: ExitCode) -> str:
        """Get human-readable description for exit code."""
        return self._exit_code_descriptions.get(code, f"Unknown error (code {code})")

    def get_suggestion(self, code: ExitCode) -> str:
        """Get suggestion for resolving the error."""
        return self._suggestions.get(code, "")

    def create_result(
        self,
        code: ExitCode,
        message: str = "",
        details: dict[str, Any] | None = None,
        suggestion: str = ""
    ) -> ExitResult:
        """Create an ExitResult with proper defaults."""
        if not message:
            message = self.get_description(code)

        if not suggestion:
            suggestion = self.get_suggestion(code)

        return ExitResult(
            code=code,
            message=message,
            details=details,
            suggestion=suggestion
        )

    def exit_with_code(
        self,
        code: ExitCode,
        message: str = "",
        details: dict[str, Any] | None = None,
        suggestion: str = "",
        show_details: bool = False
    ) -> None:
        """Exit the application with the specified code and message."""
        if code == ExitCode.SUCCESS:
            if message:
                console.print(f"[green]✓ {message}[/green]")
        else:
            # Display error message
            error_msg = message or self.get_description(code)
            console.print(f"[red]✗ {error_msg}[/red]")

            # Show suggestion if available
            suggestion = suggestion or self.get_suggestion(code)
            if suggestion:
                console.print(f"[yellow]💡 {suggestion}[/yellow]")

            # Show details if requested and available
            if show_details and details:
                console.print("[dim]Details:[/dim]")
                for key, value in details.items():
                    console.print(f"  {key}: {value}")

        raise typer.Exit(code.value)

    def handle_exception(self, exception: Exception, context: str = "") -> ExitCode:
        """Map exceptions to appropriate exit codes."""
        from vpn.core.exceptions import VPNError

        if isinstance(exception, KeyboardInterrupt):
            return ExitCode.KEYBOARD_INTERRUPT

        if isinstance(exception, VPNError):
            # Map VPNError to appropriate exit codes
            error_mapping = {
                "CONFIG_ERROR": ExitCode.CONFIG_ERROR,
                "DATABASE_ERROR": ExitCode.DATABASE_ERROR,
                "DOCKER_ERROR": ExitCode.DOCKER_ERROR,
                "USER_ERROR": ExitCode.USER_ERROR,
                "SERVER_ERROR": ExitCode.SERVER_ERROR,
                "NETWORK_ERROR": ExitCode.NETWORK_ERROR,
                "PERMISSION_ERROR": ExitCode.PERMISSION_DENIED,
                "VALIDATION_ERROR": ExitCode.VALIDATION_ERROR,
            }
            return error_mapping.get(exception.error_code, ExitCode.GENERAL_ERROR)

        if isinstance(exception, FileNotFoundError):
            return ExitCode.FILE_NOT_FOUND

        if isinstance(exception, PermissionError):
            return ExitCode.PERMISSION_DENIED

        if isinstance(exception, ConnectionError):
            return ExitCode.NETWORK_ERROR

        if isinstance(exception, TimeoutError):
            return ExitCode.CONNECTION_TIMEOUT

        if isinstance(exception, ValueError):
            return ExitCode.VALIDATION_ERROR

        # Default to general error
        return ExitCode.GENERAL_ERROR


# Global exit code manager instance
exit_manager = ExitCodeManager()


@contextmanager
def handle_cli_errors(operation: str = "Operation", show_details: bool = False):
    """Context manager for handling CLI errors with proper exit codes."""
    try:
        yield
    except KeyboardInterrupt:
        exit_manager.exit_with_code(
            ExitCode.KEYBOARD_INTERRUPT,
            f"{operation} cancelled by user"
        )
    except Exception as e:
        code = exit_manager.handle_exception(e, operation)

        details = None
        if show_details:
            details = {
                "exception_type": type(e).__name__,
                "exception_message": str(e),
                "operation": operation
            }

        exit_manager.exit_with_code(
            code,
            f"{operation} failed: {e}",
            details=details,
            show_details=show_details
        )


def success(message: str = "") -> None:
    """Exit with success code and optional message."""
    exit_manager.exit_with_code(ExitCode.SUCCESS, message)


def error(
    code: ExitCode,
    message: str = "",
    details: dict[str, Any] | None = None,
    suggestion: str = "",
    show_details: bool = False
) -> None:
    """Exit with error code and message."""
    exit_manager.exit_with_code(code, message, details, suggestion, show_details)


def user_not_found(username: str) -> None:
    """Exit with user not found error."""
    error(
        ExitCode.USER_NOT_FOUND,
        f"User '{username}' not found",
        suggestion="Use 'vpn users list' to see available users"
    )


def server_not_found(server_name: str) -> None:
    """Exit with server not found error."""
    error(
        ExitCode.SERVER_NOT_FOUND,
        f"Server '{server_name}' not found",
        suggestion="Use 'vpn server list' to see available servers"
    )


def config_error(message: str, file_path: str | None = None) -> None:
    """Exit with configuration error."""
    details = {"config_file": file_path} if file_path else None
    error(
        ExitCode.CONFIG_ERROR,
        f"Configuration error: {message}",
        details=details,
        suggestion="Check your configuration file syntax and values"
    )


def docker_error(message: str, container_name: str | None = None) -> None:
    """Exit with Docker error."""
    details = {"container": container_name} if container_name else None
    error(
        ExitCode.DOCKER_ERROR,
        f"Docker error: {message}",
        details=details,
        suggestion="Ensure Docker is running and accessible"
    )


def validation_error(field: str, value: Any, expected: str) -> None:
    """Exit with validation error."""
    error(
        ExitCode.VALIDATION_ERROR,
        f"Invalid value for {field}: {value}",
        details={"field": field, "value": str(value), "expected": expected},
        suggestion=f"Provide a valid value for {field} ({expected})"
    )


def operation_cancelled() -> None:
    """Exit with operation cancelled code."""
    error(ExitCode.OPERATION_CANCELLED, "Operation cancelled by user")


def operation_timeout(operation: str, timeout: float) -> None:
    """Exit with operation timeout error."""
    error(
        ExitCode.OPERATION_TIMEOUT,
        f"{operation} timed out after {timeout} seconds",
        suggestion="Try increasing the timeout or check system resources"
    )


# Exit code utilities for async operations

async def async_success(message: str = "") -> None:
    """Async version of success exit."""
    success(message)


async def async_error(
    code: ExitCode,
    message: str = "",
    details: dict[str, Any] | None = None,
    suggestion: str = "",
    show_details: bool = False
) -> None:
    """Async version of error exit."""
    error(code, message, details, suggestion, show_details)


def create_exit_decorator(default_error_code: ExitCode):
    """Create a decorator for automatic exit code handling."""
    def decorator(func):
        def wrapper(*args, **kwargs):
            try:
                result = func(*args, **kwargs)

                # Handle async functions
                if hasattr(result, '__await__'):
                    import asyncio

                    async def async_wrapper():
                        try:
                            return await result
                        except Exception as e:
                            code = exit_manager.handle_exception(e)
                            exit_manager.exit_with_code(
                                code or default_error_code,
                                f"Operation failed: {e}"
                            )

                    return asyncio.run(async_wrapper())

                return result

            except Exception as e:
                code = exit_manager.handle_exception(e)
                exit_manager.exit_with_code(
                    code or default_error_code,
                    f"Operation failed: {e}"
                )

        return wrapper
    return decorator


# Convenience decorators for common operations
handle_user_errors = create_exit_decorator(ExitCode.USER_ERROR)
handle_server_errors = create_exit_decorator(ExitCode.SERVER_ERROR)
handle_config_errors = create_exit_decorator(ExitCode.CONFIG_ERROR)
handle_docker_errors = create_exit_decorator(ExitCode.DOCKER_ERROR)


def get_exit_code_documentation() -> dict[str, list[dict[str, int | str]]]:
    """Get documentation for all exit codes organized by category."""
    return {
        "Success": [
            {"code": 0, "name": "SUCCESS", "description": "Operation completed successfully"}
        ],
        "General Errors": [
            {"code": 1, "name": "GENERAL_ERROR", "description": "General error occurred"},
            {"code": 2, "name": "MISUSE_OF_SHELL_BUILTINS", "description": "Misuse of shell builtins"}
        ],
        "Permission Errors": [
            {"code": 13, "name": "PERMISSION_DENIED", "description": "Permission denied"},
            {"code": 14, "name": "FILE_NOT_FOUND", "description": "File not found"},
            {"code": 15, "name": "DIRECTORY_NOT_FOUND", "description": "Directory not found"},
            {"code": 16, "name": "ACCESS_DENIED", "description": "Access denied"}
        ],
        "Configuration Errors": [
            {"code": 33, "name": "CONFIG_ERROR", "description": "Configuration error"},
            {"code": 34, "name": "CONFIG_FILE_NOT_FOUND", "description": "Configuration file not found"},
            {"code": 35, "name": "CONFIG_INVALID", "description": "Invalid configuration"},
            {"code": 36, "name": "CONFIG_PERMISSION_DENIED", "description": "Configuration permission denied"}
        ],
        "Database Errors": [
            {"code": 49, "name": "DATABASE_ERROR", "description": "Database error"},
            {"code": 50, "name": "DATABASE_CONNECTION_FAILED", "description": "Database connection failed"},
            {"code": 51, "name": "DATABASE_SCHEMA_ERROR", "description": "Database schema error"},
            {"code": 52, "name": "DATABASE_CORRUPTION", "description": "Database corruption"}
        ],
        "Network Errors": [
            {"code": 65, "name": "NETWORK_ERROR", "description": "Network error"},
            {"code": 66, "name": "CONNECTION_TIMEOUT", "description": "Connection timeout"},
            {"code": 67, "name": "CONNECTION_REFUSED", "description": "Connection refused"},
            {"code": 68, "name": "DNS_ERROR", "description": "DNS error"}
        ],
        "Docker Errors": [
            {"code": 81, "name": "DOCKER_ERROR", "description": "Docker error"},
            {"code": 82, "name": "DOCKER_NOT_FOUND", "description": "Docker not found"},
            {"code": 83, "name": "DOCKER_CONNECTION_FAILED", "description": "Docker connection failed"},
            {"code": 84, "name": "DOCKER_PERMISSION_DENIED", "description": "Docker permission denied"},
            {"code": 85, "name": "CONTAINER_NOT_FOUND", "description": "Container not found"},
            {"code": 86, "name": "CONTAINER_ALREADY_EXISTS", "description": "Container already exists"},
            {"code": 87, "name": "CONTAINER_START_FAILED", "description": "Container start failed"},
            {"code": 88, "name": "CONTAINER_STOP_FAILED", "description": "Container stop failed"}
        ],
        "User Management Errors": [
            {"code": 97, "name": "USER_ERROR", "description": "User management error"},
            {"code": 98, "name": "USER_NOT_FOUND", "description": "User not found"},
            {"code": 99, "name": "USER_ALREADY_EXISTS", "description": "User already exists"},
            {"code": 100, "name": "USER_CREATION_FAILED", "description": "User creation failed"},
            {"code": 101, "name": "USER_DELETION_FAILED", "description": "User deletion failed"},
            {"code": 102, "name": "USER_UPDATE_FAILED", "description": "User update failed"}
        ],
        "Server Management Errors": [
            {"code": 113, "name": "SERVER_ERROR", "description": "Server management error"},
            {"code": 114, "name": "SERVER_NOT_FOUND", "description": "Server not found"},
            {"code": 115, "name": "SERVER_ALREADY_EXISTS", "description": "Server already exists"},
            {"code": 116, "name": "SERVER_START_FAILED", "description": "Server start failed"},
            {"code": 117, "name": "SERVER_STOP_FAILED", "description": "Server stop failed"},
            {"code": 118, "name": "SERVER_RESTART_FAILED", "description": "Server restart failed"},
            {"code": 119, "name": "SERVER_CONFIG_ERROR", "description": "Server configuration error"}
        ]
    }


def show_exit_codes_help():
    """Display help information about exit codes."""
    from rich.panel import Panel
    from rich.table import Table

    console.print(Panel(
        "[bold]VPN Manager Exit Codes[/bold]\n\n"
        "This tool uses standardized exit codes to indicate the result of operations:\n"
        "• 0 = Success\n"
        "• 1-32 = General system errors\n"
        "• 33-224 = Application-specific errors\n"
        "• 130 = Operation cancelled (Ctrl+C)\n\n"
        "Use exit codes in scripts: if [ $? -eq 0 ]; then echo 'Success'; fi",
        title="📋 Exit Code Reference"
    ))

    documentation = get_exit_code_documentation()

    for category, codes in documentation.items():
        table = Table(title=f"{category}")
        table.add_column("Code", style="cyan", width=6)
        table.add_column("Name", style="green", width=25)
        table.add_column("Description", style="white")

        for code_info in codes:
            table.add_row(
                str(code_info["code"]),
                code_info["name"],
                code_info["description"]
            )

        console.print(table)
        console.print()


# Integration with existing CLI commands

def setup_exit_codes_for_cli():
    """Set up exit code handling for CLI application."""
    import signal

    def signal_handler(signum, frame):
        """Handle signals gracefully."""
        if signum == signal.SIGINT:
            exit_manager.exit_with_code(
                ExitCode.KEYBOARD_INTERRUPT,
                "Operation interrupted by user"
            )
        elif signum == signal.SIGTERM:
            exit_manager.exit_with_code(
                ExitCode.TERM_SIGNAL,
                "Application terminated"
            )

    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)


def validate_exit_codes():
    """Validate that all exit codes are unique and in valid ranges."""
    codes = [code.value for code in ExitCode]

    if len(codes) != len(set(codes)):
        duplicates = [code for code in codes if codes.count(code) > 1]
        raise ValueError(f"Duplicate exit codes found: {set(duplicates)}")

    invalid_codes = [code for code in codes if not (0 <= code <= 255)]
    if invalid_codes:
        raise ValueError(f"Invalid exit codes (must be 0-255): {invalid_codes}")

    return True


# Ensure exit codes are valid when module is imported
validate_exit_codes()
