#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.3"
GODOT_RELEASE="stable"
GODOT_BINARY="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/${GODOT_BINARY}.zip"
INSTALL_DIR="/usr/local/bin"

if command -v godot &>/dev/null; then
  echo "Godot already installed: $(godot --version)"
  exit 0
fi

echo "Installing Godot ${GODOT_VERSION}-${GODOT_RELEASE}..."
TMPDIR_GODOT=$(mktemp -d)
curl -fsSL "${GODOT_URL}" -o "${TMPDIR_GODOT}/godot.zip"
unzip -q "${TMPDIR_GODOT}/godot.zip" -d "${TMPDIR_GODOT}"
mv "${TMPDIR_GODOT}/${GODOT_BINARY}" "${INSTALL_DIR}/godot"
chmod +x "${INSTALL_DIR}/godot"
rm -rf "${TMPDIR_GODOT}"

echo "Godot installed: $(godot --version)"

echo "Importing Godot project..."
cd "${CLAUDE_PROJECT_DIR}"
godot --headless --import 2>&1 || true
