#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 /path/to/ScopedFind.app vX.Y.Z /path/to/output.dmg" >&2
  exit 64
fi

APP_PATH="$1"
TAG_NAME="$2"
OUTPUT_PATH="$3"
VOLUME_NAME="ScopedFind"
WORK_DIR="${RUNNER_TEMP:-/tmp}/scopedfind-dmg-${TAG_NAME}"
PAYLOAD_DIR="${WORK_DIR}/payload"
MOUNT_DIR="${WORK_DIR}/mount"
RW_DMG="${WORK_DIR}/ScopedFind-rw.dmg"

cleanup() {
  if [[ -d "${MOUNT_DIR}" ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

rm -rf "${WORK_DIR}"
mkdir -p "${PAYLOAD_DIR}/.background" "${MOUNT_DIR}"

cp -R "${APP_PATH}" "${PAYLOAD_DIR}/ScopedFind.app"
cp "docs/dmg-background.png" "${PAYLOAD_DIR}/.background/background.png"

osascript <<APPLESCRIPT
tell application "Finder"
  make new alias file to POSIX file "/Applications" at POSIX file "${PAYLOAD_DIR}" with properties {name:"Applications"}
  set payloadFolder to POSIX file "${PAYLOAD_DIR}" as alias
  open payloadFolder
  delay 1
  set current view of container window of payloadFolder to icon view
  set toolbar visible of container window of payloadFolder to false
  set statusbar visible of container window of payloadFolder to false
  set bounds of container window of payloadFolder to {100, 100, 740, 460}
  set viewOptions to the icon view options of container window of payloadFolder
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set position of item "ScopedFind.app" of container window of payloadFolder to {170, 225}
  set position of item "Applications" of container window of payloadFolder to {470, 225}
  delay 1
  close container window of payloadFolder
end tell
APPLESCRIPT

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${PAYLOAD_DIR}" \
  -ov \
  -format UDRW \
  "${RW_DMG}"

hdiutil attach "${RW_DMG}" -mountpoint "${MOUNT_DIR}" -nobrowse -quiet -readwrite

osascript <<APPLESCRIPT
tell application "Finder"
  set mountedFolder to POSIX file "${MOUNT_DIR}" as alias
  open mountedFolder
  delay 1
  set current view of container window of mountedFolder to icon view
  set toolbar visible of container window of mountedFolder to false
  set statusbar visible of container window of mountedFolder to false
  set bounds of container window of mountedFolder to {100, 100, 740, 460}
  set viewOptions to the icon view options of container window of mountedFolder
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set background picture of viewOptions to POSIX file "${MOUNT_DIR}/.background/background.png"
  delay 1
  close container window of mountedFolder
end tell
APPLESCRIPT

sync
hdiutil detach "${MOUNT_DIR}" -quiet
rmdir "${MOUNT_DIR}"

rm -f "${OUTPUT_PATH}"
hdiutil convert "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${OUTPUT_PATH}"
