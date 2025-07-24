#!/usr/bin/env python3
"""
Git Configuration Helper for Claude Code PostHook
Помогает настроить параметры автокоммита
"""

import json
import os
import sys


class GitConfigHelper:
    """Управление настройками git posthook"""
    
    def __init__(self):
        self.config_file = os.path.join(os.path.dirname(__file__), 'git_config.json')
        self.default_config = {
            'enabled': True,
            'auto_commit': {
                'enabled': True,
                'threshold': 3,  # Минимум изменений для автокоммита
                'exclude_patterns': [
                    '*.log',
                    '*.tmp',
                    '.DS_Store',
                    '__pycache__/',
                    'node_modules/',
                    'target/debug/',
                    'target/release/'
                ],
                'commit_on_stop': True,  # Коммитить при завершении сессии
                'commit_on_important_tools': True  # Коммитить после Write/Edit
            },
            'auto_push': {
                'enabled': False,  # По умолчанию отключен
                'branch_whitelist': ['main', 'master', 'develop'],
                'require_clean_working_tree': True
            },
            'commit_message': {
                'include_task_info': True,
                'include_file_stats': True,
                'conventional_commits': True,
                'max_length': 72
            },
            'notifications': {
                'on_commit': True,
                'on_push': True,
                'on_error': True
            }
        }
    
    def load_config(self):
        """Загружает конфигурацию или создает новую"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    return json.load(f)
            except:
                pass
        
        # Создаем конфигурацию по умолчанию
        self.save_config(self.default_config)
        return self.default_config
    
    def save_config(self, config):
        """Сохраняет конфигурацию"""
        with open(self.config_file, 'w') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
    
    def toggle_feature(self, feature_path: str):
        """Переключает булево значение по указанному пути"""
        config = self.load_config()
        
        # Навигация по пути
        parts = feature_path.split('.')
        current = config
        
        for part in parts[:-1]:
            if part in current:
                current = current[part]
            else:
                print(f"Error: Path '{feature_path}' not found")
                return
        
        last_part = parts[-1]
        if last_part in current and isinstance(current[last_part], bool):
            current[last_part] = not current[last_part]
            self.save_config(config)
            print(f"✓ {feature_path} = {current[last_part]}")
        else:
            print(f"Error: '{feature_path}' is not a boolean setting")
    
    def set_value(self, setting_path: str, value: any):
        """Устанавливает значение настройки"""
        config = self.load_config()
        
        # Навигация по пути
        parts = setting_path.split('.')
        current = config
        
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]
        
        # Преобразование типов
        if value.isdigit():
            value = int(value)
        elif value.lower() in ['true', 'false']:
            value = value.lower() == 'true'
        
        current[parts[-1]] = value
        self.save_config(config)
        print(f"✓ {setting_path} = {value}")
    
    def show_config(self):
        """Показывает текущую конфигурацию"""
        config = self.load_config()
        print(json.dumps(config, indent=2, ensure_ascii=False))
    
    def reset_config(self):
        """Сбрасывает конфигурацию к значениям по умолчанию"""
        self.save_config(self.default_config)
        print("✓ Configuration reset to defaults")


def main():
    """CLI интерфейс для управления настройками"""
    helper = GitConfigHelper()
    
    if len(sys.argv) < 2:
        print("Git PostHook Configuration")
        print("\nUsage:")
        print("  git_config.py show                      - Show current config")
        print("  git_config.py toggle <path>             - Toggle boolean setting")
        print("  git_config.py set <path> <value>        - Set value")
        print("  git_config.py reset                     - Reset to defaults")
        print("\nExamples:")
        print("  git_config.py toggle auto_push.enabled")
        print("  git_config.py set auto_commit.threshold 5")
        print("  git_config.py show")
        return
    
    command = sys.argv[1]
    
    if command == 'show':
        helper.show_config()
    elif command == 'toggle' and len(sys.argv) >= 3:
        helper.toggle_feature(sys.argv[2])
    elif command == 'set' and len(sys.argv) >= 4:
        helper.set_value(sys.argv[2], sys.argv[3])
    elif command == 'reset':
        helper.reset_config()
    else:
        print(f"Unknown command: {command}")


if __name__ == '__main__':
    main()