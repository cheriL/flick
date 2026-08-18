#!/usr/bin/env bash
set -euo pipefail

# Package Flick.app into a redistributable DMG using `create-dmg`.
# https://github.com/create-dmg/create-dmg
#
# Requires:
#   brew install create-dmg
#
# The .app bundle is produced by scripts/build-app.sh if it isn't already
# present, so this script can be run standalone.
#
# Output: .build/Flick-<version>.dmg
#   - VERSION env var if set (used by the release workflow, value = tag name)
#   - else `git describe --tags --always --dirty`
#   - else "dev"

cd "$(dirname "$0")/.."

APP_NAME="Flick"
APP_BUNDLE=".build/${APP_NAME}.app"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "==> ${APP_BUNDLE} missing; running scripts/build-app.sh"
    ./scripts/build-app.sh
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg not installed. Install via: brew install create-dmg" >&2
    exit 1
fi

if [[ -n "${VERSION:-}" ]]; then
    version="${VERSION}"
elif git describe --tags --always --dirty >/dev/null 2>&1; then
    version="$(git describe --tags --always --dirty)"
else
    version="dev"
fi

DMG_PATH=".build/${APP_NAME}-${version}.dmg"
rm -f "${DMG_PATH}"

echo "==> packaging ${DMG_PATH}"
create-dmg \
    --volname "${APP_NAME}" \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 175 190 \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${APP_BUNDLE}"

echo "==> done: ${DMG_PATH}"