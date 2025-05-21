#!/bin/bash

# Тест правильности команды запуска Xray в Docker

echo "=== Тест команды запуска Xray в Docker ==="

# Проверяем доступность образа
echo "1. Проверка доступности образа teddysun/xray:latest..."
if docker pull teddysun/xray:latest >/dev/null 2>&1; then
    echo "✅ Образ успешно загружен"
else
    echo "❌ Не удалось загрузить образ"
    exit 1
fi

# Проверяем правильность команды запуска
echo ""
echo "2. Проверка команды запуска xray..."
if docker run --rm teddysun/xray:latest xray version >/dev/null 2>&1; then
    echo "✅ Команда 'xray' работает в контейнере"
    docker run --rm teddysun/xray:latest xray version
else
    echo "❌ Команда 'xray' не работает в контейнере"
fi

# Проверяем альтернативные команды
echo ""
echo "3. Проверка альтернативных команд..."

# Тестируем команду run без аргументов
if docker run --rm teddysun/xray:latest xray run --help >/dev/null 2>&1; then
    echo "✅ Команда 'xray run' доступна"
else
    echo "❌ Команда 'xray run' недоступна"
fi

# Проверяем что происходит если запустить без конфига
echo ""
echo "4. Тест запуска без конфигурации (должен показать ошибку):"
docker run --rm teddysun/xray:latest xray run 2>&1 | head -3

echo ""
echo "=== Тест завершен ==="