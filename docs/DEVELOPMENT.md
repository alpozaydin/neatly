# Developing neatly

## Build from source

Building from source needs Xcode or the Command Line Tools:

```sh
swift build -c release --product neatly
.build/release/neatly ~/Downloads            # dry run: prints suggestions
.build/release/neatly --apply ~/Downloads    # rename
.build/release/neatly undo transcript-fall26.pdf
swift run checks                            # self-checks
swift run -c release neatly-eval             # accuracy + speed score
```

## Releases

Push a tag (`git tag v0.1.1 && git push --tags`). GitHub builds the binary and publishes it;
then `scripts/update-tap.sh 0.1.1` updates Homebrew.

## Tests

`Tests/eval/cases.json` lists test files and the names we want for them.
`neatly-eval` creates those files (PDFs, scans, photos), runs neatly on them, and prints a score.
All test data is made up — no real personal files.

To add a case: copy one block in `cases.json`, change the text and the wanted names, run `neatly-eval`.

`Tests/e2e/run.sh` tests the whole app end to end: the real watcher, download popup, screenshot pill,
Tidy window and menu bar, with every button pressed by code. It runs headless (nothing appears on screen)
in a temp folder with its own fake home and data, so it never touches your files.
`Tests/e2e/run.sh dl-` runs only the download tests.

`Tests/screens/` scores screenshot names on realistic screens (menu bar, desktop icons, app windows, crops):
`python3 Tests/screens/make.py held /tmp/held && python3 Tests/screens/score.py /tmp/held` (draws the screens
with Google Chrome). `tuned` is the set we tuned on; `held` was written afterwards and never tuned on.

`Tests/eval/holdout.json` is a second set that the rules were **never** tuned on
(`neatly-eval --holdout`). Its score is the honest one. Don't change neatly to fix a held-out case:
move the pattern into `cases.json` and write a fresh held-out case instead.

Requires macOS 26+ (Apple Intelligence enabled for the model step; everything else works without it).
