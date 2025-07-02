//! HTTP tunnel implementation for CONNECT method

use crate::{
    error::Result,
    manager::ProxyManager,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tracing::{debug, error};

/// Tunnel data between client and upstream server
pub async fn tunnel_data(
    client: &mut TcpStream,
    upstream: TcpStream,
    user_id: &str,
    manager: &ProxyManager,
) -> Result<()> {
    let (client_reader, client_writer) = client.split();
    let (upstream_reader, upstream_writer) = upstream.into_split();
    
    let client_to_upstream = tokio::spawn({
        let user_id = user_id.to_string();
        let manager = manager.clone();
        async move {
            tunnel_direction(
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
        let manager = manager.clone();
        async move {
            tunnel_direction(
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
    
    debug!("Tunnel closed for user {}", user_id);
    
    Ok(())
}

/// Tunnel data in one direction
async fn tunnel_direction<R, W>(
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
    
    debug!("Tunnel {} closed after {} bytes", direction, total_bytes);
    
    // Record total bytes transferred
    let metric_direction = if direction == "client->upstream" { "upload" } else { "download" };
    manager.metrics().record_bytes_transferred(total_bytes, metric_direction);
    
    Ok(())
}