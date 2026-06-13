# CERT-Assist Field Board

Emergency response coordination system for Community Emergency Response Teams (CERT).

## Project Status
- **Created**: June 9, 2026
- **Server**: cert.w6fgc.com (cert.w6fgc.com/dashboard)
- **Platform**: Docker backend + Web dashboard + Mobile apps (iPhone first, Android later)

---

## CURRENT PROJECT VISION (Updated Session)

### Problem Statement
Creating an application to help CERT teams when they activate during emergencies. System must work with degraded or no internet connectivity.

### Three-Tier Architecture

#### **TIER 1: Team Level (Local CERT Team)**

**Team Leader Station:**
- Laptop running Docker container (can run locally or on cloud server)
- Dashboard shows:
  - Team members checked in
  - Member equipment inventory (golf cart, chainsaw, AED, med kit, etc.)
  - Member locations
  - Member status (Available, Assigned, Unavailable, Request Assistance, Emergency)
  - Reports submitted by sub-teams in the field
  - Tasks assigned to sub-teams
  - Sub-team composition and color assignments

**Team Members:**
- Mobile apps (iPhone priority, Android later)
- Functions:
  - Self check-in with CERT assignment and equipment
  - View assigned tasks
  - Submit field reports (Green/Orange/Red severity)
  - Update status
  - Local data storage with immutable timestamps

#### **TIER 2: County Level (Central Command)**

**County Dashboard:**
- Overview of all CERT teams in county
- Color-coded team status:
  - **Green**: Team OK, no contact needed
  - **Orange**: Incident in progress, team handling it
  - **Red**: Emergency, priority contact required
- Real-time situational awareness across all teams

#### **TIER 3: Communication Layers (Graceful Degradation)**

1. **WiFi to local laptop** - Direct connection to team leader's Docker instance
   - Current: Laptop WiFi hotspot (limited clients)
   - Future: Unifi gear for proper local network with more capacity
2. **Cell network** - If towers up, connect to cloud-hosted Docker instance at cert.w6fgc.com
3. **Meshtastic network** - Backup communication when internet/cell down
4. **Mesh propagation** - Device-to-device relay, reports hop node-to-node until reaching dashboard

---

## Key Features & Requirements

### Sub-Teams (Color-Coded Assignment System)
- Sub-teams are the **unit of assignment** (not individuals)
- Minimum **2 members** per sub-team
- Each sub-team assigned a **color** for identification
- Dashboard shows:
  - **Color badge** indicating sub-team
  - **Number** showing member count in sub-team
  - **Assigned task** for that sub-team

### Field Reporting System
- **Report identification**: Each report marked with submitting sub-team color
- **Initial severity**: Sub-team classifies as Green/Orange/Red when submitting
- **Override capability**: Team leader can re-assign severity level
- **Sorting options**:
  - By sub-team (who submitted)
  - By severity level (Green/Orange/Red)

### Audit Trail & Data Integrity
- **All actions date and time stamped**
- **No deletion of logs** - permanent immutable record
- Reports saved **locally on device first** with immutable timestamps
- No possibility of removing timestamps or modifying logs

### Mobile Device Sync Strategy (Store-and-Forward)
- Reports stored locally on device until connectivity available
- Automatic sync when any network becomes available:
  - Close proximity to team leader (Bluetooth/MultipeerConnectivity)
  - WiFi network
  - Cell network
  - Meshtastic network
- **Mesh-style propagation**: Reports hop device-to-device (node-to-node) until reaching dashboard
- Device acts as both **reporter AND relay node**
- If mesh propagation not possible: fall back to direct Meshtastic integration

### Authentication
- Credentials system needed eventually
- **Not priority right now**

---

## Current Implementation

### iOS App (SwiftUI)
Located in `/CERT Assist/`
- Check-in system for team members
- Incident reporting with ICS (Incident Command System) positions
- Task management and assignment
- Map view for location tracking
- Incident logging
- MultipeerConnectivity for offline peer-to-peer sync

### Backend Server (Swift/Vapor)
Located in `/Backend/`
- RESTful API endpoints for members, reports, tasks, incidents
- WebSocket server for real-time dashboard updates
- Actor-based thread-safe data store
- CORS enabled for iOS app communication
- Serves web dashboard from `/Backend/Public/`
- **Dockerized deployment** ready

### Web Dashboard (HTML/JS/CSS)
Located in `/Backend/Public/dashboard.html`
- Real-time incident commander dashboard
- WebSocket connection to backend
- Live stats: team members, active reports, open tasks
- Color-coded status indicators
- Auto-reconnecting WebSocket

## Key Features

### ICS Positions Supported
- Incident Commander
- Safety Officer
- Public Information Officer
- Operations Section Chief (Medical/Triage, Search & Rescue, Fire Suppression, Damage Assessment)
- Planning Section Chief (Documentation, Resource Tracking)
- Logistics Section Chief (Communications, Supplies, Equipment)

### Report Types
- Tree Down
- Flooding
- Power Line Down
- Medical Need
- Blocked Road
- Fire/Smoke
- Gas Smell
- Welfare Check
- Structure Damage
- Needs 911

### Member Status Tracking
- Available
- Assigned
- Unavailable
- Injured
- Needs Help

---

## Design Philosophy

### Simplicity Over Complexity
- **Not ATAK**: Tactical Awareness Kit (used by military) is too complicated for CERT demographic
- Goal: Super simple, fast, elegant solution
- Mobile app interface: Keep it minimal (details to be discussed)

### No Single Point of Failure
- Multiple communication paths
- Local-first data storage
- Devices act as relay nodes
- Graceful degradation when infrastructure fails

---

## Report Types (From Original Design)
- Tree Down
- Flooding
- Power Line Down
- Medical Need
- Blocked Road
- Fire/Smoke
- Gas Smell
- Welfare Check
- Structure Damage
- Needs 911
- Other

## Member Status Tracking
- Available
- Assigned
- Unavailable
- Injured / Request Assistance
- Emergency / Needs Help

## ICS Positions Supported
- Incident Commander
- Safety Officer
- Public Information Officer
- Operations Section Chief (Medical/Triage, Search & Rescue, Fire Suppression, Damage Assessment)
- Planning Section Chief (Documentation, Resource Tracking)
- Logistics Section Chief (Communications, Supplies, Equipment)

---

## Deployment

### Docker Container Setup

**Location:** `Backend/Dockerfile` and `Backend/docker-compose.yml`

**Multi-stage Build:**
- **Build stage**: Uses `swift:5.9-jammy` image
  - Installs libsqlite3-dev
  - Compiles Swift code in release mode
- **Production stage**: Uses `swift:5.9-jammy-slim` image
  - Minimal runtime dependencies (libsqlite3-0)
  - Non-root user (vapor:vapor, uid 1000)
  - Exposes port 8080
  - Serves from `/app`
  - Mounts `Public/` directory for dashboard assets

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

**Deployment Options:**
- Can run on Ubuntu server online (cert.w6fgc.com) ✅ **Currently running**
- Can run locally on team leader's laptop
- Portable, self-contained deployment

**Commands:**
```bash
# Build and start
cd Backend
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down

# Rebuild after changes
docker-compose up -d --build
```

### Ubuntu Server (cert.w6fgc.com) - Production Deployment

**Status: ✅ LIVE**

**Access:** https://cert.w6fgc.com/dashboard

**Stack:**
- ✅ Docker container running Vapor backend (port 8080)
- ✅ Nginx reverse proxy (port 80/443 → 8080)
- ✅ SSL/HTTPS with Let's Encrypt (auto-renewing certificates)
- ✅ HTTP → HTTPS automatic redirect
- ✅ WebSocket support for real-time updates
- ✅ Rate limiting & DDoS protection
- ✅ Security headers (X-Frame-Options, XSS-Protection, etc.)

**Nginx Configuration:** `/etc/nginx/sites-available/cert`

Rate Limits:
- API endpoints: 10 req/sec (burst 20)
- WebSocket: 5 req/sec (burst 5)
- Max connections per IP: 10

**SSL Certificate:**
- Provider: Let's Encrypt (Certbot)
- Location: `/etc/letsencrypt/live/cert.w6fgc.com/`
- Auto-renewal: Managed by Certbot

**Deployment Process:**
```bash
# On Ubuntu server
cd ~/path/to/CERT-Assist/Backend
docker-compose up -d --build

# Nginx reload (if config changes)
sudo nginx -t
sudo systemctl reload nginx

# View logs
docker-compose logs -f
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

---

## TODO / Next Steps

### Immediate Priorities
- [ ] Implement **sub-team color-coding system** in dashboard and mobile app
- [ ] Update dashboard to show sub-teams (color badge + member count + task)
- [ ] Implement **report severity classification** (Green/Orange/Red)
- [ ] Add **sub-team indicator** to reports
- [ ] Team leader ability to **re-assign report severity**
- [ ] Implement **report sorting** (by sub-team or by severity)
- [ ] Docker deployment configuration files
- [ ] Deploy backend to cert.w6fgc.com

### Mobile App Development
- [ ] Build iPhone app with store-and-forward sync
- [ ] Implement local immutable data storage
- [ ] Add mesh-style device-to-device relay
- [ ] Android version (later)

### Infrastructure
- [ ] Add database persistence (SQLite or PostgreSQL)
- [ ] Implement authentication/credentials system (later priority)
- [ ] Meshtastic integration for Tier 3 communications
- [ ] Unifi network gear setup for local deployment
- [ ] SSL/HTTPS configuration

### County-Level Features (Future)
- [ ] County dashboard showing all teams
- [ ] Team status color coding (Green/Orange/Red at team level)
- [ ] Multi-team coordination view

### Enhancement Features
- [ ] Map view on web dashboard with sub-team locations
- [ ] Photo upload capability for damage reports
- [ ] PDF/CSV export for after-action reports
- [ ] Training mode for CERT drills

---

## Development Notes
- Using Swift 5.9+
- Vapor 4.89.0 for backend
- SwiftUI for iOS app
- Vanilla JavaScript for dashboard (no frameworks)
- Docker for deployment
- Git repository backed up

---

## Contact
Frank Gadot - W6FGC

---

## Project Background & Rationale

This app fills a gap that existing emergency apps don't address. FEMA's app provides alerts and preparedness information, but doesn't help small CERT teams coordinate during active incidents.

**Core problem it solves:**

During an incident, a CERT team needs answers to:
- Who is available?
- Where are they?
- What streets/homes have been checked?
- Who needs help?
- What resources do we have?
- What tasks are open?
- What was reported, when, and by whom?

Most small CERT teams do this by paper, text messages, WhatsApp, radios, or memory. That falls apart quickly.

**Target users:**
- Small CERT teams
- HOAs with emergency preparedness programs
- Neighborhood associations
- Schools, churches, campuses
- Marinas, RV parks, gated communities

**Key differentiator:**
Lightweight emergency coordination without buying a full public-safety CAD system, with resilience for degraded network conditions.
