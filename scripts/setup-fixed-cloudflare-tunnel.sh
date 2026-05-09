#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOSTNAME="${1:-${HOSTNAME:-}}"
TUNNEL_NAME="${TUNNEL_NAME:-juanmao}"
ROOM="${ROOM:-}"
PORT="${PORT:-8787}"
CLOUDFLARED="${CLOUDFLARED:-/opt/homebrew/bin/cloudflared}"
NODE_BIN="${NODE_BIN:-/opt/homebrew/bin/node}"
CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/juanmao-config.yml"
ROOM_PLIST="$HOME/Library/LaunchAgents/local.juanmao.room.plist"
TUNNEL_PLIST="$HOME/Library/LaunchAgents/local.juanmao.tunnel.plist"

export TUNNEL_NAME

if [ -z "$HOSTNAME" ]; then
  echo "Usage: $0 juanmao.example.com" >&2
  exit 2
fi

if [ -z "$ROOM" ]; then
  ROOM="$(openssl rand -hex 5)"
fi

if [ ! -x "$CLOUDFLARED" ]; then
  echo "cloudflared not found at $CLOUDFLARED" >&2
  echo "Install with: brew install cloudflared" >&2
  exit 1
fi

if [ ! -x "$NODE_BIN" ]; then
  echo "node not found at $NODE_BIN" >&2
  echo "Install with: brew install node" >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR" "$ROOT/dist"

if [ ! -f "$CONFIG_DIR/cert.pem" ]; then
  "$CLOUDFLARED" tunnel login
fi

TUNNEL_ID="$("$CLOUDFLARED" tunnel list --output json | "$NODE_BIN" -e '
const fs = require("fs");
const tunnels = JSON.parse(fs.readFileSync(0, "utf8"));
const name = process.env.TUNNEL_NAME;
const tunnel = tunnels.find((item) => item.name === name);
if (tunnel) process.stdout.write(tunnel.id);
' 2>/dev/null || true)"

if [ -z "$TUNNEL_ID" ]; then
  "$CLOUDFLARED" tunnel create "$TUNNEL_NAME"
  TUNNEL_ID="$("$CLOUDFLARED" tunnel list --output json | "$NODE_BIN" -e '
const fs = require("fs");
const tunnels = JSON.parse(fs.readFileSync(0, "utf8"));
const name = process.env.TUNNEL_NAME;
const tunnel = tunnels.find((item) => item.name === name);
if (!tunnel) process.exit(1);
process.stdout.write(tunnel.id);
' )"
fi

CREDENTIALS_FILE="$CONFIG_DIR/$TUNNEL_ID.json"
if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "Tunnel credentials not found: $CREDENTIALS_FILE" >&2
  exit 1
fi

cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE

ingress:
  - hostname: $HOSTNAME
    service: http://127.0.0.1:$PORT
  - service: http_status:404
protocol: http2
EOF

"$CLOUDFLARED" tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$HOSTNAME"

cat > "$ROOM_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.juanmao.room</string>
  <key>WorkingDirectory</key>
  <string>$ROOT</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PORT</key>
    <string>$PORT</string>
    <key>ROOM_SECRET</key>
    <string>$ROOM</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_BIN</string>
    <string>$ROOT/server/online-room.js</string>
  </array>
  <key>StandardOutPath</key>
  <string>/tmp/juanmao-room.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/juanmao-room.log</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF

cat > "$TUNNEL_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.juanmao.tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CLOUDFLARED</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>$CONFIG_FILE</string>
    <string>run</string>
  </array>
  <key>StandardOutPath</key>
  <string>/tmp/juanmao-cloudflared.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/juanmao-cloudflared.log</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$ROOM_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$ROOM_PLIST"
launchctl kickstart -k "gui/$(id -u)/local.juanmao.room"

launchctl bootout "gui/$(id -u)" "$TUNNEL_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$TUNNEL_PLIST"
launchctl kickstart -k "gui/$(id -u)/local.juanmao.tunnel"

PUBLIC_URL="https://$HOSTNAME"
printf "%s\n" "$PUBLIC_URL" > "$ROOT/dist/current-public-url.txt"
PUBLIC_URL="$PUBLIC_URL" ROOM="$ROOM" "$ROOT/scripts/package-release-apps.sh" >/dev/null

echo "Fixed URL: $PUBLIC_URL/?room=$ROOM"
echo "App zips: $ROOT/dist/release/juanmao-desktop.zip"
echo "          $ROOT/dist/release/yezi-desktop.zip"
