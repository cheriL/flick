#!/usr/bin/env bash
set -euo pipefail

# Use the Homebrew Swift toolchain (provides its own SWBBuildService.framework
# and avoids the dyld errors produced by the CommandLineTools-only `/usr/bin/swift`).
export PATH="/opt/homebrew/opt/swift/bin:$PATH"

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="Flick"
BUNDLE_ID="com.cheriL.flick"
BUILD_DIR=".build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "error: built binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"
# Copy .icns files (app icon + in-app icons) into Contents/Resources. We
# do not `cp -R Resources/` because that would risk dragging in any
# stray file added under Resources/ in the future; whitelist .icns only.
for icns in Resources/*.icns; do
    [[ -f "$icns" ]] && cp "$icns" "${APP_DIR}/Contents/Resources/"
done

echo "==> done: ${APP_DIR}"
