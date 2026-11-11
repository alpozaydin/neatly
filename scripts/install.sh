#!/bin/sh
# One-line install:  curl -fsSL https://raw.githubusercontent.com/alpozaydin/neatly/main/scripts/install.sh | sh
# Downloads the latest release, puts `neatly` in ~/.local/bin, and starts watching ~/Downloads.
# Nothing else is changed. Remove everything with:  neatly service uninstall && rm ~/.local/bin/neatly
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
mkdir -p "$BIN"
mv "$tmp/neatly" "$BIN/neatly"
chmod +x "$BIN/neatly"

"$BIN/neatly" service install

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "To use the neatly command in Terminal, add this line to ~/.zshrc:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
echo
echo "Done. Download any file and a small window will suggest a name and a folder."
