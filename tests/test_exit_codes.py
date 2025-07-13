"""
Tests for the exit code system.
"""

from unittest.mock import patch

import pytest

from vpn.cli.exit_codes import (
    ExitCode,
    ExitCodeManager,
    ExitResult,
    config_error,
    docker_error,
    error,
    exit_manager,
    get_exit_code_documentation,
    handle_cli_errors,
    operation_cancelled,
    operation_timeout,
    server_not_found,
    success,
    user_not_found,
    validate_exit_codes,
    validation_error,
)
from vpn.core.exceptions import VPNError


class TestExitCode:
    """Test exit code enum values."""

    def test_success_code(self):
        """Test success exit code."""
        assert ExitCode.SUCCESS == 0

    def test_error_codes_unique(self):
        """Test that all exit codes are unique."""
        codes = [code.value for code in ExitCode]
        assert len(codes) == len(set(codes))

    def test_error_codes_valid_range(self):
        """Test that all exit codes are in valid range (0-255)."""
        for code in ExitCode:
            assert 0 <= code.value <= 255

    def test_validate_exit_codes(self):
        """Test exit code validation."""
        # Should not raise any exception
        assert validate_exit_codes() is True


class TestExitResult:
    """Test ExitResult dataclass."""

    def test_exit_result_creation(self):
        """Test creating ExitResult."""
        result = ExitResult(
            code=ExitCode.SUCCESS,
            message="Operation completed",
            details={"items": 5},
            suggestion="Great job!"
        )

        assert result.code == ExitCode.SUCCESS
        assert result.message == "Operation completed"
        assert result.details == {"items": 5}
        assert result.suggestion == "Great job!"

    def test_is_success(self):
        """Test success detection."""
        success_result = ExitResult(ExitCode.SUCCESS)
        error_result = ExitResult(ExitCode.GENERAL_ERROR)

        assert success_result.is_success() is True
        assert error_result.is_success() is False

    def test_is_error(self):
        """Test error detection."""
        success_result = ExitResult(ExitCode.SUCCESS)
        error_result = ExitResult(ExitCode.GENERAL_ERROR)

        assert success_result.is_error() is False
        assert error_result.is_error() is True


class TestExitCodeManager:
    """Test ExitCodeManager class."""

    def test_get_description(self):
        """Test getting exit code descriptions."""
        manager = ExitCodeManager()

        assert "success" in manager.get_description(ExitCode.SUCCESS).lower()
        assert "error" in manager.get_description(ExitCode.GENERAL_ERROR).lower()
        assert "permission" in manager.get_description(ExitCode.PERMISSION_DENIED).lower()

    def test_get_suggestion(self):
        """Test getting suggestions for exit codes."""
        manager = ExitCodeManager()

        suggestion = manager.get_suggestion(ExitCode.PERMISSION_DENIED)
        assert "sudo" in suggestion.lower() or "permission" in suggestion.lower()

        suggestion = manager.get_suggestion(ExitCode.FILE_NOT_FOUND)
        assert "file" in suggestion.lower() or "path" in suggestion.lower()

    def test_create_result(self):
        """Test creating ExitResult with defaults."""
        manager = ExitCodeManager()

        result = manager.create_result(ExitCode.USER_NOT_FOUND)
        assert result.code == ExitCode.USER_NOT_FOUND
        assert result.message  # Should have default message
        assert result.suggestion  # Should have default suggestion

    def test_handle_exception_vpn_error(self):
        """Test handling VPNError exceptions."""
        manager = ExitCodeManager()

        vpn_error = VPNError("CONFIG_ERROR", "Invalid config", {"file": "test.yaml"})
        code = manager.handle_exception(vpn_error)
        assert code == ExitCode.CONFIG_ERROR

    def test_handle_exception_builtin_errors(self):
        """Test handling built-in Python exceptions."""
        manager = ExitCodeManager()

        assert manager.handle_exception(FileNotFoundError()) == ExitCode.FILE_NOT_FOUND
        assert manager.handle_exception(PermissionError()) == ExitCode.PERMISSION_DENIED
        assert manager.handle_exception(ConnectionError()) == ExitCode.NETWORK_ERROR
        assert manager.handle_exception(TimeoutError()) == ExitCode.CONNECTION_TIMEOUT
        assert manager.handle_exception(ValueError()) == ExitCode.VALIDATION_ERROR
        assert manager.handle_exception(KeyboardInterrupt()) == ExitCode.KEYBOARD_INTERRUPT

    def test_handle_exception_unknown(self):
        """Test handling unknown exceptions."""
        manager = ExitCodeManager()

        unknown_error = RuntimeError("Unknown error")
        code = manager.handle_exception(unknown_error)
        assert code == ExitCode.GENERAL_ERROR

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_exit_with_code_success(self, mock_console, mock_exit):
        """Test exiting with success code."""
        manager = ExitCodeManager()

        manager.exit_with_code(ExitCode.SUCCESS, "Test completed")

        mock_console.print.assert_called_once()
        mock_exit.assert_called_once_with(0)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_exit_with_code_error(self, mock_console, mock_exit):
        """Test exiting with error code."""
        manager = ExitCodeManager()

        manager.exit_with_code(
            ExitCode.USER_NOT_FOUND,
            "User not found",
            suggestion="Check username"
        )

        # Should print error message and suggestion
        assert mock_console.print.call_count >= 2
        mock_exit.assert_called_once_with(98)


class TestConvenienceFunctions:
    """Test convenience functions."""

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_success_function(self, mock_console, mock_exit):
        """Test success convenience function."""
        success("Operation completed")

        mock_console.print.assert_called_once()
        mock_exit.assert_called_once_with(0)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_error_function(self, mock_console, mock_exit):
        """Test error convenience function."""
        error(ExitCode.GENERAL_ERROR, "Something went wrong")

        mock_console.print.assert_called()
        mock_exit.assert_called_once_with(1)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_user_not_found_function(self, mock_console, mock_exit):
        """Test user_not_found convenience function."""
        user_not_found("john")

        mock_exit.assert_called_once_with(98)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_server_not_found_function(self, mock_console, mock_exit):
        """Test server_not_found convenience function."""
        server_not_found("prod-server")

        mock_exit.assert_called_once_with(114)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_config_error_function(self, mock_console, mock_exit):
        """Test config_error convenience function."""
        config_error("Invalid syntax", "/path/to/config.yaml")

        mock_exit.assert_called_once_with(33)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_docker_error_function(self, mock_console, mock_exit):
        """Test docker_error convenience function."""
        docker_error("Container failed to start", "vpn-server")

        mock_exit.assert_called_once_with(81)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_validation_error_function(self, mock_console, mock_exit):
        """Test validation_error convenience function."""
        validation_error("port", "99999", "1024-65535")

        mock_exit.assert_called_once_with(161)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_operation_cancelled_function(self, mock_console, mock_exit):
        """Test operation_cancelled convenience function."""
        operation_cancelled()

        mock_exit.assert_called_once_with(194)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_operation_timeout_function(self, mock_console, mock_exit):
        """Test operation_timeout convenience function."""
        operation_timeout("Database connection", 30.0)

        mock_exit.assert_called_once_with(195)


class TestHandleCliErrors:
    """Test handle_cli_errors context manager."""

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_cli_errors_success(self, mock_console, mock_exit):
        """Test handle_cli_errors with successful operation."""
        with handle_cli_errors("Test operation"):
            # Should not raise any exception
            pass

        # Should not call exit
        mock_exit.assert_not_called()

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_cli_errors_keyboard_interrupt(self, mock_console, mock_exit):
        """Test handle_cli_errors with KeyboardInterrupt."""
        with handle_cli_errors("Test operation"):
            raise KeyboardInterrupt()

        mock_exit.assert_called_once_with(130)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_cli_errors_file_not_found(self, mock_console, mock_exit):
        """Test handle_cli_errors with FileNotFoundError."""
        with handle_cli_errors("Test operation"):
            raise FileNotFoundError("File not found")

        mock_exit.assert_called_once_with(14)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_cli_errors_vpn_error(self, mock_console, mock_exit):
        """Test handle_cli_errors with VPNError."""
        with handle_cli_errors("Test operation"):
            raise VPNError("USER_ERROR", "User operation failed")

        mock_exit.assert_called_once_with(97)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_cli_errors_with_details(self, mock_console, mock_exit):
        """Test handle_cli_errors with show_details=True."""
        with handle_cli_errors("Test operation", show_details=True):
            raise ValueError("Invalid value")

        # Should show details
        mock_console.print.assert_called()
        mock_exit.assert_called_once_with(161)


class TestExitCodeDocumentation:
    """Test exit code documentation functionality."""

    def test_get_exit_code_documentation(self):
        """Test getting exit code documentation."""
        docs = get_exit_code_documentation()

        assert isinstance(docs, dict)
        assert "Success" in docs
        assert "General Errors" in docs
        assert "User Management Errors" in docs

        # Check structure
        success_codes = docs["Success"]
        assert len(success_codes) == 1
        assert success_codes[0]["code"] == 0
        assert success_codes[0]["name"] == "SUCCESS"

    @patch('vpn.cli.exit_codes.console')
    def test_show_exit_codes_help(self, mock_console):
        """Test showing exit codes help."""
        from vpn.cli.exit_codes import show_exit_codes_help

        show_exit_codes_help()

        # Should print multiple times (tables and panels)
        assert mock_console.print.call_count > 5


class TestDecorators:
    """Test exit code decorators."""

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_user_errors_decorator(self, mock_console, mock_exit):
        """Test handle_user_errors decorator."""
        from vpn.cli.exit_codes import handle_user_errors

        @handle_user_errors
        def failing_user_operation():
            raise ValueError("User validation failed")

        failing_user_operation()

        mock_exit.assert_called_once_with(97)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_server_errors_decorator(self, mock_console, mock_exit):
        """Test handle_server_errors decorator."""
        from vpn.cli.exit_codes import handle_server_errors

        @handle_server_errors
        def failing_server_operation():
            raise ConnectionError("Server unreachable")

        failing_server_operation()

        mock_exit.assert_called_once_with(113)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    def test_handle_config_errors_decorator(self, mock_console, mock_exit):
        """Test handle_config_errors decorator."""
        from vpn.cli.exit_codes import handle_config_errors

        @handle_config_errors
        def failing_config_operation():
            raise FileNotFoundError("Config file missing")

        failing_config_operation()

        mock_exit.assert_called_once_with(33)


class TestExitCodeIntegration:
    """Test exit code integration with CLI."""

    def test_global_exit_manager(self):
        """Test global exit manager instance."""

        assert isinstance(exit_manager, ExitCodeManager)
        assert exit_manager.get_description(ExitCode.SUCCESS)

    @patch('signal.signal')
    def test_setup_exit_codes_for_cli(self, mock_signal):
        """Test setting up exit codes for CLI."""
        from vpn.cli.exit_codes import setup_exit_codes_for_cli

        setup_exit_codes_for_cli()

        # Should set up signal handlers
        assert mock_signal.call_count >= 2


@pytest.mark.asyncio
class TestAsyncExitFunctions:
    """Test async exit functions."""

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    async def test_async_success(self, mock_console, mock_exit):
        """Test async success function."""
        from vpn.cli.exit_codes import async_success

        await async_success("Async operation completed")

        mock_console.print.assert_called_once()
        mock_exit.assert_called_once_with(0)

    @patch('typer.Exit')
    @patch('vpn.cli.exit_codes.console')
    async def test_async_error(self, mock_console, mock_exit):
        """Test async error function."""
        from vpn.cli.exit_codes import async_error

        await async_error(ExitCode.NETWORK_ERROR, "Connection failed")

        mock_console.print.assert_called()
        mock_exit.assert_called_once_with(65)


class TestExitCodeEdgeCases:
    """Test edge cases for exit codes."""

    def test_exit_result_with_none_details(self):
        """Test ExitResult with None details."""
        result = ExitResult(ExitCode.SUCCESS, details=None)
        assert result.details is None

    def test_exit_manager_empty_message(self):
        """Test exit manager with empty message."""
        manager = ExitCodeManager()
        result = manager.create_result(ExitCode.SUCCESS, "")
        assert result.message  # Should get default description

    def test_exit_manager_unknown_code_description(self):
        """Test getting description for unknown code."""
        manager = ExitCodeManager()
        # Create a fake enum value
        fake_code = type('FakeCode', (), {'value': 999})()
        description = manager.get_description(fake_code)
        assert "Unknown error" in description
        assert "999" in description

    def test_exit_manager_no_suggestion(self):
        """Test getting suggestion for code without suggestion."""
        manager = ExitCodeManager()
        # Use a code that doesn't have a suggestion
        suggestion = manager.get_suggestion(ExitCode.MISUSE_OF_SHELL_BUILTINS)
        assert suggestion == ""


if __name__ == "__main__":
    pytest.main([__file__])
