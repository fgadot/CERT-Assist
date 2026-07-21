#!/bin/bash
# Build Docker images on this Mac (linux/amd64), transfer to the server,
# sync all HTML/config/nginx files, and restart containers.
#
# Usage: ./build-push.sh root@134.122.120.195

set -e

SERVER=${1:?"Usage: $0 user@server_ip"}

# ── 1. Build Docker images ────────────────────────────────────────────────────

echo "==> Building cert-backend (linux/amd64)..."
docker buildx build \
  --platform linux/amd64 \
  --tag cert-backend:latest \
  --load \
  ./Backend

echo "==> Building cert-county (linux/amd64)..."
docker buildx build \
  --platform linux/amd64 \
  --tag cert-county:latest \
  --load \
  ./CountyServer

# ── 2. Transfer Docker images ─────────────────────────────────────────────────

echo ""
echo "==> Transferring cert-backend to $SERVER ..."
docker save cert-backend:latest | gzip | ssh "$SERVER" 'gunzip | docker load'

echo "==> Transferring cert-county to $SERVER ..."
docker save cert-county:latest | gzip | ssh "$SERVER" 'gunzip | docker load'

# ── 3. Ensure server directories exist ───────────────────────────────────────

echo ""
echo "==> Ensuring server directories..."
ssh "$SERVER" 'mkdir -p /opt/certcommand/public/backend /opt/certcommand/public/county /var/www/html'

# ── 4. Sync public HTML files (served via volume mounts, not baked in image) ──

echo "==> Syncing Backend public HTML..."
rsync -av --delete Backend/Public/ "$SERVER:/opt/certcommand/public/backend/"

echo "==> Syncing County public HTML..."
rsync -av --delete CountyServer/Public/ "$SERVER:/opt/certcommand/public/county/"

# ── 5. Sync versions.json to every team config directory ─────────────────────

echo "==> Syncing versions.json to all team configs..."
for TEAM in sapphire glenn lakewood lorraine bayview; do
    rsync -av Backend/config/versions.json "$SERVER:/opt/certcommand/config/$TEAM/"
done

# ── 6. Sync docker-compose ────────────────────────────────────────────────────

echo "==> Syncing docker-compose.prod.yml..."
rsync -av docker-compose.prod.yml "$SERVER:/opt/certcommand/"

# ── 7. Sync nginx config and reload ──────────────────────────────────────────

echo "==> Syncing nginx config..."
rsync -av nginx/certcommand.conf "$SERVER:/etc/nginx/sites-available/certcommand.conf"
rsync -av nginx/maintenance.html "$SERVER:/var/www/html/maintenance.html"
echo "==> Reloading nginx..."
ssh "$SERVER" 'nginx -t && systemctl reload nginx'

# ── 8. Restart containers with new images ────────────────────────────────────

echo ""
echo "==> Restarting containers..."
ssh "$SERVER" 'cd /opt/certcommand && docker compose -f docker-compose.prod.yml up -d'

echo ""
echo "=== Deploy complete ==="
echo "    Backend HTML : /opt/certcommand/public/backend/"
echo "    County HTML  : /opt/certcommand/public/county/"
echo "    versions.json: /opt/certcommand/config/<team>/"
echo "    nginx        : /etc/nginx/sites-available/certcommand.conf"
