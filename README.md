# neatly

Suggests short, meaningful names for badly named files — `1234567_2026-11-04_124701.pdf` → `transcript-fall26.pdf`.
It also suggests **which folder** each download belongs in. Reading and naming happen on your Mac, with Apple's
on-device model; see [Privacy](#privacy) for the two things that go online.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/alpozaydin/neatly/main/scripts/install.sh | sh
```

or with Homebrew: `brew install alpozaydin/tap/neatly && neatly service install`

Needs a Mac with Apple silicon and macOS 26 or newer. Turn on Apple Intelligence for the best names;
everything except the last step below works without it. No Xcode needed.

This installs **neatly.app** (in Applications, Spotlight and your menu bar) and starts it at login.
The first time it opens, neatly asks once whether to **keep itself up to date**. If you say yes, new versions
install quietly in the background whenever you're online (each download's SHA-256 is checked first; a mismatch
changes nothing). If a new version keeps crashing, neatly goes back to the previous one by itself.
Uninstall: `neatly service uninstall` removes the app, the login item and the command (then `brew uninstall neatly`
if you used Homebrew).

## Privacy

Your files are read and named on your Mac. Two things go online:

- **Update check** (only if you said yes): asks GitHub for the latest release. Nothing about you or your files is sent.
- **Paper lookup**: for a research paper with an arXiv number (e.g. `2405.12345.pdf`), neatly asks
  export.arxiv.org for its real title. Only that number is sent. Turn it off in **More options → Look up research
  papers online**, or run with `--offline`.

neatly keeps, in `~/Library/Application Support/neatly/`: your settings, the names you chose (to learn your style;
the last 2,000), and the History of what it renamed (the last 500, for Revert). **More options → Forget my history**
deletes them. Activity is logged to `~/Library/Logs/neatly.log` (kept under 4 MB).

## How it decides (cheapest first, stops as soon as it's sure)

1. **Where the file came from** — macOS records the download URL.
2. **Exact lookups** — arXiv IDs → real paper title.
3. **Embedded metadata** — PDF title, etc.
4. **Page 1 only** — the biggest text on the page is almost always the title. A 400-page PDF costs the same as a 1-page one.
5. **OCR / photo labels** — only for images and scanned PDFs, on a downsampled page 1.
6. **Apple's on-device model** — only when the steps above can't decide, and it sees ~800 characters, never the whole file.

No confident name → no suggestion. A guess is worse than a junk name.

## Naming style

lowercase-kebab, most distinctive word first, qualifier last, as short as possible:
`transcript-fall26`, `unidepth-2024`, `invoice-turkcell-nov26`.

## What it does

Open **neatly** from Spotlight or Applications: a window with a drop zone (drop files or folders to name them),
one-click Tidy Desktop / Tidy Downloads / Choose a Folder, and every setting. No Terminal needed.

- **Downloads** get a small popup with a suggested name **and folder** (below).
- **Screenshots** are named the moment you take them, in place. A small pill under the menu bar shows the
  new name: click it to change it, **↻** for another name, **Undo** to put it back. It never takes focus.
- **History** (menu bar or the window): everything neatly renamed or moved, each with **Revert**. For a download,
  **Always do this** makes a rule: files from that site always go to that folder.
- **Menu-bar icon**: Tidy Desktop, Tidy a Folder, History, Undo Last Download, name length, date, Title Case,
  app name, copy screenshots to the clipboard, Pause. **Drop files or a folder on the icon** to name them.
- **Tidy a folder** in a review window (`neatly tidy`, `neatly tidy ~/Downloads`): edit any name, untick what to
  keep, then Rename. **Undo All** puts every name back (`neatly undo --last` later).
- Works on PDFs, Word, PowerPoint, notebooks, zips, images and screenshots.

## Live mode

```sh
neatly service install             # menu-bar icon + Downloads + screenshots, starting at login
neatly service uninstall           # stop it
neatly --watch ~/Downloads --ask --screenshots --menubar   # the same, in this terminal
```

Every new download gets a popup in the top-right corner with a suggested name and folder:

```
New download  8812_4471.pdf
Name    [ceng315-syllabus]
📁 courses-fall26 › ceng315                  Choose Folder…
Away? In 5 s it's renamed and stays in Downloads.   [Leave as Is]  [Save]
```

**Save** puts it in that folder with that name. Edit the name to choose your own.
**Choose Folder…** picks another folder. **Leave as Is** changes nothing and won't ask again.
Installers (.dmg, .pkg) are skipped. The popup never takes the keyboard from the app you're typing in.

**No answer in 5 seconds = the new name is kept, in Downloads**, so downloads made by agents or scripts never wait
for a click, and nothing moves to another folder while nobody's looking (unless you made a rule for that site with
**Always do this**). A pill then shows the new name with **Undo**. Moving the mouse over the popup or typing stops
the countdown. Change the time with `--timeout N` (`--timeout 0` waits for you).
A second copy of a file you already have is flagged in the popup with **Move to Trash**; with no answer, both are kept.

Before renaming or moving, neatly checks the file is still the one it looked at: if it was still being written or
was replaced meanwhile, it's looked at again. Files that don't come from a browser must sit unchanged for 3 seconds first.

Folders are suggested only if they already exist: a course code goes to that course's folder,
a file goes where you put the same kind of file last time, or to a folder whose name it mentions.
If none of these fit, the on-device model picks from your folders — but only a folder that shares
a word with the file. Otherwise the suggestion is Downloads. Your edits are saved in
`~/Library/Application Support/neatly/corrections.jsonl` so neatly can learn from them.
On the model path, the shortlist of folders is chosen by meaning: what the file is about vs. each
folder's name and the names of the files inside it.

## Your style

neatly can copy how you already name files. It reads only file **names**, never contents:

```sh
neatly learn ~/courses-fall26     # learns e.g. "lowercase, '-'"  → transcript-fall26
neatly style                       # show the current style
neatly style --reset               # forget it
```

Or set it yourself:

```sh
neatly style --length detailed     # short (default) · standard · detailed
neatly style --case title --sep space   # Hot Honey Cornbread  (lower|title, dash|underscore|space)
neatly style --date prefix         # 2026-11-11-hot-honey-cornbread  (none|prefix|suffix)
neatly style --app on              # screenshots end with the app: …-in-safari
neatly style --copy on             # new screenshots also go to the clipboard
```

It learns per folder and skips code repos. If your folders disagree, it saves nothing and tells you.
The style is one small file: `~/Library/Application Support/neatly/style.json`.

Two more things happen on their own:

- **Names follow the folder.** A file going into a folder of `Lab Report - MAO` files gets the same
  separator, case and suffix as its neighbours (needs 3+ hand-named files there).
- **Your edits become examples.** When the on-device model names a file, it is shown up to 3 names you
  saved for the most similar past files (found with Apple's on-device text embedding). No training:
  the more you correct, the more it names files your way. Auto-saves and "Leave as is" don't count.

```sh
neatly stats      # how often you saved the suggestion unchanged, and your recent edits
```

## Usage

Building from source needs Xcode or the Command Line Tools:

```sh
swift build -c release --product neatly
.build/release/neatly ~/Downloads            # dry run: prints suggestions
.build/release/neatly --apply ~/Downloads    # rename
.build/release/neatly undo transcript-fall26.pdf
swift run checks                            # self-checks
swift run -c release neatly-eval             # accuracy + speed score
```

Releases: push a tag (`git tag v0.1.1 && git push --tags`). GitHub builds the binary and publishes it;
then `scripts/update-tap.sh 0.1.1` updates Homebrew.

## Testing accuracy

`Tests/eval/cases.json` lists test files and the names we want for them.
`neatly-eval` creates those files (PDFs, scans, photos), runs neatly on them, and prints a score.
All test data is made up — no real personal files.

To add a case: copy one block in `cases.json`, change the text and the wanted names, run `neatly-eval`.

`Tests/e2e/run.sh` tests the whole app end to end: the real watcher, download popup, screenshot pill,
Tidy window and menu bar, with every button pressed by code. It runs headless (nothing appears on screen)
in a temp folder with its own fake home and data, so it never touches your files.
`Tests/e2e/run.sh dl-` runs only the download tests.

`Tests/eval/holdout.json` is a second set that the rules were **never** tuned on
(`neatly-eval --holdout`). Its score is the honest one. Don't change neatly to fix a held-out case:
move the pattern into `cases.json` and write a fresh held-out case instead.

Requires macOS 26+ (Apple Intelligence enabled for the model step; everything else works without it).
