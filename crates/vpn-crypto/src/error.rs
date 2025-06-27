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
}

pub type Result<T> = std::result::Result<T, CryptoError>;