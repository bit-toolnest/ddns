#!/usr/bin/env bash
#
# Cloudflare Dynamic DNS Updater
# Requires env vars:
#   CF_API_TOKEN      - Cloudflare API token (Zone DNS:Edit for bitone.in)
#   CF_ZONE_ID        - Cloudflare Zone ID for bitone.in
#
# Optional env vars:
#   CF_DNS_NAME       - DNS name, e.g. bitone.in,*.bitone.in,api.bitone.in" (default: "bitone.in")
#   CF_TTL            - TTL in seconds (default: 600)
#   CF_PROXIED        - "true" or "false" (default: "false")
# Ensure Cloudflare DDNS config is in /etc

LOCAL_ENV_FILE="$(dirname "$0")/cloudflare-ddns.env"
SYSTEM_ENV_FILE="/etc/cloudflare-ddns.env"

if [ -f "$LOCAL_ENV_FILE" ] && [ ! -f "$SYSTEM_ENV_FILE" ]; then
  echo "INFO: Moving local cloudflare-ddns.env to /etc/"
  cp "$LOCAL_ENV_FILE" "$SYSTEM_ENV_FILE"
fi

# Load Cloudflare DDNS environment file if present
ENV_FILE="$SYSTEM_ENV_FILE"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

set -euo pipefail

########################################
#          CONFIGURATION               #
########################################

CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-}"

CF_DNS_NAME="${CF_DNS_NAME:-bitone.in}"
TTL="${CF_TTL:-600}"
CF_PROXIED="${CF_PROXIED:-false}"
IFS=',' read -r -a DNS_NAMES <<< "$CF_DNS_NAME"

# Check interval
CHECK_INTERVAL_SECONDS=300  # how often to check the IP (in seconds)

# Log file
LOG_FILE="/var/log/cloudflare-ddns.log"

# For logging only
DOMAIN="${DNS_NAMES[0]}"

########################################
#          HELPER FUNCTIONS            #
########################################

log() {
    # Log with fresh timestamp each time
    local now
    now=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$now $1" >> "$LOG_FILE"
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' not found. Please install it." >&2
        exit 1
    fi
}

validate_ip() {
    # Basic IPv4 validation
    local ip="$1"

    # Simple regex check
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Each octet <= 255
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    for octet in "$o1" "$o2" "$o3" "$o4"; do
        if (( octet < 0 || octet > 255 )); then
            return 1
        fi
    done

    return 0
}

get_public_ip() {
    # List of reliable IP echo services
    local urls=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )

    for url in "${urls[@]}"; do
        # Try fetching IP with 5s timeout
        local ip
        ip=$(curl -4 -s --max-time 5 "$url" || true)
        
        # Trim whitespace
        ip=$(echo "$ip" | xargs)

        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

get_record_id() {

    local dns_name="$1"

    CF_GET_RECORD_RESPONSE=$(curl -sS -m 15 \
        -w "HTTPSTATUS:%{http_code}" \
        -X GET "${CF_API_BASE}/zones/${CF_ZONE_ID}/dns_records?type=A&name=${dns_name}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" || true)

    GET_RECORD_BODY="${CF_GET_RECORD_RESPONSE%HTTPSTATUS:*}"
    GET_RECORD_STATUS="${CF_GET_RECORD_RESPONSE##*HTTPSTATUS:}"

    if [[ -z "$GET_RECORD_STATUS" || "$GET_RECORD_STATUS" == "$CF_GET_RECORD_RESPONSE" ]]; then
        log "ERROR: Failed to get Cloudflare record ID for ${dns_name} (no HTTP status). Raw response: ${CF_GET_RECORD_RESPONSE}"
        return 1
    fi

    if [[ "$GET_RECORD_STATUS" != "200" ]]; then
        log "ERROR: Cloudflare record lookup returned HTTP ${GET_RECORD_STATUS}. Body: ${GET_RECORD_BODY}"
        return 1
    fi

    CF_GET_RECORD_SUCCESS=$(echo "$GET_RECORD_BODY" | jq -r '.success // false' 2>/dev/null || echo "false")

    if [[ "$CF_GET_RECORD_SUCCESS" != "true" ]]; then
        ERRORS=$(echo "$GET_RECORD_BODY" | jq -c '.errors // []' 2>/dev/null || echo "[]")
        log "ERROR: Cloudflare record lookup success=false. Errors: ${ERRORS}"
        return 1
    fi

    RECORD_ID=$(echo "$GET_RECORD_BODY" | jq -r '.result[0].id // empty' 2>/dev/null || echo "")

    if [[ -z "$RECORD_ID" ]]; then
        log "ERROR: No DNS record ID found for ${dns_name}"
        return 1
    fi

    echo "$RECORD_ID"
}

########################################
#          INITIAL CHECKS              #
########################################

# Required env vars
if [[ -z "$CF_API_TOKEN" || -z "$CF_ZONE_ID" ]]; then
    echo "ERROR: CF_API_TOKEN and CF_ZONE_ID must be set as environment variables." >&2
    exit 1
fi

# Check required tools
require_command curl
require_command jq

# Ensure we can write log file
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
    exit 1
fi

log "===== Starting Cloudflare DDNS updater for ${DOMAIN} ====="

# Cache current IP to avoid unnecessary API calls
CURRENT_IP=""

CF_API_BASE="https://api.cloudflare.com/client/v4"

########################################
#               MAIN LOOP              #
########################################

while true; do
# 1) Fetch current public IP using the ROBUST function
    if ! NEW_IP=$(get_public_ip); then
        log "ERROR: Could not determine public IP from any provider."
        sleep 60 # Retry sooner if internet is down
        continue
    fi

    if [[ -z "${NEW_IP}" ]]; then
        log "ERROR: Could not determine current public IP (empty response)."
        sleep "$CHECK_INTERVAL_SECONDS"
        continue
    fi

    if ! validate_ip "$NEW_IP"; then
        log "ERROR: Received invalid IP address from ipify: ${NEW_IP}"
        sleep "$CHECK_INTERVAL_SECONDS"
        continue
    fi

    # If our cached IP matches, no need to hit Cloudflare
    if [[ "$NEW_IP" == "$CURRENT_IP" ]]; then
        log "INFO: Public IP unchanged (${NEW_IP}), no update required."
        sleep "$CHECK_INTERVAL_SECONDS"
        continue
    fi

    # 3) Update Cloudflare record
    log "INFO: Updating Cloudflare A record for ${DOMAIN} with ${NEW_IP}"

    for DNS_NAME in "${DNS_NAMES[@]}"; do
        DNS_NAME="$(echo "$DNS_NAME" | xargs)"

        DOMAIN="$DNS_NAME"

        log "INFO: Updating Cloudflare A record for ${DOMAIN} to ${NEW_IP}"

        CF_DNS_RECORD_ID=$(get_record_id "$DNS_NAME")

        if [[ -z "$CF_DNS_RECORD_ID" ]]; then
            log "ERROR: Skipping ${DNS_NAME}, record ID not found."
            continue
        fi

        JSON_PAYLOAD=$(jq -n \
            --arg type "A" \
            --arg name "$DNS_NAME" \
            --arg content "$NEW_IP" \
            --argjson ttl "$TTL" \
            --argjson proxied "$([[ "$CF_PROXIED" == "true" ]] && echo true || echo false)" \
            '{type:$type, name:$name, content:$content, ttl:$ttl, proxied:$proxied}')

        CF_UPDATE_RESPONSE=$(curl -sS -m 15 \
            -w "HTTPSTATUS:%{http_code}" \
            -X PUT "${CF_API_BASE}/zones/${CF_ZONE_ID}/dns_records/${CF_DNS_RECORD_ID}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$JSON_PAYLOAD" || true)

        UPDATE_BODY="${CF_UPDATE_RESPONSE%HTTPSTATUS:*}"
        UPDATE_STATUS="${CF_UPDATE_RESPONSE##*HTTPSTATUS:}"

        if [[ -z "$UPDATE_STATUS" || "$UPDATE_STATUS" == "$CF_UPDATE_RESPONSE" ]]; then
            log "ERROR: Failed to update Cloudflare (no HTTP status). Raw response: ${CF_UPDATE_RESPONSE}"
            continue
        fi

        if [[ "$UPDATE_STATUS" != "200" ]]; then
            log "ERROR: Cloudflare PUT returned HTTP ${UPDATE_STATUS}. Body: ${UPDATE_BODY}"
            continue
        fi

        CF_UPDATE_SUCCESS=$(echo "$UPDATE_BODY" | jq -r '.success // false' 2>/dev/null || echo "false")

        if [[ "$CF_UPDATE_SUCCESS" == "true" ]]; then
            log "SUCCESS: Updated Cloudflare A record for ${DOMAIN} to ${NEW_IP}"
            CURRENT_IP="$NEW_IP"
        else
            ERRORS=$(echo "$UPDATE_BODY" | jq -c '.errors // []' 2>/dev/null || echo "[]")
            log "ERROR: Cloudflare update success=false. Errors: ${ERRORS}"
        fi

    done


    # 4) Sleep before next iteration
    sleep "$CHECK_INTERVAL_SECONDS"
done
