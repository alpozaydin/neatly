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
FILTER=${1:-}
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
    waitfor '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]' 90
    check "no answer: saved after the countdown" '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]'
    check "logged as auto (doesn't teach)" '[ "$(corr auto)" = "True" ]'
    stop; fi

if want dl-duplicate; then setup dl-duplicate; start "dialog:save" 3
    f=$(make ceng-syllabus); cp "$f" "$T/stage/copy.pdf"
    arrive "$f"
    waitfor '[ -f "$T/home/courses-fall26/ceng334/ceng334-syllabus.pdf" ]' 90
    mv "$T/stage/copy.pdf" "$T/dl/8812_4471 (1).pdf"
    waitfor 'grep -q "moved to Trash" "$T/log"' 60
    check "same file again: the copy goes to the Trash after the countdown" '[ ! -e "$T/dl/8812_4471 (1).pdf" ]'
    check "no -2 copy in the folder" '[ "$(ls "$T/home/courses-fall26/ceng334" | wc -l | tr -d " ")" = "1" ]'
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
    for id in ceng-syllabus turkcell-invoice garanti-receipt payslip boarding-pass; do arrive "$(make $id)"; done
    waitfor '[ "$(grep -c "saved as" "$T/log")" -ge 5 ]' 180
    check "5 downloads at once: all 5 handled" '[ "$(grep -c "saved as" "$T/log")" -ge 5 ]'
    check "Downloads is empty or only renamed files" '! ls "$T/dl" | grep -q -E "^(8812_4471|EAF2026)"'
    stop; fi

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

if want shot-app; then setup shot-app; NEATLY_DATA_DIR=$T/data "$B" style --app on >/dev/null; start "none"
    shot; waitfor 'ls "$T/shots" | grep -qv "^Screenshot"' 90
    check "app name added (…-in-<app>)" 'ls "$T/shots" | grep -q -- "-in-"'
    stop; fi

if want shot-paused; then setup shot-paused; NEATLY_UI_TEST="menu:Pause" "$B" --watch "$T/dl" --screenshots --menubar > "$T/log" 2>&1 & PID=$!; sleep 5
    shot; sleep 8
    check "menu Pause: screenshot left alone" '[ -f "$T/shots/Screenshot 2026-10-09 at 11.26.48.png" ]'
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

# ─── Menu bar ───────────────────────────────────────────────────────────────
if want menu; then setup menu
    NEATLY_UI_TEST="menu:Name Length>Detailed,menu:Date>Date First,menu:Title Case,menu:Copy Screenshots to Clipboard" \
        "$B" --watch "$T/dl" --menubar > "$T/log" 2>&1 & PID=$!; sleep 5; stop
    s=$(cat "$T/data/style.json")
    check "length, date, case, clipboard saved" 'echo "$s" | grep -q detailed && echo "$s" | grep -q prefix && echo "$s" | grep -q "\"lowercase\" : false" && echo "$s" | grep -q "\"copyScreenshots\" : true"'
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
fi

echo
echo "$pass passed, $fail failed   (work folder: $W)"
for f in ${failed[@]+"${failed[@]}"}; do echo "  ✗ $f"; done
[ "$fail" = 0 ]
