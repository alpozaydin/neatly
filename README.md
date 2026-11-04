# namer

Suggests short, meaningful names for badly named files — `1234567_2026-11-04_124701.pdf` → `transcript-fall26.pdf`.
Runs entirely on your Mac. Changes nothing unless you say so.

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

## Usage

```sh
swift build -c release --product namer
.build/release/namer ~/Downloads            # dry run: prints suggestions
.build/release/namer --apply ~/Downloads    # rename
.build/release/namer undo transcript-fall26.pdf
swift run checks                            # self-checks
swift run -c release namer-eval             # accuracy + speed score
```

## Testing accuracy

`Tests/eval/cases.json` lists test files and the names we want for them.
`namer-eval` creates those files (PDFs, scans, photos), runs namer on them, and prints a score.
All test data is made up — no real personal files.

To add a case: copy one block in `cases.json`, change the text and the wanted names, run `namer-eval`.

Requires macOS 26+ (Apple Intelligence enabled for the model step; everything else works without it).
