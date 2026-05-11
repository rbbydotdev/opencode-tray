#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/dist/OpenCodeTray.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SOURCE_ICON="/tmp/opencode/packages/desktop/icons/prod/icon.icns"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/release/OpenCodeTray" "$MACOS/OpenCodeTray"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$SOURCE_ICON" ]; then
  cp "$SOURCE_ICON" "$RESOURCES/OpenCodeTray.icns"
else
  printf '%s\n' "Warning: missing opencode app icon: $SOURCE_ICON" >&2
fi
chmod +x "$MACOS/OpenCodeTray"

printf '%s\n' "Built $APP"
