# namer

Suggests short, meaningful names for badly named files — `1234567_2026-11-04_124701.pdf` → `transcript-fall26.pdf`.
It also suggests **which folder** each download belongs in. Runs entirely on your Mac, with Apple's on-device model.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/alpozaydin/tidy-mac/main/scripts/install.sh | sh
```

or with Homebrew: `brew install alpozaydin/tap/namer && namer service install`

Needs a Mac with Apple silicon and macOS 26 or newer. Turn on Apple Intelligence for the best names;
everything except the last step below works without it. No Xcode needed.

Uninstall: `namer service uninstall && rm ~/.local/bin/namer` (or `brew uninstall namer`).

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

## Live mode

```sh
namer --watch ~/Downloads --ask   # a small dialog for each new download
namer service install             # same, in the background, starting at login
namer service uninstall           # stop it
```

Every new download gets a dialog with a suggested folder and name:

```
Suggested folder:  courses-fall26 › ceng315
Suggested name:    [ceng315-syllabus]      Saves automatically  [Leave as is]  [Select place…]  [Save (5)]
```

**Save** puts it in that folder with that name. Edit the name to choose your own.
**Select place…** picks another folder. **Leave as is** changes nothing and won't ask again.
Installers (.dmg, .pkg) are skipped.

**No answer in 5 seconds = Save**, so downloads made by agents or scripts never wait for a click.
Moving the mouse over the dialog or typing stops the countdown. Change the time with
`--timeout N` (`--timeout 0` waits for you). A second copy of a file you already have goes to the Trash
the same way.

Folders are suggested only if they already exist: a course code goes to that course's folder,
a file goes where you put the same kind of file last time, or to a folder whose name it mentions.
If none of these fit, the on-device model picks from your folders — but only a folder that shares
a word with the file. Otherwise the suggestion is Downloads. Your edits are saved in
`~/Library/Application Support/namer/corrections.jsonl` so namer can learn from them.
On the model path, the shortlist of folders is chosen by meaning: what the file is about vs. each
folder's name and the names of the files inside it.

## Your style

namer can copy how you already name files. It reads only file **names**, never contents:

```sh
namer learn ~/courses-fall26     # learns e.g. "lowercase, '-'"  → transcript-fall26
namer style                       # show what it learned
namer style --reset               # forget it
```

It learns per folder and skips code repos. If your folders disagree, it saves nothing and tells you.
The style is one small file: `~/Library/Application Support/namer/style.json`.

Two more things happen on their own:

- **Names follow the folder.** A file going into a folder of `Lab Report - MAO` files gets the same
  separator, case and suffix as its neighbours (needs 3+ hand-named files there).
- **Your edits become examples.** When the on-device model names a file, it is shown up to 3 names you
  saved for the most similar past files (found with Apple's on-device text embedding). No training:
  the more you correct, the more it names files your way. Auto-saves and "Leave as is" don't count.

```sh
namer stats      # how often you saved the suggestion unchanged, and your recent edits
```

## Usage

Building from source needs Xcode or the Command Line Tools:

```sh
swift build -c release --product namer
.build/release/namer ~/Downloads            # dry run: prints suggestions
.build/release/namer --apply ~/Downloads    # rename
.build/release/namer undo transcript-fall26.pdf
swift run checks                            # self-checks
swift run -c release namer-eval             # accuracy + speed score
```

Releases: push a tag (`git tag v0.1.1 && git push --tags`). GitHub builds the binary and publishes it;
then `scripts/update-tap.sh 0.1.1` updates Homebrew.

## Testing accuracy

`Tests/eval/cases.json` lists test files and the names we want for them.
`namer-eval` creates those files (PDFs, scans, photos), runs namer on them, and prints a score.
All test data is made up — no real personal files.

To add a case: copy one block in `cases.json`, change the text and the wanted names, run `namer-eval`.

`Tests/eval/holdout.json` is a second set that the rules were **never** tuned on
(`namer-eval --holdout`). Its score is the honest one. Don't change namer to fix a held-out case:
move the pattern into `cases.json` and write a fresh held-out case instead.

Requires macOS 26+ (Apple Intelligence enabled for the model step; everything else works without it).
