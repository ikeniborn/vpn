# Claude Code Hooks Configuration

Эта директория содержит конфигурацию и скрипты для Claude Code hooks в проекте VPN Management System.

## Структура файлов

- `settings.json` - Конфигурация hooks для Claude Code
- `task_parser.py` - Python скрипт для парсинга запросов пользователя
- `task_schema.json` - JSON Schema для валидации структурированного вывода
- `task_history.jsonl` - История проанализированных задач (создается автоматически)
- `audit.log` - Лог модификации файлов (создается автоматически)
- `bash_history.log` - История выполнения bash команд (создается автоматически)

## Как работает prehook

1. **UserPromptSubmit Hook**: Перехватывает запрос пользователя перед отправкой Claude
2. **Task Parser**: Анализирует запрос и извлекает структурированную информацию:
   - Тип задачи (create, update, fix, etc.)
   - Затронутые компоненты системы
   - Приоритет задачи
   - Упомянутые файлы
   - Ключевые слова
   - Оценка сложности
   - Рекомендуемые инструменты

3. **Enhanced Prompt**: Добавляет анализ задачи к оригинальному запросу

## Примеры работы

### Пример 1: Создание новой функции
```
Запрос: "Создай новую функцию для валидации пользовательских данных в vpn-users"

Анализ:
{
  "task_type": "create",
  "components": ["users"],
  "priority": "medium",
  "estimated_complexity": "medium",
  "suggested_tools": ["Write", "Edit", "Task"]
}
```

### Пример 2: Исправление ошибки
```
Запрос: "Срочно исправь ошибку в proxy_installer.rs при установке Docker контейнеров"

Анализ:
{
  "task_type": "fix",
  "components": ["server", "docker"],
  "priority": "high",
  "files": ["proxy_installer.rs"],
  "estimated_complexity": "high",
  "suggested_tools": ["Read", "Edit", "Bash"]
}
```

### Пример 3: Рефакторинг
```
Запрос: "Проведи рефакторинг модуля vpn-network для улучшения производительности"

Анализ:
{
  "task_type": "refactor",
  "components": ["network"],
  "priority": "medium",
  "estimated_complexity": "high",
  "suggested_tools": ["Read", "Edit", "MultiEdit", "Grep"]
}
```

## Тестирование prehook

Для тестирования парсера можно использовать следующую команду:

```bash
echo '{"prompt": "Создай новый модуль для работы с метриками"}' | python3 .claude/task_parser.py | jq .
```

## Просмотр истории задач

История всех проанализированных задач сохраняется в `task_history.jsonl`:

```bash
# Последние 5 задач
tail -5 .claude/task_history.jsonl | jq .

# Задачи с высоким приоритетом
grep '"priority": "high"' .claude/task_history.jsonl | jq .

# Статистика по типам задач
jq -r '.task_type' .claude/task_history.jsonl | sort | uniq -c
```

## Дополнительные hooks

### PreToolUse Hook
Логирует все модификации файлов для аудита.

### PostToolUse Hook
Сохраняет историю выполнения bash команд с кодами возврата.

## Отключение hooks

Для временного отключения hooks можно переименовать файл `settings.json`:

```bash
mv .claude/settings.json .claude/settings.json.disabled
```

## Разработка новых hooks

При создании новых hooks следуйте принципам:

1. Hooks должны быть быстрыми (< 1 секунды)
2. При ошибке hook не должен блокировать работу Claude Code
3. Используйте exit code 0 для успеха
4. Логируйте важные события для отладки
5. Проверяйте входные данные на корректность