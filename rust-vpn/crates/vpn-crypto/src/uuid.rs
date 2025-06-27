use uuid::Uuid;
use sha2::{Sha256, Digest};
use crate::error::Result;

pub struct UuidGenerator;

impl UuidGenerator {
    pub fn generate_v4() -> String {
        Uuid::new_v4().to_string()
    }
    
    pub fn generate_v4_hyphenated() -> String {
        Uuid::new_v4().hyphenated().to_string()
    }
    
    pub fn generate_v4_simple() -> String {
        Uuid::new_v4().simple().to_string()
    }
    
    pub fn generate_v4_urn() -> String {
        Uuid::new_v4().urn().to_string()
    }
    
    pub fn generate_multiple(count: usize) -> Vec<String> {
        (0..count).map(|_| Self::generate_v4()).collect()
    }
    
    pub fn from_string(uuid_str: &str) -> Result<String> {
        let uuid = Uuid::parse_str(uuid_str)
            .map_err(|e| crate::error::CryptoError::InvalidKeyFormat(e.to_string()))?;
        Ok(uuid.to_string())
    }
    
    pub fn is_valid(uuid_str: &str) -> bool {
        Uuid::parse_str(uuid_str).is_ok()
    }
    
    pub fn generate_short_id() -> String {
        let uuid = Uuid::new_v4();
        let bytes = uuid.as_bytes();
        
        let mut hasher = Sha256::new();
        hasher.update(bytes);
        let hash = hasher.finalize();
        let short_bytes = &hash[..4];
        
        format!("{:02x}{:02x}{:02x}{:02x}", 
            short_bytes[0], short_bytes[1], short_bytes[2], short_bytes[3])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_uuid_generation() {
        let uuid1 = UuidGenerator::generate_v4();
        let uuid2 = UuidGenerator::generate_v4();
        
        assert_ne!(uuid1, uuid2);
        assert!(UuidGenerator::is_valid(&uuid1));
        assert!(UuidGenerator::is_valid(&uuid2));
    }
    
    #[test]
    fn test_short_id_generation() {
        let id1 = UuidGenerator::generate_short_id();
        let id2 = UuidGenerator::generate_short_id();
        
        assert_eq!(id1.len(), 8);
        assert_eq!(id2.len(), 8);
        assert_ne!(id1, id2);
    }
}