#!/bin/bash
# One-time Ubuntu 22.04 server setup for certassist.us
#
# Run this ON the Ubuntu server as root:
#   bash setup-server.sh
#
# Prerequisites:
#   - Ubuntu 22.04 LTS droplet
#   - DNS A records pointing *.certassist.us → this server's IP
#   - You've already SSH'd in as root

set -e

echo "==> Installing Docker..."
apt-get update -q
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "==> Installing nginx and certbot..."
apt-get install -y nginx certbot python3-certbot-nginx

echo "==> Creating app directory structure..."
mkdir -p /opt/certassist
cd /opt/certassist

for TEAM in sapphire glenn lakewood lorraine bayview; do
    mkdir -p data/$TEAM config/$TEAM
done

echo "==> Placing nginx config..."
cp /tmp/certassist.conf /etc/nginx/sites-available/certassist.conf
ln -sf /etc/nginx/sites-available/certassist.conf /etc/nginx/sites-enabled/certassist.conf
rm -f /etc/nginx/sites-enabled/default

echo "==> Testing nginx config..."
nginx -t

echo "==> Obtaining SSL cert (wildcard via certbot)..."
echo ""
echo "  NOTE: certbot will ask you to add a DNS TXT record for _acme-challenge.certassist.us"
echo "  Do that in your DNS provider, then press Enter in certbot when ready."
echo ""
certbot certonly --manual --preferred-challenges=dns \
  -d certassist.us \
  -d "*.certassist.us" \
  --agree-tos \
  --email frank@universe-corrupted.com

echo "==> Starting nginx..."
systemctl enable nginx
systemctl restart nginx

echo "==> Setting up Docker Compose auto-start..."
cat > /etc/systemd/system/certassist.service << 'EOF'
[Unit]
Description=CERT Assist Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/certassist
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable certassist

echo ""
echo "==================================================="
echo "Server setup complete!"
echo ""
echo "Next steps (from your Mac):"
echo "  1. Copy docker-compose.prod.yml:"
echo "       scp docker-compose.prod.yml root@SERVER:/opt/certassist/"
echo ""
echo "  2. Build and transfer images:"
echo "       chmod +x build-push.sh"
echo "       ./build-push.sh root@SERVER_IP"
echo ""
echo "  3. Start all services:"
echo "       ssh root@SERVER 'cd /opt/certassist && docker compose -f docker-compose.prod.yml up -d'"
echo "==================================================="
