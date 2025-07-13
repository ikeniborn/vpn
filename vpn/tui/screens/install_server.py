"""VPN server installation screen."""

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Grid, Horizontal, Vertical
from textual.widgets import Button, Input, Label, RadioButton, RadioSet, Static

from vpn.core.models import ProtocolType
from vpn.tui.screens.base import BaseScreen


class InstallServerScreen(BaseScreen):
    """Screen for installing new VPN servers."""

    DEFAULT_CSS = """
    InstallServerScreen {
        background: $surface;
    }
    
    .install-form {
        width: 60;
        margin: 2 auto;
        padding: 2;
        border: solid $primary;
    }
    
    .form-group {
        margin: 1 0;
    }
    
    .form-label {
        margin: 0 0 1 0;
        text-style: bold;
    }
    
    .form-input {
        width: 100%;
    }
    
    .button-group {
        margin: 2 0 0 0;
    }
    
    .protocol-radio {
        margin: 0 1;
    }
    """

    BINDINGS = [
        Binding("escape", "app.pop_screen", "Back"),
        Binding("ctrl+s", "install", "Install"),
    ]

    def __init__(self):
        """Initialize install server screen."""
        super().__init__()
        self.selected_protocol = ProtocolType.VLESS

    def compose(self) -> ComposeResult:
        """Create installation form layout."""
        yield from self.compose_header("Install VPN Server", "Configure and install new VPN server")
        
        with Container(classes="install-form"):
            yield Static("🚀 VPN Server Installation", classes="form-title")
            
            # Protocol selection
            with Vertical(classes="form-group"):
                yield Label("Select Protocol:", classes="form-label")
                with RadioSet(id="protocol-set"):
                    yield RadioButton("VLESS + Reality", value=True, id="protocol-vless")
                    yield RadioButton("Shadowsocks", id="protocol-shadowsocks")
                    yield RadioButton("WireGuard", id="protocol-wireguard")
            
            # Port configuration
            with Vertical(classes="form-group"):
                yield Label("Server Port:", classes="form-label")
                yield Input(
                    placeholder="Enter port (e.g., 8443)",
                    id="port-input",
                    classes="form-input",
                    value="8443"
                )
            
            # Domain configuration (for VLESS)
            with Vertical(classes="form-group", id="domain-group"):
                yield Label("Reality Domain (for VLESS):", classes="form-label")
                yield Input(
                    placeholder="e.g., www.google.com",
                    id="domain-input",
                    classes="form-input",
                    value="www.google.com"
                )
            
            # Server name
            with Vertical(classes="form-group"):
                yield Label("Server Name (optional):", classes="form-label")
                yield Input(
                    placeholder="Enter server name",
                    id="name-input",
                    classes="form-input"
                )
            
            # Action buttons
            with Horizontal(classes="button-group"):
                yield Button("Install", variant="primary", id="install-btn")
                yield Button("Cancel", variant="default", id="cancel-btn")

    def on_radio_set_changed(self, event: RadioSet.Changed) -> None:
        """Handle protocol selection change."""
        if event.radio_set.id == "protocol-set":
            # Determine selected protocol
            if self.query_one("#protocol-vless", RadioButton).value:
                self.selected_protocol = ProtocolType.VLESS
                self.query_one("#domain-group").display = True
            elif self.query_one("#protocol-shadowsocks", RadioButton).value:
                self.selected_protocol = ProtocolType.SHADOWSOCKS
                self.query_one("#domain-group").display = False
            elif self.query_one("#protocol-wireguard", RadioButton).value:
                self.selected_protocol = ProtocolType.WIREGUARD
                self.query_one("#domain-group").display = False

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        if event.button.id == "install-btn":
            self.action_install()
        elif event.button.id == "cancel-btn":
            self.app.pop_screen()

    async def action_install(self) -> None:
        """Install VPN server with selected configuration."""
        # Get form values
        port = self.query_one("#port-input", Input).value
        domain = self.query_one("#domain-input", Input).value if self.selected_protocol == ProtocolType.VLESS else None
        name = self.query_one("#name-input", Input).value or None
        
        # Validate input
        if not port or not port.isdigit():
            self.notify("Please enter a valid port number", severity="error")
            return
        
        if self.selected_protocol == ProtocolType.VLESS and not domain:
            self.notify("Please enter a reality domain for VLESS", severity="error")
            return
        
        # Show loading state
        self.notify(f"Installing {self.selected_protocol.value} server...", severity="information")
        
        try:
            # Install server
            result = await self.server_manager.install(
                protocol=self.selected_protocol,
                port=int(port),
                reality_domain=domain,
                name=name
            )
            
            if result.success:
                self.notify(
                    f"✅ {self.selected_protocol.value} server installed successfully on port {port}!",
                    severity="success"
                )
                # Go back to main menu
                self.app.pop_screen()
            else:
                self.notify(
                    f"❌ Installation failed: {result.message}",
                    severity="error"
                )
        except Exception as e:
            self.notify(
                f"❌ Error during installation: {str(e)}",
                severity="error"
            )