#!/bin/bash

# Тестовый скрипт для проверки работы task_parser.py

echo "=== Testing Task Parser Hook ==="
echo

# Тест 1: Создание функции
echo "Test 1: Create function request"
echo '{"prompt": "Создай новую функцию validate_user_input в модуле vpn-users/src/user.rs"}' | python3 task_parser.py | jq '.task_analysis'
echo

# Тест 2: Исправление ошибки
echo "Test 2: Fix bug request"
echo '{"prompt": "Срочно исправь ошибку в proxy_installer.rs при установке Docker контейнеров"}' | python3 task_parser.py | jq '.task_analysis'
echo

# Тест 3: Рефакторинг
echo "Test 3: Refactoring request"
echo '{"prompt": "Проведи рефакторинг модуля vpn-network для улучшения производительности"}' | python3 task_parser.py | jq '.task_analysis'
echo

# Тест 4: Анализ кода
echo "Test 4: Code analysis request"
echo '{"prompt": "Проанализируй использование памяти в vpn-server и найди утечки"}' | python3 task_parser.py | jq '.task_analysis'
echo

# Тест 5: Деплой
echo "Test 5: Deploy request"
echo '{"prompt": "Задеплой новую версию прокси сервера на production"}' | python3 task_parser.py | jq '.task_analysis'
echo

# Тест 6: Документация
echo "Test 6: Documentation request"
echo '{"prompt": "Напиши документацию для API модуля vpn-identity"}' | python3 task_parser.py | jq '.task_analysis'
echo

echo "=== Tests completed ==="