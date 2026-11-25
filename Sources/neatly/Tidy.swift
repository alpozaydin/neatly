import AppKit
import SwiftUI
import QuickLookThumbnailing
import NeatlyCore

/// The review window: files dropped on neatly, or a whole folder (Tidy Desktop / Downloads / Pick a Folder).
/// neatly suggests a name for each; you can change any name, untick any file, then Rename. Nothing changes
/// before that, and Undo puts every name back. Every row stays editable — even when neatly has no idea.
@MainActor
final class TidyWindow: NSObject, NSWindowDelegate {
    let model: TidyModel
    var window: NSWindow?

    /// `paths`: one folder (tidy what's inside) or several files (dropped on neatly).
    init(paths: [URL], neatly: Neatly) {
        var isDir: ObjCBool = false
        let oneFolder = paths.count == 1 && FileManager.default.fileExists(atPath: paths[0].path, isDirectory: &isDir) && isDir.boolValue
        let folder = oneFolder ? paths[0] : paths[0].deletingLastPathComponent()
        func inside(_ dir: URL) -> [URL] {
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles])) ?? []
        }
        // Several things picked in Finder: folders contribute the files inside them (one level), files themselves.
        let candidates = oneFolder ? inside(folder) : paths.flatMap { url -> [URL] in
            var d: ObjCBool = false
            let isFolder = FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
            let isPackage = NSWorkspace.shared.isFilePackage(atPath: url.path)   // .app, .pages: one file to you
            return isFolder && !isPackage ? inside(url) : [url]
        }
        let files = candidates
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true || NSWorkspace.shared.isFilePackage(atPath: $0.path) }
            // A folder: only meaningless names (yours are left alone). Files you dropped: you asked for them.
            .filter { Decision.make(for: $0, explicit: !oneFolder).shouldRename }
        // A folder: newest first (when it arrived there), so recent files are named first. Dropped files: A to Z.
        // NEATLY_TIDY_MTIME (tests): use the date a test can set with `touch`, since "added" dates can't be faked.
        let byMtime = ProcessInfo.processInfo.environment["NEATLY_TIDY_MTIME"] != nil
        func arrived(_ u: URL) -> Date {
            let v = try? u.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey])
            if byMtime { return v?.contentModificationDate ?? .distantPast }
            return v?.addedToDirectoryDate ?? v?.creationDate ?? v?.contentModificationDate ?? .distantPast
        }
        let dated = files.map { (url: $0, date: arrived($0)) }
            .sorted { oneFolder ? $0.date > $1.date
                                : $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        model = TidyModel(title: oneFolder ? folder.lastPathComponent : "\(files.count) file\(files.count == 1 ? "" : "s")",
                          files: dated, neatly: neatly, wholeFolder: oneFolder)
        super.init()
    }

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(headless ? .prohibited : .regular)
        Appearance.apply(neatly.profile.appearance)   // Light/Dark from Home, also in this separate window
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

    /// NEATLY_UI_TEST="edit0:name,untick1,span:365,rename,undoall,done,snapshot=<png>": press the buttons by code.
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
                if step.hasPrefix("span:"), let d = Int(step.dropFirst(5)), let s = TidySpan(rawValue: d) {
                    model.span = s
                    try? await Task.sleep(for: .milliseconds(300))
                    while model.working { try? await Task.sleep(for: .milliseconds(200)) }   // the newly shown files
                }
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
                .environment(\.colorScheme, scheme).background(look.window))
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

/// Which files of a big folder to look at, by when they arrived there.
enum TidySpan: Int, CaseIterable {
    case week = 7, month = 30, year = 365, all = 0
    var label: String { switch self { case .week: "Last 7 days"; case .month: "Last 30 days"; case .year: "Last year"; case .all: "All" } }
    func includes(_ d: Date, now: Date = Date()) -> Bool { self == .all || d >= now.addingTimeInterval(-Double(rawValue) * 86_400) }
}

@MainActor
final class TidyModel: ObservableObject {
    @Published var items: [TidyItem]
    /// Every messy file in the folder, newest first; `items` are the ones in the chosen time span.
    let all: [(url: URL, date: Date)]
    /// Files you switched away from keep what neatly found for them (names, your edits) for when you switch back.
    private var kept: [URL: TidyItem] = [:]
    @Published var span: TidySpan = .all { didSet { if span != oldValue { applySpan() } } }
    /// Only big folders get the time choice: a handful of files is quicker to just review.
    var showsSpan: Bool { wholeFolder && all.count > 25 }
    func count(_ s: TidySpan) -> Int { all.filter { s.includes($0.date) }.count }
    @Published var working = true
    @Published var done = 0
    @Published var finished: Int?            // renamed this many; nil = not yet
    @Published var message = ""
    @Published var warming = false
    let title: String
    let wholeFolder: Bool
    var neatly: Neatly
    var forPicture = false

    init(title: String, files: [(url: URL, date: Date)], neatly: Neatly, wholeFolder: Bool) {
        self.title = title
        self.wholeFolder = wholeFolder
        self.neatly = neatly
        all = files
        items = []
        // More than 100 messy files: start with the last 30 days (or the shortest span that has any).
        if wholeFolder && files.count > 100 {
            span = [TidySpan.month, .year].first { s in files.contains { s.includes($0.date) } } ?? .all
        }
        if let t = ProcessInfo.processInfo.environment["NEATLY_TIDY_SPAN"].flatMap(Int.init).flatMap(TidySpan.init) { span = t }   // tests
        applySpan()
    }

    /// Show the files of the chosen span, keeping what was already found for each one.
    func applySpan() {
        for it in items { kept[it.url] = it }
        items = all.filter { span.includes($0.date) }.map { kept[$0.url] ?? TidyItem(url: $0.url, name: $0.url.deletingPathExtension().lastPathComponent) }
        for i in items.indices where items[i].thumbnail == nil { loadThumbnail(i) }
        done = items.filter { !$0.isPending }.count
        if items.isEmpty { message = all.isEmpty ? (wholeFolder ? "Everything here already has a clear name." : "Nothing to rename.")
                                                 : "No messy names from this time. Pick a longer one." }
        else { message = "" }
        if !naming && items.contains(where: \.isPending) { Task { await nameAll() } }
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
    private var naming = false

    func nameAll() async {
        guard !naming else { return }   // already reading (started by the window or by a new time span)
        naming = true; working = true
        defer { naming = false; working = false }
        // Wake the model first (slow only on a fresh install), so no file times out while it starts.
        let t0 = Date()
        if !items.isEmpty && neatly.useModel { warming = true; await Neatly.warmUp(); warming = false }
        print("tidy: model ready after \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        // Top to bottom, newest first. The list can change while neatly reads (another time span): each file is
        // looked up again by its place on disk afterwards, and a file no longer shown keeps its result for later.
        while let next = items.first(where: \.isPending) {
            let url = next.url
            update(url) { $0.state = .reading }
            var n = neatly
            n.documentBudget = .seconds(15)
            n.imageBudget = .seconds(20)
            let t1 = Date()
            let outcome = await n.suggest(for: url, explicit: true, within: .seconds(30))
            print("tidy: \(url.lastPathComponent) → \(outcome) in \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
            update(url) { item in
                switch outcome {
                case .suggested(let s):
                    item.suggestion = s.name
                    item.name = s.name
                    item.state = .named
                case .kept(let why), .unsure(let why):
                    item.checked = false
                    item.state = .noIdea(Self.plain(why, url: url))
                }
            }
            done = items.filter { !$0.isPending }.count
        }
    }

    /// Change a file's row, whether it's shown now or kept for another time span.
    private func update(_ url: URL, _ change: (inout TidyItem) -> Void) {
        if let i = items.firstIndex(where: { $0.url == url }) { change(&items[i]) }
        else if var it = kept[url] { change(&it); kept[url] = it }
    }

    /// neatly's internal reasons, in words anyone understands.
    static func plain(_ why: String, url: URL) -> String {
        if why.contains("no better name") || why.contains("meaningful") { return "This name already looks fine" }
        if why.contains("you chose") { return "You named this one yourself" }
        if why.contains("too long") { return "Took too long — type a name if you like" }
        if ["zip", "dmg", "pkg", "iso", "exe", "app"].contains(url.pathExtension.lowercased()) {
            return "neatly doesn't look inside .\(url.pathExtension.lowercased()) files — type a name if you like"
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
            History.add(HistoryEntry(kind: .tidy, from: items[i].url, to: new))
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
            History.markReverted([r])
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
    /// Not looked at yet (or interrupted while being read): neatly still has to read it.
    var isPending: Bool { switch state { case .waiting: true; case .reading: true; default: false } }
}

// MARK: - The look (same building blocks as the neatly window)

struct TidyView: View {
    @ObservedObject var model: TidyModel

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 14)
            if !Neatly.modelAvailable { modelBanner.padding(.horizontal, 24).padding(.bottom, 12) }
            if model.forPicture { rows; Spacer(minLength: 0) }   // the off-screen renderer can't draw scroll views
            else { ScrollView { rows } }
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(look.window)
    }

    var rows: some View {
        VStack(spacing: 8) {
            if model.forPicture {   // a picture has no scrolling: the first rows, so the header stays in view
                ForEach(Array(model.items.indices.prefix(4)), id: \.self) { i in Row(item: $model.items[i], model: model) }
            } else {
                ForEach($model.items) { $item in Row(item: $item, model: model) }
            }
        }.padding(.horizontal, 24).padding(.bottom, 12)
    }

    var header: some View {
        HStack(spacing: 14) {
            TitleMark(icon: "sparkles")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.finished != nil ? "Done!" : "Review \(model.title)")
                    .font(.system(size: 20, weight: look.titleWeight, design: look.titleFont))
                if model.working, !model.items.isEmpty {
                    HStack(spacing: 8) {
                        Bar(fraction: Double(model.done) / Double(max(model.items.count, 1))).frame(width: 140, height: 6)
                        Text(model.warming ? "Getting ready… (this takes about a minute after installing or updating)"
                                           : "Reading \(model.done + 1) of \(model.items.count)…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else if let n = model.finished {
                    Text("Renamed \(n) file\(n == 1 ? "" : "s").").foregroundStyle(.secondary)
                } else {
                    Text(model.message.isEmpty ? "Check the names — change any you like." : model.message).foregroundStyle(.secondary)
                }
                if model.showsSpan && model.finished == nil {
                    HStack(spacing: 6) {
                        Text("Files from").foregroundStyle(.secondary)
                        ForEach(TidySpan.allCases, id: \.self) { s in
                            Chip(text: "\(s.label) (\(model.count(s)))", selected: model.span == s) { model.span = s }
                        }
                    }.padding(.top, 4)
                }
            }
            Spacer()
        }
    }

    var modelBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.intelligence").foregroundStyle(look.warn)
            Text("Apple Intelligence is off, so names come from the text only and are simpler.").font(.callout)
            Spacer()
            Button("Turn it on") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
            }.buttonStyle(.plain).foregroundStyle(look.link).font(.callout.weight(.semibold))
        }
        .padding(12).warnBox()
    }

    var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
            Text(model.finished != nil ? "Changed your mind? Undo puts every name back."
                 : (!model.working && model.toRename.isEmpty && !model.items.isEmpty)
                   ? (model.items.allSatisfy { if case .noIdea(let w) = $0.state { w.contains("looks fine") } else { false } }
                      ? "These names already look fine. Type a new name in a box to change one."
                      : "To rename a file, type a new name in its box.")
                   : "Nothing changes until you click Rename.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            if model.finished != nil {
                Pill(title: "Undo", primary: false) { model.undoAll() }
                Pill(title: "Done", primary: true) { NSApp.terminate(nil) }
            } else if model.toRename.isEmpty && !model.working {
                // Nothing to rename: never show a button that can't be pressed.
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
            leading.frame(width: 24)
            Group {
                if let t = item.thumbnail { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "doc").font(.title2).foregroundStyle(.secondary) }
            }
            .frame(width: 56, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
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
        .surface(dim: !item.checked)
    }

    /// A circle only where there's a rename to approve; otherwise a status icon that clearly isn't a button.
    @ViewBuilder var leading: some View {
        if item.renamedTo != nil {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.green).help("Renamed")
        } else if item.name.trimmingCharacters(in: .whitespaces) != item.stem {
            CheckCircle(on: item.checked, enabled: true) { item.checked.toggle() }.help(item.checked ? "Will be renamed" : "Will be skipped")
                .accessibilityLabel("Rename \(item.url.lastPathComponent)")
                .accessibilityValue(item.checked ? "will be renamed" : "will be skipped")
                .accessibilityAddTraits(.isToggle)
        } else {
            switch item.state {
            case .reading, .waiting: ProgressDots()
            case .noIdea(let why) where why.contains("already looks fine") || why.contains("named this one"):
                Image(systemName: "checkmark.seal").font(.system(size: 18)).foregroundStyle(.secondary).help("Name already looks fine")
            default:
                Image(systemName: "pencil.line").font(.system(size: 16)).foregroundStyle(.secondary).help("Type a name to rename it")
            }
        }
    }

    @ViewBuilder var nameField: some View {
        if model.forPicture || item.renamedTo != nil {
            Text(item.name.isEmpty ? " " : item.name).font(.body.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: look.control, style: .continuous).fill(look.field))
        } else {
            TextField("Type a name", text: $item.name)
                .accessibilityLabel("New name for \(item.url.lastPathComponent)")
                .textFieldStyle(.plain).font(.body.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: look.control, style: .continuous).fill(look.field))
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
                    .background(Circle().fill(on ? AnyShapeStyle(look.accent) : AnyShapeStyle(Color.clear)))
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(look.onAccent) }
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
            Text(title).font(.body.weight(.medium)).lineLimit(1).fixedSize()   // a button label never wraps
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(primary ? AnyShapeStyle(look.onFill) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: look.control, style: .continuous)
                    .fill(primary ? AnyShapeStyle(look.fill) : AnyShapeStyle(look.field)))
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
                Capsule().fill(look.accent).frame(width: max(6, g.size.width * fraction))
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

    /// How many files the last tidy renamed that can still be put back (0 = nothing to undo).
    static var lastCount: Int {
        guard let data = try? Data(contentsOf: lastURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return 0 }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }.count
    }

    static func undoLast() -> Int {
        guard let data = try? Data(contentsOf: lastURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return 0 }
        let back = paths.map { URL(fileURLWithPath: $0) }.filter { (try? Rename.undo($0)) != nil }
        History.markReverted(back)
        let n = back.count
        saveLast([])
        return n
    }
}

/// "Reading…" in a row, before a name arrives.
struct ProgressDots: View {
    var body: some View {
        Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(brand)
    }
}
