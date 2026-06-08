#!/bin/zsh

set -euo pipefail

# Usage: build_app.sh [arm64|x86_64|universal]
# Default: universal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="SnapX"
OUTPUT_DIR="$PROJECT_ROOT/Build"
INFO_PLIST_TEMPLATE="$PROJECT_ROOT/Packaging/$APP_NAME-Info.plist"
APP_ICON="$PROJECT_ROOT/Packaging/AppIcon.icns"
ARCH="${1:-universal}"

build_app_bundle() {
  local arch="$1"
  local binary="$2"
  local app_bundle="$OUTPUT_DIR/$APP_NAME-${arch}.app"
  local contents="$app_bundle/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"

  rm -rf "$app_bundle"
  mkdir -p "$macos" "$resources" "$contents/Frameworks"

  cp "$binary" "$macos/$APP_NAME"
  cp "$INFO_PLIST_TEMPLATE" "$contents/Info.plist"
  [[ -f "$APP_ICON" ]] && cp "$APP_ICON" "$resources/AppIcon.icns"
  for wav in "$PROJECT_ROOT/Packaging/"*.wav; do
    [[ -f "$wav" ]] && cp "$wav" "$resources/"
  done

  # Embed Sparkle framework
  local sparkle="$PROJECT_ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  [[ -d "$sparkle" ]] && cp -R "$sparkle" "$contents/Frameworks/"

  chmod +x "$macos/$APP_NAME"
  install_name_tool -add_rpath @loader_path/../Frameworks "$macos/$APP_NAME" 2>/dev/null || true

  # Sign
  local sign_id="SnapX Dev"
  if security find-identity -v -p codesigning | grep -q "$sign_id"; then
    codesign --force --sign "$sign_id" "$app_bundle" >/dev/null
  else
    codesign --force --sign - "$app_bundle" >/dev/null
  fi
  codesign --verify --deep --strict "$app_bundle"

  echo "$app_bundle"
}

mkdir -p "$OUTPUT_DIR"

case "$ARCH" in
  arm64)
    echo "Building for arm64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch arm64 >/dev/null
    BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch arm64)/$APP_NAME"
    build_app_bundle "arm64" "$BIN"
    ;;

  x86_64)
    echo "Building for x86_64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch x86_64 >/dev/null
    BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch x86_64)/$APP_NAME"
    build_app_bundle "x86_64" "$BIN"
    ;;

  universal)
    echo "Building for arm64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch arm64 >/dev/null
    echo "Building for x86_64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch x86_64 >/dev/null

    ARM64_BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch arm64)/$APP_NAME"
    X86_64_BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch x86_64)/$APP_NAME"

    UNIVERSAL_BIN="$OUTPUT_DIR/$APP_NAME-universal"
    lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$UNIVERSAL_BIN"
    build_app_bundle "universal" "$UNIVERSAL_BIN"
    ;;

  *)
    echo "Usage: build_app.sh [arm64|x86_64|universal]" >&2
    exit 1
    ;;
esac
