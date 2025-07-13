"""Cryptographic operations service.
"""

import base64
import io
import secrets
from uuid import uuid4

import qrcode
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from vpn.core.exceptions import CryptoError
from vpn.core.models import CryptoKeys, ProtocolType
from vpn.services.base import BaseService
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class CryptoService(BaseService):
    """Service for cryptographic operations."""

    async def generate_keys(self, protocol: ProtocolType) -> CryptoKeys:
        """Generate cryptographic keys for the specified protocol.
        
        Args:
            protocol: VPN protocol type
            
        Returns:
            Generated keys
        """
        keys = CryptoKeys()

        if protocol == ProtocolType.VLESS:
            # Generate UUID for VLESS
            keys.uuid = str(uuid4())

            # Generate X25519 key pair for Reality
            private_key_obj, public_key = await self.generate_x25519_keypair()
            keys.private_key = private_key_obj
            keys.public_key = public_key

            # Generate short ID (8 hex chars)
            keys.short_id = secrets.token_hex(4)

        elif protocol == ProtocolType.SHADOWSOCKS:
            # Generate password for Shadowsocks
            keys.password = await self.generate_password(32)

        elif protocol == ProtocolType.WIREGUARD:
            # Generate WireGuard key pair
            private_key_obj, public_key = await self.generate_x25519_keypair()
            keys.private_key = private_key_obj
            keys.public_key = public_key

        elif protocol in (ProtocolType.HTTP, ProtocolType.SOCKS5):
            # Generate username and password for proxy
            keys.password = await self.generate_password(16)

        logger.debug(f"Generated keys for protocol: {protocol}")
        return keys

    async def generate_x25519_keypair(self) -> tuple[str, str]:
        """Generate X25519 key pair.
        
        Returns:
            Tuple of (private_key_base64, public_key_base64)
        """
        try:
            # Generate private key
            private_key = X25519PrivateKey.generate()

            # Get public key
            public_key = private_key.public_key()

            # Serialize to base64
            private_bytes = private_key.private_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PrivateFormat.Raw,
                encryption_algorithm=serialization.NoEncryption()
            )

            public_bytes = public_key.public_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PublicFormat.Raw
            )

            private_b64 = base64.b64encode(private_bytes).decode('utf-8')
            public_b64 = base64.b64encode(public_bytes).decode('utf-8')

            return private_b64, public_b64

        except Exception as e:
            logger.error(f"Failed to generate X25519 keypair: {e}")
            raise CryptoError(f"X25519 key generation failed: {e}")

    async def generate_uuid(self) -> str:
        """Generate a random UUID v4."""
        return str(uuid4())

    async def generate_password(
        self,
        length: int = 16,
        include_special: bool = True
    ) -> str:
        """Generate a secure random password.
        
        Args:
            length: Password length
            include_special: Include special characters
            
        Returns:
            Generated password
        """
        # Character sets
        lowercase = "abcdefghijklmnopqrstuvwxyz"
        uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        digits = "0123456789"
        special = "!@#$%^&*()_+-=[]{}|;:,.<>?"

        # Build character set
        chars = lowercase + uppercase + digits
        if include_special:
            chars += special

        # Generate password
        password = ''.join(secrets.choice(chars) for _ in range(length))

        # Ensure at least one character from each set
        password_list = list(password)
        password_list[0] = secrets.choice(lowercase)
        password_list[1] = secrets.choice(uppercase)
        password_list[2] = secrets.choice(digits)
        if include_special and length >= 4:
            password_list[3] = secrets.choice(special)

        # Shuffle to avoid predictable positions
        import random
        random.shuffle(password_list)

        return ''.join(password_list)

    async def generate_qr_code(
        self,
        data: str,
        format: str = "base64"
    ) -> str:
        """Generate QR code for the given data.
        
        Args:
            data: Data to encode in QR code
            format: Output format ('base64' or 'ascii')
            
        Returns:
            QR code as base64 string or ASCII art
        """
        try:
            qr = qrcode.QRCode(
                version=None,  # Auto-determine size
                error_correction=qrcode.constants.ERROR_CORRECT_L,
                box_size=10,
                border=4,
            )

            qr.add_data(data)
            qr.make(fit=True)

            if format == "base64":
                # Generate image and convert to base64
                img = qr.make_image(fill_color="black", back_color="white")

                # Save to bytes buffer
                buffer = io.BytesIO()
                img.save(buffer, format='PNG')
                buffer.seek(0)

                # Convert to base64
                img_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
                return f"data:image/png;base64,{img_base64}"

            elif format == "ascii":
                # Generate ASCII art QR code

                buffer = io.StringIO()
                qr.print_ascii(out=buffer, tty=False, invert=False)
                return buffer.getvalue()

            else:
                raise ValueError(f"Unsupported QR code format: {format}")

        except Exception as e:
            logger.error(f"Failed to generate QR code: {e}")
            raise CryptoError(f"QR code generation failed: {e}")

    async def encode_base64(self, data: bytes) -> str:
        """Encode bytes to base64 string."""
        return base64.b64encode(data).decode('utf-8')

    async def decode_base64(self, data: str) -> bytes:
        """Decode base64 string to bytes."""
        try:
            return base64.b64decode(data)
        except Exception as e:
            raise CryptoError(f"Base64 decode failed: {e}")

    async def hash_password(self, password: str) -> str:
        """Hash password using Argon2.
        
        Args:
            password: Plain text password
            
        Returns:
            Hashed password
        """
        try:
            from argon2 import PasswordHasher

            ph = PasswordHasher()
            return ph.hash(password)

        except ImportError:
            # Fallback to bcrypt if argon2 not available
            import bcrypt

            salt = bcrypt.gensalt()
            return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')
        except Exception as e:
            logger.error(f"Failed to hash password: {e}")
            raise CryptoError(f"Password hashing failed: {e}")

    async def verify_password(self, password: str, hash: str) -> bool:
        """Verify password against hash.
        
        Args:
            password: Plain text password
            hash: Password hash
            
        Returns:
            True if password matches
        """
        try:
            from argon2 import PasswordHasher
            from argon2.exceptions import VerifyMismatchError

            ph = PasswordHasher()
            try:
                ph.verify(hash, password)
                return True
            except VerifyMismatchError:
                return False

        except ImportError:
            # Fallback to bcrypt
            import bcrypt

            return bcrypt.checkpw(password.encode('utf-8'), hash.encode('utf-8'))
        except Exception as e:
            logger.error(f"Failed to verify password: {e}")
            return False

    async def generate_token(self, length: int = 32) -> str:
        """Generate a secure random token."""
        return secrets.token_urlsafe(length)

    async def rotate_keys(
        self,
        protocol: ProtocolType,
        current_keys: CryptoKeys
    ) -> CryptoKeys:
        """Rotate cryptographic keys.
        
        Args:
            protocol: Protocol type
            current_keys: Current keys to rotate
            
        Returns:
            New keys
        """
        # Generate new keys
        new_keys = await self.generate_keys(protocol)

        # Preserve UUID for VLESS (client identifier)
        if protocol == ProtocolType.VLESS and current_keys.uuid:
            new_keys.uuid = current_keys.uuid

        logger.info(f"Rotated keys for protocol: {protocol}")
        return new_keys
