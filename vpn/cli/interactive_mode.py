"""
Interactive mode for complex VPN operations.

This module provides an interactive command-line interface for complex operations:
- Guided user creation with validation
- Interactive server setup wizard
- Bulk operations with confirmation
- Configuration wizards
- Step-by-step troubleshooting
"""

import asyncio
import re
from pathlib import Path
from typing import Dict, List, Optional, Any, Callable, Union
from dataclasses import dataclass
from enum import Enum

import typer
from rich.console import Console
from rich.prompt import Prompt, Confirm, IntPrompt, FloatPrompt
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.text import Text
from rich.tree import Tree
from rich.markdown import Markdown

console = Console()


class WizardStep:
    """Base class for wizard steps."""
    
    def __init__(self, title: str, description: str = ""):
        """Initialize wizard step."""
        self.title = title
        self.description = description
        self.data: Dict[str, Any] = {}
        self.completed = False
        self.skippable = False
    
    async def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute the wizard step."""
        raise NotImplementedError
    
    def validate(self, value: Any) -> bool:
        """Validate step input."""
        return True
    
    def get_help(self) -> str:
        """Get help text for this step."""
        return self.description


class ChoiceStep(WizardStep):
    """Wizard step for choosing from options."""
    
    def __init__(
        self,
        title: str,
        choices: Dict[str, str],
        default: Optional[str] = None,
        description: str = "",
        multiple: bool = False
    ):
        """Initialize choice step."""
        super().__init__(title, description)
        self.choices = choices
        self.default = default
        self.multiple = multiple
    
    async def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute choice step."""
        console.print(f"\n[bold blue]{self.title}[/bold blue]")
        if self.description:
            console.print(f"[dim]{self.description}[/dim]")
        
        if self.multiple:
            console.print("\n[yellow]Select multiple options (comma-separated):[/yellow]")
        
        # Display choices
        table = Table(show_header=False, box=None)
        table.add_column("Key", style="green", width=8)
        table.add_column("Description", style="white")
        
        for key, desc in self.choices.items():
            marker = " (default)" if key == self.default else ""
            table.add_row(f"[{key}]", f"{desc}{marker}")
        
        console.print(table)
        
        while True:
            if self.multiple:
                prompt_text = "Enter choices"
                if self.default:
                    prompt_text += f" (default: {self.default})"
                prompt_text += ": "
                
                response = Prompt.ask(prompt_text, default=self.default or "")
                
                if not response:
                    selected = []
                else:
                    selected = [choice.strip() for choice in response.split(",")]
                
                # Validate choices
                invalid_choices = [c for c in selected if c not in self.choices]
                if invalid_choices:
                    console.print(f"[red]Invalid choices: {', '.join(invalid_choices)}[/red]")
                    continue
                
                self.data['selected'] = selected
                break
            else:
                choice = Prompt.ask(
                    "Enter your choice",
                    choices=list(self.choices.keys()),
                    default=self.default
                )
                self.data['selected'] = choice
                break
        
        self.completed = True
        return self.data


class InputStep(WizardStep):
    """Wizard step for text input."""
    
    def __init__(
        self,
        title: str,
        prompt_text: str,
        default: Optional[str] = None,
        description: str = "",
        required: bool = True,
        validator: Optional[Callable[[str], bool]] = None,
        password: bool = False
    ):
        """Initialize input step."""
        super().__init__(title, description)
        self.prompt_text = prompt_text
        self.default = default
        self.required = required
        self.validator = validator
        self.password = password
    
    async def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute input step."""
        console.print(f"\n[bold blue]{self.title}[/bold blue]")
        if self.description:
            console.print(f"[dim]{self.description}[/dim]")
        
        while True:
            if self.password:
                value = Prompt.ask(self.prompt_text, password=True)
            else:
                value = Prompt.ask(self.prompt_text, default=self.default or "")
            
            if self.required and not value:
                console.print("[red]This field is required[/red]")
                continue
            
            if self.validator and not self.validator(value):
                console.print("[red]Invalid input. Please try again.[/red]")
                continue
            
            self.data['value'] = value
            break
        
        self.completed = True
        return self.data


class ConfirmationStep(WizardStep):
    """Wizard step for yes/no confirmation."""
    
    def __init__(
        self,
        title: str,
        prompt_text: str,
        default: bool = False,
        description: str = ""
    ):
        """Initialize confirmation step."""
        super().__init__(title, description)
        self.prompt_text = prompt_text
        self.default = default
    
    async def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute confirmation step."""
        console.print(f"\n[bold blue]{self.title}[/bold blue]")
        if self.description:
            console.print(f"[dim]{self.description}[/dim]")
        
        confirmed = Confirm.ask(self.prompt_text, default=self.default)
        self.data['confirmed'] = confirmed
        self.completed = True
        return self.data


class ReviewStep(WizardStep):
    """Wizard step for reviewing configuration."""
    
    def __init__(self, title: str = "Review Configuration", description: str = ""):
        """Initialize review step."""
        super().__init__(title, description)
    
    async def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute review step."""
        console.print(f"\n[bold blue]{self.title}[/bold blue]")
        if self.description:
            console.print(f"[dim]{self.description}[/dim]")
        
        # Display configuration summary
        tree = Tree("📋 Configuration Summary")
        
        for step_name, step_data in context.items():
            if isinstance(step_data, dict) and step_data:
                step_tree = tree.add(f"[bold]{step_name.replace('_', ' ').title()}[/bold]")
                for key, value in step_data.items():
                    if key != 'confirmed':  # Skip confirmation flags
                        step_tree.add(f"{key}: [green]{value}[/green]")
        
        console.print(tree)
        
        # Confirm to proceed
        confirmed = Confirm.ask("\nProceed with this configuration?", default=True)
        self.data['confirmed'] = confirmed
        self.completed = True
        return self.data


class Wizard:
    """Interactive wizard for complex operations."""
    
    def __init__(self, title: str, description: str = ""):
        """Initialize wizard."""
        self.title = title
        self.description = description
        self.steps: List[WizardStep] = []
        self.context: Dict[str, Any] = {}
        self.current_step = 0
    
    def add_step(self, step: WizardStep) -> None:
        """Add a step to the wizard."""
        self.steps.append(step)
    
    async def run(self) -> Dict[str, Any]:
        """Run the wizard."""
        console.print(Panel(
            f"[bold]{self.title}[/bold]\n{self.description}",
            title="🧙 Interactive Wizard",
            border_style="blue"
        ))
        
        # Show navigation help
        console.print("[dim]Navigation: Enter values as prompted, 'back' to go back, 'quit' to exit[/dim]\n")
        
        while self.current_step < len(self.steps):
            step = self.steps[self.current_step]
            
            try:
                # Show progress
                console.print(f"[dim]Step {self.current_step + 1} of {len(self.steps)}[/dim]")
                
                step_data = await step.execute(self.context)
                step_name = step.title.lower().replace(" ", "_")
                self.context[step_name] = step_data
                
                self.current_step += 1
                
            except KeyboardInterrupt:
                if Confirm.ask("\nQuit wizard?", default=False):
                    raise typer.Exit(1)
                continue
            except Exception as e:
                console.print(f"[red]Error in step: {e}[/red]")
                if not Confirm.ask("Continue anyway?", default=False):
                    raise typer.Exit(1)
                self.current_step += 1
        
        return self.context


class UserCreationWizard(Wizard):
    """Interactive wizard for creating users."""
    
    def __init__(self):
        """Initialize user creation wizard."""
        super().__init__(
            "User Creation Wizard",
            "Create a new VPN user with guided configuration"
        )
        
        # Username step
        self.add_step(InputStep(
            title="Username",
            prompt_text="Enter username",
            description="Username must be 3-50 characters, alphanumeric, hyphens, and underscores only",
            validator=self._validate_username
        ))
        
        # Protocol step
        self.add_step(ChoiceStep(
            title="VPN Protocol",
            choices={
                "vless": "VLESS with Reality (recommended for censorship resistance)",
                "shadowsocks": "Shadowsocks (fast and lightweight)",
                "wireguard": "WireGuard (modern kernel-level VPN)",
                "http": "HTTP Proxy (simple web proxy)",
                "socks5": "SOCKS5 Proxy (versatile proxy protocol)"
            },
            default="vless",
            description="Choose the VPN protocol for this user"
        ))
        
        # Email step (optional)
        self.add_step(InputStep(
            title="Email Address",
            prompt_text="Enter email address (optional)",
            description="Email for notifications and account management",
            required=False,
            validator=self._validate_email
        ))
        
        # Expiration step
        self.add_step(ChoiceStep(
            title="Account Expiration",
            choices={
                "never": "Never expires",
                "30": "30 days",
                "90": "90 days",
                "180": "6 months",
                "365": "1 year",
                "custom": "Custom duration"
            },
            default="never",
            description="Set when the user account should expire"
        ))
        
        # Traffic limit step
        self.add_step(ChoiceStep(
            title="Traffic Limit",
            choices={
                "unlimited": "Unlimited traffic",
                "10gb": "10 GB per month",
                "50gb": "50 GB per month",
                "100gb": "100 GB per month",
                "500gb": "500 GB per month",
                "custom": "Custom limit"
            },
            default="unlimited",
            description="Set monthly traffic limit for the user"
        ))
        
        # Review step
        self.add_step(ReviewStep())
    
    def _validate_username(self, username: str) -> bool:
        """Validate username format."""
        if len(username) < 3 or len(username) > 50:
            console.print("[red]Username must be 3-50 characters[/red]")
            return False
        
        if not re.match(r'^[a-zA-Z0-9_-]+$', username):
            console.print("[red]Username can only contain letters, numbers, hyphens, and underscores[/red]")
            return False
        
        return True
    
    def _validate_email(self, email: str) -> bool:
        """Validate email format."""
        if not email:  # Optional field
            return True
        
        if not re.match(r'^[^@]+@[^@]+\.[^@]+$', email):
            console.print("[red]Invalid email format[/red]")
            return False
        
        return True


class ServerSetupWizard(Wizard):
    """Interactive wizard for server setup."""
    
    def __init__(self):
        """Initialize server setup wizard."""
        super().__init__(
            "Server Setup Wizard",
            "Set up a new VPN server with guided configuration"
        )
        
        # Server name
        self.add_step(InputStep(
            title="Server Name",
            prompt_text="Enter server name",
            description="Unique name for the server (e.g., 'production', 'development')",
            validator=self._validate_server_name
        ))
        
        # Protocol
        self.add_step(ChoiceStep(
            title="Server Protocol",
            choices={
                "vless": "VLESS with Reality",
                "shadowsocks": "Shadowsocks",
                "wireguard": "WireGuard",
                "unified_proxy": "Unified Proxy (HTTP/SOCKS5)"
            },
            default="vless",
            description="Choose the main protocol for this server"
        ))
        
        # Port
        self.add_step(InputStep(
            title="Server Port",
            prompt_text="Enter port number (1024-65535)",
            default="8443",
            description="Port number for the server to listen on",
            validator=self._validate_port
        ))
        
        # Auto-start
        self.add_step(ConfirmationStep(
            title="Auto-start",
            prompt_text="Start server automatically after creation?",
            default=True,
            description="Whether to start the server immediately after setup"
        ))
        
        # Review
        self.add_step(ReviewStep())
    
    def _validate_server_name(self, name: str) -> bool:
        """Validate server name."""
        if len(name) < 1 or len(name) > 64:
            console.print("[red]Server name must be 1-64 characters[/red]")
            return False
        
        if not re.match(r'^[a-zA-Z0-9_-]+$', name):
            console.print("[red]Server name can only contain letters, numbers, hyphens, and underscores[/red]")
            return False
        
        return True
    
    def _validate_port(self, port_str: str) -> bool:
        """Validate port number."""
        try:
            port = int(port_str)
            if port < 1024 or port > 65535:
                console.print("[red]Port must be between 1024 and 65535[/red]")
                return False
            return True
        except ValueError:
            console.print("[red]Port must be a number[/red]")
            return False


class BulkOperationWizard(Wizard):
    """Interactive wizard for bulk operations."""
    
    def __init__(self, operation_type: str):
        """Initialize bulk operation wizard."""
        super().__init__(
            f"Bulk {operation_type.title()} Wizard",
            f"Perform bulk {operation_type} operations with guided configuration"
        )
        self.operation_type = operation_type
        
        if operation_type == "user_creation":
            self._setup_bulk_user_creation()
        elif operation_type == "user_deletion":
            self._setup_bulk_user_deletion()
        elif operation_type == "server_management":
            self._setup_bulk_server_management()
    
    def _setup_bulk_user_creation(self):
        """Set up bulk user creation steps."""
        # Number of users
        self.add_step(InputStep(
            title="Number of Users",
            prompt_text="How many users to create? (1-100)",
            default="5",
            description="Enter the number of users to create in bulk",
            validator=lambda x: self._validate_count(x, 1, 100)
        ))
        
        # Username pattern
        self.add_step(InputStep(
            title="Username Pattern",
            prompt_text="Enter username pattern (use {n} for number)",
            default="user{n}",
            description="Pattern for generating usernames. {n} will be replaced with numbers",
            validator=self._validate_pattern
        ))
        
        # Protocol
        self.add_step(ChoiceStep(
            title="Protocol for All Users",
            choices={
                "vless": "VLESS with Reality",
                "shadowsocks": "Shadowsocks",
                "wireguard": "WireGuard",
                "mixed": "Mixed protocols (will cycle through available protocols)"
            },
            default="vless",
            description="Choose protocol(s) for bulk user creation"
        ))
        
        # Starting number
        self.add_step(InputStep(
            title="Starting Number",
            prompt_text="Starting number for username pattern",
            default="1",
            description="The first number to use in the username pattern",
            validator=lambda x: self._validate_count(x, 1, 9999)
        ))
        
        # Review
        self.add_step(ReviewStep())
    
    def _setup_bulk_user_deletion(self):
        """Set up bulk user deletion steps."""
        # Selection method
        self.add_step(ChoiceStep(
            title="Selection Method",
            choices={
                "pattern": "Delete users matching pattern",
                "inactive": "Delete inactive users",
                "expired": "Delete expired users",
                "list": "Delete from user list"
            },
            default="pattern",
            description="How to select users for deletion"
        ))
        
        # Confirmation
        self.add_step(ConfirmationStep(
            title="Confirmation",
            prompt_text="This will permanently delete users. Are you sure?",
            default=False,
            description="This action cannot be undone"
        ))
        
        # Review
        self.add_step(ReviewStep())
    
    def _setup_bulk_server_management(self):
        """Set up bulk server management steps."""
        # Operation
        self.add_step(ChoiceStep(
            title="Server Operation",
            choices={
                "start": "Start servers",
                "stop": "Stop servers",
                "restart": "Restart servers",
                "update": "Update server configurations"
            },
            default="restart",
            description="Choose the operation to perform on servers"
        ))
        
        # Server selection
        self.add_step(ChoiceStep(
            title="Server Selection",
            choices={
                "all": "All servers",
                "running": "Only running servers",
                "stopped": "Only stopped servers",
                "pattern": "Servers matching pattern",
                "manual": "Manually select servers"
            },
            default="all",
            description="Which servers to include in the operation"
        ))
        
        # Review
        self.add_step(ReviewStep())
    
    def _validate_count(self, value: str, min_val: int, max_val: int) -> bool:
        """Validate count value."""
        try:
            count = int(value)
            if count < min_val or count > max_val:
                console.print(f"[red]Value must be between {min_val} and {max_val}[/red]")
                return False
            return True
        except ValueError:
            console.print("[red]Value must be a number[/red]")
            return False
    
    def _validate_pattern(self, pattern: str) -> bool:
        """Validate username pattern."""
        if "{n}" not in pattern:
            console.print("[red]Pattern must contain {n} placeholder[/red]")
            return False
        
        # Test pattern
        try:
            test_name = pattern.format(n=1)
            if not re.match(r'^[a-zA-Z0-9_-]+$', test_name):
                console.print("[red]Pattern generates invalid usernames[/red]")
                return False
        except Exception:
            console.print("[red]Invalid pattern format[/red]")
            return False
        
        return True


async def interactive_user_creation() -> Optional[Dict[str, Any]]:
    """Run interactive user creation wizard."""
    wizard = UserCreationWizard()
    
    try:
        result = await wizard.run()
        
        # Process the results
        if result.get('review_configuration', {}).get('confirmed', False):
            console.print("\n[green]✓ User configuration completed![/green]")
            return result
        else:
            console.print("\n[yellow]User creation cancelled[/yellow]")
            return None
    
    except Exception as e:
        console.print(f"\n[red]Error in user creation wizard: {e}[/red]")
        return None


async def interactive_server_setup() -> Optional[Dict[str, Any]]:
    """Run interactive server setup wizard."""
    wizard = ServerSetupWizard()
    
    try:
        result = await wizard.run()
        
        if result.get('review_configuration', {}).get('confirmed', False):
            console.print("\n[green]✓ Server configuration completed![/green]")
            return result
        else:
            console.print("\n[yellow]Server setup cancelled[/yellow]")
            return None
    
    except Exception as e:
        console.print(f"\n[red]Error in server setup wizard: {e}[/red]")
        return None


async def interactive_bulk_operation(operation_type: str) -> Optional[Dict[str, Any]]:
    """Run interactive bulk operation wizard."""
    wizard = BulkOperationWizard(operation_type)
    
    try:
        result = await wizard.run()
        
        if result.get('review_configuration', {}).get('confirmed', False):
            console.print(f"\n[green]✓ Bulk {operation_type} configuration completed![/green]")
            return result
        else:
            console.print(f"\n[yellow]Bulk {operation_type} cancelled[/yellow]")
            return None
    
    except Exception as e:
        console.print(f"\n[red]Error in bulk {operation_type} wizard: {e}[/red]")
        return None


def setup_interactive_commands(app: typer.Typer) -> None:
    """Set up interactive mode commands."""
    
    @app.command("interactive")
    def interactive_mode():
        """Launch interactive mode for guided operations."""
        
        console.print(Panel(
            "[bold]VPN Manager Interactive Mode[/bold]\n"
            "Choose an operation to perform with guided assistance:",
            title="🧙 Interactive Mode",
            border_style="blue"
        ))
        
        operations = {
            "1": ("Create User", "Guided user creation with step-by-step configuration"),
            "2": ("Setup Server", "Interactive server setup and configuration"),
            "3": ("Bulk User Creation", "Create multiple users at once"),
            "4": ("Bulk User Deletion", "Delete multiple users with safety checks"),
            "5": ("Bulk Server Management", "Manage multiple servers simultaneously"),
            "6": ("System Configuration", "Configure system settings interactively"),
            "7": ("Import/Export", "Import or export configurations"),
            "q": ("Quit", "Exit interactive mode")
        }
        
        while True:
            console.print("\n[bold]Available Operations:[/bold]")
            table = Table(show_header=False, box=None, padding=(0, 2))
            table.add_column("Option", style="green", width=8)
            table.add_column("Operation", style="blue", width=20)
            table.add_column("Description", style="dim")
            
            for key, (name, desc) in operations.items():
                table.add_row(f"[{key}]", name, desc)
            
            console.print(table)
            
            choice = Prompt.ask("\nEnter your choice", choices=list(operations.keys()))
            
            if choice == "q":
                console.print("[yellow]Goodbye![/yellow]")
                break
            elif choice == "1":
                asyncio.run(interactive_user_creation())
            elif choice == "2":
                asyncio.run(interactive_server_setup())
            elif choice == "3":
                asyncio.run(interactive_bulk_operation("user_creation"))
            elif choice == "4":
                asyncio.run(interactive_bulk_operation("user_deletion"))
            elif choice == "5":
                asyncio.run(interactive_bulk_operation("server_management"))
            elif choice == "6":
                console.print("[yellow]System configuration wizard coming soon![/yellow]")
            elif choice == "7":
                console.print("[yellow]Import/Export wizard coming soon![/yellow]")
            
            if choice != "q":
                if not Confirm.ask("\nPerform another operation?", default=True):
                    break
    
    @app.command("wizard")
    def wizard_mode(
        operation: str = typer.Argument(
            help="Wizard type: user, server, bulk-users, bulk-servers"
        )
    ):
        """Run specific operation wizard."""
        
        if operation == "user":
            asyncio.run(interactive_user_creation())
        elif operation == "server":
            asyncio.run(interactive_server_setup())
        elif operation == "bulk-users":
            asyncio.run(interactive_bulk_operation("user_creation"))
        elif operation == "bulk-servers":
            asyncio.run(interactive_bulk_operation("server_management"))
        else:
            console.print(f"[red]Unknown wizard type: {operation}[/red]")
            console.print("Available wizards: user, server, bulk-users, bulk-servers")
            raise typer.Exit(1)