//! Rate limiting implementation for proxy server

use crate::{
    config::RateLimitConfig,
    error::{ProxyError, Result},
};
use dashmap::DashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tracing::{debug, warn};

/// Token bucket for rate limiting
#[derive(Debug)]
struct TokenBucket {
    capacity: u32,
    tokens: f64,
    refill_rate: f64,
    last_update: Instant,
}

impl TokenBucket {
    fn new(capacity: u32, refill_rate: f64) -> Self {
        Self {
            capacity,
            tokens: capacity as f64,
            refill_rate,
            last_update: Instant::now(),
        }
    }
    
    fn try_consume(&mut self, tokens: u32) -> bool {
        self.refill();
        
        if self.tokens >= tokens as f64 {
            self.tokens -= tokens as f64;
            true
        } else {
            false
        }
    }
    
    fn refill(&mut self) {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last_update).as_secs_f64();
        let new_tokens = elapsed * self.refill_rate;
        
        self.tokens = (self.tokens + new_tokens).min(self.capacity as f64);
        self.last_update = now;
    }
}

/// Bandwidth tracker for a user
#[derive(Debug)]
struct BandwidthTracker {
    bytes_sent: u64,
    window_start: Instant,
    window_duration: Duration,
}

impl BandwidthTracker {
    fn new(window_duration: Duration) -> Self {
        Self {
            bytes_sent: 0,
            window_start: Instant::now(),
            window_duration,
        }
    }
    
    fn record_bytes(&mut self, bytes: u64) {
        let now = Instant::now();
        
        // Reset if window has passed
        if now.duration_since(self.window_start) > self.window_duration {
            self.bytes_sent = bytes;
            self.window_start = now;
        } else {
            self.bytes_sent += bytes;
        }
    }
    
    fn get_rate(&self) -> u64 {
        let elapsed = Instant::now().duration_since(self.window_start).as_secs_f64();
        if elapsed > 0.0 {
            (self.bytes_sent as f64 / elapsed) as u64
        } else {
            0
        }
    }
}

/// Rate limiter for proxy connections
pub struct RateLimiter {
    config: RateLimitConfig,
    user_buckets: Arc<DashMap<String, Arc<Mutex<TokenBucket>>>>,
    bandwidth_trackers: Arc<DashMap<String, Arc<Mutex<BandwidthTracker>>>>,
    global_bucket: Arc<Mutex<TokenBucket>>,
}

impl RateLimiter {
    /// Create a new rate limiter
    pub fn new(config: &RateLimitConfig) -> Self {
        let global_bucket = config.global_limit
            .map(|limit| Arc::new(Mutex::new(TokenBucket::new(limit * 2, limit as f64))))
            .unwrap_or_else(|| Arc::new(Mutex::new(TokenBucket::new(u32::MAX, f64::MAX))));
        
        Self {
            config: config.clone(),
            user_buckets: Arc::new(DashMap::new()),
            bandwidth_trackers: Arc::new(DashMap::new()),
            global_bucket,
        }
    }
    
    /// Check if a request is allowed for a user
    pub async fn check_rate_limit(&self, user_id: &str) -> Result<bool> {
        if !self.config.enabled {
            return Ok(true);
        }
        
        // Check global rate limit first
        if self.config.global_limit.is_some() {
            let mut global_bucket = self.global_bucket.lock().await;
            if !global_bucket.try_consume(1) {
                warn!("Global rate limit exceeded");
                return Ok(false);
            }
        }
        
        // Get or create user bucket
        let bucket = self.user_buckets
            .entry(user_id.to_string())
            .or_insert_with(|| {
                Arc::new(Mutex::new(TokenBucket::new(
                    self.config.burst_size,
                    self.config.requests_per_second as f64,
                )))
            })
            .clone();
        
        let mut bucket = bucket.lock().await;
        let allowed = bucket.try_consume(1);
        
        if !allowed {
            warn!("Rate limit exceeded for user: {}", user_id);
        } else {
            debug!("Request allowed for user: {}", user_id);
        }
        
        Ok(allowed)
    }
    
    /// Record bandwidth usage for a user
    pub async fn record_bandwidth(&self, user_id: &str, bytes: u64) -> Result<()> {
        if !self.config.enabled || self.config.bandwidth_limit.is_none() {
            return Ok(());
        }
        
        let tracker = self.bandwidth_trackers
            .entry(user_id.to_string())
            .or_insert_with(|| {
                Arc::new(Mutex::new(BandwidthTracker::new(Duration::from_secs(1))))
            })
            .clone();
        
        let mut tracker = tracker.lock().await;
        tracker.record_bytes(bytes);
        
        Ok(())
    }
    
    /// Get current bandwidth rate for a user
    pub async fn get_bandwidth_rate(&self, user_id: &str) -> Result<u64> {
        if let Some(tracker) = self.bandwidth_trackers.get(user_id) {
            let tracker = tracker.lock().await;
            Ok(tracker.get_rate())
        } else {
            Ok(0)
        }
    }
    
    /// Clean up expired entries
    pub async fn cleanup(&self) {
        // Remove inactive users after 1 hour
        let cutoff = Instant::now() - Duration::from_secs(3600);
        
        // Note: This is a simplified cleanup that doesn't check actual last access time
        // In production, you'd want to track last access time for each bucket
        if self.user_buckets.len() > 10000 {
            // Only cleanup if we have many entries
            self.user_buckets.retain(|_, _| true); // Placeholder for actual cleanup logic
            self.bandwidth_trackers.retain(|_, _| true); // Placeholder for actual cleanup logic
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_token_bucket() {
        let mut bucket = TokenBucket::new(10, 1.0);
        
        // Should allow initial requests up to capacity
        assert!(bucket.try_consume(5));
        assert!(bucket.try_consume(5));
        assert!(!bucket.try_consume(1)); // Should fail
        
        // Wait and check refill
        std::thread::sleep(Duration::from_secs(2));
        assert!(bucket.try_consume(1)); // Should succeed after refill
    }
    
    #[tokio::test]
    async fn test_rate_limiter() {
        let config = RateLimitConfig {
            enabled: true,
            requests_per_second: 10,
            burst_size: 20,
            bandwidth_limit: None,
            global_limit: None,
        };
        
        let limiter = RateLimiter::new(&config);
        
        // Should allow burst size requests
        for _ in 0..20 {
            assert!(limiter.check_rate_limit("test_user").await.unwrap());
        }
        
        // Should deny after burst is exhausted
        assert!(!limiter.check_rate_limit("test_user").await.unwrap());
    }
}