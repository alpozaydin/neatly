import AppKit

/// The popup, as a small native window with a countdown: if nobody answers, the suggestion is saved.
/// Agents and scripts that download files never get stuck waiting for a click.
/// Typing in the name field or moving the mouse over the window stops the countdown.
///
/// Runs as its own process (`neatly dialog …`) so the watcher keeps its simple loop.
/// Prints one line: "save\t<name>\t<folder path, empty = Downloads>\t<auto|user>", "keep", or "none".
@MainActor
final class CountdownDialog: NSObject, NSTextFieldDelegate {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let field = NSTextField()
    let folderLabel = NSTextField(labelWithString: "")
    let status = NSTextField(labelWithString: "")
    var saveButton: NSButton!
    var folder: URL?
    var remaining: Int
    var timer: Timer?

    init(file: String, name: String, folder: URL?, seconds: Int) {
        self.folder = folder
        self.remaining = seconds
        super.init()

        let title = NSTextField(labelWithString: file)
        title.font = .boldSystemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingMiddle
        showFolder()
        field.stringValue = name
        field.delegate = self
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)

        let leave = NSButton(title: "Leave as is", target: self, action: #selector(leaveAsIs))
        leave.keyEquivalent = "\u{1b}"
        let place = NSButton(title: "Select place…", target: self, action: #selector(selectPlace))
        saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [status, NSView(), leave, place, saveButton])
        buttons.setHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [title, folderLabel, NSTextField(labelWithString: "Suggested name:"), field, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 14, right: 18)
        for v in [field, buttons] { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true }
        stack.setCustomSpacing(14, after: folderLabel)
        stack.setCustomSpacing(14, after: field)

        panel.title = "neatly"
        panel.contentView = stack
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.setContentSize(stack.fittingSize)
        stack.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                             owner: self, userInfo: nil))
        NotificationCenter.default.addObserver(self, selector: #selector(closed), name: NSWindow.willCloseNotification, object: panel)
    }

    func showFolder() {
        folderLabel.stringValue = "Suggested folder:  " + shortFolder(folder)
    }

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if remaining > 0 {
            tick()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { self.remaining -= 1; self.tick() }
            }
        }
        NSApp.run()
        exit(0)
    }

    func tick() {
        if remaining <= 0 { saveNow(auto: true); return }
        saveButton.title = "Save (\(remaining))"
        status.stringValue = "Saves automatically"
    }

    /// The person is here: let them take their time.
    func pause() {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil
        saveButton.title = "Save"
        status.stringValue = ""
    }

    @objc func mouseEntered(_ event: NSEvent) { pause() }
    func controlTextDidChange(_ obj: Notification) { pause() }

    func finish(_ line: String) -> Never {
        print(line)
        fflush(stdout)
        exit(0)
    }

    @objc func save() { saveNow(auto: false) }

    /// auto = the countdown ran out: nobody looked, so this mustn't be read as "the person agreed".
    func saveNow(auto: Bool) -> Never {
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { finish("none") }
        finish("save\t\(name)\t\(folder?.path ?? "")\t\(auto ? "auto" : "user")")
    }

    @objc func leaveAsIs() { finish("keep") }
    @objc func closed() { finish("none") }

    @objc func selectPlace() {
        pause()
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.prompt = "Save here"
        open.message = "Save “\(field.stringValue)” in:"
        open.directoryURL = folder ?? FileManager.default.homeDirectoryForCurrentUser
        open.level = .floating
        guard open.runModal() == .OK, let url = open.url else { return }
        folder = url
        save()
    }
}

/// "courses-fall26 › ceng491", or "Downloads" for none.
func shortFolder(_ url: URL?) -> String {
    guard let url else { return "Downloads" }
    return url.pathComponents.suffix(2).joined(separator: " › ")
}

/// neatly dialog <seconds> <file> <name> [folder path]
@MainActor func runDialog(_ a: [String]) -> Never {
    guard a.count >= 3, let seconds = Int(a[0]) else { print("none"); exit(1) }
    let folder = a.count > 3 && !a[3].isEmpty ? URL(fileURLWithPath: a[3]) : nil
    CountdownDialog(file: a[1], name: a[2], folder: folder, seconds: seconds).run()
}

/// The screenshot pill: a small panel under the menu bar — thumbnail, the new name, ↻ and Undo.
/// It never steals focus: you keep typing while it shows. Click the name to change it (Return saves),
/// ↻ asks for a different name, Undo puts the original back. Hovering keeps it open.
/// Prints "ok", "undo", "redo" or "rename\t<name>".
@MainActor
final class Toast: NSObject, NSTextFieldDelegate {
    /// Borderless panels can't take keyboard input by default; this one can, so the name is editable.
    final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

    let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    let field = NSTextField()
    let original: String
    var remaining: Int
    var timer: Timer?

    init(name: String, file: URL, seconds: Int) {
        original = name
        remaining = seconds
        super.init()
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 16
        fx.layer?.masksToBounds = true

        let thumb = NSImageView()
        thumb.image = NSImage(contentsOf: file)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.widthAnchor.constraint(equalToConstant: 52).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let spark = NSTextField(labelWithString: "✦")
        field.stringValue = name
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingMiddle
        field.delegate = self
        field.target = self
        field.action = #selector(commit)
        field.toolTip = "Click to change the name, Return to save"
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let redo = NSButton(title: "↻", target: self, action: #selector(another))
        redo.bezelStyle = .rounded
        redo.toolTip = "Another name"
        let undo = NSButton(title: "Undo", target: self, action: #selector(undoRename))
        undo.bezelStyle = .rounded
        undo.bezelColor = .controlAccentColor

        let row = NSStackView(views: [thumb, spark, field, redo, undo])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
                                     row.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                                     row.topAnchor.constraint(equalTo: fx.topAnchor),
                                     row.bottomAnchor.constraint(equalTo: fx.bottomAnchor)])
        panel.contentView = fx
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let size = NSSize(width: min(480, max(340, row.fittingSize.width)), height: 56)
        panel.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {   // top-right, just under the menu bar
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 10))
        }
        fx.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self, userInfo: nil))
    }

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(nil)   // nothing selected, no keyboard focus until you click the name
        startTimer()
        uiTest()
        NSApp.run()
        exit(0)
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.remaining -= 1; if self.remaining <= 0 { self.commit() } }
        }
    }

    var editing = false
    @objc func mouseEntered(_ event: NSEvent) { timer?.invalidate(); timer = nil }
    @objc func mouseExited(_ event: NSEvent) { if !editing { remaining = max(remaining, 2); startTimer() } }
    func controlTextDidBeginEditing(_ obj: Notification) { editing = true; timer?.invalidate(); timer = nil }

    /// Return in the field, or time is up: keep the name as it is now.
    @objc func commit() {
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(typed.isEmpty || typed == original ? "ok" : "rename\t" + typed)
    }
    @objc func another() { finish("redo") }
    @objc func undoRename() { finish("undo") }

    func finish(_ line: String) -> Never {
        print(line); fflush(stdout); exit(0)
    }

    /// NEATLY_UI_TEST="edit:new name" | "redo" | "undo": press the buttons by code, to test the whole path.
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if t.hasPrefix("edit:") { self.field.stringValue = String(t.dropFirst(5)); self.commit() }
            if t == "redo" { self.another() }
            if t == "undo" { self.undoRename() }
        }
    }
}

/// neatly toast <seconds> <new name> <file path>
@MainActor func runToast(_ a: [String]) -> Never {
    guard a.count >= 3, let seconds = Int(a[0]) else { print("ok"); exit(1) }
    Toast(name: a[1], file: URL(fileURLWithPath: a[2]), seconds: max(seconds, 3)).run()
}
