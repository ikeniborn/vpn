# Claude Code Hooks Configuration

Эта директория содержит конфигурацию и скрипты для Claude Code hooks в проекте VPN Management System.

## Структура файлов

- `settings.json` - Конфигурация hooks для Claude Code
- `task_parser.py` - Python скрипт для парсинга запросов пользователя
- `task_schema.json` - JSON Schema для валидации структурированного вывода
- `task_history.jsonl` - История проанализированных задач (создается автоматически)
- `prompts/` - Каталог с детальными логами всех промптов (JSON файлы с UUID именами)
- `audit.log` - Лог модификации файлов (создается автоматически)
- `bash_history.log` - История выполнения bash команд (создается автоматически)
- `git_operations.jsonl` - История git операций (создается автоматически)
- `git_config.json` - Конфигурация git posthook

## Как работает prehook

1. **UserPromptSubmit Hook**: Перехватывает запрос пользователя перед отправкой Claude
2. **Task Parser**: Анализирует запрос и извлекает структурированную информацию:
   - Генерирует уникальный UUID для каждого запроса
   - Тип задачи (create, update, fix, etc.)
   - Затронутые компоненты системы
   - Приоритет задачи
   - Упомянутые файлы
   - Ключевые слова
   - Оценка сложности
   - Рекомендуемые инструменты

3. **Enhanced Prompt**: Добавляет анализ задачи к оригинальному запросу, включая request_id

4. **Логирование**: 
   - Сохраняет краткую информацию в `task_history.jsonl`
   - Сохраняет полную структуру промпта в `prompts/{request_id}.json`

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

## Работа с сохраненными промптами

Каждый промпт сохраняется в отдельный файл с уникальным идентификатором:

```bash
# Список всех сохраненных промптов
ls -la .claude/prompts/

# Просмотр конкретного промпта по ID
cat .claude/prompts/{request_id}.json | jq .

# Поиск промптов по типу задачи
grep -l '"task_type": "create"' .claude/prompts/*.json

# Найти все промпты за последний час
find .claude/prompts -name "*.json" -mmin -60 | xargs jq -r '.request_id + " - " + .original_prompt'

# Статистика по компонентам
jq -r '.task_analysis.components[]' .claude/prompts/*.json | sort | uniq -c | sort -nr
```

## Дополнительные hooks

### PreToolUse Hook
Логирует все модификации файлов для аудита.

### PostToolUse Hook
- Сохраняет историю выполнения bash команд с кодами возврата
- **Git Auto-commit**: Автоматически создает коммиты после модификации файлов

### Stop Hook
Автоматически коммитит все незакоммиченные изменения при завершении работы Claude.

## Git PostHook для автоматического коммита и пуша

### Описание
Git posthook автоматически создает коммиты и опционально пушит изменения в репозиторий после выполнения задач.

### Возможности
- Автоматическое создание коммитов после модификации файлов
- Интеллектуальная генерация сообщений коммитов на основе контекста задачи
- Настраиваемый порог изменений для автокоммита
- Опциональный автопуш (по умолчанию отключен)
- Исключение файлов по паттернам
- Логирование всех git операций

### Настройка

#### Управление конфигурацией
```bash
# Показать текущие настройки
.claude/git_config.py show

# Включить/выключить автопуш
.claude/git_config.py toggle auto_push.enabled

# Изменить порог автокоммита
.claude/git_config.py set auto_commit.threshold 5

# Сбросить настройки
.claude/git_config.py reset
```

#### Структура конфигурации
Настройки хранятся в `.claude/git_config.json`:

```json
{
  "enabled": true,
  "auto_commit": {
    "enabled": true,
    "threshold": 3,
    "exclude_patterns": ["*.log", "*.tmp"],
    "commit_on_stop": true,
    "commit_on_important_tools": true
  },
  "auto_push": {
    "enabled": false,
    "branch_whitelist": ["main", "master", "develop"],
    "require_clean_working_tree": true
  }
}
```

### Как работает

1. **После модификации файлов** (Write/Edit/MultiEdit):
   - Проверяет количество изменений
   - Если превышен порог, создает коммит
   - Генерирует сообщение на основе анализа задачи

2. **При завершении работы** (Stop hook):
   - Коммитит все незакоммиченные изменения
   - Использует контекст последней задачи

3. **Генерация сообщений коммитов**:
   - Использует conventional commits формат
   - Анализирует тип задачи из task_parser
   - Включает статистику изменений
   - Добавляет co-authorship с Claude

### Примеры сгенерированных коммитов

```
feat: Add new functionality to users, network
- Added 3 new file(s)
- Modified 5 file(s)

🤖 Auto-committed by Claude Code posthook

Co-Authored-By: Claude <noreply@anthropic.com>
```

```
fix: Resolve issues in proxy, docker
- Modified 2 file(s)

🤖 Auto-committed by Claude Code posthook

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Отключение автокоммита

Для временного отключения:
```bash
.claude/git_config.py toggle enabled
```

Для отключения только автопуша:
```bash
.claude/git_config.py toggle auto_push.enabled
```

### Просмотр истории операций

```bash
# История git операций
tail -20 .claude/git_operations.jsonl | jq .

# Успешные коммиты
grep '"success": true' .claude/git_operations.jsonl | jq .
```

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