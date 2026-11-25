---
title: "FAQ — neatly, the AI file renamer for Mac"
description: "Answers about neatly: how to rename screenshots, downloads and photos automatically on a Mac, privacy, requirements, and how it compares to other renamers."
permalink: /faq/
faq:
  - q: "How do I rename screenshots automatically on a Mac?"
    a: "Install neatly. Every new screenshot is named by what's on screen the moment it's saved (for example 'Hubble Space Telescope.png' instead of 'Screenshot 2026-11-16 at 10.13.03.png'). A small pill shows the new name with Undo. Tip: turn off macOS's floating thumbnail (⌘⇧5 → Options) so the file is saved, and named, right away."
  - q: "How do I rename downloaded files automatically on a Mac?"
    a: "neatly watches your Downloads folder. When a file with a meaningless name arrives (doc_8f3a2c.pdf, 2304.02643.pdf, IMG_4821.jpg), a small popup suggests a clear name and the folder it belongs in. Click Rename & Move, edit it, or ignore it: after a few seconds it keeps the new name in Downloads (or keeps the original, if you choose that in settings), so nothing waits on you."
  - q: "Can it rename photos by what's in them and where they were taken?"
    a: "Yes. Photos without a useful name get one from what they show, plus the place from the photo's GPS, for example 'Colosseum in Rome.jpg' or 'Two Cats in Istanbul.jpg'. The place lookup sends only the two GPS numbers to Apple Maps, and you can turn it off."
  - q: "Can I rename a whole folder of messy files at once?"
    a: "Yes. Open Tidy from the menu bar (or right-click files in Finder → Rename with neatly). You see every suggested name first and rename them all with one click. History lets you revert any rename later."
  - q: "Is it private? Does it upload my files?"
    a: "Your files never leave your Mac. neatly reads them with Apple's on-device model (Apple Intelligence), with no account, no tracking and no cloud AI. Only three small things can go online: the update check, an arXiv paper number (to get the paper's real title) and a photo's GPS coordinates (to name the place). All three can be turned off."
  - q: "Is neatly free?"
    a: "Yes. neatly is free and open source under the MIT license. The code is on GitHub."
  - q: "What do I need to run it?"
    a: "A Mac with Apple silicon (M1 or later) and macOS 26 or later. Turn on Apple Intelligence for the best names; without it neatly still names many files with its rules and the text it reads."
  - q: "Will it rename files I named myself?"
    a: "No. neatly only touches junk names like IMG_4821, Screenshot 2026-…, document (3) or scan_8812. Names you chose are never changed, and every rename can be undone."
  - q: "How is neatly different from rule-based or bulk renamers?"
    a: "Rule-based tools and bulk renamers follow rules or patterns you write; neatly reads each file (the text on a screenshot, page 1 of a PDF, what a photo shows) and names it by what it is. You can still add 'Always do this' rules."
  - q: "Can I choose the naming style?"
    a: "Yes: natural names by default ('Water Bill Nov 2026'), or dashes, underscores, lowercase, short or long names, and dates before or after. neatly also learns from the names you edit."
  - q: "How do I install and uninstall it?"
    a: "Download neatly.dmg from https://alpozaydin.github.io/neatly/, open it, drag neatly to Applications and open it (signed and notarized by Apple). Or in Terminal: curl -fsSL https://raw.githubusercontent.com/alpozaydin/neatly/main/scripts/install.sh | sh, or with Homebrew: brew install alpozaydin/tap/neatly && neatly service install. To uninstall, open neatly → More options → Uninstall neatly."
---

# Frequently asked questions

neatly is a free, open-source **AI file renamer for Mac**. It gives your downloads, screenshots and photos clear
names automatically, on device with Apple Intelligence.

{% for q in page.faq %}
<details{% if forloop.first %} open{% endif %}>
<summary>{{ q.q }}</summary>
<p>{{ q.a }}</p>
</details>
{% endfor %}

[← Back to neatly](./) · [Install](./#install) · [Source on GitHub](https://github.com/alpozaydin/neatly)
