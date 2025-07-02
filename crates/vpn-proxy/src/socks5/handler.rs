//! SOCKS5 server handler

use super::{AuthMethod, Command, Reply, Socks5Request};
use crate::{
    error::{ProxyError, Result},
    manager::ProxyManager,
};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tracing::{debug, error, info, warn};

/// SOCKS5 server implementation
#[derive(Clone)]
pub struct Socks5Server {
    manager: ProxyManager,
}

impl Socks5Server {
    /// Create a new SOCKS5 server
    pub fn new(manager: ProxyManager) -> Self {
        Self { manager }
    }
    
    /// Handle an incoming SOCKS5 connection
    pub async fn handle_connection(
        &self,
        client: TcpStream,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        let start_time = Instant::now();
        let protocol = "socks5";
        
        self.manager.metrics().record_connection(protocol, true);
        
        let result = self.handle_connection_inner(client, peer_addr).await;
        
        // Record metrics
        let duration = start_time.elapsed().as_secs_f64();
        self.manager.metrics().record_request_duration(protocol, "proxy", duration);
        self.manager.metrics().record_connection_closed(protocol);
        
        result
    }
    
    async fn handle_connection_inner(
        &self,
        mut client: TcpStream,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        debug!("New SOCKS5 connection from {}", peer_addr);
        
        // Handle authentication
        let user_id = self.handle_authentication(&mut client, peer_addr).await?;
        
        // Handle request
        let request = super::protocol::read_request(&mut client).await?;
        
        debug!("SOCKS5 {:?} request from {} to {:?}:{}", 
            request.command, user_id, request.address, request.port);
        
        // Check rate limit
        if let Err(e) = self.manager.check_rate_limit(&user_id).await {
            warn!("Rate limit exceeded for user {}: {}", user_id, e);
            super::protocol::send_reply(&mut client, Reply::ConnectionNotAllowed, peer_addr).await?;
            return Err(e);
        }
        
        // Handle command
        match request.command {
            Command::Connect => {
                self.handle_connect(client, request, &user_id).await
            }
            Command::Bind => {
                self.handle_bind(client, request, &user_id).await
            }
            Command::UdpAssociate => {
                self.handle_udp_associate(client, request, &user_id, peer_addr).await
            }
        }
    }
    
    /// Handle SOCKS5 authentication
    async fn handle_authentication(
        &self,
        client: &mut TcpStream,
        peer_addr: SocketAddr,
    ) -> Result<String> {
        // Read authentication methods
        let methods = super::protocol::read_auth_methods(client).await?;
        
        debug!("Client {} supports {} auth methods", peer_addr, methods.len());
        
        // Check if authentication is required
        let auth_required = self.manager.config().auth.enabled;
        
        if !auth_required && methods.contains(&AuthMethod::NoAuth) {
            // No authentication required
            client.write_all(&[0x05, AuthMethod::NoAuth as u8]).await?;
            return Ok("anonymous".to_string());
        }
        
        if auth_required && methods.contains(&AuthMethod::UserPass) {
            // Username/password authentication
            client.write_all(&[0x05, AuthMethod::UserPass as u8]).await?;
            
            // Read username/password
            let (username, password) = super::protocol::read_user_pass_auth(client).await?;
            
            // Authenticate
            match self.manager.authenticate(Some((username.clone(), password.clone())), peer_addr).await {
                Ok(user_id) => {
                    // Send success
                    client.write_all(&[0x01, 0x00]).await?;
                    Ok(user_id)
                }
                Err(e) => {
                    // Send failure
                    client.write_all(&[0x01, 0x01]).await?;
                    Err(e)
                }
            }
        } else {
            // No acceptable authentication method
            client.write_all(&[0x05, AuthMethod::NoAcceptable as u8]).await?;
            Err(ProxyError::socks5("No acceptable authentication method"))
        }
    }
    
    /// Handle CONNECT command
    async fn handle_connect(
        &self,
        mut client: TcpStream,
        request: Socks5Request,
        user_id: &str,
    ) -> Result<()> {
        // Resolve target address
        let target_addr = self.resolve_address(&request).await?;
        
        info!("SOCKS5 CONNECT from {} to {}", user_id, target_addr);
        
        // Connect to target
        let upstream = match self.manager.get_connection(target_addr).await {
            Ok(conn) => conn,
            Err(e) => {
                error!("Failed to connect to {}: {}", target_addr, e);
                let reply = match e {
                    ProxyError::Timeout => Reply::TtlExpired,
                    ProxyError::UpstreamConnectionFailed(_) => Reply::ConnectionRefused,
                    _ => Reply::GeneralFailure,
                };
                super::protocol::send_reply(&mut client, reply, target_addr).await?;
                return Err(e);
            }
        };
        
        // Send success reply
        let local_addr = upstream.local_addr()
            .unwrap_or_else(|_| SocketAddr::new(IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0)), 0));
        super::protocol::send_reply(&mut client, Reply::Success, local_addr).await?;
        
        // Start proxying data
        self.proxy_data(client, upstream, user_id).await
    }
    
    /// Resolve address from SOCKS5 address type
    async fn resolve_address(&self, request: &Socks5Request) -> Result<SocketAddr> {
        use super::AddressType;
        
        match &request.address {
            AddressType::IPv4(bytes) => {
                let ip = Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3]);
                Ok(SocketAddr::new(IpAddr::V4(ip), request.port))
            }
            AddressType::IPv6(bytes) => {
                let ip = Ipv6Addr::from(*bytes);
                Ok(SocketAddr::new(IpAddr::V6(ip), request.port))
            }
            AddressType::Domain(domain) => {
                // DNS resolution
                let addr = format!("{}:{}", domain, request.port);
                let mut resolved = tokio::net::lookup_host(&addr).await?;
                resolved
                    .next()
                    .ok_or_else(|| ProxyError::socks5(format!("Failed to resolve {}", domain)))
            }
        }
    }
    
    /// Proxy data between client and upstream
    async fn proxy_data(
        &self,
        client: TcpStream,
        upstream: TcpStream,
        user_id: &str,
    ) -> Result<()> {
        let (client_reader, client_writer) = client.into_split();
        let (upstream_reader, upstream_writer) = upstream.into_split();
        
        let client_to_upstream = tokio::spawn({
            let user_id = user_id.to_string();
            let manager = self.manager.clone();
            async move {
                proxy_direction(
                    client_reader,
                    upstream_writer,
                    "client->upstream",
                    &user_id,
                    &manager,
                ).await
            }
        });
        
        let upstream_to_client = tokio::spawn({
            let user_id = user_id.to_string();
            let manager = self.manager.clone();
            async move {
                proxy_direction(
                    upstream_reader,
                    client_writer,
                    "upstream->client",
                    &user_id,
                    &manager,
                ).await
            }
        });
        
        // Wait for either direction to complete
        tokio::select! {
            result = client_to_upstream => {
                if let Err(e) = result {
                    error!("Client to upstream task failed: {}", e);
                }
            }
            result = upstream_to_client => {
                if let Err(e) = result {
                    error!("Upstream to client task failed: {}", e);
                }
            }
        }
        
        debug!("SOCKS5 proxy closed for user {}", user_id);
        
        Ok(())
    }
    
    /// Handle BIND command
    async fn handle_bind(
        &self,
        mut client: TcpStream,
        request: Socks5Request,
        user_id: &str,
    ) -> Result<()> {
        // BIND is used for FTP-style protocols where the server initiates a connection back
        info!("SOCKS5 BIND request from {} to {:?}:{}", user_id, request.address, request.port);
        
        // Create a listener on a random port
        let bind_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0)), 0);
        let listener = tokio::net::TcpListener::bind(bind_addr).await?;
        let local_addr = listener.local_addr()?;
        
        info!("BIND listener created at {} for user {}", local_addr, user_id);
        
        // Send first reply with the bind address
        super::protocol::send_reply(&mut client, Reply::Success, local_addr).await?;
        
        // Wait for incoming connection (with timeout)
        let (inbound, remote_addr) = tokio::time::timeout(
            std::time::Duration::from_secs(30),
            listener.accept()
        )
        .await
        .map_err(|_| ProxyError::Timeout)??;
        
        info!("BIND connection received from {} for user {}", remote_addr, user_id);
        
        // Verify the connection is from expected address if specified
        use super::AddressType;
        if let AddressType::IPv4(bytes) = &request.address {
            let expected_ip = Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3]);
            if expected_ip != Ipv4Addr::new(0, 0, 0, 0) && remote_addr.ip() != IpAddr::V4(expected_ip) {
                return Err(ProxyError::socks5("BIND connection from unexpected address"));
            }
        }
        
        // Send second reply with the remote address
        super::protocol::send_reply(&mut client, Reply::Success, remote_addr).await?;
        
        // Start proxying data between client and inbound connection
        self.proxy_data(client, inbound, user_id).await
    }
    
    /// Handle UDP ASSOCIATE command
    async fn handle_udp_associate(
        &self,
        mut client: TcpStream,
        request: Socks5Request,
        user_id: &str,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        info!("SOCKS5 UDP ASSOCIATE request from {} for {:?}:{}", 
            user_id, request.address, request.port);
        
        // Create UDP socket for relay
        let udp_bind_addr = match peer_addr {
            SocketAddr::V4(_) => SocketAddr::new(IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0)), 0),
            SocketAddr::V6(_) => SocketAddr::new(IpAddr::V6(Ipv6Addr::UNSPECIFIED), 0),
        };
        
        let udp_socket = tokio::net::UdpSocket::bind(udp_bind_addr).await?;
        let udp_addr = udp_socket.local_addr()?;
        
        info!("UDP relay socket created at {} for user {}", udp_addr, user_id);
        
        // Send reply with UDP relay address
        super::protocol::send_reply(&mut client, Reply::Success, udp_addr).await?;
        
        // Start UDP relay task
        let manager = self.manager.clone();
        let user_id_clone = user_id.to_string();
        
        tokio::spawn(async move {
            if let Err(e) = handle_udp_relay(udp_socket, client, &user_id_clone, manager).await {
                error!("UDP relay error for user {}: {}", user_id_clone, e);
            }
        });
        
        Ok(())
    }
}

/// Proxy data in one direction
async fn proxy_direction<R, W>(
    mut reader: R,
    mut writer: W,
    direction: &str,
    user_id: &str,
    manager: &ProxyManager,
) -> Result<()>
where
    R: AsyncReadExt + Unpin,
    W: AsyncWriteExt + Unpin,
{
    let mut buffer = vec![0u8; 8192];
    let mut total_bytes = 0u64;
    
    loop {
        let n = match reader.read(&mut buffer).await {
            Ok(0) => {
                debug!("Connection closed ({}) after {} bytes", direction, total_bytes);
                break;
            }
            Ok(n) => n,
            Err(e) => {
                debug!("Read error ({}): {}", direction, e);
                break;
            }
        };
        
        if let Err(e) = writer.write_all(&buffer[..n]).await {
            debug!("Write error ({}): {}", direction, e);
            break;
        }
        
        if let Err(e) = writer.flush().await {
            debug!("Flush error ({}): {}", direction, e);
            break;
        }
        
        total_bytes += n as u64;
        
        // Record bandwidth for client->upstream direction
        if direction == "client->upstream" {
            if let Err(e) = manager.record_bandwidth(user_id, n as u64).await {
                error!("Failed to record bandwidth: {}", e);
            }
        }
    }
    
    debug!("SOCKS5 {} closed after {} bytes", direction, total_bytes);
    
    // Record total bytes transferred
    let metric_direction = if direction == "client->upstream" { "upload" } else { "download" };
    manager.metrics().record_bytes_transferred(total_bytes, metric_direction);
    
    Ok(())
}

/// Handle UDP relay for SOCKS5 UDP ASSOCIATE
async fn handle_udp_relay(
    udp_socket: tokio::net::UdpSocket,
    tcp_client: TcpStream,
    user_id: &str,
    manager: ProxyManager,
) -> Result<()> {
    
    info!("Starting UDP relay for user {}", user_id);
    
    let mut udp_buf = vec![0u8; 65535]; // Maximum UDP packet size
    let mut associations: std::collections::HashMap<SocketAddr, SocketAddr> = std::collections::HashMap::new();
    
    loop {
        tokio::select! {
            // Check if TCP connection is still alive
            _ = tcp_client.readable() => {
                let mut buf = [0u8; 1];
                match tcp_client.try_read(&mut buf) {
                    Ok(0) => {
                        info!("TCP control connection closed for user {}", user_id);
                        break;
                    }
                    Ok(_) => {
                        // Control connection should not send data after UDP ASSOCIATE
                        warn!("Unexpected data on control connection from user {}", user_id);
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        // Connection still alive
                    }
                    Err(e) => {
                        error!("Error reading control connection: {}", e);
                        break;
                    }
                }
            }
            
            // Handle UDP packets
            result = udp_socket.recv_from(&mut udp_buf) => {
                match result {
                    Ok((len, from_addr)) => {
                        // Parse SOCKS5 UDP header
                        if len < 10 {
                            warn!("UDP packet too small from {}", from_addr);
                            continue;
                        }
                        
                        // SOCKS5 UDP header format:
                        // +----+------+------+----------+----------+----------+
                        // |RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
                        // +----+------+------+----------+----------+----------+
                        // | 2  |  1   |  1   | Variable |    2     | Variable |
                        // +----+------+------+----------+----------+----------+
                        
                        let frag = udp_buf[2];
                        if frag != 0 {
                            warn!("Fragmented UDP packets not supported");
                            continue;
                        }
                        
                        // Parse destination address
                        let atyp = udp_buf[3];
                        let (dst_addr, header_len) = match atyp {
                            0x01 => {
                                // IPv4
                                if len < 10 {
                                    continue;
                                }
                                let ip = Ipv4Addr::new(udp_buf[4], udp_buf[5], udp_buf[6], udp_buf[7]);
                                let port = u16::from_be_bytes([udp_buf[8], udp_buf[9]]);
                                (SocketAddr::new(IpAddr::V4(ip), port), 10)
                            }
                            0x03 => {
                                // Domain name
                                let domain_len = udp_buf[4] as usize;
                                if len < 7 + domain_len {
                                    continue;
                                }
                                // For now, skip domain resolution in UDP relay
                                warn!("Domain names in UDP relay not yet supported");
                                continue;
                            }
                            0x04 => {
                                // IPv6
                                if len < 22 {
                                    continue;
                                }
                                let mut ipv6_bytes = [0u8; 16];
                                ipv6_bytes.copy_from_slice(&udp_buf[4..20]);
                                let ip = Ipv6Addr::from(ipv6_bytes);
                                let port = u16::from_be_bytes([udp_buf[20], udp_buf[21]]);
                                (SocketAddr::new(IpAddr::V6(ip), port), 22)
                            }
                            _ => {
                                warn!("Invalid address type in UDP packet: {}", atyp);
                                continue;
                            }
                        };
                        
                        // Store association
                        associations.insert(dst_addr, from_addr);
                        
                        // Forward the data (without SOCKS5 header)
                        let data = &udp_buf[header_len..len];
                        if let Err(e) = udp_socket.send_to(data, dst_addr).await {
                            error!("Failed to forward UDP packet to {}: {}", dst_addr, e);
                        }
                        
                        // Record bandwidth
                        let _ = manager.record_bandwidth(user_id, data.len() as u64).await;
                    }
                    Err(e) => {
                        error!("UDP receive error: {}", e);
                        break;
                    }
                }
            }
        }
    }
    
    info!("UDP relay ended for user {}", user_id);
    Ok(())
}