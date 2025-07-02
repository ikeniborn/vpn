# Docker Distribution Guide

Это руководство описывает различные способы распространения Docker образов VPN между машинами.

## Содержание

1. [Выбор метода распространения](#выбор-метода-распространения)
2. [Через Docker Registry](#через-docker-registry)
3. [Через файловую систему](#через-файловую-систему)
4. [Multi-arch сборки](#multi-arch-сборки)
5. [Автоматизация с CI/CD](#автоматизация-с-cicd)
6. [Безопасность](#безопасность)
7. [Оптимизация размера](#оптимизация-размера)

## Выбор метода распространения

| Метод | Когда использовать | Преимущества | Недостатки |
|-------|-------------------|--------------|------------|
| Docker Registry | Команды, CI/CD | Автоматизация, версионирование | Требует доступ к registry |
| Файловая передача | Изолированные сети | Работает offline | Ручной процесс |
| Docker Hub | Open source, публичные образы | Бесплатно, multi-arch | Публичный доступ |
| Private Registry | Корпоративные среды | Контроль, безопасность | Требует инфраструктуру |

## Через Docker Registry

### 1. Локальный Registry

```bash
# Запустить локальный registry
docker run -d -p 5000:5000 --name registry registry:2

# Сборка и тегирование
docker build -t localhost:5000/vpn:latest .
docker push localhost:5000/vpn:latest

# На другой машине в той же сети
docker pull localhost:5000/vpn:latest
```

### 2. Private Registry (Harbor, Nexus, GitLab)

```bash
# Настройка доступа
docker login registry.company.com

# Сборка с правильным тегом
docker build -t registry.company.com/vpn/server:v1.0.0 .

# Push с retry при необходимости
docker push registry.company.com/vpn/server:v1.0.0 || \
  (sleep 5 && docker push registry.company.com/vpn/server:v1.0.0)

# Pull на production
docker pull registry.company.com/vpn/server:v1.0.0
docker tag registry.company.com/vpn/server:v1.0.0 vpn:latest
```

### 3. Amazon ECR

```bash
# Аутентификация
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.us-east-1.amazonaws.com

# Push
docker tag vpn:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/vpn:latest
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/vpn:latest
```

## Через файловую систему

### 1. Базовый экспорт/импорт

```bash
# Экспорт одного образа
docker save vpn:latest -o vpn.tar
gzip vpn.tar  # Сжатие ~70%

# Экспорт нескольких образов
docker save vpn:latest vpn:v1.0.0 vpn:dev | gzip > vpn-bundle.tar.gz

# Импорт
gunzip -c vpn.tar.gz | docker load
```

### 2. Передача через SCP

```bash
# Прямая передача без сохранения на диск
docker save vpn:latest | gzip | ssh user@server 'gunzip | docker load'

# С progress bar
docker save vpn:latest | pv | gzip | ssh user@server 'gunzip | docker load'

# Batch передача
for server in server1 server2 server3; do
  docker save vpn:latest | gzip | ssh user@$server 'gunzip | docker load'
done
```

### 3. Через облачное хранилище

```bash
# AWS S3
docker save vpn:latest | gzip | aws s3 cp - s3://mybucket/vpn-latest.tar.gz
aws s3 cp s3://mybucket/vpn-latest.tar.gz - | gunzip | docker load

# Google Cloud Storage
docker save vpn:latest | gzip | gsutil cp - gs://mybucket/vpn-latest.tar.gz

# MinIO (self-hosted S3)
docker save vpn:latest | gzip | mc pipe myminio/images/vpn-latest.tar.gz
```

### 4. Через USB/внешний носитель

```bash
# Экспорт с проверкой целостности
docker save vpn:latest | gzip > /media/usb/vpn.tar.gz
sha256sum /media/usb/vpn.tar.gz > /media/usb/vpn.tar.gz.sha256

# На целевой машине
sha256sum -c /media/usb/vpn.tar.gz.sha256
docker load < /media/usb/vpn.tar.gz
```

## Multi-arch сборки

### 1. Подготовка buildx

```bash
# Создание builder для multi-arch
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# Проверка поддерживаемых платформ
docker buildx ls
```

### 2. Сборка multi-arch образа

```bash
# Локальная сборка для тестирования
docker buildx build --platform linux/amd64,linux/arm64 \
  -t vpn:multiarch --load .

# Push в registry
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 \
  -t myregistry/vpn:latest --push .
```

### 3. Экспорт multi-arch образов

```bash
# Экспорт всех архитектур
docker buildx build --platform linux/amd64,linux/arm64 \
  -t vpn:multiarch -o type=oci,dest=vpn-multiarch.tar .

# Распаковка на целевой машине
docker load < vpn-multiarch.tar
```

## Автоматизация с CI/CD

### GitHub Actions

```yaml
name: Build and Push
on:
  push:
    tags: ['v*']

jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
        
      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### GitLab CI

```yaml
docker-build:
  stage: build
  script:
    - docker buildx build --platform linux/amd64,linux/arm64
        --cache-from $CI_REGISTRY_IMAGE:cache
        --cache-to $CI_REGISTRY_IMAGE:cache
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
        -t $CI_REGISTRY_IMAGE:latest
        --push .
```

## Безопасность

### 1. Подпись образов

```bash
# Включить Docker Content Trust
export DOCKER_CONTENT_TRUST=1

# Создать ключи подписи
docker trust key generate mykey

# Push с подписью
docker trust sign myregistry/vpn:latest
```

### 2. Сканирование уязвимостей

```bash
# Trivy
trivy image vpn:latest

# Grype
grype vpn:latest

# Docker Scout
docker scout cves vpn:latest
```

### 3. Шифрование при передаче

```bash
# Шифрование файла
docker save vpn:latest | gzip | gpg -c > vpn.tar.gz.gpg

# Расшифровка
gpg -d vpn.tar.gz.gpg | gunzip | docker load
```

## Оптимизация размера

### 1. Сравнение размеров

```bash
# До оптимизации
docker images vpn --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# После оптимизации с нашими настройками
# Ожидаемые размеры:
# - Dev build: ~150MB
# - Release: ~25-30MB (со strip и LTO)
# - Сжатый tar.gz: ~10-15MB
```

### 2. Дополнительное сжатие

```bash
# Максимальное сжатие с xz (медленно, но эффективно)
docker save vpn:latest | xz -9 > vpn.tar.xz  # ~40% меньше чем gzip

# Быстрое сжатие с zstd
docker save vpn:latest | zstd -19 > vpn.tar.zst  # Быстрее и эффективнее
```

### 3. Дельта-обновления

```bash
# Создание патча между версиями
xdelta3 -e -s vpn-v1.0.0.tar vpn-v1.1.0.tar vpn-v1.0.0-to-v1.1.0.patch

# Применение патча
xdelta3 -d -s vpn-v1.0.0.tar vpn-v1.0.0-to-v1.1.0.patch vpn-v1.1.0.tar
```

## Скрипты автоматизации

### distribute.sh

```bash
#!/bin/bash
# Скрипт для автоматической дистрибуции

VERSION=${1:-latest}
REGISTRY=${2:-myregistry.com}
PLATFORMS="linux/amd64,linux/arm64"

echo "Building and distributing VPN $VERSION..."

# Multi-arch build and push
docker buildx build \
  --platform $PLATFORMS \
  -t $REGISTRY/vpn:$VERSION \
  -t $REGISTRY/vpn:latest \
  --push .

# Also save as file for offline distribution
docker save $REGISTRY/vpn:$VERSION | gzip > vpn-$VERSION.tar.gz
sha256sum vpn-$VERSION.tar.gz > vpn-$VERSION.tar.gz.sha256

echo "Distribution complete!"
echo "Registry: $REGISTRY/vpn:$VERSION"
echo "File: vpn-$VERSION.tar.gz"
```

## Troubleshooting

### Проблема: "no space left on device"
```bash
# Очистка старых образов
docker image prune -a

# Изменение директории Docker
systemctl stop docker
rsync -aqxP /var/lib/docker/ /new/path/docker
ln -s /new/path/docker /var/lib/docker
systemctl start docker
```

### Проблема: медленная передача
```bash
# Использование compression на SSH
scp -C vpn.tar.gz user@server:/tmp/

# Параллельная передача
split -b 100M vpn.tar.gz vpn.tar.gz.part
parallel -j 4 scp {} user@server:/tmp/ ::: vpn.tar.gz.part*
```

### Проблема: несовместимость архитектур
```bash
# Проверка архитектуры образа
docker image inspect vpn:latest | jq '.[0].Architecture'

# Принудительная загрузка нужной архитектуры
docker pull --platform linux/amd64 myregistry/vpn:latest
```