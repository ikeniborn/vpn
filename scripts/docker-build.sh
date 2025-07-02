#!/bin/bash
# Build multi-arch Docker images for VPN server

set -e

# Configuration
DOCKER_ORG="${DOCKER_ORG:-yourusername}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
VERSION="${VERSION:-$(git describe --tags --always --dirty)}"
PUSH="${PUSH:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker buildx version &> /dev/null; then
        log_error "Docker Buildx is not available"
        exit 1
    fi
    
    # Check if multi-arch builder exists
    if ! docker buildx ls | grep -q "multi-arch"; then
        log_info "Creating multi-arch builder..."
        docker buildx create --name multi-arch --driver docker-container --use
        docker buildx inspect --bootstrap
    else
        docker buildx use multi-arch
    fi
}

# Build function
build_image() {
    local dockerfile=$1
    local image_name=$2
    local context=${3:-.}
    
    log_info "Building $image_name from $dockerfile..."
    
    local build_args=(
        --platform "$PLATFORMS"
        --file "$dockerfile"
        --tag "${DOCKER_REGISTRY}/${DOCKER_ORG}/${image_name}:${VERSION}"
        --tag "${DOCKER_REGISTRY}/${DOCKER_ORG}/${image_name}:latest"
        --build-arg "VERSION=${VERSION}"
        --build-arg "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --build-arg "VCS_REF=$(git rev-parse --short HEAD)"
        --cache-from "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_ORG}/${image_name}:buildcache"
        --cache-to "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_ORG}/${image_name}:buildcache,mode=max"
    )
    
    if [ "$PUSH" == "true" ]; then
        build_args+=(--push)
    else
        build_args+=(--load)
        log_warning "Building for local platform only (use PUSH=true for multi-arch push)"
    fi
    
    docker buildx build "${build_args[@]}" "$context"
}

# Main execution
main() {
    log_info "Starting multi-arch Docker build process..."
    log_info "Version: $VERSION"
    log_info "Platforms: $PLATFORMS"
    log_info "Registry: $DOCKER_REGISTRY/$DOCKER_ORG"
    
    check_requirements
    
    # Build main VPN server image
    build_image "Dockerfile" "vpn-rust"
    
    # Build proxy auth service
    build_image "docker/proxy/Dockerfile.auth" "vpn-rust-proxy-auth"
    
    # Build identity service
    build_image "docker/Dockerfile.identity" "vpn-rust-identity"
    
    log_info "Build completed successfully!"
    
    if [ "$PUSH" != "true" ]; then
        log_warning "Images built locally. To push to registry, run:"
        log_warning "PUSH=true $0"
    else
        log_info "Images pushed to registry:"
        log_info "  - ${DOCKER_REGISTRY}/${DOCKER_ORG}/vpn-rust:${VERSION}"
        log_info "  - ${DOCKER_REGISTRY}/${DOCKER_ORG}/vpn-rust-proxy-auth:${VERSION}"
        log_info "  - ${DOCKER_REGISTRY}/${DOCKER_ORG}/vpn-rust-identity:${VERSION}"
    fi
}

# Run main function
main "$@"