use qrcode::{QrCode, EcLevel};
use std::fs;
use crate::error::{CryptoError, Result};

#[derive(Debug, Clone, Copy)]
pub enum ErrorCorrectionLevel {
    Low,
    Medium,
    High,
}

pub struct QrCodeGenerator;

impl QrCodeGenerator {
    pub fn new() -> Self {
        Self
    }
    pub fn generate_qr_code(&self, data: &str) -> Result<Vec<u8>> {
        let code = QrCode::new(data)
            .map_err(|e| CryptoError::QrCodeError(e.to_string()))?;
        let svg_string = code.render::<qrcode::render::svg::Color>()
            .min_dimensions(300, 300)
            .build();
        Ok(svg_string.into_bytes())
    }
    
    pub fn generate_qr_code_with_level(&self, data: &str, level: ErrorCorrectionLevel) -> Result<Vec<u8>> {
        let ec_level = match level {
            ErrorCorrectionLevel::Low => EcLevel::L,
            ErrorCorrectionLevel::Medium => EcLevel::M,
            ErrorCorrectionLevel::High => EcLevel::H,
        };
        let code = QrCode::with_error_correction_level(data, ec_level)
            .map_err(|e| CryptoError::QrCodeError(e.to_string()))?;
        let svg_string = code.render::<qrcode::render::svg::Color>()
            .min_dimensions(300, 300)
            .build();
        Ok(svg_string.into_bytes())
    }
    
    pub fn save_qr_code_to_file(&self, data: &str, path: &str) -> Result<()> {
        let qr_data = self.generate_qr_code(data)?;
        fs::write(path, qr_data).map_err(|e| CryptoError::QrCodeError(e.to_string()))?;
        Ok(())
    }
    
    
    
    
    
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    
    #[test]
    fn test_qr_generation() {
        let data = "vless://test@example.com:443";
        let gen = QrCodeGenerator::new();
        let qr_data = gen.generate_qr_code(data).expect("Failed to generate QR code");
        assert!(!qr_data.is_empty());
    }
    
    #[test]
    fn test_qr_save_as_image() {
        let dir = tempdir().expect("Failed to create temp dir");
        let path = dir.path().join("test.svg");
        let data = "vless://test@example.com:443";
        let gen = QrCodeGenerator::new();
        
        gen.save_qr_code_to_file(data, &path.to_string_lossy()).expect("Failed to save QR code");
        assert!(path.exists());
    }
    
    #[test]
    fn test_qr_generation_with_level() {
        let data = "https://example.com";
        let gen = QrCodeGenerator::new();
        let qr_data = gen.generate_qr_code_with_level(data, ErrorCorrectionLevel::High).expect("Failed to generate QR code");
        
        assert!(!qr_data.is_empty());
    }
}