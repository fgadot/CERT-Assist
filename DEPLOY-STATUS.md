# CERT Command — Deployment Status

**Server IP:** 165.22.9.234  
**Server FQDN:** alphago.certcommand.org  
**Domain:** certcommand.org  
**SSH user:** root  
**Deployed:** 2026-07-21

---

## Status: ✅ LIVE

All services running on Ubuntu 24.04 (noble), DigitalOcean Premium AMD 1vCPU/2GB.

## Checklist

- [x] Packages updated
- [x] UFW configured (ports 22 from 47.205.39.149, 80, 443 open)
- [x] Docker installed (v29.6.2)
- [x] nginx + certbot installed
- [x] fail2ban installed + certcommand-pin filter/jail deployed
- [x] IPsum threat intel blocklist (18,029 IPs blocked, daily 3am update)
- [x] SSL wildcard cert obtained (certcommand.org + *.certcommand.org)
- [x] nginx config deployed + enabled
- [x] App directory structure created (/opt/certcommand/)
- [x] Data directory ownership fixed (chown 1000:1000 for vapor user)
- [x] Systemd certcommand.service created
- [x] Docker images built and transferred (cert-backend, cert-county)
- [x] All 6 containers started and healthy
- [x] DNS records verified (all → 165.22.9.234)

---

## DNS Records (all → 165.22.9.234)

| Subdomain | Status |
|---|---|
| alphago.certcommand.org | ✓ (server hostname) |
| sapphire.certcommand.org | ✓ |
| glenn.certcommand.org | ✓ |
| lakewood.certcommand.org | ✓ |
| lorraine.certcommand.org | ✓ |
| bayview.certcommand.org | ✓ |
| county.certcommand.org | ✓ |

---

## Container Layout

| Service | Port | Team ID | Status |
|---|---|---|---|
| team-sapphire | 8080 | sapphire-point | ✅ Up |
| team-glenn | 8081 | glenn-lakes | ✅ Up |
| team-lakewood | 8082 | lakewood-ranch | ✅ Up |
| team-lorraine | 8083 | lorraine-lakes | ✅ Up |
| team-bayview | 8084 | bayview | ✅ Up |
| county | 8090 | — | ✅ Up |

---

## Known Issues / Notes

- nginx logs duplicate ssl_protocols warnings (harmless — Ubuntu 24.04 default nginx.conf already defines them)
- Data directories must be owned by uid 1000 (vapor user) — handled by setup-server.sh and noted in docs
- certbot SSL step must be run interactively (cannot be automated)

---

## Re-deploy Command (future updates)

```bash
# From Mac, project root:
./build-push.sh root@alphago.certcommand.org
```
