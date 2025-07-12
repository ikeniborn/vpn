# Proxy Authentication Configuration Example

This example shows how to integrate proxy authentication into the VPN Manager TUI.

## Integration in the App

To handle proxy authentication dialog in your app, add this to your screen or app class:

```python
from vpn.tui.dialogs.proxy_auth_dialog import ProxyAuthDialog
from vpn.tui.handlers.proxy_auth_handler import ProxyAuthHandler
from vpn.tui.widgets.server_status import ServerStatus

class ServersScreen(BaseScreen):
    """Server management screen with proxy auth support."""
    
    def __init__(self):
        super().__init__()
        self.auth_handler = ProxyAuthHandler()
    
    @on(ServerStatus.ServerAction)
    async def handle_server_action(self, event: ServerStatus.ServerAction) -> None:
        """Handle server actions from the status widget."""
        if event.action == "auth_config":
            # Show proxy authentication dialog
            await self.show_proxy_auth_dialog(event.server_name)
        elif event.action == "add_user":
            # Quick add user dialog
            await self.show_add_user_dialog(event.server_name)
        # ... handle other actions
    
    async def show_proxy_auth_dialog(self, server_name: str) -> None:
        """Show proxy authentication configuration dialog."""
        # Get current auth config if exists
        current_auth = await self.get_server_auth_config(server_name)
        
        # Show dialog
        dialog = ProxyAuthDialog(server_name, current_auth)
        auth_config = await self.push_screen_wait(dialog)
        
        if auth_config:
            # Apply configuration
            success = await self.auth_handler.configure_proxy_auth(
                server_name, auth_config
            )
            
            if success:
                self.notify(
                    f"Authentication configured for {server_name}",
                    severity="information"
                )
                # Restart server to apply changes
                await self.restart_proxy_server(server_name)
            else:
                self.notify(
                    "Failed to configure authentication",
                    severity="error"
                )
```

## Usage Example

### 1. Right-click on a proxy server in the server list
### 2. Select "Configure Authentication" from the context menu
### 3. In the dialog:
   - Choose authentication mode (None, Basic, IP Whitelist, or Combined)
   - For Basic Auth:
     - Add username/password pairs
     - Manage existing users
   - For IP Whitelist:
     - Add allowed IP addresses or CIDR ranges
### 4. Click "Save" to apply changes

## Authentication Modes

### No Authentication
- Open proxy accessible to anyone
- Not recommended for production

### Basic Authentication
- Username/password authentication
- Uses HTTP Basic Auth for HTTP proxy
- Uses SOCKS5 authentication for SOCKS proxy

### IP Whitelist
- Only allows connections from specified IP addresses
- Good for restricting access to known networks

### Combined (Basic + IP)
- Requires both valid credentials AND allowed IP
- Maximum security for production environments

## Configuration Files

After configuring authentication, the following files are updated:

### Squid (HTTP Proxy)
- `/path/to/server/config/squid.conf` - Updated with auth settings
- `/path/to/server/config/passwords` - Htpasswd file with user credentials

### Dante (SOCKS5 Proxy)
- `/path/to/server/config/danted.conf` - Updated with auth method
- `/path/to/server/config/danted.users` - User credentials file

## Testing Authentication

### HTTP Proxy with curl
```bash
# Without auth
curl -x http://server:8080 https://example.com

# With auth
curl -x http://username:password@server:8080 https://example.com
```

### SOCKS5 Proxy with curl
```bash
# Without auth
curl -x socks5://server:1080 https://example.com

# With auth
curl -x socks5://username:password@server:1080 https://example.com
```

## Troubleshooting

### Authentication not working
1. Check if the proxy server was restarted after configuration
2. Verify credentials are correct
3. Check proxy logs for authentication errors

### Cannot add users
1. Ensure you have write permissions to the config directory
2. Check if the passwords file exists and is writable

### IP whitelist not working
1. Verify IP addresses are in correct format
2. Check firewall rules are not blocking connections
3. Ensure CIDR notation is correct (e.g., 192.168.1.0/24)