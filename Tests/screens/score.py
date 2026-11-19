#!/usr/bin/env python3
"""Tests/screens/score.py <shots dir> [neatly binary] [extra neatly args...]: name every screenshot, score against cases.json."""
import json, os, re, subprocess, sys, tempfile
d = os.path.abspath(sys.argv[1]); b = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/src/neatly/.build/release/neatly")
cases = json.load(open(os.path.join(d, "cases.json")))
data = tempfile.mkdtemp()   # a fresh user: nothing learned yet
out = subprocess.run([b, *sys.argv[3:], d], capture_output=True, text=True, env={**os.environ, "NEATLY_DATA_DIR": data}).stdout
got = {}
for line in out.splitlines():
    m = re.match(r"(.+?\.png)\s+→\s+(.+?)\.png", line.strip())
    if m: got[m.group(1)] = m.group(2)
    m = re.match(r"(.+?\.png)\s+(?:skip|keep|unsure|name ok)", line.strip())
    if m and m.group(1) not in got: got[m.group(1)] = "(no name)"
ok = 0; rows = []
for c in cases:
    n = got.get(c["file"], "(no name)"); low = n.lower().replace("_", "-")
    hit = n != "(no name)" and all(any(a in low for a in g) for g in c["must"])
    words = len([w for w in re.split(r"[-\s]+", low) if w])
    ok += hit
    rows.append((("✓" if hit else "✗"), c["id"], n, c["ideal"], words))
for r in rows: print(f"{r[0]} {r[1]:22} {r[2]:42} (want ≈ {r[3]})")
print(f"\nSCORE {ok}/{len(cases)}   avg words {sum(r[4] for r in rows)/len(rows):.1f}")
