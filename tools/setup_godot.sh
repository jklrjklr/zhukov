#!/usr/bin/env bash
# Installs the Godot editor (headless-capable) and export templates.
# Idempotent; safe to rerun on a fresh container.
set -euo pipefail

VERSION="${GODOT_VERSION:-4.6.1-stable}"
TPL_DIR="$HOME/.local/share/godot/export_templates/${VERSION/-/.}"
BIN="/opt/godot/Godot_v${VERSION}_linux.x86_64"
BASE="https://github.com/godotengine/godot/releases/download/$VERSION"

if [[ ! -x "$BIN" ]]; then
  mkdir -p /opt/godot
  wget -q -O /tmp/godot.zip "$BASE/Godot_v${VERSION}_linux.x86_64.zip"
  unzip -qo /tmp/godot.zip -d /opt/godot && rm /tmp/godot.zip
  chmod +x "$BIN"
fi
ln -sf "$BIN" /usr/local/bin/godot

if [[ ! -f "$TPL_DIR/web_nothreads_release.zip" ]]; then
  mkdir -p "$TPL_DIR"
  wget -q -O /tmp/tpl.tpz "$BASE/Godot_v${VERSION}_export_templates.tpz"
  rm -rf /tmp/tpl && unzip -qo /tmp/tpl.tpz -d /tmp/tpl
  mv /tmp/tpl/templates/* "$TPL_DIR/" && rm -rf /tmp/tpl /tmp/tpl.tpz
fi

godot --headless --version
