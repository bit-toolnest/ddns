#!/bin/bash
# ==============================================================
# Simple installer for Cloudflare Dynamic DNS Updater service
# Moves script and service file to proper system directories
# ==============================================================

set -e  # Exit on first error

# File locations (source in current directory)
SCRIPT_SRC="./UpdateCloudflareDNS.sh"
SERVICE_SRC="./cloudflare-ddns.service"

# Destination paths
SCRIPT_DEST="/usr/local/bin/UpdateCloudflareDNS.sh"
SERVICE_DEST="/etc/systemd/system/cloudflare-ddns.service"
CONFIG_DEST="/etc/cloudflare-ddns.env"

echo "🚀 Installing Cloudflare DDNS updater..."

# -----------------------------------------------------
# 1. Dependency Check (CRITICAL STEP)
# -----------------------------------------------------
echo "🔍 Checking dependencies..."
MISSING_DEPS=0

for cmd in curl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ ERROR: Required tool '$cmd' is missing."
        MISSING_DEPS=1
    else
        echo "✅ Found '$cmd'"
    fi
done

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo "🛑 Installation Aborted!"
    echo "You must install the missing tools before continuing."
    echo "-----------------------------------------------------"
    echo "👉 For Ubuntu/Debian run:  sudo apt update && sudo apt install curl jq -y"
    echo "👉 For CentOS/RHEL run:    sudo yum install curl jq -y"
    echo "-----------------------------------------------------"
    exit 1
fi

# 1. Move the main script
if [ -f "$SCRIPT_SRC" ]; then
    sudo cp "$SCRIPT_SRC" "$SCRIPT_DEST"
    sudo chmod 700 "$SCRIPT_DEST"
    echo "✅ Moved script to $SCRIPT_DEST"
else
    echo "❌ ERROR: $SCRIPT_SRC not found!"
    exit 1
fi

# 2. Move the service file
if [ -f "$SERVICE_SRC" ]; then
    sudo cp "$SERVICE_SRC" "$SERVICE_DEST"
    sudo chmod 644 "$SERVICE_DEST"
    echo "✅ Moved service file to $SERVICE_DEST"
else
    echo "❌ ERROR: $SERVICE_SRC not found!"
    exit 1
fi

# -----------------------------------------------------
# 3. Create configuration directly in /etc
# -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DEST="/etc/cloudflare-ddns.env"

CF_API_TOKEN="${CF_API_TOKEN:-$(read -rsp 'Enter Cloudflare API Token: ' value; echo "$value"; echo)}"
CF_ZONE_ID="${CF_ZONE_ID:-$(read -rp 'Enter Cloudflare Zone ID: ' value; echo "$value")}"
CF_DNS_NAME="${CF_DNS_NAME:-$(read -rp 'Enter DNS Name [bitone.in]: ' value; echo "${value:-bitone.in}")}"
CF_PROXIED="${CF_PROXIED:-$(read -rp 'Enable Proxy (true/false) [false]: ' value; echo "${value:-false}")}"
CF_TTL="${CF_TTL:-$(read -rp 'Enter DNS TTL [600]: ' value; echo "${value:-600}")}"

echo "📄 Creating $CONFIG_DEST..."

sudo tee "$CONFIG_DEST" > /dev/null <<EOF
# Cloudflare DDNS Configuration
CF_API_TOKEN='$CF_API_TOKEN'
CF_ZONE_ID='$CF_ZONE_ID'
CF_DNS_NAME='$CF_DNS_NAME'
CF_PROXIED='$CF_PROXIED'
CF_TTL='$CF_TTL'
EOF

sudo chmod 600 "$CONFIG_DEST"

# 3. Reload systemd to recognize the new service
sudo systemctl daemon-reload

# 4. Enable and start the service
sudo systemctl enable cloudflare-ddns.service
sudo systemctl restart cloudflare-ddns.service

# 5. Check status
sudo systemctl status cloudflare-ddns.service --no-pager

echo "🎯 Installation complete!"
echo "View logs anytime with:  sudo journalctl -u cloudflare-ddns.service -f"
