import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NamerCore

/// The window you get when you open neatly (Spotlight, Applications, or "Open neatly…" in the menu).
/// Written for people who never open Terminal: one promise, a big drop target, three big buttons,
/// plain-language switches, and name styles you pick by their look. Everything else is under "More options".
/// It lives in the running service, so changes apply to the very next file.
@MainActor
final class HomeWindow: NSObject, NSWindowDelegate {
    static let shared = HomeWindow()
    /// Tests use their own name (NEATLY_NOTIFY), so they never open the window of the neatly you actually run.
    static let showNotification = Notification.Name("dev.neatly.show" + (ProcessInfo.processInfo.environment["NEATLY_NOTIFY"] ?? ""))

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
            window.center()
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
    ///                 home:countdown=10,home:drop=<path>,home:snapshot=<png>"
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
                case "autoupdate": model.autoUpdate = kv[1] == "on"
                case "online": model.online = kv[1] == "on"
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
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97)))
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
    @Published var autoUpdate: Bool? = nil { didSet { save() } }   // nil = not asked yet
    @Published var online = true { didSet { save() } }
    @Published var welcomed = true
    @Published var named = 0
    @Published var moreOpen = false      // view state lives here: SwiftUI's @State needs Xcode's macro plugin
    @Published var dropping = false
    var forPicture = false               // drawing for a test picture: the drop handler can't be drawn off screen
    private var loading = false

    func reload() {
        loading = true
        let p = namer.profile
        on = !paused
        downloads = p.watchDownloads != false
        screenshots = p.watchScreenshots != false
        style = p.separator == "_" ? .underscores : (!p.lowercase || p.separator == " ") ? .title : .dashes
        length = p.len
        dateFirst = p.date != nil
        appName = p.appName == true
        copyShots = p.copyScreenshots == true
        countdown = timeout
        autoUpdate = p.autoUpdate
        online = p.onlineLookups != false
        welcomed = Welcome.done
        named = Correction.all().filter { !$0.chosen.isEmpty }.count
        loading = false
    }

    func save() {
        guard !loading else { return }
        MenuBar.shared.change { p in
            p.watchDownloads = downloads
            p.watchScreenshots = screenshots
            switch style {
            case .dashes: p.separator = "-"; p.lowercase = true
            case .title: p.separator = " "; p.lowercase = false
            case .underscores: p.separator = "_"; p.lowercase = true
            }
            p.length = length
            p.date = dateFirst ? .prefix : nil
            p.appName = appName
            p.copyScreenshots = copyShots
            p.countdown = countdown
            p.autoUpdate = autoUpdate
            p.onlineLookups = online ? nil : false
        }
        namer.useNetwork = online && !offline
        timeout = countdown
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
        uninstallEverything()
        NSApp.terminate(nil)
    }

    /// What a name looks like with the current choices — shown live in the window.
    var preview: String {
        let base = length == .short ? "hot-honey-cornbread" : length == .standard ? "hot-honey-cornbread-recipe"
                                                                                 : "hot-honey-cornbread-recipe-cast-iron"
        return namer.profile.render(base, date: Date(), app: appName ? "Safari" : nil) + ".png"
    }
}

// MARK: - The look

/// neatly's colors: the teal → blue of the app icon.
let brand = Color(red: 0.13, green: 0.62, blue: 0.68)
let brandGradient = LinearGradient(colors: [Color(red: 0.20, green: 0.78, blue: 0.72), Color(red: 0.16, green: 0.42, blue: 0.86)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)

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
                .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.10)))
            }
            if model.welcomed && model.autoUpdate == nil {
                // Asked once, at first install: after that neatly keeps itself current with nothing to do.
                HStack(spacing: 12) {
                    IconBadge(icon: "arrow.triangle.2.circlepath", color: .teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep neatly up to date by itself?").font(.callout.weight(.semibold))
                        Text("New versions install quietly in the background. You won't need to do anything.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("No thanks") { model.autoUpdate = false }.buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                    Chip(text: "Yes, keep it updated", selected: true) { model.autoUpdate = true }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(brand.opacity(0.10)))
            }
            if !noAccess.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("neatly isn't allowed to see your \(noAccess.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted().joined(separator: " and ")) folder").font(.callout.weight(.semibold))
                        Text("Allow it, and neatly starts right away.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                    }.buttonStyle(.plain).foregroundStyle(brand).font(.callout.weight(.semibold))
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
            }
            if !Namer.modelAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "apple.intelligence").foregroundStyle(.orange)
                    Text("Apple Intelligence is off, so names are simpler.").font(.callout)
                    Spacer()
                    Button("Turn it on") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                    }.buttonStyle(.plain).foregroundStyle(brand).font(.callout.weight(.semibold))
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
            }
            dropZone
            HStack(spacing: 12) {
                Tile(icon: "menubar.dock.rectangle", color: .blue, title: "Tidy Desktop", subtitle: "Name what's on it") {
                    MenuBar.shared.tidyDesktop()
                }
                Tile(icon: "arrow.down.circle.fill", color: .green, title: "Tidy Downloads", subtitle: "Name your downloads") {
                    MenuBar.shared.tidy([FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads").path])
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
                    Image(systemName: "doc.fill").foregroundStyle(brand)
                    Text(model.preview).font(.system(.body, design: .rounded).weight(.medium)).lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(brand.opacity(0.10)))
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
                        SwitchRow(icon: "arrow.triangle.2.circlepath", color: .teal, title: "Update neatly automatically",
                                  subtitle: "Nothing about you or your files is sent",
                                  isOn: Binding(get: { model.autoUpdate == true }, set: { model.autoUpdate = $0 }))
                        Divider().padding(.leading, 44)
                        SwitchRow(icon: "globe", color: .blue, title: "Look up research papers online",
                                  subtitle: "Gets a paper's real title from arXiv — only its paper number is sent",
                                  isOn: $model.online)
                        Divider().padding(.leading, 44)
                        HStack(spacing: 12) {
                            IconBadge(icon: "timer", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("If I don't answer a download suggestion")
                                Text("neatly keeps the new name, in Downloads, after:").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            ForEach([3, 5, 10, 30, 0], id: \.self) { s in
                                Chip(text: s == 0 ? "Wait for me" : "\(s) sec", selected: model.countdown == s) { model.countdown = s }
                            }
                        }.padding(.leading, 44)
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
                Button("History") { HistoryWindow.shared.show() }.buttonStyle(.plain).font(.caption).foregroundStyle(brand)
                Text("·").font(.caption)
                Button("Quit neatly") { MenuBar.shared.quit() }.buttonStyle(.plain).font(.caption).foregroundStyle(brand)
            }.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 20)
        .frame(width: 520)
    }

    var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppBundle.iconPNG(256).flatMap(NSImage.init(data:)) ?? NSImage())
                .resizable().frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text("neatly").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(model.named == 0 ? "Clear names for your files, automatically."
                                      : "\(model.named) files named so far.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 4) {
                Switch(isOn: $model.on, label: "neatly on")
                Text(model.on ? "On" : "Paused").font(.caption.weight(.medium)).foregroundStyle(model.on ? brand : .secondary)
            }
        }
    }

    var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 34)).foregroundStyle(brandGradient)
            Text("Drop files here to rename them").font(.system(.title3, design: .rounded).weight(.semibold))
            Text("neatly suggests clear names. Nothing changes until you say so.").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 18).fill(brand.opacity(model.dropping ? 0.18 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(brand.opacity(model.dropping ? 0.9 : 0.45),
                                                                 style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
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
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
}

struct IconBadge: View {
    let icon: String, color: Color
    var body: some View {
        Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 8).fill(color.gradient))
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
                Capsule().fill(isOn ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: 42, height: 24)
                Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 1).frame(width: 20, height: 20).padding(2)
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
            Text(text).font(.system(.callout, design: .rounded).weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? .white : .primary)
                .background(Capsule().fill(selected ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color.primary.opacity(0.06))))
        }.buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct Tile: View {
    let icon: String, color: Color, title: String, subtitle: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)))
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
