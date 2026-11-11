import AppKit

/// neatly.app: a real Mac app (Applications, Spotlight, Launchpad, its own icon and name in permission
/// prompts), built on your Mac from the neatly binary itself — so no Xcode, and the curl and Homebrew
/// installs end up with the same app. It's a menu-bar app: no Dock icon.
enum AppBundle {
    static let identifier = "dev.neatly.app"

    /// /Applications if you can write there (admins can), else ~/Applications. NEATLY_APP_DIR in tests.
    static var folder: URL {
        if let d = ProcessInfo.processInfo.environment["NEATLY_APP_DIR"] { return URL(fileURLWithPath: d) }
        let system = URL(fileURLWithPath: "/Applications")
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
    }

    static var location: URL { folder.appending(path: "neatly.app") }
    static var executable: URL { location.appending(path: "Contents/MacOS/neatly") }

    /// Are we running from inside neatly.app (opened from Finder/Spotlight, or the service)?
    static var isRunningInside: Bool {
        URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path.contains(".app/Contents/MacOS/")
    }

    /// Build (or rebuild) the app around `binary`. Returns the app's executable.
    @discardableResult
    static func build(from binary: URL, version: String) throws -> URL {
        let fm = FileManager.default
        let app = location
        let staging = folder.appending(path: ".neatly-building.app")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
        try fm.copyItem(at: binary, to: staging.appending(path: "Contents/MacOS/neatly"))
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": "neatly",
            "CFBundleDisplayName": "neatly",
            "CFBundleExecutable": "neatly",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            "CFBundleIconFile": "AppIcon",
            "LSMinimumSystemVersion": "26.0",
            "LSUIElement": true,                       // menu-bar app: no Dock icon
            "LSApplicationCategoryType": "public.app-category.productivity",
            "NSHumanReadableCopyright": "MIT License",
            "NSDesktopFolderUsageDescription": "neatly names your new screenshots, which macOS saves on the Desktop.",
            "NSDownloadsFolderUsageDescription": "neatly suggests a name and a folder for each new download.",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: staging.appending(path: "Contents/Info.plist"))
        try? writeIcon(to: staging.appending(path: "Contents/Resources/AppIcon.icns"))
        run("/usr/bin/codesign", ["--force", "--sign", "-", staging.path])   // ad-hoc: required on Apple silicon

        // Swap in place, so a running copy is never half-written.
        try? fm.removeItem(at: app)
        try fm.moveItem(at: staging, to: app)
        // Tell Launch Services and Spotlight about it right away.
        run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", app.path])
        run("/usr/bin/mdimport", [app.path])
        return executable
    }

    static func remove() {
        run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-u", location.path])
        try? FileManager.default.removeItem(at: location)
    }

    /// The icon: the menu-bar symbol, white on a teal-to-blue gradient, in every size macOS wants.
    static func writeIcon(to icns: URL) throws {
        let fm = FileManager.default
        let set = fm.temporaryDirectory.appending(path: "neatly-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: set) }
        for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
            for s in scales {
                let px = pt * s
                guard let png = iconPNG(px) else { continue }
                try png.write(to: set.appending(path: "icon_\(pt)x\(pt)\(s == 2 ? "@2x" : "").png"))
            }
        }
        run("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", icns.path])
    }

    static func iconPNG(_ px: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px)
        let inset = s * 0.1   // macOS icons leave a margin around the rounded square
        let box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
        NSGradient(starting: NSColor(red: 0.20, green: 0.78, blue: 0.72, alpha: 1),     // teal → blue
                   ending: NSColor(red: 0.16, green: 0.42, blue: 0.86, alpha: 1))?.draw(in: shape, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: box.width * 0.5, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let sz = symbol.size
            symbol.draw(in: NSRect(x: box.midX - sz.width / 2, y: box.midY - sz.height / 2, width: sz.width, height: sz.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
