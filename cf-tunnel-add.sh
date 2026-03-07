#!/usr/bin/env bash

# Add a hostname -> service ingress rule to ~/.cloudflared/config.yml
# and restart the tunnel.
# Usage: cf-tunnel-add.sh <hostname> <service_url>
# Example: cf-tunnel-add.sh local-3003.canngo.us http://localhost:3003

set -e

CONFIG_FILE="${HOME}/.cloudflared/config.yml"
CATCH_ALL_PATTERN="  - service: http_status:404"

usage() {
  echo "Usage: $0 <hostname> <service_url>"
  echo "Example: $0 local-3003.canngo.us http://localhost:3003"
  exit 1
}

if [ $# -ne 2 ]; then
  usage
fi

HOSTNAME="$1"
SERVICE="$2"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

if grep -q "hostname: ${HOSTNAME}$" "$CONFIG_FILE"; then
  echo "Hostname already in config: $HOSTNAME"
  exit 0
fi

# Insert new ingress block before the catch-all rule
awk -v hostname="$HOSTNAME" -v service="$SERVICE" '
  /  - service: http_status:404/ && !inserted {
    print "  - hostname: " hostname
    print "    service: " service
    print "    originRequest:"
    print "      noTLSVerify: true"
    print "      disableChunkedEncoding: true"
    print ""
    inserted = 1
  }
  { print }
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "Added: $HOSTNAME -> $SERVICE"

# Read tunnel name from config (first line matching "tunnel: ...")
TUNNEL_NAME=$(grep -E '^tunnel:' "$CONFIG_FILE" | head -1 | sed 's/^tunnel:[[:space:]]*//')

if [ -z "$TUNNEL_NAME" ]; then
  echo "Could not read tunnel name from config. Restart the tunnel manually."
  exit 0
fi

# Restart tunnel: kill existing process and run in background
if pgrep -x "cloudflared" > /dev/null; then
  pkill -x "cloudflared" 2>/dev/null || true
  sleep 2
fi

nohup cloudflared tunnel run "$TUNNEL_NAME" > /dev/null 2>&1 &
echo "Tunnel restarted: $TUNNEL_NAME"
