#!/bin/bash
# source set_env.sh

# Defaults with override support
export GRADLE_ARGS="${GRADLE_ARGS:---info}"
export EXECUTION_TIMEOUT="${EXECUTION_TIMEOUT:-1800}"
# Cloudflare DDNS Configuration
export CF_API_TOKEN="your_api_token_here"
export CF_ZONE_ID="your_zone_id_here"
# Optional
export CF_DNS_NAME="bitone.in,*.bitone.in"
export CF_PROXIED=false
export CF_TTL=600

echo "Environment variables set:"
echo "  GRADLE_ARGS=$GRADLE_ARGS"
echo "  EXECUTION_TIMEOUT=$EXECUTION_TIMEOUT"



