import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NeatlyCore

/// The window you get when you open neatly (Spotlight, Applications, or "Open neatly…" in the menu).
/// Written for people who never open Terminal: one promise, a big drop target, three big buttons,
/// plain-language switches, and name styles you pick by their look. Everything else is under "More options".
/// It lives in the running service, so changes apply to the very next file.
@MainActor
final class HomeWindow: NSObject, NSWindowDelegate {
    static let shared = HomeWindow()
    /// Tests use their own name (NEATLY_NOTIFY), so they never open the window of the neatly you actually run.
    static let showNotification = Notification.Name("dev.neatly.show" + (ProcessInfo.processInfo.environment["NEATLY_NOTIFY"] ?? ""))
    /// The answer: "the window is up", so the copy that asked can stop asking.
    static let shownNotification = Notification.Name("dev.neatly.shown" + (ProcessInfo.processInfo.environment["NEATLY_NOTIFY"] ?? ""))

    let model = HomeModel()
    var window: NSWindow?

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.collectionBehavior = [.moveToActiveSpace]          // open on the desktop you're looking at
            w.contentView = NSHostingView(rootView: ScrollView { HomeView(model: model) }.scrollIndicators(.automatic))
            window = w
        }
        print("home: shown")
        if !headless, let window {
            // Never taller than the screen (the content scrolls instead).
            let fit = NSHostingView(rootView: HomeView(model: model)).fittingSize
            let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window.setContentSize(NSSize(width: fit.width, height: min(fit.height, screen.height - 40)))
            // A menu-bar-only app can't reliably come to the front on recent macOS: act like a normal app
            // (Dock icon, ⌘-Tab) while the window is open, then go back to the menu bar when it closes.
            NSApp.setActivationPolicy(.regular)
            if !window.isVisible { window.center() }   // already open (asked twice): leave it where you put it
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
        }
        uiTest()
    }

    func windowWillClose(_ notification: Notification) {
        Welcome.finish()   // closed without clicking Continue: start anyway (macOS asks for the folders now)
        model.welcomed = true
        if !headless, HistoryWindow.shared.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }

    /// NEATLY_UI_TEST="home:length=standard,home:style=title,home:date=on,home:downloads=off,home:screenshots=off,
    ///                 home:countdown=10,home:away=leave,home:drop=<path>,home:snapshot=<png>"
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [model] in
            for step in t.split(separator: ",").map(String.init) where step.hasPrefix("home:") {
                let kv = step.dropFirst(5).split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "length": model.length = StyleProfile.Length(rawValue: kv[1]) ?? .short
                case "style": model.style = NameStyle(rawValue: kv[1]) ?? .dashes
                case "date": model.dateFirst = kv[1] == "on"
                case "downloads": model.downloads = kv[1] == "on"
                case "screenshots": model.screenshots = kv[1] == "on"
                case "countdown": model.countdown = Int(kv[1]) ?? 5
                case "away": model.leaveIfAway = kv[1] == "leave"
                case "autoupdate": model.autoUpdate = kv[1] == "on"
                case "online": model.online = kv[1] == "on"
                case "appearance": model.appearance = kv[1] == "system" ? nil : kv[1]
                case "continue": model.welcome()
                case "forget": model.forget(confirm: false)
                case "uninstall": model.uninstall()
                case "drop": MenuBar.shared.dropped(kv[1].split(separator: "|").map { URL(fileURLWithPath: String($0)) })
                case "snapshot": HomeWindow.snapshot(model, to: kv[1])
                default: break
                }
            }
        }
    }

    /// Draw the window into PNGs (light and dark) without putting it on screen: the tests check the layout this way.
    static func snapshot(_ model: HomeModel, to path: String) {
        for (scheme, suffix) in [(ColorScheme.light, ""), (.dark, "-dark")] {
            model.moreOpen = true
            model.forPicture = true
            defer { model.forPicture = false }
            let r = ImageRenderer(content: HomeView(model: model)
                .environment(\.colorScheme, scheme)
                .background(look.window))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { continue }
            let out = suffix.isEmpty ? path : path.replacingOccurrences(of: ".png", with: "\(suffix).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        }
        print("home: snapshot \(path)")
    }
}

// MARK: - Model: the window's switches ⇄ neatly's settings

enum NameStyle: String, CaseIterable {
    case dashes, title, underscores
    var example: String {
        switch self { case .dashes: "beach-trip"; case .title: "Beach Trip"; case .underscores: "beach_trip" }
    }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var on = true { didSet { if !loading, on == paused { MenuBar.shared.togglePause() } } }
    @Published var downloads = true { didSet { save() } }
    @Published var screenshots = true { didSet { save() } }
    @Published var style = NameStyle.dashes { didSet { save() } }
    @Published var length = StyleProfile.Length.short { didSet { save() } }
    @Published var dateFirst = false { didSet { save() } }
    @Published var appName = false { didSet { save() } }
    @Published var copyShots = false { didSet { save() } }
    @Published var countdown = 5 { didSet { save() } }
    @Published var leaveIfAway = false { didSet { save() } }   // no answer: change nothing
    @Published var autoUpdate: Bool? = nil { didSet { save() } }   // nil = on (the default)
    @Published var online = true { didSet { save() } }
    @Published var appearance: String? = nil { didSet { save(); Appearance.apply(appearance) } }   // nil = like the Mac
    @Published var welcomed = true
    @Published var named = 0
    @Published var moreOpen = false      // view state lives here: SwiftUI's @State needs Xcode's macro plugin
    @Published var dropping = false
    var forPicture = false               // drawing for a test picture: the drop handler can't be drawn off screen
    private var loading = false
    // What the window showed when it opened: a setting is written only if you changed it, so settings the window
    // can't show exactly ("Date Last", dashes in Title Case) are never overwritten by an unrelated click.
    private var shownStyle = NameStyle.dashes, shownDateFirst = false

    func reload() {
        loading = true
        let p = neatly.profile
        on = !paused
        downloads = p.watchDownloads != false
        screenshots = p.watchScreenshots != false
        style = p.separator == "_" ? .underscores : (!p.lowercase || p.separator == " ") ? .title : .dashes
        shownStyle = style
        length = p.len
        dateFirst = p.date != nil
        shownDateFirst = dateFirst
        appName = p.appName == true
        copyShots = p.copyScreenshots == true
        countdown = timeout
        leaveIfAway = leaveWhenAway
        autoUpdate = p.autoUpdate
        online = p.onlineLookups != false
        appearance = p.appearance
        welcomed = Welcome.done
        named = Correction.all().filter { !$0.chosen.isEmpty }.count
        loading = false
    }

    func save() {
        guard !loading else { return }
        MenuBar.shared.change { p in
            p.watchDownloads = downloads
            p.watchScreenshots = screenshots
            if style != shownStyle {
                switch style {
                case .dashes: p.separator = "-"; p.lowercase = true
                case .title: p.separator = " "; p.lowercase = false
                case .underscores: p.separator = "_"; p.lowercase = true
                }
            }
            p.length = length
            if dateFirst != shownDateFirst { p.date = dateFirst ? .prefix : nil }
            p.appName = appName
            p.copyScreenshots = copyShots
            p.countdown = countdown
            p.leaveIfAway = leaveIfAway ? true : nil
            p.autoUpdate = autoUpdate
            p.onlineLookups = online ? nil : false
            p.appearance = appearance
        }
        shownStyle = style; shownDateFirst = dateFirst
        neatly.useNetwork = online && !offline
        timeout = countdown
        leaveWhenAway = leaveIfAway
        objectWillChange.send()   // the preview name follows
    }

    func welcome() {
        Welcome.finish()
        welcomed = true
    }

    /// Delete what neatly remembers about past files (learning log, history, last tidy, activity log).
    func forget(confirm: Bool = true) {
        if confirm, !headless {
            let a = NSAlert()
            a.messageText = "Forget your history?"
            a.informativeText = "neatly forgets the names you chose and the files it handled, so it can't undo them from History any more. "
                + "Your files and settings stay as they are."
            a.addButton(withTitle: "Forget")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        History.forgetAll()
        Log.clear()
        named = 0
        Notice.show("Forgot your history.")
    }

    func uninstall() {
        if !headless {
            let a = NSAlert()
            a.messageText = "Uninstall neatly?"
            a.informativeText = "neatly stops and is removed from Applications and your menu bar. Files it named keep their names."
            a.addButton(withTitle: "Uninstall")
            a.addButton(withTitle: "Cancel")
            a.buttons.first?.hasDestructiveAction = true
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        print("home: uninstall")
        if ProcessInfo.processInfo.environment["NEATLY_APP_DIR"] != nil || headless { return }   // tests: never really
        if Home.sandboxed {
            // App Store version: stop opening at login and quit; the app itself goes to the Trash like any other.
            LoginItem.set(false)
            let a = NSAlert()
            a.messageText = "neatly has stopped"
            a.informativeText = "To finish, drag neatly from your Applications folder to the Trash."
            a.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            NSApp.terminate(nil)
            return
        }
        uninstallEverything()
        NSApp.terminate(nil)
    }

    /// What a name looks like with the current choices — shown live in the window.
    var preview: String {
        let base = length == .short ? "hot-honey-cornbread" : length == .standard ? "hot-honey-cornbread-recipe"
                                                                                 : "hot-honey-cornbread-recipe-cast-iron"
        return neatly.profile.render(base, date: Date(), app: appName ? "Safari" : nil) + ".png"
    }
}

// MARK: - The look

// Colors, type and shapes live in Look.swift.

struct HomeView: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if !model.welcomed {
                // Explain the permission prompts before macOS shows them: neatly waits for this click.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconBadge(icon: "hand.raised.fill", color: .blue)
                        Text("One step before neatly starts").font(.headline)
                    }
                    Text("Next, macOS asks if neatly may use your **Downloads** and **Desktop** folders. Click **Allow**: "
                         + "neatly only looks at new files there, and everything stays on your Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack { Spacer(); Chip(text: "Continue", selected: true) { model.welcome() } }
                }
                .padding(14).surface()
            }
            if !noAccess.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(look.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("neatly isn't allowed to see your \(noAccess.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted().joined(separator: " and ")) folder").font(.callout.weight(.semibold))
                        Text("Allow it, and neatly starts right away.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                    }.buttonStyle(.plain).foregroundStyle(brand).font(.callout.weight(.semibold))
                }
                .padding(12).warnBox()
            }
            if !Neatly.modelAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "apple.intelligence").foregroundStyle(look.warn)
                    Text("Apple Intelligence is off, so names are simpler.").font(.callout)
                    Spacer()
                    Button("Turn it on") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                    }.buttonStyle(.plain).foregroundStyle(brand).font(.callout.weight(.semibold))
                }
                .padding(12).warnBox()
            }
            dropZone
            HStack(spacing: 12) {
                Tile(icon: "menubar.dock.rectangle", color: .blue, title: "Tidy Desktop", subtitle: "Name what's on it") {
                    MenuBar.shared.tidyDesktop()
                }
                Tile(icon: "arrow.down.circle.fill", color: .green, title: "Tidy Downloads", subtitle: "Name your downloads") {
                    MenuBar.shared.tidy([Home.real.appending(path: "Downloads").path])
                }
                Tile(icon: "folder.fill", color: .orange, title: "Pick a Folder", subtitle: "Any folder you like") {
                    MenuBar.shared.tidyFolder()
                }
            }

            Card(title: "Automatically") {
                SwitchRow(icon: "arrow.down.circle.fill", color: .green, title: "New downloads",
                          subtitle: "Suggest a clear name and a place to keep it", isOn: $model.downloads)
                Divider().padding(.leading, 44)
                SwitchRow(icon: "camera.viewfinder", color: .purple, title: "New screenshots",
                          subtitle: "Give them a real name right away — you can always undo", isOn: $model.screenshots)
            }

            Card(title: "How names look") {
                HStack(spacing: 8) {
                    ForEach(NameStyle.allCases, id: \.self) { s in
                        Chip(text: s.example, selected: model.style == s) { model.style = s }
                    }
                }
                HStack(spacing: 8) {
                    Text("Length").foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    ForEach(StyleProfile.Length.allCases, id: \.self) { l in
                        Chip(text: l.label, selected: model.length == l) { model.length = l }
                    }
                    Spacer()
                }
                SwitchRow(icon: "calendar", color: .red, title: "Start with the date", subtitle: nil, isOn: $model.dateFirst)
                HStack(spacing: 8) {
                    Image(systemName: "doc").foregroundStyle(look.glyph)
                    Text(model.preview).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: look.control, style: .continuous).fill(look.field))
            }

            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { model.moreOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(model.moreOpen ? 90 : 0)).font(.caption.weight(.bold))
                        Text("More options").font(.callout.weight(.medium))
                    }.foregroundStyle(.secondary).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if model.moreOpen {
                    Card(title: nil) {
                        SwitchRow(icon: "app.badge", color: .indigo, title: "Add the app's name to screenshots",
                                  subtitle: "e.g. “…-in-safari”", isOn: $model.appName)
                        Divider().padding(.leading, 44)
                        SwitchRow(icon: "doc.on.clipboard", color: .teal, title: "Copy new screenshots",
                                  subtitle: "So you can paste them right away", isOn: $model.copyShots)
                        Divider().padding(.leading, 44)
                        if Home.sandboxed {
                            SwitchRow(icon: "power", color: .teal, title: "Open at login",
                                      subtitle: "So new downloads and screenshots are always named",
                                      isOn: Binding(get: { LoginItem.isOn }, set: { LoginItem.set($0); model.objectWillChange.send() }))
                        } else {
                            SwitchRow(icon: "arrow.triangle.2.circlepath", color: .teal, title: "Update neatly automatically",
                                      subtitle: "Nothing about you or your files is sent",
                                      isOn: Binding(get: { model.autoUpdate != false }, set: { model.autoUpdate = $0 }))
                        }
                        Divider().padding(.leading, 44)
                        SwitchRow(icon: "globe", color: .blue, title: "Look up papers and photo places online",
                                  subtitle: "Sends only a paper's number or a photo's location",
                                  isOn: $model.online)
                        Divider().padding(.leading, 44)
                        HStack(spacing: 12) {
                            IconBadge(icon: "sun.max", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Appearance")
                                Text("Auto follows your Mac's light or dark mode").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            ForEach([("Auto", nil), ("Light", "light"), ("Dark", "dark")] as [(String, String?)], id: \.0) { item in
                                Chip(text: item.0, selected: model.appearance == item.1) { model.appearance = item.1 }
                            }
                        }.padding(.leading, 44)
                        Divider().padding(.leading, 44)
                        HStack(spacing: 12) {
                            IconBadge(icon: "timer", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("If I don't answer a download suggestion")
                                Text(model.countdown == 0 ? "The popup stays until you answer."
                                     : model.leaveIfAway ? "Nothing changes after:" : "neatly keeps the new name, in Downloads, after:")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            ForEach([3, 5, 10, 30, 0], id: \.self) { s in
                                Chip(text: s == 0 ? "Wait for me" : "\(s) sec", selected: model.countdown == s) { model.countdown = s }
                            }
                        }.padding(.leading, 44)
                        if model.countdown != 0 {
                            HStack(spacing: 6) {
                                Chip(text: "Keep the new name", selected: !model.leaveIfAway) { model.leaveIfAway = false }
                                Chip(text: "Change nothing", selected: model.leaveIfAway) { model.leaveIfAway = true }
                            }.padding(.leading, 44)
                        }
                        Divider().padding(.leading, 44)
                        HStack(spacing: 12) {
                            IconBadge(icon: "trash", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Forget my history")
                                Text("What neatly remembers about past files. Settings stay.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Pill(title: "Forget", primary: false) { model.forget() }
                                .accessibilityLabel("Forget my history")
                        }
                        Divider().padding(.leading, 44)
                        HStack(spacing: 12) {
                            IconBadge(icon: "xmark.bin", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Uninstall neatly")
                                Text("Removes the app. Your files keep their names.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Pill(title: "Uninstall…", primary: false) { model.uninstall() }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.caption)
                Text("Your files stay on your Mac. neatly lives in your menu bar ✦").font(.caption)
                Spacer()
                Button("History") { HistoryWindow.shared.show() }.buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(look.link)
                Text("·").font(.caption)
                Button("Quit neatly") { MenuBar.shared.quit() }.buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(look.link)
            }.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 22)
        .frame(width: 520)
        .background(look.window)
    }

    var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppBundle.iconPNG(256).flatMap(NSImage.init(data:)) ?? NSImage())
                .resizable().frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text("neatly").font(.system(size: 26, weight: look.titleWeight, design: look.titleFont)).kerning(-0.3)
                Text(model.named == 0 ? "Clear names for your files, automatically."
                                      : "\(model.named) files named so far.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 4) {
                Switch(isOn: $model.on, label: "neatly on")
                Text(model.on ? "On" : "Paused").font(.caption.weight(.medium)).foregroundStyle(model.on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
    }

    var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .light)).foregroundStyle(look.glyph)
                .padding(.bottom, 2)
            Text("Drop files here to rename them").font(.system(size: 15, weight: .semibold))
            Text("neatly suggests clear names. Nothing changes until you say so.").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: look.radius + 2, style: .continuous)
            .fill(model.dropping ? AnyShapeStyle(look.accent.opacity(0.06)) : AnyShapeStyle(look.surface.opacity(0.6))))
        .overlay(RoundedRectangle(cornerRadius: look.radius + 2, style: .continuous)
            .strokeBorder(model.dropping ? AnyShapeStyle(look.accent) : AnyShapeStyle(look.glyph.opacity(0.45)),
                          style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .modifier(DropTarget(model: model))
    }
}

/// The drop handling, separate so test pictures can leave it out.
struct DropTarget: ViewModifier {
    @ObservedObject var model: HomeModel
    func body(content: Content) -> some View {
        if model.forPicture { content } else { content.onDrop(of: [.fileURL], isTargeted: $model.dropping) { providers in
            let box = URLBox()
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { box.add(u) }; group.leave() }
            }
            group.notify(queue: .main) { MainActor.assumeIsolated { MenuBar.shared.dropped(box.urls) } }
            return true
        } }
    }
}

/// Collects dropped file URLs from background callbacks.
final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URL] = []
    func add(_ u: URL) { lock.lock(); list.append(u); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return list }
}

// MARK: - Building blocks (drawn in SwiftUI, so they look like neatly and render in tests)

struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                if look.section { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 2) }
                else { Text(title).font(.system(size: 15, weight: .semibold, design: look.titleFont)) }
            }
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .surface()
        }
    }
}

struct IconBadge: View {
    let icon: String, color: Color
    var body: some View {
        switch look.icons {
        case .badge:
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Look.badge(color)))
                .frame(width: 32)
        case .glyph:
            Image(systemName: icon.replacingOccurrences(of: ".fill", with: "")).font(.system(size: 16, weight: .regular))
                .foregroundStyle(look.glyph).frame(width: 32, height: 28)
        }
    }
}

struct SwitchRow: View {
    let icon: String, color: Color, title: String, subtitle: String?
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Switch(isOn: $isOn, label: title)
        }
        .accessibilityElement(children: .contain)
    }
}

struct Switch: View {
    @Binding var isOn: Bool
    var label = "neatly"
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? AnyShapeStyle(look.accent) : AnyShapeStyle(look.field))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.10)))
                    .frame(width: 38, height: 22)
                Circle().fill(isOn ? AnyShapeStyle(look.onAccent) : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5).frame(width: 18, height: 18).padding(2)
            }
        }.buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

struct Chip: View {
    let text: String, selected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            let shape = RoundedRectangle(cornerRadius: look.control, style: .continuous)
            if look.outlined {
                Text(text).font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(selected ? AnyShapeStyle(look.accent) : AnyShapeStyle(.primary))
                    .background(shape.fill(selected ? AnyShapeStyle(look.accent.opacity(0.07)) : AnyShapeStyle(look.surface)))
                    .overlay(shape.strokeBorder(selected ? AnyShapeStyle(look.accent) : AnyShapeStyle(look.stroke), lineWidth: selected ? 1.5 : 1))
            } else {
                Text(text).font(.callout.weight(selected ? .medium : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(selected ? AnyShapeStyle(look.onFill) : AnyShapeStyle(.primary))
                    .background(shape.fill(selected ? AnyShapeStyle(look.fill) : AnyShapeStyle(look.field)))
            }
        }.buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct Tile: View {
    let icon: String, color: Color, title: String, subtitle: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                IconBadge(icon: icon, color: color).frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .surface()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Tiles dim a little while pressed, like Apple's.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1).scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// First start: neatly waits until you've read why macOS is about to ask for your folders (the Continue button
/// in the welcome window). Tests, the command line and people who already used neatly never wait.
@MainActor
enum Welcome {
    static var url: URL { Correction.fileURL.deletingLastPathComponent().appending(path: ".welcomed") }
    static var done: Bool { headless || !menuBar || FileManager.default.fileExists(atPath: url.path) }
    static func finish() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        print("welcome: continue")
    }
    /// At most 10 minutes: if the window was never seen, neatly still starts (macOS then asks on its own).
    static func wait() async {
        let start = Date()
        while !done && Date().timeIntervalSince(start) < 600 { try? await Task.sleep(for: .milliseconds(300)) }
    }
}

/// ~/Library/Logs/neatly.log: what neatly did, for "Open Activity Log". Kept under a few MB.
/// Light or dark windows regardless of the Mac's setting (nil = follow the Mac). Popups, the pill and every
/// window follow, since they all take the app's appearance.
enum Appearance {
    @MainActor static func apply(_ s: String?) {
        NSApp.appearance = s == "light" ? NSAppearance(named: .aqua) : s == "dark" ? NSAppearance(named: .darkAqua) : nil
    }
}

enum Log {
    static var url: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/neatly.log") }
    /// Over 4 MB: keep the last 1 MB. Rewritten in place, so the service keeps writing to the same file.
    static func trim(max: Int = 4 << 20, keep: Int = 1 << 20) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > max,
              let h = try? FileHandle(forUpdating: url) else { return }
        defer { try? h.close() }
        try? h.seek(toOffset: UInt64(size - keep))
        guard let tail = try? h.readToEnd() else { return }
        try? h.truncate(atOffset: 0)
        try? h.write(contentsOf: tail)
    }
    static func clear() {
        guard let h = try? FileHandle(forUpdating: url) else { return }
        try? h.truncate(atOffset: 0); try? h.close()
    }
}
