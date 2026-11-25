# neatly user guide

Everything neatly does, every setting, and the command line. For a quick overview see the [README](../README.md).

## Install and updates

```sh
curl -fsSL https://raw.githubusercontent.com/alpozaydin/neatly/main/scripts/install.sh | sh
```

or with Homebrew: `brew install alpozaydin/tap/neatly && neatly service install`

Needs a Mac with Apple silicon and macOS 26 or newer. Turn on Apple Intelligence for the best names;
everything except the last step below works without it. No Xcode needed.

This installs **neatly.app** (in Applications, Spotlight and your menu bar) and starts it at login.
neatly **keeps itself up to date**: new versions install quietly in the background whenever you're online
(each download's SHA-256 is checked first; a mismatch changes nothing). Turn it off in **More options → Update
neatly automatically**. If a new version keeps crashing, neatly goes back to the previous one by itself.
The installer checks the download's SHA-256 before installing anything, and each release carries a signed record
of how GitHub built it (`gh attestation verify neatly-macos-arm64.tar.gz -R alpozaydin/neatly`).
Uninstall: open neatly → **More options → Uninstall neatly** (or `neatly service uninstall`; then `brew uninstall neatly`
if you used Homebrew). Moved neatly.app to another folder? Open it once from there and it carries on from the new place.

## Privacy

Your files are read and named on your Mac. Three things go online:

- **Update check** (on unless you turn it off): asks GitHub for the latest release. Nothing about you or your files is sent.
- **Paper lookup**: for a research paper with an arXiv number (e.g. `2405.12345.pdf`), neatly asks
  export.arxiv.org for its real title. Only that number is sent.
- **Photo places**: a photo from a phone records where it was taken. neatly asks Apple's map service which place
  that is, so the name can say it (`colosseum-in-rome`). Only the photo's coordinates are sent, never the photo.
  Screenshots are never looked up.

Turn both lookups off in **More options → Look up paper titles and photo places online**, or run with `--offline`.

neatly keeps, in `~/Library/Application Support/neatly/`: your settings, the names you chose (to learn your style;
the last 2,000), and the History of what it renamed (the last 500, for Revert). **More options → Forget my history**
deletes them. Activity is logged to `~/Library/Logs/neatly.log` (kept under 4 MB).

## What it does

Open **neatly** from Spotlight or Applications: a window with a drop zone (drop files or folders to name them),
one-click renaming for your Desktop, Downloads or any folder (**Rename messy files now**), and every setting. No Terminal needed.

- **Downloads** get a small popup with a suggested name **and folder** (below).
- **Screenshots** are named the moment you take them, in place, by what's on screen: `coldplay-concert-ticket`,
  `turkish-airlines-boarding-pass`, `istanbul-weather-forecast`. A small pill under the menu bar shows the
  new name: click it to change it, **↻** for another name, **Undo** to put it back. It never takes focus.
  **Screen recordings** are named the same way. Tip: macOS saves a screenshot only after its floating thumbnail
  goes away (about 5 s). For instant names, turn it off: **⌘⇧5 → Options → Show Floating Thumbnail**.
- **Photos** (downloaded, dropped on the icon, or in a folder you tidy) are named by what they show and, for phone
  photos, where they were taken: `galata-tower-in-istanbul`, `red-tulip-in-bloom`, `woman-portrait`.
- **From Finder**: select files or folders → right-click → **Quick Actions / Services → Rename with neatly**,
  or **Open With → neatly**. The review window opens for all of them (folders: the files inside).
- **History** (menu bar or the window): everything neatly renamed or moved, each with **Revert**. For a download,
  **Always do this** makes a rule: files from that site always go to that folder.
- **Menu-bar icon**: Rename Desktop Files, Rename Files in a Folder, History, Undo Last Download, name length, date, Title Case,
  app name, copy screenshots to the clipboard, Pause. **Drop files or a folder on the icon** to name them.
- **Tidy a folder** in a review window (`neatly tidy`, `neatly tidy ~/Downloads`): edit any name, untick what to
  keep, then Rename. **Undo All** puts every name back (`neatly undo --last` later).
- Works on PDFs, Word, PowerPoint, notebooks, e-books (EPUB), zips, images, screenshots and screen recordings.

## Downloads and the popup

```sh
neatly service install             # menu-bar icon + Downloads + screenshots, starting at login
neatly service uninstall           # stop it
neatly --watch ~/Downloads --ask --screenshots --menubar   # the same, in this terminal
```

A new download with a junk name gets a popup in the top-right corner with a suggested name and folder:

```
New download  scan_20261104_8812.pdf
Name    [Rent Agreement]
📁 Documents › Home                       Choose Folder…
If you don't answer in 5 s: Rename Only
                     [Keep Original]  [Rename Only]  [Rename & Move]
```

**Rename & Move** puts it in that folder with that name; **Rename Only** keeps it in Downloads. Edit the name to choose your own.
**Choose Folder…** saves it in a folder you pick (any folder you can write to, even on another drive). **Keep Original** changes nothing and won't ask again.
Installers (.dmg, .pkg) are skipped. The popup never takes the keyboard from the app you're typing in.

A download that already has a good name keeps it. If neatly knows a folder for it, the popup only offers the folder
("name looks good", **Move to** Companies › Fincart, **Keep in Downloads** / **Move**); if not, there's no popup.

**No answer in 5 seconds = the new name is kept, in Downloads**, so downloads made by agents or scripts never wait
for a click, and nothing moves to another folder while nobody's looking (unless you made a rule for that site with
**Always do this**). A pill then shows the new name with **Undo**. Moving the mouse over the popup or typing stops
the countdown. In the neatly window (More options → **If I don't answer a download suggestion**) you can change
the time, choose **Wait for me**, or choose **Keep Original**: then no answer means the file keeps its name and
stays where it is. From Terminal: `--timeout N` (`--timeout 0` waits for you), `--leave-if-away`.
A second copy of a file you already have is flagged in the popup with **Trash This Download**; with no answer, both are kept.

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
neatly learn ~/Documents         # learns e.g. "lowercase, '-'"  → rent-agreement
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

- **Names follow the folder.** A file going into a folder of `Lab Report - JKL` files gets the same
  separator, case and suffix as its neighbours (needs 3+ hand-named files there).
- **Your edits become examples.** When the on-device model names a file, it is shown up to 3 names you
  saved for the most similar past files (found with Apple's on-device text embedding). No training:
  the more you correct, the more it names files your way. Auto-saves and "Leave as is" don't count.

```sh
neatly stats      # how often you saved the suggestion unchanged, and your recent edits
```

## Naming style

By default names read like titles: **Turkish Airlines Boarding Pass**, **Netflix Invoice Nov 2026**,
**Colosseum in Rome**. Prefer compact names? Pick **with-dashes** under **Name style** (or
`neatly style --sep dash --case lower`): `turkish-airlines-boarding-pass`, `invoice-netflix-nov26`.

## How it decides (cheapest first, stops as soon as it's sure)

1. **Where the file came from** — macOS records the download URL.
2. **Exact lookups** — arXiv IDs → real paper title.
3. **Embedded metadata** — PDF title, etc.
4. **Page 1 only** — the biggest text on the page is almost always the title. A 400-page PDF costs the same as a 1-page one.
5. **OCR / photo labels** — only for images and scanned PDFs, on a downsampled page 1.
6. **Apple's on-device model** — only when the steps above can't decide, and it sees ~800 characters, never the whole file.

No confident name → no suggestion. A guess is worse than a junk name.
