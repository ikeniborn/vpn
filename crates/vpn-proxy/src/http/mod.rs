//! HTTP/HTTPS proxy implementation

mod handler;
mod parser;
mod tunnel;

pub use handler::HttpProxy;

/// HTTP methods we support
#[derive(Debug, Clone, PartialEq)]
pub enum HttpMethod {
    Connect,
    Get,
    Post,
    Put,
    Delete,
    Head,
    Options,
    Patch,
    Trace,
}

impl HttpMethod {
    fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "CONNECT" => Some(Self::Connect),
            "GET" => Some(Self::Get),
            "POST" => Some(Self::Post),
            "PUT" => Some(Self::Put),
            "DELETE" => Some(Self::Delete),
            "HEAD" => Some(Self::Head),
            "OPTIONS" => Some(Self::Options),
            "PATCH" => Some(Self::Patch),
            "TRACE" => Some(Self::Trace),
            _ => None,
        }
    }

    fn as_str(&self) -> &'static str {
        match self {
            Self::Connect => "CONNECT",
            Self::Get => "GET",
            Self::Post => "POST",
            Self::Put => "PUT",
            Self::Delete => "DELETE",
            Self::Head => "HEAD",
            Self::Options => "OPTIONS",
            Self::Patch => "PATCH",
            Self::Trace => "TRACE",
        }
    }
}

/// HTTP request parsed from client
#[derive(Debug)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub uri: String,
    pub version: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
}

impl HttpRequest {
    /// Get the Host header value
    pub fn host(&self) -> Option<&str> {
        self.headers
            .iter()
            .find(|(name, _)| name.to_lowercase() == "host")
            .map(|(_, value)| value.as_str())
    }

    /// Get Proxy-Authorization header
    pub fn proxy_auth(&self) -> Option<(String, String)> {
        self.headers
            .iter()
            .find(|(name, _)| name.to_lowercase() == "proxy-authorization")
            .and_then(|(_, value)| {
                if value.starts_with("Basic ") {
                    let encoded = &value[6..];
                    use base64::{engine::general_purpose, Engine as _};
                    if let Ok(decoded) = general_purpose::STANDARD.decode(encoded) {
                        if let Ok(creds) = String::from_utf8(decoded) {
                            let parts: Vec<&str> = creds.splitn(2, ':').collect();
                            if parts.len() == 2 {
                                return Some((parts[0].to_string(), parts[1].to_string()));
                            }
                        }
                    }
                }
                None
            })
    }

    /// Check if connection should be kept alive
    pub fn keep_alive(&self) -> bool {
        // HTTP/1.1 defaults to keep-alive
        if self.version == "HTTP/1.1" {
            !self.headers.iter().any(|(name, value)| {
                name.to_lowercase() == "connection" && value.to_lowercase() == "close"
            })
        } else {
            // HTTP/1.0 defaults to close
            self.headers.iter().any(|(name, value)| {
                name.to_lowercase() == "connection" && value.to_lowercase() == "keep-alive"
            })
        }
    }
}
