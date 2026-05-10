#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_URL="${PUBLIC_URL:?Set PUBLIC_URL to the current Cloudflare tunnel URL}"
ROOM="${ROOM:-}"
FRIEND_NAME="${FRIEND_NAME:-叶子}"
FRIEND_PET_NAME="${FRIEND_PET_NAME:-叶子}"
FRIEND_PET_KIND="${FRIEND_PET_KIND:-dachshund}"
APP_NAME="${APP_NAME:-叶子 Desktop}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"

mkdir -p "$ROOT/dist"

APP_NAME="$APP_NAME" \
BUNDLE_DISPLAY_NAME="$FRIEND_PET_NAME" \
BUNDLE_ID="local.juanmao.interactive.friend" \
MACOS_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
JUANMAO_SERVER_URL="$PUBLIC_URL" \
JUANMAO_ROOM="$ROOM" \
JUANMAO_ACTOR_NAME="$FRIEND_NAME" \
JUANMAO_PET_NAME="$FRIEND_PET_NAME" \
JUANMAO_PET_KIND="$FRIEND_PET_KIND" \
"$ROOT/scripts/build-desktop-app.sh" >/dev/null

rm -f "$ROOT/dist/yezi-desktop.zip"
xattr -cr "$ROOT/$APP_NAME.app" 2>/dev/null || true
xattr -c "$ROOT/$APP_NAME.app" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$ROOT/$APP_NAME.app" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$ROOT/$APP_NAME.app" 2>/dev/null || true
if command -v codesign >/dev/null 2>&1; then
  codesign --remove-signature "$ROOT/$APP_NAME.app" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$ROOT/$APP_NAME.app" >/dev/null
  codesign --verify --deep --strict "$ROOT/$APP_NAME.app"
fi
(
  cd "$ROOT"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$ROOT/dist/yezi-desktop.zip" "$APP_NAME.app"
)
echo "$ROOT/dist/yezi-desktop.zip"
