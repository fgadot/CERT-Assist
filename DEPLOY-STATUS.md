# CERT Assist — Deployment Status

**Server IP:** 134.122.120.195  
**Server FQDN:** test.certassist.us  
**Domain:** certassist.us  
**SSH user:** root

---

## Progress Checklist

- [x] Ubuntu 22.04 installed
- [x] fail2ban installed
- [x] UFW configured (ports 22, 80, 443 open)
- [x] DNS A records added (see table below)
- [ ] Docker installed
- [ ] nginx + certbot installed
- [ ] SSL wildcard cert obtained
- [ ] nginx config deployed
- [ ] App directory structure created on server
- [ ] Docker images built on Mac and transferred to server
- [ ] docker-compose.prod.yml placed on server
- [ ] Containers started

---

## DNS Records (all → 134.122.120.195)

| Subdomain | Status |
|---|---|
| sapphire.certassist.us | NOT RESOLVING YET — check DNS provider |
| glenn.certassist.us | ✓ |
| lakewood.certassist.us | ✓ |
| lorraine.certassist.us | ✓ |
| bayview.certassist.us | ✓ |
| county.certassist.us | ✓ |

---

## Next Step: Install Docker (Step 2)

SSH into server and run:

```bash
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

Verify: `docker --version && docker compose version`

---

## Step 3: Install nginx + certbot

```bash
apt-get install -y nginx certbot python3-certbot-nginx
```

---

## Step 4: Get SSL wildcard cert

Wildcard cert covers all subdomains with one cert. Uses DNS challenge (certbot will ask you to add a TXT record in your DNS provider).

```bash
certbot certonly --manual --preferred-challenges=dns \
  -d certassist.us \
  -d "*.certassist.us" \
  --agree-tos \
  --email frank@universe-corrupted.com
```

Cert will land at `/etc/letsencrypt/live/certassist.us/`

---

## Step 5: Deploy nginx config

The config file is at `nginx/certassist.conf` in the project root on your Mac.

```bash
# From Mac:
scp "nginx/certassist.conf" root@134.122.120.195:/etc/nginx/sites-available/certassist.conf

# On server:
ln -sf /etc/nginx/sites-available/certassist.conf /etc/nginx/sites-enabled/certassist.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
```

nginx routes by hostname → container port:
- sapphire.certassist.us → localhost:8080
- glenn.certassist.us → localhost:8081
- lakewood.certassist.us → localhost:8082
- lorraine.certassist.us → localhost:8083
- bayview.certassist.us → localhost:8084
- county.certassist.us → localhost:8090

---

## Step 6: Create directory structure on server

```bash
mkdir -p /opt/certassist
cd /opt/certassist
for TEAM in sapphire glenn lakewood lorraine bayview; do
    mkdir -p data/$TEAM config/$TEAM
done
```

---

## Step 7: Build images on Mac and transfer to server

Script is at `build-push.sh` in project root. It builds both images for linux/amd64 and pipes them over SSH — no Docker Hub needed.

```bash
# From Mac, in project root:
chmod +x build-push.sh
./build-push.sh root@134.122.120.195
```

This runs:
```bash
docker buildx build --platform linux/amd64 --tag cert-backend:latest --load ./Backend
docker buildx build --platform linux/amd64 --tag cert-county:latest --load ./CountyServer
docker save cert-backend:latest | gzip | ssh root@134.122.120.195 'gunzip | docker load'
docker save cert-county:latest  | gzip | ssh root@134.122.120.195 'gunzip | docker load'
```

---

## Step 8: Deploy docker-compose and start containers

```bash
# From Mac:
scp docker-compose.prod.yml root@134.122.120.195:/opt/certassist/

# On server:
cd /opt/certassist
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

---

## Files Created/Modified This Session

| File | Purpose |
|---|---|
| `build-push.sh` | Build Mac→server image transfer (no Docker Hub) |
| `docker-compose.prod.yml` | Production compose (6 containers, local image names) |
| `docker-compose.local.yml` | Local 5-team test setup |
| `nginx/certassist.conf` | nginx reverse proxy config with SSL + WebSocket support |
| `setup-server.sh` | One-time server setup script (reference only, follow steps above) |

---

## Container Layout (prod)

| Service | Port | Team ID | PIN |
|---|---|---|---|
| team-sapphire | 8080 | sapphire-point | 1111 |
| team-glenn | 8081 | glenn-lakes | 2222 |
| team-lakewood | 8082 | lakewood-ranch | 3333 |
| team-lorraine | 8083 | lorraine-lakes | 4444 |
| team-bayview | 8084 | bayview | 5555 |
| county | 8090 | — | (set COUNTY_PIN in compose) |
