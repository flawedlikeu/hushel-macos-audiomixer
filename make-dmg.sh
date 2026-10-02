#!/bin/bash
set -e
cd "$(dirname "$0")"

rm -rf dmg && mkdir dmg
cp -R build/Hushel.app dmg/
ln -s /Applications dmg/Applications

hdiutil create -volname "Hushel" -srcfolder dmg -ov -format UDZO Hushel.dmg
rm -rf dmg
echo "Готово: Hushel.dmg"
