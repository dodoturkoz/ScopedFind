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
MOUNT_DIR="/Volumes/${VOLUME_NAME}"
RW_DMG="${WORK_DIR}/ScopedFind-rw.dmg"
DID_ATTACH=0

cleanup() {
  if [[ "${DID_ATTACH}" == "1" && -d "${MOUNT_DIR}" ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

rm -rf "${WORK_DIR}"
mkdir -p "${PAYLOAD_DIR}/.background"

cp -R "${APP_PATH}" "${PAYLOAD_DIR}/ScopedFind.app"
cp "docs/dmg-background.png" "${PAYLOAD_DIR}/.background/background.png"

osascript <<APPLESCRIPT
tell application "Finder"
  make new alias file to POSIX file "/Applications" at POSIX file "${PAYLOAD_DIR}" with properties {name:"Applications"}
end tell
APPLESCRIPT

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${PAYLOAD_DIR}" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "${RW_DMG}"

if [[ -e "${MOUNT_DIR}" ]]; then
  echo "Mount point ${MOUNT_DIR} already exists. Eject it before creating the DMG." >&2
  exit 73
fi

hdiutil attach "${RW_DMG}" -nobrowse -quiet -readwrite
DID_ATTACH=1

osascript <<APPLESCRIPT
tell application "Finder"
  set mountedDisk to missing value
  repeat 20 times
    try
      set mountedDisk to disk "${VOLUME_NAME}"
      exit repeat
    end try
    delay 0.25
  end repeat
  if mountedDisk is missing value then error "Could not find mounted disk ${VOLUME_NAME}"

  open mountedDisk
  delay 1
  set dmgWindow to container window of mountedDisk
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to {100, 100, 740, 460}
  tell icon view options of dmgWindow
    set arrangement to not arranged
    set icon size to 96
    set background picture to (POSIX file "${MOUNT_DIR}/.background/background.png" as alias)
  end tell
  set position of item "Applications" of dmgWindow to {170, 190}
  set position of item "ScopedFind.app" of dmgWindow to {470, 190}
  delay 1
  close dmgWindow
end tell
APPLESCRIPT

sync
hdiutil detach "${MOUNT_DIR}" -quiet

rm -f "${OUTPUT_PATH}"
hdiutil convert "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${OUTPUT_PATH}"
