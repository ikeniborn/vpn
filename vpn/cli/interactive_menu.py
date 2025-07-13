"""Interactive CLI menu for VPN Manager."""

import asyncio
from typing import Optional

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, IntPrompt, Prompt
from rich.table import Table

from vpn.core.models import ProtocolType
from vpn.services.docker_manager import DockerManager
from vpn.services.server_manager import ServerManager
from vpn.services.user_manager import UserManager


console = Console()


class InteractiveMenu:
    """Interactive CLI menu for VPN management."""

    def __init__(self):
        """Initialize interactive menu."""
        self.user_manager = UserManager()
        self.server_manager = ServerManager()
        self.docker_manager = DockerManager()
        self.running = True

    def display_main_menu(self) -> None:
        """Display main menu options."""
        console.clear()
        console.print(Panel.fit(
            "[bold cyan]🔐 VPN Manager - Interactive Menu[/bold cyan]\n\n"
            "[bold green]1.[/bold green] 📦 Install VPN Server\n"
            "[bold green]2.[/bold green] 🖥️  Manage VPN Servers\n"
            "[bold green]3.[/bold green] 👥 Manage Users\n"
            "[bold green]4.[/bold green] 📊 Monitoring & Statistics\n"
            "[bold green]5.[/bold green] ⚙️  Settings\n"
            "[bold green]0.[/bold green] 🚪 Exit\n",
            title="Main Menu",
            border_style="bright_blue"
        ))

    async def install_server_menu(self) -> None:
        """Handle VPN server installation."""
        console.clear()
        console.print(Panel.fit(
            "[bold cyan]📦 Install VPN Server[/bold cyan]",
            title="Installation",
            border_style="bright_blue"
        ))

        # Protocol selection
        console.print("\n[bold]Select VPN Protocol:[/bold]")
        console.print("1. VLESS + Reality")
        console.print("2. Shadowsocks")
        console.print("3. WireGuard")
        
        protocol_choice = IntPrompt.ask(
            "\nSelect protocol",
            choices=["1", "2", "3"],
            default=1
        )
        
        protocol_map = {
            1: ProtocolType.VLESS,
            2: ProtocolType.SHADOWSOCKS,
            3: ProtocolType.WIREGUARD
        }
        protocol = protocol_map[protocol_choice]

        # Port configuration
        port = IntPrompt.ask(
            "\nEnter server port",
            default=8443,
            show_default=True
        )

        # Additional configuration based on protocol
        reality_domain = None
        if protocol == ProtocolType.VLESS:
            reality_domain = Prompt.ask(
                "\nEnter reality domain",
                default="www.google.com",
                show_default=True
            )

        # Server name
        name = Prompt.ask(
            "\nEnter server name (optional)",
            default="",
            show_default=False
        )

        # Confirm installation
        console.print(f"\n[bold]Installation Summary:[/bold]")
        console.print(f"Protocol: {protocol.value}")
        console.print(f"Port: {port}")
        if reality_domain:
            console.print(f"Reality Domain: {reality_domain}")
        if name:
            console.print(f"Server Name: {name}")

        if Confirm.ask("\nProceed with installation?", default=True):
            with console.status(f"Installing {protocol.value} server..."):
                try:
                    result = await self.server_manager.install(
                        protocol=protocol,
                        port=port,
                        reality_domain=reality_domain,
                        name=name or None
                    )
                    
                    if result.success:
                        console.print(f"\n[green]✅ Server installed successfully![/green]")
                        console.print(f"Port: {port}")
                    else:
                        console.print(f"\n[red]❌ Installation failed: {result.message}[/red]")
                except Exception as e:
                    console.print(f"\n[red]❌ Error: {str(e)}[/red]")

        Prompt.ask("\nPress Enter to continue...")

    async def manage_servers_menu(self) -> None:
        """Handle server management."""
        console.clear()
        console.print(Panel.fit(
            "[bold cyan]🖥️  Manage VPN Servers[/bold cyan]",
            title="Server Management",
            border_style="bright_blue"
        ))

        # List servers
        with console.status("Loading servers..."):
            containers = await self.docker_manager.list_containers()
            vpn_servers = [c for c in containers if any(
                label.startswith("vpn.") for label in c.get("labels", {})
            )]

        if not vpn_servers:
            console.print("\n[yellow]No VPN servers found.[/yellow]")
        else:
            table = Table(title="VPN Servers")
            table.add_column("Name", style="cyan")
            table.add_column("Protocol", style="green")
            table.add_column("Port", style="yellow")
            table.add_column("Status", style="magenta")

            for server in vpn_servers:
                labels = server.get("labels", {})
                name = server.get("name", "Unknown")
                protocol = labels.get("vpn.protocol", "Unknown")
                port = labels.get("vpn.port", "Unknown")
                status = server.get("status", "Unknown")
                
                table.add_row(name, protocol, port, status)

            console.print(table)

        console.print("\n[bold]Actions:[/bold]")
        console.print("1. Start server")
        console.print("2. Stop server")
        console.print("3. Restart server")
        console.print("4. Remove server")
        console.print("0. Back to main menu")

        action = IntPrompt.ask("\nSelect action", choices=["0", "1", "2", "3", "4"], default=0)
        
        if action != 0 and vpn_servers:
            # Server selection would go here
            console.print("[yellow]Server management features in development[/yellow]")

        Prompt.ask("\nPress Enter to continue...")

    async def manage_users_menu(self) -> None:
        """Handle user management."""
        console.clear()
        console.print(Panel.fit(
            "[bold cyan]👥 Manage Users[/bold cyan]",
            title="User Management",
            border_style="bright_blue"
        ))

        console.print("\n[bold]Actions:[/bold]")
        console.print("1. List users")
        console.print("2. Create user")
        console.print("3. Delete user")
        console.print("4. Show user config")
        console.print("0. Back to main menu")

        action = IntPrompt.ask("\nSelect action", choices=["0", "1", "2", "3", "4"], default=0)

        if action == 1:
            # List users
            with console.status("Loading users..."):
                users = await self.user_manager.list()

            if not users:
                console.print("\n[yellow]No users found.[/yellow]")
            else:
                table = Table(title="VPN Users")
                table.add_column("Username", style="cyan")
                table.add_column("Protocol", style="green")
                table.add_column("Status", style="yellow")
                table.add_column("Traffic", style="magenta")

                for user in users:
                    traffic = f"{user.traffic.total_bytes / (1024**2):.2f} MB" if user.traffic else "0 MB"
                    table.add_row(
                        user.username,
                        user.protocol.value,
                        user.status,
                        traffic
                    )

                console.print(table)

        elif action == 2:
            # Create user
            username = Prompt.ask("\nEnter username")
            email = Prompt.ask("Enter email (optional)", default="")
            
            # Protocol selection
            console.print("\n[bold]Select protocol:[/bold]")
            console.print("1. VLESS")
            console.print("2. Shadowsocks")
            console.print("3. WireGuard")
            
            protocol_choice = IntPrompt.ask("Select protocol", choices=["1", "2", "3"], default=1)
            protocol_map = {
                1: ProtocolType.VLESS,
                2: ProtocolType.SHADOWSOCKS,
                3: ProtocolType.WIREGUARD
            }
            protocol = protocol_map[protocol_choice]

            with console.status("Creating user..."):
                try:
                    user = await self.user_manager.create(
                        username=username,
                        protocol=protocol,
                        email=email or None
                    )
                    console.print(f"\n[green]✅ User '{username}' created successfully![/green]")
                except Exception as e:
                    console.print(f"\n[red]❌ Error: {str(e)}[/red]")

        elif action == 3:
            # Delete user
            username = Prompt.ask("\nEnter username to delete")
            if Confirm.ask(f"Are you sure you want to delete user '{username}'?", default=False):
                with console.status("Deleting user..."):
                    try:
                        await self.user_manager.delete(username)
                        console.print(f"\n[green]✅ User '{username}' deleted successfully![/green]")
                    except Exception as e:
                        console.print(f"\n[red]❌ Error: {str(e)}[/red]")

        Prompt.ask("\nPress Enter to continue...")

    async def monitoring_menu(self) -> None:
        """Display monitoring and statistics."""
        console.clear()
        console.print(Panel.fit(
            "[bold cyan]📊 Monitoring & Statistics[/bold cyan]",
            title="System Monitoring",
            border_style="bright_blue"
        ))

        with console.status("Loading statistics..."):
            # Get statistics
            users = await self.user_manager.list()
            containers = await self.docker_manager.list_containers()
            vpn_servers = [c for c in containers if any(
                label.startswith("vpn.") for label in c.get("labels", {})
            )]

        console.print(f"\n[bold]System Overview:[/bold]")
        console.print(f"Total Users: {len(users)}")
        console.print(f"Active Users: {sum(1 for u in users if u.status == 'active')}")
        console.print(f"Total Servers: {len(vpn_servers)}")
        console.print(f"Running Servers: {sum(1 for s in vpn_servers if s.get('status') == 'running')}")

        # Traffic statistics
        total_traffic = sum(
            u.traffic.total_bytes for u in users
            if hasattr(u, 'traffic') and u.traffic
        )
        console.print(f"Total Traffic: {total_traffic / (1024**3):.2f} GB")

        Prompt.ask("\nPress Enter to continue...")

    async def run(self) -> None:
        """Run the interactive menu."""
        while self.running:
            self.display_main_menu()
            
            choice = IntPrompt.ask(
                "\nSelect option",
                choices=["0", "1", "2", "3", "4", "5"],
                default=0
            )

            if choice == 0:
                self.running = False
                console.print("\n[yellow]Goodbye! 👋[/yellow]")
            elif choice == 1:
                await self.install_server_menu()
            elif choice == 2:
                await self.manage_servers_menu()
            elif choice == 3:
                await self.manage_users_menu()
            elif choice == 4:
                await self.monitoring_menu()
            elif choice == 5:
                console.print("\n[yellow]Settings menu in development[/yellow]")
                Prompt.ask("\nPress Enter to continue...")


def run_interactive_menu():
    """Entry point for interactive menu."""
    menu = InteractiveMenu()
    asyncio.run(menu.run())