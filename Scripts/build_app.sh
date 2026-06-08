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

# Build for both architectures
swift build -c release --package-path "$PROJECT_ROOT" --arch arm64 >/dev/null
swift build -c release --package-path "$PROJECT_ROOT" --arch x86_64 >/dev/null

# Get binary paths for each architecture
ARM64_BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch arm64)/$APP_NAME"
X86_64_BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch x86_64)/$APP_NAME"

if [[ ! -x "$ARM64_BIN" ]] || [[ ! -x "$X86_64_BIN" ]]; then
  echo "error: missing executable" >&2
  exit 1
fi

# Create universal binary using lipo
UNIVERSAL_BIN="$OUTPUT_DIR/$APP_NAME-universal"
lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$UNIVERSAL_BIN"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CONTENTS_DIR/Frameworks"

cp "$UNIVERSAL_BIN" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
fi
for wav in "$PROJECT_ROOT/Packaging/"*.wav; do
  [[ -f "$wav" ]] && cp "$wav" "$RESOURCES_DIR/"
done

# Embed Sparkle framework
SPARKLE_FRAMEWORK="$PROJECT_ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  cp -R "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

# Add rpath so the executable can find frameworks in Contents/Frameworks
install_name_tool -add_rpath @loader_path/../Frameworks "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

SIGN_IDENTITY="SnapX Dev"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
else
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
