//! SOCKS5 protocol implementation

use super::{AddressType, AuthMethod, Command, Reply, Socks5Request};
use crate::error::{ProxyError, Result};
use std::net::SocketAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tracing::debug;

/// Read authentication methods from client
pub async fn read_auth_methods(stream: &mut TcpStream) -> Result<Vec<AuthMethod>> {
    let mut header = [0u8; 2];
    stream.read_exact(&mut header).await?;

    if header[0] != 0x05 {
        return Err(ProxyError::socks5(format!(
            "Invalid SOCKS version: {}",
            header[0]
        )));
    }

    let nmethods = header[1] as usize;
    if nmethods == 0 {
        return Err(ProxyError::socks5("No authentication methods provided"));
    }

    let mut methods_buf = vec![0u8; nmethods];
    stream.read_exact(&mut methods_buf).await?;

    let methods: Vec<AuthMethod> = methods_buf
        .iter()
        .filter_map(|&b| AuthMethod::from_byte(b))
        .collect();

    debug!("Client supports auth methods: {:?}", methods);

    Ok(methods)
}

/// Read username/password authentication
pub async fn read_user_pass_auth(stream: &mut TcpStream) -> Result<(String, String)> {
    let mut header = [0u8; 2];
    stream.read_exact(&mut header).await?;

    if header[0] != 0x01 {
        return Err(ProxyError::socks5(format!(
            "Invalid auth version: {}",
            header[0]
        )));
    }

    // Read username
    let ulen = header[1] as usize;
    if ulen == 0 {
        return Err(ProxyError::socks5("Empty username"));
    }

    let mut username_buf = vec![0u8; ulen];
    stream.read_exact(&mut username_buf).await?;
    let username = String::from_utf8(username_buf)
        .map_err(|_| ProxyError::socks5("Invalid username encoding"))?;

    // Read password length
    let mut plen_buf = [0u8; 1];
    stream.read_exact(&mut plen_buf).await?;
    let plen = plen_buf[0] as usize;

    if plen == 0 {
        return Err(ProxyError::socks5("Empty password"));
    }

    let mut password_buf = vec![0u8; plen];
    stream.read_exact(&mut password_buf).await?;
    let password = String::from_utf8(password_buf)
        .map_err(|_| ProxyError::socks5("Invalid password encoding"))?;

    debug!("Received auth for user: {}", username);

    Ok((username, password))
}

/// Read SOCKS5 request
pub async fn read_request(stream: &mut TcpStream) -> Result<Socks5Request> {
    let mut header = [0u8; 4];
    stream.read_exact(&mut header).await?;

    if header[0] != 0x05 {
        return Err(ProxyError::socks5(format!(
            "Invalid SOCKS version: {}",
            header[0]
        )));
    }

    let command = Command::from_byte(header[1])
        .ok_or_else(|| ProxyError::socks5(format!("Invalid command: {}", header[1])))?;

    if header[2] != 0x00 {
        return Err(ProxyError::socks5("Reserved field must be 0"));
    }

    let atyp = header[3];

    let address = match atyp {
        0x01 => {
            // IPv4
            let mut addr = [0u8; 4];
            stream.read_exact(&mut addr).await?;
            AddressType::IPv4(addr)
        }
        0x03 => {
            // Domain name
            let mut len_buf = [0u8; 1];
            stream.read_exact(&mut len_buf).await?;
            let len = len_buf[0] as usize;

            let mut domain_buf = vec![0u8; len];
            stream.read_exact(&mut domain_buf).await?;

            let domain = String::from_utf8(domain_buf)
                .map_err(|_| ProxyError::socks5("Invalid domain encoding"))?;

            AddressType::Domain(domain)
        }
        0x04 => {
            // IPv6
            let mut addr = [0u8; 16];
            stream.read_exact(&mut addr).await?;
            AddressType::IPv6(addr)
        }
        _ => {
            return Err(ProxyError::socks5(format!(
                "Invalid address type: {}",
                atyp
            )));
        }
    };

    // Read port
    let mut port_buf = [0u8; 2];
    stream.read_exact(&mut port_buf).await?;
    let port = u16::from_be_bytes(port_buf);

    Ok(Socks5Request {
        command,
        address,
        port,
    })
}

/// Send SOCKS5 reply
pub async fn send_reply(stream: &mut TcpStream, reply: Reply, addr: SocketAddr) -> Result<()> {
    let mut response = vec![0x05, reply as u8, 0x00];

    match addr {
        SocketAddr::V4(addr) => {
            response.push(0x01); // IPv4
            response.extend_from_slice(&addr.ip().octets());
        }
        SocketAddr::V6(addr) => {
            response.push(0x04); // IPv6
            response.extend_from_slice(&addr.ip().octets());
        }
    }

    response.extend_from_slice(&addr.port().to_be_bytes());

    stream.write_all(&response).await?;
    stream.flush().await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_method_from_byte() {
        assert_eq!(AuthMethod::from_byte(0x00), Some(AuthMethod::NoAuth));
        assert_eq!(AuthMethod::from_byte(0x02), Some(AuthMethod::UserPass));
        assert_eq!(AuthMethod::from_byte(0xFF), Some(AuthMethod::NoAcceptable));
        assert_eq!(AuthMethod::from_byte(0x99), None);
    }

    #[test]
    fn test_command_from_byte() {
        assert_eq!(Command::from_byte(0x01), Some(Command::Connect));
        assert_eq!(Command::from_byte(0x02), Some(Command::Bind));
        assert_eq!(Command::from_byte(0x03), Some(Command::UdpAssociate));
        assert_eq!(Command::from_byte(0x99), None);
    }
}
