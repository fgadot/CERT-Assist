#!/bin/bash
# Build both Docker images on this Mac (linux/amd64) and transfer directly
# to the Ubuntu server via SSH — no Docker Hub needed.
#
# Usage: ./build-push.sh root@YOUR_SERVER_IP
#
# Example: ./build-push.sh root@143.244.xxx.xxx

set -e

SERVER=${1:?"Usage: $0 user@server_ip"}

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

echo ""
echo "==> Transferring cert-backend to $SERVER ..."
docker save cert-backend:latest | gzip | ssh "$SERVER" 'gunzip | docker load'

echo "==> Transferring cert-county to $SERVER ..."
docker save cert-county:latest | gzip | ssh "$SERVER" 'gunzip | docker load'

echo ""
echo "Done. Both images are now on $SERVER."
echo "SSH in and run: cd /opt/certassist && docker compose up -d"
