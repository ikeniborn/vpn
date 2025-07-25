# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rust-based VPN management system that provides comprehensive tools for managing Xray (VLESS+Reality), Outline VPN servers, and HTTP/SOCKS5 proxy servers. It replaces an original Bash implementation with a type-safe, high-performance alternative written in Rust.

### Key Infrastructure Components

- **Proxy/Load Balancer**: Traefik v3.x for reverse proxy, load balancing, and automatic SSL/TLS termination
- **VPN Server**: Xray-core with VLESS+Reality protocol for secure tunneling
- **Proxy Server**: Custom Rust-based HTTP/HTTPS and SOCKS5 proxy with authentication
- **Identity Management**: Custom Rust-based identity service with LDAP/OAuth2 support
- **Monitoring**: Prometheus + Grafana + Jaeger for comprehensive observability
- **Storage**: PostgreSQL for persistent data, Redis for sessions and caching
- **Orchestration**: Docker Compose with Traefik service discovery
- **Deployment**: Multi-arch Docker images (amd64, arm64) available on Docker Hub

## Development Guidelines

- Для получения актуальной информации перед разработкой используй инструмент context7

## Documentation

- Вся дополнительная документация хранится в каталоге docs на русском языке
- Все тестовые скрпиты хранятся в каталоге tests

## Important Reminders

- Никогда самостоятельно не редактируй CLAUDE.md. Требуй от пользователя согласования