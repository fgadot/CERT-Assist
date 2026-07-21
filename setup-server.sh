#!/bin/bash
# Complete one-time Ubuntu 22.04 server setup for certcommand.org
#
# Do NOT run this directly. Use provision.sh from your Mac:
#   ./provision.sh root@alphago.certcommand.org
#
# That script copies all required files here first, then runs this remotely.

set -e

SSH_ALLOWED_IP="${SSH_IP:-47.205.39.149}"
ADMIN_EMAIL="frank@universe-corrupted.com"

echo ""
echo "======================================================"
echo "  CERT Command — Server Setup"
echo "======================================================"
echo ""

# ── 1. Update packages ────────────────────────────────────────────────────────

echo "==> [1/11] Updating packages..."
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# ── 2. UFW firewall ───────────────────────────────────────────────────────────

echo "==> [2/11] Configuring UFW firewall..."
apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$SSH_ALLOWED_IP" to any port 22 proto tcp comment 'SSH admin'
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
echo "    UFW status:"
ufw status verbose

# ── 3. Docker ─────────────────────────────────────────────────────────────────

echo "==> [3/11] Installing Docker..."
apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
docker --version
docker compose version

# ── 4. nginx + certbot ────────────────────────────────────────────────────────

echo "==> [4/11] Installing nginx and certbot..."
apt-get install -y nginx certbot python3-certbot-nginx

# ── 5. fail2ban ───────────────────────────────────────────────────────────────

echo "==> [5/11] Installing fail2ban..."
apt-get install -y fail2ban
cp /tmp/fail2ban-filter-certcommand.conf /etc/fail2ban/filter.d/certcommand-pin.conf
cp /tmp/fail2ban-jail-certcommand.conf   /etc/fail2ban/jail.d/certcommand.conf
systemctl enable fail2ban
systemctl restart fail2ban
echo "    fail2ban status: $(systemctl is-active fail2ban)"

# ── 6. IPsum threat intelligence blocklist ────────────────────────────────────

echo "==> [6/11] Setting up IPsum threat blocklist..."
apt-get install -y ipset

cat > /usr/local/bin/update-ipsum.sh << 'IPSUM'
#!/bin/bash
echo "$(date): Updating IPsum blocklist..."
ipset -q flush ipsum 2>/dev/null || ipset create ipsum hash:ip hashsize 8192
count=0
for ip in $(curl --compressed https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt 2>/dev/null | grep -v "#" | grep -v -E "\s[1-2]$" | cut -f 1); do
    ipset add ipsum $ip 2>/dev/null && ((count++))
done
ipset save ipsum > /etc/ipset-ipsum.conf
echo "$(date): Blocked $count IPs"
IPSUM

chmod +x /usr/local/bin/update-ipsum.sh
echo "    Running initial IPsum update (this takes ~30s)..."
/usr/local/bin/update-ipsum.sh
echo "0 3 * * * root /usr/local/bin/update-ipsum.sh && ufw reload >> /var/log/ipsum-update.log 2>&1" \
    > /etc/cron.d/ipsum-update

# ── 7. App directory structure ────────────────────────────────────────────────

echo "==> [7/11] Creating app directory structure..."
mkdir -p /opt/certcommand
cd /opt/certcommand
for TEAM in sapphire glenn lakewood lorraine bayview; do
    mkdir -p data/$TEAM config/$TEAM
done
mkdir -p public/backend public/county
chown -R 1000:1000 data/
echo "    /opt/certcommand created."

# ── 8. nginx config ───────────────────────────────────────────────────────────

echo "==> [8/11] Deploying nginx config..."
cp /tmp/certcommand.conf /etc/nginx/sites-available/certcommand.conf
ln -sf /etc/nginx/sites-available/certcommand.conf /etc/nginx/sites-enabled/certcommand.conf
rm -f /etc/nginx/sites-enabled/default
echo "    nginx config deployed (skipping test — cert not yet obtained)"

# ── 9. SSL wildcard cert — MUST be run manually in an interactive SSH session ─

echo ""
echo "==> [9/11] SSL cert — SKIPPED (requires interactive terminal)"
echo ""

# ── 10. nginx not started yet — will start after cert is obtained ─────────────

echo "==> [10/11] nginx start deferred — run manually after certbot"

# ── 11. Systemd certcommand service ──────────────────────────────────────────

echo "==> [11/11] Creating certcommand systemd service..."
cat > /etc/systemd/system/certcommand.service << 'EOF'
[Unit]
Description=CERT Command Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/certcommand
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable certcommand

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "======================================================"
echo "  Automated setup complete!"
echo ""
echo "  *** MANUAL STEPS REMAINING — SSH in and run: ***"
echo ""
echo "  1. Get the SSL cert (certbot will pause for DNS TXT record):"
echo "     certbot certonly --manual --preferred-challenges=dns \\"
echo "       -d certcommand.org -d '*.certcommand.org' \\"
echo "       --agree-tos --email $ADMIN_EMAIL"
echo ""
echo "  2. Start nginx:"
echo "     nginx -t && systemctl enable nginx && systemctl restart nginx"
echo ""
echo "  3. Reboot (kernel update is pending):"
echo "     reboot"
echo ""
echo "  4. After reboot, from your Mac:"
echo "     ./build-push.sh root@alphago.certcommand.org"
echo "======================================================"
