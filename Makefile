# VPN Manager - Testing and Development Makefile

.PHONY: help test test-unit test-integration test-performance test-load test-quality test-all
.PHONY: coverage coverage-report quality-report lint format type-check
.PHONY: clean install dev-install pre-commit-install
.PHONY: benchmark memory-profile docker-test

# Default target
help:
	@echo "VPN Manager Development Commands"
	@echo "================================"
	@echo ""
	@echo "Testing Commands:"
	@echo "  test              Run all tests"
	@echo "  test-unit         Run unit tests only"
	@echo "  test-integration  Run integration tests"
	@echo "  test-performance  Run performance tests"
	@echo "  test-load         Run load tests"
	@echo "  test-quality      Run quality gate tests"
	@echo "  test-fast         Run fast tests (skip slow)"
	@echo "  test-parallel     Run tests in parallel"
	@echo ""
	@echo "Coverage Commands:"
	@echo "  coverage          Run tests with coverage"
	@echo "  coverage-report   Generate detailed coverage report"
	@echo "  coverage-html     Generate HTML coverage report"
	@echo ""
	@echo "Quality Commands:"
	@echo "  quality-report    Generate comprehensive quality report"
	@echo "  lint             Run code linting"
	@echo "  format           Format code"
	@echo "  type-check       Run type checking"
	@echo "  check            Run all quality checks"
	@echo ""
	@echo "Development Commands:"
	@echo "  install          Install package"
	@echo "  dev-install      Install development dependencies"
	@echo "  pre-commit-install Install pre-commit hooks"
	@echo "  clean            Clean build artifacts"
	@echo ""
	@echo "Performance Commands:"
	@echo "  benchmark        Run performance benchmarks"
	@echo "  memory-profile   Run memory profiling tests"
	@echo "  docker-test      Run Docker integration tests"

# Testing commands
test:
	pytest tests/ -v

test-unit:
	pytest tests/ -m "unit" -v

test-integration:
	pytest tests/ -m "integration" -v --tb=short

test-performance:
	pytest tests/ -m "performance" -v --benchmark-only

test-load:
	pytest tests/ -m "load" -v -s

test-quality:
	pytest tests/ -m "quality" -v

test-fast:
	pytest tests/ -m "not slow and not load" -v

test-parallel:
	pytest tests/ -n auto --dist worksteal -v

test-all:
	pytest tests/ -v --cov=vpn --cov-report=html --cov-report=xml --cov-report=json

# Coverage commands
coverage:
	pytest tests/ --cov=vpn --cov-branch --cov-report=term-missing

coverage-report:
	pytest tests/ --cov=vpn --cov-branch --cov-report=html --cov-report=xml --cov-report=json
	@echo "Coverage reports generated:"
	@echo "  HTML: htmlcov/index.html"
	@echo "  XML:  coverage.xml"
	@echo "  JSON: coverage.json"

coverage-html:
	pytest tests/ --cov=vpn --cov-branch --cov-report=html
	@echo "HTML coverage report: htmlcov/index.html"

# Quality commands
quality-report:
	python -m tests.test_coverage_quality
	@echo "Quality reports generated in reports/ directory"

lint:
	ruff check vpn/ tests/
	black --check vpn/ tests/

format:
	black vpn/ tests/
	ruff check --fix vpn/ tests/
	isort vpn/ tests/

type-check:
	mypy vpn/

check: lint type-check test-quality
	@echo "All quality checks completed"

# Development commands
install:
	pip install -e .

dev-install:
	pip install -e ".[dev,test,docs]"

pre-commit-install: dev-install
	pre-commit install

clean:
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/
	rm -rf htmlcov/
	rm -rf .pytest_cache/
	rm -rf .ruff_cache/
	rm -rf .mypy_cache/
	rm -rf .coverage
	rm -rf coverage.xml
	rm -rf coverage.json
	rm -rf reports/
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

# Performance commands
benchmark:
	pytest tests/ -m "performance" --benchmark-only --benchmark-sort=mean

memory-profile:
	pytest tests/ -m "memory" -v -s

docker-test:
	pytest tests/ -m "docker" -v

# Specific test categories
test-services:
	pytest tests/test_*_service*.py -v

test-models:
	pytest tests/test_models*.py -v

test-cli:
	pytest tests/test_cli*.py -v

test-tui:
	pytest tests/ -m "tui" -v

test-database:
	pytest tests/test_database*.py tests/test_*_manager.py -v

test-protocols:
	pytest tests/test_protocol*.py -v

# CI/CD friendly commands
ci-test:
	pytest tests/ -v --cov=vpn --cov-branch --cov-report=xml --cov-report=json --maxfail=5

ci-quality:
	ruff check vpn/ tests/
	black --check vpn/ tests/
	mypy vpn/
	pytest tests/ -m "quality" -v

# Test with different markers combinations
test-critical:
	pytest tests/ -m "not slow and not load and not performance" -v --maxfail=1

test-comprehensive:
	pytest tests/ -v --cov=vpn --cov-branch --cov-report=html --tb=long --durations=20

# Development workflow commands
dev-test:
	pytest tests/ -x -v --tb=short --no-cov

watch-test:
	pytest-watch tests/ -- -v --tb=short --no-cov

# Documentation
docs:
	mkdocs build -f config/mkdocs.yml

docs-serve:
	mkdocs serve -f config/mkdocs.yml

# Documentation and reporting
docs-coverage:
	python -c "\
from tests.test_coverage_quality import QualityAnalyzer;\
analyzer = QualityAnalyzer();\
metrics = analyzer.analyze_quality();\
print(f'Documentation coverage: {metrics.documentation_coverage:.1f}%')"

type-coverage:
	python -c "\
from tests.test_coverage_quality import QualityAnalyzer;\
analyzer = QualityAnalyzer();\
metrics = analyzer.analyze_quality();\
print(f'Type annotation coverage: {metrics.type_annotation_coverage:.1f}%')"

# Test data management
clean-test-data:
	python -c "\
import asyncio;\
from tests.test_data_manager import get_test_data_manager;\
asyncio.run(get_test_data_manager().cleanup_all())"

# Performance monitoring
profile-test:
	python -m cProfile -s cumulative -m pytest tests/test_performance*.py

# Environment verification
verify-env:
	python -c "\
import sys;\
print(f'Python: {sys.version}');\
try:\
    import pytest; print(f'pytest: {pytest.__version__}');\
    import coverage; print(f'coverage: {coverage.__version__}');\
    import ruff; print('ruff: available');\
    import black; print(f'black: {black.__version__}');\
    import mypy; print('mypy: available');\
    print('✅ Development environment verified');\
except ImportError as e:\
    print(f'❌ Missing dependency: {e}')"

# Quick development shortcuts
quick: test-fast lint
full: test-all coverage-report quality-report
minimal: test-unit type-check