"""
Docker Compose management commands.
"""

from pathlib import Path
from typing import List, Optional

import typer
from rich.console import Console
from rich.table import Table

from vpn.core.models import ProtocolType
from vpn.utils.docker_compose import DockerComposeManager

app = typer.Typer(help="Docker Compose orchestration commands")
console = Console()


@app.command()
def init(
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        "-p",
        help="Docker Compose project name"
    ),
    domain: str = typer.Option(
        "your-domain.com",
        "--domain",
        "-d",
        help="Domain name for the VPN services"
    ),
    monitoring: bool = typer.Option(
        True,
        "--monitoring/--no-monitoring",
        help="Include monitoring stack (Prometheus, Grafana, Jaeger)"
    )
):
    """Initialize a new Docker Compose project for VPN services."""
    async def _init_compose():
        manager = DockerComposeManager(project_name)
        
        console.print(f"[bold]Initializing Docker Compose project: {project_name}[/bold]\n")
        
        # Initialize base project
        success = await manager.initialize_compose_project()
        if not success:
            console.print("[red]Failed to initialize project[/red]")
            raise typer.Exit(1)
        
        # Add monitoring stack if requested
        if monitoring:
            console.print("[blue]Adding monitoring stack...[/blue]")
            success = await manager.add_monitoring_stack()
            if not success:
                console.print("[yellow]Warning: Failed to add monitoring stack[/yellow]")
        
        console.print(f"\n[green]✅ Project initialized successfully![/green]")
        console.print(f"[dim]Configuration: {manager.compose_dir}[/dim]")
        console.print(f"[dim]Edit .env file to configure domain and passwords[/dim]")
    
    import asyncio
    asyncio.run(_init_compose())


@app.command()
def add(
    protocol: ProtocolType = typer.Argument(help="VPN protocol to add"),
    port: int = typer.Option(None, "--port", "-p", help="Port for the VPN service"),
    domain: str = typer.Option(None, "--domain", "-d", help="Domain for the service"),
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    )
):
    """Add a VPN service to the Docker Compose configuration."""
    async def _add_service():
        manager = DockerComposeManager(project_name)
        
        if not manager.compose_file.exists():
            console.print("[red]Docker Compose project not found. Run 'vpn compose init' first.[/red]")
            raise typer.Exit(1)
        
        # Prepare service configuration
        config = {}
        if port:
            config['port'] = port
        if domain:
            config['domain'] = domain
        
        # Set default ports
        if not port:
            default_ports = {
                ProtocolType.VLESS: 8443,
                ProtocolType.SHADOWSOCKS: 8388,
                ProtocolType.WIREGUARD: 51820
            }
            config['port'] = default_ports.get(protocol, 8443)
        
        console.print(f"[blue]Adding {protocol.value} service...[/blue]")
        
        success = await manager.add_vpn_service(protocol, config)
        if success:
            console.print(f"[green]✅ {protocol.value} service added successfully![/green]")
            console.print(f"[dim]Service will be available on port {config['port']}[/dim]")
        else:
            console.print(f"[red]Failed to add {protocol.value} service[/red]")
            raise typer.Exit(1)
    
    import asyncio
    asyncio.run(_add_service())


@app.command()
def deploy(
    services: Optional[List[str]] = typer.Argument(
        None,
        help="Specific services to deploy (default: all)"
    ),
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    )
):
    """Deploy the Docker Compose stack."""
    async def _deploy():
        manager = DockerComposeManager(project_name)
        
        if not manager.compose_file.exists():
            console.print("[red]Docker Compose project not found. Run 'vpn compose init' first.[/red]")
            raise typer.Exit(1)
        
        console.print("[blue]Deploying Docker Compose stack...[/blue]")
        
        success = await manager.deploy_stack(services)
        if success:
            console.print("[green]✅ Stack deployed successfully![/green]")
            
            # Show status
            status = await manager.get_stack_status()
            console.print(f"[dim]Services running: {status['running']}/{status['total']}[/dim]")
        else:
            console.print("[red]Deployment failed[/red]")
            raise typer.Exit(1)
    
    import asyncio
    asyncio.run(_deploy())


@app.command()
def status(
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    )
):
    """Show status of Docker Compose services."""
    async def _status():
        manager = DockerComposeManager(project_name)
        
        if not manager.compose_file.exists():
            console.print("[red]Docker Compose project not found.[/red]")
            raise typer.Exit(1)
        
        console.print("[blue]Getting stack status...[/blue]\n")
        
        status = await manager.get_stack_status()
        
        if not status['services']:
            console.print("[yellow]No services found or stack is not running[/yellow]")
            return
        
        # Create status table
        table = Table(title=f"Docker Compose Stack Status - {project_name}")
        table.add_column("Service", style="cyan")
        table.add_column("Status", justify="center")
        table.add_column("Ports", style="blue")
        table.add_column("Image", style="dim")
        
        for service in status['services']:
            status_style = "green" if service.get('State') == 'running' else "red"
            status_text = service.get('State', 'unknown').title()
            
            ports = service.get('Ports', '')
            if isinstance(ports, list):
                ports = ', '.join(ports)
            
            table.add_row(
                service.get('Service', ''),
                f"[{status_style}]{status_text}[/{status_style}]",
                ports,
                service.get('Image', '')
            )
        
        console.print(table)
        console.print(f"\n[dim]Total: {status['total']} services, Running: {status['running']}[/dim]")
    
    import asyncio
    asyncio.run(_status())


@app.command()
def scale(
    service: str = typer.Argument(help="Service name to scale"),
    replicas: int = typer.Argument(help="Number of replicas"),
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    )
):
    """Scale a specific service in the Docker Compose stack."""
    async def _scale():
        manager = DockerComposeManager(project_name)
        
        console.print(f"[blue]Scaling {service} to {replicas} replicas...[/blue]")
        
        success = await manager.scale_service(service, replicas)
        if not success:
            raise typer.Exit(1)
    
    import asyncio
    asyncio.run(_scale())


@app.command()
def logs(
    service: str = typer.Argument(help="Service name to show logs for"),
    lines: int = typer.Option(100, "--lines", "-n", help="Number of log lines to show"),
    follow: bool = typer.Option(False, "--follow", "-f", help="Follow log output"),
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    )
):
    """Show logs for a specific service."""
    async def _logs():
        manager = DockerComposeManager(project_name)
        
        if follow:
            console.print(f"[blue]Following logs for {service}... (Press Ctrl+C to stop)[/blue]\n")
            # TODO: Implement live log following
            console.print("[yellow]Live log following not yet implemented[/yellow]")
        else:
            console.print(f"[blue]Getting logs for {service}...[/blue]\n")
            
            log_lines = await manager.get_service_logs(service, lines)
            
            if not log_lines:
                console.print("[yellow]No logs found[/yellow]")
                return
            
            for line in log_lines:
                if line.strip():
                    console.print(line)
    
    import asyncio
    asyncio.run(_logs())


@app.command()
def down(
    volumes: bool = typer.Option(
        False,
        "--volumes",
        help="Remove volumes as well"
    ),
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    ),
    confirm: bool = typer.Option(
        False,
        "--yes",
        "-y",
        help="Skip confirmation prompt"
    )
):
    """Stop and remove the Docker Compose stack."""
    async def _down():
        if not confirm:
            remove_volumes_text = " and volumes" if volumes else ""
            confirmation = typer.confirm(
                f"Are you sure you want to remove the stack{remove_volumes_text}?"
            )
            if not confirmation:
                console.print("[yellow]Operation cancelled[/yellow]")
                return
        
        manager = DockerComposeManager(project_name)
        
        console.print("[blue]Removing Docker Compose stack...[/blue]")
        
        success = await manager.remove_stack(volumes)
        if not success:
            raise typer.Exit(1)
        
        if volumes:
            console.print("[yellow]All volumes have been removed[/yellow]")
    
    import asyncio
    asyncio.run(_down())


@app.command()
def config(
    project_name: str = typer.Option(
        "vpn-manager",
        "--project",
        help="Docker Compose project name"
    )
):
    """Show the current Docker Compose configuration."""
    manager = DockerComposeManager(project_name)
    
    if not manager.compose_file.exists():
        console.print("[red]Docker Compose project not found.[/red]")
        raise typer.Exit(1)
    
    console.print(f"[blue]Docker Compose configuration:[/blue] {manager.compose_file}\n")
    
    with open(manager.compose_file, 'r') as f:
        content = f.read()
        console.print(content)


if __name__ == "__main__":
    app()