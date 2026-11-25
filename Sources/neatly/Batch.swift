import AppKit
import NeatlyCore
import QuickLookThumbnailing
import SwiftUI

/// Several downloads at once ("Download all" in WhatsApp, a few attachments, a folder of photos): one popup
/// for all of them instead of one per file. The files are named in the background while it shows.
///   Put in Folder: a new folder (name suggested, editable) with the named files inside.
///   Rename Only:   each file gets its name and stays in Downloads.
///   Keep Originals: nothing changes.
/// No answer = Rename Only, like a single download: nothing moves unseen. A pill then says what was done, with Undo.
/// With "Keep Original" chosen in the window, no answer = nothing changes.
///
/// Answers with one line: "folder\t<folder name>\t<where, empty = Downloads>\t<user|picked>", "rename\t<auto|user>",
/// "keep" or "keep\tauto" (nobody answered).
@MainActor
final class BatchModel: ObservableObject {
    @Published var folderName: String
    @Published var location: URL?           // where the new folder goes; nil = Downloads
    @Published var remaining: Int
    @Published var counting: Bool
    @Published var thumbnails: [NSImage] = []
    var leave = false                       // nobody answers → change nothing
    @Published var named = 0                // how many names are ready
    var edited = false                      // you typed a folder name: suggestions don't replace it any more
    var picked = false
    var forPicture = false
    let count: Int
    let source: String?
    init(count: Int, source: String?, folderName: String, seconds: Int) {
        self.count = count; self.source = source; self.folderName = folderName
        self.remaining = seconds; self.counting = seconds > 0
    }
}

@MainActor
final class BatchDialog: NSObject {
    let model: BatchModel
    let panel = CountdownDialog.Panel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
                                      styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                                      backing: .buffered, defer: false)
    var timer: Timer?
    var onFinish: (String) -> Void = { _ in }
    private var finished = false

    init(files: [URL], source: String?, folderName: String, seconds: Int) {
        model = BatchModel(count: files.count, source: source, folderName: folderName, seconds: seconds)
        super.init()
        let view = BatchView(model: model,
                             folder: { [weak self] in self?.putInFolder() },
                             rename: { [weak self] in self?.finish("rename\tuser") },
                             keep: { [weak self] in self?.finish("keep") },
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
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 10))
        }
        for f in files.prefix(4) { loadThumbnail(f) }
        NotificationCenter.default.addObserver(self, selector: #selector(closed), name: NSWindow.willCloseNotification, object: panel)
    }

    func loadThumbnail(_ url: URL) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.thumbnails.append(img) } }
        }
    }

    func present() {
        if !headless { panel.orderFrontRegardless() }
        if model.counting {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    self.model.remaining -= 1
                    if self.model.remaining <= 0 { self.finish(self.model.leave ? "keep\tauto" : "rename\tauto") }
                }
            }
        }
        uiTest()
    }

    /// NEATLY_UI_TEST="batch:folder" | "batch:folder:<name>" | "batch:place:<where>" | "batch:rename" | "batch:keep" | "batch:wait"
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"], t.hasPrefix("batch:") else { return }
        let step = String(t.dropFirst(6))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if step == "folder" { self.putInFolder() }
            if step.hasPrefix("folder:") { self.model.folderName = String(step.dropFirst(7)); self.model.edited = true; self.putInFolder() }
            if step.hasPrefix("place:") { self.model.location = URL(fileURLWithPath: String(step.dropFirst(6))); self.model.picked = true; self.putInFolder() }
            if step == "rename" { self.finish("rename\tuser") }
            if step == "keep" { self.finish("keep") }
            if step.hasPrefix("snapshot=") { self.snapshot(String(step.dropFirst(9))) }
        }
    }

    func snapshot(_ path: String) {
        model.forPicture = true
        defer { model.forPicture = false }
        let r = ImageRenderer(content: BatchView(model: model, folder: {}, rename: {}, keep: {}, choose: {}, pause: {})
            .environment(\.colorScheme, .light).background(look.window))
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        print("batch: snapshot \(path)")
    }

    func pause() {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil
        model.counting = false
    }

    func putInFolder() {
        let name = cleanFolderName(model.folderName)
        guard !name.isEmpty else { finish("rename\tuser"); return }
        finish("folder\t\(name)\t\(model.location?.path ?? "")\t\(model.picked ? "picked" : "user")")
    }

    func finish(_ line: String) {
        guard !finished else { return }
        finished = true
        timer?.invalidate(); timer = nil
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
        onFinish(line)
    }

    @objc func closed() { finish("keep") }

    func chooseFolder() {
        pause()
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.prompt = "Put It Here"
        open.message = "Make the folder “\(cleanFolderName(model.folderName))” in:"
        open.directoryURL = model.location ?? Home.real
        open.level = .modalPanel
        NSApp.activate()
        open.begin { [weak self] r in
            guard r == .OK, let url = open.url else { return }
            MainActor.assumeIsolated { self?.model.location = url; self?.model.picked = true }
        }
        open.orderFrontRegardless()
        open.makeKey()
    }
}

/// A folder name: no slashes or colons (they'd make a path), no leading dot (hidden), trimmed.
func cleanFolderName(_ s: String) -> String {
    var t = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasPrefix(".") { t.removeFirst() }
    return String(t.prefix(120))
}

struct BatchView: View {
    @ObservedObject var model: BatchModel
    let folder: () -> Void, rename: () -> Void, keep: () -> Void, choose: () -> Void, pause: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    if model.thumbnails.isEmpty {
                        Image(systemName: "doc.on.doc").font(.system(size: 24, weight: .light)).foregroundStyle(look.glyph)
                    }
                    ForEach(Array(model.thumbnails.prefix(3).enumerated()), id: \.offset) { i, img in
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(look.window, lineWidth: 2))
                            .offset(x: CGFloat(i) * 14)
                    }
                }
                .frame(width: 64, height: 44, alignment: .leading)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.count) new downloads").font(.callout.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Folder name").font(.caption).foregroundStyle(.secondary)
                Group {
                    if model.forPicture { Text(model.folderName).frame(maxWidth: .infinity, alignment: .leading) }
                    else {
                        TextField("Type a folder name", text: Binding(get: { model.folderName },
                                                                     set: { model.folderName = $0; model.edited = true; pause() }))
                            .textFieldStyle(.plain)
                    }
                }.font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: look.control, style: .continuous).fill(look.field))
                    .accessibilityLabel("Folder name")
            }
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(look.glyph).accessibilityHidden(true)
                Text("in \(model.location.map { shortFolder($0) } ?? "Downloads")").lineLimit(1).truncationMode(.head)
                Spacer()
                Button("Choose Folder…", action: choose).buttonStyle(.plain).foregroundStyle(look.link).font(.callout.weight(.medium))
            }
            Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Pill(title: "Keep Originals", primary: false, action: keep).keyboardShortcut(.cancelAction)
                Pill(title: "Rename Only", primary: false, action: rename)
                Pill(title: "Put in Folder", primary: true, action: folder).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 18)
        .frame(width: 460)
        .background(look.window)
        .onHover { if $0 { pause() } }
    }

    var subtitle: String {
        let from = model.source.map { "from \($0) · " } ?? ""
        return from + (model.named >= model.count ? "names ready" : "naming \(model.named + 1) of \(model.count)…")
    }

    var status: String {
        let each = "Each file gets a clear name."
        guard model.counting else { return each }
        if model.leave { return "\(each) If you don't answer in \(max(model.remaining, 0)) s: Keep Originals" }
        return "\(each) If you don't answer in \(max(model.remaining, 0)) s: Rename Only"
    }
}

extension InApp {
    static func askBatch(files: [URL], source: String?, folderName: String, seconds: Int, leave: Bool = false,
                         progress: @escaping (BatchModel) -> Void) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let d = BatchDialog(files: files, source: source, folderName: folderName, seconds: seconds)
            d.model.leave = leave
            keep(d)
            d.onFinish = { line in release(d); c.resume(returning: line) }
            progress(d.model)
            d.present()
        }
    }
}

// MARK: - Folder name ideas

enum BatchName {
    /// "Photos", "Videos", "PDFs" or "Files": what the group is, for the folder name.
    static func kind(_ files: [URL]) -> String {
        let exts = Set(files.map { $0.pathExtension.lowercased() })
        if exts.isSubset(of: Neatly.imageLike) { return "Photos" }
        if exts.isSubset(of: ["mov", "mp4", "m4v", "avi", "mkv", "webm", "3gp"]) { return "Videos" }
        if exts == ["pdf"] { return "PDFs" }
        return "Files"
    }

    /// "web.whatsapp.com" → "WhatsApp". Only when every file came from the same place.
    static func source(_ files: [URL]) -> String? {
        let hosts = files.map { Evidence.sourceHost(of: $0) }
        guard let first = hosts.first, let host = first, hosts.allSatisfy({ $0 == host }) else { return nil }
        return pretty(host)
    }

    static func pretty(_ host: String) -> String {
        let h = host.lowercased()
        let known: [(String, String)] = [("whatsapp", "WhatsApp"), ("mail.google", "Gmail"), ("mail-attachment.googleusercontent", "Gmail"),
                                         ("drive.google", "Google Drive"), ("drive.usercontent.google", "Google Drive"),
                                         ("docs.google", "Google Docs"), ("photos.google", "Google Photos"), ("icloud", "iCloud"),
                                         ("dropbox", "Dropbox"), ("telegram", "Telegram"), ("slack", "Slack"), ("outlook", "Outlook"),
                                         ("onedrive", "OneDrive"), ("sharepoint", "OneDrive"), ("wetransfer", "WeTransfer"),
                                         ("instagram", "Instagram"), ("discord", "Discord")]
        if let k = known.first(where: { h.contains($0.0) }) { return k.1 }
        var parts = h.split(separator: ".").map(String.init)
        while parts.count > 2, ["www", "web", "m", "app", "cdn", "files", "download", "dl"].contains(parts[0]) { parts.removeFirst() }
        let label = parts.first ?? h
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Before any file is named: "WhatsApp Photos 18 Nov 2026".
    static func initial(_ files: [URL], source: String?, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return [source, kind(files), f.string(from: date)].compactMap { $0 }.joined(separator: " ")
    }

    /// Once names are in: what most of them share. "Colosseum in Rome", "Trevi Fountain in Rome", "Pantheon in Rome"
    /// → "Rome Photos". Nil when they share nothing (then the first idea stays).
    static func theme(_ names: [String], kind: String) -> String? {
        guard names.count >= 2 else { return nil }
        let skip: Set<String> = ["in", "at", "of", "the", "and", "a", "an", "on", "for", "with", "to", "from", "by", "my",
                                 "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
                                 "photo", "image", "img", "screenshot", "file", "document", "copy", "new"]
        func words(_ s: String) -> [String] {
            s.split(whereSeparator: { " -_.,()".contains($0) }).map(String.init)
                .filter { $0.count > 1 && !skip.contains($0.lowercased()) && $0.rangeOfCharacter(from: .letters) != nil }
        }
        var count: [String: Int] = [:]
        var shown: [String: String] = [:]
        var order: [String] = []
        for n in names {
            for w in Set(words(n).map { $0.lowercased() }) { count[w, default: 0] += 1 }
            for w in words(n) where shown[w.lowercased()] == nil { shown[w.lowercased()] = w; order.append(w.lowercased()) }
        }
        let need = max(2, Int((Double(names.count) * 0.6).rounded(.up)))
        let common = order.filter { (count[$0] ?? 0) >= need }.prefix(3).compactMap { shown[$0] }
        guard !common.isEmpty else { return nil }
        // "rome" → "Rome", but codes stay as they are ("cs334", "iPhone").
        let t = common.map { $0.allSatisfy(\.isLowercase) ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }.joined(separator: " ")
        return common.count >= 2 || t.lowercased().hasSuffix(kind.lowercased()) ? t : "\(t) \(kind)"
    }
}

// MARK: - Handling a group

@MainActor private final class BatchState {
    var names: [URL: String] = [:]
    var done = 0
    var model: BatchModel?
}

/// One question for the whole group, the names worked out meanwhile, then everything done at once.
@MainActor func handleBatch(_ files: [URL], downloads dir: URL) async {
    let source = BatchName.source(files), kind = BatchName.kind(files)
    let stamps = files.map { FileStamp($0) }
    let state = BatchState()
    print("\(files.count) downloads at once\(source.map { " from \($0)" } ?? ""): one popup for all")
    let naming = Task { @MainActor in
        await Warm.ready()
        for u in files {
            if Task.isCancelled { return }
            if case .suggested(let s) = await neatly.suggest(for: u, explicit: false, within: .seconds(20)) {
                state.names[u] = s.name
                print("   \(u.lastPathComponent)  →  \(s.name)   [\(s.via)]")
            }
            state.done += 1
            if let m = state.model {
                m.named = state.done
                if !m.edited, state.done >= min(3, files.count),
                   let t = BatchName.theme(Array(state.names.values), kind: kind) { m.folderName = t }
            }
        }
    }
    let reply = await InApp.askBatch(files: files, source: source, folderName: BatchName.initial(files, source: source),
                                     seconds: timeout, leave: leaveWhenAway) { state.model = $0 }
    state.model = nil
    let parts = reply.components(separatedBy: "\t")
    if parts.first == "keep" {
        naming.cancel()
        // Nobody answered: leave them alone, but don't record "you chose these names" either.
        if parts.count > 1, parts[1] == "auto" { print("   no answer, left as is"); return }
        files.forEach { Decision.markKeep($0) }
        print("   left as is")
        return
    }
    var folder: URL?
    if parts.first == "folder", parts.count >= 3 {
        folder = (parts[2].isEmpty ? dir : URL(fileURLWithPath: parts[2])).appending(path: parts[1], directoryHint: .isDirectory)
    }
    let auto = parts.first == "rename" && parts.count > 1 && parts[1] == "auto"
    let existed = folder.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
    await naming.value   // the popup is gone: the last names finish in the background

    var entries: [HistoryEntry] = []
    for (u, stamp) in zip(files, stamps) {
        // Still the same file neatly looked at? (Not grown, swapped or moved away meanwhile.)
        guard let stamp, FileStamp(u) == stamp else { print("   \(u.lastPathComponent) changed or is gone: skipped"); continue }
        let original = u.deletingPathExtension().lastPathComponent
        let stem = state.names[u] ?? original
        if stem == original && folder == nil { Decision.markKeep(u); continue }   // nothing to change
        var moved = try? Rename.apply(u, to: stem, in: folder)
        if moved == nil, let f = folder {   // can't make or write that folder: keep the name, stay in Downloads
            print("   couldn't put files in \(Destination.short(f)): kept in Downloads")
            Notice.show("Couldn't save in \(shortFolder(f)) — kept in Downloads.", icon: "exclamationmark.triangle.fill")
            folder = nil
            moved = stem == original ? nil : try? Rename.apply(u, to: stem)
        }
        guard let moved else { Decision.markKeep(u); continue }
        Decision.markKeep(moved)
        let e = HistoryEntry(kind: .download, from: u, to: moved, host: Evidence.sourceHost(of: moved), auto: auto)
        History.add(e)
        entries.append(e)
        print("   saved as \(Destination.short(folder))/\(moved.lastPathComponent)")
    }
    guard let first = entries.first else { return }
    // One pill for the whole group, with Undo for all of it.
    let what = folder.map { "\(entries.count) files in “\($0.lastPathComponent)”" } ?? "Named \(entries.count) files"
    let made = existed ? nil : folder
    Pills.enqueue {
        let reply = await InApp.pill(name: what, file: URL(fileURLWithPath: first.to), seconds: max(timeout, 5),
                                     redo: false, editable: false)
        guard reply == "undo" else { return }
        let back = entries.filter { (try? History.revert($0.id)) != nil }.count
        if let made, ((try? FileManager.default.contentsOfDirectory(atPath: made.path)) ?? ["?"]).allSatisfy({ $0 == ".DS_Store" }) {
            try? FileManager.default.removeItem(at: made)   // the folder neatly made, now empty again
        }
        print("   undone: \(back) files")
        Notice.show("Put back \(back) files.", icon: "arrow.uturn.backward.circle.fill")
    }
}

/// A download just finished. Are more coming with it? Collect each one as it finishes, until the folder has been
/// quiet for 1.5 s (90 s at most). A lone download costs one 0.4 s look.
/// `downloading`: the browser's unfinished files. One starting or finishing counts as activity; a big download
/// that just keeps growing (or one abandoned long ago) doesn't hold anything up.
@MainActor func gatherGroup(_ ready: [String], in dir: URL, seen: Set<String>, listing: () -> [String: Int],
                            downloading: () -> Set<String>) async -> [String] {
    var group = Set(ready)
    var sizes: [String: (size: Int, since: Date)] = [:]
    var partial = downloading()
    func others() -> Bool { listing().keys.contains { !seen.contains($0) && !group.contains($0) } }
    if ready.count < 2 && !others() {
        try? await Task.sleep(for: .milliseconds(400))
        if downloading() == partial && !others() { return ready }
    }
    let start = Date()
    var lastChange = Date()
    while Date().timeIntervalSince(start) < 90 {
        try? await Task.sleep(for: .milliseconds(300))
        let now = listing()
        let p = downloading()
        if p != partial { partial = p; lastChange = Date() }
        for (name, size) in now where !seen.contains(name) && !group.contains(name) {
            guard let was = sizes[name], was.size == size else { sizes[name] = (size, Date()); lastChange = Date(); continue }
            // Finished: unchanged since the last look (a browser download), or for 3 s (a copy, a script).
            let fromBrowser = getxattr(dir.appending(path: name).path, "com.apple.metadata:kMDItemWhereFroms", nil, 0, 0, 0) > 0
            if fromBrowser || Date().timeIntervalSince(was.since) >= 3 { group.insert(name) }
        }
        let unsettled = now.keys.contains { !seen.contains($0) && !group.contains($0) }
        if !unsettled && Date().timeIntervalSince(lastChange) >= 1.5 { break }
    }
    return Array(group)
}
