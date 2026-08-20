#!/bin/sh

# SPDX-FileCopyrightText: 2026 Kavoye
# SPDX-License-Identifier: Apache-2.0

#
# Makes the two files that give the disk image its window: Tools/dmg/background.tiff
# and Tools/dmg/DS_Store.
#
#     sh Tools/make-dmg-layout.sh
#
# Only Finder can write a .DS_Store, and the release runner has no Finder
# session to drive. So the layout is made one time on a Mac, committed, and
# copied into the staging folder by the release workflow. Run this again after
# you change the artwork or the positions below.
#
# The volume name must stay "Linen": the background is recorded as an alias that
# names the volume, and the workflow gives the image the same name.
#

set -eu

cd "$(dirname "$0")/.."

VOLUME="Linen"
WORK="$(mktemp -d)"
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

swift Tools/make-dmg-background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
  -out Tools/dmg/background.tiff >/dev/null

mkdir -p "$WORK/stage/.background" "$WORK/stage/Linen.app"
ln -s /Applications "$WORK/stage/Applications"
cp Tools/dmg/background.tiff "$WORK/stage/.background/background.tiff"

hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$WORK/stage" -volname "$VOLUME" -fs HFS+ \
  -format UDRW -size 20m -ov "$WORK/rw.dmg" >/dev/null
hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen >/dev/null

osascript <<AS >/dev/null
tell application "Finder"
  tell disk "$VOLUME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 80, 1040, 516}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    delay 1
    set position of item "Linen.app" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    set position of item ".background" of container window to {1180, 720}
    update without registering applications
    delay 2
    close
  end tell
end tell
AS

sleep 2
cp "/Volumes/$VOLUME/.DS_Store" Tools/dmg/DS_Store
hdiutil detach "/Volumes/$VOLUME" -quiet

echo "wrote Tools/dmg/background.tiff and Tools/dmg/DS_Store"
