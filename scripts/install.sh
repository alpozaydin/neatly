#!/bin/sh
# One-line install:  curl -fsSL https://raw.githubusercontent.com/alpozaydin/tidy-mac/main/scripts/install.sh | sh
# Downloads the latest release, puts `namer` in ~/.local/bin, and starts watching ~/Downloads.
# Nothing else is changed. Remove everything with:  namer service uninstall && rm ~/.local/bin/namer
set -eu

REPO="alpozaydin/tidy-mac"
BIN="$HOME/.local/bin"

[ "$(uname -s)" = "Darwin" ] || { echo "namer runs on macOS only."; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "namer needs a Mac with Apple silicon (M1 or newer)."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || { echo "namer needs macOS 26 or newer (you have $(sw_vers -productVersion))."; exit 1; }

echo "Downloading namer…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
URL="${NAMER_URL:-https://github.com/$REPO/releases/latest/download/namer-macos-arm64.tar.gz}"   # NAMER_URL: for testing
curl -fsSL "$URL" -o "$tmp/namer.tar.gz"
tar -xzf "$tmp/namer.tar.gz" -C "$tmp"
mkdir -p "$BIN"
mv "$tmp/namer" "$BIN/namer"
chmod +x "$BIN/namer"

"$BIN/namer" service install

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "To use the namer command in Terminal, add this line to ~/.zshrc:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
echo
echo "Done. Download any file and a small window will suggest a name and a folder."
