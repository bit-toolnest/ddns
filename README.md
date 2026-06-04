# Cloudflare Dynamic DNS Updater

A lightweight, automated Dynamic DNS (DDNS) updater using **Cloudflare's DNS API**.

If your ISP assigns you a dynamic public IP address, this tool ensures your domain (e.g., `bitone.in`) always points to your home server automatically. It runs in the background as a systemd service.

---

## 📋 Prerequisites

Before installing, ensure you have:
1. **A Domain Name** (e.g., `bitone.in`) using **Cloudflare Nameservers**.
2. **Linux Server** (Debian/Ubuntu/Raspberry Pi) with `curl` and `jq` installed.
3. **Root/Sudo Access** to the server.

### Install Dependencies
```bash
sudo apt update && sudo apt install curl jq -y
```
⚙️ Configuration Guide
You need three key pieces of information from Cloudflare to configure this tool.

1. Get Your API Credentials
A. API Token

Log in to Cloudflare Dashboard.

Go to My Profile > API Tokens > Create Token.

Use the Edit zone DNS template.

Under Zone Resources, select Include > Specific zone > your domain.

Copy the token immediately.

B. Zone ID

Go to your domain's dashboard in Cloudflare.

On the Overview page, scroll down to the bottom right sidebar.

Copy the Zone ID.

C. DNS Record ID

Use the API to fetch the record ID for your A record:

```bash
curl -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=bitone.in" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json"
```
Copy the "id" field from the JSON response.

🚀 Installation
1. Clone & Prepare
Download the repository files to your server. Ensure you have the following files in your folder:

UpdateCloudflareDNS.sh

cloudflare-ddns.service

install.sh

2. Run the Installer
The installer will move scripts to the system folder, copy the config file, and set up the service.

```bash
chmod +x install.sh
sudo ./install.sh
3. Edit Configuration
The installer creates /etc/cloudflare-ddns.env. You must edit this file to add your API keys.
```

```bash
sudo nano /etc/cloudflare-ddns.env
```
Fill in your details (quotes required for tokens and IDs):

```ini
# Cloudflare DDNS Configuration
CF_API_TOKEN="your_token_here"
CF_ZONE_ID="your_zone_id_here"
```

# Optional
CF_DNS_NAME="bitone.in,*.bitone.in"
CF_TTL=600
CF_PROXIED=false
4. Start the Service
Once configured, restart the service to apply changes.

```bash
sudo systemctl restart cloudflare-ddns.service
```
🔍 Verification & Logs
Check if the service is running correctly:

```bash
# Check status
sudo systemctl status cloudflare-ddns.service
```

# View live logs
sudo journalctl -u cloudflare-ddns.service -f
Success Output Example:

```Code
INFO: Checking Cloudflare DNS for bitone.in (current public IP: 203.0.113.1)
SUCCESS: Updated Cloudflare A record for bitone.in to 203.0.113.1
```
🗑️ Uninstall
To remove the script, service, and logs:

```bash
chmod +x uninstall.sh
sudo ./uninstall.sh
```
🧠 How It Works
IP Detection: The script checks your public IP using reliable providers (ipify, icanhazip, etc.).

Comparison: It compares your current IP with the IP stored in your Cloudflare DNS record.

Update: If (and only if) the IPs do not match, it sends an API request to Cloudflare to update the record.

Loop: The systemd service runs this check every 5 minutes (configurable).
