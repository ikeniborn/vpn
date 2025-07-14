# VPN Management System

🦀 **Высокопроизводительная система управления VPN на Rust** с поддержкой Xray (VLESS+Reality), Outline VPN и прокси-серверов.

[![CI Status](https://github.com/ikeniborn/vpn/workflows/CI/badge.svg)](https://github.com/ikeniborn/vpn/actions)
[![Docker Build](https://github.com/ikeniborn/vpn/workflows/Docker%20Build%20and%20Publish/badge.svg)](https://github.com/ikeniborn/vpn/actions)
[![Security Audit](https://github.com/ikeniborn/vpn/workflows/Security%20Audit/badge.svg)](https://github.com/ikeniborn/vpn/actions)
[![Rust Version](https://img.shields.io/badge/rust-1.75+-blue.svg)](https://www.rust-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 🚀 Быстрый старт

**Rust-версия (рекомендуется для разработки):**
```bash
# Клонировать и установить Rust-версию
git clone https://github.com/ikeniborn/vpn.git
cd vpn
./install.sh  # Автоматически удалит конфликтующие версии

# После установки
vpn --version       # Проверить версию Rust
sudo vpn menu       # Интерактивное меню
```

**Production установка:**
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

#### 1. Установка из готового релиза (быстрая установка)

```bash
# Скачать готовый релиз
wget https://github.com/ikeniborn/vpn/releases/download/latest/vpn-release.tar.gz
tar -xzf vpn-release.tar.gz
cd vpn-release

# Установить
./install.sh

# Проверить установку
vpn --version
```

Скрипт установки автоматически:
- Обнаружит и предложит удалить существующие версии VPN
- Установит все необходимые компоненты
- Настроит systemd сервисы
- Создаст конфигурационные файлы

#### 2. Через GitHub Releases (рекомендуется)

```bash
# Автоматическая установка последней версии на удаленном сервере
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/rust/scripts/install-remote.sh | sudo bash

# Установка определенной версии
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/rust/scripts/install-remote.sh | sudo bash -s -- --version v1.2.3

# Дополнительные опции
sudo ./install-remote.sh --install-dir /opt/vpn/bin --config-dir /opt/vpn/config
sudo ./install-remote.sh --no-docker --no-firewall  # Минимальная установка
```

**Ручная установка из releases:**

```bash
# Скачать бинарный файл для вашей платформы
wget https://github.com/ikeniborn/vpn/releases/download/v1.2.3/vpn-x86_64-unknown-linux-gnu.tar.gz
wget https://github.com/ikeniborn/vpn/releases/download/v1.2.3/vpn-x86_64-unknown-linux-gnu.tar.gz.sha256

# Проверить контрольную сумму
sha256sum -c vpn-x86_64-unknown-linux-gnu.tar.gz.sha256

# Установить
tar -xzf vpn-x86_64-unknown-linux-gnu.tar.gz
sudo cp vpn /usr/local/bin/
sudo chmod +x /usr/local/bin/vpn
```

**Поддерживаемые платформы:**
- `x86_64-unknown-linux-gnu` - Linux x86_64
- `aarch64-unknown-linux-gnu` - Linux ARM64 (Raspberry Pi 4+)
- `armv7-unknown-linux-gnueabihf` - Linux ARMv7 (Raspberry Pi 3)
- `x86_64-unknown-linux-musl` - Linux x86_64 (статическая сборка)
- `x86_64-apple-darwin` - macOS Intel
- `aarch64-apple-darwin` - macOS Apple Silicon
- `x86_64-pc-windows-msvc` - Windows x86_64

**Docker образы доступны для:**
- `linux/amd64` - Intel/AMD x86_64
- `linux/arm64` - ARM64 (включая Apple Silicon, AWS Graviton)
- `linux/arm/v7` - ARMv7 (Raspberry Pi 3+)

```bash
# Использование через Docker
docker run --rm ghcr.io/ikeniborn/vpn:latest --help
```

#### 3. Автоматическая установка (локальная)

```bash
# Полная установка с Docker
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/rust/scripts/install.sh | bash

# Опции установки
./install.sh --no-menu       # Без интерактивного меню
./install.sh --skip-docker   # Без Docker
./install.sh --binary-only   # Только бинарный файл
```

#### 4. Production развертывание

**Docker (рекомендуется):**

**Вариант 1: Через Docker Registry (рекомендуется для команд)**
```bash
# На сборочной машине
docker build -t myregistry.com/vpn:latest .
docker push myregistry.com/vpn:latest

# На production сервере
docker pull myregistry.com/vpn:latest
docker-compose up -d
```

**Вариант 2: Через файл (для изолированных сред)**
```bash
# На сборочной машине
./scripts/docker-build.sh
docker save vpn:latest | gzip > vpn-$(date +%Y%m%d).tar.gz
# Размер архива: ~25-30MB

# Передача на production (выберите один способ):
scp vpn-*.tar.gz user@server:/tmp/
# или через USB/внешний носитель
# или через S3/облачное хранилище

# На production сервере
docker load < vpn-*.tar.gz
docker-compose up -d
```

**Вариант 3: Multi-arch сборка через Docker Hub**
```bash
# Сборка и публикация multi-arch образа
docker buildx build --platform linux/amd64,linux/arm64 \
  -t yourusername/vpn:latest --push .

# На любом сервере (автоматически выберет нужную архитектуру)
docker pull yourusername/vpn:latest
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

#### 5. Сборка из исходников

**Автоматическая установка Rust-версии (рекомендуется):**

```bash
# Клонировать репозиторий
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# Запустить скрипт установки (обнаружит и удалит конфликтующие версии)
./install.sh
```

**Сборка релиза из исходников:**

```bash
# Клонировать репозиторий
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# Создать готовый релиз
./build-release.sh

# Релиз будет создан в каталоге release/
ls -la release/
# vpn-release.tar.gz - готовый архив для распространения
# vpn-release.tar.gz.sha256 - контрольная сумма
```

**Ручная сборка:**

```bash
# Установить Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Клонировать и собрать
git clone https://github.com/ikeniborn/vpn.git
cd vpn
cargo build --release
sudo cp target/release/vpn /usr/local/bin/

# Проверить установку
vpn --version
```

**Важно:** Скрипт `install.sh` автоматически:
- Проверяет системные требования (Rust, Cargo)
- Обнаруживает существующие установки VPN (Python, других версий)
- Создает резервные копии в `/tmp/vpn-backup-*`
- Удаляет конфликтующие версии из PATH и виртуальных окружений
- Собирает и устанавливает Rust-версию
- Создает скрипт удаления `uninstall.sh`

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

Полная документация доступна в каталоге [docs/](docs/). 

### Основные разделы

- **[Быстрый старт](docs/guides/DOCKER.md)** - Установка и первые шаги
- **[Руководство по эксплуатации](docs/guides/OPERATIONS.md)** - Управление и обслуживание
- **[Безопасность](docs/guides/SECURITY.md)** - Настройка безопасности и best practices
- **[Оглавление документации](docs/README.md)** - Полный список документов

### По темам

- **Развертывание**: [Docker](docs/guides/DOCKER.md) | [Распространение образов](docs/guides/DOCKER_DISTRIBUTION.md)
- **Архитектура**: [Система](docs/architecture/system-architecture.md) | [Сеть](docs/architecture/network-topology.md) | [Компоненты](docs/architecture/crate-dependencies.md)
- **Оптимизация**: [Производительность](docs/guides/PERFORMANCE.md) | [Сборка](docs/BUILD_OPTIMIZATION.md)
- **Разработка**: [История изменений](docs/CHANGELOG.md) | [Спецификации](docs/specs/)

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