#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-卷毛 Desktop}"
BUNDLE_DISPLAY_NAME="${BUNDLE_DISPLAY_NAME:-卷毛}"
BUNDLE_ID="${BUNDLE_ID:-local.juanmao.interactive}"
JUANMAO_SERVER_URL="${JUANMAO_SERVER_URL:-http://127.0.0.1:8787}"
JUANMAO_ROOM="${JUANMAO_ROOM:-}"
JUANMAO_PET_NAME="${JUANMAO_PET_NAME:-卷毛}"
JUANMAO_PET_KIND="${JUANMAO_PET_KIND:-cockapoo}"
JUANMAO_ACTOR_NAME="${JUANMAO_ACTOR_NAME:-$JUANMAO_PET_NAME}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
export JUANMAO_SERVER_URL JUANMAO_ROOM JUANMAO_PET_NAME JUANMAO_PET_KIND JUANMAO_ACTOR_NAME
APP="$ROOT/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
if [ "$APP_NAME" = "卷毛 Desktop" ]; then
  rm -rf "$ROOT/Coco Desktop.app"
fi
mkdir -p "$MACOS" "$RESOURCES/assets"

MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" swiftc "$ROOT/macos/CocoInteractive.swift" \
  -target "arm64-apple-macosx$MACOS_DEPLOYMENT_TARGET" \
  -framework Cocoa \
  -framework QuartzCore \
  -o "$MACOS/CocoInteractive"

cp "$ROOT/macos/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $BUNDLE_DISPLAY_NAME" "$CONTENTS/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MACOS_DEPLOYMENT_TARGET" "$CONTENTS/Info.plist" >/dev/null
if [ "$JUANMAO_PET_KIND" = "dachshund" ] && [ -f "$ROOT/assets/dachshund-spritesheet.png" ]; then
  ICON_SOURCE="$ROOT/assets/dachshund-spritesheet.png"
else
  ICON_SOURCE="$ROOT/assets/coco-spritesheet.png"
fi
/usr/bin/swift "$ROOT/scripts/make-app-icon.swift" "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
cp "$ROOT/desktop.html" "$RESOURCES/desktop.html"
cp "$ROOT/desktop.css" "$RESOURCES/desktop.css"
cp "$ROOT/desktop.js" "$RESOURCES/desktop.js"
node - "$RESOURCES/online-config.json" <<'NODE'
const fs = require("fs");
const [file] = process.argv.slice(2);
fs.writeFileSync(file, JSON.stringify({
  serverURL: process.env.JUANMAO_SERVER_URL,
  room: process.env.JUANMAO_ROOM,
  actorName: process.env.JUANMAO_ACTOR_NAME,
  petName: process.env.JUANMAO_PET_NAME,
  petKind: process.env.JUANMAO_PET_KIND
}, null, 2) + "\n");
NODE
cp "$ROOT/assets/coco-spritesheet.webp" "$RESOURCES/assets/coco-spritesheet.webp"
if [ ! -f "$ROOT/assets/coco-spritesheet.png" ]; then
  sips -s format png "$ROOT/assets/coco-spritesheet.webp" --out "$ROOT/assets/coco-spritesheet.png" >/dev/null
fi
cp "$ROOT/assets/coco-spritesheet.png" "$RESOURCES/assets/coco-spritesheet.png"
if [ -f "$ROOT/assets/dachshund-pet.json" ]; then
  cp "$ROOT/assets/dachshund-pet.json" "$RESOURCES/assets/dachshund-pet.json"
fi
if [ -f "$ROOT/assets/dachshund-spritesheet.webp" ]; then
  cp "$ROOT/assets/dachshund-spritesheet.webp" "$RESOURCES/assets/dachshund-spritesheet.webp"
fi
if [ -f "$ROOT/assets/dachshund-spritesheet.png" ]; then
  cp "$ROOT/assets/dachshund-spritesheet.png" "$RESOURCES/assets/dachshund-spritesheet.png"
elif [ -f "$ROOT/assets/dachshund-spritesheet.webp" ]; then
  sips -s format png "$ROOT/assets/dachshund-spritesheet.webp" --out "$RESOURCES/assets/dachshund-spritesheet.png" >/dev/null
fi

if command -v codesign >/dev/null 2>&1; then
  xattr -cr "$APP" 2>/dev/null || true
  xattr -c "$APP" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  codesign --remove-signature "$APP" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$APP" >/dev/null
fi

echo "$APP"
