import AppKit
import NeatlyCore

/// The menu-bar icon: Tidy, naming options, Pause, Undo. Drop files or a folder on it to name them.
/// Settings change the same style.json as `neatly style`, and apply to the next file right away.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate, NSWindowDelegate {
    static let shared = MenuBar()
    var item: NSStatusItem!
    let menu = NSMenu()

    func start() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = !headless
        item.button?.image = Icon.menuBarGlyph()
        Appearance.apply(neatly.profile.appearance)
        item.button?.toolTip = "neatly — drop files or a folder here to name them"
        menu.delegate = self
        menu.autoenablesItems = false   // items are enabled/disabled by hand (Undo greys out when there's nothing)
        item.menu = menu
        // Drops on the icon: the window forwards dragging messages to its delegate.
        item.button?.window?.registerForDraggedTypes([.fileURL])
        item.button?.window?.delegate = self
        // Made by an older version's updater? Bring the app's icon and Finder menu up to date.
        #if !APPSTORE
        if !headless { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { AppBundle.refreshIfStale() } }
        #endif
        // Finder: "Open With → neatly" (AppDelegate) and "Rename with neatly" (Services) → the review window.
        // Only the real app offers the service: a test or debug copy must never take it over.
        if !headless, AppBundle.isRunningInside { NSApp.servicesProvider = FinderHandoff.provider }
        FinderHandoff.provider.handle = { [weak self] urls in self?.dropped(urls) }
        FinderHandoff.listen { [weak self] urls in self?.dropped(urls) }
        // "Open neatly" from Spotlight/Applications while it runs → show the window here.
        DistributedNotificationCenter.default().addObserver(forName: HomeWindow.showNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HomeWindow.shared.show() }
        }
        // First run after installing: show the window, which explains the folder permission prompts before
        // macOS shows them (the watchers wait for its Continue button).
        if !Welcome.done { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { HomeWindow.shared.show() } }
        uiTest()
        if ProcessInfo.processInfo.environment["NEATLY_UI_TEST"]?.contains("home:") == true { HomeWindow.shared.show() }
    }

    // MARK: Menu (rebuilt each time it opens, so checkmarks are always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let p = neatly.profile
        let status = NSMenuItem(title: paused ? "Paused" : "Naming downloads and screenshots", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(entry("Open neatly…", #selector(openHome)))
        menu.addItem(.separator())
        menu.addItem(entry("Tidy Desktop…", #selector(tidyDesktop)))
        menu.addItem(entry("Tidy a Folder…", #selector(tidyFolder)))
        menu.addItem(entry("History…", #selector(openHistory)))
        // Greyed out (with nothing to say) when there's nothing to undo.
        let lastDownload = History.lastDownload()
        let undoDownload = entry(lastDownload.map { "Undo “\(URL(fileURLWithPath: $0.to).lastPathComponent)”" } ?? "Undo Last Download",
                                 #selector(undoLastDownload))
        undoDownload.isEnabled = lastDownload != nil
        menu.addItem(undoDownload)
        let n = Tidy.lastCount
        let undoTidy = entry(n > 0 ? "Undo Last Tidy (\(n) file\(n == 1 ? "" : "s"))" : "Undo Last Tidy", #selector(undoLastTidy))
        undoTidy.isEnabled = n > 0
        menu.addItem(undoTidy)
        menu.addItem(.separator())

        let length = NSMenu()
        for l in StyleProfile.Length.allCases {
            let i = entry(l.label, #selector(setLength(_:)))
            i.representedObject = l.rawValue
            i.state = p.len == l ? .on : .off
            length.addItem(i)
        }
        let lengthItem = NSMenuItem(title: "Name Length", action: nil, keyEquivalent: "")
        lengthItem.submenu = length
        menu.addItem(lengthItem)

        let date = NSMenu()
        for (title, value) in [("No Date", "none"), ("Date First", "prefix"), ("Date Last", "suffix")] {
            let i = entry(title, #selector(setDate(_:)))
            i.representedObject = value
            i.state = (p.date?.rawValue ?? "none") == value ? .on : .off
            date.addItem(i)
        }
        let dateItem = NSMenuItem(title: "Date", action: nil, keyEquivalent: "")
        dateItem.submenu = date
        menu.addItem(dateItem)

        menu.addItem(toggle("Title Case", !p.lowercase, #selector(toggleCase)))
        menu.addItem(toggle("Add App Name to Screenshots", p.appName == true, #selector(toggleApp)))
        menu.addItem(toggle("Copy Screenshots to Clipboard", p.copyScreenshots == true, #selector(toggleCopy)))
        menu.addItem(.separator())
        menu.addItem(toggle("Pause", paused, #selector(togglePause)))
        menu.addItem(entry("Open Activity Log", #selector(openLog)))
        menu.addItem(entry("Quit neatly", #selector(quit)))
    }

    func entry(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let i = entry(title, action)
        i.state = on ? .on : .off
        return i
    }

    // MARK: Actions

    /// Tidy runs as its own window/process, so the watchers keep going.
    func tidy(_ paths: [String]) {
        let p = Process()
        p.executableURL = selfExecutable
        var flags: [String] = []
        if offline || !neatly.useNetwork { flags.append("--offline") }     // --offline means offline everywhere
        if !neatly.useModel { flags.append("--no-model") }
        // Thousands of files (⌘A in a photo folder) can't go on a command line (limit 4096 arguments, and a
        // total size): hand them over in a list file instead.
        if paths.count > 200 {
            let list = FileManager.default.temporaryDirectory.appending(path: "neatly-tidy-\(UUID().uuidString).txt")
            guard (try? paths.joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)) != nil else { return }
            p.arguments = ["tidy"] + flags + ["--list", list.path]
        } else {
            p.arguments = ["tidy"] + flags + paths
        }
        do { try p.run() } catch {
            print("menu: couldn't open the review window: \(error)")
            Notice.show("Couldn't open the review window for these files.", icon: "exclamationmark.triangle.fill")
        }
    }

    @objc func openHome() { HomeWindow.shared.show() }

    @objc func tidyDesktop() { tidy([screenshotFolder().path]) }

    @objc func tidyFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.prompt = "Tidy"
        open.message = "Choose a folder: neatly suggests names for its badly named files. Nothing changes until you click Rename."
        NSApp.activate()
        open.begin { [weak self] r in   // not modal: neatly keeps working while the picker is open
            guard r == .OK, let url = open.url else { return }
            MainActor.assumeIsolated { self?.tidy([url.path]) }
        }
    }

    @objc func openHistory() { HistoryWindow.shared.show() }

    @objc func undoLastTidy() {
        let n = Tidy.undoLast()
        print("menu: put back \(n) name(s) from the last tidy")
        Notice.show(n == 0 ? "Nothing to put back." : "Put back \(n) name\(n == 1 ? "" : "s") from the last tidy.",
                    icon: n == 0 ? "info.circle.fill" : "arrow.uturn.backward.circle.fill")
    }

    @objc func undoLastDownload() {
        guard let e = History.lastDownload() else { Notice.show("Nothing to undo.", icon: "info.circle.fill"); return }
        if let back = try? History.revert(e.id) {
            Notice.show("Put back “\(back.lastPathComponent)” in \(shortFolder(back.deletingLastPathComponent())).",
                        icon: "arrow.uturn.backward.circle.fill")
        } else {
            Notice.show("Couldn't put it back — open History for details.", icon: "exclamationmark.circle.fill")
        }
    }

    func change(_ edit: (inout StyleProfile) -> Void) {
        edit(&neatly.profile)
        try? neatly.profile.save()
    }

    @objc func setLength(_ sender: NSMenuItem) {
        change { $0.length = StyleProfile.Length(rawValue: sender.representedObject as? String ?? "short") }
    }
    @objc func setDate(_ sender: NSMenuItem) {
        change { $0.date = StyleProfile.DatePosition(rawValue: sender.representedObject as? String ?? "none") }
    }
    @objc func toggleCase() { change { $0.lowercase.toggle() } }
    @objc func toggleApp() { change { $0.appName = !($0.appName ?? false) } }
    @objc func toggleCopy() { change { $0.copyScreenshots = !($0.copyScreenshots ?? false) } }
    @objc func togglePause() {
        paused.toggle()
        item.button?.appearsDisabled = paused
        print("menu: \(paused ? "paused" : "resumed")")
    }

    @objc func openLog() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/neatly.log"))
    }

    /// Quitting means downloads and screenshots aren't named until the next login: offer Pause instead.
    /// Quit stops until the next login (the service is still installed). `neatly service uninstall` removes it.
    @objc func quit() {
        if !headless {
            NSApp.activate()
            let a = NSAlert()
            a.messageText = "Quit neatly?"
            a.informativeText = "New downloads and screenshots won't be named until you log in again or open neatly. "
                + "To stop for a while, pause instead."
            a.addButton(withTitle: "Pause Instead")
            a.addButton(withTitle: "Quit")
            a.addButton(withTitle: "Cancel")
            switch a.runModal() {
            case .alertFirstButtonReturn: if !paused { togglePause() }; return
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        quitNow()
    }

    func quitNow() {
        #if !APPSTORE
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/dev.neatly.watch"]
        try? p.run()
        #endif
        NSApp.terminate(nil)
    }

    // MARK: Drop files or a folder on the icon

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        item.button?.highlight(true)
        return .copy
    }
    func draggingExited(_ sender: NSDraggingInfo?) { item.button?.highlight(false) }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        item.button?.highlight(false)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        dropped(urls)
        return !urls.isEmpty
    }

    /// A folder → Tidy that folder. Files → Tidy just those files.
    func dropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        print("menu: dropped \(urls.count) item(s)")
        tidy(urls.map(\.path))
    }

    /// NEATLY_UI_TEST="menu:<item title>" or "drop:<path>|<path>": use the menu / drop by code, for tests.
    func uiTest() {
        guard let t = ProcessInfo.processInfo.environment["NEATLY_UI_TEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let w = self.item.button?.window
            print("menu: icon frame \(w?.frame ?? .zero) visible \(w?.isVisible ?? false) onActiveSpace \(w?.isOnActiveSpace ?? false) window \(w?.windowNumber ?? 0)")
            for step in t.split(separator: ",").map(String.init) {
                if step.hasPrefix("menu:") {
                    self.menuNeedsUpdate(self.menu)
                    let path = step.dropFirst(5).split(separator: ">").map(String.init)
                    var m: NSMenu? = self.menu, found: NSMenuItem?
                    for title in path { found = m?.items.first { $0.title == title }; m = found?.submenu }
                    if let found, let action = found.action { NSApp.sendAction(action, to: found.target, from: found) }
                    else { print("menu: no item \(path)") }
                }
                if step.hasPrefix("drop:") { self.dropped(step.dropFirst(5).split(separator: "|").map { URL(fileURLWithPath: String($0)) }) }
                // Finder hand-offs, by code: "Rename with neatly" (through a real pasteboard) and "Open With".
                let files = { (s: Substring) in s.split(separator: "|").map { URL(fileURLWithPath: String($0)) } }
                if step.hasPrefix("service:") {
                    let pb = NSPasteboard(name: NSPasteboard.Name("dev.neatly.test.\(UUID().uuidString)"))
                    pb.clearContents(); pb.writeObjects(files(step.dropFirst(8)) as [NSURL])
                    var err: NSString?
                    FinderHandoff.provider.renameWithNeatly(pb, userData: nil, error: &err)
                    pb.releaseGlobally()
                }
                if step.hasPrefix("open:") { AppDelegate.shared.application(NSApp, open: files(step.dropFirst(5))) }
            }
        }
    }
}

/// macOS sends "reopen" to the running copy when you open neatly from Spotlight, Finder or the Dock
/// (it never starts a second copy of an app that's already running): show the window then.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    /// Files or folders dropped on neatly's icon in Finder or the Dock → the review window for them.
    func application(_ application: NSApplication, open urls: [URL]) {
        MenuBar.shared.dropped(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        HomeWindow.shared.show()
        return true
    }
}


/// Files handed to neatly from Finder: "Open With → neatly" and the "Rename with neatly" service.
/// The running copy opens the review window for them. If neatly wasn't running, macOS starts the app, which
/// collects the files, makes sure the background copy runs, and passes them on (`forward`).
@MainActor
enum FinderHandoff {
    @MainActor final class Provider: NSObject {
        var handle: @MainActor ([URL]) -> Void = { _ in }
        /// The "Rename with neatly" service (NSServices in Info.plist).
        @objc func renameWithNeatly(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
            let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            print("finder: service with \(urls.count) item(s)")
            handle(urls)
        }
    }
    static let provider = Provider()
    static let openNotification = Notification.Name("dev.neatly.open" + (ProcessInfo.processInfo.environment["NEATLY_NOTIFY"] ?? ""))
    private static var seen = Set<String>()

    /// In the running copy: take files passed on by a just-started app. Each hand-off is sent a few times (the
    /// background copy may still be starting) with one id, so it opens one window, not three.
    static func listen(_ handle: @escaping @MainActor @Sendable ([URL]) -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: openNotification, object: nil, queue: .main) { n in
            guard let info = n.userInfo, let id = info["id"] as? String, let paths = info["paths"] as? [String] else { return }
            MainActor.assumeIsolated {
                guard seen.insert(id).inserted else { return }
                print("finder: handed \(paths.count) item(s)")
                handle(paths.map { URL(fileURLWithPath: $0) })
            }
        }
    }

    static func forward(_ paths: [String]) {
        let id = UUID().uuidString
        for i in 0..<3 {
            DistributedNotificationCenter.default().postNotificationName(openNotification, object: nil,
                                                                         userInfo: ["id": id, "paths": paths], deliverImmediately: true)
            if i < 2 { usleep(1_200_000) }
        }
    }

    /// A just-started app (opened from Finder with files, or for the service): wait a moment for macOS to hand
    /// over the files, then return them.
    static func collect(for seconds: Double = 1.5) -> [URL] {
        final class Catcher: NSObject, NSApplicationDelegate {
            var urls: [URL] = []
            func application(_ application: NSApplication, open urls: [URL]) { self.urls += urls }
            /// A plain launch (Spotlight, Applications, Dock) brings no files: stop waiting right away.
            func applicationDidFinishLaunching(_ n: Notification) {
                if (n.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if self.urls.isEmpty { FinderHandoff.stop() } }
                }
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let catcher = Catcher()
        app.delegate = catcher
        provider.handle = { catcher.urls += $0 }
        app.servicesProvider = provider
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { stop() }
        app.run()
        return catcher.urls
    }

    static func stop() {
        NSApp.stop(nil)
        // stop() takes effect after the next event: send one.
        NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
    }
}
