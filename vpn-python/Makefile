.PHONY: help install install-dev test test-cov lint format type-check clean run-cli run-tui docs

# Default target
help:
	@echo "VPN Manager - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make install      Install production dependencies"
	@echo "  make install-dev  Install development dependencies"
	@echo ""
	@echo "Development:"
	@echo "  make test         Run tests"
	@echo "  make test-cov     Run tests with coverage"
	@echo "  make lint         Run linter (ruff)"
	@echo "  make format       Format code (black)"
	@echo "  make type-check   Run type checking (mypy)"
	@echo "  make clean        Clean temporary files"
	@echo ""
	@echo "Running:"
	@echo "  make run-cli      Run CLI application"
	@echo "  make run-tui      Run TUI application"
	@echo ""
	@echo "Documentation:"
	@echo "  make docs         Build documentation"

# Installation
install:
	pip install -e .

install-dev:
	pip install -e ".[dev,test,docs]"
	pre-commit install

# Testing
test:
	pytest -v

test-cov:
	pytest --cov=vpn --cov-report=html --cov-report=term

# Code quality
lint:
	ruff check .

format:
	black .
	ruff check --fix .

type-check:
	mypy vpn

# Cleaning
clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type f -name ".coverage" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type d -name ".mypy_cache" -exec rm -rf {} +
	find . -type d -name ".ruff_cache" -exec rm -rf {} +
	find . -type d -name "htmlcov" -exec rm -rf {} +
	find . -type d -name "dist" -exec rm -rf {} +
	find . -type d -name "build" -exec rm -rf {} +

# Running
run-cli:
	python -m vpn --help

run-tui:
	python -m vpn menu

# Documentation
docs:
	mkdocs build

docs-serve:
	mkdocs serve

# Development workflow
dev: install-dev
	@echo "Development environment ready!"

check: lint type-check test
	@echo "All checks passed!"

fix: format
	@echo "Code formatted!"