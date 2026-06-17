# CERT-Assist Field Board

Emergency response coordination system for Community Emergency Response Teams (CERT).

- **Created:** June 9, 2026
- **Last Updated:** June 17, 2026
- **Servers:** team.cert.w6fgc.com (team), county.cert.w6fgc.com (county)
- **Platform:** Docker backend (Swift/Vapor) + Web dashboard + iOS app

---

## Architecture — Three-Tier Hub & Spoke

```
County Dashboard (county.cert.w6fgc.com)
    ↑  Teams POST summary on every state change
    ↑  Teams poll /api/messages every 30s for county replies (acks, alerts)
    
Team Server(s) (team.cert.w6fgc.com or local Pi/laptop)
    ↑  iOS app members check in, submit reports, update status
    ↑  WebSocket → team leader dashboard (real-time)
    
Field Members (iPhone)
    → self check-in with equipment
    → submit field reports
    → view assigned tasks
```

### Network Modes (Graceful Degradation)

| Mode | How it works |
|------|-------------|
| **Internet up** | Each team has its own FQDN. Teams push summaries to county over internet. |
| **Internet down** | Team leader runs Docker on laptop. Team members connect to local WiFi hotspot. County unreachable — team operates standalone. |
| **Hybrid** | Pi runs team server locally; if internet comes up it auto-reconnects to county. Pi pings `county.cert.w6fgc.com`; if reachable it pushes; otherwise it skips silently. |

---

## Current Implementation — Feature Complete (v0.7)

### iOS App (`/CERT Assist/`)
- Check-in with name, role, ICS position, equipment list
- Field report submission (type, severity, location, notes)
- Task view and status updates
- Map view for location tracking
- MultipeerConnectivity for offline peer-to-peer sync

### Backend Server (`/Backend/`)
- **Runtime:** Swift/Vapor 4, actor-based in-memory DataStore
- **Persistence:** SQLite via Fluent (file: `data/cert_data.db`)
- **WebSocket:** Real-time push to all connected dashboards on every state change
- **County integration:** Pushes `TeamSummary` to county on every mutation; polls county for messages every 30s

#### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/auth` | PIN validation |
| POST | `/api/checkin` | Member check-in / update |
| GET | `/api/members` | All members |
| GET/POST | `/api/reports` | List / create reports |
| PUT | `/api/reports/:id` | Update report (status, escalation, etc.) |
| PATCH | `/api/reports/:id/severity` | Override severity only |
| GET/POST | `/api/tasks` | List / create tasks |
| PUT | `/api/tasks/:id` | Update task |
| POST/GET/PUT/DELETE | `/api/subteams` | Sub-team management |
| POST | `/api/members/:id/free` | Remove member from sub-team |
| POST | `/api/incident` | Set active incident |
| GET | `/api/dashboard` | Full dashboard snapshot |
| WS | `/ws` | WebSocket real-time feed |

### Team Dashboard (`/Backend/Public/dashboard.html`)
- Real-time WebSocket connection, auto-reconnect
- Live stats: members, active reports, open tasks, sub-teams
- **Sub-team management:** create, reassign members, delete, assign tasks
- **Task management:** create, edit, complete, cancel, re-open
- **Report detail modal:** click any report to see full details
  - Acknowledge (New → Assigned)
  - Mark Resolved
  - Re-open
  - County escalation toggle (see below)
- 📡 indicator on report cards that are being sent to county
- PIN modal on first load; PIN stored in `sessionStorage`

### Member Portal (`/Backend/Public/member.html`)
- Self check-in with team PIN
- Equipment selection
- Report submission
- Status update

### County Server (`/CountyServer/`)
- Separate Docker service (default port 8090)
- Receives `TeamSummary` pushes from all teams
- Queues messages (acks, alerts, info) for teams to poll
- County dashboard shows all teams, color-coded by severity
- Team detail view fetches live data from team endpoint
- PIN auth via `COUNTY_PIN` env var

---

## County Escalation System

Reports have an `escalatedToCounty: Bool?` field:

| Severity | `escalatedToCounty` | Behavior |
|----------|-------------------|----------|
| High / Life Safety | `nil` (default) | Auto-escalated — county sees it |
| High / Life Safety | `false` | Suppressed — team leader chose to keep it local |
| Low / Medium | `nil` (default) | Local only — county does NOT see it |
| Low / Medium | `true` | Manually pushed — team leader sent it to county |

The team leader dashboard has a **County Visibility** toggle in every report's detail modal. High/LS reports show a 🔕 Suppress button; Low/Medium reports show a 📡 Push to county button.

The county's `unacknowledgedPriority` count in `TeamSummary` reflects only reports that (a) go to county and (b) have not yet been acknowledged by the county EOC.

---

## Authentication

### PIN Authentication (Implemented)
- **Header:** `X-CERT-Token: <pin>`
- **Scope:** All non-GET API calls require the PIN. GETs and WebSocket upgrades are open.
- **Team server:** Set `TEAM_PIN` env var in `docker-compose.yml`
- **County server:** Set `COUNTY_PIN` env var in `CountyServer/docker-compose.yml`
- **Dashboard:** Shows PIN modal on load; PIN stored in `sessionStorage`
- **Member portal:** PIN field in check-in form; stored in `localStorage`

### How PIN works end-to-end
1. Team leader sets `TEAM_PIN=XXXX` in `docker-compose.yml` before deployment
2. Dashboard loads → calls `POST /api/auth` with saved PIN
3. If 401 → shows PIN modal; correct PIN saved to sessionStorage
4. All subsequent writes (`apiCall()`) send `X-CERT-Token` header automatically
5. Members enter PIN in the member portal check-in form

---

## Data Models (Key Fields)

### IncidentReport
```
id, type, location, severity, status, notes,
reportedBy (UUID), subTeamID,
acknowledgedByCounty (Bool?),   ← nil = false, set by county ack message
acknowledgedAt,
escalatedToCounty (Bool?),      ← nil = auto, true = forced up, false = suppressed
reportedAt, lastUpdated
```

### CERTMember
```
id, name, role, icsPosition, status, equipment, location, subTeamID, lastUpdated
```

### CERTTask
```
id, title, description, assignedTo, assignedSubTeamID, status, priority,
location, relatedReportID, createdAt, completedAt, notes
```

### SubTeam
```
id, color (Red/Blue/Green/Yellow/Purple/Orange/Teal/Pink),
memberIDs, assignedTaskID, createdAt, lastUpdated
```

---

## Security (Implemented)

| Layer | Status | Details |
|-------|--------|---------|
| PIN authentication | ✅ | `X-CERT-Token` header; per-deployment shared PIN |
| XSS prevention | ✅ | `esc()` applied to all user-sourced innerHTML in dashboard |
| SSRF prevention | ✅ | County dashboard validates team endpoints (`https://` only) |
| Input validation | ✅ | `teamId` validated as `^[a-zA-Z0-9\-_]{1,64}$` in county routes |
| SSL/TLS | ✅ | Let's Encrypt on both cloud servers |
| Network firewall | ✅ | UFW + iptables on Ubuntu servers |
| Threat intelligence | ✅ | IPsum blocklist, auto-updated daily at 3 AM |
| Rate limiting | ✅ | Nginx: 10 req/s API, 5 req/s WebSocket |
| Docker isolation | ✅ | Port 8080 not directly internet-accessible |

See `SECURITY-STATUS.md` for full details.

---

## Known Limitations / Technical Debt

- **In-memory storage:** Data is lost on container restart. SQLite is wired up via Fluent but migrations/models not yet implemented. All data currently lives in the `DataStore` actor.
- **Single PIN:** No per-user authentication. Shared PIN is simple but can't revoke a single user.
- **No offline sync:** iOS app uses MultipeerConnectivity but full store-and-forward mesh relay is not implemented.
- **Sub-team badge on reports:** The JSON key `sub_team_id` is sent by the server but the member list in the dashboard uses `member.subTeamID` (a pre-existing JS/snake_case mismatch). Team badges on report cards now correctly use `report.sub_team_id`.

---

## Deployment Quick Reference

See `DEPLOYMENT.md` for full details.

```bash
# Team server
cd Backend
docker-compose up -d --build

# County server
cd CountyServer
docker-compose up -d --build
```

**Key env vars to set before deploying:**

```yaml
# Backend/docker-compose.yml
TEAM_ID: your-team-id
TEAM_NAME: "My CERT Team"
TEAM_PIN: "4012"              # Change this!
COUNTY_ENDPOINT: https://county.cert.w6fgc.com

# CountyServer/docker-compose.yml
COUNTY_PIN: ""                # Set if you want county dashboard protected
```

---

## Contact
Frank Gadot — W6FGC
