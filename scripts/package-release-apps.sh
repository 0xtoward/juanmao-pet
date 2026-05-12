#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_URL="${PUBLIC_URL:-http://127.0.0.1:8787}"
ROOM="${ROOM:-}"
OUT_DIR="${OUT_DIR:-$ROOT/dist/release}"

mkdir -p "$OUT_DIR"

build_one() {
  local app_name="$1"
  local bundle_name="$2"
  local bundle_id="$3"
  local pet_name="$4"
  local pet_kind="$5"
  local zip_name="$6"
  local deployment_target="$7"

  APP_NAME="$app_name" \
  BUNDLE_DISPLAY_NAME="$bundle_name" \
  BUNDLE_ID="$bundle_id" \
  MACOS_DEPLOYMENT_TARGET="$deployment_target" \
  JUANMAO_SERVER_URL="$PUBLIC_URL" \
  JUANMAO_ROOM="$ROOM" \
  JUANMAO_ACTOR_NAME="$pet_name" \
  JUANMAO_PET_NAME="$pet_name" \
  JUANMAO_PET_KIND="$pet_kind" \
  "$ROOT/scripts/build-desktop-app.sh" >/dev/null

  rm -f "$OUT_DIR/$zip_name"
  xattr -cr "$ROOT/$app_name.app" 2>/dev/null || true
  xattr -c "$ROOT/$app_name.app" 2>/dev/null || true
  find "$ROOT/$app_name.app" -exec xattr -c {} + 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$ROOT/$app_name.app" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$ROOT/$app_name.app" 2>/dev/null || true
  if command -v codesign >/dev/null 2>&1; then
    codesign --remove-signature "$ROOT/$app_name.app" >/dev/null 2>&1 || true
    codesign --force --deep --sign - "$ROOT/$app_name.app" >/dev/null
    codesign --verify --deep --strict "$ROOT/$app_name.app"
  fi
  (
    cd "$ROOT"
    COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$OUT_DIR/$zip_name" "$app_name.app"
  )
  printf "%s\n" "$OUT_DIR/$zip_name"
}

build_one "卷毛 Desktop" "卷毛" "local.juanmao.interactive.juanmao" "卷毛" "cockapoo" "juanmao-desktop.zip" "12.0"
build_one "叶子 Desktop" "叶子" "local.juanmao.interactive.yezi" "叶子" "dachshund" "yezi-desktop.zip" "12.0"
