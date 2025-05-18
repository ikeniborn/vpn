#!/bin/bash
#
# Helper script to install dependencies for the VLESS client generator

set -e

echo "Checking and installing required dependencies for VLESS client generator..."

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# List of required packages
DEPENDENCIES=("jq" "qrencode")
MISSING_DEPS=()

# Check which dependencies are missing
for dep in "${DEPENDENCIES[@]}"; do
  if ! command_exists "$dep"; then
    MISSING_DEPS+=("$dep")
  fi
done

# Install missing dependencies if any
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  echo "The following dependencies are missing: ${MISSING_DEPS[*]}"
  
  if command_exists apt-get; then
    echo "Installing missing dependencies using apt-get..."
    sudo apt-get update
    sudo apt-get install -y "${MISSING_DEPS[@]}"
  elif command_exists yum; then
    echo "Installing missing dependencies using yum..."
    sudo yum install -y "${MISSING_DEPS[@]}"
  elif command_exists dnf; then
    echo "Installing missing dependencies using dnf..."
    sudo dnf install -y "${MISSING_DEPS[@]}"
  elif command_exists pacman; then
    echo "Installing missing dependencies using pacman..."
    sudo pacman -S --noconfirm "${MISSING_DEPS[@]}"
  else
    echo "ERROR: Could not determine package manager. Please install these packages manually:"
    echo "  ${MISSING_DEPS[*]}"
    exit 1
  fi
  
  echo "Dependencies installed successfully!"
else
  echo "All required dependencies are already installed!"
fi

echo
echo "You can now run the VLESS client generator script with:"
echo "./generate-vless-client.sh --name \"your-device-name\""
echo
echo "For more options, use:"
echo "./generate-vless-client.sh --help"