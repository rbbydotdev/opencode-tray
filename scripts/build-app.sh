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

if [ ! -f "$SOURCE_ICON" ]; then
  printf '%s\n' "Missing opencode app icon: $SOURCE_ICON" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/release/OpenCodeTray" "$MACOS/OpenCodeTray"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$SOURCE_ICON" "$RESOURCES/OpenCodeTray.icns"
chmod +x "$MACOS/OpenCodeTray"

printf '%s\n' "Built $APP"
