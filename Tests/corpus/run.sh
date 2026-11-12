#!/bin/bash
# Real-world corpus check: name every file in the given folders the way the review window does (explicit request),
# on COPIES, and report what a person would see. Flags "couldn't tell", timeouts and anything slow.
#   Tests/corpus/run.sh ~/Downloads ~/Desktop …
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
B=${NEATLY_BIN:-$(swift build -c release --product neatly --show-bin-path --package-path "$ROOT")/neatly}
W=$(mktemp -d /tmp/neatly-corpus.XXXXXX); mkdir -p "$W/data"
export NEATLY_DATA_DIR=$W/data NEATLY_HEADLESS=1
n=0; ok=0; fine=0; unsure=0; slow=0; out=$W/report.txt
# Like the app after installing or updating: do the one-time setup first, so the first files don't pay for it.
"$B" warmup
for dir in "$@"; do
  find "$dir" -maxdepth 1 -type f ! -name ".*" -print0 | while IFS= read -r -d '' f; do
    c="$W/files/$(basename "$dir")"; mkdir -p "$c"; cp -p "$f" "$c/" 2>/dev/null || continue
    g="$c/$(basename "$f")"
    s=$(python3 -c 'import time;print(time.time())')
    r=$("$B" --force --why "$g" 2>/dev/null | grep -E "→|  \?  |keep" | head -1)
    ms=$(python3 -c "import time;print(int((time.time()-$s)*1000))")
    if echo "$r" | grep -q "→"; then kind=named; elif echo "$r" | grep -q "no better name"; then kind=fine; else kind=UNSURE; fi
    printf "%-7s %6d ms  %-45s %s\n" "$kind" "$ms" "$(basename "$f" | cut -c1-45)" "$(echo "$r" | sed -E 's/^.*(→|\?|keep) +//' | cut -c1-60)" >> "$out"
  done
done
sort "$out" | awk '{k[$1]++; if ($2 > 8000) slow++} END {for (x in k) printf "%s: %d   ", x, k[x]; printf "slow(>8s): %d\n", slow+0}'
echo "report: $out"
