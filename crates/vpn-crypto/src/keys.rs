use x25519_dalek::{PublicKey, StaticSecret};
use rand_core::OsRng;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use std::path::Path;
use std::fs;
use crate::error::{CryptoError, Result};

#[derive(Debug, Clone)]
pub struct KeyPair {
    pub private_key: Vec<u8>,
    pub public_key: Vec<u8>,
}

impl KeyPair {
    pub fn private_key_base64(&self) -> String {
        BASE64.encode(&self.private_key)
    }
    
    pub fn public_key_base64(&self) -> String {
        BASE64.encode(&self.public_key)
    }
    
    pub fn private_key_hex(&self) -> String {
        hex::encode(&self.private_key)
    }
    
    pub fn public_key_hex(&self) -> String {
        hex::encode(&self.public_key)
    }
}

pub struct X25519KeyManager;

impl X25519KeyManager {
    pub fn new() -> Self {
        Self
    }
    
    pub fn generate_keypair(&self) -> Result<KeyPair> {
        let secret = StaticSecret::new(OsRng);
        let public = PublicKey::from(&secret);
        
        Ok(KeyPair {
            private_key: secret.to_bytes().to_vec(),
            public_key: public.to_bytes().to_vec(),
        })
    }
    
    pub fn save_keypair(&self, keypair: &KeyPair, private_path: &Path, public_path: &Path) -> Result<()> {
        fs::write(private_path, &keypair.private_key_base64())
            .map_err(|e| CryptoError::IoError(e))?;
        
        fs::write(public_path, &keypair.public_key_base64())
            .map_err(|e| CryptoError::IoError(e))?;
        
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let private_perms = fs::Permissions::from_mode(0o600);
            fs::set_permissions(private_path, private_perms)?;
        }
        
        Ok(())
    }
    
    pub fn load_keypair(&self, private_path: &Path, public_path: &Path) -> Result<KeyPair> {
        let private_base64 = fs::read_to_string(private_path)?;
        let public_base64 = fs::read_to_string(public_path)?;
        
        let private_key = BASE64.decode(private_base64.trim())?;
        let public_key = BASE64.decode(public_base64.trim())?;
        
        if private_key.len() != 32 {
            return Err(CryptoError::InvalidKeyFormat(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        if public_key.len() != 32 {
            return Err(CryptoError::InvalidKeyFormat(
                format!("Public key must be 32 bytes, got {}", public_key.len())
            ));
        }
        
        Ok(KeyPair {
            private_key,
            public_key,
        })
    }
    
    pub fn derive_public_key(&self, private_key: &[u8]) -> Result<Vec<u8>> {
        if private_key.len() != 32 {
            return Err(CryptoError::InvalidKeyFormat(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(private_key);
        let secret = StaticSecret::from(bytes);
        let public = PublicKey::from(&secret);
        
        Ok(public.to_bytes().to_vec())
    }
    
    pub fn from_base64(&self, private_base64: &str) -> Result<KeyPair> {
        let private_key = BASE64.decode(private_base64.trim())?;
        let public_key = self.derive_public_key(&private_key)?;
        
        Ok(KeyPair {
            private_key,
            public_key,
        })
    }
    
    pub fn validate_keypair(&self, keypair: &KeyPair) -> Result<()> {
        let derived_public = self.derive_public_key(&keypair.private_key)?;
        
        if derived_public != keypair.public_key {
            return Err(CryptoError::InvalidKeyFormat(
                "Public key does not match private key".to_string()
            ));
        }
        
        Ok(())
    }
    
    pub fn validate_private_key(&self, private_key_base64: &str) -> Result<()> {
        let private_key = BASE64.decode(private_key_base64.trim())
            .map_err(|e| CryptoError::InvalidKeyFormat(format!("Invalid base64 encoding: {}", e)))?;
        
        if private_key.len() != 32 {
            return Err(CryptoError::InvalidKeyFormat(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        Ok(())
    }
    
    pub fn validate_public_key(&self, public_key_base64: &str) -> Result<()> {
        if public_key_base64.is_empty() {
            return Err(CryptoError::InvalidKeyFormat("Public key cannot be empty".to_string()));
        }
        
        let public_key = BASE64.decode(public_key_base64.trim())
            .map_err(|e| CryptoError::InvalidKeyFormat(format!("Invalid base64 encoding: {}", e)))?;
        
        if public_key.len() != 32 {
            return Err(CryptoError::InvalidKeyFormat(
                format!("Public key must be 32 bytes, got {}", public_key.len())
            ));
        }
        
        Ok(())
    }
    
    pub fn derive_public_key_base64(&self, private_key_base64: &str) -> Result<String> {
        let private_key = BASE64.decode(private_key_base64.trim())
            .map_err(|e| CryptoError::InvalidKeyFormat(format!("Invalid base64 encoding: {}", e)))?;
        let public_key = self.derive_public_key(&private_key)?;
        Ok(BASE64.encode(&public_key))
    }
}