---
layout: default
title: "AI file renamer for Mac: free, private, on-device"
description: "neatly is a free, open-source AI file renamer for Mac. It names downloads, screenshots and photos by what they are, on your Mac with Apple Intelligence. How it works and how it keeps files private."
permalink: /ai-file-renamer-mac/
---

# AI file renamer for Mac

An AI file renamer reads a file and names it by what it is: `IMG_4120.JPG` becomes `Galata Tower in Istanbul.jpg`,
`invoice_78123.pdf` becomes `Netflix Invoice Nov 2026.pdf`. [neatly](../) does this on your Mac, for free, with
nothing uploaded.

## What neatly renames

| Kind | Before | After |
|---|---|---|
| Screenshot | `Screenshot 2026-11-10 at 9.41.07.png` | `Turkish Airlines Boarding Pass.png` |
| Download | `doc_8f3a2c_20261104.pdf` | `Water Bill Nov 2026.pdf` |
| Research paper | `2304.02643v1.pdf` | `Segment Anything 2023.pdf` |
| Photo | `IMG_4108.HEIC` | `Colosseum in Rome.heic` |
| Scan | `scan_20261104_8812.pdf` | `Rent Agreement.pdf` |

It works three ways: **automatically** for new downloads and screenshots, **in bulk** with the Tidy window, and
**on demand** from Finder (right-click → Rename with neatly).

## How it works

neatly reads as little as it can, cheapest step first:

1. **Skip good names.** A name you chose is never changed. Only names like `IMG_4821`, `Screenshot 2026-…` or
   `document (3)` are touched.
2. **Read the cheap clues:** where the file was downloaded from, its title, page 1 of a PDF, the text on a screenshot.
3. **Simple rules** for common files such as invoices, receipts, tickets and official forms. Instant and predictable.
4. **Apple Intelligence**, on device, sees at most a page of text or the image itself, and names what it is.
5. **Check the answer.** Typos are fixed from the file's own text and made-up words are dropped. If it's unsure, the
   name stays as it is.

It also learns your style from the names you edit, and suggests the folder you would pick.

## Why on-device matters

Many AI renamers send your files to a cloud model. Your files include bank statements, contracts, IDs and private
photos. neatly uses Apple's on-device model, so the content never leaves your Mac. Three small lookups can go online,
and each can be turned off:

- an update check (only if you agreed),
- a research paper's arXiv number, to get its real title,
- a photo's GPS coordinates (two numbers), to name the place with Apple Maps.

## Free and open source

neatly is free, with no account, no credits and no subscription. The code is MIT licensed on
[GitHub](https://github.com/alpozaydin/neatly), so anyone can check what it does.

<p><a style="display:inline-block;background:var(--deep);color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700" href="https://github.com/alpozaydin/neatly/releases/latest/download/neatly.dmg">⬇️ Download neatly for Mac</a></p>

Needs a Mac with Apple silicon (M1 or later) and macOS 26 or later. Turn on Apple Intelligence for the best names;
without it, neatly still names many files with its rules and the text it reads.

## Related

- [Rename screenshots automatically on Mac](../rename-screenshots-mac/)
- [Organize the Downloads folder on Mac](../organize-downloads-mac/)
- [neatly vs Finder, Shortcuts and Hazel](../alternatives/)
- [FAQ](../faq/)
