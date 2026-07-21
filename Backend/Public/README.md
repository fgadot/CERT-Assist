# CERT-Assist Field Board

Emergency response coordination system for Community Emergency Response Teams (CERT).

- **Created:** June 9, 2026
- **Last Updated:** July 2, 2026
- **Version:** v0.9
- **Servers:** team.cert.w6fgc.com (team), county.cert.w6fgc.com (county)
- **Platform:** Docker backend (Swift/Vapor 4) + Web dashboards + iOS app

---

## Architecture — Three-Tier Hub & Spoke

```
County Dashboard (county.cert.w6fgc.com / localhost:8090)
    ↑  Teams POST /api/teams/summary on every state change
    ↑  Teams poll /api/messages every 30s for county replies (acks, alerts)
    ↑  County broadcasts updates to dashboard via WebSocket
    
Team Server(s) (team.cert.w6fgc.com / localhost:808x)
    ↑  iOS app members check in, submit reports, update status
    ↑  WebSocket → team leader dashboard (real-time)
    
Field Members (iPhone / member.html)
    → self check-in with equipment
    → submit field reports
    → view assigned tasks
```

### Network Modes (Graceful Degradation)

| Mode | How it works |
|------|-------------|
| **Internet up** | Each team has its own FQDN. Teams push summaries to county over HTTPS. |
| **Internet down** | Team leader runs Docker on laptop. Team members connect to local WiFi hotspot. County unreachable — team operates standalone. |
| **Hybrid** | Pi runs team server locally; if internet comes up it auto-reconnects to county. |

---

## Current Implementation — Feature Status (v0.9)

### iOS App (`/CERT Command/`)
- Check-in with name, role, ICS position, equipment list
- Field report submission (type, severity, location, notes)
- Task view and status updates
- Map view for location tracking
- MultipeerConnectivity for offline peer-to-peer sync

### Backend Server (`/Backend/`)
- **Runtime:** Swift/Vapor 4, actor-based in-memory `DataStore`
- **Persistence:** SQLite via Fluent (file: `data/cert_data.db`) — wired up but not fully migrated; all active data is in-memory
- **WebSocket:** Real-time push to all connected dashboards on every state change
- **County integration:** Pushes `TeamSummary` to county on every mutation (but only when ≥1 member checked in); polls county for messages every 30s

### County Server (`/CountyServer/`)
- Separate Vapor service (default port 8090 in Docker, 8080 inside container)
- Receives `TeamSummary` pushes from all teams
- Only displays teams that have ≥1 member checked in (`memberCount > 0`)
- Queues messages (acks, alerts, info) for teams to poll
- County dashboard shows all active teams, color-coded by severity
- Team detail view fetches live data from team endpoint
- WebSocket broadcasts updated dashboard state on every team push or message event
- PIN auth via `COUNTY_PIN` env var

---

## County Integration — Complete

**Status:** Fully working as of July 2, 2026. See `COUNTY-INTEGRATION.md` for full architecture details, the JSON key strategy gotcha, and debugging history.

Key behaviors:
- Team only appears on county dashboard once it has ≥1 member checked in
- Team disappears from county if all members check out (memberCount drops to 0)
- County acknowledgments propagate back to team reports within 30s
- Cross-team member lending: team marks member "loanable" → county lists them → other teams' Transfer panel polls every 5s

---

## Sub-Team System — Complete

See `SUB-TEAM-FEATURE.md` for full details.

- Team leader creates color-coded sub-teams (Red, Blue, Green, Yellow, Purple, Orange, Teal, Pink)
- Sub-teams are the assignment unit for tasks and reports
- Members show their sub-team color badge
- Creating/deleting sub-teams broadcasts real-time updates via WebSocket

---

## Cross-Team Member Transfer — Complete

When a team needs personnel from another team:

1. **Owning team** marks a member as "loanable" (toggle in member row)
2. Member is registered at county `POST /api/available-members`
3. **Requesting team** sees the member in their Transfer Panel (polls county every 5s)
4. Requesting team clicks "Request" → county creates `TransferRequest` + notifies owning team
5. Owning team accepts/denies → requesting team is notified via county message

---

## API Endpoints

### Team Server (`/Backend/`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/auth` | none | PIN validation |
| POST | `/api/checkin` | member PIN | Member check-in / update |
| GET | `/api/members` | none | All members |
| GET/POST | `/api/reports` | GET:none, POST:PIN | List / create reports |
| PUT | `/api/reports/:id` | PIN | Update report |
| PATCH | `/api/reports/:id/severity` | PIN | Override severity |
| GET/POST | `/api/tasks` | GET:none, POST:PIN | List / create tasks |
| PUT | `/api/tasks/:id` | PIN | Update task |
| POST/GET/PUT/DELETE | `/api/subteams` | PIN | Sub-team management |
| POST | `/api/members/:id/free` | PIN | Remove from sub-team |
| PATCH | `/api/members/:id/loanable` | PIN | Mark member available for transfer |
| POST | `/api/incident` | PIN | Set active incident |
| GET | `/api/dashboard` | none | Full dashboard snapshot |
| GET | `/api/config` | none | Team ID, name, county_enabled flag |
| GET | `/api/county/available-members` | PIN | Proxy: available members from county |
| POST | `/api/county/transfer-requests` | PIN | Proxy: request a member from county |
| GET | `/api/county/transfer-requests` | PIN | Proxy: transfer requests for this team |
| PUT | `/api/county/transfer-requests/:id` | PIN | Proxy: accept/deny a transfer request |
| WS | `/ws` | none | WebSocket real-time feed |

### County Server (`/CountyServer/`)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/teams/summary` | Team pushes summary (triggers WebSocket broadcast) |
| GET | `/api/county/dashboard` | REST snapshot of dashboard data |
| POST | `/api/teams/:teamId/acknowledge/:reportId` | County acks a report |
| POST | `/api/teams/:teamId/message` | County sends alert/info to a team |
| GET | `/api/messages?team=:id` | Team polls for pending messages |
| POST | `/api/messages/:id/confirm` | Team confirms message processed |
| POST | `/api/available-members` | Register loanable member |
| DELETE | `/api/available-members/:memberId` | Remove loanable member |
| GET | `/api/available-members?exclude=:teamId` | List members available for transfer |
| POST | `/api/transfer-requests` | Request a member from another team |
| GET | `/api/transfer-requests?team=:id` | Get transfer requests for a team |
| PUT | `/api/transfer-requests/:id` | Accept or deny a request |
| WS | `/ws` | County dashboard WebSocket |

---

## Authentication

### PIN Authentication
- **Header:** `X-CERT-Token: <pin>`
- **Scope:** All non-GET API calls require PIN. GETs and WebSocket upgrades are open.
- **Team server:** `TEAM_PIN` env var
- **County server:** `COUNTY_PIN` env var (can be blank for open county)
- **Dashboard:** Shows PIN modal on load; PIN stored in `sessionStorage`
- **Member portal:** PIN field in check-in form; stored in `localStorage`

---

## Data Models

### TeamSummary (sent from team → county)
```
teamId, teamName, location, endpoint,
memberCount, activeMemberCount,
reportCounts { lifeSafety, high, medium, low },
unacknowledgedPriority, openTaskCount, lastContact
```

**CRITICAL:** `teamId` must use lowercase `d` (not `teamID`) because Swift's
`convertFromSnakeCase` strategy turns `team_id` → `teamId`, not `teamID`.
See `COUNTY-INTEGRATION.md` for full explanation.

### IncidentReport
```
id, type, location, severity, status, notes,
reportedBy (UUID), subTeamID,
acknowledgedByCounty (Bool?),
acknowledgedAt,
escalatedToCounty (Bool?),   ← nil=auto, true=force up, false=suppress
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

### AvailableMember (county cross-team transfer)
```
memberId, teamId, teamName, memberName, memberRole, addedAt
```

### TransferRequest
```
id, requestingTeamId, requestingTeamName, owningTeamId,
memberId, memberName, status (Pending/Accepted/Denied),
requestedAt, respondedAt
```

---

## County Escalation System

Reports have an `escalatedToCounty: Bool?` field:

| Severity | `escalatedToCounty` | Behavior |
|----------|-------------------|----------|
| High / Life Safety | `nil` (default) | Auto-escalated — county sees it |
| High / Life Safety | `false` | Suppressed — team leader chose to keep it local |
| Low / Medium | `nil` (default) | Local only — county does NOT see it |
| Low / Medium | `true` | Manually pushed — team leader sent it to county |

---

## Security

| Layer | Status | Details |
|-------|--------|---------|
| PIN authentication | ✅ | `X-CERT-Token` header; per-deployment shared PIN |
| XSS prevention | ✅ | `esc()` applied to all user-sourced innerHTML |
| SSRF prevention | ✅ | County validates team endpoints; `https://` in production, `http://localhost` allowed for local dev |
| Input validation | ✅ | `teamId` validated as `^[a-zA-Z0-9\-_]{1,64}$` in county routes |
| SSL/TLS | ✅ | Let's Encrypt on both cloud servers |

See `SECURITY-STATUS.md` for full details.

---

## Known Limitations / Technical Debt

- **In-memory storage:** Data lost on container restart. SQLite via Fluent is wired up but migrations not yet implemented.
- **Single PIN:** No per-user authentication. Shared PIN can't revoke a single user.
- **No offline sync:** iOS app uses MultipeerConnectivity but full store-and-forward mesh is not implemented.
- **County transfer panel 5s poll:** Works well for lab testing; production could benefit from WebSocket push from county to team dashboards.
- **No county PIN on loanable/transfer routes:** The county proxy routes in the Backend require the team PIN but the county-side routes are currently open (protected only if COUNTY_PIN is set).

---

## Quick Reference — Local Multi-Team Testing

```bash
# Start all 3 services (county + team-alpha + team-beta)
cd "CERT Command"
docker compose -f docker-compose.local.yml up --build

# Check in to team alpha (port 8080, memberPin 0000)
./Backend/test_checkin.sh alpha Frank
./Backend/test_checkin.sh alpha "Sarah Johnson" "Medical Specialist" 0000

# Check in to team beta (port 8081)
./Backend/test_checkin.sh beta Mike
./Backend/test_checkin.sh beta "Jane Smith" "Team Leader" 0000

# Dashboards
open http://localhost:8080/dashboard   # Alpha  (dashboard PIN: 1111)
open http://localhost:8081/dashboard   # Beta   (dashboard PIN: 2222)
open http://localhost:8090/county      # County (no PIN)
```

See `DEPLOYMENT.md` for full production and local deployment details.

---

## Contact
Frank Gadot — W6FGC
