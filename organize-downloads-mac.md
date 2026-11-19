---
layout: default
title: "How to organize the Downloads folder on Mac"
description: "Clean up a messy Mac Downloads folder and keep it clean: Finder tricks, folder rules, and automatic names and folders for every download with neatly (free, on-device)."
permalink: /organize-downloads-mac/
---

# How to organize the Downloads folder on Mac

Downloads fill up with files like `doc_8f3a2c_20261104.pdf`, `invoice_78123.pdf` and `IMG_4821.jpg`. The names say
nothing, so you end up opening each file to find the one you need. Here's how to clean it up once, and keep it clean.

## 1. Clean up what's already there

- **Sort by date added.** In Finder, open Downloads, choose View → as List, then right-click the column header and
  turn on **Date Added**. Old files sink to the bottom.
- **Group by kind.** View → Use Groups → **Kind** puts PDFs, images and installers together.
- **Delete installers.** `.dmg` and `.pkg` files are safe to delete once the app is installed.
- **Name the rest.** This is the slow part: open each file, read it, type a name.
  [neatly](../)'s **Tidy** window does it for a whole folder at once. You see every suggested name and folder, then
  click Rename. Every change can be reverted from History.

## 2. Keep it clean: name new downloads as they arrive

neatly watches your Downloads folder. When a file with a meaningless name arrives, a small popup suggests a clear
name **and the folder it belongs in**:

| Download | neatly suggests |
|---|---|
| `doc_8f3a2c_20261104.pdf` | `Water Bill Nov 2026.pdf` → Documents › Bills |
| `invoice_78123.pdf` | `Netflix Invoice Nov 2026.pdf` → Bills |
| `2304.02643v1.pdf` | `Segment Anything 2023.pdf` (the paper's real title) |
| `scan_20261104_8812.pdf` | `Rent Agreement.pdf` → Documents |

- **Never in your way.** Click Save, edit the name, or ignore it. After a short countdown it keeps the new name, so
  downloads by scripts or AI agents never wait on you.
- **"Download all" gets one popup.** Download ten photos at once and neatly asks once, with a folder name for the group.
- **Learns your folders.** It suggests the folder you'd pick, from the files already in your folders and your past choices.
- **"Always do this"** turns a choice into a rule.
- **Names you chose are never touched.** Only junk names like `IMG_4821` or `document (3)` get renamed.

<p><a style="display:inline-block;background:var(--deep);color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700" href="https://github.com/alpozaydin/neatly/releases/latest/download/neatly.dmg">⬇️ Download neatly for Mac</a></p>

## 3. Is it private?

Yes. neatly reads each file on your Mac with Apple's on-device model (Apple Intelligence): the browser's "where from"
address, the title, page 1 of a PDF, or what a photo shows. Files are never uploaded. There is no account and no
tracking. [Privacy details](../privacy/)

## Related

- [Rename screenshots automatically on Mac](../rename-screenshots-mac/)
- [AI file renamer for Mac: how it works](../ai-file-renamer-mac/)
- [neatly vs Finder, Shortcuts and Hazel](../alternatives/)
- [FAQ](../faq/)
