import Foundation

/// Renaming with an undo trail: the original name is kept in an extended attribute on the file itself,
/// so undo works even after the app restarts or the file moves.
public enum Rename {
    static let attr = "dev.neatly.original-name"
    static let folderAttr = "dev.neatly.original-folder"
    /// Every earlier (name, folder), oldest first, so Undo goes back one step at a time.
    static let stepsAttr = "dev.neatly.steps"

    struct Step: Codable { let name: String; let folder: String }

    /// A name that's safe to use: ":" shows up as "/" in Finder, a leading "." hides the file, and "/" would be
    /// read as a folder. Everything typed by a person (popup, pill, review window) passes through here.
    public static func clean(_ stem: String) -> String {
        var s = stem.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        s = s.components(separatedBy: .newlines).joined(separator: " ")
        while let f = s.first, f == "." || f == " " || f == "-" { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        // File names max out at 255 BYTES (an accented letter takes 2, an emoji 4): leave room for "-2" and the extension.
        while s.utf8.count > 200 { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Rename (and optionally move to `folder`). Never overwrites: adds -2, -3… instead.
    /// The undo information is written only once the move succeeded, so a failed rename leaves no trace.
    @discardableResult
    public static func apply(_ url: URL, to rawStem: String, in folder: URL? = nil) throws -> URL {
        let stem = clean(rawStem)
        guard !stem.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let ext = url.pathExtension
        let dir = folder ?? url.deletingLastPathComponent()
        if folder != nil { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        var target = dir.appending(path: ext.isEmpty ? stem : "\(stem).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {   // never overwrite
            target = dir.appending(path: ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)")
            n += 1
        }
        if target.standardizedFileURL == url.standardizedFileURL { return url }
        var history = steps(url)
        let first = originalName(url) == nil
        try FileManager.default.moveItem(at: url, to: target)
        history.append(Step(name: url.lastPathComponent, folder: url.deletingLastPathComponent().path))
        write(target, stepsAttr, (try? JSONEncoder().encode(Array(history.suffix(20)))).map { String(decoding: $0, as: UTF8.self) } ?? "")
        if first {   // the very first name and folder, kept across repeated renames
            write(target, attr, url.lastPathComponent)
            write(target, folderAttr, url.deletingLastPathComponent().path)
        }
        return target
    }

    public static func originalName(_ url: URL) -> String? { read(url, attr) ?? read(url, "dev.filed.original-name") ?? read(url, "dev.namer.original-name") }   // + old names

    static func steps(_ url: URL) -> [Step] {
        guard let s = read(url, stepsAttr), let list = try? JSONDecoder().decode([Step].self, from: Data(s.utf8)) else { return [] }
        return list
    }

    static func read(_ url: URL, _ name: String) -> String? {
        let len = getxattr(url.path, name, nil, 0, 0, 0)
        guard len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard getxattr(url.path, name, &buf, len, 0, 0) == len else { return nil }
        return String(decoding: buf, as: UTF8.self)
    }

    static func write(_ url: URL, _ name: String, _ value: String) {
        let bytes = Array(value.utf8)
        _ = setxattr(url.path, name, bytes, bytes.count, 0, 0)
    }

    static func forget(_ url: URL) {
        for a in [attr, folderAttr, stepsAttr, "dev.filed.original-name", "dev.filed.original-folder",
                  "dev.namer.original-name", "dev.namer.original-folder"] { removexattr(url.path, a, 0) }
    }

    /// Undo the last rename (one step back). `all`: straight back to the very first name and folder.
    @discardableResult
    public static func undo(_ url: URL, all: Bool = false) throws -> URL? {
        var history = steps(url)
        let back: Step
        if !all, let last = history.popLast() {
            back = last
        } else if let name = originalName(url) {
            let folder = read(url, folderAttr) ?? read(url, "dev.filed.original-folder") ?? read(url, "dev.namer.original-folder")
            back = Step(name: name, folder: folder ?? url.deletingLastPathComponent().path)
            history = []
        } else if let first = history.first {
            back = first; history = []
        } else { return nil }
        let target = URL(fileURLWithPath: back.folder).appending(path: back.name)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: target.path])
        }
        try FileManager.default.moveItem(at: url, to: target)
        if history.isEmpty { forget(target) }
        else { write(target, stepsAttr, (try? JSONEncoder().encode(history)).map { String(decoding: $0, as: UTF8.self) } ?? "") }
        return target
    }
}

/// What a file is right now: if any of this changes between "neatly looked" and "neatly acts", it's not the same file.
public struct FileStamp: Equatable, Sendable {
    let inode: UInt64, device: Int32, size: Int64, modified: Double
    public init?(_ url: URL) {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        inode = UInt64(st.st_ino); device = st.st_dev; size = Int64(st.st_size)
        modified = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
    }
}

/// The project was called "namer", then "filed": move their settings and corrections to the new folder once.
public func migrateFromOldName() {
    for name in ["filed", "namer"] { migrate(from: name) }
}

func migrate(from name: String) {
    let fm = FileManager.default
    let support = fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    let old = support.appending(path: name), new = support.appending(path: "neatly")
    guard fm.fileExists(atPath: old.path) else { return }
    if !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new); return }
    // Both exist (the old service wrote while we moved): append old corrections, then drop the old folder.
    let oldLog = old.appending(path: "corrections.jsonl"), newLog = new.appending(path: "corrections.jsonl")
    if let extra = try? Data(contentsOf: oldLog) {
        if let h = try? FileHandle(forWritingTo: newLog) { h.seekToEndOfFile(); h.write(extra); try? h.close() }
        else { try? extra.write(to: newLog) }
    }
    for f in ["style.json", "last-tidy.json"] where !fm.fileExists(atPath: new.appending(path: f).path) {
        try? fm.moveItem(at: old.appending(path: f), to: new.appending(path: f))
    }
    try? fm.removeItem(at: old)
}
