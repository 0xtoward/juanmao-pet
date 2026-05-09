#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8787}"

cd "$ROOT"
PORT="$PORT" node "$ROOT/server/online-room.js"
