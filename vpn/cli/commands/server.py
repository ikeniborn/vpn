"""Server management CLI commands.
"""


import typer
from rich.console import Console
from rich.prompt import Confirm

from vpn.cli.formatters.base import get_formatter
from vpn.core.models import ProtocolType
from vpn.services.docker_manager import DockerManager
from vpn.services.network_manager import NetworkManager
from vpn.services.server_manager import ServerManager
from vpn.utils.logger import get_logger

app = typer.Typer(help="Server management commands")
console = Console()
logger = get_logger(__name__)


def run_async(coro):
    """Run async coroutine."""
    import asyncio
    return asyncio.run(coro)


@app.command("install")
def install_server(
    protocol: str = typer.Option(
        "vless",
        "--protocol",
        "-p",
        help="VPN protocol: vless, shadowsocks, wireguard",
    ),
    port: int | None = typer.Option(
        None,
        "--port",
        help="Server port (auto-detect if not specified)",
    ),
    name: str | None = typer.Option(
        None,
        "--name",
        "-n",
        help="Server name",
    ),
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Skip confirmation prompts",
    ),
):
    """Install a new VPN server."""
    try:
        formatter = get_formatter()

        # Validate protocol
        try:
            protocol_type = ProtocolType(protocol)
        except ValueError:
            valid_protocols = "vless, shadowsocks, wireguard"
            console.print(formatter.format_error(
                f"Invalid protocol: {protocol}",
                {"valid_protocols": valid_protocols}
            ))
            raise typer.Exit(1)

        async def _install():
            server_manager = ServerManager()
            network_manager = NetworkManager()

            # Auto-detect port if not specified
            if not port:
                with console.status("Finding available port..."):
                    available_port = await network_manager.find_available_port()
                    if not available_port:
                        console.print(formatter.format_error(
                            "No available ports found in range 10000-65000"
                        ))
                        raise typer.Exit(1)

                    console.print(formatter.format_info(
                        f"Selected port: {available_port}"
                    ))
                    server_port = available_port
            else:
                server_port = port

            # Generate server name
            server_name = name or f"{protocol}-server-{server_port}"

            # Confirm installation
            if not force:
                console.print("\n[bold]Server Configuration:[/bold]")
                console.print(f"  Protocol: {protocol}")
                console.print(f"  Port: {server_port}")
                console.print(f"  Name: {server_name}")

                if not Confirm.ask("\nProceed with installation?", default=True):
                    console.print("Installation cancelled")
                    raise typer.Exit(0)

            # Install server
            with console.status(f"Installing {protocol} server..."):
                try:
                    server = await server_manager.install(
                        protocol=protocol_type,
                        port=server_port,
                        name=server_name
                    )

                    console.print(formatter.format_success(
                        f"Server '{server_name}' installed successfully!"
                    ))

                    # Show connection info
                    console.print("\n[bold]Server Details:[/bold]")
                    console.print(f"  Name: {server.name}")
                    console.print(f"  Protocol: {server.protocol.value}")
                    console.print(f"  Port: {server.port}")
                    console.print(f"  Status: {server.status.value}")

                    if server.public_ip:
                        console.print(f"  Public IP: {server.public_ip}")
                    if server.domain:
                        console.print(f"  Domain: {server.domain}")

                except Exception as e:
                    console.print(formatter.format_error(
                        f"Failed to install server: {e!s}"
                    ))
                    raise typer.Exit(1)

        run_async(_install())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("list")
def list_servers(
    status: str | None = typer.Option(
        None,
        "--status",
        "-s",
        help="Filter by status: running, stopped, error",
    ),
    format: str | None = typer.Option(
        None,
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
):
    """List all VPN servers."""
    try:
        formatter = get_formatter(format)

        async def _list():
            server_manager = ServerManager()

            # Get all servers
            servers = await server_manager.list()

            if not servers:
                console.print(formatter.format_warning("No VPN servers found"))
                return

            # Filter by status if specified
            if status:
                servers = [s for s in servers if s.status.value == status]

            if not servers:
                console.print(formatter.format_warning(f"No servers with status '{status}'"))
                return

            # Prepare server data
            server_data = []
            for server in servers:
                # Get current status
                current_status = await server_manager.get_status(server.name)

                server_data.append({
                    "name": server.name,
                    "status": current_status.value,
                    "protocol": server.protocol.value,
                    "port": server.port,
                    "domain": server.domain or "-",
                    "created": server.created_at.strftime("%Y-%m-%d") if server.created_at else "-",
                })

            # Format output
            output = formatter.format_list(
                server_data,
                columns=["name", "status", "protocol", "port", "domain", "created"],
                title="VPN Servers"
            )
            console.print(output)

        run_async(_list())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("start")
def start_server(
    name: str = typer.Argument(..., help="Server name to start"),
):
    """Start a VPN server."""
    try:
        formatter = get_formatter()

        async def _start():
            server_manager = ServerManager()

            # Start server
            with console.status(f"Starting server '{name}'..."):
                try:
                    await server_manager.start(name)
                    console.print(formatter.format_success(f"Server '{name}' started successfully"))
                except Exception as e:
                    console.print(formatter.format_error(f"Failed to start server '{name}': {e}"))
                    raise typer.Exit(1)

        run_async(_start())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("stop")
def stop_server(
    name: str = typer.Argument(..., help="Server name to stop"),
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Force stop without confirmation",
    ),
):
    """Stop a VPN server."""
    try:
        formatter = get_formatter()

        # Confirm stop
        if not force:
            if not Confirm.ask(f"Stop server '{name}'?", default=True):
                console.print("Operation cancelled")
                raise typer.Exit(0)

        async def _stop():
            server_manager = ServerManager()

            # Stop server
            with console.status(f"Stopping server '{name}'..."):
                try:
                    await server_manager.stop(name)
                    console.print(formatter.format_success(f"Server '{name}' stopped successfully"))
                except Exception as e:
                    console.print(formatter.format_error(f"Failed to stop server '{name}': {e}"))
                    raise typer.Exit(1)

        run_async(_stop())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("restart")
def restart_server(
    name: str = typer.Argument(..., help="Server name to restart"),
):
    """Restart a VPN server."""
    try:
        formatter = get_formatter()

        async def _restart():
            docker_manager = DockerManager()

            # Find container
            containers = await docker_manager.list_containers(
                filters={"name": name}
            )

            if not containers:
                console.print(formatter.format_error(f"Server '{name}' not found"))
                raise typer.Exit(1)

            container = containers[0]

            # Restart container
            with console.status(f"Restarting server '{name}'..."):
                success = await docker_manager.restart_container(container.id)

                if success:
                    console.print(formatter.format_success(f"Server '{name}' restarted successfully"))
                else:
                    console.print(formatter.format_error(f"Failed to restart server '{name}'"))
                    raise typer.Exit(1)

        run_async(_restart())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("remove")
def remove_server(
    name: str = typer.Argument(..., help="Server name to remove"),
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Force removal without confirmation",
    ),
    volumes: bool = typer.Option(
        True,
        "--volumes/--no-volumes",
        help="Remove associated volumes",
    ),
):
    """Remove a VPN server."""
    try:
        formatter = get_formatter()

        # Confirm removal
        if not force:
            if not Confirm.ask(
                f"[red]Remove server '{name}'? This action cannot be undone.[/red]",
                default=False
            ):
                console.print("Operation cancelled")
                raise typer.Exit(0)

        async def _remove():
            docker_manager = DockerManager()

            # Find container
            containers = await docker_manager.list_containers(
                all=True,
                filters={"name": name}
            )

            if not containers:
                console.print(formatter.format_error(f"Server '{name}' not found"))
                raise typer.Exit(1)

            container = containers[0]

            # Remove container
            with console.status(f"Removing server '{name}'..."):
                success = await docker_manager.remove_container(
                    container.id,
                    force=True,
                    volumes=volumes
                )

                if success:
                    console.print(formatter.format_success(f"Server '{name}' removed successfully"))
                else:
                    console.print(formatter.format_error(f"Failed to remove server '{name}'"))
                    raise typer.Exit(1)

        run_async(_remove())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("logs")
def show_logs(
    name: str = typer.Argument(..., help="Server name"),
    tail: int = typer.Option(
        100,
        "--tail",
        "-n",
        help="Number of lines to show",
    ),
    follow: bool = typer.Option(
        False,
        "--follow",
        "-f",
        help="Follow log output",
    ),
):
    """Show server logs."""
    try:
        formatter = get_formatter()

        async def _logs():
            docker_manager = DockerManager()

            # Find container
            containers = await docker_manager.list_containers(
                all=True,
                filters={"name": name}
            )

            if not containers:
                console.print(formatter.format_error(f"Server '{name}' not found"))
                raise typer.Exit(1)

            container = containers[0]

            # Get logs
            if follow:
                console.print(formatter.format_info(f"Following logs for '{name}' (Ctrl+C to exit)..."))

            logs = await docker_manager.get_container_logs(
                container.id,
                tail=tail,
                follow=follow
            )

            if isinstance(logs, str):
                console.print(logs)
            else:
                # Streaming logs
                try:
                    for line in logs:
                        console.print(line.decode('utf-8', errors='replace'), end='')
                except KeyboardInterrupt:
                    console.print("\n[yellow]Log streaming stopped[/yellow]")

        run_async(_logs())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("status")
def server_status(
    name: str | None = typer.Argument(
        None,
        help="Server name (show all if not specified)",
    ),
    detailed: bool = typer.Option(
        False,
        "--detailed",
        "-d",
        help="Show detailed status information",
    ),
    format: str | None = typer.Option(
        None,
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
):
    """Show server status information."""
    try:
        formatter = get_formatter(format)

        async def _status():
            docker_manager = DockerManager()

            # Get containers
            filters = {"label": "vpn.managed=true"}
            if name:
                filters["name"] = name

            containers = await docker_manager.list_containers(
                all=True,
                filters=filters
            )

            if not containers:
                if name:
                    console.print(formatter.format_error(f"Server '{name}' not found"))
                else:
                    console.print(formatter.format_warning("No VPN servers found"))
                raise typer.Exit(1)

            # Get status for each container
            for container in containers:
                info = await docker_manager.get_container_info(container.id)
                status = await docker_manager.get_container_status(container.id)

                status_data = {
                    "name": container.name,
                    "status": status.value,
                    "id": container.short_id,
                    "image": info.get("image", "unknown"),
                    "created": info.get("created", "unknown"),
                    "ports": str(info.get("ports", {})),
                }

                if detailed:
                    # Get resource stats
                    stats = await docker_manager.get_container_stats(container.id)
                    status_data.update({
                        "cpu_percent": f"{stats.get('cpu_percent', 0):.1f}%",
                        "memory_usage": f"{stats.get('memory_usage_mb', 0):.1f} MB",
                        "network_rx": f"{stats.get('network_rx_mb', 0):.1f} MB",
                        "network_tx": f"{stats.get('network_tx_mb', 0):.1f} MB",
                    })

                    # Get health status
                    health = await docker_manager.health_check(container.id)
                    status_data["healthy"] = health

                output = formatter.format_single(
                    status_data,
                    title=f"Server Status: {container.name}"
                )
                console.print(output)

                if len(containers) > 1:
                    console.print()  # Empty line between servers

        run_async(_status())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)
