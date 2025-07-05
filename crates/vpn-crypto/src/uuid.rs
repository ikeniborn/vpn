use crate::error::Result;
use sha2::{Digest, Sha256};
use uuid::Uuid;

pub struct UuidGenerator;

impl UuidGenerator {
    pub fn new() -> Self {
        Self
    }
    pub fn generate_v4(&self) -> Result<String> {
        Ok(Uuid::new_v4().to_string())
    }

    pub fn generate_v4_hyphenated(&self) -> String {
        Uuid::new_v4().hyphenated().to_string()
    }

    pub fn generate_v4_simple(&self) -> String {
        Uuid::new_v4().simple().to_string()
    }

    pub fn generate_v4_urn(&self) -> String {
        Uuid::new_v4().urn().to_string()
    }

    pub fn generate_multiple(&self, count: usize) -> Vec<String> {
        (0..count)
            .map(|_| self.generate_v4().unwrap_or_default())
            .collect()
    }

    pub fn from_string(&self, uuid_str: &str) -> Result<String> {
        let uuid = Uuid::parse_str(uuid_str)
            .map_err(|e| crate::error::CryptoError::InvalidKeyFormat(e.to_string()))?;
        Ok(uuid.to_string())
    }

    pub fn is_valid(&self, uuid_str: &str) -> bool {
        Uuid::parse_str(uuid_str).is_ok()
    }

    pub fn generate_short_id(&self, uuid_str: &str) -> Result<String> {
        let uuid = Uuid::parse_str(uuid_str)
            .map_err(|e| crate::error::CryptoError::InvalidKeyFormat(e.to_string()))?;
        let bytes = uuid.as_bytes();

        let mut hasher = Sha256::new();
        hasher.update(bytes);
        let hash = hasher.finalize();
        let short_bytes = &hash[..4];

        Ok(format!(
            "{:02x}{:02x}{:02x}{:02x}",
            short_bytes[0], short_bytes[1], short_bytes[2], short_bytes[3]
        ))
    }

    pub fn validate_uuid(&self, uuid_str: &str) -> Result<()> {
        Uuid::parse_str(uuid_str)
            .map_err(|e| crate::error::CryptoError::InvalidKeyFormat(e.to_string()))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_uuid_generation() {
        let gen = UuidGenerator::new();
        let uuid1 = gen.generate_v4().unwrap();
        let uuid2 = gen.generate_v4().unwrap();

        assert_ne!(uuid1, uuid2);
        assert!(gen.is_valid(&uuid1));
        assert!(gen.is_valid(&uuid2));
    }

    #[test]
    fn test_short_id_generation() {
        let gen = UuidGenerator::new();
        let uuid1 = gen.generate_v4().unwrap();
        let uuid2 = gen.generate_v4().unwrap();
        let id1 = gen.generate_short_id(&uuid1).unwrap();
        let id2 = gen.generate_short_id(&uuid2).unwrap();

        assert_eq!(id1.len(), 8);
        assert_eq!(id2.len(), 8);
        assert_ne!(id1, id2);
    }
}
