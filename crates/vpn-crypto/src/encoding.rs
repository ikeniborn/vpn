use crate::error::{CryptoError, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

pub struct EncodingUtils;

impl EncodingUtils {
    pub fn new() -> Self {
        Self
    }

    pub fn base64_encode(&self, data: &[u8]) -> Result<String> {
        Ok(BASE64.encode(data))
    }

    pub fn base64_decode(&self, encoded: &str) -> Result<Vec<u8>> {
        BASE64
            .decode(encoded.trim())
            .map_err(|e| CryptoError::EncodingError(e.to_string()))
    }

    pub fn base64_url_encode(&self, data: &[u8]) -> Result<String> {
        use base64::{engine::general_purpose::URL_SAFE as BASE64_URL, Engine};
        Ok(BASE64_URL.encode(data))
    }

    pub fn base64_url_decode(&self, encoded: &str) -> Result<Vec<u8>> {
        use base64::{engine::general_purpose::URL_SAFE as BASE64_URL, Engine};
        BASE64_URL
            .decode(encoded.trim())
            .map_err(|e| CryptoError::EncodingError(e.to_string()))
    }

    pub fn hex_encode(&self, data: &[u8]) -> String {
        hex::encode(data)
    }

    pub fn hex_decode(&self, encoded: &str) -> Result<Vec<u8>> {
        hex::decode(encoded.trim()).map_err(|e| CryptoError::EncodingError(e.to_string()))
    }
}

pub struct Base64Encoder;

impl Base64Encoder {
    pub fn encode<T: AsRef<[u8]>>(data: T) -> String {
        BASE64.encode(data)
    }

    pub fn decode(encoded: &str) -> Result<Vec<u8>> {
        BASE64.decode(encoded.trim()).map_err(|e| e.into())
    }

    pub fn encode_string(text: &str) -> String {
        Self::encode(text.as_bytes())
    }

    pub fn decode_string(encoded: &str) -> Result<String> {
        let bytes = Self::decode(encoded)?;
        String::from_utf8(bytes).map_err(|e| CryptoError::EncodingError(e.to_string()))
    }

    pub fn is_valid_base64(data: &str) -> bool {
        BASE64.decode(data.trim()).is_ok()
    }
}

pub struct HexEncoder;

impl HexEncoder {
    pub fn encode<T: AsRef<[u8]>>(data: T) -> String {
        hex::encode(data)
    }

    pub fn decode(encoded: &str) -> Result<Vec<u8>> {
        hex::decode(encoded.trim()).map_err(|e| CryptoError::EncodingError(e.to_string()))
    }

    pub fn encode_string(text: &str) -> String {
        Self::encode(text.as_bytes())
    }

    pub fn decode_string(encoded: &str) -> Result<String> {
        let bytes = Self::decode(encoded)?;
        String::from_utf8(bytes).map_err(|e| CryptoError::EncodingError(e.to_string()))
    }

    pub fn is_valid_hex(data: &str) -> bool {
        hex::decode(data.trim()).is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base64_encoding() {
        let original = "Hello, VPN!";
        let encoded = Base64Encoder::encode_string(original);
        let decoded = Base64Encoder::decode_string(&encoded).unwrap();

        assert_eq!(original, decoded);
        assert!(Base64Encoder::is_valid_base64(&encoded));
    }

    #[test]
    fn test_hex_encoding() {
        let original = "Hello, VPN!";
        let encoded = HexEncoder::encode_string(original);
        let decoded = HexEncoder::decode_string(&encoded).unwrap();

        assert_eq!(original, decoded);
        assert!(HexEncoder::is_valid_hex(&encoded));
    }
}
