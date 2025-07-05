//! HTTP proxy request handler

use super::{HttpMethod, HttpRequest};
use crate::{
    error::{ProxyError, Result},
    manager::ProxyManager,
};
use std::net::SocketAddr;
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tracing::{debug, error, info, warn};

/// HTTP proxy handler
#[derive(Clone)]
pub struct HttpProxy {
    manager: ProxyManager,
}

impl HttpProxy {
    /// Create a new HTTP proxy handler
    pub fn new(manager: ProxyManager) -> Self {
        Self { manager }
    }

    /// Handle an incoming connection
    pub async fn handle_connection(&self, client: TcpStream, peer_addr: SocketAddr) -> Result<()> {
        let start_time = Instant::now();
        let protocol = "http";

        self.manager.metrics().record_connection(protocol, true);

        let result = self.handle_connection_inner(client, peer_addr).await;

        // Record metrics
        let duration = start_time.elapsed().as_secs_f64();
        self.manager
            .metrics()
            .record_request_duration(protocol, "proxy", duration);
        self.manager.metrics().record_connection_closed(protocol);

        result
    }

    async fn handle_connection_inner(
        &self,
        mut client: TcpStream,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        loop {
            // Read request
            let request = match super::parser::parse_request(&mut client).await {
                Ok(req) => req,
                Err(e) => {
                    if matches!(e, ProxyError::Io(_)) {
                        // Connection closed
                        debug!("Client {} closed connection", peer_addr);
                        return Ok(());
                    }
                    error!("Failed to parse request from {}: {}", peer_addr, e);
                    self.send_error_response(&mut client, 400, "Bad Request")
                        .await?;
                    return Err(e);
                }
            };

            debug!(
                "HTTP {} request from {} to {}",
                request.method.as_str(),
                peer_addr,
                request.uri
            );

            // Authenticate if required
            let user_id = match self
                .manager
                .authenticate(request.proxy_auth(), peer_addr)
                .await
            {
                Ok(id) => id,
                Err(e) => {
                    warn!("Authentication failed for {}: {}", peer_addr, e);
                    self.send_auth_required_response(&mut client).await?;
                    continue;
                }
            };

            // Check rate limit
            if let Err(e) = self.manager.check_rate_limit(&user_id).await {
                warn!("Rate limit exceeded for user {}: {}", user_id, e);
                self.send_error_response(&mut client, 429, "Too Many Requests")
                    .await?;
                continue;
            }

            // Handle the request
            let keep_alive = request.keep_alive();

            match request.method {
                HttpMethod::Connect => {
                    // HTTPS tunneling
                    self.handle_connect(client, request, &user_id).await?;
                    // CONNECT always closes the connection after tunneling
                    return Ok(());
                }
                _ => {
                    // Regular HTTP proxy
                    self.handle_http_request(&mut client, request, &user_id)
                        .await?;
                }
            }

            // Check if we should keep the connection alive
            if !keep_alive {
                debug!("Closing connection to {} (keep-alive disabled)", peer_addr);
                return Ok(());
            }
        }
    }

    /// Handle CONNECT method for HTTPS tunneling
    async fn handle_connect(
        &self,
        mut client: TcpStream,
        request: HttpRequest,
        user_id: &str,
    ) -> Result<()> {
        // Parse target address
        let target_addr = self.parse_connect_target(&request.uri)?;

        info!("CONNECT tunnel from {} to {}", user_id, target_addr);

        // Connect to target
        let upstream = match self.manager.get_connection(target_addr).await {
            Ok(conn) => conn,
            Err(e) => {
                error!("Failed to connect to {}: {}", target_addr, e);
                self.send_error_response(&mut client, 502, "Bad Gateway")
                    .await?;
                return Err(e);
            }
        };

        // Send 200 OK response
        client
            .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            .await?;
        client.flush().await?;

        // Start tunneling
        super::tunnel::tunnel_data(client, upstream, user_id, &self.manager).await?;

        Ok(())
    }

    /// Handle regular HTTP requests
    async fn handle_http_request(
        &self,
        client: &mut TcpStream,
        request: HttpRequest,
        user_id: &str,
    ) -> Result<()> {
        // Parse target URL
        let (host, port) = self.parse_http_target(&request)?;
        let target_addr: SocketAddr = format!("{}:{}", host, port)
            .parse()
            .map_err(|e| ProxyError::invalid_request(format!("Invalid target address: {}", e)))?;

        debug!(
            "HTTP {} request from {} to {}",
            request.method.as_str(),
            user_id,
            target_addr
        );

        // Connect to target
        let mut upstream = match self.manager.get_connection(target_addr).await {
            Ok(conn) => conn,
            Err(e) => {
                error!("Failed to connect to {}: {}", target_addr, e);
                self.send_error_response(client, 502, "Bad Gateway").await?;
                return Err(e);
            }
        };

        // Forward the request
        self.forward_http_request(&mut upstream, request).await?;

        // Read and forward the response
        self.forward_http_response(&mut upstream, client, user_id)
            .await?;

        // Return connection to pool
        self.manager.return_connection(target_addr, upstream).await;

        Ok(())
    }

    /// Parse CONNECT target address
    fn parse_connect_target(&self, uri: &str) -> Result<SocketAddr> {
        let parts: Vec<&str> = uri.split(':').collect();
        if parts.len() != 2 {
            return Err(ProxyError::invalid_request("Invalid CONNECT target"));
        }

        let host = parts[0];
        let port: u16 = parts[1]
            .parse()
            .map_err(|_| ProxyError::invalid_request("Invalid port number"))?;

        format!("{}:{}", host, port)
            .parse()
            .map_err(|e| ProxyError::invalid_request(format!("Invalid target address: {}", e)))
    }

    /// Parse HTTP target from request
    fn parse_http_target(&self, request: &HttpRequest) -> Result<(String, u16)> {
        // Check absolute URI first
        if request.uri.starts_with("http://") {
            let url = request.uri.strip_prefix("http://").unwrap();
            let parts: Vec<&str> = url.splitn(2, '/').collect();
            let host_port = parts[0];

            let parts: Vec<&str> = host_port.split(':').collect();
            let host = parts[0].to_string();
            let port = if parts.len() > 1 {
                parts[1]
                    .parse()
                    .map_err(|_| ProxyError::invalid_request("Invalid port number"))?
            } else {
                80
            };

            Ok((host, port))
        } else {
            // Use Host header
            let host_header = request
                .host()
                .ok_or_else(|| ProxyError::invalid_request("Missing Host header"))?;

            let parts: Vec<&str> = host_header.split(':').collect();
            let host = parts[0].to_string();
            let port = if parts.len() > 1 {
                parts[1]
                    .parse()
                    .map_err(|_| ProxyError::invalid_request("Invalid port in Host header"))?
            } else {
                80
            };

            Ok((host, port))
        }
    }

    /// Forward HTTP request to upstream
    async fn forward_http_request(
        &self,
        upstream: &mut TcpStream,
        request: HttpRequest,
    ) -> Result<()> {
        // Build request line
        let request_line = format!(
            "{} {} {}\r\n",
            request.method.as_str(),
            request.uri,
            request.version
        );

        upstream.write_all(request_line.as_bytes()).await?;

        // Forward headers (skip Proxy-Authorization)
        for (name, value) in &request.headers {
            if name.to_lowercase() != "proxy-authorization" {
                let header_line = format!("{}: {}\r\n", name, value);
                upstream.write_all(header_line.as_bytes()).await?;
            }
        }

        upstream.write_all(b"\r\n").await?;

        // Forward body if present
        if let Some(body) = request.body {
            upstream.write_all(&body).await?;
        }

        upstream.flush().await?;

        Ok(())
    }

    /// Forward HTTP response from upstream to client
    async fn forward_http_response(
        &self,
        upstream: &mut TcpStream,
        client: &mut TcpStream,
        user_id: &str,
    ) -> Result<()> {
        let mut buffer = vec![0u8; 8192];
        let mut total_bytes = 0u64;

        loop {
            let n = upstream.read(&mut buffer).await?;
            if n == 0 {
                break;
            }

            client.write_all(&buffer[..n]).await?;
            total_bytes += n as u64;

            // Record bandwidth
            self.manager.record_bandwidth(user_id, n as u64).await?;
        }

        client.flush().await?;

        debug!("Forwarded {} bytes of response to {}", total_bytes, user_id);

        Ok(())
    }

    /// Send error response
    async fn send_error_response(
        &self,
        client: &mut TcpStream,
        code: u16,
        reason: &str,
    ) -> Result<()> {
        let response = format!(
            "HTTP/1.1 {} {}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            code, reason
        );

        client.write_all(response.as_bytes()).await?;
        client.flush().await?;

        Ok(())
    }

    /// Send authentication required response
    async fn send_auth_required_response(&self, client: &mut TcpStream) -> Result<()> {
        let response = "HTTP/1.1 407 Proxy Authentication Required\r\n\
                       Proxy-Authenticate: Basic realm=\"Proxy\"\r\n\
                       Content-Length: 0\r\n\
                       Connection: close\r\n\r\n";

        client.write_all(response.as_bytes()).await?;
        client.flush().await?;

        Ok(())
    }
}
