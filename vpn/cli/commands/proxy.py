"""Proxy management CLI commands.
"""

import asyncio

import typer
from rich.console import Console

from vpn.cli.formatters.base import get_formatter
from vpn.services.proxy_server import ProxyServerManager
from vpn.utils.logger import get_logger

app = typer.Typer(help="Proxy management commands")
console = Console()
logger = get_logger(__name__)


def run_async(coro):
    """Run async coroutine."""
    return asyncio.run(coro)


@app.command("start")
def start_proxy(
    proxy_type: str = typer.Option(
        "http",
        "--type",
        "-t",
        help="Proxy type: http, socks5",
    ),
    port: int | None = typer.Option(
        None,
        "--port",
        "-p",
        help="Port number (default: 8888 for HTTP, 1080 for SOCKS5)",
    ),
    host: str = typer.Option(
        "0.0.0.0",
        "--host",
        help="Host to bind to",
    ),
    no_auth: bool = typer.Option(
        False,
        "--no-auth",
        help="Disable authentication",
    ),
):
    """Start proxy server."""
    try:
        formatter = get_formatter()

        # Validate proxy type
        if proxy_type not in ["http", "socks5"]:
            console.print(formatter.format_error(
                "Invalid proxy type. Must be 'http' or 'socks5'"
            ))
            raise typer.Exit(1)

        # Set default ports
        if port is None:
            port = 8888 if proxy_type == "http" else 1080

        async def _start():
            proxy_manager = ProxyServerManager()
            auth_required = not no_auth

            try:
                if proxy_type == "http":
                    server_name = await proxy_manager.start_http_proxy(
                        host=host,
                        port=port,
                        auth_required=auth_required
                    )
                else:  # socks5
                    server_name = await proxy_manager.start_socks5_proxy(
                        host=host,
                        port=port,
                        auth_required=auth_required
                    )

                console.print(formatter.format_success(
                    f"{proxy_type.upper()} proxy server started"
                ))
                console.print(f"  Server: {server_name}")
                console.print(f"  Address: {host}:{port}")
                console.print(f"  Authentication: {'Required' if auth_required else 'Disabled'}")

                if auth_required:
                    console.print("\n[yellow]Note: Use VPN user credentials to authenticate[/yellow]")

            except Exception as e:
                console.print(formatter.format_error(f"Failed to start proxy: {e}"))
                raise typer.Exit(1)

        run_async(_start())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("stop")
def stop_proxy(
    server_name: str = typer.Argument(..., help="Proxy server name to stop"),
):
    """Stop proxy server."""
    try:
        formatter = get_formatter()

        async def _stop():
            proxy_manager = ProxyServerManager()

            try:
                await proxy_manager.stop_proxy(server_name)
                console.print(formatter.format_success(
                    f"Proxy server '{server_name}' stopped"
                ))
            except Exception as e:
                console.print(formatter.format_error(f"Failed to stop proxy: {e}"))
                raise typer.Exit(1)

        run_async(_stop())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("list")
def list_proxies(
    format: str | None = typer.Option(
        None,
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
):
    """List running proxy servers."""
    try:
        formatter = get_formatter(format)

        async def _list():
            proxy_manager = ProxyServerManager()

            try:
                proxies = await proxy_manager.list_proxies()

                if not proxies:
                    console.print(formatter.format_warning("No proxy servers running"))
                    return

                output = formatter.format_list(
                    proxies,
                    columns=["name", "type", "port", "status"],
                    title="Proxy Servers"
                )
                console.print(output)

            except Exception as e:
                console.print(formatter.format_error(f"Failed to list proxies: {e}"))
                raise typer.Exit(1)

        run_async(_list())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("status")
def proxy_status(
    server_name: str | None = typer.Argument(
        None,
        help="Proxy server name (show all if not specified)",
    ),
    detailed: bool = typer.Option(
        False,
        "--detailed",
        "-d",
        help="Show detailed statistics",
    ),
):
    """Show proxy server status."""
    try:
        formatter = get_formatter()

        async def _status():
            proxy_manager = ProxyServerManager()

            try:
                if server_name:
                    # Show specific server status
                    stats = await proxy_manager.get_proxy_stats(server_name)

                    status_data = {
                        "server": server_name,
                        "connections": stats["connections"],
                        "bytes_transferred": stats["bytes_transferred"],
                        "requests_per_minute": stats["requests_per_minute"],
                    }

                    output = formatter.format_single(
                        status_data,
                        title=f"Proxy Status: {server_name}"
                    )
                    console.print(output)
                else:
                    # Show all servers
                    proxies = await proxy_manager.list_proxies()

                    if not proxies:
                        console.print(formatter.format_warning("No proxy servers running"))
                        return

                    for proxy in proxies:
                        if detailed:
                            stats = await proxy_manager.get_proxy_stats(proxy["name"])
                            proxy.update(stats)

                    columns = ["name", "type", "port", "status"]
                    if detailed:
                        columns.extend(["connections", "bytes_transferred", "requests_per_minute"])

                    output = formatter.format_list(
                        proxies,
                        columns=columns,
                        title="Proxy Server Status"
                    )
                    console.print(output)

            except Exception as e:
                console.print(formatter.format_error(f"Failed to get status: {e}"))
                raise typer.Exit(1)

        run_async(_status())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)


@app.command("test")
def test_proxy(
    proxy_type: str = typer.Option(
        "http",
        "--type",
        "-t",
        help="Proxy type to test: http, socks5",
    ),
    host: str = typer.Option(
        "localhost",
        "--host",
        help="Proxy host",
    ),
    port: int = typer.Option(
        8888,
        "--port",
        "-p",
        help="Proxy port",
    ),
    url: str = typer.Option(
        "http://httpbin.org/ip",
        "--url",
        help="URL to test with",
    ),
):
    """Test proxy server connection."""
    try:
        formatter = get_formatter()

        async def _test():
            import aiohttp

            try:
                if proxy_type == "http":
                    proxy_url = f"http://{host}:{port}"
                elif proxy_type == "socks5":
                    proxy_url = f"socks5://{host}:{port}"
                else:
                    console.print(formatter.format_error("Invalid proxy type"))
                    raise typer.Exit(1)

                console.print(formatter.format_info(f"Testing {proxy_type.upper()} proxy at {host}:{port}"))
                console.print(f"Target URL: {url}")

                async with aiohttp.ClientSession() as session:
                    async with session.get(url, proxy=proxy_url, timeout=10) as response:
                        content = await response.text()

                        console.print(formatter.format_success("Proxy test successful!"))
                        console.print(f"Status: {response.status}")
                        console.print(f"Response: {content[:200]}...")

            except Exception as e:
                console.print(formatter.format_error(f"Proxy test failed: {e}"))
                raise typer.Exit(1)

        run_async(_test())

    except Exception as e:
        console.print(formatter.format_error(str(e)))
        raise typer.Exit(1)
