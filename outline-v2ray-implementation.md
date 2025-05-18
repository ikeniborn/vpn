# Outline VPN with v2ray VLESS Implementation

This document contains the implementation details for installing Outline VPN with v2ray VLESS protocol masking. The script below removes monitoring and management components from the original Outline installer while adding v2ray VLESS integration.

## Installation Script

```bash
#!/bin/bash
#
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

# Script to install Outline Server with v2ray VLESS protocol masking
# This version removes monitoring and management components for enhanced privacy.

# You may set the following environment variables, overriding their defaults:
# SB_IMAGE: The Outline Server Docker image to install, e.g. quay.io/outline/shadowbox:nightly
# CONTAINER_NAME: Docker instance name for shadowbox (default shadowbox).
#     For multiple instances also change SHADOWBOX_DIR to an other location
#     e.g. CONTAINER_NAME=shadowbox-inst1 SHADOWBOX_DIR=/opt/outline/inst1
# SHADOWBOX_DIR: Directory for persistent Outline Server state.
# V2RAY_CONTAINER_NAME: Docker instance name for v2ray (default v2ray).
# V2RAY_DIR: Directory for persistent v2ray state.
# V2RAY_UUID: UUID for VLESS protocol authentication (auto-generated if not provided).
# V2RAY_WS_PATH: WebSocket path for VLESS protocol (default /ws).
# V2RAY_PORT: Port for v2ray to listen on (default 443).

# Requires curl and docker to be installed

set -euo pipefail

function display_usage() {
  cat <<EOF
Usage: install_server.sh [--hostname <hostname>] [--v2ray-port <port>] [--keys-port <port>]

  --hostname   The hostname to be used for accessing the VPN
  --v2ray-port The port number for v2ray VLESS protocol (default: 443)
  --keys-port  The port number for the access keys
EOF
}

# I/O conventions for this script:
# - Ordinary status messages are printed to STDOUT
# - STDERR is only used in the event of a fatal error
# - Detailed logs are recorded to this FULL_LOG, which is preserved if an error occurred.
# - The most recent error is stored in LAST_ERROR, which is never preserved.
FULL_LOG="$(mktemp -t outline_logXXXXXXXXXX)"
LAST_ERROR="$(mktemp -t outline_last_errorXXXXXXXXXX)"
readonly FULL_LOG LAST_ERROR

function log_command() {
  # Direct STDOUT and STDERR to FULL_LOG, and forward STDOUT.
  # The most recent STDERR output will also be stored in LAST_ERROR.
  "$@" > >(tee -a "${FULL_LOG}") 2> >(tee -a "${FULL_LOG}" > "${LAST_ERROR}")
}

function log_error() {
  local -r ERROR_TEXT="\033[0;31m"  # red
  local -r NO_COLOR="\033[0m"
  echo -e "${ERROR_TEXT}$1${NO_COLOR}"
  echo "$1" >> "${FULL_LOG}"
}

# Pretty prints text to stdout, and also writes to log file if set.
function log_start_step() {
  local -r str="> $*"
  local -ir lineLength=47
  echo -n "${str}"
  local -ir numDots=$(( lineLength - ${#str} - 1 ))
  if (( numDots > 0 )); then
    echo -n " "
    for _ in $(seq 1 "${numDots}"); do echo -n .; done
  fi
  echo -n " "
}

# Prints $1 as the step name and runs the remainder as a command.
# STDOUT will be forwarded. STDERR will be logged silently, and
# revealed only in the event of a fatal error.
function run_step() {
  local -r msg="$1"
  log_start_step "${msg}"
  shift 1
  if log_command "$@"; then
    echo "OK"
  else
    # Propagates the error code
    return
  fi
}

function confirm() {
  echo -n "> $1 [Y/n] "
  local RESPONSE
  read -r RESPONSE
  RESPONSE=$(echo "${RESPONSE}" | tr '[:upper:]' '[:lower:]') || return
  [[ -z "${RESPONSE}" || "${RESPONSE}" == "y" || "${RESPONSE}" == "yes" ]]
}

function command_exists {
  command -v "$@" &> /dev/null
}

# Check to see if docker is installed.
function verify_docker_installed() {
  if command_exists docker; then
    return 0
  fi
  log_error "NOT INSTALLED"
  if ! confirm "Would you like to install Docker? This will run 'curl https://get.docker.com/ | sh'."; then
    exit 0
  fi
  if ! run_step "Installing Docker" install_docker; then
    log_error "Docker installation failed, please visit https://docs.docker.com/install for instructions."
    exit 1
  fi
  log_start_step "Verifying Docker installation"
  command_exists docker
}

function verify_docker_running() {
  local STDERR_OUTPUT
  STDERR_OUTPUT="$(docker info 2>&1 >/dev/null)"
  local -ir RET=$?
  if (( RET == 0 )); then
    return 0
  elif [[ "${STDERR_OUTPUT}" == *"Is the docker daemon running"* ]]; then
    start_docker
    return
  fi
  return "${RET}"
}

function fetch() {
  curl --silent --show-error --fail "$@"
}

function install_docker() {
  (
    # Change umask so that /usr/share/keyrings/docker-archive-keyring.gpg has the right permissions.
    # See https://github.com/Jigsaw-Code/outline-server/issues/951.
    # We do this in a subprocess so the umask for the calling process is unaffected.
    umask 0022
    fetch https://get.docker.com/ | sh
  ) >&2
}

function start_docker() {
  systemctl enable --now docker.service >&2
}

function docker_container_exists() {
  docker ps -a --format '{{.Names}}'| grep --quiet "^$1$"
}

function remove_shadowbox_container() {
  remove_docker_container "${CONTAINER_NAME}"
}

function remove_v2ray_container() {
  remove_docker_container "${V2RAY_CONTAINER_NAME}"
}

function remove_docker_container() {
  docker rm -f "$1" >&2
}

function handle_docker_container_conflict() {
  local -r CONTAINER_NAME="$1"
  local -r EXIT_ON_NEGATIVE_USER_RESPONSE="$2"
  local PROMPT="The container name \"${CONTAINER_NAME}\" is already in use by another container. This may happen when running this script multiple times."
  if [[ "${EXIT_ON_NEGATIVE_USER_RESPONSE}" == 'true' ]]; then
    PROMPT="${PROMPT} We will attempt to remove the existing container and restart it. Would you like to proceed?"
  else
    PROMPT="${PROMPT} Would you like to replace this container? If you answer no, we will proceed with the remainder of the installation."
  fi
  if ! confirm "${PROMPT}"; then
    if ${EXIT_ON_NEGATIVE_USER_RESPONSE}; then
      exit 0
    fi
    return 0
  fi
  if run_step "Removing ${CONTAINER_NAME} container" "remove_${CONTAINER_NAME}_container" ; then
    log_start_step "Restarting ${CONTAINER_NAME}"
    "start_${CONTAINER_NAME}"
    return $?
  fi
  return 1
}

# Set trap which publishes error tag only if there is an error.
function finish {
  local -ir EXIT_CODE=$?
  if (( EXIT_CODE != 0 )); then
    if [[ -s "${LAST_ERROR}" ]]; then
      log_error "\nLast error: $(< "${LAST_ERROR}")" >&2
    fi
    log_error "\nSorry! Something went wrong. If you can't figure this out, please copy and paste all this output into the Outline Manager screen, and send it to us, to see if we can help you." >&2
    log_error "Full log: ${FULL_LOG}" >&2
  else
    rm "${FULL_LOG}"
  fi
  rm "${LAST_ERROR}"
}

function get_random_port {
  local -i num=0  # Init to an invalid value, to prevent "unbound variable" errors.
  until (( 1024 <= num && num < 65536)); do
    num=$(( RANDOM + (RANDOM % 2) * 32768 ));
  done;
  echo "${num}";
}

function create_persisted_state_dir() {
  readonly STATE_DIR="${SHADOWBOX_DIR}/persisted-state"
  mkdir -p "${STATE_DIR}"
  chmod ug+rwx,g+s,o-rwx "${STATE_DIR}"
}

# Generate a UUID for v2ray VLESS authentication
function generate_uuid() {
  if [[ -z "${V2RAY_UUID:-}" ]]; then
    V2RAY_UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
  readonly V2RAY_UUID
}

# Generate a secret key for access to the Management API and store it in a tag.
# 16 bytes = 128 bits of entropy should be plenty for this use.
function safe_base64() {
  # Implements URL-safe base64 of stdin, stripping trailing = chars.
  # Writes result to stdout.
  local url_safe
  url_safe="$(base64 -w 0 - | tr '/+' '_-')"
  echo -n "${url_safe%%=*}"  # Strip trailing = chars
}

function generate_secret_key() {
  SB_API_PREFIX="$(head -c 16 /dev/urandom | safe_base64)"
  readonly SB_API_PREFIX
}

function generate_certificate() {
  # Generate self-signed cert and store it in the persistent state directory.
  local -r CERTIFICATE_NAME="${STATE_DIR}/shadowbox-selfsigned"
  readonly SB_CERTIFICATE_FILE="${CERTIFICATE_NAME}.crt"
  readonly SB_PRIVATE_KEY_FILE="${CERTIFICATE_NAME}.key"
  declare -a openssl_req_flags=(
    -x509 -nodes -days 36500 -newkey rsa:4096
    -subj "/CN=${PUBLIC_HOSTNAME}"
    -keyout "${SB_PRIVATE_KEY_FILE}" -out "${SB_CERTIFICATE_FILE}"
  )
  openssl req "${openssl_req_flags[@]}" >&2
}

function generate_certificate_fingerprint() {
  # Add a tag with the SHA-256 fingerprint of the certificate.
  local CERT_OPENSSL_FINGERPRINT
  CERT_OPENSSL_FINGERPRINT="$(openssl x509 -in "${SB_CERTIFICATE_FILE}" -noout -sha256 -fingerprint)" || return
  # Example format: "BDDBC9A4395CB34E6ECF1843619F07A2090737356367"
  local CERT_HEX_FINGERPRINT
  CERT_HEX_FINGERPRINT="$(echo "${CERT_OPENSSL_FINGERPRINT#*=}" | tr -d :)" || return
  output_config "certSha256:${CERT_HEX_FINGERPRINT}"
}

function join() {
  local IFS="$1"
  shift
  echo "$*"
}

function write_outline_config() {
  local -a config=()
  if (( FLAGS_KEYS_PORT != 0 )); then
    config+=("\"portForNewAccessKeys\": ${FLAGS_KEYS_PORT}")
  fi
  config+=("\"hostname\": \"$(escape_json_string "${PUBLIC_HOSTNAME}")\"")
  echo "{$(join , "${config[@]}")}" > "${STATE_DIR}/shadowbox_server_config.json"
}

function write_v2ray_config() {
  # Create v2ray config with VLESS protocol
  mkdir -p "${V2RAY_DIR}"
  cat > "${V2RAY_DIR}/config.json" << EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  },
  "inbounds": [
    {
      "port": ${V2RAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${V2RAY_UUID}",
            "level": 0
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${V2RAY_WS_PATH}",
          "headers": {
            "Host": "${PUBLIC_HOSTNAME}"
          }
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${SB_CERTIFICATE_FILE}",
              "keyFile": "${SB_PRIVATE_KEY_FILE}"
            }
          ],
          "alpn": ["http/1.1"]
        }
      },
      "tag": "vless-ws-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      },
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    },
    {
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": ${OUTLINE_PORT},
            "method": "${SS_METHOD}",
            "password": "${SS_PASSWORD}"
          }
        ]
      },
      "tag": "shadowsocks-outbound"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "inboundTag": [
          "vless-ws-tls"
        ],
        "outboundTag": "shadowsocks-outbound"
      }
    ]
  },
  "dns": {
    "servers": [
      "1.1.1.1",
      "8.8.8.8",
      "https+local://dns.google/dns-query",
      "localhost"
    ]
  }
}
EOF
}

function start_shadowbox() {
  # Start the shadowbox container
  local -r START_SCRIPT="${STATE_DIR}/start_container.sh"
  cat <<-EOF > "${START_SCRIPT}"
# This script starts the Outline server container ("Shadowbox").
# If you need to customize how the server is run, you can edit this script, then restart with:
#
#     "${START_SCRIPT}"

set -eu

docker stop "${CONTAINER_NAME}" 2> /dev/null || true
docker rm -f "${CONTAINER_NAME}" 2> /dev/null || true

docker_command=(
  docker
  run
  -d
  --name "${CONTAINER_NAME}" --restart always --net host

  # Use log rotation. See https://docs.docker.com/config/containers/logging/configure/.
  --log-driver local

  # The state that is persisted across restarts.
  -v "${STATE_DIR}:${STATE_DIR}"

  # Where the container keeps its persistent state.
  -e "SB_STATE_DIR=${STATE_DIR}"

  # Location of the certificates.
  -e "SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}"
  -e "SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}"

  # Shadowsocks configuration
  -e "PORT=${OUTLINE_PORT}"
  -e "METHOD=${SS_METHOD}"
  -e "PASSWORD=${SS_PASSWORD}"

  # The Outline server image to run.
  "${SB_IMAGE}"
)
"\${docker_command[@]}"
EOF
  chmod +x "${START_SCRIPT}"
  
  # Execute the start script
  local STDERR_OUTPUT
  STDERR_OUTPUT="$({ "${START_SCRIPT}" >/dev/null; } 2>&1)" && return
  readonly STDERR_OUTPUT
  log_error "FAILED"
  if docker_container_exists "${CONTAINER_NAME}"; then
    handle_docker_container_conflict "${CONTAINER_NAME}" true
    return
  else
    log_error "${STDERR_OUTPUT}"
    return 1
  fi
}

function start_v2ray() {
  # Start the v2ray container
  local -r START_SCRIPT="${V2RAY_DIR}/start_container.sh"
  cat <<-EOF > "${START_SCRIPT}"
# This script starts the v2ray container.
# If you need to customize how the server is run, you can edit this script, then restart with:
#
#     "${START_SCRIPT}"

set -eu

docker stop "${V2RAY_CONTAINER_NAME}" 2> /dev/null || true
docker rm -f "${V2RAY_CONTAINER_NAME}" 2> /dev/null || true

docker_command=(
  docker
  run
  -d
  --name "${V2RAY_CONTAINER_NAME}" --restart always --net host

  # Use log rotation
  --log-driver local

  # v2ray configuration
  -v "${V2RAY_DIR}/config.json:/etc/v2ray/config.json:ro"
  
  # Certificate access
  -v "${SB_CERTIFICATE_FILE}:${SB_CERTIFICATE_FILE}:ro"
  -v "${SB_PRIVATE_KEY_FILE}:${SB_PRIVATE_KEY_FILE}:ro"

  # Create log directory
  -v "${V2RAY_DIR}/logs:/var/log/v2ray"

  # The v2ray image to run
  "v2fly/v2fly-core:latest"
)
"\${docker_command[@]}"
EOF
  chmod +x "${START_SCRIPT}"
  
  # Execute the start script
  local STDERR_OUTPUT
  STDERR_OUTPUT="$({ "${START_SCRIPT}" >/dev/null; } 2>&1)" && return
  readonly STDERR_OUTPUT
  log_error "FAILED"
  if docker_container_exists "${V2RAY_CONTAINER_NAME}"; then
    handle_docker_container_conflict "${V2RAY_CONTAINER_NAME}" true
    return
  else
    log_error "${STDERR_OUTPUT}"
    return 1
  fi
}

function output_config() {
  echo "$@" >> "${ACCESS_CONFIG}"
}

function check_firewall() {
  if ! fetch --max-time 5 --cacert "${SB_CERTIFICATE_FILE}" "https://${PUBLIC_HOSTNAME}:${V2RAY_PORT}${V2RAY_WS_PATH}" >/dev/null; then
     log_error "BLOCKED"
     FIREWALL_STATUS="\
You won't be able to access it externally, despite your server being correctly
set up, because there's a firewall (in this machine, your router or cloud
provider) that is preventing incoming connections to port ${V2RAY_PORT}."
  else
    FIREWALL_STATUS="\
If you have connection problems, it may be that your router or cloud provider
blocks inbound connections, even though your machine seems to allow them."
  fi
  FIREWALL_STATUS="\
${FIREWALL_STATUS}

Make sure to open the following ports on your firewall, router or cloud provider:
- v2ray port ${V2RAY_PORT}, for both TCP and UDP
"
}

function set_hostname() {
  # These are URLs that return the client's apparent IP address.
  # We have more than one to try in case one starts failing
  local -ar urls=(
    'https://icanhazip.com/'
    'https://ipinfo.io/ip'
    'https://domains.google.com/checkip'
  )
  for url in "${urls[@]}"; do
    PUBLIC_HOSTNAME="$(fetch --ipv4 "${url}")" && return
  done
  echo "Failed to determine the server's IP address. Try using --hostname <server IP>." >&2
  return 1
}

function install_vpn() {
  local MACHINE_TYPE
  MACHINE_TYPE="$(uname -m)"
  if [[ "${MACHINE_TYPE}" != "x86_64" ]]; then
    log_error "Unsupported machine type: ${MACHINE_TYPE}. Please run this script on a x86_64 machine"
    exit 1
  fi

  # Make sure we don't leak readable files to other users.
  umask 0007

  export CONTAINER_NAME="${CONTAINER_NAME:-shadowbox}"
  export V2RAY_CONTAINER_NAME="${V2RAY_CONTAINER_NAME:-v2ray}"

  run_step "Verifying that Docker is installed" verify_docker_installed
  run_step "Verifying that Docker daemon is running" verify_docker_running

  # Create Outline directory
  export SHADOWBOX_DIR="${SHADOWBOX_DIR:-/opt/outline}"
  mkdir -p "${SHADOWBOX_DIR}"
  chmod u+s,ug+rwx,o-rwx "${SHADOWBOX_DIR}"

  # Create v2ray directory
  export V2RAY_DIR="${V2RAY_DIR:-/opt/v2ray}"
  mkdir -p "${V2RAY_DIR}"
  chmod u+s,ug+rwx,o-rwx "${V2RAY_DIR}"

  # Set ports
  export V2RAY_PORT="${FLAGS_V2RAY_PORT}"
  if (( V2RAY_PORT == 0 )); then
    V2RAY_PORT=${SB_V2RAY_PORT:-443}  # Default to HTTPS port
  fi
  readonly V2RAY_PORT

  # Set Outline port
  export OUTLINE_PORT=${FLAGS_KEYS_PORT}
  if (( OUTLINE_PORT == 0 )); then
    OUTLINE_PORT=$(get_random_port)
  fi
  readonly OUTLINE_PORT

  # Set WebSocket path
  export V2RAY_WS_PATH="${V2RAY_WS_PATH:-/ws}"
  readonly V2RAY_WS_PATH

  # Set Shadowsocks method and password
  export SS_METHOD="${SS_METHOD:-chacha20-ietf-poly1305}"
  if [[ -z "${SS_PASSWORD:-}" ]]; then
    SS_PASSWORD="$(head -c 16 /dev/urandom | safe_base64)"
  fi
  readonly SS_METHOD SS_PASSWORD

  readonly ACCESS_CONFIG="${ACCESS_CONFIG:-${SHADOWBOX_DIR}/access.txt}"
  readonly SB_IMAGE="${SB_IMAGE:-shadowsocks/shadowsocks-libev:latest}"

  PUBLIC_HOSTNAME="${FLAGS_HOSTNAME:-${SB_PUBLIC_IP:-}}"
  if [[ -z "${PUBLIC_HOSTNAME}" ]]; then
    run_step "Setting PUBLIC_HOSTNAME to external IP" set_hostname
  fi
  readonly PUBLIC_HOSTNAME

  # If $ACCESS_CONFIG is already populated, make a backup before clearing it.
  if [[ -s "${ACCESS_CONFIG}" ]]; then
    cp "${ACCESS_CONFIG}" "${ACCESS_CONFIG}.bak" && true > "${ACCESS_CONFIG}"
  fi

  # Make a directory for persistent state
  run_step "Creating persistent state dir" create_persisted_state_dir
  run_step "Generating UUID for v2ray" generate_uuid
  run_step "Generating secret key" generate_secret_key
  run_step "Generating TLS certificate" generate_certificate
  run_step "Generating SHA-256 certificate fingerprint" generate_certificate_fingerprint
  run_step "Writing Outline config" write_outline_config
  run_step "Writing v2ray config" write_v2ray_config

  run_step "Starting Outline VPN" start_shadowbox
  run_step "Starting v2ray with VLESS" start_v2ray

  FIREWALL_STATUS=""
  run_step "Checking host firewall" check_firewall

  # Output the connection information
  cat <<END_OF_SERVER_OUTPUT

CONGRATULATIONS! Your Outline VPN with v2ray VLESS masking is up and running.

To connect using v2ray with VLESS protocol:

Server:   ${PUBLIC_HOSTNAME}
Port:     ${V2RAY_PORT}
UUID:     ${V2RAY_UUID}
Protocol: VLESS
TLS:      YES
Network:  WebSocket
Path:     ${V2RAY_WS_PATH}
TLS Host: ${PUBLIC_HOSTNAME}

${FIREWALL_STATUS}
END_OF_SERVER_OUTPUT
} # end of install_vpn

function is_valid_port() {
  (( 0 < "$1" && "$1" <= 65535 ))
}

function escape_json_string() {
  local input=$1
  for ((i = 0; i < ${#input}; i++)); do
    local char="${input:i:1}"
    local escaped="${char}"
    case "${char}" in
      $'"' ) escaped="\\\"";;
      $'\\') escaped="\\\\";;
      *)
        if [[ "${char}" < $'\x20' ]]; then
          case "${char}" in
            $'\b') escaped="\\b";;
            $'\f') escaped="\\f";;
            $'\n') escaped="\\n";;
            $'\r') escaped="\\r";;
            $'\t') escaped="\\t";;
            *) escaped=$(printf "\u%04X" "'${char}")
          esac
        fi;;
    esac
    echo -n "${escaped}"
  done
}

function parse_flags() {
  local params
  params="$(getopt --longoptions hostname:,v2ray-port:,keys-port: -n "$0" -- "$0" "$@")"
  eval set -- "${params}"

  while (( $# > 0 )); do
    local flag="$1"
    shift
    case "${flag}" in
      --hostname)
        FLAGS_HOSTNAME="$1"
        shift
        ;;
      --v2ray-port)
        FLAGS_V2RAY_PORT=$1
        shift
        if ! is_valid_port "${FLAGS_V2RAY_PORT}"; then
          log_error "Invalid value for ${flag}: ${FLAGS_V2RAY_PORT}" >&2
          exit 1
        fi
        ;;
      --keys-port)
        FLAGS_KEYS_PORT=$1
        shift
        if ! is_valid_port "${FLAGS_KEYS_PORT}"; then
          log_error "Invalid value for ${flag}: ${FLAGS_KEYS_PORT}" >&2
          exit 1
        fi
        ;;
      --)
        break
        ;;
      *) # This should not happen
        log_error "Unsupported flag ${flag}" >&2
        display_usage >&2
        exit 1
        ;;
    esac
  done
  if (( FLAGS_V2RAY_PORT != 0 && FLAGS_V2RAY_PORT == FLAGS_KEYS_PORT )); then
    log_error "--v2ray-port must be different from --keys-port" >&2
    exit 1
  fi
  return 0
}

function main() {
  trap finish EXIT
  declare FLAGS_HOSTNAME=""
  declare -i FLAGS_V2RAY_PORT=0
  declare -i FLAGS_KEYS_PORT=0
  parse_flags "$@"
  install_vpn
}

main "$@"
```

## Usage Instructions

After implementing this script, it can be used with the following commands:

1. **Basic installation (uses default options):**
   ```bash
   ./outline-v2ray-install.sh
   ```

2. **Custom hostname and ports:**
   ```bash
   ./outline-v2ray-install.sh --hostname example.com --v2ray-port 443 --keys-port 8388
   ```

3. **Environment variable customization:**
   ```bash
   SS_METHOD=aes-256-gcm SS_PASSWORD=myCustomPassword ./outline-v2ray-install.sh
   ```

## Implementation Notes

1. **Removed Components:**
   - Watchtower container
   - Management API and web interface
   - All monitoring components (Prometheus, Alertmanager, Grafana)

2. **Key Additions:**
   - v2ray VLESS protocol integration
   - WebSocket transport for traffic masking
   - TLS encryption for secure communications
   - Automatic UUID generation
   - Direct routing between v2ray and Outline VPN

3. **Security Enhancements:**
   - No management API exposed
   - Minimal attack surface
   - Strong default encryption

4. **Client Configuration:**
   - The output provides all necessary information for connecting with v2ray VLESS clients
   - Compatible with v2ray, v2rayNG, Qv2ray, and other clients

## Next Steps

After implementing this script:

1. Switch to Code mode to implement the actual installation script
2. Test the implementation on a clean server
3. Create additional documentation for client configuration if needed