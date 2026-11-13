import AppKit
import SwiftUI
import QuickLookThumbnailing

/// The download popup: a picture of the file, the suggested name (editable), where it goes, and Save.
/// If nobody answers, the new name is kept but the file stays in Downloads (unless one of your rules says
/// where it goes), so agents and scripts never wait on a click and nothing disappears into a folder unseen.
/// It never takes the keyboard: whatever you're typing elsewhere stays there until you click the popup.
/// Hovering or typing stops the countdown.
///
/// Answers with one line: "save\t<name>\t<folder path, empty = Downloads>\t<auto|user>", "keep", "trash" or "none".
@MainActor
final class DialogModel: ObservableObject {
    @Published var name: String
    @Published var folder: URL?
    @Published var remaining: Int
    @Published var counting: Bool
    @Published var thumbnail: NSImage?
    var forPicture = false   // test pictures: text fields can't be drawn off screen
    let file: String
    let duplicate: URL?      // the same file you already have
    let pinned: Bool         // the folder comes from one of your rules: it's used even when nobody answers
    init(file: String, name: String, folder: URL?, seconds: Int, duplicate: URL?, pinned: Bool) {
        self.file = file; self.name = name; self.folder = folder; self.remaining = seconds
        self.counting = seconds > 0; self.duplicate = duplicate; self.pinned = pinned
    }
}

@MainActor
final class CountdownDialog: NSObject {
    /// Can take typing once you click it, without bringing neatly (or anything) to the front before that.
    final class Panel: NSPanel { override var canBecomeKey: Bool { true } }

    let model: DialogModel
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 10),
                      styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    var timer: Timer?

    init(file: String, name: String, folder: URL?, seconds: Int, path: URL? = nil, duplicate: URL? = nil, pinned: Bool = false) {
        model = DialogModel(file: file, name: name, folder: folder, seconds: seconds, duplicate: duplicate, pinned: pinned)
        super.init()
        let view = DialogView(model: model, save: { [weak self] in self?.saveNow(auto: false) },
                              keep: { [weak self] in self?.finish("keep") },
                              trash: { [weak self] in self?.finish("trash") },
                              choose: { [weak self] in self?.chooseFolder() },
                              pause: { [weak self] in self?.pause() })
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let size = host.fittingSize
        panel.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {   // top-right, like a notification: out of the way of your work
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 10))
        }
        if let path { loadThumbnail(path) }
        NotificationCenter.default.addObserver(self, selector: #selector(closed), name: NSWindow.willCloseNotification, object: panel)
    }

    func loadThumbnail(_ url: URL) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.thumbnail = img } }
        }
    }

    /// Inside neatly: the answer goes here (no extra process). On its own (`neatly dialog`): print it and exit.
    var onFinish: (String) -> Void = { print($0); fflush(stdout); exit(0) }
    private var finished = false

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        present()
        NSApp.run()
        exit(0)
    }

    /// Show it and start the countdown. No activating, no key window: the app you're in keeps the keyboard.
    func present() {
        if !headless { panel.orderFrontRegardless() }
        if model.counting {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    self.model.remaining -= 1
                    if self.model.remaining <= 0 { self.saveNow(auto: true) }
                }
            }
        }
        uiTest()
    }

    /// NEATLY_UI_TEST="dialog:save" | "dialog:edit:<name>" | "dialog:place:<folder>" | "dialog:keep" | "dialog:trash"
    /// | "dialog:wait" (let the countdown run) | "dialog:snapshot=<png>" (draw it, then let the countdown run).
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"], t.hasPrefix("dialog:") else { return }
        let step = String(t.dropFirst(7))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if step == "save" { self.saveNow(auto: false) }
            if step == "keep" { self.finish("keep") }
            if step == "trash" { self.finish(self.model.duplicate != nil ? "trash" : "keep") }
            if step.hasPrefix("edit:") { self.model.name = String(step.dropFirst(5)); self.pause(); self.saveNow(auto: false) }
            if step.hasPrefix("place:") { self.model.folder = URL(fileURLWithPath: String(step.dropFirst(6))); self.saveNow(auto: false) }
            if step.hasPrefix("snapshot=") { self.snapshot(String(step.dropFirst(9))) }
        }
    }

    func snapshot(_ path: String) {
        model.forPicture = true
        defer { model.forPicture = false }
        for (scheme, suffix) in [(ColorScheme.light, ""), (.dark, "-dark")] {
            let r = ImageRenderer(content: DialogView(model: model, save: {}, keep: {}, trash: {}, choose: {}, pause: {})
                .environment(\.colorScheme, scheme).background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.98)))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { continue }
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: suffix.isEmpty ? path : path.replacingOccurrences(of: ".png", with: "\(suffix).png")))
        }
        print("dialog: snapshot \(path)")
    }

    /// The person is here: let them take their time.
    func pause() {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil
        model.counting = false
    }

    func finish(_ line: String) {
        guard !finished else { return }
        finished = true
        timer?.invalidate(); timer = nil
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
        onFinish(line)
    }

    /// auto = the countdown ran out: nobody looked, so this mustn't be read as "the person agreed".
    func saveNow(auto: Bool) {
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { finish("none"); return }
        finish("save\t\(name)\t\(model.folder?.path ?? "")\t\(auto ? "auto" : "user")")
    }

    @objc func closed() { finish("none") }

    func chooseFolder() {
        pause()
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.prompt = "Save Here"
        open.message = "Save “\(model.name)” in:"
        open.directoryURL = model.folder ?? FileManager.default.homeDirectoryForCurrentUser
        open.level = .floating
        NSApp.activate()   // you clicked "Choose Folder…": now it's fine to come forward
        // Not modal: everything else in neatly (other downloads, screenshots, the menu) keeps running meanwhile.
        open.begin { [weak self] r in
            guard r == .OK, let url = open.url else { return }
            MainActor.assumeIsolated { self?.model.folder = url }
        }
    }
}

struct DialogView: View {
    @ObservedObject var model: DialogModel
    let save: () -> Void, keep: () -> Void, trash: () -> Void, choose: () -> Void, pause: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Group {
                    if let t = model.thumbnail { Image(nsImage: t).resizable().aspectRatio(contentMode: .fit) }
                    else { Image(systemName: "doc.fill").font(.system(size: 26)).foregroundStyle(brandGradient) }
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New download").font(.caption.weight(.semibold)).foregroundStyle(brand)
                    Text(model.file).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                Group {
                    if model.forPicture { Text(model.name).frame(maxWidth: .infinity, alignment: .leading) }
                    else { TextField("Type a name", text: $model.name).textFieldStyle(.plain) }
                }.font(.system(.title3, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .onChange(of: model.name) { _, _ in pause() }
                    .accessibilityLabel("New name")
            }
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(brand).accessibilityHidden(true)
                Text(model.folder.map { shortFolder($0) } ?? "Downloads").lineLimit(1).truncationMode(.head)
                    .accessibilityLabel("Goes to \(model.folder.map { shortFolder($0) } ?? "Downloads")")
                if model.pinned { Text("your rule").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Choose Folder…", action: choose).buttonStyle(.plain).foregroundStyle(brand).font(.callout.weight(.medium))
            }
            if let twin = model.duplicate {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You already have this file").font(.callout.weight(.semibold))
                        Text("\(shortFolder(twin.deletingLastPathComponent())) › \(twin.lastPathComponent)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Move to Trash", action: trash).buttonStyle(.plain).foregroundStyle(.orange).font(.callout.weight(.semibold))
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            HStack(spacing: 10) {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Pill(title: "Leave as Is", primary: false, action: keep).keyboardShortcut(.cancelAction)
                Pill(title: "Save", primary: true, action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 16)
        .frame(width: 440)
        .onHover { if $0 { pause() } }
    }

    var status: String {
        guard model.counting else { return "" }
        let s = "\(max(model.remaining, 0)) s"
        if model.pinned { return "Saves in \(s), by your rule." }
        return model.duplicate != nil ? "Away? In \(s) both are kept." : "Away? In \(s) it's renamed and stays in Downloads."
    }
}

/// NEATLY_HEADLESS=1 (tests): windows are built and their buttons pressed by code, but nothing is ever shown
/// on screen and nothing takes focus.
let headless = ProcessInfo.processInfo.environment["NEATLY_HEADLESS"] != nil

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

    init(name: String, file: URL, seconds: Int, redo allowRedo: Bool = true) {
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
        redo.setAccessibilityLabel("Suggest another name")
        redo.isHidden = !allowRedo
        let undo = NSButton(title: "Undo", target: self, action: #selector(undoRename))
        undo.setAccessibilityLabel("Undo: put the old name back")
        field.setAccessibilityLabel("New name")
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

    var onFinish: (String) -> Void = { print($0); fflush(stdout); exit(0) }
    private var finished = false

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        present()
        NSApp.run()
        exit(0)
    }

    func present() {
        if !headless { panel.orderFrontRegardless() }
        panel.makeFirstResponder(nil)   // nothing selected, no keyboard focus until you click the name
        startTimer()
        uiTest()
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

    func finish(_ line: String) {
        guard !finished else { return }
        finished = true
        timer?.invalidate(); timer = nil
        panel.orderOut(nil)
        onFinish(line)
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

/// Popups and pills shown inside neatly itself: no extra program to start (that cost ~235 ms each time).
@MainActor
enum InApp {
    private static var open: [NSObject] = []   // keep each window alive until it answers
    /// Something is on screen (a popup or a pill): don't restart for an update now.
    static var busy: Bool { !open.isEmpty }

    static func ask(file: String, suggestion: String, folder: URL?, seconds: Int, path: URL? = nil,
                    duplicate: URL? = nil, pinned: Bool = false) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let d = CountdownDialog(file: file, name: suggestion, folder: folder, seconds: seconds, path: path,
                                    duplicate: duplicate, pinned: pinned)
            open.append(d)
            d.onFinish = { line in open.removeAll { $0 === d }; c.resume(returning: line) }
            d.present()
        }
    }

    static func pill(name: String, file: URL, seconds: Int, redo: Bool = true) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let t = Toast(name: name, file: file, seconds: max(seconds, 3), redo: redo)
            open.append(t)
            t.onFinish = { line in open.removeAll { $0 === t }; c.resume(returning: line) }
            t.present()
        }
    }
}

/// Pills that report something already done (a download saved while you were away) wait their turn,
/// one after another, without holding up the next download.
@MainActor
enum Pills {
    private static var tail: Task<Void, Never>?
    static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let before = tail
        tail = Task { @MainActor in await before?.value; await work() }
    }
}

/// A short message under the menu bar ("Put back 3 names."), gone after a few seconds. Never takes focus.
@MainActor
enum Notice {
    static func show(_ text: String, icon: String = "checkmark.circle.fill") {
        print("notice: \(text)")
        guard !headless else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        let view = HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(brand)
            Text(text).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Capsule().fill(.regularMaterial))
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let size = host.fittingSize
        panel.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 10))
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { panel.orderOut(nil) }
    }
}
