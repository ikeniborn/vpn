#!/bin/bash
# Show clean project structure

echo "📁 VPN Manager Project Structure"
echo "================================"
echo ""

# Main directories
echo "📂 Root Directory Organization:"
tree -L 1 -d --charset=ascii | grep -v "^\." | head -20

echo ""
echo "📂 Source Code Structure (vpn/):"
tree vpn -L 2 -d --charset=ascii 2>/dev/null | head -30

echo ""
echo "📂 Tests Structure:"
tree tests -L 2 --charset=ascii 2>/dev/null | grep -E "\.(py|yaml|json)$" | head -20

echo ""
echo "📂 Configuration Files:"
echo "  config/"
ls -la config/ 2>/dev/null | grep -v "^total" | grep -v "^d"
echo "  docker/"
ls -la docker/ 2>/dev/null | grep -v "^total" | grep -v "^d"
echo "  .config/"
tree .config -L 2 --charset=ascii 2>/dev/null

echo ""
echo "📊 File Count Summary:"
echo "  Python files: $(find vpn -name "*.py" | wc -l)"
echo "  Test files: $(find tests -name "test_*.py" | wc -l)"
echo "  Config files: $(find config -type f | wc -l)"
echo "  Docker files: $(find docker -type f | wc -l)"
echo "  Documentation: $(find docs -name "*.md" | wc -l)"

echo ""
echo "🧹 Root directory is now organized with:"
echo "  - config/: Application configuration files"
echo "  - docker/: Docker-related files"
echo "  - .config/: Development configuration (git, QA tools)"
echo "  - Main code, docs, and tests remain in standard locations"