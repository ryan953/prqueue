#!/bin/bash
# Build PRQueue and assemble it into a double-clickable .app bundle.
#
# Usage: Scripts/bundle.sh [--version 1.2.3] [--universal] [--output dist]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="0.0.0-dev"
OUTPUT="dist"
UNIVERSAL=0
APP_NAME="PRQueue"
EXECUTABLE_NAME="PRQueue"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --output)  OUTPUT="$2";  shift 2 ;;
    --universal) UNIVERSAL=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# A leading "v" is fine in a git tag but not in CFBundleVersion.
VERSION="${VERSION#v}"

APP="$OUTPUT/$APP_NAME.app"
echo "==> Building PRQueue ${VERSION}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Built one slice per arch and lipo'd together rather than
# `swift build --arch arm64 --arch x86_64`, which routes through xcbuild and
# needs a full Xcode install rather than just the command line tools.
if [[ "$UNIVERSAL" == 1 ]]; then
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  lipo -create -output "$APP/Contents/MacOS/$EXECUTABLE_NAME" \
    ".build/arm64-apple-macosx/release/PRQueue" \
    ".build/x86_64-apple-macosx/release/PRQueue"
  lipo -info "$APP/Contents/MacOS/$EXECUTABLE_NAME"
else
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/PRQueue" \
    "$APP/Contents/MacOS/$EXECUTABLE_NAME"
fi

echo "==> Assembling $APP"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__EXECUTABLE__/$EXECUTABLE_NAME/g" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

# A missing icon leaves a blank tile in the Dock rather than failing the build,
# so the app is still usable if the render breaks.
if "$ROOT/Scripts/make-icon.sh" "$APP/Contents/Resources/AppIcon.icns"; then
  echo "==> Icon generated"
else
  echo "==> Skipping icon (generation failed)" >&2
fi

# Ad-hoc signature. Without it macOS refuses to launch an arm64 binary that has
# been moved or unzipped, which is exactly what a release download is.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "==> codesign unavailable, continuing" >&2

echo "==> Built $APP"
