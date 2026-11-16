import Foundation

public enum Home {
    /// The person's real home folder. In the App Store version (sandboxed), FileManager's "home" is the app's own
    /// private container, so the folders people use (Downloads, Desktop, Documents) are looked up here instead.
    public static let real: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Running inside the App Store sandbox?
    public static var sandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    /// "~/Downloads" → the real Downloads folder (expandingTildeInPath would give the container's in the sandbox).
    public static func expand(_ path: String) -> URL {
        if path == "~" { return real }
        if path.hasPrefix("~/") { return real.appending(path: String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }
}
