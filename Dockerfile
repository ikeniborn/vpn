# Multi-stage Dockerfile for VPN Server
# Supports multi-arch builds (amd64, arm64)

# Build stage
FROM --platform=$BUILDPLATFORM rust:1.75-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev openssl-dev perl make

# Set up cross compilation
ARG TARGETARCH
ARG BUILDPLATFORM
RUN case "$TARGETARCH" in \
    "amd64") echo "x86_64-unknown-linux-musl" > /target.txt ;; \
    "arm64") echo "aarch64-unknown-linux-musl" > /target.txt ;; \
    *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac

# Create app directory
WORKDIR /app

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY crates/ ./crates/

# Install cross compilation tools if needed
RUN if [ "$BUILDPLATFORM" != "linux/$TARGETARCH" ]; then \
        rustup target add $(cat /target.txt); \
    fi

# Build release binary
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/app/target \
    cargo build --release --target $(cat /target.txt) --bin vpn && \
    cp target/$(cat /target.txt)/release/vpn /vpn-binary

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    libgcc \
    docker-cli \
    docker-compose \
    curl \
    bash \
    sudo \
    shadow

# Create vpn user and group
RUN addgroup -g 1000 vpn && \
    adduser -D -u 1000 -G vpn -s /bin/bash vpn && \
    echo "vpn ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create necessary directories
RUN mkdir -p /opt/vpn /etc/vpn /var/log/vpn && \
    chown -R vpn:vpn /opt/vpn /etc/vpn /var/log/vpn

# Copy binary from builder
COPY --from=builder /vpn-binary /usr/local/bin/vpn
RUN chmod +x /usr/local/bin/vpn

# Copy templates and scripts
COPY --chown=vpn:vpn templates/ /opt/vpn/templates/
COPY --chown=vpn:vpn scripts/ /opt/vpn/scripts/

# Set environment variables
ENV VPN_INSTALL_PATH=/opt/vpn \
    VPN_CONFIG_PATH=/etc/vpn/config.toml \
    VPN_LOG_PATH=/var/log/vpn

# Switch to vpn user
USER vpn
WORKDIR /opt/vpn

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD vpn status || exit 1

# Default command
CMD ["vpn", "--help"]

# Labels
LABEL org.opencontainers.image.title="VPN Server" \
      org.opencontainers.image.description="Advanced VPN Server Management Tool" \
      org.opencontainers.image.vendor="VPN Project Team" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/yourusername/vpn-rust" \
      org.opencontainers.image.documentation="https://github.com/yourusername/vpn-rust/blob/main/README.md"