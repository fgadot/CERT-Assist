#!/bin/bash

# Team selector: first arg can be "alpha" or "beta"; defaults to alpha
# Usage: test_checkin.sh [alpha|beta] <name> [role] [pin]

TEAM_ARG="$1"

if [[ "$TEAM_ARG" == "alpha" || "$TEAM_ARG" == "beta" ]]; then
    TEAM="$TEAM_ARG"
    shift
else
    TEAM="alpha"
fi

if [ -z "$1" ]; then
    echo "Usage: test_checkin.sh [alpha|beta] <name> [role] [pin]"
    echo ""
    echo "Examples:"
    echo "  test_checkin.sh Frank"
    echo "  test_checkin.sh alpha Frank"
    echo "  test_checkin.sh beta \"Sarah Johnson\" \"Medical Specialist\""
    echo "  test_checkin.sh alpha Frank \"CERT Member\" 0000"
    echo ""
    echo "  Team defaults to 'alpha' if not specified."
    echo "  PIN is the MEMBER PIN (set in Settings ⚙️ on the dashboard, not the dashboard PIN)."
    exit 1
fi

NAME="$1"
ROLE="${2:-CERT Member}"
PIN="${3:-}"

# Resolve server and dashboard URL from team name (or CERT_SERVER env override)
if [ -n "$CERT_SERVER" ]; then
    SERVER="$CERT_SERVER"
elif [ "$TEAM" = "beta" ]; then
    SERVER="http://localhost:8081"
else
    SERVER="http://localhost:8080"
fi

echo "🚨 Checking in:"
echo "   Team:   $TEAM"
echo "   Name:   $NAME"
echo "   Role:   $ROLE"
echo "   PIN:    ${PIN:-(none — open access)}"
echo "   Server: $SERVER"
echo ""

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$SERVER/api/checkin" \
  -H "Content-Type: application/json" \
  -H "X-CERT-Token: $PIN" \
  -d "{
    \"name\": \"$NAME\",
    \"role\": \"$ROLE\",
    \"status\": \"Available\",
    \"equipment\": [\"Radio\"],
    \"last_updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }")

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Check-in successful"
    echo "$HTTP_BODY" | python3 -m json.tool 2>/dev/null
elif [ "$HTTP_STATUS" = "401" ]; then
    echo "❌ Wrong PIN (HTTP 401)"
    echo "   Use the MEMBER PIN, not the dashboard PIN."
    echo "   Find it in Settings ⚙️ → Member Access PIN on the dashboard."
    echo "   Server said: $HTTP_BODY"
elif [ "$HTTP_STATUS" = "000" ]; then
    echo "❌ Cannot reach $SERVER — is the server running?"
elif [ -z "$HTTP_STATUS" ]; then
    echo "❌ No response from server"
else
    echo "❌ Server error (HTTP $HTTP_STATUS)"
    echo "   Response: $HTTP_BODY"
fi

echo ""
echo "📺 Dashboard: $SERVER/dashboard"
echo "🗺️  County:    http://localhost:8090/county"
