#!/bin/sh
# After the release workflow finishes: point the Homebrew formula at the new release.
# Usage: scripts/update-tap.sh 0.1.0
set -eu
v="$1"
sha=$(curl -fsSL "https://github.com/alpozaydin/neatly/releases/download/v$v/neatly-macos-arm64.tar.gz.sha256" | cut -d' ' -f1)
tap=$(mktemp -d)
gh repo clone alpozaydin/homebrew-tap "$tap" -- -q
mkdir -p "$tap/Formula"
sed -e "s/__VERSION__/$v/g" -e "s/__SHA256__/$sha/" "$(dirname "$0")/homebrew/neatly.rb.template" > "$tap/Formula/neatly.rb"
# Earlier names of this formula: Homebrew moves people who installed them to the new one.
rm -f "$tap/Formula/filed.rb"
printf '{\n  "filed": "neatly"\n}\n' > "$tap/formula_renames.json"
git -C "$tap" add -A
# Commit as whoever commits to this repo (the temp clone has no identity of its own).
name=$(git config user.name || git log -1 --format=%an); email=$(git config user.email || git log -1 --format=%ae)
[ -n "$name" ] || name=$(git log -1 --format=%an)
git -C "$tap" -c user.name="$name" -c user.email="$email" commit -qm "neatly $v"
git -C "$tap" push -q
echo "brew install alpozaydin/tap/neatly now installs $v"
