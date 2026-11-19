---
layout: default
title: "How to rename screenshots automatically on Mac"
description: "Stop getting files called Screenshot 2026-11-10 at 9.41.07.png. Three ways to give Mac screenshots real names: macOS settings, Shortcuts, or automatically with neatly (free, on-device)."
permalink: /rename-screenshots-mac/
---

# How to rename screenshots automatically on Mac

Every Mac screenshot is saved as `Screenshot <date> at <time>.png`. After a week, your Desktop has dozens of them and
you can't tell which is which. Here are three ways to fix that, from built-in settings to fully automatic names.

## Option 1: change what macOS does (built in, no names)

macOS can't name a screenshot by its content, but you can make screenshots easier to manage:

- **Save them somewhere else.** Press ⌘⇧5 → **Options** → **Save to**, and pick a folder such as `Screenshots`.
- **Change the prefix.** In Terminal:
  ```sh
  defaults write com.apple.screencapture name "Shot"
  killall SystemUIServer
  ```
  Files are then called `Shot 2026-11-10 at 9.41.07.png`. Still a date, not a name.
- **Turn off the floating thumbnail** (⌘⇧5 → Options) so the file is saved at once.

Good for tidiness. It does not tell you what's in each screenshot.

## Option 2: build a Shortcut with Apple Intelligence

On macOS 26 or later you can build a Shortcut that extracts the text from an image, asks Apple Intelligence for a
title, and renames the file. You then attach it to a folder action so it runs on new screenshots.

- Free, and you control every step.
- Takes some setup, and it's slow on busy screenshots.
- You need to handle edge cases yourself: duplicate names, screenshots without text, and Undo.

## Option 3: let neatly name them as you take them

[neatly](../) is a free, open-source menu-bar app that names each screenshot the moment it is saved, by what's on
screen:

| Before | After |
|---|---|
| `Screenshot 2026-11-10 at 9.41.07.png` | `Turkish Airlines Boarding Pass.png` |
| `Screenshot 2026-11-16 at 10.13.03.png` | `Hubble Space Telescope.png` |

- **Automatic:** no hotkey, no Shortcut. Take a screenshot as usual.
- **One click to undo:** a small pill shows the new name with **Undo**.
- **Screen recordings too:** they're named from what's on screen.
- **Private:** it reads the screenshot on your Mac with Apple's on-device model. Nothing is uploaded.
- **Your style:** natural names by default, or `turkish-airlines-boarding-pass` with dashes, dates first or last.
- **Old screenshots:** open **Tidy** from the menu bar to name the ones already on your Desktop. You review every name first.

<p><a style="display:inline-block;background:var(--deep);color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700" href="https://github.com/alpozaydin/neatly/releases/latest/download/neatly.dmg">⬇️ Download neatly for Mac</a></p>

Needs a Mac with Apple silicon and macOS 26 or later. Turn on Apple Intelligence for the best names.

## Which should I use?

- You only want screenshots out of the way: **option 1**.
- You like building your own automations: **option 2**.
- You want real names with no setup, and Undo: **option 3**.

## Related

- [Organize the Downloads folder on Mac](../organize-downloads-mac/)
- [AI file renamer for Mac: how it works](../ai-file-renamer-mac/)
- [neatly vs Finder, Shortcuts and Hazel](../alternatives/)
- [FAQ](../faq/)
