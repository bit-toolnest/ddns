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
# 3. Create Config Template (If missing)
# -----------------------------------------------------
if [ ! -f "$CONFIG_DEST" ]; then
    echo "⚠️  Config file not found. Creating template at $CONFIG_DEST..."
    sudo bash -c "cat > $CONFIG_DEST" <<EOF
# Cloudflare DDNS Configuration
CF_API_TOKEN=your_api_token_here
CF_ZONE_ID=your_zone_id_here
CF_DNS_RECORD_ID=your_record_id_here

CF_DNS_NAME=bitone.in
CF_TTL=600
CF_PROXIED=false
EOF
    sudo chmod 600 "$CONFIG_DEST"
    echo "✅ Created config template."
else
    echo "ℹ️  Config file already exists. Skipping creation."
fi

# 3. Reload systemd to recognize the new service
sudo systemctl daemon-reload

# 4. Enable and start the service
sudo systemctl enable cloudflare-ddns.service
sudo systemctl restart cloudflare-ddns.service

# 5. Check status
sudo systemctl status cloudflare-ddns.service --no-pager

echo "🎯 Installation complete!"
echo "View logs anytime with:  sudo journalctl -u cloudflare-ddns.service -f"
