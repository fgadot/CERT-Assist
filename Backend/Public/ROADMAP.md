# CERT Command — Roadmap & Future Enhancements

**Created:** July 10, 2026  
**Purpose:** Track ideas, planned features, and scaling considerations. Update this file as decisions are made.

---

## Push Notifications

### Current: Browser Notifications API (implemented)
- Triggered when a new county message arrives via WebSocket
- Works in all modern browsers (Chrome, Safari, Firefox, iOS Safari PWA)
- Requires user permission — prompted on first dashboard load
- Zero infrastructure cost

### Near-term: Web Push (VAPID)
When polling latency (30s) is too slow or you need notifications when the dashboard tab is closed:
- Generate a VAPID key pair (once, store in env vars)
- Each browser registers a `PushSubscription` on page load; county stores it
- County POSTs push notifications directly to browser vendors (Google/Apple relay) on message creation
- Works on mobile home screen apps (PWA installed)
- No third-party SDK needed — standard `web-push` library or roll your own
- **Complexity:** medium. Needs subscription storage (SQLite table).

### Long-term: APNs / FCM (for native iOS app)
- APNs for iOS app push notifications
- Firebase Cloud Messaging (FCM) as a unified layer for iOS + Android
- Requires Apple Developer account and APNs certificate rotation
- **When to add:** when the iOS app is in production and you need background alerts

---

## Persistence (SQLite)

### Current state
All data is in-memory. A server restart during an active incident loses:
- All members, reports, tasks
- County messages and flags
- Transfer requests and history

### What to persist (priority order)
1. **Incident reports** — loss during an active incident is unacceptable
2. **County inbox messages** — audit trail for EOC communication
3. **Team flags** — need acknowledgment history
4. **Transfer requests** — history and current status
5. **Members** — nice to have; check-in can re-establish on restart

### Implementation notes
- SQLite is already a dependency (Fluent + FluentSQLiteDriver in Package.swift)
- The DB file path is set in `configure.swift` (`data/cert_data.db`) — just not used yet
- Add Fluent models for each type, run migrations on boot
- **Effort:** 1–2 days per data type

---

## Scaling

### Current architecture handles well
- Up to ~300 teams with 30s polling: ~10 req/s to county server, trivially light
- A single $10/month VPS (2 vCPU, 2GB RAM) handles 300 teams comfortably
- WebSocket connections: only county dashboard operators hold persistent connections

### Potential bottlenecks at > 500 teams
- **In-memory state:** all team data is in a single `CountyDataStore` actor. At 500+ teams with high-frequency updates, the actor becomes a bottleneck
  - Fix: shard by region (multiple county servers behind a load balancer) OR use an external store (Redis) for shared state
- **30s poll storm:** 500 teams × 1 req/30s = ~17 req/s. Fine, but if teams reduce to 5s polling, 500 × 0.2 = 100 req/s. Still manageable on a $20/month server.
- **Message fan-out:** broadcasting to 500 teams creates 500 `CountyMessage` entries at once. In-memory this is fast; with SQLite writes it adds ~100ms. Acceptable.

### Horizontal scaling path (if needed)
1. Add Redis for shared state between county server instances
2. Put a load balancer (nginx or Caddy) in front of multiple county containers
3. Use sticky sessions for WebSocket connections

---

## Messaging Enhancements

### Message threading (team ↔ county per-conversation)
- Each team gets a message thread; county can reply in context
- Requires: thread ID, reply-to, message history endpoint
- **Complexity:** high (needs persistence first)

### Message read receipts
- County sees when a team has "read" (confirmed) a message
- Currently messages are confirmed silently; surface this in the county UI

### Message expiry / archiving
- Keep last N messages per team; archive older ones
- Important once SQLite persistence is in place

### Canned responses / templates
- County can send pre-defined messages with one click (e.g., "Shelter at current location", "Medical unit en route")
- Reduces typing under stress

---

## County Dashboard Enhancements

### Map view
- Show all active teams on a Mapbox/Leaflet map with their location
- Bubble size = member count, color = urgency level
- **Requires:** teams to set a lat/lon in their summary (currently just a text address)

### Incident timeline
- Chronological log of all events: reports, acks, messages, flags, member transfers
- Read-only audit trail for after-action review

### Resource tracking
- Track supplies (water, medical kits, radios) across all teams
- Teams mark what they have and need; county sees shortfalls across the incident
- **New model needed:** `TeamResource` with category, quantity, status

### County → team task assignment
- County assigns a task to a specific team; task appears in their task board
- Currently tasks are created within a team; county has no visibility or control

---

## Team Dashboard Enhancements

### Offline mode / service worker
- Cache the dashboard shell so it loads even without a server connection
- Queue report submissions locally; sync when reconnected
- **Requires:** Service Worker + IndexedDB

### Multiple language support (i18n)
- CERT teams often operate in multilingual environments
- Add locale files for Spanish as a starting point

### iOS app county integration
- The iOS app currently communicates only with the team backend
- Add county summary view and message inbox to the iOS app
- Show county flags/alerts as push notifications (APNs)

---

## Security Enhancements

### API rate limiting
- Add per-IP rate limiting to prevent brute-force on PIN endpoints
- Vapor has a middleware ecosystem for this; or use nginx upstream

### Message signing
- Sign county → team messages so teams can verify they came from the real county server
- Useful if teams are deployed across untrusted networks
- **Approach:** HMAC-SHA256 with a shared secret (COUNTY_PIN is already available)

### HTTPS enforcement in local dev
- Currently `http://localhost` is allowed for SSRF to simplify local dev
- Consider using mkcert for local HTTPS certs and removing the HTTP exception

### Audit log
- Record every state change with timestamp, actor, and action
- Already stubbed in `BackendSourcesAppModelsAuditLog.swift` — wire it up

---

## Operational

### Zero-downtime deploys
- Add health check endpoint (`GET /health`) with structured JSON response
- Configure Docker's `HEALTHCHECK` directive
- Use `docker-compose up --no-deps --build team-alpha` for rolling restarts

### Backup & restore
- Once SQLite is in place: cron job to copy `cert_data.db` to S3 / object storage every 5 minutes during an active incident

### Multi-county support
- A single county EOC currently manages all teams
- For regional incidents: add a hierarchy where county servers can aggregate to a state-level EOC
- **Architecture:** each county becomes a "team" from the state server's perspective; county servers push `CountySummary` upward

---

## Known Limitations (Current)

| Limitation | Impact | Fix |
|-----------|--------|-----|
| All state in-memory | Data lost on restart | SQLite persistence |
| 30s county poll latency | Messages delayed up to 30s | Web Push (VAPID) |
| No message history | Can't review past comms | SQLite + history endpoint |
| No team flag history | Acknowledged flags disappear on restart | SQLite persistence |
| Browser notifications require open tab | Misses alerts if tab is closed | Web Push service worker |
| Single county server | No failover | Redis-backed multi-instance |
