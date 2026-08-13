#!/usr/bin/env bash
# Launch Google Chrome with the accessibility flag that makes Chrome expose
# web content to macOS Accessibility (so Flick can read selected text in
# web pages). The `chrome://accessibility/` toggle in Chrome's UI does the
# same thing but is session-only and resets on Chrome restart; the
# `--force-renderer-accessibility` command-line flag is the persistent
# alternative.
#
# Use this instead of clicking Chrome in the Dock — running Chrome with
# `--args` via `open` here ensures the flag is on for that session.
#
# Note: if Chrome is already running without the flag, this will
# (re)launch it. macOS may hand the same process to the new instance;
# fully quit Chrome (Cmd-Q) first if the flag doesn't seem to take.

set -euo pipefail

exec open -a "Google Chrome" --args --force-renderer-accessibility
