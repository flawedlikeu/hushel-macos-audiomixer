#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/Hushel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Hushel "$APP/Contents/MacOS/Hushel"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Готово: $APP"
open "$APP"
