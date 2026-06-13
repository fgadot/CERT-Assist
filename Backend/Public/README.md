# CERT-Assist Field Board

Emergency response coordination system for Community Emergency Response Teams (CERT).

## Project Status
- **Created**: June 9, 2026
- **Server**: cert.w6fgc.com
- **Platform**: iOS app + Web dashboard + Swift backend

## Architecture

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

### Web Dashboard (HTML/JS/CSS)
Located in `/Backend/Public/dashboard.html`
- Real-time incident commander dashboard
- WebSocket connection to backend
- Live stats: team members, active reports, open tasks
- Color-coded status indicators
- Auto-reconnecting WebSocket

## Communication Strategy (Disaster Resilience)

**Tier 1: Internet Available**
- iOS app → Cloud server (cert.w6fgc.com) → Web dashboard
- Full real-time coordination

**Tier 2: Internet Down, Local Network**
- MultipeerConnectivity for peer-to-peer device sync
- WiFi Direct / Bluetooth LE mesh

**Tier 3: Cell Towers Down**
- Meshtastic integration planned
- LoRa mesh network for text-based status updates
- Long-range, low-bandwidth emergency comms

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

## Deployment

### Ubuntu Server (cert.w6fgc.com)
Backend will run as systemd service with nginx reverse proxy.

## TODO / Next Steps
- [ ] Connect iOS app to backend API (network service layer)
- [ ] Deploy backend to cert.w6fgc.com
- [ ] Add database persistence (SQLite or PostgreSQL)
- [ ] Implement Meshtastic integration
- [ ] Add SSL/HTTPS configuration
- [ ] Add authentication/authorization
- [ ] Map view on web dashboard
- [ ] Photo upload capability for damage reports
- [ ] Offline mode with sync when connectivity restored

## Development Notes
- Using Swift 5.9+
- Vapor 4.89.0 for backend
- SwiftUI for iOS app
- Vanilla JavaScript for dashboard (no frameworks)
- Git repository backed up

## Contact
Frank Gadot - W6FGC
