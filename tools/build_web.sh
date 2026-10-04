#!/usr/bin/env bash
# Exports the HTML5 build to build/web/. Serve with: python3 -m http.server -d build/web
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web
godot --headless --import >/dev/null 2>&1 || true
godot --headless --export-release Web build/web/index.html
ls -la build/web
