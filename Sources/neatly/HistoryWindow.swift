import AppKit
import SwiftUI
import NamerCore

/// "Where did my file go?": everything neatly renamed or moved, newest first, each with Revert.
/// For a download from a site, "Always do this" makes its folder a rule: files from that site go there,
/// even when you don't answer the popup. Your rules are listed on top, each with Remove.
@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    static let shared = HistoryWindow()
    let model = HistoryModel()
    var window: NSWindow?

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "neatly History"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.minSize = NSSize(width: 520, height: 360)
            w.collectionBehavior = [.moveToActiveSpace]
            w.contentView = NSHostingView(rootView: HistoryView(model: model))
            window = w
        }
        print("history: shown (\(model.entries.count) entries, \(model.rules.count) rules)")
        if !headless, let window {
            NSApp.setActivationPolicy(.regular)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        uiTest()
    }

    func windowWillClose(_ notification: Notification) {
        if !headless, HomeWindow.shared.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }

    /// NEATLY_UI_TEST="history:revert0,history:always0,history:unrule0,history:snapshot=<png>" (0 = newest).
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [model] in
            for step in t.split(separator: ",").map(String.init) where step.hasPrefix("history:") {
                let s = String(step.dropFirst(8))
                if s.hasPrefix("revert"), let i = Int(s.dropFirst(6)), model.entries.indices.contains(i) { model.revert(model.entries[i]) }
                if s.hasPrefix("always"), let i = Int(s.dropFirst(6)), model.entries.indices.contains(i) { model.always(model.entries[i]) }
                if s.hasPrefix("unrule"), let i = Int(s.dropFirst(6)), model.rules.indices.contains(i) { model.removeRule(model.rules[i].host) }
                if s.hasPrefix("snapshot=") { HistoryWindow.snapshot(model, to: String(s.dropFirst(9))) }
            }
        }
    }

    static func snapshot(_ model: HistoryModel, to path: String) {
        model.forPicture = true
        defer { model.forPicture = false }
        for (scheme, suffix) in [(ColorScheme.light, ""), (.dark, "-dark")] {
            let r = ImageRenderer(content: HistoryView(model: model).frame(width: 600, height: 560)
                .environment(\.colorScheme, scheme).background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97)))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { continue }
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: suffix.isEmpty ? path : path.replacingOccurrences(of: ".png", with: "\(suffix).png")))
        }
        print("history: snapshot \(path)")
    }
}

@MainActor
final class HistoryModel: ObservableObject {
    struct Rule: Identifiable { var id: String { host }; let host: String; let folder: String }
    @Published var entries: [HistoryEntry] = []
    @Published var rules: [Rule] = []
    @Published var message = ""
    var forPicture = false

    func reload() {
        entries = History.all().reversed()
        rules = (namer.profile.rules ?? [:]).map { Rule(host: $0.key, folder: $0.value) }.sorted { $0.host < $1.host }
    }

    func revert(_ e: HistoryEntry) {
        do {
            let back = try History.revert(e.id)
            message = "Put back “\(back.lastPathComponent)” in \(shortFolder(back.deletingLastPathComponent()))."
        } catch History.RevertError.gone {
            message = "Can't find “\(URL(fileURLWithPath: e.to).lastPathComponent)” any more — it was moved or deleted."
        } catch {
            message = "Couldn't put it back: a file with the old name is already there."
        }
        print("history: \(message)")
        reload()
    }

    /// Files from this site always go to this entry's folder.
    func always(_ e: HistoryEntry) {
        guard let host = e.host else { return }
        let folder = URL(fileURLWithPath: e.to).deletingLastPathComponent().path
        MenuBar.shared.change { p in var r = p.rules ?? [:]; r[host] = folder; p.rules = r }
        message = "From now on, files from \(site(host)) go to \(shortFolder(URL(fileURLWithPath: folder)))."
        print("history: rule \(host) → \(folder)")
        reload()
    }

    func removeRule(_ host: String) {
        MenuBar.shared.change { p in p.rules?[host] = nil; if p.rules?.isEmpty == true { p.rules = nil } }
        message = "Removed the rule for \(site(host))."
        print("history: rule removed \(host)")
        reload()
    }

    func hasRule(_ e: HistoryEntry) -> Bool {
        guard let host = e.host else { return false }
        return namer.profile.rules?[host] == URL(fileURLWithPath: e.to).deletingLastPathComponent().path
    }
}

/// "www.metu.edu.tr" → "metu.edu.tr"
func site(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }

struct HistoryView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 12).fill(brandGradient))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(model.message.isEmpty ? "Everything neatly renamed or moved. Revert puts a file back as it was."
                                               : model.message)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 14)
            if model.forPicture { content; Spacer(minLength: 0) } else { ScrollView { content } }
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.rules.isEmpty {
                Card(title: "Your rules") {
                    ForEach(model.rules) { r in
                        HStack(spacing: 10) {
                            IconBadge(icon: "pin.fill", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Files from \(site(r.host))")
                                Text("always go to \(shortFolder(URL(fileURLWithPath: r.folder)))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Pill(title: "Remove", primary: false) { model.removeRule(r.host) }
                                .accessibilityLabel("Remove the rule for \(site(r.host))")
                        }
                    }
                }
            }
            if model.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Nothing yet. New downloads and screenshots will show up here.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(model.entries) { e in HistoryRow(entry: e, model: model) }
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    @ObservedObject var model: HistoryModel

    var to: URL { URL(fileURLWithPath: entry.to) }
    var from: URL { URL(fileURLWithPath: entry.from) }
    var moved: Bool { to.deletingLastPathComponent().path != from.deletingLastPathComponent().path }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: entry.kind == .download ? "arrow.down.circle.fill" : entry.kind == .screenshot ? "camera.viewfinder" : "sparkles",
                      color: entry.kind == .download ? .green : entry.kind == .screenshot ? .purple : .blue)
                .accessibilityLabel(entry.kind.rawValue)
            VStack(alignment: .leading, spacing: 3) {
                Text(to.lastPathComponent).font(.system(.body, design: .rounded).weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                    .strikethrough(entry.reverted == true)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if entry.reverted == true {
                Text("Put back").font(.caption).foregroundStyle(.secondary)
            } else {
                if entry.kind == .download, entry.host != nil, moved, !model.hasRule(entry) {
                    Button("Always do this") { model.always(entry) }
                        .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(brand)
                        .help("Files from \(site(entry.host ?? "")) always go to \(shortFolder(to.deletingLastPathComponent()))")
                        .accessibilityLabel("Always put files from \(site(entry.host ?? "")) in \(shortFolder(to.deletingLastPathComponent()))")
                }
                Pill(title: "Revert", primary: false) { model.revert(entry) }
                    .accessibilityLabel("Revert \(to.lastPathComponent) to \(from.lastPathComponent)")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(entry.reverted == true ? 0.025 : 0.05)))
    }

    var detail: String {
        var parts = ["was \(from.lastPathComponent)"]
        if moved { parts.append("now in \(shortFolder(to.deletingLastPathComponent()))") }
        if let h = entry.host { parts.append("from \(site(h))") }
        if entry.auto == true { parts.append("saved while you were away") }
        parts.append(entry.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
