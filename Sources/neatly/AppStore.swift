import AppKit
import NamerCore
import ServiceManagement

/// The App Store version runs in Apple's sandbox: it may only open folders you give it. neatly asks once for your
/// home folder (so it can name downloads and screenshots and file them where they belong) and remembers it.
/// Outside the sandbox (the DMG, Terminal and Homebrew versions) all of this does nothing.
@MainActor
enum FolderAccess {
    private static let key = "homeFolderBookmark"
    private static var active: URL?

    /// Use the permission you gave earlier, if any. Safe to call in every process (the Tidy window is one too).
    @discardableResult
    static func resume() -> Bool {
        guard Home.sandboxed else { return true }
        if active != nil { return true }
        guard let data = UserDefaults.standard.data(forKey: key) else { return false }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
                                 bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() else { return false }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        active = url
        return true
    }

    /// First start: explain, then let the person pick their home folder (already selected). Asks again if they
    /// picked something else; "Not now" leaves neatly running with whatever it may open.
    static func ensure() {
        guard Home.sandboxed, !resume() else { return }
        while true {
            NSApp.activate()
            let a = NSAlert()
            a.messageText = "Let neatly see your files"
            a.informativeText = "To name new downloads and screenshots and put files in the right folder, neatly needs "
                + "access to your home folder. Your files stay on your Mac.\n\nIn the next window, just click Allow."
            a.addButton(withTitle: "Continue")
            a.addButton(withTitle: "Not Now")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            let p = NSOpenPanel()
            p.message = "Allow neatly to name and file the files in your home folder"
            p.prompt = "Allow"
            p.canChooseDirectories = true
            p.canChooseFiles = false
            p.allowsMultipleSelection = false
            p.directoryURL = Home.real.deletingLastPathComponent()
            p.nameFieldStringValue = Home.real.lastPathComponent
            guard p.runModal() == .OK, let url = p.url else { return }
            // Your home folder, or a folder that contains it.
            guard Home.real.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path),
                  let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { continue }
            UserDefaults.standard.set(data, forKey: key)
            resume()
            return
        }
    }
}

/// Open at login, the App Store way (System Settings → General → Login Items lists it). Only with your OK.
@MainActor
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { print("login item: \(error.localizedDescription)") }
    }
    /// Asked once, after the folder permission.
    static func offerOnce() {
        guard Home.sandboxed, !UserDefaults.standard.bool(forKey: "loginItemAsked") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemAsked")
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Open neatly when you log in?"
        a.informativeText = "neatly lives in your menu bar and names new downloads and screenshots. "
            + "You can change this any time in neatly's settings."
        a.addButton(withTitle: "Open at Login")
        a.addButton(withTitle: "Not Now")
        if a.runModal() == .alertFirstButtonReturn { set(true) }
    }
}
