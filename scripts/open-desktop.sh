#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-desktop-app.sh" >/dev/null
open "$ROOT/卷毛 Desktop.app"
