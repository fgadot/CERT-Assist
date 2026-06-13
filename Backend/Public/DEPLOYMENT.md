# CERT-Assist Deployment Guide

## Current Production Deployment

**Server:** cert.w6fgc.com (Ubuntu)  
**Status:** ✅ Live  
**URL:** https://cert.w6fgc.com/dashboard

---

## Architecture

```
Internet (HTTPS/WSS)
    ↓
Nginx (Port 80/443)
    ↓ (proxy_pass)
Docker Container (Port 8080)
    ↓
Vapor Backend (Swift)
    ↓
In-Memory DataStore (Actor)
```

---

## Server Configuration

### 1. Nginx Reverse Proxy

**Location:** `/etc/nginx/sites-available/cert`

**Key Features:**
- SSL/TLS termination with Let's Encrypt
- HTTP → HTTPS automatic redirect
- WebSocket upgrade support
- Rate limiting for API and WebSocket endpoints
- Security headers
- Connection limits per IP

**Configuration:**
```nginx
server {
    server_name cert.w6fgc.com;
    
    # Limit connections per IP
    limit_conn conn_limit 10;
    
    # API endpoints - rate limit
    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;
        limit_req_status 429;
        
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # WebSocket - stricter rate limit
    location /ws {
        limit_req zone=ws_limit burst=5 nodelay;
        limit_req_status 429;
        
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
    
    # Dashboard and other routes
    location / {
        limit_req zone=api_limit burst=10 nodelay;
        
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/cert.w6fgc.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cert.w6fgc.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if ($host = cert.w6fgc.com) {
        return 301 https://$host$request_uri;
    }

    listen 80;
    server_name cert.w6fgc.com;
    return 404;
}
```

**Rate Limit Zones (in nginx.conf):**
```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=ws_limit:10m rate=5r/s;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
```

### 2. Docker Setup

**Location:** `Backend/`

**docker-compose.yml:**
```yaml
services:
  app:
    build:
      context: .
    ports:
      - "8080:8080"
    volumes:
      - ./Public:/app/Public
    restart: unless-stopped
    environment:
      - ENVIRONMENT=development
```

**Dockerfile:** Multi-stage build
- Build stage: Swift 5.9 + compile
- Production stage: Minimal runtime + non-root user

### 3. SSL/TLS Certificates

**Provider:** Let's Encrypt via Certbot

**Certificate Location:**
- Fullchain: `/etc/letsencrypt/live/cert.w6fgc.com/fullchain.pem`
- Private Key: `/etc/letsencrypt/live/cert.w6fgc.com/privkey.pem`

**Auto-renewal:** Managed by Certbot systemd timer

**Manual renewal (if needed):**
```bash
sudo certbot renew
sudo systemctl reload nginx
```

---

## Deployment Procedures

### Initial Setup (Already Complete)

1. **Install Docker**
```bash
sudo apt update
sudo apt install docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
```

2. **Install Nginx**
```bash
sudo apt install nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

3. **Install Certbot**
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d cert.w6fgc.com
```

4. **Clone Repository**
```bash
git clone <repo-url> ~/cert-assist
cd ~/cert-assist/Backend
```

5. **Build and Start**
```bash
docker-compose up -d --build
```

### Updating the Application

**After code changes (push to GitHub):**

```bash
# SSH to server
ssh user@cert.w6fgc.com

# Pull latest code
cd ~/cert-assist  # or wherever repo is located
git pull origin main

# Rebuild and restart Docker container
cd Backend
docker-compose down
docker-compose up -d --build

# Verify
docker-compose logs -f
```

**Quick update (dashboard.html only):**
```bash
# Dashboard updates are hot-reloaded via volume mount
cd ~/cert-assist/Backend/Public
# Edit dashboard.html
# Changes are immediately live (no rebuild needed)
```

### Updating Nginx Configuration

```bash
# Edit config
sudo nano /etc/nginx/sites-available/cert

# Test configuration
sudo nginx -t

# Reload (if test passes)
sudo systemctl reload nginx
```

---

## Monitoring & Maintenance

### View Logs

**Docker/Application logs:**
```bash
cd ~/cert-assist/Backend
docker-compose logs -f
```

**Nginx access logs:**
```bash
sudo tail -f /var/log/nginx/access.log
```

**Nginx error logs:**
```bash
sudo tail -f /var/log/nginx/error.log
```

### Check Status

**Docker container:**
```bash
docker-compose ps
docker stats
```

**Nginx:**
```bash
sudo systemctl status nginx
```

**SSL Certificate expiry:**
```bash
sudo certbot certificates
```

### Restart Services

**Docker container:**
```bash
cd ~/cert-assist/Backend
docker-compose restart
```

**Nginx:**
```bash
sudo systemctl restart nginx
```

---

## Local Development Deployment

For testing on team leader's laptop:

```bash
cd Backend
docker-compose up -d

# Access at:
# http://localhost:8080/dashboard
```

**Local network access:**
- Laptop creates WiFi hotspot
- Team members connect to hotspot
- Access via `http://<laptop-ip>:8080/dashboard`

**Future: Unifi Network Deployment**
- Deploy Unifi AP for better capacity
- Docker container on laptop or dedicated server
- Local DNS or mDNS for easy access

---

## Security Considerations

### Current Protections

✅ **SSL/TLS encryption** - All traffic encrypted  
✅ **Rate limiting** - Prevents API abuse  
✅ **Connection limits** - 10 per IP  
✅ **Security headers** - XSS, clickjacking protection  
✅ **Non-root container** - Limited privilege escalation  
✅ **HTTP → HTTPS redirect** - Force secure connections

### Future Enhancements

- [ ] Authentication system (credentials for team members)
- [ ] Firewall rules (ufw or iptables)
- [ ] Fail2ban for brute force protection
- [ ] Regular security updates
- [ ] Database backup strategy
- [ ] Monitoring/alerting (Prometheus + Grafana)

---

## Troubleshooting

### Dashboard not loading

1. Check Docker container:
```bash
docker-compose ps
docker-compose logs
```

2. Check Nginx:
```bash
sudo nginx -t
sudo systemctl status nginx
```

3. Check network:
```bash
curl http://localhost:8080/
curl https://cert.w6fgc.com/dashboard
```

### WebSocket connection failing

1. Check browser console for errors
2. Verify Nginx WebSocket config
3. Check rate limits (might be hitting 5 req/sec limit)

### SSL certificate issues

```bash
sudo certbot certificates
sudo certbot renew --dry-run
```

### Container won't start

```bash
docker-compose down
docker-compose up --build
# Watch for build errors
```

---

## Production Checklist

- [x] Docker container running
- [x] Nginx reverse proxy configured
- [x] SSL/TLS with Let's Encrypt
- [x] HTTP → HTTPS redirect
- [x] WebSocket support
- [x] Rate limiting
- [x] Security headers
- [ ] Database persistence (currently in-memory)
- [ ] Automated backups
- [ ] Monitoring/alerting
- [ ] Authentication system
- [ ] Firewall configuration
- [ ] Log rotation

---

## Contact

Frank Gadot - W6FGC  
Server: cert.w6fgc.com
