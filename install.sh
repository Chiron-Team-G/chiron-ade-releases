#!/usr/bin/env bash
#
# Chiron ADE — one line to install it.
#
#   curl -fsSL <RAW>/install.sh | bash                      # production
#   curl -fsSL <RAW>/install.sh | bash -s -- --channel dev  # the team's build
#
# WHY A SCRIPT AND NOT "DOWNLOAD THE DMG". A file a BROWSER downloads carries
# macOS's quarantine flag, and an app that is not notarised by Apple dies there
# with "the app is damaged" — the dialog that makes people give up. `curl` sets
# no such flag, so an app installed this way opens on the first double click
# with no Gatekeeper dance and no right-click ceremony. It is the same reason
# the chiron CLI installs this way and needs no Apple account.
#
# The DMG is published too, for whoever prefers dragging and does not mind the
# first-open warning. When the Developer ID certificate exists, notarised
# builds make both paths silent and this script stops being the recommended
# one — nothing else about it changes.
#
# This script is the source of truth in the ADE repo; the copy that people
# actually run lives on `main` of the releases repo. Editing one and not the
# other is how the CLI once handed the dev board a production installer.
set -euo pipefail

REPO="${CHIRON_ADE_REPO:-Chiron-Team-G/chiron-ade-releases}"
CHANNEL="prod"

while [ $# -gt 0 ]; do
  case "$1" in
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --channel=*) CHANNEL="${1#*=}"; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$CHANNEL" in
  prod|beta|dev) ;;
  *) echo "Unknown channel '$CHANNEL' (expected prod, beta or dev)." >&2; exit 2 ;;
esac

# One app per channel, installed side by side on purpose: each talks to its own
# Engineers and keeps its own sessions, so a dev build can never answer for a
# production one.
case "$CHANNEL" in
  prod) APP_NAME="Chiron ADE";      SLUG="" ;;
  beta) APP_NAME="Chiron ADE Beta"; SLUG="-beta" ;;
  dev)  APP_NAME="Chiron ADE Dev";  SLUG="-dev" ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is for macOS. On Windows, download the installer from https://github.com/$REPO/releases" >&2
  exit 1
fi

case "$(uname -m)" in
  arm64) ARCH="arm64" ;;
  x86_64) ARCH="x64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Production resolves through the releases page's permanent `latest` link; the
# other channels through a rolling tag that every build replaces, so there is
# exactly one of each alive and its URL never moves.
if [ "$CHANNEL" = "prod" ]; then
  BASE="${CHIRON_ADE_RELEASES:-https://github.com/$REPO/releases/latest/download}"
else
  BASE="${CHIRON_ADE_RELEASES:-https://github.com/$REPO/releases/download/$CHANNEL}"
fi
ZIP="chiron-ade${SLUG}-${ARCH}-mac.zip"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $APP_NAME ($ARCH)…"
if ! curl -fL --progress-bar "$BASE/$ZIP" -o "$TMP/$ZIP"; then
  echo "Could not download $BASE/$ZIP" >&2
  exit 1
fi

# Checksums are published beside the artifacts. Missing ones are not fatal —
# an older release may predate them — but a MISMATCH always is.
if curl -fsSL "$BASE/checksums.txt" -o "$TMP/checksums.txt" 2>/dev/null; then
  expected="$(awk -v f="$ZIP" '$2 == f || $2 == "*"f {print $1}' "$TMP/checksums.txt" | head -1)"
  if [ -n "$expected" ]; then
    actual="$(shasum -a 256 "$TMP/$ZIP" | awk '{print $1}')"
    if [ "$expected" != "$actual" ]; then
      echo "Checksum mismatch — the download is not what the release published. Aborting." >&2
      exit 1
    fi
    echo "✓ checksum verified"
  fi
fi

# `ditto` rather than `unzip`: it is what created the archive and the only one
# that restores an app bundle's symlinks and extended attributes intact.
mkdir -p "$TMP/unpacked"
ditto -x -k "$TMP/$ZIP" "$TMP/unpacked"
SRC="$(/usr/bin/find "$TMP/unpacked" -maxdepth 2 -name "*.app" -print -quit)"
[ -n "$SRC" ] || { echo "The archive did not contain an app." >&2; exit 1; }

# /Applications when it is writable (the usual case for the person who set the
# Mac up), the home folder otherwise — never sudo. An installer that asks for a
# password to copy a file teaches people to type it for anything.
if [ -w "/Applications" ]; then DEST_DIR="/Applications"; else DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; fi
DEST="$DEST_DIR/$APP_NAME.app"

# A running copy cannot be replaced under its own feet. Ask it to quit the
# polite way first: the app closes its agents' terminals cleanly instead of
# having them killed with the bundle.
if pgrep -f "$APP_NAME.app/Contents/MacOS/" >/dev/null 2>&1; then
  echo "Closing the running ${APP_NAME}…"
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$APP_NAME.app/Contents/MacOS/" >/dev/null 2>&1 || break
    sleep 1
  done
fi

rm -rf "$DEST"
ditto "$SRC" "$DEST"

# Defensive: `curl` sets no quarantine flag, but the same zip re-run from a
# browser download would, and one stale flag is the whole "app is damaged"
# experience.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "✓ $APP_NAME installed at $DEST"
open "$DEST"
