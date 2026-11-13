#!/bin/bash
# End-to-end tests: the real watcher, download popup, screenshot pill, Tidy window and menu bar,
# with every button pressed by code (NEATLY_UI_TEST). Never touches your files: each test gets its own
# temp folder with a fake home (NEATLY_HOME), its own data (NEATLY_DATA_DIR) and screenshot folder.
# Runs headless: nothing appears on screen, nothing takes focus.
#
#   swift build --product neatly && swift build -c release --product neatly-eval && Tests/e2e/run.sh [filter]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
B=${NEATLY_BIN:-$ROOT/.build/debug/neatly}
E=${NEATLY_EVAL:-$ROOT/.build/release/neatly-eval}
W=$(mktemp -d /tmp/neatly-e2e.XXXXXX)
export NEATLY_HEADLESS=1   # never show a window or take focus while testing
export NEATLY_NOTIFY=".test$$"   # our own "show window" signal: never reaches the neatly you actually run
FILTER=${1:-}
# Whatever happens, stop everything this run started (watchers, Tidy windows) when it ends.
trap 'pkill -f "$W" 2>/dev/null; pkill -f "neatly-e2e" 2>/dev/null' EXIT
pass=0; fail=0; failed=()

check() {   # check "what" 'shell condition'
    if eval "$2"; then echo "  ✓ $1"; pass=$((pass + 1)); else echo "  ✗ $1"; fail=$((fail + 1)); failed+=("$CUR: $1"); fi
}
waitfor() { for _ in $(seq 1 "${2:-60}"); do eval "$1" && return 0; sleep 1; done; return 1; }
setup() {
    CUR=$1; T=$W/$1
    mkdir -p "$T/home/courses-fall26/ceng334" "$T/home/finance" "$T/dl" "$T/shots" "$T/data" "$T/stage"
    export NEATLY_DATA_DIR=$T/data NEATLY_HOME=$T/home NEATLY_SCREENSHOT_DIR=$T/shots
    echo "• $1"
}
start() { NEATLY_UI_TEST="$1" "$B" --watch "$T/dl" --ask --screenshots --timeout "${2:-3}" > "$T/log" 2>&1 & PID=$!; sleep 3; }
stop() { kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; }
make() { "$E" --make "$1" "$T/stage" 2>/dev/null | tail -1; }        # a test file, with its "downloaded from" data
arrive() { mv "$1" "$T/dl/"; }                                         # a download finishing = a file appearing
corr() { python3 -c "import json,sys;d=[json.loads(l) for l in open('$T/data/corrections.jsonl')];print(d[-1].get('$1'))" 2>/dev/null; }
want() { [ -z "$FILTER" ] || [[ "$1" == *"$FILTER"* ]]; }

# Warm up: the first run of a new build loads the on-device model (~45 s).
"$B" --force "$ROOT/Package.swift" >/dev/null 2>&1

# ─── Downloads ──────────────────────────────────────────────────────────────
if want dl-save; then setup dl-save; start "dialog:save"
    arrive "$(make ceng-syllabus)"
    waitfor 'ls "$T"/home/courses-fall26/ceng334/*.pdf >/dev/null 2>&1' 90
    check "moved to the course folder with the suggested name" '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]'
    check "nothing left in Downloads" '[ -z "$(ls "$T/dl")" ]'
    check "logged as your answer (not auto)" '[ "$(corr auto)" = "None" ] && [ "$(corr chosen)" = "ceng334-syllabus" ]'
    check "undo info stored on the file" 'xattr "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" | grep -q dev.neatly.original-name'
    "$B" undo "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" >/dev/null
    check "undo puts it back in Downloads with its old name" '[ -f "$T/dl/8812_4471.pdf" ]'
    stop; fi

if want dl-edit; then setup dl-edit; start "dialog:edit:my-os-syllabus"
    arrive "$(make ceng-syllabus)"
    waitfor '[ -f "$T/home/courses-fall26/ceng334/my-os-syllabus.pdf" ]' 90
    check "your typed name is used" '[ -f "$T/home/courses-fall26/ceng334/my-os-syllabus.pdf" ]'
    check "edit logged for learning" '[ "$(corr chosen)" = "my-os-syllabus" ] && [ "$(corr suggested)" = "ceng334-syllabus" ]'
    check "your name is marked as yours" 'xattr "$T/home/courses-fall26/ceng334/my-os-syllabus.pdf" | grep -q dev.neatly.keep'
    stop; fi

if want dl-typed-path; then setup dl-typed-path; start "dialog:edit:$T/home/finance/typed-here"
    arrive "$(make ceng-syllabus)"
    waitfor '[ -f "$T/home/finance/typed-here.pdf" ]' 90
    check "a typed path moves it there" '[ -f "$T/home/finance/typed-here.pdf" ]'
    stop; fi

if want dl-keep; then setup dl-keep; start "dialog:keep"
    arrive "$(make ceng-syllabus)"
    waitfor 'grep -q "left as is" "$T/log"' 90
    check "Leave as is: same name, still in Downloads" '[ -f "$T/dl/8812_4471.pdf" ]'
    check "never asked again (keep mark)" 'xattr "$T/dl/8812_4471.pdf" | grep -q dev.neatly.keep'
    stop; fi

if want dl-place; then setup dl-place; start "dialog:place:$T/home/finance"
    arrive "$(make turkcell-invoice)"
    waitfor 'ls "$T"/home/finance/*.pdf >/dev/null 2>&1' 90
    check "Select place puts it in the chosen folder" 'ls "$T"/home/finance/invoice-turkcell*.pdf >/dev/null 2>&1'
    stop; fi

if want dl-outside-home; then setup dl-outside-home; start "dialog:place:/private/tmp"
    arrive "$(make turkcell-invoice)"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "a folder outside your home is refused (stays in Downloads)" 'ls "$T"/dl/invoice-turkcell*.pdf >/dev/null 2>&1'
    stop; fi

if want dl-countdown; then setup dl-countdown; start "dialog:wait" 3
    arrive "$(make ceng-syllabus)"
    waitfor '[ -f "$T/dl/ceng334-syllabus.pdf" ]' 90
    check "no answer: renamed, but stays in Downloads (nothing moves unseen)" '[ -f "$T/dl/ceng334-syllabus.pdf" ] && [ -z "$(ls "$T/home/courses-fall26/ceng334")" ]'
    check "logged as auto (doesn't teach), without what the file said" '[ "$(corr auto)" = "True" ] && [ "$(corr context)" = "None" ]'
    check "in History, as saved while you were away" 'grep -q "\"auto\":true" "$T/data/history.jsonl" && grep -q "ceng334-syllabus.pdf" "$T/data/history.jsonl"'
    stop; fi

if want dl-look; then setup dl-look; start "dialog:snapshot=$T/dialog.png" 4
    f=$(make ceng-syllabus); cp "$f" "$T/home/courses-fall26/ceng334/old-copy.pdf"; arrive "$f"
    waitfor '[ -s "$T/dialog.png" ]' 90
    check "download popup drawn (light and dark)" '[ -s "$T/dialog.png" ] && [ -s "$T/dialog-dark.png" ]'
    waitfor 'grep -q "saved as" "$T/log"' 30
    stop; fi

# A rule ("Always do this") is followed even when nobody answers.
if want dl-rule; then setup dl-rule
    NEATLY_DATA_DIR=$T/data "$B" style --length short >/dev/null
    python3 -c "import json;p='$T/data/style.json';d=json.load(open(p));d['rules']={'odtuclass.metu.edu.tr':'$T/home/finance'};json.dump(d,open(p,'w'))"
    start "dialog:wait" 3
    arrive "$(make ceng-syllabus)"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "your rule: no answer, still goes to the rule's folder" '[ -f "$T/home/finance/ceng334-syllabus.pdf" ]'
    check "the popup said it was your rule" 'grep -q "(your rule)" "$T/log"'
    stop; fi

if want dl-duplicate; then setup dl-duplicate; start "dialog:trash" 3
    f=$(make ceng-syllabus); cp "$f" "$T/stage/copy.pdf"
    arrive "$f"
    waitfor 'grep -q "left as is" "$T/log"' 90
    mv "$T/stage/copy.pdf" "$T/dl/8812_4471 (1).pdf"
    waitfor 'grep -q "moved to Trash" "$T/log"' 60
    check "same file again: Move to Trash in the popup trashes the copy" '[ ! -e "$T/dl/8812_4471 (1).pdf" ] && [ -f "$T/dl/8812_4471.pdf" ]'
    stop; fi

if want dl-duplicate-wait; then setup dl-duplicate-wait; start "dialog:wait" 3
    f=$(make ceng-syllabus); cp "$f" "$T/stage/copy.pdf"
    arrive "$f"
    waitfor '[ -f "$T/dl/ceng334-syllabus.pdf" ]' 90
    mv "$T/stage/copy.pdf" "$T/dl/8812_4471 (1).pdf"
    waitfor '[ "$(grep -c "saved as" "$T/log")" -ge 2 ]' 60
    check "same file again, no answer: both kept, nothing trashed" '[ "$(ls "$T/dl" | wc -l | tr -d " ")" = "2" ] && ! grep -q "Trash" "$T/log"'
    stop; fi

# Not from a browser (curl, an agent): written in pieces with pauses. Must wait until it's really done.
if want dl-slow-writer; then setup dl-slow-writer; start "dialog:save" 3
    f=$(make ceng-syllabus); xattr -c "$f"; size=$(stat -f %z "$f")
    half=$((size / 2))
    head -c $half "$f" > "$T/dl/8812_4471.pdf"; sleep 2
    tail -c +$((half + 1)) "$f" >> "$T/dl/8812_4471.pdf"
    waitfor 'grep -q "saved as" "$T/log"' 90
    out=$(find "$T/dl" "$T/home" -name "*.pdf" | head -1)
    check "a file written with a 2 s pause is handled once, complete" '[ "$(grep -c "→\|name ok" "$T/log")" = "1" ] && [ "$(stat -f %z "$out")" = "$size" ]'
    stop; fi

# The file changes while the popup is open: neatly doesn't act on what it saw before; it looks again.
if want dl-changed; then setup dl-changed; start "dialog:wait" 6
    f=$(make ceng-syllabus); arrive "$f"
    waitfor 'grep -q "folder:" "$T/log"' 90
    echo "more" >> "$T/dl/8812_4471.pdf"
    waitfor 'grep -q "changed while" "$T/log"' 30
    check "changed while the popup was open: not renamed on old information" 'grep -q "changed while" "$T/log"'
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "…and handled again once it settled" 'grep -q "saved as" "$T/log"'
    stop; fi

if want dl-partial; then setup dl-partial; start "dialog:save"
    f=$(make turkcell-invoice); cp "$f" "$T/dl/EAF2026000123456.pdf.crdownload"; rm "$f"
    sleep 5
    check "an unfinished download is not touched" '[ -f "$T/dl/EAF2026000123456.pdf.crdownload" ] && ! grep -q "→" "$T/log"'
    mv "$T/dl/EAF2026000123456.pdf.crdownload" "$T/dl/EAF2026000123456.pdf"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "handled once, when finished" '[ "$(grep -c "→" "$T/log")" = "1" ]'
    stop; fi

if want dl-skips; then setup dl-skips; start "dialog:save"
    head -c 2000 /dev/urandom > "$T/stage/Install Thing.dmg"; arrive "$T/stage/Install Thing.dmg"
    mkdir "$T/dl/some folder"
    sleep 8
    check "installers are left alone" '[ -f "$T/dl/Install Thing.dmg" ] && ! grep -q "saved as" "$T/log"'
    check "folders are left alone" '[ -d "$T/dl/some folder" ]'
    stop; fi

if want dl-weird-names; then setup dl-weird-names; start "dialog:save"
    f=$(make metu-transcript); mv "$f" "$T/stage/Ödev \"çözüm\" (1) — final’s copy.pdf"
    arrive "$T/stage/Ödev \"çözüm\" (1) — final’s copy.pdf"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "quotes, accents and dashes in the name: no crash, saved" 'grep -q "saved as" "$T/log"'
    stop; fi

if want dl-burst; then setup dl-burst; start "dialog:save"
    for id in ceng-syllabus turkcell-invoice garanti-receipt payslip boarding-pass metu-transcript homework lab-manual exam-schedule; do
        arrive "$(make $id)"; done
    waitfor '[ "$(grep -c "saved as" "$T/log")" -ge 9 ]' 300
    check "9 downloads at once: all 9 handled, none lost" '[ "$(grep -c "saved as" "$T/log")" -ge 9 ]'
    check "every file still exists (renamed or with its downloaded name)" '[ "$(find "$T/dl" "$T/home" -type f | wc -l | tr -d " ")" -ge 9 ]'
    check "Downloads is empty or only renamed files" '! ls "$T/dl" | grep -q -E "^(8812_4471|EAF2026)"'
    stop
    # Stopping the watcher mid-burst leaves its requests running in macOS's shared AI service; let them drain,
    # or the next tests wait behind them (a real burst finishes normally — nobody kills neatly halfway).
    sleep 25; fi

# ─── How browsers really download ───
if want dl-firefox; then setup dl-firefox; start "dialog:save"
    # Firefox: an EMPTY file with the final name + a .part it writes into, then the .part replaces the empty one.
    : > "$T/dl/EAF2026000123456.pdf"; f=$(make turkcell-invoice); cp "$f" "$T/dl/EAF2026000123456.pdf.part"; rm "$f"
    sleep 4
    check "Firefox: the empty placeholder is not touched" '! grep -q "→" "$T/log" && [ -f "$T/dl/EAF2026000123456.pdf" ]'
    mv -f "$T/dl/EAF2026000123456.pdf.part" "$T/dl/EAF2026000123456.pdf"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "Firefox: the real file is handled when it lands" 'ls "$T/home/finance" "$T/dl" 2>/dev/null | grep -q invoice-turkcell'
    stop; fi

if want dl-safari; then setup dl-safari; start "dialog:save"
    # Safari: downloads into "x.pdf.download/" (a folder), then renames it to the finished file.
    mkdir "$T/dl/EAF2026000123456.pdf.download"; f=$(make turkcell-invoice); cp "$f" "$T/dl/EAF2026000123456.pdf.download/data"; sleep 3
    mv "$f" "$T/stage/real.pdf"; rm -rf "$T/dl/EAF2026000123456.pdf.download"; mv "$T/stage/real.pdf" "$T/dl/EAF2026000123456.pdf"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "Safari: handled once, after it finished" '[ "$(grep -c "→\|name ok" "$T/log")" = "1" ]'
    stop; fi

if want dl-vanished; then setup dl-vanished; start "dialog:wait" 4
    arrive "$(make ceng-syllabus)"; sleep 2; rm -f "$T/dl/8812_4471.pdf"     # you deleted it while the popup was open
    sleep 8
    check "file gone while the popup is open: no crash, watcher keeps going" 'kill -0 $PID 2>/dev/null'
    arrive "$(make turkcell-invoice)"
    waitfor 'grep -q "EAF2026000123456" "$T/log"' 60
    check "…and the next download still works" 'grep -q "EAF2026000123456" "$T/log"'
    stop; fi

if want dl-typed-odd; then setup dl-typed-odd; start "dialog:edit:.Q3: report"
    arrive "$(make ceng-syllabus)"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "typed name starting with a dot doesn't hide the file" '! find "$T/home" "$T/dl" -name ".*.pdf" | grep -q .'
    check "a colon in a typed name becomes a dash" 'find "$T/home" "$T/dl" -name "*Q3- report*" | grep -q .'
    stop; fi

if want dl-locked; then setup dl-locked; start "dialog:save"
    f=$(make ceng-syllabus); arrive "$f"; chflags uchg "$T/dl/8812_4471.pdf"    # locked after it arrived
    waitfor 'grep -q -E "saved as|couldn|left as is" "$T/log"' 90; sleep 2
    check "locked file: says it couldn't rename, file untouched" 'grep -q "couldn.t rename" "$T/log" && [ -f "$T/dl/8812_4471.pdf" ]'
    check "locked file: no crash, watcher keeps going" 'kill -0 $PID 2>/dev/null'
    chflags -R nouchg "$T" 2>/dev/null
    stop; fi

if want dl-no-access; then setup dl-no-access
    chmod 000 "$T/dl"
    "$B" --watch "$T/dl" --ask > "$T/log" 2>&1 & PID=$!; sleep 4
    check "no permission for Downloads: says so (not silent)" 'grep -q -i "can.t see\|no access\|permission" "$T/log"'
    chmod 755 "$T/dl"; stop; fi

# ─── Screenshots ────────────────────────────────────────────────────────────
shot() { "$E" --make shot-recipe "$T/stage" >/dev/null 2>&1; mv "$T/stage/Screenshot 2026-10-09 at 11.26.48.png" "$T/shots/"; }

if want shot-keep; then setup shot-keep; start "none"
    shot; waitfor 'ls "$T/shots" | grep -qv "^Screenshot"' 90
    check "named in place, no popup" 'ls "$T/shots" | grep -q -E "^(smoky|black|chili)"'
    waitfor '[ -s "$T/data/corrections.jsonl" ]' 20     # written when the pill closes
    check "pill timed out: logged as auto" '[ "$(corr auto)" = "True" ]'
    stop; fi

if want shot-edit; then setup shot-edit; start "edit:chili-night"
    shot; waitfor '[ -f "$T/shots/chili-night.png" ]' 90
    check "pill: typed name used" '[ -f "$T/shots/chili-night.png" ]'
    check "pill: edit logged as yours" '[ "$(corr chosen)" = "chili-night" ] && [ "$(corr auto)" = "None" ]'
    stop; fi

if want shot-undo; then setup shot-undo; start "undo"
    shot; waitfor 'grep -q undone "$T/log"' 90
    check "pill: Undo restores the original name" '[ -f "$T/shots/Screenshot 2026-10-09 at 11.26.48.png" ]'
    stop; fi

if want shot-redo; then setup shot-redo; start "redo"
    shot; waitfor 'grep -q -E "another name|no other name" "$T/log"' 90; sleep 25
    names=$(grep -o -E "→  [^ ]+|another name: [^ ]+" "$T/log" | awk '{print $NF}')
    check "pill: ↻ never repeats a name" '[ "$(echo "$names" | sort | uniq -d | wc -l | tr -d " ")" = "0" ]'
    stop; fi

if want shot-app; then setup shot-app; NEATLY_DATA_DIR=$T/data "$B" style --app on >/dev/null; NEATLY_FRONT_APP=Safari start "none"
    shot; waitfor 'ls "$T/shots" | grep -qv "^Screenshot"' 90
    check "app name added (…-in-safari)" 'ls "$T/shots" | grep -q -- "-in-safari"'
    stop; fi

if want shot-paused; then setup shot-paused; NEATLY_UI_TEST="menu:Pause" "$B" --watch "$T/dl" --screenshots --menubar > "$T/log" 2>&1 & PID=$!; sleep 5
    shot; sleep 8
    check "menu Pause: screenshot left alone" '[ -f "$T/shots/Screenshot 2026-10-09 at 11.26.48.png" ]'
    stop; fi

if want shot-cleanshot; then setup shot-cleanshot; start "none"
    "$E" --make shot-recipe "$T/stage" >/dev/null 2>&1
    mv "$T/stage/Screenshot 2026-10-09 at 11.26.48.png" "$T/shots/CleanShot 2026-11-12 at 10.04.11@2x.png"
    waitfor 'ls "$T/shots" | grep -qv "^CleanShot"' 90
    check "CleanShot screenshots are named too" 'ls "$T/shots" | grep -qv "^CleanShot"'
    stop; fi

if want shot-two; then setup shot-two; start "none"
    "$E" --make shot-recipe "$T/stage" >/dev/null 2>&1; "$E" --make shot-weather "$T/stage" >/dev/null 2>&1
    mv "$T/stage/Screenshot 2026-10-09 at 11.26.48.png" "$T/shots/"; sleep 1
    mv "$T/stage/Screenshot 2026-10-11 at 09.20.03.png" "$T/shots/"      # second one while the first pill shows
    waitfor '[ "$(ls "$T/shots" | grep -c "^Screenshot")" = "0" ]' 120
    check "two screenshots in a row: both named" '[ "$(ls "$T/shots" | grep -c "^Screenshot")" = "0" ]'
    stop; fi

# ─── Tidy ───────────────────────────────────────────────────────────────────
if want tidy; then setup tidy
    for id in shot-recipe shot-weather error-screenshot; do "$E" --make $id "$T/shots" >/dev/null 2>&1; done
    echo hi > "$T/shots/my notes for monday.txt"
    NEATLY_UI_TEST="edit0:first-one,untick1,rename,done" "$B" tidy "$T/shots" > "$T/log" 2>&1
    check "edited name used" '[ -f "$T/shots/first-one.png" ]'
    check "unticked file untouched" '[ "$(ls "$T/shots" | grep -c "^Screenshot")" = "1" ]'
    check "your own name untouched" '[ -f "$T/shots/my notes for monday.txt" ]'
    "$B" undo --last >/dev/null
    check "undo --last restores all" '[ "$(ls "$T/shots" | grep -c "^Screenshot")" = "3" ]'
    NEATLY_UI_TEST="rename,undoall,done" "$B" tidy "$T/shots" > "$T/log" 2>&1
    check "Undo All in the window restores all" '[ "$(ls "$T/shots" | grep -c "^Screenshot")" = "3" ]'
fi

# A file neatly can't read stays editable: type a name, Rename works (v0.3.0 locked the field — dead end).
if want tidy-noidea; then setup tidy-noidea
    echo "x" > "$T/stage/certificate_of_attendance.doc"
    NEATLY_UI_TEST="edit0:attendance-certificate,rename,done" "$B" tidy "$T/stage/certificate_of_attendance.doc" > "$T/log" 2>&1
    check "no suggestion, but typing a name and Rename works" '[ -f "$T/stage/attendance-certificate.doc" ]'
fi

# ─── History: Revert, Always do this, Undo Last Download ───────────────────────
if want history; then setup history; start "dialog:save"
    arrive "$(make ceng-syllabus)"
    waitfor '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]' 90
    stop
    NEATLY_UI_TEST="menu:History…,history:always0,history:snapshot=$T/history.png,history:revert0" \
        "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 6; stop
    check "Revert puts the download back in Downloads with its old name" '[ -f "$T/dl/8812_4471.pdf" ] && [ ! -e "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]'
    check "…and marks it put back" 'grep -q "\"reverted\":true" "$T/data/history.jsonl"'
    check "Always do this saves a rule for the site" 'grep -q "odtuclass.metu.edu.tr" "$T/data/style.json"'
    check "History window drawn (light and dark)" '[ -s "$T/history.png" ] && [ -s "$T/history-dark.png" ]'
    NEATLY_UI_TEST="menu:Undo Last Download" "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 4; stop
    check "Undo Last Download with nothing left: says so, no crash" 'grep -q -i "no item\|nothing" "$T/log"'
fi

if want undo-download; then setup undo-download; start "dialog:save"
    arrive "$(make ceng-syllabus)"
    waitfor '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]' 90
    stop
    NEATLY_UI_TEST="menu:Undo “ceng334-syllabus.pdf”" "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 4; stop
    check "menu Undo Last Download puts it back" '[ -f "$T/dl/8812_4471.pdf" ]'
    check "…and says so" 'grep -q "notice: Put back" "$T/log"'
fi

if want forget; then setup forget; start "dialog:save"
    arrive "$(make ceng-syllabus)"
    waitfor 'grep -q "saved as" "$T/log"' 90; stop
    NEATLY_UI_TEST="home:forget=1,home:online=off" "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 4; stop
    check "Forget my history deletes the learning log and History" '[ ! -e "$T/data/corrections.jsonl" ] && [ ! -e "$T/data/history.jsonl" ]'
    check "online lookups can be turned off" 'grep -q "\"onlineLookups\" : false" "$T/data/style.json"'
    NEATLY_UI_TEST="home:uninstall=1" "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 3; stop
    check "Uninstall button is wired up (tests never really uninstall)" 'grep -q "home: uninstall" "$T/log"'
fi

# ─── Menu bar ───────────────────────────────────────────────────────────────
if want menu; then setup menu
    NEATLY_UI_TEST="menu:Name Length>Long,menu:Date>Date First,menu:Title Case,menu:Copy Screenshots to Clipboard" \
        "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 5; stop
    s=$(cat "$T/data/style.json")
    check "length, date, case, clipboard saved" 'echo "$s" | grep -q detailed && echo "$s" | grep -q prefix && echo "$s" | grep -q "\"lowercase\" : false" && echo "$s" | grep -q "\"copyScreenshots\" : true"'
fi

# ─── The neatly window (opened from Spotlight/Applications) ──────────────────
if want home; then setup home
    "$E" --make shot-recipe "$T/stage" >/dev/null 2>&1
    NEATLY_UI_TEST="home:length=detailed,home:style=title,home:date=on,home:countdown=10,home:screenshots=off,home:drop=$T/stage/Screenshot 2026-10-09 at 11.26.48.png,home:snapshot=$T/home.png" \
        "$B" --watch "$T/dl" --screenshots --menubar > "$T/log" 2>&1 & PID=$!; sleep 5
    s=$(cat "$T/data/style.json")
    check "window choices are saved (length, style, date, countdown)" 'echo "$s" | grep -q detailed && echo "$s" | grep -q prefix && echo "$s" | grep -q "\"countdown\" : 10" && echo "$s" | grep -q "\"lowercase\" : false"'
    check "dropping files on the window opens Tidy for them" 'grep -q "dropped 1 item" "$T/log"'
    pkill -f "neatly tidy $T" 2>/dev/null
    "$E" --make shot-weather "$T/stage" >/dev/null 2>&1; mv "$T/stage/Screenshot 2026-10-11 at 09.20.03.png" "$T/shots/"; sleep 6
    check "“New screenshots” off: screenshots are left alone" '[ -f "$T/shots/Screenshot 2026-10-11 at 09.20.03.png" ]'
    check "window drawn (light and dark)" '[ -s "$T/home.png" ] && [ -s "$T/home-dark.png" ]'
    n=$(grep -c "home: shown" "$T/log")
    osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("dev.neatly.show'"$NEATLY_NOTIFY"'", $(), $(), true)' >/dev/null
    sleep 2
    check "opening the app while it runs shows the window (no second copy)" '[ "$(grep -c "home: shown" "$T/log")" -gt "$n" ]'
    stop; fi

# ─── Run by name, the way Homebrew installs it (v0.2.0 crashed here: it looked for ./neatly) ───
if want by-name; then setup by-name
    mkdir -p "$T/Cellar/neatly/9.9/bin" "$T/bin" "$T/elsewhere" "$T/apps"
    cp "$B" "$T/Cellar/neatly/9.9/bin/neatly"; ln -s "$T/Cellar/neatly/9.9/bin/neatly" "$T/bin/neatly"
    out=$(cd "$T/elsewhere" && PATH="$T/bin:$PATH" NEATLY_APP_DIR="$T/apps" neatly app-bundle 2>&1)
    check "\`neatly\` from PATH, in another folder: builds the app (no crash)" '[ -x "$T/apps/neatly.app/Contents/MacOS/neatly" ]'
    (cd "$T/elsewhere" && PATH="$T/bin:$PATH" NEATLY_UI_TEST="dialog:save" neatly --watch "$T/dl" --ask --timeout 3 > "$T/log" 2>&1) & PID=$!; sleep 3
    arrive "$(make ceng-syllabus)"
    waitfor 'grep -q "saved as" "$T/log"' 90
    check "…and its download popup works too" '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]'
    stop; pkill -f "$T/bin/neatly" 2>/dev/null
fi

# ─── Auto-update, against a fake release (never the real app or GitHub) ───
if want update; then setup update; mkdir -p "$T/apps" "$T/rel"
    cp "$B" "$T/rel/neatly"; codesign --force --sign - "$T/rel/neatly" 2>/dev/null
    tar -czf "$T/rel/neatly-macos-arm64.tar.gz" -C "$T/rel" neatly
    shasum -a 256 "$T/rel/neatly-macos-arm64.tar.gz" > "$T/rel/neatly-macos-arm64.tar.gz.sha256"
    v=$("$B" --version | awk '{print $2}')
    feed() { printf '{"tag_name":"v%s","assets":[{"name":"neatly-macos-arm64.tar.gz","browser_download_url":"file://%s"},{"name":"neatly-macos-arm64.tar.gz.sha256","browser_download_url":"file://%s"}]}' "$v" "$T/rel/neatly-macos-arm64.tar.gz" "$1" > "$T/rel/latest.json"; }
    NEATLY_APP_DIR=$T/apps "$B" app-bundle >/dev/null; ino=$(stat -f %i "$T/apps/neatly.app")
    export NEATLY_APP_DIR=$T/apps NEATLY_UPDATE_URL=file://$T/rel/latest.json
    echo "0000000000000000000000000000000000000000000000000000000000000000  x" > "$T/rel/bad.sha256"; feed "$T/rel/bad.sha256"
    out=$(NEATLY_VERSION_OVERRIDE=0.0.1 "$B" update 2>&1)
    check "wrong fingerprint: update refused, app untouched" 'echo "$out" | grep -q "checksum" && [ "$(stat -f %i "$T/apps/neatly.app")" = "$ino" ]'
    feed "$T/rel/neatly-macos-arm64.tar.gz.sha256"
    out=$(NEATLY_VERSION_OVERRIDE=9.9.9 "$B" update 2>&1)
    check "already newest: nothing happens" 'echo "$out" | grep -q "up to date"'
    out=$(NEATLY_UPDATE_URL=http://127.0.0.1:9/none NEATLY_VERSION_OVERRIDE=0.0.1 "$B" update 2>&1)
    check "offline: no error, nothing happens" 'echo "$out" | grep -q "up to date"'
    out=$(NEATLY_VERSION_OVERRIDE=0.0.1 "$B" update 2>&1)
    check "newer version: downloaded, checked and installed" 'echo "$out" | grep -q "updated to neatly $v"'
    check "…in place (Launchpad keeps it), signed, runs" '[ "$(stat -f %i "$T/apps/neatly.app")" = "$ino" ] && codesign --verify --deep "$T/apps/neatly.app" 2>/dev/null && "$T/apps/neatly.app/Contents/MacOS/neatly" --version | grep -q "$v"'
    # The background service does it by itself — only after the person said yes.
    NEATLY_DATA_DIR=$T/data "$B" style --length short >/dev/null
    NEATLY_VERSION_OVERRIDE=0.0.1 NEATLY_UPDATE_SOON=1 "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 6
    check "not asked yet / said no: never updates" '! grep -q "updated to" "$T/log"'
    stop
    python3 -c "import json;p='$T/data/style.json';d=json.load(open(p));d['autoUpdate']=True;json.dump(d,open(p,'w'))"
    NEATLY_VERSION_OVERRIDE=0.0.1 NEATLY_UPDATE_SOON=1 "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!
    waitfor 'grep -q "updated to" "$T/log"' 40
    check "said yes once: the service updates by itself" 'grep -q "updated to neatly $v" "$T/log"'
    stop
    check "the version before is kept, to go back to" '[ -x "$T/data/previous/neatly" ] && [ "$(cat "$T/data/previous/version")" = "0.0.1" ]'
    # The new version keeps crashing (3 starts without running 2 minutes): the 4th start goes back.
    printf '{"to":"7.7.7","from":"0.0.1","starts":3}' > "$T/data/update-pending.json"
    NEATLY_VERSION_OVERRIDE=7.7.7 "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 5; stop
    check "a version that keeps stopping is rolled back by itself" 'grep -q "keeps stopping" "$T/log" && [ "$(plutil -extract CFBundleShortVersionString raw "$T/apps/neatly.app/Contents/Info.plist")" = "0.0.1" ]'
    check "…and not installed again" '[ "$(cat "$T/data/update-skip")" = "7.7.7" ]'
    printf '{"to":"7.7.8","from":"0.0.1","starts":0}' > "$T/data/update-pending.json"
    NEATLY_VERSION_OVERRIDE=7.7.8 NEATLY_UPDATE_SOON=1 "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!
    waitfor 'grep -q "running fine" "$T/log"' 20; stop
    check "a version that runs fine is kept" 'grep -q "running fine" "$T/log" && [ ! -e "$T/data/update-pending.json" ]'
    unset NEATLY_APP_DIR NEATLY_UPDATE_URL
fi

# ─── The one-line installer (only its refusals: a real install would change your login items) ───
if want installer; then setup installer; mkdir -p "$T/rel"
    cp "$B" "$T/rel/neatly"; tar -czf "$T/rel/neatly-macos-arm64.tar.gz" -C "$T/rel" neatly
    echo "0000000000000000000000000000000000000000000000000000000000000000  x" > "$T/rel/neatly-macos-arm64.tar.gz.sha256"
    out=$(HOME=$T/home NEATLY_URL=file://$T/rel/neatly-macos-arm64.tar.gz sh "$ROOT/scripts/install.sh" 2>&1)
    check "installer: a download that doesn't match its fingerprint is refused, nothing installed" 'echo "$out" | grep -q "damaged" && [ ! -e "$T/home/Library/LaunchAgents" ]'
    out=$(head -c 900 "$ROOT/scripts/install.sh" | HOME=$T/home sh 2>&1)
    check "installer: a script cut off halfway runs nothing" '! echo "$out" | grep -q "Downloading"'
fi

# ─── neatly.app (built into a temp folder; never touches the installed app or login item) ───
if want app; then setup app; mkdir -p "$T/apps"
    NEATLY_APP_DIR=$T/apps "$B" app-bundle > /dev/null
    A=$T/apps/neatly.app
    check "app bundle built" '[ -x "$A/Contents/MacOS/neatly" ]'
    check "menu-bar app (no Dock icon), right id" '[ "$(plutil -extract LSUIElement raw "$A/Contents/Info.plist")" = "true" ] && [ "$(plutil -extract CFBundleIdentifier raw "$A/Contents/Info.plist")" = "dev.neatly.app" ]'
    check "has an icon" '[ -s "$A/Contents/Resources/AppIcon.icns" ]'
    check "signature valid" 'codesign --verify --deep "$A" 2>/dev/null'
    check "app binary runs" '"$A/Contents/MacOS/neatly" --version | grep -q "^neatly "'
    before=$(stat -f %i "$A"); NEATLY_APP_DIR=$T/apps "$B" app-bundle > /dev/null
    check "updating keeps the same app (Launchpad/Dock don't lose it)" '[ "$(stat -f %i "$A")" = "$before" ] && codesign --verify --deep "$A" 2>/dev/null && "$A/Contents/MacOS/neatly" --version | grep -q "^neatly "'
fi

echo
echo "$pass passed, $fail failed   (work folder: $W)"
for f in ${failed[@]+"${failed[@]}"}; do echo "  ✗ $f"; done
[ "$fail" = 0 ]
