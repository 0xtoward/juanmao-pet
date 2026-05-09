#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_URL="${PUBLIC_URL:?Set PUBLIC_URL to the current Cloudflare tunnel URL}"
ROOM="${ROOM:-}"
FRIEND_NAME="${FRIEND_NAME:-叶子}"
FRIEND_PET_NAME="${FRIEND_PET_NAME:-叶子}"
FRIEND_PET_KIND="${FRIEND_PET_KIND:-dachshund}"
APP_NAME="${APP_NAME:-叶子 Desktop}"

mkdir -p "$ROOT/dist"

APP_NAME="$APP_NAME" \
BUNDLE_DISPLAY_NAME="卷毛联机" \
BUNDLE_ID="local.juanmao.interactive.friend" \
JUANMAO_SERVER_URL="$PUBLIC_URL" \
JUANMAO_ROOM="$ROOM" \
JUANMAO_ACTOR_NAME="$FRIEND_NAME" \
JUANMAO_PET_NAME="$FRIEND_PET_NAME" \
JUANMAO_PET_KIND="$FRIEND_PET_KIND" \
"$ROOT/scripts/build-desktop-app.sh" >/dev/null

rm -f "$ROOT/dist/yezi-desktop.zip"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/$APP_NAME.app" "$ROOT/dist/yezi-desktop.zip"
echo "$ROOT/dist/yezi-desktop.zip"
