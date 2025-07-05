//! SOCKS5 proxy implementation

mod handler;
mod protocol;

pub use handler::Socks5Server;

/// SOCKS5 authentication methods
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum AuthMethod {
    NoAuth = 0x00,
    GssApi = 0x01,
    UserPass = 0x02,
    NoAcceptable = 0xFF,
}

impl AuthMethod {
    fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0x00 => Some(Self::NoAuth),
            0x01 => Some(Self::GssApi),
            0x02 => Some(Self::UserPass),
            0xFF => Some(Self::NoAcceptable),
            _ => None,
        }
    }
}

/// SOCKS5 command
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum Command {
    Connect = 0x01,
    Bind = 0x02,
    UdpAssociate = 0x03,
}

impl Command {
    fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0x01 => Some(Self::Connect),
            0x02 => Some(Self::Bind),
            0x03 => Some(Self::UdpAssociate),
            _ => None,
        }
    }
}

/// SOCKS5 address type
#[derive(Debug, Clone, PartialEq)]
pub enum AddressType {
    IPv4([u8; 4]),
    Domain(String),
    IPv6([u8; 16]),
}

/// SOCKS5 reply code
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum Reply {
    Success = 0x00,
    GeneralFailure = 0x01,
    ConnectionNotAllowed = 0x02,
    NetworkUnreachable = 0x03,
    HostUnreachable = 0x04,
    ConnectionRefused = 0x05,
    TtlExpired = 0x06,
    CommandNotSupported = 0x07,
    AddressTypeNotSupported = 0x08,
}

/// SOCKS5 request
#[derive(Debug)]
pub struct Socks5Request {
    pub command: Command,
    pub address: AddressType,
    pub port: u16,
}
