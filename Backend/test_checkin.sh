#!/bin/bash

# Default to localhost, but allow override
SERVER="${CERT_SERVER:-http://localhost:8080}"

# Check if name was provided
if [ -z "$1" ]; then
	echo "Usage: test_checkin.sh <name> [role] [ics-position]"
	echo ""
	echo "Examples:"
	echo "  test_checkin.sh Frank"
	echo "  test_checkin.sh \"Sarah Johnson\" \"Medical Specialist\" \"Operations - Medical/Triage\""
	echo "  test_checkin.sh Mike \"CERT Member\" \"Logistics - Communications\""
	echo ""
	echo "ICS Positions:"
	echo "  - Incident Commander"
	echo "  - Operations - Medical/Triage"
	echo "  - Operations - Search & Rescue"
	echo "  - Logistics - Communications"
	echo "  - Planning - Documentation"
	echo "  (and more...)"
	echo ""
	echo "Server: $SERVER (set CERT_SERVER env var to change)"
	exit 1
fi

NAME="$1"
ROLE="${2:-CERT Member}"
ICS_POSITION="${3:-Not Assigned}"

echo "🚨 Checking in:"
echo "   Name: $NAME"
echo "   Role: $ROLE"
echo "   ICS Position: $ICS_POSITION"
echo "   Server: $SERVER"

curl -X POST "$SERVER/api/checkin" \
  -H "Content-Type: application/json" \
  -d "{
	\"name\": \"$NAME\",
	\"role\": \"$ROLE\",
	\"icsPosition\": \"$ICS_POSITION\",
	\"status\": \"Available\",
	\"equipment\": [\"Radio\"],
	\"lastUpdated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }"

echo ""
if [[ "$SERVER" == *"localhost"* ]]; then
	echo "✅ Check the dashboard: http://localhost:8080/dashboard"
else
	echo "✅ Check the dashboard: $SERVER/dashboard"
fi
