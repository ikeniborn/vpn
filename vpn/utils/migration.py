"""Migration utilities for migrating from Rust VPN Manager to Python version.
"""

import json
import shutil
import subprocess
from pathlib import Path

import toml
from rich.console import Console
from rich.progress import track

from vpn.core.config import settings
from vpn.core.models import ProtocolConfig, ProtocolType, User, UserStatus
from vpn.services.user_manager import UserManager
from vpn.utils.logger import get_logger

logger = get_logger(__name__)
console = Console()


class RustMigrator:
    """Handles migration from Rust VPN Manager."""

    def __init__(self, rust_path: Path | None = None):
        self.rust_path = rust_path or Path("/opt/vpn") / "users"
        self.backup_path = settings.data_path / "migration_backup"
        self.user_manager = None

    async def migrate_from_rust(self, backup: bool = True) -> tuple[int, list[str]]:
        """Migrate users and configuration from Rust version.
        
        Returns:
            Tuple of (migrated_count, error_messages)
        """
        errors = []
        migrated_count = 0

        try:
            # Initialize user manager
            self.user_manager = UserManager()

            # Create backup if requested
            if backup:
                await self._create_backup()

            # Find Rust installation
            rust_locations = await self._find_rust_installation()
            if not rust_locations:
                errors.append("No Rust VPN Manager installation found")
                return 0, errors

            console.print(f"[green]Found Rust installation at: {rust_locations[0]}[/green]")
            self.rust_path = rust_locations[0]

            # Migrate configuration
            config_migrated = await self._migrate_configuration()
            if not config_migrated:
                errors.append("Failed to migrate configuration")

            # Migrate users
            users = await self._discover_rust_users()
            if not users:
                errors.append("No users found in Rust installation")
                return 0, errors

            console.print(f"[blue]Found {len(users)} users to migrate[/blue]")

            for user_data in track(users, description="Migrating users..."):
                try:
                    migrated_user = await self._migrate_user(user_data)
                    if migrated_user:
                        migrated_count += 1
                except Exception as e:
                    error_msg = f"Failed to migrate user {user_data.get('username', 'unknown')}: {e}"
                    errors.append(error_msg)
                    logger.error(error_msg)

            # Migrate server configuration
            await self._migrate_server_config()

            console.print(f"[green]Migration completed: {migrated_count} users migrated[/green]")

        except Exception as e:
            error_msg = f"Migration failed: {e}"
            errors.append(error_msg)
            logger.exception("Migration error")

        return migrated_count, errors

    async def _create_backup(self):
        """Create backup of current Python installation."""
        if settings.data_path.exists():
            backup_dir = self.backup_path / f"python_backup_{int(__import__('time').time())}"
            backup_dir.mkdir(parents=True, exist_ok=True)

            shutil.copytree(settings.data_path, backup_dir / "data", dirs_exist_ok=True)
            if settings.config_path.exists():
                shutil.copytree(settings.config_path, backup_dir / "config", dirs_exist_ok=True)

            console.print(f"[blue]Created backup at: {backup_dir}[/blue]")

    async def _find_rust_installation(self) -> list[Path]:
        """Find Rust VPN Manager installations."""
        possible_locations = [
            Path("/opt/vpn"),
            Path("/usr/local/vpn"),
            Path.home() / ".vpn",
            Path.home() / ".local" / "share" / "vpn",
            Path("/etc/vpn"),
        ]

        found_locations = []

        for location in possible_locations:
            if (location / "users").exists() or (location / "config.toml").exists():
                found_locations.append(location)

        # Also check if vpn binary exists and ask for its location
        vpn_binary = shutil.which("vpn")
        if vpn_binary:
            try:
                result = subprocess.run(
                    [vpn_binary, "--version"],
                    check=False, capture_output=True,
                    text=True,
                    timeout=5
                )
                if "rust" in result.stdout.lower():
                    # Try to get installation path from binary
                    binary_path = Path(vpn_binary).parent.parent
                    if (binary_path / "users").exists():
                        found_locations.append(binary_path)
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
                pass

        return found_locations

    async def _migrate_configuration(self) -> bool:
        """Migrate configuration from Rust to Python format."""
        try:
            rust_config_path = self.rust_path / "config.toml"
            if not rust_config_path.exists():
                return True  # No config to migrate

            with open(rust_config_path) as f:
                rust_config = toml.load(f)

            # Convert Rust config to Python format
            python_config = self._convert_rust_config(rust_config)

            # Save to Python config location
            python_config_path = settings.config_path / "config.toml"
            python_config_path.parent.mkdir(parents=True, exist_ok=True)

            with open(python_config_path, 'w') as f:
                toml.dump(python_config, f)

            console.print("[green]Configuration migrated successfully[/green]")
            return True

        except Exception as e:
            logger.error(f"Configuration migration failed: {e}")
            return False

    def _convert_rust_config(self, rust_config: dict) -> dict:
        """Convert Rust configuration format to Python format."""
        # Map Rust config keys to Python keys
        python_config = {
            "vpn": {
                "install_path": rust_config.get("install_path", "/opt/vpn"),
                "data_path": rust_config.get("data_path", "/var/lib/vpn"),
                "log_level": rust_config.get("log_level", "INFO"),
            },
            "server": {
                "default_protocol": rust_config.get("default_protocol", "vless"),
                "default_port": rust_config.get("default_port", 8443),
            },
            "database": {
                "url": "sqlite+aiosqlite:///db/vpn.db",
            }
        }

        # Migrate server-specific settings
        if "server" in rust_config:
            server_config = rust_config["server"]
            python_config["server"].update({
                "domain": server_config.get("domain"),
                "certificate_path": server_config.get("certificate_path"),
                "private_key_path": server_config.get("private_key_path"),
            })

        return python_config

    async def _discover_rust_users(self) -> list[dict]:
        """Discover users from Rust installation."""
        users_dir = self.rust_path / "users"
        if not users_dir.exists():
            return []

        users = []

        for user_dir in users_dir.iterdir():
            if not user_dir.is_dir():
                continue

            config_file = user_dir / "config.json"
            if not config_file.exists():
                continue

            try:
                with open(config_file) as f:
                    user_data = json.load(f)

                # Add directory name as fallback username
                if "username" not in user_data:
                    user_data["username"] = user_dir.name

                users.append(user_data)

            except Exception as e:
                logger.warning(f"Failed to read user config {config_file}: {e}")

        return users

    async def _migrate_user(self, rust_user_data: dict) -> User | None:
        """Migrate a single user from Rust format to Python format."""
        try:
            # Extract user information
            username = rust_user_data.get("username")
            if not username:
                raise ValueError("Username not found in user data")

            # Convert protocol configuration
            protocol_config = self._convert_protocol_config(rust_user_data)

            # Create user with Python UserManager
            user = await self.user_manager.create(
                username=username,
                protocol=protocol_config.protocol,
                email=rust_user_data.get("email"),
                **self._extract_protocol_params(rust_user_data)
            )

            # Migrate additional user data
            if "status" in rust_user_data:
                user.status = UserStatus(rust_user_data["status"])

            # Migrate traffic statistics if available
            if "traffic" in rust_user_data:
                traffic_data = rust_user_data["traffic"]
                user.traffic.upload_bytes = traffic_data.get("upload_bytes", 0)
                user.traffic.download_bytes = traffic_data.get("download_bytes", 0)
                user.traffic.total_sessions = traffic_data.get("total_sessions", 0)

            # Save migrated user
            await self.user_manager.update(user.id, user.model_dump())

            return user

        except Exception as e:
            logger.error(f"Failed to migrate user {rust_user_data.get('username')}: {e}")
            raise

    def _convert_protocol_config(self, rust_user_data: dict) -> ProtocolConfig:
        """Convert Rust protocol configuration to Python format."""
        protocol_name = rust_user_data.get("protocol", "vless").lower()

        # Map Rust protocol names to Python enums
        protocol_mapping = {
            "vless": ProtocolType.VLESS,
            "shadowsocks": ProtocolType.SHADOWSOCKS,
            "outline": ProtocolType.SHADOWSOCKS,  # Outline is Shadowsocks
            "wireguard": ProtocolType.WIREGUARD,
        }

        protocol_type = protocol_mapping.get(protocol_name, ProtocolType.VLESS)

        # Extract protocol-specific configuration
        config_data = {}

        if protocol_type == ProtocolType.VLESS:
            config_data = {
                "port": rust_user_data.get("port", 8443),
                "domain": rust_user_data.get("domain"),
                "public_key": rust_user_data.get("keys", {}).get("public_key"),
                "private_key": rust_user_data.get("keys", {}).get("private_key"),
            }
        elif protocol_type == ProtocolType.SHADOWSOCKS:
            config_data = {
                "port": rust_user_data.get("port", 8388),
                "password": rust_user_data.get("password"),
                "method": rust_user_data.get("method", "chacha20-ietf-poly1305"),
            }
        elif protocol_type == ProtocolType.WIREGUARD:
            config_data = {
                "port": rust_user_data.get("port", 51820),
                "private_key": rust_user_data.get("keys", {}).get("private_key"),
                "public_key": rust_user_data.get("keys", {}).get("public_key"),
                "endpoint": rust_user_data.get("endpoint"),
            }

        return ProtocolConfig(protocol=protocol_type, config=config_data)

    def _extract_protocol_params(self, rust_user_data: dict) -> dict:
        """Extract protocol-specific parameters for user creation."""
        params = {}

        if "port" in rust_user_data:
            params["port"] = rust_user_data["port"]

        if "domain" in rust_user_data:
            params["domain"] = rust_user_data["domain"]

        if "password" in rust_user_data:
            params["password"] = rust_user_data["password"]

        return params

    async def _migrate_server_config(self):
        """Migrate server configuration and Docker containers."""
        try:
            # Check if Rust containers are running
            result = subprocess.run(
                ["docker", "ps", "--filter", "label=vpn-manager=rust", "--format", "{{.Names}}"],
                check=False, capture_output=True,
                text=True
            )

            if result.returncode == 0 and result.stdout.strip():
                containers = result.stdout.strip().split('\n')
                console.print(f"[yellow]Found {len(containers)} Rust containers running[/yellow]")
                console.print("[dim]Consider stopping them: docker stop " + " ".join(containers) + "[/dim]")

        except subprocess.CalledProcessError:
            pass  # Docker not available or no containers found


async def migrate_from_rust(
    rust_path: Path | None = None,
    backup: bool = True,
    dry_run: bool = False
) -> tuple[int, list[str]]:
    """Main migration function.
    
    Args:
        rust_path: Path to Rust VPN Manager installation
        backup: Whether to create backup before migration
        dry_run: Only analyze what would be migrated
    
    Returns:
        Tuple of (migrated_count, error_messages)
    """
    migrator = RustMigrator(rust_path)

    if dry_run:
        console.print("[blue]DRY RUN: Analyzing Rust installation...[/blue]")
        # TODO: Implement dry run analysis
        return 0, ["Dry run not implemented yet"]

    return await migrator.migrate_from_rust(backup=backup)
