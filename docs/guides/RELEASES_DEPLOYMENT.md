# Развертывание через GitHub Releases

Это руководство описывает установку и развертывание VPN Manager с использованием предсобранных бинарных файлов из GitHub Releases.

## Преимущества GitHub Releases

- **Быстрое развертывание**: предсобранные оптимизированные бинарные файлы
- **Безопасность**: каждый релиз подписан и имеет контрольные суммы SHA256
- **Мультиплатформенность**: поддержка Linux, macOS, Windows и различных архитектур
- **Автоматическое управление версиями**: семантическое версионирование с автоматическими релизами
- **Простота автоматизации**: легко интегрируется в CI/CD пайплайны

## Системы автоматического управления версиями

### Создание релизов

#### Автоматические релизы через теги
```bash
# Создание тега для автоматического релиза
git tag v1.2.3
git push origin v1.2.3
```

#### Ручные релизы через GitHub Actions
```bash
# Через веб-интерфейс GitHub:
# Actions → Release → Run workflow → выбрать тип версии (patch/minor/major)
```

#### Программное создание релизов
```bash
# Использование GitHub CLI
gh workflow run release.yml -f version_type=minor

# Прямое создание тега с автоматическим релизом
git tag v$(cargo metadata --no-deps --format-version 1 | jq -r '.packages[0].version')
git push origin --tags
```

### Типы версий

- **patch** (1.2.3 → 1.2.4): исправления ошибок, совместимые изменения
- **minor** (1.2.3 → 1.3.0): новые функции, обратная совместимость
- **major** (1.2.3 → 2.0.0): breaking changes, несовместимые изменения

## Установка на различные системы

### Linux серверы

#### Ubuntu/Debian
```bash
# Автоматическая установка
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | sudo bash

# Ручная установка
wget https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-unknown-linux-gnu.tar.gz
wget https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-unknown-linux-gnu.tar.gz.sha256
sha256sum -c vpn-x86_64-unknown-linux-gnu.tar.gz.sha256
tar -xzf vpn-x86_64-unknown-linux-gnu.tar.gz
sudo cp vpn /usr/local/bin/
```

#### CentOS/RHEL/Fedora
```bash
# Автоматическая установка
curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | sudo bash

# Ручная установка
wget https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-unknown-linux-gnu.tar.gz
sudo tar -xzf vpn-x86_64-unknown-linux-gnu.tar.gz -C /usr/local/bin/
sudo chmod +x /usr/local/bin/vpn
```

#### Alpine Linux
```bash
# Использовать musl версию для Alpine
wget https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-unknown-linux-musl.tar.gz
tar -xzf vpn-x86_64-unknown-linux-musl.tar.gz
sudo cp vpn /usr/local/bin/
```

### ARM-based системы

#### Raspberry Pi 4+ (ARM64)
```bash
wget https://github.com/ikeniborn/vpn/releases/latest/download/vpn-aarch64-unknown-linux-gnu.tar.gz
tar -xzf vpn-aarch64-unknown-linux-gnu.tar.gz
sudo cp vpn /usr/local/bin/
```

#### Raspberry Pi 3 (ARMv7)
```bash
wget https://github.com/ikeniborn/vpn/releases/latest/download/vpn-armv7-unknown-linux-gnueabihf.tar.gz
tar -xzf vpn-armv7-unknown-linux-gnueabihf.tar.gz
sudo cp vpn /usr/local/bin/
```

### macOS

#### Intel Macs
```bash
curl -L https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-apple-darwin.tar.gz -o vpn.tar.gz
tar -xzf vpn.tar.gz
sudo cp vpn /usr/local/bin/
```

#### Apple Silicon Macs
```bash
curl -L https://github.com/ikeniborn/vpn/releases/latest/download/vpn-aarch64-apple-darwin.tar.gz -o vpn.tar.gz
tar -xzf vpn.tar.gz
sudo cp vpn /usr/local/bin/
```

### Windows

#### PowerShell
```powershell
# Скачать и распаковать
Invoke-WebRequest -Uri "https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-pc-windows-msvc.zip" -OutFile "vpn.zip"
Expand-Archive -Path "vpn.zip" -DestinationPath "C:\Program Files\VPN"

# Добавить в PATH
$env:PATH += ";C:\Program Files\VPN"
```

## Docker развертывание

### Использование GitHub Container Registry

```bash
# Скачать образ
docker pull ghcr.io/ikeniborn/vpn:latest

# Запустить контейнер
docker run -d --name vpn-manager \
  -p 8443:8443 \
  -p 8080:8080 \
  -v /opt/vpn:/data \
  ghcr.io/ikeniborn/vpn:latest

# С Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  vpn:
    image: ghcr.io/ikeniborn/vpn:latest
    ports:
      - "8443:8443"
      - "8080:8080"
    volumes:
      - vpn_data:/data
    restart: unless-stopped
    environment:
      - VPN_CONFIG_PATH=/data/config.toml
      
volumes:
  vpn_data:
EOF

docker-compose up -d
```

### Мультиархитектурные образы

```bash
# Образы автоматически выбирают правильную архитектуру
docker pull ghcr.io/ikeniborn/vpn:latest  # Работает на x86_64, ARM64, ARMv7

# Принудительно выбрать архитектуру
docker pull --platform linux/amd64 ghcr.io/ikeniborn/vpn:latest
docker pull --platform linux/arm64 ghcr.io/ikeniborn/vpn:latest
docker pull --platform linux/arm/v7 ghcr.io/ikeniborn/vpn:latest
```

## CI/CD интеграция

### GitHub Actions

```yaml
name: Deploy VPN
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'VPN version to deploy'
        required: true
        default: 'latest'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - name: Deploy to server
      run: |
        ssh ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }} \
          "curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | sudo bash -s -- --version ${{ github.event.inputs.version }}"
```

### GitLab CI

```yaml
deploy_vpn:
  stage: deploy
  script:
    - |
      ssh $SERVER_USER@$SERVER_HOST \
        "curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | sudo bash -s -- --version $VERSION"
  variables:
    VERSION: "latest"
  when: manual
```

### Ansible

```yaml
---
- name: Deploy VPN Manager
  hosts: vpn_servers
  become: yes
  tasks:
    - name: Download and install VPN
      shell: |
        curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | bash -s -- --version {{ vpn_version | default('latest') }}
      args:
        creates: /usr/local/bin/vpn
```

## Автоматизация обновлений

### Systemd timer для автоматических обновлений

```bash
# Создать скрипт обновления
sudo tee /usr/local/bin/vpn-update.sh << 'EOF'
#!/bin/bash
CURRENT_VERSION=$(vpn --version | head -n1 | grep -oP 'v\d+\.\d+\.\d+')
LATEST_VERSION=$(curl -s https://api.github.com/repos/ikeniborn/vpn/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
    echo "Updating VPN from $CURRENT_VERSION to $LATEST_VERSION"
    curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | bash -s -- --version "$LATEST_VERSION" --force
    systemctl restart vpn-manager
    echo "VPN updated successfully"
else
    echo "VPN is already up to date ($CURRENT_VERSION)"
fi
EOF

sudo chmod +x /usr/local/bin/vpn-update.sh

# Создать systemd service
sudo tee /etc/systemd/system/vpn-update.service << 'EOF'
[Unit]
Description=Update VPN Manager
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vpn-update.sh
User=root
EOF

# Создать systemd timer
sudo tee /etc/systemd/system/vpn-update.timer << 'EOF'
[Unit]
Description=Update VPN Manager weekly
Requires=vpn-update.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Активировать timer
sudo systemctl daemon-reload
sudo systemctl enable vpn-update.timer
sudo systemctl start vpn-update.timer
```

### Cron для автоматических обновлений

```bash
# Добавить в crontab для еженедельной проверки обновлений
echo "0 2 * * 0 /usr/local/bin/vpn-update.sh" | sudo crontab -
```

## Мониторинг релизов

### Webhook уведомления

```bash
# Настроить webhook для уведомлений о новых релизах
# В GitHub: Settings → Webhooks → Add webhook
# Payload URL: https://your-server.com/webhook/vpn-release
# Content type: application/json
# Events: Releases

# Пример обработчика webhook (Python Flask)
from flask import Flask, request
import subprocess

app = Flask(__name__)

@app.route('/webhook/vpn-release', methods=['POST'])
def handle_release():
    data = request.json
    if data['action'] == 'published':
        version = data['release']['tag_name']
        # Автоматически обновить VPN на серверах
        subprocess.run([
            'ansible-playbook', 
            'update-vpn.yml', 
            '-e', f'vpn_version={version}'
        ])
    return 'OK'
```

### Проверка доступности новых версий

```bash
# Скрипт для проверки новых версий
#!/bin/bash
check_updates() {
    local current_version=$(vpn --version | head -n1 | grep -oP 'v\d+\.\d+\.\d+')
    local latest_version=$(curl -s https://api.github.com/repos/ikeniborn/vpn/releases/latest | jq -r '.tag_name')
    
    if [[ "$current_version" != "$latest_version" ]]; then
        echo "New version available: $latest_version (current: $current_version)"
        echo "Update with: curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | sudo bash -s -- --version $latest_version --force"
        return 1
    else
        echo "VPN is up to date: $current_version"
        return 0
    fi
}

check_updates
```

## Откат к предыдущей версии

### Быстрый откат

```bash
# Откат к конкретной версии
sudo curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | bash -s -- --version v1.1.0 --force

# Сохранение текущей версии перед обновлением
sudo cp /usr/local/bin/vpn /usr/local/bin/vpn.backup.$(date +%Y%m%d)
```

### Автоматический откат при ошибках

```bash
#!/bin/bash
# Скрипт безопасного обновления с автоматическим откатом

BACKUP_PATH="/usr/local/bin/vpn.backup"
NEW_VERSION="$1"

# Создать бекап
cp /usr/local/bin/vpn "$BACKUP_PATH"

# Обновить
if curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | bash -s -- --version "$NEW_VERSION" --force; then
    # Проверить работоспособность
    if vpn --version >/dev/null 2>&1; then
        echo "Update successful"
        rm "$BACKUP_PATH"
    else
        echo "Update failed, rolling back"
        cp "$BACKUP_PATH" /usr/local/bin/vpn
        systemctl restart vpn-manager
    fi
else
    echo "Installation failed, restoring backup"
    cp "$BACKUP_PATH" /usr/local/bin/vpn
fi
```

## Безопасность

### Проверка подписей

```bash
# Проверка контрольных сумм SHA256
wget https://github.com/ikeniborn/vpn/releases/download/v1.2.3/vpn-x86_64-unknown-linux-gnu.tar.gz.sha256
sha256sum -c vpn-x86_64-unknown-linux-gnu.tar.gz.sha256
```

### Безопасная загрузка

```bash
# Использование HTTPS и проверка сертификатов
curl -sSL --fail --cert-status https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-unknown-linux-gnu.tar.gz -o vpn.tar.gz

# Альтернативно с wget
wget --secure-protocol=TLSv1_2 --https-only https://github.com/ikeniborn/vpn/releases/latest/download/vpn-x86_64-unknown-linux-gnu.tar.gz
```

## Часто задаваемые вопросы

### Как узнать текущую установленную версию?
```bash
vpn --version
```

### Как получить список всех доступных версий?
```bash
curl -s https://api.github.com/repos/ikeniborn/vpn/releases | jq -r '.[].tag_name'
```

### Как установить бета-версию?
```bash
# Найти последний pre-release
BETA_VERSION=$(curl -s https://api.github.com/repos/ikeniborn/vpn/releases | jq -r '.[] | select(.prerelease==true) | .tag_name' | head -n1)
sudo curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | bash -s -- --version "$BETA_VERSION" --force
```

### Как настроить автоматические обновления только для patch-версий?
```bash
# Модифицировать скрипт обновления для проверки только patch-версий
#!/bin/bash
CURRENT_MAJOR_MINOR=$(vpn --version | grep -oP 'v\d+\.\d+')
LATEST_PATCH=$(curl -s https://api.github.com/repos/ikeniborn/vpn/releases | jq -r --arg prefix "$CURRENT_MAJOR_MINOR" '.[] | select(.tag_name | startswith($prefix)) | .tag_name' | head -n1)

if [[ "$LATEST_PATCH" ]]; then
    curl -sSL https://raw.githubusercontent.com/ikeniborn/vpn/master/scripts/install-remote.sh | bash -s -- --version "$LATEST_PATCH" --force
fi
```

## Заключение

GitHub Releases предоставляет надежную и масштабируемую платформу для развертывания VPN Manager. Автоматизированные релизы с семантическим версионированием упрощают управление обновлениями и обеспечивают стабильность производственных развертываний.

Для production-среды рекомендуется:
1. Использовать автоматические скрипты установки
2. Настроить мониторинг новых релизов
3. Реализовать стратегию отката
4. Тестировать обновления в staging-среде перед production