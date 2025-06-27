use vpn_crypto::{
    X25519KeyManager, UuidGenerator, QrCodeGenerator, 
    EncodingUtils, KeyPair, VpnProtocol
};
use uuid::Uuid;

#[test]
fn test_x25519_key_generation() -> Result<(), Box<dyn std::error::Error>> {
    let key_manager = X25519KeyManager::new();
    
    // Test key pair generation
    let keypair = key_manager.generate_keypair()?;
    assert_eq!(keypair.private_key.len(), 44); // Base64 encoded 32 bytes
    assert_eq!(keypair.public_key.len(), 44);
    
    // Test that keys are different each time
    let keypair2 = key_manager.generate_keypair()?;
    assert_ne!(keypair.private_key, keypair2.private_key);
    assert_ne!(keypair.public_key, keypair2.public_key);
    
    Ok(())
}

#[test]
fn test_x25519_key_validation() -> Result<(), Box<dyn std::error::Error>> {
    let key_manager = X25519KeyManager::new();
    
    // Test valid key validation
    let keypair = key_manager.generate_keypair()?;
    assert!(key_manager.validate_private_key(&keypair.private_key).is_ok());
    assert!(key_manager.validate_public_key(&keypair.public_key).is_ok());
    
    // Test invalid key validation
    assert!(key_manager.validate_private_key("invalid-key").is_err());
    assert!(key_manager.validate_public_key("").is_err());
    assert!(key_manager.validate_private_key("not-base64!@#").is_err());
    
    Ok(())
}

#[test]
fn test_x25519_public_key_derivation() -> Result<(), Box<dyn std::error::Error>> {
    let key_manager = X25519KeyManager::new();
    let keypair = key_manager.generate_keypair()?;
    
    // Test deriving public key from private key
    let derived_public = key_manager.derive_public_key(&keypair.private_key)?;
    assert_eq!(derived_public, keypair.public_key);
    
    Ok(())
}

#[test]
fn test_uuid_generation() -> Result<(), Box<dyn std::error::Error>> {
    let uuid_gen = UuidGenerator::new();
    
    // Test UUID v4 generation
    let uuid1 = uuid_gen.generate_v4()?;
    let uuid2 = uuid_gen.generate_v4()?;
    
    assert_ne!(uuid1, uuid2);
    assert!(Uuid::parse_str(&uuid1).is_ok());
    assert!(Uuid::parse_str(&uuid2).is_ok());
    
    // Test short ID generation
    let short_id1 = uuid_gen.generate_short_id(&uuid1)?;
    let short_id2 = uuid_gen.generate_short_id(&uuid2)?;
    
    assert_ne!(short_id1, short_id2);
    assert_eq!(short_id1.len(), 16); // 8 bytes in hex
    assert_eq!(short_id2.len(), 16);
    
    // Test consistency
    let short_id1_again = uuid_gen.generate_short_id(&uuid1)?;
    assert_eq!(short_id1, short_id1_again);
    
    Ok(())
}

#[test]
fn test_uuid_validation() {
    let uuid_gen = UuidGenerator::new();
    
    // Test valid UUIDs
    assert!(uuid_gen.validate_uuid("550e8400-e29b-41d4-a716-446655440000").is_ok());
    assert!(uuid_gen.validate_uuid("6ba7b810-9dad-11d1-80b4-00c04fd430c8").is_ok());
    
    // Test invalid UUIDs
    assert!(uuid_gen.validate_uuid("invalid-uuid").is_err());
    assert!(uuid_gen.validate_uuid("").is_err());
    assert!(uuid_gen.validate_uuid("550e8400-e29b-41d4-a716").is_err());
    assert!(uuid_gen.validate_uuid("550e8400-e29b-41d4-a716-446655440000-extra").is_err());
}

#[test]
fn test_qr_code_generation() -> Result<(), Box<dyn std::error::Error>> {
    let qr_gen = QrCodeGenerator::new();
    
    // Test simple text QR code
    let qr_data = qr_gen.generate_qr_code("Hello, World!")?;
    assert!(!qr_data.is_empty());
    
    // Test VLESS connection URL
    let vless_url = "vless://uuid@example.com:443?type=tcp&security=reality&sni=google.com";
    let qr_data = qr_gen.generate_qr_code(vless_url)?;
    assert!(!qr_data.is_empty());
    
    // Test saving QR code (creates file)
    let temp_path = "/tmp/test_qr.png";
    qr_gen.save_qr_code_to_file("Test QR Code", temp_path)?;
    assert!(std::path::Path::new(temp_path).exists());
    
    // Cleanup
    std::fs::remove_file(temp_path).ok();
    
    Ok(())
}

#[test]
fn test_qr_code_error_correction() -> Result<(), Box<dyn std::error::Error>> {
    let qr_gen = QrCodeGenerator::new();
    
    // Test different error correction levels
    let data = "Test data for QR code";
    
    let qr_low = qr_gen.generate_qr_code_with_level(data, vpn_crypto::ErrorCorrectionLevel::Low)?;
    let qr_medium = qr_gen.generate_qr_code_with_level(data, vpn_crypto::ErrorCorrectionLevel::Medium)?;
    let qr_high = qr_gen.generate_qr_code_with_level(data, vpn_crypto::ErrorCorrectionLevel::High)?;
    
    // All should generate valid QR codes
    assert!(!qr_low.is_empty());
    assert!(!qr_medium.is_empty());
    assert!(!qr_high.is_empty());
    
    Ok(())
}

#[test]
fn test_encoding_utils() -> Result<(), Box<dyn std::error::Error>> {
    let utils = EncodingUtils::new();
    
    // Test Base64 encoding/decoding
    let original = "Hello, World!";
    let encoded = utils.base64_encode(original.as_bytes())?;
    let decoded = utils.base64_decode(&encoded)?;
    assert_eq!(original.as_bytes(), decoded);
    
    // Test hex encoding/decoding
    let hex_encoded = utils.hex_encode(original.as_bytes());
    let hex_decoded = utils.hex_decode(&hex_encoded)?;
    assert_eq!(original.as_bytes(), hex_decoded);
    
    // Test URL-safe Base64
    let url_safe_encoded = utils.base64_url_encode(original.as_bytes())?;
    let url_safe_decoded = utils.base64_url_decode(&url_safe_encoded)?;
    assert_eq!(original.as_bytes(), url_safe_decoded);
    
    Ok(())
}

#[test]
fn test_encoding_edge_cases() -> Result<(), Box<dyn std::error::Error>> {
    let utils = EncodingUtils::new();
    
    // Test empty data
    let empty_encoded = utils.base64_encode(&[])?;
    let empty_decoded = utils.base64_decode(&empty_encoded)?;
    assert_eq!(empty_decoded, Vec::<u8>::new());
    
    // Test binary data
    let binary_data: Vec<u8> = (0..255).collect();
    let binary_encoded = utils.base64_encode(&binary_data)?;
    let binary_decoded = utils.base64_decode(&binary_encoded)?;
    assert_eq!(binary_data, binary_decoded);
    
    // Test invalid Base64
    assert!(utils.base64_decode("invalid!@#$%").is_err());
    
    // Test invalid hex
    assert!(utils.hex_decode("invalid_hex_string").is_err());
    
    Ok(())
}

#[test]
fn test_key_pair_structure() {
    let keypair = KeyPair {
        private_key: "private_key_data".to_string(),
        public_key: "public_key_data".to_string(),
    };
    
    assert_eq!(keypair.private_key, "private_key_data");
    assert_eq!(keypair.public_key, "public_key_data");
}

#[test]
fn test_vpn_protocol_serialization() -> Result<(), Box<dyn std::error::Error>> {
    // Test protocol serialization/deserialization
    let protocols = vec![
        VpnProtocol::Vless,
        VpnProtocol::Vmess, 
        VpnProtocol::Trojan,
        VpnProtocol::Shadowsocks,
    ];
    
    for protocol in protocols {
        let serialized = serde_json::to_string(&protocol)?;
        let deserialized: VpnProtocol = serde_json::from_str(&serialized)?;
        assert_eq!(protocol, deserialized);
    }
    
    Ok(())
}

#[test]
fn test_large_data_encoding() -> Result<(), Box<dyn std::error::Error>> {
    let utils = EncodingUtils::new();
    
    // Test large data encoding (1MB)
    let large_data: Vec<u8> = (0..1024*1024).map(|i| (i % 256) as u8).collect();
    let encoded = utils.base64_encode(&large_data)?;
    let decoded = utils.base64_decode(&encoded)?;
    
    assert_eq!(large_data.len(), decoded.len());
    assert_eq!(large_data, decoded);
    
    Ok(())
}

#[test]
fn test_concurrent_key_generation() -> Result<(), Box<dyn std::error::Error>> {
    use std::thread;
    use std::sync::Arc;
    
    let key_manager = Arc::new(X25519KeyManager::new());
    let mut handles = vec![];
    
    // Generate keys concurrently
    for _ in 0..10 {
        let km = Arc::clone(&key_manager);
        let handle = thread::spawn(move || {
            km.generate_keypair()
        });
        handles.push(handle);
    }
    
    let mut keypairs = vec![];
    for handle in handles {
        let keypair = handle.join().unwrap()?;
        keypairs.push(keypair);
    }
    
    // Verify all keys are unique
    for i in 0..keypairs.len() {
        for j in i+1..keypairs.len() {
            assert_ne!(keypairs[i].private_key, keypairs[j].private_key);
            assert_ne!(keypairs[i].public_key, keypairs[j].public_key);
        }
    }
    
    Ok(())
}