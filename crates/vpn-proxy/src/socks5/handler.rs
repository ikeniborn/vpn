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
        mut client: TcpStream,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        let start_time = Instant::now();
        let protocol = "socks5";
        
        self.manager.metrics().record_connection(protocol, true);
        
        let result = self.handle_connection_inner(&mut client, peer_addr).await;
        
        // Record metrics
        let duration = start_time.elapsed().as_secs_f64();
        self.manager.metrics().record_request_duration(protocol, "proxy", duration);
        self.manager.metrics().record_connection_closed(protocol);
        
        result
    }
    
    async fn handle_connection_inner(
        &self,
        client: &mut TcpStream,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        debug!("New SOCKS5 connection from {}", peer_addr);
        
        // Handle authentication
        let user_id = self.handle_authentication(client, peer_addr).await?;
        
        // Handle request
        let request = super::protocol::read_request(client).await?;
        
        debug!("SOCKS5 {:?} request from {} to {:?}:{}", 
            request.command, user_id, request.address, request.port);
        
        // Check rate limit
        if let Err(e) = self.manager.check_rate_limit(&user_id).await {
            warn!("Rate limit exceeded for user {}: {}", user_id, e);
            super::protocol::send_reply(client, Reply::ConnectionNotAllowed, peer_addr).await?;
            return Err(e);
        }
        
        // Handle command
        match request.command {
            Command::Connect => {
                self.handle_connect(client, request, &user_id).await
            }
            Command::Bind => {
                super::protocol::send_reply(client, Reply::CommandNotSupported, peer_addr).await?;
                Err(ProxyError::socks5("BIND command not supported"))
            }
            Command::UdpAssociate => {
                super::protocol::send_reply(client, Reply::CommandNotSupported, peer_addr).await?;
                Err(ProxyError::socks5("UDP ASSOCIATE command not supported"))
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
            match self.manager.authenticate(Some((&username, &password)), peer_addr).await {
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
        client: &mut TcpStream,
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
                super::protocol::send_reply(client, reply, target_addr).await?;
                return Err(e);
            }
        };
        
        // Send success reply
        let local_addr = upstream.local_addr()
            .unwrap_or_else(|_| SocketAddr::new(IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0)), 0));
        super::protocol::send_reply(client, Reply::Success, local_addr).await?;
        
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
                tokio::net::lookup_host(&addr)
                    .await?
                    .next()
                    .ok_or_else(|| ProxyError::socks5(format!("Failed to resolve {}", domain)))
            }
        }
    }
    
    /// Proxy data between client and upstream
    async fn proxy_data(
        &self,
        client: &mut TcpStream,
        upstream: TcpStream,
        user_id: &str,
    ) -> Result<()> {
        let (client_reader, client_writer) = client.split();
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