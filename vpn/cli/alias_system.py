"""
Command alias system for Typer CLI.

This module provides a comprehensive command alias system that allows users to:
- Create custom aliases for complex commands
- Save frequently used command combinations
- Support parameter substitution in aliases
- Manage aliases through configuration
- Use shell-like alias expansion
"""

import json
import shlex
import re
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime

import typer
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.syntax import Syntax

console = Console()


@dataclass
class CommandAlias:
    """Represents a command alias."""
    name: str
    command: str
    description: str = ""
    parameters: Dict[str, str] = None
    created_at: str = ""
    used_count: int = 0
    
    def __post_init__(self):
        if self.parameters is None:
            self.parameters = {}
        if not self.created_at:
            self.created_at = datetime.now().isoformat()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert alias to dictionary."""
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CommandAlias':
        """Create alias from dictionary."""
        return cls(**data)


class AliasManager:
    """Manages command aliases for the CLI."""
    
    def __init__(self, config_dir: Optional[Path] = None):
        """Initialize alias manager."""
        self.config_dir = config_dir or Path.home() / ".config" / "vpn-manager"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.aliases_file = self.config_dir / "aliases.json"
        
        self._aliases: Dict[str, CommandAlias] = {}
        self._load_aliases()
    
    def _load_aliases(self) -> None:
        """Load aliases from configuration file."""
        if self.aliases_file.exists():
            try:
                with open(self.aliases_file, 'r') as f:
                    data = json.load(f)
                
                for alias_data in data.get('aliases', []):
                    alias = CommandAlias.from_dict(alias_data)
                    self._aliases[alias.name] = alias
            
            except Exception as e:
                console.print(f"[yellow]Warning: Could not load aliases: {e}[/yellow]")
                self._create_default_aliases()
        else:
            self._create_default_aliases()
    
    def _save_aliases(self) -> None:
        """Save aliases to configuration file."""
        try:
            data = {
                'aliases': [alias.to_dict() for alias in self._aliases.values()],
                'version': '1.0',
                'updated_at': datetime.now().isoformat()
            }
            
            with open(self.aliases_file, 'w') as f:
                json.dump(data, f, indent=2)
        
        except Exception as e:
            console.print(f"[red]Error saving aliases: {e}[/red]")
    
    def _create_default_aliases(self) -> None:
        """Create default useful aliases."""
        default_aliases = [
            # Quick shortcuts
            CommandAlias(
                name="ls",
                command="users list",
                description="List all users (short form)"
            ),
            CommandAlias(
                name="ll",
                command="users list --format table --verbose",
                description="List users with detailed information"
            ),
            CommandAlias(
                name="ps",
                command="server list",
                description="List all servers (process-style)"
            ),
            CommandAlias(
                name="top",
                command="monitor status --refresh",
                description="Show real-time system status"
            ),
            
            # User management shortcuts
            CommandAlias(
                name="useradd",
                command="users create $1 --protocol $2",
                description="Create user with protocol",
                parameters={"$1": "username", "$2": "protocol"}
            ),
            CommandAlias(
                name="userdel",
                command="users delete $1 --force",
                description="Delete user forcefully",
                parameters={"$1": "username"}
            ),
            CommandAlias(
                name="usermod",
                command="users update $1",
                description="Modify user settings",
                parameters={"$1": "username"}
            ),
            
            # Server management shortcuts
            CommandAlias(
                name="start",
                command="server start $1",
                description="Start server",
                parameters={"$1": "server_name"}
            ),
            CommandAlias(
                name="stop",
                command="server stop $1",
                description="Stop server",
                parameters={"$1": "server_name"}
            ),
            CommandAlias(
                name="restart",
                command="server restart $1",
                description="Restart server",
                parameters={"$1": "server_name"}
            ),
            CommandAlias(
                name="logs",
                command="server logs $1 --follow",
                description="Follow server logs",
                parameters={"$1": "server_name"}
            ),
            
            # Monitoring shortcuts
            CommandAlias(
                name="status",
                command="monitor status --format table",
                description="Show system status"
            ),
            CommandAlias(
                name="stats",
                command="monitor traffic --period day",
                description="Show daily traffic stats"
            ),
            
            # Configuration shortcuts
            CommandAlias(
                name="backup",
                command="config export --include-users --include-servers",
                description="Create complete backup"
            ),
            CommandAlias(
                name="restore",
                command="config import $1 --merge",
                description="Restore from backup",
                parameters={"$1": "backup_file"}
            ),
            
            # Complex operations
            CommandAlias(
                name="deploy",
                command="server create $1 --protocol vless --port $2 --auto-start",
                description="Quick server deployment",
                parameters={"$1": "server_name", "$2": "port"}
            ),
            CommandAlias(
                name="bulkuser",
                command="users create-batch --count $1 --protocol $2 --prefix user",
                description="Create multiple users",
                parameters={"$1": "count", "$2": "protocol"}
            ),
            
            # Diagnostic shortcuts
            CommandAlias(
                name="check",
                command="doctor --quick",
                description="Quick system health check"
            ),
            CommandAlias(
                name="checkall",
                command="doctor --comprehensive --fix-issues",
                description="Comprehensive system check with fixes"
            ),
        ]
        
        for alias in default_aliases:
            self._aliases[alias.name] = alias
        
        self._save_aliases()
        console.print("[green]Default aliases created[/green]")
    
    def add_alias(self, name: str, command: str, description: str = "", force: bool = False) -> bool:
        """Add a new alias."""
        if name in self._aliases and not force:
            return False
        
        # Parse parameters from command
        parameters = self._extract_parameters(command)
        
        alias = CommandAlias(
            name=name,
            command=command,
            description=description,
            parameters=parameters
        )
        
        self._aliases[name] = alias
        self._save_aliases()
        return True
    
    def remove_alias(self, name: str) -> bool:
        """Remove an alias."""
        if name in self._aliases:
            del self._aliases[name]
            self._save_aliases()
            return True
        return False
    
    def get_alias(self, name: str) -> Optional[CommandAlias]:
        """Get an alias by name."""
        return self._aliases.get(name)
    
    def list_aliases(self, pattern: Optional[str] = None) -> List[CommandAlias]:
        """List all aliases, optionally filtered by pattern."""
        aliases = list(self._aliases.values())
        
        if pattern:
            aliases = [
                alias for alias in aliases
                if pattern.lower() in alias.name.lower() or 
                   pattern.lower() in alias.description.lower() or
                   pattern.lower() in alias.command.lower()
            ]
        
        return sorted(aliases, key=lambda a: a.name)
    
    def expand_alias(self, name: str, args: List[str]) -> Optional[Tuple[str, List[str]]]:
        """Expand an alias with arguments."""
        alias = self.get_alias(name)
        if not alias:
            return None
        
        # Increment usage count
        alias.used_count += 1
        self._save_aliases()
        
        # Expand command with parameters
        expanded_command = self._expand_command(alias.command, args)
        
        # Parse the expanded command
        try:
            command_parts = shlex.split(expanded_command)
            if command_parts:
                command = command_parts[0]
                command_args = command_parts[1:]
                return command, command_args
        except ValueError:
            # If shlex parsing fails, fall back to simple split
            command_parts = expanded_command.split()
            if command_parts:
                command = command_parts[0]
                command_args = command_parts[1:]
                return command, command_args
        
        return None
    
    def _extract_parameters(self, command: str) -> Dict[str, str]:
        """Extract parameter placeholders from command."""
        parameters = {}
        
        # Find $1, $2, etc. parameters
        positional_params = re.findall(r'\$(\d+)', command)
        for param in positional_params:
            parameters[f'${param}'] = f'arg{param}'
        
        # Find ${name} parameters
        named_params = re.findall(r'\$\{([^}]+)\}', command)
        for param in named_params:
            parameters[f'${{{param}}}'] = param
        
        return parameters
    
    def _expand_command(self, command: str, args: List[str]) -> str:
        """Expand command with provided arguments."""
        expanded = command
        
        # Expand positional parameters ($1, $2, etc.)
        for i, arg in enumerate(args, 1):
            expanded = expanded.replace(f'${i}', arg)
        
        # Expand named parameters (${name})
        # This could be enhanced to support environment variables
        
        return expanded
    
    def get_suggestions(self, partial_name: str) -> List[str]:
        """Get alias suggestions for partial name."""
        return [
            alias.name for alias in self._aliases.values()
            if alias.name.startswith(partial_name)
        ]
    
    def import_aliases(self, file_path: Path) -> Tuple[int, List[str]]:
        """Import aliases from a file."""
        imported_count = 0
        errors = []
        
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
            
            for alias_data in data.get('aliases', []):
                try:
                    alias = CommandAlias.from_dict(alias_data)
                    self._aliases[alias.name] = alias
                    imported_count += 1
                except Exception as e:
                    errors.append(f"Failed to import alias '{alias_data.get('name', 'unknown')}': {e}")
            
            if imported_count > 0:
                self._save_aliases()
        
        except Exception as e:
            errors.append(f"Failed to read file: {e}")
        
        return imported_count, errors
    
    def export_aliases(self, file_path: Path, pattern: Optional[str] = None) -> int:
        """Export aliases to a file."""
        aliases_to_export = self.list_aliases(pattern)
        
        data = {
            'aliases': [alias.to_dict() for alias in aliases_to_export],
            'exported_at': datetime.now().isoformat(),
            'version': '1.0'
        }
        
        with open(file_path, 'w') as f:
            json.dump(data, f, indent=2)
        
        return len(aliases_to_export)


# Global alias manager instance
_global_alias_manager: Optional[AliasManager] = None


def get_alias_manager() -> AliasManager:
    """Get the global alias manager instance."""
    global _global_alias_manager
    if _global_alias_manager is None:
        _global_alias_manager = AliasManager()
    return _global_alias_manager


def setup_alias_commands(app: typer.Typer) -> None:
    """Set up alias management commands."""
    
    alias_app = typer.Typer(
        name="alias",
        help="Manage command aliases",
        no_args_is_help=True
    )
    
    @alias_app.command("add")
    def add_alias(
        name: str = typer.Argument(help="Alias name"),
        command: str = typer.Argument(help="Command to alias"),
        description: str = typer.Option("", "--desc", help="Alias description"),
        force: bool = typer.Option(False, "--force", help="Overwrite existing alias")
    ):
        """Add a new command alias."""
        manager = get_alias_manager()
        
        if manager.add_alias(name, command, description, force):
            console.print(f"[green]✓ Alias '{name}' added successfully[/green]")
            
            # Show parameter info if any
            alias = manager.get_alias(name)
            if alias and alias.parameters:
                console.print("\n[blue]Parameters detected:[/blue]")
                for param, desc in alias.parameters.items():
                    console.print(f"  {param}: {desc}")
        else:
            console.print(f"[red]✗ Alias '{name}' already exists. Use --force to overwrite[/red]")
            raise typer.Exit(1)
    
    @alias_app.command("remove")
    def remove_alias(
        name: str = typer.Argument(help="Alias name to remove")
    ):
        """Remove a command alias."""
        manager = get_alias_manager()
        
        if manager.remove_alias(name):
            console.print(f"[green]✓ Alias '{name}' removed successfully[/green]")
        else:
            console.print(f"[red]✗ Alias '{name}' not found[/red]")
            raise typer.Exit(1)
    
    @alias_app.command("list")
    def list_aliases(
        pattern: Optional[str] = typer.Option(None, "--pattern", "-p", help="Filter aliases by pattern"),
        verbose: bool = typer.Option(False, "--verbose", "-v", help="Show detailed information")
    ):
        """List all command aliases."""
        manager = get_alias_manager()
        aliases = manager.list_aliases(pattern)
        
        if not aliases:
            if pattern:
                console.print(f"[yellow]No aliases found matching pattern: {pattern}[/yellow]")
            else:
                console.print("[yellow]No aliases defined[/yellow]")
            return
        
        if verbose:
            # Detailed view
            for alias in aliases:
                panel_content = f"[bold]Command:[/bold] {alias.command}\n"
                if alias.description:
                    panel_content += f"[bold]Description:[/bold] {alias.description}\n"
                if alias.parameters:
                    panel_content += f"[bold]Parameters:[/bold] {', '.join(alias.parameters.keys())}\n"
                panel_content += f"[bold]Used:[/bold] {alias.used_count} times\n"
                panel_content += f"[bold]Created:[/bold] {alias.created_at[:10]}"
                
                console.print(Panel(panel_content, title=f"[green]{alias.name}[/green]"))
        else:
            # Table view
            table = Table(title="Command Aliases")
            table.add_column("Name", style="green", width=15)
            table.add_column("Command", style="blue", width=40)
            table.add_column("Description", style="dim", width=30)
            table.add_column("Used", justify="right", width=8)
            
            for alias in aliases:
                table.add_row(
                    alias.name,
                    alias.command[:37] + "..." if len(alias.command) > 40 else alias.command,
                    alias.description[:27] + "..." if len(alias.description) > 30 else alias.description,
                    str(alias.used_count)
                )
            
            console.print(table)
    
    @alias_app.command("show")
    def show_alias(
        name: str = typer.Argument(help="Alias name to show")
    ):
        """Show detailed information about an alias."""
        manager = get_alias_manager()
        alias = manager.get_alias(name)
        
        if not alias:
            console.print(f"[red]✗ Alias '{name}' not found[/red]")
            raise typer.Exit(1)
        
        panel_content = f"[bold]Command:[/bold] {alias.command}\n"
        if alias.description:
            panel_content += f"[bold]Description:[/bold] {alias.description}\n"
        
        if alias.parameters:
            panel_content += f"\n[bold]Parameters:[/bold]\n"
            for param, desc in alias.parameters.items():
                panel_content += f"  {param}: {desc}\n"
        
        panel_content += f"\n[bold]Usage Statistics:[/bold]\n"
        panel_content += f"  Used: {alias.used_count} times\n"
        panel_content += f"  Created: {alias.created_at}\n"
        
        # Show usage examples
        if alias.parameters:
            panel_content += f"\n[bold]Usage Examples:[/bold]\n"
            if '$1' in alias.parameters:
                panel_content += f"  vpn {name} example_arg\n"
            if len(alias.parameters) > 1:
                args = [f"arg{i}" for i in range(1, len(alias.parameters) + 1)]
                panel_content += f"  vpn {name} {' '.join(args)}\n"
        else:
            panel_content += f"\n[bold]Usage:[/bold]\n  vpn {name}\n"
        
        console.print(Panel(panel_content, title=f"[green]Alias: {name}[/green]"))
    
    @alias_app.command("import")
    def import_aliases(
        file_path: Path = typer.Argument(help="File to import aliases from")
    ):
        """Import aliases from a JSON file."""
        if not file_path.exists():
            console.print(f"[red]✗ File not found: {file_path}[/red]")
            raise typer.Exit(1)
        
        manager = get_alias_manager()
        imported_count, errors = manager.import_aliases(file_path)
        
        if imported_count > 0:
            console.print(f"[green]✓ Imported {imported_count} aliases successfully[/green]")
        
        if errors:
            console.print(f"\n[yellow]Warnings/Errors:[/yellow]")
            for error in errors:
                console.print(f"  • {error}")
        
        if imported_count == 0 and errors:
            raise typer.Exit(1)
    
    @alias_app.command("export")
    def export_aliases(
        file_path: Path = typer.Argument(help="File to export aliases to"),
        pattern: Optional[str] = typer.Option(None, "--pattern", "-p", help="Export only aliases matching pattern")
    ):
        """Export aliases to a JSON file."""
        manager = get_alias_manager()
        
        try:
            exported_count = manager.export_aliases(file_path, pattern)
            console.print(f"[green]✓ Exported {exported_count} aliases to {file_path}[/green]")
        except Exception as e:
            console.print(f"[red]✗ Export failed: {e}[/red]")
            raise typer.Exit(1)
    
    # Add alias command group to main app
    app.add_typer(alias_app, name="alias", help="Manage command aliases")


def process_command_with_aliases(command_parts: List[str]) -> List[str]:
    """Process command parts and expand aliases if found."""
    if not command_parts:
        return command_parts
    
    manager = get_alias_manager()
    command_name = command_parts[0]
    args = command_parts[1:]
    
    # Check if first part is an alias
    expansion = manager.expand_alias(command_name, args)
    if expansion:
        expanded_command, expanded_args = expansion
        
        # Recursively process in case the expanded command also contains aliases
        new_parts = [expanded_command] + expanded_args
        return process_command_with_aliases(new_parts)
    
    return command_parts


def show_alias_examples():
    """Show examples of alias usage."""
    examples = """
# Create simple aliases
vpn alias add ls "users list"
vpn alias add ps "server list"
vpn alias add top "monitor status --refresh"

# Create parameterized aliases
vpn alias add useradd "users create \$1 --protocol \$2" --desc "Create user with protocol"
vpn alias add start "server start \$1" --desc "Start server"
vpn alias add logs "server logs \$1 --follow" --desc "Follow server logs"

# Use aliases
vpn ls                          # Lists users
vpn useradd john vless         # Creates user 'john' with VLESS protocol
vpn start production-server    # Starts the production server
vpn logs production-server     # Shows logs for production server

# Manage aliases
vpn alias list                 # List all aliases
vpn alias list --pattern user  # List aliases containing 'user'
vpn alias show useradd         # Show details of 'useradd' alias
vpn alias remove old-alias     # Remove an alias

# Import/Export aliases
vpn alias export my-aliases.json              # Export all aliases
vpn alias export team-aliases.json --pattern team  # Export team-related aliases
vpn alias import shared-aliases.json          # Import aliases from file
"""
    
    syntax = Syntax(examples, "bash", theme="monokai", line_numbers=False)
    console.print(Panel(syntax, title="[bold green]Alias Examples[/bold green]"))