# VPN Kubernetes Operator

A Kubernetes operator for managing VPN server deployments with support for multiple protocols (VLESS, Outline, WireGuard, OpenVPN).

## Features

- **Multi-Protocol Support**: Deploy VPN servers using different protocols
- **High Availability**: Built-in support for HA deployments with multiple replicas
- **Auto-scaling**: Automatic scaling based on user count and resource usage
- **Security**: TLS support, firewall rules, and network policies
- **Monitoring**: Prometheus metrics and distributed tracing support
- **User Management**: Automatic user provisioning with quotas
- **External Auth**: Integration with LDAP, OAuth2, OIDC, and SAML

## Installation

### Prerequisites

- Kubernetes 1.24+
- kubectl configured to access your cluster
- Helm 3.0+ (optional, for Helm installation)

### Install CRDs

```bash
kubectl apply -f deploy/manifests/crd.yaml
```

### Install Operator

```bash
# Create namespace
kubectl create namespace vpn-system

# Install RBAC
kubectl apply -f deploy/manifests/rbac.yaml

# Deploy operator
kubectl apply -f deploy/manifests/deployment.yaml
```

## Usage

### Create a VPN Server

```yaml
apiVersion: vpn.io/v1alpha1
kind: VpnServer
metadata:
  name: my-vpn
  namespace: default
spec:
  protocol: vless
  port: 8443
  replicas: 2
  highAvailability: true
  users:
    maxUsers: 100
    autoCreate: true
    quotaGb: 50
  network:
    serviceType: LoadBalancer
  security:
    enableTls: true
    enableFirewall: true
  monitoring:
    enableMetrics: true
```

Apply the configuration:

```bash
kubectl apply -f vpnserver.yaml
```

### Check Status

```bash
# List VPN servers
kubectl get vpnservers

# Get detailed status
kubectl describe vpnserver my-vpn

# Check operator logs
kubectl logs -n vpn-system deployment/vpn-operator
```

## Configuration

### Operator Configuration

The operator can be configured via command-line flags or a configuration file:

```yaml
# /etc/vpn-operator/config.yaml
namespace: ""  # Watch all namespaces
vpnImage: "vpn-server:latest"
defaultProtocol: "vless"
enableHA: false
metricsPort: 8080
webhookPort: 9443
leaderElection: true
resourceLimits:
  cpuRequest: "100m"
  cpuLimit: "500m"
  memoryRequest: "128Mi"
  memoryLimit: "512Mi"
```

### VPN Server Specification

#### Protocol Options
- `vless`: VLESS + Reality protocol
- `outline`: Shadowsocks-based Outline
- `wireguard`: WireGuard VPN
- `openvpn`: OpenVPN

#### Network Types
- `ClusterIP`: Internal cluster access only
- `NodePort`: Expose on a specific node port
- `LoadBalancer`: Cloud provider load balancer

#### External Authentication

```yaml
spec:
  users:
    externalAuth:
      authType: ldap
      endpoint: ldap://ldap.example.com
      secretName: ldap-credentials
```

Create the secret:

```bash
kubectl create secret generic ldap-credentials \
  --from-literal=username=admin \
  --from-literal=password=secret
```

## Monitoring

### Prometheus Metrics

The operator exposes metrics on port 8080:

- `vpn_server_total`: Total number of VPN servers
- `vpn_server_ready`: Number of ready VPN servers
- `vpn_server_users_active`: Active users per server
- `vpn_server_traffic_bytes`: Traffic statistics

### Grafana Dashboard

Import the dashboard from `deploy/monitoring/dashboard.json`.

## Development

### Building

```bash
# Build operator binary
cargo build --release --bin vpn-operator

# Build Docker image
docker build -t vpn-operator:latest .
```

### Running Locally

```bash
# Set KUBECONFIG
export KUBECONFIG=~/.kube/config

# Run operator
cargo run --bin vpn-operator -- --debug
```

### Testing

```bash
# Run unit tests
cargo test -p vpn-operator

# Run integration tests (requires kind/minikube)
./scripts/integration-test.sh
```

## Troubleshooting

### Common Issues

1. **Operator not starting**
   - Check RBAC permissions: `kubectl auth can-i --list -n vpn-system --as system:serviceaccount:vpn-system:vpn-operator`
   - Check logs: `kubectl logs -n vpn-system deployment/vpn-operator`

2. **VPN server stuck in Pending**
   - Check events: `kubectl describe vpnserver <name>`
   - Verify resource availability: `kubectl describe nodes`

3. **Unable to connect to VPN**
   - Check service endpoint: `kubectl get svc`
   - Verify firewall rules allow traffic
   - Check VPN server logs: `kubectl logs <vpn-pod>`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details