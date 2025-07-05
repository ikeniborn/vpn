//! High Availability integration tests

use std::collections::HashMap;
use vpn_compose::{ComposeConfig, HAConfig, HAManager, MultiRegionConfig, RoutingPolicy};

#[tokio::test]
async fn test_ha_manager_creation() {
    let compose_config = ComposeConfig::default();
    let ha_config = HAConfig::default();

    let manager = HAManager::new(ha_config, compose_config).await;
    assert!(manager.is_ok());
}

#[tokio::test]
async fn test_ha_config_with_replicas() {
    let ha_config = HAConfig {
        enabled: true,
        vpn_replicas: 5,
        api_replicas: 3,
        nginx_replicas: 2,
        virtual_ip: "192.168.100.100".to_string(),
        auto_failover: true,
        health_check_interval: 5,
        failover_timeout: 20,
        service_discovery: true,
        redis_sentinel: true,
        postgres_replication: true,
        postgres_replicas: 3,
        keepalived: true,
        multi_region: None,
    };

    assert_eq!(ha_config.vpn_replicas, 5);
    assert_eq!(ha_config.api_replicas, 3);
    assert_eq!(ha_config.virtual_ip, "192.168.100.100");
    assert!(ha_config.auto_failover);
}

#[tokio::test]
async fn test_multi_region_config() {
    let mut region_endpoints = HashMap::new();
    region_endpoints.insert("us-east".to_string(), "east.vpn.example.com".to_string());
    region_endpoints.insert("us-west".to_string(), "west.vpn.example.com".to_string());
    region_endpoints.insert("eu-central".to_string(), "eu.vpn.example.com".to_string());

    let multi_region = MultiRegionConfig {
        primary_region: "us-east".to_string(),
        secondary_regions: vec!["us-west".to_string(), "eu-central".to_string()],
        cross_region_replication: true,
        region_endpoints,
        routing_policy: RoutingPolicy::GeoProximity,
    };

    assert_eq!(multi_region.primary_region, "us-east");
    assert_eq!(multi_region.secondary_regions.len(), 2);
    assert!(multi_region.cross_region_replication);
}

#[tokio::test]
async fn test_routing_policies() {
    // Test GeoProximity
    let geo_policy = RoutingPolicy::GeoProximity;
    assert!(matches!(geo_policy, RoutingPolicy::GeoProximity));

    // Test Failover
    let failover_policy = RoutingPolicy::Failover;
    assert!(matches!(failover_policy, RoutingPolicy::Failover));

    // Test Weighted
    let mut weights = HashMap::new();
    weights.insert("us-east".to_string(), 60);
    weights.insert("us-west".to_string(), 40);
    let weighted_policy = RoutingPolicy::Weighted(weights.clone());

    if let RoutingPolicy::Weighted(w) = weighted_policy {
        assert_eq!(w.get("us-east"), Some(&60));
        assert_eq!(w.get("us-west"), Some(&40));
    } else {
        panic!("Expected Weighted routing policy");
    }

    // Test RoundRobin
    let rr_policy = RoutingPolicy::RoundRobin;
    assert!(matches!(rr_policy, RoutingPolicy::RoundRobin));
}

#[tokio::test]
async fn test_ha_config_serialization() {
    let ha_config = HAConfig {
        enabled: true,
        vpn_replicas: 3,
        api_replicas: 2,
        nginx_replicas: 2,
        virtual_ip: "10.0.0.100".to_string(),
        auto_failover: true,
        health_check_interval: 10,
        failover_timeout: 30,
        service_discovery: true,
        redis_sentinel: true,
        postgres_replication: true,
        postgres_replicas: 2,
        keepalived: true,
        multi_region: None,
    };

    // Test JSON serialization
    let json = serde_json::to_string(&ha_config).unwrap();
    assert!(json.contains("\"enabled\":true"));
    assert!(json.contains("\"vpn_replicas\":3"));
    assert!(json.contains("\"virtual_ip\":\"10.0.0.100\""));

    // Test deserialization
    let deserialized: HAConfig = serde_json::from_str(&json).unwrap();
    assert_eq!(deserialized.enabled, ha_config.enabled);
    assert_eq!(deserialized.vpn_replicas, ha_config.vpn_replicas);
    assert_eq!(deserialized.virtual_ip, ha_config.virtual_ip);
}

#[tokio::test]
async fn test_ha_health_status_structure() {
    use vpn_compose::HAHealthStatus;

    let mut active_replicas = HashMap::new();
    active_replicas.insert("vpn-server".to_string(), 3);
    active_replicas.insert("vpn-api".to_string(), 2);
    active_replicas.insert("nginx-proxy".to_string(), 2);

    let mut expected_replicas = HashMap::new();
    expected_replicas.insert("vpn-server".to_string(), 3);
    expected_replicas.insert("vpn-api".to_string(), 3);
    expected_replicas.insert("nginx-proxy".to_string(), 2);

    let health_status = HAHealthStatus {
        overall_health: "degraded".to_string(),
        vpn_servers_healthy: true,
        api_servers_healthy: false,
        load_balancer_healthy: true,
        service_discovery_healthy: true,
        active_replicas,
        expected_replicas,
    };

    assert_eq!(health_status.overall_health, "degraded");
    assert!(health_status.vpn_servers_healthy);
    assert!(!health_status.api_servers_healthy);
    assert_eq!(health_status.active_replicas.get("vpn-api"), Some(&2));
    assert_eq!(health_status.expected_replicas.get("vpn-api"), Some(&3));
}

#[tokio::test]
async fn test_multi_region_with_weighted_routing() {
    let mut weights = HashMap::new();
    weights.insert("us-east".to_string(), 50);
    weights.insert("us-west".to_string(), 30);
    weights.insert("eu-central".to_string(), 20);

    let mut region_endpoints = HashMap::new();
    region_endpoints.insert("us-east".to_string(), "east.vpn.example.com".to_string());
    region_endpoints.insert("us-west".to_string(), "west.vpn.example.com".to_string());
    region_endpoints.insert("eu-central".to_string(), "eu.vpn.example.com".to_string());

    let multi_region = MultiRegionConfig {
        primary_region: "us-east".to_string(),
        secondary_regions: vec!["us-west".to_string(), "eu-central".to_string()],
        cross_region_replication: true,
        region_endpoints,
        routing_policy: RoutingPolicy::Weighted(weights),
    };

    // Verify weighted routing configuration
    if let RoutingPolicy::Weighted(w) = &multi_region.routing_policy {
        let total_weight: u32 = w.values().sum();
        assert_eq!(total_weight, 100);
        assert_eq!(w.get("us-east"), Some(&50));
    } else {
        panic!("Expected Weighted routing policy");
    }
}

// Note: Full integration tests would require a Docker environment
// These tests verify the structure and basic functionality
