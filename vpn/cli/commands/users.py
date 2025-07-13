"""User management CLI commands.
"""

from pathlib import Path

import typer
from rich.console import Console
from rich.prompt import Confirm

from vpn.cli.formatters.base import get_formatter
from vpn.core.exceptions import UserAlreadyExistsError, VPNError
from vpn.core.models import ProtocolType, UserStatus
from vpn.services.user_manager import UserManager
from vpn.utils.logger import get_logger
from vpn.utils.qr_display import display_connection_qr

app = typer.Typer(help="User management commands")
console = Console()
logger = get_logger(__name__)


def run_async(coro):
    """Run async coroutine."""
    import asyncio
    return asyncio.run(coro)


@app.command("list")
def list_users(
    status: str | None = typer.Option(
        None,
        "--status",
        "-s",
        help="Filter by status: active, inactive, suspended",
    ),
    limit: int | None = typer.Option(
        None,
        "--limit",
        "-l",
        help="Limit number of results",
    ),
    format: str | None = typer.Option(
        None,
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
):
    """List all VPN users."""
    try:
        formatter = get_formatter(format)

        async def _list():
            manager = UserManager()
            status_filter = UserStatus(status) if status else None
            users = await manager.list(status=status_filter, limit=limit)

            if not users:
                console.print(formatter.format_warning("No users found"))
                return

            # Prepare data for display
            user_data = []
            for user in users:
                user_data.append({
                    "username": user.username,
                    "status": user.status.value,
                    "protocol": user.protocol.type.value,
                    "email": user.email or "-",
                    "traffic": {
                        "total_mb": user.traffic.total_mb,
                        "upload_mb": user.traffic.upload_mb,
                        "download_mb": user.traffic.download_mb,
                    },
                    "created": user.created_at.strftime("%Y-%m-%d %H:%M"),
                })

            # Format output
            output = formatter.format_list(
                user_data,
                columns=["username", "status", "protocol", "email", "traffic", "created"],
                title="VPN Users"
            )
            console.print(output)

        run_async(_list())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("create")
def create_user(
    username: str = typer.Argument(..., help="Username for the new user"),
    protocol: str = typer.Option(
        "vless",
        "--protocol",
        "-p",
        help="VPN protocol: vless, shadowsocks, wireguard, http, socks5",
    ),
    email: str | None = typer.Option(
        None,
        "--email",
        "-e",
        help="User email address",
    ),
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Skip confirmation prompts",
    ),
    format: str | None = typer.Option(
        None,
        "--format",
        help="Output format: table, json, yaml, plain",
    ),
):
    """Create a new VPN user."""
    try:
        formatter = get_formatter(format)

        # Validate protocol
        try:
            protocol_type = ProtocolType(protocol)
        except ValueError:
            valid_protocols = ", ".join([p.value for p in ProtocolType])
            console.print(formatter.format_error(
                f"Invalid protocol: {protocol}",
                {"valid_protocols": valid_protocols}
            ))
            raise typer.Exit(1)

        # Confirm creation
        if not force:
            if not Confirm.ask(
                f"Create user '{username}' with protocol '{protocol}'?",
                default=True
            ):
                console.print("Operation cancelled")
                raise typer.Exit(0)

        async def _create():
            manager = UserManager()

            with console.status(f"Creating user '{username}'..."):
                try:
                    user = await manager.create(
                        username=username,
                        protocol=protocol_type,
                        email=email
                    )

                    # Display created user
                    user_data = {
                        "id": str(user.id),
                        "username": user.username,
                        "protocol": user.protocol.type.value,
                        "email": user.email or "Not set",
                        "status": user.status.value,
                        "uuid": user.keys.uuid,
                        "created_at": user.created_at.isoformat(),
                    }

                    output = formatter.format_single(
                        user_data,
                        title=f"User Created: {username}"
                    )
                    console.print(output)
                    console.print(formatter.format_success(f"User '{username}' created successfully"))

                except UserAlreadyExistsError:
                    console.print(formatter.format_error(f"User '{username}' already exists"))
                    raise typer.Exit(1)

        run_async(_create())

    except VPNError as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("delete")
def delete_user(
    username: str = typer.Argument(..., help="Username to delete"),
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Skip confirmation prompt",
    ),
):
    """Delete a VPN user."""
    try:
        formatter = get_formatter()

        # Confirm deletion
        if not force:
            if not Confirm.ask(
                f"[red]Delete user '{username}'? This action cannot be undone.[/red]",
                default=False
            ):
                console.print("Operation cancelled")
                raise typer.Exit(0)

        async def _delete():
            manager = UserManager()

            # Get user first
            user = await manager.get_by_username(username)
            if not user:
                console.print(formatter.format_error(f"User '{username}' not found"))
                raise typer.Exit(1)

            # Delete user
            with console.status(f"Deleting user '{username}'..."):
                deleted = await manager.delete(str(user.id))

                if deleted:
                    console.print(formatter.format_success(f"User '{username}' deleted successfully"))
                else:
                    console.print(formatter.format_error(f"Failed to delete user '{username}'"))
                    raise typer.Exit(1)

        run_async(_delete())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("show")
def show_user(
    username: str = typer.Argument(..., help="Username to display"),
    show_keys: bool = typer.Option(
        False,
        "--show-keys",
        "-k",
        help="Show sensitive key information",
    ),
    format: str | None = typer.Option(
        None,
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
):
    """Show detailed information for a user."""
    try:
        formatter = get_formatter(format)

        async def _show():
            manager = UserManager()

            user = await manager.get_by_username(username)
            if not user:
                console.print(formatter.format_error(f"User '{username}' not found"))
                raise typer.Exit(1)

            # Prepare user data
            user_data = {
                "id": str(user.id),
                "username": user.username,
                "email": user.email or "Not set",
                "status": user.status.value,
                "protocol": user.protocol.type.value,
                "created_at": user.created_at.isoformat(),
                "updated_at": user.updated_at.isoformat() if user.updated_at else "Never",
                "expires_at": user.expires_at.isoformat() if user.expires_at else "Never",
                "is_active": user.is_active,
                "traffic_upload_mb": f"{user.traffic.upload_mb:.2f}",
                "traffic_download_mb": f"{user.traffic.download_mb:.2f}",
                "traffic_total_mb": f"{user.traffic.total_mb:.2f}",
            }

            # Add keys if requested
            if show_keys:
                user_data.update({
                    "uuid": user.keys.uuid,
                    "public_key": user.keys.public_key or "Not set",
                    "short_id": user.keys.short_id or "Not set",
                })

            output = formatter.format_single(
                user_data,
                title=f"User Details: {username}"
            )
            console.print(output)

        run_async(_show())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("update")
def update_user(
    username: str = typer.Argument(..., help="Username to update"),
    status: str | None = typer.Option(
        None,
        "--status",
        "-s",
        help="New status: active, inactive, suspended",
    ),
    email: str | None = typer.Option(
        None,
        "--email",
        "-e",
        help="New email address",
    ),
    notes: str | None = typer.Option(
        None,
        "--notes",
        "-n",
        help="Update user notes",
    ),
):
    """Update user information."""
    try:
        formatter = get_formatter()

        # Check if any updates provided
        if not any([status, email, notes]):
            console.print(formatter.format_error("No updates specified"))
            raise typer.Exit(1)

        async def _update():
            manager = UserManager()

            # Get user
            user = await manager.get_by_username(username)
            if not user:
                console.print(formatter.format_error(f"User '{username}' not found"))
                raise typer.Exit(1)

            # Prepare updates
            updates = {}
            if status:
                try:
                    updates["status"] = UserStatus(status)
                except ValueError:
                    console.print(formatter.format_error(f"Invalid status: {status}"))
                    raise typer.Exit(1)

            if email is not None:
                updates["email"] = email if email != "none" else None

            if notes is not None:
                updates["notes"] = notes

            # Update user
            with console.status(f"Updating user '{username}'..."):
                updated_user = await manager.update(str(user.id), **updates)

                if updated_user:
                    console.print(formatter.format_success(f"User '{username}' updated successfully"))
                else:
                    console.print(formatter.format_error(f"Failed to update user '{username}'"))
                    raise typer.Exit(1)

        run_async(_update())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("reset-traffic")
def reset_traffic(
    username: str = typer.Argument(..., help="Username to reset traffic for"),
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Skip confirmation prompt",
    ),
):
    """Reset user traffic statistics."""
    try:
        formatter = get_formatter()

        # Confirm reset
        if not force:
            if not Confirm.ask(
                f"Reset traffic statistics for user '{username}'?",
                default=True
            ):
                console.print("Operation cancelled")
                raise typer.Exit(0)

        async def _reset():
            manager = UserManager()

            # Get user
            user = await manager.get_by_username(username)
            if not user:
                console.print(formatter.format_error(f"User '{username}' not found"))
                raise typer.Exit(1)

            # Reset traffic
            with console.status(f"Resetting traffic for '{username}'..."):
                updated_user = await manager.reset_traffic(str(user.id))

                if updated_user:
                    console.print(formatter.format_success(
                        f"Traffic statistics reset for user '{username}'"
                    ))
                else:
                    console.print(formatter.format_error(
                        f"Failed to reset traffic for user '{username}'"
                    ))
                    raise typer.Exit(1)

        run_async(_reset())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("export")
def export_users(
    output: Path = typer.Option(
        None,
        "--output",
        "-o",
        help="Output file path (default: stdout)",
    ),
    format: str = typer.Option(
        "json",
        "--format",
        "-f",
        help="Export format: json, csv",
    ),
    include_keys: bool = typer.Option(
        False,
        "--include-keys",
        "-k",
        help="Include sensitive key data",
    ),
):
    """Export all users to file."""
    try:
        formatter = get_formatter()

        async def _export():
            manager = UserManager()

            with console.status("Exporting users..."):
                data = await manager.export_users(
                    format=format,
                    include_keys=include_keys
                )

                if output:
                    output.write_text(data)
                    console.print(formatter.format_success(
                        f"Users exported to {output}"
                    ))
                else:
                    console.print(data)

        run_async(_export())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("import")
def import_users(
    input_file: Path = typer.Argument(
        ...,
        help="Input file path",
        exists=True,
    ),
    format: str = typer.Option(
        "json",
        "--format",
        "-f",
        help="Import format: json, csv",
    ),
    skip_existing: bool = typer.Option(
        True,
        "--skip-existing/--overwrite",
        help="Skip existing users or overwrite",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show what would be imported without making changes",
    ),
):
    """Import users from file."""
    try:
        formatter = get_formatter()

        # Read input file
        data = input_file.read_text()

        async def _import():
            manager = UserManager()

            if dry_run:
                console.print(formatter.format_info("Dry run mode - no changes will be made"))

            with console.status("Importing users..."):
                if not dry_run:
                    stats = await manager.import_users(
                        data=data,
                        format=format,
                        skip_existing=skip_existing
                    )

                    console.print(formatter.format_success(
                        f"Import complete: {stats['imported']} imported, "
                        f"{stats['skipped']} skipped, {stats['failed']} failed"
                    ))
                else:
                    # For dry run, just parse and show what would be imported
                    import json
                    users = json.loads(data) if format == "json" else []
                    console.print(formatter.format_info(
                        f"Would import {len(users)} users"
                    ))

        run_async(_import())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("connection")
def show_connection(
    username: str = typer.Argument(..., help="Username to generate connection for"),
    server: str = typer.Option(
        "localhost",
        "--server",
        "-s",
        help="Server address or domain",
    ),
    port: int = typer.Option(
        8443,
        "--port",
        "-p",
        help="Server port",
    ),
    qr: bool = typer.Option(
        False,
        "--qr",
        "-q",
        help="Display QR code",
    ),
    format: str | None = typer.Option(
        None,
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
):
    """Generate connection information for a user."""
    try:
        formatter = get_formatter(format)

        async def _connection():
            manager = UserManager()

            # Get user
            user = await manager.get_by_username(username)
            if not user:
                console.print(formatter.format_error(f"User '{username}' not found"))
                raise typer.Exit(1)

            # Generate connection info
            with console.status("Generating connection information..."):
                conn_info = await manager.generate_connection_info(
                    user_id=str(user.id),
                    server_address=server,
                    server_port=port
                )

                # Prepare display data
                conn_data = {
                    "username": username,
                    "protocol": conn_info.protocol.value,
                    "server": conn_info.server_address,
                    "port": conn_info.server_port,
                    "link": conn_info.connection_link,
                    "instructions": conn_info.instructions,
                }

                output = formatter.format_single(
                    conn_data,
                    title=f"Connection Info: {username}"
                )
                console.print(output)

                # Display QR code if requested
                if qr and conn_info.qr_code:
                    if conn_info.qr_code.startswith("data:image"):
                        console.print(formatter.format_info(
                            "QR code generated (use web UI to view image)"
                        ))
                    else:
                        # ASCII QR code
                        console.print("\n[bold]QR Code:[/bold]")
                        console.print(conn_info.qr_code)

        run_async(_connection())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("qr")
def show_qr_code(
    username: str = typer.Argument(..., help="Username to generate QR code for"),
    server: str = typer.Option(
        "localhost",
        "--server",
        "-s",
        help="Server address or domain",
    ),
    port: int = typer.Option(
        8443,
        "--port",
        "-p",
        help="Server port",
    ),
    style: str = typer.Option(
        "unicode",
        "--style",
        help="QR code style: unicode, ascii",
    ),
    save: Path | None = typer.Option(
        None,
        "--save",
        help="Save QR code as image file",
    ),
):
    """Display QR code for user's VPN connection in terminal."""
    try:
        async def _show_qr():
            manager = UserManager()

            # Get user
            user = await manager.get_by_username(username)
            if not user:
                console.print(f"[red]User '{username}' not found[/red]")
                raise typer.Exit(1)

            # Generate connection info
            with console.status("Generating connection QR code..."):
                conn_info = await manager.generate_connection_info(
                    user_id=str(user.id),
                    server_address=server,
                    server_port=port
                )

                if not conn_info.connection_link:
                    console.print("[red]Failed to generate connection link[/red]")
                    raise typer.Exit(1)

                # Display QR code in terminal
                display_connection_qr(
                    connection_url=conn_info.connection_link,
                    username=username,
                    protocol=conn_info.protocol.value,
                    style=style,
                    console=console
                )

                # Save image if requested
                if save:
                    from vpn.utils.qr_display import TerminalQRCode
                    qr_display = TerminalQRCode(console)
                    success = qr_display.save_qr_image(
                        conn_info.connection_link,
                        str(save)
                    )
                    if success:
                        console.print(f"\n[green]✓ QR code image saved to: {save}[/green]")
                    else:
                        console.print("\n[red]✗ Failed to save QR code image[/red]")

        run_async(_show_qr())

    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)
