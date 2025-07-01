use dns_lookup::lookup_host;
use reqwest;
use std::time::Duration;
use crate::error::Result;

pub struct SniValidator;

impl SniValidator {
    pub fn validate_domain(domain: &str) -> Result<bool> {
        Ok(Self::is_valid_domain_format(domain))
    }
    
    pub async fn validate_sni(domain: &str) -> Result<bool> {
        if !Self::is_valid_domain_format(domain) {
            return Ok(false);
        }
        
        if !Self::has_dns_record(domain).await? {
            return Ok(false);
        }
        
        Ok(Self::is_reachable(domain).await?)
    }
    
    fn is_valid_domain_format(domain: &str) -> bool {
        if domain.is_empty() || domain.len() > 253 {
            return false;
        }
        
        if domain.starts_with('.') || domain.ends_with('.') {
            return false;
        }
        
        let labels: Vec<&str> = domain.split('.').collect();
        if labels.is_empty() || labels.len() == 1 {
            return false;
        }
        
        for label in &labels {
            if label.is_empty() || label.len() > 63 {
                return false;
            }
            
            if label.starts_with('-') || label.ends_with('-') {
                return false;
            }
            
            if !label.chars().all(|c| c.is_alphanumeric() || c == '-') {
                return false;
            }
        }
        
        if let Some(tld) = labels.last() {
            if tld.chars().all(|c| c.is_numeric()) {
                return false;
            }
        }
        
        true
    }
    
    async fn has_dns_record(domain: &str) -> Result<bool> {
        match lookup_host(domain) {
            Ok(ips) => Ok(!ips.is_empty()),
            Err(_) => Ok(false),
        }
    }
    
    async fn is_reachable(domain: &str) -> Result<bool> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .danger_accept_invalid_certs(true)
            .build()?;
        
        let url = format!("https://{}", domain);
        
        match client.head(&url).send().await {
            Ok(response) => Ok(response.status().is_success() || response.status().is_redirection()),
            Err(_) => {
                let url = format!("http://{}", domain);
                match client.head(&url).send().await {
                    Ok(response) => Ok(response.status().is_success() || response.status().is_redirection()),
                    Err(_) => Ok(false),
                }
            }
        }
    }
    
    pub fn get_recommended_snis() -> Vec<&'static str> {
        vec![
            "www.google.com",
            "www.cloudflare.com",
            "www.amazon.com",
            "www.microsoft.com",
            "www.apple.com",
            "www.facebook.com",
            "www.youtube.com",
            "www.wikipedia.org",
            "www.github.com",
            "www.stackoverflow.com",
        ]
    }
    
    pub async fn find_best_sni(domains: &[&str]) -> Result<Option<String>> {
        for domain in domains {
            if Self::validate_sni(domain).await? {
                return Ok(Some(domain.to_string()));
            }
        }
        Ok(None)
    }
    
    pub async fn test_sni_quality(domain: &str) -> Result<f64> {
        let start = std::time::Instant::now();
        
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .danger_accept_invalid_certs(true)
            .build()?;
        
        let url = format!("https://{}", domain);
        
        match client.head(&url).send().await {
            Ok(_) => {
                let elapsed = start.elapsed().as_millis() as f64;
                Ok(1000.0 / elapsed)
            }
            Err(_) => Ok(0.0),
        }
    }
    
    pub fn extract_domain_from_url(url: &str) -> Option<String> {
        if let Ok(parsed) = url.parse::<reqwest::Url>() {
            parsed.host_str().map(|h| h.to_string())
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_domain_format_validation() {
        assert!(SniValidator::is_valid_domain_format("www.google.com"));
        assert!(SniValidator::is_valid_domain_format("subdomain.example.co.uk"));
        assert!(!SniValidator::is_valid_domain_format(""));
        assert!(!SniValidator::is_valid_domain_format(".example.com"));
        assert!(!SniValidator::is_valid_domain_format("example.com."));
        assert!(!SniValidator::is_valid_domain_format("example"));
        assert!(!SniValidator::is_valid_domain_format("exam ple.com"));
        assert!(!SniValidator::is_valid_domain_format("-example.com"));
    }
    
    #[test]
    fn test_url_domain_extraction() {
        assert_eq!(
            SniValidator::extract_domain_from_url("https://www.google.com/search"),
            Some("www.google.com".to_string())
        );
        assert_eq!(
            SniValidator::extract_domain_from_url("http://example.com"),
            Some("example.com".to_string())
        );
        assert_eq!(
            SniValidator::extract_domain_from_url("invalid-url"),
            None
        );
    }
}