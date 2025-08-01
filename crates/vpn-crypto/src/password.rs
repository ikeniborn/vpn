use crate::{CryptoError, Result};
use argon2::password_hash::{rand_core::OsRng, SaltString};
use argon2::{Argon2, PasswordHash, PasswordHasher as ArgonPasswordHasher, PasswordVerifier};

/// Password hasher using Argon2
pub struct PasswordHasher {
    argon2: Argon2<'static>,
}

impl PasswordHasher {
    /// Create a new password hasher with default settings
    pub fn new() -> Self {
        Self {
            argon2: Argon2::default(),
        }
    }

    /// Hash a password using Argon2
    pub fn hash_password(&self, password: &str) -> Result<String> {
        let salt = SaltString::generate(&mut OsRng);

        let password_hash = self
            .argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| CryptoError::PasswordHashError(e.to_string()))?;

        Ok(password_hash.to_string())
    }

    /// Verify a password against a hash
    pub fn verify_password(&self, password: &str, hash: &str) -> Result<bool> {
        let parsed_hash =
            PasswordHash::new(hash).map_err(|e| CryptoError::PasswordHashError(e.to_string()))?;

        Ok(self
            .argon2
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }
}

impl Default for PasswordHasher {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_password_hashing() {
        let hasher = PasswordHasher::new();
        let password = "test_password123";

        // Hash the password
        let hash = hasher.hash_password(password).unwrap();
        assert!(hash.starts_with("$argon2"));

        // Verify correct password
        assert!(hasher.verify_password(password, &hash).unwrap());

        // Verify incorrect password
        assert!(!hasher.verify_password("wrong_password", &hash).unwrap());
    }

    #[test]
    fn test_different_hashes_for_same_password() {
        let hasher = PasswordHasher::new();
        let password = "test_password123";

        let hash1 = hasher.hash_password(password).unwrap();
        let hash2 = hasher.hash_password(password).unwrap();

        // Hashes should be different due to random salt
        assert_ne!(hash1, hash2);

        // But both should verify correctly
        assert!(hasher.verify_password(password, &hash1).unwrap());
        assert!(hasher.verify_password(password, &hash2).unwrap());
    }
}
