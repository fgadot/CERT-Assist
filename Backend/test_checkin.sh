#!/bin/bash

# Default to localhost, but allow override
SERVER="${CERT_SERVER:-http://localhost:8080}"

if [ -z "$1" ]; then
    echo "Usage: test_checkin.sh <name> [role] [pin]"
    echo ""
    echo "Examples:"
    echo "  test_checkin.sh Frank"
    echo "  test_checkin.sh \"Sarah Johnson\" \"Medical Specialist\""
    echo "  test_checkin.sh Frank \"CERT Member\" 4012"
    echo ""
    echo "Server: $SERVER (set CERT_SERVER env var to change)"
    exit 1
fi

NAME="$1"
ROLE="${2:-CERT Member}"
PIN="${3:-}"

echo "🚨 Checking in:"
echo "   Name: $NAME"
echo "   Role: $ROLE"
echo "   PIN:  ${PIN:-(none)}"
echo "   Server: $SERVER"

curl -s -X POST "$SERVER/api/checkin" \
  -H "Content-Type: application/json" \
  -H "X-CERT-Token: $PIN" \
  -d "{
    \"name\": \"$NAME\",
    \"role\": \"$ROLE\",
    \"status\": \"Available\",
    \"equipment\": [\"Radio\"],
    \"last_updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }" | python3 -m json.tool 2>/dev/null || echo "(no JSON response)"

echo ""
if [[ "$SERVER" == *"localhost"* ]]; then
    echo "✅ Check the dashboard: http://localhost:8080/dashboard"
else
    echo "✅ Check the dashboard: $SERVER/dashboard"
fi
