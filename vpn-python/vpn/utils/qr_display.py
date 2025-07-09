"""
Terminal QR code display utilities for VPN connection links.
"""

import io
from typing import Optional

import qrcode
from rich.console import Console
from rich.panel import Panel
from rich.text import Text

from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class TerminalQRCode:
    """Generate and display QR codes in terminal."""
    
    def __init__(self, console: Optional[Console] = None):
        self.console = console or Console()
    
    def generate_ascii_qr(self, data: str, border: int = 2) -> str:
        """Generate ASCII QR code for terminal display."""
        try:
            # Create QR code instance
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=1,
                border=border,
            )
            
            qr.add_data(data)
            qr.make(fit=True)
            
            # Generate ASCII representation
            f = io.StringIO()
            qr.print_ascii(out=f, tty=False)
            f.seek(0)
            return f.read()
            
        except Exception as e:
            logger.error(f"Failed to generate QR code: {e}")
            return f"Error generating QR code: {e}"
    
    def generate_unicode_qr(self, data: str, border: int = 1) -> str:
        """Generate Unicode QR code using block characters."""
        try:
            # Create QR code instance
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=1,
                border=border,
            )
            
            qr.add_data(data)
            qr.make(fit=True)
            
            # Get the matrix
            matrix = qr.get_matrix()
            
            # Convert to unicode blocks
            result = []
            for i in range(0, len(matrix), 2):
                line = []
                for j in range(len(matrix[i])):
                    top = matrix[i][j] if i < len(matrix) else False
                    bottom = matrix[i + 1][j] if i + 1 < len(matrix) else False
                    
                    if top and bottom:
                        line.append('█')  # Full block
                    elif top:
                        line.append('▀')  # Upper half block
                    elif bottom:
                        line.append('▄')  # Lower half block
                    else:
                        line.append(' ')  # Empty space
                
                result.append(''.join(line))
            
            return '\n'.join(result)
            
        except Exception as e:
            logger.error(f"Failed to generate unicode QR code: {e}")
            return f"Error generating QR code: {e}"
    
    def display_qr_code(
        self,
        data: str,
        title: str = "QR Code",
        style: str = "unicode",
        show_data: bool = True
    ) -> None:
        """Display QR code in terminal with optional title and data."""
        try:
            if style == "unicode":
                qr_text = self.generate_unicode_qr(data)
            else:
                qr_text = self.generate_ascii_qr(data)
            
            # Create content for panel
            content = Text()
            content.append(qr_text, style="white")
            
            if show_data:
                content.append("\n\n")
                content.append("Connection URL:\n", style="bold cyan")
                content.append(data, style="blue")
            
            # Display in a panel
            panel = Panel(
                content,
                title=f"📱 {title}",
                title_align="left",
                border_style="green",
                padding=(1, 2)
            )
            
            self.console.print(panel)
            
        except Exception as e:
            logger.error(f"Failed to display QR code: {e}")
            self.console.print(f"[red]Error displaying QR code: {e}[/red]")
    
    def display_connection_qr(
        self,
        connection_url: str,
        username: str,
        protocol: str,
        style: str = "unicode"
    ) -> None:
        """Display QR code for VPN connection with formatted info."""
        try:
            # Create title with user and protocol info
            title = f"{protocol.upper()} Connection - {username}"
            
            # Display QR code
            self.display_qr_code(
                data=connection_url,
                title=title,
                style=style,
                show_data=True
            )
            
            # Add usage instructions
            self.console.print("\n[dim]📱 Scan this QR code with your VPN client to connect[/dim]")
            self.console.print("[dim]💡 Or copy the connection URL manually[/dim]")
            
        except Exception as e:
            logger.error(f"Failed to display connection QR: {e}")
            self.console.print(f"[red]Error displaying connection QR: {e}[/red]")
    
    def save_qr_image(self, data: str, filename: str, size: int = 10) -> bool:
        """Save QR code as image file."""
        try:
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=size,
                border=4,
            )
            
            qr.add_data(data)
            qr.make(fit=True)
            
            # Create image
            img = qr.make_image(fill_color="black", back_color="white")
            img.save(filename)
            
            logger.info(f"QR code saved to: {filename}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to save QR code image: {e}")
            return False


def display_qr_code(
    data: str,
    title: str = "QR Code",
    style: str = "unicode",
    show_data: bool = True,
    console: Optional[Console] = None
) -> None:
    """Convenience function to display QR code."""
    qr_display = TerminalQRCode(console)
    qr_display.display_qr_code(data, title, style, show_data)


def display_connection_qr(
    connection_url: str,
    username: str,
    protocol: str,
    style: str = "unicode",
    console: Optional[Console] = None
) -> None:
    """Convenience function to display connection QR code."""
    qr_display = TerminalQRCode(console)
    qr_display.display_connection_qr(connection_url, username, protocol, style)


def generate_qr_ascii(data: str) -> str:
    """Generate ASCII QR code string."""
    qr_display = TerminalQRCode()
    return qr_display.generate_ascii_qr(data)


def generate_qr_unicode(data: str) -> str:
    """Generate Unicode QR code string."""
    qr_display = TerminalQRCode()
    return qr_display.generate_unicode_qr(data)