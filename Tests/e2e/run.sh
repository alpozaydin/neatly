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

# ─── Menu bar ───────────────────────────────────────────────────────────────
if want menu; then setup menu
    NEATLY_UI_TEST="menu:Name Length>Detailed,menu:Date>Date First,menu:Title Case,menu:Copy Screenshots to Clipboard" \
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
