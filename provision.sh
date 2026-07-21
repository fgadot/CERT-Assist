#!/bin/bash
# Provision a fresh Ubuntu 22.04 droplet for certcommand.org.
#
# Usage:
#   ./provision.sh root@alphago.certcommand.org
#
# What it does:
#   1. Copies nginx config, fail2ban configs, and setup-server.sh to the server
#   2. SSHes in and runs setup-server.sh (interactive for certbot SSL step)
#
# After this completes, run:
#   ./build-push.sh root@alphago.certcommand.org

set -e

SERVER=${1:?"Usage: $0 user@server"}

echo "==> Copying setup files to $SERVER ..."
scp \
  nginx/certcommand.conf \
  server-config/fail2ban-filter-certcommand.conf \
  server-config/fail2ban-jail-certcommand.conf \
  setup-server.sh \
  "$SERVER:/tmp/"

echo "==> Starting server setup (you will be prompted during the SSL cert step)..."
ssh -t "$SERVER" "bash /tmp/setup-server.sh"
