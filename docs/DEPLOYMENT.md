# VPN Server Deployment Guide

## Обзор улучшений стабильности

Обновленная версия VPN сервера включает следующие улучшения для повышения стабильности:

### 🛡️ Health Checks
- **Docker Health Checks**: Автоматическая проверка состояния контейнеров
- **Интервал проверки**: 30 секунд
- **Timeout**: 10 секунд
- **Количество попыток**: 3-5 (в зависимости от сервиса)

### 🔄 Политика перезапуска
- **unless-stopped**: Контейнеры перезапускаются автоматически, кроме случаев ручной остановки
- **Улучшенная обработка ошибок**: Graceful handling при сбоях

### 📊 Ограничения ресурсов
- **CPU лимиты**: 
  - Xray: 2 CPU, резерв 0.5 CPU
  - Watchtower: 0.5 CPU, резерв 0.1 CPU
  - Autoheal: 0.2 CPU, резерв 0.05 CPU
- **Memory лимиты**:
  - Xray: 2GB, резерв 512MB
  - Watchtower: 256MB, резерв 128MB
  - Autoheal: 128MB, резерв 64MB

### 🔍 VPN Watchdog Service
- **Мониторинг контейнеров**: Проверка состояния каждые 60 секунд
- **Автоматический перезапуск**: При обнаружении проблем
- **Cooldown период**: 5 минут между попытками перезапуска
- **Лимит попыток**: 3 попытки перед переходом в cooldown
- **Логирование**: Детальные логи в `/var/log/vpn-watchdog.log`

## Способы развертывания

### 1. Ручное развертывание

```bash
# Скачать проект
git clone <repository-url>
cd vpn

# Развернуть на сервере
sudo ./deploy.sh install

# Или обновить существующую установку
sudo ./deploy.sh update
```

### 2. CI/CD развертывание (GitHub Actions)

#### Настройка GitHub Secrets и Variables

**Secrets:**
```
SSH_PRIVATE_KEY = <ваш приватный SSH ключ>
```

**Variables:**
```
STAGING_SERVER_IP = <IP staging сервера>
STAGING_SERVER_USER = <пользователь для staging>
PRODUCTION_SERVER_IP = <IP production сервера>
PRODUCTION_SERVER_USER = <пользователь для production>
```

#### Запуск развертывания

1. **Автоматическое**: При push в ветку `main/master`
2. **Ручное**: Через GitHub Actions interface
   - Выберите действие: `install`, `update`, `backup`, `restart`
   - Выберите сервер: `staging` или `production`

### 3. Использование deploy.sh скрипта

```bash
# Показать справку
./deploy.sh --help

# Свежая установка
./deploy.sh install

# Обновление с бэкапом
./deploy.sh update

# Создать бэкап
./deploy.sh backup

# Восстановить из бэкапа
./deploy.sh restore

# Показать статус
./deploy.sh status

# Перезапустить сервисы
./deploy.sh restart

# Просмотр логов
./deploy.sh logs

# Установка без watchdog
./deploy.sh install --no-watchdog

# Использование пользовательских директорий
./deploy.sh install --dir=/custom/path --backup=/backup/path
```

## Структура файлов после развертывания

```
/opt/v2ray/
├── config/
│   ├── config.json              # Конфигурация Xray
│   ├── private_key.txt          # Reality приватный ключ
│   ├── public_key.txt           # Reality публичный ключ
│   ├── short_id.txt             # Reality short ID
│   ├── sni.txt                  # SNI домен
│   ├── protocol.txt             # Тип протокола
│   └── port.txt                 # Порт сервера
├── users/
│   ├── user1.json               # Конфигурация пользователя
│   ├── user1.link               # Ссылка подключения
│   └── user1.png                # QR код
├── logs/
│   ├── access.log               # Логи доступа
│   └── error.log                # Логи ошибок
├── docker-compose.yml           # Docker Compose конфигурация
├── docker-compose.override.yml  # Production настройки
├── install_vpn.sh               # Скрипт установки
├── manage_users.sh              # Скрипт управления
├── watchdog.sh                  # Watchdog скрипт
└── deploy.sh                    # Скрипт развертывания
```

## Системные службы

### VPN Watchdog Service
```bash
# Статус службы
sudo systemctl status vpn-watchdog

# Запуск службы
sudo systemctl start vpn-watchdog

# Остановка службы
sudo systemctl stop vpn-watchdog

# Просмотр логов
sudo journalctl -u vpn-watchdog -f

# Просмотр watchdog логов
sudo tail -f /var/log/vpn-watchdog.log
```

## Мониторинг и управление

### Через manage_users.sh
```bash
sudo v2ray-manage
```
Новый пункт меню **"12 🛡️ Управление Watchdog службой"** предоставляет:
- Запуск/остановка/перезапуск службы
- Просмотр статуса и логов
- Включение/выключение автозапуска
- Тестирование работы watchdog

### Через deploy.sh
```bash
# Проверка статуса всех сервисов
sudo ./deploy.sh status

# Просмотр логов
sudo ./deploy.sh logs

# Перезапуск при проблемах
sudo ./deploy.sh restart
```

## Автоматическое восстановление

### Docker Autoheal
- Контейнер `autoheal` автоматически перезапускает нездоровые контейнеры
- Работает на основе Docker health checks
- Проверка каждые 30 секунд

### VPN Watchdog
- Мониторит контейнеры Xray, Shadowbox, Watchtower
- Перезапускает при сбоях с умным cooldown
- Очистка ресурсов и ротация логов
- Проверка системных ресурсов

### Watchtower
- Автоматическое обновление Docker образов
- Проверка обновлений каждый час
- Автоматическая очистка старых образов

## Troubleshooting

### Проверка состояния контейнеров
```bash
# Статус всех контейнеров
docker ps -a

# Логи конкретного контейнера
docker logs xray
docker logs shadowbox
docker logs watchtower

# Health check статус
docker inspect xray | grep -A 5 Health
```

### Проверка watchdog
```bash
# Статус службы
sudo systemctl status vpn-watchdog

# Последние действия
sudo grep -E "restart|check|monitor" /var/log/vpn-watchdog.log | tail -10

# Ручная проверка
sudo /usr/local/bin/vpn-watchdog.sh
```

### Восстановление после сбоя
```bash
# Автоматическое восстановление
sudo ./deploy.sh restart

# Восстановление из бэкапа
sudo ./deploy.sh restore

# Полная переустановка
sudo ./deploy.sh backup
sudo ./deploy.sh install
```

## Логирование

### Основные логи
- **Xray access**: `/opt/v2ray/logs/access.log`
- **Xray error**: `/opt/v2ray/logs/error.log`
- **Watchdog**: `/var/log/vpn-watchdog.log`
- **System**: `journalctl -u vpn-watchdog`

### Ротация логов
- **Docker logs**: Автоматическая ротация (10MB, 3-5 файлов)
- **Watchdog logs**: Автоматическая ротация при превышении 10MB
- **Xray logs**: Управляется через меню `v2ray-manage`

## Безопасность

### Systemd Security
- **PrivateTmp**: Изолированная временная директория
- **NoNewPrivileges**: Запрет повышения привилегий
- **ProtectSystem**: Защита системных каталогов
- **ProtectHome**: Защита домашних каталогов

### Docker Security
- **Resource limits**: Ограничение CPU и памяти
- **Restart policies**: Контролируемый перезапуск
- **Network isolation**: Изолированные сети
- **Read-only paths**: Ограничение записи