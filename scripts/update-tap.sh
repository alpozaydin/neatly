#!/bin/sh
# After the release workflow finishes: point the Homebrew formula at the new release.
# Usage: scripts/update-tap.sh 0.1.0
set -eu
v="$1"
sha=$(curl -fsSL "https://github.com/alpozaydin/tidy-mac/releases/download/v$v/namer-macos-arm64.tar.gz.sha256" | cut -d' ' -f1)
tap=$(mktemp -d)
gh repo clone alpozaydin/homebrew-tap "$tap" -- -q
mkdir -p "$tap/Formula"
sed -e "s/__VERSION__/$v/g" -e "s/__SHA256__/$sha/" "$(dirname "$0")/homebrew/namer.rb.template" > "$tap/Formula/namer.rb"
git -C "$tap" add Formula/namer.rb
git -C "$tap" commit -qm "namer $v"
git -C "$tap" push -q
echo "brew install alpozaydin/tap/namer now installs $v"
