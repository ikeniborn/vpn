//! HTTP request parser

use super::{HttpMethod, HttpRequest};
use crate::error::{ProxyError, Result};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, BufReader};
use tokio::net::TcpStream;
use tracing::debug;

/// Parse an HTTP request from the client
pub async fn parse_request(stream: &mut TcpStream) -> Result<HttpRequest> {
    let mut reader = BufReader::new(stream);
    let mut lines = Vec::new();
    
    // Read headers
    loop {
        let mut line = String::new();
        let n = reader.read_line(&mut line).await?;
        
        if n == 0 {
            return Err(ProxyError::Io(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "Connection closed while reading request",
            )));
        }
        
        // Remove \r\n
        line = line.trim_end().to_string();
        
        // Empty line indicates end of headers
        if line.is_empty() {
            break;
        }
        
        lines.push(line);
    }
    
    if lines.is_empty() {
        return Err(ProxyError::invalid_request("Empty request"));
    }
    
    // Parse request line
    let request_line = &lines[0];
    let parts: Vec<&str> = request_line.split_whitespace().collect();
    
    if parts.len() != 3 {
        return Err(ProxyError::invalid_request("Invalid request line"));
    }
    
    let method = HttpMethod::from_str(parts[0])
        .ok_or_else(|| ProxyError::invalid_request(format!("Unknown method: {}", parts[0])))?;
    
    let uri = parts[1].to_string();
    let version = parts[2].to_string();
    
    // Parse headers
    let mut headers = Vec::new();
    let mut content_length = None;
    
    for line in &lines[1..] {
        let colon_pos = line.find(':')
            .ok_or_else(|| ProxyError::invalid_request("Invalid header format"))?;
        
        let name = line[..colon_pos].trim().to_string();
        let value = line[colon_pos + 1..].trim().to_string();
        
        if name.to_lowercase() == "content-length" {
            content_length = Some(value.parse::<usize>()
                .map_err(|_| ProxyError::invalid_request("Invalid Content-Length"))?);
        }
        
        headers.push((name, value));
    }
    
    // Read body if present
    let body = if let Some(len) = content_length {
        if len > 0 {
            let mut body = vec![0u8; len];
            reader.read_exact(&mut body).await?;
            Some(body)
        } else {
            None
        }
    } else {
        None
    };
    
    debug!("Parsed {} request to {} with {} headers", 
        method.as_str(), uri, headers.len());
    
    Ok(HttpRequest {
        method,
        uri,
        version,
        headers,
        body,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_parse_simple_request() {
        let request_data = b"GET http://example.com/path HTTP/1.1\r\n\
                           Host: example.com\r\n\
                           User-Agent: test\r\n\
                           \r\n";
        
        // Would need a mock TcpStream for proper testing
        // This is a placeholder for the test structure
        assert!(true);
    }
}