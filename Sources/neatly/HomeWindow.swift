import AppKit
import NamerCore

/// The window you get when you open neatly (Spotlight, Applications, or "Open neatly…" in the menu):
/// a drop zone, one-click tidying, and every setting — no Terminal needed. It lives in the running service,
/// so changes apply to the very next file.
@MainActor
final class HomeWindow: NSObject, NSWindowDelegate {
    static let shared = HomeWindow()
    /// Tests use their own name (NEATLY_NOTIFY), so they never open the window of the neatly you actually run.
    static let showNotification = Notification.Name("dev.neatly.show" + (ProcessInfo.processInfo.environment["NEATLY_NOTIFY"] ?? ""))

    var window: NSWindow?
    let example = NSTextField(labelWithString: "")
    let status = NSTextField(labelWithString: "")
    let pauseButton = NSButton(checkboxWithTitle: "Pause neatly", target: nil, action: nil)
    let length = NSSegmentedControl(labels: ["Short", "Standard", "Detailed"], trackingMode: .selectOne, target: nil, action: nil)
    let caseMenu = NSPopUpButton()
    let sepMenu = NSPopUpButton()
    let dateMenu = NSPopUpButton()
    let appName = NSButton(checkboxWithTitle: "Add the app's name to screenshots (… in Safari)", target: nil, action: nil)
    let copyShots = NSButton(checkboxWithTitle: "Copy new screenshots to the clipboard", target: nil, action: nil)
    let countdown = NSPopUpButton()

    func show() {
        if window == nil { build() }
        refresh()
        print("home: shown")
        guard let window else { return }
        if headless { uiTest(); return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        uiTest()
    }

    // MARK: Layout

    func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "neatly"
        w.isReleasedWhenClosed = false
        w.delegate = self

        // Header: icon, name, what it's doing.
        let icon = NSImageView(image: NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
                                               ?? AppBundle.location.appending(path: "Contents/Resources/AppIcon.icns"))
                               ?? NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: nil)!)
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let title = NSTextField(labelWithString: "neatly")
        title.font = .boldSystemFont(ofSize: 22)
        status.textColor = .secondaryLabelColor
        let headText = NSStackView(views: [title, status])
        headText.orientation = .vertical
        headText.alignment = .leading
        headText.spacing = 2
        let head = NSStackView(views: [icon, headText])
        head.spacing = 14

        // Drop zone.
        let drop = DropZone { urls in MenuBar.shared.dropped(urls) }

        // One click.
        let tidyDesktop = NSButton(title: "Tidy Desktop", target: self, action: #selector(tidyDesktop))
        let tidyDownloads = NSButton(title: "Tidy Downloads", target: self, action: #selector(tidyDownloads))
        let tidyFolder = NSButton(title: "Choose a Folder…", target: self, action: #selector(tidyFolder))
        let undo = NSButton(title: "Undo Last Tidy", target: self, action: #selector(undoLast))
        let actions = NSStackView(views: [tidyDesktop, tidyDownloads, tidyFolder, undo])
        actions.spacing = 8

        // Settings.
        length.target = self; length.action = #selector(changed)
        caseMenu.addItems(withTitles: ["lowercase", "Title Case"])
        sepMenu.addItems(withTitles: ["dashes  a-b", "underscores  a_b", "spaces  a b"])
        dateMenu.addItems(withTitles: ["no date", "date first", "date last"])
        countdown.addItems(withTitles: ["3 seconds", "5 seconds", "10 seconds", "30 seconds", "wait for me"])
        for c in [caseMenu, sepMenu, dateMenu, countdown] { c.target = self; c.action = #selector(changed) }
        for b in [appName, copyShots, pauseButton] { b.target = self; b.action = #selector(changed) }

        let grid = NSGridView(views: [
            [label("Name length"), length],
            [label("Style"), NSStackView(views: [caseMenu, sepMenu])],
            [label("Date"), dateMenu],
            [label("Download popup saves after"), countdown],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        example.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        example.textColor = .controlAccentColor

        // Footer: where it lives, and how to stop it.
        let hint = NSTextField(wrappingLabelWithString:
            "neatly runs in your menu bar (the ✦ icon at the top right). New downloads get a small popup with a name and "
            + "folder; new screenshots are named on their own, with Undo. Drop files on the menu-bar icon too.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        hint.preferredMaxLayoutWidth = 512
        let quit = NSButton(title: "Quit neatly", target: MenuBar.shared, action: #selector(MenuBar.quit))
        let log = NSButton(title: "Open Log", target: MenuBar.shared, action: #selector(MenuBar.openLog))
        let footerButtons = NSStackView(views: [pauseButton, NSView(), log, quit])

        let stack = NSStackView(views: [head, drop, actions, separator(), section("Naming"), grid, example,
                                        appName, copyShots, separator(), hint, footerButtons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
        for v in [drop, hint, footerButtons] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        drop.heightAnchor.constraint(equalToConstant: 130).isActive = true
        stack.widthAnchor.constraint(equalToConstant: 560).isActive = true
        stack.setCustomSpacing(6, after: grid)
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        window = w
    }

    func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = .secondaryLabelColor
        return l
    }
    func section(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 13)
        return l
    }
    func separator() -> NSView {
        let b = NSBox(); b.boxType = .separator
        b.widthAnchor.constraint(equalToConstant: 512).isActive = true
        return b
    }

    // MARK: Settings ⇄ controls

    let countdownValues = [3, 5, 10, 30, 0]

    func refresh() {
        let p = namer.profile
        length.selectedSegment = StyleProfile.Length.allCases.firstIndex(of: p.len) ?? 0
        caseMenu.selectItem(at: p.lowercase ? 0 : 1)
        sepMenu.selectItem(at: ["-": 0, "_": 1, " ": 2][p.separator] ?? 0)
        dateMenu.selectItem(at: p.date == .prefix ? 1 : p.date == .suffix ? 2 : 0)
        countdown.selectItem(at: countdownValues.firstIndex(of: timeout) ?? 1)
        appName.state = p.appName == true ? .on : .off
        copyShots.state = p.copyScreenshots == true ? .on : .off
        pauseButton.state = paused ? .on : .off
        let sample = p.len == .short ? "hot-honey-cornbread" : p.len == .standard ? "hot-honey-cornbread-recipe"
                                                                               : "hot-honey-cornbread-recipe-10-inch-skillet"
        example.stringValue = "Example:  " + p.render(sample, date: Date(), app: "Safari")
        let all = Correction.all().filter { $0.auto != true }
        let kept = all.filter { !$0.chosen.isEmpty && $0.chosen == $0.suggested }.count
        status.stringValue = (paused ? "Paused" : "Running")
            + (all.isEmpty ? " — waiting for your first download or screenshot"
                           : " — you kept \(Int((Double(kept) / Double(all.count) * 100).rounded()))% of \(all.count) suggestions as they were")
    }

    @objc func changed() {
        MenuBar.shared.change { p in
            p.length = StyleProfile.Length.allCases[max(0, length.selectedSegment)]
            p.lowercase = caseMenu.indexOfSelectedItem == 0
            p.separator = ["-", "_", " "][max(0, sepMenu.indexOfSelectedItem)]
            p.date = [nil, .prefix, .suffix][max(0, dateMenu.indexOfSelectedItem)]
            p.appName = appName.state == .on
            p.copyScreenshots = copyShots.state == .on
            p.countdown = countdownValues[max(0, countdown.indexOfSelectedItem)]
        }
        timeout = namer.profile.countdown ?? timeout
        if (pauseButton.state == .on) != paused { MenuBar.shared.togglePause() }
        refresh()
    }

    // MARK: Actions

    @objc func tidyDesktop() { MenuBar.shared.tidyDesktop() }
    @objc func tidyDownloads() { MenuBar.shared.tidy([FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads").path]) }
    @objc func tidyFolder() { MenuBar.shared.tidyFolder() }
    @objc func undoLast() { MenuBar.shared.undoLastTidy(); refresh() }

    /// NEATLY_UI_TEST="home:length=standard,home:date=prefix,home:case=title,home:countdown=10,home:drop=<path>,home:snapshot=<png>"
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for step in t.split(separator: ",").map(String.init) where step.hasPrefix("home:") {
                let kv = step.dropFirst(5).split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "length": self.length.selectedSegment = ["short", "standard", "detailed"].firstIndex(of: kv[1]) ?? 0; self.changed()
                case "date": self.dateMenu.selectItem(at: ["none", "prefix", "suffix"].firstIndex(of: kv[1]) ?? 0); self.changed()
                case "case": self.caseMenu.selectItem(at: kv[1] == "title" ? 1 : 0); self.changed()
                case "countdown": self.countdown.selectItem(at: self.countdownValues.firstIndex(of: Int(kv[1]) ?? 5) ?? 1); self.changed()
                case "drop": MenuBar.shared.dropped(kv[1].split(separator: "|").map { URL(fileURLWithPath: String($0)) })
                case "snapshot": self.snapshot(to: kv[1])
                default: break
                }
            }
        }
    }

    /// Draw the window into a PNG without putting it on screen (tests check the layout this way).
    func snapshot(to path: String) {
        guard let view = window?.contentView else { return }
        view.appearance = NSAppearance(named: .aqua)          // light mode, so text shows up on the white below
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        view.appearance = nil
        let img = NSImage(size: view.bounds.size)
        img.lockFocus()
        NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB)?.setFill()
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        rep.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) else { return }
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("home: snapshot \(path)")
    }
}

/// "Drop files or folders here": a dashed box that takes files from Finder.
final class DropZone: NSView {
    let onDrop: ([URL]) -> Void
    var hovering = false { didSet { needsDisplay = true } }

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        let icon = NSImageView(image: NSImage(systemSymbolName: "square.and.arrow.down.on.square", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: "Drop files or folders here")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let sub = NSTextField(labelWithString: "neatly suggests a name for each one. Nothing changes until you click Rename.")
        sub.textColor = .secondaryLabelColor
        sub.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [icon, title, sub])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.quaternaryLabelColor.withAlphaComponent(0.08)).setFill()
        path.fill()
        path.lineWidth = 2
        path.setLineDash([7, 5], count: 2, phase: 0)
        (hovering ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { hovering = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop(urls)
        return !urls.isEmpty
    }
}
