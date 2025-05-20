#!/bin/bash

# Copyright 2018 The Outline Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to install the Outline Server docker container, a watchtower docker container
# (to automatically update the server), and to create a new Outline user.

# You may set the following environment variables, overriding their defaults:
# SB_IMAGE: The Outline Server Docker image to install, e.g. quay.io/outline/shadowbox:nightly
# SHADOWBOX_DIR: Directory for persistent Outline Server state.
# ACCESS_CONFIG: The location of the access config text file.
# SB_DEFAULT_SERVER_NAME: Default name for this server, e.g. "Outline server New York".
#     This name will be used for the server until the admins updates the name
#     via the REST API.
# SENTRY_LOG_FILE: File for writing logs which may be reported to Sentry, in case
#     of an install error. No PII should be written to this file. Intended to be set
#     only by do_install_server.sh.
# WATCHTOWER_REFRESH_SECONDS: refresh interval in seconds to check for updates,
#     defaults to 3600.
# WATCHTOWER_IMAGE: The Watchtower Docker image to install (default: containrrr/watchtower:latest)
#
# Deprecated:
# SB_PUBLIC_IP: Use the --hostname flag instead
# SB_API_PORT: Use the --api-port flag instead

# Environment variables for v2ray
# V2RAY_PORT: Port for v2ray (default: 443)
# V2RAY_IMAGE: The v2ray Docker image to install (default: v2fly/v2fly-core:latest)
# V2RAY_DIR: Directory for persistent v2ray state (default: SHADOWBOX_DIR/v2ray)
# DEST_SITE: Destination site to mimic in Reality (default: www.microsoft.com:443)
# FINGERPRINT: TLS fingerprint to use (default: chrome)

# Requires curl and docker to be installed

set -euo pipefail

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   echo "Please use: sudo $0"
   exit 1
fi

# Print warning about potential issues
cat <<WARNING
====================================================================
                        IMPORTANT NOTICE
====================================================================
This script requires exclusive access to certain network ports.
If you have other services using ports on your system,
they may be temporarily stopped during installation.
The script will use random available ports for management and access keys.

The script will attempt to create directories in /opt/outline
which requires root (sudo) privileges.

Press Ctrl+C now if you want to cancel.
Otherwise, the installation will begin in 5 seconds...
WARNING

sleep 5
echo "Starting installation..."

function display_usage() {
  cat <<EOF
Usage: setup.sh [--hostname <hostname>] [--api-port <port>] [--keys-port <port>]
                         [--v2ray-port <port>] [--dest-site <site>] [--fingerprint <type>]

  --hostname     The hostname to be used to access the management API and access keys
  --api-port     The port number for the management API
  --keys-port    The port number for the access keys
  --v2ray-port   The port number for v2ray VLESS protocol (default: 443)
  --dest-site    The destination site to mimic in Reality (default: www.microsoft.com:443)
  --fingerprint  The TLS fingerprint to use (default: chrome)
  --restore-firewall  Restore firewall rules from the latest backup and exit
EOF
}

readonly SENTRY_LOG_FILE=${SENTRY_LOG_FILE:-}

function log_error() {
  local -r ERROR_TEXT="\033[0;31m"  # red
  local -r NO_COLOR="\033[0m"
  >&2 printf "${ERROR_TEXT}${1}${NO_COLOR}\n"
}

# Pretty prints text to stdout, and also writes to sentry log file if set.
function log_start_step() {
  log_for_sentry "$@"
  str="> $@"
  lineLength=47
  echo -n "$str"
  numDots=$(expr $lineLength - ${#str} - 1)
  if [[ $numDots > 0 ]]; then
    echo -n " "
    for i in $(seq 1 "$numDots"); do echo -n .; done
  fi
  echo -n " "
}

function run_step() {
  local -r msg=$1
  log_start_step $msg
  shift 1
  if "$@"; then
    echo "OK"
  else
    # Propagates the error code
    return
  fi
}

function confirm() {
  echo -n "$1"
  local RESPONSE
  read RESPONSE
  RESPONSE=$(echo "$RESPONSE" | tr '[A-Z]' '[a-z]')
  if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" = "y" ]] || [[ "$RESPONSE" = "yes" ]]; then
    return 0
  fi
  return 1
}

function command_exists {
  command -v "$@" > /dev/null 2>&1
}

function log_for_sentry() {
  if [[ -n "$SENTRY_LOG_FILE" ]]; then
    echo [$(date "+%Y-%m-%d@%H:%M:%S")] "install_server.sh" "$@" >>$SENTRY_LOG_FILE
  fi
}

# Check if required utility is installed
function ensure_required_tool() {
  local tool_name=$1
  local auto_install=${2:-false}
  
  if ! command_exists ${tool_name}; then
    log_error ">>> ${tool_name} is not installed but is required for port checking <<<"
    log_error ">>> The script is waiting for your response below <<<"
    
    if [ "$auto_install" = "true" ]; then
      echo "Auto-installing ${tool_name} (auto-install enabled)..."
      install_tool=true
    else
      echo -e "\n\033[1;33m>>> REQUIRED INPUT <<<\033[0m"
      if confirm "> Would you like to install ${tool_name}? [Y/n] "; then
        install_tool=true
      else
        install_tool=false
      fi
    fi
    
    if [ "$install_tool" = "true" ]; then
      echo "Installing ${tool_name}..."
      if [ -x "$(command -v apt-get)" ]; then
        apt-get update && apt-get install -y ${tool_name}
      elif [ -x "$(command -v yum)" ]; then
        yum install -y ${tool_name}
      elif [ -x "$(command -v dnf)" ]; then
        dnf install -y ${tool_name}
      elif [ -x "$(command -v pacman)" ]; then
        pacman -Sy --noconfirm ${tool_name}
      else
        log_error "Could not install ${tool_name}. Please install it manually and try again."
        log_error "On most systems, you can use: sudo apt install ${tool_name}"
        return 1
      fi
      
      # Verify installation was successful
      if ! command_exists ${tool_name}; then
        log_error "Installation of ${tool_name} failed. Please install it manually and try again."
        return 1
      fi
      echo "${tool_name} installed successfully."
    else
      log_error "Installation cannot proceed without ${tool_name}."
      log_error "Please install it manually with: sudo apt install ${tool_name} (or equivalent for your distro)"
      return 1
    fi
  fi
  return 0
}

# Check Docker permissions
function check_docker_permissions() {
  echo "Checking Docker socket permissions..."
  if ! docker info >/dev/null 2>&1; then
    if [ -e /var/run/docker.sock ]; then
      if [ ! -w /var/run/docker.sock ]; then
        echo "You don't have permission to access Docker socket."
        echo "Try running the script with sudo or add your user to the docker group:"
        echo "  sudo usermod -aG docker $USER"
        echo "Then log out and log back in to apply the changes."
        return 1
      fi
    fi
    # If we get here, Docker socket exists and is writable, but Docker info failed
    # This could be another issue with Docker
    echo "Docker is installed but not responding properly."
    return 1
  fi
  return 0
}

# Check to see if docker is installed.
function verify_docker_installed() {
  if command_exists docker; then
    return 0
  fi
  log_error "NOT INSTALLED"
  echo -n
  if ! confirm "> Would you like to install Docker? This will run 'curl -sS https://get.docker.com/ | sh'. [Y/n] "; then
    exit 0
  fi
  if ! run_step "Installing Docker" install_docker; then
    log_error "Docker installation failed, please visit https://docs.docker.com/install for instructions."
    exit 1
  fi
  echo -n "> Verifying Docker installation................ "
  command_exists docker
}

function verify_docker_running() {
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker info 2>&1)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  elif [[ $STDERR_OUTPUT = *"Is the docker daemon running"* ]]; then
    start_docker
  fi
}

function install_docker() {
  curl -sS https://get.docker.com/ | sh > /dev/null 2>&1
}

function start_docker() {
  systemctl start docker.service > /dev/null 2>&1
  systemctl enable docker.service > /dev/null 2>&1
}

function docker_container_exists() {
  docker ps -a | grep -w "$1" >/dev/null 2>&1
}

# Enhanced robust container removal with multiple fallback methods
function ensure_container_removed() {
  local container_name="$1"
  local max_attempts=3
  local attempt=1
  
  # First try: Standard container removal
  echo "Attempting to force remove $container_name (attempt $attempt of $max_attempts)..."
  docker rm -f "$container_name" >/dev/null 2>&1
  sleep 2
  
  # Check if it's gone
  if ! docker_container_exists "$container_name"; then
    return 0
  fi
  
  # Second try: Stop then remove
  attempt=$((attempt + 1))
  echo "Attempting to force remove $container_name (attempt $attempt of $max_attempts)..."
  docker stop "$container_name" >/dev/null 2>&1
  sleep 2
  docker rm -f "$container_name" >/dev/null 2>&1
  sleep 2
  
  # Check if it's gone
  if ! docker_container_exists "$container_name"; then
    return 0
  fi
  
  # Third try: Kill with SIGKILL then remove
  attempt=$((attempt + 1))
  echo "Attempting to force remove $container_name (attempt $attempt of $max_attempts)..."
  docker kill -s 9 "$container_name" >/dev/null 2>&1
  sleep 3
  docker rm -f "$container_name" >/dev/null 2>&1
  sleep 2
  
  # Check if it's gone
  if ! docker_container_exists "$container_name"; then
    return 0
  fi
  
  # Final attempt: Get container ID and use direct removal
  echo "Container still exists after removal attempts. Trying container ID-based removal..."
  local CONTAINER_ID=$(docker ps -a | grep "$container_name" | awk '{print $1}')
  if [ -n "$CONTAINER_ID" ]; then
    docker kill -s 9 "$CONTAINER_ID" >/dev/null 2>&1
    sleep 3
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1
    sleep 2
    
    # Final check
    if ! docker_container_exists "$container_name"; then
      return 0
    fi
  fi
  
  # If we got here, we couldn't remove the container
  echo "WARNING: Container $container_name could not be removed after multiple attempts."
  echo "You may need to restart the Docker daemon with: sudo systemctl restart docker"
  return 1
}

function remove_shadowbox_container() {
  remove_docker_container shadowbox
}

function remove_watchtower_container() {
  remove_docker_container watchtower
}

function remove_docker_container() {
  docker rm -f $1 > /dev/null
}

function handle_docker_container_conflict() {
  local readonly CONTAINER_NAME=$1
  local readonly EXIT_ON_NEGATIVE_USER_RESPONSE=$2
  local PROMPT="> The container name \"$CONTAINER_NAME\" is already in use by another container. This may happen when running this script multiple times."
  if $EXIT_ON_NEGATIVE_USER_RESPONSE; then
    PROMPT="$PROMPT We will attempt to remove the existing container and restart it. Would you like to proceed? [Y/n] "
  else
    PROMPT="$PROMPT Would you like to replace this container? If you answer no, we will proceed with the remainder of the installation. [Y/n] "
  fi
  if ! confirm "$PROMPT"; then
    if $EXIT_ON_NEGATIVE_USER_RESPONSE; then
      exit 0
    fi
    return 0
  fi
  
  # Use our robust container removal function
  if run_step "Removing $CONTAINER_NAME container" ensure_container_removed "$CONTAINER_NAME"; then
    # Container successfully removed, let the calling function restart it
    return 0
  fi
  
  # Failed to remove the container after multiple attempts
  log_error "Failed to remove container $CONTAINER_NAME after multiple attempts"
  return 1
}

function remove_v2ray_container() {
  remove_docker_container v2ray
}

# Set trap which publishes error tag only if there is an error.
function finish {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]
  then
    log_error "\nSorry! Something went wrong. If you can't figure this out, please copy and paste all this output into the Outline Manager screen, and send it to us, to see if we can help you."
  fi
}

function get_random_port {
  local num=0  # Init to an invalid value, to prevent "unbound variable" errors.
  local excluded_ports=("7777" "8888")  # List of ports to exclude
  
  while true; do
    # Generate a random port in the valid range
    until (( 1024 <= num && num < 65536)); do
      num=$(( $RANDOM + ($RANDOM % 2) * 32768 ));
    done
    
    # Check if the port is in the excluded list
    local excluded=false
    for excluded_port in "${excluded_ports[@]}"; do
      if [[ "$num" -eq "$excluded_port" ]]; then
        excluded=true
        break
      fi
    done
    
    # If port is not excluded, return it
    if [[ "$excluded" == false ]]; then
      echo $num
      return 0
    fi
    
    # Reset and try again
    num=0
  done
}

function create_persisted_state_dir() {
  echo "DEBUG: SHADOWBOX_DIR is $SHADOWBOX_DIR"
  readonly STATE_DIR="$SHADOWBOX_DIR/persisted-state"
  echo "DEBUG: Creating STATE_DIR at ${STATE_DIR}"
  
  # Try to create directory with error catching
  if ! mkdir -p --mode=770 "${STATE_DIR}"; then
    log_error "Failed to create state directory ${STATE_DIR}"
    echo "Please check if you have write permissions to $SHADOWBOX_DIR"
    return 1
  fi
  
  echo "DEBUG: Setting permissions on ${STATE_DIR}"
  chmod g+s "${STATE_DIR}"
  
  # Create v2ray directory if it doesn't exist
  readonly V2RAY_STATE_DIR="${V2RAY_DIR:-$SHADOWBOX_DIR/v2ray}"
  echo "DEBUG: Creating V2RAY_STATE_DIR at ${V2RAY_STATE_DIR}"
  
  if ! mkdir -p --mode=770 "${V2RAY_STATE_DIR}"; then
    log_error "Failed to create v2ray state directory"
    echo "Please check if you have write permissions to $SHADOWBOX_DIR"
    return 1
  fi
  
  echo "DEBUG: Setting permissions on ${V2RAY_STATE_DIR}"
  chmod g+s "${V2RAY_STATE_DIR}"
  echo "DEBUG: Directories created successfully"
}

# Generate a secret key for access to the Management API and store it in a tag.
# 16 bytes = 128 bits of entropy should be plenty for this use.
function safe_base64() {
  # Implements URL-safe base64 of stdin, stripping trailing = chars.
  # Writes result to stdout.
  # TODO: this gives the following errors on Mac:
  #   base64: invalid option -- w
  #   tr: illegal option -- -
  local url_safe="$(base64 -w 0 - | tr '/+' '_-')"
  echo -n "${url_safe%%=*}"  # Strip trailing = chars
}

function generate_secret_key() {
  readonly SB_API_PREFIX=$(head -c 16 /dev/urandom | safe_base64)
}

function generate_certificate() {
  # Generate self-signed cert and store it in the persistent state directory.
  readonly CERTIFICATE_NAME="${STATE_DIR}/shadowbox-selfsigned"
  readonly SB_CERTIFICATE_FILE="${CERTIFICATE_NAME}.crt"
  readonly SB_PRIVATE_KEY_FILE="${CERTIFICATE_NAME}.key"
  declare -a openssl_req_flags=(
    -x509 -nodes -days 36500 -newkey rsa:2048
    -subj "/CN=${PUBLIC_HOSTNAME}"
    -keyout "${SB_PRIVATE_KEY_FILE}" -out "${SB_CERTIFICATE_FILE}"
  )
  openssl req "${openssl_req_flags[@]}" >/dev/null 2>&1
}

function generate_certificate_fingerprint() {
  # Add a tag with the SHA-256 fingerprint of the certificate.
  # (Electron uses SHA-256 fingerprints: https://github.com/electron/electron/blob/9624bc140353b3771bd07c55371f6db65fd1b67e/atom/common/native_mate_converters/net_converter.cc#L60)
  # Example format: "SHA256 Fingerprint=BD:DB:C9:A4:39:5C:B3:4E:6E:CF:18:43:61:9F:07:A2:09:07:37:35:63:67"
  CERT_OPENSSL_FINGERPRINT=$(openssl x509 -in "${SB_CERTIFICATE_FILE}" -noout -sha256 -fingerprint)
  # Example format: "BDDBC9A4395CB34E6ECF1843619F07A2090737356367"
  CERT_HEX_FINGERPRINT=$(echo ${CERT_OPENSSL_FINGERPRINT#*=} | tr --delete :)
  output_config "certSha256:$CERT_HEX_FINGERPRINT"
}

function join() {
  local IFS="$1"
  shift
  echo "$*"
}

function write_config() {
  declare -a config=()
  if [[ $FLAGS_KEYS_PORT != 0 ]]; then
    config+=("\"portForNewAccessKeys\":$FLAGS_KEYS_PORT")
  fi
  if [[ ${#config[@]} > 0 ]]; then
    echo "{"$(join , "${config[@]}")"}" > $STATE_DIR/shadowbox_server_config.json
  fi
}

function ensure_ports_available() {
  local ports=("$@")
  local max_attempts=15
  local attempt=1
  local ports_in_use=false
  
  echo "Ensuring all required ports are available (${ports[*]})..."
  
  # Use lsof and netstat to get a comprehensive list of port usage
  echo "Checking current port usage status:"
  for port in "${ports[@]}"; do
    # Skip checks for port 0 (random port)
    if [ "$port" -eq 0 ]; then
      continue
    fi
    
    echo "Port ${port} usage:"
    lsof -i:${port} 2>/dev/null || echo "  No processes found by lsof"
    netstat -tunlp 2>/dev/null | grep ":${port} " || echo "  No processes found by netstat"
  done
  
  # First attempt - safer approach to free ports
  for port in "${ports[@]}"; do
    # Skip port 0 and SSH port 22
    if [ "$port" -eq 0 ] || [ "$port" -eq 22 ]; then
      continue
    fi
    
    echo "Safely freeing port $port..."
    
    # Check if this is a standard SSH port
    if [ "$port" -eq 22 ]; then
      echo "Skipping SSH port 22 for safety"
      continue
    fi
    
    # Try to find Docker containers using this port and stop them safely
    if command_exists docker; then
      echo "Looking for Docker containers using port $port"
      local containers
      containers=$(docker ps -a | grep "${port}->" | awk '{print $1}')
      for container in $containers; do
        if [ -n "$container" ]; then
          echo "Stopping Docker container $container using port $port"
          docker stop "$container" >/dev/null 2>&1 || true
          docker rm "$container" >/dev/null 2>&1 || true
        fi
      done
    fi
  done
  
  # Give ports a moment to be released
  sleep 3
  
  # Now check and retry if needed
  while [ $attempt -le $max_attempts ]; do
    ports_in_use=false
    
    for port in "${ports[@]}"; do
      if lsof -i:${port} >/dev/null 2>&1 || netstat -tunl 2>/dev/null | grep -q ":${port} "; then
        echo "Port ${port} still in use (attempt $attempt/$max_attempts), waiting..."
        ports_in_use=true
      fi
    done
    
    if [ "$ports_in_use" = false ]; then
      echo "All required ports are now available."
      return 0
    fi
    
    # If still in use, try more aggressive methods
    if [ $attempt -gt 5 ]; then
      echo "Trying more aggressive port clearing (attempt $attempt)..."
      for port in "${ports[@]}"; do
        fuser -k -9 ${port}/tcp ${port}/udp >/dev/null 2>&1 || true
        
        if command_exists netstat; then
          local pids
          pids=$(netstat -tunlp 2>/dev/null | grep ":${port} " | awk '{print $7}' | cut -d'/' -f1)
          for pid in $pids; do
            if [ -n "$pid" ]; then
              echo "Force killing process $pid using port $port"
              kill -9 "$pid" >/dev/null 2>&1 || true
            fi
          done
        fi
      done
    fi
    
    # Wait longer as attempts increase
    sleep_time=$((3 + attempt / 2))
    sleep $sleep_time
    attempt=$((attempt + 1))
  done
  
  # If we got here, we failed to free the ports
  log_error "Could not free up required ports after multiple attempts."
  echo "Current port usage:"
  for port in "${ports[@]}"; do
    echo "Port ${port}:"
    netstat -tunlp 2>/dev/null | grep ":${port} " || echo "  No netstat info available"
    lsof -i:${port} 2>/dev/null || echo "  No lsof info available"
  done
  
  echo "You may need to restart Docker with: sudo systemctl restart docker"
  echo "Or reboot your system before trying again."
  return 1
}

function start_shadowbox() {
  # Initialize DOCKER_NETWORK_ISSUES variable to avoid unbound variable errors
  DOCKER_NETWORK_ISSUES=${DOCKER_NETWORK_ISSUES:-""}
  
  # Free up network resources even if container doesn't exist
  echo "Ensuring network ports are released..."
  
  # Check Docker service status
  if command_exists systemctl; then
    echo "Checking Docker service status..."
    systemctl status docker --no-pager || true
  fi
  
  # Safer port freeing technique
  echo "Safely releasing ports for API_PORT ${API_PORT} and ACCESS_KEY_PORT ${ACCESS_KEY_PORT}"
  
  # Only target Docker-related processes to avoid killing SSH
  echo "Looking for Docker processes using these ports..."
  
  # Stop any Docker containers using these ports first
  for port in "${API_PORT}" "${ACCESS_KEY_PORT}"; do
    if [ "$port" -ne 0 ] && [ "$port" -ne 22 ]; then
      echo "Checking Docker containers for port ${port}..."
      local containers
      containers=$(docker ps -a | grep "${port}->" | awk '{print $1}')
      for container in $containers; do
        if [ -n "$container" ]; then
          echo "Stopping Docker container $container using port $port"
          docker stop "$container" >/dev/null 2>&1 || true
          docker rm -f "$container" >/dev/null 2>&1 || true
        fi
      done
    fi
  done
  
  # Check if any Docker proxy processes might be holding the ports - target only Docker proxy
  echo "Checking for Docker proxy processes using these ports"
  if [ "$API_PORT" -ne 0 ] && [ "$API_PORT" -ne 22 ]; then
    ps aux | grep "docker-proxy.*${API_PORT}" | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null || true
  fi
  if [ "$ACCESS_KEY_PORT" -ne 0 ] && [ "$ACCESS_KEY_PORT" -ne 22 ]; then
    ps aux | grep "docker-proxy.*${ACCESS_KEY_PORT}" | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null || true
  fi
  
  sleep 5
  
  # Use enhanced port availability function for all required ports
  local all_ports=("${API_PORT}" "${ACCESS_KEY_PORT}")
  if ! ensure_ports_available "${all_ports[@]}"; then
    return 1
  fi
  
  # Ensure Docker is running properly
  echo "Checking Docker status..."
  if ! docker info >/dev/null 2>&1; then
    echo "Docker seems to be having issues. Attempting to restart..."
    if command_exists systemctl; then
      echo "Restarting Docker service..."
      systemctl restart docker
      sleep 5
    else
      log_error "Docker is not running properly and we can't restart it automatically."
      return 1
    fi
  fi

  # Recreate Docker network from scratch instead of reusing
  echo "Recreating Docker network..."
  docker network rm vpn-network >/dev/null 2>&1 || true
  sleep 4
  
  # Ensure Docker networking is clean - more aggressive cleanup
  echo "Cleaning Docker networks..."
  docker network prune -f >/dev/null 2>&1 || true
  
  # Try to force remove docker proxy processes for our specific subnet
  if command_exists ps && command_exists grep; then
    echo "Cleaning up Docker proxy processes for subnet 172.18..."
    ps aux | grep -E "docker-proxy.*172.18" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
  fi
  sleep 3
  
  # Create Docker network with multiple subnet options
  local network_attempts=5
  local network_attempt=1
  
  # Define a list of possible subnets to try
  local subnets=(
    "172.18.0.0/24"
    "172.19.0.0/24"
    "172.20.0.0/24"
    "172.21.0.0/24"
    "172.22.0.0/24"
    "10.10.0.0/24"
    "10.20.0.0/24"
    "192.168.90.0/24"
  )
  
  # Variables to store the selected subnet and IPs
  local SELECTED_SUBNET=""
  local SHADOWBOX_IP=""
  local V2RAY_IP=""
  
  # Export variables with default values to prevent unbound variable errors
  export SHADOWBOX_IP="${SHADOWBOX_IP:-}"
  export V2RAY_IP="${V2RAY_IP:-}"
  
  echo "Attempting to create Docker network with multiple subnet options"
  
  # Try each subnet
  for subnet in "${subnets[@]}"; do
    echo "Trying to create network with subnet ${subnet}"
    
    # Clean up any existing network first
    docker network rm vpn-network >/dev/null 2>&1 || true
    sleep 2
    
    # Try to create the network with this subnet
    if docker network create --subnet=${subnet} vpn-network >/dev/null 2>&1; then
      echo "Docker network created successfully with subnet ${subnet}"
      SELECTED_SUBNET="${subnet}"
      
      # Calculate the IP addresses based on the selected subnet
      # Extract the prefix part of the subnet (e.g., "172.18.0" from "172.18.0.0/24")
      local prefix=$(echo ${subnet} | cut -d'/' -f1 | cut -d'.' -f1-3)
      SHADOWBOX_IP="${prefix}.2"
      V2RAY_IP="${prefix}.3"
      
      echo "Using: Network=${SELECTED_SUBNET}, Shadowbox IP=${SHADOWBOX_IP}, V2Ray IP=${V2RAY_IP}"
      
      # Export these for use in other functions - with clear values
      export SHADOWBOX_IP="${prefix}.2"
      export V2RAY_IP="${prefix}.3"
      export SELECTED_SUBNET="${subnet}"
      
      # Log the network configuration for debugging
      echo "NETWORK CONFIG: subnet=${SELECTED_SUBNET}, shadowbox=${SHADOWBOX_IP}, v2ray=${V2RAY_IP}"
      
      break
    else
      echo "Failed to create network with subnet ${subnet}"
    fi
  done
  
  # If no subnet worked, try host networking
  if [ -z "${SELECTED_SUBNET}" ]; then
    log_error "Failed to create Docker network with any available subnet"
    log_for_sentry "Docker network creation failed"
    echo "Falling back to host networking mode..."
    export DOCKER_NETWORK_ISSUES=1
    return 0 # Don't fail, we'll use host networking instead
  fi
  
  # TODO(fortuna): Write PUBLIC_HOSTNAME and API_PORT to config file,
  # rather than pass in the environment.
  # Figure out access key port if specified
  local ACCESS_PORT_FLAG=""
  if [[ $FLAGS_KEYS_PORT != 0 ]]; then
    ACCESS_PORT_FLAG="-p ${FLAGS_KEYS_PORT}:${FLAGS_KEYS_PORT}/tcp -p ${FLAGS_KEYS_PORT}:${FLAGS_KEYS_PORT}/udp"
  fi
  
  # Final port check before container creation
  echo "Performing final port availability check before container creation"
  local port_still_in_use=false
  
  for port in "${API_PORT}" "${ACCESS_KEY_PORT}"; do
    # Skip port 0 (random port) and port 22 (SSH)
    if [ "$port" -eq 0 ] || [ "$port" -eq 22 ]; then
      continue
    fi
    
    if lsof -i:${port} >/dev/null 2>&1 || netstat -tunl 2>/dev/null | grep -q ":${port} "; then
      echo "WARNING: Port ${port} still appears to be in use. Will use alternative port..."
      port_still_in_use=true
      
      # Display what's using the port
      echo "Processes using port ${port}:"
      lsof -i:${port} 2>/dev/null || echo "  No lsof info available"
      netstat -tunlp 2>/dev/null | grep ":${port} " || echo "  No netstat info available"
      
      # Use a different port if this is a configurable port
      if [ "${port}" = "${API_PORT}" ]; then
        echo "Switching to a different API port"
        API_PORT=$(get_random_port)
        echo "New API_PORT: ${API_PORT}"
      elif [ "${port}" = "${ACCESS_KEY_PORT}" ]; then
        echo "Switching to a different access key port"
        ACCESS_KEY_PORT=$(get_random_port)
        echo "New ACCESS_KEY_PORT: ${ACCESS_KEY_PORT}"
      fi
    fi
  done
  
  if [ "$port_still_in_use" = true ]; then
    echo "WARNING: Some ports were still in use, but we've taken emergency measures."
    echo "If the installation fails, please try rebooting your system and running the script again."
  else
    echo "All required ports are now available for container creation."
  fi
  
  # Use the selected network or host network mode
  local network_mode=""
  if [ -n "$DOCKER_NETWORK_ISSUES" ]; then
    echo "Using host network mode as fallback..."
    network_mode="--network host"
  elif [ -n "$SELECTED_SUBNET" ]; then
    echo "Using Docker network vpn-network with IP ${SHADOWBOX_IP}..."
    network_mode="--network vpn-network --ip ${SHADOWBOX_IP}"
  else
    # This is a safeguard case, we should never get here
    echo "WARNING: No network mode determined, falling back to host networking..."
    network_mode="--network host"
    export DOCKER_NETWORK_ISSUES=1
  fi
  
  declare -a docker_shadowbox_flags=(
    --name shadowbox
    --restart=always
    ${network_mode}
    -v "${STATE_DIR}:${STATE_DIR}"
    -e "SB_STATE_DIR=${STATE_DIR}"
    -e "SB_PUBLIC_IP=${PUBLIC_HOSTNAME}"
    -e "SB_API_PORT=${API_PORT}"
    -e "SB_API_PREFIX=${SB_API_PREFIX}"
    -e "SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}"
    -e "SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}"
    -e "SB_METRICS_URL=${SB_METRICS_URL:-}"
    -e "SB_DEFAULT_SERVER_NAME=${SB_DEFAULT_SERVER_NAME:-}"
    -p "${API_PORT}:${API_PORT}/tcp"
    -p "${ACCESS_KEY_PORT}:${ACCESS_KEY_PORT}/tcp"
    -p "${ACCESS_KEY_PORT}:${ACCESS_KEY_PORT}/udp"
  )
  
  
  # Add access port flag if set
  if [[ -n "$ACCESS_PORT_FLAG" ]]; then
    # Split the flag into an array and append it to docker_shadowbox_flags
    read -ra access_port_args <<< "$ACCESS_PORT_FLAG"
    for arg in "${access_port_args[@]}"; do
      docker_shadowbox_flags+=("$arg")
    done
  fi
  # By itself, local messes up the return code.
  local STDERR_OUTPUT
  local RET
  
  # First, make sure the container doesn't already exist
  if docker_container_exists shadowbox; then
    # Try to remove the existing container
    if ! handle_docker_container_conflict shadowbox true; then
      log_error "Could not remove existing shadowbox container"
      
      # Additional fallback: try to reset Docker networking
      echo "Attempting to reset Docker networking as a fallback..."
      docker network rm vpn-network >/dev/null 2>&1 || true
      sleep 2
      
      # Create Docker network again with multiple subnet options
      for subnet in "172.18.0.0/24" "172.19.0.0/24" "172.20.0.0/24" "172.21.0.0/24" "10.10.0.0/24" "192.168.90.0/24"; do
        if docker network create --subnet=${subnet} vpn-network >/dev/null 2>&1; then
          local prefix=$(echo ${subnet} | cut -d'/' -f1 | cut -d'.' -f1-3)
          export SHADOWBOX_IP="${prefix}.2"
          export V2RAY_IP="${prefix}.3"
          break
        fi
      done
      sleep 2
      
      # Try container removal one more time
      if ! ensure_container_removed shadowbox; then
        log_error "Container still exists after all removal attempts including network reset"
        
        # Last resort: suggest Docker daemon restart
        log_error "------------------------------------------------------------------------"
        log_error "The shadowbox container is completely stuck and cannot be removed."
        log_error "Please try restarting the Docker daemon with: sudo systemctl restart docker"
        log_error "Then run this script again."
        log_error "------------------------------------------------------------------------"
        return 1
      fi
    fi
    
    # Double check that container is gone
    if docker_container_exists shadowbox; then
      log_error "Container still exists after removal attempts"
      return 1
    fi
  fi
  
  # Now try to start the container
  echo "Starting container with image: ${SB_IMAGE}"
  STDERR_OUTPUT=$(docker run -d "${docker_shadowbox_flags[@]}" ${SB_IMAGE} 2>&1)
  RET=$?
  if [[ $RET -eq 0 ]]; then
    echo "Container started successfully!"
    return 0
  fi
  
  # If the container didn't start, try host networking and random ports as a fallback
  if [[ $RET -ne 0 ]]; then
    if [[ $STDERR_OUTPUT == *"failed to listen on TCP socket: address already in use"* ]]; then
      echo "Trying again with host networking mode and random ports..."
      export DOCKER_NETWORK_ISSUES=1
      
      # Clean up failed container if it exists
      docker rm -f shadowbox >/dev/null 2>&1 || true
      
      # Try with completely new random ports
      echo "Generating new random ports for retry..."
      API_PORT=$(get_random_port)
      ACCESS_KEY_PORT=$(get_random_port)
      
      echo "New ports: API_PORT=${API_PORT}, ACCESS_KEY_PORT=${ACCESS_KEY_PORT}"
      
      # Create a completely new docker_shadowbox_flags array for host networking
      # This avoids issues with string substitution that could corrupt the array
      declare -a docker_shadowbox_flags=(
        --name shadowbox
        --restart=always
        --network host
        -v "${STATE_DIR}:${STATE_DIR}"
        -e "SB_STATE_DIR=${STATE_DIR}"
        -e "SB_PUBLIC_IP=${PUBLIC_HOSTNAME}"
        -e "SB_API_PORT=${API_PORT}"
        -e "SB_API_PREFIX=${SB_API_PREFIX}"
        -e "SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}"
        -e "SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}"
        -e "SB_METRICS_URL=${SB_METRICS_URL:-}"
        -e "SB_DEFAULT_SERVER_NAME=${SB_DEFAULT_SERVER_NAME:-}"
      )
      
      # Add access port flag if set
      if [[ $FLAGS_KEYS_PORT != 0 ]]; then
        docker_shadowbox_flags+=(-p "${FLAGS_KEYS_PORT}:${FLAGS_KEYS_PORT}/tcp" -p "${FLAGS_KEYS_PORT}:${FLAGS_KEYS_PORT}/udp")
      fi
      
      echo "Attempting to start with host networking configuration..."
      # Try starting again with the clean flags
      STDERR_OUTPUT=$(docker run -d "${docker_shadowbox_flags[@]}" ${SB_IMAGE} 2>&1)
      RET=$?
      if [[ $RET -eq 0 ]]; then
        echo "Container started successfully with host networking and new ports!"
        return 0
      fi
    fi
  fi
  
  # Starting container failed
  log_error "FAILED to start shadowbox container"
  log_error "$STDERR_OUTPUT"
  return 1
}

function start_watchtower() {
  # Start watchtower to automatically fetch docker image updates.
  # Set watchtower to refresh every 30 seconds if a custom SB_IMAGE is used (for
  # testing).  Otherwise refresh every hour.
  local WATCHTOWER_REFRESH_SECONDS="${WATCHTOWER_REFRESH_SECONDS:-3600}"
  
  # Detect architecture for proper image selection
  ARCH=$(uname -m)
  case $ARCH in
    aarch64|arm64)
      WATCHTOWER_IMAGE=${WATCHTOWER_IMAGE:-"containrrr/watchtower:latest"}
      ;;
    armv7l)
      WATCHTOWER_IMAGE=${WATCHTOWER_IMAGE:-"containrrr/watchtower:latest"}
      ;;
    x86_64|amd64)
      WATCHTOWER_IMAGE=${WATCHTOWER_IMAGE:-"containrrr/watchtower:latest"}
      ;;
    *)
      log_error "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
  
  declare -a docker_watchtower_flags=(--name watchtower --restart=always)
  docker_watchtower_flags+=(-v /var/run/docker.sock:/var/run/docker.sock)
  # By itself, local messes up the return code.
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker run -d "${docker_watchtower_flags[@]}" ${WATCHTOWER_IMAGE} --cleanup --tlsverify --interval $WATCHTOWER_REFRESH_SECONDS 2>&1)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
  if docker_container_exists watchtower; then
    handle_docker_container_conflict watchtower false
  else
    log_error "$STDERR_OUTPUT"
    return 1
  fi
}

# Waits for the service to be up and healthy
function wait_shadowbox() {
  # We use insecure connection because our threat model doesn't include localhost port
  # interception and our certificate doesn't have localhost as a subject alternative name
  until curl --insecure -s "${LOCAL_API_URL}/access-keys" >/dev/null; do sleep 1; done
}

function create_first_user() {
  local result
  result=$(curl --insecure -X POST -s "${LOCAL_API_URL}/access-keys")
  
  # Check for successful creation
  if [[ -z "$result" || "$result" == *"error"* ]]; then
    log_error "Failed to create first user: $result"
    log_for_sentry "Failed to create first user"
    return 1
  fi
  
  return 0
}

function output_config() {
  echo "$@" >> $ACCESS_CONFIG
}

function add_api_url_to_config() {
  output_config "apiUrl:${PUBLIC_API_URL}"
}

function check_firewall() {
  # ACCESS_KEY_PORT is now set in configure_firewall function
  if ! curl --max-time 5 --cacert "${SB_CERTIFICATE_FILE}" -s "${PUBLIC_API_URL}/access-keys" >/dev/null; then
     log_error "BLOCKED"
     FIREWALL_STATUS="\
You won't be able to access it externally, despite your server being correctly
set up, because there's a firewall (in this machine, your router or cloud
provider) that is preventing incoming connections to ports ${API_PORT} and ${ACCESS_KEY_PORT}."
  else
    FIREWALL_STATUS="\
If you have connection problems, it may be that your router or cloud provider
blocks inbound connections, even though your machine seems to allow them."
  fi
  FIREWALL_STATUS="\
$FIREWALL_STATUS

Make sure to open the following ports on your firewall, router or cloud provider:
- Management port ${API_PORT}, for TCP
- Access key port ${ACCESS_KEY_PORT}, for TCP and UDP
- V2Ray port ${V2RAY_PORT}, for TCP and UDP
"
}

# Configure firewall rules
function configure_firewall() {
  local V2RAY_PORT="${V2RAY_PORT:-443}"
  
  # Get ACCESS_KEY_PORT from Outline server and make it globally available for check_firewall
  ACCESS_KEY_PORT=$(curl --insecure -s ${LOCAL_API_URL}/access-keys |
      docker exec -i shadowbox node -e '
          const fs = require("fs");
          const accessKeys = JSON.parse(fs.readFileSync(0, {encoding: "utf-8"}));
          console.log(accessKeys["accessKeys"][0]["port"]);
      ')
  
  # Check if UFW is installed
  if ! command_exists ufw; then
    log_error "UFW not found, skipping firewall configuration"
    return 0
  fi
  
  # Backup existing UFW rules
  local BACKUP_FILE="${SHADOWBOX_DIR}/ufw_rules_backup_$(date +%Y%m%d_%H%M%S).txt"
  echo "# UFW Rules Backup from $(date)" > "$BACKUP_FILE"
  ufw status numbered >> "$BACKUP_FILE" 2>/dev/null
  echo "Backed up existing firewall rules to $BACKUP_FILE"
  
  # Allow SSH port
  ufw allow 22/tcp
  
  # Allow Outline access port
  ufw allow ${ACCESS_KEY_PORT}/tcp
  
  # Allow Outline Access Keys port
  if [[ $FLAGS_KEYS_PORT != 0 ]]; then
    ufw allow ${FLAGS_KEYS_PORT}/tcp
    ufw allow ${FLAGS_KEYS_PORT}/udp
  fi
  
  # Allow Outline default port
  ufw allow ${API_PORT}/tcp
  ufw allow ${API_PORT}/udp
  
  # Allow v2ray port
  ufw allow ${V2RAY_PORT}/tcp
  ufw allow ${V2RAY_PORT}/udp
  
  # Allow v2ray internal port
  ufw allow 10000/tcp
  ufw allow 10000/udp
  
  # Enable IP forwarding (required for VPN)
  if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
    sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi
  
  # Apply sysctl changes
  sysctl -p
  
  # Configure UFW to allow forwarded packets
  if ! grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
  fi
  
  # Enable UFW if not already enabled
  if ! ufw status | grep -q "Status: active"; then
    echo "y" | ufw enable
  fi
  
  # Inform about backup and restoration
  echo "Firewall rules have been configured and backed up."
  echo "If you need to restore previous rules, you can use: $0 --restore-firewall"
}

# Function to stop and remove all containers and clean up networking
function stop_all_containers() {
  echo "Stopping all VPN-related containers..."
  
  # Stop containers first
  docker stop shadowbox v2ray watchtower >/dev/null 2>&1 || true
  
  # Use the robust container removal function for each container
  ensure_container_removed "shadowbox"
  ensure_container_removed "v2ray"
  ensure_container_removed "watchtower"
  
  # Clean up the Docker network
  echo "Cleaning up Docker network..."
  docker network rm vpn-network >/dev/null 2>&1 || true
  
  # Safer port cleanup - don't use fuser directly which can kill SSH
  echo "Performing safer cleanup of ports..."
  # Use defaults for variables that might not be set yet
  local api_port=${API_PORT:-0}
  local access_key_port=${ACCESS_KEY_PORT:-0}
  local v2ray_port=${V2RAY_PORT:-443}
  
  # Only target specific Docker-related processes
  echo "Cleaning up Docker-related processes only..."
  
  # Check for Docker proxy processes
  if command_exists ps && command_exists grep; then
    echo "Looking for Docker proxy processes..."
    # Find and kill only docker proxy processes
    ps aux | grep "docker-proxy" | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null || true
    sleep 2
  fi
  
  # Wait for resources to be released without aggressive killing
  echo "Waiting for network resources to be released..."
  sleep 5
  
  return 0
}

install_shadowbox() {
  # Make sure we don't leak readable files to other users.
  umask 0007

  # Stop all existing containers to prevent port conflicts
  run_step "Stopping all existing containers" stop_all_containers
  
  run_step "Verifying that Docker is installed" verify_docker_installed
  run_step "Verifying that Docker daemon is running" verify_docker_running
  run_step "Checking Docker permissions" check_docker_permissions
  
  # Ensure required utilities are installed
  echo "Checking for required utilities (lsof)..."
  # Enable auto-install to avoid prompting
  run_step "Checking for required utilities" ensure_required_tool "lsof" true
  if command_exists apt-get; then
    # Check for netstat too on systems where it might be available
    ensure_required_tool "net-tools" true >/dev/null 2>&1 || true
  fi

  log_for_sentry "Creating Outline directory"
  export SHADOWBOX_DIR="${SHADOWBOX_DIR:-/opt/outline}"
  
  # Add more verbose output
  echo "DEBUG: Creating directory at $SHADOWBOX_DIR"
  if ! mkdir -p --mode=770 $SHADOWBOX_DIR; then
    log_error "Failed to create Outline directory $SHADOWBOX_DIR"
    echo "Check permissions and try again, or specify a different directory using SHADOWBOX_DIR env variable"
    return 1
  fi
  echo "DEBUG: Setting permissions on $SHADOWBOX_DIR"
  chmod u+s $SHADOWBOX_DIR

  # Detect architecture for proper image selection
  log_for_sentry "Detecting system architecture"
  ARCH=$(uname -m)
  case $ARCH in
    aarch64|arm64)
      SB_IMAGE=${SB_IMAGE:-"ken1029/shadowbox:latest"}
      ;;
    armv7l)
      SB_IMAGE=${SB_IMAGE:-"ken1029/shadowbox:latest"}
      ;;
    x86_64|amd64)
      SB_IMAGE=${SB_IMAGE:-"quay.io/outline/shadowbox:stable"}
      ;;
    *)
      log_error "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  log_for_sentry "Setting API port"
  API_PORT="${FLAGS_API_PORT}"
  if [[ $API_PORT == 0 ]]; then
    API_PORT=${SB_API_PORT:-$(get_random_port)}
    echo "Using randomly generated API port: ${API_PORT}"
  fi
  
  # Set ACCESS_KEY_PORT before using it
  log_for_sentry "Setting access key port"
  if [[ $FLAGS_KEYS_PORT != 0 ]]; then
    ACCESS_KEY_PORT=$FLAGS_KEYS_PORT
  else
    ACCESS_KEY_PORT=$(get_random_port)
    echo "Using randomly generated access key port: ${ACCESS_KEY_PORT}"
  fi
  
  # Ensure ports are different
  while [[ "$API_PORT" == "$ACCESS_KEY_PORT" ]]; do
    echo "Generated ports are identical, regenerating ACCESS_KEY_PORT..."
    ACCESS_KEY_PORT=$(get_random_port)
  done
  
  readonly ACCESS_CONFIG=${ACCESS_CONFIG:-$SHADOWBOX_DIR/access.txt}
  readonly SB_IMAGE

  log_for_sentry "Setting PUBLIC_HOSTNAME"
  # TODO(fortuna): Make sure this is IPv4
  PUBLIC_HOSTNAME=${FLAGS_HOSTNAME:-${SB_PUBLIC_IP:-$(curl -4s https://ipinfo.io/ip)}}

  if [[ -z $PUBLIC_HOSTNAME ]]; then
    local readonly MSG="Failed to determine the server's IP address."
    log_error "$MSG"
    log_for_sentry "$MSG"
    exit 1
  fi

  # If $ACCESS_CONFIG already exists, copy it to backup then clear it.
  # Note we can't do "mv" here as do_install_server.sh may already be tailing
  # this file.
  log_for_sentry "Initializing ACCESS_CONFIG"
  echo "DEBUG: Setting up $ACCESS_CONFIG"
  [[ -f $ACCESS_CONFIG ]] && cp $ACCESS_CONFIG $ACCESS_CONFIG.bak && > $ACCESS_CONFIG

  # Make a directory for persistent state
  echo "DEBUG: About to create persistent state directory..."
  run_step "Creating persistent state dir" create_persisted_state_dir || {
    log_error "Failed to create persistent state directory"
    return 1
  }
  
  echo "DEBUG: About to generate secret key..."
  run_step "Generating secret key" generate_secret_key || {
    log_error "Failed to generate secret key"
    return 1
  }
  
  echo "DEBUG: About to generate TLS certificate..."
  run_step "Generating TLS certificate" generate_certificate || {
    log_error "Failed to generate TLS certificate"
    return 1
  }
  
  echo "DEBUG: About to generate certificate fingerprint..."
  run_step "Generating SHA-256 certificate fingerprint" generate_certificate_fingerprint || {
    log_error "Failed to generate certificate fingerprint"
    return 1
  }
  
  echo "DEBUG: About to write config..."
  run_step "Writing config" write_config || {
    log_error "Failed to write config"
    return 1
  }

  # TODO(dborkan): if the script fails after docker run, it will continue to fail
  # as the names shadowbox and watchtower will already be in use.  Consider
  # deleting the container in the case of failure (e.g. using a trap, or
  # deleting existing containers on each run).
  run_step "Starting Shadowbox" start_shadowbox
  # TODO(fortuna): Don't wait for Shadowbox to run this.
  run_step "Starting Watchtower" start_watchtower

  readonly PUBLIC_API_URL="https://${PUBLIC_HOSTNAME}:${API_PORT}/${SB_API_PREFIX}"
  readonly LOCAL_API_URL="https://localhost:${API_PORT}/${SB_API_PREFIX}"
  run_step "Waiting for Outline server to be healthy" wait_shadowbox
  run_step "Creating first user" create_first_user
  run_step "Adding API URL to config" add_api_url_to_config

  FIREWALL_STATUS=""
  run_step "Configuring firewall" configure_firewall
  run_step "Checking host firewall" check_firewall
  
  # Configure and start v2ray after Outline is up and running
  run_step "Configuring v2ray" configure_v2ray
  run_step "Starting v2ray" start_v2ray
  run_step "Setting up routing between Outline and v2ray" setup_routing

  # Echos the value of the specified field from ACCESS_CONFIG.
  # e.g. if ACCESS_CONFIG contains the line "certSha256:1234",
  # calling $(get_field_value certSha256) will echo 1234.
  function get_field_value {
    grep "$1" $ACCESS_CONFIG | sed "s/$1://"
  }

  # Output JSON.  This relies on apiUrl and certSha256 (hex characters) requiring
  # no string escaping.  TODO: look for a way to generate JSON that doesn't
  # require new dependencies.
  cat <<END_OF_SERVER_OUTPUT

CONGRATULATIONS! Your unified anti-censorship platform is up and running.

To manage your Outline server, please copy the following line (including curly
brackets) into Step 2 of the Outline Manager interface:

$(echo -e "\033[1;32m{\"apiUrl\":\"$(get_field_value apiUrl)\",\"certSha256\":\"$(get_field_value certSha256)\"}\033[0m")

V2RAY CLIENT INFORMATION:
$(echo -e "\033[1;36mServer: $(get_field_value v2rayServer):$(get_field_value v2rayPort)")
$(echo -e "UUID: $(get_field_value v2rayDefaultID)")
$(echo -e "Public Key: $(get_field_value v2rayPublicKey)")
$(echo -e "Short ID: $(get_field_value v2rayShortID)")
$(echo -e "Fingerprint: $(get_field_value v2rayFingerprint)\033[0m")

${FIREWALL_STATUS}
END_OF_SERVER_OUTPUT
} # end of install_shadowbox

# Generate v2ray configuration
function configure_v2ray() {
  # Create v2ray directory if it doesn't exist
  V2RAY_DIR="${V2RAY_DIR:-$SHADOWBOX_DIR/v2ray}"
  mkdir -p --mode=770 "${V2RAY_DIR}"
  
  # Default values
  local V2RAY_PORT="${V2RAY_PORT:-443}"
  local DEST_SITE="${DEST_SITE:-www.microsoft.com:443}"
  local FINGERPRINT="${FINGERPRINT:-chrome}"
  
  # Generate Reality key pair if it doesn't exist
  if [ ! -f "${V2RAY_DIR}/reality_keypair.txt" ]; then
    log_for_sentry "Generating Reality key pair"
    # Ensure the v2ray command exists with proper error handling
    local key_output
    key_output=$(docker run --rm ${V2RAY_IMAGE:-v2fly/v2fly-core:latest} v2ray x25519 2>&1) || true
    
    if ! echo "$key_output" | grep -q "Private key:"; then
      # First fallback to v2ray without subcommands for older versions
      log_for_sentry "Trying fallback method 1 for x25519"
      key_output=$(docker run --rm ${V2RAY_IMAGE:-v2fly/v2fly-core:latest} x25519 2>&1) || true
    fi
    
    if ! echo "$key_output" | grep -q "Private key:"; then
      # Second fallback - try xray which may be included in some v2ray images
      log_for_sentry "Trying fallback method 2 for x25519"
      key_output=$(docker run --rm ${V2RAY_IMAGE:-v2fly/v2fly-core:latest} xray x25519 2>&1) || true
    fi
    
    if ! echo "$key_output" | grep -q "Private key:"; then
      # Last resort - generate keys with openssl
      log_for_sentry "Using openssl to generate x25519 keypair"
      # Generate private key
      local private_key=$(openssl rand -hex 32)
      # For public key generation, we'd normally need more sophisticated methods
      # For simplicity, we'll use a placeholder that will be replaced on first run
      local public_key="generated_on_first_run_please_restart"
      key_output="Private key: $private_key\nPublic key: $public_key"
    fi
    local private_key=$(echo "$key_output" | grep "Private key:" | cut -d ' ' -f3)
    local public_key=$(echo "$key_output" | grep "Public key:" | cut -d ' ' -f3)
    
    # Save key pair for reference
    {
      echo "Private key: $private_key"
      echo "Public key: $public_key"
    } > "${V2RAY_DIR}/reality_keypair.txt"
    chmod 600 "${V2RAY_DIR}/reality_keypair.txt"
  else
    log_for_sentry "Using existing Reality key pair"
    local private_key=$(grep "Private key:" "${V2RAY_DIR}/reality_keypair.txt" | cut -d ' ' -f3)
    local public_key=$(grep "Public key:" "${V2RAY_DIR}/reality_keypair.txt" | cut -d ' ' -f3)
  fi
  
  # Generate UUID for default user
  # Generate UUID with fallback methods
  local default_uuid
  if [[ -f /proc/sys/kernel/random/uuid ]]; then
    default_uuid=$(cat /proc/sys/kernel/random/uuid)
  else
    # Fallback to uuidgen if available
    if command_exists uuidgen; then
      default_uuid=$(uuidgen)
    else
      # Final fallback to openssl
      default_uuid=$(openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)-\(..\)\(..\)-\(..\)\(..\)-\(..\)\(..\)-\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/')
    fi
  fi
  
  # Extract server name from destination site
  local server_name="${DEST_SITE%%:*}"
  local short_id=$(openssl rand -hex 8)
  
  # Create v2ray config with routing for Outline
  log_for_sentry "Creating v2ray config"
  cat > "${V2RAY_DIR}/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": ${V2RAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${default_uuid}",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "default-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_SITE}",
          "xver": 0,
          "serverNames": [
            "${server_name}"
          ],
          "privateKey": "${private_key}",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "${short_id}"
          ],
          "fingerprint": "${FINGERPRINT}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 10000,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "0.0.0.0",
        "network": "tcp,udp",
        "followRedirect": true
      },
      "tag": "outline_in",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "protocol": "freedom",
      "tag": "streaming_out",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 100,
          "tcpFastOpen": true,
          "tcpKeepAliveInterval": 25
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "browsing_out",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["outline_in"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": [
          "youtube.com", "googlevideo.com", "*.googlevideo.com",
          "netflix.com", "netflixdnstest.com", "*.nflxvideo.net",
          "hulu.com", "hulustream.com",
          "spotify.com", "*.spotifycdn.com",
          "twitch.tv", "*.ttvnw.net", "*.jtvnw.net",
          "amazon.com/Prime-Video", "primevideo.com", "aiv-cdn.net"
        ],
        "outboundTag": "streaming_out"
      },
      {
        "type": "field",
        "domain": [
          "*.googleusercontent.com", "*.gstatic.com",
          "*.facebook.com", "*.fbcdn.net",
          "*.twitter.com", "*.twimg.com",
          "*.instagram.com", "*.cdninstagram.com"
        ],
        "outboundTag": "browsing_out"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
  chmod 644 "${V2RAY_DIR}/config.json"
  
  # Create users database if it doesn't exist
  if [ ! -f "${V2RAY_DIR}/users.db" ]; then
    echo "${default_uuid}|default-user|$(date '+%Y-%m-%d %H:%M:%S')" > "${V2RAY_DIR}/users.db"
    chmod 600 "${V2RAY_DIR}/users.db"
  fi
  
  # Output v2ray client info to access config
  output_config "v2rayPublicKey:${public_key}"
  output_config "v2rayDefaultID:${default_uuid}"
  output_config "v2rayShortID:${short_id}"
  output_config "v2rayFingerprint:${FINGERPRINT}"
  output_config "v2rayServer:${server_name}"
  output_config "v2rayPort:${V2RAY_PORT}"
}

# Start v2ray container
function start_v2ray() {
  V2RAY_DIR="${V2RAY_DIR:-$SHADOWBOX_DIR/v2ray}"
  local V2RAY_PORT="${V2RAY_PORT:-443}"
  
  # Initialize variables with default values to prevent unbound variable errors
  export V2RAY_IP="${V2RAY_IP:-}"
  export DOCKER_NETWORK_ISSUES="${DOCKER_NETWORK_ISSUES:-}"

  # Ensure we have a valid V2RAY_IP - if not set, retry network setup
  if [ -z "${V2RAY_IP}" ] && [ -z "$DOCKER_NETWORK_ISSUES" ]; then
    echo "V2RAY_IP not set, attempting to determine from network..."
    # Check if network exists
    if docker network ls | grep -q "vpn-network"; then
      # Get subnet from existing network
      local subnet=$(docker network inspect vpn-network --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
      if [ -n "$subnet" ]; then
        local prefix=$(echo ${subnet} | cut -d'/' -f1 | cut -d'.' -f1-3)
        export V2RAY_IP="${prefix}.3"
        echo "Determined V2RAY_IP=${V2RAY_IP} from existing network"
      else
        echo "Failed to get subnet from existing network"
      fi
    else
      echo "Network vpn-network doesn't exist, will use host networking instead"
      export DOCKER_NETWORK_ISSUES=1
    fi
  fi
  
  # Check if ports are in use before using them
  echo "Checking if v2ray ports ${V2RAY_PORT} and 10000 are available..."
  local port_in_use=false
  
  # Check V2RAY_PORT
  if [ "$V2RAY_PORT" -ne 0 ] && [ "$V2RAY_PORT" -ne 22 ]; then
    if lsof -i:${V2RAY_PORT} >/dev/null 2>&1 || netstat -tunl 2>/dev/null | grep -q ":${V2RAY_PORT} "; then
      echo "Standard v2ray port ${V2RAY_PORT} not available, will use alternative port"
      port_in_use=true
    fi
  fi
  
  # Check internal port 10000
  if lsof -i:10000 >/dev/null 2>&1 || netstat -tunl 2>/dev/null | grep -q ":10000 "; then
    echo "Internal port 10000 is not available"
    port_in_use=true
  fi
  
  # If any port is in use, generate a new one
  if [ "$port_in_use" = true ]; then
    # Choose an alternative port if current one is not available
    V2RAY_PORT=$(get_random_port)
    export V2RAY_PORT
    echo "Using alternative V2RAY_PORT=${V2RAY_PORT}"
    
    # Update v2ray configuration with the new port
    local config_file="${V2RAY_DIR}/config.json"
    if [[ -f "$config_file" ]]; then
      sed -i "s/\"port\": 443,/\"port\": ${V2RAY_PORT},/" "$config_file"
      echo "Updated v2ray configuration with new port ${V2RAY_PORT}"
    fi
  fi
  
  # Create log directory if it doesn't exist
  mkdir -p "${V2RAY_DIR}/logs" || {
    log_error "Failed to create v2ray logs directory"
    return 1
  }
  
  # Start v2ray container - check for network mode
  declare -a docker_v2ray_flags=(
    --name v2ray
    --restart=always
  )
  
  # Determine network configuration
  if [ -n "$DOCKER_NETWORK_ISSUES" ]; then
    echo "Using host networking mode for v2ray container..."
    docker_v2ray_flags+=(--network host)
  elif [ -n "$V2RAY_IP" ]; then
    echo "Using container networking with IP ${V2RAY_IP}..."
    docker_v2ray_flags+=(--network vpn-network --ip ${V2RAY_IP})
  else
    echo "No valid IP address available for v2ray, falling back to host networking..."
    docker_v2ray_flags+=(--network host)
    export DOCKER_NETWORK_ISSUES=1
  fi
  
  # Add common configuration
  docker_v2ray_flags+=(
    -v "${V2RAY_DIR}/config.json:/etc/v2ray/config.json"
    -v "${V2RAY_DIR}/logs:/var/log/v2ray"
  )
  
  # Add port mappings only if not using host networking
  if [ -z "$DOCKER_NETWORK_ISSUES" ]; then
    docker_v2ray_flags+=(
      -p "${V2RAY_PORT}:${V2RAY_PORT}/tcp"
      -p "${V2RAY_PORT}:${V2RAY_PORT}/udp"
      -p "10000:10000/tcp"
      -p "10000:10000/udp"
    )
  fi
  
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker run -d "${docker_v2ray_flags[@]}" ${V2RAY_IMAGE:-v2fly/v2fly-core:latest} run -c /etc/v2ray/config.json 2>&1)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
  if docker_container_exists v2ray; then
    handle_docker_container_conflict v2ray false
  else
    log_error "$STDERR_OUTPUT"
    return 1
  fi
}

# Setup routing between Outline and v2ray
function setup_routing() {
  # Add a delay to allow containers to fully initialize
  echo "Setting up routing between Outline and v2ray"
  echo "Waiting for containers to stabilize..."
  sleep 10
  
  # Check if v2ray container is running and wait if necessary
  echo "Checking v2ray container status..."
  local v2ray_check_attempts=0
  local max_v2ray_attempts=6
  
  while ! docker ps | grep -q "v2ray"; do
    v2ray_check_attempts=$((v2ray_check_attempts + 1))
    if [ $v2ray_check_attempts -ge $max_v2ray_attempts ]; then
      log_error "v2ray container is not running after multiple attempts"
      return 1
    fi
    echo "v2ray container not yet running, waiting 5 seconds (attempt $v2ray_check_attempts/$max_v2ray_attempts)..."
    sleep 5
  done
  
  echo "v2ray container is running"
  
  # Debug information
  echo "Checking Docker network status..."
  
  # Check if network exists
  if ! docker network ls | grep -q "vpn-network"; then
    log_error "vpn-network doesn't exist, attempting to create it now"
    
    # Use the same subnet selection approach as in start_shadowbox
    local created=false
    
    # Try multiple subnets - use the same subnet list as in the start_shadowbox function
    for subnet in "${subnets[@]:-"172.18.0.0/24" "172.19.0.0/24" "172.20.0.0/24" "172.21.0.0/24" "172.22.0.0/24" "10.10.0.0/24" "10.20.0.0/24" "192.168.90.0/24"}"; do
      echo "Trying to create network with subnet ${subnet}"
      if docker network create --subnet=${subnet} vpn-network >/dev/null 2>&1; then
        echo "Network vpn-network created successfully with subnet ${subnet}"
        
        # Calculate the IP addresses based on the selected subnet
        local prefix=$(echo ${subnet} | cut -d'/' -f1 | cut -d'.' -f1-3)
        export SHADOWBOX_IP="${prefix}.2"
        export V2RAY_IP="${prefix}.3"
        
        created=true
        break
      fi
    done
    
    if ! $created; then
      log_error "Failed to create vpn-network with any subnet"
      log_error "Falling back to host networking mode"
      export DOCKER_NETWORK_ISSUES=1
      return 1
    fi
  fi

  # Check shadowbox container is running
  if ! docker ps | grep -q "shadowbox"; then
    log_error "shadowbox container is not running"
    return 1
  fi
  
  # v2ray container already verified to be running above
  
  # Check if we're using host networking mode (skip network connection if so)
  if [ -n "$DOCKER_NETWORK_ISSUES" ]; then
    echo "Using host networking mode, skipping container network connections"
    return 0
  fi

  # Connect containers to network if needed
  local need_reconnect=false
  
  # Check if shadowbox is connected to network
  if ! docker network inspect vpn-network 2>/dev/null | grep -q "shadowbox"; then
    echo "Connecting shadowbox to vpn-network with IP ${SHADOWBOX_IP}..."
    if ! docker network connect --ip=${SHADOWBOX_IP} vpn-network shadowbox; then
      log_error "Failed to connect shadowbox to network"
      log_error "Falling back to host networking mode"
      export DOCKER_NETWORK_ISSUES=1
      return 0
    fi
    need_reconnect=true
  fi
  
  # Check if v2ray is connected to network
  if ! docker network inspect vpn-network 2>/dev/null | grep -q "v2ray"; then
    echo "Connecting v2ray to vpn-network with IP ${V2RAY_IP}..."
    if ! docker network connect --ip=${V2RAY_IP} vpn-network v2ray; then
      log_error "Failed to connect v2ray to network"
      log_error "Falling back to host networking mode"
      export DOCKER_NETWORK_ISSUES=1
      return 0
    fi
    need_reconnect=true
  fi
  
  # Restart containers if needed
  if [ "$need_reconnect" = true ]; then
    echo "Network connections changed, restarting containers..."
    docker restart shadowbox v2ray
  fi
  
  echo "Routing setup complete. Both containers connected to vpn-network."
  log_for_sentry "Containers properly connected to vpn-network"
  return 0
}

# Function to restore UFW rules from a backup
function restore_ufw_rules() {
  local BACKUP_DIR="${SHADOWBOX_DIR:-/opt/outline}"
  local LATEST_BACKUP=$(ls -t ${BACKUP_DIR}/ufw_rules_backup_*.txt 2>/dev/null | head -1)
  
  if [[ -z "$LATEST_BACKUP" ]]; then
    echo "No UFW rules backup found in ${BACKUP_DIR}"
    return 1
  fi
  
  echo "Restoring UFW rules from backup: $LATEST_BACKUP"
  
  # Reset UFW to default
  ufw --force reset
  
  # Extract and apply rules from backup
  grep -E "^\[[0-9]+\] " "$LATEST_BACKUP" | while read -r line; do
    # Parse the rule from the backup format
    rule=$(echo "$line" | sed -E 's/^\[[0-9]+\]\s+//' | awk '{print $1, $2, $3}')
    if [[ -n "$rule" ]]; then
      echo "Restoring rule: $rule"
      ufw $rule
    fi
  done
  
  # Enable UFW if it was enabled in the backup
  if grep -q "Status: active" "$LATEST_BACKUP"; then
    echo "Enabling UFW"
    echo "y" | ufw enable
  fi
  
  echo "UFW rules restored from $LATEST_BACKUP"
  return 0
}

function is_valid_port() {
  (( 0 < "$1" && "$1" <= 65535 ))
}

function parse_flags() {
  params=$(getopt -o "" --longoptions hostname:,api-port:,keys-port:,v2ray-port:,dest-site:,fingerprint:,restore-firewall -n $0 -- "$@")
  [[ $? == 0 ]] || exit 1
  eval set -- $params
  declare -g FLAGS_HOSTNAME=""
  declare -gi FLAGS_API_PORT=0  # Default to 0 to use random port
  declare -gi FLAGS_KEYS_PORT=0  # Default to 0 to use random port
  declare -gi FLAGS_V2RAY_PORT=443
  declare -g FLAGS_DEST_SITE="www.microsoft.com:443"
  declare -g FLAGS_FINGERPRINT="chrome"
  declare -g FLAGS_RESTORE_FIREWALL=false

  while [[ "$#" > 0 ]]; do
    local flag=$1
    shift
    case "$flag" in
      --hostname)
        FLAGS_HOSTNAME=${1}
        shift
        ;;
      --api-port)
        FLAGS_API_PORT=${1}
        shift
        if ! is_valid_port $FLAGS_API_PORT; then
          log_error "Invalid value for $flag: $FLAGS_API_PORT"
          exit 1
        fi
        ;;
      --keys-port)
        FLAGS_KEYS_PORT=$1
        shift
        if ! is_valid_port $FLAGS_KEYS_PORT; then
          log_error "Invalid value for $flag: $FLAGS_KEYS_PORT"
          exit 1
        fi
        ;;
      --v2ray-port)
        FLAGS_V2RAY_PORT=$1
        shift
        if ! is_valid_port $FLAGS_V2RAY_PORT; then
          log_error "Invalid value for $flag: $FLAGS_V2RAY_PORT"
          exit 1
        fi
        ;;
      --dest-site)
        FLAGS_DEST_SITE=$1
        shift
        ;;
      --fingerprint)
        FLAGS_FINGERPRINT=$1
        shift
        ;;
      --restore-firewall)
        FLAGS_RESTORE_FIREWALL=true
        ;;
      --)
        break
        ;;
      *) # This should not happen
        log_error "Unsupported flag $flag"
        display_usage
        exit 1
        ;;
    esac
  done
  # Validate ports don't conflict with each other
  if [[ $FLAGS_API_PORT != 0 && $FLAGS_API_PORT == $FLAGS_KEYS_PORT ]]; then
    log_error "--api-port must be different from --keys-port"
    exit 1
  fi
  
  if [[ $FLAGS_API_PORT != 0 && $FLAGS_API_PORT == $FLAGS_V2RAY_PORT ]]; then
    log_error "--api-port must be different from --v2ray-port"
    exit 1
  fi
  
  if [[ $FLAGS_KEYS_PORT != 0 && $FLAGS_KEYS_PORT == $FLAGS_V2RAY_PORT ]]; then
    log_error "--keys-port must be different from --v2ray-port"
    exit 1
  fi
  
  # Export v2ray-related flags as environment variables
  export V2RAY_PORT="$FLAGS_V2RAY_PORT"
  export DEST_SITE="$FLAGS_DEST_SITE"
  export FINGERPRINT="$FLAGS_FINGERPRINT"
  
  return 0
}

# Define global subnet list to ensure consistency across functions
declare -a SUBNET_OPTIONS=(
  "172.18.0.0/24"
  "172.19.0.0/24"
  "172.20.0.0/24"
  "172.21.0.0/24"
  "172.22.0.0/24"
  "10.10.0.0/24"
  "10.20.0.0/24"
  "192.168.90.0/24"
)

function main() {
  trap finish EXIT
  
  # Set default values for critical variables to prevent "unbound variable" errors
  API_PORT=${API_PORT:-0}  # Use 0 to trigger random port generation
  ACCESS_KEY_PORT=${ACCESS_KEY_PORT:-0}  # Use 0 to trigger random port generation
  V2RAY_PORT=${V2RAY_PORT:-443}
  # Make subnet options globally available
  export subnets=("${SUBNET_OPTIONS[@]}")
  
  parse_flags "$@"
  
  if [[ "$FLAGS_RESTORE_FIREWALL" == "true" ]]; then
    # Just restore the firewall rules and exit
    restore_ufw_rules
    exit $?
  else
    # Normal installation
    if ! install_shadowbox; then
      # If installation failed, offer to restart Docker as a last resort
      echo ""
      log_error "Installation failed. This may be due to lingering Docker resources, port conflicts, or permission issues."
      log_error "Check the DEBUG output above to see where the process stopped."
      
      if command_exists systemctl; then
        echo ""
        echo "Do you want to try restarting Docker daemon as a last resort?"
        if confirm "> This will restart the Docker daemon and try again. Would you like to proceed? [Y/n] "; then
          echo "Stopping and starting Docker containers (safer than restarting daemon)..."
          # Only stop containers by name rather than all containers to avoid killing critical system containers
          docker stop shadowbox v2ray watchtower >/dev/null 2>&1 || true
          # Clean up Docker network
          docker network rm vpn-network >/dev/null 2>&1 || true
          sleep 5
          echo "Attempting installation again..."
          
          # Clear any network-specific variables in case they're causing issues
          unset DOCKER_NETWORK_ISSUES
          
          # Try installation again
          if ! install_shadowbox; then
            log_error "Installation failed even after Docker restart. Please check the logs above for errors."
            exit 1
          fi
        else
          log_error "Installation aborted. You may want to restart Docker manually with: sudo systemctl restart docker"
          exit 1
        fi
      else
        log_error "Installation failed. You may want to restart Docker manually if available on your system."
        exit 1
      fi
    fi
  fi
}

# Already defined at the top of the script

main "$@"