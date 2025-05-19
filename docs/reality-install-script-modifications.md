# Installation Script Modifications for VLESS-Reality

This document outlines specific code changes needed in the installation script to support VLESS-Reality.

## 1. New Command Line Parameters

Add the following parameters to the `display_usage()` function:

```bash
Usage: install_server.sh [--hostname <hostname>] [--v2ray-port <port>] [--keys-port <port>] [--fix-permissions]
                        [--dest-site <domain:port>] [--fingerprint <type>]

  --hostname        The hostname to be used for accessing the VPN
  --v2ray-port      The port number for v2ray VLESS protocol (default: 443)
  --keys-port       The port number for the access keys
  --fix-permissions Only fix permissions for existing installation
  --dest-site       The destination site to mimic (default: www.microsoft.com:443)
  --fingerprint     TLS fingerprint to simulate (default: chrome)
  --help            Display this help message
```

## 2. Add Reality Keypair Generation

Replace the certificate generation function with:

```bash
function generate_reality_keypair() {
  # Generate reality keypair for VLESS Reality
  mkdir -p "${V2RAY_DIR}"
  
  # Use docker to generate the keypair since it has xray installed
  local PRIVATE_KEY_OUTPUT
  PRIVATE_KEY_OUTPUT=$(docker run --rm "${V2RAY_IMAGE}" xray x25519)
  
  # Extract private and public keys
  REALITY_PRIVATE_KEY=$(echo "$PRIVATE_KEY_OUTPUT" | grep "Private key:" | cut -d' ' -f3)
  REALITY_PUBLIC_KEY=$(echo "$PRIVATE_KEY_OUTPUT" | grep "Public key:" | cut -d' ' -f3)
  
  # Save keys to file for reference
  echo "Private key: ${REALITY_PRIVATE_KEY}" > "${V2RAY_DIR}/reality_keypair.txt"
  echo "Public key: ${REALITY_PUBLIC_KEY}" >> "${V2RAY_DIR}/reality_keypair.txt"
  chmod 600 "${V2RAY_DIR}/reality_keypair.txt"
  
  # Generate short ID if not provided
  if [[ -z "${REALITY_SHORTID:-}" ]]; then
    REALITY_SHORTID=$(openssl rand -hex 8)
    echo "Short ID: ${REALITY_SHORTID}" >> "${V2RAY_DIR}/reality_keypair.txt"
  fi
  
  readonly REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORTID
}
```

## 3. Update V2Ray Configuration Function

Replace the `write_v2ray_config()` function with:

```bash
function write_v2ray_config() {
  # Create v2ray config with VLESS Reality protocol
  mkdir -p "${V2RAY_DIR}"
  
  # Check if a directory exists at the config.json location and remove it
  if [[ -d "${V2RAY_DIR}/config.json" ]]; then
    rm -rf "${V2RAY_DIR}/config.json"
  fi
  
  # Parse destination site
  local DEST_DOMAIN
  local DEST_PORT
  IFS=':' read -r DEST_DOMAIN DEST_PORT <<< "${REALITY_DEST_SITE}"
  if [[ -z "$DEST_PORT" ]]; then
    DEST_PORT="443"  # Default to 443 if not specified
  fi
  
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
            "flow": "xtls-rprx-vision",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST_SITE}",
          "serverNames": ["${DEST_DOMAIN}"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORTID}"],
          "fingerprint": "${REALITY_FINGERPRINT}"
        }
      },
      "tag": "vless-reality"
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
            "address": "${CONTAINER_NAME}",
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
          "vless-reality"
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
  # Ensure the config file has proper permissions for the container to read
  chmod 644 "${V2RAY_DIR}/config.json"
}
```

## 4. Update Parse Flags Function

Add support for the new command-line parameters:

```bash
function parse_flags() {
  local params
  params="$(getopt --longoptions hostname:,v2ray-port:,keys-port:,fix-permissions,dest-site:,fingerprint:,help -n "$0" -- "$0" "$@")"
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
      --dest-site)
        FLAGS_DEST_SITE="$1"
        shift
        ;;
      --fingerprint)
        FLAGS_FINGERPRINT="$1"
        shift
        ;;
      --fix-permissions)
        FLAGS_FIX_PERMISSIONS=true
        ;;
      --help)
        display_usage
        exit 0
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
```

## 5. Update Firewall Check Function

Since we can't use the same method to check the firewall with Reality:

```bash
function check_firewall() {
  # For Reality, we can't check using curl as we did with TLS+WebSocket
  # Instead, we'll just check if the port is open
  if ss -tuln | grep -q ":${V2RAY_PORT} "; then
    echo "Port ${V2RAY_PORT} is open"
  else
    log_error "BLOCKED"
    FIREWALL_STATUS="\
You won't be able to access it externally, despite your server being correctly
set up, because there's a firewall (in this machine, your router or cloud
provider) that is preventing incoming connections to port ${V2RAY_PORT}."
  fi
  
  FIREWALL_STATUS="\
${FIREWALL_STATUS}

Make sure to open the following ports on your firewall, router or cloud provider:
- v2ray port ${V2RAY_PORT}, for both TCP and UDP
"
}
```

## 6. Add New Environment Variables

Add these variables at the installation function:

```bash
# Set Reality parameters
export REALITY_DEST_SITE="${FLAGS_DEST_SITE:-${REALITY_DEST_SITE:-www.microsoft.com:443}}"
export REALITY_FINGERPRINT="${FLAGS_FINGERPRINT:-${REALITY_FINGERPRINT:-chrome}}"
readonly REALITY_DEST_SITE REALITY_FINGERPRINT
```

## 7. Update Server Output

Modify the connection output information:

```bash
cat <<END_OF_SERVER_OUTPUT

CONGRATULATIONS! Your Outline VPN with v2ray VLESS Reality is up and running on ${MACHINE_TYPE} architecture.

To connect using v2ray with VLESS Reality protocol:

Server:       ${PUBLIC_HOSTNAME}
Port:         ${V2RAY_PORT}
UUID:         ${V2RAY_UUID}
Protocol:     VLESS
Flow:         xtls-rprx-vision
Security:     Reality
Dest:         ${REALITY_DEST_SITE}
SNI:          ${REALITY_DEST_SITE%%:*}
Fingerprint:  ${REALITY_FINGERPRINT}
ShortID:      ${REALITY_SHORTID}
PublicKey:    ${REALITY_PUBLIC_KEY}

${FIREWALL_STATUS}
END_OF_SERVER_OUTPUT