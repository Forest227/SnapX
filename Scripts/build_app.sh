#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="SnapX"
OUTPUT_DIR="$PROJECT_ROOT/Build"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_TEMPLATE="$PROJECT_ROOT/Packaging/$APP_NAME-Info.plist"
APP_ICON="$PROJECT_ROOT/Packaging/AppIcon.icns"

swift build -c release --package-path "$PROJECT_ROOT" >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT")"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: missing executable at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
fi
for wav in "$PROJECT_ROOT/Packaging/"*.wav; do
  [[ -f "$wav" ]] && cp "$wav" "$RESOURCES_DIR/"
done
chmod +x "$MACOS_DIR/$APP_NAME"

SIGN_IDENTITY="SnapX Dev"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
else
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
