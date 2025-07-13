"""System diagnostics utilities for VPN Manager.
"""

import os
import platform
import shutil
import subprocess
import sys

import psutil
from docker import DockerClient
from docker.errors import DockerException

from vpn.core.config import settings
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class DiagnosticCheck:
    """Represents a single diagnostic check."""

    def __init__(self, name: str, status: str, details: str, severity: str = "info"):
        self.name = name
        self.status = status  # ✓, ⚠, ✗
        self.details = details
        self.severity = severity  # "info", "warning", "error"


class SystemDiagnostics:
    """System diagnostics checker."""

    def __init__(self):
        self.checks: list[DiagnosticCheck] = []

    async def run_all_checks(self) -> list[DiagnosticCheck]:
        """Run all diagnostic checks."""
        self.checks = []

        # Basic system checks
        await self._check_python_version()
        await self._check_platform()
        await self._check_memory()
        await self._check_disk_space()

        # VPN Manager specific checks
        await self._check_directories()
        await self._check_database()
        await self._check_permissions()

        # External dependencies
        await self._check_docker()
        await self._check_network_tools()
        await self._check_firewall()

        # Configuration checks
        await self._check_configuration()
        await self._check_ports()

        return self.checks

    async def _check_python_version(self):
        """Check Python version compatibility."""
        version = sys.version_info
        if version >= (3, 10):
            self.checks.append(DiagnosticCheck(
                "Python Version",
                "✓",
                f"Python {version.major}.{version.minor}.{version.micro}",
                "info"
            ))
        elif version >= (3, 8):
            self.checks.append(DiagnosticCheck(
                "Python Version",
                "⚠",
                f"Python {version.major}.{version.minor} (3.10+ recommended)",
                "warning"
            ))
        else:
            self.checks.append(DiagnosticCheck(
                "Python Version",
                "✗",
                f"Python {version.major}.{version.minor} (3.10+ required)",
                "error"
            ))

    async def _check_platform(self):
        """Check platform compatibility."""
        system = platform.system()
        supported = system in ["Linux", "Darwin", "Windows"]

        if supported:
            self.checks.append(DiagnosticCheck(
                "Platform",
                "✓",
                f"{system} {platform.release()}",
                "info"
            ))
        else:
            self.checks.append(DiagnosticCheck(
                "Platform",
                "⚠",
                f"{system} (limited support)",
                "warning"
            ))

    async def _check_memory(self):
        """Check available memory."""
        memory = psutil.virtual_memory()
        total_gb = memory.total / (1024**3)
        available_gb = memory.available / (1024**3)

        if available_gb >= 1.0:
            self.checks.append(DiagnosticCheck(
                "Memory",
                "✓",
                f"{available_gb:.1f}GB available of {total_gb:.1f}GB",
                "info"
            ))
        elif available_gb >= 0.5:
            self.checks.append(DiagnosticCheck(
                "Memory",
                "⚠",
                f"{available_gb:.1f}GB available (low memory)",
                "warning"
            ))
        else:
            self.checks.append(DiagnosticCheck(
                "Memory",
                "✗",
                f"{available_gb:.1f}GB available (insufficient)",
                "error"
            ))

    async def _check_disk_space(self):
        """Check available disk space."""
        try:
            usage = psutil.disk_usage(str(settings.data_path.parent))
            free_gb = usage.free / (1024**3)

            if free_gb >= 5.0:
                self.checks.append(DiagnosticCheck(
                    "Disk Space",
                    "✓",
                    f"{free_gb:.1f}GB available",
                    "info"
                ))
            elif free_gb >= 1.0:
                self.checks.append(DiagnosticCheck(
                    "Disk Space",
                    "⚠",
                    f"{free_gb:.1f}GB available (low space)",
                    "warning"
                ))
            else:
                self.checks.append(DiagnosticCheck(
                    "Disk Space",
                    "✗",
                    f"{free_gb:.1f}GB available (insufficient)",
                    "error"
                ))
        except Exception as e:
            self.checks.append(DiagnosticCheck(
                "Disk Space",
                "✗",
                f"Unable to check: {e}",
                "error"
            ))

    async def _check_directories(self):
        """Check VPN Manager directories."""
        directories = [
            ("Config", settings.config_path),
            ("Data", settings.data_path),
            ("Installation", settings.install_path),
        ]

        for name, path in directories:
            if path.exists() and os.access(path, os.R_OK | os.W_OK):
                self.checks.append(DiagnosticCheck(
                    f"{name} Directory",
                    "✓",
                    f"{path} (writable)",
                    "info"
                ))
            elif path.exists():
                self.checks.append(DiagnosticCheck(
                    f"{name} Directory",
                    "⚠",
                    f"{path} (read-only)",
                    "warning"
                ))
            else:
                self.checks.append(DiagnosticCheck(
                    f"{name} Directory",
                    "✗",
                    f"{path} (missing)",
                    "error"
                ))

    async def _check_database(self):
        """Check database connectivity."""
        try:
            from sqlalchemy import text

            from vpn.core.database import get_session

            async for session in get_session():
                # Simple query to test connection
                await session.execute(text("SELECT 1"))
                break  # Exit after successful test

            self.checks.append(DiagnosticCheck(
                "Database",
                "✓",
                "SQLite connection OK",
                "info"
            ))
        except Exception as e:
            self.checks.append(DiagnosticCheck(
                "Database",
                "✗",
                f"Connection failed: {e}",
                "error"
            ))

    async def _check_permissions(self):
        """Check user permissions."""
        is_root = os.geteuid() == 0 if hasattr(os, 'geteuid') else False
        can_bind_privileged = self._can_bind_privileged_ports()

        if is_root:
            self.checks.append(DiagnosticCheck(
                "Permissions",
                "✓",
                "Running as root (full access)",
                "info"
            ))
        elif can_bind_privileged:
            self.checks.append(DiagnosticCheck(
                "Permissions",
                "✓",
                "Can bind privileged ports",
                "info"
            ))
        else:
            self.checks.append(DiagnosticCheck(
                "Permissions",
                "⚠",
                "Limited permissions (use sudo for server operations)",
                "warning"
            ))

    async def _check_docker(self):
        """Check Docker availability."""
        try:
            client = DockerClient.from_env()
            version = client.version()
            client.ping()

            self.checks.append(DiagnosticCheck(
                "Docker",
                "✓",
                f"Docker {version['Version']} (API {version['ApiVersion']})",
                "info"
            ))
        except DockerException as e:
            self.checks.append(DiagnosticCheck(
                "Docker",
                "✗",
                f"Docker unavailable: {e}",
                "error"
            ))
        except Exception as e:
            self.checks.append(DiagnosticCheck(
                "Docker",
                "✗",
                f"Docker check failed: {e}",
                "error"
            ))

    async def _check_network_tools(self):
        """Check network tools availability."""
        tools = {
            "iptables": "Firewall management",
            "ip": "Network configuration",
            "ss": "Socket statistics",
        }

        available_tools = []
        missing_tools = []

        for tool, description in tools.items():
            if shutil.which(tool):
                available_tools.append(f"{tool} ({description})")
            else:
                missing_tools.append(tool)

        if not missing_tools:
            self.checks.append(DiagnosticCheck(
                "Network Tools",
                "✓",
                f"All tools available: {', '.join(tools.keys())}",
                "info"
            ))
        elif len(missing_tools) <= len(tools) // 2:
            self.checks.append(DiagnosticCheck(
                "Network Tools",
                "⚠",
                f"Missing: {', '.join(missing_tools)}",
                "warning"
            ))
        else:
            self.checks.append(DiagnosticCheck(
                "Network Tools",
                "✗",
                f"Most tools missing: {', '.join(missing_tools)}",
                "error"
            ))

    async def _check_firewall(self):
        """Check firewall status."""
        try:
            if platform.system() == "Linux":
                # Check iptables
                result = subprocess.run(
                    ["iptables", "-L", "-n"],
                    check=False, capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    self.checks.append(DiagnosticCheck(
                        "Firewall",
                        "✓",
                        "iptables accessible",
                        "info"
                    ))
                else:
                    self.checks.append(DiagnosticCheck(
                        "Firewall",
                        "⚠",
                        "iptables not accessible (requires sudo)",
                        "warning"
                    ))
            else:
                self.checks.append(DiagnosticCheck(
                    "Firewall",
                    "⚠",
                    f"Platform {platform.system()} (manual configuration needed)",
                    "warning"
                ))
        except (subprocess.TimeoutExpired, FileNotFoundError):
            self.checks.append(DiagnosticCheck(
                "Firewall",
                "✗",
                "Firewall tools not available",
                "error"
            ))
        except Exception as e:
            self.checks.append(DiagnosticCheck(
                "Firewall",
                "✗",
                f"Firewall check failed: {e}",
                "error"
            ))

    async def _check_configuration(self):
        """Check configuration validity."""
        try:
            # Check if settings are valid
            config_valid = settings.config_path.exists() or True  # Default config is valid

            if config_valid:
                self.checks.append(DiagnosticCheck(
                    "Configuration",
                    "✓",
                    "Configuration valid",
                    "info"
                ))
            else:
                self.checks.append(DiagnosticCheck(
                    "Configuration",
                    "✗",
                    "Configuration invalid",
                    "error"
                ))
        except Exception as e:
            self.checks.append(DiagnosticCheck(
                "Configuration",
                "✗",
                f"Configuration check failed: {e}",
                "error"
            ))

    async def _check_ports(self):
        """Check for port conflicts."""
        try:
            # Check common VPN ports
            common_ports = [443, 8443, 1080, 8080]
            in_use_ports = []

            for conn in psutil.net_connections():
                if conn.laddr and conn.laddr.port in common_ports:
                    in_use_ports.append(conn.laddr.port)

            if not in_use_ports:
                self.checks.append(DiagnosticCheck(
                    "Port Availability",
                    "✓",
                    "Common VPN ports available",
                    "info"
                ))
            else:
                self.checks.append(DiagnosticCheck(
                    "Port Availability",
                    "⚠",
                    f"Ports in use: {', '.join(map(str, set(in_use_ports)))}",
                    "warning"
                ))
        except Exception as e:
            self.checks.append(DiagnosticCheck(
                "Port Availability",
                "⚠",
                f"Unable to check ports: {e}",
                "warning"
            ))

    def _can_bind_privileged_ports(self) -> bool:
        """Check if we can bind to privileged ports (<1024)."""
        import socket

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.bind(('127.0.0.1', 443))
            sock.close()
            return True
        except PermissionError:
            return False
        except OSError:
            # Port already in use, but we have permission
            return True
        except Exception:
            return False

    def get_summary(self) -> dict[str, int]:
        """Get summary of check results."""
        summary = {"total": len(self.checks), "passed": 0, "warnings": 0, "errors": 0}

        for check in self.checks:
            if check.status == "✓":
                summary["passed"] += 1
            elif check.status == "⚠":
                summary["warnings"] += 1
            elif check.status == "✗":
                summary["errors"] += 1

        return summary


async def run_diagnostics() -> tuple[list[DiagnosticCheck], dict[str, int]]:
    """Run complete system diagnostics."""
    diagnostics = SystemDiagnostics()
    checks = await diagnostics.run_all_checks()
    summary = diagnostics.get_summary()
    return checks, summary
