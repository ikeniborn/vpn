# VPN Manager - Development Guide

## Quick Start

### 1. Create Virtual Environment

```bash
# Create virtual environment
python -m venv venv

# Activate virtual environment
# On Linux/macOS:
source venv/bin/activate
# On Windows:
venv\Scripts\activate
```

### 2. Install Dependencies

```bash
# Install development dependencies
pip install -e ".[dev,test,docs]"

# Or use make command
make install-dev
```

### 3. Initialize Development Environment

```bash
# Install pre-commit hooks
pre-commit install

# Initialize application (create directories and database)
python -m vpn init

# Run diagnostics
python -m vpn doctor
```

### 4. Run Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=vpn

# Or use make
make test
make test-cov
```

### 5. Code Quality

```bash
# Format code
black .
# or
make format

# Run linter
ruff check .
# or
make lint

# Type checking
mypy vpn
# or
make type-check
```

## Project Structure

```
vpn-python/
├── vpn/                    # Main package
│   ├── __init__.py        # Package initialization
│   ├── __main__.py        # Module entry point
│   ├── cli/               # CLI interface
│   │   ├── app.py         # Main CLI application
│   │   └── commands/      # CLI command implementations
│   ├── core/              # Core functionality
│   │   ├── config.py      # Configuration management
│   │   ├── database.py    # Database models and operations
│   │   ├── exceptions.py  # Custom exceptions
│   │   └── models.py      # Pydantic data models
│   ├── services/          # Business logic services
│   ├── tui/               # Terminal UI (Textual)
│   ├── templates/         # Configuration templates
│   └── utils/             # Utility modules
├── tests/                 # Test suite
│   ├── conftest.py       # Pytest configuration
│   └── test_*.py         # Test files
├── docs/                  # Documentation
├── scripts/               # Utility scripts
├── pyproject.toml        # Project configuration
├── Makefile              # Development commands
└── README.md             # Project documentation
```

## Available Commands

### CLI Commands

```bash
# Show help
python -m vpn --help

# Show version
python -m vpn --version

# Initialize configuration
python -m vpn init

# Run diagnostics
python -m vpn doctor

# Launch TUI (when implemented)
python -m vpn menu
```

### Make Commands

```bash
# Show all available commands
make help

# Install dependencies
make install      # Production only
make install-dev  # Development

# Testing
make test         # Run tests
make test-cov     # Run with coverage

# Code quality
make lint         # Run linter
make format       # Format code
make type-check   # Type checking

# Running
make run-cli      # Show CLI help
make run-tui      # Launch TUI

# Clean temporary files
make clean
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# Copy example file
cp .env.example .env

# Edit as needed
```

Key environment variables:
- `VPN_DEBUG`: Enable debug mode
- `VPN_LOG_LEVEL`: Set logging level (DEBUG, INFO, WARNING, ERROR)
- `VPN_DATABASE_URL`: Database connection string
- `VPN_INSTALL_PATH`: Installation directory path

### Settings

Configuration is managed through Pydantic Settings with the following hierarchy:
1. Default values in code
2. Configuration files (YAML/TOML)
3. Environment variables
4. Command-line arguments

## Database

### Initialize Database

```bash
python -m vpn init
```

### Database Migrations

Currently using SQLAlchemy with automatic table creation. For production, we'll add Alembic for proper migrations.

## Testing

### Running Tests

```bash
# All tests
pytest

# Specific test file
pytest tests/test_models.py

# Specific test
pytest tests/test_models.py::TestUser::test_minimal_user

# With coverage
pytest --cov=vpn --cov-report=html
```

### Test Categories

Tests are marked with categories:
- `unit`: Unit tests (default)
- `integration`: Integration tests
- `slow`: Slow tests

Run specific categories:
```bash
pytest -m unit
pytest -m "not slow"
```

## Code Style

### Formatting

We use Black for code formatting:
```bash
black .
```

### Linting

We use Ruff for linting:
```bash
ruff check .
ruff check --fix .  # Auto-fix issues
```

### Type Checking

We use mypy for static type checking:
```bash
mypy vpn
```

## Git Workflow

### Pre-commit Hooks

Pre-commit hooks are configured to run:
- Code formatting (Black)
- Linting (Ruff)
- Type checking (mypy)
- Security checks (Bandit)

Install hooks:
```bash
pre-commit install
```

Run manually:
```bash
pre-commit run --all-files
```

## Debugging

### Enable Debug Mode

```bash
# Via environment variable
export VPN_DEBUG=true
python -m vpn

# Via command line
python -m vpn --debug
```

### Using IPython

For interactive debugging:
```bash
pip install ipython
ipython
```

Then in IPython:
```python
from vpn.core.models import User, ProtocolConfig, ProtocolType

# Create test user
protocol = ProtocolConfig(type=ProtocolType.VLESS)
user = User(username="test", protocol=protocol)
print(user)
```

## Performance Profiling

### Using cProfile

```bash
python -m cProfile -o profile.stats -m vpn doctor

# Analyze results
python -m pstats profile.stats
```

### Memory Profiling

```bash
pip install memory-profiler
mprof run python -m vpn
mprof plot
```

## Documentation

### Building Documentation

```bash
# Install docs dependencies
pip install -e ".[docs]"

# Build docs
mkdocs build

# Serve locally
mkdocs serve
```

Documentation will be available at http://localhost:8000

## Troubleshooting

### Common Issues

1. **Import errors**: Ensure you've installed the package in development mode:
   ```bash
   pip install -e .
   ```

2. **Database errors**: Initialize the database:
   ```bash
   python -m vpn init
   ```

3. **Permission errors**: Some operations require elevated privileges:
   ```bash
   sudo python -m vpn
   ```

4. **Type checking errors**: Update type stubs:
   ```bash
   mypy --install-types
   ```

### Getting Help

- Check the documentation
- Run diagnostics: `python -m vpn doctor`
- Enable debug mode for detailed logs
- Check GitHub issues