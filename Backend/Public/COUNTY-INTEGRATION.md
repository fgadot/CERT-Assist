# County Integration Architecture

**Last Updated:** July 10, 2026  
**Status:** ✅ Fully working

This document covers the county ↔ team server integration: architecture decisions, data flow, the critical JSON key strategy gotcha, and debugging history. Read this before touching any county-related code.

---

## Architecture Overview

County and team servers communicate via plain HTTP. There is no persistent connection from county to teams — teams always initiate.

```
Team Server                    County Server
    |                               |
    |── POST /api/teams/summary ──→ |   (on every state change, if memberCount > 0)
    |                               |
    |←── GET /api/messages ────────|   (team polls every 30s)
    |── POST /api/messages/:id/confirm →|
    |                               |
    |── POST /api/available-members → |  (when member marked loanable)
    |── DELETE /api/available-members/:id → | (when loanable cleared)
    |                               |
    |── GET /api/available-members ─→ |  (team dashboard polls every 5s)
    |── POST /api/transfer-requests → |
    |── PUT /api/transfer-requests/:id → |
```

County dashboard connects via WebSocket to county server. Every time county receives a team push or state change, it broadcasts the updated `CountyDashboardData` to all connected dashboards.

Team dashboards do NOT connect to county's WebSocket. They only poll via HTTP.

---

## Critical: JSON Key Strategy — The `...Id` vs `...ID` Rule

**This is the most common source of silent bugs in this codebase. Read carefully.**

Both servers use:
```swift
encoder.keyEncodingStrategy = .convertToSnakeCase
decoder.keyDecodingStrategy = .convertFromSnakeCase
```

The strategy transforms property names as follows:

| Property name | Encoded as | Decoded back as |
|--------------|------------|-----------------|
| `teamId` | `team_id` | `teamId` ✅ |
| `teamID` | `team_id` | `teamId` ← **MISMATCH** if property is `teamID` |
| `memberId` | `member_id` | `memberId` ✅ |
| `memberID` | `member_id` | `memberId` ← **MISMATCH** |

**Why:** `convertToSnakeCase` encodes both `teamId` and `teamID` as `team_id` (correct). But `convertFromSnakeCase` decodes `team_id` as `teamId` (lowercase d) — it cannot produce `teamID` (uppercase D). So if the receiving struct has `teamID`, the decode silently fails.

**The rule:** All ID-bearing properties MUST use lowercase `d`:
- ✅ `teamId`, `memberId`, `reportId`, `requestingTeamId`, `owningTeamId`
- ❌ `teamID`, `memberID`, `reportID` — will decode as nil/empty silently

**Note on `try?`:** All `countyDecode()` calls use `try?`. A decode failure returns `nil`, which becomes `[] ?? []` for arrays. This is why the bug shows up as an empty list rather than an error.

### Affected files and current correct state

| File | Properties that were fixed |
|------|--------------------------|
| `CountyServer/Sources/App/Models/CountyModels.swift` | All `...Id` (lowercase d) throughout |
| `CountyServer/Sources/App/routes.swift` | All `...Id` throughout |
| `Backend/Sources/App/Models/CERTModels.swift` | `CountyMessage.targetTeamId`, `CountyMessage.reportId`, `AvailableMember.memberId/teamId`, `TransferRequest.requestingTeamId/owningTeamId/memberId` |
| `Backend/Sources/App/routes.swift` | All county proxy routes use `...Id` |

`TeamSummary` in `CERTModels.swift` still uses `teamID` (uppercase) because it is only ever **encoded** (sent to county), and `convertToSnakeCase` handles it correctly on the way out. The county's own `TeamSummary` struct uses `teamId` (lowercase) for decoding.

---

## County Visibility Rules

**County dashboard only shows teams with `memberCount > 0`.**

This is enforced in two places:
1. **Team side** (`Backend/Sources/App/routes.swift`, `pushToCounty()`): skips the push entirely if `members.isEmpty`. County never even stores a phantom entry.
2. **County side** (`CountyServer/Sources/App/routes.swift`, `getDashboardData()`): filters `teams.values.filter { $0.memberCount > 0 }` before building the dashboard response.

**Result:** A team appears on the county dashboard only after the first member checks in. A team disappears if its `memberCount` drops to 0.

---

## Team → County Push Flow

Every call to `dataStore.broadcastUpdate()` on the team server also fires `pushToCounty()` (fire-and-forget `Task`). `pushToCounty()`:
1. Guards `!members.isEmpty` — skips if no members
2. Builds `TeamSummary` via `buildTeamSummary()`
3. Encodes with `convertToSnakeCase`
4. POSTs to `$COUNTY_ENDPOINT/api/teams/summary`

On startup, `configure.swift` fires an initial `broadcastUpdate()` after a 3-second delay. Since `members` is empty at startup, `pushToCounty()` skips — county sees nothing until first check-in.

---

## County → Team Message Flow (Polling)

`configure.swift` starts a background loop that polls `GET $COUNTY_ENDPOINT/api/messages?team=$TEAM_ID` every 30 seconds. For each message:
1. Calls `dataStore.applyCountyMessage(message)` to process it locally
2. POSTs to `$COUNTY_ENDPOINT/api/messages/:id/confirm` to clear it
3. Calls `dataStore.broadcastUpdate()` so dashboard reflects the change via WebSocket

`alert` and `info` messages are saved into `DataStore.countyInbox` (last 50), which is included in `DashboardData` and pushed to the team dashboard via WebSocket. The team dashboard renders a **County Messages** panel and triggers browser notifications and a toast when new messages arrive.

Message types:
| Type | Effect on team |
|------|---------------|
| `acknowledgment` | Marks a report as `acknowledgedByCounty = true` |
| `alert` | Saved to `countyInbox`, shown in panel (red), browser notification triggered |
| `info` | Saved to `countyInbox`, shown in panel (blue), browser notification triggered |
| `transferRequest` | Logged — owning team sees request in Transfer Panel (5s poll) |
| `transferResponse` | Logged — requesting team sees accept/deny in Transfer Panel |
| `transferRelease` | Clears `lentToTeam` on member — member returns to alpha's roster |
| `transferRecallRequest` | Logged — beta team sees recall notice in Transfer Panel |

---

## County → All Teams Broadcast

County can send a message to **all registered teams** at once:

```
POST /api/broadcast  { type: "alert" | "info", text: "…" }
```

This creates a `CountyMessage` for every key in `countyStore.teams` (all teams that have ever pushed a summary, regardless of member count). Each team picks it up on its next 30s poll.

County dashboard: the **📢 Broadcast** button in the header opens a modal with type selector and message field.

---

## Team → County Flags

Team leads can raise a flag for the County EOC to review:

```
Team dashboard → "📣 Flag for County" button
    → POST /api/county/flag { text: "…" }       (to team's own backend)
    → Backend proxies to county: POST /api/team-flags { teamId, teamName, text }

County dashboard → "Flags from Teams" section (polls every 15s)
    → GET /api/team-flags
    → POST /api/team-flags/:id/acknowledge
```

Flags are displayed below the team grid on the county dashboard with an unread count badge. Acknowledged flags dim and show a checkmark.

**Key distinction from messages:** Messages flow county → team (downward). Flags flow team → county (upward). They use completely separate stores.

---

## Cross-Team Member Transfer Flow

```
Team Alpha marks member loanable
    → PATCH /api/members/:id/loanable { loanable: true }
    → Alpha backend POSTs AvailableMember to county

Team Beta's Transfer Panel (polls county every 5s)
    → GET /api/county/available-members (proxied through Beta's backend)
    → Backend calls county GET /api/available-members?exclude=beta
    → Renders available members list

Beta clicks "Request"
    → POST /api/county/transfer-requests { owning_team_id, member_id, member_name }
    → County creates TransferRequest + queues CountyMessage for Alpha
    → Alpha picks up the message on next 30s poll

Alpha accepts/denies (in Alpha's Transfer Panel)
    → PUT /api/county/transfer-requests/:id { status: "Accepted" }
    → County queues CountyMessage for Beta
    → If Accepted: county removes member from available list
    → Alpha backend calls setLoanable(false) for that member
    → Beta picks up the response on next 30s poll
```

---

## Local Development — SSRF Relaxation

Production SSRF validation requires `https://` endpoints. For local testing, the county server allows `http://localhost` and `http://127.0.0.1`:

**County server** (`routes.swift`):
```swift
let isLocalHTTP = endpoint.hasPrefix("http://localhost") || endpoint.hasPrefix("http://127.0.0.1")
guard (endpoint.hasPrefix("https://") || isLocalHTTP), URL(string: endpoint) != nil else { ... }
```

**County dashboard JS** (`county.html`, `isSafeEndpoint()`):
```javascript
if (parsed.protocol === 'http:') {
    return parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
}
```

In production (`docker-compose.yml`), `TEAM_ENDPOINT` is set to the team's public HTTPS URL. In `docker-compose.local.yml`, it is set to `http://localhost:8080` / `http://localhost:8081`.

---

## docker-compose.local.yml

Located at repo root. Runs county + team-alpha + team-beta on a shared Docker network.

```yaml
county:      port 8090  COUNTY_PIN=(empty)
team-alpha:  port 8080  TEAM_ID=alpha  TEAM_PIN=1111  TEAM_ENDPOINT=http://localhost:8080
team-beta:   port 8081  TEAM_ID=beta   TEAM_PIN=2222  TEAM_ENDPOINT=http://localhost:8081
```

Teams reach county internally via `http://county:8080` (Docker network alias). The browser reaches teams via `localhost:8080` / `localhost:8081`.

PIN config files for local test:
- `local-test/alpha/config/pins.json` → `{"dashboardPin":"1111","memberPin":"0000"}`
- `local-test/beta/config/pins.json` → create if missing (copy alpha, change dashboardPin to "2222")

---

## Debugging Checklist

**County dashboard shows "Waiting for teams…" (no teams appear)**
1. Check team container logs for `POST /api/teams/summary` — is it sending?
2. Look for `No such key` warnings in county logs — means a property name uses `...ID` instead of `...Id`
3. Verify a member is actually checked in (teams only push when `members.count > 0`)
4. Check SSRF: if `TEAM_ENDPOINT` is `http://localhost`, verify the county SSRF guard allows it

**Transfer panel shows no available members**
1. Check that the loanable toggle sent `PATCH /api/members/:id/loanable` successfully
2. Check county logs for `POST /api/available-members` — did it arrive?
3. Check `countyDecode` in the team backend — if it returns nil, the struct has an `...ID` mismatch
4. Verify `AvailableMember` and `TransferRequest` structs in `CERTModels.swift` all use `...Id`

**County messages not arriving at team**
1. Check that the 30s poll loop started (look for log: `County endpoint: http://... — startup push + polling every 30s`)
2. Check `GET /api/messages?team=TEAM_ID` manually — does it return messages?
3. Check for `CountyMessage.targetTeamId` decode issues (must be lowercase `d`)

**County Messages panel not showing on team dashboard**
1. Verify `countyInbox` is populated: `DataStore.countyInbox` is only filled for `alert` and `info` types
2. Check that `DashboardData.countyInbox` is included in the WebSocket push
3. Panel is shown only if `countyConfig.county_enabled` is true

**Team flag not appearing on county dashboard**
1. Check team backend log: `POST /api/county/flag` → proxied to county `/api/team-flags`
2. County uses PIN auth — verify `COUNTY_PIN` env var matches
3. Flags section polls every 15s; wait one cycle or click browser refresh

---

## Files Reference

| File | Role |
|------|------|
| `CountyServer/Sources/App/routes.swift` | County DataStore actor, all county API routes |
| `CountyServer/Sources/App/Models/CountyModels.swift` | County-side struct definitions |
| `CountyServer/Public/county.html` | County dashboard UI (volume-mounted, hot-reload) |
| `Backend/Sources/App/configure.swift` | Startup push + 30s county polling loop |
| `Backend/Sources/App/routes.swift` | Team DataStore, `pushToCounty()`, county proxy routes |
| `Backend/Sources/App/Models/CERTModels.swift` | Team-side struct definitions (incl. county types) |
| `docker-compose.local.yml` | 3-service local lab environment |
| `Backend/test_checkin.sh` | CLI check-in script; `test_checkin.sh [alpha|beta] <name> [role] [pin]` |
