#!/bin/bash
#
# alert.sh - Alert notification script for the integrated VPN solution
# This script sends alerts via various methods (email, SMS, etc.) when issues are detected

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
LOG_DIR="${BASE_DIR}/logs"
CONFIG_FILE="${BASE_DIR}/alert-config.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
ALERT_EMAIL="admin@example.com"
ENABLE_EMAIL=true
ENABLE_SMS=false
ENABLE_WEBHOOK=false
SMS_NUMBER=""
WEBHOOK_URL=""
ALERT_LEVEL="WARNING"  # INFO, WARNING, CRITICAL
ATTACHMENT_FILE=""

# Function to display status messages
log_message() {
    local level="$1"
    local message="$2"
    local color="${NC}"
    
    case "$level" in
        "INFO")
            color="${GREEN}"
            ;;
        "WARNING")
            color="${YELLOW}"
            ;;
        "ERROR")
            color="${RED}"
            ;;
    esac
    
    echo -e "${color}[${level}]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $message" >> "${LOG_DIR}/alerts.log"
}

# Display usage information
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <subject> <message> [attachment_file]

Send alert notifications when issues are detected.

Arguments:
  <subject>              Alert subject/title
  <message>              Alert message content
  [attachment_file]      Optional file to attach to the alert

Options:
  --email EMAIL          Email address to send alerts to (default: ${ALERT_EMAIL})
  --sms NUMBER           Phone number to send SMS alerts to
  --webhook URL          Webhook URL to send alerts to
  --level LEVEL          Alert level: INFO, WARNING, CRITICAL (default: WARNING)
  --help                 Display this help message

Example:
  $(basename "$0") "Disk Space Warning" "Disk usage is at 90%"
  $(basename "$0") --level CRITICAL "Service Down" "v2ray service has crashed"
EOF
}

# Load configuration from file if it exists
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_message "INFO" "Loading configuration from ${CONFIG_FILE}"
        
        # Check if jq is installed
        if command -v jq &> /dev/null; then
            ALERT_EMAIL=$(jq -r '.email // "admin@example.com"' "$CONFIG_FILE")
            ENABLE_EMAIL=$(jq -r '.enable_email // true' "$CONFIG_FILE")
            ENABLE_SMS=$(jq -r '.enable_sms // false' "$CONFIG_FILE")
            ENABLE_WEBHOOK=$(jq -r '.enable_webhook // false' "$CONFIG_FILE")
            SMS_NUMBER=$(jq -r '.sms_number // ""' "$CONFIG_FILE")
            WEBHOOK_URL=$(jq -r '.webhook_url // ""' "$CONFIG_FILE")
        else
            log_message "WARNING" "jq not installed. Using default configuration."
        fi
    else
        log_message "INFO" "No configuration file found. Using default settings."
    fi
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --email)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    log_message "ERROR" "--email requires an email address"
                    exit 1
                fi
                ALERT_EMAIL="$2"
                shift
                ;;
            --sms)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    log_message "ERROR" "--sms requires a phone number"
                    exit 1
                fi
                SMS_NUMBER="$2"
                ENABLE_SMS=true
                shift
                ;;
            --webhook)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    log_message "ERROR" "--webhook requires a URL"
                    exit 1
                fi
                WEBHOOK_URL="$2"
                ENABLE_WEBHOOK=true
                shift
                ;;
            --level)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    log_message "ERROR" "--level requires a value (INFO, WARNING, CRITICAL)"
                    exit 1
                fi
                
                # Validate alert level
                case "$2" in
                    INFO|WARNING|CRITICAL)
                        ALERT_LEVEL="$2"
                        ;;
                    *)
                        log_message "ERROR" "Invalid alert level: $2 (valid options: INFO, WARNING, CRITICAL)"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --help)
                display_usage
                exit 0
                ;;
            -*)
                log_message "ERROR" "Unknown option: $1"
                display_usage
                exit 1
                ;;
            *)
                # Process positional arguments
                if [ -z "${SUBJECT+x}" ]; then
                    SUBJECT="$1"
                elif [ -z "${MESSAGE+x}" ]; then
                    MESSAGE="$1"
                elif [ -z "${ATTACHMENT_FILE+x}" ]; then
                    ATTACHMENT_FILE="$1"
                else
                    log_message "ERROR" "Too many arguments provided"
                    display_usage
                    exit 1
                fi
                ;;
        esac
        shift
    done
    
    # Validate required arguments
    if [ -z "${SUBJECT+x}" ] || [ -z "${MESSAGE+x}" ]; then
        log_message "ERROR" "Subject and message are required"
        display_usage
        exit 1
    fi
}

# Send email alert
send_email_alert() {
    if [ "$ENABLE_EMAIL" != "true" ]; then
        log_message "INFO" "Email alerts are disabled"
        return 0
    fi
    
    log_message "INFO" "Sending email alert to ${ALERT_EMAIL}"
    
    # Add server information to the message
    local server_info="
---
Server: $(hostname -f || hostname)
IP: $(hostname -I | awk '{print $1}')
Date: $(date '+%Y-%m-%d %H:%M:%S')
"
    
    # Check if mail command is available
    if ! command -v mail &> /dev/null; then
        log_message "ERROR" "mail command not found. Install mailutils to enable email alerts."
        return 1
    fi
    
    # Format subject with alert level
    local formatted_subject="[${ALERT_LEVEL}] ${SUBJECT}"
    
    # If attachment file is provided and exists
    if [ -n "$ATTACHMENT_FILE" ] && [ -f "$ATTACHMENT_FILE" ]; then
        log_message "INFO" "Sending email with attachment: ${ATTACHMENT_FILE}"
        echo -e "${MESSAGE}${server_info}" | mail -s "$formatted_subject" -A "$ATTACHMENT_FILE" "$ALERT_EMAIL"
    else
        # Send email without attachment
        echo -e "${MESSAGE}${server_info}" | mail -s "$formatted_subject" "$ALERT_EMAIL"
    fi
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "Email alert sent successfully"
    else
        log_message "ERROR" "Failed to send email alert"
        return 1
    fi
    
    return 0
}

# Send SMS alert
send_sms_alert() {
    if [ "$ENABLE_SMS" != "true" ] || [ -z "$SMS_NUMBER" ]; then
        log_message "INFO" "SMS alerts are disabled or no phone number configured"
        return 0
    fi
    
    log_message "INFO" "Sending SMS alert to ${SMS_NUMBER}"
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_message "ERROR" "curl command not found. Install curl to enable SMS alerts."
        return 1
    fi
    
    # This is a placeholder for SMS sending logic
    # You would typically use an SMS gateway API here
    
    log_message "WARNING" "SMS sending not implemented - this is a placeholder"
    log_message "INFO" "Would send SMS with subject: ${SUBJECT}"
    
    # Example using Twilio API (you would need to set up Twilio credentials)
    # curl -X POST https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json \
    #    --data-urlencode "To=$SMS_NUMBER" \
    #    --data-urlencode "From=$TWILIO_PHONE_NUMBER" \
    #    --data-urlencode "Body=[${ALERT_LEVEL}] ${SUBJECT}" \
    #    -u $TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN
    
    return 0
}

# Send webhook alert
send_webhook_alert() {
    if [ "$ENABLE_WEBHOOK" != "true" ] || [ -z "$WEBHOOK_URL" ]; then
        log_message "INFO" "Webhook alerts are disabled or no webhook URL configured"
        return 0
    fi
    
    log_message "INFO" "Sending webhook alert to ${WEBHOOK_URL}"
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_message "ERROR" "curl command not found. Install curl to enable webhook alerts."
        return 1
    fi
    
    # Format JSON payload
    local json_payload="{\"level\":\"${ALERT_LEVEL}\",\"subject\":\"${SUBJECT}\",\"message\":\"${MESSAGE}\",\"server\":\"$(hostname -f || hostname)\",\"ip\":\"$(hostname -I | awk '{print $1}')\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
    
    # Send webhook request
    curl -s -X POST -H "Content-Type: application/json" -d "$json_payload" "$WEBHOOK_URL" > /dev/null
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "Webhook alert sent successfully"
    else
        log_message "ERROR" "Failed to send webhook alert"
        return 1
    fi
    
    return 0
}

# Log alert to file
log_alert() {
    local alert_file="${LOG_DIR}/alerts_history.log"
    
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}"
    
    # Create alert log entry
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${ALERT_LEVEL}] ${SUBJECT}"
        echo "Message: ${MESSAGE}"
        echo "Server: $(hostname -f || hostname) ($(hostname -I | awk '{print $1}'))"
        echo "--------------------------------------------"
    } >> "$alert_file"
}

# Main function
main() {
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}"
    
    # Start execution
    log_message "INFO" "Alert notification system started"
    
    # Load configuration
    load_config
    
    # Parse command line arguments
    parse_args "$@"
    
    # Log the alert
    log_alert
    
    # Send alerts via all enabled methods
    send_email_alert || true
    send_sms_alert || true
    send_webhook_alert || true
    
    log_message "INFO" "Alert notification completed"
}

# Run main function if arguments provided
if [ $# -eq 0 ]; then
    display_usage
    exit 1
else
    main "$@"
fi