use qrcode::{QrCode, EcLevel};
use std::path::Path;
use std::fs;
use crate::error::{CryptoError, Result};

pub struct QrCodeGenerator;

impl QrCodeGenerator {
    pub fn generate(data: &str) -> Result<QrCode> {
        QrCode::new(data)
            .map_err(|e| CryptoError::QrCodeError(e.to_string()))
    }
    
    pub fn generate_with_level(data: &str, level: EcLevel) -> Result<QrCode> {
        QrCode::with_error_correction_level(data, level)
            .map_err(|e| CryptoError::QrCodeError(e.to_string()))
    }
    
    pub fn save_as_image(data: &str, path: &Path, size: u32) -> Result<()> {
        let code = Self::generate(data)?;
        let image = code.render::<qrcode::render::svg::Color>()
            .min_dimensions(size, size)
            .build();
        
        fs::write(path, image).map_err(|e| CryptoError::QrCodeError(e.to_string()))?;
        Ok(())
    }
    
    pub fn save_as_png(data: &str, path: &Path) -> Result<()> {
        Self::save_as_image(data, path, 300)
    }
    
    pub fn generate_image_buffer(data: &str, size: u32) -> Result<Vec<u8>> {
        let code = Self::generate(data)?;
        let svg_string = code.render::<qrcode::render::svg::Color>()
            .min_dimensions(size, size)
            .build();
        
        Ok(svg_string.into_bytes())
    }
    
    pub fn to_string_art(data: &str) -> Result<String> {
        let code = Self::generate(data)?;
        
        let string = code.render::<char>()
            .quiet_zone(false)
            .module_dimensions(2, 1)
            .build();
        
        Ok(string)
    }
    
    pub fn to_terminal_string(data: &str) -> Result<String> {
        let code = Self::generate(data)?;
        
        let string = code.render::<char>()
            .quiet_zone(true)
            .dark_color('█')
            .light_color(' ')
            .module_dimensions(2, 1)
            .build();
        
        Ok(string)
    }
    
    pub fn validate_data_size(data: &str) -> Result<()> {
        let max_size = 2953;
        
        if data.len() > max_size {
            return Err(CryptoError::QrCodeError(
                format!("Data too large for QR code. Maximum size: {}, got: {}", 
                    max_size, data.len())
            ));
        }
        
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
        let qr = QrCodeGenerator::generate(data).unwrap();
        assert!(qr.width() > 0);
    }
    
    #[test]
    fn test_qr_save_as_image() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.png");
        let data = "vless://test@example.com:443";
        
        QrCodeGenerator::save_as_png(data, &path).unwrap();
        assert!(path.exists());
    }
    
    #[test]
    fn test_terminal_string() {
        let data = "https://example.com";
        let terminal_str = QrCodeGenerator::to_terminal_string(data).unwrap();
        
        assert!(terminal_str.contains('█'));
        assert!(terminal_str.contains(' '));
    }
}