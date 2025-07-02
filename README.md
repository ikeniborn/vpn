# VPN Management System

🦀 **Высокопроизводительная система управления VPN на Rust** с поддержкой Xray (VLESS+Reality), Outline VPN и прокси-серверов.

[![CI Status](https://github.com/ikeniborn/vpn/workflows/CI/badge.svg)](https://github.com/ikeniborn/vpn/actions)
[![Docker Build](https://github.com/ikeniborn/vpn/workflows/Docker%20Build%20and%20Publish/badge.svg)](https://github.com/ikeniborn/vpn/actions)
[![Security Audit](https://github.com/ikeniborn/vpn/workflows/Security%20Audit/badge.svg)](https://github.com/ikeniborn/vpn/actions)
[![Rust Version](https://img.shields.io/badge/rust-1.75+-blue.svg)](https://www.rust-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 🚀 Быстрый старт

```bash
# Установка одной командой (НЕ используйте sudo)
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install.sh | bash

# После установки
vpn menu  # Интерактивное меню
```

## ✨ Основные возможности

### Протоколы и безопасность
- **VPN протоколы**: VLESS+Reality, VMess, Trojan, Shadowsocks
- **Прокси-сервер**: HTTP/HTTPS и SOCKS5 с аутентификацией
- **Шифрование**: X25519, Reality protocol, автоматическая ротация ключей
- **Управление доступом**: LDAP/OAuth2, IP-whitelist, rate limiting

### Производительность
- **Запуск**: 0.005с (в 420 раз быстрее bash-версии)
- **Память**: ~10MB (на 78% меньше)
- **Операции**: создание пользователя 15мс, генерация ключей 8мс
- **Zero-copy**: использование Linux splice для оптимальной передачи данных

### Инфраструктура
- **Orchestration**: Docker Compose с Traefik v3.x
- **Мониторинг**: Prometheus + Grafana + Jaeger
- **Хранение**: PostgreSQL + Redis
- **Архитектуры**: x86_64, ARM64, ARMv7

## 📦 Установка

### Системные требования

**Минимальные:**
- CPU: 1 vCPU
- RAM: 512MB
- Storage: 2GB
- OS: Linux с systemd

**Рекомендуемые:**
- CPU: 2+ vCPU
- RAM: 1GB+
- Storage: 10GB+

### Варианты установки

#### 1. Автоматическая установка (рекомендуется)

```bash
# Полная установка с Docker
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install.sh | bash

# Опции установки
./install.sh --no-menu       # Без интерактивного меню
./install.sh --skip-docker   # Без Docker
./install.sh --binary-only   # Только бинарный файл
```

#### 2. Production развертывание

**Docker (рекомендуется):**
```bash
# На сборочной машине
./scripts/docker-build.sh
docker save vpn:latest | gzip > vpn.tar.gz

# На production сервере
docker load < vpn.tar.gz
docker-compose up -d
```

**Бинарные файлы:**
```bash
# Клонировать и собрать локально
git clone https://github.com/ikeniborn/vpn.git
cd vpn
cargo build --release
sudo cp target/release/vpn /usr/local/bin/
sudo chmod +x /usr/local/bin/vpn
```

#### 3. Сборка из исходников

```bash
# Установить Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Клонировать и собрать
git clone https://github.com/ikeniborn/vpn.git
cd vpn
cargo install --path crates/vpn-cli
```

## 💻 Использование

### Основные команды

```bash
# Управление сервером
sudo vpn install --protocol vless --port 443
sudo vpn status
sudo vpn start/stop/restart

# Управление пользователями
sudo vpn users create alice
vpn users list
vpn users link alice --qr

# Прокси-сервер
sudo vpn install --protocol proxy-server --port 8888
vpn proxy status --detailed
vpn proxy monitor --user alice

# Мониторинг
vpn doctor              # Диагностика системы
vpn monitor traffic     # Статистика трафика
vpn monitor health      # Проверка здоровья
```

### Интерактивное меню

```bash
vpn menu  # Удобный интерфейс для всех операций
```

### Конфигурация

```bash
vpn config edit                    # Редактировать конфигурацию
vpn config set server.port 8443    # Изменить параметр
```

## 🏗️ Архитектура

### Стек сервисов

```
├── Traefik v3.x        # Reverse proxy, SSL, балансировка
├── VPN Server          # Xray-core (VLESS+Reality)
├── Proxy Auth          # Аутентификация для прокси
├── Identity Service    # LDAP/OAuth2 интеграция
├── PostgreSQL          # База данных
├── Redis               # Кеш и сессии
├── Prometheus          # Метрики
├── Grafana             # Дашборды
└── Jaeger              # Трассировка
```

### Структура проекта

```
crates/
├── vpn-cli/        # CLI интерфейс
├── vpn-server/     # Управление сервером
├── vpn-users/      # Управление пользователями
├── vpn-proxy/      # HTTP/SOCKS5 прокси
├── vpn-docker/     # Docker интеграция
├── vpn-compose/    # Docker Compose
├── vpn-crypto/     # Криптография
├── vpn-network/    # Сетевые утилиты
├── vpn-monitor/    # Мониторинг
├── vpn-identity/   # Управление идентификацией
└── vpn-types/      # Общие типы
```

## 📊 Производительность

| Операция | Bash | Rust | Улучшение |
|----------|------|------|-----------|
| Запуск | 2.1с | 0.005с | **420x** |
| Создание пользователя | 250мс | 15мс | **16.7x** |
| Генерация ключей | 180мс | 8мс | **22.5x** |
| Docker операции | 320мс | 20мс | **16x** |
| Использование памяти | 45MB | 10MB | **-78%** |

## 📖 Документация

- [Docker руководство](docs/guides/DOCKER.md)
- [Руководство по безопасности](docs/guides/SECURITY.md)
- [Операционное руководство](docs/guides/OPERATIONS.md)
- [Оптимизация производительности](docs/guides/PERFORMANCE.md)
- [Архитектура системы](docs/architecture/)
- [Технические спецификации](docs/specs/)
- [История изменений](docs/CHANGELOG.md)

## 🤝 Участие в разработке

Мы приветствуем вклад в проект! См. [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
# Разработка
cargo test --workspace          # Тесты
cargo fmt --all                 # Форматирование
cargo clippy --workspace        # Линтер
cargo audit                     # Проверка безопасности
```

## 📄 Лицензия

MIT License - см. [LICENSE](LICENSE)

## 📊 Статус проекта

**Production Ready** - режим поддержки

- ✅ 8 недель разработки
- ✅ ~50,000+ строк кода
- ✅ 15+ специализированных crates
- ✅ Multi-arch Docker образы
- ✅ Полная документация

---

**Сделано с ❤️ и 🦀 Rust**

[🐛 Issues](https://github.com/ikeniborn/vpn/issues) | [💬 Discussions](https://github.com/ikeniborn/vpn/discussions)