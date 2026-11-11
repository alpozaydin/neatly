import AppKit
import QuickLookThumbnailing
import NamerCore

/// `neatly tidy [folder]`: name a whole folder at once (Desktop by default) in a review window.
/// Names appear as they are found; edit any of them, untick what you want to keep, then Rename.
/// Nothing changes until you click Rename, and Undo All puts every name back.
@MainActor
final class TidyWindow: NSObject, NSWindowDelegate {
    @MainActor struct Item {
        let url: URL
        var suggestion: String?
        let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        let field = NSTextField()
        let status = NSTextField(labelWithString: "naming…")
        var renamed: URL?
    }

    let folder: URL
    let namer: Namer
    var items: [Item] = []
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let header = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    let renameButton = NSButton(title: "Rename", target: nil, action: nil)
    let undoButton = NSButton(title: "Undo All", target: nil, action: nil)
    let doneButton = NSButton(title: "Done", target: nil, action: nil)
    let closeButton = NSButton(title: "Close", target: nil, action: nil)

    /// `paths`: one folder (tidy what's inside) or several files (dropped on the menu-bar icon).
    init(paths: [URL], namer: Namer) {
        var isDir: ObjCBool = false
        let oneFolder = paths.count == 1 && FileManager.default.fileExists(atPath: paths[0].path, isDirectory: &isDir) && isDir.boolValue
        self.folder = oneFolder ? paths[0] : paths[0].deletingLastPathComponent()
        self.namer = namer
        super.init()
        let candidates = oneFolder
            ? ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles])) ?? [])
            : paths
        let files = candidates
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            // A folder: only meaningless names (yours are left alone). Files you dropped: you asked for them.
            .filter { Decision.make(for: $0, explicit: !oneFolder).shouldRename }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        items = files.map { Item(url: $0) }
        build()
    }

    func build() {
        window.title = "neatly — \(folder.lastPathComponent)"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: folder.lastPathComponent)
        title.font = .boldSystemFont(ofSize: 18)
        header.textColor = .secondaryLabelColor
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = Double(max(items.count, 1))
        let top = NSStackView(views: [title, header, progress])
        top.orientation = .vertical
        top.alignment = .leading

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        for i in items.indices {
            let item = items[i]
            item.check.state = .on
            item.check.target = self
            item.check.action = #selector(updateButton)
            item.field.placeholderString = "naming…"
            item.field.isEnabled = false
            item.field.widthAnchor.constraint(equalToConstant: 330).isActive = true
            item.status.textColor = .secondaryLabelColor
            item.status.font = .systemFont(ofSize: 11)
            let was = NSTextField(labelWithString: "was " + item.url.lastPathComponent)
            was.textColor = .tertiaryLabelColor
            was.font = .systemFont(ofSize: 11)
            was.lineBreakMode = .byTruncatingMiddle
            was.widthAnchor.constraint(lessThanOrEqualToConstant: 330).isActive = true
            let texts = NSStackView(views: [item.field, was])
            texts.orientation = .vertical
            texts.alignment = .leading
            texts.spacing = 2
            let thumb = NSImageView()
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.widthAnchor.constraint(equalToConstant: 72).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 48).isActive = true
            loadThumbnail(item.url, into: thumb)
            let row = NSStackView(views: [item.check, thumb, texts, item.status])
            row.spacing = 10
            list.addArrangedSubview(row)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let clip = FlippedView()
        clip.addSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        clip.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = clip
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 4),
            list.topAnchor.constraint(equalTo: clip.topAnchor, constant: 4),
            clip.bottomAnchor.constraint(equalTo: list.bottomAnchor, constant: 4),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        let hint = NSTextField(labelWithString: "Click a name to change it. Nothing is renamed until you click Rename.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        renameButton.target = self; renameButton.action = #selector(renameAll); renameButton.keyEquivalent = "\r"
        renameButton.isEnabled = false
        undoButton.target = self; undoButton.action = #selector(undoAll); undoButton.isHidden = true
        doneButton.target = self; doneButton.action = #selector(done)
        closeButton.target = self; closeButton.action = #selector(done)
        let close = closeButton
        doneButton.isHidden = true
        let bottom = NSStackView(views: [hint, NSView(), undoButton, close, renameButton, doneButton])

        let root = NSStackView(views: [top, scroll, bottom])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 14, right: 18)
        for v in [top, scroll, bottom, progress] as [NSView] {
            v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        window.contentView = root
        header.stringValue = items.isEmpty ? "Nothing to rename: every file here already has a real name."
                                           : "Naming 0 of \(items.count)…"
    }

    func loadThumbnail(_ url: URL, into view: NSImageView) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 144, height: 96), scale: 2,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { view.image = img }
        }
    }

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await nameAll() }
        NSApp.run()
        exit(0)
    }

    /// One at a time: the on-device model is one shared resource; parallel calls only queue up behind each other.
    func nameAll() async {
        let start = Date()
        for i in items.indices {
            let outcome = await namer.suggest(for: items[i].url)
            if case .suggested(let s) = outcome {
                items[i].suggestion = s.name
                items[i].field.stringValue = s.name
                items[i].field.isEnabled = true
                items[i].status.stringValue = ""
            } else {
                items[i].check.state = .off
                items[i].check.isEnabled = false
                items[i].field.placeholderString = "no better name"
                items[i].status.stringValue = ""
            }
            progress.doubleValue = Double(i + 1)
            let left = Date().timeIntervalSince(start) / Double(i + 1) * Double(items.count - i - 1)
            header.stringValue = "Naming \(i + 1) of \(items.count)" + (i + 1 < items.count ? " · about \(Int(left.rounded(.up)))s left" : "")
            updateButton()
        }
        header.stringValue = "Named \(items.filter { $0.suggestion != nil }.count) of \(items.count). Check the names, then Rename."
        uiTest()
    }

    /// NEATLY_UI_TEST="edit0:name,untick1,rename,undoall,done": press the buttons by code, to test the whole path.
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        var delay = 1.0
        for step in t.split(separator: ",").map(String.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if step.hasPrefix("edit"), let colon = step.firstIndex(of: ":"), let i = Int(step.dropFirst(4).prefix(while: \.isNumber)),
                   self.items.indices.contains(i) { self.items[i].field.stringValue = String(step[step.index(after: colon)...]) }
                if step.hasPrefix("untick"), let i = Int(step.dropFirst(6)), self.items.indices.contains(i) {
                    self.items[i].check.state = .off; self.updateButton()
                }
                if step == "rename" { self.renameAll() }
                if step == "undoall" { self.undoAll() }
                if step == "done" { self.done() }
            }
            delay += 1.5
        }
    }

    var chosen: [Int] {
        items.indices.filter { items[$0].check.state == .on && items[$0].renamed == nil
            && !items[$0].field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty && items[$0].field.isEnabled }
    }

    @objc func updateButton() {
        let n = chosen.count
        renameButton.title = n == 1 ? "Rename 1 File" : "Rename \(n) Files"
        renameButton.isEnabled = n > 0
    }

    @objc func renameAll() {
        var done = 0
        for i in chosen {
            let typed = items[i].field.stringValue.trimmingCharacters(in: .whitespaces)
            guard let new = try? Rename.apply(items[i].url, to: typed) else { continue }
            items[i].renamed = new
            items[i].status.stringValue = "✓"
            items[i].field.isEnabled = false
            items[i].check.isEnabled = false
            done += 1
            // Your edits teach future names, like edits in the download popup.
            Correction(original: items[i].url.lastPathComponent, suggested: items[i].suggestion ?? "", chosen: typed,
                       via: "tidy", source: nil, title: nil).save()
        }
        if done > 0 { Tidy.saveLast(items.compactMap(\.renamed)) }   // an empty run must not forget the last real one
        header.stringValue = "Renamed \(done) file\(done == 1 ? "" : "s")."
        renameButton.isHidden = true
        closeButton.isHidden = true
        undoButton.isHidden = false
        doneButton.isHidden = false
    }

    @objc func undoAll() {
        var n = 0
        for i in items.indices {
            guard let r = items[i].renamed, (try? Rename.undo(r)) != nil else { continue }
            items[i].renamed = nil
            items[i].status.stringValue = "undone"
            n += 1
        }
        Tidy.saveLast([])
        header.stringValue = "Put back \(n) original name\(n == 1 ? "" : "s")."
        undoButton.isHidden = true
    }

    @objc func done() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

/// Scroll content that starts at the top.
final class FlippedView: NSView { override var isFlipped: Bool { true } }

enum Tidy {
    static var lastURL: URL { Correction.fileURL.deletingLastPathComponent().appending(path: "last-tidy.json") }

    /// Remember the last batch so `neatly undo --last` works after the window is closed.
    static func saveLast(_ urls: [URL]) {
        try? JSONEncoder().encode(urls.map(\.path)).write(to: lastURL)
    }

    static func undoLast() -> Int {
        guard let data = try? Data(contentsOf: lastURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return 0 }
        let n = paths.filter { (try? Rename.undo(URL(fileURLWithPath: $0))) != nil }.count
        saveLast([])
        return n
    }
}
