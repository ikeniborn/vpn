use crate::error::{CryptoError, Result};
use aes_gcm::aead::OsRng;
use aes_gcm::{aead::Aead, Aes256Gcm, Key, KeyInit, Nonce};
use base64::Engine;
use pbkdf2::pbkdf2_hmac;
use rand::RngCore;
use sha2::Sha256;
use std::path::Path;
use zeroize::{Zeroize, ZeroizeOnDrop};

const SALT_SIZE: usize = 32;
const NONCE_SIZE: usize = 12;
const PBKDF2_ITERATIONS: u32 = 100_000;

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct SecureKeyManager {
    master_key: [u8; 32],
}

#[derive(Debug, Clone)]
pub struct EncryptedKeyData {
    pub salt: Vec<u8>,
    pub nonce: Vec<u8>,
    pub ciphertext: Vec<u8>,
}

impl SecureKeyManager {
    /// Create a new SecureKeyManager from a password
    pub fn new(password: &str) -> Result<Self> {
        if password.len() < 8 {
            return Err(CryptoError::InvalidKeyFormat(
                "Password must be at least 8 characters".to_string(),
            ));
        }

        // Generate a random master key for this session
        let mut master_key = [0u8; 32];
        OsRng.fill_bytes(&mut master_key);

        Ok(Self { master_key })
    }

    /// Create SecureKeyManager from existing master key
    pub fn from_master_key(key: [u8; 32]) -> Self {
        Self { master_key: key }
    }

    /// Derive encryption key from password and salt
    fn derive_key(password: &str, salt: &[u8]) -> Result<[u8; 32]> {
        let mut key = [0u8; 32];
        pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, PBKDF2_ITERATIONS, &mut key);
        Ok(key)
    }

    /// Encrypt data with password-derived key
    pub fn encrypt_with_password(data: &[u8], password: &str) -> Result<EncryptedKeyData> {
        // Generate random salt and nonce
        let mut salt = vec![0u8; SALT_SIZE];
        let mut nonce_bytes = vec![0u8; NONCE_SIZE];
        OsRng.fill_bytes(&mut salt);
        OsRng.fill_bytes(&mut nonce_bytes);

        // Derive encryption key from password
        let key_bytes = Self::derive_key(password, &salt)?;
        let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        // Encrypt the data
        let cipher = Aes256Gcm::new(key);
        let ciphertext = cipher
            .encrypt(nonce, data)
            .map_err(|e| CryptoError::EncryptionError(e.to_string()))?;

        Ok(EncryptedKeyData {
            salt,
            nonce: nonce_bytes,
            ciphertext,
        })
    }

    /// Decrypt data with password-derived key
    pub fn decrypt_with_password(
        encrypted_data: &EncryptedKeyData,
        password: &str,
    ) -> Result<Vec<u8>> {
        // Derive the same encryption key
        let key_bytes = Self::derive_key(password, &encrypted_data.salt)?;
        let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
        let nonce = Nonce::from_slice(&encrypted_data.nonce);

        // Decrypt the data
        let cipher = Aes256Gcm::new(key);
        let plaintext = cipher
            .decrypt(nonce, encrypted_data.ciphertext.as_ref())
            .map_err(|e| CryptoError::DecryptionError(e.to_string()))?;

        Ok(plaintext)
    }

    /// Save encrypted key to file
    pub async fn save_encrypted_key(data: &[u8], password: &str, file_path: &Path) -> Result<()> {
        let encrypted = Self::encrypt_with_password(data, password)?;

        // Serialize encrypted data as JSON
        let json_data = serde_json::json!({
            "version": "1",
            "salt": base64::prelude::BASE64_STANDARD.encode(&encrypted.salt),
            "nonce": base64::prelude::BASE64_STANDARD.encode(&encrypted.nonce),
            "ciphertext": base64::prelude::BASE64_STANDARD.encode(&encrypted.ciphertext),
            "created": chrono::Utc::now().to_rfc3339(),
        });

        tokio::fs::write(file_path, serde_json::to_string_pretty(&json_data)?)
            .await
            .map_err(|e| CryptoError::IoError(e))?;

        // Set restrictive permissions on Unix systems
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let permissions = std::fs::Permissions::from_mode(0o600);
            std::fs::set_permissions(file_path, permissions)
                .map_err(|e| CryptoError::IoError(e))?;
        }

        Ok(())
    }

    /// Load and decrypt key from file
    pub async fn load_encrypted_key(file_path: &Path, password: &str) -> Result<Vec<u8>> {
        let content = tokio::fs::read_to_string(file_path)
            .await
            .map_err(|e| CryptoError::IoError(e))?;

        let json: serde_json::Value = serde_json::from_str(&content)?;

        // Extract encrypted data
        let salt = base64::prelude::BASE64_STANDARD.decode(
            json["salt"]
                .as_str()
                .ok_or_else(|| CryptoError::InvalidKeyFormat("Missing salt".to_string()))?,
        )?;

        let nonce = base64::prelude::BASE64_STANDARD.decode(
            json["nonce"]
                .as_str()
                .ok_or_else(|| CryptoError::InvalidKeyFormat("Missing nonce".to_string()))?,
        )?;

        let ciphertext =
            base64::prelude::BASE64_STANDARD.decode(json["ciphertext"].as_str().ok_or_else(
                || CryptoError::InvalidKeyFormat("Missing ciphertext".to_string()),
            )?)?;

        let encrypted_data = EncryptedKeyData {
            salt,
            nonce,
            ciphertext,
        };

        Self::decrypt_with_password(&encrypted_data, password)
    }

    /// Generate a secure random password
    pub fn generate_secure_password(length: usize) -> String {
        use rand::Rng;
        const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ\
                                 abcdefghijklmnopqrstuvwxyz\
                                 0123456789\
                                 !@#$%^&*";

        let mut rng = rand::thread_rng();
        (0..length)
            .map(|_| {
                let idx = rng.gen_range(0..CHARSET.len());
                CHARSET[idx] as char
            })
            .collect()
    }

    /// Validate password strength
    pub fn validate_password_strength(password: &str) -> Result<()> {
        if password.len() < 12 {
            return Err(CryptoError::InvalidKeyFormat(
                "Password must be at least 12 characters long".to_string(),
            ));
        }

        let has_upper = password.chars().any(|c| c.is_ascii_uppercase());
        let has_lower = password.chars().any(|c| c.is_ascii_lowercase());
        let has_digit = password.chars().any(|c| c.is_ascii_digit());
        let has_special = password
            .chars()
            .any(|c| "!@#$%^&*()_+-=[]{}|;:,.<>?".contains(c));

        if !(has_upper && has_lower && has_digit && has_special) {
            return Err(CryptoError::InvalidKeyFormat(
                "Password must contain uppercase, lowercase, digit, and special character"
                    .to_string(),
            ));
        }

        Ok(())
    }

    /// Rotate encryption keys (re-encrypt with new password)
    pub async fn rotate_key(
        file_path: &Path,
        old_password: &str,
        new_password: &str,
    ) -> Result<()> {
        // Validate new password
        Self::validate_password_strength(new_password)?;

        // Load and decrypt with old password
        let data = Self::load_encrypted_key(file_path, old_password).await?;

        // Re-encrypt with new password
        Self::save_encrypted_key(&data, new_password, file_path).await?;

        Ok(())
    }

    /// Securely delete file (overwrite before deletion)
    pub async fn secure_delete(file_path: &Path) -> Result<()> {
        if tokio::fs::try_exists(file_path).await.unwrap_or(false) {
            // Get file size
            let metadata = tokio::fs::metadata(file_path)
                .await
                .map_err(|e| CryptoError::IoError(e))?;

            let file_size = metadata.len() as usize;

            // Overwrite with random data multiple times
            for _ in 0..3 {
                let mut random_data = vec![0u8; file_size];
                OsRng.fill_bytes(&mut random_data);

                tokio::fs::write(file_path, &random_data)
                    .await
                    .map_err(|e| CryptoError::IoError(e))?;
            }

            // Finally remove the file
            tokio::fs::remove_file(file_path)
                .await
                .map_err(|e| CryptoError::IoError(e))?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_password_validation() {
        assert!(SecureKeyManager::validate_password_strength("Weak123").is_err());
        assert!(SecureKeyManager::validate_password_strength("StrongP@ssw0rd123").is_ok());
    }

    #[tokio::test]
    async fn test_encrypt_decrypt_cycle() {
        let data = b"sensitive key data";
        let password = "TestP@ssw0rd123";

        let encrypted =
            SecureKeyManager::encrypt_with_password(data, password).expect("Encryption failed");

        let decrypted = SecureKeyManager::decrypt_with_password(&encrypted, password)
            .expect("Decryption failed");

        assert_eq!(data, decrypted.as_slice());
    }

    #[tokio::test]
    async fn test_file_encryption() {
        let dir = tempdir().expect("Failed to create temp dir");
        let file_path = dir.path().join("test_key.enc");
        let data = b"test key data";
        let password = "TestP@ssw0rd123";

        SecureKeyManager::save_encrypted_key(data, password, &file_path)
            .await
            .expect("Failed to save encrypted key");

        let loaded_data = SecureKeyManager::load_encrypted_key(&file_path, password)
            .await
            .expect("Failed to load encrypted key");

        assert_eq!(data, loaded_data.as_slice());
    }

    #[tokio::test]
    async fn test_key_rotation() {
        let dir = tempdir().expect("Failed to create temp dir");
        let file_path = dir.path().join("rotation_test.enc");
        let data = b"rotation test data";
        let old_password = "OldP@ssw0rd123";
        let new_password = "NewP@ssw0rd456";

        // Save with old password
        SecureKeyManager::save_encrypted_key(data, old_password, &file_path)
            .await
            .expect("Failed to save with old password");

        // Rotate to new password
        SecureKeyManager::rotate_key(&file_path, old_password, new_password)
            .await
            .expect("Failed to rotate key");

        // Verify we can read with new password
        let loaded_data = SecureKeyManager::load_encrypted_key(&file_path, new_password)
            .await
            .expect("Failed to load with new password");

        assert_eq!(data, loaded_data.as_slice());

        // Verify old password no longer works
        assert!(
            SecureKeyManager::load_encrypted_key(&file_path, old_password)
                .await
                .is_err()
        );
    }
}
