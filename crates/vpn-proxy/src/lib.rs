//! VPN Proxy Server Implementation
//!
//! This crate provides HTTP/HTTPS and SOCKS5 proxy server functionality
//! with authentication, rate limiting, and monitoring capabilities.

pub mod config;
pub mod error;
pub mod http;
pub mod socks5;
pub mod auth;
pub mod metrics;
pub mod manager;
pub mod pool;
pub mod rate_limit;

pub use config::{ProxyConfig, ProxyProtocol};
pub use error::{ProxyError, Result};
pub use manager::ProxyManager;
pub use metrics::ProxyMetrics;

use tokio::net::TcpListener;
use tracing::{info, error};

/// Main proxy server that can handle both HTTP and SOCKS5 protocols
pub struct ProxyServer {
    config: ProxyConfig,
    manager: ProxyManager,
    metrics: ProxyMetrics,
}

impl ProxyServer {
    /// Create a new proxy server instance
    pub fn new(config: ProxyConfig) -> Result<Self> {
        let metrics = ProxyMetrics::new()?;
        let manager = ProxyManager::new(config.clone(), metrics.clone())?;
        
        Ok(Self {
            config,
            manager,
            metrics,
        })
    }
    
    /// Start the proxy server
    pub async fn start(&self) -> Result<()> {
        match self.config.protocol {
            ProxyProtocol::Http => self.start_http_proxy().await,
            ProxyProtocol::Socks5 => self.start_socks5_proxy().await,
            ProxyProtocol::Both => self.start_combined_proxy().await,
        }
    }
    
    /// Start HTTP/HTTPS proxy server
    async fn start_http_proxy(&self) -> Result<()> {
        let addr = self.config.bind_address()?;
        info!("Starting HTTP proxy server on {}", addr);
        
        let listener = TcpListener::bind(addr).await?;
        let http_proxy = http::HttpProxy::new(self.manager.clone());
        
        loop {
            let (socket, peer_addr) = listener.accept().await?;
            let proxy = http_proxy.clone();
            
            tokio::spawn(async move {
                if let Err(e) = proxy.handle_connection(socket, peer_addr).await {
                    error!("HTTP proxy error from {}: {}", peer_addr, e);
                }
            });
        }
    }
    
    /// Start SOCKS5 proxy server
    async fn start_socks5_proxy(&self) -> Result<()> {
        let addr = self.config.socks5_bind_address()?;
        info!("Starting SOCKS5 proxy server on {}", addr);
        
        let listener = TcpListener::bind(addr).await?;
        let socks_proxy = socks5::Socks5Server::new(self.manager.clone());
        
        loop {
            let (socket, peer_addr) = listener.accept().await?;
            let proxy = socks_proxy.clone();
            
            tokio::spawn(async move {
                if let Err(e) = proxy.handle_connection(socket, peer_addr).await {
                    error!("SOCKS5 proxy error from {}: {}", peer_addr, e);
                }
            });
        }
    }
    
    /// Start both HTTP and SOCKS5 proxy servers
    async fn start_combined_proxy(&self) -> Result<()> {
        let http_handle = {
            let server = self.clone();
            tokio::spawn(async move {
                server.start_http_proxy().await
            })
        };
        
        let socks_handle = {
            let server = self.clone();
            tokio::spawn(async move {
                server.start_socks5_proxy().await
            })
        };
        
        // Wait for both servers
        tokio::try_join!(http_handle, socks_handle)
            .map_err(|e| ProxyError::internal(format!("Task join error: {}", e)))?;
        Ok(())
    }
    
    /// Get server metrics
    pub fn metrics(&self) -> &ProxyMetrics {
        &self.metrics
    }
    
    /// Shutdown the proxy server gracefully
    pub async fn shutdown(&self) -> Result<()> {
        info!("Shutting down proxy server");
        self.manager.shutdown().await?;
        Ok(())
    }
}

impl Clone for ProxyServer {
    fn clone(&self) -> Self {
        Self {
            config: self.config.clone(),
            manager: self.manager.clone(),
            metrics: self.metrics.clone(),
        }
    }
}