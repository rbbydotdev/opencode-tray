#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_PARENT="${TMPDIR:-/tmp}"
BUILD_ROOT="$(mktemp -d "$BUILD_PARENT/opencode-tray-build.XXXXXX")"
APP="$ROOT/dist/OpenCodeTray.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
HELPERS="$CONTENTS/Helpers"
RESOURCES="$CONTENTS/Resources"
ICON_CANDIDATES="
$ROOT/Resources/OpenCodeTray.icns
$HOME/etc/projects/opencode/packages/desktop/src-tauri/icons/prod/icon.icns
$HOME/etc/projects/opencode/packages/desktop-electron/icons/prod/icon.icns
/tmp/opencode/packages/desktop/icons/prod/icon.icns
"

trap 'rm -rf "$BUILD_ROOT"' EXIT INT TERM

cd "$ROOT"
swift build -c release --build-path "$BUILD_ROOT" \
  -Xswiftc -gnone \
  -Xswiftc -file-prefix-map -Xswiftc "$ROOT=." \
  -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=." \
  -Xcc "-fdebug-prefix-map=$ROOT=."

rm -rf "$APP"
mkdir -p "$MACOS" "$HELPERS" "$RESOURCES"

cp "$BUILD_ROOT/release/OpenCodeTray" "$MACOS/OpenCodeTray"
strip -S "$MACOS/OpenCodeTray"
chmod +x "$MACOS/OpenCodeTray"

cp "$BUILD_ROOT/release/OpenCodeTrayHelper" "$HELPERS/OpenCodeTrayHelper"
strip -S "$HELPERS/OpenCodeTrayHelper"
chmod +x "$HELPERS/OpenCodeTrayHelper"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

SOURCE_ICON=""
for candidate in $ICON_CANDIDATES; do
  if [ -f "$candidate" ]; then
    SOURCE_ICON="$candidate"
    break
  fi
done
if [ -n "$SOURCE_ICON" ]; then
  cp "$SOURCE_ICON" "$RESOURCES/OpenCodeTray.icns"
  printf '%s\n' "Using app icon: $SOURCE_ICON"
else
  printf '%s\n' "Warning: no opencode app icon found in: $ICON_CANDIDATES" >&2
fi

# Ad-hoc sign both binaries. The helper needs a valid signature for launchd to load it
# even when manually installed; ad-hoc is sufficient for that path (only SMAppService
# requires Developer ID).
codesign --sign - --force --timestamp=none "$HELPERS/OpenCodeTrayHelper"
codesign --sign - --force --timestamp=none "$MACOS/OpenCodeTray"

printf '%s\n' "Built dist/OpenCodeTray.app"
