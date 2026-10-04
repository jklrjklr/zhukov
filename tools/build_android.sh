#!/usr/bin/env bash
# Exports a debug-signed arm64 APK to build/android/zhukov.apk.
# Needs: godot (4.6.1) with Android export templates, JDK 17 (JAVA_HOME),
# Android SDK with platform-tools + build-tools (ANDROID_HOME), a debug keystore.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17}"
: "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:?set GODOT_ANDROID_KEYSTORE_DEBUG_PATH to a debug keystore}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"
GODOT="${GODOT:-godot}"
mkdir -p build/android
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-debug Android build/android/zhukov.apk
ls -la build/android
