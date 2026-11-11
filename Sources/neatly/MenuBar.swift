import AppKit
import NamerCore

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
        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "neatly")
        item.button?.toolTip = "neatly — drop files or a folder here to name them"
        menu.delegate = self
        item.menu = menu
        // Drops on the icon: the window forwards dragging messages to its delegate.
        item.button?.window?.registerForDraggedTypes([.fileURL])
        item.button?.window?.delegate = self
        uiTest()
    }

    // MARK: Menu (rebuilt each time it opens, so checkmarks are always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let p = namer.profile
        let status = NSMenuItem(title: paused ? "Paused" : "Naming downloads and screenshots", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(entry("Tidy Desktop…", #selector(tidyDesktop)))
        menu.addItem(entry("Tidy a Folder…", #selector(tidyFolder)))
        menu.addItem(entry("Undo Last Tidy", #selector(undoLastTidy)))
        menu.addItem(.separator())

        let length = NSMenu()
        for l in StyleProfile.Length.allCases {
            let i = entry(l.rawValue.capitalized, #selector(setLength(_:)))
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
        menu.addItem(entry("Open Log", #selector(openLog)))
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
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        p.arguments = ["tidy"] + paths
        try? p.run()
    }

    @objc func tidyDesktop() { tidy([screenshotFolder().path]) }

    @objc func tidyFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.prompt = "Tidy"
        open.message = "Choose a folder: neatly suggests names for its badly named files. Nothing changes until you click Rename."
        NSApp.activate(ignoringOtherApps: true)
        if open.runModal() == .OK, let url = open.url { tidy([url.path]) }
    }

    @objc func undoLastTidy() {
        let n = Tidy.undoLast()
        print("menu: put back \(n) name(s) from the last tidy")
    }

    func change(_ edit: (inout StyleProfile) -> Void) {
        edit(&namer.profile)
        try? namer.profile.save()
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

    /// Stops until the next login (the service is still installed). `neatly service uninstall` removes it.
    @objc func quit() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/dev.neatly.watch"]
        try? p.run()
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
            }
        }
    }
}
