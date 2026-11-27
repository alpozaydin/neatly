---
layout: default
title: "How to rename photos automatically on Mac"
description: "Turn IMG_4108.HEIC into Colosseum in Rome.heic. Three ways to give photo files real names on a Mac: Finder, the Photos app, or automatically by what's in them with neatly (free, on-device)."
permalink: /rename-photos-mac/
---

# How to rename photos automatically on Mac

Photos from a phone or camera arrive as `IMG_4108.HEIC`, `DSC_0042.JPG` or `PXL_20261103_181502.jpg`. The names
say nothing about the picture, so finding one later means opening them one by one. Here are three ways to fix
that, from built-in tools to names based on what each photo shows.

## Option 1: Finder's batch rename (built in, numbers only)

Select the photos in Finder, right-click → **Rename…**, choose **Format**, and type a name such as `Rome`. Finder
names them `Rome 1.heic`, `Rome 2.heic`, and so on.

- Fast for a set of photos from one trip or event.
- Every photo gets the same name plus a number. It doesn't look at what's in the picture.

## Option 2: export from the Photos app with titles

If your photos are in the Photos app, give a photo a title (⌘I, then type it), then **File → Export** and set
**File Name** to **Use Title**.

- Good when you already keep titles in Photos.
- You type every title yourself, and it only covers photos in your Photos library.

## Option 3: let neatly name them by what's in them

[neatly](../) is a free, open-source Mac app that names photo files by what they show and, for phone photos,
where they were taken:

| Before | After |
|---|---|
| `IMG_4108.HEIC` | `Colosseum in Rome.heic` |
| `IMG_4120.JPG` | `Galata Tower in Istanbul.jpg` |
| `IMG_5531.jpeg` | `Red Tulip in Bloom.jpeg` |

- **New photos:** photos you download or AirDrop land in Downloads, and a small popup suggests a name.
- **A whole folder:** open neatly → **Rename messy files now** → pick a folder. For big folders, choose
  **Last 7 days**, **Last 30 days**, **Last year** or **All**. You see every name before anything changes.
- **Drop to rename:** drop photos or a folder on the neatly window or its menu-bar icon.
- **Private:** the picture is read on your Mac with Apple's on-device model. To name the place, only the photo's
  GPS coordinates are sent to Apple's map service, never the photo. You can turn that off.
- **Your style:** natural names by default, or `colosseum-in-rome` with dashes, with or without the date.
- **Undo:** History lists every rename, each with **Revert**.

neatly renames photo files on disk. It doesn't change photos inside the Photos library; export them first.

<p><a style="display:inline-block;background:var(--deep);color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700" href="https://github.com/alpozaydin/neatly/releases/latest/download/neatly.dmg">⬇️ Download neatly for Mac</a></p>

Needs a Mac with Apple silicon and macOS 26 or later. Turn on Apple Intelligence for the best names.

## Which should I use?

- One trip, and numbers are enough: **option 1**.
- Your photos live in the Photos app and you like writing titles: **option 2**.
- You want each file named by what's in it, with no typing: **option 3**.

## Related

- [Rename PDF files by their content on Mac](../rename-pdf-files-mac/)
- [Rename screenshots automatically on Mac](../rename-screenshots-mac/)
- [Organize the Downloads folder on Mac](../organize-downloads-mac/)
- [AI file renamer for Mac: how it works](../ai-file-renamer-mac/)
- [FAQ](../faq/)
