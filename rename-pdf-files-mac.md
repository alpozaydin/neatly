---
layout: default
title: "How to rename PDF files by their content on Mac"
description: "Turn scan_20261104_8812.pdf into Rent Agreement.pdf. Three ways to name PDFs by what's in them on a Mac: by hand, with Shortcuts, or automatically with neatly (free, on-device)."
permalink: /rename-pdf-files-mac/
---

# How to rename PDF files by their content on Mac

Invoices, scans and papers arrive as `invoice_78123.pdf`, `scan_20261104_8812.pdf` or `2304.02643v1.pdf`. A month
later you can't tell them apart without opening each one. Here are three ways to give PDFs names that say what's
inside.

## Option 1: by hand with Quick Look (built in)

In Finder, select a PDF and press **Space** to preview it. Close the preview, press **Return**, and type a name.

- Free, and you decide every name.
- Slow: one file at a time, and you read each one yourself.

## Option 2: build a Shortcut with Apple Intelligence

On macOS 26 or later you can build a Shortcut that gets the text from a PDF, asks Apple Intelligence for a short
title, and renames the file. Run it from Finder's Quick Actions, or attach it to a folder.

- Free, and you control every step.
- Takes some setup. Scanned PDFs have no text to read, so they need an extra text recognition step.
- You handle the rest yourself: duplicate names, long documents, and Undo.

## Option 3: let neatly name them

[neatly](../) is a free, open-source Mac app that names PDFs by what's in them and suggests the folder they belong
in:

| Before | After |
|---|---|
| `scan_20261104_8812.pdf` | `Rent Agreement.pdf` → *Documents* |
| `invoice_78123.pdf` | `Netflix Invoice Nov 2026.pdf` → *Bills* |
| `doc_8f3a2c.pdf` | `Water Bill Nov 2026.pdf` |
| `2304.02643v1.pdf` | `Segment Anything 2023.pdf` |

- **Reads as little as it needs:** the PDF's title, page 1, and where it was downloaded from. Scans are read with
  text recognition.
- **Simple rules first** for invoices, receipts and tickets, then Apple Intelligence on your Mac for the rest.
- **Research papers** get their real title and year. For an arXiv paper, only its number is sent to arXiv to look
  up the title. You can turn that off.
- **New downloads:** a small popup suggests the name and folder. Ignore it and the new name is kept, in Downloads.
- **A whole folder:** open neatly → **Rename messy files now** → pick a folder, and check every name first.
- **Not only PDFs:** Word, PowerPoint, e-books (EPUB), notebooks and zips too.
- **Safe:** names you chose are never changed, and History can revert any rename.

<p><a style="display:inline-block;background:var(--deep);color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700" href="https://github.com/alpozaydin/neatly/releases/latest/download/neatly.dmg">⬇️ Download neatly for Mac</a></p>

Needs a Mac with Apple silicon and macOS 26 or later. Turn on Apple Intelligence for the best names.

## Which should I use?

- A few files now and then: **option 1**.
- You like building your own automations: **option 2**.
- Every new PDF named for you, plus the right folder: **option 3**.

## Related

- [Organize the Downloads folder on Mac](../organize-downloads-mac/)
- [Rename photos automatically on Mac](../rename-photos-mac/)
- [AI file renamer for Mac: how it works](../ai-file-renamer-mac/)
- [neatly vs Finder, Shortcuts and Hazel](../alternatives/)
- [FAQ](../faq/)
