use thiserror::Error;

#[derive(Error, Debug)]
pub enum CryptoError {
    #[error("Key generation failed: {0}")]
    KeyGenerationError(String),
    
    #[error("Encoding error: {0}")]
    EncodingError(String),
    
    #[error("QR code generation failed: {0}")]
    QrCodeError(String),
    
    #[error("Invalid key format: {0}")]
    InvalidKeyFormat(String),
    
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    
    #[error("Base64 decode error: {0}")]
    Base64Error(#[from] base64::DecodeError),
    
    #[error("Image error: {0}")]
    ImageError(#[from] image::ImageError),
    
    #[error("Encryption error: {0}")]
    EncryptionError(String),
    
    #[error("Decryption error: {0}")]
    DecryptionError(String),
    
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
}

impl PartialEq for CryptoError {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (CryptoError::KeyGenerationError(a), CryptoError::KeyGenerationError(b)) => a == b,
            (CryptoError::EncodingError(a), CryptoError::EncodingError(b)) => a == b,
            (CryptoError::QrCodeError(a), CryptoError::QrCodeError(b)) => a == b,
            (CryptoError::InvalidKeyFormat(a), CryptoError::InvalidKeyFormat(b)) => a == b,
            (CryptoError::EncryptionError(a), CryptoError::EncryptionError(b)) => a == b,
            (CryptoError::DecryptionError(a), CryptoError::DecryptionError(b)) => a == b,
            // For complex error types, just compare discriminants
            (CryptoError::IoError(_), CryptoError::IoError(_)) => true,
            (CryptoError::Base64Error(_), CryptoError::Base64Error(_)) => true,
            (CryptoError::ImageError(_), CryptoError::ImageError(_)) => true,
            (CryptoError::JsonError(_), CryptoError::JsonError(_)) => true,
            _ => false,
        }
    }
}

pub type Result<T> = std::result::Result<T, CryptoError>;