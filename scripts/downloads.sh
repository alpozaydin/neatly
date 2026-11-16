#!/bin/sh
# How many times each release file was downloaded (DMG, and the Terminal/Homebrew/auto-update binary).
gh api repos/alpozaydin/neatly/releases --jq '.[] | .tag_name as $t | .assets[]
  | select(.name | endswith(".sha256") | not) | "\($t)\t\(.download_count)\t\(.name)"' |
  awk -F'\t' '{ total += $2; print } END { print "total\t" total }' | column -t -s "$(printf '\t')"
