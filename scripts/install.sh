#!/bin/sh
# One-line install:  curl -fsSL https://raw.githubusercontent.com/alpozaydin/neatly/main/scripts/install.sh | sh
# Downloads the latest release, installs neatly.app, links the `neatly` command in ~/.local/bin, and starts it.
# Nothing else is changed. Remove everything with:  neatly service uninstall
set -eu

REPO="alpozaydin/neatly"
BIN="$HOME/.local/bin"

[ "$(uname -s)" = "Darwin" ] || { echo "neatly runs on macOS only."; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "neatly needs a Mac with Apple silicon (M1 or newer)."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || { echo "neatly needs macOS 26 or newer (you have $(sw_vers -productVersion))."; exit 1; }

echo "Downloading neatly…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
URL="${NEATLY_URL:-https://github.com/$REPO/releases/latest/download/neatly-macos-arm64.tar.gz}"   # NEATLY_URL: for testing
curl -fsSL "$URL" -o "$tmp/neatly.tar.gz"
tar -xzf "$tmp/neatly.tar.gz" -C "$tmp"
chmod +x "$tmp/neatly"

# Builds neatly.app (in /Applications, or ~/Applications), links the neatly command to it, starts it at login.
"$tmp/neatly" service install

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "To use the neatly command in Terminal, add this line to ~/.zshrc:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
echo
echo "Done. neatly is in your menu bar and in Applications (open it from Spotlight any time)."
