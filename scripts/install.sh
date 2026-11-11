#!/bin/sh
# One-line install:  curl -fsSL https://raw.githubusercontent.com/alpozaydin/filed/main/scripts/install.sh | sh
# Downloads the latest release, puts `filed` in ~/.local/bin, and starts watching ~/Downloads.
# Nothing else is changed. Remove everything with:  filed service uninstall && rm ~/.local/bin/filed
set -eu

REPO="alpozaydin/filed"
BIN="$HOME/.local/bin"

[ "$(uname -s)" = "Darwin" ] || { echo "filed runs on macOS only."; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "filed needs a Mac with Apple silicon (M1 or newer)."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || { echo "filed needs macOS 26 or newer (you have $(sw_vers -productVersion))."; exit 1; }

echo "Downloading filed…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
URL="${FILED_URL:-https://github.com/$REPO/releases/latest/download/filed-macos-arm64.tar.gz}"   # FILED_URL: for testing
curl -fsSL "$URL" -o "$tmp/filed.tar.gz"
tar -xzf "$tmp/filed.tar.gz" -C "$tmp"
mkdir -p "$BIN"
mv "$tmp/filed" "$BIN/filed"
chmod +x "$BIN/filed"

"$BIN/filed" service install

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "To use the filed command in Terminal, add this line to ~/.zshrc:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
echo
echo "Done. Download any file and a small window will suggest a name and a folder."
