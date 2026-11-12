import AppKit
import SwiftUI
import QuickLookThumbnailing
import NamerCore

/// The review window: files dropped on neatly, or a whole folder (Tidy Desktop / Downloads / Pick a Folder).
/// neatly suggests a name for each; you can change any name, untick any file, then Rename. Nothing changes
/// before that, and Undo puts every name back. Every row stays editable — even when neatly has no idea.
@MainActor
final class TidyWindow: NSObject, NSWindowDelegate {
    let model: TidyModel
    var window: NSWindow?

    /// `paths`: one folder (tidy what's inside) or several files (dropped on neatly).
    init(paths: [URL], namer: Namer) {
        var isDir: ObjCBool = false
        let oneFolder = paths.count == 1 && FileManager.default.fileExists(atPath: paths[0].path, isDirectory: &isDir) && isDir.boolValue
        let folder = oneFolder ? paths[0] : paths[0].deletingLastPathComponent()
        let candidates = oneFolder
            ? ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles])) ?? [])
            : paths
        let files = candidates
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            // A folder: only meaningless names (yours are left alone). Files you dropped: you asked for them.
            .filter { Decision.make(for: $0, explicit: !oneFolder).shouldRename }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        model = TidyModel(title: oneFolder ? folder.lastPathComponent : "\(files.count) file\(files.count == 1 ? "" : "s")",
                          files: files, namer: namer, wholeFolder: oneFolder)
        super.init()
    }

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(headless ? .prohibited : .regular)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "neatly"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.minSize = NSSize(width: 560, height: 420)
        w.contentView = NSHostingView(rootView: TidyView(model: model))
        window = w
        if !headless {
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        Task { await model.nameAll() }
        uiTest()
        NSApp.run()
        exit(0)
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }

    /// NEATLY_UI_TEST="edit0:name,untick1,rename,undoall,done,snapshot=<png>": press the buttons by code.
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        let steps = t.split(separator: ",").map(String.init)
        Task { @MainActor in
            while model.working { try? await Task.sleep(for: .milliseconds(200)) }   // wait for the names
            for step in steps {
                try? await Task.sleep(for: .milliseconds(300))
                if step.hasPrefix("edit"), let colon = step.firstIndex(of: ":"),
                   let i = Int(step.dropFirst(4).prefix(while: \.isNumber)), model.items.indices.contains(i) {
                    model.items[i].name = String(step[step.index(after: colon)...]); model.edited(i)
                }
                if step.hasPrefix("untick"), let i = Int(step.dropFirst(6)), model.items.indices.contains(i) { model.items[i].checked = false }
                if step == "rename" { model.renameAll() }
                if step == "undoall" { model.undoAll() }
                if step.hasPrefix("snapshot=") { snapshot(to: String(step.dropFirst(9))) }
                if step == "done" { NSApp.terminate(nil) }
            }
        }
    }

    func snapshot(to path: String) {
        model.forPicture = true
        defer { model.forPicture = false }
        for (scheme, suffix) in [(ColorScheme.light, ""), (.dark, "-dark")] {
            let r = ImageRenderer(content: TidyView(model: model).frame(width: 640, height: 620)
                .environment(\.colorScheme, scheme).background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97)))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { continue }
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: suffix.isEmpty ? path : path.replacingOccurrences(of: ".png", with: "\(suffix).png")))
        }
        print("tidy: snapshot \(path)")
    }
}

// MARK: - Model

struct TidyItem: Identifiable {
    enum State { case waiting, reading, named, noIdea(String), renamed, undone }
    let id = UUID()
    let url: URL
    var name: String                 // what's in the field
    var suggestion: String?
    var checked = true
    var state = State.waiting
    var thumbnail: NSImage?
    var renamedTo: URL?
    var stem: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
final class TidyModel: ObservableObject {
    @Published var items: [TidyItem]
    @Published var working = true
    @Published var done = 0
    @Published var finished: Int?            // renamed this many; nil = not yet
    @Published var message = ""
    @Published var warming = false
    let title: String
    let wholeFolder: Bool
    var namer: Namer
    var forPicture = false

    init(title: String, files: [URL], namer: Namer, wholeFolder: Bool) {
        self.title = title
        self.wholeFolder = wholeFolder
        self.namer = namer
        items = files.map { TidyItem(url: $0, name: $0.deletingPathExtension().lastPathComponent) }
        for i in items.indices { loadThumbnail(i) }
    }

    var toRename: [Int] {
        items.indices.filter { i in
            let it = items[i]
            guard it.checked, it.renamedTo == nil else { return false }
            let n = it.name.trimmingCharacters(in: .whitespaces)
            return !n.isEmpty && n != it.stem
        }
    }

    /// One file at a time: the on-device model is one shared resource. Each file gets 15–20 s — this window
    /// shows progress, so waiting a little beats giving up.
    func nameAll() async {
        message = items.isEmpty ? (wholeFolder ? "Everything here already has a clear name." : "Nothing to rename.") : ""
        // Wake the model first (slow only on a fresh install), so no file times out while it starts.
        let t0 = Date()
        if !items.isEmpty && namer.useModel { warming = true; await Namer.warmUp(); warming = false }
        print("tidy: model ready after \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        for i in items.indices {
            items[i].state = .reading
            var n = namer
            n.documentBudget = .seconds(15)
            n.imageBudget = .seconds(20)
            let t1 = Date()
            let outcome = await n.suggest(for: items[i].url, explicit: true)
            print("tidy: \(items[i].url.lastPathComponent) → \(outcome) in \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
            switch outcome {
            case .suggested(let s):
                items[i].suggestion = s.name
                items[i].name = s.name
                items[i].state = .named
            case .kept(let why), .unsure(let why):
                items[i].checked = false
                items[i].state = .noIdea(Self.plain(why, url: items[i].url))
            }
            done = i + 1
        }
        working = false
    }

    /// neatly's internal reasons, in words anyone understands.
    static func plain(_ why: String, url: URL) -> String {
        if why.contains("no better name") || why.contains("meaningful") { return "This name already looks fine" }
        if why.contains("you chose") { return "You named this one yourself" }
        let ext = url.pathExtension.lowercased()
        if !["pdf", "docx", "pptx", "ipynb", "zip", "png", "jpg", "jpeg", "heic", "tiff", "webp", "gif"].contains(ext) {
            return "neatly can't read .\(ext) files yet — type a name if you like"
        }
        return "Couldn't tell what's inside — type a name if you like"
    }

    /// Typing a name means you want it: tick the file.
    func edited(_ i: Int) {
        items[i].checked = items[i].name.trimmingCharacters(in: .whitespaces) != items[i].stem
    }

    func renameAll() {
        var count = 0
        for i in toRename {
            let typed = items[i].name.trimmingCharacters(in: .whitespaces)
            guard let new = try? Rename.apply(items[i].url, to: typed) else { continue }
            items[i].renamedTo = new
            items[i].state = .renamed
            count += 1
            // Your edits teach future names, like edits in the download popup.
            Correction(original: items[i].url.lastPathComponent, suggested: items[i].suggestion ?? "", chosen: typed,
                       via: "tidy", source: nil, title: nil).save()
        }
        if count > 0 { Tidy.saveLast(items.compactMap(\.renamedTo)) }   // an empty run must not forget the last real one
        finished = count
    }

    func undoAll() {
        var n = 0
        for i in items.indices {
            guard let r = items[i].renamedTo, (try? Rename.undo(r)) != nil else { continue }
            items[i].renamedTo = nil
            items[i].state = .undone
            n += 1
        }
        Tidy.saveLast([])
        message = "Put back \(n) original name\(n == 1 ? "" : "s")."
        finished = nil
        for i in items.indices where items[i].stateIsUndone { items[i].checked = false }
    }

    func loadThumbnail(_ i: Int) {
        let id = items[i].id
        let req = QLThumbnailGenerator.Request(fileAt: items[i].url, size: CGSize(width: 96, height: 72), scale: 2,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated {
                if let j = self.items.firstIndex(where: { $0.id == id }) { self.items[j].thumbnail = img }
            } }
        }
    }
}

extension TidyItem {
    var stateIsUndone: Bool { if case .undone = state { true } else { false } }
}

// MARK: - The look (same building blocks as the neatly window)

struct TidyView: View {
    @ObservedObject var model: TidyModel

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 14)
            if !Namer.modelAvailable { modelBanner.padding(.horizontal, 24).padding(.bottom, 12) }
            if model.forPicture { rows; Spacer(minLength: 0) }   // the off-screen renderer can't draw scroll views
            else { ScrollView { rows } }
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    var rows: some View {
        VStack(spacing: 8) {
            ForEach($model.items) { $item in Row(item: $item, model: model) }
        }.padding(.horizontal, 24).padding(.bottom, 12)
    }

    var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 12).fill(brandGradient))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.finished != nil ? "Done!" : "Rename \(model.title)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if model.working, !model.items.isEmpty {
                    HStack(spacing: 8) {
                        Bar(fraction: Double(model.done) / Double(max(model.items.count, 1))).frame(width: 140, height: 6)
                        Text(model.warming ? "Getting ready… (only the very first time takes a minute)"
                                           : "Reading \(model.done + 1) of \(model.items.count)…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else if let n = model.finished {
                    Text("Renamed \(n) file\(n == 1 ? "" : "s").").foregroundStyle(.secondary)
                } else {
                    Text(model.message.isEmpty ? "Check the names — change any you like." : model.message).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    var modelBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.intelligence").foregroundStyle(.orange)
            Text("Apple Intelligence is off, so names come from the text only and are simpler.").font(.callout)
            Spacer()
            Button("Turn it on") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
            }.buttonStyle(.plain).foregroundStyle(brand).font(.callout.weight(.semibold))
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
            Text(model.finished != nil ? "Changed your mind? Undo puts every name back."
                                       : "Nothing changes until you click Rename.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            if model.finished != nil {
                Pill(title: "Undo", primary: false) { model.undoAll() }
                Pill(title: "Done", primary: true) { NSApp.terminate(nil) }
            } else {
                Pill(title: "Cancel", primary: false) { NSApp.terminate(nil) }
                let n = model.toRename.count
                Pill(title: n == 0 ? "Rename" : "Rename \(n) file\(n == 1 ? "" : "s")", primary: true, enabled: n > 0) {
                    model.renameAll()
                }
            }
        }
    }
}

struct Row: View {
    @Binding var item: TidyItem
    @ObservedObject var model: TidyModel

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(on: item.checked, enabled: item.renamedTo == nil) { item.checked.toggle() }
            Group {
                if let t = item.thumbnail { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "doc").font(.title2).foregroundStyle(.secondary) }
            }
            .frame(width: 56, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 4) {
                nameField
                HStack(spacing: 6) {
                    Text("was \(item.url.lastPathComponent)").lineLimit(1).truncationMode(.middle)
                    stateText
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(item.checked ? 0.05 : 0.025)))
    }

    @ViewBuilder var nameField: some View {
        if model.forPicture || item.renamedTo != nil {
            Text(item.name.isEmpty ? " " : item.name).font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
        } else {
            TextField("Type a name", text: $item.name)
                .textFieldStyle(.plain).font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                .onChange(of: item.name) { _, _ in
                    if let i = model.items.firstIndex(where: { $0.id == item.id }) { model.edited(i) }
                }
        }
    }

    @ViewBuilder var stateText: some View {
        switch item.state {
        case .waiting: Text("· waiting")
        case .reading: Text("· reading…").foregroundStyle(brand)
        case .named: Text("· ✦ suggested").foregroundStyle(brand)
        case .noIdea(let why): Text("· \(why)")
        case .renamed: Text("· ✓ renamed").foregroundStyle(.green)
        case .undone: Text("· name put back")
        }
    }
}

struct CheckCircle: View {
    let on: Bool, enabled: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(on ? Color.clear : Color.primary.opacity(0.25), lineWidth: 1.5)
                    .background(Circle().fill(on ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color.clear)))
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
            }.frame(width: 22, height: 22).opacity(enabled ? 1 : 0.5)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

struct Pill: View {
    let title: String, primary: Bool
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(primary ? .white : .primary)
                .background(Capsule().fill(primary ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
                .opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

struct Bar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(brandGradient).frame(width: max(6, g.size.width * fraction))
            }
        }
    }
}

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
