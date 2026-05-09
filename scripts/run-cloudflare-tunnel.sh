#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="/tmp/juanmao-cloudflared.log"
RUN_LOG="/tmp/juanmao-cloudflared-current.log"
CURRENT_URL="/tmp/juanmao-current-url.txt"
PROJECT_URL="$ROOT/dist/current-public-url.txt"
CLOUDFLARED="/opt/homebrew/bin/cloudflared"

mkdir -p "$ROOT/dist"

while true; do
  : > "$LOG"
  : > "$RUN_LOG"
  "$CLOUDFLARED" tunnel --protocol http2 --url http://127.0.0.1:8787 >> "$RUN_LOG" 2>&1 &
  pid="$!"
  started_at="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    /bin/cp "$RUN_LOG" "$LOG" 2>/dev/null || true
    url="$(LC_ALL=C /usr/bin/grep -Eo 'https://[^[:space:]]+\.trycloudflare\.com' "$RUN_LOG" 2>/dev/null | /usr/bin/tail -n 1 || true)"
    if [ -n "$url" ]; then
      printf '%s\n' "$url" > "$CURRENT_URL"
      printf '%s\n' "$url" > "$PROJECT_URL"
    fi

    if /usr/bin/grep -Eq 'Unauthorized: Tunnel not found|no more connections active and exiting' "$RUN_LOG" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      break
    fi

    now="$(date +%s)"
    if [ -z "$url" ] && [ "$((now - started_at))" -gt 90 ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      break
    fi

    sleep 5
  done

  wait "$pid" 2>/dev/null || true
  /bin/cp "$RUN_LOG" "$LOG" 2>/dev/null || true
  sleep 4
done
