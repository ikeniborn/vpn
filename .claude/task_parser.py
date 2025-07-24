#!/usr/bin/env python3
"""
Task Parser Hook for Claude Code
Парсит запрос пользователя и формирует структурированное задание в формате JSON
"""

import json
import sys
import re
from datetime import datetime
from typing import Dict, List, Optional, Any


class TaskParser:
    """Парсер для извлечения структурированной информации из запроса пользователя"""
    
    def __init__(self):
        self.task_keywords = {
            'create': ['создать', 'создай', 'сделать', 'сделай', 'добавить', 'добавь', 'написать', 'напиши'],
            'update': ['обновить', 'обнови', 'изменить', 'измени', 'исправить', 'исправь', 'поправить', 'поправь'],
            'delete': ['удалить', 'удали', 'убрать', 'убери', 'очистить', 'очисти'],
            'analyze': ['проанализировать', 'проанализируй', 'изучить', 'изучи', 'проверить', 'проверь', 'посмотреть', 'посмотри'],
            'fix': ['исправить', 'исправь', 'починить', 'почини', 'решить', 'реши'],
            'refactor': ['рефакторинг', 'переписать', 'перепиши', 'оптимизировать', 'оптимизируй'],
            'test': ['протестировать', 'протестируй', 'тест', 'тестирование', 'проверка'],
            'deploy': ['задеплоить', 'деплой', 'развернуть', 'разверни', 'запустить', 'запусти'],
            'configure': ['настроить', 'настрой', 'сконфигурировать', 'конфигурация'],
            'document': ['документировать', 'документация', 'описать', 'опиши']
        }
        
        self.component_keywords = {
            'server': ['сервер', 'server', 'vpn-server'],
            'proxy': ['прокси', 'proxy', 'vpn-proxy'],
            'users': ['пользователь', 'users', 'vpn-users'],
            'network': ['сеть', 'network', 'vpn-network'],
            'docker': ['докер', 'docker', 'контейнер'],
            'config': ['конфиг', 'config', 'настройк'],
            'cli': ['cli', 'команд', 'интерфейс'],
            'identity': ['identity', 'auth', 'авториз'],
            'monitor': ['монитор', 'monitor', 'метрик']
        }
        
        self.priority_indicators = {
            'high': ['срочно', 'важно', 'критично', 'немедленно', 'asap', 'urgent'],
            'medium': ['желательно', 'нужно', 'необходимо'],
            'low': ['можно', 'потом', 'позже', 'когда-нибудь']
        }

    def extract_task_type(self, text: str) -> str:
        """Определяет тип задачи из текста"""
        text_lower = text.lower()
        
        for task_type, keywords in self.task_keywords.items():
            if any(keyword in text_lower for keyword in keywords):
                return task_type
        
        return 'general'

    def extract_components(self, text: str) -> List[str]:
        """Извлекает компоненты системы, затронутые в задаче"""
        text_lower = text.lower()
        components = []
        
        for component, keywords in self.component_keywords.items():
            if any(keyword in text_lower for keyword in keywords):
                components.append(component)
        
        return components if components else ['general']

    def extract_priority(self, text: str) -> str:
        """Определяет приоритет задачи"""
        text_lower = text.lower()
        
        for priority, indicators in self.priority_indicators.items():
            if any(indicator in text_lower for indicator in indicators):
                return priority
        
        return 'medium'

    def extract_files(self, text: str) -> List[str]:
        """Извлекает упомянутые файлы из текста"""
        # Паттерны для поиска файлов
        patterns = [
            r'[\w\-./]+\.rs',  # Rust файлы
            r'[\w\-./]+\.toml',  # TOML файлы
            r'[\w\-./]+\.json',  # JSON файлы
            r'[\w\-./]+\.md',  # Markdown файлы
            r'[\w\-./]+\.yml',  # YAML файлы
            r'[\w\-./]+\.yaml',  # YAML файлы
            r'[\w\-./]+\.sh',  # Shell скрипты
            r'[\w\-./]+\.py',  # Python файлы
        ]
        
        files = []
        for pattern in patterns:
            matches = re.findall(pattern, text)
            files.extend(matches)
        
        return list(set(files))  # Удаляем дубликаты

    def extract_keywords(self, text: str) -> List[str]:
        """Извлекает ключевые слова из текста"""
        # Удаляем стоп-слова
        stop_words = {
            'и', 'в', 'на', 'с', 'для', 'по', 'из', 'к', 'от', 'до', 'о', 'об',
            'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for'
        }
        
        words = re.findall(r'\b\w+\b', text.lower())
        keywords = [w for w in words if len(w) > 3 and w not in stop_words]
        
        # Подсчитываем частоту и возвращаем топ-10
        word_freq = {}
        for word in keywords:
            word_freq[word] = word_freq.get(word, 0) + 1
        
        sorted_keywords = sorted(word_freq.items(), key=lambda x: x[1], reverse=True)
        return [word for word, _ in sorted_keywords[:10]]

    def parse_task(self, prompt: str) -> Dict[str, Any]:
        """Основной метод парсинга задачи"""
        task = {
            'timestamp': datetime.now().isoformat(),
            'original_prompt': prompt,
            'task_type': self.extract_task_type(prompt),
            'components': self.extract_components(prompt),
            'priority': self.extract_priority(prompt),
            'files': self.extract_files(prompt),
            'keywords': self.extract_keywords(prompt),
            'estimated_complexity': self._estimate_complexity(prompt),
            'suggested_tools': self._suggest_tools(prompt),
            'metadata': {
                'prompt_length': len(prompt),
                'word_count': len(prompt.split()),
                'has_code_blocks': '```' in prompt,
                'has_urls': bool(re.search(r'https?://\S+', prompt)),
                'language': 'ru' if any(ord(c) > 127 for c in prompt) else 'en'
            }
        }
        
        return task

    def _estimate_complexity(self, prompt: str) -> str:
        """Оценивает сложность задачи"""
        word_count = len(prompt.split())
        component_count = len(self.extract_components(prompt))
        
        if word_count > 100 or component_count > 3:
            return 'high'
        elif word_count > 50 or component_count > 1:
            return 'medium'
        else:
            return 'low'

    def _suggest_tools(self, prompt: str) -> List[str]:
        """Предлагает инструменты для выполнения задачи"""
        prompt_lower = prompt.lower()
        tools = []
        
        tool_keywords = {
            'Read': ['прочитать', 'читать', 'посмотреть', 'изучить', 'read', 'view'],
            'Write': ['записать', 'создать файл', 'write', 'create file'],
            'Edit': ['изменить', 'редактировать', 'исправить', 'edit', 'modify'],
            'Bash': ['команда', 'запустить', 'выполнить', 'bash', 'run', 'execute'],
            'Grep': ['найти', 'поиск', 'искать', 'search', 'find', 'grep'],
            'Task': ['задача', 'план', 'task', 'plan'],
            'TodoWrite': ['todo', 'список', 'задачи', 'план']
        }
        
        for tool, keywords in tool_keywords.items():
            if any(keyword in prompt_lower for keyword in keywords):
                tools.append(tool)
        
        return tools if tools else ['Task']


def main():
    """Главная функция для обработки входящего prompt"""
    try:
        # Читаем входные данные
        input_data = json.loads(sys.stdin.read())
        
        # Извлекаем prompt
        prompt = input_data.get('prompt', '')
        
        # Парсим задачу
        parser = TaskParser()
        task_info = parser.parse_task(prompt)
        
        # Формируем расширенный prompt с контекстом
        enhanced_prompt = f"""
{prompt}

---
TASK ANALYSIS:
Type: {task_info['task_type']}
Components: {', '.join(task_info['components'])}
Priority: {task_info['priority']}
Complexity: {task_info['estimated_complexity']}
Suggested Tools: {', '.join(task_info['suggested_tools'])}
Keywords: {', '.join(task_info['keywords'][:5])}
"""
        
        # Сохраняем анализ в файл для истории
        history_file = '/home/ikeniborn/Documents/Project/vpn/.claude/task_history.jsonl'
        with open(history_file, 'a') as f:
            f.write(json.dumps(task_info, ensure_ascii=False) + '\n')
        
        # Возвращаем модифицированный prompt
        output = {
            'prompt': enhanced_prompt.strip(),
            'task_analysis': task_info
        }
        
        print(json.dumps(output, ensure_ascii=False))
        
    except Exception as e:
        # В случае ошибки просто передаем оригинальный prompt
        print(json.dumps({'prompt': input_data.get('prompt', '')}, ensure_ascii=False))
        sys.exit(0)


if __name__ == '__main__':
    main()