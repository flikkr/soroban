#!/bin/sh
# Downloads the latest Soroban release and installs it into ~/Applications.
#   curl -fsSL https://raw.githubusercontent.com/flikkr/soroban/main/install.sh | sh
set -e

REPO=flikkr/soroban
DEST="$HOME/Applications"

if [ "$(uname)" != "Darwin" ]; then
    echo "Soroban only runs on macOS." >&2
    exit 1
fi

URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
    | head -n 1 \
    | sed 's/.*"\(https[^"]*\)"/\1/')

if [ -z "$URL" ]; then
    echo "Couldn't find a release to download from https://github.com/$REPO/releases" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null; rm -rf "$TMP"' EXIT

echo "Downloading $URL"
curl -fL --progress-bar -o "$TMP/Soroban.dmg" "$URL"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/Soroban.dmg"

pkill -x Soroban 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/Soroban.app"
cp -R "$TMP/mnt/Soroban.app" "$DEST/"
# The app isn't notarized, so clear the quarantine flag in case it was set.
xattr -dr com.apple.quarantine "$DEST/Soroban.app" 2>/dev/null || true

echo "Installed to $DEST/Soroban.app"
open "$DEST/Soroban.app"
