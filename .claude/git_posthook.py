#!/usr/bin/env python3
"""
Git PostHook for Claude Code
Автоматически создает коммит и пушит изменения после выполнения задач
"""

import json
import sys
import subprocess
import os
from datetime import datetime
from typing import Dict, List, Tuple, Optional


class GitPostHook:
    """Обработчик для автоматического коммита и пуша изменений"""
    
    def __init__(self):
        self.repo_path = "/home/ikeniborn/Documents/Project/vpn"
        self.task_history_file = os.path.join(self.repo_path, ".claude/task_history.jsonl")
        self.config_file = os.path.join(self.repo_path, ".claude/git_config.json")
        self.config = self.load_config()
        self.commit_threshold = self.config.get('auto_commit', {}).get('threshold', 3)
    
    def load_config(self) -> Dict:
        """Загружает конфигурацию из файла"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    return json.load(f)
        except Exception:
            pass
        return {}
        
    def run_git_command(self, command: List[str]) -> Tuple[int, str, str]:
        """Выполняет git команду и возвращает результат"""
        try:
            result = subprocess.run(
                command,
                cwd=self.repo_path,
                capture_output=True,
                text=True
            )
            return result.returncode, result.stdout, result.stderr
        except Exception as e:
            return 1, "", str(e)
    
    def get_git_status(self) -> Dict[str, List[str]]:
        """Получает текущий статус репозитория"""
        status = {
            'modified': [],
            'added': [],
            'deleted': [],
            'untracked': []
        }
        
        returncode, stdout, _ = self.run_git_command(['git', 'status', '--porcelain'])
        
        if returncode == 0:
            for line in stdout.strip().split('\n'):
                if not line:
                    continue
                    
                status_code = line[:2]
                file_path = line[3:]
                
                if status_code[0] == 'M' or status_code[1] == 'M':
                    status['modified'].append(file_path)
                elif status_code[0] == 'A':
                    status['added'].append(file_path)
                elif status_code[0] == 'D':
                    status['deleted'].append(file_path)
                elif status_code == '??':
                    status['untracked'].append(file_path)
        
        return status
    
    def get_recent_task_info(self) -> Optional[Dict]:
        """Получает информацию о последней выполненной задаче"""
        try:
            if os.path.exists(self.task_history_file):
                with open(self.task_history_file, 'r') as f:
                    lines = f.readlines()
                    if lines:
                        return json.loads(lines[-1])
        except Exception:
            pass
        return None
    
    def generate_commit_message(self, event_type: str, tool_info: Dict, git_status: Dict) -> str:
        """Генерирует сообщение коммита на основе контекста"""
        # Получаем информацию о последней задаче
        task_info = self.get_recent_task_info()
        
        # Определяем тип изменений
        change_types = []
        if git_status['added']:
            change_types.append('feat')
        elif git_status['modified']:
            if any('fix' in f or 'bug' in f for f in git_status['modified']):
                change_types.append('fix')
            elif any('test' in f for f in git_status['modified']):
                change_types.append('test')
            elif any('doc' in f or 'README' in f or 'CHANGELOG' in f for f in git_status['modified']):
                change_types.append('docs')
            else:
                change_types.append('refactor')
        
        commit_type = change_types[0] if change_types else 'chore'
        
        # Формируем основное сообщение
        if task_info:
            task_type = task_info.get('task_type', 'general')
            components = task_info.get('components', ['general'])
            
            if task_type == 'create':
                message = f"{commit_type}: Add new functionality to {', '.join(components)}"
            elif task_type == 'update':
                message = f"{commit_type}: Update {', '.join(components)} components"
            elif task_type == 'fix':
                message = f"fix: Resolve issues in {', '.join(components)}"
            elif task_type == 'refactor':
                message = f"refactor: Improve {', '.join(components)} implementation"
            elif task_type == 'test':
                message = f"test: Add tests for {', '.join(components)}"
            elif task_type == 'document':
                message = f"docs: Update documentation for {', '.join(components)}"
            else:
                message = f"{commit_type}: Update {', '.join(components)}"
        else:
            # Базовое сообщение на основе измененных файлов
            affected_dirs = set()
            for files in git_status.values():
                for f in files:
                    if '/' in f:
                        affected_dirs.add(f.split('/')[0])
            
            if affected_dirs:
                message = f"{commit_type}: Update {', '.join(list(affected_dirs)[:3])}"
            else:
                message = f"{commit_type}: Update project files"
        
        # Добавляем детали
        details = []
        if git_status['added']:
            details.append(f"- Added {len(git_status['added'])} new file(s)")
        if git_status['modified']:
            details.append(f"- Modified {len(git_status['modified'])} file(s)")
        if git_status['deleted']:
            details.append(f"- Removed {len(git_status['deleted'])} file(s)")
        
        # Формируем полное сообщение
        full_message = message
        if details:
            full_message += "\n\n" + "\n".join(details)
        
        # Добавляем метаинформацию
        full_message += "\n\n🤖 Auto-committed by Claude Code posthook"
        full_message += "\n\nCo-Authored-By: Claude <noreply@anthropic.com>"
        
        return full_message
    
    def should_commit(self, event_type: str, tool_info: Dict) -> bool:
        """Определяет, нужно ли делать коммит"""
        # Проверяем, включен ли автокоммит
        if not self.config.get('enabled', True):
            return False
        
        if not self.config.get('auto_commit', {}).get('enabled', True):
            return False
        
        # Не коммитим после чтения файлов или поиска
        if event_type == 'PostToolUse' and tool_info.get('tool_name') in ['Read', 'Grep', 'Glob', 'LS']:
            return False
        
        # Проверяем статус репозитория
        git_status = self.get_git_status()
        total_changes = sum(len(files) for files in git_status.values())
        
        # Коммитим если есть достаточно изменений
        if total_changes >= self.commit_threshold:
            return True
        
        # Коммитим после важных операций
        if event_type == 'Stop' and total_changes > 0 and self.config.get('auto_commit', {}).get('commit_on_stop', True):
            return True
        
        # Коммитим после модификации файлов
        if event_type == 'PostToolUse' and tool_info.get('tool_name') in ['Write', 'Edit', 'MultiEdit'] and self.config.get('auto_commit', {}).get('commit_on_important_tools', True):
            return True
        
        return False
    
    def perform_commit_and_push(self, commit_message: str) -> Dict[str, any]:
        """Выполняет коммит и пуш"""
        result = {
            'success': False,
            'commit_sha': None,
            'push_result': None,
            'error': None
        }
        
        try:
            # Добавляем все изменения
            returncode, _, stderr = self.run_git_command(['git', 'add', '-A'])
            if returncode != 0:
                result['error'] = f"Failed to add files: {stderr}"
                return result
            
            # Создаем коммит
            returncode, stdout, stderr = self.run_git_command(['git', 'commit', '-m', commit_message])
            if returncode != 0:
                if "nothing to commit" in stderr or "nothing to commit" in stdout:
                    result['error'] = "Nothing to commit"
                else:
                    result['error'] = f"Failed to commit: {stderr}"
                return result
            
            # Получаем SHA коммита
            returncode, stdout, _ = self.run_git_command(['git', 'rev-parse', 'HEAD'])
            if returncode == 0:
                result['commit_sha'] = stdout.strip()[:7]
            
            # Пушим изменения если включен автопуш
            if self.config.get('auto_push', {}).get('enabled', False):
                # Проверяем текущую ветку
                returncode, stdout, _ = self.run_git_command(['git', 'branch', '--show-current'])
                if returncode == 0:
                    current_branch = stdout.strip()
                    whitelist = self.config.get('auto_push', {}).get('branch_whitelist', [])
                    
                    if not whitelist or current_branch in whitelist:
                        returncode, stdout, stderr = self.run_git_command(['git', 'push'])
                        if returncode == 0:
                            result['push_result'] = 'pushed'
                            result['success'] = True
                        else:
                            # Если не удалось запушить, коммит все равно создан
                            result['push_result'] = 'commit_only'
                            result['error'] = f"Push failed: {stderr}"
                            result['success'] = True  # Частичный успех
                    else:
                        result['push_result'] = 'commit_only'
                        result['error'] = f"Branch '{current_branch}' not in whitelist"
                        result['success'] = True
                else:
                    result['push_result'] = 'commit_only'
                    result['success'] = True
            else:
                result['push_result'] = 'commit_only'
                result['success'] = True
            
            return result
            
        except Exception as e:
            result['error'] = str(e)
            return result
    
    def process_hook(self, event_type: str, event_data: Dict) -> Dict[str, any]:
        """Основной метод обработки хука"""
        # Извлекаем информацию о событии
        tool_info = {
            'tool_name': event_data.get('tool_name', ''),
            'exit_code': event_data.get('exit_code', 0)
        }
        
        # Проверяем, нужно ли делать коммит
        if not self.should_commit(event_type, tool_info):
            return {
                'action': 'skip',
                'reason': 'Not enough changes or non-modifying operation'
            }
        
        # Получаем статус git
        git_status = self.get_git_status()
        
        # Генерируем сообщение коммита
        commit_message = self.generate_commit_message(event_type, tool_info, git_status)
        
        # Выполняем коммит и пуш
        result = self.perform_commit_and_push(commit_message)
        
        # Логируем результат
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'event_type': event_type,
            'tool_info': tool_info,
            'git_status': git_status,
            'commit_result': result
        }
        
        log_file = os.path.join(self.repo_path, '.claude/git_operations.jsonl')
        with open(log_file, 'a') as f:
            f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
        
        return result


def main():
    """Главная функция для обработки входящего события"""
    try:
        # Читаем входные данные
        input_data = json.loads(sys.stdin.read())
        
        # Определяем тип события
        event_type = input_data.get('event_type', 'PostToolUse')
        
        # Создаем и запускаем обработчик
        hook = GitPostHook()
        result = hook.process_hook(event_type, input_data)
        
        # Возвращаем результат
        print(json.dumps(result, ensure_ascii=False))
        
    except Exception as e:
        # В случае ошибки не блокируем работу Claude
        print(json.dumps({'error': str(e), 'action': 'skip'}, ensure_ascii=False))
        sys.exit(0)


if __name__ == '__main__':
    main()