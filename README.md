# Cloudflare Dynamic DNS Updater (DDNS)

## 📌 Overview

This project provides an automated **Dynamic DNS (DDNS) updater** using **Cloudflare's DNS API**.

Many internet providers assign **dynamic public IP addresses**. When your IP changes, your domain (e.g., `bitone.in`) may stop pointing to your server.

This DDNS setup:

- Uses **GoDaddy** only as the **domain registrar**
- Uses **Cloudflare** as the **DNS provider**
- Detects your current **public IP**
- Updates the A record in **Cloudflare DNS** automatically
- Runs continuously in the background using **systemd**

So your domain always points to your server, even if your ISP changes your IP.

---

## 🧩 How GoDaddy and Cloudflare Work Together

We are intentionally using **two services**:

1. **GoDaddy – Registrar**
   - You bought and own `bitone.in` here.
   - GoDaddy keeps ownership information, renewal, billing, etc.
   - We **do not** use GoDaddy’s DNS API anymore (it’s restricted for small accounts).

2. **Cloudflare – DNS Hosting**
   - Cloudflare hosts the **DNS zone** for `bitone.in`.
   - All DNS queries (like “what is the IP of bitone.in?”) are answered by Cloudflare.
   - Our script talks only to **Cloudflare’s DNS API**, not to GoDaddy.

### 🔁 Link between them

- In GoDaddy, you change the **nameservers** of `bitone.in` from:

  ```text
  ns53.domaincontrol.com
  ns54.domaincontrol.com
to Cloudflare nameservers, for example:

text
Copy code
jose.ns.cloudflare.com
laylah.ns.cloudflare.com
After that, Cloudflare becomes the authoritative DNS for bitone.in.

The domain is still owned at GoDaddy, but DNS is managed at Cloudflare.

This is a very common & recommended setup.

📁 Project Structure
text
Copy code
/
├─ UpdateCloudflareDNS.sh        # Main DDNS updater script
├─ cloudflare-ddns.service       # Systemd service file (runs script at boot)
├─ setup_cloudflare_ddns.sh      # Installer script to install script + service
└─ README.md                     # Documentation
🧱 Dependencies
Required packages (on your Linux server):
bash
Copy code
sudo apt update
sudo apt install curl jq -y
Required Cloudflare items:
You need three things from Cloudflare for your domain (e.g., bitone.in):

API Token – with permission to edit DNS for your zone

Zone ID – identifies the DNS zone (your domain)

DNS Record ID – identifies the specific DNS record (A record) to update

Detailed steps are below.

🌐 Step 1 – Move DNS from GoDaddy to Cloudflare
Do this once per domain.

Sign in to Cloudflare.

Click “Add a site” and enter: bitone.in.

Select the Free plan.

Cloudflare will scan existing DNS records from GoDaddy. Confirm that:

There is an A record for bitone.in (name @).

Cloudflare will show you two nameservers, similar to:

text
Copy code
jose.ns.cloudflare.com
laylah.ns.cloudflare.com
Now sign in to GoDaddy → My Products → bitone.in → DNS.

Find the Nameservers section and click Change.

Choose Custom nameservers and replace:

ns53.domaincontrol.com, ns54.domaincontrol.com
with:

jose.ns.cloudflare.com, laylah.ns.cloudflare.com
(use the exact names given by Cloudflare)

Save the change.

After some minutes, Cloudflare will show the domain as active and your DNS is now handled by Cloudflare.

🔑 Step 2 – Create Cloudflare API Token
In Cloudflare dashboard, click your avatar (top-right) → My Profile.

Go to API Tokens.

Click Create Token.

Either:

Use template: “Edit zone DNS”, or

Create custom token with:

Permissions:
Zone → DNS → Edit

Zone Resources:
Include → Specific zone → bitone.in

Click Create Token.

Copy the token immediately (you won’t see it again!) and store it securely.

This is your CF_API_TOKEN.

🆔 Step 3 – Get Zone ID for Your Domain
Option A – From Cloudflare Dashboard (UI)
Go to Cloudflare → Websites → select bitone.in.

On the Overview page, scroll down to API section.

You will see:

text
Copy code
Zone ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Copy that value → this is your CF_ZONE_ID.

Option B – Using curl (optional)
If you prefer command line:

bash
Copy code
export CF_API_TOKEN="your_cloudflare_token_here"

curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=bitone.in" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json"
In the JSON result, find:

json
Copy code
"result": [
  {
    "id": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "name": "bitone.in",
    ...
  }
]
The id here is your CF_ZONE_ID.

🧾 Step 4 – Get DNS Record ID for the A Record
We want the A record for bitone.in (the root record @).

Option A – From Cloudflare Dashboard
Go to Cloudflare → bitone.in → DNS.

Find the A record:

text
Copy code
Type: A
Name: bitone.in
Content: some IP
Click on that record → in the URL bar or advanced section, Cloudflare sometimes shows the record ID (depends on UI version).

Because the UI sometimes hides the record ID, the curl method is more reliable.

Option B – Using curl (recommended)
bash
Copy code
export CF_API_TOKEN="your_cloudflare_token_here"
export CF_ZONE_ID="your_zone_id_here"

curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=bitone.in" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json"
Look for:

json
Copy code
"result": [
  {
    "id": "yyyyyyyyyyyyyyyyyyyyyyyyyyyy",
    "type": "A",
    "name": "bitone.in",
    "content": "1.2.3.4",
    ...
  }
]
The "id" here is your CF_DNS_RECORD_ID.

⚙️ Step 5 – Create the Cloudflare Env File
Create /etc/cloudflare-ddns.env:

bash
Copy code
sudo nano /etc/cloudflare-ddns.env
Add:

bash
Copy code
CF_API_TOKEN=your_cloudflare_token_here
CF_ZONE_ID=your_zone_id_here
CF_DNS_RECORD_ID=your_dns_record_id_here

CF_DNS_NAME=bitone.in
CF_TTL=600
CF_PROXIED=false
Secure it:

bash
Copy code
sudo chmod 600 /etc/cloudflare-ddns.env
This file makes your configuration persistent and available for systemd and the script.

🚀 Step 6 – Install via setup_cloudflare_ddns.sh
To simplify installation, this project includes an installer script.

1. Make sure all files are in one directory
You should have:

text
Copy code
UpdateCloudflareDNS.sh
cloudflare-ddns.service
setup_cloudflare_ddns.sh
2. Make installer executable
bash
Copy code
chmod +x setup_cloudflare_ddns.sh
chmod +x UpdateCloudflareDNS.sh
3. Run the installer
bash
Copy code
sudo ./setup_cloudflare_ddns.sh
The installer will:

Move UpdateCloudflareDNS.sh to /usr/local/bin/UpdateCloudflareDNS.sh

Move cloudflare-ddns.service to /etc/systemd/system/cloudflare-ddns.service

Reload systemd

Enable and start the cloudflare-ddns.service

At the end, you’ll see the service status.

If the installer script prints errors about missing files, make sure the file names match exactly.

🧪 Step 7 – Verify the DDNS Service
Check status:

bash
Copy code
sudo systemctl status cloudflare-ddns.service
View live logs:

bash
Copy code
sudo journalctl -u cloudflare-ddns.service -f
You should see messages like:

text
Copy code
INFO: Checking Cloudflare DNS for bitone.in (current public IP: X.X.X.X)
SUCCESS: Updated Cloudflare A record for bitone.in to X.X.X.X
Each time your public IP changes, the service will detect it and update the A record in Cloudflare.

🔄 Controlling the Service
Restart after script or config changes:

bash
Copy code
sudo systemctl restart cloudflare-ddns.service
Stop:

bash
Copy code
sudo systemctl stop cloudflare-ddns.service
Disable auto-start:

bash
Copy code
sudo systemctl disable cloudflare-ddns.service
✅ Summary
Domain: registered at GoDaddy

DNS: hosted at Cloudflare

IP: detected via https://api.ipify.org

DNS record: updated via Cloudflare API

Service: runs at boot via cloudflare-ddns.service

Config: stored in /etc/cloudflare-ddns.env

Setup: automated via setup_cloudflare_ddns.sh

This gives you a clean, maintainable, and provider-independent DDNS solution.

markdown
Copy code

If you want, we can also add:

- A small **“Quick Start”** section at the top  
- Or a **Troubleshooting** section with the most common errors (bad token, wrong Zone ID, etc.).
::contentReference[oaicite:0]{index=0}






