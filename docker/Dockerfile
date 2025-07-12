# Multi-stage build for VPN Manager Python
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry
ENV POETRY_VERSION=1.6.1
RUN pip install poetry==$POETRY_VERSION

# Configure Poetry
ENV POETRY_NO_INTERACTION=1 \
    POETRY_VENV_IN_PROJECT=1 \
    POETRY_CACHE_DIR=/tmp/poetry_cache

# Copy dependency files
WORKDIR /app
COPY pyproject.toml poetry.lock ./

# Install dependencies
RUN poetry install --only=main --no-root && rm -rf $POETRY_CACHE_DIR

# Copy source code
COPY . .

# Install the application
RUN poetry install --only=main

# Production stage
FROM python:3.11-slim as production

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    iptables \
    iproute2 \
    net-tools \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://get.docker.com | sh

# Create app user
RUN useradd --create-home --shell /bin/bash app

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application
COPY --from=builder /app /app

# Set permissions
RUN chown -R app:app /app

# Switch to app user
USER app
WORKDIR /app

# Ensure virtual environment is in PATH
ENV PATH="/app/.venv/bin:$PATH"

# Create directories
RUN mkdir -p /home/app/.config/vpn-manager \
             /home/app/.local/share/vpn-manager \
             /home/app/.cache/vpn-manager

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD vpn doctor --check basic || exit 1

# Default command
CMD ["vpn", "server", "start", "--all"]

# Expose common ports
EXPOSE 8443 8444 1080 8888 51820

# Labels
LABEL maintainer="VPN Manager Team <team@vpn-manager.io>"
LABEL org.opencontainers.image.title="VPN Manager Python"
LABEL org.opencontainers.image.description="Comprehensive VPN management system with Python/Pydantic/TUI stack"
LABEL org.opencontainers.image.url="https://github.com/vpn-manager/vpn-python"
LABEL org.opencontainers.image.source="https://github.com/vpn-manager/vpn-python"
LABEL org.opencontainers.image.documentation="https://docs.vpn-manager.io"
LABEL org.opencontainers.image.licenses="MIT"

# Development stage
FROM builder as development

# Install development dependencies
RUN poetry install

# Install additional development tools
RUN apt-get update && apt-get install -y \
    vim \
    less \
    tree \
    htop \
    && rm -rf /var/lib/apt/lists/*

# Switch to app user
USER app
WORKDIR /app

# Set development environment variables
ENV PYTHONPATH=/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VPN_LOG_LEVEL=debug

# Default command for development
CMD ["bash"]