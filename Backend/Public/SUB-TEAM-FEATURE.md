# Sub-Team Feature Implementation

**Implemented:** June 14, 2026  
**Status:** ✅ Complete - Ready for Testing

---

## Overview

The sub-team feature allows team leaders to organize CERT members into color-coded teams of 2+ people. This implements your core vision where:

- Sub-teams are the unit of assignment (not individuals)
- Each sub-team has a color identifier (Red, Blue, Green, Yellow, Purple, Orange, Teal, Pink)
- Reports are attributed to the submitting sub-team
- Tasks are assigned to sub-teams
- Team leader can re-assign report severity

---

## What Was Built

### Backend Changes

#### 1. Data Models (`CERTModels.swift`)

**New `SubTeam` struct:**
```swift
struct SubTeam: Content {
    var id: UUID?
    var color: TeamColor
    var memberIDs: [UUID]
    var assignedTaskID: UUID?
    var createdAt: Date
    var lastUpdated: Date
    
    enum TeamColor: String, Codable, CaseIterable {
        case red, blue, green, yellow, purple, orange, teal, pink
        var hexColor: String { /* Returns hex color */ }
    }
}
```

**Updated Models:**
- `CERTMember`: Added `subTeamID: UUID?`
- `IncidentReport`: Added `subTeamID: UUID?` (tracks which sub-team submitted)
- `CERTTask`: Added `assignedSubTeamID: UUID?`
- `DashboardData`: Added `subTeams: [SubTeam]`

#### 2. API Endpoints (`routes.swift`)

**Sub-Team Management:**
- `POST /api/subteams` - Create new sub-team
- `GET /api/subteams` - Get all sub-teams
- `PUT /api/subteams/:id` - Update sub-team
- `DELETE /api/subteams/:id` - Delete sub-team and unassign members

**Report Management:**
- `PATCH /api/reports/:id/severity` - Team leader can override report severity

**DataStore Actor Methods:**
- `createSubTeam()` - Creates sub-team and assigns members
- `updateSubTeam()` - Updates membership, unassigns old members
- `deleteSubTeam()` - Removes sub-team and sets members back to available
- Auto-updates member status when assigned to sub-team

### Dashboard Changes (`dashboard.html`)

#### Visual Features

**1. Sub-Team Counter Card:**
- Shows total number of active sub-teams
- Flashes when count changes

**2. Sub-Team Management Panel:**
- Lists all active sub-teams
- Shows color badge, member count, and member names
- Delete button for each sub-team
- "Create Sub-Team" button

**3. Color Badges:**
- Members show their sub-team color badge
- Reports show submitting sub-team badge
- Tasks show assigned sub-team badge

**4. Create Sub-Team Modal:**
- Dropdown to select team color (8 colors available)
- Checkbox list of available members
- Validates minimum 2 members
- Only shows "Available" members not in another sub-team

#### UI/UX

**Color Palette:**
- 🔴 Red: #dc3545
- 🔵 Blue: #0d6efd
- 🟢 Green: #198754
- 🟡 Yellow: #ffc107
- 🟣 Purple: #6f42c1
- 🟠 Orange: #fd7e14
- 🔷 Teal: #20c997
- 🩷 Pink: #d63384

**Animations:**
- Cards flash when data changes
- Smooth slide-in animations for new items
- Real-time WebSocket updates

---

## How to Use

### Team Leader Workflow

**1. Members Check In**
```
Team members use mobile app or API to check in:
POST /api/checkin
{
  "name": "Frank Gadot",
  "role": "CERT Member",
  "status": "Available",
  "equipment": ["Radio", "First Aid Kit"]
}
```

**2. Create Sub-Teams**
1. Open dashboard at https://cert.w6fgc.com/dashboard
2. Click "+ Create Sub-Team" button
3. Select team color (e.g., "Red Team")
4. Check at least 2 available members
5. Click "Create Sub-Team"

Result:
- Sub-team appears in list with color badge
- Members are automatically marked as "Assigned"
- Members show their team color badge

**3. Assign Tasks to Sub-Teams**
```
POST /api/tasks
{
  "title": "Check Oak Street for damage",
  "description": "Assess homes 100-200 block",
  "assignedSubTeamID": "<red-team-id>",
  "priority": "High",
  "status": "Assigned"
}
```

**4. Sub-Teams Submit Reports**
```
POST /api/reports
{
  "type": "Tree Down",
  "severity": "Medium",
  "subTeamID": "<red-team-id>",
  "reportedBy": "<member-id>",
  "location": {...},
  "notes": "Large oak blocking road"
}
```

**5. Team Leader Reviews Reports**
- Dashboard shows all reports with sub-team color badges
- If severity needs adjustment:
```
PATCH /api/reports/<report-id>/severity
{
  "severity": "High"  // Team leader overrides from Medium to High
}
```

**6. Disband Sub-Team (End of Shift)**
- Click "Delete" button on sub-team
- Confirms action
- Members automatically set back to "Available"

---

## Testing

### Test Scenario 1: Create Sub-Team

**Prerequisites:**
- At least 2 members checked in with "Available" status

**Steps:**
1. Open dashboard
2. Click "+ Create Sub-Team"
3. Select "Red" team
4. Check 2-3 members
5. Click "Create Sub-Team"

**Expected Result:**
- Modal closes
- Red team appears in sub-team list
- Member count badge shows correct number
- Members show red badge in member list
- Sub-team counter increments

### Test Scenario 2: WebSocket Real-Time Update

**Prerequisites:**
- Dashboard open in browser

**Steps:**
1. Use test script to check in a member:
```bash
cd Backend
./test_checkin.sh
```

2. Create sub-team via API:
```bash
curl -X POST https://cert.w6fgc.com/api/subteams \
  -H "Content-Type: application/json" \
  -d '{
    "color": "Blue",
    "memberIDs": ["<member-id-1>", "<member-id-2>"],
    "createdAt": "2026-06-14T12:00:00Z",
    "lastUpdated": "2026-06-14T12:00:00Z"
  }'
```

**Expected Result:**
- Dashboard updates immediately without refresh
- Blue team appears
- Members move from "Available" to "Assigned"
- Smooth animations

### Test Scenario 3: Delete Sub-Team

**Prerequisites:**
- At least one sub-team exists

**Steps:**
1. Click "Delete" button on a sub-team
2. Confirm deletion

**Expected Result:**
- Sub-team removed from list
- Members return to "Available" status
- Red badges removed from members
- Sub-team counter decrements

### Test Scenario 4: Report Attribution

**Prerequisites:**
- Sub-team created (e.g., Green Team)

**Steps:**
1. Submit report with subTeamID:
```bash
curl -X POST https://cert.w6fgc.com/api/reports \
  -H "Content-Type: application/json" \
  -d '{
    "type": "Tree Down",
    "severity": "Medium",
    "subTeamID": "<green-team-id>",
    "reportedBy": "<member-id>",
    "location": {
      "latitude": 28.5,
      "longitude": -81.5,
      "address": "123 Main St",
      "timestamp": "2026-06-14T12:00:00Z"
    },
    "notes": "Oak tree blocking road",
    "status": "New",
    "reportedAt": "2026-06-14T12:00:00Z",
    "lastUpdated": "2026-06-14T12:00:00Z"
  }'
```

**Expected Result:**
- Report appears in dashboard with green team badge
- Report severity shows "Medium"

### Test Scenario 5: Override Report Severity

**Prerequisites:**
- Report exists with "Medium" severity

**Steps:**
```bash
curl -X PATCH https://cert.w6fgc.com/api/reports/<report-id>/severity \
  -H "Content-Type: application/json" \
  -d '{"severity": "High"}'
```

**Expected Result:**
- Report severity changes to "High"
- Dashboard updates in real-time
- Severity badge changes color

---

## Architecture Flow

```
Team Leader Dashboard
        ↓
   Creates Sub-Team
        ↓
POST /api/subteams
        ↓
    DataStore Actor
        ↓
  Updates Members
  (status → Assigned)
        ↓
  Broadcast via WebSocket
        ↓
   Dashboard Updates
   (shows color badges)
        
        
Field Team (Mobile App)
        ↓
   Submits Report
   (includes subTeamID)
        ↓
POST /api/reports
        ↓
    DataStore Actor
        ↓
  Broadcast via WebSocket
        ↓
   Dashboard Shows Report
   (with team color badge)
```

---

## Known Limitations

### Current Implementation

1. **No persistence** - Data lost on server restart (in-memory only)
   - **Solution needed:** Add SQLite/PostgreSQL database

2. **No authentication** - Anyone can create/delete sub-teams
   - **Solution needed:** Add team leader PIN or credentials

3. **No sub-team editing** - Can only delete and recreate
   - **Solution needed:** Add edit modal to change members

4. **No task-to-subteam UI** - Can assign via API but not dashboard
   - **Solution needed:** Add task creation UI with sub-team dropdown

5. **Mobile app not connected** - iOS app doesn't use these APIs yet
   - **Solution needed:** Implement network layer in iOS app

### Design Decisions

1. **Minimum 2 members per sub-team**
   - Enforced in UI validation
   - Not enforced in backend (should add)

2. **One sub-team per member**
   - Member can only be in one sub-team at a time
   - Automatically unassigned from old team if reassigned

3. **Deleting sub-team unassigns members**
   - Members return to "Available" status
   - Could keep as "Assigned" for audit trail

---

## Next Steps

### Immediate (Do This Week)

1. **Test the implementation**
   - Use test_checkin.sh to create members
   - Create sub-teams via dashboard
   - Test WebSocket updates

2. **Add backend validation**
   - Minimum 2 members per sub-team
   - Unique color per active sub-team
   - Validate member exists before adding

3. **Update test script**
   - Add sub-team creation examples
   - Add report submission with sub-team

### Short-Term (Before Production)

4. **Add database persistence**
   - SQLite for development
   - PostgreSQL for production
   - Migration script for data models

5. **Add authentication**
   - Team leader PIN for dashboard
   - API keys for mobile apps
   - JWT tokens for session management

6. **Add task assignment UI**
   - Create task modal with sub-team dropdown
   - Show assigned sub-team on task cards
   - Allow reassignment

7. **Connect iOS app**
   - Network service layer
   - API integration
   - Sync local MultipeerConnectivity with server

### Long-Term (Nice to Have)

8. **Sub-team editing**
   - Add/remove members from existing sub-team
   - Change sub-team color
   - Merge/split sub-teams

9. **Sub-team analytics**
   - Reports completed per sub-team
   - Tasks assigned per sub-team
   - Time tracking

10. **Map view with sub-teams**
    - Show sub-team locations on map
    - Color-code markers by team
    - Track movement history

---

## API Reference

### Create Sub-Team

```http
POST /api/subteams
Content-Type: application/json

{
  "color": "Red",
  "memberIDs": ["uuid1", "uuid2"],
  "createdAt": "2026-06-14T12:00:00Z",
  "lastUpdated": "2026-06-14T12:00:00Z"
}
```

**Response:**
```json
{
  "id": "generated-uuid",
  "color": "Red",
  "memberIDs": ["uuid1", "uuid2"],
  "assignedTaskID": null,
  "createdAt": "2026-06-14T12:00:00Z",
  "lastUpdated": "2026-06-14T12:00:00Z"
}
```

### Get All Sub-Teams

```http
GET /api/subteams
```

**Response:**
```json
[
  {
    "id": "uuid",
    "color": "Red",
    "memberIDs": ["uuid1", "uuid2"],
    "assignedTaskID": null,
    "createdAt": "2026-06-14T12:00:00Z",
    "lastUpdated": "2026-06-14T12:00:00Z"
  }
]
```

### Update Sub-Team

```http
PUT /api/subteams/{id}
Content-Type: application/json

{
  "color": "Red",
  "memberIDs": ["uuid1", "uuid2", "uuid3"],
  "createdAt": "2026-06-14T12:00:00Z",
  "lastUpdated": "2026-06-14T13:00:00Z"
}
```

### Delete Sub-Team

```http
DELETE /api/subteams/{id}
```

**Response:** 200 OK

### Override Report Severity

```http
PATCH /api/reports/{id}/severity
Content-Type: application/json

{
  "severity": "High"
}
```

**Response:**
```json
{
  "id": "report-uuid",
  "type": "Tree Down",
  "severity": "High",
  "subTeamID": "team-uuid",
  ...
}
```

---

## Files Modified

### Backend

1. **`Backend/Sources/CERTModels.swift`**
   - Added `SubTeam` struct with `TeamColor` enum
   - Added `subTeamID` to `CERTMember`
   - Added `subTeamID` to `IncidentReport`
   - Added `assignedSubTeamID` to `CERTTask`
   - Updated `DashboardData` to include `subTeams`

2. **`Backend/Sources/routes.swift`**
   - Added `subTeams` storage to `DataStore` actor
   - Added `createSubTeam()`, `updateSubTeam()`, `deleteSubTeam()` methods
   - Added `updateMember()`, `updateReport()`, `updateTask()` methods
   - Added `/api/subteams` endpoints (POST, GET, PUT, DELETE)
   - Added `/api/reports/:id/severity` PATCH endpoint
   - Updated `getDashboardData()` to include sub-teams

3. **`Backend/Public/dashboard.html`**
   - Added sub-team counter card
   - Added sub-team management panel
   - Added create sub-team modal
   - Added color badge styles (8 colors)
   - Added sub-team list rendering
   - Updated member/report/task lists to show team badges
   - Added JavaScript functions for sub-team CRUD operations
   - Added real-time WebSocket updates for sub-teams

---

## Deployment

**Current Status:** Code ready, not yet deployed to cert.w6fgc.com

**To deploy:**

```bash
# On your Mac
cd ~/DEV/XCODE/CERT\ Assist
git add .
git commit -m "Implement sub-team color-coding system"
git push origin main

# On Ubuntu server
ssh user@cert.w6fgc.com
cd ~/cert-assist  # or wherever you cloned the repo
git pull origin main
cd Backend
docker-compose down
docker-compose up -d --build

# Watch logs
docker-compose logs -f
```

**Verify deployment:**
1. Open https://cert.w6fgc.com/dashboard
2. Should see new "Sub-Teams" counter card
3. Should see "Create Sub-Team" button
4. Test creating a sub-team

---

## Contact

Frank Gadot - W6FGC

**Questions or Issues:**
- Check logs: `docker-compose logs -f`
- Test API: `curl https://cert.w6fgc.com/api/dashboard`
- WebSocket: Check browser console for connection status

---

**Last Updated:** June 14, 2026  
**Feature Status:** ✅ Complete - Ready for Testing
