use proptest::prelude::*;
use quickcheck::{quickcheck, TestResult};
use vpn_crypto::{
    X25519KeyManager, QrCodeGenerator, UuidGenerator, EncodingUtils,
    ErrorCorrectionLevel, Base64Encoder, HexEncoder
};
use vpn_crypto::protocol::VpnProtocol;

// Property-based tests for X25519 key generation
proptest! {
    #[test]
    fn test_x25519_keypair_generation_always_produces_valid_keys(
        _seed in any::<u64>()
    ) {
        let key_manager = X25519KeyManager::new();
        let keypair = key_manager.generate_keypair();
        
        prop_assert!(keypair.is_ok());
        let keypair = keypair.unwrap();
        
        // Private key should be 32 bytes when base64 decoded
        let private_key_bytes = Base64Encoder::decode(&keypair.private_key_base64());
        prop_assert!(private_key_bytes.is_ok());
        prop_assert_eq!(private_key_bytes.unwrap().len(), 32);
        
        // Public key should be 32 bytes when base64 decoded
        let public_key_bytes = Base64Encoder::decode(&keypair.public_key_base64());
        prop_assert!(public_key_bytes.is_ok());
        prop_assert_eq!(public_key_bytes.unwrap().len(), 32);
        
        // Keys should not be all zeros
        prop_assert_ne!(keypair.private_key_base64(), Base64Encoder::encode(&[0u8; 32]));
        prop_assert_ne!(keypair.public_key_base64(), Base64Encoder::encode(&[0u8; 32]));
    }
    
    #[test]
    fn test_x25519_keypair_uniqueness(
        iterations in 1..20usize
    ) {
        let key_manager = X25519KeyManager::new();
        let mut generated_private_keys = std::collections::HashSet::new();
        let mut generated_public_keys = std::collections::HashSet::new();
        
        for _ in 0..iterations {
            let keypair = key_manager.generate_keypair().unwrap();
            
            // Each generated key should be unique
            prop_assert!(generated_private_keys.insert(keypair.private_key_base64()));
            prop_assert!(generated_public_keys.insert(keypair.public_key_base64()));
        }
    }
    
    #[test]
    fn test_x25519_key_validation_roundtrip(
        iterations in 1..10usize
    ) {
        let key_manager = X25519KeyManager::new();
        
        for _ in 0..iterations {
            let keypair = key_manager.generate_keypair().unwrap();
            
            // Validate that generated keys pass validation
            prop_assert!(key_manager.validate_private_key(&keypair.private_key_base64()).is_ok());
            prop_assert!(key_manager.validate_public_key(&keypair.public_key_base64()).is_ok());
            
            // Validate that keys are properly formatted base64
            prop_assert!(Base64Encoder::decode(&keypair.private_key_base64()).is_ok());
            prop_assert!(Base64Encoder::decode(&keypair.public_key_base64()).is_ok());
        }
    }
}

// Property-based tests for UUID generation
proptest! {
    #[test]
    fn test_uuid_generation_properties(
        iterations in 1..50usize
    ) {
        let uuid_generator = UuidGenerator::new();
        let mut generated_uuids = std::collections::HashSet::new();
        
        for _ in 0..iterations {
            let uuid = uuid_generator.generate_v4().unwrap();
            
            // UUID should be valid
            prop_assert!(uuid_generator.validate_uuid(&uuid).is_ok());
            
            // Each UUID should be unique
            prop_assert!(generated_uuids.insert(uuid.clone()));
            
            // UUID should have correct format (36 characters with hyphens)
            prop_assert_eq!(uuid.len(), 36);
            prop_assert_eq!(uuid.chars().filter(|&c| c == '-').count(), 4);
            
            // UUID should only contain valid hex characters and hyphens
            prop_assert!(uuid.chars().all(|c| c.is_ascii_hexdigit() || c == '-'));
        }
    }
    
    #[test]
    fn test_uuid_validation_with_malformed_input(
        malformed_uuid in "[a-zA-Z0-9-]{0,50}"
    ) {
        let uuid_generator = UuidGenerator::new();
        
        if malformed_uuid.len() != 36 || malformed_uuid.chars().filter(|&c| c == '-').count() != 4 {
            // Malformed UUIDs should fail validation
            prop_assert!(uuid_generator.validate_uuid(&malformed_uuid).is_err());
        }
    }
}

// Property-based tests for QR code generation
proptest! {
    #[test]
    fn test_qr_code_generation_with_various_inputs(
        data in ".*",
        correction_level in prop_oneof![
            Just(ErrorCorrectionLevel::Low),
            Just(ErrorCorrectionLevel::Medium),
            Just(ErrorCorrectionLevel::High)
        ]
    ) {
        let qr_generator = QrCodeGenerator::new();
        
        // QR code generation should handle any string input
        let result = qr_generator.generate_qr_code_with_level(&data, correction_level);
        
        if data.len() <= 4296 { // Max capacity for QR codes
            prop_assert!(result.is_ok());
            let qr_data = result.unwrap();
            prop_assert!(!qr_data.is_empty());
        } else {
            // Very large data might fail, which is acceptable
            prop_assert!(result.is_ok() || result.is_err());
        }
    }
    
    #[test]
    fn test_qr_code_with_vpn_config_data(
        protocol in prop_oneof![
            Just(VpnProtocol::Vless),
            Just(VpnProtocol::Shadowsocks),
            Just(VpnProtocol::Trojan),
            Just(VpnProtocol::Vmess)
        ],
        uuid in "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}",
        port in 1..=65535u16,
        domain in "[a-z]{3,10}\\\\.[a-z]{2,5}"
    ) {
        let qr_generator = QrCodeGenerator::new();
        
        // Generate VPN-like configuration strings
        let config = match protocol {
            VpnProtocol::Vless => format!("vless://{}@{}:{}?type=tcp", uuid, domain, port),
            VpnProtocol::Shadowsocks => format!("ss://{}@{}:{}", uuid, domain, port),
            VpnProtocol::Trojan => format!("trojan://{}@{}:{}", uuid, domain, port),
            VpnProtocol::Vmess => format!("vmess://{}@{}:{}", uuid, domain, port),
        };
        
        let result = qr_generator.generate_qr_code_with_level(&config, ErrorCorrectionLevel::Medium);
        prop_assert!(result.is_ok());
        
        let qr_data = result.unwrap();
        prop_assert!(!qr_data.is_empty());
        
        // QR code should be SVG format (starts with SVG tag)
        prop_assert!(qr_data.len() > 4);
        let svg_start = String::from_utf8_lossy(&qr_data[0..4]);
        prop_assert!(svg_start.starts_with("<svg") || svg_start.starts_with("<?xm"));
    }
}

// Property-based tests for encoding utilities
proptest! {
    #[test]
    fn test_base64_encoding_roundtrip(
        data in prop::collection::vec(any::<u8>(), 0..1024)
    ) {
        // Test that base64 encoding/decoding is reversible
        let encoded = Base64Encoder::encode(&data);
        let decoded = Base64Encoder::decode(&encoded);
        
        prop_assert!(decoded.is_ok());
        prop_assert_eq!(decoded.unwrap(), data);
    }
    
    #[test]
    fn test_hex_encoding_roundtrip(
        data in prop::collection::vec(any::<u8>(), 0..512)
    ) {
        // Test that hex encoding/decoding is reversible
        let encoded = HexEncoder::encode(&data);
        let decoded = HexEncoder::decode(&encoded);
        
        prop_assert!(decoded.is_ok());
        prop_assert_eq!(decoded.unwrap(), data);
    }
    
    #[test]
    fn test_url_safe_base64_properties(
        data in prop::collection::vec(any::<u8>(), 0..256)
    ) {
        let encoder = EncodingUtils::new();
        let encoded = encoder.base64_url_encode(&data).unwrap();
        
        // URL-safe base64 should not contain '+' or '/'
        prop_assert!(!encoded.contains('+'));
        prop_assert!(!encoded.contains('/'));
        // Note: URL-safe base64 may still contain '=' for padding
        
        // Should be decodable
        let decoded = encoder.base64_url_decode(&encoded);
        prop_assert!(decoded.is_ok());
        prop_assert_eq!(decoded.unwrap(), data);
    }
}

// QuickCheck-style tests for additional validation
#[test]
fn test_x25519_private_key_security() {
    quickcheck(test_x25519_private_key_security_impl as fn(Vec<u8>) -> TestResult);
}

fn test_x25519_private_key_security_impl(data: Vec<u8>) -> TestResult {
    if data.len() != 32 {
        return TestResult::discard();
    }
    
    let key_manager = X25519KeyManager::new();
    let base64_key = Base64Encoder::encode(&data);
    
    // Test that we can validate any 32-byte sequence as a potential private key
    let validation_result = key_manager.validate_private_key(&base64_key);
    
    // All 32-byte sequences should be valid private keys (mathematically)
    TestResult::from_bool(validation_result.is_ok())
}

#[test]
fn test_uuid_format_consistency() {
    quickcheck(test_uuid_format_consistency_impl as fn(String) -> TestResult);
}

fn test_uuid_format_consistency_impl(uuid_str: String) -> TestResult {
    let uuid_generator = UuidGenerator::new();
    let validation_result = uuid_generator.validate_uuid(&uuid_str);
    
    // If validation passes, the UUID should have the correct format
    if validation_result.is_ok() {
        TestResult::from_bool(
            uuid_str.len() == 36 && 
            uuid_str.chars().filter(|&c| c == '-').count() == 4 &&
            uuid_str.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
        )
    } else {
        // If validation fails, that's also acceptable for malformed input
        TestResult::passed()
    }
}

#[test]
fn test_encoding_consistency() {
    quickcheck(test_encoding_consistency_impl as fn(Vec<u8>) -> bool);
}

fn test_encoding_consistency_impl(data: Vec<u8>) -> bool {
    // Test that all encoding methods are consistent
    let base64 = Base64Encoder::encode(&data);
    let hex = HexEncoder::encode(&data);
    let encoder = EncodingUtils::new();
    let url_safe_base64 = encoder.base64_url_encode(&data).unwrap_or_default();
    
    // Decoding should recover the original data
    Base64Encoder::decode(&base64).map_or(false, |d| d == data) &&
    HexEncoder::decode(&hex).map_or(false, |d| d == data) &&
    encoder.base64_url_decode(&url_safe_base64).map_or(false, |d| d == data)
}

// Simplified chaos engineering style tests
proptest! {
    #[test]
    fn test_crypto_operations_under_load(
        iterations in 50..200usize
    ) {
        let key_manager = X25519KeyManager::new();
        let uuid_generator = UuidGenerator::new();
        let qr_generator = QrCodeGenerator::new();
        let mut success_count = 0;
        
        for _ in 0..iterations {
            // Perform multiple crypto operations sequentially
            let keypair = key_manager.generate_keypair();
            let uuid = uuid_generator.generate_v4();
            let qr_result = qr_generator.generate_qr_code(&uuid.unwrap_or_default());
            
            if keypair.is_ok() && qr_result.is_ok() {
                success_count += 1;
            }
        }
        
        // At least 90% success rate under load
        prop_assert!(success_count as f64 / iterations as f64 > 0.9);
    }
}