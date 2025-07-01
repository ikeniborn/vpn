# Build stage
FROM rust:1.75-slim AS builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Create workspace
WORKDIR /build

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY crates/ ./crates/

# Build operator
RUN cargo build --release --bin vpn-operator

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -u 65532 -m operator

# Copy binary
COPY --from=builder /build/target/release/vpn-operator /usr/local/bin/vpn-operator

# Set permissions
RUN chmod +x /usr/local/bin/vpn-operator

# Switch to non-root user
USER operator

# Expose ports
EXPOSE 8080 9443

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/vpn-operator"]